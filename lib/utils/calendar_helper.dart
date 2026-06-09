import 'package:flutter/foundation.dart';
import '../models/core/application_model.dart';
import '../models/core/attendance_model.dart';

/// 캘린더 관련 헬퍼 함수
class CalendarHelper {
  /// 지원 목록 → 날짜별 인덱스 맵 생성 (O(n) 1회 → 이후 O(1) 조회)
  /// 사용: 달력 렌더 전 한 번 빌드하고, 각 날짜 셀에서 map[dateKey] 조회
  static Map<String, List<ApplicationModel>> buildDateIndex(
    List<ApplicationModel> applications,
    String selectedFilter, {
    int rangeMonths = 3,
  }) {
    final index = <String, List<ApplicationModel>>{};
    final now = DateTime.now();

    for (final app in applications) {
      if (!_passesFilter(app, selectedFilter)) continue;

      if (!app.isLongTermApplication) {
        final key = _dateKey(app.workDate);
        (index[key] ??= []).add(app);
      } else {
        // 장기: 계약 기간의 요일별로 날짜 전개
        final start = app.desiredStartDate ?? app.workDate;
        final end = app.actualResignDate ??
            app.workEndDate ??
            now.add(Duration(days: rangeMonths * 30));
        if (app.workDays == null || app.workDays!.isEmpty) {
          (index[_dateKey(start)] ??= []).add(app);
          continue;
        }
        var current = start;
        while (!current.isAfter(end)) {
          if (app.isScheduledOnDate(current)) {
            (index[_dateKey(current)] ??= []).add(app);
          }
          current = current.add(const Duration(days: 1));
        }
      }
    }
    return index;
  }

  /// 날짜 키 문자열 생성
  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 인덱스 맵에서 특정 날짜 이벤트 조회 (O(1))
  static List<ApplicationModel> getEventsForDayFromIndex(
    DateTime day,
    Map<String, List<ApplicationModel>> index,
  ) {
    return index[_dateKey(day)] ?? const [];
  }

  /// 특정 날짜의 지원 내역 가져오기 — 인덱스 없을 때 fallback (O(n))
  static List<ApplicationModel> getEventsForDay(
    DateTime day,
    List<ApplicationModel> applications,
    String selectedFilter,
  ) {
    return applications
        .where((app) => app.isScheduledOnDate(day) && _passesFilter(app, selectedFilter))
        .toList();
  }

  /// 필터 통과 여부
  static bool _passesFilter(ApplicationModel app, String selectedFilter) {
    // 퇴사/해지 완료된 장기 근무는 모든 필터에서 제외
    if (app.isLongTermApplication && app.isTerminationApproved) return false;

    if (selectedFilter == AppStatus.confirmed) {
      return AppStatus.confirmedStatuses.contains(app.status);
    } else if (selectedFilter == AppStatus.pending) {
      return app.status == AppStatus.pending;
    }

    // ALL: 취소/거절 제외
    return !AppStatus.inactiveStates.contains(app.status);
  }

  /// 이번 달 통계 대상 지원서 필터링
  ///
  /// - 단기: workDate가 이번 달
  /// - 장기 미확정: workDate가 이번 달 (지원일 기준)
  /// - 장기 확정: 계약 기간이 이번 달과 겹치는 경우
  static List<ApplicationModel> getThisMonthApplications(
    List<ApplicationModel> applications,
    DateTime focusedDay,
  ) {
    final firstOfMonth = DateTime(focusedDay.year, focusedDay.month, 1);
    final lastOfMonth = DateTime(focusedDay.year, focusedDay.month + 1, 0);

    return applications.where((app) {
      if (!app.isLongTermApplication) {
        return app.workDate.year == focusedDay.year &&
               app.workDate.month == focusedDay.month;
      }

      // 장기 미확정: 지원일 기준
      if (!AppStatus.confirmedStatuses.contains(app.status)) {
        return app.workDate.year == focusedDay.year &&
               app.workDate.month == focusedDay.month;
      }

      // 장기 확정: 계약 기간이 이번 달과 겹치는지
      if (app.isTerminationApproved) return false;
      final endDate = app.actualResignDate ?? app.workEndDate;
      if (endDate == null) return false;
      final startDate = app.desiredStartDate ?? app.workDate;
      return !startDate.isAfter(lastOfMonth) && !endDate.isBefore(firstOfMonth);
    }).toList();
  }

  /// 확정 근무 수 계산 (단기만 카운트)
  static int getConfirmedCount(List<ApplicationModel> applications) {
    return applications.where((app) =>
      AppStatus.confirmedStatuses.contains(app.status) &&
      !app.isLongTermApplication
    ).length;
  }

  /// 대기 중 수 계산
  static int getPendingCount(List<ApplicationModel> applications) {
    return applications.where((app) => app.status == AppStatus.pending).length;
  }

