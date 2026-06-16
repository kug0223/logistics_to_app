// lib/utils/attendance_badge_helper.dart
//
// 출퇴근 배지(지각/조퇴/연장/심야) 표시 여부를 중앙에서 판단.
// 위젯 빌드는 각 화면에 위임하고, 플래그 계산만 담당.

import 'attendance_status_helper.dart';
import '../models/core/wage_detail_model.dart';

class AttendanceFlags {
  final bool isLate;
  final bool isEarlyLeave;
  final bool isOvertime;
  final bool isNight;
  final bool isEarlyArrival;

  const AttendanceFlags({
    required this.isLate,
    required this.isEarlyLeave,
    required this.isOvertime,
    required this.isNight,
    required this.isEarlyArrival,
  });

  bool get hasAny => isLate || isEarlyLeave || isOvertime || isNight || isEarlyArrival;

  static const none = AttendanceFlags(
    isLate: false,
    isEarlyLeave: false,
    isOvertime: false,
    isNight: false,
    isEarlyArrival: false,
  );
}

class AttendanceBadgeHelper {
  /// 출퇴근 시각과 wageDetail 기준으로 배지 표시 플래그를 계산.
  ///
  /// [graceMinutes] 연장 판단 허용 오차 분 (기본 0, 급여 확인 화면은 5).
  /// [wageDetail] 있으면 실제 계산값 우선 사용, 없으면 시각 비교로 추정.
  static AttendanceFlags compute({
    required String? checkIn,
    required String? checkOut,
    required String effStart,
    required String effEnd,
    WageDetailModel? wageDetail,
    int graceMinutes = 0,
  }) {
    if (checkIn == null) return AttendanceFlags.none;

    // 지각: checkIn만 있으면 판단 가능 (아직 퇴근 안 한 상태에서도 표시)
    // 야간 시프트(effStart >= 20:00, checkIn < 06:00): 자정 넘김 보정 필요
    final effStartMins = AttendanceStatusHelper.timeToMinutes(effStart);
    final checkInMins = AttendanceStatusHelper.timeToMinutes(checkIn);
    final isNextDay = effStartMins >= 20 * 60 && checkInMins < 6 * 60;
    final isLate = AttendanceStatusHelper.isLate(checkIn, effStart, isNextDay: isNextDay);
    // isNextDay=true(자정 이후 체크인)이면 effStart보다 반드시 늦으므로 조출 불가
    final isEarlyArrival = isNextDay
        ? false
        : AttendanceStatusHelper.isEarlyArrival(checkIn, effStart);

    // 조퇴·연장·심야: checkOut 없으면 판단 불가
    if (checkOut == null) {
      return AttendanceFlags(
        isLate: isLate,
        isEarlyLeave: false,
        isOvertime: false,
        isNight: false,
        isEarlyArrival: isEarlyArrival,
      );
    }

    final isEarlyLeave = AttendanceStatusHelper.isEarlyLeave(
        checkOut, effEnd, checkIn: checkIn);

    // wageDetail이 있으면 earlyArrivalMinutes로 정확히 분리
    // - isEarlyArrival: 조출 시간이 있음
    // - isOvertime: 연장 시간(조출 제외)이 있음
    // → 둘 다 true이면 조출+연장 배지 모두 표시
    final bool effectiveIsEarlyArrival;
    final bool isOvertime;
    if (wageDetail != null) {
      effectiveIsEarlyArrival = wageDetail.earlyArrivalMinutes > 0;
      isOvertime = (wageDetail.overtimeMinutes - wageDetail.earlyArrivalMinutes) > 0;
    } else {
      effectiveIsEarlyArrival = isEarlyArrival;
      isOvertime = AttendanceStatusHelper.isOvertime(checkOut, effEnd,
          checkIn: checkIn, graceMinutes: graceMinutes);
    }

    final isNight = wageDetail != null
        ? wageDetail.nightAllowanceApplied && wageDetail.nightMinutes > 0
        : (isOvertime &&
            AttendanceStatusHelper.isNightOvertime(checkOut, effEnd, checkIn,
                graceMinutes: graceMinutes));

    return AttendanceFlags(
      isLate: isLate,
      isEarlyLeave: isEarlyLeave,
      isOvertime: isOvertime,
      isNight: isNight,
      isEarlyArrival: effectiveIsEarlyArrival,
    );
  }
}
