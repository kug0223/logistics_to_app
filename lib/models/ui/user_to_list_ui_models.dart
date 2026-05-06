import '../core/to_model.dart';
import '../core/slot_model.dart';
import '../core/work_detail_data.dart';
import '../core/application_model.dart';

/// TO와 업무 상세를 함께 담는 모델 (사용자 공고 목록용)
class TOWithDetails {
  final TOModel to;
  final List<WorkDetailData> workDetails;
  final List<SlotModel> slots;
  final bool isLoading;

  TOWithDetails({
    required this.to,
    required this.workDetails,
    this.slots = const [],
    this.isLoading = false,
  });

  TOWithDetails copyWith({
    TOModel? to,
    List<WorkDetailData>? workDetails,
    List<SlotModel>? slots,
    bool? isLoading,
  }) {
    return TOWithDetails(
      to: to ?? this.to,
      workDetails: workDetails ?? this.workDetails,
      slots: slots ?? this.slots,
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

  static ApplicationStatus notApplied() =>
      ApplicationStatus(hasApplied: false);

  static ApplicationStatus applied(String workType, ApplicationModel app) {
    return ApplicationStatus(
      hasApplied: true,
      appliedWorkType: workType,
      application: app,
    );
  }
}
