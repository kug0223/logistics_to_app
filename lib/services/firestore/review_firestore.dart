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
    NetworkChecker.instance.assertOnline('리뷰 작성을 하려면 인터넷 연결이 필요합니다.');
    try {
      debugPrint('📝 [createReview] 리뷰 작성 시작');
      
      // 1+3. 리뷰 생성 + 지원서 업데이트를 batch로 원자화
      final reviewRef = _firestore.collection('reviews').doc();
      final batch = _firestore.batch();
      batch.set(reviewRef, {
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
      batch.update(_firestore.collection('applications').doc(applicationId), {
        'hasReview': true,
        'reviewId': reviewRef.id,
      });
      await batch.commit();

      // 2. 사용자 통계 업데이트 (평균 평점, 리뷰 수) — 독립 실행
      await _updateUserReviewStats(targetUserId);

      // 4. 알림 생성 — 실패해도 리뷰 결과에 영향 없음
      try {
        await createNotification(
          NotificationModel.createReviewReceived(
            userId: targetUserId,
            businessName: businessName,
            rating: rating,
            reviewId: reviewRef.id,
          ),
        );
      } catch (e) {
        debugPrint('⚠️ [createReview] 알림 생성 실패: $e');
      }

      debugPrint('✅ [createReview] 리뷰 작성 완료: ${reviewRef.id}');
      return reviewRef.id;
    } catch (e) {
      debugPrint('❌ [createReview] 실패: $e');
      return null;
    }
  }

  /// 사용자 리뷰 통계 업데이트
  ///
  /// ⚠️ G-055: isPublished=true 리뷰만 통계에 반영 — 신규 리뷰는 CF 공개 전까지 통계 미반영.
  /// 의도된 설계: CF가 publish 후 통계를 재계산하는 방식으로 운영.
  Future<void> _updateUserReviewStats(String userId) async {
    try {
      final reviews = await _firestore
          .collection('reviews')
          .where('targetUserId', isEqualTo: userId)
          .where('isPublished', isEqualTo: true)
          .get();
      
      if (reviews.docs.isEmpty) return;

      // [BUG-수정] reviewCount도 rating>0인 리뷰만 집계 — averageRating과 기준 통일
      final ratedReviews = reviews.docs
          .where((d) => ((d.data()['rating'] as int?) ?? 0) > 0)
          .toList();
      final ratedCount = ratedReviews.length;
      final totalRating = ratedReviews.fold<int>(
        0,
        (acc, d) => acc + (((d.data()['rating'] as int?) ?? 0)),
      );
      final avgRating = ratedCount > 0 ? totalRating / ratedCount : null;

      await _firestore.collection('users').doc(userId).update({
        'averageRating': avgRating,
        'reviewCount': ratedCount,  // [BUG-수정] rating>0인 것만 카운트
      });

      debugPrint('✅ 사용자 리뷰 통계 업데이트: avg=$avgRating, count=$ratedCount');
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