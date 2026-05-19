import 'package:flutter/foundation.dart';
import '../models/core/application_model.dart';
import '../models/core/attendance_model.dart';

/// 캘린더 관련 헬퍼 함수
class CalendarHelper {
  /// 특정 날짜의 지원 내역 가져오기 (장기 근무 확장 포함)
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
  // ↓ 추가할 코드 (getTotalIncome 메서드 뒤에)
  
  /// 실근무일수 계산 (출근 기록 있는 날짜 수, 날짜 기준 - 2잡도 1일로 카운트)
  static int getActualWorkDays(List<AttendanceModel> attendances, DateTime focusedDay) {
    // 이번 달 출근 기록만 필터링
    final thisMonthAttendances = attendances.where((att) =>
      att.workDate.year == focusedDay.year &&
      att.workDate.month == focusedDay.month &&
      att.checkIn != null  // 출근 기록 있는 것만
    ).toList();
    
    // 날짜 기준으로 중복 제거 (같은 날 2잡도 1일로 카운트)
    final uniqueDates = <String>{};
    for (var att in thisMonthAttendances) {
      final dateKey = '${att.workDate.year}-${att.workDate.month}-${att.workDate.day}';
      uniqueDates.add(dateKey);
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
}
