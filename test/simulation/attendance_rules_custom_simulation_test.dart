// test/simulation/attendance_rules_custom_simulation_test.dart
//
// AttendanceRules 커스텀 설정 조합 + isZeroWork 시나리오 시뮬레이션
//
// 기존 테스트(attendance_rounding_helper_test.dart)의 미검증 영역만 커버:
//   - earlyWindow/lateWindow/lateGrace 비기본값 경계 정밀 검증
//   - earlyArrivalUnit/lateUnit/overtimeUnit/earlyLeaveUnit 커스텀 조합
//   - isZeroWork=true 발생 시나리오 (반올림 후 checkIn >= checkOut)
//   - AttendanceRules.fromMap clamp 방어 전체 필드
//   - resolveRules(null) 폴백
//   - 야간 교대 + 커스텀 earlyWindow 조합
//
// 명명 규칙: SCENARIO-ARC-그룹번호 (ARC = Attendance Rules Custom)

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/utils/attendance_rounding_helper.dart';

// ── 기준 날짜 / 계약 기준점 ───────────────────────────────────
final _date = DateTime(2026, 1, 15);
final _cIn  = DateTime(2026, 1, 15,  9,  0);   // 계약 출근 09:00
final _cOut = DateTime(2026, 1, 15, 18,  0);   // 계약 퇴근 18:00
// 야간 교대 22:00 ~ 06:00
final _nIn  = DateTime(2026, 1, 15, 22,  0);

// ── 공통 헬퍼 ────────────────────────────────────────────────

/// 출근 반올림 결과 전체 반환
RoundingResult _in(int offsetMin, AttendanceRules rules) =>
    processCheckin(offsetMinutes: offsetMin, referenceAt: _cIn, rules: rules);

/// 퇴근 반올림 결과 전체 반환 (referenceAt = _cOut)
RoundingResult _out(int offsetMin, AttendanceRules rules) =>
    processCheckout(offsetMinutes: offsetMin, referenceAt: _cOut, rules: rules);

/// 출근 반올림 결과 전체 반환 (referenceAt 지정)
RoundingResult _inAt(int offsetMin, DateTime ref, AttendanceRules rules) =>
    processCheckin(offsetMinutes: offsetMin, referenceAt: ref, rules: rules);

/// 퇴근 반올림 결과 전체 반환 (referenceAt 지정)
RoundingResult _outAt(int offsetMin, DateTime ref, AttendanceRules rules) =>
    processCheckout(offsetMinutes: offsetMin, referenceAt: ref, rules: rules);

/// isZeroWork 판정용 — 반올림 후 순 근무 분 (음수 → 0 clamp)
int _workMinutes(DateTime checkInRounded, DateTime checkOutRounded) {
  final diff = checkOutRounded.difference(checkInRounded).inMinutes;
  return diff < 0 ? 0 : diff;
}

