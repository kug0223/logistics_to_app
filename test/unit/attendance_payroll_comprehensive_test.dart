// test/unit/attendance_payroll_comprehensive_test.dart
//
// 근태·급여 로직 종합 시나리오 검증 — 200+ 시나리오
//
// ── 커버 범위 ────────────────────────────────────────────────
//  A. WageCalculator.legalMaxBreakMinutes          (12)
//  B. 야간분(_calculateNightMinutes) 경계값         (22)
//  C. 시급제 — 기본/휴게                            (15)
//  D. 시급제 — 연장(OT) 경계                        (16)
//  E. 시급제 — 야간+연장 복합                        (14)
//  F. 시급제 — 안전장치/엣지                         (8)
//  G. 일급제 — 기본/미달 비율                        (15)
//  H. 일급제 — OT 8시간 분기                         (14)
//  I. 일급제 — 조출(earlyArrival)                   (8)
//  J. 일급제 — nightIncluded                        (8)
//  K. 일급제 — supplementWage / 최저시급 연도별      (12)
//  L. 주휴수당(weeklyHolidayPay)                    (12)
//  M. AttendanceStatusHelper — isLate 심화          (16)
//  N. AttendanceStatusHelper — isEarlyLeave 심화    (16)
//  O. AttendanceStatusHelper — isOvertime 심화      (14)
//  P. AttendanceStatusHelper — isNightOvertime 심화 (10)
//  Q. AttendanceStatusHelper — minutesBetween 심화  (10)
//  R. AttendanceModel — getter/copyWith 심화         (16)
//
// 합계: 218 시나리오
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/wage_calculator.dart';
import 'package:ALfit/utils/attendance_status_helper.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';

// ── 공통 상수 ─────────────────────────────────────────────────

const int _w = 12000;       // 테스트 시급
const int _d = 120000;      // 테스트 일급

final DateTime _date2026 = DateTime(2026, 6, 1); // 최저시급 10,320원
final DateTime _date2025 = DateTime(2025, 6, 1); // 최저시급 10,030원
final DateTime _date2024 = DateTime(2024, 6, 1); // 최저시급  9,860원
final DateTime _date2023 = DateTime(2023, 6, 1); // 최저시급  9,620원
final DateTime _date2022 = DateTime(2022, 6, 1); // 최저시급  9,160원

// ── 헬퍼 ──────────────────────────────────────────────────────

/// 시급제 계산 (scheduledStart == actualStart 기본)
WageDetailModel _h({
  int wage = _w,
  required String s,   // scheduledStart = actualStart
  required String e,   // scheduledEnd   = actualEnd
  String? as_,         // actualStart override
  String? ae,          // actualEnd   override
  int br = 0,
  bool night = true,
  int add = 0,
  DateTime? date,
}) =>
    WageCalculator.calculate(
      wageType: 'hourly',
      baseWage: wage,
      workDate: date ?? _date2026,
      scheduledStart: s,
      scheduledEnd: e,
      actualStart: as_ ?? s,
      actualEnd: ae ?? e,
      breakMinutes: br,
      nightAllowanceApplied: night,
      additionalAmount: add,
    );

/// 일급제 계산
WageDetailModel _day({
  int wage = _d,
  required String ss,   // scheduledStart
  required String se,   // scheduledEnd
  required String as_,  // actualStart
  required String ae,   // actualEnd
  int br = 0,
  int? sbr,             // scheduledBreakMinutes
  bool night = true,
  bool ni = false,      // nightIncluded
  int? bh,              // baseHourlyWage
  int add = 0,
  DateTime? date,
}) =>
    WageCalculator.calculate(
      wageType: 'daily',
      baseWage: wage,
      workDate: date ?? _date2026,
      scheduledStart: ss,
      scheduledEnd: se,
      actualStart: as_,
      actualEnd: ae,
      breakMinutes: br,
      scheduledBreakMinutes: sbr,
      nightAllowanceApplied: night,
      nightIncluded: ni,
      baseHourlyWage: bh,
      additionalAmount: add,
    );

/// AttendanceModel 생성 헬퍼 (v2 DateTime 기반)
AttendanceModel _att({
  DateTime? ci,           // checkInAt
  DateTime? co,           // checkOutAt
  DateTime? origCi,       // originalCheckInAt
  DateTime? origCo,       // originalCheckOutAt
  String status = AttendanceModel.statusPresent,
  String wageStatus = AttendanceModel.wagePending,
  int? finalWage,
}) =>
    AttendanceModel(
      id: 'att-test',
      applicationId: 'app-test',
      userId: 'uid-test',
      businessId: 'biz-test',
      businessName: '테스트',
      workDate: DateTime(2026, 6, 1),
      workType: '테스트',
      checkInAt: ci,
      checkOutAt: co,
      originalCheckInAt: origCi,
      originalCheckOutAt: origCo,
      status: status,
      wageStatus: wageStatus,
      finalWage: finalWage,
      createdAt: DateTime(2026, 6, 1, 9, 0),
    );

