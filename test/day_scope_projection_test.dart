// [R7-P1-2 DEVICE.1I] 머리말 범위 count 가 **본문과 같은 projection** 인가.
//
//   실기기 캡처: 9/28 과 9/30 모두 머리말이 `공고 8개 · 업무 8개` 인데 본문에는
//   2개만 보였다.
//
//   DEV 실측(`callableGetDayStaffingDetail`, businessId fLmSOHVKUwmBHcbwQE0I):
//
//     날짜        raw rows   distinct toId   isClosed   open
//     2026-09-28     8            8            6         2
//     2026-09-30     8            8            6         2
//
//   `raw 8 == distinct toId 8` 이므로 **decode 누락은 없다** — 8건 전부 파싱됐고
//   6건은 `isClosed` 로 인한 **의도된 제외**다. 그룹 보강 루프가 종료된 단위로는
//   새 그룹을 세우지 않기 때문이다("채울 수 없으므로 보여 줄 이유가 없다").
//
//   DEVICE.1H 의 머리말은 filter **이전** rows 를 셌다. 그것이 불일치의 원인이다.
//   같은 범위를 말하는 제목·머리말·요약·본문은 같은 projection 을 써야 한다.
//
//   날짜를 고정해 baseline drift 를 피한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/ui/day_staffing_row.dart';

DayStaffingRow _row({
  required String toId,
  required String wdId,
  required bool isClosed,
  int required = 5,
  int confirmed = 0,
  String title = '공고',
  bool isLongTerm = false,
}) =>
    DayStaffingRow(
      toId: toId,
      toTitle: title,
      slotId: 'slot_$toId',
      wdId: wdId,
      workType: '사무업무',
      startTime: '09:00',
      endTime: '18:00',
      requiredCount: required,
      confirmedCount: confirmed,
      pendingCount: 0,
      isClosed: isClosed,
      isLongTerm: isLongTerm,
    );

/// DEV 9/28 의 실제 모양: 8 rows / 6 closed / 2 open.
List<DayStaffingRow> _dev0928() => [
      for (var i = 1; i <= 6; i++)
        _row(
            toId: 'closed$i',
            wdId: 'wd_closed$i',
            isClosed: true,
            title: '[R8P2] p3a sameTO-c$i'),
      _row(
          toId: 'short',
          wdId: 'wd_short',
          isClosed: false,
          required: 3,
          confirmed: 1,
          title: '[R7FIX] 부족 남은 공고'),
      _row(
          toId: 'long',
          wdId: 'wd_long',
          isClosed: false,
          required: 2,
          confirmed: 0,
          title: '[R7FIX] 장기 근무 공고',
          isLongTerm: true),
    ];

/// DEV 9/30: 8 rows / 6 closed / 2 open (단기 정원 1).
List<DayStaffingRow> _dev0930() => [
      for (var i = 1; i <= 6; i++)
        _row(toId: 'closed$i', wdId: 'wd_closed$i', isClosed: true),
      _row(
          toId: 'oneday',
          wdId: 'wd_oneday',
          isClosed: false,
          required: 1,
          confirmed: 0,
          title: '[R7FIX] 한 날짜만 마감'),
      _row(
          toId: 'long',
          wdId: 'wd_long',
          isClosed: false,
          required: 2,
          confirmed: 0,
          isLongTerm: true),
    ];

/// 본문이 세우는 그룹 — production 과 같은 술어를 쓴다.
///   (지원서·초대로 선 그룹은 이 경로 밖이다. 아래 SCOPE-C 가 그 경우를 덮는다.)
List<DayStaffingRow> _bodyGroups(List<DayStaffingRow> rows) =>
    rows.where((r) => r.seedsGroup).toList();

String _label(List<DayStaffingRow> rows, String dateLabel,
        {bool unknown = false, Set<String>? extraPostings, int extraUnits = 0}) {
  final groups = _bodyGroups(rows);
  final ids = {...groups.map((g) => g.toId), ...?extraPostings}
    ..removeWhere((e) => e.isEmpty);
  return DayStaffingRow.scopeLabel(
    dateLabel: dateLabel,
    rowsUnknown: unknown,
    postingIds: ids,
    workUnitCount: groups.length + extraUnits,
  );
}