void main() {

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-01: earlyWindow=0 — 1분 조기 도착도 즉시 조출
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-01: earlyWindow=0', () {
    const rules = AttendanceRules(earlyWindow: 0);

    test('ARC-01-1: offset=0 → 정시 (earlyWindow=0이어도 정각은 정시)', () {
      final r = _in(0, rules);
      expect(r.type, RoundingType.onTime);
      expect(r.roundedOffset, 0);
    });

    test('ARC-01-2: offset=-1 → 즉시 조출, earlyArrivalUnit=30으로 올림 → roundedOffset=0 → 09:00', () {
      // (-1 ~/ 30) * 30 = 0 * 30 = 0 (Dart ~/ 는 zero-truncation)
      final r = _in(-1, rules);
      expect(r.type, RoundingType.earlyArrival);
      expect(r.roundedOffset, 0);
      expect(r.rounded, '09:00');
    });

    test('ARC-01-3: offset=-30 → 조출, roundedOffset=-30 → 08:30', () {
      // (-30 ~/ 30) * 30 = -1 * 30 = -30
      final r = _in(-30, rules);
      expect(r.type, RoundingType.earlyArrival);
      expect(r.roundedOffset, -30);
      expect(r.rounded, '08:30');
    });

    test('ARC-01-4: offset=-31 → 조출, roundedOffset=-30 → 08:30', () {
      // (-31 ~/ 30) * 30 = -1 * 30 = -30 (truncate toward 0: -31/30=-1.033→-1)
      final r = _in(-31, rules);
      expect(r.type, RoundingType.earlyArrival);
      expect(r.roundedOffset, -30);
      expect(r.rounded, '08:30');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-02: earlyWindow=60 — 60분 이내 조출은 정시 처리
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-02: earlyWindow=60', () {
    const rules = AttendanceRules(earlyWindow: 60);

    test('ARC-02-1: offset=-59 → 정시 (60분 이내)', () {
      final r = _in(-59, rules);
      expect(r.type, RoundingType.onTime);
      expect(r.roundedOffset, 0);
    });

    test('ARC-02-2: offset=-60 → 정시 (경계: NOT < -60)', () {
      // earlyWindow=60, 조건 offsetMinutes < -60이므로 -60은 해당 없음
      final r = _in(-60, rules);
      expect(r.type, RoundingType.onTime);
      expect(r.roundedOffset, 0);
      expect(r.rounded, '09:00');
    });

    test('ARC-02-3: offset=-61 → 조출 (경계+1), roundedOffset=-60 → 08:00', () {
      // (-61 ~/ 30) * 30: -61/30=-2.033→-2, -2*30=-60
      final r = _in(-61, rules);
      expect(r.type, RoundingType.earlyArrival);
      expect(r.roundedOffset, -60);
      expect(r.rounded, '08:00');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-03: earlyWindow=120 — 2시간 이내 조출은 정시 처리
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-03: earlyWindow=120', () {
    const rules = AttendanceRules(earlyWindow: 120);

    test('ARC-03-1: offset=-119 → 정시 (120분 이내)', () {
      final r = _in(-119, rules);
      expect(r.type, RoundingType.onTime);
      expect(r.roundedOffset, 0);
    });

    test('ARC-03-2: offset=-120 → 정시 (경계: NOT < -120)', () {
      final r = _in(-120, rules);
      expect(r.type, RoundingType.onTime);
      expect(r.roundedOffset, 0);
    });

    test('ARC-03-3: offset=-121 → 조출, roundedOffset=-120 → 07:00', () {
      // (-121 ~/ 30) * 30: -121/30=-4.033→-4, -4*30=-120
      final r = _in(-121, rules);
      expect(r.type, RoundingType.earlyArrival);
      expect(r.roundedOffset, -120);
      expect(r.rounded, '07:00');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-04: earlyWindow=30 경계 정밀 검증 (기본값 경계)
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-04: earlyWindow=30 경계 정밀', () {
    const rules = AttendanceRules(earlyWindow: 30);

    test('ARC-04-1: offset=-30 → 정시 (NOT < -30)', () {
      final r = _in(-30, rules);
      expect(r.type, RoundingType.onTime);
      expect(r.roundedOffset, 0);
    });

    test('ARC-04-2: offset=-31 → 조출, roundedOffset=-30 → 08:30', () {
      final r = _in(-31, rules);
      expect(r.type, RoundingType.earlyArrival);
      expect(r.roundedOffset, -30);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-05: lateWindow=0 — 1분 초과 퇴근도 즉시 연장
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-05: lateWindow=0', () {
    const rules = AttendanceRules(lateWindow: 0);

    test('ARC-05-1: offset=0 → 정시 (정각은 정시)', () {
      final r = _out(0, rules);
      expect(r.type, RoundingType.onTimeOut);
      expect(r.roundedOffset, 0);
    });

    test('ARC-05-2: offset=1 → 즉시 연장, overtimeUnit=10 → floor → roundedOffset=0 → 18:00', () {
      // (1 ~/ 10) * 10 = 0 (floor toward contractEnd)
      final r = _out(1, rules);
      expect(r.type, RoundingType.overtime);
      expect(r.roundedOffset, 0);
      expect(r.rounded, '18:00');
    });

    test('ARC-05-3: offset=10 → 연장 10분, roundedOffset=10 → 18:10', () {
      final r = _out(10, rules);
      expect(r.type, RoundingType.overtime);
      expect(r.roundedOffset, 10);
      expect(r.rounded, '18:10');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-06: lateWindow=15 — 15분 이내는 정시 퇴근
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-06: lateWindow=15', () {
    const rules = AttendanceRules(lateWindow: 15);

    test('ARC-06-1: offset=15 → 정시 (경계: NOT > 15)', () {
      final r = _out(15, rules);
      expect(r.type, RoundingType.onTimeOut);
      expect(r.roundedOffset, 0);
    });

    test('ARC-06-2: offset=16 → 연장, overtimeUnit=10 → (16~/10)*10=10 → 18:10', () {
      final r = _out(16, rules);
      expect(r.type, RoundingType.overtime);
      expect(r.roundedOffset, 10);
      expect(r.rounded, '18:10');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-07: lateWindow=60 — 60분 이내는 정시 퇴근
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-07: lateWindow=60', () {
    const rules = AttendanceRules(lateWindow: 60);

    test('ARC-07-1: offset=60 → 정시 (경계: NOT > 60)', () {
      final r = _out(60, rules);
      expect(r.type, RoundingType.onTimeOut);
      expect(r.roundedOffset, 0);
    });

    test('ARC-07-2: offset=61 → 연장, (61~/10)*10=60 → 19:00', () {
      final r = _out(61, rules);
      expect(r.type, RoundingType.overtime);
      expect(r.roundedOffset, 60);
      expect(r.rounded, '19:00');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-08: lateWindow=30 경계 정밀 검증 (기본값 경계)
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-08: lateWindow=30 경계 정밀', () {
    const rules = AttendanceRules(lateWindow: 30);

    test('ARC-08-1: offset=30 → 정시 (NOT > 30)', () {
      final r = _out(30, rules);
      expect(r.type, RoundingType.onTimeOut);
      expect(r.roundedOffset, 0);
    });

    test('ARC-08-2: offset=31 → 연장, (31~/10)*10=30 → 18:30', () {
      final r = _out(31, rules);
      expect(r.type, RoundingType.overtime);
      expect(r.roundedOffset, 30);
      expect(r.rounded, '18:30');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-09: lateGrace=0 — 1분도 지각
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-09: lateGrace=0', () {
    const rules = AttendanceRules(lateGrace: 0);

    test('ARC-09-1: offset=0 → 정시', () {
      final r = _in(0, rules);
      expect(r.type, RoundingType.onTime);
      expect(r.roundedOffset, 0);
    });

    test('ARC-09-2: offset=1 → 즉시 지각, lateUnit=30 → ceil(1/30)*30=30 → 09:30', () {
      // ((1 + 30 - 1) ~/ 30) * 30 = (30 ~/ 30) * 30 = 30
      final r = _in(1, rules);
      expect(r.type, RoundingType.late);
      expect(r.roundedOffset, 30);
      expect(r.rounded, '09:30');
    });

    test('ARC-09-3: offset=-1 → 정시 (조기 도착은 earlyWindow 기준)', () {
      // earlyWindow=30(default), -1 < -30? NO. -1 <= 0 → onTime
      final r = _in(-1, rules);
      expect(r.type, RoundingType.onTime);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-10: lateGrace=30 — 30분 이내는 정시 처리
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-10: lateGrace=30', () {
    const rules = AttendanceRules(lateGrace: 30);

    test('ARC-10-1: offset=30 → 지각 유예 (경계: NOT > 30)', () {
      final r = _in(30, rules);
      expect(r.type, RoundingType.lateGrace);
      expect(r.roundedOffset, 0);
      expect(r.rounded, '09:00');
    });

    test('ARC-10-2: offset=31 → 지각, ceil(31/30)*30=60 → 10:00', () {
      // ((31 + 30 - 1) ~/ 30) * 30 = (60 ~/ 30) * 30 = 60
      final r = _in(31, rules);
      expect(r.type, RoundingType.late);
      expect(r.roundedOffset, 60);
      expect(r.rounded, '10:00');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-11: lateGrace=5 경계 정밀 검증 (기본값 경계)
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-11: lateGrace=5 경계 정밀', () {
    const rules = AttendanceRules(lateGrace: 5);

    test('ARC-11-1: offset=5 → 지각 유예 (NOT > 5)', () {
      final r = _in(5, rules);
      expect(r.type, RoundingType.lateGrace);
      expect(r.roundedOffset, 0);
    });

    test('ARC-11-2: offset=6 → 지각, ceil(6/30)*30=30 → 09:30', () {
      // ((6 + 30 - 1) ~/ 30) * 30 = (35 ~/ 30) * 30 = 1 * 30 = 30
      final r = _in(6, rules);
      expect(r.type, RoundingType.late);
      expect(r.roundedOffset, 30);
      expect(r.rounded, '09:30');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-12: 모든 단위 5분 (최소값) — 세밀한 반올림
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-12: 모든 단위=5 (최소)', () {
    const rules = AttendanceRules(
      earlyArrivalUnit: 5,
      lateUnit:         5,
      overtimeUnit:     5,
      earlyLeaveUnit:   5,
    );

    // earlyWindow=30이므로 offset < -30이면 조출
    test('ARC-12-1: 조출 offset=-31 → ceil toward 0: (-31~/5)*5=-30 → 08:30', () {
      // -31 ~/ 5 = -6 (truncate toward 0: -31/5=-6.2→-6), -6*5=-30
      final r = _in(-31, rules);
      expect(r.type, RoundingType.earlyArrival);
      expect(r.roundedOffset, -30);
      expect(r.rounded, '08:30');
    });

    test('ARC-12-2: 조출 offset=-35 → (-35~/5)*5=-35 → 08:25', () {
      final r = _in(-35, rules);
      expect(r.roundedOffset, -35);
      expect(r.rounded, '08:25');
    });

    test('ARC-12-3: 조출 offset=-36 → (-36~/5)*5=-35 → 08:25', () {
      // -36/5=-7.2→truncate→-7, -7*5=-35
      final r = _in(-36, rules);
      expect(r.roundedOffset, -35);
      expect(r.rounded, '08:25');
    });

    test('ARC-12-4: 지각 offset=6 → ceil(6/5)*5=10 → 09:10', () {
      // ((6 + 5 - 1) ~/ 5) * 5 = (10 ~/ 5) * 5 = 10
      final r = _in(6, rules);
      expect(r.type, RoundingType.late);
      expect(r.roundedOffset, 10);
      expect(r.rounded, '09:10');
    });

    test('ARC-12-5: 지각 offset=11 → ceil(11/5)*5=15 → 09:15', () {
      // ((11 + 5 - 1) ~/ 5) * 5 = (15 ~/ 5) * 5 = 15
      final r = _in(11, rules);
      expect(r.roundedOffset, 15);
    });

    test('ARC-12-6: 연장 offset=31 → floor: (31~/5)*5=30 → 18:30', () {
      final r = _out(31, rules);
      expect(r.type, RoundingType.overtime);
      expect(r.roundedOffset, 30);
      expect(r.rounded, '18:30');
    });

    test('ARC-12-7: 조퇴 offset=-6 → ceil(6/5)*5=10 → roundedOffset=-10 → 17:50', () {
      // earlyDiff=6, ((6+5-1)~/5)*5 = (10~/5)*5 = 10, rounded=-10
      final r = _out(-6, rules);
      expect(r.type, RoundingType.earlyLeave);
      expect(r.roundedOffset, -10);
      expect(r.rounded, '17:50');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-13: 단위 최대값 조합
  // earlyArrivalUnit=60, lateUnit=60, overtimeUnit=30, earlyLeaveUnit=60
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-13: 단위 최대값', () {
    const rules = AttendanceRules(
      earlyArrivalUnit: 60,
      lateUnit:         60,
      overtimeUnit:     30,   // max=30
      earlyLeaveUnit:   60,
    );

    test('ARC-13-1: 조출 offset=-31 → (-31~/60)*60=0 → roundedAt=contractStart(09:00)', () {
      // -31/60=-0.516→truncate toward 0→0, 0*60=0
      final r = _in(-31, rules);
      expect(r.type, RoundingType.earlyArrival);
      expect(r.roundedOffset, 0);
      expect(r.rounded, '09:00'); // 조출 분류지만 기록 시각은 정각
    });

    test('ARC-13-2: 조출 offset=-60 → (-60~/60)*60=-60 → 08:00', () {
      final r = _in(-60, rules);
      expect(r.type, RoundingType.earlyArrival);
      expect(r.roundedOffset, -60);
      expect(r.rounded, '08:00');
    });

    test('ARC-13-3: 조출 offset=-61 → (-61~/60)*60=-60 → 08:00', () {
      // -61/60=-1.016→-1, -1*60=-60
      final r = _in(-61, rules);
      expect(r.roundedOffset, -60);
      expect(r.rounded, '08:00');
    });

    test('ARC-13-4: 지각 offset=6 → ceil(6/60)*60=60 → 10:00', () {
      // ((6 + 60 - 1) ~/ 60) * 60 = (65 ~/ 60) * 60 = 1 * 60 = 60
      final r = _in(6, rules);
      expect(r.type, RoundingType.late);
      expect(r.roundedOffset, 60);
      expect(r.rounded, '10:00');
    });

    test('ARC-13-5: 지각 offset=60 → ceil(60/60)*60=60 → 10:00', () {
      // ((60 + 60 - 1) ~/ 60) * 60 = (119 ~/ 60) * 60 = 1 * 60 = 60
      final r = _in(60, rules);
      expect(r.roundedOffset, 60);
    });

    test('ARC-13-6: 지각 offset=61 → ceil(61/60)*60=120 → 11:00', () {
      // ((61 + 60 - 1) ~/ 60) * 60 = (120 ~/ 60) * 60 = 2 * 60 = 120
      final r = _in(61, rules);
      expect(r.roundedOffset, 120);
      expect(r.rounded, '11:00');
    });

    test('ARC-13-7: 연장 offset=31 → (31~/30)*30=30 → 18:30', () {
      final r = _out(31, rules);
      expect(r.type, RoundingType.overtime);
      expect(r.roundedOffset, 30);
    });

    test('ARC-13-8: 조퇴 offset=-1 → ceil(1/60)*60=60 → roundedOffset=-60 → 17:00', () {
      // earlyDiff=1, ((1+60-1)~/60)*60 = (60~/60)*60 = 60, rounded=-60
      final r = _out(-1, rules);
      expect(r.type, RoundingType.earlyLeave);
      expect(r.roundedOffset, -60);
      expect(r.rounded, '17:00');
    });

    test('ARC-13-9: 조퇴 offset=-61 → ceil(61/60)*60=120 → roundedOffset=-120 → 16:00', () {
      // earlyDiff=61, ((61+60-1)~/60)*60 = (120~/60)*60 = 120
      final r = _out(-61, rules);
      expect(r.roundedOffset, -120);
      expect(r.rounded, '16:00');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-14: 혼합 커스텀 단위
  // earlyArrivalUnit=15, lateUnit=30, overtimeUnit=5, earlyLeaveUnit=15
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-14: 혼합 커스텀 단위', () {
    const rules = AttendanceRules(
      earlyArrivalUnit: 15,
      lateUnit:         30,
      overtimeUnit:      5,
      earlyLeaveUnit:   15,
    );

    test('ARC-14-1: 조출 offset=-31 → (-31~/15)*15=-30 → 08:30', () {
      // -31/15=-2.066→-2, -2*15=-30
      final r = _in(-31, rules);
      expect(r.type, RoundingType.earlyArrival);
      expect(r.roundedOffset, -30);
      expect(r.rounded, '08:30');
    });

    test('ARC-14-2: 조출 offset=-45 → (-45~/15)*15=-45 → 08:15', () {
      final r = _in(-45, rules);
      expect(r.roundedOffset, -45);
      expect(r.rounded, '08:15');
    });

    test('ARC-14-3: 조출 offset=-46 → (-46~/15)*15=-45 → 08:15', () {
      // -46/15=-3.066→-3, -3*15=-45
      final r = _in(-46, rules);
      expect(r.roundedOffset, -45);
      expect(r.rounded, '08:15');
    });

    test('ARC-14-4: 지각 offset=6 (lateUnit=30) → ceil(6/30)*30=30 → 09:30', () {
      final r = _in(6, rules);
      expect(r.type, RoundingType.late);
      expect(r.roundedOffset, 30);
    });

    test('ARC-14-5: 지각 offset=31 (lateUnit=30) → ceil(31/30)*30=60 → 10:00', () {
      // ((31+30-1)~/30)*30 = (60~/30)*30 = 60
      final r = _in(31, rules);
      expect(r.roundedOffset, 60);
      expect(r.rounded, '10:00');
    });

    test('ARC-14-6: 연장 offset=31 (overtimeUnit=5) → (31~/5)*5=30 → 18:30', () {
      final r = _out(31, rules);
      expect(r.type, RoundingType.overtime);
      expect(r.roundedOffset, 30);
    });

    test('ARC-14-7: 연장 offset=36 (overtimeUnit=5) → (36~/5)*5=35 → 18:35', () {
      final r = _out(36, rules);
      expect(r.roundedOffset, 35);
      expect(r.rounded, '18:35');
    });

    test('ARC-14-8: 조퇴 offset=-1 (earlyLeaveUnit=15) → ceil(1/15)*15=15 → roundedOffset=-15 → 17:45', () {
      // earlyDiff=1, ((1+15-1)~/15)*15 = (15~/15)*15 = 15
      final r = _out(-1, rules);
      expect(r.type, RoundingType.earlyLeave);
      expect(r.roundedOffset, -15);
      expect(r.rounded, '17:45');
    });

    test('ARC-14-9: 조퇴 offset=-16 (earlyLeaveUnit=15) → ceil(16/15)*15=30 → roundedOffset=-30 → 17:30', () {
      // earlyDiff=16, ((16+15-1)~/15)*15 = (30~/15)*15 = 30
      final r = _out(-16, rules);
      expect(r.roundedOffset, -30);
      expect(r.rounded, '17:30');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-15: isZeroWork=true 발생 시나리오
  // 반올림 후 checkIn >= checkOut → 순 근무 0분
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-15: isZeroWork 발생 시나리오', () {
    // 계약 09:00-10:00 (60분 계약) — 짧은 계약에서 반올림 충돌 빈발
    final cIn60  = DateTime(2026, 1, 15,  9,  0);  // 계약 출근 09:00
    final cOut60 = DateTime(2026, 1, 15, 10,  0);  // 계약 퇴근 10:00
    const rulesDefault = AttendanceRules(); // 기본 규칙

    test('ARC-15-1: 지각 반올림(→09:30) = 조퇴 반올림(→09:30) → workMinutes=0', () {
      // checkIn 09:25 → offset=+25, lateGrace=5, lateUnit=30
      // ((25+30-1)~/30)*30 = (54~/30)*30 = 1*30=30 → 09:30
      final inR  = processCheckin(
        offsetMinutes: 25, referenceAt: cIn60, rules: rulesDefault);
      // checkOut 09:35 → offset=-25 from 10:00, earlyLeaveUnit=30
      // earlyDiff=25, ((25+30-1)~/30)*30=(54~/30)*30=30 → roundedOffset=-30 → 09:30
      final outR = processCheckout(
        offsetMinutes: -25, referenceAt: cOut60, rules: rulesDefault);

      expect(inR.roundedAt,  DateTime(2026, 1, 15, 9, 30), reason: '출근 09:30으로 반올림');
      expect(outR.roundedAt, DateTime(2026, 1, 15, 9, 30), reason: '퇴근 09:30으로 반올림');
      expect(_workMinutes(inR.roundedAt, outR.roundedAt), 0, reason: 'isZeroWork');
    });

    test('ARC-15-2: 지각 반올림 > 조퇴 반올림 (checkIn=10:00, checkOut=09:30) → workMinutes=0', () {
      // checkIn 09:31 → offset=+31, late: ((31+30-1)~/30)*30=(60~/30)*30=60 → 10:00
      final inR  = processCheckin(
        offsetMinutes: 31, referenceAt: cIn60, rules: rulesDefault);
      // checkOut 09:45 → offset=-15, earlyLeave: ceil(15/30)*30=30 → -30 → 09:30
      final outR = processCheckout(
        offsetMinutes: -15, referenceAt: cOut60, rules: rulesDefault);

      expect(inR.roundedAt,  DateTime(2026, 1, 15, 10, 0));
      expect(outR.roundedAt, DateTime(2026, 1, 15,  9, 30));
      expect(_workMinutes(inR.roundedAt, outR.roundedAt), 0, reason: '역전 → isZeroWork');
    });

    test('ARC-15-3: lateGrace=0 + 10분 계약 → lateUnit 반올림 후 역전 → workMinutes=0', () {
      // 계약 09:00-09:10 (10분), lateGrace=0
      final cIn10  = DateTime(2026, 1, 15,  9,  0);
      final cOut10 = DateTime(2026, 1, 15,  9, 10);
      const rulesNoGrace = AttendanceRules(lateGrace: 0);
      // checkIn 09:01 → offset=+1, lateGrace=0 → 즉시 지각
      // ((1+30-1)~/30)*30 = 30 → 09:30
      final inR  = processCheckin(
        offsetMinutes: 1, referenceAt: cIn10, rules: rulesNoGrace);
      // checkOut 09:10 → offset=0, onTimeOut → 09:10
      final outR = processCheckout(
        offsetMinutes: 0, referenceAt: cOut10, rules: rulesNoGrace);

      expect(inR.roundedAt,  DateTime(2026, 1, 15,  9, 30));
      expect(outR.roundedAt, DateTime(2026, 1, 15,  9, 10));
      expect(_workMinutes(inR.roundedAt, outR.roundedAt), 0, reason: '09:30 > 09:10 → isZeroWork');
    });

    test('ARC-15-4: 30분 계약 + 지각 6분 + 조퇴 5분 → 양쪽 반올림 역전 → workMinutes=0', () {
      // 계약 09:00-09:30 (30분)
      final cIn30  = DateTime(2026, 1, 15, 9,  0);
      final cOut30 = DateTime(2026, 1, 15, 9, 30);
      // checkIn 09:06 → offset=+6, lateGrace=5, late: ((6+30-1)~/30)*30=35~/30*30=30 → 09:30
      final inR = processCheckin(
        offsetMinutes: 6, referenceAt: cIn30, rules: const AttendanceRules());
      // checkOut 09:25 → offset=-5 from 09:30, earlyLeave: ceil(5/30)*30=30 → -30 → 09:00
      final outR = processCheckout(
        offsetMinutes: -5, referenceAt: cOut30, rules: const AttendanceRules());

      expect(inR.roundedAt,  DateTime(2026, 1, 15, 9, 30));
      expect(outR.roundedAt, DateTime(2026, 1, 15, 9,  0));
      expect(_workMinutes(inR.roundedAt, outR.roundedAt), 0);
    });

    test('ARC-15-5: 5분 계약 + 조퇴 1분 → earlyLeaveUnit=30으로 08:35 → checkIn 09:00 > 08:35 → isZeroWork', () {
      // 계약 09:00-09:05 (5분)
      final cIn5  = DateTime(2026, 1, 15, 9, 0);
      final cOut5 = DateTime(2026, 1, 15, 9, 5);
      // checkIn 09:04 → offset=+4, lateGrace=5 → lateGrace(정시) → 09:00
      final inR = processCheckin(
        offsetMinutes: 4, referenceAt: cIn5, rules: const AttendanceRules());
      // checkOut 09:04 → offset=-1 from 09:05, earlyLeave: ceil(1/30)*30=30 → -30 → 08:35
      final outR = processCheckout(
        offsetMinutes: -1, referenceAt: cOut5, rules: const AttendanceRules());

      expect(inR.roundedAt,  DateTime(2026, 1, 15, 9,  0));
      expect(outR.roundedAt, DateTime(2026, 1, 15, 8, 35));
      expect(_workMinutes(inR.roundedAt, outR.roundedAt), 0, reason: '09:00 > 08:35 → isZeroWork');
    });

    test('ARC-15-6: 정상 근무(09:06→09:30 + 17:45→17:30)는 isZeroWork=false (산티 체크)', () {
      // checkIn 09:06 → late 30분 → 09:30
      final inR = processCheckin(
        offsetMinutes: 6, referenceAt: _cIn, rules: const AttendanceRules());
      // checkOut 17:45 → earlyLeave 30분 → 17:30
      final outR = processCheckout(
        offsetMinutes: -15, referenceAt: _cOut, rules: const AttendanceRules());

      expect(inR.roundedAt,  DateTime(2026, 1, 15,  9, 30));
      expect(outR.roundedAt, DateTime(2026, 1, 15, 17, 30));
      final workMin = _workMinutes(inR.roundedAt, outR.roundedAt);
      expect(workMin, 480, reason: '17:30 - 09:30 = 480분 → 정상 근무');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-16: AttendanceRules.fromMap clamp 방어
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-16: fromMap clamp 방어', () {
    test('ARC-16-1: earlyWindow=150 → clamp(0,120) → 120', () {
      final r = AttendanceRules.fromMap({'earlyWindow': 150});
      expect(r.earlyWindow, 120);
    });

    test('ARC-16-2: earlyWindow=-5 → clamp(0,120) → 0', () {
      final r = AttendanceRules.fromMap({'earlyWindow': -5});
      expect(r.earlyWindow, 0);
    });

    test('ARC-16-3: earlyArrivalUnit=3 → clamp(5,60) → 5', () {
      final r = AttendanceRules.fromMap({'earlyArrivalUnit': 3});
      expect(r.earlyArrivalUnit, 5);
    });

    test('ARC-16-4: earlyArrivalUnit=70 → clamp(5,60) → 60', () {
      final r = AttendanceRules.fromMap({'earlyArrivalUnit': 70});
      expect(r.earlyArrivalUnit, 60);
    });

    test('ARC-16-5: lateGrace=35 → clamp(0,30) → 30', () {
      final r = AttendanceRules.fromMap({'lateGrace': 35});
      expect(r.lateGrace, 30);
    });

    test('ARC-16-6: lateUnit=2 → clamp(5,60) → 5', () {
      final r = AttendanceRules.fromMap({'lateUnit': 2});
      expect(r.lateUnit, 5);
    });

    test('ARC-16-7: lateWindow=70 → clamp(0,60) → 60', () {
      final r = AttendanceRules.fromMap({'lateWindow': 70});
      expect(r.lateWindow, 60);
    });

    test('ARC-16-8: overtimeUnit=4 → clamp(5,30) → 5', () {
      final r = AttendanceRules.fromMap({'overtimeUnit': 4});
      expect(r.overtimeUnit, 5);
    });

    test('ARC-16-9: overtimeUnit=35 → clamp(5,30) → 30', () {
      final r = AttendanceRules.fromMap({'overtimeUnit': 35});
      expect(r.overtimeUnit, 30);
    });

    test('ARC-16-10: earlyLeaveUnit=70 → clamp(5,60) → 60', () {
      final r = AttendanceRules.fromMap({'earlyLeaveUnit': 70});
      expect(r.earlyLeaveUnit, 60);
    });

    test('ARC-16-11: 모든 필드 동시 범위 초과 → 각 clamp 상한/하한 적용', () {
      final r = AttendanceRules.fromMap({
        'earlyWindow':      999,
        'earlyArrivalUnit': 999,
        'lateGrace':        999,
        'lateUnit':         999,
        'lateWindow':       999,
        'overtimeUnit':     999,
        'earlyLeaveUnit':   999,
      });
      expect(r.earlyWindow,       120);
      expect(r.earlyArrivalUnit,   60);
      expect(r.lateGrace,          30);
      expect(r.lateUnit,           60);
      expect(r.lateWindow,         60);
      expect(r.overtimeUnit,       30);
      expect(r.earlyLeaveUnit,     60);
    });

    test('ARC-16-12: 모든 필드 최소 미달 → 각 clamp 하한 적용', () {
      final r = AttendanceRules.fromMap({
        'earlyWindow':       -1,
        'earlyArrivalUnit':  -1,
        'lateGrace':         -1,
        'lateUnit':          -1,
        'lateWindow':        -1,
        'overtimeUnit':      -1,
        'earlyLeaveUnit':    -1,
      });
      expect(r.earlyWindow,       0);
      expect(r.earlyArrivalUnit,  5);
      expect(r.lateGrace,         0);
      expect(r.lateUnit,          5);
      expect(r.lateWindow,        0);
      expect(r.overtimeUnit,      5);
      expect(r.earlyLeaveUnit,    5);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-17: resolveRules(null) 폴백 검증
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-17: resolveRules(null) 폴백', () {
    test('ARC-17-1: null 전달 → defaults() 반환', () {
      final r = resolveRules(null);
      expect(r.earlyWindow,      30);
      expect(r.earlyArrivalUnit, 30);
      expect(r.lateGrace,         5);
      expect(r.lateUnit,         30);
      expect(r.lateWindow,       30);
      expect(r.overtimeUnit,     10);
      expect(r.earlyLeaveUnit,   30);
    });

    test('ARC-17-2: 비null 전달 → 그대로 반환', () {
      const custom = AttendanceRules(lateGrace: 10);
      final r = resolveRules(custom);
      expect(r.lateGrace, 10, reason: '커스텀 값 그대로 유지');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // SCENARIO-ARC-18: 야간 교대(22:00~06:00) + earlyWindow=60
  // ═══════════════════════════════════════════════════════════
  group('SCENARIO-ARC-18: 야간 교대 + earlyWindow=60', () {
    // 야간 계약 22:00, referenceAt = _nIn = DateTime(2026,1,15,22,0)
    const rules = AttendanceRules(earlyWindow: 60);

    test('ARC-18-1: 21:01 도착 → offset=-59 → earlyWindow=60 이내 → 정시', () {
      final punch = DateTime(2026, 1, 15, 21, 1);
      final offset = punch.difference(_nIn).inMinutes; // -59
      final r = _inAt(offset, _nIn, rules);
      expect(r.type, RoundingType.onTime);
      expect(r.rounded, '22:00');
    });

    test('ARC-18-2: 21:00 도착 → offset=-60 → 경계(NOT < -60) → 정시', () {
      final punch = DateTime(2026, 1, 15, 21, 0);
      final offset = punch.difference(_nIn).inMinutes; // -60
      expect(offset, -60);
      final r = _inAt(offset, _nIn, rules);
      expect(r.type, RoundingType.onTime,
          reason: '-60은 < -60이 아니므로 정시');
      expect(r.rounded, '22:00');
    });

    test('ARC-18-3: 20:59 도착 → offset=-61 → 조출, earlyArrivalUnit=30 → roundedOffset=-60 → 21:00', () {
      final punch = DateTime(2026, 1, 15, 20, 59);
      final offset = punch.difference(_nIn).inMinutes; // -61
      // (-61 ~/ 30) * 30: -61/30=-2.033→-2, -2*30=-60
      final r = _inAt(offset, _nIn, rules);
      expect(r.type, RoundingType.earlyArrival);
      expect(r.roundedOffset, -60);
      expect(r.rounded, '21:00');
    });

    test('ARC-18-4: 22:00 도착 → offset=0 → 정시', () {
      final r = _inAt(0, _nIn, rules);
      expect(r.type, RoundingType.onTime);
      expect(r.rounded, '22:00');
    });

    test('ARC-18-5: 21:30 도착 → offset=-30 → earlyWindow=60 이내 → 정시', () {
      final punch = DateTime(2026, 1, 15, 21, 30);
      final offset = punch.difference(_nIn).inMinutes; // -30
      final r = _inAt(offset, _nIn, rules);
      expect(r.type, RoundingType.onTime);
      expect(r.rounded, '22:00');
    });
  });
}
