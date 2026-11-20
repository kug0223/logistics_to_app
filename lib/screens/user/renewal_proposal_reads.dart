import '../../models/core/renewal_proposal_model.dart';

/// [DU262] 계약 연장 제안 화면이 **제안 목록을 읽을 때** 나가는 경계.
///
/// 시험에서 제안 카드(조건·수락·거절)를 실제로 그려 보려면 목록을 줄 수 있어야 한다.
/// production 은 `reads: null` — 화면이 지금처럼 FirestoreService 로 읽는다.
/// 수락·거절(쓰기)은 이 경계에 넣지 않는다 — 읽기만 갈아끼운다(InterimSettlementReads 와 같은 원칙).
class RenewalProposalReads {
  const RenewalProposalReads({required this.myRenewalProposals});

  final Future<List<RenewalProposalModel>> Function() myRenewalProposals;
}
