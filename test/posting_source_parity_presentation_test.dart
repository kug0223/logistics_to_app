// [R7-P1-2 DEVICE.1D] 한 카드가 두 숫자를 말했고, 끝난 공고가 부족을 말했다.
//
//   ── ISSUE A ───────────────────────────────────────────────────
//
//   같은 ACTIVE 공고에서 동시에:
//     요약    충원 1 / 필요 2 · 부족 1
//     업무상세 충원 0 · 대기 0 · 미충원 2 · 0/2
//
//   원인은 "업무 상세가 있는가"를 두 곳이 다르게 판정한 것이다.
//     요약 `resolveStats()`  : TOItem 자기 workDetails 만 본다
//     상세 `_getSingleTOWorkDetails()` : 마스터 TO 까지 폴백한다
//   장기/단건 카드가 만드는 합성 TOItem 은 workDetails 를 받지 않으므로,
//   집계가 손에 있어도 요약은 카운터로 떨어졌다. 카운터가 뒤처지는 모든
//   순간에 두 숫자가 갈라진다.
//
//   ── ISSUE B ───────────────────────────────────────────────────
//
//   현재-좌석 의미를 제대로 적용하면 운영이 끝난 공고는 `충원 0 / 부족 N`
//   이 된다. 산술은 맞지만 "결국 못 구했고 지금도 부족하다" 로 읽힌다.
//   끝난 공고가 묻는 질문은 다르다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/posting_presentation_mode.dart';

String _read(String p) => File(p).readAsStringSync();

