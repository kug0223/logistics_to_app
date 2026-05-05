// lib/services/monthly_review_service.dart

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/core/monthly_review_model.dart';
import '../models/settings/trust_settings_model.dart';

/// 월별 리뷰 서비스
/// 
/// 주요 기능:
/// - 리뷰 작성 (월 1회, 수정 불가)
/// - 3일 후 자동 공개
/// - 리뷰 태그 관리
class MonthlyReviewService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ═══════════════════════════════════════════════════════════
  // 리뷰 작성
  // ═══════════════════════════════════════════════════════════

  /// 관리자 → 지원자 리뷰 작성
  /// 
  /// 반환값:
  /// - 성공: 리뷰 ID
  /// - 이미 작성됨: null, error 메시지
  /// - 실패: null
  Future<({String? reviewId, String? error})> createReviewForUser({
    required String reviewerId,
    required String reviewerName,
    required String businessId,
    required String businessName,
    required String targetUserId,
    required String targetUserName,
    required int reviewYear,
    required int reviewMonth,
    required int workDaysInMonth,
    required int normalAttendanceDays,
    required int lateDays,
    required int rating,
    required bool wouldRehire,
    required List<String> positiveTags,
    required List<String> improvementTags,
    String? comment,
  }) async {
    try {
      // 1. 중복 체크
      final reviewKey = MonthlyReviewModel.generateKeyForUser(
        businessId: businessId,
        targetUserId: targetUserId,
        year: reviewYear,
        month: reviewMonth,
      );

      final existing = await _firestore
          .collection('monthly_reviews')
          .where('reviewKey', isEqualTo: reviewKey)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        debugPrint('⚠️ 이미 작성된 리뷰가 있습니다: $reviewKey');
        return (reviewId: null, error: '이번 달 리뷰는 이미 작성되었습니다.');
      }

      // 2. 공개일 계산 (작성일 + 3일)
      final now = DateTime.now();
      final publishAt = now.add(const Duration(days: 3));

      // 3. 리뷰 생성
      final review = MonthlyReviewModel(
        id: '',
        reviewKey: reviewKey,
        reviewType: ReviewType.ADMIN_TO_USER,
        reviewerId: reviewerId,
        reviewerName: reviewerName,
        businessId: businessId,
        businessName: businessName,
        targetUserId: targetUserId,
        targetUserName: targetUserName,
        reviewYear: reviewYear,
        reviewMonth: reviewMonth,
        workDaysInMonth: workDaysInMonth,
        normalAttendanceDays: normalAttendanceDays,
        lateDays: lateDays,
        rating: rating,
        wouldRehire: wouldRehire,
        positiveTags: positiveTags,
        improvementTags: improvementTags,
        comment: comment,
        isPublished: false,
        publishAt: publishAt,
        createdAt: now,
      );

      final docRef = await _firestore.collection('monthly_reviews').add(review.toMap());
      debugPrint('✅ 리뷰 작성 완료: ${docRef.id}');

      // 4. 사용자 통계 업데이트
      await _updateUserReviewStats(targetUserId);

      // 5. 알림 생성 (3일 후 공개 예정)
      await _createReviewNotification(
        userId: targetUserId,
        businessName: businessName,
        rating: rating,
        reviewId: docRef.id,
        publishAt: publishAt,
      );

      return (reviewId: docRef.id, error: null);
    } catch (e) {
      debugPrint('❌ 리뷰 작성 실패: $e');
      return (reviewId: null, error: '리뷰 작성에 실패했습니다.');
    }
  }

  /// 지원자 → 사업장 리뷰 작성
  Future<({String? reviewId, String? error})> createReviewForBusiness({
    required String reviewerId,
    required String reviewerName,
    required String businessId,
    required String businessName,
    required int reviewYear,
    required int reviewMonth,
    required int workDaysInMonth,
    required int rating,
    required bool wouldWorkAgain,
    required List<String> positiveTags,
    required List<String> improvementTags,
    String? comment,
  }) async {
    try {
      // 1. 중복 체크
      final reviewKey = MonthlyReviewModel.generateKeyForBusiness(
        businessId: businessId,
        reviewerId: reviewerId,
        year: reviewYear,
        month: reviewMonth,
      );

      final existing = await _firestore
          .collection('monthly_reviews')
          .where('reviewKey', isEqualTo: reviewKey)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        return (reviewId: null, error: '이번 달 리뷰는 이미 작성되었습니다.');
      }

      // 2. 공개일 계산 (작성일 + 3일)
      final now = DateTime.now();
      final publishAt = now.add(const Duration(days: 3));

      // 3. 리뷰 생성
      final review = MonthlyReviewModel(
        id: '',
        reviewKey: reviewKey,
        reviewType: ReviewType.USER_TO_BUSINESS,
        reviewerId: reviewerId,
        reviewerName: '익명', // 사업장 리뷰는 익명
        businessId: businessId,
        businessName: businessName,
        targetUserId: null,
        targetUserName: null,
        reviewYear: reviewYear,
        reviewMonth: reviewMonth,
        workDaysInMonth: workDaysInMonth,
        normalAttendanceDays: 0,
        lateDays: 0,
        rating: rating,
        wouldRehire: wouldWorkAgain,
        positiveTags: positiveTags,
        improvementTags: improvementTags,
        comment: comment,
        isPublished: false,
        publishAt: publishAt,
        createdAt: now,
      );

      final docRef = await _firestore.collection('monthly_reviews').add(review.toMap());
      debugPrint('✅ 사업장 리뷰 작성 완료: ${docRef.id}');

      return (reviewId: docRef.id, error: null);
    } catch (e) {
      debugPrint('❌ 사업장 리뷰 작성 실패: $e');
      return (reviewId: null, error: '리뷰 작성에 실패했습니다.');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 리뷰 조회
  // ═══════════════════════════════════════════════════════════

  /// 특정 사업장이 작성한 리뷰 목록 조회 (관리자 → 지원자)
  Future<List<MonthlyReviewModel>> getReviewsByBusiness({
    required String businessId,
    int limit = 50,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('monthly_reviews')
          .where('businessId', isEqualTo: businessId)
          .where('reviewType', isEqualTo: ReviewType.ADMIN_TO_USER.name)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => MonthlyReviewModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ 사업장 작성 리뷰 조회 실패: $e');
      return [];
    }
  }

  /// 특정 사용자가 받은 리뷰 목록 조회 (관리자용 - 모든 리뷰)
  Future<List<MonthlyReviewModel>> getReviewsForUser({
    required String targetUserId,
    int limit = 20,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('monthly_reviews')
          .where('targetUserId', isEqualTo: targetUserId)
          .where('reviewType', isEqualTo: ReviewType.ADMIN_TO_USER.name)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => MonthlyReviewModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ 사용자 리뷰 조회 실패: $e');
      return [];
    }
  }

  /// 특정 사용자가 받은 공개된 리뷰만 조회 (지원자 본인용)
  Future<List<MonthlyReviewModel>> getPublishedReviewsForUser({
    required String targetUserId,
    int limit = 20,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('monthly_reviews')
          .where('targetUserId', isEqualTo: targetUserId)
          .where('reviewType', isEqualTo: ReviewType.ADMIN_TO_USER.name)
          .where('isPublished', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => MonthlyReviewModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ 공개 리뷰 조회 실패: $e');
      return [];
    }
  }

  /// 특정 사업장이 받은 리뷰 조회 (해당 사업장 관리자용)
  Future<List<MonthlyReviewModel>> getReviewsForBusiness({
    required String businessId,
    int limit = 20,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('monthly_reviews')
          .where('businessId', isEqualTo: businessId)
          .where('reviewType', isEqualTo: ReviewType.USER_TO_BUSINESS.name)
          .where('isPublished', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => MonthlyReviewModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ 사업장 리뷰 조회 실패: $e');
      return [];
    }
  }

  /// 특정 사업장에서 특정 지원자에 대한 리뷰 조회
  Future<List<MonthlyReviewModel>> getReviewsByBusinessForUser({
    required String businessId,
    required String targetUserId,
    int limit = 12,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('monthly_reviews')
          .where('businessId', isEqualTo: businessId)
          .where('targetUserId', isEqualTo: targetUserId)
          .where('reviewType', isEqualTo: ReviewType.ADMIN_TO_USER.name)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => MonthlyReviewModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ 사업장별 사용자 리뷰 조회 실패: $e');
      return [];
    }
  }

  /// 이번 달 리뷰 작성 여부 확인
  Future<bool> hasReviewThisMonth({
    required String businessId,
    required String targetUserId,
    required int year,
    required int month,
  }) async {
    final reviewKey = MonthlyReviewModel.generateKeyForUser(
      businessId: businessId,
      targetUserId: targetUserId,
      year: year,
      month: month,
    );

    final snapshot = await _firestore
        .collection('monthly_reviews')
        .where('reviewKey', isEqualTo: reviewKey)
        .limit(1)
        .get();

    return snapshot.docs.isNotEmpty;
  }

  /// 이번 달 사업장 리뷰 작성 여부 확인
  Future<bool> hasBusinessReviewThisMonth({
    required String businessId,
    required String reviewerId,
    required int year,
    required int month,
  }) async {
    final reviewKey = MonthlyReviewModel.generateKeyForBusiness(
      businessId: businessId,
      reviewerId: reviewerId,
      year: year,
      month: month,
    );

    final snapshot = await _firestore
        .collection('monthly_reviews')
        .where('reviewKey', isEqualTo: reviewKey)
        .limit(1)
        .get();

    return snapshot.docs.isNotEmpty;
  }

  // ═══════════════════════════════════════════════════════════
  // 공개 처리 (Cloud Functions에서 호출하거나 앱에서 체크)
  // ═══════════════════════════════════════════════════════════

  /// 공개 대상 리뷰 처리 (3일 지난 리뷰 공개)
  Future<int> publishDueReviews() async {
    try {
      final now = DateTime.now();
      
      final snapshot = await _firestore
          .collection('monthly_reviews')
          .where('isPublished', isEqualTo: false)
          .where('publishAt', isLessThanOrEqualTo: Timestamp.fromDate(now))
          .get();

      int publishedCount = 0;
      final batch = _firestore.batch();

      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'isPublished': true});
        publishedCount++;
      }

      if (publishedCount > 0) {
        await batch.commit();
        debugPrint('✅ $publishedCount개 리뷰 공개 처리 완료');
      }

      return publishedCount;
    } catch (e) {
      debugPrint('❌ 리뷰 공개 처리 실패: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 통계 업데이트
  // ═══════════════════════════════════════════════════════════

  /// 사용자 리뷰 통계 업데이트
  Future<void> _updateUserReviewStats(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('monthly_reviews')
          .where('targetUserId', isEqualTo: userId)
          .where('reviewType', isEqualTo: ReviewType.ADMIN_TO_USER.name)
          .get();

      if (snapshot.docs.isEmpty) return;

      double totalRating = 0;
      int rehireYesCount = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        totalRating += (data['rating'] ?? 0) as int;
        if (data['wouldRehire'] == true) rehireYesCount++;
      }

      final avgRating = totalRating / snapshot.docs.length;
      final rehireRate = rehireYesCount / snapshot.docs.length;

      await _firestore.collection('users').doc(userId).update({
        'averageRating': avgRating,
        'reviewCount': snapshot.docs.length,
        'rehireRate': rehireRate,
      });

      debugPrint('✅ 사용자 리뷰 통계 업데이트: avg=$avgRating, count=${snapshot.docs.length}, rehireRate=$rehireRate');
    } catch (e) {
      debugPrint('⚠️ 사용자 리뷰 통계 업데이트 실패: $e');
    }
  }

  /// 사업장 리뷰 통계 업데이트
  Future<void> updateBusinessReviewStats(String businessId) async {
    try {
      final snapshot = await _firestore
          .collection('monthly_reviews')
          .where('businessId', isEqualTo: businessId)
          .where('reviewType', isEqualTo: ReviewType.USER_TO_BUSINESS.name)
          .where('isPublished', isEqualTo: true)
          .get();

      if (snapshot.docs.isEmpty) return;

      double totalRating = 0;
      for (final doc in snapshot.docs) {
        totalRating += (doc.data()['rating'] ?? 0) as int;
      }

      final avgRating = totalRating / snapshot.docs.length;

      await _firestore.collection('businesses').doc(businessId).update({
        'rating': avgRating,
        'reviewCount': snapshot.docs.length,
      });

      debugPrint('✅ 사업장 리뷰 통계 업데이트: avg=$avgRating, count=${snapshot.docs.length}');
    } catch (e) {
      debugPrint('⚠️ 사업장 리뷰 통계 업데이트 실패: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 알림
  // ═══════════════════════════════════════════════════════════

  Future<void> _createReviewNotification({
    required String userId,
    required String businessName,
    required int rating,
    required String reviewId,
    required DateTime publishAt,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'type': 'REVIEW_RECEIVED',
        'title': '새 리뷰가 등록되었습니다',
        'body': '$businessName에서 평가를 받았습니다. ${publishAt.month}/${publishAt.day}에 공개됩니다.',
        'data': {
          'reviewId': reviewId,
          'action': 'reviewDetail',
        },
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('⚠️ 리뷰 알림 생성 실패: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 설정 조회
  // ═══════════════════════════════════════════════════════════

  /// 리뷰 태그 설정 조회
  Future<ReviewTagsModel> getReviewTags() async {
    try {
      final doc = await _firestore.collection('settings').doc('review_tags').get();
      
      if (!doc.exists) {
        // 기본값 저장 후 반환
        final defaults = ReviewTagsModel.defaults();
        await _firestore.collection('settings').doc('review_tags').set(defaults.toMap());
        return defaults;
      }

      return ReviewTagsModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('❌ 리뷰 태그 조회 실패: $e');
      return ReviewTagsModel.defaults();
    }
  }

  /// 신뢰도 규칙 조회
  Future<TrustSettingsModel> getTrustSettings() async {
    try {
      final doc = await _firestore.collection('settings').doc('trust_rules').get();
      
      if (!doc.exists) {
        // 기본값 저장 후 반환
        final defaults = TrustSettingsModel.defaults();
        await _firestore.collection('settings').doc('trust_rules').set(defaults.toMap());
        return defaults;
      }

      return TrustSettingsModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('❌ 신뢰도 규칙 조회 실패: $e');
      return TrustSettingsModel.defaults();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 리뷰 대상자 조회 (해당 월 근무자)
  // ═══════════════════════════════════════════════════════════

  /// 해당 월에 사업장에서 근무한 지원자 목록 (리뷰 작성 대상)
  Future<List<Map<String, dynamic>>> getReviewableWorkers({
    required String businessId,
    required int year,
    required int month,
  }) async {
    try {
      // 해당 월의 시작일과 종료일
      final startDate = DateTime(year, month, 1);
      final endDate = DateTime(year, month + 1, 0, 23, 59, 59);

      // 해당 월에 확정된 지원서 조회
      final snapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('workDate', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      // 사용자별 근무 집계
      final Map<String, Map<String, dynamic>> workerMap = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final uid = data['uid'] as String;
        
        if (!workerMap.containsKey(uid)) {
          workerMap[uid] = {
            'uid': uid,
            'name': data['applicantName'] ?? '',
            'workDays': 0,
            'normalDays': 0,
            'lateDays': 0,
          };
        }
        
        workerMap[uid]!['workDays'] = (workerMap[uid]!['workDays'] as int) + 1;
        
        // 출퇴근 기록 확인 (추후 구현)
        // TODO: attendance 기록과 연동
      }

      // 이미 리뷰 작성된 사용자 제외
      final List<Map<String, dynamic>> result = [];
      for (final worker in workerMap.values) {
        final hasReview = await hasReviewThisMonth(
          businessId: businessId,
          targetUserId: worker['uid'],
          year: year,
          month: month,
        );
        
        if (!hasReview) {
          result.add(worker);
        }
      }

      return result;
    } catch (e) {
      debugPrint('❌ 리뷰 대상자 조회 실패: $e');
      return [];
    }
  }
}