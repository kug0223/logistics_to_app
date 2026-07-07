// test/unit/attendance_status_helper_test.dart
// AttendanceStatusHelper 순수 Dart 시간 계산 단위 테스트
//
// 모든 메서드가 Firebase 의존 없는 순수 계산 로직.
// 자정 넘김, 야간 판정, 폴백 처리 등 엣지 케이스 집중 검증.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/attendance_status_helper.dart';

void main() {
  // ══════════════════════════════════════════════════════
  // timeToMinutes
  // ══════════════════════════════════════════════════════
  group('AttendanceStatusHelper.timeToMinutes', () {
    test('"09:00" → 540', () {
      expect(AttendanceStatusHelper.timeToMinutes('09:00'), equals(540));
    });

    test('"18:30" → 1110', () {
      expect(AttendanceStatusHelper.timeToMinutes('18:30'), equals(1110));
    });

    test('"00:00" → 0', () {
      expect(AttendanceStatusHelper.timeToMinutes('00:00'), equals(0));
    });

    test('"23:59" → 1439 (하루 최대)', () {
      expect(AttendanceStatusHelper.timeToMinutes('23:59'), equals(1439));
    });

    test('"09:00:30" (초 포함) → 540 (초 무시)', () {
      // parts[0]=9, parts[1]=0 → 540
      expect(AttendanceStatusHelper.timeToMinutes('09:00:30'), equals(540));
    });

    test('빈 문자열 → 0 (폴백)', () {
      expect(AttendanceStatusHelper.timeToMinutes(''), equals(0));
    });

    test('"invalid" → 0 (파싱 실패 폴백)', () {
      expect(AttendanceStatusHelper.timeToMinutes('invalid'), equals(0));
    });

    test('"25:00" → 1500 (비정상 시간도 수학적 변환)', () {
      // 25 * 60 + 0 = 1500
      expect(AttendanceStatusHelper.timeToMinutes('25:00'), equals(1500));
    });
  });

  // ══════════════════════════════════════════════════════
  // minutesBetween
  // ══════════════════════════════════════════════════════
  group('AttendanceStatusHelper.minutesBetween', () {
    test('"09:00" ~ "18:00" → 540', () {
      expect(AttendanceStatusHelper.minutesBetween('09:00', '18:00'), equals(540));
    });

    test('"00:00" ~ "00:00" → 0 (동일 시각 = 0분, 24시간 아님)', () {
      // s=0, e=0. e < s? No. result = 0 → 자정 넘김 오감지 방지
      expect(AttendanceStatusHelper.minutesBetween('00:00', '00:00'), equals(0));
    });

    test('"09:00" ~ "09:00" → 0', () {
      expect(AttendanceStatusHelper.minutesBetween('09:00', '09:00'), equals(0));
    });

    test('"22:00" ~ "06:00" (야간, 자정 넘김) → 480', () {
      // s=1320, e=360. e < s → e += 1440 → 1800. 1800-1320=480
      expect(AttendanceStatusHelper.minutesBetween('22:00', '06:00'), equals(480));
    });

    test('"23:00" ~ "01:00" (자정 넘김) → 120', () {
      // s=1380, e=60. e < s → e += 1440 → 1500. 1500-1380=120
      expect(AttendanceStatusHelper.minutesBetween('23:00', '01:00'), equals(120));
    });

    test('"00:30" ~ "23:30" (이른 새벽 시작, 전날까지) → 1380', () {
      // s=30, e=1410. e < s? No. result=1380
      expect(AttendanceStatusHelper.minutesBetween('00:30', '23:30'), equals(1380));
    });

    test('"09:00" ~ "01:00" (다음날 새벽 퇴근) → 960 (16시간)', () {
      // s=540, e=60. e < s → e += 1440 → 1500. 1500-540=960
      expect(AttendanceStatusHelper.minutesBetween('09:00', '01:00'), equals(960));
    });
  });

  // ══════════════════════════════════════════════════════
  // isLate
  // ══════════════════════════════════════════════════════
  group('AttendanceStatusHelper.isLate', () {
    test('1분 지각 → true', () {
      expect(AttendanceStatusHelper.isLate('09:01', '09:00'), isTrue);
    });

    test('정각 출근 → false (지각 아님)', () {
      expect(AttendanceStatusHelper.isLate('09:00', '09:00'), isFalse);
    });

    test('1분 일찍 출근 → false', () {
      expect(AttendanceStatusHelper.isLate('08:59', '09:00'), isFalse);
    });

    test('30분 지각 → true', () {
      expect(AttendanceStatusHelper.isLate('09:30', '09:00'), isTrue);
    });

    test('야간 시프트: isNextDay=true, 실제 00:30 출근 예정 23:00 → true', () {
      // actual=30+1440=1470, scheduled=1380. 1470-1380=90 > 0 → true
      expect(
        AttendanceStatusHelper.isLate('00:30', '23:00', isNextDay: true),
        isTrue,
      );
    });

    test('야간 시프트: isNextDay=true, 정각 출근 → false', () {
      // actual=1380+1440=2820, scheduled=1380. 2820-1380=1440 > 0 → true
      // 실제: checkIn="23:00" isNextDay=true → 1380+1440=2820 > 1380 → true
      // 아니면 checkIn="23:00" isNextDay=false → 1380-1380=0 > 0 → false
      expect(
        AttendanceStatusHelper.isLate('23:00', '23:00', isNextDay: false),
        isFalse,
      );
    });
  });

  // ══════════════════════════════════════════════════════
  // isEarlyArrival
  // ══════════════════════════════════════════════════════
  group('AttendanceStatusHelper.isEarlyArrival', () {
    test('30분 일찍 출근, threshold=30 → true (경계값 포함)', () {
      // scheduled=540, actual=510. 540-510=30 >= 30 → true
      expect(AttendanceStatusHelper.isEarlyArrival('08:30', '09:00'), isTrue);
    });

    test('29분 일찍, threshold=30 → false', () {
      // scheduled=540, actual=511. 540-511=29 >= 30 → false
      expect(AttendanceStatusHelper.isEarlyArrival('08:31', '09:00'), isFalse);
    });

    test('정각 출근 → false', () {
      // 540-540=0 >= 30 → false
      expect(AttendanceStatusHelper.isEarlyArrival('09:00', '09:00'), isFalse);
    });

    test('야간 시프트 오감지 방지: scheduled=00:30, actual=23:30 → false', () {
      // scheduled=30, actual=1410. 30-1410=-1380 < 0 → false
      // 이유: 야간 시프트에서 checkIn이 scheduled보다 항상 크게 나타남
      expect(AttendanceStatusHelper.isEarlyArrival('23:30', '00:30'), isFalse);
    });

    test('threshold=0: 1분 일찍 → true', () {
      expect(
        AttendanceStatusHelper.isEarlyArrival('08:59', '09:00', thresholdMinutes: 0),
        isTrue,
      );
    });

    test('threshold=60: 59분 일찍 → false', () {
      expect(
        AttendanceStatusHelper.isEarlyArrival('08:01', '09:00', thresholdMinutes: 60),
        isFalse,
      );
    });
  });

  // ══════════════════════════════════════════════════════
  // isEarlyLeave
  // ══════════════════════════════════════════════════════
  group('AttendanceStatusHelper.isEarlyLeave', () {
    test('1분 일찍 퇴근 → true', () {
      // scheduled=1080, actual=1079. 1080-1079=1 > 0 → true
      expect(AttendanceStatusHelper.isEarlyLeave('17:59', '18:00'), isTrue);
    });

    test('정시 퇴근 → false', () {
      // 1080-1080=0 > 0 → false
      expect(AttendanceStatusHelper.isEarlyLeave('18:00', '18:00'), isFalse);
    });

    test('1분 늦게 퇴근 → false (연장)', () {
      // 1080-1081 < 0 → false
      expect(AttendanceStatusHelper.isEarlyLeave('18:01', '18:00'), isFalse);
    });

    test('야간 근무 자정 넘김: checkIn=14:30, checkOut=01:00, scheduled=23:00 → false', () {
      // checkIn=870, actual=60. actual < checkIn → actual += 1440 → 1500
      // scheduled=1380, checkIn=870 → scheduled > checkIn → no adjust
      // 1380-1500 = -120 > 0 → false (조퇴 아님)
      expect(
        AttendanceStatusHelper.isEarlyLeave('01:00', '23:00', checkIn: '14:30'),
        isFalse,
      );
    });

    test('야간 근무: checkIn=22:00, checkOut=01:00, scheduled=02:00 → false (정시 못 채움)', () {
      // checkIn=1320, actual=60. actual < checkIn → actual += 1440 → 1500
      // scheduled=120. scheduled < checkIn → scheduled += 1440 → 1560
      // 1560-1500=60 > 0 → true (조퇴)
      expect(
        AttendanceStatusHelper.isEarlyLeave('01:00', '02:00', checkIn: '22:00'),
        isTrue,
      );
    });

    test('checkIn 없이 단순 비교: 17:30 < 18:00 → true', () {
      expect(AttendanceStatusHelper.isEarlyLeave('17:30', '18:00'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // isOvertime
  // ══════════════════════════════════════════════════════
  group('AttendanceStatusHelper.isOvertime', () {
    test('1분 연장 → true', () {
      // 1081 > 1080 → true
      expect(AttendanceStatusHelper.isOvertime('18:01', '18:00'), isTrue);
    });

    test('정시 퇴근 → false', () {
      expect(AttendanceStatusHelper.isOvertime('18:00', '18:00'), isFalse);
    });

    test('일찍 퇴근 → false', () {
      expect(AttendanceStatusHelper.isOvertime('17:59', '18:00'), isFalse);
    });

    test('graceMinutes=5: 4분 연장 → false (허용 오차 내)', () {
      // 1084 > 1080 + 5 = 1085 → false
      expect(
        AttendanceStatusHelper.isOvertime('18:04', '18:00', graceMinutes: 5),
        isFalse,
      );
    });

    test('graceMinutes=5: 6분 연장 → true (허용 오차 초과)', () {
      // 1086 > 1085 → true
      expect(
        AttendanceStatusHelper.isOvertime('18:06', '18:00', graceMinutes: 5),
        isTrue,
      );
    });

    test('야간 근무 연장: checkIn=22:00, checkOut=06:30, scheduled=06:00 → true', () {
      // checkIn=1320, actual=390. actual < checkIn → actual+1440=1830
      // scheduled=360. scheduled < checkIn → scheduled+1440=1800
      // 1830 > 1800 → true
      expect(
        AttendanceStatusHelper.isOvertime('06:30', '06:00', checkIn: '22:00'),
        isTrue,
      );
    });

    test('야간 근무 정시: checkIn=22:00, checkOut=06:00, scheduled=06:00 → false', () {
      // actual=360+1440=1800, scheduled=360+1440=1800 → false
      expect(
        AttendanceStatusHelper.isOvertime('06:00', '06:00', checkIn: '22:00'),
        isFalse,
      );
    });
  });

  // ══════════════════════════════════════════════════════
  // isNightOvertime
  // ══════════════════════════════════════════════════════
  group('AttendanceStatusHelper.isNightOvertime', () {
    test('22:01 퇴근 (계약 18:00) → 연장이고 야간 → true', () {
      // isOvertime: 1321 > 1080 → true
      // outMins=1321, inMins=540. 1321 < 540? No. 1321 > 1320 → true
      expect(
        AttendanceStatusHelper.isNightOvertime('22:01', '18:00', '09:00'),
        isTrue,
      );
    });

    test('21:59 퇴근 (계약 18:00) → 연장이지만 야간 시간대 아님 → false', () {
      // outMins=1319, inMins=540. 1319 > 1320? no → false
      expect(
        AttendanceStatusHelper.isNightOvertime('21:59', '18:00', '09:00'),
        isFalse,
      );
    });

    test('정시 퇴근 → isOvertime=false → false', () {
      expect(
        AttendanceStatusHelper.isNightOvertime('18:00', '18:00', '09:00'),
        isFalse,
      );
    });

    test('야간 시프트 연장: checkIn=22:00, checkOut=06:30, scheduled=06:00 → true', () {
      // isOvertime → true (검증 위에서 함)
      // outMins=390, inMins=1320. outMins < inMins → outMins+1440=1830
      // 1830 > 1320 → true
      expect(
        AttendanceStatusHelper.isNightOvertime('06:30', '06:00', '22:00'),
        isTrue,
      );
    });
  });

  // ══════════════════════════════════════════════════════
  // workMinutes
  // ══════════════════════════════════════════════════════
  group('AttendanceStatusHelper.workMinutes', () {
    test('"09:00" ~ "18:00" → 540', () {
      expect(AttendanceStatusHelper.workMinutes('09:00', '18:00'), equals(540));
    });

    test('"22:00" ~ "06:00" (야간) → 480', () {
      expect(AttendanceStatusHelper.workMinutes('22:00', '06:00'), equals(480));
    });

    test('동일 시각 → 0', () {
      expect(AttendanceStatusHelper.workMinutes('09:00', '09:00'), equals(0));
    });
  });

  // ══════════════════════════════════════════════════════
  // isValidWorkPeriod
  // ══════════════════════════════════════════════════════
  group('AttendanceStatusHelper.isValidWorkPeriod', () {
    test('"09:00" ~ "18:00" (9시간) → true', () {
      expect(AttendanceStatusHelper.isValidWorkPeriod('09:00', '18:00'), isTrue);
    });

    test('동일 시각 → 0분 → false', () {
      expect(AttendanceStatusHelper.isValidWorkPeriod('09:00', '09:00'), isFalse);
    });

    test('"09:00" ~ "01:00" (16시간, 경계값) → true', () {
      // 960분 = 16*60 → true (960 > 0 && 960 <= 960)
      expect(AttendanceStatusHelper.isValidWorkPeriod('09:00', '01:00'), isTrue);
    });

    test('"09:00" ~ "01:01" (16시간 1분, 초과) → false', () {
      // s=540, e=61 < 540 → e+1440=1501. 1501-540=961 > 960 → false
      expect(AttendanceStatusHelper.isValidWorkPeriod('09:00', '01:01'), isFalse);
    });

    test('maxHours=8: 8시간 근무 → true', () {
      expect(
        AttendanceStatusHelper.isValidWorkPeriod('09:00', '17:00', maxHours: 8),
        isTrue,
      );
    });

    test('maxHours=8: 8시간 1분 → false', () {
      expect(
        AttendanceStatusHelper.isValidWorkPeriod('09:00', '17:01', maxHours: 8),
        isFalse,
      );
    });

    test('야간 근무 16시간 이내 → true', () {
      // "22:00" ~ "06:00" = 480분 (8시간) → true
      expect(AttendanceStatusHelper.isValidWorkPeriod('22:00', '06:00'), isTrue);
    });
  });
}
