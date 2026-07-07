// test/unit/labor_standards_test.dart
// LaborStandards 순수 계산 단위 테스트
//
// currentMinimumWage는 WageCalculator 의존(Firestore 우선) → 상수값 직접 검증 생략.
// 계산 메서드와 상수 검증에 집중.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/labor_standards.dart';

void main() {
  // ══════════════════════════════════════════════════════
  // 상수
  // ══════════════════════════════════════════════════════
  group('LaborStandards: 상수', () {
    test('월 소정근로시간 = 209.0', () {
      expect(LaborStandards.monthlyStandardHours, equals(209.0));
    });

    test('1일 기본 근로시간 = 8', () {
      expect(LaborStandards.dailyStandardHours, equals(8));
    });

    test('주 법정 근로시간 = 40', () {
      expect(LaborStandards.weeklyStandardHours, equals(40));
    });

    test('주휴수당 비율 = 0.2', () {
      expect(LaborStandards.weeklyHolidayPayRate, equals(0.2));
    });

    test('주휴수당 지급 기준 = 15 (시간)', () {
      expect(LaborStandards.weeklyHolidayPayThreshold, equals(15));
    });

    test('2025년 최저시급 = 10030', () {
      expect(LaborStandards.minimumWage2025, equals(10030));
    });

    test('2026년 최저시급 = 10320', () {
      expect(LaborStandards.minimumWage2026, equals(10320));
    });
  });

  // ══════════════════════════════════════════════════════
  // calculateDailyWage
  // ══════════════════════════════════════════════════════
  group('LaborStandards.calculateDailyWage', () {
    test('시급 10000 × 8시간 = 80000', () {
      expect(LaborStandards.calculateDailyWage(10000, 8.0), equals(80000));
    });

    test('시급 10320 × 8시간 = 82560 (2026년 최저시급)', () {
      expect(LaborStandards.calculateDailyWage(10320, 8.0), equals(82560));
    });

    test('시급 10000 × 4.5시간 = 45000 (반올림)', () {
      // 10000 * 4.5 = 45000.0 → round = 45000
      expect(LaborStandards.calculateDailyWage(10000, 4.5), equals(45000));
    });

    test('시급 10001 × 1.5시간 = 15002 (반올림)', () {
      // 10001 * 1.5 = 15001.5 → round = 15002
      expect(LaborStandards.calculateDailyWage(10001, 1.5), equals(15002));
    });

    test('시급 0 → 0', () {
      expect(LaborStandards.calculateDailyWage(0, 8.0), equals(0));
    });

    test('근무시간 0 → 0', () {
      expect(LaborStandards.calculateDailyWage(10000, 0.0), equals(0));
    });
  });

  // ══════════════════════════════════════════════════════
  // calculateDailyWageWithHolidayPay
  // ══════════════════════════════════════════════════════
  group('LaborStandards.calculateDailyWageWithHolidayPay', () {
    test('시급 10000 × 8시간 + 주휴 = 96000 (80000 × 1.2)', () {
      // 80000 * 1.2 = 96000.0 → round = 96000
      expect(LaborStandards.calculateDailyWageWithHolidayPay(10000, 8.0), equals(96000));
    });

    test('시급 10320 × 8시간 + 주휴 = 99072 (82560 × 1.2)', () {
      // 82560 * 1.2 = 99072.0 → round = 99072
      expect(LaborStandards.calculateDailyWageWithHolidayPay(10320, 8.0), equals(99072));
    });

    test('calculateDailyWageWithHolidayPay ≥ calculateDailyWage (항상 20% 이상)', () {
      final base = LaborStandards.calculateDailyWage(15000, 6.0);
      final withHoliday = LaborStandards.calculateDailyWageWithHolidayPay(15000, 6.0);
      expect(withHoliday, greaterThan(base));
    });

    test('반올림: 시급 10001 × 4시간 = (40004 × 1.2).round() = 48005', () {
      // 40004 * 1.2 = 48004.8 → round = 48005
      expect(LaborStandards.calculateDailyWageWithHolidayPay(10001, 4.0), equals(48005));
    });
  });

  // ══════════════════════════════════════════════════════
  // convertMonthlyToHourly
  // ══════════════════════════════════════════════════════
  group('LaborStandards.convertMonthlyToHourly', () {
    test('월 2090000원 ÷ 209시간 = 10000/시간', () {
      expect(LaborStandards.convertMonthlyToHourly(2090000, 209.0), equals(10000));
    });

    test('월 2156880원 ÷ 209시간 = 10320/시간 (2026년 최저시급 검증)', () {
      // 10320 * 209 = 2156880
      expect(LaborStandards.convertMonthlyToHourly(2156880, 209.0), equals(10320));
    });

    test('반올림: 월 100000원 ÷ 209시간 = (100000/209).round() = 478', () {
      // 100000 / 209 ≈ 478.47 → round = 478
      expect(LaborStandards.convertMonthlyToHourly(100000, 209.0), equals(478));
    });

    test('다른 monthlyHours 값 사용 가능', () {
      // 월 174000원 ÷ 174시간 = 1000
      expect(LaborStandards.convertMonthlyToHourly(174000, 174.0), equals(1000));
    });
  });

  // ══════════════════════════════════════════════════════
  // convertHourlyToMonthly
  // ══════════════════════════════════════════════════════
  group('LaborStandards.convertHourlyToMonthly', () {
    test('시급 10000 × 209시간 = 2090000', () {
      expect(LaborStandards.convertHourlyToMonthly(10000), equals(2090000));
    });

    test('시급 10320 × 209시간 = 2156880 (2026년 최저시급 → 월급)', () {
      // 10320 * 209 = 2156880
      expect(LaborStandards.convertHourlyToMonthly(10320), equals(2156880));
    });

    test('시급 0 → 0', () {
      expect(LaborStandards.convertHourlyToMonthly(0), equals(0));
    });

    test('반올림: 시급 1 × 209 = 209', () {
      expect(LaborStandards.convertHourlyToMonthly(1), equals(209));
    });
  });

  // ══════════════════════════════════════════════════════
  // convertMonthlyToHourly ↔ convertHourlyToMonthly 역변환 일관성
  // ══════════════════════════════════════════════════════
  group('LaborStandards: 역변환 일관성', () {
    test('시급 → 월급 → 시급 왕복 (정수 반올림 오차 허용 ±1)', () {
      const hourly = 12000;
      final monthly = LaborStandards.convertHourlyToMonthly(hourly);
      final backToHourly = LaborStandards.convertMonthlyToHourly(monthly, 209.0);
      expect(backToHourly, closeTo(hourly, 1));
    });
  });
}
