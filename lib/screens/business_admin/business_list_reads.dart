/// [R7-PREDEVICE-STABILIZATION.1A] 사업장 목록 화면이 나가는 **읽기 경계**.
///
/// ── 왜 필요한가 ───────────────────────────────────────────────────
///   이 화면은 "조회 실패"와 "사업장 0개"를 구분해야 한다. 구분이 없으면
///   읽기 한 번이 실패한 것이 "등록된 사업장이 없습니다" 라는 전혀 다른
///   사실로 번지고, SubAdmin 에게는 거기에 등록 CTA 까지 붙는다.
///
///   그래서 **던지는** 변형(`*OrThrow`)만 노출한다. 삼키는 변형을 쓰면
///   화면의 catch 가 돌지 않아 실패가 조용히 0개가 된다.
///
///   경계를 잘라 둔 두 번째 이유는 그 구분을 **테스트로 증명**하기
///   위해서다. 실기기 없이 Firestore 를 실패시킬 방법이 없고, 테스트
///   환경에서는 호출이 던지지 않고 그대로 매달린다 — 그러면 실패 화면에
///   영원히 도달하지 못한다.
///
///   쓰기(삭제)는 이 경계에 넣지 않는다. production 은 `reads: null` 이라
///   기존 서비스 호출을 그대로 쓴다.
library;

import '../../models/core/business_model.dart';
import '../../services/firestore_service.dart';

class BusinessListReads {
  const BusinessListReads({
    required this.businessById,
    required this.businessesByIds,
  });

  /// SubAdmin 경로 — 배정된 사업장 하나.
  /// `null` 은 **부재**(문서 없음)다. 실패는 throw 로 올라온다.
  final Future<BusinessModel?> Function(String businessId) businessById;

  /// 오너 경로 — 관리 중인 사업장들. 빈 목록은 **정말 0개**다.
  final Future<List<BusinessModel>> Function(List<String> ids) businessesByIds;

  factory BusinessListReads.of() {
    final svc = FirestoreService();
    return BusinessListReads(
      businessById: svc.getBusinessByIdOrThrow,
      businessesByIds: svc.getBusinessesByIdsOrThrow,
    );
  }
}
