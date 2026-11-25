// [BULK-DISPATCH-INTEGRITY] 여러 날짜를 한 번에 고르는 것은 **일괄 발송**이다.
//
//   정책(확정): 한 근무일 = 한 Application = 한 독립 계약 = 양측 독립 서명 =
//   독립 PDF. 날짜를 여러 개 고르는 것은 계약을 하나로 합치는 기능이 아니라,
//   독립 계약 N개의 발송을 한 번에 처리하는 기능이다.
//
//   그래서 이 파일이 고정하는 세 문장.
//
//     이미 발송됨 != 실패          — 서버가 막은 중복은 실패가 아니다
//     발송 실패 != 상태 롤백 대상   — 계약이 살아 있는데 지원서만 PENDING 이면 어긋난다
//     건 != 명                    — 선택 단위는 지원서(근무일)다
//
//   실제로 있던 결함:
//     · work_applicants 첫 경로(확정+발송)가 `already-exists` 를 일반 catch 로
//       받아 **확정을 PENDING 으로 되돌렸다.** 계약서는 서버에 그대로 있다.
//       관리자에게는 "실패"로 보여 다시 누르게 만들고, 눌러도 같은 결과였다.
//     · 분모가 `_selectedIds.length` 였다 — 사용자 정보를 못 읽어 처리에서
//       빠진 건도 분모에 들어가 **항상 일부 실패처럼** 보였다.
//     · 문구가 "N명"이었다. 슬롯 없이 들어오면 공고 전체 날짜의 지원서가
//       목록에 오므로 같은 사람의 3일이 "3명"이 됐다.
//     · 'already' 를 `pending_worker` 로 적었다 — 근로자가 이미 서명했을 수도
//       있는데 서명대기로 보여 준다. 모르는 것을 아는 것처럼 쓴 것이다.
//
//   번들링은 **활성화하지 않는다**. `_addSlot` 은 도달 불가 상태 그대로 둔다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

