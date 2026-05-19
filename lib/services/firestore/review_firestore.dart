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

  /// 리뷰 작성
  Future<String?> createReview({
    required String applicationId,
    required String reviewerId,
    required String reviewerName,
    required String targetUserId,
    required String businessId,
    required String businessName,
    required String workType,
    required DateTime workDate,
    required int rating,
    String? comment,
    bool wouldRehire = true,
  }) async {
    try {
      debugPrint('📝 [createReview] 리뷰 작성 시작');
      
      // 1. 리뷰 생성
      final docRef = await _firestore.collection('reviews').add({
        'applicationId': applicationId,
        'reviewerId': reviewerId,
        'reviewerName': reviewerName,
        'targetUserId': targetUserId,
        'businessId': businessId,
        'businessName': businessName,
        'workType': workType,
        'workDate': Timestamp.fromDate(workDate),
        'rating': rating,
        'comment': comment,
        'wouldRehire': wouldRehire,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      // 2. 사용자 통계 업데이트 (평균 평점, 리뷰 수)
      await _updateUserReviewStats(targetUserId);
      
      // 3. 지원서에 리뷰 작성 표시
      await _firestore.collection('applications').doc(applicationId).update({
        'hasReview': true,
        'reviewId': docRef.id,
      });
      
      // 4. 알림 생성
      await createNotification(
        NotificationModel.createReviewReceived(
          userId: targetUserId,
          businessName: businessName,
          rating: rating,
          reviewId: docRef.id,
        ),
      );
      
      debugPrint('✅ [createReview] 리뷰 작성 완료: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('❌ [createReview] 실패: $e');
      return null;
    }
  }

  /// 사용자 리뷰 통계 업데이트
  Future<void> _updateUserReviewStats(String userId) async {
    try {
      final reviews = await _firestore
          .collection('reviews')
          .where('targetUserId', isEqualTo: userId)
          .get();
      
      if (reviews.docs.isEmpty) return;
      
      double totalRating = 0;
      for (var doc in reviews.docs) {
        totalRating += ((doc.data()['rating'] ?? 0) as num).toDouble();
      }
      
      final avgRating = totalRating / reviews.docs.length;
      
      await _firestore.collection('users').doc(userId).update({
        'averageRating': avgRating,
        'reviewCount': reviews.docs.length,
      });
      
      debugPrint('✅ 사용자 리뷰 통계 업데이트: avg=$avgRating, count=${reviews.docs.length}');
    } catch (e) {
      debugPrint('⚠️ 사용자 리뷰 통계 업데이트 실패: $e');
    }
  }

  /// 사용자가 받은 리뷰 목록 조회
  Future<List<ReviewModel>> getUserReviews(String userId, {int limit = 10}) async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .where('targetUserId', isEqualTo: userId)
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