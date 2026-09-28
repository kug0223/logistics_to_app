import '../../models/core/application_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../services/contract_service.dart';
import '../../services/firestore_service.dart';

/// [R7-P1-6 P16-C] 계약 관리 화면의 **원시 외부 읽기 경계**.
///
/// P1-3 `AttendanceReads` · P1-4 `AdminHomeReads` · P1-5 `PayrollOverviewReads` 와
/// 같은 형태다 — 화면이 나가서 읽는 두 호출만 함수로 들고 있고 **파싱 이전에서
/// 끊는다.** 탭 분류·검색·정렬·빈/실패 문구·행동 게이트는 화면에 남는다.
class AdminContractReads {
  const AdminContractReads({
    required this.contractsPaged,
    required this.unsentApplications,
  });

  /// 사업장 계약서 목록(상태 필터 + 커서). 실패는 **throw** 한다.
  final Future<({List<EmploymentContractModel> items, String? lastDocId, bool hasMore})>
      Function(
    String businessId, {
    ContractStatus? statusFilter,
    String? startAfterId,
  }) contractsPaged;

  /// 계약서를 아직 받지 못한 확정 지원서. 실패는 **throw** 한다 —
  /// 호출부가 '없음'이 아니라 '모름'으로 다룬다(빈 목록 = 모두 발송했다는 주장이다).
  final Future<List<ApplicationModel>> Function(String businessId)
      unsentApplications;

  factory AdminContractReads.of({
    ContractService? contractService,
    FirestoreService? firestoreService,
  }) {
    final contracts = contractService ?? ContractService();
    final svc = firestoreService ?? FirestoreService();
    return AdminContractReads(
      contractsPaged: (
        businessId, {
        ContractStatus? statusFilter,
        String? startAfterId,
      }) =>
          contracts.getByBusinessPaged(
            businessId,
            statusFilter: statusFilter,
            startAfterId: startAfterId,
          ),
      unsentApplications: svc.getUnsentApplicationsByBusiness,
    );
  }
}
