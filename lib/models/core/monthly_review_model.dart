// lib/models/core/monthly_review_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// 리뷰 유형
enum ReviewType {
  ADMIN_TO_USER,    // 관리자 → 지원자
  USER_TO_BUSINESS, // 지원자 → 사업장
}

/// 월별 리뷰 모델
/// 
/// 정책:
/// - 사업장 + 지원자 + 년월 단위로 1회만 작성 가능
/// - 작성 후 수정 불가
/// - 작성 후 3일 뒤 공개
class MonthlyReviewModel {
  final String id;
  
  /// 중복 방지 키 (businessId_targetUserId_year_month 또는 businessId_reviewerId_year_month)
  final String reviewKey;
  
  /// 리뷰 유형
  final ReviewType reviewType;
  
  // ═══════════════════════════════════════════════════════════
  // 작성자/대상 정보
  // ═══════════════════════════════════════════════════════════
  
  /// 리뷰 작성자 UID
  final String reviewerId;
  
  /// 리뷰 작성자 이름
  final String reviewerName;
  
  /// 사업장 ID
  final String businessId;
  
  /// 사업장 이름
  final String businessName;
  
  /// 리뷰 대상 사용자 UID (ADMIN_TO_USER인 경우)
  final String? targetUserId;
  
  /// 리뷰 대상 사용자 이름 (ADMIN_TO_USER인 경우)
  final String? targetUserName;
  
  // ═══════════════════════════════════════════════════════════
  // 기간 정보
  // ═══════════════════════════════════════════════════════════
  
  /// 리뷰 대상 년도
  final int reviewYear;
  
  /// 리뷰 대상 월 (1~12)
  final int reviewMonth;
  
  /// 해당 월 근무 일수
  final int workDaysInMonth;
  
  /// 해당 월 정상 출근 일수
  final int normalAttendanceDays;
  
  /// 해당 월 지각 횟수
  final int lateDays;
  
  // ═══════════════════════════════════════════════════════════
  // 평가 내용
  // ═══════════════════════════════════════════════════════════
  
  /// 평점 (1~5)
  final int rating;
  
  /// 재고용 의사 (ADMIN_TO_USER만 해당, 관리자만 열람)
  final bool? wouldRehire;
  
  /// 긍정 태그 목록
  final List<String> positiveTags;
  
  /// 개선 태그 목록
  final List<String> improvementTags;
  
  /// 상세 코멘트 (관리자끼리만 공유, 지원자 비공개)
  final String? comment;
  
  // ═══════════════════════════════════════════════════════════
  // 공개 상태
  // ═══════════════════════════════════════════════════════════
  
  /// 공개 여부
  final bool isPublished;
  
  /// 공개 예정일 (작성일 + 3일)
  final DateTime publishAt;
  
  /// 작성일
  final DateTime createdAt;

  MonthlyReviewModel({
    required this.id,
    required this.reviewKey,
    required this.reviewType,
    required this.reviewerId,
    required this.reviewerName,
    required this.businessId,
    required this.businessName,
    this.targetUserId,
    this.targetUserName,
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
    required this.publishAt,
    required this.createdAt,
  });

  // ═══════════════════════════════════════════════════════════
  // Firestore 변환
  // ═══════════════════════════════════════════════════════════

