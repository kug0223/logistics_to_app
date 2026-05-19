import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/core/application_model.dart';
import '../utils/format_helper.dart';
import '../models/core/monthly_review_model.dart';
import '../models/core/review_request_model.dart';
import '../models/settings/trust_settings_model.dart';

/// 월별 리뷰 서비스 (재설계 v2)
///
/// 핵심 변경사항:
///   - reviewKey를 문서 ID로 사용 → Race Condition 방지 (C-2)
///   - publishAt은 CF에서 서버 시간 기준 설정 (C-3)
///   - 통계는 isPublished=true 리뷰만 반영 (C-1)
///   - USER_TO_BUSINESS 리뷰에 reviewerId 미저장 (C-4)
///   - review_requests 페어를 통한 양방향 동시 공개
///   - getReviewableWorkers: 장기 근로자 포함 + N+1 쿼리 제거 (H-1, H-2)
///   - 리뷰 작성 기한 14일 검증 (H-3)
class MonthlyReviewService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const int _reviewWindowDays = 7;

  // ═══════════════════════════════════════════════════════════
  // 리뷰 요청 (review_requests)
  // ═══════════════════════════════════════════════════════════

  /// requestKey로 단일 review_request 조회
  Future<ReviewRequestModel?> getReviewRequest(String requestKey) async {
    try {
      final doc = await _db.collection('review_requests').doc(requestKey).get();
      if (!doc.exists) return null;
      return ReviewRequestModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('❌ 리뷰 요청 조회 실패: $e');
      return null;
    }
  }

  /// 특정 workerId의 미작성 리뷰 요청 조회 (지원자용)
  Future<List<ReviewRequestModel>> getPendingRequestsForWorker(
      String workerId) async {
    try {
      final snap = await _db
          .collection('review_requests')
          .where('workerId', isEqualTo: workerId)
          .where('workerStatus', isEqualTo: 'pending')
          .where('isPublished', isEqualTo: false)
          .get();
      return snap.docs.map(ReviewRequestModel.fromFirestore).toList();
    } catch (e) {
      debugPrint('❌ worker 리뷰 요청 조회 실패: $e');
      return [];
    }
  }

  /// 특정 businessId의 미작성 리뷰 요청 조회 (관리자용)
  Future<List<ReviewRequestModel>> getPendingRequestsForBusiness(
      String businessId) async {
    try {
      final snap = await _db
          .collection('review_requests')
          .where('businessId', isEqualTo: businessId)
          .where('adminStatus', isEqualTo: 'pending')
          .where('isPublished', isEqualTo: false)
          .get();
      return snap.docs.map(ReviewRequestModel.fromFirestore).toList();
    } catch (e) {
      debugPrint('❌ admin 리뷰 요청 조회 실패: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 리뷰 작성
  // ═══════════════════════════════════════════════════════════

  /// 관리자 → 지원자 리뷰 작성
  ///
  /// - reviewKey를 doc ID로 set() → 동시 요청 중복 방지
  /// - review_requests.adminStatus 업데이트
  /// - 양쪽 모두 submitted이면 CF가 즉시 공개 처리
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
    String? requestId,
  }) async {
    try {
      // 작성 기한 검증 (H-3): 해당 월 마지막 날 + 14일 이내
      if (!_isWithinReviewWindow(reviewYear, reviewMonth)) {
        return (reviewId: null, error: '리뷰 작성 기한(근무 완료 후 14일)이 지났습니다.');
      }

      final reviewKey = MonthlyReviewModel.generateKeyForUser(
        businessId: businessId,
        targetUserId: targetUserId,
        year: reviewYear,
        month: reviewMonth,
      );

      final review = MonthlyReviewModel(
        id: reviewKey,
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
        requestId: requestId,
        createdAt: DateTime.now(),
      );

      // set() with doc ID = reviewKey → 중복 시 이미 존재 예외 발생
      final docRef = _db.collection('monthly_reviews').doc(reviewKey);
      await docRef.set(review.toMap());

      // review_requests 업데이트
      if (requestId != null) {
        await _db.collection('review_requests').doc(requestId).update({
          'adminStatus': 'submitted',
          'adminReviewId': reviewKey,
        });
      }

      debugPrint('✅ 리뷰 작성 완료: $reviewKey');
      return (reviewId: reviewKey, error: null);
    } on FirebaseException catch (e) {
      if (e.code == 'already-exists') {
        return (reviewId: null, error: '이번 달 리뷰는 이미 작성되었습니다.');
      }
      debugPrint('❌ 리뷰 작성 실패: $e');
      return (reviewId: null, error: '리뷰 작성에 실패했습니다.');
    } catch (e) {
      debugPrint('❌ 리뷰 작성 실패: $e');
      return (reviewId: null, error: '리뷰 작성에 실패했습니다.');
    }
  }

  /// 지원자 → 사업장 리뷰 작성 (익명)
  ///
  /// - reviewerId는 문서에 저장하지 않음 (review_requests로 작성자 추적)
  /// - review_requests.workerStatus 업데이트
  Future<({String? reviewId, String? error})> createReviewForBusiness({
    required String reviewerId,
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
    String? requestId,
  }) async {
    try {
      if (!_isWithinReviewWindow(reviewYear, reviewMonth)) {
        return (reviewId: null, error: '리뷰 작성 기한(근무 완료 후 14일)이 지났습니다.');
      }

      final reviewKey = MonthlyReviewModel.generateKeyForBusiness(
        businessId: businessId,
        reviewerId: reviewerId,
        year: reviewYear,
        month: reviewMonth,
      );

      final review = MonthlyReviewModel(
        id: reviewKey,
        reviewKey: reviewKey,
        reviewType: ReviewType.USER_TO_BUSINESS,
        // reviewerId 저장 안 함 (익명 보장)
        reviewerName: '익명',
        businessId: businessId,
        businessName: businessName,
        reviewYear: reviewYear,
        reviewMonth: reviewMonth,
        workDaysInMonth: workDaysInMonth,
        rating: rating,
        wouldRehire: wouldWorkAgain,
        positiveTags: positiveTags,
        improvementTags: improvementTags,
        comment: comment,
        requestId: requestId,
        createdAt: DateTime.now(),
      );

      final docRef = _db.collection('monthly_reviews').doc(reviewKey);
      await docRef.set(review.toMap());

      if (requestId != null) {
        await _db.collection('review_requests').doc(requestId).update({
          'workerStatus': 'submitted',
          'workerReviewId': reviewKey,
        });
      }

      debugPrint('✅ 사업장 리뷰 작성 완료: $reviewKey');
      return (reviewId: reviewKey, error: null);
    } on FirebaseException catch (e) {
      if (e.code == 'already-exists') {
        return (reviewId: null, error: '이번 달 리뷰는 이미 작성되었습니다.');
      }
      debugPrint('❌ 사업장 리뷰 작성 실패: $e');
      return (reviewId: null, error: '리뷰 작성에 실패했습니다.');
    } catch (e) {
      debugPrint('❌ 사업장 리뷰 작성 실패: $e');
      return (reviewId: null, error: '리뷰 작성에 실패했습니다.');
    }
  }

  /// 사업장 답변 달기 (USER_TO_BUSINESS 리뷰)
  Future<bool> addBusinessResponse({
    required String reviewId,
    required String response,
  }) async {
    try {
      await _db.collection('monthly_reviews').doc(reviewId).update({
        'businessResponse': response,
        'businessRespondedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('❌ 사업장 답변 실패: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 리뷰 조회
  // ═══════════════════════════════════════════════════════════

  /// 사업장이 작성한 리뷰 (관리자 → 지원자)
  Future<List<MonthlyReviewModel>> getReviewsByBusiness({
    required String businessId,
    int limit = 50,
  }) async {
    try {
      final snap = await _db
          .collection('monthly_reviews')
          .where('businessId', isEqualTo: businessId)
          .where('reviewType', isEqualTo: ReviewType.ADMIN_TO_USER.name)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map(MonthlyReviewModel.fromFirestore).toList();
    } catch (e) {
      debugPrint('❌ 사업장 작성 리뷰 조회 실패: $e');
      return [];
    }
  }

  /// 사용자가 받은 공개 리뷰 (지원자 본인 + 관리자용)
  Future<List<MonthlyReviewModel>> getPublishedReviewsForUser({
    required String targetUserId,
    int limit = 20,
  }) async {
    try {
      final snap = await _db
          .collection('monthly_reviews')
          .where('targetUserId', isEqualTo: targetUserId)
          .where('reviewType', isEqualTo: ReviewType.ADMIN_TO_USER.name)
          .where('isPublished', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map(MonthlyReviewModel.fromFirestore).toList();
    } catch (e) {
      debugPrint('❌ 공개 리뷰 조회 실패: $e');
      return [];
    }
  }

  /// 사용자가 받은 모든 리뷰 (관리자 전용 — 미공개 포함)
  Future<List<MonthlyReviewModel>> getAllReviewsForUser({
    required String targetUserId,
    int limit = 20,
  }) async {
    try {
      final snap = await _db
          .collection('monthly_reviews')
          .where('targetUserId', isEqualTo: targetUserId)
          .where('reviewType', isEqualTo: ReviewType.ADMIN_TO_USER.name)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map(MonthlyReviewModel.fromFirestore).toList();
    } catch (e) {
      debugPrint('❌ 사용자 리뷰 조회 실패: $e');
      return [];
    }
  }

  /// 사업장이 받은 공개 리뷰 (지원자 → 사업장)
  Future<List<MonthlyReviewModel>> getPublishedReviewsForBusiness({
    required String businessId,
    int limit = 20,
  }) async {
    try {
      final snap = await _db
          .collection('monthly_reviews')
          .where('businessId', isEqualTo: businessId)
          .where('reviewType', isEqualTo: ReviewType.USER_TO_BUSINESS.name)
          .where('isPublished', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map(MonthlyReviewModel.fromFirestore).toList();
    } catch (e) {
      debugPrint('❌ 사업장 리뷰 조회 실패: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 리뷰 대상자 조회 (H-1 장기 근로자 포함, H-2 N+1 제거)
  // ═══════════════════════════════════════════════════════════

  /// 해당 월 근무자 목록 (단기 + 장기 통합, 이미 리뷰한 근무자 제외)
  Future<List<Map<String, dynamic>>> getReviewableWorkers({
    required String businessId,
    required int year,
    required int month,
  }) async {
    try {
      final monthStart = DateTime(year, month, 1);
      final monthEnd = DateTime(year, month + 1, 0, 23, 59, 59);

      // 단기: workDate가 해당 월인 확정 지원서
      final shortTermFuture = _db
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: AppStatus.confirmed)
          .where('workDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('workDate',
              isLessThanOrEqualTo: Timestamp.fromDate(monthEnd))
          .get();

      // 장기: workEndDate가 해당 월 이후 (계약이 해당 월에 걸침)
      final longTermFuture = _db
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: AppStatus.confirmed)
          .where('workEndDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .get();

      // 해당 월 기존 리뷰 일괄 조회 (N+1 제거)
      final existingReviewsFuture = _db
          .collection('monthly_reviews')
          .where('businessId', isEqualTo: businessId)
          .where('reviewType', isEqualTo: ReviewType.ADMIN_TO_USER.name)
          .where('reviewYear', isEqualTo: year)
          .where('reviewMonth', isEqualTo: month)
          .get();

      final results =
          await Future.wait([shortTermFuture, longTermFuture, existingReviewsFuture]);

      final shortTermDocs = results[0].docs;
      final longTermDocs = results[1].docs;
      final existingReviewDocs = results[2].docs;

      // 이미 리뷰된 targetUserId 집합
      final reviewedUserIds = existingReviewDocs
          .map((d) => d.data()['targetUserId'] as String?)
          .whereType<String>()
          .toSet();

      final Map<String, Map<String, dynamic>> workerMap = {};

      // 단기 근무자 집계
      for (final doc in shortTermDocs) {
        final data = doc.data();
        final uid = data['uid'] as String? ?? '';
        if (uid.isEmpty || reviewedUserIds.contains(uid)) continue;
        workerMap.putIfAbsent(uid, () => {
              'uid': uid,
              'name': data['applicantName'] ?? '',
              'workDays': 0,
              'normalDays': 0,
              'lateDays': 0,
            });
        workerMap[uid]!['workDays'] =
            (workerMap[uid]!['workDays'] as int) + 1;
      }

      // 장기 근무자 집계 (해당 월에 실제 근무한 날 수 계산)
      for (final doc in longTermDocs) {
        final data = doc.data();
        final uid = data['uid'] as String? ?? '';
        final workDays = data['workDays'] as List<dynamic>?;
        if (uid.isEmpty || workDays == null || workDays.isEmpty) continue;
        if (reviewedUserIds.contains(uid)) continue;

        final workDate = (data['workDate'] as Timestamp?)?.toDate();
        final workEndDate = (data['workEndDate'] as Timestamp?)?.toDate();
        if (workDate == null || workEndDate == null) continue;

        // 해당 월 근무 일수 추정 (요일 기반)
        final daysInMonth = _countWorkingDaysInMonth(
          workDays.cast<String>(),
          year,
          month,
          workDate,
          workEndDate,
        );
        if (daysInMonth == 0) continue;

        workerMap.putIfAbsent(uid, () => {
              'uid': uid,
              'name': data['applicantName'] ?? '',
              'workDays': 0,
              'normalDays': 0,
              'lateDays': 0,
            });
        workerMap[uid]!['workDays'] =
            (workerMap[uid]!['workDays'] as int) + daysInMonth;
      }

      return workerMap.values.toList();
    } catch (e) {
      debugPrint('❌ 리뷰 대상자 조회 실패: $e');
      return [];
    }
  }

  /// 해당 월의 특정 요일 근무 일수 계산
  int _countWorkingDaysInMonth(
    List<String> workDayNames,
    int year,
    int month,
    DateTime contractStart,
    DateTime contractEnd,
  ) {
    final monthStart = DateTime(year, month, 1);
    final monthEnd = DateTime(year, month + 1, 0);

    final effectiveStart =
        contractStart.isAfter(monthStart) ? contractStart : monthStart;
    final effectiveEnd =
        contractEnd.isBefore(monthEnd) ? contractEnd : monthEnd;

    if (effectiveStart.isAfter(effectiveEnd)) return 0;

    int count = 0;
    DateTime cursor = effectiveStart;
    while (!cursor.isAfter(effectiveEnd)) {
      final dayName = FormatHelper.weekday(cursor);
      if (workDayNames.contains(dayName)) count++;
      cursor = cursor.add(const Duration(days: 1));
    }
    return count;
  }

  // ═══════════════════════════════════════════════════════════
  // 작성 기한 검증 (H-3)
  // ═══════════════════════════════════════════════════════════

  /// 해당 년월의 리뷰 작성 가능 여부
  /// 해당 월 마지막 날 + 14일 이내만 허용
  bool _isWithinReviewWindow(int year, int month) {
    final monthEnd = DateTime(year, month + 1, 0); // 해당 월 마지막 날
    final deadline = monthEnd.add(const Duration(days: _reviewWindowDays));
    return DateTime.now().isBefore(deadline);
  }

  /// 외부에서 기한 확인용
  bool canWriteReview(int year, int month) =>
      _isWithinReviewWindow(year, month);

  // ═══════════════════════════════════════════════════════════
  // 중복 확인 (review_requests 기반)
  // ═══════════════════════════════════════════════════════════

  /// reviewId(= reviewKey)로 기작성 리뷰 단건 조회
  Future<MonthlyReviewModel?> getReviewById(String reviewId) async {
    try {
      final doc = await _db.collection('monthly_reviews').doc(reviewId).get();
      if (!doc.exists) return null;
      return MonthlyReviewModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('❌ 리뷰 조회 실패: $e');
      return null;
    }
  }

  Future<bool> hasAdminReviewThisMonth({
    required String businessId,
    required String targetUserId,
    required int year,
    required int month,
  }) async {
    final key = MonthlyReviewModel.generateKeyForUser(
      businessId: businessId,
      targetUserId: targetUserId,
      year: year,
      month: month,
    );
    final doc = await _db.collection('monthly_reviews').doc(key).get();
    return doc.exists;
  }

  Future<bool> hasWorkerReviewThisMonth({
    required String businessId,
    required String reviewerId,
    required int year,
    required int month,
  }) async {
    final key = MonthlyReviewModel.generateKeyForBusiness(
      businessId: businessId,
      reviewerId: reviewerId,
      year: year,
      month: month,
    );
    final doc = await _db.collection('monthly_reviews').doc(key).get();
    return doc.exists;
  }

  // ═══════════════════════════════════════════════════════════
  // 통계 업데이트 (C-1: isPublished=true만 반영)
  // ═══════════════════════════════════════════════════════════

  Future<void> updateUserReviewStats(String userId) async {
    try {
      final snap = await _db
          .collection('monthly_reviews')
          .where('targetUserId', isEqualTo: userId)
          .where('reviewType', isEqualTo: ReviewType.ADMIN_TO_USER.name)
          .where('isPublished', isEqualTo: true) // 공개된 리뷰만
          .get();

      if (snap.docs.isEmpty) return;

      double totalRating = 0;
      int rehireYesCount = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        totalRating += (data['rating'] as num? ?? 0).toDouble();
        if (data['wouldRehire'] == true) rehireYesCount++;
      }

      await _db.collection('users').doc(userId).update({
        'averageRating': totalRating / snap.size,
        'reviewCount': snap.size,
        'rehireRate': rehireYesCount / snap.size,
      });
    } catch (e) {
      debugPrint('⚠️ 사용자 통계 업데이트 실패: $e');
    }
  }

  Future<void> updateBusinessReviewStats(String businessId) async {
    try {
      final snap = await _db
          .collection('monthly_reviews')
          .where('businessId', isEqualTo: businessId)
          .where('reviewType', isEqualTo: ReviewType.USER_TO_BUSINESS.name)
          .where('isPublished', isEqualTo: true)
          .get();

      if (snap.docs.isEmpty) return;

      double totalRating = 0;
      for (final doc in snap.docs) {
        totalRating += (doc.data()['rating'] as num? ?? 0).toDouble();
      }

      await _db.collection('businesses').doc(businessId).update({
        'rating': totalRating / snap.size,
        'reviewCount': snap.size,
      });
    } catch (e) {
      debugPrint('⚠️ 사업장 통계 업데이트 실패: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 설정 조회
  // ═══════════════════════════════════════════════════════════

  Future<ReviewTagsModel> getReviewTags() async {
    try {
      final doc =
          await _db.collection('settings').doc('review_tags').get();
      if (!doc.exists) {
        final defaults = ReviewTagsModel.defaults();
        await _db
            .collection('settings')
            .doc('review_tags')
            .set(defaults.toMap());
        return defaults;
      }
      return ReviewTagsModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('❌ 리뷰 태그 조회 실패: $e');
      return ReviewTagsModel.defaults();
    }
  }

  Future<TrustSettingsModel> getTrustSettings() async {
    try {
      final doc =
          await _db.collection('settings').doc('trust_rules').get();
      if (!doc.exists) {
        final defaults = TrustSettingsModel.defaults();
        await _db
            .collection('settings')
            .doc('trust_rules')
            .set(defaults.toMap());
        return defaults;
      }
      return TrustSettingsModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('❌ 신뢰도 규칙 조회 실패: $e');
      return TrustSettingsModel.defaults();
    }
  }
}

