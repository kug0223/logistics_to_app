// test/simulation/attendance_wage_e2e_simulation_test.dart
//
// 체크인→체크아웃→급여 계산 E2E 통합 시뮬레이션
//
// ── 기존 테스트와의 차별성 ────────────────────────────────────
// 기존: 반올림 OR 급여를 개별로 검증
// 이 파일: 실제 펀치 시각 → 반올림 → 급여 계산 → 금액 검증을
//         하나의 파이프라인으로 연결하는 통합 E2E
//
// ── 커버 범위 ────────────────────────────────────────────────
//  A. 주간 시급제 (09:00~18:00, break=60, wage=12000)  — 12 케이스
//  B. 야간 시급제 (22:00~06:00, break=60, wage=12000)  —  8 케이스
//  C. 일급제 기본 (08:00~17:00, break=60, daily=100000) —  8 케이스
//  D. 경계값 시나리오                                   —  8 케이스
//  E. 커스텀 AttendanceRules                            —  7 케이스
//  F. 세전 급여 정합성                                  —  7 케이스
//
// 합계: 50 시나리오
//
// ── 계산 규칙 (CLAUDE.md 기준) ──────────────────────────────
// processCheckin  offsetMinutes = punchAt - contractStartAt (음수=조출, 양수=지각)
// processCheckout offsetMinutes = punchAt - contractEndAt   (음수=조퇴, 양수=연장)
//
// 조출(earlyArrival) : (offset~/earlyArrivalUnit)*earlyArrivalUnit (ceil, 0 방향)
// 지각(late)         : ((offset+lateUnit-1)~/lateUnit)*lateUnit    (ceil)
// 연장(overtime)     : (offset~/overtimeUnit)*overtimeUnit          (floor)
// 조퇴(earlyLeave)   : -(((earlyDiff+earlyLeaveUnit-1)~/earlyLeaveUnit)*earlyLeaveUnit) (floor)
//
// 시급제 OT  : workMin > 480 초과분 × wage × 1.5
// 일급제 OT  : workMin > scheduledWorkMin 초과분 × supplementWage
//              (8h 이하: 1배, 8h 초과: 1.5배)
// 야간수당   : nightMin × wage × 0.5
// totalAmount: baseAmount + overtimeAmount + nightAmount + additionalAmount
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/utils/attendance_rounding_helper.dart';
import 'package:ALfit/utils/wage_calculator.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';

// ── 공통 상수 ─────────────────────────────────────────────────

/// 기준 근무일 (최저시급 2026 = 10,320원)
final _date = DateTime(2026, 1, 15);

/// 기본 시급
const int _hourlyWage = 12000;

/// 기본 일급
const int _dailyWage = 100000;

// ── 기본 AttendanceRules (defaults) ──────────────────────────
// earlyWindow=30, earlyArrivalUnit=30, lateGrace=5, lateUnit=30
// lateWindow=30, overtimeUnit=10, earlyLeaveUnit=30
const _defaultRules = AttendanceRules();

// ── E2E 헬퍼 — 반올림 후 HH:mm 문자열 계산 ──────────────────

/// 출근 펀치 → 반올림된 "HH:mm"
String _roundedCheckIn(
  int punchHour,
  int punchMin, {
  int contractStartHour = 9,
  int contractStartMin = 0,
  AttendanceRules rules = _defaultRules,
  DateTime? workDate,
}) {
  final date = workDate ?? _date;
  final contractStart =
      DateTime(date.year, date.month, date.day, contractStartHour, contractStartMin);
  final punchAt =
      DateTime(date.year, date.month, date.day, punchHour, punchMin);
  final offset = punchAt.difference(contractStart).inMinutes;
  return processCheckin(
    offsetMinutes: offset,
    referenceAt: contractStart,
    rules: rules,
  ).rounded;
}

/// 퇴근 펀치 → 반올림된 "HH:mm"
/// [nextDay] 퇴근 펀치가 다음날인 경우 (야간 교대 종료 등)
String _roundedCheckOut(
  int punchHour,
  int punchMin, {
  int contractStartHour = 9,
  int contractStartMin = 0,
  int contractEndHour = 18,
  int contractEndMin = 0,
  AttendanceRules rules = _defaultRules,
  DateTime? workDate,
  bool nextDay = false,
}) {
  final date = workDate ?? _date;
  final contractEnd = contractEndAt(
    date,
    '${contractStartHour.toString().padLeft(2, '0')}:${contractStartMin.toString().padLeft(2, '0')}',
    '${contractEndHour.toString().padLeft(2, '0')}:${contractEndMin.toString().padLeft(2, '0')}',
  );
  final punchDate = nextDay ? date.add(const Duration(days: 1)) : date;
  final punchAt =
      DateTime(punchDate.year, punchDate.month, punchDate.day, punchHour, punchMin);
  final offset = punchAt.difference(contractEnd).inMinutes;
  return processCheckout(
    offsetMinutes: offset,
    referenceAt: contractEnd,
    rules: rules,
  ).rounded;
}

/// 시급제 E2E 계산: 반올림 후 HH:mm → WageCalculator
WageDetailModel _calcHourly({
  required String actualStart,
  required String actualEnd,
  String scheduledStart = '09:00',
  String scheduledEnd = '18:00',
  int breakMinutes = 60,
  int wage = _hourlyWage,
  bool nightAllowance = true,
  int additionalAmount = 0,
}) =>
    WageCalculator.calculate(
      wageType: 'hourly',
      baseWage: wage,
      workDate: _date,
      scheduledStart: scheduledStart,
      scheduledEnd: scheduledEnd,
      actualStart: actualStart,
      actualEnd: actualEnd,
      breakMinutes: breakMinutes,
      nightAllowanceApplied: nightAllowance,
      additionalAmount: additionalAmount,
    );

/// 일급제 E2E 계산
WageDetailModel _calcDaily({
  required String actualStart,
  required String actualEnd,
  String scheduledStart = '08:00',
  String scheduledEnd = '17:00',
  int breakMinutes = 60,
  int? scheduledBreakMinutes,
  int wage = _dailyWage,
  bool nightAllowance = true,
  int additionalAmount = 0,
  int? baseHourlyWage,
}) =>
    WageCalculator.calculate(
      wageType: 'daily',
      baseWage: wage,
      workDate: _date,
      scheduledStart: scheduledStart,
      scheduledEnd: scheduledEnd,
      actualStart: actualStart,
      actualEnd: actualEnd,
      breakMinutes: breakMinutes,
      scheduledBreakMinutes: scheduledBreakMinutes,
      nightAllowanceApplied: nightAllowance,
      additionalAmount: additionalAmount,
      baseHourlyWage: baseHourlyWage,
    );

