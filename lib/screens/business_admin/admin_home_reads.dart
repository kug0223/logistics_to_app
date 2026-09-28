import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/contract_template_model.dart';
import '../../models/ui/admin_home_summary_model.dart';
import '../../models/ui/staffing_readiness_model.dart';
import '../../services/admin_home_summary_service.dart';
import '../../services/business_posting_readiness.dart';
import '../../services/contract_template_service.dart';
import '../../services/firestore_service.dart';
import '../../services/staffing_readiness_service.dart';
import '../../services/work_detail_time_service.dart';
import '../../utils/tour_helper.dart';

/// [R7-P1-4 H4] 관리자 홈의 **원시 외부 읽기 경계**.
///
/// P1-3 의 `AttendanceReads` · 8차의 `DayApplicantsReads` 와 같은 형태다 —
/// 홈이 실제로 나가서 읽는 7개 호출만 함수로 들고 있고, **파싱 이전에서 끊는다.**
/// 병합·파생·수치·문구·권한 판정·탭 분류는 전부 화면에 남는다. 그래야 테스트가
/// 화면의 계약을 검증하고, 테스트용 복제본을 검증하지 않는다.
///
/// 기본값은 production owner 그대로다(`AdminHomeReads.of()`), 테스트만 대체한다.
class AdminHomeReads {
  const AdminHomeReads({
    required this.summary,
    required this.businessesByIds,
    required this.staffingReadiness,
    required this.attendanceByDate,
    required this.confirmedWorkers,
    required this.workDetailTimes,
    required this.postingReadiness,
    required this.contractTemplates,
    required this.tourCompleted,
  });

  /// CF `callableGetAdminHomeSummary` — 처리할 일 canonical.
  final Future<AdminHomeSummaryModel> Function({String? selectedBusinessId})
      summary;

  /// 관리 사업장 조회. 실패는 throw 로 올라온다(빈 목록으로 삼키지 않는다).
  final Future<List<BusinessModel>> Function(List<String> ids) businessesByIds;

  /// CF `callableGetStaffingReadiness` — 오늘/D+1~D+7 인력.
  final Future<StaffingReadinessModel> Function({String? selectedBusinessId})
      staffingReadiness;

  final Future<List<AttendanceModel>> Function({
    required String businessId,
    required DateTime date,
  }) attendanceByDate;

  final Future<List<ApplicationModel>> Function({
    required DateTime date,
    required String businessId,
  }) confirmedWorkers;

  final Future<Map<String, dynamic>> Function(List<ApplicationModel> workers)
      workDetailTimes;

  final Future<Map<String, BusinessPostingReadiness>> Function(
      List<BusinessModel> businesses) postingReadiness;

  final Future<List<ContractTemplateModel>> Function(String businessId)
      contractTemplates;

  /// 관리자 홈 투어를 이미 봤는지(로컬 저장소 한 줄).
  /// **데이터의 전제가 아니다** — 이 future 가 늦거나 던져도 수치 조회는 진행된다.
  final Future<bool> Function() tourCompleted;

  factory AdminHomeReads.of(
    FirestoreService svc, {
    AdminHomeSummaryService? summaryService,
    ContractTemplateService? templateService,
  }) {
    final summarySvc = summaryService ?? AdminHomeSummaryService();
    final templateSvc = templateService ?? ContractTemplateService();
    return AdminHomeReads(
      summary: ({String? selectedBusinessId}) =>
          summarySvc.fetchSummary(selectedBusinessId: selectedBusinessId),
      businessesByIds: svc.getBusinessesByIdsOrThrow,
      staffingReadiness: ({String? selectedBusinessId}) =>
          StaffingReadinessService.fetchReadiness(
              selectedBusinessId: selectedBusinessId),
      attendanceByDate: ({required String businessId, required DateTime date}) =>
          svc.getAttendanceByDate(businessId: businessId, date: date),
      confirmedWorkers: ({required DateTime date, required String businessId}) =>
          svc.getConfirmedWorkersByDateAndBusinessOrThrow(
              date: date, businessId: businessId),
      workDetailTimes: WorkDetailTimeService.load,
      postingReadiness: (businesses) =>
          BusinessPostingReadiness.forBusinesses(businesses, svc),
      contractTemplates: templateSvc.getTemplates,
      tourCompleted: () => TourHelper.isCompleted(TourHelper.adminHome),
    );
  }
}
