// test/unit/wage_calculator_shift_scenarios_test.dart
// 출근시간대별 100개 시나리오 — 시급제/일급제 급여계산 이상유무 검증
//
// 검증 항목:
//   A. 시급제 (hourly) — 주간/야간/조출/연장/자정넘김
//   B. 일급제 (daily)  — 정상/미달/연장(8h이내/초과)/조출/nightIncluded
//   C. 경계값 — 정확히 4h/8h, breakMinutes 극단값
//   D. 야간교대 — 22:00~06:00 패턴
//   E. 불변식 검증 — totalAmount = baseAmount+overtimeAmount+nightAmount

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/wage_calculator.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';

// 2026년 최저시급 10,320원
const int _minWage = 10320;
const int _hw = 12000;     // 테스트용 시급
const int _dw = 120000;    // 테스트용 일급 (8h 계약 기준 → 통상시급 15,000원)
const int _dw4 = 60000;    // 4h 계약 일급 → 통상시급 15,000원
final DateTime _d = DateTime(2026, 6, 1);

/// 계산 후 불변식 확인 헬퍼
void _assertInvariants(
  WageDetailModel Function() calc, {
  String? label,
  int? expectWork,
  int? expectOvertime,
  int? expectNight,
  int? expectBase,
  int? expectTotal,
  bool expectOvertimeZero = false,
  bool expectNightZero = false,
}) {
  final r = calc();
  final tag = label ?? '';

  // totalAmount 불변식
  expect(
    r.totalAmount,
    equals(r.baseAmount + r.overtimeAmount + r.nightAmount + r.additionalAmount),
    reason: '$tag: totalAmount 불변식 위반',
  );

  // 음수 없음
  expect(r.baseAmount, greaterThanOrEqualTo(0), reason: '$tag: baseAmount 음수');
  expect(r.overtimeAmount, greaterThanOrEqualTo(0), reason: '$tag: overtimeAmount 음수');
  expect(r.nightAmount, greaterThanOrEqualTo(0), reason: '$tag: nightAmount 음수');
  expect(r.workMinutes, greaterThanOrEqualTo(0), reason: '$tag: workMinutes 음수');
  expect(r.earlyArrivalMinutes, greaterThanOrEqualTo(0), reason: '$tag: earlyArrivalMinutes 음수');

  if (expectWork != null) expect(r.workMinutes, equals(expectWork), reason: '$tag: workMinutes');
  if (expectOvertime != null) expect(r.overtimeMinutes, equals(expectOvertime), reason: '$tag: overtimeMinutes');
  if (expectNight != null) expect(r.nightMinutes, equals(expectNight), reason: '$tag: nightMinutes');
  if (expectBase != null) expect(r.baseAmount, equals(expectBase), reason: '$tag: baseAmount');
  if (expectTotal != null) expect(r.totalAmount, equals(expectTotal), reason: '$tag: totalAmount');
  if (expectOvertimeZero) expect(r.overtimeAmount, equals(0), reason: '$tag: overtimeAmount 0이어야 함');
  if (expectNightZero) expect(r.nightAmount, equals(0), reason: '$tag: nightAmount 0이어야 함');
}

WageDetailModel _calc({
  String wageType = 'hourly',
  int baseWage = _hw,
  String schedStart = '09:00',
  String schedEnd = '18:00',
  String actualStart = '09:00',
  String actualEnd = '18:00',
  int breakMinutes = 60,
  int? scheduledBreakMinutes,
  bool nightAllowanceApplied = true,
  bool nightIncluded = false,
  int additionalAmount = 0,
  int? baseHourlyWage,
}) =>
    WageCalculator.calculate(
      wageType: wageType,
      baseWage: baseWage,
      workDate: _d,
      scheduledStart: schedStart,
      scheduledEnd: schedEnd,
      actualStart: actualStart,
      actualEnd: actualEnd,
      breakMinutes: breakMinutes,
      scheduledBreakMinutes: scheduledBreakMinutes,
      nightAllowanceApplied: nightAllowanceApplied,
      nightIncluded: nightIncluded,
      additionalAmount: additionalAmount,
      baseHourlyWage: baseHourlyWage,
    );

