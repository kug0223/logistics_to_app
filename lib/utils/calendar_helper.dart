import '../models/core/application_model.dart';

/// 캘린더 관련 헬퍼 함수
class CalendarHelper {
  /// 특정 날짜의 지원 내역 가져오기 (장기 근무 확장 포함)
  static List<ApplicationModel> getEventsForDay(
    DateTime day,
    List<ApplicationModel> applications,
    String selectedFilter,
  ) {
    final result = <ApplicationModel>[];
    
    for (var app in applications) {
      // 1. 단기 근무: workDate와 비교
      if (!app.isLongTermApplication) {
        if (_isSameDay(app.workDate, day)) {
          if (_passesFilter(app, selectedFilter)) {
            result.add(app);
          }
        }
      }
      // 2. 장기 근무: 근무 기간 + 요일 체크
      else {
        if (_isWorkingOnDate(app, day)) {
          if (_passesFilter(app, selectedFilter)) {
            result.add(app);
          }
        }
      }
    }
    
    return result;
  }
  
  /// 장기 근무가 특정 날짜에 근무하는지 확인
  static bool _isWorkingOnDate(ApplicationModel app, DateTime targetDate) {
    // 확정되지 않은 장기 근무는 지원일에만 표시
    if (app.status != 'CONFIRMED') {
      return _isSameDay(app.workDate, targetDate);
    }
    
    // 🔥 퇴사/해지 완료된 경우 표시 안함
    if (app.resignStatus == 'APPROVED' || app.resignStatus == 'AUTO_APPROVED' ||
        app.terminationStatus == 'APPROVED' || app.terminationStatus == 'AUTO_APPROVED') {
      return false;
    }
    
    // 확정된 장기 근무: 근무 기간 + 요일 체크
    // 🔥 actualResignDate(실제 퇴사일)가 있으면 그 날짜까지만
    final endDate = app.actualResignDate ?? app.workEndDate;
    if (endDate == null) return false;
    
    // 🔥 시작일 계산: desiredStartDate 우선 → confirmedAt → workDate
    DateTime effectiveStartDate = app.desiredStartDate ?? app.workDate;
    if (app.confirmedAt != null && app.desiredStartDate == null) {
      final confirmedDate = DateTime(
        app.confirmedAt!.year,
        app.confirmedAt!.month,
        app.confirmedAt!.day,
      );
      if (confirmedDate.isAfter(app.workDate)) {
        effectiveStartDate = confirmedDate;
      }
    }
    
    // 날짜 범위 체크 (확정일 기준 시작)
    final isInRange = !targetDate.isBefore(effectiveStartDate) && 
                      !targetDate.isAfter(endDate);
    
    if (!isInRange) return false;
    
    // ⭐ 휴무일 체크 (leaveDates) - 표시는 하되 휴무 상태로
    if (app.leaveDates != null && app.leaveDates!.isNotEmpty) {
      final isLeaveDay = app.leaveDates!.any((leaveDate) =>
          leaveDate.year == targetDate.year &&
          leaveDate.month == targetDate.month &&
          leaveDate.day == targetDate.day);
      
      if (isLeaveDay) return true; // ⭐ 변경: true로 반환 (표시는 함)
    }
    
    // ⭐ 추가 근무일 체크 (extraWorkDates)
    if (app.extraWorkDates != null && app.extraWorkDates!.isNotEmpty) {
      final isExtraWorkDay = app.extraWorkDates!.any((extraDate) =>
          extraDate.year == targetDate.year &&
          extraDate.month == targetDate.month &&
          extraDate.day == targetDate.day);
      
      if (isExtraWorkDay) return true;
    }
    
    // 근무 요일 체크
    if (app.workDays == null || app.workDays!.isEmpty) {
      return true; // 모든 날 근무
    }
    
    final targetDayKorean = _getKoreanDayOfWeek(targetDate);
    return app.workDays!.contains(targetDayKorean);
  }
  
  /// 두 날짜가 같은지 비교 (시간 제외)
  static bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }
  
  /// 요일을 한글로 변환
  static String _getKoreanDayOfWeek(DateTime date) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[date.weekday - 1];
  }
  
  /// 필터 통과 여부
  static bool _passesFilter(ApplicationModel app, String selectedFilter) {
    // 🔥 퇴사/해지 완료된 장기 근무는 모든 필터에서 제외
    if (app.isLongTermApplication) {
      if (app.resignStatus == 'APPROVED' || app.resignStatus == 'AUTO_APPROVED' ||
          app.terminationStatus == 'APPROVED' || app.terminationStatus == 'AUTO_APPROVED') {
        return false;
      }
    }
    
    if (selectedFilter == 'CONFIRMED') {
      return app.status == 'CONFIRMED';
    } else if (selectedFilter == 'PENDING') {
      return app.status == 'PENDING';
    }
    
    // ALL: 취소/거절 제외
    return app.status != 'CANCELED' && 
           app.status != 'REJECTED' &&
           app.status != 'AUTO_CANCELED';
  }
  
  /// 이번 달 데이터 필터링
  static List<ApplicationModel> getThisMonthApplications(
    List<ApplicationModel> applications,
    DateTime focusedDay,
  ) {
    return applications.where((app) {
      return app.workDate.year == focusedDay.year &&
             app.workDate.month == focusedDay.month;
    }).toList();
  }
  
  /// 확정 근무 수 계산 (단기만 카운트, 장기 제외)
  static int getConfirmedCount(List<ApplicationModel> applications) {
    return applications.where((app) => 
      app.status == 'CONFIRMED' && 
      !app.isLongTermApplication  // ⭐ 장기 근무 제외
    ).length;
  }
  
  /// 대기 중 수 계산
  static int getPendingCount(List<ApplicationModel> applications) {
    return applications.where((app) => app.status == 'PENDING').length;
  }
  
  /// 총 예상 수입 계산
  static int getTotalIncome(List<ApplicationModel> applications) {
    return applications
        .where((app) => app.status == 'CONFIRMED')
        .fold(0, (sum, app) => sum + app.wage);
  }
}