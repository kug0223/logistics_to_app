import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/core/application_model.dart';
import '../utils/format_helper.dart';
import '../models/core/monthly_review_model.dart';
import '../models/core/review_request_model.dart';
import '../models/settings/trust_settings_model.dart';
import '../utils/network_checker.dart';

/// 리뷰 커서 기반 페이지네이션 결과
class ReviewPage<T> {
  final List<T> records;
  final DocumentSnapshot? cursor;
  final bool hasMore;
  const ReviewPage({required this.records, this.cursor, required this.hasMore});
}

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

  static const int _reviewWindowDays = 14;

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
          .limit(200)
          .get();
      return snap.docs.map(ReviewRequestModel.fromFirestore).toList();
    } catch (e) {
      debugPrint('❌ admin 리뷰 요청 조회 실패: $e');
      return [];
    }
  }

  /// 미공개 리뷰 요청 전체 조회 (deadline 맵 구성용)
  /// adminStatus 무관 — 작성완료 후 상대방 대기 중인 요청도 포함
  Future<List<ReviewRequestModel>> getAllNonPublishedRequestsForBusiness(
      String businessId) async {
    try {
      final snap = await _db
          .collection('review_requests')
          .where('businessId', isEqualTo: businessId)
          .where('isPublished', isEqualTo: false)
          .get();
      return snap.docs.map(ReviewRequestModel.fromFirestore).toList();
    } catch (e) {
      debugPrint('❌ 미공개 리뷰 요청 조회 실패: $e');
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
    String? targetUserGender,
    int? targetUserAge,
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
    NetworkChecker.instance.assertOnline('리뷰 작성을 하려면 인터넷 연결이 필요합니다.');
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
        targetUserGender: targetUserGender,
        targetUserAge: targetUserAge,
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

      // 트랜잭션으로 중복 제출 방지 + review_requests 원자 갱신 (BUG-G-01)
      // review_requests를 트랜잭션 밖에서 업데이트하면 CF 공개 트리거 미발동 가능
      final docRef = _db.collection('monthly_reviews').doc(reviewKey);
      await _db.runTransaction((tx) async {
        final existing = await tx.get(docRef);
        if (existing.exists) {
          throw FirebaseException(plugin: 'firestore', code: 'already-exists');
        }
        tx.set(docRef, review.toMap());
        if (requestId != null) {
          final requestRef = _db.collection('review_requests').doc(requestId);
          tx.set(requestRef, {
            'adminStatus': 'submitted',
            'adminReviewId': reviewKey,
          }, SetOptions(merge: true));
        }
      });

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
    NetworkChecker.instance.assertOnline('리뷰 작성을 하려면 인터넷 연결이 필요합니다.');
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

      // 트랜잭션으로 중복 제출 방지 + review_requests 원자 갱신 (BUG-G-02)
      // reviewerId 미저장(익명) 특성상 중복 감지가 어려우므로 반드시 트랜잭션 사용
      final docRef = _db.collection('monthly_reviews').doc(reviewKey);
      await _db.runTransaction((tx) async {
        final existing = await tx.get(docRef);
        if (existing.exists) {
          throw FirebaseException(plugin: 'firestore', code: 'already-exists');
        }
        tx.set(docRef, review.toMap());
        if (requestId != null) {
          final requestRef = _db.collection('review_requests').doc(requestId);
          tx.set(requestRef, {
            'workerStatus': 'submitted',
            'workerReviewId': reviewKey,
          }, SetOptions(merge: true));
        }
      });

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
  ///
  /// ⚠️ G-072: 기존 답변 덮어쓰기 가능 — 존재 여부 체크 없음.
  /// UI에서 businessResponse == null 일 때만 "답변하기" 버튼 표시하므로 실제 발생 가능성 낮음.
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
  ///
  /// ⚠️ G-020: UI에서 limit(100) 호출 — 100건 초과 시 오래된 리뷰 누락. 향후 페이지네이션 필요.
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
  ///
  /// wageConfirmed 이후에만 리뷰를 허용하는 강제 조건이 없다 — 의도된 설계.
  /// 리뷰는 급여 확정과 무관하게 해당 월 근무(confirmed/contractPending) 기준으로 작성 가능.
  /// 대신 getReviewableWorkers 조회 경로 자체가 confirmed 상태 지원서만 반환하므로
  /// 근무 이력 없는 사람에게 리뷰가 생성될 위험은 없다.
  Future<List<Map<String, dynamic>>> getReviewableWorkers({
    required String businessId,
    required int year,
    required int month,
  }) async {
    try {
      final monthStart = DateTime(year, month, 1);
      // [A06 수정] isLessThan 패턴: 말일 23:59:59가 아닌 다음 달 1일 자정을 사용.
      // Timestamp 비교는 초 단위이므로 DateTime(y, m+1, 0, 23, 59, 59)를 isLessThan에 쓰면
      // 말일 23:59:59 정확히 일치하는 문서가 제외된다.
      // DateTime(year, month+1, 1)는 Dart가 13월을 자동 정규화(1월로 변환)하므로 12월도 안전.
      final monthEndExclusive = DateTime(year, month + 1, 1);

      // whereIn 복합 쿼리 → PERMISSION_DENIED 방지를 위해 status별 병렬 쿼리로 분리
      // 단기: workDate가 해당 월인 확정 지원서 (CONFIRMED + CONTRACT_PENDING 각각)
      // 장기: workEndDate가 해당 월 이후 (CONFIRMED + CONTRACT_PENDING 각각)
      // 해당 월 기존 리뷰 일괄 조회 (N+1 제거)
      final allResults = await Future.wait([
        _db.collection('applications')
            .where('businessId', isEqualTo: businessId)
            .where('status', isEqualTo: AppStatus.confirmed)
            .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
            .where('workDate', isLessThan: Timestamp.fromDate(monthEndExclusive))
            .get(),
        _db.collection('applications')
            .where('businessId', isEqualTo: businessId)
            .where('status', isEqualTo: AppStatus.contractPending)
            .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
            .where('workDate', isLessThan: Timestamp.fromDate(monthEndExclusive))
            .get(),
        // ⚠️ G-045: limit(500) 각각 — 초대형 사업장에서 status당 500명 초과 시 일부 누락. 현실적 위험 낮음.
        _db.collection('applications')
            .where('businessId', isEqualTo: businessId)
            .where('status', isEqualTo: AppStatus.confirmed)
            .where('workEndDate', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
            .limit(500)
            .get(),
        _db.collection('applications')
            .where('businessId', isEqualTo: businessId)
            .where('status', isEqualTo: AppStatus.contractPending)
            .where('workEndDate', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
            .limit(500)
            .get(),
        _db.collection('monthly_reviews')
            .where('businessId', isEqualTo: businessId)
            .where('reviewType', isEqualTo: ReviewType.ADMIN_TO_USER.name)
            .where('reviewYear', isEqualTo: year)
            .where('reviewMonth', isEqualTo: month)
            .get(),
      ]);

      final shortTermDocs = [...allResults[0].docs, ...allResults[1].docs];
      final longTermDocs = [...allResults[2].docs, ...allResults[3].docs];
      final existingReviewDocs = allResults[4].docs;

      // 이미 리뷰된 targetUserId 집합
      final reviewedUserIds = existingReviewDocs
          .map((d) => d.data()['targetUserId'] as String?)
          .whereType<String>()
          .toSet();

      final Map<String, Map<String, dynamic>> workerMap = {};

      // [F-001] 장기 지원서 ID 집합 — shortTermDocs 쿼리가 workDate 기준이라
      // 당월 시작하는 장기 지원서도 잡힘. 중복 집계 방지를 위해 먼저 처리 후 단기에서 제외
      final longTermDocIds = longTermDocs.map((d) => d.id).toSet();

      // 단기 근무자 집계 (장기 지원서 제외)
      for (final doc in shortTermDocs) {
        if (longTermDocIds.contains(doc.id)) continue; // 장기 지원서 중복 방지
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
        // [특이사항] putIfAbsent 직후 접근 — workerMap[uid]와 'workDays' 키 모두 보장, ! 안전
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

        final workDate = (data['workDate'] as Timestamp?)?.toDate().toLocal();
        final workEndDate = (data['workEndDate'] as Timestamp?)?.toDate().toLocal();
        if (workDate == null || workEndDate == null) continue;

        // 해당 월 근무 일수 추정 (요일 기반)
        final daysInMonth = _countWorkingDaysInMonth(
          workDays.whereType<String>().toList(),
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
  ///
  /// ⚠️ G-013: 기기 클라이언트 시간 기준 — 기기 시간 조작 시 기한 우회 가능.
  /// UX 제어 목적으로 의도된 설계. 엄격한 강제가 필요하면 CF에서 serverTimestamp 재검증 필요.
  bool _isWithinReviewWindow(int year, int month) {
    // 해당 월 마지막 날 + 14일의 '끝'(= 다음 날 자정)을 deadline으로 사용.
    // DateTime(year, month+1, 0)은 말일 00:00:00이므로 그대로 +14일 하면
    // 14일 당일 자정이 deadline이 되어 14일 하루 전체가 기한 초과로 처리됨(BUG).
    // +15일(다음 날 자정)을 사용하면 말일 기준 정확히 14일 23:59:59까지 허용.
    final monthEnd = DateTime(year, month + 1, 0); // 해당 월 마지막 날 00:00:00
    final deadline = monthEnd.add(const Duration(days: _reviewWindowDays + 1));
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

      if (snap.docs.isEmpty) {
        // 공개된 리뷰가 없으면 통계 초기화 (마지막 리뷰 비공개 전환 시 stale 방지)
        await _db.collection('users').doc(userId).update({
          'averageRating': null,
          'reviewCount': 0,
          'rehireRate': 0.0,
        });
        return;
      }

      double totalRating = 0;
      int ratedCount = 0;
      int rehireYesCount = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final r = (data['rating'] as num? ?? 0).toInt();
        if (r > 0) { totalRating += r; ratedCount++; }
        if (data['wouldRehire'] == true) rehireYesCount++;
      }

      await _db.collection('users').doc(userId).update({
        'averageRating': ratedCount > 0 ? totalRating / ratedCount : null,
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

      if (snap.docs.isEmpty) {
        await _db.collection('businesses').doc(businessId).update({
          'rating': null,
          'reviewCount': 0,
        });
        return;
      }

      double totalRating = 0;
      int ratedCount = 0;
      for (final doc in snap.docs) {
        final r = (doc.data()['rating'] as num? ?? 0).toInt();
        if (r > 0) { totalRating += r; ratedCount++; }
      }

      await _db.collection('businesses').doc(businessId).update({
        'rating': ratedCount > 0 ? totalRating / ratedCount : null,
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
      // 문서 미존재 시 클라이언트에서 set() 금지 — settings 쓰기는 isSuperAdmin() 전용.
      // 슈퍼어드민이 아닌 사용자가 set()을 시도하면 PERMISSION_DENIED 발생.
      // 문서가 없으면 기본값을 반환하고, 초기 생성은 슈퍼어드민 설정 화면에서 수행.
      if (!doc.exists) return ReviewTagsModel.defaults();
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
      // 동일 이유: 문서 미존재 시 기본값 반환 (클라이언트 set() 금지)
      if (!doc.exists) return TrustSettingsModel.defaults();
      return TrustSettingsModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('❌ 신뢰도 규칙 조회 실패: $e');
      return TrustSettingsModel.defaults();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 커서 기반 페이지네이션 (pageSize+1 패턴으로 hasMore 정확도 보장)
  // ═══════════════════════════════════════════════════════════

  /// 사업장이 작성한 리뷰 (ADMIN_TO_USER) — 페이지네이션
  Future<ReviewPage<MonthlyReviewModel>> getReviewsByBusinessPaged({
    required String businessId,
    DocumentSnapshot? startAfter,
    int pageSize = 50,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _db
          .collection('monthly_reviews')
          .where('businessId', isEqualTo: businessId)
          .where('reviewType', isEqualTo: ReviewType.ADMIN_TO_USER.name)
          .orderBy('createdAt', descending: true)
          .limit(pageSize + 1);
      if (startAfter != null) q = q.startAfterDocument(startAfter);
      final snap = await q.get();
      final hasMore = snap.docs.length > pageSize;
      final docs = hasMore ? snap.docs.sublist(0, pageSize) : snap.docs;
      return ReviewPage(
        records: docs.map(MonthlyReviewModel.fromFirestore).toList(),
        cursor: docs.isNotEmpty ? docs.last : null,
        hasMore: hasMore,
      );
    } catch (e) {
      debugPrint('❌ 사업장 작성 리뷰 페이지 조회 실패: $e');
      return const ReviewPage(records: [], cursor: null, hasMore: false);
    }
  }

  /// 사업장이 받은 공개 리뷰 (USER_TO_BUSINESS) — 페이지네이션
  Future<ReviewPage<MonthlyReviewModel>> getPublishedReviewsForBusinessPaged({
    required String businessId,
    DocumentSnapshot? startAfter,
    int pageSize = 50,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _db
          .collection('monthly_reviews')
          .where('businessId', isEqualTo: businessId)
          .where('reviewType', isEqualTo: ReviewType.USER_TO_BUSINESS.name)
          .where('isPublished', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(pageSize + 1);
      if (startAfter != null) q = q.startAfterDocument(startAfter);
      final snap = await q.get();
      final hasMore = snap.docs.length > pageSize;
      final docs = hasMore ? snap.docs.sublist(0, pageSize) : snap.docs;
      return ReviewPage(
        records: docs.map(MonthlyReviewModel.fromFirestore).toList(),
        cursor: docs.isNotEmpty ? docs.last : null,
        hasMore: hasMore,
      );
    } catch (e) {
      debugPrint('❌ 사업장 받은 리뷰 페이지 조회 실패: $e');
      return const ReviewPage(records: [], cursor: null, hasMore: false);
    }
  }

  /// 근무자가 받은 공개 리뷰 (ADMIN_TO_USER) — 페이지네이션
  Future<ReviewPage<MonthlyReviewModel>> getPublishedReviewsForUserPaged({
    required String targetUserId,
    DocumentSnapshot? startAfter,
    int pageSize = 30,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _db
          .collection('monthly_reviews')
          .where('targetUserId', isEqualTo: targetUserId)
          .where('reviewType', isEqualTo: ReviewType.ADMIN_TO_USER.name)
          .where('isPublished', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(pageSize + 1);
      if (startAfter != null) q = q.startAfterDocument(startAfter);
      final snap = await q.get();
      final hasMore = snap.docs.length > pageSize;
      final docs = hasMore ? snap.docs.sublist(0, pageSize) : snap.docs;
      return ReviewPage(
        records: docs.map(MonthlyReviewModel.fromFirestore).toList(),
        cursor: docs.isNotEmpty ? docs.last : null,
        hasMore: hasMore,
      );
    } catch (e) {
      debugPrint('❌ 근무자 리뷰 페이지 조회 실패: $e');
      return const ReviewPage(records: [], cursor: null, hasMore: false);
    }
  }

  /// 지원자 본인이 받은 모든 리뷰 (공개 여부 무관) — 페이지네이션
  /// 인덱스: (targetUserId, reviewType, createdAt DESC) — firestore.indexes.json에 존재
  Future<ReviewPage<MonthlyReviewModel>> getAllReviewsForUserPaged({
    required String targetUserId,
    DocumentSnapshot? startAfter,
    int pageSize = 30,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _db
          .collection('monthly_reviews')
          .where('targetUserId', isEqualTo: targetUserId)
          .where('reviewType', isEqualTo: ReviewType.ADMIN_TO_USER.name)
          .orderBy('createdAt', descending: true)
          .limit(pageSize + 1);
      if (startAfter != null) q = q.startAfterDocument(startAfter);
      final snap = await q.get();
      final hasMore = snap.docs.length > pageSize;
      final docs = hasMore ? snap.docs.sublist(0, pageSize) : snap.docs;
      return ReviewPage(
        records: docs.map(MonthlyReviewModel.fromFirestore).toList(),
        cursor: docs.isNotEmpty ? docs.last : null,
        hasMore: hasMore,
      );
    } catch (e) {
      debugPrint('❌ 근무자 전체 리뷰 조회 실패: $e');
      return const ReviewPage(records: [], cursor: null, hasMore: false);
    }
  }
}

