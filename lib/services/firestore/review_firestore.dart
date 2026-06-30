part of '../firestore_service.dart';

  // ═══════════════════════════════════════════════════════════
  // 리뷰 관리 (Notification & Review Management)
  // ═══════════════════════════════════════════════════════════

  extension ReviewFirestore on FirestoreService {  
  
  // ═══════════════════════════════════════════════════════════════════════════
  // 📝 FirestoreService 추가 메서드 (리뷰, 신분증 열람, 알림)
  // 이 내용을 lib/services/firestore_service.dart에 추가하세요
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════
  // 리뷰 관리 (Review Management)
  // ═══════════════════════════════════════════════════════════

  // [BUG-REV-01 삭제] createReview는 레거시 'reviews' 컬렉션에 저장하는 사용되지 않는 함수였음.
  // 현재 리뷰 시스템은 monthly_review_service.dart의 createReviewForUser/createReviewForBusiness를 사용.
  // CF onReviewCreated 트리거도 'monthly_reviews' 컬렉션만 감지하므로 'reviews'에 저장하면 공개 불가.

  /// 사용자가 받은 리뷰 목록 조회
  Future<List<ReviewModel>> getUserReviews(String userId, {int limit = 10}) async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .where('targetUserId', isEqualTo: userId)
          .where('isPublished', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      
      return snapshot.docs
          .map((doc) => ReviewModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ 사용자 리뷰 조회 실패: $e');
      return [];
    }
  }

  /// 특정 지원서의 리뷰 조회
  Future<ReviewModel?> getReviewByApplicationId(String applicationId) async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .where('applicationId', isEqualTo: applicationId)
          .limit(1)
          .get();
      
      if (snapshot.docs.isEmpty) return null;
      return ReviewModel.fromFirestore(snapshot.docs.first);
    } catch (e) {
      debugPrint('❌ 리뷰 조회 실패: $e');
      return null;
    }
  }
}