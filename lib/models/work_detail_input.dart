/// 업무 상세 입력 데이터 클래스
class WorkDetailInput {
  final String? workType;
  final String workTypeIcon;
  final String workTypeColor;
  final String? workTypeBackgroundColor; // ✅ 추가
  final int? wage;
  final int? requiredCount;
  final String? startTime;
  final String? endTime;
  final String wageType;
  final String? shiftType;
  final bool nightAllowanceApplied;
  final bool nightIncluded;
  final int breakMinutes;
  /// 일급제 수당 기초 시급 — 연장·야간·휴일수당 계산 기준
  /// null이면 최저시급 적용
  final int? baseHourlyWage;

  /// 주휴수당 포함 여부
  final bool weeklyHolidayIncluded;

  /// 소정근로일 수 (주휴미포함 시, 1~7)
  final int? scheduledDaysPerWeek;

  WorkDetailInput({
    this.workType,
    this.workTypeIcon = 'work',
    this.workTypeColor = '#2196F3',
    this.workTypeBackgroundColor,
    this.wage,
    this.requiredCount,
    this.startTime,
    this.endTime,
    this.wageType = 'hourly',
    this.shiftType,
    this.nightAllowanceApplied = true,
    this.nightIncluded = false,
    this.breakMinutes = 0,
    this.baseHourlyWage,
    this.weeklyHolidayIncluded = false,
    this.scheduledDaysPerWeek,
  });

  bool get isValid =>
      workType != null &&
      wage != null &&
      requiredCount != null &&
      startTime != null &&
      endTime != null;

  Map<String, dynamic> toMap() {
    return {
      'workType': workType!,
      'workTypeIcon': workTypeIcon,
      'workTypeColor': workTypeColor,
      'workTypeBackgroundColor': workTypeBackgroundColor, // ✅ 추가
      'wage': wage!,
      'wageType': wageType,
      'requiredCount': requiredCount!,
      'startTime': startTime!,
      'endTime': endTime!,
      if (shiftType != null) 'shiftType': shiftType,
      if (!nightAllowanceApplied) 'nightAllowanceApplied': false,
      if (nightIncluded) 'nightIncluded': true,
      if (breakMinutes > 0) 'breakMinutes': breakMinutes,
      if (baseHourlyWage != null) 'baseHourlyWage': baseHourlyWage,
      if (weeklyHolidayIncluded) 'weeklyHolidayIncluded': true,
      if (scheduledDaysPerWeek != null) 'scheduledDaysPerWeek': scheduledDaysPerWeek,
    };
  }
}