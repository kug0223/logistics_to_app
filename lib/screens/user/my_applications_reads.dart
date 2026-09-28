import '../../models/core/employment_contract_model.dart';
import '../../models/core/to_model.dart';
import '../../services/contract_service.dart';
import '../../services/firestore_service.dart';

/// [R7-P2-2 후속 P22-M] 내 지원 목록이 **화면을 만들 때** 나가는 읽기 경계.
///
/// 상태·사유 문구·CTA·필터는 전부 화면에 남는다 — 여기 있는 것은 나가서
/// 읽는 호출뿐이다. production 은 `reads: null` 이라 기존 서비스 인스턴스를 쓴다.
///
/// 취소·지원(쓰기)은 이 경계에 넣지 않는다.
class MyApplicationsReads {
  const MyApplicationsReads({
    required this.myApplicationsPaged,
    required this.toOrFailure,
    required this.contractsByWorker,
    required this.autoExpirePending,
  });

  /// `{items, lastDocId, hasMore}` 모양 그대로.
  final Future<Map<String, dynamic>> Function({
    required String uid,
    required int pageSize,
    String? startAfterDocId,
  }) myApplicationsPaged;

  final Future<({TOModel? to, bool failed})> Function(String toId) toOrFailure;

  final Future<List<EmploymentContractModel>> Function(String uid)
      contractsByWorker;

  /// 만료 처리는 목록 표시의 근거가 아니다 — 실패해도 목록은 그린다.
  final Future<void> Function(String uid) autoExpirePending;

  factory MyApplicationsReads.of([
    FirestoreService? service,
    ContractService? contractService,
  ]) {
    final svc = service ?? FirestoreService();
    final cs = contractService ?? ContractService();
    return MyApplicationsReads(
      myApplicationsPaged: (
              {required String uid,
              required int pageSize,
              String? startAfterDocId}) =>
          svc.getMyApplicationsPaged(
              uid: uid, pageSize: pageSize, startAfterDocId: startAfterDocId),
      toOrFailure: svc.getTOOrFailure,
      contractsByWorker: cs.getByWorker,
      autoExpirePending: (uid) => svc.autoExpirePendingApplications(uid),
    );
  }
}
