part of '../firestore_service.dart';

  // ═══════════════════════════════════════════════════════════
  // 리뷰 관리 (Notification & Review Management)
  // ═══════════════════════════════════════════════════════════

  extension ReviewFirestore on FirestoreService {

  // [BUG-REV-01] createReview, getUserReviews, getReviewByApplicationId 삭제
  // 레거시 'reviews' 컬렉션을 사용하는 함수들 — 현재 리뷰 시스템은 'monthly_reviews' 컬렉션 사용.
  // getBusinessWorkHistory의 reviews 쿼리도 monthly_reviews로 전환 완료.
}
