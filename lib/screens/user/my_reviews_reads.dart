import '../../models/core/monthly_review_model.dart';
import '../../services/monthly_review_service.dart';

/// [R7-P2-4 P24-R] 내 근무 평가 화면이 **목록을 만들 때** 나가는 읽기 경계.
///
/// 이 화면은 **내가 받은 평가**를 읽는다(`targetUserId = 내 uid`).
/// 리뷰 **작성**은 여기가 아니라 내 지원 화면의 작성 창(`showBusinessReviewDialog`)
/// 이 담당한다 — 이 경계에 쓰기를 넣지 않는다.
///
/// production 은 `reads: null` 이라 기존 서비스를 쓴다.
class MyReviewsReads {
  const MyReviewsReads({required this.reviewsForUserPaged});

  final Future<ReviewPage<MonthlyReviewModel>> Function({
    required String targetUserId,
    String? startAfterId,
    int pageSize,
  }) reviewsForUserPaged;

  factory MyReviewsReads.of([MonthlyReviewService? service]) {
    final svc = service ?? MonthlyReviewService();
    return MyReviewsReads(
      reviewsForUserPaged: (
              {required String targetUserId,
              String? startAfterId,
              int pageSize = 30}) =>
          svc.getAllReviewsForUserPaged(
              targetUserId: targetUserId,
              startAfterId: startAfterId,
              pageSize: pageSize),
    );
  }
}