/// 주석을 지운다 — 왜 바꿨는지 적은 문장에 옛 표현이 그대로 남아 있다.
String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 그룹 수집 시점에도 불리므로 expect 대신 예외로 실패시킨다.
String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  if (i < 0) throw StateError('구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  if (j < 0) throw StateError('구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

// ── 집계·문구 판단 복제 ──────────────────────────────────────────────
//
//   화면이 하는 판단 그대로다. 네 결과를 **구별**하는지, 실패를 숨기지
//   않는지가 여기서 실행된다.

enum _Kind { allSent, someAlready, needsCheck, hasFailed }

({_Kind kind, int sent, int already, int unknown, int failed, String msg})
    _summarize(List<String> results, {int skipped = 0}) {
  final total = results.length; // 분모는 **처리 대상** 수다 (선택 수가 아니다)
  final sent = results.where((r) => r == 'sent').length;
  final already = results.where((r) => r == 'already').length;
  final unknown = results.where((r) => r == 'unknown').length;
  final failed = total - sent - already - unknown;
  final skippedMsg =
      skipped > 0 ? '\n$skipped건은 지원자 정보를 불러오지 못해 시도하지 못했습니다.' : '';
  final unknownMsg = unknown > 0
      ? '\n$unknown건은 처리 여부를 확인하지 못했습니다. 목록에서 계약 상태를 확인해주세요.'
      : '';
  if (failed > 0) {
    return (
      kind: _Kind.hasFailed,
      sent: sent,
      already: already,
      unknown: unknown,
      failed: failed,
      msg: '$sent/$total건 계약서 발송 완료. '
          '실패한 $failed건은 다시 시도해주세요.$unknownMsg$skippedMsg',
    );
  }
  if (unknown > 0 || skipped > 0) {
    return (
      kind: _Kind.needsCheck,
      sent: sent,
      already: already,
      unknown: unknown,
      failed: 0,
      msg: '$sent건 계약서 발송 완료.'
          '${already > 0 ? ' ($already건은 이미 발송된 근무)' : ''}'
          '$unknownMsg$skippedMsg',
    );
  }
  if (already > 0) {
    return (
      kind: _Kind.someAlready,
      sent: sent,
      already: already,
      unknown: 0,
      failed: 0,
      msg: sent > 0
          ? '$sent건 계약서를 발송했습니다 ($already건은 이미 발송된 근무)'
          : '$already건은 이미 계약서가 발송된 근무예요',
    );
  }
  return (
    kind: _Kind.allSent,
    sent: sent,
    already: 0,
    unknown: 0,
    failed: 0,
    msg: '$total건 계약서를 발송했습니다',
  );
}

void main() {
  final workRaw = _read('lib/screens/business_admin/dialogs/work_applicants_dialog.dart');
  final dayRaw = _read('lib/screens/business_admin/dialogs/day_applicants_dialog.dart');
  final work = _codeOf(workRaw);
  final day = _codeOf(dayRaw);
  final svc = _codeOf(_read('lib/services/contract_service.dart'));

  // 첫 경로 = 대기자 확정 + 계약 발송. 두 번째 경로 = 확정자 계약서 일괄작성.
  //   `_codeOf` 가 주석을 지우므로 구간 표지도 **코드**여야 한다.
  final path1 = _slice(work, 'Future<String> processOne(Map<String, dynamic> item) async {',
      'const batchSize = 5;');
  final path1Tail =
      _slice(work, 'const batchSize = 5;', 'for (var toId in _affectedOtherTOIds)');
  final path2 = _slice(work, 'Future<void> _batchCreateContractsForConfirmed() async {',
      'Future<void> _updateLocalStats');

  group('BDI-1 — 네 결과를 구별한다', () {
    test('BDI-01 집계는 성공·이미 처리됨·실패를 따로 센다', () {
      final r = _summarize(['sent', 'already', 'failed', 'sent']);
      expect(r.sent, 2);
      expect(r.already, 1);
      expect(r.failed, 1);
      expect(r.kind, _Kind.hasFailed);
      expect(r.msg, contains('실패한 1건'), reason: '실패 수를 숨기면 안 된다');
      expect(r.msg, contains('2/4건'));
    });

    test('BDI-02 전부 "이미 발송됨"이면 실패가 아니다', () {
      final r = _summarize(['already', 'already']);
      expect(r.kind, _Kind.someAlready);
      expect(r.failed, 0, reason: '서버가 막은 중복은 실패가 아니다');
      expect(r.msg, contains('이미 계약서가 발송된 근무'));
      expect(r.msg.contains('실패'), isFalse);
    });

    test('BDI-03 일부만 이미 발송된 경우 두 수를 함께 말한다', () {
      final r = _summarize(['sent', 'already']);
      expect(r.msg, contains('1건 계약서를 발송했습니다'));
      expect(r.msg, contains('1건은 이미 발송된 근무'));
    });

    test('BDI-04 하나라도 실패하면 전체 성공으로 말하지 않는다', () {
      final r = _summarize(['sent', 'sent', 'failed']);
      expect(r.kind, _Kind.hasFailed);
      expect(r.msg.startsWith('2/3건'), isTrue,
          reason: '분자/분모를 함께 보여야 몇 건이 남았는지 안다');
    });

    test('BDI-05 전부 성공일 때만 성공 문구다', () {
      final r = _summarize(['sent', 'sent']);
      expect(r.kind, _Kind.allSent);
      expect(r.msg, '2건 계약서를 발송했습니다');
    });

    test('BDI-06 시도하지 못한 건을 성공으로 덮지 않는다', () {
      // 지원자 정보를 못 읽어 처리 대상에서 빠진 건 — 성공도 실패도 아니다.
      //   분모를 처리 대상으로 바꾸면 이 건은 **아무 데도 안 나온다.**
      final r = _summarize(['sent', 'sent'], skipped: 1);
      expect(r.kind, _Kind.needsCheck);
      expect(r.msg, contains('2건 계약서 발송 완료'));
      expect(r.msg, contains('1건은 지원자 정보를 불러오지 못해 시도하지 못했습니다'));
    });

    test('BDI-08 "처리 여부 확인 필요"는 실패가 아니다', () {
      // 타임아웃·연결 끊김 — 서버가 썼는지 모른다. 실패로 세면 관리자는
      //   롤백됐다고 믿고, 성공으로 세면 안 보냈을 수 있다.
      final r = _summarize(['sent', 'unknown']);
      expect(r.kind, _Kind.needsCheck);
      expect(r.unknown, 1);
      expect(r.failed, 0, reason: '모르는 것을 실패로 세지 않는다');
      expect(r.msg, contains('1건은 처리 여부를 확인하지 못했습니다'));
    });

    test('BDI-09 네 결과가 한 번에 나와도 각각 센다', () {
      final r = _summarize(['sent', 'already', 'unknown', 'failed'], skipped: 1);
      expect(r.kind, _Kind.hasFailed);
      expect([r.sent, r.already, r.unknown, r.failed], [1, 1, 1, 1]);
      expect(r.msg, contains('1/4건'));
      expect(r.msg, contains('실패한 1건'));
      expect(r.msg, contains('1건은 처리 여부를'));
      expect(r.msg, contains('1건은 지원자 정보를'));
    });

    test('BDI-07 실패와 미시도를 함께 말한다', () {
      final r = _summarize(['sent', 'failed'], skipped: 2);
      expect(r.kind, _Kind.hasFailed);
      expect(r.msg, contains('실패한 1건'));
      expect(r.msg, contains('2건은 지원자 정보를'));
    });
  });

  group('BDI-2 — 두 발송 경로가 모두 3분기다 (실제 배선)', () {
    test('BDI-10 첫 경로 processOne 은 String 세 값을 돌려준다', () {
      expect(_flat(path1), contains("return 'sent';"));
      expect(_flat(path1), contains("return 'already';"));
      expect(_flat(path1), contains("return 'failed';"));
      expect(path1.contains('return true;'), isFalse,
          reason: 'bool 로 되돌아가면 "이미 발송됨"이 다시 실패가 된다');
    });

    test('BDI-11 already-exists 를 FirebaseFunctionsException 으로 집는다', () {
      expect(_flat(path1), contains('on FirebaseFunctionsException catch'));
      expect(_flat(path1), contains("e.code == 'already-exists'"));
      expect(workRaw, contains("import 'package:cloud_functions/cloud_functions.dart';"));
    });

    test('BDI-12 already 분기는 지원서 상태를 롤백하지 않는다', () {
      // 'already' 를 돌려주는 지점까지의 코드에 롤백이 없어야 한다.
      //   여기서 PENDING 으로 되돌리면 계약서는 살아 있는데 지원서만
      //   되돌아가 **계약과 지원서 상태가 어긋난다.**
      final already = _slice(path1, "e.code == 'already-exists'", "return 'already';");
      expect(already.contains('updateApplicationStatus'), isFalse,
          reason: '중복 발송 차단이 확정 취소의 이유가 될 수 없다');
      expect(already.contains('batchRollbackWithCollateral'), isFalse);
    });

    test('BDI-16 응답을 못 받은 건은 상태를 되돌리지 않는다', () {
      // 커밋됐을 수도 있다 — 되돌리면 근로자가 PENDING 지원서의 계약서에
      //   서명한다. 확정 유지가 복구 가능한 쪽이다.
      //
      // [RECONCILE 이후] 이 분기는 원장을 한 번 보되 **되돌리지는 않는다**
      //   (`mayRollback: false`). 더 자세한 경계는
      //   bulk_dispatch_error_reconciliation_test 가 고정한다.
      final unknown = _slice(path1, '_indeterminateCfCodes.contains(e.code)',
          '} catch (itemErr)');
      expect(unknown.contains('updateApplicationStatus'), isFalse);
      expect(_flat(unknown), contains('mayRollback: false'));
      expect(_flat(work), contains("const Set<String> _indeterminateCfCodes = { 'deadline-exceeded', "
          "'unavailable', 'internal', 'cancelled', 'aborted', };"));
      // 집계·문구에서 실패와 섞이지 않는다.
      expect(_flat(path1Tail), contains("results.where((r) => r == 'unknown')"));
      expect(_flat(path1Tail),
          contains('toProcess.length - successCount - alreadyCount - unknownCount'));
      expect(_flat(path1Tail), contains('처리 여부를 확인하지 못했습니다'));
      // 모르는 상태는 재조회로 메운다 — 첫 경로는 항상 목록을 다시 읽는다.
      expect(_flat(path1Tail), contains('await _loadApplicants();'));
    });

    test('BDI-13 실패는 **쓰지 않고** 분류된다', () {
      // [ROLLBACK-ATOMICITY] 확정 롤백이 제거됐다. 그 쓰기가 다른 관리자의
      //   정상 계약을 void 할 수 있었고(실측: scripts/rbatom-rollback-race.js),
      //   그 틈을 닫는 안전성은 이 환경에서 입증할 수 없었다.
      //   자세한 경계는 bulk_dispatch_error_reconciliation_test 가 고정한다.
      final settle = _slice(work, 'Future<String> settleFailure(',
          'Future<String> processOne(Map<String, dynamic> item)');
      expect(settle.contains('status: AppStatus.pending'), isFalse,
          reason: '롤백 쓰기가 되살아났다');
      expect(_flat(settle), contains("return 'needsReissue';"));
      // 겹침 TO 캐시 무효화는 유지한다(확정은 그대로이므로 집계가 바뀐다).
      expect(_flat(path1), contains('_affectedOtherTOIds.addAll(affectedTOIds)'));
    });

    test('BDI-14 두 번째 경로(확정자 일괄작성)도 3분기다', () {
      expect(_flat(path2), contains('Future<String> processOne'));
      expect(_flat(path2), contains("e.code == 'already-exists'"));
      expect(_flat(path2), contains("return 'already';"));
      expect(_flat(path2), contains("results[j] == 'sent'"));
      expect(_flat(path2), contains("results[j] == 'already'"));
    });

    test('BDI-15 당일 명단 경로의 기존 3분기는 유지된다', () {
      final dayPath = _slice(day, 'Future<String> processOne(ApplicationModel app) async {',
          'Future<bool?> _showBatchContractPreview');
      expect(_flat(dayPath), contains("e.code == 'already-exists'"));
      expect(_flat(dayPath), contains("return 'already';"));
      expect(_flat(dayPath), contains('final failedCount = toProcess.length'));
    });
  });

  group('BDI-3 — 분모는 처리 대상이고, 모르는 상태를 적지 않는다', () {
    test('BDI-20 첫 경로의 분모가 toProcess.length 다', () {
      expect(_flat(path1Tail), contains(r'$successCount/${toProcess.length}건'));
      expect(path1Tail.contains(r'${_selectedIds.length}명'), isFalse,
          reason: '사용자 정보를 못 읽어 빠진 건까지 분모에 넣으면 항상 실패처럼 보인다');
      expect(path1Tail.contains(r'/${_selectedIds.length}'), isFalse);
    });

    test('BDI-21 두 경로 모두 failedCount 를 계산해 보여 준다', () {
      expect(_flat(path1Tail), contains('final failedCount = toProcess.length'));
      expect(_flat(path2), contains('final failedCount = toProcess.length'));
    });

    test('BDI-22 "이미 발송됨"의 계약 상태를 추측해 쓰지 않는다', () {
      // 두 번째 경로: 성공한 건만 pending_worker 로 적고, already 는 재조회한다.
      final tail = _slice(path2, 'if (successCount > 0)', '} catch (e)');
      // [REISSUE-RECOVERY] 계약 상태는 `ContractStatusBatch` 가 됐다 —
      //   낙관적 반영은 `withStatus` 로 한다(unresolved 도 같이 지워진다).
      expect(_flat(tail), contains("withStatus(app.id, 'pending_worker')"));
      final alreadyBranch = _slice(tail, 'if (alreadyCount > 0)', '}');
      expect(_flat(alreadyBranch), contains('_loadApplicants()'),
          reason: '근로자가 이미 서명했을 수 있다 — 서버에서 다시 읽는다');
    });

    test('BDI-24 미리보기가 약속하는 건수 = 실제로 시도하는 건수', () {
      final approve = _slice(work, 'Future<void> _batchApprove() async {',
          'Future<bool?> _showBatchContractPreview');
      // 대상 수집이 미리보기 **앞**에 있다.
      final collectAt = approve.indexOf("if (item.isNotEmpty && item['user'] != null) toProcess.add(item);");
      final previewAt = approve.indexOf('_showBatchContractPreview(');
      expect(collectAt, greaterThan(-1));
      expect(previewAt, greaterThan(collectAt),
          reason: '선택 수를 약속하고 더 적게 보내면 관리자는 보냈다고 믿는다');
      expect(_flat(approve), contains('count: toProcess.length,'));
      expect(approve.contains('count: _selectedIds.length,'), isFalse);
    });

    test('BDI-25 전부 시도 불가면 발송을 시작하지 않는다', () {
      final approve = _slice(work, 'Future<void> _batchApprove() async {',
          'Future<bool?> _showBatchContractPreview');
      final guard = _slice(approve, 'if (toProcess.isEmpty)', 'final firstItem');
      expect(_flat(guard), contains('지원자 정보를 불러오지 못했습니다'));
      expect(_flat(guard), contains('return;'));
      expect(_flat(approve),
          contains(r'final skippedCount = _selectedIds.length - toProcess.length;'));
    });

    test('BDI-26 첫 건의 지원자 정보 부재가 전체를 중단시키지 않는다', () {
      final approve = _slice(work, 'Future<void> _batchApprove() async {',
          'Future<bool?> _showBatchContractPreview');
      expect(_flat(approve), contains('final firstItem = toProcess.first;'),
          reason: '시도 가능한 것 중 첫 건을 미리보기 대상으로 쓴다');
      expect(approve.contains("final firstUser = firstItem['user'] as UserModel?;"),
          isFalse,
          reason: 'toProcess 는 user 가 있는 건만 담는다 — 다시 null 검사로 중단하지 않는다');
    });

    test('BDI-23 당일 명단도 already 를 pending_worker 로 적지 않는다', () {
      final dayTail = _slice(day, 'if (successCount > 0) {', 'Future<bool?> _showBatchContractPreview');
      expect(_flat(dayTail), contains('if (alreadyCount > 0) { _hasChanges = true; await _load(); }'),
          reason: '모르는 상태는 재조회로 메운다');
      // successApps 에 already 건을 섞어 넣지 않는다.
      final loop = _slice(day, "results[j] == 'already'", 'final failedCount');
      expect(loop.contains('successApps.add'), isFalse);
    });
  });

  group('BDI-4 — 단위는 건이다 (한 근무일 = 한 계약)', () {
    test('BDI-30 선택 수 표시가 "건"이다', () {
      expect(_flat(work), contains(r"'선택: ${_selectedIds.length}건'"));
      expect(_flat(work), contains(r"'${_selectedIds.length}건'"));
      expect(work.contains(r"'선택: ${_selectedIds.length}명'"), isFalse,
          reason: '슬롯 없이 들어오면 같은 사람의 여러 날짜가 여러 건으로 잡힌다');
    });

    test('BDI-31 미리보기가 한 근무일 = 계약서 1장임을 말한다', () {
      final banner = _slice(work, '아래 조건으로 선택한', '이름·생년월일');
      expect(banner, contains(r'$count건의 근무'));
      expect(_flat(work), contains('근무일마다 계약서가 1장씩 따로 만들어집니다.'),
          reason: '관리자가 "3일 = 계약 1장"으로 오해하지 않게 한다');
      expect(_flat(work), contains(r"Text('$count건 발송')"));
      expect(work.contains(r'$count명에게 계약서가 발송됩니다'), isFalse);
    });

    test('BDI-32 같은 선택 집합을 쓰는 거절 문구도 같은 단위다', () {
      expect(_flat(work), contains(r"'선택한 ${_selectedIds.length}건의 지원을 거절합니다."));
      expect(work.contains(r"'$successCount명이 거절되었습니다'"), isFalse);
    });

    test('BDI-33 좌석·부족 수는 그대로 "명"이다', () {
      // 자리 수는 사람 수가 맞다 — 단위 통일이라는 이름으로 쓸어내지 않는다.
      expect(_flat(work), contains(r"'근무 초대 ($shortage명 부족)'"));
    });
  });

  group('BDI-5 — 번들링을 새로 활성화하지 않았다', () {
    test('BDI-40 _createNew 는 여전히 저장하지 않는다 (isNewUnsaved)', () {
      expect(_flat(svc), contains('isNewUnsaved: true'),
          reason: 'pending_employer 계약이 저장되기 시작하면 번들링이 깨어난다');
    });

    test('BDI-41 일괄 루프는 건별로 findOrCreate → 서명이다', () {
      for (final p in [path1, path2]) {
        expect(_flat(p), contains('findOrCreateContract('));
        expect(_flat(p), contains('saveEmployerSignature('));
      }
      // 메모리에서 날짜를 묶는 그룹핑을 넣지 않았다.
      expect(work.contains('_addSlot'), isFalse);
      expect(work.contains('groupBy'), isFalse);
    });

    test('BDI-42 ContractSlot 스키마는 6필드 그대로다', () {
      final model = _read('lib/models/core/employment_contract_model.dart');
      final cls = _slice(model, 'class ContractSlot {', 'String get wageTypeLabel');
      for (final f in ['applicationId', 'workDate', 'startTime', 'endTime', 'wage', 'wageType']) {
        expect(cls, contains(f), reason: '$f 가 사라졌다');
      }
      expect(cls.contains('breakMinutes'), isFalse,
          reason: '휴게시간 필드 추가는 정책 결정 사항이다 (이번 범위 아님)');
    });

    test('BDI-43 동시성 정책 [C01] 은 그대로다 (배치 5건 병렬)', () {
      expect(_flat(path1Tail), contains('const batchSize = 5;'));
      expect(_flat(path2), contains('const batchSize = 5;'));
      expect(_flat(day), contains('const batchSize = 5;'));
    });
  });

  group('BDI-6 — 발송 성공의 근거는 알림 수가 아니다', () {
    test('BDI-50 집계는 processOne 결과만 센다', () {
      // 알림·FCM 결과를 세는 코드가 집계에 들어오면 안 된다.
      for (final p in [path1Tail, path2]) {
        expect(_flat(p), contains('await Future.wait(batch.map(processOne))'));
        expect(p.contains('notification'), isFalse);
        expect(p.contains('fcm'), isFalse);
      }
    });

    test('BDI-51 성공 판단은 서명 저장까지 끝난 뒤다', () {
      // saveEmployerSignature 가 'sent' 보다 **앞**에 있어야 한다.
      for (final p in [path1, path2]) {
        final sign = p.indexOf('saveEmployerSignature(');
        final sent = p.indexOf("return 'sent';");
        expect(sign, greaterThan(-1));
        expect(sent, greaterThan(sign),
            reason: '서명 저장 전에 성공으로 세면 발송되지 않은 계약을 성공이라 말한다');
      }
    });
  });
}