// ─────────────────────────────────────────────────────────────
void main() {

  // ════════════════════════════════════════════════════════════
  // A. 주간 시급제 E2E — 09:00~18:00, break=60, wage=12000
  //    기대값 산출 근거:
  //    actualMinutes = 분 간격, workMin = actualMin-60
  //    baseAmount    = regularMin × 12000 / 60
  //    overtimeAmount= OTMin × 12000 × 1.5 / 60
  // ════════════════════════════════════════════════════════════
  group('A. 주간 시급제 E2E (09:00~18:00, break=60, wage=12000)', () {

    // ── A01 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-A01: 정시 출퇴근 → workMin=480, total=96000', () {
      // 펀치: 09:00 / 18:00
      final ci = _roundedCheckIn(9, 0);
      final co = _roundedCheckOut(18, 0);
      expect(ci, '09:00', reason: 'offset=0 → onTime');
      expect(co, '18:00', reason: 'offset=0 → onTimeOut');

      final r = _calcHourly(actualStart: ci, actualEnd: co);
      expect(r.workMinutes,  480);
      expect(r.overtimeMinutes, 0);
      expect(r.baseAmount,   96000);
      expect(r.overtimeAmount, 0);
      expect(r.nightAmount,  0);
      expect(r.totalAmount,  96000);
    });

    // ── A02 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-A02: 5분 지각(lateGrace=5) → 정시 처리 → total=96000', () {
      // 펀치: 09:05 → offset=5 ≤ lateGrace(5) → 09:00
      final ci = _roundedCheckIn(9, 5);
      final co = _roundedCheckOut(18, 0);
      expect(ci, '09:00', reason: 'lateGrace 이내 → 정시');
      expect(co, '18:00');

      final r = _calcHourly(actualStart: ci, actualEnd: co);
      expect(r.workMinutes,  480);
      expect(r.totalAmount,  96000);
    });

    // ── A03 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-A03: 7분 지각(유예 초과) → lateUnit=30으로 올림 → 09:30, workMin=450, total=90000', () {
      // 펀치: 09:07 → offset=7>5, ceil(7/30)*30=30 → 09:30
      final ci = _roundedCheckIn(9, 7);
      final co = _roundedCheckOut(18, 0);
      expect(ci, '09:30', reason: 'ceil(7/30)*30=30 → contractStart+30');

      final r = _calcHourly(actualStart: ci, actualEnd: co);
      // actualMinutes = 18:00 - 09:30 = 510
      expect(r.actualMinutes,  510);
      expect(r.workMinutes,    450);   // 510 - 60
      expect(r.overtimeMinutes, 0);
      expect(r.baseAmount,     90000); // 450 × 12000 / 60
      expect(r.totalAmount,    90000);
    });

    // ── A04 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-A04: 15분 일찍 → earlyWindow(30) 이내 → 정시 처리', () {
      // 펀치: 08:45 → offset=-15. -15 NOT < -30 → onTime → 09:00
      final ci = _roundedCheckIn(8, 45);
      expect(ci, '09:00', reason: 'earlyWindow 이내 도착 → 정시');

      final r = _calcHourly(actualStart: ci, actualEnd: '18:00');
      expect(r.workMinutes, 480);
      expect(r.totalAmount, 96000);
    });

    // ── A05 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-A05: 31분 일찍 → earlyWindow 초과 → 조출 08:30, workMin=510, total=105000', () {
      // 펀치: 08:29 → offset=-31 < -earlyWindow(-30)
      // earlyArrival: (-31~/30)*30 = (-1)*30 = -30 → 09:00-30 = 08:30
      final ci = _roundedCheckIn(8, 29);
      final co = _roundedCheckOut(18, 0);
      expect(ci, '08:30', reason: '조출 31분 → ceil 방향(0쪽) → -30 → 08:30');

      final r = _calcHourly(actualStart: ci, actualEnd: co);
      // actualMinutes = 18:00 - 08:30 = 570, workMin = 570-60 = 510
      expect(r.actualMinutes,    570);
      expect(r.workMinutes,      510);
      expect(r.overtimeMinutes,  30);  // 510-480
      expect(r.earlyArrivalMinutes, 30);
      expect(r.baseAmount,       96000); // 480 × 12000/60
      expect(r.overtimeAmount,   9000);  // 30 × 12000 × 1.5 / 60
      expect(r.totalAmount,      105000);
    });

    // ── A06 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-A06: 30분 조퇴 → earlyLeaveUnit=30 → 17:30, workMin=450, total=90000', () {
      // 펀치: 17:30 → offset=-30, earlyDiff=30, ceil(30/30)*30=30 → -30 → 17:30
      final co = _roundedCheckOut(17, 30);
      expect(co, '17:30', reason: '조퇴 30분 정각 → 17:30');

      final r = _calcHourly(actualStart: '09:00', actualEnd: co);
      expect(r.workMinutes,   450); // 510-60
      expect(r.totalAmount,   90000);
    });

    // ── A07 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-A07: 35분 조퇴 → 60분 올림 → 17:00, workMin=420, total=84000', () {
      // 펀치: 17:25 → offset=-35, earlyDiff=35, ceil(35/30)*30=60 → -60 → 17:00
      final co = _roundedCheckOut(17, 25);
      expect(co, '17:00', reason: 'ceil(35/30)*30=60 → contractEnd-60=17:00');

      final r = _calcHourly(actualStart: '09:00', actualEnd: co);
      expect(r.workMinutes,  420); // 480-60
      expect(r.baseAmount,   84000); // 420 × 12000/60
      expect(r.totalAmount,  84000);
    });

    // ── A08 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-A08: 35분 연장 → overtimeUnit=10 내림 → 18:30, OT=30', () {
      // 펀치: 18:35 → offset=35>30, (35~/10)*10=30 → 18:30
      final co = _roundedCheckOut(18, 35);
      expect(co, '18:30', reason: 'floor(35/10)*10=30 → contractEnd+30');

      final r = _calcHourly(actualStart: '09:00', actualEnd: co);
      expect(r.workMinutes,     510);
      expect(r.overtimeMinutes, 30);
      expect(r.baseAmount,      96000);
      expect(r.overtimeAmount,  9000); // 30 × 12000 × 1.5 / 60
      expect(r.totalAmount,     105000);
    });

    // ── A09 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-A09: 65분 연장 → 60분 내림 → 19:00, OT=60, total=114000', () {
      // 펀치: 19:05 → offset=65>30, (65~/10)*10=60 → 19:00
      final co = _roundedCheckOut(19, 5);
      expect(co, '19:00');

      final r = _calcHourly(actualStart: '09:00', actualEnd: co);
      expect(r.workMinutes,     540);
      expect(r.overtimeMinutes, 60);
      expect(r.overtimeAmount,  18000); // 60 × 12000 × 1.5 / 60
      expect(r.totalAmount,     114000);
    });

    // ── A10 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-A10: 30분 지각 정각 → ceil(30/30)=1 → 09:30, workMin=450', () {
      // 펀치: 09:30 → offset=30>5, ceil(30/30)*30=30 → 09:30 (정각도 올림 대상)
      final ci = _roundedCheckIn(9, 30);
      expect(ci, '09:30');

      final r = _calcHourly(actualStart: ci, actualEnd: '18:00');
      expect(r.workMinutes, 450);
      expect(r.totalAmount, 90000);
    });

    // ── A11 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-A11: 조출+조퇴 복합 (08:29→08:30, 17:25→17:00) → workMin=450', () {
      // 조출: 08:29 → 08:30 (earlyArrival -30)
      // 조퇴: 17:25 → 17:00 (earlyLeave -60)
      final ci = _roundedCheckIn(8, 29);
      final co = _roundedCheckOut(17, 25);
      expect(ci, '08:30');
      expect(co, '17:00');

      final r = _calcHourly(actualStart: ci, actualEnd: co);
      // actualMinutes = 17:00 - 08:30 = 510, workMin = 450
      expect(r.actualMinutes,    510);
      expect(r.workMinutes,      450);
      expect(r.overtimeMinutes,  0); // 450 < 480
      expect(r.totalAmount,      90000);
    });

    // ── A12 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-A12: 지각+연장 복합 (09:07→09:30, 18:35→18:30) → workMin=480, OT=0', () {
      // 지각: 09:07 → 09:30 (+30분)
      // 연장: 18:35 → 18:30 (+30분)
      // actualMinutes = 09:30~18:30 = 540, workMin = 480 (정확히 8h → OT 없음)
      final ci = _roundedCheckIn(9, 7);
      final co = _roundedCheckOut(18, 35);
      expect(ci, '09:30');
      expect(co, '18:30');

      final r = _calcHourly(actualStart: ci, actualEnd: co);
      expect(r.actualMinutes,    540);
      expect(r.workMinutes,      480);
      expect(r.overtimeMinutes,  0);
      expect(r.totalAmount,      96000);
    });
  });

  // ════════════════════════════════════════════════════════════
  // B. 야간 시급제 E2E — 22:00~06:00, break=60, wage=12000
  //    nightMinutes 계산 시 휴게는 주간 구간 먼저 소진
  //    nightAmount = nightMin × 12000 × 0.5 / 60
  // ════════════════════════════════════════════════════════════
  group('B. 야간 시급제 E2E (22:00~06:00, break=60, wage=12000)', () {

    // 야간 출퇴근 반올림 헬퍼 (계약 22:00~06:00, 퇴근은 다음날)
    String _nightIn(int h, int m, {AttendanceRules rules = _defaultRules}) {
      final contractStart = DateTime(_date.year, _date.month, _date.day, 22, 0);
      // 22 이전 시각은 같은 날, 0~21은 다음날로 처리
      final isNextDay = h < 12;
      final punchDate = isNextDay
          ? _date.add(const Duration(days: 1))
          : _date;
      final punchAt = DateTime(punchDate.year, punchDate.month, punchDate.day, h, m);
      final offset = punchAt.difference(contractStart).inMinutes;
      return processCheckin(
        offsetMinutes: offset,
        referenceAt: contractStart,
        rules: rules,
      ).rounded;
    }

    String _nightOut(int h, int m, {AttendanceRules rules = _defaultRules}) {
      final contractEnd = contractEndAt(_date, '22:00', '06:00');
      final punchAt = DateTime(
        contractEnd.year, contractEnd.month, contractEnd.day, h, m);
      final offset = punchAt.difference(contractEnd).inMinutes;
      return processCheckout(
        offsetMinutes: offset,
        referenceAt: contractEnd,
        rules: rules,
      ).rounded;
    }

    WageDetailModel _nightCalc({
      required String actualStart,
      required String actualEnd,
      bool night = true,
      int add = 0,
    }) =>
        WageCalculator.calculate(
          wageType: 'hourly',
          baseWage: _hourlyWage,
          workDate: _date,
          scheduledStart: '22:00',
          scheduledEnd: '06:00',
          actualStart: actualStart,
          actualEnd: actualEnd,
          breakMinutes: 60,
          nightAllowanceApplied: night,
          additionalAmount: add,
        );

    // ── B01 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-B01: 야간 정시 출퇴근 → workMin=420, night=420, total=126000', () {
      final ci = _nightIn(22, 0);
      final co = _nightOut(6, 0);
      expect(ci, '22:00');
      expect(co, '06:00');

      final r = _nightCalc(actualStart: ci, actualEnd: co);
      // actualMinutes=480(22~06), workMin=420(480-60)
      // rawNight=480, dayPortion=0, breakInNight=60, nightMin=420
      expect(r.actualMinutes,  480);
      expect(r.workMinutes,    420);
      expect(r.overtimeMinutes, 0);
      expect(r.nightMinutes,   420);
      expect(r.baseAmount,     84000);  // 420 × 12000 / 60
      expect(r.nightAmount,    42000);  // 420 × 12000 × 0.5 / 60
      expect(r.totalAmount,    126000);
    });

    // ── B02 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-B02: 20분 지각 → 30분 반올림 (22:30) → workMin=390, night=390', () {
      // 펀치: 22:20 → offset=20>5, ceil(20/30)*30=30 → 22:30
      final ci = _nightIn(22, 20);
      expect(ci, '22:30');

      final r = _nightCalc(actualStart: ci, actualEnd: '06:00');
      // actualMinutes=450(22:30~06:00), workMin=390
      // rawNight=450, dayPortion=0, breakInNight=60, nightMin=390
      expect(r.workMinutes,  390);
      expect(r.nightMinutes, 390);
      expect(r.baseAmount,   78000); // 390 × 12000 / 60
      expect(r.nightAmount,  39000); // 390 × 12000 × 0.5 / 60
      expect(r.totalAmount,  117000);
    });

    // ── B03 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-B03: 31분 조출 (21:29→21:30) → workMin=450, night=450, total=135000', () {
      // 펀치: 21:29 → offset=-31 < -earlyWindow(-30)
      // earlyArrival: (-31~/30)*30 = (-1)*30=-30 → 21:30
      final ci = _nightIn(21, 29);
      expect(ci, '21:30');

      final r = _nightCalc(actualStart: ci, actualEnd: '06:00');
      // actualMinutes=510(21:30~06:00), workMin=450
      // rawNight=480(22:00~06:00), dayPortion=30, breakInNight=30, nightMin=450
      expect(r.actualMinutes,   510);
      expect(r.workMinutes,     450);
      expect(r.nightMinutes,    450);
      expect(r.earlyArrivalMinutes, 30); // schedStart=22:00, actualStart=21:30
      expect(r.baseAmount,      90000);
      expect(r.nightAmount,     45000);
      expect(r.totalAmount,     135000);
    });

    // ── B04 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-B04: 35분 연장 → 30분 반올림 (06:35→06:30) → workMin=450, night=450', () {
      // 펀치: 06:35 → offset=35>30, (35~/10)*10=30 → 06:30
      final co = _nightOut(6, 35);
      expect(co, '06:30');

      final r = _nightCalc(actualStart: '22:00', actualEnd: co);
      // actualMinutes=510(22:00~06:30), workMin=450, OT=0(450<480)
      // rawNight=480, dayPortion=30, breakInNight=30, nightMin=450
      expect(r.workMinutes,     450);
      expect(r.overtimeMinutes, 0);
      expect(r.nightMinutes,    450);
      expect(r.baseAmount,      90000);
      expect(r.nightAmount,     45000);
      expect(r.totalAmount,     135000);
    });

    // ── B05 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-B05: 야간 OT 발생 (22:00~08:00, 10h, break=60) → OT=60, night=480', () {
      // actualStart='22:00', actualEnd='08:00', break=60
      // actualMinutes=600, workMin=540, OT=60
      // rawNight=480, dayPortion=120, breakInNight=max(0,60-120)=0, nightMin=480
      final r = _nightCalc(actualStart: '22:00', actualEnd: '08:00');
      expect(r.workMinutes,     540);
      expect(r.overtimeMinutes, 60);
      expect(r.nightMinutes,    480);
      expect(r.baseAmount,      96000);  // 480 × 12000 / 60
      expect(r.overtimeAmount,  18000);  // 60 × 12000 × 1.5 / 60
      expect(r.nightAmount,     48000);  // 480 × 12000 × 0.5 / 60
      expect(r.totalAmount,     162000);
    });

    // ── B06 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-B06: 5분 지각 유예 (22:05→22:00) → 정시 처리 → B01과 동일 결과', () {
      // 펀치: 22:05 → offset=5=lateGrace → onTime → 22:00
      final ci = _nightIn(22, 5);
      expect(ci, '22:00', reason: 'offset=5 ≤ lateGrace(5) → 정시 처리');

      final r = _nightCalc(actualStart: ci, actualEnd: '06:00');
      expect(r.workMinutes,  420);
      expect(r.nightMinutes, 420);
      expect(r.totalAmount,  126000);
    });

    // ── B07 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-B07: lateWindow 이내 초과 퇴근 (06:25→06:00) → 정시 처리', () {
      // 펀치: 06:25 → offset=25 ≤ lateWindow(30) → onTimeOut → 06:00
      final co = _nightOut(6, 25);
      expect(co, '06:00', reason: 'lateWindow(30) 이내 → 정시');

      final r = _nightCalc(actualStart: '22:00', actualEnd: co);
      expect(r.workMinutes,  420);
      expect(r.nightMinutes, 420);
      expect(r.totalAmount,  126000);
    });

    // ── B08 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-B08: 야간수당 미적용(nightAllowanceApplied=false) → nightAmount=0', () {
      final r = _nightCalc(
          actualStart: '22:00', actualEnd: '06:00', night: false);
      expect(r.workMinutes,  420);
      expect(r.nightMinutes, isNonNegative); // 분은 계산되지만
      expect(r.nightAmount,  0,
          reason: 'nightAllowanceApplied=false → 야간수당 미지급');
      expect(r.totalAmount,  84000); // base만
    });
  });

  // ════════════════════════════════════════════════════════════
  // C. 일급제 E2E — 08:00~17:00, break=60, daily=100000
  //    scheduledWorkMin = 540-60 = 480
  //    rawOrdinary = (100000/480*60).round() = 12500
  //    supplementWage = max(12500, 10320) = 12500
  // ════════════════════════════════════════════════════════════
  group('C. 일급제 E2E (08:00~17:00, break=60, daily=100000)', () {

    // ── C01 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-C01: 정시 출퇴근 → 일급 전액 100000', () {
      final ci = _roundedCheckIn(8, 0,
          contractStartHour: 8, contractStartMin: 0);
      final co = _roundedCheckOut(17, 0,
          contractStartHour: 8, contractEndHour: 17);
      expect(ci, '08:00');
      expect(co, '17:00');

      final r = _calcDaily(actualStart: ci, actualEnd: co);
      expect(r.workMinutes,    480);
      expect(r.overtimeMinutes, 0);
      expect(r.baseAmount,     100000);
      expect(r.totalAmount,    100000);
    });

    // ── C02 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-C02: 7분 지각 → 08:30 처리 → 비율 93750', () {
      // 펀치: 08:07 → offset=7>5, ceil(7/30)*30=30 → 08:30
      final ci = _roundedCheckIn(8, 7,
          contractStartHour: 8, contractStartMin: 0);
      expect(ci, '08:30');

      final r = _calcDaily(actualStart: ci, actualEnd: '17:00');
      // workMin = 510-60 = 450, 450<480 → base=(100000*450/480).round()
      expect(r.workMinutes,    450);
      expect(r.baseAmount,     93750); // (100000×450/480).round()
      expect(r.overtimeMinutes, 0);
      expect(r.totalAmount,    93750);
    });

    // ── C03 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-C03: 30분 연장(17:35→17:30) → OT 1.5배, total=109375', () {
      // 펀치: 17:35 → offset=35>30, (35~/10)*10=30 → 17:30
      final co = _roundedCheckOut(17, 35,
          contractStartHour: 8, contractEndHour: 17);
      expect(co, '17:30');

      final r = _calcDaily(actualStart: '08:00', actualEnd: co);
      // workMin=510, OT=30, workMin>480 → 1.5배
      // over8=30, within8=0, amount15x=(30×12500×1.5/60)=9375
      expect(r.workMinutes,     510);
      expect(r.overtimeMinutes, 30);
      expect(r.baseAmount,      100000);
      expect(r.overtimeAmount,  9375);
      expect(r.totalAmount,     109375);
    });

    // ── C04 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-C04: 조출(07:25→07:30) + 일급 전액 → OT 1.5배', () {
      // 펀치: 07:25 → offset=07:25-08:00=-35 < -30 → earlyArrival: -30 → 07:30
      final ci = _roundedCheckIn(7, 25,
          contractStartHour: 8, contractStartMin: 0);
      expect(ci, '07:30');

      final r = _calcDaily(actualStart: ci, actualEnd: '17:00');
      // workMin=570-60=510, OT=30, earlyArrivalMin=30
      // workMin(510)>480 → over8=30, within8=0
      // amount15x=(30×12500×1.5/60)=9375
      expect(r.workMinutes,        510);
      expect(r.overtimeMinutes,    30);
      expect(r.earlyArrivalMinutes, 30);
      expect(r.baseAmount,         100000);
      expect(r.overtimeAmount,     9375);
      expect(r.totalAmount,        109375);
    });

    // ── C05 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-C05: 단시간 shift OT 1배 (09:00~14:00, daily=50000, OT=30분)', () {
      // scheduled 09:00~14:00, break=0, daily=50000
      // scheduledWorkMin=300, rawOrdinary=10000 < minimumWage(10320) → supp=10320
      // punch out: 14:35 → offset=35>30, (35~/10)*10=30 → 14:30
      final co = _roundedCheckOut(14, 35,
          contractStartHour: 9, contractEndHour: 14);
      expect(co, '14:30');

      final r = _calcDaily(
        actualStart: '09:00',
        actualEnd: co,
        scheduledStart: '09:00',
        scheduledEnd: '14:00',
        breakMinutes: 0,
        wage: 50000,
      );
      // workMin=330, 330>scheduledWorkMin(300) → base=50000
      // OT=30, workMin(330)<=480 → 1배: 30×10320/60=5160
      expect(r.workMinutes,     330);
      expect(r.overtimeMinutes, 30);
      expect(r.baseAmount,      50000);
      expect(r.overtimeAmount,  5160);
      expect(r.totalAmount,     55160);
    });

    // ── C06 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-C06: 대형 지각(08:00→11:30) → 비율 56250', () {
      // 펀치: 11:01 → offset=181>5, ceil(181/30)*30=210 → 08:00+210=11:30
      final ci = _roundedCheckIn(11, 1,
          contractStartHour: 8, contractStartMin: 0);
      expect(ci, '11:30', reason: 'ceil(181/30)*30=210 → 11:30');

      final r = _calcDaily(actualStart: ci, actualEnd: '17:00');
      // actualMinutes=330, workMin=270
      // 270<480 → base=(100000×270/480).round()=56250
      expect(r.workMinutes, 270);
      expect(r.baseAmount,  56250);
      expect(r.totalAmount, 56250);
    });

    // ── C07 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-C07: 35분 조퇴 → 60분 반올림 (16:25→16:00) → 비율 87500', () {
      // 펀치: 16:25 → offset=-35, earlyDiff=35, ceil(35/30)*30=60 → 16:00
      final co = _roundedCheckOut(16, 25,
          contractStartHour: 8, contractEndHour: 17);
      expect(co, '16:00');

      final r = _calcDaily(actualStart: '08:00', actualEnd: co);
      // workMin=420, 420<480 → base=(100000×420/480).round()=87500
      expect(r.workMinutes, 420);
      expect(r.baseAmount,  87500);
      expect(r.totalAmount, 87500);
    });

    // ── C08 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-C08: 지각+연장 복합(08:07→08:30, 17:35→17:30) → 정확히 480분 → 일급 전액', () {
      // 지각: 08:07 → 08:30 (+30분)
      // 연장: 17:35 → 17:30 (+30분)
      // actualMinutes = 08:30~17:30 = 540, workMin = 480
      // workMin(480) == scheduledWorkMin(480) → base = 100000
      final ci = _roundedCheckIn(8, 7, contractStartHour: 8);
      final co = _roundedCheckOut(17, 35, contractStartHour: 8, contractEndHour: 17);
      expect(ci, '08:30');
      expect(co, '17:30');

      final r = _calcDaily(actualStart: ci, actualEnd: co);
      expect(r.actualMinutes,   540);
      expect(r.workMinutes,     480);
      expect(r.overtimeMinutes, 0);
      expect(r.baseAmount,      100000);
      expect(r.totalAmount,     100000);
    });
  });

  // ════════════════════════════════════════════════════════════
  // D. 경계값 시나리오
  // ════════════════════════════════════════════════════════════
  group('D. 경계값 시나리오', () {

    // ── D01 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-D01: breakMinutes > actualMinutes → workMin=0 (안전장치)', () {
      // actualMinutes=30, break=60 → (30-60).clamp(0,9999)=0
      final r = _calcHourly(
        actualStart: '09:00',
        actualEnd: '09:30',
        breakMinutes: 60,
      );
      expect(r.actualMinutes, 30);
      expect(r.workMinutes,   0,
          reason: 'breakMinutes(60) > actualMinutes(30) → 음수 방지 clamp');
      expect(r.baseAmount,    0);
      expect(r.totalAmount,   0);
    });

    // ── D02 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-D02: 자정 근무 23:00~01:00 → actualMinutes=120, nightMin=120', () {
      // _calculateMinutesBetween: s=1380, e0=60, e<s→e=1500 → 120분
      // nightMinutes: overlap(1320,1440)=60 + overlap(1440,1800)=60 = 120
      final r = _calcHourly(
        actualStart: '23:00',
        actualEnd: '01:00',
        scheduledStart: '23:00',
        scheduledEnd: '01:00',
        breakMinutes: 0,
      );
      expect(r.actualMinutes, 120);
      expect(r.workMinutes,   120);
      expect(r.nightMinutes,  120, reason: '23:00~01:00 전구간 야간 시간대');
      expect(r.baseAmount,    24000); // 120 × 12000 / 60
      expect(r.nightAmount,   12000); // 120 × 12000 × 0.5 / 60
      expect(r.totalAmount,   36000);
    });

    // ── D03 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-D03: 조출+연장 복합 (08:29→08:30, 19:05→19:00) → OT=90, total=123000', () {
      final ci = _roundedCheckIn(8, 29);
      final co = _roundedCheckOut(19, 5);
      expect(ci, '08:30');
      expect(co, '19:00');

      final r = _calcHourly(actualStart: ci, actualEnd: co);
      // actualMinutes=630(08:30~19:00), workMin=570, OT=90
      expect(r.actualMinutes,    630);
      expect(r.workMinutes,      570);
      expect(r.overtimeMinutes,  90);
      expect(r.earlyArrivalMinutes, 30);
      expect(r.baseAmount,       96000);  // 480 × 12000 / 60
      expect(r.overtimeAmount,   27000);  // 90 × 12000 × 1.5 / 60
      expect(r.totalAmount,      123000);
    });

    // ── D04 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-D04: 지각+조퇴 복합 (09:07→09:30, 17:25→17:00) → workMin=390, total=78000', () {
      final ci = _roundedCheckIn(9, 7);
      final co = _roundedCheckOut(17, 25);
      expect(ci, '09:30');
      expect(co, '17:00');

      final r = _calcHourly(actualStart: ci, actualEnd: co);
      // actualMinutes=450(09:30~17:00), workMin=390
      expect(r.actualMinutes, 450);
      expect(r.workMinutes,   390);
      expect(r.baseAmount,    78000); // 390 × 12000 / 60
      expect(r.totalAmount,   78000);
    });

    // ── D05 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-D05: lateWindow 경계 정확히 = 30 → 정시 퇴근 처리', () {
      // 18:30, offset=30, Is 30 > lateWindow(30)? 아니오(strict >) → onTimeOut → 18:00
      final co = _roundedCheckOut(18, 30);
      expect(co, '18:00', reason: 'offset=30 NOT > lateWindow(30) → 정시');

      final r = _calcHourly(actualStart: '09:00', actualEnd: co);
      expect(r.workMinutes, 480);
      expect(r.totalAmount, 96000);
    });

    // ── D06 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-D06: lateWindow+1 → 연장 시작 (18:31→18:30) → OT=30', () {
      // 18:31, offset=31 > 30 → OT: (31~/10)*10=30 → 18:30
      final co = _roundedCheckOut(18, 31);
      expect(co, '18:30', reason: 'offset=31 > lateWindow(30) → 첫 OT 발생');

      final r = _calcHourly(actualStart: '09:00', actualEnd: co);
      expect(r.workMinutes,     510);
      expect(r.overtimeMinutes, 30);
      expect(r.overtimeAmount,  9000);
      expect(r.totalAmount,     105000);
    });

    // ── D07 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-D07: earlyWindow 경계 정확히 = 30 → 정시 (08:30→09:00)', () {
      // 08:30, offset=-30. Is -30 < -earlyWindow(-30)? 아니오(strict <) → onTime → 09:00
      final ci = _roundedCheckIn(8, 30);
      expect(ci, '09:00',
          reason: 'offset=-30 NOT < -earlyWindow(-30) → 정시 처리');

      final r = _calcHourly(actualStart: ci, actualEnd: '18:00');
      expect(r.workMinutes, 480);
      expect(r.totalAmount, 96000);
    });

    // ── D08 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-D08: 일급제 OT 8h 초과 분기 (08:00~14:00, OT=150분) → total=88380', () {
      // scheduled: 08:00~14:00, break=0, daily=60000
      // scheduledWorkMin=360, rawOrdinary=10000 < minimumWage(10320) → supp=10320
      // punch out: 16:35 → offset=155>30, (155~/10)*10=150 → 14:00+150=16:30
      final co = _roundedCheckOut(16, 35,
          contractStartHour: 8, contractEndHour: 14);
      expect(co, '16:30', reason: 'floor(155/10)*10=150 → 14:00+150=16:30');

      final r = _calcDaily(
        actualStart: '08:00',
        actualEnd: co,
        scheduledStart: '08:00',
        scheduledEnd: '14:00',
        breakMinutes: 0,
        wage: 60000,
      );
      // workMin=510, OT=150, workMin(510)>480 → 8h 초과분 분기
      // over8=30, within8=120
      // amount1x=(120×10320/60).round()=20640
      // amount15x=(30×10320×1.5/60).round()=7740
      expect(r.workMinutes,     510);
      expect(r.overtimeMinutes, 150);
      expect(r.baseAmount,      60000);
      expect(r.overtimeAmount,  28380); // 20640 + 7740
      expect(r.totalAmount,     88380);
    });
  });

  // ════════════════════════════════════════════════════════════
  // E. 커스텀 AttendanceRules + 급여 조합
  // ════════════════════════════════════════════════════════════
  group('E. 커스텀 AttendanceRules 조합', () {

    // ── E01 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-E01: lateUnit=15, lateGrace=0 → 1분 지각도 15분 반올림', () {
      const rules = AttendanceRules(
        earlyWindow: 30, earlyArrivalUnit: 30,
        lateGrace: 0, lateUnit: 15,
        lateWindow: 30, overtimeUnit: 10, earlyLeaveUnit: 30,
      );
      // 09:01 → offset=1>0, ceil(1/15)*15=15 → 09:15
      final ci = _roundedCheckIn(9, 1, rules: rules);
      expect(ci, '09:15', reason: 'lateGrace=0, lateUnit=15 → 1분도 15분으로 올림');

      final r = _calcHourly(actualStart: ci, actualEnd: '18:00');
      // actualMinutes=525, workMin=465
      expect(r.workMinutes, 465);
      expect(r.baseAmount,  93000); // 465 × 12000 / 60
      expect(r.totalAmount, 93000);
    });

    // ── E02 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-E02: overtimeUnit=5, lateWindow=5 → 6분 초과부터 5분 단위 OT', () {
      const rules = AttendanceRules(
        earlyWindow: 30, earlyArrivalUnit: 30,
        lateGrace: 5, lateUnit: 30,
        lateWindow: 5, overtimeUnit: 5, earlyLeaveUnit: 30,
      );
      // 18:08 → offset=8>lateWindow(5), (8~/5)*5=5 → 18:05
      final co = _roundedCheckOut(18, 8, rules: rules);
      expect(co, '18:05', reason: 'floor(8/5)*5=5 → contractEnd+5=18:05');

      final r = _calcHourly(actualStart: '09:00', actualEnd: co);
      // actualMinutes=545, workMin=485, OT=5
      expect(r.workMinutes,     485);
      expect(r.overtimeMinutes, 5);
      expect(r.overtimeAmount,  1500); // 5 × 12000 × 1.5 / 60
      expect(r.totalAmount,     97500);
    });

    // ── E03 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-E03: earlyWindow=60 → 30분 조기 도착도 정시 처리', () {
      const rules = AttendanceRules(
        earlyWindow: 60, earlyArrivalUnit: 30,
        lateGrace: 5, lateUnit: 30,
        lateWindow: 30, overtimeUnit: 10, earlyLeaveUnit: 30,
      );
      // 08:30 → offset=-30. Is -30 < -earlyWindow(-60)? NO → onTime → 09:00
      final ci = _roundedCheckIn(8, 30, rules: rules);
      expect(ci, '09:00',
          reason: 'earlyWindow=60: offset=-30 NOT < -60 → 정시');

      final r = _calcHourly(actualStart: ci, actualEnd: '18:00');
      expect(r.workMinutes, 480);
      expect(r.totalAmount, 96000);
    });

    // ── E04 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-E04: earlyLeaveUnit=15 → 10분 조퇴도 15분 반올림', () {
      const rules = AttendanceRules(
        earlyWindow: 30, earlyArrivalUnit: 30,
        lateGrace: 5, lateUnit: 30,
        lateWindow: 30, overtimeUnit: 10, earlyLeaveUnit: 15,
      );
      // 17:50 → offset=-10, earlyDiff=10, ceil(10/15)*15=15, rounded=-15 → 17:45
      final co = _roundedCheckOut(17, 50, rules: rules);
      expect(co, '17:45', reason: 'earlyLeaveUnit=15: ceil(10/15)*15=15 → -15 → 17:45');

      final r = _calcHourly(actualStart: '09:00', actualEnd: co);
      // actualMinutes=525, workMin=465
      expect(r.workMinutes, 465);
      expect(r.baseAmount,  93000);
      expect(r.totalAmount, 93000);
    });

    // ── E05 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-E05: lateUnit=15 + 일급제 → 3분 지각도 15분 처리', () {
      const rules = AttendanceRules(
        earlyWindow: 30, earlyArrivalUnit: 30,
        lateGrace: 0, lateUnit: 15,
        lateWindow: 30, overtimeUnit: 10, earlyLeaveUnit: 30,
      );
      // contracted 08:00, 08:03 → offset=3>0, ceil(3/15)*15=15 → 08:15
      final ci = _roundedCheckIn(8, 3,
          contractStartHour: 8, rules: rules);
      expect(ci, '08:15');

      final r = _calcDaily(actualStart: ci, actualEnd: '17:00');
      // actualMinutes=525, workMin=465, 465<480 → 비율
      // base=(100000×465/480).round()=96875
      expect(r.workMinutes, 465);
      expect(r.baseAmount,  96875);
      expect(r.totalAmount, 96875);
    });

    // ── E06 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-E06: lateGrace=10 → 09:10 지각도 정시 처리', () {
      const rules = AttendanceRules(
        earlyWindow: 30, earlyArrivalUnit: 30,
        lateGrace: 10, lateUnit: 30,
        lateWindow: 30, overtimeUnit: 10, earlyLeaveUnit: 30,
      );
      // 09:10 → offset=10 ≤ lateGrace(10) → lateGrace → 09:00
      final ci = _roundedCheckIn(9, 10, rules: rules);
      expect(ci, '09:00', reason: 'lateGrace=10: 10분도 유예 범위 내');

      final r = _calcHourly(actualStart: ci, actualEnd: '18:00');
      expect(r.workMinutes, 480);
      expect(r.totalAmount, 96000);
    });

    // ── E07 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-E07: earlyArrivalUnit=15 → 55분 조출(08:05→08:15), OT=45분', () {
      // earlyWindow=30이므로 -55 < -30 → earlyArrival
      // (-55~/15)*15 = (-3)*15 = -45 → 09:00-45=08:15
      const rules = AttendanceRules(
        earlyWindow: 30, earlyArrivalUnit: 15,
        lateGrace: 5, lateUnit: 30,
        lateWindow: 30, overtimeUnit: 10, earlyLeaveUnit: 30,
      );
      final ci = _roundedCheckIn(8, 5, rules: rules);
      expect(ci, '08:15',
          reason: '(-55~/15)*15=(-3)*15=-45 → 09:00-45=08:15');

      final r = _calcHourly(actualStart: ci, actualEnd: '18:00');
      // actualMinutes=585, workMin=525, OT=45
      expect(r.workMinutes,      525);
      expect(r.overtimeMinutes,  45);
      expect(r.earlyArrivalMinutes, 45); // schedStart(540) - actualStart(495) = 45
      expect(r.overtimeAmount,   13500); // 45 × 12000 × 1.5 / 60
      expect(r.totalAmount,      109500);
    });
  });

  // ════════════════════════════════════════════════════════════
  // F. 세전 급여 정합성
  //    totalAmount = baseAmount + overtimeAmount + nightAmount + additionalAmount
  //    deductionAmount는 WageCalculator.calculate() 결과에 포함 안 됨
  // ════════════════════════════════════════════════════════════
  group('F. 세전 급여 정합성', () {

    // ── F01 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-F01: additionalAmount=50000 → total=146000', () {
      final r = _calcHourly(
        actualStart: '09:00',
        actualEnd: '18:00',
        additionalAmount: 50000,
      );
      expect(r.baseAmount,       96000);
      expect(r.overtimeAmount,   0);
      expect(r.nightAmount,      0);
      expect(r.additionalAmount, 50000);
      // total = 96000 + 0 + 0 + 50000
      expect(r.totalAmount,      146000);
    });

    // ── F02 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-F02: 야간 + additionalAmount 조합 → total=136000', () {
      // 22:00~06:00, break=60, wage=12000, add=10000
      // workMin=420, base=84000, night=42000, add=10000
      final r = WageCalculator.calculate(
        wageType: 'hourly',
        baseWage: _hourlyWage,
        workDate: _date,
        scheduledStart: '22:00',
        scheduledEnd: '06:00',
        actualStart: '22:00',
        actualEnd: '06:00',
        breakMinutes: 60,
        nightAllowanceApplied: true,
        additionalAmount: 10000,
      );
      expect(r.workMinutes,     420);
      expect(r.baseAmount,      84000);
      expect(r.nightAmount,     42000);
      expect(r.additionalAmount, 10000);
      expect(r.totalAmount,     136000);
    });

    // ── F03 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-F03: deductionAmount는 calculate() 결과 totalAmount에 미포함', () {
      // WageCalculator.calculate()는 deductionAmount 파라미터 자체가 없음
      // → 반환된 WageDetailModel의 deductionAmount=0(기본), total은 공제 전 금액
      final r = _calcHourly(
        actualStart: '09:00',
        actualEnd: '18:00',
      );
      expect(r.deductionAmount, 0,
          reason: 'calculate()는 deductionAmount를 계산하지 않음 — UI에서 별도 처리');
      expect(r.totalAmount,     96000,
          reason: 'totalAmount는 세전 합계 (공제 전)');
    });

    // ── F04 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-F04: workMinutes = (actualMin - break).clamp(0,9999) 하한 검증', () {
      // actual=20min, break=30 → (20-30).clamp=0
      final r = _calcHourly(
        actualStart: '09:00',
        actualEnd: '09:20',
        breakMinutes: 30,
      );
      expect(r.actualMinutes, 20);
      expect(r.workMinutes,   0,
          reason: 'clamp(0,9999) 하한: 음수 근무시간 방지');
      expect(r.totalAmount,   0);
    });

    // ── F05 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-F05: additionalAmount만 있는 경우 → total=additionalAmount', () {
      // 0분 근무(동일 시각), add=30000
      final r = _calcHourly(
        actualStart: '09:00',
        actualEnd: '09:00',
        breakMinutes: 0,
        additionalAmount: 30000,
      );
      expect(r.actualMinutes,    0);
      expect(r.workMinutes,      0);
      expect(r.baseAmount,       0);
      expect(r.additionalAmount, 30000);
      expect(r.totalAmount,      30000,
          reason: 'total = 0 + 0 + 0 + additionalAmount');
    });

    // ── F06 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-F06: nightAllowanceApplied=false → nightAmount=0, totalAmount=base만', () {
      final r = WageCalculator.calculate(
        wageType: 'hourly',
        baseWage: _hourlyWage,
        workDate: _date,
        scheduledStart: '22:00',
        scheduledEnd: '06:00',
        actualStart: '22:00',
        actualEnd: '06:00',
        breakMinutes: 60,
        nightAllowanceApplied: false,
      );
      expect(r.workMinutes,  420);
      expect(r.nightAmount,  0);
      expect(r.baseAmount,   84000);
      expect(r.totalAmount,  84000);
    });

    // ── F07 ──────────────────────────────────────────────────
    test('SCENARIO-E2E-F07: OT+야간+추가수당 전체 합산 (22:00~07:30, break=60, add=20000)', () {
      // actualMinutes=570, workMin=510, OT=30
      // rawNight=480, dayPortion=90, breakInNight=max(0,60-90)=0, nightMin=480
      // base=(480×12000/60)=96000, OTAmt=(30×12000×1.5/60)=9000
      // night=(480×12000×0.5/60)=48000, add=20000
      // total=96000+9000+48000+20000=173000
      final r = WageCalculator.calculate(
        wageType: 'hourly',
        baseWage: _hourlyWage,
        workDate: _date,
        scheduledStart: '22:00',
        scheduledEnd: '06:00',
        actualStart: '22:00',
        actualEnd: '07:30',
        breakMinutes: 60,
        nightAllowanceApplied: true,
        additionalAmount: 20000,
      );
      expect(r.workMinutes,      510);
      expect(r.overtimeMinutes,  30);
      expect(r.nightMinutes,     480);
      expect(r.baseAmount,       96000);
      expect(r.overtimeAmount,   9000);
      expect(r.nightAmount,      48000);
      expect(r.additionalAmount, 20000);
      // 정합성: totalAmount == base + OT + night + additional
      expect(r.totalAmount,
          r.baseAmount + r.overtimeAmount + r.nightAmount + r.additionalAmount,
          reason: 'totalAmount 정합성: base+OT+night+additional');
      expect(r.totalAmount, 173000);
    });
  });

  // ════════════════════════════════════════════════════════════
  // 공통 불변식 — 모든 케이스에 적용되는 정합성 규칙
  // ════════════════════════════════════════════════════════════
  group('Z. 공통 불변식 검증', () {

    test('SCENARIO-E2E-Z01: totalAmount = base+OT+night+additional 항등식 (시급제 복합)', () {
      final r = _calcHourly(
        actualStart: '08:30',
        actualEnd: '19:00',
        additionalAmount: 15000,
      );
      // workMin=570, OT=90, night=0
      expect(r.totalAmount,
          r.baseAmount + r.overtimeAmount + r.nightAmount + r.additionalAmount,
          reason: '항등식: total = base + OT + night + additional');
    });

    test('SCENARIO-E2E-Z02: totalAmount 항등식 (일급제 OT 포함)', () {
      final r = _calcDaily(
        actualStart: '07:30',
        actualEnd: '17:30',
        additionalAmount: 5000,
      );
      expect(r.totalAmount,
          r.baseAmount + r.overtimeAmount + r.nightAmount + r.additionalAmount);
    });

    test('SCENARIO-E2E-Z03: workMinutes >= 0 (음수 불가)', () {
      // 극단적 짧은 근무
      for (final breakMin in [0, 30, 60, 120]) {
        final r = _calcHourly(
          actualStart: '09:00',
          actualEnd: '09:30',
          breakMinutes: breakMin,
        );
        expect(r.workMinutes, greaterThanOrEqualTo(0),
            reason: 'break=$breakMin → workMin 음수 불가');
      }
    });
  });
}
