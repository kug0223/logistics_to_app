// [DATE-SCOPE-ENTRY] 기간 합계와 날짜별 현황이 같은 사실을 말하는가.
//
// ── 기기에서 본 것 (DEV `ZujrV62Z2ctTDtdVZy9y`, 2026-10-12~13) ──────────
//   접힌 카드      `충원 1 / 필요 4 · 부족 3 · 대기 0`
//   펼친 날짜 칩    10/12 `1/2` · 10/13 `0/2`          ← 여기까지는 맞다
//   10/12 칩 선택   칩이 `0/2` 로, 머리말이 `충원 0 · 부족 4` 로 바뀌고
//                  업무 행은 `확정 0 · 미충원 1`      ← **확정자가 사라졌다**
//   원장           `slot.workDetailCounts.UBxR73VI78Z6MSkSd04Z.confirmedCount = 1`
//
//   원인은 범위가 아니라 **identity** 다. `loadTOWorkDetails` 는 정의마다
//   `{confirmed:0, pending:0}` 을 깔고(seed) 지원서는 자기 `wdId` 자리에
//   센다. 정의에 wdId 가 없으면 seed 키는 composite 이고 지원서는 문서형
//   wdId 라 둘은 만나지 못하는데, **seed 된 0 이 조회를 성공시켜** 모르는
//   것이 진짜 0 으로 보고됐다.
//
//   둘째 결함은 진입이다. 기간으로 말하는 카드의 `인력 현황` 버튼이 말없이
//   하루(운영 날짜)만 열었다 — 그 날짜에 확정자가 없으면 관리자는 `0` 을
//   보고 돌아선다. 날짜 선택 경로(`날짜별 현황` 칩)는 이미 있었다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/models/ui/group_header_totals.dart';

// ══ fixture ════════════════════════════════════════════════════════════
DateTime _day(int m, int d) => DateTime.utc(2026, m, d);

WorkDetailData _wd({
  required String start,
  required String end,
  int requiredCount = 1,
  String? wdId,
  String workType = 'QA 분류',
}) =>
    WorkDetailData(
      workType: workType,
      startTime: start,
      endTime: end,
      wage: 53000,
      wageType: 'daily',
      requiredCount: requiredCount,
      wdId: wdId,
    );

TOModel _master({int totalRequired = 0, int totalConfirmed = 0}) => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: 'QA 사업장',
      type: 'flex',
      title: 'QA #D261011-C',
      creatorUID: 'uid1',
      status: TOStatus.closed,
      deadlineType: 'HOURS_BEFORE',
      hoursBeforeStart: 2,
      workDetails: const [],
      totalRequired: totalRequired,
      totalConfirmed: totalConfirmed,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime.utc(2026, 10, 1),
      statusUpdatedAt: DateTime.utc(2026, 10, 1),
    );

/// 날짜 슬롯 하나. [counterConfirmed] 는 CF 가 유지하는 원장 카운터다.
TOItem _slot(
  TOModel master,
  DateTime date, {
  required List<WorkDetailData> details,
  int counterConfirmed = 0,
  int counterPending = 0,
}) =>
    TOItem(
      to: master,
      slot: SlotModel(
        id: 'slot_${date.month}_${date.day}',
        toId: master.id,
        date: date,
        status: 'closed',
        workDetails: details,
        createdAt: DateTime.utc(2026, 10, 1),
      ),
      workDetails: details,
      confirmedCount: counterConfirmed,
      pendingCount: counterPending,
      totalRequired: details.fold(0, (a, w) => a + w.requiredCount),
    );

/// 기기에서 본 그 모양 — 정의에는 wdId 가 없고 집계는 문서형 wdId 로 온다.
Map<String, Map<String, int>> _mismatchedStats(
  List<WorkDetailData> details, {
  required String orphanKey,
  int confirmed = 1,
  int pending = 0,
}) =>
    {
      // seed — `loadTOWorkDetails` 가 정의마다 먼저 깐다.
      for (final w in details) w.canonicalId: {'confirmed': 0, 'pending': 0},
      // 지원서가 센 자리 — 어느 정의와도 만나지 못한다.
      orphanKey: {'confirmed': confirmed, 'pending': pending},
    };

/// identity 가 맞는 정상 집계.
Map<String, Map<String, int>> _alignedStats(
  List<WorkDetailData> details,
  List<int> confirmed,
) =>
    {
      for (var i = 0; i < details.length; i++)
        details[i].canonicalId: {'confirmed': confirmed[i], 'pending': 0},
    };

