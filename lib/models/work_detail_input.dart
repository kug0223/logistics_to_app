import 'core/insurance_rate_model.dart';

/// 업무 상세 입력 데이터 클래스
class WorkDetailInput {
  final String? workType;
  final String workTypeIcon;
  final String workTypeColor;
  final String? workTypeBackgroundColor;
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

  /// 급여 지급 유형: 'same_day' | 'next_day' | 'weekly' | 'monthly'
  final String? payScheduleType;
  /// 지급 기준일: 주급=1~7(월~일), 월급=1~31(31=말일), 당일/익일=null
  final int? payScheduleDay;
  /// 입금 예정 시간 'HH:mm' (선택)
  final String? payScheduleTime;

  /// 공제 방식: InsuranceRateModel.typeNone | typeFreelancer33 | typeDailyWorker | typeDailyAuto8 | typeFourInsuranceFixed
  final String taxDeductionType;

  /// 업무 설명 (선택 사항)
  final String? description;

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
    this.payScheduleType,
    this.payScheduleDay,
    this.payScheduleTime,
    this.taxDeductionType = InsuranceRateModel.typeNone,
    this.description,
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
      'workTypeBackgroundColor': workTypeBackgroundColor,
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
      if (payScheduleType != null) 'payScheduleType': payScheduleType,
      if (payScheduleDay != null) 'payScheduleDay': payScheduleDay,
      if (payScheduleTime != null) 'payScheduleTime': payScheduleTime,
      if (taxDeductionType != InsuranceRateModel.typeNone) 'taxDeductionType': taxDeductionType,
      if (description != null) 'description': description,
    };
  }
}