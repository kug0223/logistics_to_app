// lib/utils/attendance_status_helper.dart
//
// 출퇴근 상태 판단 전용 유틸리티.
// 지각/조퇴 로직이 여러 파일에 복제되어 있던 것을 이곳으로 통일.
// 모든 시간 비교·변환은 반드시 이 클래스를 거친다.

import '../models/core/attendance_model.dart';
import '../models/core/application_model.dart';

class AttendanceStatusHelper {
  // ── 시간 변환 ──────────────────────────────────────────────

  /// "HH:mm" 또는 "HH:mm:ss" → 분 단위 정수
  static int timeToMinutes(String timeStr) {
    final parts = timeStr.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// 두 시간 사이 분 수 계산 (자정 넘김 자동 처리)
  static int minutesBetween(String start, String end) {
    final s = timeToMinutes(start);
    var e = timeToMinutes(end);
    if (e <= s) e += 1440; // 자정 넘김
    return e - s;
  }

  // ── 지각 판단 ──────────────────────────────────────────────

  /// 실제 출근이 예정보다 1분 이상 늦은지
  ///
  /// [isNextDay] 출근일이 근무 날짜의 다음날인 경우(야간 시프트)
  /// → Firestore checkIn 시 `DateTime.now()` vs `workDate` 비교로 결정
  static bool isLate(
    String checkIn,
    String scheduledStart, {
    bool isNextDay = false,
  }) {
    try {
      int actual = timeToMinutes(checkIn);
      final scheduled = timeToMinutes(scheduledStart);
      if (isNextDay) actual += 1440;
      return actual - scheduled > 0;
    } catch (_) {
      return false;
    }
  }

  // ── 조퇴 판단 ──────────────────────────────────────────────

  /// 실제 퇴근이 예정보다 1분 이상 이른지
  ///
  /// [checkIn] 출근 시각("HH:mm")을 전달하면 자정을 넘는 야간 근무를 정확히 처리.
  /// 예) 14:30 출근 / 23:00 계약 퇴근 / 01:00 실제 퇴근
  ///   → checkOut(01:00) < checkIn(14:30) → 익일 보정 → 25:00
  ///   → 25:00 > 23:00 → 조퇴 아님 ✅
  static bool isEarlyLeave(
    String checkOut,
    String scheduledEnd, {
    String? checkIn,
  }) {
    try {
      int actual = timeToMinutes(checkOut);
      int scheduled = timeToMinutes(scheduledEnd);
      if (checkIn != null) {
        final checkInMins = timeToMinutes(checkIn);
        if (actual < checkInMins) actual += 1440;
        if (scheduled < checkInMins) scheduled += 1440;
      }
      return scheduled - actual > 0;
    } catch (_) {
      return false;
    }
  }

  // ── 통합 상태 결정 ─────────────────────────────────────────

  /// 출퇴근 시각으로 DB 저장 상태 결정
  ///
  /// 조퇴 우선 → 지각 → 정상 순서로 판단.
  static String deriveStatus(
    ApplicationModel app,
    String checkIn,
    String? checkOut, {
    bool isNextDayCheckIn = false,
  }) {
    final scheduledStart = app.startTime.isNotEmpty ? app.startTime : '09:00';
    final scheduledEnd = app.endTime.isNotEmpty ? app.endTime : '18:00';

    if (checkOut != null &&
        isEarlyLeave(checkOut, scheduledEnd, checkIn: checkIn)) {
      return AttendanceModel.statusEarlyLeave;
    }
    if (isLate(checkIn, scheduledStart, isNextDay: isNextDayCheckIn)) {
      return AttendanceModel.statusLate;
    }
    return AttendanceModel.statusPresent;
  }

  // ── 근무 시간 계산 ─────────────────────────────────────────

  /// 실제 근무 분 수 계산 (자정 넘김 자동 처리)
  static int workMinutes(String checkIn, String checkOut) {
    try {
      return minutesBetween(checkIn, checkOut);
    } catch (_) {
      return 0;
    }
  }
}
