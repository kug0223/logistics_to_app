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
  /// [특이사항] 구버전 데이터나 수동 입력으로 형식이 깨진 시간 문자열이 올 수 있음.
  /// 파싱 실패 시 0 반환 → 지각 판단에서 항상 정각 처리됨 (관대한 방향).
  static int timeToMinutes(String timeStr) {
    try {
      final parts = timeStr.split(':');
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    } catch (_) {
      return 0;
    }
  }

  /// 두 시간 사이 분 수 계산 (자정 넘김 자동 처리)
  static int minutesBetween(String start, String end) {
    final s = timeToMinutes(start);
    var e = timeToMinutes(end);
    if (e < s) e += 1440; // 자정 넘김 (e == s는 0분 근무 — 24시간으로 잘못 계산 방지)
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

  // ── 조출 판단 ──────────────────────────────────────────────

  /// 실제 출근이 예정보다 [thresholdMinutes](기본 30)분 이상 이른지
  ///
  /// [A21 설계] 야간 시프트(예: 예정 시작 00:30, 실제 출근 23:30)에서 자정 넘김 보정을 하지 않는다.
  /// 이유: 조출은 "같은 근무 시프트 내에서 일찍 출근"을 의미하며, 야간 시프트에서는
  /// checkIn이 scheduledStart보다 항상 크게 나타나므로 오감지 우려가 없다.
  /// (scheduled=30, actual=1410 → 30-1410 < 0 → 조출 아님으로 올바르게 처리)
  static bool isEarlyArrival(
    String checkIn,
    String scheduledStart, {
    int thresholdMinutes = 30,
  }) {
    try {
      final actual = timeToMinutes(checkIn);
      final scheduled = timeToMinutes(scheduledStart);
      return scheduled - actual >= thresholdMinutes;
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
    String? effStart,
    String? effEnd,
  }) {
    final scheduledStart = (effStart != null && effStart.isNotEmpty)
        ? effStart
        : (app.startTime.isNotEmpty ? app.startTime : '09:00');
    final scheduledEnd = (effEnd != null && effEnd.isNotEmpty)
        ? effEnd
        : (app.endTime.isNotEmpty ? app.endTime : '18:00');

    if (checkOut != null &&
        isEarlyLeave(checkOut, scheduledEnd, checkIn: checkIn)) {
      return AttendanceModel.statusEarlyLeave;
    }
    if (isLate(checkIn, scheduledStart, isNextDay: isNextDayCheckIn)) {
      return AttendanceModel.statusLate;
    }
    return AttendanceModel.statusPresent;
  }

  // ── 연장·심야 판단 ────────────────────────────────────────

  /// 실제 퇴근이 예정 종료시간보다 늦은지 (연장 여부)
  ///
  /// [graceMinutes] 허용 오차 분. 기본 0(1분 초과 시 연장).
  /// [checkIn] 전달 시 자정 넘김을 자동 처리.
  static bool isOvertime(
    String checkOut,
    String scheduledEnd, {
    String? checkIn,
    int graceMinutes = 0,
  }) {
    try {
      int actual = timeToMinutes(checkOut);
      int scheduled = timeToMinutes(scheduledEnd);
      if (checkIn != null) {
        final inMins = timeToMinutes(checkIn);
        if (actual < inMins) actual += 1440;
        if (scheduled <= inMins) scheduled += 1440;
      }
      return actual > scheduled + graceMinutes;
    } catch (_) {
      return false;
    }
  }

  /// 계약 종료 이후 야간 구간(22:00~)에서 연장 발생 여부
  ///
  /// 계약 시간 내 야간은 일급에 포함이므로 연장 없으면 심야 배지 불필요.
  static bool isNightOvertime(
    String checkOut,
    String scheduledEnd,
    String checkIn, {
    int graceMinutes = 0,
  }) {
    if (!isOvertime(checkOut, scheduledEnd, checkIn: checkIn, graceMinutes: graceMinutes)) {
      return false;
    }
    try {
      int outMins = timeToMinutes(checkOut);
      final inMins = timeToMinutes(checkIn);
      if (outMins < inMins) outMins += 1440;
      return outMins > 22 * 60;
    } catch (_) {
      return false;
    }
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

  // ── 시간 유효성 검증 ───────────────────────────────────────

  /// 출퇴근 시간 조합이 유효한지 확인.
  ///
  /// 계산된 근무 시간이 0분 이하이거나 [maxHours] 시간(기본 16)을 초과하면
  /// 시간 역전으로 간주하여 false 반환.
  /// 야간 근무(자정 넘김)는 `minutesBetween`이 자동 보정하므로
  /// 16시간(기본)을 넘지 않으면 정상으로 통과된다.
  static bool isValidWorkPeriod(
    String checkIn,
    String checkOut, {
    int maxHours = 16,
  }) {
    try {
      final minutes = workMinutes(checkIn, checkOut);
      return minutes > 0 && minutes <= maxHours * 60;
    } catch (_) {
      return false;
    }
  }
}
