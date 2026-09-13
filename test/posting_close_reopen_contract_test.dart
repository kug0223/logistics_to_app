// [POSTING-V2-03E.1] 공고 종료 / 재오픈 — 호출 계약과 실패 의미
//
// 03E READ에서 확인된 것:
//   · callableUpdateTO는 2026-09-08(4779925)부터 expectedEditRevision을
//     fail-closed로 요구하는데, 그 커밋이 firestore_service.dart의 raw caller
//     두 곳(reopenTO · markTOAsExpired)을 갱신하지 않았다
//     → 공고 재오픈은 권한 검증에 닿기도 전에 invalid-argument로 거부됐다.
//       즉 정상 공고의 재오픈이 100% 실패하는 상태였다.
//   · closeTOManually / reopenTO가 예외를 `false`로 바꿔, 서버가 구분해 보낸
//     거부 사유가 서비스 경계에서 소멸했다. 그래서 위 장애가 5일간
//     '공고 재오픈에 실패했습니다.' 한 줄 뒤에 숨어 있었다.
//
// 계약:
//   · expectedEditRevision = required (누락은 컴파일 에러)
//   · revision source = 사용자가 지금 보고 있는 entity
//   · 실패 = 예외 전파, 성공 = true 하나
//   · 서버 문구가 있으면 그대로, 없으면 action별 fallback
//
// FirestoreService는 Firebase 초기화를 요구해 단위 테스트로 호출할 수 없다.
// 호출 계약과 배선은 소스로 검증한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _svcPath = 'lib/services/firestore_service.dart';
const _dialogsPath = 'lib/screens/business_admin/dialogs/to_list_dialogs.dart';
const _ctrlPath = 'lib/controllers/workforce_controller.dart';
const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _fnsPath = 'functions/src/index.ts';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) throw StateError('$signature 를 찾지 못함');
  var paren = 0;
  var afterParams = start;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') paren++;
    if (source[i] == ')') {
      paren--;
      if (paren == 0) {
        afterParams = i;
        break;
      }
    }
  }
  final open = source.indexOf('{', afterParams);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$signature 본문의 끝을 찾지 못함');
}