  factory MonthlyReviewModel.fromMap(Map<String, dynamic> map, String id) {
    return MonthlyReviewModel(
      id: id,
      reviewKey: map['reviewKey'] ?? '',
      reviewType: ReviewType.values.firstWhere(
        (e) => e.name == map['reviewType'],
        orElse: () => ReviewType.ADMIN_TO_USER,
      ),
      reviewerId: map['reviewerId'] ?? '',
      reviewerName: map['reviewerName'] ?? '',
      businessId: map['businessId'] ?? '',
      businessName: map['businessName'] ?? '',
      targetUserId: map['targetUserId'],
      targetUserName: map['targetUserName'],
      reviewYear: map['reviewYear'] ?? DateTime.now().year,
      reviewMonth: map['reviewMonth'] ?? DateTime.now().month,
      workDaysInMonth: map['workDaysInMonth'] ?? 0,
      normalAttendanceDays: map['normalAttendanceDays'] ?? 0,
      lateDays: map['lateDays'] ?? 0,
      rating: map['rating'] ?? 0,
      wouldRehire: map['wouldRehire'],
      positiveTags: List<String>.from(map['positiveTags'] ?? []),
      improvementTags: List<String>.from(map['improvementTags'] ?? []),
      comment: map['comment'],
      isPublished: map['isPublished'] ?? false,
      publishAt: (map['publishAt'] as Timestamp?)?.toDate().toLocal() ?? DateTime.now(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate().toLocal() ?? DateTime.now(),
    );
  }

  factory MonthlyReviewModel.fromFirestore(DocumentSnapshot doc) {
    return MonthlyReviewModel.fromMap(
      doc.data() as Map<String, dynamic>,
      doc.id,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'reviewKey': reviewKey,
      'reviewType': reviewType.name,
      'reviewerId': reviewerId,
      'reviewerName': reviewerName,
      'businessId': businessId,
      'businessName': businessName,
      'targetUserId': targetUserId,
      'targetUserName': targetUserName,
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
      'publishAt': Timestamp.fromDate(publishAt),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  // ═══════════════════════════════════════════════════════════
  // 헬퍼 메서드
  // ═══════════════════════════════════════════════════════════

  /// 리뷰 키 생성 (관리자 → 지원자)
  static String generateKeyForUser({
    required String businessId,
    required String targetUserId,
    required int year,
    required int month,
  }) {
    return '${businessId}_${targetUserId}_${year}_$month';
  }

  /// 리뷰 키 생성 (지원자 → 사업장)
  static String generateKeyForBusiness({
    required String businessId,
    required String reviewerId,
    required int year,
    required int month,
  }) {
    return '${businessId}_${reviewerId}_${year}_${month}_biz';
  }

  /// 별점 문자열
  String get ratingStars => '⭐' * rating + '☆' * (5 - rating);

  /// 평점 텍스트
  String get ratingText {
    switch (rating) {
      case 5: return '최고';
      case 4: return '좋음';
      case 3: return '보통';
      case 2: return '미흡';
      case 1: return '불량';
      default: return '';
    }
  }

  /// 기간 문자열 (예: "2024년 12월")
  String get periodText => '$reviewYear년 $reviewMonth월';

  /// 공개까지 남은 시간
  Duration get timeUntilPublish => publishAt.difference(DateTime.now());

  /// 공개 가능 여부
  bool get canPublish => DateTime.now().isAfter(publishAt);

  /// 출근율 계산
  double get attendanceRate {
    if (workDaysInMonth == 0) return 0;
    return (normalAttendanceDays / workDaysInMonth) * 100;
  }

  /// 공개 상태 텍스트
  String get publishStatusText {
    if (isPublished) return '공개됨';
    final days = timeUntilPublish.inDays;
    final hours = timeUntilPublish.inHours % 24;
    if (days > 0) return '$days일 후 공개';
    if (hours > 0) return '$hours시간 후 공개';
    return '곧 공개';
  }

  // ═══════════════════════════════════════════════════════════
  // copyWith
  // ═══════════════════════════════════════════════════════════

  MonthlyReviewModel copyWith({
    String? id,
    String? reviewKey,
    ReviewType? reviewType,
    String? reviewerId,
    String? reviewerName,
    String? businessId,
    String? businessName,
    String? targetUserId,
    String? targetUserName,
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
    DateTime? createdAt,
  }) {
    return MonthlyReviewModel(
      id: id ?? this.id,
      reviewKey: reviewKey ?? this.reviewKey,
      reviewType: reviewType ?? this.reviewType,
      reviewerId: reviewerId ?? this.reviewerId,
      reviewerName: reviewerName ?? this.reviewerName,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      targetUserId: targetUserId ?? this.targetUserId,
      targetUserName: targetUserName ?? this.targetUserName,
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
      createdAt: createdAt ?? this.createdAt,
    );
  }
}