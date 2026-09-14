// [POSTING-V2-03M.1] 해석하지 못한 슬롯을 조용히 지우지 않는다
//
// 03M READ에서 확인된 것:
//   · getSlots는 파싱 실패 문서를 whereType으로 조용히 버렸다.
//   · 다이얼로그는 그 결과만 보여줘, 관리자는 그것이 전부라고 믿었다.
//   · 서버는 slotId만 알면 지울 수 있는데 UI가 id를 넘길 방법이 없어,
//     malformed 슬롯이 하나라도 있는 FLEX DRAFT는 앱에서 정리 불가였다.
//   · assertNoSlotRelations의 계약 검사는 슬롯 date로 대조하므로,
//     date를 읽을 수 없는 슬롯이 조용히 빠져 fail-open이었다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';
const _dialogPath =
    'lib/screens/business_admin/dialogs/slot_batch_select_dialog.dart';
const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _toFsPath = 'lib/services/firestore/to_firestore.dart';
const _svcPath = 'lib/services/firestore_service.dart';

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

String _caseBlock(String source, String head) {
  final start = source.indexOf(head);
  if (start == -1) throw StateError('$head 를 찾지 못함');
  final end = source.indexOf('\n        break;', start);
  return source.substring(start, end == -1 ? source.length : end);
}

// ═══════════════════════════════════════════════════════════════
// getSlotCandidates 분류 replica
// ═══════════════════════════════════════════════════════════════

enum DocShape { valid, supportedLegacy, missingDate, badWorkDetails }

/// SlotModel.tryFromMap의 성공/실패 조건 replica.
///   · date 없음/타입오류 → 파싱 실패 (canonical malformed)
///   · createdAt 없음      → 정상 (03D.1 — LEGACY != MALFORMED)
bool _parses(DocShape s) =>
    s == DocShape.valid || s == DocShape.supportedLegacy;

class SlotLoad {
  final List<String> validIds;
  final List<String> malformedIds;
  const SlotLoad(this.validIds, this.malformedIds);
  int get documentCount => validIds.length + malformedIds.length;
}

/// 한 pass 분류 — 문서를 두 번 파싱하지 않는다.
SlotLoad classify(Map<String, DocShape> docs) {
  final valid = <String>[];
  final malformed = <String>[];
  docs.forEach((id, shape) {
    if (_parses(shape)) {
      valid.add(id);
    } else {
      malformed.add(id);
    }
  });
  return SlotLoad(valid, malformed);
}

// ═══════════════════════════════════════════════════════════════
// assertNoSlotRelations 계약 대조 replica
// ═══════════════════════════════════════════════════════════════

class SlotRel {
  final String id;
  /// null이면 date를 읽을 수 없는 문서(malformed).
  final String? dateKey;
  const SlotRel(this.id, this.dateKey);
}

/// 선택 슬롯 삭제가 관계로 막히는가.
/// [contractDates]는 이 공고의 employment_contracts.workDate 집합.
bool slotRelationBlocked({
  required List<SlotRel> selected,
  required Set<String> applicationSlotIds,
  required List<String> contractDates,
}) {
  // 1. 지원서 — slotId로 정확히 본다. date와 무관하게 완전하다.
  if (selected.any((s) => applicationSlotIds.contains(s.id))) return true;
  // 2. 계약 — slotId가 없어 날짜로 잇는다.
  if (contractDates.isEmpty) return false;
  // [POSTING-V2-03M.1] 날짜를 읽을 수 없는 슬롯은 어떤 계약과도 대조할 수
  //   없다. 계약이 하나라도 있으면 보수적으로 막는다.
  if (selected.any((s) => s.dateKey == null)) return true;
  final targets = selected.map((s) => s.dateKey!).toSet();
  return contractDates.any(targets.contains);
}

