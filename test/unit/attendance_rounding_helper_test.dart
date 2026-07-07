// test/unit/attendance_rounding_helper_test.dart
//
// 출퇴근 자동 반올림 단위 테스트 — DateTime 오프셋 기반
//
// 핵심 설계:
//   processCheckin  offsetMinutes = punchAt.difference(contractStart).inMinutes
//   processCheckout offsetMinutes = punchAt.difference(contractEnd).inMinutes
//
// 음수 = 계약 기준보다 이른 펀치, 양수 = 늦은 펀치
// 날짜를 포함한 DateTime을 사용하므로 야간 교대·자정 출근 등
// 모든 경계가 특수 처리 없이 자연스럽게 해결된다.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/utils/attendance_rounding_helper.dart';

// ── 기본 규칙 ─────────────────────────────────────────────────
const AttendanceRules _rules = AttendanceRules(
  earlyWindow:      30,
  earlyArrivalUnit: 30,
  lateGrace:        5,
  lateUnit:         30,
  lateWindow:       30,
  overtimeUnit:     10,
  earlyLeaveUnit:   30,
);

// ── 기준 날짜 (고정 — 요일/월 무관) ─────────────────────────
final _date  = DateTime(2026, 1, 15);            // 기준 근무일
final _cIn   = DateTime(2026, 1, 15,  9,  0);   // 계약 출근 09:00
final _cOut  = DateTime(2026, 1, 15, 18,  0);   // 계약 퇴근 18:00

// 야간 교대 22:00 ~ 06:00 (자정 교차)
final _nIn   = DateTime(2026, 1, 15, 22,  0);   // 계약 출근 22:00
final _nOut  = DateTime(2026, 1, 16,  6,  0);   // 계약 퇴근 06:00 (다음날)

// ── 헬퍼 — 같은날 시:분으로 펀치 시뮬레이션 ─────────────────
DateTime _punch(int h, int m, {bool nextDay = false}) {
  final d = nextDay ? _date.add(const Duration(days: 1)) : _date;
  return DateTime(d.year, d.month, d.day, h, m);
}

String _checkIn(int h, int m) {
  final punch = _punch(h, m);
  final offset = punch.difference(_cIn).inMinutes;
  return processCheckin(
    offsetMinutes: offset,
    referenceAt: _cIn,
    rules: _rules,
  ).rounded;
}

RoundingType _checkInType(int h, int m) {
  final punch = _punch(h, m);
  final offset = punch.difference(_cIn).inMinutes;
  return processCheckin(
    offsetMinutes: offset,
    referenceAt: _cIn,
    rules: _rules,
  ).type;
}

String _checkOut(int h, int m) {
  final punch = _punch(h, m);
  final offset = punch.difference(_cOut).inMinutes;
  return processCheckout(
    offsetMinutes: offset,
    referenceAt: _cOut,
    rules: _rules,
  ).rounded;
}

RoundingType _checkOutType(int h, int m) {
  final punch = _punch(h, m);
  final offset = punch.difference(_cOut).inMinutes;
  return processCheckout(
    offsetMinutes: offset,
    referenceAt: _cOut,
    rules: _rules,
  ).type;
}

// 야간 교대 헬퍼 — 자정 이후(00~12시)는 다음날로 판단
String _nightIn(int h, int m) {
  final isNextDay = h < 12; // 00~11 = 자정 이후 다음날 파트
  final punch = _punch(h, m, nextDay: isNextDay);
  final offset = punch.difference(_nIn).inMinutes;
  return processCheckin(
    offsetMinutes: offset,
    referenceAt: _nIn,
    rules: _rules,
  ).rounded;
}

RoundingType _nightInType(int h, int m) {
  final isNextDay = h < 12;
  final punch = _punch(h, m, nextDay: isNextDay);
  final offset = punch.difference(_nIn).inMinutes;
  return processCheckin(
    offsetMinutes: offset,
    referenceAt: _nIn,
    rules: _rules,
  ).type;
}

