import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 근무 리뷰 모델
/// 관리자가 근무자에 대해 작성하는 평가
class ReviewModel {
  final String id;
  final String applicationId;       // 관련 지원서 ID
  final String reviewerId;          // 리뷰 작성자 (관리자 UID)
  final String reviewerName;        // 작성자 이름
  final String targetUserId;        // 리뷰 대상 (근무자 UID)
  final String businessId;          // 사업장 ID
  final String businessName;        // 사업장 이름
  final String workType;            // 업무 유형
  final DateTime workDate;          // 근무 날짜
  final int rating;                 // 평점 (1~5)
  final String? comment;            // 코멘트 (선택)
  final bool wouldRehire;           // 재고용 의사
  final DateTime createdAt;         // 작성일
  final DateTime? updatedAt;        // 수정일

  ReviewModel({
    required this.id,
    required this.applicationId,
    required this.reviewerId,
    required this.reviewerName,
    required this.targetUserId,
    required this.businessId,
    required this.businessName,
    required this.workType,
    required this.workDate,
    required this.rating,
    this.comment,
    this.wouldRehire = true,
    required this.createdAt,
    this.updatedAt,
  });

  /// Firestore에서 변환
  factory ReviewModel.fromMap(Map<String, dynamic> map, String id) {
    final workDate = (map['workDate'] as Timestamp?)?.toDate().toLocal();
    if (workDate == null) {
      throw ArgumentError('ReviewModel: workDate is missing (id=$id)');
    }
    final createdAt = (map['createdAt'] as Timestamp?)?.toDate().toLocal();
    if (createdAt == null) {
      throw ArgumentError('ReviewModel: createdAt is missing (id=$id)');
    }
    return ReviewModel(
      id: id,
      applicationId: map['applicationId'] ?? '',
      reviewerId: map['reviewerId'] ?? '',
      reviewerName: map['reviewerName'] ?? '',
      targetUserId: map['targetUserId'] ?? '',
      businessId: map['businessId'] ?? '',
      businessName: map['businessName'] ?? '',
      workType: map['workType'] ?? '',
      workDate: workDate,
      rating: ((map['rating'] as num?)?.toInt() ?? 0).clamp(0, 5),
      comment: map['comment'],
      wouldRehire: map['wouldRehire'] ?? true,
      createdAt: createdAt,
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate().toLocal(),
    );
  }

  factory ReviewModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) {
      throw ArgumentError('ReviewModel: document ${doc.id} has no data');
    }
    return ReviewModel.fromMap(raw as Map<String, dynamic>, doc.id);
  }

  // [SCHEMA-09] 역직렬화 실패 격리 — 손상 문서 1건이 목록 전체 크래시 방지
  static ReviewModel? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return ReviewModel.fromFirestore(doc);
    } catch (e, st) {
      debugPrint('[ReviewModel] 역직렬화 실패 id=${doc.id}: $e\n$st');
      return null;
    }
  }

  /// Firestore에 저장
  Map<String, dynamic> toMap() {
    return {
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
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  /// 별점 문자열 (⭐⭐⭐⭐☆)
  String get ratingStars {
    return '⭐' * rating + '☆' * (5 - rating);
  }

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
}