void main() {
  // ── §1, §2 revision contract ───────────────────────────────────
  group('CLOSEREOPEN-01 재오픈이 revision을 반드시 싣는다', () {
    test('01-a 서버가 revision을 fail-closed로 요구한다 (장애의 근거)', () {
      final fns = _src(_fnsPath);
      expect(
          fns.contains('if (typeof expectedEditRevision !== "number") {'), true,
          reason: '이 guard가 없으면 이번 수정의 전제가 사라진다');
      expect(fns.contains('"expectedEditRevision이 필요합니다."'), true);
    });

    test('01-b reopenTO의 expectedEditRevision이 required다 (§1)', () {
      final sig = _flat(_codeOf(_bodyOf(_src(_svcPath), 'Future<bool> reopenTO(')));
      expect(sig.contains('required int expectedEditRevision,'), true,
          reason: 'optional/default면 같은 누락이 조용히 재발한다');
      expect(sig.contains('int expectedEditRevision = 0'), false);
      expect(sig.contains('int? expectedEditRevision'), false);
    });

    test('01-c payload에 실제로 실린다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_svcPath), 'Future<bool> reopenTO(')));
      expect(body.contains("'expectedEditRevision': expectedEditRevision,"), true);
      // 재오픈 의미 자체는 그대로 (§15 — server policy 무변경)
      expect(body.contains("'isManualClosed': false,"), true);
      expect(body.contains("'status': TOStatus.active,"), true);
    });

    test('01-d revision을 하드코딩하거나 재조회하지 않는다 (§2)', () {
      final body = _codeOf(_bodyOf(_src(_svcPath), 'Future<bool> reopenTO('));
      expect(body.contains("'expectedEditRevision': 0"), false);
      expect(body.contains('.get()'), false,
          reason: '최신 revision을 따로 읽어오면 optimistic concurrency가 무의미해진다');
    });

    test('01-e revision source = 사용자가 보고 있는 entity (§2)', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_dialogsPath), 'Future<void> showReopenTODialog(')));
      expect(body.contains('expectedEditRevision: to.editRevision'), true,
          reason: '다이얼로그가 대상으로 삼은 바로 그 TO의 revision이어야 한다');
      expect(body.contains('getTOById'), false);
      expect(body.contains('await firestoreService.getTO'), false);
    });
  });

  // ── §4, §14 bool contract 제거 ─────────────────────────────────
  group('CLOSEREOPEN-02 실패를 false로 바꾸지 않는다', () {
    test('02-a closeTOManually가 rethrow한다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_svcPath), 'Future<bool> closeTOManually(')));
      expect(body.contains("debugPrint('❌ TO 수동 마감 실패: \$e'); rethrow;"), true);
      expect(body.contains('return false;'), false,
          reason: 'false = 모든 실패는 information-loss contract다');
    });

    test('02-b reopenTO가 rethrow한다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_svcPath), 'Future<bool> reopenTO(')));
      expect(body.contains("debugPrint('❌ TO 재오픈 실패: \$e'); rethrow;"), true);
      expect(body.contains('return false;'), false);
    });

    test('02-c 성공 경로는 true 하나뿐이다 (§4)', () {
      for (final sig in [
        'Future<bool> closeTOManually(',
        'Future<bool> reopenTO(',
      ]) {
        final body = _codeOf(_bodyOf(_src(_svcPath), sig));
        expect('return true;'.allMatches(body).length, 1, reason: sig);
        expect(body.contains('return false'), false, reason: sig);
      }
    });

    test('02-d GlobalLoadingController 해제가 유지된다', () {
      for (final sig in [
        'Future<bool> closeTOManually(',
        'Future<bool> reopenTO(',
      ]) {
        final body = _flat(_codeOf(_bodyOf(_src(_svcPath), sig)));
        expect(body.contains('} finally { GlobalLoadingController.hide(); }'),
            true,
            reason: '$sig — rethrow해도 로딩은 반드시 걷힌다');
      }
    });
  });

  // ── §5, §6 error surface ───────────────────────────────────────
  group('CLOSEREOPEN-03 서버 문구가 화면까지 도달한다', () {
    test('03-a catch가 도달 가능하고 서버 메시지를 쓴다', () {
      for (final entry in [
        ('Future<void> showCloseTODialog(', '공고 종료에 실패했습니다.'),
        ('Future<void> showReopenTODialog(', '공고 재오픈에 실패했습니다.'),
      ]) {
        final body = _flat(_codeOf(_bodyOf(_src(_dialogsPath), entry.$1)));
        expect(
            body.contains("ToastHelper.showError( _cfErrorMessage(e, "
                "fallback: '${entry.$2}'));"),
            true,
            reason: '${entry.$1} — 서버 문구 우선, 없을 때만 fallback');
      }
    });

    test('03-b generic else 분기가 사라졌다', () {
      final code = _codeOf(_src(_dialogsPath));
      // 실패는 이제 catch 한 곳에서만 표현된다
      expect(code.contains("} else { ToastHelper.showError('공고 종료에 실패했습니다.'); }"),
          false);
      expect(_flat(code).contains('if (success == null) return; if (success) {'),
          false,
          reason: 'false가 없어졌으므로 삼분기도 없어야 한다');
      for (final sig in [
        'Future<void> showCloseTODialog(',
        'Future<void> showReopenTODialog(',
      ]) {
        final body = _flat(_codeOf(_bodyOf(_src(_dialogsPath), sig)));
        expect(body.contains('if (success != true) return;'), true, reason: sig);
      }
    });

    test('03-c fallback 문구는 기존 것을 그대로 쓴다 (§5)', () {
      final code = _codeOf(_src(_dialogsPath));
      expect(code.contains("'공고 종료에 실패했습니다.'"), true);
      expect(code.contains("'공고 재오픈에 실패했습니다.'"), true);
      // '…중 오류가 발생했습니다'는 같은 실패를 두 가지로 말하던 잔재였다
      expect(code.contains("'공고 종료 중 오류가 발생했습니다.'"), false);
      expect(code.contains("'공고 재오픈 중 오류가 발생했습니다.'"), false);
    });

    test('03-d code별 error table을 만들지 않았다 (§5)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_dialogsPath), 'String _cfErrorMessage(')));
      expect(body.contains('error is FirebaseFunctionsException'), true);
      expect(body.contains('return fallback;'), true);
      for (final code in [
        "'permission-denied'",
        "'already-exists'",
        "'failed-precondition'",
        "'not-found'",
        'switch (',
      ]) {
        expect(body.contains(code), false,
            reason: '$code — 서버가 이미 구분한 것을 클라이언트가 다시 분류하지 않는다');
      }
    });

    test('03-e 날짜 일괄 경로와 같은 규칙이다 (§5)', () {
      final dialogMapper = _flat(_codeOf(
          _bodyOf(_src(_dialogsPath), 'String _cfErrorMessage(')));
      final cardMapper = _flat(_codeOf(
          _bodyOf(_src(_cardPath), 'String _cfErrorMessage(')));
      expect(dialogMapper.contains('final msg = error.message; '
          'if (msg != null && msg.isNotEmpty) return msg;'), true);
      expect(cardMapper.contains('final msg = error.message; '
          'if (msg != null && msg.isNotEmpty) return msg;'), true);
    });

    test('03-f 공통 mapper를 새로 추출하지 않았다 (§6)', () {
      // 프로젝트에 shared Functions error mapper가 없다 — 이번 Phase 범위보다 크다
      expect(Directory('lib/utils').existsSync(), true);
      final utils = Directory('lib/utils')
          .listSync()
          .whereType<File>()
          .map((f) => f.readAsStringSync())
          .join('\n');
      expect(utils.contains('FirebaseFunctionsException'), false,
          reason: 'shared error framework를 만들지 않는다');
      // private 메서드를 외부에서 억지로 쓰지도 않았다
      expect(_codeOf(_src(_dialogsPath)).contains('_cfErrorMessage(e,'), true);
    });
  });

  // ── §7 success path 무회귀 ─────────────────────────────────────
  group('CLOSEREOPEN-04 성공 흐름은 그대로다', () {
    test('04-a close 성공 = toast + onChanged + notify(jobs)', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_dialogsPath), 'Future<void> showCloseTODialog(')));
      expect(body.contains("ToastHelper.showSuccess('공고가 종료되었습니다.');"), true);
      expect(body.contains('onChanged();'), true);
      expect(
          body.contains('WorkforceController.notifyDataChanged( '
              'origin: AdminMutationOrigin.jobs, );'),
          true);
    });

    test('04-b reopen 성공 = toast + onChanged + notify(jobs)', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_dialogsPath), 'Future<void> showReopenTODialog(')));
      expect(body.contains("ToastHelper.showSuccess('공고가 재오픈되었습니다.');"), true);
      expect(body.contains('onChanged();'), true);
      expect(
          body.contains('WorkforceController.notifyDataChanged( '
              'origin: AdminMutationOrigin.jobs, );'),
          true);
    });

    test('04-c 실패 시 success 부수효과가 실행되지 않는다', () {
      for (final sig in [
        'Future<void> showCloseTODialog(',
        'Future<void> showReopenTODialog(',
      ]) {
        final body = _codeOf(_bodyOf(_src(_dialogsPath), sig));
        final guard = body.indexOf('if (success != true) return;');
        expect(guard, greaterThan(-1), reason: sig);
        expect(body.indexOf('onChanged();'), greaterThan(guard), reason: sig);
        expect(body.indexOf('WorkforceController.notifyDataChanged'),
            greaterThan(guard),
            reason: sig);
      }
    });
  });

  // ── §9, §10, §11 markTOAsExpired ───────────────────────────────
  group('CLOSEREOPEN-05 자동 만료 쓰기도 revision을 싣는다', () {
    test('05-a expectedEditRevision이 required다 (§9)', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_svcPath), 'Future<void> markTOAsExpired(')));
      expect(body.contains('required int expectedEditRevision,'), true);
      expect(body.contains("'expectedEditRevision': expectedEditRevision,"), true);
    });

    test('05-b production caller 전부가 revision을 넘긴다 (§13)', () {
      final code = _codeOf(_src(_ctrlPath));
      final calls = 'markTOAsExpired('.allMatches(code).length;
      final withRevision =
          'markTOAsExpired(to.id, expectedEditRevision: to.editRevision)'
              .allMatches(_flat(code))
              .length;
      expect(calls, 2, reason: 'caller 수가 바뀌면 이 테스트를 다시 본다');
      expect(withRevision, calls,
          reason: 'revision 없는 caller가 하나라도 있으면 그 경로는 항상 실패한다');
    });

    test('05-c best-effort 성격은 유지된다 (§10)', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_svcPath), 'Future<void> markTOAsExpired(')));
      expect(body.contains("debugPrint('❌ markTOAsExpired 실패 (\$toId): \$e');"),
          true);
      expect(body.contains('rethrow'), false,
          reason: '사용자 action이 아니므로 toast를 새로 만들지 않는다 — 조용한 실패가 계약이다');
      expect(body.contains('ToastHelper'), false);
    });

    test('05-d stale conflict를 강제로 덮어쓰지 않는다 (§9, §11)', () {
      final body = _codeOf(_bodyOf(_src(_svcPath), 'Future<void> markTOAsExpired('));
      // 재시도·최신 revision 재조회·revision 무시 경로가 없어야 한다
      expect(body.contains('.get()'), false);
      expect(body.contains('retry'), false);
      expect(body.contains('expectedEditRevision: 0'), false);
      expect(body.contains("'expectedEditRevision': 0"), false);
    });

    test('05-e optimistic 화면 처리 구조를 바꾸지 않았다 (§11)', () {
      for (final sig in [
        'void _maybeCascadeCloseExpiredTO(',
        'void _maybeCascadeCloseExpiredContractTOs(',
      ]) {
        final body = _flat(_codeOf(_bodyOf(_src(_ctrlPath), sig)));
        expect(body.contains('.then((_) {'), true, reason: sig);
        expect(body.contains('.catchError('), true, reason: sig);
        expect(body.contains('await _service.markTOAsExpired'), false,
            reason: '$sig — fire-and-forget을 await로 바꾸지 않는다');
      }
    });
  });

  // ── §12, §15 범위 ──────────────────────────────────────────────
  group('CLOSEREOPEN-06 범위를 넘지 않았다', () {
    test('06-a 재오픈 CTA를 숨기지 않았다 (§12)', () {
      final code = _codeOf(_src(_cardPath));
      expect(code.contains("label: '공고 재오픈',"), true);
      expect(
          code.contains("onTap: () => _handleSingleTOMenuAction(context, 'reopen'),"),
          true);
      // availability predicate 그대로 — isClosed && isManualClosed
      expect(code.contains('if (isClosed && isManualClosed)'), true);
    });

    test('06-b close mutation 로직은 건드리지 않았다 (§8)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_svcPath), 'Future<bool> closeTOManually(')));
      expect(body.contains("httpsCallable('callableCloseTOManually',"), true);
      expect(body.contains("await callable.call<Map<String, dynamic>>({'toId': toId});"),
          true,
          reason: '서버 계약이 정상이므로 payload를 바꿀 이유가 없다');
      expect(body.contains('expectedEditRevision'), false,
          reason: 'callableCloseTOManually는 이 필드를 요구하지 않는다');
    });

    test('06-c 서버 lifecycle policy/schema 무변경 (§15)', () {
      final fns = _src(_fnsPath);
      for (final marker in [
        'export const callableCloseTOManually',
        'export const callableUpdateTO',
        '"이미 수동 마감된 공고입니다."',
        '"이미 재개된 공고입니다."',
        '"다른 관리자가 공고를 수정했습니다. 최신 내용을 다시 확인해 주세요."',
      ]) {
        expect(fns.contains(marker), true, reason: '$marker 가 사라졌다');
      }
    });

    test('06-d slot batch lifecycle 무변경 (§15)', () {
      final code = _codeOf(_src(_cardPath));
      expect(code.contains("_cfErrorMessage(e, fallback: '종료 처리에 실패했습니다')"),
          true);
      expect(code.contains("_cfErrorMessage(e, fallback: '날짜 재오픈에 실패했습니다')"),
          true);
    });
  });
}
