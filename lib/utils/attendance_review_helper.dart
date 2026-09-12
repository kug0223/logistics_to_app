// lib/utils/attendance_review_helper.dart
//
// [AH-V2-04A] "지금 관리자가 확인·처리해야 하는 오늘 근태"의 canonical 판정.
//
// 관리자 Home의 `근태 확인 N명`과 AttendanceStatusDialog의 `검토` 탭은
// 같은 질문에 답해야 한다. 이전에는 두 곳이 서로 다른 조건을 들고 있어
// 숫자가 어긋났고, 처리를 끝낸 건이 Home에서 사라지지 않았다.
//
// [계약]
//   ACTION_REQUIRED != ABNORMAL_HISTORY     처리 끝난 이력은 할 일이 아니다
//   ACTION_REQUIRED != FUTURE_NOT_STARTED   아직 시작도 안 한 근무는 할 일이 아니다
//
// [종결 상태 — 다시 처리할 것이 없다]
//   NO_SHOW        관리자 노쇼 처리 결과 (wageStatus=confirmed, finalWage=0)
//   absent         시스템 결근 확정 (자동결근 스케줄러 / 퇴사 / 사업장·계정 삭제)
//                  ※ 퇴사·삭제 경로는 wageStatus를 쓰지 않으므로 status로 직접 판정해야 한다
//   wageStatus     calculated / confirmed / transferred — 정산 단계 진입
//   adminConfirmed 관리자 1차 확인 완료
//
// [시간 기준]
//   출근 기록 없음 → scheduledStart 경과 시점부터 확인 대상
//   퇴근 기록 없음 → scheduledEnd 경과 시점부터 확인 대상 (야간 시프트 자정 보정)
//   사업장 lateGrace(지각 유예)는 "체크인을 지각으로 분류할지"의 규칙이며
//   미출근 판정에 쓰인 적이 없다. 여기서도 적용하지 않는다.
//
import '../models/core/attendance_model.dart';
import 'attendance_status_helper.dart';

class AttendanceReviewHelper {
  const AttendanceReviewHelper._();

  /// "HH:mm" / "HH:mm:ss"(레거시) → 근무일 기준 DateTime.
  /// 파싱 불가 시 null.
  static DateTime? _at(DateTime workDate, String raw) {
    final timeStr = raw.length >= 5 ? raw.substring(0, 5) : raw;
    final parts = timeStr.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return DateTime(workDate.year, workDate.month, workDate.day, h, m);
  }

  /// 퇴근 예정 시각 — 종료가 시작보다 이르면 익일로 넘긴다 (야간 시프트).
  static DateTime? _endAt(DateTime workDate, String start, String end) {
    final s = _at(workDate, start);
    final e = _at(workDate, end);
    if (e == null) return null;
    if (s != null && !e.isAfter(s)) return e.add(const Duration(days: 1));
    return e;
  }

  /// 이미 처리가 끝나 더 볼 것이 없는 근태인지.
  ///
  /// 완료/이력 표면에는 그대로 남아야 하며, "처리할 일"에서만 빠진다.
  static bool isSettled(AttendanceModel? attendance) {
    final att = attendance;
    if (att == null) return false;
    if (att.status == AttendanceModel.statusNoShow) return true;
    if (att.status == AttendanceModel.statusAbsent) return true;
    if (att.wageStatus == AttendanceModel.wageCalculated ||
        att.wageStatus == AttendanceModel.wageConfirmed ||
        att.wageStatus == AttendanceModel.wageTransferred) {
      return true;
    }
    if (att.adminConfirmed) return true;
    return false;
  }

  /// 지금 관리자 확인·처리가 필요한 근태인가.
  ///
  /// [scheduledStart]/[scheduledEnd]는 호출부가 해석한 "HH:mm" 근무 예정 시각이다.
  /// (dialog는 workDetail override를 반영한 effectiveStart/End, Home은 지원서 시각)
  static bool requiresReviewNow({
    required DateTime now,
    required DateTime workDate,
    required String scheduledStart,
    required String scheduledEnd,
    AttendanceModel? attendance,
  }) {
    if (isSettled(attendance)) return false;

    final att = attendance;

    // 출근 기록 없음 — 출근 예정 시각 전이면 아직 정상이다
    if (att?.checkInAt == null) {
      final startAt = _at(workDate, scheduledStart);
      if (startAt == null) return false; // 시각 해석 불가 → 임의 판정하지 않음
      return !now.isBefore(startAt);
    }

    // 출근했고 퇴근 기록 없음 — 퇴근 예정 시각이 지나야 처리 대상 (근무 중은 정상)
    if (att!.checkOutAt == null) {
      final endAt = _endAt(workDate, scheduledStart, scheduledEnd);
      if (endAt == null) return false;
      return !now.isBefore(endAt);
    }

    // 출퇴근 완료 — 지각·조퇴 등 이상이 있을 때만.
    // 정상 완료 건의 마감은 Home의 `마감 필요` 행이 담당한다 (중복 집계 금지).
    final ci = att.checkIn;
    final co = att.checkOut;
    if (ci == null || co == null) return false;
    final isLate = AttendanceStatusHelper.isLate(
      ci,
      scheduledStart,
      isNextDay: AttendanceStatusHelper.isNextDayCheckIn(ci, scheduledStart),
    );
    final isEarlyLeave = AttendanceStatusHelper.isEarlyLeave(
      co,
      scheduledEnd,
      checkIn: ci,
    );
    return isLate || isEarlyLeave;
  }
}
