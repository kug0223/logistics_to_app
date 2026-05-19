/// 주 단위 계산 유틸리티 (월요일 시작 ~ 일요일 종료)
class WeekHelper {
  /// 해당 날짜가 속한 주의 월요일 (0시 기준)
  static DateTime weekStart(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  /// 해당 날짜가 속한 주의 일요일 (0시 기준)
  static DateTime weekEnd(DateTime date) =>
      weekStart(date).add(const Duration(days: 6));
}

/// 주휴수당 자격 판정 결과
class WeeklyHolidayEligibility {
  final bool isEligible;
  final int workedDays;
  final int scheduledDaysPerWeek;
  final int totalWorkMinutes;
  final int weeklyHolidayAmount;
  final DateTime weekStart;
  final DateTime weekEnd;

  const WeeklyHolidayEligibility({
    required this.isEligible,
    required this.workedDays,
    required this.scheduledDaysPerWeek,
    required this.totalWorkMinutes,
    required this.weeklyHolidayAmount,
    required this.weekStart,
    required this.weekEnd,
  });

  bool get meetsHours => totalWorkMinutes >= 15 * 60;
  bool get meetsDays => workedDays >= scheduledDaysPerWeek;

  double get totalWorkHours => totalWorkMinutes / 60.0;
}
