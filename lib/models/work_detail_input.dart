/// 업무 상세 입력 데이터 클래스
class WorkDetailInput {
  final String? workType;
  final String workTypeIcon;
  final String workTypeColor;
  final int? wage;
  final int? requiredCount;
  final String? startTime;
  final String? endTime;
  final String wageType;

  WorkDetailInput({
    this.workType,
    this.workTypeIcon = 'work',
    this.workTypeColor = '#2196F3',
    this.wage,
    this.requiredCount,
    this.startTime,
    this.endTime,
    this.wageType = 'hourly',
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
      'wage': wage!,
      'requiredCount': requiredCount!,
      'startTime': startTime!,
      'endTime': endTime!,
    };
  }
}