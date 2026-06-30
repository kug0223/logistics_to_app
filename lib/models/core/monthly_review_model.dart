import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum ReviewType {
  ADMIN_TO_USER,    // 관리자 → 지원자
  USER_TO_BUSINESS, // 지원자 → 사업장 (익명)
}

/// 월별 리뷰 모델
///
/// 정책:
///   - review_requests 페어를 통해 양방향 동시 공개
///   - reviewKey(= doc ID)로 Race Condition 방지
///   - publishAt은 CF onDocumentCreated에서 서버 시간 기준 설정
///   - USER_TO_BUSINESS 리뷰는 reviewerId 미저장 (익명 보장)
class MonthlyReviewModel {
  final String id; // == reviewKey (doc ID)

  /// 중복 방지 + 문서 ID 역할
  /// ADMIN_TO_USER:    businessId_targetUserId_year_month
  /// USER_TO_BUSINESS: businessId_workerId_year_month_biz
  final String reviewKey;

  final ReviewType reviewType;

  // ─── 작성자/대상 ────────────────────────────────────────────
  final String reviewerName;

  /// USER_TO_BUSINESS는 저장하지 않음 (익명 보장)
  final String? reviewerId;

  final String businessId;
  final String businessName;

  /// ADMIN_TO_USER 전용
  final String? targetUserId;
  final String? targetUserName;
  final String? targetUserGender; // '남성' | '여성'
  final int? targetUserAge;       // 작성 시점 만 나이

  // ─── 기간 ───────────────────────────────────────────────────
  final int reviewYear;
  final int reviewMonth;

  final int workDaysInMonth;
  final int normalAttendanceDays;
  final int lateDays;

  // ─── 평가 ───────────────────────────────────────────────────
  final int rating;

  /// ADMIN_TO_USER 전용 (관리자 간에만 공유)
  final bool? wouldRehire;

  final List<String> positiveTags;
  final List<String> improvementTags;

  /// 상세 코멘트 (ADMIN_TO_USER: 지원자 비공개 / USER_TO_BUSINESS: 공개)
  final String? comment;

  // ─── 공개 ───────────────────────────────────────────────────
  final bool isPublished;

  /// CF onDocumentCreated 에서 서버 시간 기준으로 설정됨
  /// 클라이언트에서는 null로 저장
  final DateTime? publishAt;

  final DateTime? publishedAt;

  // ─── 연결 ───────────────────────────────────────────────────
  /// review_requests 문서 ID
  final String? requestId;

  /// 사업장 답변 (USER_TO_BUSINESS 리뷰에 사업장이 달 수 있음)
  final String? businessResponse;
  final DateTime? businessRespondedAt;

  final DateTime createdAt;

  const MonthlyReviewModel({
    required this.id,
    required this.reviewKey,
    required this.reviewType,
    required this.reviewerName,
    this.reviewerId,
    required this.businessId,
    required this.businessName,
    this.targetUserId,
    this.targetUserName,
    this.targetUserGender,
    this.targetUserAge,
    required this.reviewYear,
    required this.reviewMonth,
    required this.workDaysInMonth,
    this.normalAttendanceDays = 0,
    this.lateDays = 0,
    required this.rating,
    this.wouldRehire,
    this.positiveTags = const [],
    this.improvementTags = const [],
    this.comment,
    this.isPublished = false,
    this.publishAt,
    this.publishedAt,
    this.requestId,
    this.businessResponse,
    this.businessRespondedAt,
    required this.createdAt,
  });