String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  expect(i, greaterThan(-1), reason: '구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  expect(j, greaterThan(i), reason: '구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

/// KST 자정 instant — 저장 모양 그대로.
DateTime _d(int y, int m, int day) =>
    DateTime.utc(y, m, day).subtract(const Duration(hours: 9));

// ── resolveStats 복제 (수정 후 규칙) ────────────────────────────
int _clamp(int n) => n > 0 ? n : 0;

({int confirmed, int pending, int required, int shortage}) resolveStats({
  required List<({String id, int required})> itemDetails,
  required List<({String id, int required})> toDetails,
  required Map<String, Map<String, int>>? stats,
  required bool statsFailed,
  required int counterConfirmed,
  required int counterPending,
  required int counterRequired,
}) {
  if (statsFailed) {
    return (
      confirmed: counterConfirmed,
      pending: counterPending,
      required: counterRequired,
      shortage: _clamp(counterRequired - counterConfirmed),
    );
  }
  final details = itemDetails.isNotEmpty ? itemDetails : toDetails;
  if (stats != null && details.isNotEmpty) {
    var c = 0, p = 0, r = 0, s = 0;
    for (final w in details) {
      final st = stats[w.id];
      final wc = st?['confirmed'] ?? 0;
      c += wc;
      p += st?['pending'] ?? 0;
      r += w.required;
      s += _clamp(w.required - wc);
    }
    return (confirmed: c, pending: p, required: r, shortage: s);
  }
  return (
    confirmed: counterConfirmed,
    pending: counterPending,
    required: counterRequired,
    shortage: _clamp(counterRequired - counterConfirmed),
  );
}

void main() {
  late String models, card, detail;

  setUpAll(() {
    models = _codeOf(_read('lib/models/ui/admin_to_list_ui_models.dart'));
    card = _codeOf(_read('lib/widgets/admin/cards/admin_to_group_card.dart'));
    detail = _codeOf(_read('lib/widgets/admin/cards/admin_work_detail.dart'));
  });

  // ══════════════════════════════════════════════════════════════
  // A~F. source parity (§29)
  // ══════════════════════════════════════════════════════════════

  group('PSP-A source parity', () {
    const wd = [(id: '사무업무_06:00_08:00', required: 2)];

    test('PSP-A 합성 TOItem(workDetails 없음)도 집계를 쓴다', () {
      final s = resolveStats(
        itemDetails: const [], // ← 합성 TOItem
        toDetails: wd,
        stats: {'사무업무_06:00_08:00': {'confirmed': 0, 'pending': 0}},
        statsFailed: false,
        counterConfirmed: 1, counterPending: 0, counterRequired: 2,
      );
      expect(s.confirmed, 0, reason: '카운터 1이 아니라 집계 0');
      expect(s.shortage, 2);
    });

    test('PSP-B stale 카운터보다 로드된 집계가 우선한다', () {
      // 실기기에서 본 그 상태: 카운터 1, 집계 0.
      final s = resolveStats(
        itemDetails: const [], toDetails: wd,
        stats: {'사무업무_06:00_08:00': {'confirmed': 0, 'pending': 0}},
        statsFailed: false,
        counterConfirmed: 1, counterPending: 0, counterRequired: 2,
      );
      // 요약·상세가 같은 함수에서 나오므로 같은 수다.
      final detailConfirmed =
          {'사무업무_06:00_08:00': {'confirmed': 0}}['사무업무_06:00_08:00']!['confirmed']!;
      expect(s.confirmed, detailConfirmed);
    });

    test('PSP-C 집계가 없으면 0이라고 말하지 않는다', () {
      final s = resolveStats(
        itemDetails: const [], toDetails: wd,
        stats: null, statsFailed: false,
        counterConfirmed: 1, counterPending: 0, counterRequired: 2,
      );
      expect(s.confirmed, 1, reason: 'null 을 0 으로 바꾸지 않는다 — 카운터 폴백');
      // 그리고 화면은 그 상태를 `모름` 으로 그린다.
      expect(models, contains('bool get hasLoadedStats'));
      expect(card, contains('stats == null'));
    });

    test('PSP-D 성공한 0 은 진짜 0 이다', () {
      final s = resolveStats(
        itemDetails: const [], toDetails: wd,
        stats: {'사무업무_06:00_08:00': {'confirmed': 0, 'pending': 0}},
        statsFailed: false,
        counterConfirmed: 9, counterPending: 9, counterRequired: 2,
      );
      expect(s.confirmed, 0);
      expect(s.pending, 0);
    });

    test('PSP-E FLEX 경로 회귀 없음 — 자기 workDetails 가 있으면 그것을 쓴다', () {
      const slotWd = [(id: '홀서빙_09:00_18:00', required: 3)];
      final s = resolveStats(
        itemDetails: slotWd, // 슬롯이 자기 업무를 갖고 있다
        toDetails: const [(id: '사무업무_06:00_08:00', required: 2)],
        stats: {'홀서빙_09:00_18:00': {'confirmed': 2, 'pending': 1}},
        statsFailed: false,
        counterConfirmed: 0, counterPending: 0, counterRequired: 0,
      );
      expect(s.confirmed, 2);
      expect(s.required, 3, reason: '마스터 TO 가 아니라 슬롯 업무를 쓴다');
    });

    test('PSP-F 여러 업무 — 합산과 clamp 그대로', () {
      const wds = [
        (id: 'a', required: 2),
        (id: 'b', required: 1),
      ];
      final s = resolveStats(
        itemDetails: const [], toDetails: wds,
        stats: {'a': {'confirmed': 0, 'pending': 0}, 'b': {'confirmed': 3, 'pending': 0}},
        statsFailed: false,
        counterConfirmed: 0, counterPending: 0, counterRequired: 0,
      );
      expect(s.confirmed, 3);
      expect(s.shortage, 2, reason: 'b 초과확정이 a 부족을 상쇄하지 않는다');
    });

    test('PSP-A2 조회 실패는 여전히 카운터 폴백이다', () {
      final s = resolveStats(
        itemDetails: const [], toDetails: wd,
        stats: {'사무업무_06:00_08:00': {'confirmed': 0, 'pending': 0}},
        statsFailed: true,
        counterConfirmed: 1, counterPending: 0, counterRequired: 2,
      );
      expect(s.confirmed, 1);
    });

    test('PSP-A3 실제 코드가 같은 폴백을 쓴다', () {
      final fn = _slice(models, 'resolveStats() {', 'bool get hasLoadedStats');
      // [R7 STAFFING AUDIT] 폴백이 `statsAlignedWorkDetails` 라는 이름을 얻었다.
      //
      //   DEVICE.1D 의 계약("요약과 상세가 같은 정의 목록을 본다")은 그대로다.
      //   달라진 것은 **slot 이 있을 때 master 로 폴백하지 않는다**는 점이다 —
      //   FLEX 는 slot 과 master 의 wdId 가 서로 다른 값이어서, master 로
      //   갈아타면 집계와 만나지 못하고 `충원 1` 이 `0` 이 됐다.
      //   두 소비자(`resolveStats`·`hasLoadedStats`)가 여전히 같은 것을 쓴다.
      expect(fn, contains('statsAlignedWorkDetails'));
      final aligned =
          _slice(models, 'get statsAlignedWorkDetails {', 'bool get resolvedIsFull');
      expect(aligned, contains('if (slot != null) return const [];'));
      expect(aligned, contains('return to.workDetails;'),
          reason: 'slot 이 없는 장기는 master 가 유일한 원천이다 (DEVICE.1D 유지)');
      // [2차] 집계 사용 판정이 `_aggregateUsable` 한 곳으로 모였다 —
      //   `resolveStats` 와 `hasLoadedStats` 가 같은 것을 써야 한다.
      expect(fn, contains('if (_aggregateUsable)'));
      final usable = _slice(models, 'bool get _aggregateUsable {', 'bool get resolvedIsFull');
      expect(usable, contains('if (details.isEmpty) return false;'));
      expect(usable, contains('lookupByIdentity(stats) == null'),
          reason: 'identity miss 를 집계 사용 조건에 포함한다');
      expect(fn, isNot(contains('isWorkDetailLoaded && workDetails.isNotEmpty')),
          reason: '옛 판정이 남아 있으면 다시 갈라진다');
    });

    test('PSP-A4 카드 요약이 같은 resolver 를 거친다', () {
      final cache = _slice(card, 'if (_targetTOs.isEmpty) {', '} else {');
      expect(cache, contains('single.resolveStats()'));
      expect(cache, isNot(contains('g.totalConfirmed')),
          reason: '카운터를 직접 읽으면 상세와 갈라진다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // G~M. presentation mode (§30)
  // ══════════════════════════════════════════════════════════════

  group('PSP-G presentation mode', () {
    final today = _d(2026, 9, 27);

    test('PSP-G 운영기간 미래 + 모집중 → ACTIVE', () {
      expect(
          resolvePostingPresentationMode(
              operationEnd: _d(2026, 10, 23),
              recruitmentClosed: false,
              now: today),
          PostingPresentationMode.active);
    });

    test('PSP-H 운영기간 미래 + FULL → ACTIVE (FULL 은 종료가 아니다)', () {
      // FULL 은 모집 lifecycle 이 닫힌 것이 아니다 — isClosed=false 로 온다.
      expect(
          resolvePostingPresentationMode(
              operationEnd: _d(2026, 10, 23),
              recruitmentClosed: false,
              now: today),
          PostingPresentationMode.active);
    });

    test('PSP-I 모집 마감 + 운영 잔존 → CLOSED_ACTIVE', () {
      final m = resolvePostingPresentationMode(
          operationEnd: _d(2026, 10, 23),
          recruitmentClosed: true,
          now: today);
      expect(m, PostingPresentationMode.closedActive);
      expect(m.showsCurrentStaffing, isTrue,
          reason: '근무가 남아 있으면 운영 수치는 계속 필요하다');
    });

    test('PSP-J 운영기간 경과 + 마감 → PAST_ENDED', () {
      expect(
          resolvePostingPresentationMode(
              operationEnd: _d(2026, 9, 22),
              recruitmentClosed: true,
              now: today),
          PostingPresentationMode.pastEnded);
    });

    test('PSP-K 운영기간 경과 + status 가 아직 ACTIVE 여도 terminal', () {
      // stale status 로 과거 공고를 운영 중처럼 말하지 않는다.
      expect(
          resolvePostingPresentationMode(
              operationEnd: _d(2026, 9, 22),
              recruitmentClosed: false,
              now: today),
          PostingPresentationMode.pastEnded);
    });

    test('PSP-K2 마지막 근무일 당일은 아직 운영 중', () {
      expect(
          resolvePostingPresentationMode(
              operationEnd: _d(2026, 9, 27),
              recruitmentClosed: false,
              now: today),
          PostingPresentationMode.active);
    });

    test('PSP-K3 운영 종료일을 모르면 끝났다고 단정하지 않는다', () {
      expect(
          resolvePostingPresentationMode(
              operationEnd: null, recruitmentClosed: false, now: today),
          PostingPresentationMode.active);
      expect(
          resolvePostingPresentationMode(
              operationEnd: null, recruitmentClosed: true, now: today),
          PostingPresentationMode.closedActive);
    });

    test('PSP-L 근로자 한 명의 종료로 공고를 끝내지 않는다', () {
      // 실기기 fixture: 근로자 end 9/22, 공고 rangeEnd 10/23, today 9/27
      final m = resolvePostingPresentationMode(
          operationEnd: _d(2026, 10, 23),
          recruitmentClosed: false,
          now: today);
      expect(m, PostingPresentationMode.active);
      // resolver 가 근로자 필드를 아예 받지 않는다.
      final src = _codeOf(_read('lib/utils/posting_presentation_mode.dart'));
      for (final banned in ['workEndDate', 'actualResignDate', 'application']) {
        expect(src, isNot(contains(banned)), reason: '근로자 축이 섞였다: $banned');
      }
    });

    test('PSP-M 기기 timezone 과 무관하다', () {
      final end = _d(2026, 9, 27); // KST 9/27
      // 같은 instant 를 UTC/local 어느 표현으로 줘도 같은 판정.
      for (final v in [end, end.toUtc(), end.toLocal()]) {
        expect(
            resolvePostingPresentationMode(
                operationEnd: v, recruitmentClosed: false, now: today),
            PostingPresentationMode.active);
      }
      final src = _codeOf(_read('lib/utils/posting_presentation_mode.dart'));
      expect(src, contains('FormatHelper.toKstDate'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // N~S. PAST 표현 (§31)
  // ══════════════════════════════════════════════════════════════

  group('PSP-N PAST 표현', () {
    test('PSP-N 운영 종료 문구', () {
      expect(card, contains("Text('운영 종료'"));
      expect(detail, contains("Text('운영 종료'"));
    });

    test('PSP-O 요약에서 현재 부족을 말하지 않는다', () {
      expect(card, contains('_presentationMode.showsCurrentStaffing'));
      final branch = _slice(card, 'if (_presentationMode.showsCurrentStaffing)',
          '_buildLongTermMeta(');
      expect(branch, contains('_buildStaffingLine('));
      expect(branch, contains('_buildOperationEndedLine(context)'));
    });

    test('PSP-P 업무 상세에서 미충원·N/M 을 말하지 않는다', () {
      expect(detail, contains('if (!widget.mode.showsCurrentStaffing)'));
      expect(detail, contains('_buildOperationEndedRow(context)'));
      // 순서: lifecycle → data state. ERROR 를 종료처럼 보여주지 않는다.
      final branch = _slice(detail, 'if (!widget.mode.showsCurrentStaffing)',
          '_buildPersonnelStatus(');
      expect(branch.indexOf('_buildOperationEndedRow'),
          lessThan(branch.indexOf('_buildStatsErrorRow')));
    });

    test('PSP-Q 이력 진입을 지우지 않았다', () {
      expect(card, contains('인력 현황'));
    });

    test('PSP-R 원래 필요 인원 데이터는 그대로다', () {
      // 표현에서 내릴 뿐 값을 지우지 않는다.
      expect(card, contains('required: totalRequired'));
      expect(detail, contains('widget.work.requiredCount'));
    });

    test('PSP-S 삭제가 없다', () {
      final src = _codeOf(_read('lib/utils/posting_presentation_mode.dart'));
      for (final banned in ['delete', 'remove']) {
        expect(src, isNot(contains(banned)));
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §24. mode 와 data state 를 합치지 않는다
  // ══════════════════════════════════════════════════════════════

  group('PSP-X 축 분리', () {
    test('PSP-X1 mode 는 데이터 상태를 모른다', () {
      final src = _codeOf(_read('lib/utils/posting_presentation_mode.dart'));
      for (final banned in ['stats', 'loading', 'error', 'permission']) {
        expect(src.toLowerCase(), isNot(contains(banned)),
            reason: 'lifecycle 에 데이터 상태가 섞였다: $banned');
      }
    });

    test('PSP-X2 ACTIVE + UNKNOWN 이 가능하다', () {
      // 두 조건이 독립 분기라 조합이 살아 있다.
      expect(detail, contains('else if (widget.statsFailed)'));
    });

    test('PSP-X3 resolver 가 하나뿐이다 — 화면마다 복제 없음', () {
      expect('resolvePostingPresentationMode('.allMatches(card).length, 1,
          reason: '카드가 한 번만 판정하고 상세에 넘긴다');
      expect(detail, isNot(contains('resolvePostingPresentationMode(')),
          reason: '상세는 다시 계산하지 않는다');
      expect(detail, contains('final PostingPresentationMode mode;'));
    });
  });
}
