// test/unit/week_helper_test.dart
// WeekHelper / WeeklyHolidayEligibility 단위 테스트
//
// 월요일 시작, 일요일 종료 기준 주 계산 검증.
// WeeklyHolidayEligibility는 순수 값 객체 — 생성자 직접 사용.
//
// [R7-FS-1 B] 기대값을 `DateTime` 에서 `DateTime.utc` 로 옮겼다.
//
//   `weekStart/weekEnd` 는 `FormatHelper.toKstDate` 를 지난다. 그 함수는
//   일부러 `DateTime.utc(y, m, d)` 를 돌려준다 — **기기 시간대와 무관한
//   KST 달력일 비교 키**이고, "실제 KST 자정 instant" 가 아니다(원본 주석).
//   그래서 로컬 `DateTime(2026, 6, 1)` 과는 같지 않다.
//
//   이 키를 로컬로 되돌리면 비-KST 기기에서 주 경계가 하루 밀린다 —
//   그것을 막으려고 넣은 성질이므로 **제품이 아니라 기대값을 옮겼다.**
//   키라는 성질 자체는 아래 `weekStart 는 KST 달력일 비교 키다` 가 지킨다.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/week_helper.dart';

void main() {
  // ══════════════════════════════════════════════════════
  // WeekHelper.weekStart
  // ══════════════════════════════════════════════════════
  group('WeekHelper.weekStart', () {
    // 2026-06-01 = 월요일 (weekday=1)
    test('월요일 → 자기 자신', () {
      final result = WeekHelper.weekStart(DateTime(2026, 6, 1));
      expect(result, equals(DateTime.utc(2026, 6, 1)));
    });

    // 2026-06-05 = 금요일 (weekday=5)
    test('금요일 → 해당 주 월요일', () {
      final result = WeekHelper.weekStart(DateTime(2026, 6, 5));
      expect(result, equals(DateTime.utc(2026, 6, 1)));
    });

    // 2026-06-07 = 일요일 (weekday=7)
    test('일요일 → 해당 주 월요일', () {
      final result = WeekHelper.weekStart(DateTime(2026, 6, 7));
      expect(result, equals(DateTime.utc(2026, 6, 1)));
    });

    // 2026-06-08 = 월요일 (다음 주 시작)
    test('다음 주 월요일 → 다음 주 월요일', () {
      final result = WeekHelper.weekStart(DateTime(2026, 6, 8));
      expect(result, equals(DateTime.utc(2026, 6, 8)));
    });

    // 월 경계: 2026-03-01 = 일요일, 월요일은 2026-02-23
    test('월 경계 넘김 → 이전 달 월요일 반환', () {
      // 2026-03-01 = 일요일(weekday=7) → weekStart = 2026-03-01 - 6일 = 2026-02-23(월)
      final result = WeekHelper.weekStart(DateTime(2026, 3, 1));
      expect(result, equals(DateTime.utc(2026, 2, 23)));
    });

    // 연 경계: 2026-01-01 = 목요일 (weekday=4), weekStart = 2025-12-29(월)
    test('연 경계 넘김 → 전년도 12월 월요일', () {
      final result = WeekHelper.weekStart(DateTime(2026, 1, 1));
      expect(result, equals(DateTime.utc(2025, 12, 29)));
    });

    test('시간 정보는 0시 기준으로 반환', () {
      final result = WeekHelper.weekStart(DateTime(2026, 6, 3, 14, 30));
      // 2026-06-03 = 수요일 → 월요일 = 2026-06-01 00:00
      expect(result, equals(DateTime.utc(2026, 6, 1)));
      expect(result.hour,   equals(0));
      expect(result.minute, equals(0));
    });

    // [R7-FS-1 B] 위 기대값이 `.utc` 인 **이유**를 여기서 지킨다.
    //   누가 다시 로컬 DateTime 으로 되돌리면 이 셀이 먼저 걸린다.
    test('weekStart 는 기기 시간대와 무관한 KST 달력일 비교 키다', () {
      final result = WeekHelper.weekStart(DateTime(2026, 6, 3, 14, 30));
      expect(result.isUtc, isTrue,
          reason: 'KST 달력일 키다 — 로컬 자정 instant 가 아니다');

      // 같은 KST 순간을 서로 다른 오프셋으로 표현해도 같은 키가 나온다.
      final kstNoon = DateTime.utc(2026, 6, 3, 3); // = KST 12:00
      expect(WeekHelper.weekStart(kstNoon), equals(result));
      expect(WeekHelper.weekStart(kstNoon.toLocal()), equals(result));
    });
  });

  // ══════════════════════════════════════════════════════
  // WeekHelper.weekEnd
  // ══════════════════════════════════════════════════════
  group('WeekHelper.weekEnd', () {
    // weekEnd = weekStart + 6일
    test('월요일 입력 → 해당 주 일요일', () {
      final result = WeekHelper.weekEnd(DateTime(2026, 6, 1));
      // 2026-06-01 (월) + 6 = 2026-06-07 (일)
      expect(result, equals(DateTime.utc(2026, 6, 7)));
    });

    test('금요일 입력 → 해당 주 일요일', () {
      final result = WeekHelper.weekEnd(DateTime(2026, 6, 5));
      expect(result, equals(DateTime.utc(2026, 6, 7)));
    });

    test('일요일 입력 → 자기 자신(일요일)', () {
      final result = WeekHelper.weekEnd(DateTime(2026, 6, 7));
      expect(result, equals(DateTime.utc(2026, 6, 7)));
    });

    test('월 경계 넘김 → 다음 달 일요일', () {
      // 2026-05-25 = 월요일 → weekEnd = 2026-05-31(일)
      final result = WeekHelper.weekEnd(DateTime(2026, 5, 25));
      expect(result, equals(DateTime.utc(2026, 5, 31)));
    });

    test('연 경계: weekEnd ≥ weekStart', () {
      // 항상 weekEnd가 weekStart보다 늦어야 함
      final start = WeekHelper.weekStart(DateTime(2025, 12, 31));
      final end   = WeekHelper.weekEnd(DateTime(2025, 12, 31));
      expect(end.isAfter(start), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // weekStart / weekEnd 일관성
  // ══════════════════════════════════════════════════════
  group('WeekHelper: weekStart/weekEnd 일관성', () {
    test('weekEnd - weekStart = 6일', () {
      final start = WeekHelper.weekStart(DateTime(2026, 6, 3));
      final end   = WeekHelper.weekEnd(DateTime(2026, 6, 3));
      final diff  = end.difference(start).inDays;
      expect(diff, equals(6));
    });

    test('weekStart는 항상 월요일(weekday=1)', () {
      final start = WeekHelper.weekStart(DateTime(2026, 6, 5));
      expect(start.weekday, equals(DateTime.monday));
    });

    test('weekEnd는 항상 일요일(weekday=7)', () {
      final end = WeekHelper.weekEnd(DateTime(2026, 6, 5));
      expect(end.weekday, equals(DateTime.sunday));
    });
  });

  // ══════════════════════════════════════════════════════
  // WeeklyHolidayEligibility.meetsHours
  // ══════════════════════════════════════════════════════
  group('WeeklyHolidayEligibility.meetsHours', () {
    WeeklyHolidayEligibility _make({required int totalWorkMinutes}) {
      return WeeklyHolidayEligibility(
        isEligible: false,
        workedDays: 5,
        scheduledDaysPerWeek: 5,
        totalWorkMinutes: totalWorkMinutes,
        weeklyHolidayAmount: 0,
        weekStart: DateTime(2026, 6, 1),
        weekEnd: DateTime(2026, 6, 7),
      );
    }

    test('900분(15시간) → true (경계값 포함)', () {
      expect(_make(totalWorkMinutes: 900).meetsHours, isTrue);
    });

    test('899분 → false (경계값 미만)', () {
      expect(_make(totalWorkMinutes: 899).meetsHours, isFalse);
    });

    test('0분 → false', () {
      expect(_make(totalWorkMinutes: 0).meetsHours, isFalse);
    });

    test('2400분(40시간 주 풀타임) → true', () {
      expect(_make(totalWorkMinutes: 2400).meetsHours, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // WeeklyHolidayEligibility.meetsDays
  // ══════════════════════════════════════════════════════
  group('WeeklyHolidayEligibility.meetsDays', () {
    WeeklyHolidayEligibility _make({
      required int workedDays,
      required int scheduledDaysPerWeek,
    }) {
      return WeeklyHolidayEligibility(
        isEligible: false,
        workedDays: workedDays,
        scheduledDaysPerWeek: scheduledDaysPerWeek,
        totalWorkMinutes: 2400,
        weeklyHolidayAmount: 0,
        weekStart: DateTime(2026, 6, 1),
        weekEnd: DateTime(2026, 6, 7),
      );
    }

    test('근무일수 = 예정일수 → true', () {
      expect(_make(workedDays: 5, scheduledDaysPerWeek: 5).meetsDays, isTrue);
    });

    test('근무일수 > 예정일수 → true', () {
      expect(_make(workedDays: 6, scheduledDaysPerWeek: 5).meetsDays, isTrue);
    });

    test('근무일수 < 예정일수 → false', () {
      expect(_make(workedDays: 4, scheduledDaysPerWeek: 5).meetsDays, isFalse);
    });

    test('근무일수 0, 예정일수 0 → true (0 ≥ 0)', () {
      expect(_make(workedDays: 0, scheduledDaysPerWeek: 0).meetsDays, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // WeeklyHolidayEligibility.totalWorkHours
  // ══════════════════════════════════════════════════════
  group('WeeklyHolidayEligibility.totalWorkHours', () {
    test('900분 → 15.0시간', () {
      final e = WeeklyHolidayEligibility(
        isEligible: true,
        workedDays: 5,
        scheduledDaysPerWeek: 5,
        totalWorkMinutes: 900,
        weeklyHolidayAmount: 82560,
        weekStart: DateTime(2026, 6, 1),
        weekEnd: DateTime(2026, 6, 7),
      );
      expect(e.totalWorkHours, equals(15.0));
    });

    test('2400분 → 40.0시간', () {
      final e = WeeklyHolidayEligibility(
        isEligible: true,
        workedDays: 5,
        scheduledDaysPerWeek: 5,
        totalWorkMinutes: 2400,
        weeklyHolidayAmount: 82560,
        weekStart: DateTime(2026, 6, 1),
        weekEnd: DateTime(2026, 6, 7),
      );
      expect(e.totalWorkHours, equals(40.0));
    });

    test('90분 → 1.5시간', () {
      final e = WeeklyHolidayEligibility(
        isEligible: false,
        workedDays: 1,
        scheduledDaysPerWeek: 5,
        totalWorkMinutes: 90,
        weeklyHolidayAmount: 0,
        weekStart: DateTime(2026, 6, 1),
        weekEnd: DateTime(2026, 6, 7),
      );
      expect(e.totalWorkHours, equals(1.5));
    });
  });
}