  factory MonthlyReviewModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) throw ArgumentError('Document ${doc.id} has no data');
    final data = raw as Map<String, dynamic>;
    final reviewYear = (data['reviewYear'] as num?)?.toInt();
    if (reviewYear == null) throw ArgumentError('Document ${doc.id} missing required field: reviewYear');
    final reviewMonth = (data['reviewMonth'] as num?)?.toInt();
    if (reviewMonth == null) throw ArgumentError('Document ${doc.id} missing required field: reviewMonth');
    final createdAtTs = data['createdAt'] as Timestamp?;
    if (createdAtTs == null) throw ArgumentError('Document ${doc.id} missing required field: createdAt');
    return MonthlyReviewModel(
      id: doc.id,
      reviewKey: data['reviewKey'] ?? doc.id,
      reviewType: ReviewType.values.firstWhere(
        (e) => e.name == data['reviewType'],
        orElse: () => ReviewType.ADMIN_TO_USER,
      ),
      reviewerName: data['reviewerName'] ?? '',
      reviewerId: data['reviewerId'],
      businessId: data['businessId'] ?? '',
      businessName: data['businessName'] ?? '',
      targetUserId: data['targetUserId'],
      targetUserName: data['targetUserName'],
      targetUserGender: data['targetUserGender'],
      targetUserAge: (data['targetUserAge'] as num?)?.toInt(),
      reviewYear: reviewYear,
      reviewMonth: reviewMonth,
      workDaysInMonth: (data['workDaysInMonth'] as num?)?.toInt() ?? 0,
      normalAttendanceDays: (data['normalAttendanceDays'] as num?)?.toInt() ?? 0,
      lateDays: (data['lateDays'] as num?)?.toInt() ?? 0,
      rating: (data['rating'] as num?)?.toInt() ?? 0,
      wouldRehire: data['wouldRehire'],
      positiveTags: List<String>.from(data['positiveTags'] ?? []),
      improvementTags: List<String>.from(data['improvementTags'] ?? []),
      comment: data['comment'],
      isPublished: data['isPublished'] ?? false,
      publishAt: (data['publishAt'] as Timestamp?)?.toDate().toLocal(),
      publishedAt: (data['publishedAt'] as Timestamp?)?.toDate().toLocal(),
      requestId: data['requestId'],
      businessResponse: data['businessResponse'],
      businessRespondedAt:
          (data['businessRespondedAt'] as Timestamp?)?.toDate().toLocal(),
      createdAt: createdAtTs.toDate().toLocal(),
    );
  }

  // [SCHEMA-09] 역직렬화 실패 격리 — 손상 문서 1건이 목록 전체 크래시 방지
  static MonthlyReviewModel? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return MonthlyReviewModel.fromFirestore(doc);
    } catch (e, st) {
      debugPrint('[MonthlyReviewModel] 역직렬화 실패 id=${doc.id}: $e\n$st');
      return null;
    }
  }

  Map<String, dynamic> toMap() => {
        'reviewKey': reviewKey,
        'reviewType': reviewType.name,
        'reviewerName': reviewerName,
        // USER_TO_BUSINESS는 reviewerId 저장 안 함
        if (reviewType == ReviewType.ADMIN_TO_USER && reviewerId != null)
          'reviewerId': reviewerId,
        'businessId': businessId,
        'businessName': businessName,
        'targetUserId': targetUserId,
        'targetUserName': targetUserName,
        'targetUserGender': targetUserGender,
        'targetUserAge': targetUserAge,
        'reviewYear': reviewYear,
        'reviewMonth': reviewMonth,
        'workDaysInMonth': workDaysInMonth,
        'normalAttendanceDays': normalAttendanceDays,
        'lateDays': lateDays,
        'rating': rating,
        'wouldRehire': wouldRehire,
        'positiveTags': positiveTags,
        'improvementTags': improvementTags,
        'comment': comment,
        'isPublished': isPublished,
        // publishAt은 CF에서 설정 — 클라이언트는 null
        'publishAt': null,
        'requestId': requestId,
        'createdAt': FieldValue.serverTimestamp(),
      };

  // ─── 헬퍼 ───────────────────────────────────────────────────

  String get ratingStars => '⭐' * rating + '☆' * (5 - rating);

  String get ratingText => switch (rating) {
        5 => '최고',
        4 => '좋음',
        3 => '보통',
        2 => '미흡',
        1 => '불량',
        _ => '',
      };

  String get periodText => '$reviewYear년 $reviewMonth월';

  double get attendanceRate {
    if (workDaysInMonth == 0) return 0;
    return (normalAttendanceDays / workDaysInMonth) * 100;
  }

  String get publishStatusText {
    if (isPublished) return '공개됨';
    if (publishAt == null) return '공개 대기';
    final diff = publishAt!.difference(DateTime.now());
    if (diff.inDays > 0) return '${diff.inDays}일 후 공개';
    if (diff.inHours > 0) return '${diff.inHours}시간 후 공개';
    return '곧 공개';
  }

  // ─── 키 생성 ─────────────────────────────────────────────────
  static String generateKeyForUser({
    required String businessId,
    required String targetUserId,
    required int year,
    required int month,
  }) =>
      '${businessId}_${targetUserId}_${year}_$month';

  static String generateKeyForBusiness({
    required String businessId,
    required String reviewerId,
    required int year,
    required int month,
  }) =>
      '${businessId}_${reviewerId}_${year}_${month}_biz';

  MonthlyReviewModel copyWith({
    String? id,
    String? reviewKey,
    ReviewType? reviewType,
    String? reviewerName,
    String? reviewerId,
    String? businessId,
    String? businessName,
    String? targetUserId,
    String? targetUserName,
    String? targetUserGender,
    int? targetUserAge,
    int? reviewYear,
    int? reviewMonth,
    int? workDaysInMonth,
    int? normalAttendanceDays,
    int? lateDays,
    int? rating,
    bool? wouldRehire,
    List<String>? positiveTags,
    List<String>? improvementTags,
    String? comment,
    bool? isPublished,
    DateTime? publishAt,
    DateTime? publishedAt,
    String? requestId,
    String? businessResponse,
    DateTime? businessRespondedAt,
    DateTime? createdAt,
  }) =>
      MonthlyReviewModel(
        id: id ?? this.id,
        reviewKey: reviewKey ?? this.reviewKey,
        reviewType: reviewType ?? this.reviewType,
        reviewerName: reviewerName ?? this.reviewerName,
        reviewerId: reviewerId ?? this.reviewerId,
        businessId: businessId ?? this.businessId,
        businessName: businessName ?? this.businessName,
        targetUserId: targetUserId ?? this.targetUserId,
        targetUserName: targetUserName ?? this.targetUserName,
        targetUserGender: targetUserGender ?? this.targetUserGender,
        targetUserAge: targetUserAge ?? this.targetUserAge,
        reviewYear: reviewYear ?? this.reviewYear,
        reviewMonth: reviewMonth ?? this.reviewMonth,
        workDaysInMonth: workDaysInMonth ?? this.workDaysInMonth,
        normalAttendanceDays: normalAttendanceDays ?? this.normalAttendanceDays,
        lateDays: lateDays ?? this.lateDays,
        rating: rating ?? this.rating,
        wouldRehire: wouldRehire ?? this.wouldRehire,
        positiveTags: positiveTags ?? this.positiveTags,
        improvementTags: improvementTags ?? this.improvementTags,
        comment: comment ?? this.comment,
        isPublished: isPublished ?? this.isPublished,
        publishAt: publishAt ?? this.publishAt,
        publishedAt: publishedAt ?? this.publishedAt,
        requestId: requestId ?? this.requestId,
        businessResponse: businessResponse ?? this.businessResponse,
        businessRespondedAt: businessRespondedAt ?? this.businessRespondedAt,
        createdAt: createdAt ?? this.createdAt,
      );
}
