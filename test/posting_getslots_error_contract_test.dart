// [POSTING-V2-03D.1] getSlots 실패/완전성 계약 — ERROR != ZERO
//
// 03D READ에서 확인된 것:
//   · getSlots의 마지막 catch가 모든 실패를 `return []` 로 바꿨다
//   · 그래서 "근무일이 0개인 공고"와 "조회가 실패한 공고"가 같은 값이 됐다
//   · caller 6곳 중 3곳은 실패 UI를 갖고도 그 코드에 도달하지 못했고
//     (EditTO의 slotSyncFailed 경고, SlotBatchSelectDialog의 실패 토스트,
//      JobPostingScreen의 슬롯 없음 화면)
//     1곳은 그 0을 **전체 개수**로 믿고 공고까지 삭제할 수 있었다
//
// 계약(§1):
//   · 조회 성공 + 문서 0개        → []            (TRUE EMPTY)
//   · 조회 실패                   → 예외 전파
//   · 상한 초과                   → FlexSlotOverflowException (03C.1)
//   · requireComplete + 파싱 누락 → SlotDataException
//
// [TARGETED CORRECTION 2] LEGACY != MALFORMED.
//   처음에는 완전성을 opt-in으로만 두고 파싱 실패를 "허용된 손실"로 봤는데,
//   그 손실의 정체가 **정상 슬롯**이었다. `SlotModel.createdAt`은 앱 어디에서도
//   읽히지 않는 메타데이터인데 required라서, 결측 문서 하나가 통째로 버려졌다.
//   (서버는 serverTimestamp로 쓰므로 pending-write 스냅샷에서도 결측이 보인다)
//   → 모델을 nullable로 고쳐 정상 슬롯이 모든 caller에서 살아남게 하고,
//     completeness는 진짜 파손(date 결측/타입오류)만 가리키게 한다.
//
// FirestoreService는 Firebase 초기화를 요구해 단위 테스트로 호출할 수 없다.
// 예외 계약은 타입으로, 배선은 소스로 검증한다.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/services/firestore_service.dart';

const _toPath = 'lib/services/firestore/to_firestore.dart';
const _svcPath = 'lib/services/firestore_service.dart';
const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _jobPostingPath = 'lib/screens/common/job_posting_screen.dart';
const _batchDialogPath =
    'lib/screens/business_admin/dialogs/slot_batch_select_dialog.dart';
const _editToPath =
    'lib/screens/business_admin/to_management/edit_to_screen.dart';

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

String _caseBlock(String source, String caseLabel) {
  final start = source.indexOf(caseLabel);
  if (start == -1) throw StateError('$caseLabel 를 찾지 못함');
  final end = source.indexOf('break;', start);
  if (end == -1) throw StateError('$caseLabel 의 break를 찾지 못함');
  return source.substring(start, end);
}

/// 완전성 판정 replica — 문서 수와 파싱 수만으로 갈린다.
bool incomplete({required int docs, required int parsed}) => parsed != docs;

// ── raw 슬롯 fixture ─────────────────────────────────────────────
enum SlotShape {
  /// 현재 스키마 — createdAt 포함
  current,

  /// supported legacy — createdAt 없음 (서버 serverTimestamp pending 포함)
  legacy,

  /// genuinely malformed — date 자체가 없거나 Timestamp가 아니다
  malformed,
}

Map<String, dynamic> _rawSlot(DateTime date, SlotShape shape) => {
      if (shape != SlotShape.malformed) 'date': Timestamp.fromDate(date),
      if (shape == SlotShape.malformed) 'date': 'not-a-timestamp',
      'status': 'open',
      'confirmedCount': 0,
      'pendingCount': 0,
      if (shape == SlotShape.current) 'createdAt': Timestamp.fromDate(date),
    };

/// getSlots의 파싱 단계 replica — 실제 canonical parser를 그대로 쓴다.
List<SlotModel> _parse(List<Map<String, dynamic>> raws) => raws
    .map((r) => SlotModel.tryFromMap(r, 'doc_${raws.indexOf(r)}', 'to1'))
    .whereType<SlotModel>()
    .toList();

