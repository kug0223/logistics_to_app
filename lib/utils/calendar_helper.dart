import '../models/core/application_model.dart';
import '../models/core/attendance_model.dart';

// ══════════════════════════════════════════════════════════════════════════
// [검증 이력 — 재검증 시 참고]
//
// ▶ 설계 원칙
//   · 단기: 날짜 1개(workDate), 예상수입 = _dailyWage(app) × 1건
//   · 장기 확정: 이번 달 workDays 해당 요일 수 × _dailyWage(app)
//   · effectiveStart = desiredStartDate ?? workDate, confirmedAt > workDate이면 confirmedAt으로 보정
//     (isWorkingOnDate · isScheduledOnDate · _workDaysInMonth · workPeriodDisplay 모두 동일 로직)
//
// ▶ 검증 완료 항목
//   [C1] 단기 wageType='hourly' 예상수입 오류 → getTotalIncome에서 _dailyWage 경유로 수정 (2026-06)
//   [B3] _workDaysInMonth confirmedAt 보정 추가 — confirmedAt > workDate이면 미근무 기간 제외 (2026-06)
//
// ▶ 설계 수용 사항 (수정 불필요)
//   · workEndDate=null 장기 확정: 전 시스템(isWorkingOnDate 포함)에서 일관되게 false/0 처리 — "기간 미정" 계약 전용
//   · getConfirmedCount 장기 제외: 장기는 건수보다 예상수입/실근무일수로 표현하는 것이 의도된 설계
//   · getActualWorkDays 복수 잡: Set 중복 제거로 같은 날 2개 잡도 1일로 정확히 처리
//   · 시급 계산 시 휴게시간 미반영: 앱 스펙상 허용 범위 (breakMinutes 필드 application에 없음)
//   · buildDateIndex start = workDate 기준 (confirmedAt 보정 없음):
//     isScheduledOnDate 내부에서 효과적으로 필터링되므로 오버인덱싱 없음
// ══════════════════════════════════════════════════════════════════════════

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
    return index[_dateKey(day)] ?? [];
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
  /// - 장기 미확정: workDate가 이번 달 (지원일 기준 — 달 이동 시 PENDING이 사라지는 것이 의도된 동작)
  /// - 장기 확정: 계약 기간이 이번 달과 겹치는 경우
  ///
  /// ⚠️ 장기 확정에서 startDate는 confirmedAt 보정 없이 desiredStartDate ?? workDate 사용.
  ///    "겹치는지" 체크가 목적이므로 영향 없음 — _workDaysInMonth에서 confirmedAt 보정이 실제 계산을 담당.
  ///
  /// ⚠️ workEndDate=null인 장기 확정은 항상 false → 통계에서 제외.
  ///    isWorkingOnDate도 동일하게 false를 반환하므로 전 시스템 일관성 있음.
  ///    "기간 미정" 계약이 실제 데이터에 존재한다면 별도 처리 필요.
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

      // 장기 미확정: 지원일 기준 (해당 달에만 PENDING으로 집계 — 의도된 설계)
      if (!AppStatus.confirmedStatuses.contains(app.status)) {
        return app.workDate.year == focusedDay.year &&
               app.workDate.month == focusedDay.month;
      }

      // 장기 확정: 계약 기간이 이번 달과 겹치는지
      // isTerminationApproved=true(퇴사·해지 완료) 이면 통계에서 완전 제외
      if (app.isTerminationApproved) return false;
      final endDate = app.actualResignDate ?? app.workEndDate;
      if (endDate == null) return false; // workEndDate=null → 제외 (isWorkingOnDate도 동일)
      final startDate = app.desiredStartDate ?? app.workDate;
      return !startDate.isAfter(lastOfMonth) && !endDate.isBefore(firstOfMonth);
    }).toList();
  }

  /// 확정 근무 수 계산 (단기만 카운트)
  ///
  /// 장기를 제외하는 것은 의도된 설계: 장기는 건수 카운트보다 예상수입·실근무일수로 표현.
  /// 장기 포함이 필요해지면 이 함수가 아닌 UI 레이어에서 별도 카운트 표시 추가 권장.
  static int getConfirmedCount(List<ApplicationModel> applications) {
    return applications.where((app) =>
      AppStatus.confirmedStatuses.contains(app.status) &&
      !app.isLongTermApplication
    ).length;
  }

  /// 대기 중 수 계산 (단기·장기 모두 포함)
  static int getPendingCount(List<ApplicationModel> applications) {
    return applications.where((app) => app.status == AppStatus.pending).length;
  }

  /// 총 예상 수입 계산 (세전)
  ///
  /// - 단기: _dailyWage(app) — wageType='hourly'이면 시급×근무시간, 'daily'이면 wage 그대로
  /// - 장기 확정: _dailyWage(app) × 이번 달 근무일수
  ///
  /// ⚠️ 단기도 반드시 _dailyWage 경유: wageType='hourly'인 경우 app.wage는 시급이므로
  ///    app.wage를 그대로 합산하면 실제 예상수입보다 대폭 과소 계산됨.
  static int getTotalIncome(
    List<ApplicationModel> applications,
    DateTime focusedDay,
  ) {
    return applications
        .where((app) => AppStatus.confirmedStatuses.contains(app.status))
        .fold(0, (sum, app) {
          if (!app.isLongTermApplication) {
            return sum + _dailyWage(app);
          }
          final workDaysCount = _workDaysInMonth(app, focusedDay);
          final daily = _dailyWage(app);
          return sum + daily * workDaysCount;
        });
  }

  /// 출근기록에서 실근무일수·확정수입을 단일 순회로 계산 (O(n) 1회)
  ///
  /// [actualWorkDays] 실근무일수: checkIn != null인 날짜 수 (같은 날 2잡도 1일)
  /// [confirmedIncome] 확정수입: wageStatus=='confirmed'|'transferred'인 finalWage 합산
  static ({int actualWorkDays, int confirmedIncome}) getAttendanceStats(
    List<AttendanceModel> attendances,
    DateTime focusedDay,
  ) {
    final uniqueDates = <String>{};
    var income = 0;
    for (final att in attendances) {
      if (att.workDate.year != focusedDay.year ||
          att.workDate.month != focusedDay.month) { continue; }
      if (att.checkIn != null) {
        uniqueDates.add('${att.workDate.year}-${att.workDate.month}-${att.workDate.day}');
      }
      if ((att.wageStatus == 'confirmed' || att.wageStatus == 'transferred') &&
          att.finalWage != null) {
        income += att.finalWage!;
      }
    }
    return (actualWorkDays: uniqueDates.length, confirmedIncome: income);
  }

  /// 실근무일수 계산 (출근 기록 있는 날짜 수, 같은 날 2잡도 1일로 카운트)
  ///
  /// · checkIn != null 조건: 출근 미완료(생성만 된 attendance) 제외
  /// · `Set<String>` 중복 제거: 같은 날 A사·B사 동시 근무여도 1일로 집계
  /// · 야간 근무(11/30 23:50 checkIn): workDate=11/30으로 저장 → 11월에 카운트 (논리적으로 올바름)
  /// · _buildAttendanceMap의 key 포맷과 일치: 'year-month-day' (미패딩) — 변경 시 함께 수정
  ///
  /// 대부분의 경우 [getAttendanceStats]를 사용해 두 값을 단일 순회로 계산하는 것을 권장.
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

  /// 확정수입 계산 (wageStatus == 'confirmed' 또는 'transferred'인 attendance의 finalWage 합산)
  ///
  /// wageStatus 전환 순서: pending → calculated → confirmed → transferred
  /// · 'calculated': 관리자가 금액 계산만 한 단계 — 아직 확정 전이므로 제외
  /// · 'confirmed': 관리자가 확정한 금액 — 집계 포함
  /// · 'transferred': 이체 완료 — 집계 포함
  /// · finalWage=null 체크: confirmed인데 finalWage 없는 비정상 데이터 graceful 처리
  ///
  /// 대부분의 경우 [getAttendanceStats]를 사용해 두 값을 단일 순회로 계산하는 것을 권장.
  static int getConfirmedIncome(List<AttendanceModel> attendances, DateTime focusedDay) {
    final confirmedList = attendances.where((att) =>
      att.workDate.year == focusedDay.year &&
      att.workDate.month == focusedDay.month &&
      (att.wageStatus == 'confirmed' || att.wageStatus == 'transferred') &&
      att.finalWage != null
    ).toList();

    return confirmedList.fold(0, (sum, att) => sum + (att.finalWage ?? 0));
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  /// 시급/일급을 일당으로 환산
  ///
  /// · wageType='hourly': app.wage=시급, startTime~endTime으로 총 근무시간 계산
  ///   - endMin <= startMin이면 야간 시프트(22:00~06:00 등) → endMin += 1440(다음날)으로 보정
  ///   - 휴게시간(breakMinutes) 미반영: ApplicationModel에 필드 없으므로 총 시간으로 계산
  /// · wageType='daily'(또는 null): app.wage가 이미 일당 → 그대로 반환
  ///
  /// 호출처: getTotalIncome (단기·장기 모두), _workDaysInMonth 간접 사용
  static int _dailyWage(ApplicationModel app) {
    if (app.wageType == 'hourly') {
      int toMin(String t) {
        final p = t.split(':');
        if (p.length < 2) return 0;
        // app.startTime/endTime은 DB에 "HH:mm"으로만 저장 — parse 예외 없음
        return int.parse(p[0]) * 60 + int.parse(p[1]);
      }
      final startMin = toMin(app.startTime);
      var endMin = toMin(app.endTime);
      if (endMin <= startMin) endMin += 1440; // 야간 시프트 (ex: 22:00~06:00)
      final hours = (endMin - startMin) / 60.0;
      return (app.wage * hours).round();
    }
    return app.wage; // daily
  }

  /// 장기공고의 이번 달 근무 예정 일수
  ///
  /// · endDate = actualResignDate ?? workEndDate
  ///   - actualResignDate 우선: 조기 퇴사 시 남은 기간 미계산
  ///   - workEndDate=null → 0 반환: isWorkingOnDate도 동일하게 false — 의도된 "기간 미정" 처리
  /// · leaveDates: 해당 날짜 카운트 제외
  /// · extraWorkDates: 정규 요일 무관 1일 추가 카운트
  static int _workDaysInMonth(ApplicationModel app, DateTime focusedDay) {
    if (app.workDays == null || app.workDays!.isEmpty) return 0;

    final firstOfMonth = DateTime(focusedDay.year, focusedDay.month, 1);
    final lastOfMonth = DateTime(focusedDay.year, focusedDay.month + 1, 0);

    // effectiveStart: isWorkingOnDate·isScheduledOnDate와 동일한 결정 로직 사용 [B3 수정]
    // workDate가 지원일이고 관리자 확정(confirmedAt)이 workDate 이후면
    // 그 기간 동안 실제 근무는 없었으므로 confirmedAt 당일을 실질 시작일로 본다.
    // desiredStartDate가 있으면 confirmedAt 보정 비활성 — 사용자가 직접 지정한 시작일 우선.
    DateTime startDate = app.desiredStartDate ?? app.workDate;
    if (app.confirmedAt != null && app.desiredStartDate == null) {
      final confirmedDay = DateTime(app.confirmedAt!.year, app.confirmedAt!.month, app.confirmedAt!.day);
      if (confirmedDay.isAfter(startDate)) startDate = confirmedDay;
    }
    final endDate = app.actualResignDate ?? app.workEndDate;
    if (endDate == null) return 0; // workEndDate=null은 전 시스템 일관되게 0/false 처리

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
