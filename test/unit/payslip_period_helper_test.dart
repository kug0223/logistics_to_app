// test/unit/payslip_period_helper_test.dart
//
// weeksOfMonth() — 이체현황(_calcWeekRanges)과 동일한 월요일 기준인지 검증

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/screens/payroll/payslip_period_helper.dart';

void main() {
  group('PayslipPeriodHelper.weeksOfMonth — 월요일 기준 주차 분리', () {
    // ─── 2026년 7월 ─────────────────────────────────────────────────
    // 7/1 = 수요일 → 첫 번째 월요일: 7/6
    // 1주차: 7/6~7/12, 2주차: 7/13~7/19, 3주차: 7/20~7/26, 4주차: 7/27~8/2
    group('2026년 7월 (1일=수)', () {
      late List<WeekPeriod> weeks;
      setUp(() => weeks = PayslipPeriodHelper.weeksOfMonth(2026, 7));

      test('주차 수 4개', () => expect(weeks.length, 4));

      test('1주차: 7/6~7/12', () {
        expect(weeks[0].start, DateTime(2026, 7, 6));
        expect(weeks[0].end, DateTime(2026, 7, 12));
        expect(weeks[0].weekNo, 1);
      });

      test('2주차: 7/13~7/19', () {
        expect(weeks[1].start, DateTime(2026, 7, 13));
        expect(weeks[1].end, DateTime(2026, 7, 19));
      });

      test('3주차: 7/20~7/26', () {
        expect(weeks[2].start, DateTime(2026, 7, 20));
        expect(weeks[2].end, DateTime(2026, 7, 26));
      });

      test('4주차: 7/27~8/2 (다음 달 포함)', () {
        expect(weeks[3].start, DateTime(2026, 7, 27));
        expect(weeks[3].end, DateTime(2026, 8, 2));
      });

      test('7/1~7/5는 어느 주차에도 포함 안 됨', () {
        for (final day in [1, 2, 3, 4, 5]) {
          final d = DateTime(2026, 7, day);
          final inAny = weeks.any(
            (w) => !d.isBefore(DateTime(w.start.year, w.start.month, w.start.day)) &&
                   !d.isAfter(DateTime(w.end.year, w.end.month, w.end.day)),
          );
          expect(inAny, isFalse,
              reason: '7/$day 는 이전 달 주차에 속하므로 제외되어야 함');
        }
      });
    });

    // ─── 2026년 6월 ─────────────────────────────────────────────────
    // 6/1 = 월요일 → 첫 번째 월요일: 6/1
    // 1주차: 6/1~6/7, 2주차: 6/8~6/14, 3주차: 6/15~6/21,
    // 4주차: 6/22~6/28, 5주차: 6/29~7/5
    group('2026년 6월 (1일=월)', () {
      late List<WeekPeriod> weeks;
      setUp(() => weeks = PayslipPeriodHelper.weeksOfMonth(2026, 6));

      test('주차 수 5개', () => expect(weeks.length, 5));

      test('1주차: 6/1~6/7', () {
        expect(weeks[0].start, DateTime(2026, 6, 1));
        expect(weeks[0].end, DateTime(2026, 6, 7));
      });

      test('5주차: 6/29~7/5 (다음 달 포함)', () {
        expect(weeks[4].start, DateTime(2026, 6, 29));
        expect(weeks[4].end, DateTime(2026, 7, 5));
      });
    });

    // ─── 2026년 2월 ─────────────────────────────────────────────────
    // 2/1 = 일요일 → 첫 번째 월요일: 2/2
    // 1주차: 2/2~2/8, 2주차: 2/9~2/15, 3주차: 2/16~2/22, 4주차: 2/23~3/1
    group('2026년 2월 (1일=일)', () {
      late List<WeekPeriod> weeks;
      setUp(() => weeks = PayslipPeriodHelper.weeksOfMonth(2026, 2));

      test('최소 4주차 보장', () => expect(weeks.length, greaterThanOrEqualTo(4)));

      test('1주차: 2/2~2/8', () {
        expect(weeks[0].start, DateTime(2026, 2, 2));
        expect(weeks[0].end, DateTime(2026, 2, 8));
      });

      test('2/1은 어느 주차에도 포함 안 됨', () {
        final d = DateTime(2026, 2, 1);
        final inAny = weeks.any(
          (w) => !d.isBefore(DateTime(w.start.year, w.start.month, w.start.day)) &&
                 !d.isAfter(DateTime(w.end.year, w.end.month, w.end.day)),
        );
        expect(inAny, isFalse);
      });
    });

    // ─── 주차 시작일 요일 검증 ─────────────────────────────────────────
    test('모든 주차의 start가 월요일(weekday=1)인지 검증', () {
      for (final month in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]) {
        final ws = PayslipPeriodHelper.weeksOfMonth(2026, month);
        for (final w in ws) {
          expect(w.start.weekday, 1,
              reason: '${w.start} 는 weekday=${w.start.weekday} (월요일=1 이어야 함)');
        }
      }
    });

    test('연속 주차는 7일 차이', () {
      final weeks = PayslipPeriodHelper.weeksOfMonth(2026, 7);
      for (int i = 1; i < weeks.length; i++) {
        final diff = weeks[i].start.difference(weeks[i - 1].start).inDays;
        expect(diff, 7);
      }
    });

    // ─── filterByWeek 연동 확인 ───────────────────────────────────────
    test('2026-07-06(월) filterByWeek → 1주차에 포함', () {
      final weeks = PayslipPeriodHelper.weeksOfMonth(2026, 7);
      final d = DateTime(2026, 7, 6);
      final w1 = weeks[0];
      final s = DateTime(w1.start.year, w1.start.month, w1.start.day);
      final e = DateTime(w1.end.year, w1.end.month, w1.end.day);
      expect(!d.isBefore(s) && !d.isAfter(e), isTrue);
    });

    test('2026-07-05(일) filterByWeek → 어느 7월 주차에도 미포함', () {
      final weeks = PayslipPeriodHelper.weeksOfMonth(2026, 7);
      final d = DateTime(2026, 7, 5);
      final inAny = weeks.any((w) {
        final s = DateTime(w.start.year, w.start.month, w.start.day);
        final e = DateTime(w.end.year, w.end.month, w.end.day);
        return !d.isBefore(s) && !d.isAfter(e);
      });
      expect(inAny, isFalse);
    });
  });
}
