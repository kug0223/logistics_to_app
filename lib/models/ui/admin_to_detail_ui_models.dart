import '../core/to_model.dart';
import '../core/slot_model.dart';
import '../core/work_detail_data.dart';

/// TO 상세 아이템 (슬롯 단위)
class DateTOItem {
  final TOModel to;
  final SlotModel? slot;
  final List<WorkDetailWithApplicants> workDetails;

  DateTOItem({
    required this.to,
    this.slot,
    required this.workDetails,
  });

  DateTime? get date => slot?.date;
}

/// 업무별 지원자 정보
class WorkDetailWithApplicants {
  final WorkDetailData workDetail;
  final List<Map<String, dynamic>> pendingApplicants;
  final List<Map<String, dynamic>> confirmedApplicants;
  final List<Map<String, dynamic>> rejectedApplicants;

  WorkDetailWithApplicants({
    required this.workDetail,
    required this.pendingApplicants,
    required this.confirmedApplicants,
    required this.rejectedApplicants,
  });

  int get totalApplicants =>
      pendingApplicants.length +
      confirmedApplicants.length +
      rejectedApplicants.length;
}