void main() {
  group('SCOPE-A 9/28 — filter 이전 8 vs 이후 2', () {
    final rows = _dev0928();

    test('SCOPE-A1 raw 는 8, 본문 그룹은 2다', () {
      expect(rows.length, 8, reason: 'DEV 실측 raw rows');
      expect(rows.map((r) => r.toId).toSet().length, 8,
          reason: 'distinct toId 8 — decode 누락이 아니다');
      expect(_bodyGroups(rows).length, 2, reason: '6건은 isClosed 로 제외된다');
    });

    test('SCOPE-A2 머리말이 본문과 같은 수를 말한다', () {
      expect(_label(rows, '2026년 9월 28일 월요일'),
          '2026년 9월 28일 월요일 · 공고 2개 · 업무 2개');
    });

    test('SCOPE-A3 raw 를 세면 8개가 된다 — 이것이 1H 의 동작이었다', () {
      // 회귀 대비: 잘못된 계산을 실행으로 남겨 차이를 고정한다.
      final wrong = DayStaffingRow.scopeLabel(
        dateLabel: 'D',
        rowsUnknown: false,
        postingIds: rows.map((r) => r.toId).toSet(),
        workUnitCount: rows.length,
      );
      expect(wrong, 'D · 공고 8개 · 업무 8개');
      expect(_label(rows, 'D'), 'D · 공고 2개 · 업무 2개');
    });

    test('SCOPE-A4 보이는 부족 합이 4다 — 상단 숫자와 같은 모집단', () {
      // 단기 3-1=2, 장기 2-0=2. 종료 단위는 부족이 아니다.
      final shortage = _bodyGroups(rows).fold<int>(
          0,
          (acc, g) => acc +
              (g.requiredCount - g.confirmedCount)
                  .clamp(0, g.requiredCount));
      expect(shortage, 4);
    });
  });

  group('SCOPE-B 9/30', () {
    final rows = _dev0930();

    test('SCOPE-B1 머리말 공고 2개 · 업무 2개', () {
      expect(_label(rows, '2026년 9월 30일 수요일'),
          '2026년 9월 30일 수요일 · 공고 2개 · 업무 2개');
    });

    test('SCOPE-B2 보이는 부족 합이 3이다', () {
      final shortage = _bodyGroups(rows).fold<int>(
          0,
          (acc, g) => acc +
              (g.requiredCount - g.confirmedCount)
                  .clamp(0, g.requiredCount));
      expect(shortage, 3);
    });
  });

  group('SCOPE-C 경계', () {
    test('SCOPE-C1 UNKNOWN 이면 수를 만들지 않는다', () {
      expect(_label(_dev0928(), '9/28', unknown: true), '9/28');
    });

    test('SCOPE-C2 보여 줄 그룹이 없으면 날짜만', () {
      final allClosed = [
        for (var i = 1; i <= 4; i++)
          _row(toId: 'c$i', wdId: 'w$i', isClosed: true),
      ];
      expect(_bodyGroups(allClosed), isEmpty);
      expect(_label(allClosed, '9/28'), '9/28');
    });

    test('SCOPE-C3 종료 단위에 지원이 있으면 본문에 서고 수에도 들어간다', () {
      // 지원·초대로 선 그룹은 종료여도 본문에 남는다(초대가 왜 수락되지
      // 않는지 알아야 한다). 그때 머리말도 그 그룹을 센다.
      final rows = _dev0928();
      final withApp = _label(rows, 'D',
          extraPostings: {'closed1'}, extraUnits: 1);
      expect(withApp, 'D · 공고 3개 · 업무 3개');
    });

    test('SCOPE-C4 `전체` 라는 말을 쓰지 않는다', () {
      expect(_label(_dev0928(), 'D'), isNot(contains('전체')));
    });

    test('SCOPE-C5 seedsGroup 은 isClosed 의 반대다', () {
      expect(_row(toId: 'a', wdId: 'w', isClosed: false).seedsGroup, isTrue);
      expect(_row(toId: 'a', wdId: 'w', isClosed: true).seedsGroup, isFalse);
    });
  });
}