void main() {
  // ── §1 계약 값 ─────────────────────────────────────────────────
  group('GETSLOTS-01 실패 계약이 타입으로 존재한다', () {
    test('01-a SlotDataException이 어느 공고에서 몇 개가 빠졌는지 말한다', () {
      const e = SlotDataException('to_1', 10, 7);
      expect(e.toId, 'to_1');
      expect(e.documentCount, 10);
      expect(e.parsedCount, 7);
      expect(e.toString().contains('to_1'), true);
      expect(e.toString().contains('10'), true);
      expect(e.toString().contains('7'), true);
    });

    test('01-b overflow와 parse 실패는 서로 다른 타입이다', () {
      const parse = SlotDataException('to_1', 10, 7);
      const overflow = FlexSlotOverflowException('to_1', kMaxFlexSlotsPerTO);
      expect(parse is FlexSlotOverflowException, false);
      expect(overflow is SlotDataException, false);
      expect(
          parse is Exception && overflow is Exception, true,
          reason: '둘 다 예외로 전파돼야 catch가 잡는다');
    });

    test('01-c 완전성 판정 — 0개 파싱 실패만 정상', () {
      expect(incomplete(docs: 0, parsed: 0), false, reason: 'TRUE EMPTY');
      expect(incomplete(docs: 12, parsed: 12), false);
      expect(incomplete(docs: 12, parsed: 11), true,
          reason: '1개만 빠져도 "전체"가 아니다');
      expect(incomplete(docs: 12, parsed: 0), true);
    });
  });

  // ── §2 generic catch → rethrow ─────────────────────────────────
  group('GETSLOTS-02 조회 실패를 빈 목록으로 바꾸지 않는다', () {
    test('02-a 마지막 catch가 rethrow로 끝난다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_toPath), 'Future<List<SlotModel>> getSlots(')));
      expect(body.contains("debugPrint('❌ [TO] 슬롯 조회 실패: \$e'); rethrow;"), true,
          reason: 'ERROR != ZERO');
    });

    test('02-b 본문 어디에도 return [] 가 남아 있지 않다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_toPath), 'Future<List<SlotModel>> getSlots(')));
      expect(body.contains('return [];'), false);
    });

    test('02-c 03C overflow sentinel은 그대로다 (§2)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_toPath), 'Future<List<SlotModel>> getSlots(')));
      expect(body.contains('.limit(_kFlexSlotProbeLimit)'), true);
      expect(
          body.contains('if (snap.docs.length > kMaxFlexSlotsPerTO) { '
              'throw FlexSlotOverflowException(toId, kMaxFlexSlotsPerTO); }'),
          true);
      expect(body.contains('} on FlexSlotOverflowException { rethrow; }'), true);
    });

    test('02-d Result/Either 구조를 도입하지 않았다 (§15)', () {
      final code = _codeOf(_src(_toPath));
      expect(code.contains('Result<'), false);
      expect(code.contains('Either<'), false);
      final sig = _flat(_codeOf(
          _bodyOf(_src(_toPath), 'Future<List<SlotModel>> getSlots(')));
      expect(sig.startsWith('Future<List<SlotModel>> getSlots('), true,
          reason: '반환 타입을 바꾸지 않고 예외로만 표현한다');
    });
  });

  // ── §4, §5 완전성은 opt-in, visibleOnly보다 앞 ──────────────────
  group('GETSLOTS-03 완전성 요구는 선택이고 필터보다 앞이다', () {
    // [TC2 재작성] 기본값이 false인 이유가 "레거시 손실을 눈감아 주기 위해"였는데,
    // 그 레거시는 이제 정상 파싱된다. 기본값은 그대로 두되 이유가 바뀌었다:
    // 표시 전용 화면은 파손 문서 하나 때문에 전체가 안 보이는 편이 더 나쁘다.
    test('03-a requireComplete 기본값이 false다 (표시 화면 우선)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_toPath), 'Future<List<SlotModel>> getSlots(')));
      expect(body.contains('bool requireComplete = false,'), true,
          reason: '파손 문서 1개로 나머지 날짜까지 못 보게 만들지 않는다');
    });

    test('03-b requireComplete일 때만 SlotDataException을 던진다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_toPath), 'Future<List<SlotModel>> getSlots(')));
      expect(
          body.contains('if (requireComplete && slots.length != snap.docs.length) { '
              'throw SlotDataException(toId, snap.docs.length, slots.length); }'),
          true);
    });

    test('03-c 완전성 판정이 visibleOnly 필터보다 앞이다 (§5)', () {
      final body = _codeOf(
          _bodyOf(_src(_toPath), 'Future<List<SlotModel>> getSlots('));
      final completeIdx = body.indexOf('throw SlotDataException(');
      final visibleIdx = body.indexOf('if (!visibleOnly) return slots;');
      expect(completeIdx, greaterThan(-1));
      expect(visibleIdx, greaterThan(completeIdx),
          reason: '필터가 먼저면 숨겨진 슬롯 때문에 불완전 판정이 난다');
    });

    test('03-d 완전성 판정이 파싱 뒤다', () {
      final body = _codeOf(
          _bodyOf(_src(_toPath), 'Future<List<SlotModel>> getSlots('));
      final parseIdx = body.indexOf('SlotModel.tryFromMap(');
      final completeIdx = body.indexOf('throw SlotDataException(');
      expect(parseIdx, greaterThan(-1));
      expect(completeIdx, greaterThan(parseIdx));
    });

    // [TC2 재작성] 이전 판단("파싱 완화가 아니라 완전성 요구로 해결한다")이
    // 틀렸다. 완전성 요구만으로는 정상 레거시 슬롯이 계속 버려진 채였고,
    // caller마다 그 손실을 다르게 감췄다. 원인을 canonical parser에서 고친다.
    test('03-e canonical parser 한 곳에서 해결했다 (caller별 우회 없음)', () {
      final code = _codeOf(_src('lib/models/core/slot_model.dart'));
      expect(code.contains('static SlotModel? tryFromMap('), true);
      expect(code.contains('final DateTime? createdAt;'), true);

      // 어느 caller도 자체 파서/raw 디코딩 우회로를 만들지 않았다 (§7)
      for (final p in [_jobPostingPath, _batchDialogPath, _editToPath, _cardPath]) {
        final c = _codeOf(_src(p));
        expect(c.contains("['createdAt']"), false, reason: p);
        expect(c.contains('SlotModel.fromMap('), false, reason: p);
        expect(c.contains('SlotModel.tryFromMap('), false, reason: p);
      }
    });
  });

  // ── §6 파괴적 호출부 ────────────────────────────────────────────
  group('GETSLOTS-04 개수로 공고를 지우는 경로가 먼저 멈춘다', () {
    test('04-a 유일하게 requireComplete를 쓰는 곳이 일괄삭제다', () {
      final code = _codeOf(_src(_cardPath));
      expect(code.contains('getSlots(masterTO.id, requireComplete: true)'), true);

      // 다른 caller는 계속 기존(부분 파싱 허용) 계약을 쓴다
      for (final p in [_jobPostingPath, _batchDialogPath, _editToPath]) {
        expect(_codeOf(_src(p)).contains('requireComplete'), false, reason: p);
      }
    });

    test('04-b deletesAll 계산에 도달하기 전에 중단한다', () {
      final block = _flat(_codeOf(_caseBlock(_src(_cardPath), "case 'batchDelete':")));
      final guardIdx = block.indexOf('if (totalSlotCount == null) {');
      final deletesAllIdx = block.indexOf('final deletesAll =');
      expect(guardIdx, greaterThan(-1), reason: '실패 시 중단 분기가 없다');
      expect(deletesAllIdx, greaterThan(guardIdx),
          reason: '실패한 개수로 "전부 삭제"를 판정하면 공고까지 지운다');
      expect(block.contains('return; }'), true);
    });

    test('04-c 실패는 삭제 자체를 수행하지 않는다', () {
      final block = _flat(_codeOf(_caseBlock(_src(_cardPath), "case 'batchDelete':")));
      final guardIdx = block.indexOf('if (totalSlotCount == null) {');
      final batchDeleteIdx = block.indexOf('batchDeleteSlots(');
      final deleteTOIdx = block.indexOf('deleteTO(masterTO.id)');
      expect(batchDeleteIdx, greaterThan(guardIdx));
      expect(deleteTOIdx, greaterThan(guardIdx));
    });

    test('04-d 사용자에게 원시 예외를 보여주지 않는다 (§12)', () {
      final block = _flat(_codeOf(_caseBlock(_src(_cardPath), "case 'batchDelete':")));
      expect(block.contains("ToastHelper.showError('날짜 목록을 불러오는데 실패했습니다.')"),
          true, reason: '기존 문구 재사용');
      expect(block.contains('showError(\$e'), false);
      expect(block.contains('SlotDataException'), false,
          reason: '예외 타입명이 UI 문구에 새지 않는다');
    });

    test('04-e 개수 기반 추론이라는 한계를 backlog로 남겼다 (§6)', () {
      final raw = _src(_cardPath);
      expect(raw.contains('[BACKLOG-BATCH-DELETE-DELETESALL-DERIVED-FROM-COUNT]'),
          true);
    });

    test('04-f deletesAll 의미 자체는 바꾸지 않았다 (§15)', () {
      final block = _flat(_codeOf(_caseBlock(_src(_cardPath), "case 'batchDelete':")));
      expect(block.contains('deleteSlots.length >= totalSlotCount'), true,
          reason: '비교 대상만 완전성이 보장된 값으로 바뀌었을 뿐이다');
    });
  });

  // ── §8 JobPostingScreen ────────────────────────────────────────
  group('GETSLOTS-05 지원 화면이 실패를 날짜 없음으로 표시하지 않는다', () {
    test('05-a 일반 실패도 03C의 _slotLoadError로 합류한다', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_jobPostingPath), 'Future<void> _loadSlots(')));
      expect('_slotLoadError = true;'.allMatches(body).length, 2,
          reason: 'overflow 경로 1 + 일반 실패 경로 1');
      expect(body.contains('_slotLoadError = false;'), true,
          reason: '재시도 성공 시 실패 상태가 남으면 안 된다');
    });

    test('05-b 일반 실패도 목록을 비우고 알린다', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_jobPostingPath), 'Future<void> _loadSlots(')));
      final genericIdx = body.lastIndexOf('} catch (e) {');
      final tail = body.substring(genericIdx);
      expect(tail.contains('_allSlots = [];'), true);
      expect(tail.contains('_slotLoadError = true;'), true);
      expect(tail.contains("ToastHelper.showError('근무 일정을 불러오지 못했습니다')"), true,
          reason: '03C에서 쓰던 문구를 그대로 쓴다');
    });

    test('05-c 새 error state를 추가하지 않았다 (§8)', () {
      final code = _codeOf(_src(_jobPostingPath));
      expect('bool _slotLoadError'.allMatches(code).length, 1,
          reason: 'overflow 전용/일반 전용으로 쪼개면 화면 분기가 두 배가 된다');
    });

    test('05-d 지원 action 차단은 그대로 한 번만 건다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_jobPostingPath), 'Future<void> _showConfirmAndApply(')));
      expect(body.contains('if (_to!.isFlexType && _slotLoadError) {'), true);
    });
  });

  // ── §9 날짜 선택 다이얼로그 ─────────────────────────────────────
  group('GETSLOTS-06 날짜 선택 다이얼로그가 실패와 빈 목록을 구분한다', () {
    test('06-a 실패 상태를 화면에 남긴다', () {
      final code = _codeOf(_src(_batchDialogPath));
      expect(code.contains('bool _loadError = false;'), true,
          reason: 'toast는 사라지고 목록만 남으면 "날짜 없음"으로 읽힌다');
    });

    test('06-b 실패 분기가 빈 목록 분기보다 먼저다', () {
      final body = _codeOf(_bodyOf(_src(_batchDialogPath), 'Widget _buildContent('));
      final errIdx = body.indexOf('if (_loadError) {');
      final emptyIdx = body.indexOf('if (_slots.isEmpty) {');
      expect(errIdx, greaterThan(-1));
      expect(emptyIdx, greaterThan(errIdx));
    });

    test('06-c 두 화면이 서로 다른 말을 한다', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_batchDialogPath), 'Widget _buildContent(')));
      expect(body.contains("'날짜 목록을 불러오는데 실패했습니다.'"), true,
          reason: '기존 toast 문구 재사용 (§12)');
      expect(body.contains("'등록된 날짜가 없습니다'"), true,
          reason: 'TRUE EMPTY 문구는 그대로 (§11)');
      expect(body.contains('Icons.cloud_off'), true);
    });

    test('06-d 실패 시 이전 목록을 남기지 않는다', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_batchDialogPath), 'Future<void> _loadSlots(')));
      final catchIdx = body.indexOf('} catch (e) {');
      final tail = body.substring(catchIdx);
      expect(tail.contains('_slots = [];'), true);
      expect(tail.contains('_loadError = true;'), true);
    });

    test('06-e 성공 시 실패 상태가 해제된다', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_batchDialogPath), 'Future<void> _loadSlots(')));
      expect(body.contains('_slots = filtered; _isLoading = false; _loadError = false;'),
          true);
    });
  });

  // ── §7 EditTO ──────────────────────────────────────────────────
  group('GETSLOTS-07 공고 수정 화면의 두 경로가 살아난다', () {
    test('07-a 로드 실패가 기존 catch로 전달된다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_editToPath), 'Future<void> _loadData(')));
      expect(body.contains('_firestoreService.getSlots(widget.to.id)'), true);
      expect(body.contains("ToastHelper.showError('데이터를 불러오는데 실패했습니다')"), true,
          reason: 'getSlots가 삼키던 동안에는 실행될 수 없던 코드다');
    });

    test('07-b 첫 근무일을 모르는 상태를 성공으로 만들지 않는다', () {
      final body = _codeOf(_bodyOf(_src(_editToPath), 'Future<void> _loadData('));
      final slotsIdx = body.indexOf('final slots = await slotsFuture;');
      final setIdx = body.indexOf('_firstSlotDate = firstSlotDate;');
      expect(slotsIdx, greaterThan(-1));
      expect(setIdx, greaterThan(slotsIdx),
          reason: 'await가 던지면 setState에 도달하지 않는다');
      expect(body.contains('catch'), true);
    });

    test('07-c 저장 시 슬롯 동기화 실패 경고가 도달 가능해졌다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_editToPath), 'Future<void> _saveChanges(')));
      expect(body.contains('bool slotSyncFailed = false;'), true);
      expect(body.contains('slotSyncFailed = true;'), true);
      expect(
          body.contains("ToastHelper.showWarning('공고가 수정되었으나 슬롯 동기화에 실패했습니다. "
              "다시 저장해 주세요.')"),
          true);
      expect(body.contains('NavigationHelper.popWithChange(context);'), true,
          reason: '성공 경로는 그대로 pop한다');
    });

    test('07-d 실패 시 화면에 남아 재저장이 가능하다', () {
      final body = _codeOf(_bodyOf(_src(_editToPath), 'Future<void> _saveChanges('));
      final warnIdx = body.indexOf('if (slotSyncFailed) {');
      expect(warnIdx, greaterThan(-1));
      final popIdx =
          body.indexOf('NavigationHelper.popWithChange(context);', warnIdx);
      expect(popIdx, greaterThan(warnIdx),
          reason: '실패 분기가 성공 분기보다 앞이어야 실패 시 pop되지 않는다');
      expect(body.substring(warnIdx, popIdx).contains('setState(() => _hasChanges = true);'),
          true,
          reason: '실패 시 재저장 가능 상태로 남긴다');
    });
  });

  // ── §10 내부 write helper ──────────────────────────────────────
  group('GETSLOTS-08 내부 write helper는 부분 쓰기를 성공으로 보고하지 않는다', () {
    // [TC2 재작성] 이전 판단("쓰기 대상은 파싱된 슬롯뿐이므로 완전성을 요구하지
    // 않는다")이 정확히 틀린 지점이었다. 파싱하지 못한 문서는 갱신에서 빠지는데
    // 호출부는 성공이라고 말한다 — 그 날짜만 옛 마감·공개 설정을 유지한다.
    // PARTIAL WRITE != SUCCESS.
    test('08-a empty면 조용히 끝내되, 불완전하면 실패한다 (§10)', () {
      for (final sig in [
        'Future<void> updateSlotsDeadlines(',
        'Future<void> updateSlotsPublishSettings(',
      ]) {
        final body = _flat(_codeOf(_bodyOf(_src(_toPath), sig)));
        expect(
            body.contains('final slots = await getSlots(toId, requireComplete: true); '
                'if (slots.isEmpty) return;'),
            true,
            reason: '$sig — TRUE EMPTY는 no-op, 부분 해석은 실패여야 한다');
      }
    });

    test('08-a2 완전성 요구가 no-op 판정보다 앞이다', () {
      for (final sig in [
        'Future<void> updateSlotsDeadlines(',
        'Future<void> updateSlotsPublishSettings(',
      ]) {
        final body = _codeOf(_bodyOf(_src(_toPath), sig));
        final getIdx = body.indexOf('requireComplete: true');
        final emptyIdx = body.indexOf('if (slots.isEmpty) return;');
        expect(getIdx, greaterThan(-1), reason: sig);
        expect(emptyIdx, greaterThan(getIdx),
            reason: '$sig — 실패를 "슬롯 0개"로 읽으면 안 된다');
      }
    });

    test('08-b 조회 실패는 두 helper 모두 호출자에게 전파된다', () {
      for (final sig in [
        'Future<void> updateSlotsDeadlines(',
        'Future<void> updateSlotsPublishSettings(',
      ]) {
        final body = _flat(_codeOf(_bodyOf(_src(_toPath), sig)));
        expect(body.endsWith('rethrow; } }'), true,
            reason: '$sig — 실패가 "슬롯 0개라 아무것도 안 함"과 같아지면 안 된다');
      }
    });
  });

  // ── §11 TRUE EMPTY 회귀 금지 ───────────────────────────────────
  group('GETSLOTS-09 정상 빈 상태는 그대로다', () {
    test('09-a 성공 + 0개는 여전히 빈 목록이다', () {
      final body = _codeOf(
          _bodyOf(_src(_toPath), 'Future<List<SlotModel>> getSlots('));
      // 문서 0개면 map 결과도 0개 — 예외 조건 어디에도 걸리지 않는다
      expect(incomplete(docs: 0, parsed: 0), false);
      expect(body.contains('if (snap.docs.isEmpty) throw'), false);
      expect(body.contains('if (slots.isEmpty) throw'), false);
    });

    test('09-b 지원 화면의 TRUE EMPTY 문구가 살아 있다', () {
      final code = _codeOf(_src(_jobPostingPath));
      expect(code.contains("'현재 선택 가능한 근무 날짜가 없습니다.'"), true);
    });

    test('09-c canonical reader(02D single-snapshot)를 건드리지 않았다 (§14)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_svcPath), 'Future<FlexSlotLoad> loadFlexSlots(')));
      expect('_flexSlotSnapshot(toId)'.allMatches(body).length, 1);
      expect(body.contains('requireComplete'), false,
          reason: '표시용 reader는 파손 문서 하나로 전체를 막지 않는다');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // [TARGETED CORRECTION 2] LEGACY != MALFORMED
  // ═══════════════════════════════════════════════════════════════

  // ── §1, §2, §8 canonical decoding ──────────────────────────────
  group('LEGACY-01 supported legacy와 malformed를 구분한다', () {
    final d = DateTime(2026, 9, 20);

    test('01-a createdAt 없는 슬롯은 정상 파싱된다', () {
      final slot = SlotModel.tryFromMap(_rawSlot(d, SlotShape.legacy), 's1', 'to1');
      expect(slot, isNotNull, reason: '정상 데이터를 파서가 버리면 안 된다');
      expect(slot!.date, d);
      expect(slot.createdAt, isNull, reason: '모르는 값을 지어내지 않는다 (§4)');
    });

    test('01-b createdAt이 슬롯 의미를 바꾸지 않는다', () {
      final withCa = SlotModel.tryFromMap(_rawSlot(d, SlotShape.current), 's', 'to1')!;
      final without = SlotModel.tryFromMap(_rawSlot(d, SlotShape.legacy), 's', 'to1')!;
      expect(without.date, withCa.date);
      expect(without.status, withCa.status);
      expect(without.isEffectivelyClosed, withCa.isEffectivelyClosed);
      expect(without.totalRequired, withCa.totalRequired);
    });

    test('01-c date가 파손된 문서만 파싱 실패다', () {
      expect(SlotModel.tryFromMap(_rawSlot(d, SlotShape.malformed), 's', 'to1'),
          isNull);
    });

    test('01-d 혼합 집합 — 10개 중 legacy 2개 포함해 10개가 나온다 (§10)', () {
      final raws = [
        for (var i = 0; i < 8; i++)
          _rawSlot(d.add(Duration(days: i)), SlotShape.current),
        _rawSlot(d.add(const Duration(days: 8)), SlotShape.legacy),
        _rawSlot(d.add(const Duration(days: 9)), SlotShape.legacy),
      ];
      final parsed = _parse(raws);
      expect(parsed.length, 10);
      expect(incomplete(docs: raws.length, parsed: parsed.length), false,
          reason: 'legacy 2개가 completeness failure로 세어지면 안 된다');
    });

    test('01-e malformed가 섞이면 완전성 실패다 (§9)', () {
      final raws = [
        for (var i = 0; i < 9; i++)
          _rawSlot(d.add(Duration(days: i)), SlotShape.current),
        _rawSlot(d.add(const Duration(days: 9)), SlotShape.malformed),
      ];
      final parsed = _parse(raws);
      expect(parsed.length, 9);
      expect(incomplete(docs: raws.length, parsed: parsed.length), true);
    });
  });

  // ── §10 write sync ─────────────────────────────────────────────
  group('LEGACY-02 write sync가 legacy를 누락하지 않는다', () {
    final d = DateTime(2026, 9, 20);

    test('02-a legacy 포함 10개 전부가 sync 대상이다', () {
      // updateSlotsDeadlines / updateSlotsPublishSettings는 getSlots 결과를
      // 그대로 순회한다 — 파싱된 수가 곧 쓰기 대상 수다.
      final raws = [
        for (var i = 0; i < 8; i++)
          _rawSlot(d.add(Duration(days: i)), SlotShape.current),
        _rawSlot(d.add(const Duration(days: 8)), SlotShape.legacy),
        _rawSlot(d.add(const Duration(days: 9)), SlotShape.legacy),
      ];
      final writeTargets = _parse(raws);
      expect(writeTargets.length, raws.length,
          reason: 'legacy 2개가 옛 마감/공개 설정을 유지한 채 남으면 안 된다');
      expect(
          writeTargets.where((s) => s.createdAt == null).length, 2,
          reason: 'legacy가 실제로 대상에 들어 있다');
    });

    test('02-b legacy만 있는 공고도 slotSyncFailed가 아니다', () {
      final raws = [
        for (var i = 0; i < 3; i++)
          _rawSlot(d.add(Duration(days: i)), SlotShape.legacy),
      ];
      final parsed = _parse(raws);
      expect(incomplete(docs: raws.length, parsed: parsed.length), false);
    });

    test('02-c malformed 포함 시 partial success가 아니다 (§10)', () {
      final raws = [
        for (var i = 0; i < 9; i++)
          _rawSlot(d.add(Duration(days: i)), SlotShape.current),
        _rawSlot(d.add(const Duration(days: 9)), SlotShape.malformed),
      ];
      final parsed = _parse(raws);
      // requireComplete: true → SlotDataException → EditTO catch → slotSyncFailed
      expect(incomplete(docs: raws.length, parsed: parsed.length), true,
          reason: '9개만 갱신하고 "공고가 수정되었습니다"라고 말하면 안 된다');
      final e = SlotDataException('to1', raws.length, parsed.length);
      expect(e.documentCount, 10);
      expect(e.parsedCount, 9);
    });
  });

  // ── §11 destructive count ──────────────────────────────────────
  group('LEGACY-03 legacy 때문에 deletesAll이 뒤집히지 않는다', () {
    final d = DateTime(2026, 9, 20);

    List<SlotModel> tenWithTwoLegacy() => _parse([
          for (var i = 0; i < 8; i++)
            _rawSlot(d.add(Duration(days: i)), SlotShape.current),
          _rawSlot(d.add(const Duration(days: 8)), SlotShape.legacy),
          _rawSlot(d.add(const Duration(days: 9)), SlotShape.legacy),
        ]);

    test('03-a 10개 중 8개 선택 → deletesAll = false', () {
      final all = tenWithTwoLegacy();
      expect(all.length, 10, reason: 'legacy 2개가 빠지면 8 >= 8이 되어 공고가 삭제된다');
      expect(8 >= all.length, false);
    });

    test('03-b 10개 전부 선택 → deletesAll = true', () {
      final all = tenWithTwoLegacy();
      expect(10 >= all.length, true);
    });

    test('03-c malformed가 있으면 개수 판정 자체에 도달하지 않는다 (§9)', () {
      final raws = [
        for (var i = 0; i < 9; i++)
          _rawSlot(d.add(Duration(days: i)), SlotShape.current),
        _rawSlot(d.add(const Duration(days: 9)), SlotShape.malformed),
      ];
      expect(incomplete(docs: raws.length, parsed: _parse(raws).length), true);
      // 배선: 일괄삭제만 requireComplete: true → totalSlotCount == null → return
      final block = _flat(_codeOf(_caseBlock(_src(_cardPath), "case 'batchDelete':")));
      expect(block.contains('requireComplete: true'), true);
      expect(block.indexOf('if (totalSlotCount == null) {'),
          lessThan(block.indexOf('final deletesAll =')));
    });
  });

  // ── §12 JobPostingScreen ───────────────────────────────────────
  group('LEGACY-04 legacy만 있는 공고가 false empty가 되지 않는다', () {
    final d = DateTime(2026, 9, 20);

    test('04-a legacy 슬롯만 있어도 표시할 날짜가 남는다', () {
      final parsed = _parse([
        for (var i = 0; i < 3; i++)
          _rawSlot(d.add(Duration(days: i)), SlotShape.legacy),
      ]);
      expect(parsed.isEmpty, false,
          reason: "빈 목록이면 '현재 선택 가능한 근무 날짜가 없습니다'가 뜬다");
      expect(parsed.length, 3);
    });

    test('04-b 표시 화면은 requireComplete를 쓰지 않는다 (§12)', () {
      final body = _flat(
          _codeOf(_bodyOf(_src(_jobPostingPath), 'Future<void> _loadSlots(')));
      expect(body.contains('requireComplete'), false,
          reason: 'malformed 1개로 정상 날짜까지 못 보게 되면 과교정이다');
      expect(body.contains("getSlots(_to!.id, visibleOnly: false)"), true);
    });

    test('04-c legacy 슬롯도 지원 flow를 막지 않는다', () {
      final slot = SlotModel.tryFromMap(_rawSlot(d, SlotShape.legacy), 's', 'to1')!;
      // 지원 가능 판정은 date/status/workDetails만 본다
      expect(slot.isOpen, true);
      expect(slot.isManualClosed, false);
      expect(slot.visibleFrom, isNull);
    });

    test('04-d SlotBatchSelectDialog / EditTO도 같은 집합을 쓴다 (§7)', () {
      for (final p in [_batchDialogPath, _editToPath]) {
        final code = _codeOf(_src(p));
        expect(code.contains('getSlots('), true, reason: p);
        expect(code.contains('requireComplete'), false, reason: p);
      }
    });
  });
}
