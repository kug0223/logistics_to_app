import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/confirmed_reassignment_proposal.dart';
import '../../../models/core/to_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/work_detail_data.dart';
import '../../../services/confirmed_reassignment_service.dart';
import '../../../services/contract_service.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/id_card_helper.dart';

/// [E2-INVITED-SEAT] 업무별 지원자 창이 **읽는** 것 — 한 곳에 모은 주입 지점.
///
///   이 창은 서비스를 직접 불러 화면 전체를 테스트에서 실행할 방법이 없었다.
///   그래서 초대 행·분리 함수만 따로 그려 보고 "창 전체 검증"이라 부를 수 없었다.
///   [DayApplicantsReads] 와 같은 모양으로 **읽기만** 모았다. 쓰기(승인·거절·
///   계약·초대)는 여기 없다 — 테스트가 쓰기를 대신하지 않게 한다.
///
///   운영은 [WorkApplicantsReads.production] 하나다. 호출 순서·인자는 예전
///   인라인 호출과 같다(동작 변경 없음).
class WorkApplicantsReads {
  const WorkApplicantsReads({
    required this.applications,
    required this.usersBatch,
    required this.weeklyAttendance,
    required this.contractStatusBatch,
    required this.hasWorkedMap,
    required this.idCardStatusBatch,
    required this.capacity,
    required this.reassignProposals,
    this.contractAttendances,
  });

  /// [NOSHOW-CONTRACT-GUARD] KST 영업일 [first, last] 의 근태 — 노쇼·결근 근무일에
  ///   계약서를 권하지 않기 위해. null(주지 않음)이거나 실패·상한 도달이면 화면은
  ///   근태를 **모르는** 것으로 보고 단기 근무의 `계약서 작성` 을 내지 않는다.
  final Future<List<AttendanceModel>> Function({
    required String businessId,
    required DateTime first,
    required DateTime last,
  })? contractAttendances;

  /// 이 창의 지원서 — 슬롯이 있으면 슬롯 범위, 없으면 공고 전체.
  final Future<List<ApplicationModel>> Function(
    TOModel to, {
    String? slotId,
    required String purpose,
  }) applications;

  final Future<Map<String, UserModel>> Function(
    List<String> uids, {
    required String businessId,
    String? purpose,
  }) usersBatch;

  final Future<Map<String, List<AttendanceModel>>> Function({
    required String businessId,
    required DateTime weekStart,
    required DateTime weekEnd,
  }) weeklyAttendance;

  final Future<ContractStatusBatch> Function(
    List<String> applicationIds, {
    required String businessId,
  }) contractStatusBatch;

  final Future<Map<String, bool>> Function({
    required String businessId,
    required DateTime date,
  }) hasWorkedMap;

  final Future<Map<String, String>> Function({
    required String requesterId,
    required List<String> targetUserIds,
  }) idCardStatusBatch;

  /// 정원 — 카드와 같은 `loadTOWorkDetails`.
  final Future<Map<String, dynamic>> Function(
    TOModel to, {
    String? slotId,
    List<WorkDetailData>? slotWorkDetails,
  }) capacity;

  final Future<List<ConfirmedReassignmentProposal>> Function(String businessId)
      reassignProposals;

  /// 테스트 전용 — null 이면 운영 구현을 쓴다(ApplicantDocumentReviewService.debugOverride 와 같은 관례).
  static WorkApplicantsReads? debugOverride;

  factory WorkApplicantsReads.production(FirestoreService svc) =>
      WorkApplicantsReads(
        applications: (to, {slotId, required purpose}) => slotId != null
            ? svc.getApplicationsBySlotId(to.id, slotId,
                businessId: to.businessId, purpose: purpose)
            : svc.getApplicationsByTOId(to.id,
                businessId: to.businessId, purpose: purpose),
        usersBatch: (uids, {required businessId, purpose}) =>
            svc.getUsersBatch(uids, businessId: businessId, purpose: purpose),
        weeklyAttendance: ({required businessId, required weekStart,
                required weekEnd}) =>
            svc.getWeeklyAttendanceByBusiness(
                businessId: businessId, weekStart: weekStart, weekEnd: weekEnd),
        contractStatusBatch: (ids, {required businessId}) =>
            ContractService().getContractStatusBatch(ids, businessId: businessId),
        hasWorkedMap: ({required businessId, required date}) =>
            svc.loadHasWorkedMap(businessId: businessId, date: date),
        idCardStatusBatch: ({required requesterId, required targetUserIds}) =>
            IdCardHelper.loadStatusBatch(
                firestoreService: svc,
                requesterId: requesterId,
                targetUserIds: targetUserIds),
        capacity: (to, {slotId, slotWorkDetails}) => svc.loadTOWorkDetails(to,
            slotId: slotId, slotWorkDetails: slotWorkDetails),
        reassignProposals: (bizId) =>
            ConfirmedReassignmentService.instance.proposalsByBusiness(bizId),
        contractAttendances: ({required businessId, required first,
                required last}) =>
            svc.getAttendanceForKstDays(
                businessId: businessId, first: first, last: last),
      );
}