  /// 총 예상 수입 계산 (세후)
  ///
  /// - 단기: app.wage (세전)
  /// - 장기 확정: 일당 × 이번 달 근무일수 (세전)
  static int getTotalIncome(
    List<ApplicationModel> applications,
    DateTime focusedDay,
  ) {
    return applications
        .where((app) => AppStatus.confirmedStatuses.contains(app.status))
        .fold(0, (sum, app) {
          if (!app.isLongTermApplication) {
            return sum + app.wage;
          }
          final workDaysCount = _workDaysInMonth(app, focusedDay);
          final daily = _dailyWage(app);
          return sum + daily * workDaysCount;
        });
  }

  /// 실근무일수 계산 (출근 기록 있는 날짜 수, 같은 날 2잡도 1일로 카운트)
  static int getActualWorkDays(List<AttendanceModel> attendances, DateTime focusedDay) {
    final uniqueDates = <String>{};
    for (var att in attendances) {
      if (att.workDate.year == focusedDay.year &&
          att.workDate.month == focusedDay.month &&
          att.checkIn != null) {
        uniqueDates.add('${att.workDate.year}-${att.workDate.month}-${att.workDate.day}');
      }
    }
    return uniqueDates.length;
  }

  /// 확정수입 계산 (wageStatus == 'confirmed'인 attendance의 finalWage 합산)
  static int getConfirmedIncome(List<AttendanceModel> attendances, DateTime focusedDay) {
    debugPrint('🔍 [getConfirmedIncome] 확정수입 계산');
    debugPrint('   전체 attendance: ${attendances.length}건');

    final confirmedList = attendances.where((att) =>
      att.workDate.year == focusedDay.year &&
      att.workDate.month == focusedDay.month &&
      att.wageStatus == 'confirmed' &&
      att.finalWage != null
    ).toList();

    debugPrint('   confirmed 상태: ${confirmedList.length}건');
    for (var att in confirmedList) {
      debugPrint('   💰 ${att.workDate.toString().substring(0, 10)}: finalWage=${att.finalWage}');
    }

    final total = confirmedList.fold(0, (sum, att) => sum + (att.finalWage ?? 0));
    debugPrint('   총 확정수입: $total');
    return total;
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  /// 일용직 근로소득세 적용 후 세후 일당 반환
  ///
  /// ⚠️ Deprecated — getTotalIncome이 세전으로 전환(2026-05)되어 더 이상 사용되지 않음.
  /// 세후 계산이 필요한 경우에만 직접 호출.
  @Deprecated('세전 집계로 전환. 세후 계산 필요 시에만 직접 사용.')
  static int calculateNetDailyWage(int grossWage) {
    if (grossWage <= 150000) return grossWage;
    final taxableAmount = grossWage - 150000;
    final tax = (taxableAmount * 0.06 * 0.45).round();
    return grossWage - tax;
  }

  /// 시급/일급을 일당으로 환산
  static int _dailyWage(ApplicationModel app) {
    if (app.wageType == 'hourly') {
      int toMin(String t) {
        final p = t.split(':');
        if (p.length < 2) return 0;
        return int.parse(p[0]) * 60 + int.parse(p[1]);
      }
      final startMin = toMin(app.startTime);
      var endMin = toMin(app.endTime);
      if (endMin <= startMin) endMin += 1440; // 야간 시프트
      final hours = (endMin - startMin) / 60.0;
      return (app.wage * hours).round();
    }
    return app.wage; // daily
  }

  /// 장기공고의 이번 달 근무 예정 일수
  static int _workDaysInMonth(ApplicationModel app, DateTime focusedDay) {
    if (app.workDays == null || app.workDays!.isEmpty) return 0;

    final firstOfMonth = DateTime(focusedDay.year, focusedDay.month, 1);
    final lastOfMonth = DateTime(focusedDay.year, focusedDay.month + 1, 0);

    final startDate = app.desiredStartDate ?? app.workDate;
    final endDate = app.actualResignDate ?? app.workEndDate;
    if (endDate == null) return 0;

    final rangeStart = startDate.isAfter(firstOfMonth) ? startDate : firstOfMonth;
    final rangeEnd = endDate.isBefore(lastOfMonth) ? endDate : lastOfMonth;

    final startOnly = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final endOnly = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);

    if (startOnly.isAfter(endOnly)) return 0;

    const weekDayNames = ['월', '화', '수', '목', '금', '토', '일'];
    int count = 0;
    DateTime d = startOnly;
    while (!d.isAfter(endOnly)) {
      final dayName = weekDayNames[d.weekday - 1]; // 1=Mon
      if (app.isLeaveDateOn(d)) {
        // 휴무: 카운트 없음
      } else if (app.isExtraWorkDateOn(d)) {
        // 추가 근무: 정규 근무일 여부와 무관하게 1일 카운트
        count++;
      } else if (app.workDays!.contains(dayName)) {
        count++;
      }
      d = d.add(const Duration(days: 1));
    }
    return count;
  }
}