void main() {
  late final String fns = _src(_fnsPath);
  late final String dialog = _src(_dialogPath);
  late final String cardDelete =
      _flat(_codeOf(_caseBlock(_src(_cardPath), "case 'batchDelete':")));

  // ── §20 parser / result ───────────────────────────────────────
  group('MALFORMED-01 분류', () {
    test('01-a 전부 정상이면 malformed 0', () {
      final r = classify({
        's1': DocShape.valid,
        's2': DocShape.valid,
      });
      expect(r.validIds.length, 2);
      expect(r.malformedIds, isEmpty);
    });

    test('01-b supported legacy는 정상 후보다 (03D.1)', () {
      final r = classify({
        's1': DocShape.valid,
        's2': DocShape.supportedLegacy, // createdAt 없음
      });
      expect(r.validIds.length, 2);
      expect(r.malformedIds, isEmpty,
          reason: 'LEGACY != MALFORMED — 레거시를 오류로 표시하면 안 된다');
    });

    test('01-c date 없음은 malformed 후보다', () {
      final r = classify({
        's1': DocShape.valid,
        's2': DocShape.missingDate,
      });
      expect(r.validIds, ['s1']);
      expect(r.malformedIds, ['s2']);
    });

    test('01-d workDetails 파싱 실패도 malformed 후보다', () {
      final r = classify({'s1': DocShape.badWorkDetails});
      expect(r.malformedIds, ['s1']);
    });

    test('01-e 혼합 — canonical == valid + malformed (§6)', () {
      final r = classify({
        's1': DocShape.valid,
        's2': DocShape.supportedLegacy,
        's3': DocShape.missingDate,
        's4': DocShape.valid,
      });
      expect(r.documentCount, 4, reason: '조용히 사라지는 문서가 없다');
      expect(r.validIds.length, 3);
      expect(r.malformedIds.length, 1);
    });
  });

  // ── §1, §2 service 배선 ───────────────────────────────────────
  group('MALFORMED-02 같은 조회 하나에서 나눈다', () {
    test('02-a getSlotCandidates가 한 pass로 가른다 (§17)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_toFsPath), 'Future<SlotLoadResult> getSlotCandidates(')));
      expect(body.contains('for (final d in snap.docs) {'), true);
      expect(
          body.contains('final parsed = SlotModel.tryFromMap(d.data(), d.id, toId); '
              'if (parsed == null) { malformedIds.add(d.id); } '
              'else { slots.add(parsed); }'),
          true,
          reason: '같은 문서를 두 번 파싱하지 않는다');
      expect('.get(const GetOptions(source: Source.server))'.allMatches(body).length,
          1, reason: '추가 조회 금지 (§2)');
    });

    test('02-b getSlots가 같은 조회를 재사용한다 — 중복 쿼리 없음 (§1, §2)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_toFsPath), 'Future<List<SlotModel>> getSlots(')));
      expect(body.contains('await getSlotCandidates(toId)'), true);
      expect(body.contains('collection(\'slots\')'), false,
          reason: '쿼리가 두 벌이 되면 계약이 갈라진다');
    });

    test('02-c requireComplete 계약이 그대로다 (03D.1)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_toFsPath), 'Future<List<SlotModel>> getSlots(')));
      expect(
          body.contains('if (requireComplete && result.malformedIds.isNotEmpty) { '
              'throw SlotDataException( toId, result.documentCount, result.slots.length); }'),
          true);
      // 완전성 판정이 visibleOnly 필터보다 앞이다
      expect(body.indexOf('requireComplete'),
          lessThan(body.indexOf('if (!visibleOnly)')));
    });

    test('02-d overflow / query error 계약 유지 (§16)', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_toFsPath), 'Future<SlotLoadResult> getSlotCandidates(')));
      expect(
          body.contains('if (snap.docs.length > kMaxFlexSlotsPerTO) { '
              'throw FlexSlotOverflowException(toId, kMaxFlexSlotsPerTO); }'),
          true);
      expect(body.contains('} on FlexSlotOverflowException { rethrow; }'), true);
      expect(body.contains('rethrow;'), true,
          reason: 'QUERY FAILURE != MALFORMED DOCUMENT');
    });

    test('02-e 결과 타입이 문서 id만 남긴다 (§3)', () {
      final code = _codeOf(_src(_svcPath));
      expect(code.contains('class SlotLoadResult {'), true);
      expect(code.contains('final List<String> malformedIds;'), true);
      expect(code.contains('int get documentCount => slots.length + malformedIds.length;'),
          true);
      // 날짜를 임의 값으로 복원하지 않는다
      final body = _bodyOf(_src(_toFsPath), 'Future<SlotLoadResult> getSlotCandidates(');
      expect(body.contains('DateTime.now()'), false);
      expect(body.contains('DateTime(1970'), false);
    });
  });

  // ── §21 UI ────────────────────────────────────────────────────
  group('MALFORMED-03 다이얼로그', () {
    test('03-a silent omission이 없다 — 복구 행을 그린다 (§5, §6)', () {
      final code = _codeOf(dialog);
      expect(code.contains('Widget _buildMalformedTile(String slotId, int ordinal)'),
          true);
      expect(code.contains("'날짜 확인 불가 \$ordinal'"), true);
      expect(code.contains("'데이터 오류로 날짜를 표시할 수 없습니다.'"), true);
    });

    test('03-b 문서 id를 화면에 노출하지 않는다 (§5)', () {
      final body = _flat(_codeOf(_bodyOf(dialog,
          'Widget _buildMalformedTile(String slotId, int ordinal)')));
      // slotId는 선택 상태에만 쓰고 Text로 그리지 않는다
      expect(body.contains('Text( slotId'), false);
      expect(body.contains("Text('\$slotId"), false);
      expect(body.contains('_selectedIds.contains(slotId)'), true);
    });

    test('03-c 삭제 경로에서만 선택 가능하다 (§7, §12)', () {
      final code = _flat(_codeOf(dialog));
      expect(code.contains('final bool includeMalformed;'), true);
      expect(
          code.contains('if (widget.includeMalformed) ...List.generate( '
              '_malformedIds.length, '
              '(i) => _buildMalformedTile(_malformedIds[i], i + 1), )'),
          true);
      // 다른 경로에서도 존재는 알린다
      expect(
          code.contains('else if (_malformedIds.isNotEmpty) _buildMalformedNotice(),'),
          true);
      expect(code.contains('Widget _buildMalformedNotice()'), true);
    });

    test('03-d 전체 선택이 복구 항목을 포함한다 (§12)', () {
      final code = _flat(_codeOf(dialog));
      expect(
          code.contains('List<String> get _selectableIds => [ '
              '..._slots.map((s) => s.id), '
              'if (widget.includeMalformed) ..._malformedIds, ];'),
          true);
      expect(code.contains('_selectedIds.addAll(_selectableIds);'), true);
      expect(code.contains("'전체 선택 (\${_selectableIds.length}개)'"), true);
    });

    test('03-e 선택 결과가 정상/복구를 나눠 돌려준다 (§12)', () {
      final code = _flat(_codeOf(dialog));
      expect(code.contains('class SlotBatchSelection {'), true);
      expect(
          code.contains('List<String> get slotIds => '
              '[...slots.map((s) => s.id), ...malformedSlotIds];'),
          true);
      expect(
          code.contains('malformedSlotIds: _malformedIds '
              '.where(_selectedIds.contains) .toList(),'),
          true);
    });

    test('03-f query error는 복구 행이 아니라 error다 (§16)', () {
      final body = _flat(_codeOf(_bodyOf(dialog, 'Widget _buildContent(')));
      final errorIdx = body.indexOf('if (_loadError) {');
      final emptyIdx = body.indexOf('if (_slots.isEmpty && _malformedIds.isEmpty)');
      expect(errorIdx, greaterThan(-1));
      expect(emptyIdx, greaterThan(errorIdx), reason: '실패 분기가 빈 목록보다 앞이다');
      // 실패했을 때는 복구 행도 만들지 않는다
      final load = _flat(_codeOf(_bodyOf(dialog, 'Future<void> _loadSlots(')));
      expect(load.contains('_malformedIds = const []; _isLoading = false; _loadError = true;'),
          true);
    });

    test('03-g malformed만 있어도 빈 목록으로 보이지 않는다 (§6)', () {
      final body = _flat(_codeOf(_bodyOf(dialog, 'Widget _buildContent(')));
      expect(body.contains('if (_slots.isEmpty && _malformedIds.isEmpty) {'), true,
          reason: 'malformed 1개뿐인 공고가 "등록된 날짜가 없습니다"로 보이면 안 된다');
    });
  });

  // ── §13 확인 문구 ─────────────────────────────────────────────
  group('MALFORMED-04 확인/결과 문구', () {
    test('04-a 복구 항목이 섞이면 항목으로 부른다 (§13)', () {
      expect(
          cardDelete.contains("subtitle: hasMalformedSelected "
              "? '선택한 \${deleteSlotIds.length}개 항목을 삭제하시겠습니까?' "
              ": '선택한 \${deleteSlotIds.length}개 날짜를 삭제하시겠습니까?',"),
          true);
      expect(
          cardDelete.contains("'날짜 정보를 확인할 수 없는 항목이 포함되어 있습니다.\\n'"),
          true);
    });

    test('04-b 03L.1 조건부 문구 유지 (§14)', () {
      expect(cardDelete.contains("'삭제 후 남은 날짜가 없으면 미공개 공고도 함께 삭제됩니다.',"),
          true);
      expect(cardDelete.contains('deletesAll'), false);
    });

    test('04-c 성공 문구도 항목/날짜를 구분한다 (§18)', () {
      expect(
          cardDelete.contains("ToastHelper.showSuccess(hasMalformedSelected "
              "? '\$deleted개 항목이 삭제되었습니다' "
              ": '\$deleted개 날짜가 삭제되었습니다');"),
          true);
      // 03L.1 result contract 그대로
      expect(cardDelete.contains("result['postingDeleted'] == true"), true);
      expect(cardDelete.contains("ToastHelper.showSuccess('공고가 삭제되었습니다')"), true);
    });

    test('04-d 기존 callable을 그대로 쓴다 (§7)', () {
      expect(cardDelete.contains('batchDeleteSlots( toId: masterTO.id, '
          'businessId: masterTO.businessId, slotIds: deleteSlotIds, );'), true);
      expect(cardDelete.contains('deleteTO('), false);
      final all = _codeOf(_src(_toFsPath));
      expect(all.contains('callableDeleteSlots'), true);
      expect(all.contains('callableCleanup'), false,
          reason: '새 cleanup endpoint를 만들지 않는다');
    });
  });

  // ── §8, §10, §22 server relation safety ──────────────────────
  group('MALFORMED-05 관계 검사에 fail-open이 없다', () {
    const slotA = SlotRel('A', '2026-09-15');
    const slotBad = SlotRel('X', null);

    test('05-a 지원서는 slotId로 보므로 date와 무관하다 (§9)', () {
      expect(
          slotRelationBlocked(
            selected: [slotBad],
            applicationSlotIds: {'X'},
            contractDates: const [],
          ),
          true);
    });

    test('05-b 계약이 없으면 malformed도 지울 수 있다', () {
      expect(
          slotRelationBlocked(
            selected: [slotBad],
            applicationSlotIds: const {},
            contractDates: const [],
          ),
          false,
          reason: '막을 근거가 없는데 막으면 복구 경로가 사라진다');
    });

    test('05-c 계약이 있으면 malformed는 보수적으로 막힌다 (§10)', () {
      expect(
          slotRelationBlocked(
            selected: [slotBad],
            applicationSlotIds: const {},
            contractDates: const ['2026-01-01'], // 날짜가 달라 보여도
          ),
          true,
          reason: '대조할 수 없으면 배제할 근거도 없다');
    });

    test('05-d 정상 슬롯은 날짜로 정확히 가른다 — 과잉 차단 없음', () {
      expect(
          slotRelationBlocked(
            selected: [slotA],
            applicationSlotIds: const {},
            contractDates: const ['2026-01-01'],
          ),
          false);
      expect(
          slotRelationBlocked(
            selected: [slotA],
            applicationSlotIds: const {},
            contractDates: const ['2026-09-15'],
          ),
          true);
    });

    test('05-e 정상+malformed 혼합 선택도 보수적이다', () {
      expect(
          slotRelationBlocked(
            selected: [slotA, slotBad],
            applicationSlotIds: const {},
            contractDates: const ['2026-01-01'],
          ),
          true);
    });

    // ── 서버 배선 ──
    test('05-f 서버가 undated target을 fail-closed로 처리한다 (§8, §10)', () {
      final body = _flat(_codeOf(
          _bodyOf(fns, 'async function assertNoSlotRelations(')));
      expect(body.contains('let hasUndatedTarget = false;'), true);
      expect(
          body.contains('if (d?.toMillis) targetDates.add(kstDateKey(d)); '
              'else hasUndatedTarget = true;'),
          true);
      expect(
          body.contains('if (hasUndatedTarget) { '
              'return {blocked: true, reason: "CONTRACT_EXISTS"}; }'),
          true);
      // 계약이 없으면 이 분기에 오지 않는다
      expect(body.indexOf('if (!contractSnap.empty) {'),
          lessThan(body.indexOf('let hasUndatedTarget = false;')));
    });

    test('05-g 지원서 검사는 그대로 slotId 기반이다 (§9)', () {
      final body = _flat(_codeOf(
          _bodyOf(fns, 'async function assertNoSlotRelations(')));
      expect(body.contains('.where("slotId", "==", slotId) .limit(1)'), true);
      expect(body.contains('return {blocked: true, reason: "APPLICATION_EXISTS"};'),
          true);
    });

    test('05-h DRAFT라는 이유로 guard를 건너뛰지 않는다 (§11)', () {
      final body = _codeOf(_bodyOf(fns, 'async function assertNoSlotRelations('));
      expect(body.contains('DRAFT'), false);
      expect(body.contains('isDraft'), false);
    });

    test('05-i 03L.1 lifecycle 무회귀 (§14)', () {
      expect(
          fns.contains('allSlotSnap.docs.filter((d) => !uniqueSlotIdSet.has(d.id)).length'),
          true);
      expect(fns.contains('if (postingRelation.blocked) {'), true);
      expect(fns.contains('postingDeleteBlockedReason'), false);
    });
  });
}
