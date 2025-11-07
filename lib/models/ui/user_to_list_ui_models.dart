import '../../../models/to_model.dart';
import '../../../models/work_detail_model.dart';
import '../../../models/application_model.dart';

/// TO와 업무 상세를 함께 담는 모델
class TOWithDetails {
  final TOModel to;
  final List<WorkDetailModel> workDetails;
  final bool isLoading;

  TOWithDetails({
    required this.to,
    required this.workDetails,
    this.isLoading = false,
  });

  TOWithDetails copyWith({
    TOModel? to,
    List<WorkDetailModel>? workDetails,
    bool? isLoading,
  }) {
    return TOWithDetails(
      to: to ?? this.to,
      workDetails: workDetails ?? this.workDetails,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 지원 상태 정보
class ApplicationStatus {
  final bool hasApplied;
  final String? appliedWorkType;
  final ApplicationModel? application;

  ApplicationStatus({
    required this.hasApplied,
    this.appliedWorkType,
    this.application,
  });

  static ApplicationStatus notApplied() {
    return ApplicationStatus(hasApplied: false);
  }

  static ApplicationStatus applied(String workType, ApplicationModel app) {
    return ApplicationStatus(
      hasApplied: true,
      appliedWorkType: workType,
      application: app,
    );
  }
}