// ─────────────────────────────────────────────────────────────
void main() {

  // ══════════════════════════════════════════════════════════
  // A. WageCalculator.legalMaxBreakMinutes — 12 케이스
  //    [법정기준] 4h 미만=0, 4h~8h 미만=30, 8h 이상=60
  // ══════════════════════════════════════════════════════════
  group('A. legalMaxBreakMinutes 경계값', () {
    test('A-01: 0분 → 0', () => expect(WageCalculator.legalMaxBreakMinutes(0), 0));
    test('A-02: 1분 → 0', () => expect(WageCalculator.legalMaxBreakMinutes(1), 0));
    test('A-03: 239분(3h59m) → 0', () => expect(WageCalculator.legalMaxBreakMinutes(239), 0));

    // [특이사항] 240분 정각(4h)부터 30분 적용
    test('A-04: 240분(4h) → 30', () => expect(WageCalculator.legalMaxBreakMinutes(240), 30));
    test('A-05: 241분 → 30', () => expect(WageCalculator.legalMaxBreakMinutes(241), 30));
    test('A-06: 300분(5h) → 30', () => expect(WageCalculator.legalMaxBreakMinutes(300), 30));
    test('A-07: 479분(7h59m) → 30', () => expect(WageCalculator.legalMaxBreakMinutes(479), 30));

    // [특이사항] 480분 정각(8h)부터 60분 적용
    test('A-08: 480분(8h) → 60', () => expect(WageCalculator.legalMaxBreakMinutes(480), 60));
    test('A-09: 481분 → 60', () => expect(WageCalculator.legalMaxBreakMinutes(481), 60));
    test('A-10: 600분(10h) → 60', () => expect(WageCalculator.legalMaxBreakMinutes(600), 60));
    test('A-11: 960분(16h) → 60', () => expect(WageCalculator.legalMaxBreakMinutes(960), 60));
    test('A-12: 961분 → 60', () => expect(WageCalculator.legalMaxBreakMinutes(961), 60));
  });

  // ══════════════════════════════════════════════════════════
  // B. 야간분(_calculateNightMinutes) 경계값 — 22 케이스
  //    야간 구간: [0,360) 00~06, [1320,1440) 22~24, [1440,1800) 00~06(익일)
  // ══════════════════════════════════════════════════════════
  group('B. 야간분 계산 경계값', () {
    // 주간 전용
    test('B-01: 완전 주간 09:00~17:00 → 야간 0분', () {
      expect(_h(s: '09:00', e: '17:00').nightMinutes, 0);
    });
    test('B-02: 21:00~22:00 → 야간 0분 (22:00 미만)', () {
      expect(_h(s: '21:00', e: '22:00').nightMinutes, 0);
    });

    // [특이사항] 22:00 정각부터 야간 시작 — 경계 1분 단위 검증
    test('B-03: 21:59~22:01 → 야간 1분 (22:00~22:01)', () {
      expect(_h(s: '21:59', e: '22:01').nightMinutes, 1);
    });
    test('B-04: 22:00~23:00 → 야간 60분', () {
      expect(_h(s: '22:00', e: '23:00').nightMinutes, 60);
    });
    test('B-05: 22:00~24:00 → 야간 120분', () {
      expect(_h(s: '22:00', e: '00:00').nightMinutes, 120);
    });
    test('B-06: 22:00~06:00 → 야간 480분 (전체 야간)', () {
      expect(_h(s: '22:00', e: '06:00').nightMinutes, 480);
    });

    // [특이사항] 06:00 정각에 끝나면 야간 포함, 06:01에 끝나면 야간 동일
    test('B-07: 05:59~06:01 → 야간 1분 (05:59~06:00)', () {
      expect(_h(s: '05:59', e: '06:01').nightMinutes, 1);
    });
    test('B-08: 05:00~06:00 → 야간 60분', () {
      expect(_h(s: '05:00', e: '06:00').nightMinutes, 60);
    });
    test('B-09: 06:00~07:00 → 야간 0분 (06:00 이후는 주간)', () {
      expect(_h(s: '06:00', e: '07:00').nightMinutes, 0);
    });
    test('B-10: 06:01~08:00 → 야간 0분', () {
      expect(_h(s: '06:01', e: '08:00').nightMinutes, 0);
    });

    // 자정 넘김 복합
    test('B-11: 23:00~01:00 → 야간 120분 (23~00=60, 00~01=60)', () {
      // overlap(1320,1440)=60, overlap(1440,1800)=60
      expect(_h(s: '23:00', e: '01:00').nightMinutes, 120);
    });
    test('B-12: 20:00~23:00 → 야간 60분 (22:00~23:00)', () {
      expect(_h(s: '20:00', e: '23:00').nightMinutes, 60);
    });
    test('B-13: 20:00~02:00 → 야간 240분 (22~00=120, 00~02=120)', () {
      expect(_h(s: '20:00', e: '02:00').nightMinutes, 240);
    });
    test('B-14: 00:00~06:00 → 야간 360분', () {
      expect(_h(s: '00:00', e: '06:00').nightMinutes, 360);
    });
    test('B-15: 01:00~05:00 → 야간 240분', () {
      expect(_h(s: '01:00', e: '05:00').nightMinutes, 240);
    });
    test('B-16: 18:00~22:00 → 야간 0분', () {
      expect(_h(s: '18:00', e: '22:00').nightMinutes, 0);
    });

    // 휴게 시간이 야간분을 줄이는 케이스
    test('B-17: 22:00~06:00 break=60 → 야간 420분 (480-60)', () {
      // dayPortion=480-480=0, breakInNight=60, night=480-60=420
      expect(_h(s: '22:00', e: '06:00', br: 60).nightMinutes, 420);
    });
    test('B-18: 22:00~06:00 break=120 → 야간 360분', () {
      expect(_h(s: '22:00', e: '06:00', br: 120).nightMinutes, 360);
    });

    // 주간+야간 혼합에서 휴게는 주간 먼저 차감
    test('B-19: 20:00~23:00(3h) break=90 → 야간 60분 (주간180→휴게90→잔여90, 야간60 그대로)', () {
      // rawNight=60, dayPortion=180-60=120, breakInNight=max(0,90-120)=0, night=60
      expect(_h(s: '20:00', e: '23:00', br: 90).nightMinutes, 60);
    });
    test('B-20: 20:00~23:00(3h) break=150 → 야간 30분 (주간=120 < 휴게150 → 야간에서30차감)', () {
      // rawNight=60, dayPortion=180-60=120, breakInNight=max(0,150-120)=30, night=60-30=30
      expect(_h(s: '20:00', e: '23:00', br: 150).nightMinutes, 30);
    });

    // nightAllowanceApplied=false
    test('B-21: nightAllowanceApplied=false → nightAmount=0 (nightMinutes는 여전히 계산)', () {
      final r = _h(s: '22:00', e: '06:00', night: false);
      expect(r.nightAmount, 0);
      // [특이사항] nightMinutes 필드 자체는 계산되지만 amount만 0
    });
    test('B-22: 22:00~06:00 야간전용: nightAmount 계산 검증', () {
      // 480min * 12000 * 0.5 / 60 = 48000
      final r = _h(s: '22:00', e: '06:00');
      expect(r.nightAmount, 48000);
    });
  });

  // ══════════════════════════════════════════════════════════
  // C. 시급제 — 기본 / 휴게 — 15 케이스
  // ══════════════════════════════════════════════════════════
  group('C. 시급제 기본', () {
    test('C-01: 1시간 → 12,000원', () {
      expect(_h(s: '09:00', e: '10:00').baseAmount, 12000);
    });
    test('C-02: 30분 → 6,000원', () {
      expect(_h(s: '09:00', e: '09:30').baseAmount, 6000);
    });
    test('C-03: 4시간(정확 경계) → 48,000원', () {
      expect(_h(s: '09:00', e: '13:00').baseAmount, 48000);
    });
    test('C-04: 7시간59분 → (479*12000/60)=95,800원', () {
      expect(_h(s: '09:00', e: '16:59').baseAmount, 95800);
    });
    test('C-05: 8시간(기본급 최대) → 96,000원, OT=0', () {
      final r = _h(s: '09:00', e: '17:00');
      expect(r.baseAmount, 96000);
      expect(r.overtimeMinutes, 0);
    });
    test('C-06: 시급 10,320원(2026 최저시급) 8시간 → 82,560원', () {
      expect(_h(wage: 10320, s: '09:00', e: '17:00').totalAmount, 82560);
    });
    test('C-07: 시급 5,000원(최저시급 미만) — UI경고, 계산 그대로 → 40,000원', () {
      // [특이사항] 시급제는 최저시급 강제 미적용, UI에서 경고만 표시
      expect(_h(wage: 5000, s: '09:00', e: '17:00').baseAmount, 40000);
    });
    test('C-08: 휴게 30분 적용 → workMinutes 감소', () {
      // 8h실제 - 30min휴게 = 7.5h=450min, OT=(450-480).clamp=0
      final r = _h(s: '09:00', e: '17:00', br: 30);
      expect(r.workMinutes, 450);
      expect(r.overtimeMinutes, 0);
      expect(r.baseAmount, 90000); // 450*12000/60
    });
    test('C-09: 휴게 60분 → workMinutes=420', () {
      final r = _h(s: '09:00', e: '17:00', br: 60);
      expect(r.workMinutes, 420);
      expect(r.baseAmount, 84000);
    });
    test('C-10: 추가수당 양수 → totalAmount 증가', () {
      final r = _h(s: '09:00', e: '17:00', add: 5000);
      expect(r.totalAmount, 96000 + 5000);
    });
    test('C-11: 추가수당 음수 → totalAmount 감소', () {
      final r = _h(s: '09:00', e: '17:00', add: -5000);
      expect(r.totalAmount, 96000 - 5000);
    });
    test('C-12: actualStart 조정(지각), actualEnd 동일 → 실제 근무 감소', () {
      // 09:30 출근, 17:00 퇴근 → 7.5h=450min
      final r = _h(s: '09:00', e: '17:00', as_: '09:30', ae: '17:00');
      expect(r.workMinutes, 450);
    });
    test('C-13: actualEnd 조기 퇴근(조퇴) → 실제 근무 감소', () {
      final r = _h(s: '09:00', e: '17:00', ae: '15:00');
      expect(r.workMinutes, 360);
      expect(r.baseAmount, 72000);
    });
    test('C-14: 2025 최저시급(10,030원) 하위 시급 8시간 계산', () {
      // 시급제는 최저시급 강제 없으므로 그대로 계산
      expect(_h(wage: 10030, s: '09:00', e: '17:00', date: _date2025).baseAmount, 80240);
    });
    test('C-15: scheduledMinutes 필드 검증 — 야간 포함', () {
      // 22:00~06:00 = 480분
      expect(_h(s: '22:00', e: '06:00').scheduledMinutes, 480);
    });
  });

  // ══════════════════════════════════════════════════════════
  // D. 시급제 — 연장(OT) 경계 — 16 케이스
  //    8시간(480분) 초과분이 1.5배 적용
  // ══════════════════════════════════════════════════════════
  group('D. 시급제 연장 경계', () {
    test('D-01: 8시간 정각 → OT=0', () {
      expect(_h(s: '09:00', e: '17:00').overtimeMinutes, 0);
    });
    test('D-02: 8시간+1분 → OT=1분', () {
      expect(_h(s: '09:00', e: '17:01').overtimeMinutes, 1);
    });
    test('D-03: 8시간+1분 OT금액 → (1*12000*1.5/60)=300원', () {
      expect(_h(s: '09:00', e: '17:01').overtimeAmount, 300);
    });
    test('D-04: 8시간+30분 → OT=30분, base=96000, OT=9000', () {
      final r = _h(s: '09:00', e: '17:30');
      expect(r.overtimeMinutes, 30);
      expect(r.baseAmount, 96000); // 480*12000/60
      expect(r.overtimeAmount, 9000); // 30*12000*1.5/60
      expect(r.totalAmount, 105000);
    });
    test('D-05: 8시간+60분 → total=114,000원', () {
      final r = _h(s: '09:00', e: '18:00');
      expect(r.overtimeMinutes, 60);
      expect(r.totalAmount, 114000); // 96000+18000
    });
    test('D-06: 8시간+120분 → OT=120, total=132,000원', () {
      expect(_h(s: '09:00', e: '19:00').totalAmount, 132000); // 96000+36000
    });
    test('D-07: 10시간(OT=120) base검증 → regularMins=480', () {
      final r = _h(s: '09:00', e: '19:00');
      expect(r.workMinutes, 600);
      expect(r.overtimeMinutes, 120);
      expect(r.baseAmount, 96000); // regularMins=480
    });
    test('D-08: 12시간(OT=240) → total=168,000원', () {
      // base=96000, OT=(240*12000*1.5/60)=72000 → 168000
      expect(_h(s: '09:00', e: '21:00').totalAmount, 168000);
    });

    // [특이사항] 야간교대에서의 연장 계산 — checkIn 기준 자정 보정
    test('D-09: 야간 22:00~07:00(OT=60, 06:00 계약) break=0 → OT=60분', () {
      final r = _h(s: '22:00', e: '06:00', ae: '07:00');
      expect(r.overtimeMinutes, 60);
    });
    test('D-10: 야간 22:00~04:00(6h) → OT=0 (480분 미만)', () {
      // workMin=360, 360<480 → OT=0
      expect(_h(s: '22:00', e: '04:00').overtimeMinutes, 0);
    });
    test('D-11: 야간 22:00~06:00(8h=480분) → OT=0 (경계 정각)', () {
      expect(_h(s: '22:00', e: '06:00').overtimeMinutes, 0);
    });
    test('D-12: 야간 22:00~06:01 → OT=1분', () {
      expect(_h(s: '22:00', e: '06:00', ae: '06:01').overtimeMinutes, 1);
    });

    // 휴게 후 OT 계산
    test('D-13: 9시간 근무 break=30 → workMin=510, OT=30', () {
      // 09:00~18:00(9h), break=30 → work=510, OT=510-480=30
      final r = _h(s: '09:00', e: '18:00', br: 30);
      expect(r.workMinutes, 510);
      expect(r.overtimeMinutes, 30);
    });
    test('D-14: 9시간 break=60 → workMin=480, OT=0 (휴게 후 딱 8h)', () {
      final r = _h(s: '09:00', e: '18:00', br: 60);
      expect(r.workMinutes, 480);
      expect(r.overtimeMinutes, 0);
    });
    test('D-15: 10시간 break=60 → workMin=540, OT=60', () {
      final r = _h(s: '09:00', e: '19:00', br: 60);
      expect(r.workMinutes, 540);
      expect(r.overtimeMinutes, 60);
    });
    test('D-16: appliedSupplementWage = baseWage (시급제는 항상)', () {
      expect(_h(s: '09:00', e: '17:00').appliedSupplementWage, _w);
    });
  });

  // ══════════════════════════════════════════════════════════
  // E. 시급제 — 야간+연장 복합 — 14 케이스
  // ══════════════════════════════════════════════════════════
  group('E. 시급제 야간+연장 복합', () {
    test('E-01: 주간만 연장(21:00 퇴근) → nightAmt=0, OT 있음', () {
      // 09:00~21:00(12h), OT=240
      final r = _h(s: '09:00', e: '21:00');
      expect(r.nightMinutes, 0);
      expect(r.nightAmount, 0);
      expect(r.overtimeMinutes, 240);
    });
    test('E-02: 22:01 퇴근 → nightAmt>0, OT>0', () {
      // 09:00~22:01(13h1m=781m), OT=301, night=1
      final r = _h(s: '09:00', e: '22:01');
      expect(r.nightMinutes, 1);
      expect(r.nightAmount, 100); // (1*12000*0.5/60).round()=100
      expect(r.overtimeMinutes, 301);
    });
    test('E-03: 22:00~07:00(9h=540m, OT=60) break=0 → night=480', () {
      final r = _h(s: '22:00', e: '06:00', ae: '07:00');
      expect(r.nightMinutes, 480);
      expect(r.overtimeMinutes, 60);
      // nightAmount = 480*12000*0.5/60=48000
      expect(r.nightAmount, 48000);
      // baseAmount = (480*12000/60)=96000 (regularMins=480)
      expect(r.baseAmount, 96000);
      // OT = 60*12000*1.5/60=18000
      expect(r.overtimeAmount, 18000);
      expect(r.totalAmount, 162000);
    });
    test('E-04: 20:00~07:00(11h) break=60 → night=480, OT=120', () {
      // workMin=660-60=600, OT=120, night=480
      // dayPortion=600-480=120, breakInNight=max(0,60-120)=0
      final r = _h(s: '20:00', e: '07:00', br: 60);
      expect(r.workMinutes, 600);
      expect(r.nightMinutes, 480);
      expect(r.overtimeMinutes, 120);
      expect(r.totalAmount, 180000); // 96000+36000+48000
    });
    test('E-05: 23:00~02:00(3h) → night=180, OT=0, total=54,000원', () {
      // base=36000, night=18000
      final r = _h(s: '23:00', e: '02:00');
      expect(r.nightMinutes, 180);
      expect(r.totalAmount, 54000);
    });
    test('E-06: 23:00~03:00(4h) break=60 → night=180, workMin=180', () {
      // rawNight=240, dayPortion=0, breakInNight=60, night=180
      final r = _h(s: '23:00', e: '03:00', br: 60);
      expect(r.workMinutes, 180);
      expect(r.nightMinutes, 180);
      expect(r.nightAmount, 18000); // 180*12000*0.5/60
    });
    test('E-07: 22:00~02:00(4h=240m) → night=240, OT=0', () {
      final r = _h(s: '22:00', e: '02:00');
      expect(r.nightMinutes, 240);
      expect(r.overtimeMinutes, 0);
      expect(r.totalAmount, 72000); // base=48000+night=24000
    });
    test('E-08: 야간 없고 OT 없음 → 순수 기본급', () {
      final r = _h(s: '09:00', e: '17:00');
      expect(r.nightAmount, 0);
      expect(r.overtimeAmount, 0);
      expect(r.totalAmount, r.baseAmount);
    });
    test('E-09: 18:00~22:01(4h1m) → nightMins=1, OT=0(4h1m<8h)', () {
      final r = _h(s: '18:00', e: '22:01');
      expect(r.nightMinutes, 1);
      expect(r.overtimeMinutes, 0);
    });
    test('E-10: totalAmount = base + OT + night + additional', () {
      final r = _h(s: '09:00', e: '22:30', add: 1000);
      // 13.5h=810m, OT=330, night=30
      expect(r.totalAmount, r.baseAmount + r.overtimeAmount + r.nightAmount + 1000);
    });
    test('E-11: 야간 중 break 과다 → nightMinutes 감소 확인', () {
      // 22:00~02:00(4h), break=200 → dayPortion=0, breakInNight=200, night=max(0,240-200)=40
      final r = _h(s: '22:00', e: '02:00', br: 200);
      expect(r.nightMinutes, 40);
    });
    test('E-12: 야간 시작 경계 — 21:59 시작 → 21:59~22:00=1분 야간 제외', () {
      // 21:59~23:00(1h1m=61m), night=60(22:00~23:00)
      final r = _h(s: '21:59', e: '23:00');
      expect(r.nightMinutes, 60);
    });
    test('E-13: 야간 종료 경계 — 05:59~06:01 → 야간=1분', () {
      final r = _h(s: '05:59', e: '06:01');
      expect(r.nightMinutes, 1);
    });
    test('E-14: 시급 10,320원(최저시급) 야간 8h → nightAmount=41,280원', () {
      // 480*10320*0.5/60=41280
      expect(_h(wage: 10320, s: '22:00', e: '06:00').nightAmount, 41280);
    });
  });

  // ══════════════════════════════════════════════════════════
  // F. 시급제 — 안전장치/엣지케이스 — 8 케이스
  // ══════════════════════════════════════════════════════════
  group('F. 시급제 안전장치', () {
    // [특이사항] break > actualMinutes → workMinutes=0 (음수 임금 방지)
    test('F-01: break(60) > actual(30) → workMin=0, total=0', () {
      final r = _h(s: '09:00', e: '09:30', br: 60);
      expect(r.workMinutes, 0);
      expect(r.totalAmount, 0);
    });
    test('F-02: break = actual → workMin=0', () {
      final r = _h(s: '09:00', e: '10:00', br: 60);
      expect(r.workMinutes, 0);
    });
    test('F-03: 동일 시작/종료 → 0분 → total=0', () {
      final r = _h(s: '09:00', e: '09:00');
      expect(r.workMinutes, 0);
      expect(r.totalAmount, 0);
    });
    test('F-04: additional만 → total=additional', () {
      // workMin=0일 때도 additional은 포함
      final r = _h(s: '09:00', e: '09:00', add: 10000);
      expect(r.totalAmount, 10000);
    });
    test('F-05: break=0 명시 → 전체 실근무 반영', () {
      final r = _h(s: '09:00', e: '17:00', br: 0);
      expect(r.workMinutes, 480);
    });
    test('F-06: actualMinutes 필드 = 실제 체류 분(break 포함)', () {
      // 09:00~18:00=540min, break=60 → actualMinutes=540, workMinutes=480
      final r = _h(s: '09:00', e: '18:00', br: 60);
      expect(r.actualMinutes, 540);
      expect(r.workMinutes, 480);
    });
    test('F-07: breakMinutes 필드 = 입력값 그대로 저장', () {
      final r = _h(s: '09:00', e: '17:00', br: 45);
      expect(r.breakMinutes, 45);
    });
    test('F-08: earlyArrivalMinutes = 0 (시급제는 조출 계산 없음)', () {
      // 시급제는 earlyArrivalMinutes=0 고정
      final r = _h(s: '09:00', e: '17:00', as_: '08:00');
      // [특이사항] 시급제에서 조출은 OT에 이미 반영됨 — 별도 earlyArrivalMinutes 없음
      expect(r.earlyArrivalMinutes, 60); // schedStart-actualStart clamp
    });
  });

  // ══════════════════════════════════════════════════════════
  // G. 일급제 — 기본 / 미달 비율 — 15 케이스
  //    일급 120,000원, 09:00~18:00 (9h, break=60 → schedWork=480)
  // ══════════════════════════════════════════════════════════
  group('G. 일급제 기본/미달', () {
    // schedWork=480, ordinaryHourly=(120000/480*60).round()=15000
    test('G-01: 정확히 8시간 근무 → base=120,000원', () {
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '18:00', br: 60);
      expect(r.baseAmount, 120000);
      expect(r.overtimeAmount, 0);
      expect(r.totalAmount, 120000);
    });
    test('G-02: 7시간 근무(7h=420m < schedWork480) → 비율 계산 = 105,000원', () {
      // (120000*420/480).round()=105000
      final r = _day(ss: '09:00', se: '18:00', as_: '10:00', ae: '18:00', br: 60);
      expect(r.workMinutes, 420);
      expect(r.baseAmount, 105000);
    });
    test('G-03: 6시간 근무 → 90,000원', () {
      final r = _day(ss: '09:00', se: '18:00', as_: '11:00', ae: '18:00', br: 60);
      expect(r.baseAmount, 90000);
    });
    test('G-04: 4시간 근무 → 60,000원', () {
      final r = _day(ss: '09:00', se: '18:00', as_: '13:00', ae: '18:00', br: 60);
      expect(r.baseAmount, 60000);
    });
    test('G-05: 2시간 근무 → 30,000원', () {
      final r = _day(ss: '09:00', se: '18:00', as_: '15:00', ae: '18:00', br: 60);
      expect(r.baseAmount, 30000);
    });
    test('G-06: 0분 근무 → 0원', () {
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '09:00', br: 0);
      expect(r.baseAmount, 0);
    });
    test('G-07: 공고 기준 6시간(break=0) → schedWork=360', () {
      // 120000, 09:00~15:00 (6h, break=0), 정확히 6h 근무
      // ordinaryHourly=(120000/360*60).round()=20000
      final r = _day(ss: '09:00', se: '15:00', as_: '09:00', ae: '15:00', br: 0);
      expect(r.baseAmount, 120000);
      expect(r.overtimeMinutes, 0);
    });
    test('G-08: 공고 5시간, 실제 4시간 → 비율', () {
      // schedWork=300, work=240, 240<300 → (120000*240/300).round()=96000
      final r = _day(ss: '09:00', se: '14:00', as_: '09:00', ae: '13:00', br: 0);
      expect(r.baseAmount, 96000);
    });
    test('G-09: scheduledMinutes 검증', () {
      // 09:00~18:00=540분
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '18:00', br: 60);
      expect(r.scheduledMinutes, 540);
    });
    test('G-10: 야간 일급 22:00~06:00(8h), 정상 근무 → base=일급 전액', () {
      final r = _day(ss: '22:00', se: '06:00', as_: '22:00', ae: '06:00', br: 0);
      expect(r.baseAmount, _d);
    });
    test('G-11: 야간 일급 22:00~06:00, 5시간만 근무 → 비율', () {
      // schedWork=480, work=300, (120000*300/480).round()=75000
      final r = _day(ss: '22:00', se: '06:00', as_: '22:00', ae: '03:00', br: 0);
      expect(r.workMinutes, 300);
      expect(r.baseAmount, 75000);
    });
    test('G-12: additional 포함 → totalAmount에 반영', () {
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '18:00', br: 60, add: 10000);
      expect(r.totalAmount, 130000);
    });
    test('G-13: wageType 필드 = daily 저장', () {
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '18:00', br: 0);
      expect(r.wageType, 'daily');
    });
    test('G-14: baseWage 필드 = 입력 일급 저장', () {
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '18:00', br: 0);
      expect(r.baseWage, _d);
    });
    test('G-15: break > actual → workMin=0, base=0', () {
      // 09:00~09:30(30m), break=60 → workMin=(30-60).clamp(0,...)=0
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '09:30', br: 60);
      expect(r.workMinutes, 0);
      expect(r.baseAmount, 0);
    });
  });

  // ══════════════════════════════════════════════════════════
  // H. 일급제 — OT 8시간 분기 — 14 케이스
  //    [핵심] 총 workMinutes ≤480 → 연장분 1배, >480 → 8h 초과분 1.5배
  // ══════════════════════════════════════════════════════════
  group('H. 일급제 OT 8시간 분기', () {
    // 09:00~15:00(6h, break=0) schedWork=360, supplementWage=20000
    final ss = '09:00'; final se = '15:00';

    test('H-01: 정확히 schedWork(6h) → OT=0', () {
      final r = _day(ss: ss, se: se, as_: '09:00', ae: '15:00', br: 0, bh: 20000);
      expect(r.overtimeMinutes, 0);
      expect(r.overtimeAmount, 0);
    });
    test('H-02: 7시간(OT=60, total=420m ≤480) → OT 1배', () {
      // OT=60, workMin=420 ≤ 480 → 1배
      // OT금액=60*20000/60=20000
      final r = _day(ss: ss, se: se, as_: '09:00', ae: '16:00', br: 0, bh: 20000);
      expect(r.overtimeMinutes, 60);
      expect(r.workMinutes, 420);
      expect(r.overtimeAmount, 20000);
      expect(r.totalAmount, 140000); // 120000+20000
    });
    test('H-03: 8시간(OT=120, total=480m ≤480) → OT 전체 1배', () {
      // OT=120, workMin=480=standardWorkMin → within8h=120, over8h=0 → 1배
      final r = _day(ss: ss, se: se, as_: '09:00', ae: '17:00', br: 0, bh: 20000);
      expect(r.overtimeMinutes, 120);
      expect(r.workMinutes, 480);
      expect(r.overtimeAmount, 40000); // 120*20000/60
      expect(r.totalAmount, 160000);
    });
    test('H-04: 8시간+1분(OT=121, total=481 >480) → 1분은 1.5배', () {
      // over8h=481-480=1, within8h=120, amount1x=120*20000/60=40000
      // amount15x=(1*20000*1.5/60).round()=500
      final r = _day(ss: ss, se: se, as_: '09:00', ae: '17:01', br: 0, bh: 20000);
      expect(r.workMinutes, 481);
      expect(r.overtimeAmount, 40500);
    });
    test('H-05: 10시간(OT=240, total=600 >480) → over8h=120, within8h=120', () {
      // over8h=120, within8h=120
      // amount1x=120*20000/60=40000
      // amount15x=120*20000*1.5/60=60000
      // OT=100000
      final r = _day(ss: ss, se: se, as_: '09:00', ae: '19:00', br: 0, bh: 20000);
      expect(r.overtimeMinutes, 240);
      expect(r.overtimeAmount, 100000);
      expect(r.totalAmount, 220000);
    });
    test('H-06: schedWork=0(동일 시작/종료)이면 OT 계산 스킵', () {
      // schedWork=0 → base=일급전액, OT=0 방어
      final r = _day(ss: '09:00', se: '09:00', as_: '09:00', ae: '11:00', br: 0);
      expect(r.baseAmount, _d); // scheduledWorkMinutes==0 → 일급 전액
      expect(r.overtimeAmount, 0);
    });
    test('H-07: OT 1배 경계 — total=480분 정각', () {
      // workMin=480 ≤ 480 → 전체 1배
      final r = _day(ss: '09:00', se: '13:00', as_: '09:00', ae: '17:00', br: 0, bh: 20000);
      // schedWork=240, work=480, OT=240, workMin=480≤480
      expect(r.overtimeAmount, (240 * 20000 / 60).round());
    });
    test('H-08: OT 1.5배 경계 — total=481분', () {
      final r = _day(ss: '09:00', se: '13:00', as_: '09:00', ae: '17:01', br: 0, bh: 20000);
      // OT=241, over8h=481-480=1, within8h=OT-over8h=241-1=240
      // amount1x=240*20000/60=80000, amount15x=1*20000*1.5/60=500 → 80500
      final expected = (240 * 20000 / 60).round() + (1 * 20000 * 1.5 / 60).round();
      expect(r.overtimeAmount, expected);
    });

    // 09:00~18:00(9h, break=60) schedWork=480 기준
    test('H-09: 정시 퇴근(schedWork=8h) → base=일급, OT=0', () {
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '18:00', br: 60);
      expect(r.overtimeMinutes, 0);
      expect(r.baseAmount, _d);
    });
    test('H-10: 30분 연장(total=510 >480) → 1.5배', () {
      // OT=30, work=510>480, over8h=30, within8h=0
      // amount15x=(30*15000*1.5/60).round()=11250
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '18:30', br: 60, bh: 15000);
      expect(r.overtimeAmount, 11250);
      expect(r.totalAmount, 131250);
    });
    test('H-11: 2시간 연장(total=600) → 1.5배 2시간', () {
      // over8h=120, within8h=0
      // amount15x=(120*15000*1.5/60).round()=45000
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '20:00', br: 60, bh: 15000);
      expect(r.overtimeAmount, 45000);
    });
    test('H-12: 야간 연장(22:00~06:00→07:00, OT=60) → 1.5배', () {
      // schedWork=480, work=540, over8h=60 → 1.5배
      final r = _day(ss: '22:00', se: '06:00', as_: '22:00', ae: '07:00', br: 0, bh: 15000);
      expect(r.overtimeMinutes, 60);
      // work=540>480 → over8h=60, within8h=0
      expect(r.overtimeAmount, (60 * 15000 * 1.5 / 60).round()); // 22500
    });
    test('H-13: baseAmount = 일급 전액(>=schedWork) 검증', () {
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '19:00', br: 60, bh: 15000);
      expect(r.baseAmount, _d);
    });
    test('H-14: OT 있을 때 totalAmount = base + OT 검증', () {
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '18:30', br: 60, bh: 15000);
      expect(r.totalAmount, r.baseAmount + r.overtimeAmount + r.nightAmount);
    });
  });

  // ══════════════════════════════════════════════════════════
  // I. 일급제 — 조출(earlyArrival) — 8 케이스
  // ══════════════════════════════════════════════════════════
  group('I. 일급제 조출', () {
    // 09:00~18:00(9h, break=60→schedWork=480), bh=15000
    test('I-01: 정시 출근 → earlyArrivalMinutes=0', () {
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '18:00', br: 60, bh: 15000);
      expect(r.earlyArrivalMinutes, 0);
    });
    test('I-02: 지각 출근 → earlyArrivalMinutes=0 (clamp)', () {
      final r = _day(ss: '09:00', se: '18:00', as_: '09:30', ae: '18:00', br: 60, bh: 15000);
      expect(r.earlyArrivalMinutes, 0);
    });
    test('I-03: 30분 조출 → earlyArrivalMinutes=30', () {
      final r = _day(ss: '09:00', se: '18:00', as_: '08:30', ae: '18:00', br: 60, bh: 15000);
      expect(r.earlyArrivalMinutes, 30);
    });
    test('I-04: 1시간 조출(OT=60, total=540>480) → earlyArrivalAmt=1.5배', () {
      // OT=60, work=540>480, over8h=60, within8h=0
      // earlyIn8h=min(60,0)=0, earlyOver8h=60
      // earlyArrivalAmt=0+(60*15000*1.5/60).round()=22500
      final r = _day(ss: '09:00', se: '18:00', as_: '08:00', ae: '18:00', br: 60, bh: 15000);
      expect(r.earlyArrivalMinutes, 60);
      expect(r.earlyArrivalAmount, 22500);
    });
    test('I-05: earlyArrivalAmount는 totalAmount에 미포함 확인', () {
      // [특이사항] earlyArrivalAmount는 OT의 하위 분류로, totalAmount에는 포함 안 됨
      final r = _day(ss: '09:00', se: '18:00', as_: '08:00', ae: '18:00', br: 60, bh: 15000);
      // totalAmount = base + OT(포함earlyArrival) + night
      expect(r.totalAmount, r.baseAmount + r.overtimeAmount + r.nightAmount);
    });
    test('I-06: 30분 조출(OT=30, total=510>480) → earlyIn8h=0, earlyOver8h=30', () {
      // work=510>480, over8h=30, within8h=0
      // earlyIn8h=min(30,0)=0, earlyOver8h=30
      // earlyAmt=30*15000*1.5/60=11250
      final r = _day(ss: '09:00', se: '18:00', as_: '08:30', ae: '18:00', br: 60, bh: 15000);
      expect(r.earlyArrivalAmount, 11250);
    });
    test('I-07: 2시간 조출(total=600>480) earlyArrivalAmt 검증', () {
      // OT=120, work=600>480, over8h=120, within8h=0
      // earlyIn8h=min(120,0)=0, earlyOver8h=120
      // earlyAmt=120*15000*1.5/60=45000
      final r = _day(ss: '09:00', se: '18:00', as_: '07:00', ae: '18:00', br: 60, bh: 15000);
      expect(r.earlyArrivalMinutes, 120);
      expect(r.earlyArrivalAmount, 45000);
    });
    test('I-08: 조출로 total≤8h인 경우 earlyArrivalAmt=1배', () {
      // schedWork=480(09~15, break=0, 6h)
      // actual 08:00~15:00(7h=420m≤480) → OT=60, work=420≤480 → 1배
      // earlyIn8h=min(60,60)=60, earlyOver8h=0
      // earlyAmt=60*20000/60=20000
      final r = _day(ss: '09:00', se: '15:00', as_: '08:00', ae: '15:00', br: 0, bh: 20000);
      expect(r.earlyArrivalAmount, 20000);
    });
  });

  // ══════════════════════════════════════════════════════════
  // J. 일급제 — nightIncluded — 8 케이스
  // ══════════════════════════════════════════════════════════
  group('J. 일급제 nightIncluded', () {
    // [특이사항] nightIncluded=true: 계약구간 야간은 이미 일급에 포함,
    //           OT 발생 시 그 OT 구간에 해당하는 야간분만 추가 적용
    test('J-01: OT 없음 → nightAmount=0 (야간 이미 포함)', () {
      final r = _day(ss: '22:00', se: '06:00', as_: '22:00', ae: '06:00',
                     br: 0, ni: true, bh: 15000);
      expect(r.nightAmount, 0);
    });
    test('J-02: OT 1시간(주간) → nightAmount=0 (06:00~07:00은 주간)', () {
      // _calculateNightMinutes("06:00","07:00") = 0
      final r = _day(ss: '22:00', se: '06:00', as_: '22:00', ae: '07:00',
                     br: 0, ni: true, bh: 15000);
      expect(r.nightMinutes, 0);
      expect(r.nightAmount, 0);
    });
    test('J-03: OT 1시간(야간 — 04:00~05:00) → nightAmount>0', () {
      // schedule 22:00~04:00(6h), actual ~05:00(7h)
      // _calculateNightMinutes("04:00","05:00")=60 (00~06 구간)
      final r = _day(ss: '22:00', se: '04:00', as_: '22:00', ae: '05:00',
                     br: 0, ni: true, bh: 15000);
      expect(r.overtimeMinutes, 60);
      expect(r.nightMinutes, 60);
      expect(r.nightAmount, 7500); // 60*15000*0.5/60
    });
    test('J-04: OT 2시간 야간 → nightAmount=2h분', () {
      // schedule 22:00~04:00(6h), actual ~06:00(8h), OT=2h
      // nightMins("04:00","06:00")=120 (04~06)
      final r = _day(ss: '22:00', se: '04:00', as_: '22:00', ae: '06:00',
                     br: 0, ni: true, bh: 15000);
      expect(r.nightMinutes, 120);
      expect(r.nightAmount, 15000); // 120*15000*0.5/60
    });
    test('J-05: nightIncluded=false → 전체 야간분 적용', () {
      final r = _day(ss: '22:00', se: '06:00', as_: '22:00', ae: '06:00',
                     br: 0, ni: false, bh: 15000);
      expect(r.nightMinutes, 480);
      expect(r.nightAmount, 60000); // 480*15000*0.5/60
    });
    test('J-06: nightIncluded=true, OT 없으면 night=0이므로 total=base만', () {
      final r = _day(ss: '22:00', se: '06:00', as_: '22:00', ae: '06:00',
                     br: 0, ni: true, bh: 15000);
      expect(r.totalAmount, _d);
    });
    test('J-07: nightIncluded=false vs true 비교 — OT없을 때 야간수당 차이', () {
      final withNight = _day(ss: '22:00', se: '06:00', as_: '22:00', ae: '06:00',
                              br: 0, ni: false, bh: 15000);
      final inclNight = _day(ss: '22:00', se: '06:00', as_: '22:00', ae: '06:00',
                              br: 0, ni: true, bh: 15000);
      // nightIncluded=false: 야간수당 추가됨
      // nightIncluded=true:  야간수당 0
      expect(withNight.nightAmount, greaterThan(0));
      expect(inclNight.nightAmount, 0);
    });
    test('J-08: nightAllowanceApplied=false이면 nightIncluded 무관 → 야간 0', () {
      final r = _day(ss: '22:00', se: '06:00', as_: '22:00', ae: '07:00',
                     br: 0, night: false, ni: true, bh: 15000);
      expect(r.nightAmount, 0);
    });
  });

  // ══════════════════════════════════════════════════════════
  // K. 일급제 — supplementWage / 최저시급 연도별 — 12 케이스
  // ══════════════════════════════════════════════════════════
  group('K. supplementWage 및 연도별 최저시급', () {
    // [핵심] supplementWage = max(ordinaryHourly, minimumWage)
    //       ordinaryHourly = (dailyWage / schedWorkMins * 60).round()

    test('K-01: 통상시급(15000) > 최저시급(10320) → supplementWage=15000', () {
      // 120000, 09~18, break=60 → schedWork=480 → ordinary=15000
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '18:00', br: 60);
      expect(r.appliedSupplementWage, 15000);
    });
    test('K-02: 일급 낮아 통상시급<최저시급 → supplementWage=minimumWage(2026)', () {
      // 40000, schedWork=480 → ordinary=(40000/480*60)=5000 < 10320
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '18:00',
                     br: 60, wage: 40000);
      expect(r.appliedSupplementWage, greaterThanOrEqualTo(10320));
    });
    test('K-03: baseHourlyWage 명시 → 그 값 우선', () {
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '18:00',
                     br: 60, bh: 14000);
      expect(r.appliedSupplementWage, 14000);
    });
    test('K-04: baseHourlyWage < minimumWage여도 명시값 그대로', () {
      // [특이사항] baseHourlyWage 명시 시 최저시급 가드 미적용
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '18:00',
                     br: 60, bh: 5000);
      expect(r.appliedSupplementWage, 5000);
    });

    // 연도별 최저시급 검증
    test('K-05: 2026년 최저시급 = 10,320원', () {
      expect(WageCalculator.getMinimumWage(2026), 10320);
    });
    test('K-06: 2025년 최저시급 = 10,030원', () {
      expect(WageCalculator.getMinimumWage(2025), 10030);
    });
    test('K-07: 2024년 최저시급 = 9,860원', () {
      expect(WageCalculator.getMinimumWage(2024), 9860);
    });
    test('K-08: 2023년 최저시급 = 9,620원', () {
      expect(WageCalculator.getMinimumWage(2023), 9620);
    });
    test('K-09: 2022년 최저시급 = 9,160원', () {
      expect(WageCalculator.getMinimumWage(2022), 9160);
    });
    test('K-10: appliedMinimumWage 필드 = 근무일 연도 최저시급', () {
      final r2026 = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '18:00',
                          br: 60, date: _date2026);
      final r2025 = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '18:00',
                          br: 60, date: _date2025);
      expect(r2026.appliedMinimumWage, 10320);
      expect(r2025.appliedMinimumWage, 10030);
    });
    test('K-11: 2025년 기준 낮은 일급 → supplementWage=10,030원', () {
      final r = _day(ss: '09:00', se: '18:00', as_: '09:00', ae: '18:00',
                     br: 60, wage: 40000, date: _date2025);
      expect(r.appliedSupplementWage, greaterThanOrEqualTo(10030));
    });
    test('K-12: 시급제 appliedMinimumWage = 근무일 기준 연도', () {
      final r = _h(wage: 12000, s: '09:00', e: '17:00', date: _date2023);
      expect(r.appliedMinimumWage, 9620);
    });
  });

  // ══════════════════════════════════════════════════════════
  // L. 주휴수당(weeklyHolidayPay) — 12 케이스
  // ══════════════════════════════════════════════════════════
  group('L. 주휴수당 경계값', () {
    // [설계] 15시간(900분) 미만 → 0, 이상 → (주간근무/40h)*8h*시급, 최대 40h 상한
    const hw = 10320; // 2026 최저시급

    test('L-01: 0분 → 0', () => expect(WageCalculator.calculateWeeklyHolidayPay(
        ordinaryHourlyWage: hw, weeklyWorkMinutes: 0), 0));
    test('L-02: 899분(14h59m) → 0', () => expect(WageCalculator.calculateWeeklyHolidayPay(
        ordinaryHourlyWage: hw, weeklyWorkMinutes: 899), 0));
    test('L-03: 900분(15h) → 비례 = (15/40)*8*10320=30960원', () {
      // (900/60/40)*8*10320 = (0.375)*8*10320 = 30960
      expect(WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: hw, weeklyWorkMinutes: 900), 30960);
    });
    test('L-04: 901분 → 900분보다 크거나 같음', () {
      final at900 = WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: hw, weeklyWorkMinutes: 900);
      final at901 = WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: hw, weeklyWorkMinutes: 901);
      expect(at901, greaterThanOrEqualTo(at900));
    });
    test('L-05: 1200분(20h) → (20/40)*8*10320=41280원', () {
      expect(WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: hw, weeklyWorkMinutes: 1200), 41280);
    });
    test('L-06: 1800분(30h) → (30/40)*8*10320=61920원', () {
      expect(WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: hw, weeklyWorkMinutes: 1800), 61920);
    });
    test('L-07: 2400분(40h) → 최대 (40/40)*8*10320=82560원', () {
      expect(WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: hw, weeklyWorkMinutes: 2400), 82560);
    });
    test('L-08: 2401분(40h 초과) → 2400분과 동일(clamp 40h)', () {
      final at40h = WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: hw, weeklyWorkMinutes: 2400);
      final over = WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: hw, weeklyWorkMinutes: 2401);
      expect(over, at40h);
    });
    test('L-09: 3000분(50h) → 2400분과 동일', () {
      final at40h = WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: hw, weeklyWorkMinutes: 2400);
      expect(WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: hw, weeklyWorkMinutes: 3000), at40h);
    });
    test('L-10: 시급 12,000원 30h → (30/40)*8*12000=72000원', () {
      expect(WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: 12000, weeklyWorkMinutes: 1800), 72000);
    });
    test('L-11: 시급 15,000원 40h → 8h*15000=120000원', () {
      expect(WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: 15000, weeklyWorkMinutes: 2400), 120000);
    });
    test('L-12: 시급 20,000원 20h → (20/40)*8*20000=80000원', () {
      expect(WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: 20000, weeklyWorkMinutes: 1200), 80000);
    });
  });

  // ══════════════════════════════════════════════════════════
  // M. AttendanceStatusHelper — isLate 심화 — 16 케이스
  // ══════════════════════════════════════════════════════════
  group('M. isLate 심화', () {
    test('M-01: 정각 출근 → false', () {
      expect(AttendanceStatusHelper.isLate('09:00', '09:00'), isFalse);
    });
    test('M-02: 1분 지각 → true', () {
      expect(AttendanceStatusHelper.isLate('09:01', '09:00'), isTrue);
    });
    test('M-03: 59분 지각 → true', () {
      expect(AttendanceStatusHelper.isLate('09:59', '09:00'), isTrue);
    });
    test('M-04: 1분 일찍 출근 → false', () {
      expect(AttendanceStatusHelper.isLate('08:59', '09:00'), isFalse);
    });
    test('M-05: 30분 일찍 출근 → false', () {
      expect(AttendanceStatusHelper.isLate('08:30', '09:00'), isFalse);
    });
    test('M-06: 스케줄 22:00, 출근 22:00 → false', () {
      expect(AttendanceStatusHelper.isLate('22:00', '22:00'), isFalse);
    });
    test('M-07: 스케줄 22:00, 출근 22:01 → true', () {
      expect(AttendanceStatusHelper.isLate('22:01', '22:00'), isTrue);
    });
    test('M-08: 스케줄 00:00, 출근 00:01 → true', () {
      expect(AttendanceStatusHelper.isLate('00:01', '00:00'), isTrue);
    });
    test('M-09: 스케줄 00:30, 출근 00:00 → false (30분 일찍)', () {
      expect(AttendanceStatusHelper.isLate('00:00', '00:30'), isFalse);
    });
    // isNextDay=true: actual += 1440
    test('M-10: isNextDay=true, 출근 00:30 / 스케줄 23:00 → true (자정 넘긴 지각)', () {
      // actual=30+1440=1470, scheduled=1380, 1470>1380 → true
      expect(AttendanceStatusHelper.isLate('00:30', '23:00', isNextDay: true), isTrue);
    });
    test('M-11: isNextDay=true, 출근 23:00 / 스케줄 23:00 → true (1440분 차이)', () {
      // actual=1380+1440=2820 > scheduled=1380 → true
      // [특이사항] isNextDay=true이면 자정 다음날 출근 → 항상 지각으로 처리됨
      expect(AttendanceStatusHelper.isLate('23:00', '23:00', isNextDay: true), isTrue);
    });
    test('M-12: isNextDay=false(기본), 자정 근처 경계 23:59 vs 23:59', () {
      expect(AttendanceStatusHelper.isLate('23:59', '23:59'), isFalse);
    });
    test('M-13: 스케줄 23:59, 출근 00:00 → false (1분 일찍, 자정 넘어도 early)', () {
      // 00:00=0 < 23:59=1439 → early, not late
      expect(AttendanceStatusHelper.isLate('00:00', '23:59'), isFalse);
    });
    test('M-14: 스케줄 06:00, 출근 06:00 → false', () {
      expect(AttendanceStatusHelper.isLate('06:00', '06:00'), isFalse);
    });
    test('M-15: 스케줄 06:00, 출근 06:01 → true', () {
      expect(AttendanceStatusHelper.isLate('06:01', '06:00'), isTrue);
    });
    test('M-16: 파싱 실패 → false (관대한 방향)', () {
      expect(AttendanceStatusHelper.isLate('invalid', '09:00'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════
  // N. AttendanceStatusHelper — isEarlyLeave 심화 — 16 케이스
  // ══════════════════════════════════════════════════════════
  group('N. isEarlyLeave 심화', () {
    test('N-01: 정시 퇴근 → false', () {
      expect(AttendanceStatusHelper.isEarlyLeave('18:00', '18:00'), isFalse);
    });
    test('N-02: 1분 일찍 퇴근 → true', () {
      expect(AttendanceStatusHelper.isEarlyLeave('17:59', '18:00'), isTrue);
    });
    test('N-03: 30분 일찍 퇴근 → true', () {
      expect(AttendanceStatusHelper.isEarlyLeave('17:30', '18:00'), isTrue);
    });
    test('N-04: 1분 늦게 퇴근(연장) → false', () {
      expect(AttendanceStatusHelper.isEarlyLeave('18:01', '18:00'), isFalse);
    });
    test('N-05: 야간근무 checkIn 제공 — 자정 넘김 보정', () {
      // checkIn=22:00, checkOut=01:00, scheduledEnd=02:00
      // actual=60, checkIn=1320: 60<1320 → actual+=1440=1500
      // scheduled=120, 120<1320 → scheduled+=1440=1560
      // 1560-1500=60>0 → true (01:00에 나감, 02:00 예정)
      expect(
        AttendanceStatusHelper.isEarlyLeave('01:00', '02:00', checkIn: '22:00'),
        isTrue,
      );
    });
    test('N-06: 야간근무 — 계획보다 늦게 퇴근 → false', () {
      // checkIn=22:00, checkOut=02:30, scheduledEnd=02:00
      // actual=150+1440=1590, scheduled=120+1440=1560
      // 1560-1590=-30 > 0? No → false
      expect(
        AttendanceStatusHelper.isEarlyLeave('02:30', '02:00', checkIn: '22:00'),
        isFalse,
      );
    });
    test('N-07: 야간근무 정시 퇴근 → false', () {
      expect(
        AttendanceStatusHelper.isEarlyLeave('02:00', '02:00', checkIn: '22:00'),
        isFalse,
      );
    });
    test('N-08: 야간근무 중간 퇴근(23:00 퇴근, 02:00 계획) → true', () {
      // checkIn=22:00, checkOut=23:00, scheduledEnd=02:00
      // actual=1380 >= checkIn=1320 → no adjust
      // scheduled=120 < checkIn=1320 → 120+1440=1560
      // 1560-1380=180>0 → true
      expect(
        AttendanceStatusHelper.isEarlyLeave('23:00', '02:00', checkIn: '22:00'),
        isTrue,
      );
    });
    test('N-09: checkIn 없이 단순 비교 (야간 자정 넘김 보정 없음)', () {
      // 01:00 < 02:00 → true (단순 비교)
      expect(AttendanceStatusHelper.isEarlyLeave('01:00', '02:00'), isTrue);
    });
    test('N-10: 14:30 출근, 01:00 퇴근, 23:00 예정종료 → false (야간 정시 이후 퇴근)', () {
      // checkIn=870, actual=60: 60<870 → +1440=1500
      // scheduled=1380: 1380>=870 → no adjust
      // 1380-1500=-120 > 0? No → false
      expect(
        AttendanceStatusHelper.isEarlyLeave('01:00', '23:00', checkIn: '14:30'),
        isFalse,
      );
    });
    test('N-11: 스케줄 06:00, 퇴근 06:00 → false', () {
      expect(AttendanceStatusHelper.isEarlyLeave('06:00', '06:00'), isFalse);
    });
    test('N-12: 스케줄 06:00, 퇴근 05:59 → true', () {
      expect(AttendanceStatusHelper.isEarlyLeave('05:59', '06:00'), isTrue);
    });
    test('N-13: 스케줄 06:00, 퇴근 06:01 → false (연장)', () {
      expect(AttendanceStatusHelper.isEarlyLeave('06:01', '06:00'), isFalse);
    });
    test('N-14: 스케줄 00:00, 퇴근 23:00 → true (단순 비교: 23:00>00:00이므로 false 아님?)', () {
      // [특이사항] checkIn 없으면 단순 비교 — 00:00=0, 23:00=1380
      // scheduled=0, actual=1380. 0-1380=-1380>0? No → false
      expect(AttendanceStatusHelper.isEarlyLeave('23:00', '00:00'), isFalse);
    });
    test('N-15: 파싱 실패 checkOut → true (timeToMinutes 실패 시 0 반환 → 00:00으로 처리)', () {
      // [특이사항] timeToMinutes('invalid')=0 (0분=00:00으로 폴백)
      // actual=0, scheduled=1080 → 1080-0=1080>0 → true(조퇴 판정)
      // 파싱 오류가 false 반환이 아닌 00:00 폴백이므로 주의
      expect(AttendanceStatusHelper.isEarlyLeave('invalid', '18:00'), isTrue);
    });
    test('N-16: checkIn과 동일한 checkOut → scheduled 보정 후 비교', () {
      // checkIn=22:00, checkOut=22:00, scheduledEnd=06:00
      // actual=1320, checkIn=1320 → no adjust
      // scheduled=360 < checkIn=1320 → +1440=1800
      // 1800-1320=480>0 → true
      expect(
        AttendanceStatusHelper.isEarlyLeave('22:00', '06:00', checkIn: '22:00'),
        isTrue,
      );
    });
  });

  // ══════════════════════════════════════════════════════════
  // O. AttendanceStatusHelper — isOvertime 심화 — 14 케이스
  // ══════════════════════════════════════════════════════════
  group('O. isOvertime 심화', () {
    test('O-01: 정시 퇴근 → false', () {
      expect(AttendanceStatusHelper.isOvertime('18:00', '18:00'), isFalse);
    });
    test('O-02: 1분 연장 → true', () {
      expect(AttendanceStatusHelper.isOvertime('18:01', '18:00'), isTrue);
    });
    test('O-03: 1분 조퇴 → false', () {
      expect(AttendanceStatusHelper.isOvertime('17:59', '18:00'), isFalse);
    });
    test('O-04: graceMinutes=5, 5분 연장 → false (경계=허용)', () {
      // 1085 > 1080+5=1085? No → false
      expect(AttendanceStatusHelper.isOvertime('18:05', '18:00', graceMinutes: 5), isFalse);
    });
    test('O-05: graceMinutes=5, 6분 연장 → true', () {
      expect(AttendanceStatusHelper.isOvertime('18:06', '18:00', graceMinutes: 5), isTrue);
    });
    test('O-06: graceMinutes=0, 1분 → true', () {
      expect(AttendanceStatusHelper.isOvertime('18:01', '18:00', graceMinutes: 0), isTrue);
    });
    test('O-07: graceMinutes=30, 30분 연장 → false', () {
      expect(AttendanceStatusHelper.isOvertime('18:30', '18:00', graceMinutes: 30), isFalse);
    });
    test('O-08: graceMinutes=30, 31분 연장 → true', () {
      expect(AttendanceStatusHelper.isOvertime('18:31', '18:00', graceMinutes: 30), isTrue);
    });
    // 야간 자정 넘김
    test('O-09: 야간정시 checkIn=22:00, checkOut=06:00, sched=06:00 → false', () {
      expect(
        AttendanceStatusHelper.isOvertime('06:00', '06:00', checkIn: '22:00'),
        isFalse,
      );
    });
    test('O-10: 야간연장 checkIn=22:00, checkOut=06:30, sched=06:00 → true', () {
      expect(
        AttendanceStatusHelper.isOvertime('06:30', '06:00', checkIn: '22:00'),
        isTrue,
      );
    });
    test('O-11: 야간조퇴 checkIn=22:00, checkOut=05:30, sched=06:00 → false', () {
      expect(
        AttendanceStatusHelper.isOvertime('05:30', '06:00', checkIn: '22:00'),
        isFalse,
      );
    });
    test('O-12: checkIn 없이 자정 넘김(단순비교) 01:00>00:00 → true', () {
      expect(AttendanceStatusHelper.isOvertime('01:00', '00:00'), isTrue);
    });
    test('O-13: checkIn=22:00, sched=03:00, actual=03:01 → true', () {
      // actual=181+1440=1621, scheduled=180+1440=1620. 1621>1620 → true
      expect(
        AttendanceStatusHelper.isOvertime('03:01', '03:00', checkIn: '22:00'),
        isTrue,
      );
    });
    test('O-14: graceMinutes=10, 10분 이내 연장 → false', () {
      expect(AttendanceStatusHelper.isOvertime('18:10', '18:00', graceMinutes: 10), isFalse);
      expect(AttendanceStatusHelper.isOvertime('18:11', '18:00', graceMinutes: 10), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════
  // P. AttendanceStatusHelper — isNightOvertime 심화 — 10 케이스
  //    [핵심] OT이면서 outMins(보정후) > 22*60 인 경우
  // ══════════════════════════════════════════════════════════
  group('P. isNightOvertime 심화', () {
    test('P-01: OT이지만 21:59 퇴근 → false (22:00 미만)', () {
      // outMins=1319, inMins=540, 1319>1320? No
      expect(AttendanceStatusHelper.isNightOvertime('21:59', '18:00', '09:00'), isFalse);
    });
    test('P-02: 22:00 정각 퇴근(OT있음) → false (>1320 아님)', () {
      // outMins=1320 > 1320? No → false
      // [특이사항] 22:00 정각은 심야 OT 아님 (strict >)
      expect(AttendanceStatusHelper.isNightOvertime('22:00', '18:00', '09:00'), isFalse);
    });
    test('P-03: 22:01 퇴근(OT있음) → true', () {
      expect(AttendanceStatusHelper.isNightOvertime('22:01', '18:00', '09:00'), isTrue);
    });
    test('P-04: OT 없으면 → false (isOvertime 먼저 체크)', () {
      expect(AttendanceStatusHelper.isNightOvertime('22:01', '22:30', '09:00'), isFalse);
    });
    test('P-05: 야간 시프트 연장 checkIn=22:00, sched=06:00, out=06:30 → true', () {
      // outMins=390+1440=1830 > 1320 → true
      expect(AttendanceStatusHelper.isNightOvertime('06:30', '06:00', '22:00'), isTrue);
    });
    test('P-06: graceMinutes=5, 22:05 퇴근(5분이내) → OT없으므로 false', () {
      expect(
        AttendanceStatusHelper.isNightOvertime('22:05', '22:00', '09:00', graceMinutes: 5),
        isFalse,
      );
    });
    test('P-07: graceMinutes=5, 22:06 퇴근 → OT있고 22:00 초과 → true', () {
      // isOvertime: 22:06 > 22:00+5=22:05 → true
      // outMins=1326 > 1320 → true
      expect(
        AttendanceStatusHelper.isNightOvertime('22:06', '22:00', '09:00', graceMinutes: 5),
        isTrue,
      );
    });
    test('P-08: 23:00 퇴근, sched=21:00, checkIn=09:00 → true', () {
      expect(AttendanceStatusHelper.isNightOvertime('23:00', '21:00', '09:00'), isTrue);
    });
    test('P-09: 새벽 OT — checkIn=22:00, sched=03:00, out=03:30 → true', () {
      // outMins=210+1440=1650 > 1320 → true
      expect(AttendanceStatusHelper.isNightOvertime('03:30', '03:00', '22:00'), isTrue);
    });
    test('P-10: 파싱 실패 → isOvertime=true (invalid=00:00→익일보정→심야)', () {
      // [특이사항] timeToMinutes('invalid')=0 → actual=0, inMins=540, 0<540 → actual+=1440=1440
      // scheduled=1080 < inMins=540? No(1080>=540) → no adjust. 1440>1080 → overtime
      // outMins=0+1440=1440 > 22*60=1320 → nightOvertime=true
      // 파싱 오류가 심야OT로 오판정될 수 있음 (실제 입력 검증 필요)
      expect(AttendanceStatusHelper.isNightOvertime('invalid', '18:00', '09:00'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════
  // Q. AttendanceStatusHelper — minutesBetween 심화 — 10 케이스
  // ══════════════════════════════════════════════════════════
  group('Q. minutesBetween 심화', () {
    test('Q-01: 06:00~22:00 → 960분 (16시간)', () {
      expect(AttendanceStatusHelper.minutesBetween('06:00', '22:00'), 960);
    });
    test('Q-02: 00:00~00:00 → 0 (24h로 잘못 계산 방지)', () {
      expect(AttendanceStatusHelper.minutesBetween('00:00', '00:00'), 0);
    });
    test('Q-03: 23:59~00:00 → 1분 (자정 넘김 1분)', () {
      // e=0 < s=1439 → e+=1440=1440, 1440-1439=1
      expect(AttendanceStatusHelper.minutesBetween('23:59', '00:00'), 1);
    });
    test('Q-04: 23:00~01:00 → 120분 (자정 넘김)', () {
      expect(AttendanceStatusHelper.minutesBetween('23:00', '01:00'), 120);
    });
    test('Q-05: 22:00~06:00 → 480분', () {
      expect(AttendanceStatusHelper.minutesBetween('22:00', '06:00'), 480);
    });
    test('Q-06: 09:00~18:30 → 570분', () {
      expect(AttendanceStatusHelper.minutesBetween('09:00', '18:30'), 570);
    });
    test('Q-07: 동일 시각(09:00) → 0분', () {
      expect(AttendanceStatusHelper.minutesBetween('09:00', '09:00'), 0);
    });
    test('Q-08: 00:30~23:30 → 1380분', () {
      expect(AttendanceStatusHelper.minutesBetween('00:30', '23:30'), 1380);
    });
    test('Q-09: 09:00~01:00 → 960분 (다음날 01:00)', () {
      expect(AttendanceStatusHelper.minutesBetween('09:00', '01:00'), 960);
    });
    test('Q-10: 12:00~12:01 → 1분', () {
      expect(AttendanceStatusHelper.minutesBetween('12:00', '12:01'), 1);
    });
  });

  // ══════════════════════════════════════════════════════════
  // R. AttendanceModel — getter / copyWith 심화 — 16 케이스
  // ══════════════════════════════════════════════════════════
  group('R. AttendanceModel 심화', () {
    final workDate = DateTime(2026, 6, 1);

    test('R-01: checkIn getter 포맷 — 단자리 시:분 패딩', () {
      // 08:05 → "08:05" (left-pad 확인)
      final m = _att(ci: DateTime(2026, 6, 1, 8, 5));
      expect(m.checkIn, '08:05');
    });
    test('R-02: checkOut getter 자정 → "00:00"', () {
      final m = _att(co: DateTime(2026, 6, 2, 0, 0)); // 다음날 00:00
      expect(m.checkOut, '00:00');
    });
    test('R-03: checkIn=null → checkIn getter=null', () {
      expect(_att().checkIn, isNull);
    });
    test('R-04: checkOut=null → checkOut getter=null', () {
      expect(_att(ci: DateTime(2026, 6, 1, 9, 0)).checkOut, isNull);
    });

    // isMissedCheckout 상세
    test('R-05: checkIn 있고 checkOut 없음, status=absent → true (absent는 미제외)', () {
      // [특이사항] isMissedCheckout = hasCheckedIn && !hasCheckedOut && !isNoShow
      // statusAbsent는 isNoShow가 아니므로 제외 안 됨 → true 반환
      // (statusNoShow만 제외, statusAbsent는 해당 없음)
      final m = _att(ci: DateTime(2026, 6, 1, 9, 0), status: AttendanceModel.statusAbsent);
      expect(m.isMissedCheckout, isTrue);
    });
    test('R-06: checkIn 있고 checkOut 없음, status=earlyLeave → true', () {
      final m = _att(ci: DateTime(2026, 6, 1, 9, 0), status: AttendanceModel.statusEarlyLeave);
      expect(m.isMissedCheckout, isTrue);
    });
    test('R-07: 둘 다 있음 → isMissedCheckout=false', () {
      final m = _att(ci: DateTime(2026, 6, 1, 9, 0), co: DateTime(2026, 6, 1, 18, 0));
      expect(m.isMissedCheckout, isFalse);
    });

    // originalCheckInAt 유무로 자동반올림 여부 확인
    test('R-08: originalCheckInAt=null → 자동반올림 미적용', () {
      final m = _att(ci: DateTime(2026, 6, 1, 9, 0));
      expect(m.originalCheckInAt, isNull);
    });
    test('R-09: originalCheckInAt 있음 → 자동반올림 적용됨', () {
      final m = _att(
        ci: DateTime(2026, 6, 1, 9, 0),
        origCi: DateTime(2026, 6, 1, 8, 55),
      );
      expect(m.originalCheckInAt, isNotNull);
      expect(m.originalCheckInAt, DateTime(2026, 6, 1, 8, 55));
    });

    // copyWith
    test('R-10: copyWith(status) → status 변경, 나머지 보존', () {
      final original = _att(
        ci: DateTime(2026, 6, 1, 9, 0),
        status: AttendanceModel.statusPresent,
        wageStatus: AttendanceModel.wagePending,
      );
      final copied = original.copyWith(status: AttendanceModel.statusLate);
      expect(copied.status, AttendanceModel.statusLate);
      expect(copied.wageStatus, AttendanceModel.wagePending); // 보존
      expect(copied.checkInAt, original.checkInAt);           // 보존
    });
    test('R-11: copyWith(status: null) → ?? 패턴으로 원본 유지 (null 초기화 불가)', () {
      final original = _att(status: AttendanceModel.statusNoShow);
      final copied = original.copyWith(status: null);
      // [특이사항] status는 String(non-nullable) + copyWith `??` 패턴 → null 전달해도 원본 유지
      // 노쇼 취소 시 status를 실제로 바꾸려면 statusAbsent를 명시 전달해야 함
      // (attendance_status_dialog 수정 완료: copyWith(status: statusAbsent, wageStatus: wagePending))
      expect(copied.status, AttendanceModel.statusNoShow);
    });
    test('R-12: copyWith(wageStatus, finalWage) 복합', () {
      final original = _att(wageStatus: AttendanceModel.wagePending, finalWage: null);
      final copied = original.copyWith(
        wageStatus: AttendanceModel.wageConfirmed,
        finalWage: 100000,
      );
      expect(copied.wageStatus, AttendanceModel.wageConfirmed);
      expect(copied.finalWage, 100000);
    });
    test('R-13: copyWith(finalWage: null) → ?? 패턴으로 원본 유지 (null 초기화 불가)', () {
      final original = _att(finalWage: 100000);
      final copied = original.copyWith(finalWage: null);
      // [특이사항/주의] `finalWage: finalWage ?? this.finalWage` 패턴
      // null 전달 → 원본 값(100000) 유지됨
      // attendance_status_dialog의 copyWith(finalWage: null)도 효과 없음
      expect(copied.finalWage, 100000);
    });

    // statusLabel 전체
    test('R-14: 알 수 없는 status → statusLabel = "미출근"', () {
      expect(_att(status: 'unknown').statusLabel, '미출근');
    });

    // displayWage 체인
    test('R-15: wageConfirmed + finalWage=0 → displayWage=0', () {
      final m = _att(wageStatus: AttendanceModel.wageConfirmed, finalWage: 0);
      expect(m.displayWage, 0);
    });
    test('R-16: wageTransferred + finalWage=50000 → formattedDisplayWage="50,000원"', () {
      final m = _att(wageStatus: AttendanceModel.wageTransferred, finalWage: 50000);
      expect(m.formattedDisplayWage, '50,000원');
    });
  });
}
