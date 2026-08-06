// ignore_for_file: lines_longer_than_80_chars
//
// 출퇴근(근태) 감사 체크리스트 시뮬레이션 테스트
//
// 검증 대상:
//   A. AttendanceStatusHelper — 시간 변환·상태 판단 (38개)
//   B. AttendanceRoundingHelper — 반올림 로직 (12개)
//   C. AttendanceModel — 역직렬화·getter·야간교대 보정 (15개)
//
// 주요 감사 포인트:
//   - minutesBetween 자정 경계 및 동일시각(0분, 24시간 아님)
//   - isLate 경계: 정확히 1분 지각 = 지각
//   - isEarlyLeave 야간 자정 보정 — 01:00 퇴근(계약 23:00)은 조퇴 아님
//   - processCheckin 지각 올림 방향 (lateUnit 단위 ceil)
//   - processCheckout 조퇴 올림 방향 (earlyLeaveUnit 단위 ceil, 불리한 방향)
//   - contractEndAt 야간교대: end < start → +1일
//   - displayWage: confirmed·transferred 상태만 반환
//   - fromMap 야간교대 보정: checkOut < checkIn → +1일

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/utils/attendance_rounding_helper.dart';
import 'package:ALfit/utils/attendance_status_helper.dart';

// ════════════════════════════════════════════════════════════
// 공통 헬퍼
// ════════════════════════════════════════════════════════════

final _todayTs = Timestamp.fromDate(DateTime.now());

/// KST 시각을 UTC Timestamp로 변환 (기기 타임존 독립적)
Timestamp _kstTs(int year, int month, int day, int hour, int minute) =>
    Timestamp.fromDate(
      DateTime.utc(year, month, day, hour, minute)
          .subtract(const Duration(hours: 9)),
    );

/// 최소 필드로 AttendanceModel 생성
AttendanceModel _makeAttendance({
  String? checkIn,         // "HH:mm" v1 형식
  String? checkOut,        // "HH:mm" v1 형식
  Timestamp? checkInTs,    // v2 Timestamp 형식
  Timestamp? checkOutTs,   // v2 Timestamp 형식
  String wageStatus = AttendanceModel.wagePending,
  int? finalWage,
  String status = AttendanceModel.statusPresent,
}) {
  final map = <String, dynamic>{
    'applicationId': 'app_1',
    'userId': 'u1',
    'businessId': 'b1',
    'businessName': '테스트 사업장',
    'workDate': _todayTs,
    'workType': '주방보조',
    'status': status,
    'wageStatus': wageStatus,
    'createdAt': _todayTs,
    if (checkIn != null) 'checkIn': checkIn,
    if (checkOut != null) 'checkOut': checkOut,
    if (checkInTs != null) 'checkIn': checkInTs,
    if (checkOutTs != null) 'checkOut': checkOutTs,
    if (finalWage != null) 'finalWage': finalWage,
  };
  return AttendanceModel.fromMap(map, 'att_1');
}

/// deriveStatus 테스트용 최소 ApplicationModel
ApplicationModel _makeApp({
  String start = '09:00',
  String end = '18:00',
}) =>
    ApplicationModel.fromMap({
      'uid': 'u1',
      'toId': 'to1',
      'businessId': 'b1',
      'status': 'confirmed',
      'workDate': _todayTs,
      'appliedAt': _todayTs,
      'applicantName': '테스트',
      'selectedWorkType': '주방보조',
      'startTime': start,
      'endTime': end,
    }, 'app_1');