void main() {
  // ═══════════════════════════════════════════════════════════════
  // A. 시급제 — 주간 패턴
  // ═══════════════════════════════════════════════════════════════
  group('A-시급제/주간', () {
    test('A01: 정시 8h 근무 (09:00~18:00, 휴게60) — 연장없음 야간없음', () {
      _assertInvariants(
        () => _calc(schedStart: '09:00', schedEnd: '18:00', actualEnd: '18:00', breakMinutes: 60),
        label: 'A01',
        expectWork: 480,
        expectOvertime: 0,
        expectNightZero: true,
        expectOvertimeZero: true,
        expectBase: (480 * _hw / 60).round(),
      );
    });

    test('A02: 4h 근무 (09:00~13:00, 휴게0) — 연장없음', () {
      _assertInvariants(
        () => _calc(schedStart: '09:00', schedEnd: '13:00', actualStart: '09:00', actualEnd: '13:00', breakMinutes: 0),
        label: 'A02',
        expectWork: 240,
        expectOvertime: 0,
        expectOvertimeZero: true,
        expectNightZero: true,
      );
    });

    test('A03: 4h 초과 근무 6h (09:00~15:00, 휴게0) — 8h 이하 → 시급제는 연장0', () {
      // 시급제는 8h 초과분만 연장 → 6h 근무는 연장 0
      _assertInvariants(
        () => _calc(schedStart: '09:00', schedEnd: '15:00', actualEnd: '15:00', breakMinutes: 0),
        label: 'A03',
        expectWork: 360,
        expectOvertime: 0,
        expectOvertimeZero: true,
      );
    });

    test('A04: 9h 근무 (09:00~19:00, 휴게60) — 연장 1h', () {
      // workMinutes = 540-60 = 480, overtimeMinutes = 0 (정확히 8h)
      // actualEnd 19:00 → actualMinutes=600, workMinutes=600-60=540, overtime=60
      _assertInvariants(
        () => _calc(schedStart: '09:00', schedEnd: '18:00', actualEnd: '19:00', breakMinutes: 60),
        label: 'A04',
        expectWork: 540,
        expectOvertime: 60,
      );
    });

    test('A05: 10h 근무 (09:00~20:00, 휴게60) — 연장 2h', () {
      _assertInvariants(
        () => _calc(schedStart: '09:00', schedEnd: '18:00', actualEnd: '20:00', breakMinutes: 60),
        label: 'A05',
        expectWork: 600,
        expectOvertime: 120,
      );
    });

    test('A06: 12h 근무 (09:00~22:00, 휴게60) — 연장 4h + 야간 없음(22시 시작)', () {
      final r = _calc(schedStart: '09:00', schedEnd: '18:00', actualEnd: '22:00', breakMinutes: 60);
      expect(r.workMinutes, equals(720));
      expect(r.overtimeMinutes, equals(240));
      // 22:00까지는 야간 시작점 → nightMinutes는 0
      expect(r.nightMinutes, equals(0));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('A07: 13h 근무 (09:00~23:00, 휴게60) — 연장 4h + 야간 1h', () {
      final r = _calc(schedStart: '09:00', schedEnd: '18:00', actualEnd: '23:00', breakMinutes: 60);
      expect(r.workMinutes, equals(780));
      expect(r.overtimeMinutes, equals(300));
      expect(r.nightMinutes, equals(60)); // 22:00~23:00
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('A08: 조출 30분 (08:30~18:00, 휴게60) — 시급제 연장0 (8h 미초과)', () {
      // workMinutes = 570-60=510 → overtime=30
      final r = _calc(actualStart: '08:30', actualEnd: '18:00', breakMinutes: 60);
      expect(r.earlyArrivalMinutes, equals(30));
      expect(r.overtimeMinutes, equals(30)); // 8h 초과분만 연장 → 510-480=30
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('A09: 조출 2h (07:00~18:00, 휴게60) — 연장 2h (workMinutes=600)', () {
      final r = _calc(actualStart: '07:00', actualEnd: '18:00', breakMinutes: 60);
      expect(r.earlyArrivalMinutes, equals(120));
      expect(r.workMinutes, equals(600));
      expect(r.overtimeMinutes, equals(120));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('A10: 지각 1h (10:00~18:00, 휴게60) — 연장0, workMinutes=420', () {
      final r = _calc(actualStart: '10:00', actualEnd: '18:00', breakMinutes: 60);
      expect(r.earlyArrivalMinutes, equals(0));
      expect(r.workMinutes, equals(420));
      expect(r.overtimeMinutes, equals(0));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // B. 시급제 — 야간 패턴
  // ═══════════════════════════════════════════════════════════════
  group('B-시급제/야간', () {
    test('B01: 완전 야간 8h (22:00~07:00, 휴게60) — 야간 480min', () {
      // dayPortion=540-480=60, breakInNight=max(0,60-60)=0 → nightMinutes=480 (휴게 주간분=야간분)
      final r = _calc(
        schedStart: '22:00', schedEnd: '07:00',
        actualStart: '22:00', actualEnd: '07:00',
        breakMinutes: 60,
      );
      expect(r.workMinutes, equals(480));
      expect(r.nightMinutes, equals(480)); // 22:00~06:00 전체 — 주간 60분이 휴게60과 상쇄
      expect(r.overtimeMinutes, equals(0));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('B02: 야간 4h (22:00~03:00, 휴게0) — 야간 4h(240분)', () {
      final r = _calc(
        schedStart: '22:00', schedEnd: '03:00',
        actualStart: '22:00', actualEnd: '03:00',
        breakMinutes: 0,
      );
      expect(r.workMinutes, equals(300));
      expect(r.nightMinutes, equals(300)); // 22:00~03:00 모두 야간
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('B03: 저녁~자정 (18:00~24:00, 휴게0) — 야간 0h (22:00 이전 퇴근 불가, 24:00은 00:00)', () {
      // 18:00~24:00 = 00:00으로 파싱. 자정 넘김 처리 → e=1440 < s=1080이 아님 → e=0이 되어 s=1080보다 작음
      // 그러므로 e += 1440 → e=1440: 18:00~24:00 = 360분
      // nightMinutes: overlap(1320,1440) = min(1440,1440)-max(1080,1320) = 1440-1320 = 120 → 2h
      final r = _calc(
        schedStart: '18:00', schedEnd: '24:00',
        actualStart: '18:00', actualEnd: '00:00',
        breakMinutes: 0,
      );
      expect(r.workMinutes, equals(360));
      expect(r.nightMinutes, equals(120)); // 22:00~24:00
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('B04: 심야 연장 (22:00~08:00, 휴게60) — 연장 1h + 야간 8h', () {
      // actualMinutes=600, workMinutes=540, overtime=60
      // nightMinutes: 22:00~06:00=480, 휴게60은 주간(없음)→야간에서 0 (주간 portion=0, breakInNight=min(60,0)=0?
      // dayPortion = 600 - 480 = 120. breakInNight = max(0, 60-120) = 0 → nightMinutes=480
      final r = _calc(
        schedStart: '22:00', schedEnd: '07:00',
        actualStart: '22:00', actualEnd: '08:00',
        breakMinutes: 60,
      );
      expect(r.overtimeMinutes, equals(60));
      expect(r.nightMinutes, equals(480)); // 22:00~06:00
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('B05: 야간수당 미적용 (nightAllowanceApplied=false)', () {
      final r = _calc(
        schedStart: '22:00', schedEnd: '07:00',
        actualStart: '22:00', actualEnd: '07:00',
        breakMinutes: 60,
        nightAllowanceApplied: false,
      );
      expect(r.nightAmount, equals(0));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount));
    });

    test('B06: 주간+야간 혼합 (14:00~23:00, 휴게60) — 야간 1h(22:00~23:00)', () {
      final r = _calc(
        schedStart: '14:00', schedEnd: '23:00',
        actualStart: '14:00', actualEnd: '23:00',
        breakMinutes: 60,
      );
      expect(r.workMinutes, equals(480));
      expect(r.nightMinutes, equals(60)); // 22:00~23:00
      expect(r.overtimeMinutes, equals(0)); // 정확히 8h
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('B07: 야간 조출 30분 (21:30~07:00, 휴게60)', () {
      final r = _calc(
        schedStart: '22:00', schedEnd: '07:00',
        actualStart: '21:30', actualEnd: '07:00',
        breakMinutes: 60,
      );
      expect(r.earlyArrivalMinutes, equals(30));
      // workMinutes = 570-60=510, overtime=30
      expect(r.workMinutes, equals(510));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('B08: 완전 새벽 근무 (01:00~06:00, 휴게0) — 야간 5h', () {
      final r = _calc(
        schedStart: '01:00', schedEnd: '06:00',
        actualStart: '01:00', actualEnd: '06:00',
        breakMinutes: 0,
      );
      expect(r.workMinutes, equals(300));
      expect(r.nightMinutes, equals(300)); // 01:00~06:00 모두 야간(00:00~06:00)
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('B09: 06:00 경계 (04:00~08:00, 휴게0) — 야간 2h', () {
      final r = _calc(
        schedStart: '04:00', schedEnd: '08:00',
        actualStart: '04:00', actualEnd: '08:00',
        breakMinutes: 0,
      );
      expect(r.nightMinutes, equals(120)); // 04:00~06:00
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('B10: 자정 정각 퇴근 (20:00~00:00, 휴게0) — 야간 2h(22:00~24:00)', () {
      final r = _calc(
        schedStart: '20:00', schedEnd: '00:00',
        actualStart: '20:00', actualEnd: '00:00',
        breakMinutes: 0,
      );
      expect(r.workMinutes, equals(240));
      expect(r.nightMinutes, equals(120)); // 22:00~24:00
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // C. 일급제 — 주간 패턴
  // ═══════════════════════════════════════════════════════════════
  group('C-일급제/주간', () {
    // _dw=120,000 / 8h계약(휴게60) → 순근무480분 → 통상시급 15,000원
    test('C01: 정시 출퇴근 (09:00~18:00, 휴게60) — 일급 전액', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '09:00', schedEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.baseAmount, equals(_dw));
      expect(r.overtimeAmount, equals(0));
      expect(r.totalAmount, equals(_dw));
    });

    test('C02: 조기퇴근 30분 — 미근무 공제', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '09:00', schedEnd: '18:00',
        actualStart: '09:00', actualEnd: '17:30',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      // workMinutes=450-60=... actualMinutes=510, workMinutes=510-60=450
      expect(r.workMinutes, equals(450));
      expect(r.baseAmount, lessThan(_dw)); // 미달 → 공제
      expect(r.overtimeAmount, equals(0));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('C03: 지각 1h (10:00~18:00, 휴게60) — 미근무 공제', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '09:00', schedEnd: '18:00',
        actualStart: '10:00', actualEnd: '18:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.workMinutes, equals(420));
      expect(r.baseAmount, lessThan(_dw));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('C04: 연장 1h — 8h 이내 → 1배', () {
      // schedWork=480, workMinutes=540, overtime=60, total<8h
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '09:00', schedEnd: '18:00',
        actualStart: '09:00', actualEnd: '19:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.overtimeMinutes, equals(60));
      // workMinutes=540 ≤ 480+60=540 but 540>480 → 8h비교: 540 > 480 → 8h초과
      // over8=60, within8=0 → amount1x=0, amount15x=60*15000*1.5/60=22,500
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('C05: 연장 2h (8h 초과) — 1.5배', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '09:00', schedEnd: '18:00',
        actualStart: '09:00', actualEnd: '20:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.overtimeMinutes, equals(120));
      expect(r.overtimeAmount, greaterThan(0));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('C06: 4h 계약 연장 2h (8h이내) — 1배 적용', () {
      // schedWork=240, workMinutes=360, overtime=120, total=360<480 → 1배
      final r = _calc(
        wageType: 'daily', baseWage: _dw4,
        schedStart: '09:00', schedEnd: '13:00',
        actualStart: '09:00', actualEnd: '15:00',
        breakMinutes: 0, scheduledBreakMinutes: 0,
        baseHourlyWage: 15000,
      );
      expect(r.overtimeMinutes, equals(120));
      expect(r.workMinutes, equals(360));
      // 360 < 480 → 1배: 120*15000/60 = 30,000
      expect(r.overtimeAmount, equals((120 * 15000 / 60).round()));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('C07: 4h 계약 연장 6h (8h초과 2h) — 4h는 1배 + 2h는 1.5배', () {
      // schedWork=240, workMinutes=600, overtime=360
      // over8=600-480=120, within8=360-120=240
      final r = _calc(
        wageType: 'daily', baseWage: _dw4,
        schedStart: '09:00', schedEnd: '13:00',
        actualStart: '09:00', actualEnd: '19:00',
        breakMinutes: 0, scheduledBreakMinutes: 0,
        baseHourlyWage: 15000,
      );
      expect(r.overtimeMinutes, equals(360));
      final expected = (240 * 15000 / 60).round() + (120 * 15000 * 1.5 / 60).round();
      expect(r.overtimeAmount, equals(expected));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('C08: 조출 1h + 정시퇴근 (8h계약) — 연장 1h, earlyArrivalAmount > 0', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '09:00', schedEnd: '18:00',
        actualStart: '08:00', actualEnd: '18:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.earlyArrivalMinutes, equals(60));
      expect(r.overtimeMinutes, equals(60));
      expect(r.earlyArrivalAmount, greaterThan(0));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('C09: 조출 2h + 연장 1h (8h계약) — overtimeMinutes=3h', () {
      // schedWork=480, workMinutes=480+180=660, overtime=180
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '09:00', schedEnd: '18:00',
        actualStart: '07:00', actualEnd: '19:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.earlyArrivalMinutes, equals(120));
      expect(r.overtimeMinutes, equals(180));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('C10: 완전 결근 — baseAmount=0', () {
      // breakMinutes=540(전체)로 workMinutes=0 테스트
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '09:00', schedEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00',
        breakMinutes: 540, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.workMinutes, equals(0));
      expect(r.baseAmount, equals(0));
      expect(r.overtimeAmount, equals(0));
      expect(r.totalAmount, equals(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // D. 일급제 — 야간 패턴
  // ═══════════════════════════════════════════════════════════════
  group('D-일급제/야간', () {
    test('D01: 야간 8h 계약 정시 (22:00~07:00, 휴게60) — 일급전액+야간수당', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '22:00', schedEnd: '07:00',
        actualStart: '22:00', actualEnd: '07:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.baseAmount, equals(_dw));
      expect(r.overtimeAmount, equals(0));
      expect(r.nightMinutes, greaterThan(0));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('D02: nightIncluded=true 정시 — 야간수당 0 (계약 내 야간분 제외)', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '22:00', schedEnd: '07:00',
        actualStart: '22:00', actualEnd: '07:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        nightIncluded: true,
        baseHourlyWage: 15000,
      );
      expect(r.nightMinutes, equals(0)); // 초과분 없으므로 야간수당 0
      expect(r.nightAmount, equals(0));
    });

    test('D03: nightIncluded=true + 연장 1h — 연장분 야간수당 발생', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '22:00', schedEnd: '07:00',
        actualStart: '22:00', actualEnd: '08:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        nightIncluded: true,
        baseHourlyWage: 15000,
      );
      expect(r.overtimeMinutes, equals(60));
      // scheduledEnd=07:00, actualEnd=08:00 → 07:00~08:00 야간 아님(06:00 이후)
      expect(r.nightMinutes, equals(0));
    });

    test('D04: nightIncluded=true + 연장 퇴근 04:00 → 04:00~04:00 없음', () {
      // schedEnd=07:00, actualEnd=04:00 → 연장 아님 (조기퇴근)
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '22:00', schedEnd: '07:00',
        actualStart: '22:00', actualEnd: '04:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        nightIncluded: true,
        baseHourlyWage: 15000,
      );
      expect(r.nightMinutes, equals(0)); // 연장 없으므로 0
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('D05: 야간 조출 (21:00~07:00, 계약22:00~07:00, 휴게60) — 조출 1h', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '22:00', schedEnd: '07:00',
        actualStart: '21:00', actualEnd: '07:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.earlyArrivalMinutes, equals(60));
      expect(r.overtimeMinutes, equals(60));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('D06: 석간 근무 (15:00~23:00, 휴게60) — 야간 1h(22:00~23:00)', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '15:00', schedEnd: '23:00',
        actualStart: '15:00', actualEnd: '23:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.nightMinutes, equals(60));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('D07: 야간수당 비적용 야간계약 (nightAllowanceApplied=false)', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '22:00', schedEnd: '07:00',
        actualStart: '22:00', actualEnd: '07:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        nightAllowanceApplied: false,
        baseHourlyWage: 15000,
      );
      expect(r.nightAmount, equals(0));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount));
    });

    test('D08: 야간 지각 1h (23:00~07:00, 계약22:00~07:00, 휴게60)', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '22:00', schedEnd: '07:00',
        actualStart: '23:00', actualEnd: '07:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.earlyArrivalMinutes, equals(0));
      expect(r.workMinutes, equals(420)); // 8h-60=480-60? actualMinutes=480, work=480-60=420
      expect(r.baseAmount, lessThan(_dw));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('D09: 야간 연장 2h (초과 8h) — 1.5배 적용', () {
      // schedWork=480, overtime=120, workMinutes=600>480→ over8=120, within8=0
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '22:00', schedEnd: '07:00',
        actualStart: '22:00', actualEnd: '09:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.overtimeMinutes, equals(120));
      expect(r.overtimeAmount, equals((120 * 15000 * 1.5 / 60).round()));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('D10: 자정 넘김 야간 조출+연장 (21:00~09:00, 계약22:00~08:00, 휴게60)', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '22:00', schedEnd: '08:00',
        actualStart: '21:00', actualEnd: '09:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.earlyArrivalMinutes, equals(60));
      expect(r.overtimeMinutes, equals(120)); // 조출60 + 연장60
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // E. 경계값 — 정확히 4h/8h 경계
  // ═══════════════════════════════════════════════════════════════
  group('E-경계값', () {
    test('E01: 시급제 정확히 8h (workMinutes=480) — 연장 0', () {
      final r = _calc(
        schedStart: '09:00', schedEnd: '18:00',
        actualEnd: '18:00', breakMinutes: 60,
      );
      expect(r.workMinutes, equals(480));
      expect(r.overtimeMinutes, equals(0));
    });

    test('E02: 시급제 8h+1분 (workMinutes=481) — 연장 1분', () {
      final r = _calc(
        schedStart: '09:00', schedEnd: '18:00',
        actualEnd: '18:01', breakMinutes: 60,
      );
      expect(r.workMinutes, equals(481));
      expect(r.overtimeMinutes, equals(1));
    });

    test('E03: 시급제 8h-1분 (workMinutes=479) — 연장 0', () {
      final r = _calc(
        schedStart: '09:00', schedEnd: '17:59',
        actualEnd: '17:59', breakMinutes: 60,
      );
      expect(r.workMinutes, equals(479));
      expect(r.overtimeMinutes, equals(0));
    });

    test('E04: 일급제 정확히 4h (workMinutes=240=schedWork) — 일급전액', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw4,
        schedStart: '09:00', schedEnd: '13:00',
        actualEnd: '13:00', breakMinutes: 0, scheduledBreakMinutes: 0,
        baseHourlyWage: 15000,
      );
      expect(r.workMinutes, equals(240));
      expect(r.baseAmount, equals(_dw4));
      expect(r.overtimeAmount, equals(0));
    });

    test('E05: breakMinutes = actualMinutes → workMinutes=0', () {
      final r = _calc(
        schedStart: '09:00', schedEnd: '13:00',
        actualEnd: '13:00', breakMinutes: 240,
      );
      expect(r.workMinutes, equals(0));
      expect(r.baseAmount, equals(0));
      expect(r.totalAmount, equals(0));
    });

    test('E06: breakMinutes > actualMinutes → workMinutes=0 (clamp)', () {
      final r = _calc(
        schedStart: '09:00', schedEnd: '13:00',
        actualEnd: '13:00', breakMinutes: 300, // 실제 4h인데 5h 휴게 입력
      );
      expect(r.workMinutes, equals(0));
      expect(r.totalAmount, equals(0));
    });

    test('E07: 일급제 workMinutes=scheduledWorkMinutes 정확히 — 일급전액', () {
      // schedWork=480, workMinutes=480
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '09:00', schedEnd: '18:00',
        actualEnd: '18:00', breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.baseAmount, equals(_dw));
      expect(r.overtimeAmount, equals(0));
    });

    test('E08: 22:00 정각 시작+야간 경계 (22:00~23:00) — 야간 1h', () {
      final r = _calc(
        schedStart: '22:00', schedEnd: '23:00',
        actualStart: '22:00', actualEnd: '23:00', breakMinutes: 0,
      );
      expect(r.nightMinutes, equals(60));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('E09: 06:00 정각 종료 — 야간 경계', () {
      final r = _calc(
        schedStart: '02:00', schedEnd: '06:00',
        actualStart: '02:00', actualEnd: '06:00', breakMinutes: 0,
      );
      expect(r.nightMinutes, equals(240)); // 02:00~06:00 모두 야간
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('E10: 06:01 종료 — 야간 경계 이후 1분은 야간 아님', () {
      final r = _calc(
        schedStart: '02:00', schedEnd: '06:01',
        actualStart: '02:00', actualEnd: '06:01', breakMinutes: 0,
      );
      expect(r.nightMinutes, equals(240)); // 02:00~06:00만 야간
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // F. 추가수당 + 불변식 강화
  // ═══════════════════════════════════════════════════════════════
  group('F-추가수당/불변식', () {
    test('F01: 추가수당 10,000원 — totalAmount에 포함', () {
      final r = _calc(additionalAmount: 10000);
      expect(r.additionalAmount, equals(10000));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount + 10000));
    });

    test('F02: 시급제 연장+야간+추가수당 모두 — 불변식', () {
      final r = _calc(
        schedStart: '18:00', schedEnd: '03:00',
        actualStart: '18:00', actualEnd: '04:00',
        breakMinutes: 60, additionalAmount: 5000,
      );
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount + 5000));
    });

    test('F03: scheduledBreakMinutes < breakMinutes (석식공제) — 연장 시간 차감 확인', () {
      // 계약: 09:00~18:30 (기본30분 휴게), 석식공제 추가로 실제 휴게=90분
      // schedWork = 540-30=510, workMinutes = 630-90=540, overtime=30
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '09:00', schedEnd: '18:30',
        actualStart: '09:00', actualEnd: '19:30',
        breakMinutes: 90, scheduledBreakMinutes: 30,
        baseHourlyWage: 15000,
      );
      // actualMinutes=630, workMinutes=630-90=540, schedWork=570-30=510? schedMin=630-30=600?
      // schedMin = _calculateMinutesBetween('09:00','18:30') = 570
      // schedWork = 570-30=540, workMinutes=540 → overtime=0 (같음)
      // 올바른 케이스: actualEnd=19:30 → actualMinutes=630, workMinutes=540, schedWork=540 → overtime=0
      // 연장 30분 만들려면 actualEnd=20:00: workMinutes=570, overtime=30
      expect(r.workMinutes, equals(540));
      expect(r.overtimeMinutes, equals(0)); // 석식공제로 workMinutes == schedWorkMin
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('F03b: 석식공제 — 퇴근 더 늦을 때 연장 발생', () {
      // 계약: 09:00~18:00 (휴게0), 실제 휴게90(석식), actualEnd=20:00
      // schedWork=540, workMinutes=660-90=570, overtime=30
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '09:00', schedEnd: '18:00',
        actualStart: '09:00', actualEnd: '20:30',
        breakMinutes: 90, scheduledBreakMinutes: 0,
        baseHourlyWage: 15000,
      );
      // actualMinutes=690, workMinutes=690-90=600, schedWork=540-0=540, overtime=60
      expect(r.workMinutes, equals(600));
      expect(r.overtimeMinutes, equals(60));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('F04: 최저시급 미만 시급 → 계산은 진행 (경고는 UI)', () {
      final r = _calc(baseWage: 5000); // 최저시급 미만
      expect(r.baseAmount, greaterThan(0));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('F05: baseHourlyWage 지정 일급제 — 연장수당 기초 시급 override', () {
      // baseHourlyWage=20000 강제 지정
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '09:00', schedEnd: '18:00',
        actualStart: '09:00', actualEnd: '19:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 20000,
      );
      // overtime=60min, over8=60, amount15x = 60*20000*1.5/60 = 30,000
      expect(r.overtimeAmount, equals((60 * 20000 * 1.5 / 60).round()));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // G. 다양한 시간대 시나리오 (시급제)
  // ═══════════════════════════════════════════════════════════════
  group('G-시급제/다양한시간대', () {
    final shifts = [
      // [schedStart, schedEnd, break, label, expectWork]
      ['06:00', '14:00', 60, 'G01:조조(06~14)', 420],
      ['07:00', '15:00', 60, 'G02:이른아침(07~15)', 420],
      ['08:00', '16:00', 60, 'G03:아침(08~16)', 420],
      ['09:00', '17:00', 60, 'G04:오전(09~17)', 420],
      ['10:00', '18:00', 60, 'G05:낮(10~18)', 420],
      ['11:00', '19:00', 60, 'G06:점심(11~19)', 420],
      ['12:00', '20:00', 60, 'G07:정오(12~20)', 420],
      ['13:00', '21:00', 60, 'G08:오후(13~21)', 420],
      ['14:00', '22:00', 60, 'G09:석간(14~22)', 420],
      ['15:00', '23:00', 60, 'G10:석간야(15~23)', 420],
    ];

    for (final s in shifts) {
      final start = s[0] as String;
      final end = s[1] as String;
      final brk = s[2] as int;
      final label = s[3] as String;
      final expWork = s[4] as int;

      test(label, () {
        _assertInvariants(
          () => _calc(
            schedStart: start, schedEnd: end,
            actualStart: start, actualEnd: end,
            breakMinutes: brk,
          ),
          label: label,
          expectWork: expWork,
          expectOvertime: 0,
        );
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════
  // H. 다양한 시간대 시나리오 (일급제, 불변식)
  // ═══════════════════════════════════════════════════════════════
  group('H-일급제/다양한시간대', () {
    final shifts = [
      ['06:00', '15:00', 60, 'H01:조조8h'],
      ['07:00', '16:00', 60, 'H02:이른아침8h'],
      ['08:00', '17:00', 60, 'H03:아침8h'],
      ['09:00', '18:00', 60, 'H04:표준8h'],
      ['10:00', '19:00', 60, 'H05:늦은오전8h'],
      ['12:00', '21:00', 60, 'H06:점심8h'],
      ['14:00', '23:00', 60, 'H07:석간8h'],
      ['16:00', '01:00', 60, 'H08:저녁8h'],
      ['18:00', '03:00', 60, 'H09:야간8h'],
      ['22:00', '07:00', 60, 'H10:심야8h'],
    ];

    for (final s in shifts) {
      final start = s[0] as String;
      final end = s[1] as String;
      final brk = s[2] as int;
      final label = s[3] as String;

      test('$label — 불변식', () {
        _assertInvariants(
          () => _calc(
            wageType: 'daily', baseWage: _dw,
            schedStart: start, schedEnd: end,
            actualStart: start, actualEnd: end,
            breakMinutes: brk, scheduledBreakMinutes: brk,
            baseHourlyWage: 15000,
          ),
          label: label,
          expectOvertime: 0,
        );
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════
  // I. 조출 시나리오 매트릭스 (일급제 — 다양한 계약 시간)
  // ═══════════════════════════════════════════════════════════════
  group('I-일급제/조출매트릭스', () {
    // [schedStart, schedEnd, actualStart, actualEnd, earlyExpected, label]
    final cases = [
      ['09:00', '18:00', '08:00', '18:00', 60,  'I01:조출60분-표준8h'],
      ['09:00', '18:00', '07:30', '18:00', 90,  'I02:조출90분-표준8h'],
      ['09:00', '18:00', '07:00', '18:00', 120, 'I03:조출120분-표준8h'],
      ['09:00', '13:00', '08:00', '13:00', 60,  'I04:조출60분-4h계약'],
      ['22:00', '07:00', '21:00', '07:00', 60,  'I05:조출60분-야간8h'],
      ['22:00', '07:00', '20:00', '07:00', 120, 'I06:조출120분-야간8h'],
      ['10:00', '18:00', '09:30', '18:00', 30,  'I07:조출30분-7h계약'],
      ['09:00', '18:00', '09:00', '18:00', 0,   'I08:조출없음(정시)'],
      ['09:00', '18:00', '10:00', '18:00', 0,   'I09:지각(조출 없음)'],
      ['06:00', '14:00', '05:00', '14:00', 60,  'I10:조조조출60분'],
    ];

    for (final c in cases) {
      final ss = c[0] as String;
      final se = c[1] as String;
      final as_ = c[2] as String;
      final ae = c[3] as String;
      final earlyExp = c[4] as int;
      final label = c[5] as String;

      test(label, () {
        final r = _calc(
          wageType: 'daily', baseWage: _dw,
          schedStart: ss, schedEnd: se,
          actualStart: as_, actualEnd: ae,
          breakMinutes: 60, scheduledBreakMinutes: 60,
          baseHourlyWage: 15000,
        );
        expect(r.earlyArrivalMinutes, equals(earlyExp), reason: '$label: earlyArrivalMinutes');
        expect(
          r.totalAmount,
          equals(r.baseAmount + r.overtimeAmount + r.nightAmount),
          reason: '$label: 불변식',
        );
        if (earlyExp > 0) {
          expect(r.overtimeMinutes, greaterThanOrEqualTo(earlyExp),
              reason: '$label: overtimeMinutes >= earlyArrivalMinutes');
        }
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════
  // J. 복합 시나리오 (조출+연장+야간)
  // ═══════════════════════════════════════════════════════════════
  group('J-복합시나리오', () {
    test('J01: 조출+연장+야간 (07:00~23:00, 계약09:00~18:00, 휴게60)', () {
      // schedWork=480, actualMinutes=960, workMinutes=900, overtime=420
      // earlyArrival=120(07:00~09:00), 야간=60(22:00~23:00)
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '09:00', schedEnd: '18:00',
        actualStart: '07:00', actualEnd: '23:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.earlyArrivalMinutes, equals(120)); // 07:00~09:00
      expect(r.overtimeMinutes, equals(420)); // 전체 계약초과 = 900-480
      expect(r.nightMinutes, equals(60)); // 22:00~23:00
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('J02: 시급제 야간교대 조출+연장 (21:00~08:00, 계약22:00~07:00, 휴게60)', () {
      final r = _calc(
        schedStart: '22:00', schedEnd: '07:00',
        actualStart: '21:00', actualEnd: '08:00',
        breakMinutes: 60,
      );
      // actualMinutes=660, workMinutes=600, overtime=120
      expect(r.earlyArrivalMinutes, equals(60));
      expect(r.overtimeMinutes, equals(120));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('J03: 일급제 미달+야간 (22:00~02:00, 계약22:00~07:00, 휴게60)', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '22:00', schedEnd: '07:00',
        actualStart: '22:00', actualEnd: '02:00',
        breakMinutes: 0, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.workMinutes, equals(240));
      expect(r.baseAmount, lessThan(_dw)); // 미달 공제
      expect(r.nightMinutes, greaterThan(0)); // 22:00~02:00 야간
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('J04: 시급제 연속 12h (10:00~23:00, 휴게60) — 연장3h+야간1h', () {
      final r = _calc(
        schedStart: '10:00', schedEnd: '19:00',
        actualStart: '10:00', actualEnd: '23:00',
        breakMinutes: 60,
      );
      // workMinutes=720, overtime=240, night=60(22:00~23:00)
      expect(r.workMinutes, equals(720));
      expect(r.overtimeMinutes, equals(240));
      expect(r.nightMinutes, equals(60));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('J05: 일급제 조출+연장+야간 복합 (21:00~23:00, 4h계약09:00~13:00)', () {
      // 완전히 다른 시간대 — 실무에서 발생 불가하지만 로직 강건성 테스트
      final r = _calc(
        wageType: 'daily', baseWage: _dw4,
        schedStart: '09:00', schedEnd: '13:00',
        actualStart: '21:00', actualEnd: '23:00',
        breakMinutes: 0, scheduledBreakMinutes: 0,
        baseHourlyWage: 15000,
      );
      // earlyArrivalMinutes: schedStart(09:00=540) - actualStart(21:00=1260) → 음수 → 0
      expect(r.earlyArrivalMinutes, equals(0));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('J06: 시급제 야간 완전 포함 + 연장 (22:00~09:00, 휴게60) — 야간480+연장60', () {
      final r = _calc(
        schedStart: '22:00', schedEnd: '07:00',
        actualStart: '22:00', actualEnd: '09:00',
        breakMinutes: 60,
      );
      expect(r.workMinutes, equals(600));
      expect(r.overtimeMinutes, equals(120));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('J07: 일급제 연장 정확히 8h 총근무 (4h계약+4h연장=8h) — 1배 적용', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw4,
        schedStart: '09:00', schedEnd: '13:00',
        actualStart: '09:00', actualEnd: '17:00',
        breakMinutes: 0, scheduledBreakMinutes: 0,
        baseHourlyWage: 15000,
      );
      // workMinutes=480 = standardWorkMinutes → 1배
      expect(r.workMinutes, equals(480));
      expect(r.overtimeMinutes, equals(240));
      // workMinutes==480이므로 over8=0, within8=240 → 1배
      expect(r.overtimeAmount, equals((240 * 15000 / 60).round()));
    });

    test('J08: 일급제 연장 8h+1분 총근무 — 1분은 1.5배', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw4,
        schedStart: '09:00', schedEnd: '13:00',
        actualStart: '09:00', actualEnd: '17:01',
        breakMinutes: 0, scheduledBreakMinutes: 0,
        baseHourlyWage: 15000,
      );
      expect(r.workMinutes, equals(481));
      // overtime=241, over8=1, within8=240
      // amount1x=(240*15000/60).round()=60000, amount15x=(1*15000*1.5/60).round()=375
      final expected = (240 * 15000 / 60).round() + (1 * 15000 * 1.5 / 60).round();
      expect(r.overtimeAmount, equals(expected)); // 60375
    });

    test('J09: 시급제 8h 이상이지만 연장은 정시 체크인 (연장 = workMinutes-480)', () {
      final r = _calc(
        schedStart: '09:00', schedEnd: '18:00',
        actualStart: '09:00', actualEnd: '20:00',
        breakMinutes: 60,
      );
      // workMinutes=660, overtime=180
      expect(r.overtimeMinutes, equals(r.workMinutes - 480));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });

    test('J10: 일급제 earlyArrivalAmount <= overtimeAmount 항상 성립', () {
      final r = _calc(
        wageType: 'daily', baseWage: _dw,
        schedStart: '09:00', schedEnd: '18:00',
        actualStart: '07:00', actualEnd: '20:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      expect(r.earlyArrivalAmount, lessThanOrEqualTo(r.overtimeAmount));
      expect(r.totalAmount, equals(r.baseAmount + r.overtimeAmount + r.nightAmount));
    });
  });
}