TOGroupItem _group(List<TOItem> slots, TOModel master) {
  final g = TOGroupItem(singleTO: master);
  g.setGroupTOs(slots);
  g.setSlotDates(slots.map((s) => s.slot!.date).toList());
  return g;
}

GroupHeaderTotals _headerOf(TOGroupItem g) => projectGroupHeaderTotals(
      targetTOs: g.groupTOs,
      singleFallback: () => g.groupTOs.first,
    );

// ══ 소스 helper (기존 posting_card_ia_test 와 같은 방식) ═══════════════
const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _itemCardPath = 'lib/widgets/admin/cards/admin_to_item_card.dart';
const _modelPath = 'lib/models/ui/admin_to_list_ui_models.dart';

String _src(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
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
  // 기기에서 본 그 공고: 이틀 × 업무 2개(각 1명), 10/12 에만 확정 1.
  final defs = [
    _wd(start: '09:00', end: '13:00'),
    _wd(start: '14:00', end: '18:00'),
  ];

  group('[DS-A] 집계 identity 가 어긋나도 확정자를 잃지 않는다', () {
    test('DS-1 (사례 2) 첫날만 확정 1 — 날짜 칩이 1/2 를 유지한다', () {
      final m = _master();
      final d12 = _slot(m, _day(10, 12), details: defs, counterConfirmed: 1);
      // 업무 상세 로드 — 기기에서 칩을 누른 그 순간이다.
      d12.setWorkDetails(
        defs,
        _mismatchedStats(defs, orphanKey: 'UBxR73VI78Z6MSkSd04Z'),
      );
      final s = d12.resolveStats();
      expect(s.confirmed, 1,
          reason: '원장은 1 인데 화면이 0 이라고 말하면 이미 찬 자리를 다시 뽑는다');
      expect(s.required, 2);
      expect(s.shortage, 1);
      expect(d12.hasLoadedStats, isFalse,
          reason: '집계를 못 쓰는 상태를 "집계에서 나온 값" 이라고 보고하면 안 된다');
    });

    test('DS-2 (사례 3) 마지막 날만 확정 1 — 같은 판정', () {
      final m = _master();
      final d13 = _slot(m, _day(10, 13), details: defs, counterConfirmed: 1);
      d13.setWorkDetails(
        defs,
        _mismatchedStats(defs, orphanKey: 'e3pkioDqCbfOIxhwpwws'),
      );
      expect(d13.resolveStats().confirmed, 1);
    });

    test('DS-3 identity 가 맞으면 집계를 그대로 쓴다 — 폴백으로 덮지 않는다', () {
      final aligned = [
        _wd(start: '09:00', end: '13:00', wdId: 'wd_a'),
        _wd(start: '14:00', end: '18:00', wdId: 'wd_b'),
      ];
      final m = _master();
      final d = _slot(m, _day(10, 12), details: aligned, counterConfirmed: 99);
      d.setWorkDetails(aligned, _alignedStats(aligned, [0, 1]));
      final s = d.resolveStats();
      expect(d.hasLoadedStats, isTrue);
      expect(s.confirmed, 1, reason: '카운터(99)가 아니라 집계를 써야 한다');
      expect(s.shortage, 1, reason: '업무별로 clamp 한 뒤 더한다');
    });

    test('DS-4 아무도 집지 않은 자리가 **0명** 이면 집계는 여전히 유효하다', () {
      final m = _master();
      final d = _slot(m, _day(10, 12), details: defs, counterConfirmed: 0);
      d.setWorkDetails(
        defs,
        _mismatchedStats(defs, orphanKey: '유령', confirmed: 0, pending: 0),
      );
      expect(d.hasLoadedStats, isTrue,
          reason: '빈 자리는 집계를 무효로 만들지 않는다 — 진짜 0 이다');
      expect(d.resolveStats().confirmed, 0);
    });

    test('DS-4b [OPEN] 집계 전부 0 + 카운터 1 은 **이 Phase 에서 바꾸지 않았다**', () {
      // 기기에서 본 증상의 실제 원인이지만, 여기서 카운터를 믿게 만들면
      //   `group_header_projection` A-2("집계가 0이라고 말하면 머리말도 0")
      //   와 정반대가 된다. 취소 직후 집계 0 / 카운터 1 인 정상 상태에서
      //   유령 확정자를 보이게 하기 때문이다. 현행 동작을 그대로 고정해
      //   두고, 근본 해결(CF projection 에 appliedAt 추가)을 OPEN 으로 둔다.
      final m = _master();
      final d = _slot(m, _day(10, 12), details: defs, counterConfirmed: 1);
      d.setWorkDetails(defs, _alignedStats(defs, [0, 0]));
      expect(d.hasLoadedStats, isTrue);
      expect(d.resolveStats().confirmed, 0,
          reason: 'A-2 계약 유지 — 이 자리를 바꾸려면 정책 결정이 필요하다');
    });

    test('DS-5 (사례 11) 조회 실패는 0 이 아니라 카운터로 말한다', () {
      final m = _master();
      final d = _slot(m, _day(10, 12), details: defs, counterConfirmed: 1);
      d.setWorkDetails(defs, const {}, statsFailed: true);
      expect(d.resolveStats().confirmed, 1);
      expect(d.hasLoadedStats, isFalse);
    });
  });

  group('[DS-B] 기간 합계와 날짜별 값이 같은 사실이다', () {
    test('DS-6 (사례 4) 선택 날짜 0 · 다른 날짜 확정 1 — 합계는 1', () {
      final m = _master();
      final d12 = _slot(m, _day(10, 12), details: defs, counterConfirmed: 1)
        ..setWorkDetails(
            defs, _mismatchedStats(defs, orphanKey: 'UBxR73VI78Z6MSkSd04Z'));
      final d13 = _slot(m, _day(10, 13), details: defs, counterConfirmed: 0)
        ..setWorkDetails(defs,
            _mismatchedStats(defs, orphanKey: '유령', confirmed: 0));
      final g = _group([d12, d13], m);
      final h = _headerOf(g);
      expect(h.confirmed, 1, reason: '기기 카드가 말한 `충원 1` 과 같아야 한다');
      expect(h.required, 4);
      expect(h.shortage, 3);
      // 날짜별 값의 합이 곧 기간 합계다 — 두 표면이 같은 사실을 말한다.
      expect(d12.resolveStats().confirmed + d13.resolveStats().confirmed,
          h.confirmed);
      expect(
          d12.resolveStats().required + d13.resolveStats().required, h.required);
    });

    test('DS-7 (사례 5) 날짜별 필요 인원이 달라도 합계는 날짜 합이다', () {
      final m = _master();
      final a = [_wd(start: '09:00', end: '13:00', requiredCount: 3)];
      final b = [_wd(start: '09:00', end: '13:00', requiredCount: 1)];
      final d12 = _slot(m, _day(10, 12), details: a);
      final d13 = _slot(m, _day(10, 13), details: b);
      final h = _headerOf(_group([d12, d13], m));
      expect(h.required, 4);
      expect(h.requiredKnown, isTrue);
    });

    test('DS-8 (사례 6) FULL 과 부족이 섞여도 과충원이 부족을 상쇄하지 않는다', () {
      final m = _master();
      final full = [_wd(start: '09:00', end: '13:00', wdId: 'f')];
      final short = [_wd(start: '09:00', end: '13:00', wdId: 's', requiredCount: 3)];
      final d12 = _slot(m, _day(10, 12), details: full)
        ..setWorkDetails(full, _alignedStats(full, [5]));
      final d13 = _slot(m, _day(10, 13), details: short)
        ..setWorkDetails(short, _alignedStats(short, [0]));
      final h = _headerOf(_group([d12, d13], m));
      expect(h.shortage, 3, reason: '5-1 의 과충원이 3 의 부족을 지우면 안 된다');
      expect(d12.resolvedIsFull, isTrue);
      expect(d13.resolvedIsFull, isFalse);
      expect(h.isFull, isFalse);
    });

    test('DS-9 (사례 1) 하루짜리 공고는 기간 합계 = 그 날짜', () {
      final m = _master();
      final only = _slot(m, _day(10, 12), details: defs, counterConfirmed: 1)
        ..setWorkDetails(
            defs, _mismatchedStats(defs, orphanKey: 'UBxR73VI78Z6MSkSd04Z'));
      final h = _headerOf(_group([only], m));
      final s = only.resolveStats();
      expect(h.confirmed, s.confirmed);
      expect(h.required, s.required);
      expect(h.shortage, s.shortage);
    });

    test('DS-10 (사례 8) 제목이 같아도 toId 가 다르면 섞이지 않는다', () {
      final m1 = _master();
      final m2 = TOModel(
        id: 'to2',
        businessId: 'biz1',
        businessName: 'QA 사업장',
        type: 'flex',
        title: 'QA #D261011-C', // 같은 제목
        creatorUID: 'uid1',
        status: TOStatus.closed,
        deadlineType: 'HOURS_BEFORE',
        hoursBeforeStart: 2,
        workDetails: const [],
        totalRequired: 0,
        totalConfirmed: 0,
        totalPending: 0,
        isPublished: true,
        publishMode: 'immediate',
        createdAt: DateTime.utc(2026, 10, 1),
        statusUpdatedAt: DateTime.utc(2026, 10, 1),
      );
      final g1 = _group(
          [_slot(m1, _day(10, 12), details: defs, counterConfirmed: 1)], m1);
      final g2 = _group([_slot(m2, _day(10, 12), details: defs)], m2);
      expect(_headerOf(g1).confirmed, 1);
      expect(_headerOf(g2).confirmed, 0, reason: '다른 공고의 확정자를 끌어오면 안 된다');
    });
  });

  group('[DS-C] 진입 — 기간으로 말하는 카드는 하루를 임의로 열지 않는다', () {
    final card = _src(_cardPath);

    test('DS-11 기간 문구가 있으면 명단 target 을 확정하지 않는다', () {
      final body = _codeOf(_bodyOf(card, '_ApplicantTarget? _applicantTarget('));
      expect(
        _flat(body).contains(
            'if (_collapsedDateRangeText(widget.groupItem.masterTO) != null) { return null; }'),
        isTrue,
        reason: '기간 합계 아래 버튼이 말없이 하루만 열면 다른 날짜의 확정자를 못 본다',
      );
    });

    test('DS-12 기존 계약은 그대로 — operationalSlot·CONTRACT 규칙 유지', () {
      final body = _codeOf(_bodyOf(card, '_ApplicantTarget? _applicantTarget('));
      // [posting_card_ia 08-c] 단일 날짜 FLEX 는 여전히 그 날짜로 간다.
      expect(body.contains('widget.groupItem.operationalSlot'), isTrue);
      expect(body.contains('groupTOs.first'), isFalse);
      // [posting_card_ia 08-e] CONTRACT 는 업무가 하나일 때만.
      expect(body.contains('if (details.length != 1) return null;'), isTrue);
    });

    test('DS-13 확정 못 하면 펼침(날짜별 현황)으로 넘긴다', () {
      final bar = _codeOf(_bodyOf(card, 'Widget _buildActionBar('));
      expect(_flat(bar).contains('onTap: target == null ? widget.onToggleExpand'),
          isTrue);
      // 날짜 선택 경로가 실제로 거기 있다.
      final multi = _codeOf(_bodyOf(card, 'Widget _buildMultiSlotLayout('));
      expect(multi.contains("'날짜별 현황'"), isTrue);
      expect(multi.contains('_buildDateChip('), isTrue);
      expect(multi.contains('_buildDayPanel('), isTrue);
    });

    test('DS-14 (사례 9) 카드를 접으면 날짜 선택이 풀린다', () {
      final body = _codeOf(_bodyOf(card, 'void didUpdateWidget('));
      expect(
        _flat(body).contains(
            'if (old.isExpanded && !widget.isExpanded && _selectedChipDate != null)'),
        isTrue,
      );
    });
  });

  group('[DS-D] 행과 요약이 같은 확신도를 쓴다', () {
    test('DS-15 세 행 호출부가 모두 hasLoadedStats 를 읽는다', () {
      final card = _flat(_codeOf(_src(_cardPath)));
      final item = _flat(_codeOf(_src(_itemCardPath)));
      expect(card.contains('!toItem.hasLoadedStats'), isTrue);
      expect(card.contains('!_getSingleTOItem().hasLoadedStats'), isTrue);
      expect(item.contains('!widget.toItem.hasLoadedStats'), isTrue);
    });

    test('DS-16 hasLoadedStats 는 resolveStats 의 분기와 같은 판정이다', () {
      final model = _src(_modelPath);
      expect(model.contains('bool get hasLoadedStats => _aggregateUsable;'),
          isTrue);
      final body = _codeOf(_bodyOf(model, 'bool get _aggregateUsable'));
      expect(body.contains('claimed'), isTrue,
          reason: '아무도 집지 않은 자리를 가려내야 한다');
    });
  });
}
