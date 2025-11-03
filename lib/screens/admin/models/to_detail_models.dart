import '../../../models/to_model.dart';
import '../../../models/work_detail_model.dart';

/// 날짜별 TO 아이템
class DateTOItem {
  final TOModel to;
  final List<WorkDetailWithApplicants> workDetails;
  
  DateTOItem({
    required this.to,
    required this.workDetails,
  });
}

/// 업무별 지원자 정보
class WorkDetailWithApplicants {
  final WorkDetailModel workDetail;
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