String _nightOut(int h, int m) {
  final punch = _punch(h, m, nextDay: true); // 퇴근은 항상 다음날
  final offset = punch.difference(_nOut).inMinutes;
  return processCheckout(
    offsetMinutes: offset,
    referenceAt: _nOut,
    rules: _rules,
  ).rounded;
}

void main() {
  // ═══════════════════════════════════════════════════════════
  // 1. contractStartAt / contractEndAt 유틸 검증
  // ═══════════════════════════════════════════════════════════
  group('contractStartAt / contractEndAt', () {
    test('contractStartAt: 09:00 → 2026-01-15 09:00', () {
      final dt = contractStartAt(_date, '09:00');
      expect(dt, DateTime(2026, 1, 15, 9, 0));
    });

    test('contractEndAt 일반: 18:00 → 당일 18:00', () {
      final dt = contractEndAt(_date, '09:00', '18:00');
      expect(dt, DateTime(2026, 1, 15, 18, 0));
    });

    test('contractEndAt 야간 교대: 22:00~06:00 → 다음날 06:00', () {
      final dt = contractEndAt(_date, '22:00', '06:00');
      expect(dt, DateTime(2026, 1, 16, 6, 0));
    });

    test('contractEndAt 자정 시작: 00:00~08:00 → 당일 08:00 (start=end이 아니므로 당일)', () {
      final dt = contractEndAt(_date, '00:00', '08:00');
      expect(dt, DateTime(2026, 1, 15, 8, 0));
    });

    test('contractEndAt 자정 종료: 16:00~00:00 → 다음날 00:00 (end<=start)', () {
      final dt = contractEndAt(_date, '16:00', '00:00');
      expect(dt, DateTime(2026, 1, 16, 0, 0));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 2. 출근 — 조출 (조출 earlyWindow 초과, ceil toward start)
  // ═══════════════════════════════════════════════════════════
  group('출근 — 조출 (ceil toward contractStart)', () {
    // offsetMinutes = punch - cIn
    // Dart ~/ : zero-truncation → 음수에서 0(contractStart) 방향으로 올림

    test('08:20 → 08:30 (offset=-40, (-40~/30)*30=-30)', () {
      expect(_checkIn(8, 20), '08:30');
      expect(_checkInType(8, 20), RoundingType.earlyArrival);
    });

    test('08:00 → 08:00 (offset=-60, (-60~/30)*30=-60)', () {
      expect(_checkIn(8, 0), '08:00');
    });

    test('08:01 → 08:30 (offset=-59, (-59~/30)*30=-30)', () {
      expect(_checkIn(8, 1), '08:30');
    });

    test('07:31 → 08:00 (offset=-89, (-89~/30)*30=-60)', () {
      expect(_checkIn(7, 31), '08:00');
    });

    test('07:30 → 07:30 (offset=-90, (-90~/30)*30=-90)', () {
      expect(_checkIn(7, 30), '07:30');
    });

    test('조출 경계: 08:29 → 조출 (offset=-31 < -earlyWindow(-30))', () {
      expect(_checkInType(8, 29), RoundingType.earlyArrival);
      expect(_checkIn(8, 29), '08:30');
    });

    test('조출 경계: 08:30 → 정시 (offset=-30, NOT < -30)', () {
      expect(_checkIn(8, 30), '09:00');
      expect(_checkInType(8, 30), RoundingType.onTime);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 3. 출근 — 정시 / 지각 유예
  // ═══════════════════════════════════════════════════════════
  group('출근 — 정시 / 지각 유예', () {
    test('09:00 → 정시 (offset=0)', () {
      expect(_checkIn(9, 0), '09:00');
      expect(_checkInType(9, 0), RoundingType.onTime);
    });

    test('09:05 → 정시 (offset=5 = lateGrace)', () {
      expect(_checkIn(9, 5), '09:00');
      expect(_checkInType(9, 5), RoundingType.lateGrace);
    });

    test('09:06 → 지각 (offset=6 > lateGrace)', () {
      expect(_checkInType(9, 6), RoundingType.late);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 4. 출근 — 지각 (ceil: 보수적 방향)
  // ═══════════════════════════════════════════════════════════
  group('출근 — 지각 (ceil)', () {
    test('09:06 → 09:30 (offset=6, ceil(6/30)*30=30)', () {
      expect(_checkIn(9, 6), '09:30');
    });

    test('09:30 → 09:30 (offset=30, ceil(30/30)*30=30)', () {
      expect(_checkIn(9, 30), '09:30');
    });

    test('09:31 → 10:00 (offset=31, ceil(31/30)*30=60)', () {
      expect(_checkIn(9, 31), '10:00');
    });

    test('10:00 → 10:00 (offset=60, ceil(60/30)*30=60)', () {
      expect(_checkIn(10, 0), '10:00');
    });

    test('10:01 → 10:30 (offset=61)', () {
      expect(_checkIn(10, 1), '10:30');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 5. 퇴근 — 정시 (lateWindow 이내)
  // ═══════════════════════════════════════════════════════════
  group('퇴근 — 정시 (lateWindow 이내)', () {
    test('18:00 → 18:00 (offset=0)', () {
      expect(_checkOut(18, 0), '18:00');
      expect(_checkOutType(18, 0), RoundingType.onTimeOut);
    });

    test('18:30 → 18:00 (offset=30 = lateWindow)', () {
      expect(_checkOut(18, 30), '18:00');
      expect(_checkOutType(18, 30), RoundingType.onTimeOut);
    });

    test('18:31 → 연장 시작 (offset=31 > lateWindow)', () {
      expect(_checkOutType(18, 31), RoundingType.overtime);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 6. 퇴근 — 연장 (floor toward contractEnd)
  // ═══════════════════════════════════════════════════════════
  group('퇴근 — 연장 (floor toward contractEnd)', () {
    test('18:35 → 18:30 (offset=35, (35~/10)*10=30)', () {
      expect(_checkOut(18, 35), '18:30');
      expect(_checkOutType(18, 35), RoundingType.overtime);
    });

    test('18:40 → 18:40 (offset=40, (40~/10)*10=40)', () {
      expect(_checkOut(18, 40), '18:40');
    });

    test('18:59 → 18:50 (offset=59, (59~/10)*10=50)', () {
      expect(_checkOut(18, 59), '18:50');
    });

    test('19:00 → 19:00 (offset=60, (60~/10)*10=60)', () {
      expect(_checkOut(19, 0), '19:00');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 7. 퇴근 — 조퇴 (floor toward -∞ = ceil of |offset|)
  // ═══════════════════════════════════════════════════════════
  group('퇴근 — 조퇴 (floor toward -∞)', () {
    test('17:45 → 17:30 (offset=-15, ceil(15/30)*30=30)', () {
      expect(_checkOut(17, 45), '17:30');
      expect(_checkOutType(17, 45), RoundingType.earlyLeave);
    });

    test('17:30 → 17:30 (offset=-30, ceil(30/30)*30=30)', () {
      expect(_checkOut(17, 30), '17:30');
    });

    test('17:29 → 17:00 (offset=-31, ceil(31/30)*30=60)', () {
      expect(_checkOut(17, 29), '17:00');
    });

    test('17:00 → 17:00 (offset=-60, ceil(60/30)*30=60)', () {
      expect(_checkOut(17, 0), '17:00');
    });

    test('16:59 → 16:30 (offset=-61, ceil(61/30)*30=90)', () {
      expect(_checkOut(16, 59), '16:30');
    });

    test('15:00 → 15:00 (offset=-180, ceil(180/30)*30=180)', () {
      expect(_checkOut(15, 0), '15:00');
    });

    // 비정각 contractEnd 검증 (자정 기준 버그 재현 방지)
    test('contractEnd=18:45, actual=18:15 → 18:15 (offset=-30, ceil(30/30)=1)', () {
      final cOutNonMidnight = contractEndAt(_date, '09:00', '18:45');
      final punch  = DateTime(2026, 1, 15, 18, 15);
      final offset = punch.difference(cOutNonMidnight).inMinutes; // -30
      final result = processCheckout(
        offsetMinutes: offset, referenceAt: cOutNonMidnight, rules: _rules);
      expect(result.rounded, '18:15');
      expect(result.type, RoundingType.earlyLeave);
    });

    test('contractEnd=18:45, actual=18:14 → 17:45 (offset=-31, ceil(31/30)=2)', () {
      final cOutNonMidnight = contractEndAt(_date, '09:00', '18:45');
      final punch  = DateTime(2026, 1, 15, 18, 14);
      final offset = punch.difference(cOutNonMidnight).inMinutes; // -31
      final result = processCheckout(
        offsetMinutes: offset, referenceAt: cOutNonMidnight, rules: _rules);
      expect(result.rounded, '17:45');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 8. 야간 교대 (22:00 ~ 06:00) — 날짜 포함 DateTime으로 검증
  // ═══════════════════════════════════════════════════════════
  group('야간 교대 (22:00 ~ 06:00)', () {
    // ── 출근 ──
    test('22:00 → 정시 (offset=0)', () {
      expect(_nightIn(22, 0), '22:00');
      expect(_nightInType(22, 0), RoundingType.onTime);
    });

    test('21:30 → 정시 (offset=-30 = earlyWindow, NOT < -30)', () {
      expect(_nightIn(21, 30), '22:00');
      expect(_nightInType(21, 30), RoundingType.onTime);
    });

    test('21:29 → 조출 (offset=-31, (-31~/30)*30=-30 → 21:30)', () {
      expect(_nightIn(21, 29), '21:30');
      expect(_nightInType(21, 29), RoundingType.earlyArrival);
    });

    test('22:06 → 지각 (offset=6, ceil(6/30)*30=30 → 22:30)', () {
      expect(_nightIn(22, 6), '22:30');
      expect(_nightInType(22, 6), RoundingType.late);
    });

    // 자정 이후 출근 — 이제 날짜 포함이므로 특수 처리 불필요
    test('00:15(다음날) → 지각 (offset=135, ceil(135/30)*30=150 → 00:30)', () {
      // punchAt = 2026-01-16 00:15, contractStart = 2026-01-15 22:00
      // offset = 135분 지각
      expect(_nightIn(0, 15), '00:30');
      expect(_nightInType(0, 15), RoundingType.late);
    });

    test('00:00(다음날) → 지각 (offset=120, 120~/30*30=120? no ceil: ceil(120/30)=4 → 120 → 00:00)', () {
      // offset=120, ceil(120/30)*30=120 → 22:00+120=00:00
      expect(_nightIn(0, 0), '00:00');
      expect(_nightInType(0, 0), RoundingType.late);
    });

    // 00:00~08:00 근무에서 전날 23:31 출근 — 핵심 버그 시나리오
    test('00:00~08:00 근무, 전날 23:31 출근 → 정시 (offset=-29)', () {
      final cIn0 = contractStartAt(_date, '00:00');
      // 전날 23:31 = date - 1일 + 23:31
      final punchPrevDay = DateTime(_date.year, _date.month, _date.day - 1, 23, 31);
      final offset = punchPrevDay.difference(cIn0).inMinutes; // -29
      final result = processCheckin(
        offsetMinutes: offset, referenceAt: cIn0, rules: _rules);
      expect(result.type, RoundingType.onTime,
          reason: 'earlyWindow(30) 이내 → 정시. 이전 코드는 +1411분 지각 오분류였음');
      expect(result.rounded, '00:00');
    });

    // ── 퇴근 ──
    test('06:00 → 정시 (offset=0)', () {
      expect(_nightOut(6, 0), '06:00');
    });

    test('05:45 → 조퇴 (offset=-15, ceil(15/30)=1 → -30 → 05:30)', () {
      expect(_nightOut(5, 45), '05:30');
    });

    test('06:15 → 정시 (offset=15 ≤ lateWindow(30))', () {
      expect(_nightOut(6, 15), '06:00');
    });

    test('06:31 → 연장 (offset=31, (31~/10)*10=30 → 06:30)', () {
      expect(_nightOut(6, 31), '06:30');
    });

    test('02:00(다음날) → 조퇴 (offset=-240, ceil(240/30)=8 → -240 → 02:00)', () {
      // punchAt=02:00, contractEnd=06:00, offset=-240
      // ceil(240/30)*30=240 → 06:00-240=02:00
      expect(_nightOut(2, 0), '02:00');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 9. AttendanceRules.defaults() 검증
  // ═══════════════════════════════════════════════════════════
  group('AttendanceRules defaults', () {
    test('기본값 7개 필드 정확히 설정됨', () {
      final r = AttendanceRules.defaults();
      expect(r.earlyWindow,      30);
      expect(r.earlyArrivalUnit, 30);
      expect(r.lateGrace,        5);
      expect(r.lateUnit,         30);
      expect(r.lateWindow,       30);
      expect(r.overtimeUnit,     10);
      expect(r.earlyLeaveUnit,   30);
    });

    test('resolveRules(null) → defaults()', () {
      expect(resolveRules(null).lateGrace, 5);
    });

    test('fromMap → toMap 라운드트립', () {
      const original = AttendanceRules(
        earlyWindow: 20, earlyArrivalUnit: 15, lateGrace: 10,
        lateUnit: 15, lateWindow: 20, overtimeUnit: 5, earlyLeaveUnit: 15,
      );
      final restored = AttendanceRules.fromMap(original.toMap());
      expect(restored.earlyWindow,      20);
      expect(restored.earlyArrivalUnit, 15);
      expect(restored.lateGrace,        10);
      expect(restored.lateUnit,         15);
      expect(restored.lateWindow,       20);
      expect(restored.overtimeUnit,      5);
      expect(restored.earlyLeaveUnit,   15);
    });

    test('fromMap clamp — 범위 초과 값 슬라이더 범위로 clamp', () {
      final r = AttendanceRules.fromMap({
        'earlyWindow': 999, 'earlyArrivalUnit': -1, 'lateGrace': 999,
        'lateUnit': -1,     'lateWindow': 999,       'overtimeUnit': -1,
        'earlyLeaveUnit': 999,
      });
      expect(r.earlyWindow,      inInclusiveRange(0, 120)); // clamp(0,120)
      expect(r.earlyArrivalUnit, inInclusiveRange(5,  60)); // clamp(5,60)
    });

    test('summary getter — 필수 정보 포함', () {
      final s = AttendanceRules.defaults().summary;
      expect(s, contains('30'));
      expect(s.isNotEmpty, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 10. 전수 스윕 — 출근 05:00~12:00 (5분 간격)
  // ═══════════════════════════════════════════════════════════
  group('출근 전수 스윕 05:00~12:00 (5분 간격)', () {
    // contractStart=09:00, earlyWindow=30, lateGrace=5, lateUnit=30
    String _expected(int punchMin) {
      const refMin = 9 * 60; // 540
      final offset = punchMin - refMin;
      if (offset < -30) {
        // earlyArrival: (offset ~/30)*30 로 계산된 roundedOffset → refMin + rounded
        final rounded = (offset ~/ 30) * 30;
        return _hhmm(refMin + rounded);
      } else if (offset <= 5) {
        return '09:00';
      } else {
        final rounded = ((offset + 29) ~/ 30) * 30;
        return _hhmm(refMin + rounded);
      }
    }

    test('05:00~12:00 5분 간격 전 케이스 오프셋 계산 일치', () {
      for (int min = 300; min <= 720; min += 5) {
        final punch = DateTime(2026, 1, 15, min ~/ 60, min % 60);
        final offset = punch.difference(_cIn).inMinutes;
        final result = processCheckin(
          offsetMinutes: offset, referenceAt: _cIn, rules: _rules);
        final expected = _expected(min);
        expect(result.rounded, expected,
            reason: '입력 ${_hhmm(min)} → expected $expected, got ${result.rounded}');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 11. 전수 스윕 — 퇴근 14:00~23:00 (5분 간격)
  // ═══════════════════════════════════════════════════════════
  group('퇴근 전수 스윕 14:00~23:00 (5분 간격)', () {
    // contractEnd=18:00, lateWindow=30, overtimeUnit=10, earlyLeaveUnit=30
    String _expected(int punchMin) {
      const refMin = 18 * 60; // 1080
      final offset = punchMin - refMin;
      if (offset > 30) {
        final rounded = (offset ~/ 10) * 10;
        return _hhmm(refMin + rounded);
      } else if (offset >= 0) {
        return '18:00';
      } else {
        // 조퇴: floor toward -∞ = ceil of |offset|
        final earlyDiff = -offset;
        final rounded = -(((earlyDiff + 29) ~/ 30) * 30);
        return _hhmm(refMin + rounded);
      }
    }

    test('14:00~23:00 5분 간격 전 케이스 오프셋 계산 일치', () {
      for (int min = 840; min <= 1380; min += 5) {
        final punch = DateTime(2026, 1, 15, min ~/ 60, min % 60);
        final offset = punch.difference(_cOut).inMinutes;
        final result = processCheckout(
          offsetMinutes: offset, referenceAt: _cOut, rules: _rules);
        final expected = _expected(min);
        expect(result.rounded, expected,
            reason: '입력 ${_hhmm(min)} → expected $expected, got ${result.rounded}');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 12. 커스텀 규칙
  // ═══════════════════════════════════════════════════════════
  group('커스텀 규칙', () {
    const small = AttendanceRules(
      earlyWindow: 15, earlyArrivalUnit: 15, lateGrace: 0,
      lateUnit: 15,   lateWindow: 15,        overtimeUnit: 5,
      earlyLeaveUnit: 15,
    );

    test('earlyArrivalUnit=15: 08:40 → 08:45 (offset=-20, (-20~/15)*15=-15)', () {
      final punch  = DateTime(2026, 1, 15, 8, 40);
      final offset = punch.difference(_cIn).inMinutes; // -20
      final result = processCheckin(
        offsetMinutes: offset, referenceAt: _cIn, rules: small);
      expect(result.rounded, '08:45');
    });

    test('lateUnit=15: 09:01 → 09:15 (offset=1, lateGrace=0 → 지각, ceil(1/15)*15=15)', () {
      final punch  = DateTime(2026, 1, 15, 9, 1);
      final offset = punch.difference(_cIn).inMinutes; // 1
      final result = processCheckin(
        offsetMinutes: offset, referenceAt: _cIn, rules: small);
      expect(result.rounded, '09:15');
      expect(result.type, RoundingType.late);
    });

    test('overtimeUnit=5: 18:16 → 18:15 (offset=16 > lateWindow=15, (16~/5)*5=15)', () {
      final punch  = DateTime(2026, 1, 15, 18, 16);
      final offset = punch.difference(_cOut).inMinutes; // 16
      final result = processCheckout(
        offsetMinutes: offset, referenceAt: _cOut, rules: small);
      expect(result.rounded, '18:15');
      expect(result.type, RoundingType.overtime);
    });

    test('earlyLeaveUnit=15: 17:50 → 17:45 (offset=-10, ceil(10/15)=1 → -15)', () {
      final punch  = DateTime(2026, 1, 15, 17, 50);
      final offset = punch.difference(_cOut).inMinutes; // -10
      final result = processCheckout(
        offsetMinutes: offset, referenceAt: _cOut, rules: small);
      expect(result.rounded, '17:45');
    });
  });
}

// ── 유틸 ─────────────────────────────────────────────────────
String _hhmm(int totalMin) {
  final h = (totalMin ~/ 60) % 24;
  final m = totalMin % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}
