/// [R7-P2 잔여 I45] 내 요청 인박스가 **열릴 때** 나가는 네 읽기.
///
/// `MyRequestsDialog` 는 시작하자마자 이 넷을 `Future.wait` 한다. 넷 모두
/// `FirestoreService` 하드 싱글턴(+ extension 정적 디스패치)과 CF 뒤에 있어
/// 하위 클래스 fake 로는 대신할 수 없다 — A1 에서 확인한 그 구조다.
///
/// **읽기뿐이다.** 승인·거절·동의·해지·취소 같은 mutation 은 넣지 않는다 —
/// 그 호출들은 화면에 그대로 남는다.
///
/// production 은 `reads: null` 이라 아래 기본값이 **지금 쓰는 같은 메서드를
/// 같은 uid 로** 부른다. 실패 의미(네 개 중 하나가 throw 하면 `Future.wait` 가
/// 전체를 던지고 화면이 오류 상태로 간다)도 바꾸지 않는다.
library;

import '../../../models/core/application_model.dart';
import '../../../models/core/id_card_access_request_model.dart';
import '../../../models/core/interim_settlement_request_model.dart';
import '../../../models/core/schedule_change_request_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/payroll_payment_service.dart';

class MyRequestsReads {
  const MyRequestsReads({
    required this.scheduleChangeRequests,
    required this.pendingIdCardRequests,
    required this.terminationRequests,
    required this.interimSettlements,
  });

  /// key = 지원자 uid
  final Future<List<ScheduleChangeRequestModel>> Function(String applicantUid)
      scheduleChangeRequests;

  /// key = 대상 uid. 사업장·요청 id 는 각 요청 문서가 들고 있다.
  final Future<List<IdCardAccessRequestModel>> Function(String userId)
      pendingIdCardRequests;

  /// 해지 요청은 **Application** 으로 온다 — 요청 key 는 applicationId 다.
  final Future<List<ApplicationModel>> Function(String uid) terminationRequests;

  /// 계정 스코프 CF — 인자 없음.
  final Future<List<InterimSettlementRequestModel>> Function()
      interimSettlements;

  factory MyRequestsReads.of([
    FirestoreService? service,
    PayrollPaymentService? payService,
  ]) {
    final svc = service ?? FirestoreService();
    final pay = payService ?? PayrollPaymentService();
    return MyRequestsReads(
      scheduleChangeRequests: svc.getMyScheduleChangeRequests,
      pendingIdCardRequests: svc.getPendingIdCardRequestsForUser,
      terminationRequests: svc.getMyTerminationRequests,
      interimSettlements: () => pay.getMyInterimSettlements(),
    );
  }
}
