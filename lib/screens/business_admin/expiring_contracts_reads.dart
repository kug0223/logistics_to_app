// [DU347] 계약 확인 필요(ExpiringContractsScreen) 조회 경계 — 같은 폴더 *_reads.dart(AttendanceReads 등) 패턴.
//   화면이 부르던 세 조회만 묶는다. 판정(needsManagerRenewalAction) · 대기 제안 actionable 필터 · 정렬 · 표시는 화면에 남는다.
//   [ExpiringContractsReads.of] 는 기존 화면 호출과 같다(같은 인자 · 같은 purpose).
import '../../models/core/application_model.dart';
import '../../models/core/renewal_proposal_model.dart';
import '../../models/core/user_model.dart';
import '../../services/firestore_service.dart';

class ExpiringContractsReads {
  final Future<List<ApplicationModel>> Function({
    required String businessId,
    required DateTime fromDate,
  }) expiringApplications;

  final Future<List<RenewalProposalModel>> Function(String businessId)
      pendingRenewalProposals;

  /// [PII-DOC-R0.1 / INV-1] 계약 만료 화면 — 이름만 쓴다. 목적은 이 경계가 workerDirectory 로 고정한다.
  final Future<Map<String, UserModel>> Function(
    List<String> uids, {
    required String businessId,
  }) usersBatch;

  const ExpiringContractsReads({
    required this.expiringApplications,
    required this.pendingRenewalProposals,
    required this.usersBatch,
  });

  factory ExpiringContractsReads.of(FirestoreService svc) => ExpiringContractsReads(
        expiringApplications: ({required businessId, required fromDate}) =>
            svc.getExpiringLongTermApplications(businessId: businessId, fromDate: fromDate),
        pendingRenewalProposals: (businessId) => svc.getPendingRenewalProposals(businessId),
        usersBatch: (uids, {required businessId}) => svc.getUsersBatch(uids,
            businessId: businessId, purpose: FirestoreService.purposeWorkerDirectory),
      );
}