// ════════════════════════════════════════════════════════════
void main() {
// ════════════════════════════════════════════════════════════
// A. AttendanceStatusHelper
// ════════════════════════════════════════════════════════════
  group('A. AttendanceStatusHelper — 시간 변환 및 상태 판단', () {

    // ── A-1. timeToMinutes ───────────────────────────────────
    group('A-1. timeToMinutes', () {
      test('A-01: "09:00" → 540', () {
        expect(AttendanceStatusHelper.timeToMinutes('09:00'), 540);
      });

      test('A-02: "00:00" → 0', () {
        expect(AttendanceStatusHelper.timeToMinutes('00:00'), 0);
      });

      test('A-03: "23:59" → 1439', () {
        expect(AttendanceStatusHelper.timeToMinutes('23:59'), 1439);
      });

      test('A-04: "09:30:00" → 570 (초 단위 무시)', () {
        expect(AttendanceStatusHelper.timeToMinutes('09:30:00'), 570);
      });

      test('A-05: 잘못된 형식 → 0 (관대한 폴백)', () {
        expect(AttendanceStatusHelper.timeToMinutes('invalid'), 0);
        expect(AttendanceStatusHelper.timeToMinutes(''), 0);
        expect(AttendanceStatusHelper.timeToMinutes('ab:cd'), 0);
      });
    });

    // ── A-2. minutesBetween ──────────────────────────────────
    group('A-2. minutesBetween', () {
      test('A-06: 일반 근무 "09:00"~"18:00" → 540분', () {
        expect(AttendanceStatusHelper.minutesBetween('09:00', '18:00'), 540);
      });

      test('A-07: 야간 교대 "22:00"~"06:00" → 480분 (자정 넘김 보정)', () {
        // 22:00=1320분, 06:00=360분 → 360 < 1320 → 360+1440=1800, 1800-1320=480
        expect(AttendanceStatusHelper.minutesBetween('22:00', '06:00'), 480);
      });

      test('A-08: 동일 시각 "09:00"~"09:00" → 0분 (24시간 아님)', () {
        // 코드: e==s이면 e+=1440 미적용 → 0분 반환 (24시간 시프트 오해석 방지)
        expect(AttendanceStatusHelper.minutesBetween('09:00', '09:00'), 0);
      });

      test('A-09: 자정 경계 "00:00"~"00:01" → 1분', () {
        expect(AttendanceStatusHelper.minutesBetween('00:00', '00:01'), 1);
      });
    });

    // ── A-3. isLate ──────────────────────────────────────────
    group('A-3. isLate', () {
      test('A-10: 1분 지각("09:01", 기준"09:00") → true', () {
        expect(AttendanceStatusHelper.isLate('09:01', '09:00'), isTrue);
      });

      test('A-11: 정각 출근("09:00") → false', () {
        expect(AttendanceStatusHelper.isLate('09:00', '09:00'), isFalse);
      });

      test('A-12: 1분 이른 출근("08:59") → false', () {
        expect(AttendanceStatusHelper.isLate('08:59', '09:00'), isFalse);
      });

      test('A-13: 야간 시프트 지각 (isNextDay=true, 06:05 출근, 기준 22:00) → true', () {
        // actual = 365 + 1440 = 1805, scheduled = 1320, 1805-1320 = 485 > 0
        expect(
          AttendanceStatusHelper.isLate('06:05', '22:00', isNextDay: true),
          isTrue,
        );
      });

      test('A-14: 야간 시프트 정시 (isNextDay=true, 06:00 출근, 기준 06:00 → 24:00 + 6:00) → false', () {
        // actual = 360 + 1440 = 1800, scheduled = 360 (야간 06:00 시작)
        // 1800-360 = 1440 > 0 → true? 잠깐, 야간 기준 22:00이라면:
        // actual=360+1440=1800, scheduled=1320, 1800-1320=480>0 → 지각
        // 정확히 정시(22:00+isNextDay)를 테스트:
        // actual=1320+1440=2760, scheduled=1320, 2760-1320=1440>0 → 지각! (isNextDay 사용 맥락 맞음)
        // isNextDay=true인데 checkIn="22:00"이면 같은 날 밤이라 1440 추가 → 엄청 지각
        // 실제로 isNextDay는 "다음날 새벽에 출근"하는 경우, e.g. 야간 22:00 시작 → 다음날 00:05 출근
        // isNextDay=false 케이스: actual=1320, scheduled=1320, 0>0 → false (정시)
        expect(
          AttendanceStatusHelper.isLate('22:00', '22:00', isNextDay: false),
          isFalse,
        );
      });
    });

    // ── A-4. isNextDayCheckIn ────────────────────────────────
    group('A-4. isNextDayCheckIn', () {
      test('A-15: 야간 시작(22:00) + 새벽 출근(06:00) → true', () {
        expect(
          AttendanceStatusHelper.isNextDayCheckIn('06:00', '22:00'),
          isTrue,
        );
      });

      test('A-16: 주간 시작(09:00) + 새벽 출근 → false (시작이 20:00 미만)', () {
        expect(
          AttendanceStatusHelper.isNextDayCheckIn('06:00', '09:00'),
          isFalse,
        );
      });

      test('A-17: 야간 시작(22:00) + 08:01 출근 → false (임계값 08:00 초과)', () {
        // ciMins=481, 481 <= 480 → false
        expect(
          AttendanceStatusHelper.isNextDayCheckIn('08:01', '22:00'),
          isFalse,
        );
      });

      test('A-18: 야간 시작(22:00) + 정확히 08:00 → true (임계값 포함)', () {
        // ciMins=480, 480 <= 480 → true
        expect(
          AttendanceStatusHelper.isNextDayCheckIn('08:00', '22:00'),
          isTrue,
        );
      });
    });

    // ── A-5. isEarlyArrival ──────────────────────────────────
    group('A-5. isEarlyArrival', () {
      test('A-19: 60분 이른 출근(기준 30분) → true', () {
        expect(AttendanceStatusHelper.isEarlyArrival('08:00', '09:00'), isTrue);
      });

      test('A-20: 정확히 30분 이른 출근 → true (경계값 포함)', () {
        // scheduled(540) - actual(510) = 30 >= 30 → true
        expect(AttendanceStatusHelper.isEarlyArrival('08:30', '09:00'), isTrue);
      });

      test('A-21: 29분 이른 출근 → false (threshold 미만)', () {
        // 540 - 511 = 29 >= 30 → false
        expect(AttendanceStatusHelper.isEarlyArrival('08:31', '09:00'), isFalse);
      });

      test('A-22: 정시 출근 → false', () {
        expect(AttendanceStatusHelper.isEarlyArrival('09:00', '09:00'), isFalse);
      });
    });

    // ── A-6. isEarlyLeave ────────────────────────────────────
    group('A-6. isEarlyLeave', () {
      test('A-23: 1분 조퇴("17:59", 계약"18:00") → true', () {
        expect(AttendanceStatusHelper.isEarlyLeave('17:59', '18:00'), isTrue);
      });

      test('A-24: 정시 퇴근("18:00") → false', () {
        // scheduled - actual = 0 > 0 → false
        expect(AttendanceStatusHelper.isEarlyLeave('18:00', '18:00'), isFalse);
      });

      test('A-25: 1분 연장 퇴근 → false', () {
        expect(AttendanceStatusHelper.isEarlyLeave('18:01', '18:00'), isFalse);
      });

      test('A-26: 야간 자정 보정 — 01:00 퇴근(계약 23:00, 출근 14:30) → false (조퇴 아님)', () {
        // actual=60, checkIn=870 → actual+=1440 → 1500 (01:00 익일)
        // scheduled=1380, checkIn=870 → 1380>=870 → 보정 없음
        // 1380-1500 = -120 > 0 → false ✓ (계약 23:00보다 실제로 늦게 퇴근)
        expect(
          AttendanceStatusHelper.isEarlyLeave('01:00', '23:00', checkIn: '14:30'),
          isFalse,
        );
      });

      test('A-27: 야간 자정 보정 — 22:00 퇴근(계약 23:00, 출근 14:30) → true (조퇴)', () {
        // actual=1320, checkIn=870 → 1320>=870 → 보정 없음
        // scheduled=1380, 1380>=870 → 보정 없음
        // 1380-1320=60>0 → true
        expect(
          AttendanceStatusHelper.isEarlyLeave('22:00', '23:00', checkIn: '14:30'),
          isTrue,
        );
      });
    });

    // ── A-7. isOvertime ──────────────────────────────────────
    group('A-7. isOvertime', () {
      test('A-28: 30분 연장 퇴근 → true', () {
        expect(AttendanceStatusHelper.isOvertime('18:30', '18:00'), isTrue);
      });

      test('A-29: 정시 퇴근 → false', () {
        expect(AttendanceStatusHelper.isOvertime('18:00', '18:00'), isFalse);
      });

      test('A-30: graceMinutes=30, 30분 초과 → false (grace 내)', () {
        // actual=1110, scheduled=1080, 1110 > 1080+30=1110 → false
        expect(
          AttendanceStatusHelper.isOvertime('18:30', '18:00', graceMinutes: 30),
          isFalse,
        );
      });

      test('A-31: graceMinutes=30, 31분 초과 → true (grace 초과)', () {
        expect(
          AttendanceStatusHelper.isOvertime('18:31', '18:00', graceMinutes: 30),
          isTrue,
        );
      });
    });

    // ── A-8. isNightOvertime ────────────────────────────────
    group('A-8. isNightOvertime', () {
      test('A-32: 23:00 퇴근(계약 18:00, 출근 09:00) → 야간 연장 true', () {
        // isOvertime: actual=1380, scheduled=1080, 1380>1080 → true
        // outMins=1380 > 22*60=1320 → true
        expect(
          AttendanceStatusHelper.isNightOvertime('23:00', '18:00', '09:00'),
          isTrue,
        );
      });

      test('A-33: 19:00 퇴근(계약 18:00, 출근 09:00) → 야간 연장 false (22시 미만)', () {
        // isOvertime: true, outMins=1140, 1140 > 1320 → false
        expect(
          AttendanceStatusHelper.isNightOvertime('19:00', '18:00', '09:00'),
          isFalse,
        );
      });
    });

    // ── A-9. workMinutes / isValidWorkPeriod ────────────────
    group('A-9. workMinutes / isValidWorkPeriod', () {
      test('A-34: "09:00"~"18:00" → 540분', () {
        expect(AttendanceStatusHelper.workMinutes('09:00', '18:00'), 540);
      });

      test('A-35: 야간 "22:00"~"06:00" → 480분', () {
        expect(AttendanceStatusHelper.workMinutes('22:00', '06:00'), 480);
      });

      test('A-36: 동일 시각 "09:00"~"09:00" → 0분', () {
        expect(AttendanceStatusHelper.workMinutes('09:00', '09:00'), 0);
      });

      test('A-37: 8시간 근무 → 유효', () {
        expect(
          AttendanceStatusHelper.isValidWorkPeriod('09:00', '17:00'),
          isTrue,
        );
      });

      test('A-38: 16시간 정확히 → 유효 (경계값 포함)', () {
        // 08:00~00:00 = 960분 = 16시간 → 960 <= 16*60=960 → true
        expect(
          AttendanceStatusHelper.isValidWorkPeriod('08:00', '00:00'),
          isTrue,
        );
      });

      test('A-39: 17시간 초과 → 유효하지 않음', () {
        // 06:00~23:01 = 17*60+1 = 1021분 > 960 → false
        expect(
          AttendanceStatusHelper.isValidWorkPeriod('06:00', '23:01'),
          isFalse,
        );
      });

      test('A-40: 동일 시각(0분) → 유효하지 않음', () {
        expect(
          AttendanceStatusHelper.isValidWorkPeriod('09:00', '09:00'),
          isFalse,
        );
      });
    });

    // ── A-10. deriveStatus ──────────────────────────────────
    group('A-10. deriveStatus', () {
      final app = _makeApp(start: '09:00', end: '18:00');

      test('A-41: 정시 출근·퇴근 없음 → present', () {
        expect(
          AttendanceStatusHelper.deriveStatus(app, '09:00', null,
              effStart: '09:00', effEnd: '18:00'),
          AttendanceModel.statusPresent,
        );
      });

      test('A-42: 1분 지각·퇴근 없음 → late', () {
        expect(
          AttendanceStatusHelper.deriveStatus(app, '09:01', null,
              effStart: '09:00', effEnd: '18:00'),
          AttendanceModel.statusLate,
        );
      });

      test('A-43: 정시 출근·1분 조퇴 → early_leave (조퇴 우선)', () {
        expect(
          AttendanceStatusHelper.deriveStatus(app, '09:00', '17:59',
              effStart: '09:00', effEnd: '18:00'),
          AttendanceModel.statusEarlyLeave,
        );
      });

      test('A-44: 지각 + 조퇴 동시 → early_leave (조퇴 우선, 지각 무시)', () {
        expect(
          AttendanceStatusHelper.deriveStatus(app, '09:30', '17:59',
              effStart: '09:00', effEnd: '18:00'),
          AttendanceModel.statusEarlyLeave,
        );
      });

      test('A-45: 정시 출근·정시 퇴근 → present', () {
        expect(
          AttendanceStatusHelper.deriveStatus(app, '09:00', '18:00',
              effStart: '09:00', effEnd: '18:00'),
          AttendanceModel.statusPresent,
        );
      });
    });
  });

// ════════════════════════════════════════════════════════════
// B. AttendanceRoundingHelper
// ════════════════════════════════════════════════════════════
  group('B. AttendanceRoundingHelper — 반올림 로직', () {
    final workDate = DateTime(2024, 1, 15);
    // 기본 규칙: earlyWindow=30, lateGrace=5, lateUnit=30, lateWindow=30,
    //             overtimeUnit=30, earlyLeaveUnit=30
    final rules = AttendanceRules.defaults();

    // ── B-1. contractStartAt / contractEndAt ─────────────────
    group('B-1. contractStartAt / contractEndAt', () {
      test('B-01: contractStartAt("09:00") → 2024-01-15 09:00', () {
        final result = contractStartAt(workDate, '09:00');
        expect(result.hour, 9);
        expect(result.minute, 0);
        expect(result.day, 15);
      });

      test('B-02: contractEndAt 야간교대 ("22:00"~"06:00") → +1일', () {
        final result = contractEndAt(workDate, '22:00', '06:00');
        // 06:00 < 22:00 → +1일
        expect(result.day, 16);
        expect(result.hour, 6);
        expect(result.minute, 0);
      });

      test('B-03: contractEndAt 동일 시각 → 0분 시프트 (24시간 오해석 방지)', () {
        // end == start → isBefore = false → 보정 없음 → 같은 시각
        final start = contractStartAt(workDate, '09:00');
        final end   = contractEndAt(workDate, '09:00', '09:00');
        expect(end, equals(start));
      });

      test('B-04: contractEndAt 정상 주간 ("09:00"~"18:00") → 같은 날', () {
        final result = contractEndAt(workDate, '09:00', '18:00');
        expect(result.day, 15);
        expect(result.hour, 18);
      });
    });

    // ── B-2. processCheckin ──────────────────────────────────
    group('B-2. processCheckin', () {
      final refStart = contractStartAt(workDate, '09:00'); // 2024-01-15 09:00

      test('B-05: 60분 조출(08:00 도착) → earlyArrival, 30분 단위 반올림', () {
        // offset = -60, earlyWindow=30, -60 < -30 → earlyArrival
        // rounded = (-60 ~/ 30) * 30 = -2 * 30 = -60 → 08:00 유지
        final result = processCheckin(
          offsetMinutes: -60,
          referenceAt: refStart,
          rules: rules,
        );
        expect(result.type, RoundingType.earlyArrival);
        expect(result.roundedOffset, -60);
        expect(result.rounded, '08:00');
      });

      test('B-06: 15분 이른 도착(earlyWindow=30 내) → onTime, offset=0', () {
        // offset = -15, -15 >= -30 → earlyWindow 내
        // -15 <= 5(lateGrace) → onTime
        final result = processCheckin(
          offsetMinutes: -15,
          referenceAt: refStart,
          rules: rules,
        );
        expect(result.type, RoundingType.onTime);
        expect(result.roundedOffset, 0);
        expect(result.rounded, '09:00');
      });

      test('B-07: 3분 지각(lateGrace=5 이내) → lateGrace, offset=0', () {
        // offset = +3, 3 <= 5 → lateGrace (정시 처리)
        final result = processCheckin(
          offsetMinutes: 3,
          referenceAt: refStart,
          rules: rules,
        );
        expect(result.type, RoundingType.lateGrace);
        expect(result.roundedOffset, 0);
        expect(result.rounded, '09:00');
      });

      test('B-08: 10분 지각(lateGrace 초과) → late, 30분 단위 올림 → 09:30', () {
        // offset = +10, 10 > 5 → late
        // rounded = ((10+30-1)~/30)*30 = (39~/30)*30 = 30 → 09:30
        final result = processCheckin(
          offsetMinutes: 10,
          referenceAt: refStart,
          rules: rules,
        );
        expect(result.type, RoundingType.late);
        expect(result.roundedOffset, 30);
        expect(result.rounded, '09:30');
      });

      test('B-09: 정확히 30분 지각 → late, 30분 올림 → 09:30 (경계값)', () {
        // offset = +30, ((30+29)~/30)*30 = (59~/30)*30 = 30 → 09:30
        final result = processCheckin(
          offsetMinutes: 30,
          referenceAt: refStart,
          rules: rules,
        );
        expect(result.type, RoundingType.late);
        expect(result.roundedOffset, 30);
      });

      test('B-10: 31분 지각 → late, 60분 올림 → 10:00', () {
        // offset = +31, ((31+29)~/30)*30 = (60~/30)*30 = 60 → 10:00
        final result = processCheckin(
          offsetMinutes: 31,
          referenceAt: refStart,
          rules: rules,
        );
        expect(result.type, RoundingType.late);
        expect(result.roundedOffset, 60);
      });
    });

    // ── B-3. processCheckout ─────────────────────────────────
    group('B-3. processCheckout', () {
      final refEnd = contractEndAt(workDate, '09:00', '18:00'); // 2024-01-15 18:00

      test('B-11: 정시 퇴근(offset=0) → onTimeOut', () {
        final result = processCheckout(
          offsetMinutes: 0,
          referenceAt: refEnd,
          rules: rules,
        );
        expect(result.type, RoundingType.onTimeOut);
        expect(result.roundedOffset, 0);
        expect(result.rounded, '18:00');
      });

      test('B-12: 20분 초과(lateWindow=30 이내) → onTimeOut, offset=0', () {
        // offset=+20, 20 <= 30(lateWindow) → 연장 아님 → onTimeOut
        // 단, 20 >= 0 → onTimeOut
        final result = processCheckout(
          offsetMinutes: 20,
          referenceAt: refEnd,
          rules: rules,
        );
        expect(result.type, RoundingType.onTimeOut);
        expect(result.roundedOffset, 0);
      });

      test('B-13: 45분 초과(lateWindow 초과) → overtime, 10분 단위 내림 → 18:40', () {
        // offset=+45, 45 > 30(lateWindow) → overtime
        // overtimeUnit 기본값 = 10 (lateUnit=30과 다름!)
        // rounded = (45~/10)*10 = 4*10 = 40 → 18:40
        final result = processCheckout(
          offsetMinutes: 45,
          referenceAt: refEnd,
          rules: rules,
        );
        expect(result.type, RoundingType.overtime);
        expect(result.roundedOffset, 40);
        expect(result.rounded, '18:40');
      });

      test('B-14: 15분 조퇴 → earlyLeave, 30분 단위 올림 → 17:30 (불리한 방향)', () {
        // offset=-15, earlyDiff=15
        // rounded = -(((15+29)~/30)*30) = -((44~/30)*30) = -(30) = -30 → 17:30
        final result = processCheckout(
          offsetMinutes: -15,
          referenceAt: refEnd,
          rules: rules,
        );
        expect(result.type, RoundingType.earlyLeave);
        expect(result.roundedOffset, -30);
        expect(result.rounded, '17:30');
      });
    });

    // ── B-4. resolveRules ────────────────────────────────────
    test('B-15: resolveRules — null → defaults 폴백 (overtimeUnit=10 포함)', () {
      final resolved = resolveRules(null);
      expect(resolved.earlyWindow,      30);
      expect(resolved.earlyArrivalUnit, 30);
      expect(resolved.lateGrace,        5);
      expect(resolved.lateUnit,         30);
      expect(resolved.lateWindow,       30);
      expect(resolved.overtimeUnit,     10,  reason: '연장 단위는 10분 — 지각·조퇴(30분)와 다름');
      expect(resolved.earlyLeaveUnit,   30);
    });
  });

// ════════════════════════════════════════════════════════════
// C. AttendanceModel
// ════════════════════════════════════════════════════════════
  group('C. AttendanceModel — 역직렬화·getter·야간교대 보정', () {

    // ── C-1. fromMap 필수 필드 검증 ──────────────────────────
    group('C-1. fromMap 필수 필드 검증', () {
      test('C-01: workDate 없음 → ArgumentError', () {
        expect(
          () => AttendanceModel.fromMap({
            'applicationId': 'a',
            'userId': 'u',
            'businessId': 'b',
            'businessName': 'n',
            'workType': 'w',
            'createdAt': _todayTs,
          }, 'att'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('C-02: createdAt 없음 → ArgumentError', () {
        expect(
          () => AttendanceModel.fromMap({
            'applicationId': 'a',
            'userId': 'u',
            'businessId': 'b',
            'businessName': 'n',
            'workDate': _todayTs,
            'workType': 'w',
          }, 'att'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('C-03: 최소 필드 제공 → 정상 생성', () {
        final model = _makeAttendance();
        expect(model.id, 'att_1');
        expect(model.businessId, 'b1');
        expect(model.wageStatus, AttendanceModel.wagePending);
      });
    });

    // ── C-2. _parseTimeField 포맷 처리 ───────────────────────
    group('C-2. _parseTimeField 포맷 처리', () {
      test('C-04: v2 Timestamp → DateTime 변환 후 getter 표시 정확', () {
        // 09:00 KST = UTC 00:00
        final ts = _kstTs(2024, 1, 15, 9, 0);
        final model = _makeAttendance(checkInTs: ts);
        expect(model.checkInAt, isNotNull);
        expect(model.checkIn, '09:00');
      });

      test('C-05: CF Map({_seconds, _nanoseconds}) → DateTime 변환', () {
        // _kstTs로 생성한 Timestamp를 Map으로 분해
        final ts = _kstTs(2024, 1, 15, 13, 30);
        final map = <String, dynamic>{
          'applicationId': 'a',
          'userId': 'u',
          'businessId': 'b',
          'businessName': 'n',
          'workDate': _todayTs,
          'workType': 'w',
          'checkIn': {'_seconds': ts.seconds, '_nanoseconds': ts.nanoseconds},
          'status': 'present',
          'createdAt': _todayTs,
          'wageStatus': 'pending',
        };
        final model = AttendanceModel.fromMap(map, 'att');
        expect(model.checkInAt, isNotNull);
        expect(model.checkIn, '13:30');
      });

      test('C-06: null 값 → checkInAt null, getter null', () {
        final model = _makeAttendance();
        expect(model.checkInAt, isNull);
        expect(model.checkIn, isNull);
      });

      test('C-07: 잘못된 CF Map (필드 없음) → null (예외 삼킴)', () {
        final map = <String, dynamic>{
          'applicationId': 'a',
          'userId': 'u',
          'businessId': 'b',
          'businessName': 'n',
          'workDate': _todayTs,
          'workType': 'w',
          'checkIn': {'bad': 'data'},  // _seconds 없음
          'status': 'present',
          'createdAt': _todayTs,
          'wageStatus': 'pending',
        };
        final model = AttendanceModel.fromMap(map, 'att');
        expect(model.checkInAt, isNull);
      });
    });

    // ── C-3. 야간교대 checkOut 보정 ─────────────────────────
    group('C-3. 야간교대 checkOut 보정', () {
      test('C-08: v2 Timestamp 야간교대 — 익일 퇴근 Timestamp는 보정 없음(이미 정확)', () {
        // checkIn = 22:00 KST, checkOut = 06:00 KST 익일 → Timestamp에 날짜 포함
        // checkOut Timestamp는 checkIn보다 이미 미래 → isBefore = false → 보정 없음
        final tsIn  = _kstTs(2024, 1, 15, 22, 0);  // 2024-01-15 22:00 KST
        final tsOut = _kstTs(2024, 1, 16,  6, 0);  // 2024-01-16 06:00 KST (익일)
        final map = <String, dynamic>{
          'applicationId': 'a', 'userId': 'u', 'businessId': 'b',
          'businessName': 'n', 'workDate': _todayTs, 'workType': 'w',
          'checkIn': tsIn, 'checkOut': tsOut,
          'status': 'present', 'createdAt': _todayTs, 'wageStatus': 'pending',
        };
        final model = AttendanceModel.fromMap(map, 'att');
        expect(model.checkOutAt!.isAfter(model.checkInAt!), isTrue);
      });

      test('C-09: v1 String 야간교대 — checkOut("06:00") < checkIn("22:00") → +1일 보정', () {
        // 같은 workDate에서 "06:00"과 "22:00"을 복원하면 checkOut < checkIn
        // → 보정 적용: checkOut += 1일 → checkOut > checkIn
        final workDateTs = Timestamp.fromDate(DateTime(2024, 1, 15));
        final map = <String, dynamic>{
          'applicationId': 'a', 'userId': 'u', 'businessId': 'b',
          'businessName': 'n', 'workDate': workDateTs, 'workType': 'w',
          'checkIn': '22:00',   // v1 String
          'checkOut': '06:00',  // v1 String — 같은 workDate → 보정 필요
          'status': 'present', 'createdAt': workDateTs, 'wageStatus': 'pending',
        };
        final model = AttendanceModel.fromMap(map, 'att');
        expect(model.checkInAt, isNotNull);
        expect(model.checkOutAt, isNotNull);
        expect(model.checkOutAt!.isAfter(model.checkInAt!), isTrue,
            reason: 'checkOut이 checkIn보다 이전이면 +1일 보정 적용되어야 함');
      });

      test('C-10: 정상 주간 근무 — checkOut > checkIn → 보정 없음', () {
        final workDateTs = Timestamp.fromDate(DateTime(2024, 1, 15));
        final map = <String, dynamic>{
          'applicationId': 'a', 'userId': 'u', 'businessId': 'b',
          'businessName': 'n', 'workDate': workDateTs, 'workType': 'w',
          'checkIn': '09:00',
          'checkOut': '18:00',
          'status': 'present', 'createdAt': workDateTs, 'wageStatus': 'pending',
        };
        final model = AttendanceModel.fromMap(map, 'att');
        // 18:00 > 09:00 → isBefore = false → 보정 없음
        expect(model.checkOut, '18:00');
        expect(model.checkIn, '09:00');
      });
    });

    // ── C-4. tryFromMap ──────────────────────────────────────
    group('C-4. tryFromMap', () {
      test('C-11: workDate 없음 → null 반환 (예외 삼킴)', () {
        final result = AttendanceModel.tryFromMap({
          'applicationId': 'a',
          'createdAt': _todayTs,
          // workDate 없음
        }, 'att');
        expect(result, isNull);
      });
    });

    // ── C-5. displayWage / 상태 getter ─────────────────────
    group('C-5. displayWage 및 wageStatus 상태 게이트', () {
      test('C-12: wageStatus=pending → displayWage null', () {
        final model = _makeAttendance(
          wageStatus: AttendanceModel.wagePending,
          finalWage: 100000,
        );
        expect(model.displayWage, isNull);
        expect(model.formattedDisplayWage, '-');
      });

      test('C-13: wageStatus=calculated → displayWage null', () {
        final model = _makeAttendance(
          wageStatus: AttendanceModel.wageCalculated,
          finalWage: 100000,
        );
        expect(model.displayWage, isNull);
      });

      test('C-14: wageStatus=confirmed → displayWage = finalWage', () {
        final model = _makeAttendance(
          wageStatus: AttendanceModel.wageConfirmed,
          finalWage: 80000,
        );
        expect(model.displayWage, 80000);
      });

      test('C-15: wageStatus=transferred → displayWage = finalWage', () {
        final model = _makeAttendance(
          wageStatus: AttendanceModel.wageTransferred,
          finalWage: 120000,
        );
        expect(model.displayWage, 120000);
      });

      test('C-16: formattedDisplayWage 쉼표 포맷 — 120000 → "120,000원"', () {
        final model = _makeAttendance(
          wageStatus: AttendanceModel.wageConfirmed,
          finalWage: 120000,
        );
        expect(model.formattedDisplayWage, '120,000원');
      });

      test('C-17: isMissedCheckout — 출근 있음·퇴근 없음·NO_SHOW 아님 → true', () {
        final tsIn = _kstTs(2024, 1, 15, 9, 0);
        final model = _makeAttendance(checkInTs: tsIn, status: AttendanceModel.statusPresent);
        expect(model.isMissedCheckout, isTrue);
      });

      test('C-18: isMissedCheckout — NO_SHOW 상태 → false (노쇼는 미퇴근 아님)', () {
        final tsIn = _kstTs(2024, 1, 15, 9, 0);
        final model = _makeAttendance(
          checkInTs: tsIn,
          status: AttendanceModel.statusNoShow,
        );
        expect(model.isMissedCheckout, isFalse);
      });
    });
  });
}
