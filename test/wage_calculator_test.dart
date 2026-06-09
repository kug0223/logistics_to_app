// test/wage_calculator_test.dart
// 급여 계산 로직 단위 테스트
//
// 테스트 대상: WageCalculator.calculate()
// 핵심 시나리오: 시급제·일급제 기본급, 연장수당, 야간수당, 최저임금 적용

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/wage_calculator.dart';

// 기준: 2026년 최저시급 10,320원
const int _minWage2026 = 10320;
final DateTime _workDate2026 = DateTime(2026, 6, 1);

void main() {
  // ──────────────────────────────────────────────────────────
  // 최저시급 조회
  // ──────────────────────────────────────────────────────────
  group('WageCalculator.getMinimumWage', () {
    test('2026년 최저시급 10,320원', () {
      expect(WageCalculator.getMinimumWage(2026), equals(10320));
    });

    test('2025년 최저시급 10,030원', () {
      expect(WageCalculator.getMinimumWage(2025), equals(10030));
    });

    test('2024년 최저시급 9,860원', () {
      expect(WageCalculator.getMinimumWage(2024), equals(9860));
    });

    test('존재하지 않는 연도 → 최근 연도 값 반환', () {
      // 2030년은 테이블에 없음 → 가장 최근 연도(2026)값 반환
      expect(WageCalculator.getMinimumWage(2030), greaterThanOrEqualTo(_minWage2026));
    });
  });

  // ──────────────────────────────────────────────────────────
  // 휴게시간 규정
  // ──────────────────────────────────────────────────────────
  group('WageCalculator.legalMaxBreakMinutes', () {
    test('4시간 미만 → 휴게 의무 없음(0분)', () {
      expect(WageCalculator.legalMaxBreakMinutes(239), equals(0));
    });

    test('4시간(240분) → 30분', () {
      expect(WageCalculator.legalMaxBreakMinutes(240), equals(30));
    });

    test('8시간(480분) → 60분', () {
      expect(WageCalculator.legalMaxBreakMinutes(480), equals(60));
    });

    test('9시간 → 60분 (8시간 이상은 60분으로 고정)', () {
      expect(WageCalculator.legalMaxBreakMinutes(540), equals(60));
    });
  });

  // ──────────────────────────────────────────────────────────
  // 시급제 — 기본 케이스
  // ──────────────────────────────────────────────────────────
  group('WageCalculator.calculate [시급제]', () {
    test('시급 12,000원 × 8시간 = 96,000원', () {
      final result = WageCalculator.calculate(
        wageType: 'hourly',
        baseWage: 12000,
        workDate: _workDate2026,
        scheduledStart: '09:00',
        scheduledEnd: '18:00',
        actualStart: '09:00',
        actualEnd: '18:00',
        breakMinutes: 60,
        nightAllowanceApplied: false,
      );
      // 근무 8시간(480분) → baseAmount = 480/60 × 12000 = 96,000
      expect(result.workMinutes, equals(480));
      expect(result.baseAmount, equals(96000));
      expect(result.overtimeAmount, equals(0));
      expect(result.nightAmount, equals(0));
      expect(result.totalAmount, equals(96000));
    });

    test('시급 12,000원 × 9시간 → 연장 1시간 1.5배 적용', () {
      final result = WageCalculator.calculate(
        wageType: 'hourly',
        baseWage: 12000,
        workDate: _workDate2026,
        scheduledStart: '09:00',
        scheduledEnd: '19:00',
        actualStart: '09:00',
        actualEnd: '19:00',
        breakMinutes: 60,
        nightAllowanceApplied: false,
      );
      // 근무 9시간: 기본 8시간=96,000 + 연장 1시간×12,000×1.5=18,000 = 114,000
      expect(result.workMinutes, equals(480 + 60)); // 9시간
      expect(result.overtimeMinutes, equals(60));
      expect(result.baseAmount, equals(96000));
      expect(result.overtimeAmount, equals(18000));
      expect(result.totalAmount, equals(114000));
    });

    test('시급 12,000원 × 4시간 야간(22:00~02:00) → 야간수당 0.5배 가산', () {
      final result = WageCalculator.calculate(
        wageType: 'hourly',
        baseWage: 12000,
        workDate: _workDate2026,
        scheduledStart: '22:00',
        scheduledEnd: '02:00',
        actualStart: '22:00',
        actualEnd: '02:00',
        breakMinutes: 0,
        nightAllowanceApplied: true,
      );
      // 4시간(240분), 연장 없음(8시간 미만)
      // 기본급 = 240/60 × 12000 = 48,000
      // 야간분 = 22:00~02:00 = 240분 (모두 야간 22:00~06:00 범위)
      // 야간수당 = 240/60 × 12000 × 0.5 = 24,000
      expect(result.workMinutes, equals(240));
      expect(result.baseAmount, equals(48000));
      expect(result.nightAmount, equals(24000));
      expect(result.totalAmount, equals(72000));
    });

    test('시급이 최저시급 미만이어도 그대로 계산 (UI에서 경고, 강제 변경 없음)', () {
      final result = WageCalculator.calculate(
        wageType: 'hourly',
        baseWage: 9000, // 최저시급 10,320원 미만
        workDate: _workDate2026,
        scheduledStart: '09:00',
        scheduledEnd: '17:00',
        actualStart: '09:00',
        actualEnd: '17:00',
        breakMinutes: 60,
        nightAllowanceApplied: false,
      );
      // 7시간(420분), baseAmount = 420/60 × 9000 = 63,000
      expect(result.workMinutes, equals(420));
      expect(result.baseAmount, equals(63000));
    });

    test('실제 근무시간이 예정보다 짧아도 실제 기준으로 계산', () {
      final result = WageCalculator.calculate(
        wageType: 'hourly',
        baseWage: 12000,
        workDate: _workDate2026,
        scheduledStart: '09:00',
        scheduledEnd: '18:00',
        actualStart: '09:30', // 30분 지각
        actualEnd: '18:00',
        breakMinutes: 60,
        nightAllowanceApplied: false,
      );
      // 실제: 8.5시간 - 1시간 휴게 = 7.5시간(450분)
      expect(result.workMinutes, equals(450));
      expect(result.totalAmount, equals((450 / 60 * 12000).round()));
    });

    test('휴게시간 0분 처리', () {
      final result = WageCalculator.calculate(
        wageType: 'hourly',
        baseWage: 12000,
        workDate: _workDate2026,
        scheduledStart: '09:00',
        scheduledEnd: '13:00',
        actualStart: '09:00',
        actualEnd: '13:00',
        breakMinutes: 0,
        nightAllowanceApplied: false,
      );
      expect(result.workMinutes, equals(240));
      expect(result.breakMinutes, equals(0));
    });
  });

  // ──────────────────────────────────────────────────────────
  // 일급제
  // ──────────────────────────────────────────────────────────
  group('WageCalculator.calculate [일급제]', () {
    test('일급 100,000원 × 예정 8시간 = 예정 근무 시 100,000원', () {
      final result = WageCalculator.calculate(
        wageType: 'daily',
        baseWage: 100000,
        workDate: _workDate2026,
        scheduledStart: '09:00',
        scheduledEnd: '18:00',
        actualStart: '09:00',
        actualEnd: '18:00',
        breakMinutes: 60,
        nightAllowanceApplied: false,
      );
      // 예정 = 실제 → 기본급 = 일급 전액
      expect(result.baseAmount, equals(100000));
      expect(result.overtimeAmount, equals(0));
      expect(result.totalAmount, equals(100000));
    });

    test('일급 100,000원, 예정 8시간 중 7시간만 근무 → 비율 계산', () {
      final result = WageCalculator.calculate(
        wageType: 'daily',
        baseWage: 100000,
        workDate: _workDate2026,
        scheduledStart: '09:00',
        scheduledEnd: '18:00',
        actualStart: '10:00', // 1시간 늦게 출근
        actualEnd: '18:00',
        breakMinutes: 60,
        nightAllowanceApplied: false,
      );
      // 예정 480분, 실제 420분 → 비율 420/480 = 0.875 → 87,500원
      expect(result.workMinutes, equals(420));
      expect(result.overtimeMinutes, equals(0));
      expect(result.baseAmount, lessThan(100000));
    });
  });

  // ──────────────────────────────────────────────────────────
  // 추가수당
  // ──────────────────────────────────────────────────────────
  group('WageCalculator.calculate [추가수당]', () {
    test('추가수당 5,000원 포함', () {
      final result = WageCalculator.calculate(
        wageType: 'hourly',
        baseWage: 12000,
        workDate: _workDate2026,
        scheduledStart: '09:00',
        scheduledEnd: '17:00',
        actualStart: '09:00',
        actualEnd: '17:00',
        breakMinutes: 60,
        nightAllowanceApplied: false,
        additionalAmount: 5000,
      );
      final base = (7 * 12000); // 7시간 × 12,000
      expect(result.totalAmount, equals(base + 5000));
    });
  });

  // ──────────────────────────────────────────────────────────
  // 엣지 케이스
  // ──────────────────────────────────────────────────────────
  group('WageCalculator.calculate [엣지 케이스]', () {
    test('출퇴근 시간 같음 → 근무시간 0분, 급여 0원', () {
      final result = WageCalculator.calculate(
        wageType: 'hourly',
        baseWage: 12000,
        workDate: _workDate2026,
        scheduledStart: '09:00',
        scheduledEnd: '09:00',
        actualStart: '09:00',
        actualEnd: '09:00',
        nightAllowanceApplied: false,
      );
      expect(result.workMinutes, equals(0));
      expect(result.totalAmount, equals(0));
    });

    test('자정 넘는 근무 (22:00~06:00) 8시간 정상 계산', () {
      final result = WageCalculator.calculate(
        wageType: 'hourly',
        baseWage: 12000,
        workDate: _workDate2026,
        scheduledStart: '22:00',
        scheduledEnd: '06:00',
        actualStart: '22:00',
        actualEnd: '06:00',
        breakMinutes: 60,
        nightAllowanceApplied: false,
      );
      // 8시간(480분) - 60분 = 420분
      expect(result.workMinutes, equals(420));
    });
  });
}
