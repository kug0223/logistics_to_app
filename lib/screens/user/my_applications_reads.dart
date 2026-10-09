import '../../models/core/employment_contract_model.dart';
import '../../models/core/to_model.dart';
import '../../services/contract_service.dart';
import '../../services/firestore_service.dart';
import '../../services/tax_identity_service.dart';

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
    required this.taxStatus,
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

  /// [R7-PREDEVICE-DISCLOSURE-RENDER.1] 초대 수락이 지나는 세무 축.
  ///
  ///   `_acceptInvite` 는 확인창을 띄우기 전에 이 값을 읽어 지원 문턱을
  ///   판정한다(수락도 직접 지원과 같은 문턱이다). 호출이 **매달리면**
  ///   확인창이 영원히 열리지 않고, 그 안에 있는 근태·급여 기준 고지도
  ///   그려지지 않는다 — 실제로 테스트 격리 환경에서 그랬다.
  ///
  ///   판정 자체는 바꾸지 않는다. 읽기만 경계로 옮겨, 그 화면을 실제로
  ///   그려 확인할 수 있게 한다. production 은 `reads: null` 이므로
  ///   기존 `TaxIdentityService.loadStatus` 를 그대로 쓴다.
  final Future<TaxIdentityStatus> Function() taxStatus;

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
      taxStatus: TaxIdentityService.loadStatus,
    );
  }
}
