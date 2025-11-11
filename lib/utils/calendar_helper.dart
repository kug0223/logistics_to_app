import '../models/core/application_model.dart';

/// 캘린더 관련 헬퍼 함수
class CalendarHelper {
  /// 특정 날짜의 지원 내역 가져오기
  static List<ApplicationModel> getEventsForDay(
    DateTime day,
    List<ApplicationModel> applications,
    String selectedFilter,
  ) {
    return applications.where((app) {
      // 날짜만 비교 (시간 제외)
      final isSameDay = app.workDate.year == day.year &&
                       app.workDate.month == day.month &&
                       app.workDate.day == day.day;
      
      if (!isSameDay) return false;
      
      // 필터 적용
      if (selectedFilter == 'CONFIRMED') {
        return app.status == 'CONFIRMED';
      } else if (selectedFilter == 'PENDING') {
        return app.status == 'PENDING';
      }
      
      // ALL: 취소/거절 제외
      return app.status != 'CANCELED' && 
             app.status != 'REJECTED' &&
             app.status != 'AUTO_CANCELED';
    }).toList();
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
  
  /// 확정 근무 수 계산
  static int getConfirmedCount(List<ApplicationModel> applications) {
    return applications.where((app) => app.status == 'CONFIRMED').length;
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