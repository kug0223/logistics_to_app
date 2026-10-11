import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../utils/firestore_helper.dart';

/// 리뷰 요청 상태
enum ReviewPartyStatus {
  pending,   // 미작성
  submitted, // 작성 완료
}

/// 양방향 리뷰 페어 추적 모델
///
/// Firestore: review_requests/{requestKey}
/// requestKey = businessId_workerId_year_month
///
/// 공개 규칙:
///   - 양쪽 모두 submitted → 즉시 동시 공개
///   - deadline 경과 → submitted된 쪽만 자동 공개
class ReviewRequestModel {
  final String id; // == requestKey
  final String requestKey;

  final String businessId;
  final String businessName;
  final String workerId;
  final String workerName;

  final int reviewYear;
  final int reviewMonth;

  /// 근무 완료일 기준 +14일 (CF 서버에서 설정)
  final DateTime deadline;

  final ReviewPartyStatus adminStatus;
  final ReviewPartyStatus workerStatus;

  final String? adminReviewId;
  final String? workerReviewId;

  final bool isPublished;
  final DateTime? publishedAt;
  final DateTime createdAt;

  /// [R7-RER.2 §3B] 자격 보류 시각 (서버 전용 쓰기)
  ///
  /// 리뷰 요청은 발급 시점의 근무 자격을 담은 토큰이다. 발급 뒤 관리자가
  /// 급여 마감을 취소해 그 달의 마지막 확정 근무가 사라지면 서버가 이 값을
  /// 세우고, Firestore Rules 가 미제출 리뷰 생성을 막는다.
  /// 급여가 다시 확정되면 서버가 이 값을 지운다 — deadline 은 그대로다.
  final DateTime? eligibilitySuspendedAt;

  const ReviewRequestModel({
    required this.id,
    required this.requestKey,
    required this.businessId,
    required this.businessName,
    required this.workerId,
    required this.workerName,
    required this.reviewYear,
    required this.reviewMonth,
    required this.deadline,
    required this.adminStatus,
    required this.workerStatus,
    this.adminReviewId,
    this.workerReviewId,
    required this.isPublished,
    this.publishedAt,
    required this.createdAt,
    this.eligibilitySuspendedAt,
  });

  static String generateKey({
    required String businessId,
    required String workerId,
    required int year,
    required int month,
  }) =>
      '${businessId}_${workerId}_${year}_$month';

  factory ReviewRequestModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) {
      throw ArgumentError('ReviewRequestModel: document ${doc.id} has no data');
    }
    final data = raw as Map<String, dynamic>;
    final deadline = (data['deadline'] as Timestamp?)?.toDate().toLocal();
    if (deadline == null) {
      throw ArgumentError('ReviewRequestModel: deadline is missing (id=${doc.id})');
    }
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate().toLocal();
    if (createdAt == null) {
      throw ArgumentError('ReviewRequestModel: createdAt is missing (id=${doc.id})');
    }
    return ReviewRequestModel(
      id: doc.id,
      requestKey: data['requestKey'] ?? doc.id,
      businessId: data['businessId'] ?? '',
      businessName: data['businessName'] ?? '',
      workerId: data['workerId'] ?? '',
      workerName: data['workerName'] ?? '',
      reviewYear: (data['reviewYear'] as num?)?.toInt() ?? 0,
      reviewMonth: (data['reviewMonth'] as num?)?.toInt() ?? 0,
      deadline: deadline,
      adminStatus: _parseStatus(data['adminStatus']),
      workerStatus: _parseStatus(data['workerStatus']),
      adminReviewId: data['adminReviewId'],
      workerReviewId: data['workerReviewId'],
      isPublished: data['isPublished'] ?? false,
      publishedAt: (data['publishedAt'] as Timestamp?)?.toDate().toLocal(),
      createdAt: createdAt,
      eligibilitySuspendedAt:
          (data['eligibilitySuspendedAt'] as Timestamp?)?.toDate().toLocal(),
    );
  }

  // [SCHEMA-09] 역직렬화 실패 격리 — 손상 문서 1건이 목록 전체 크래시 방지
  static ReviewRequestModel? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return ReviewRequestModel.fromFirestore(doc);
    } catch (e, st) {
      debugPrint('[ReviewRequestModel] 역직렬화 실패 id=${doc.id}: $e\n$st');
      return null;
    }
  }

  /// CF callable 응답 데이터(serializeFirestoreData 직렬화)에서 변환.
  /// Timestamp 필드는 {_seconds, _nanoseconds} Map으로 전달된다.
  static ReviewRequestModel? tryFromMap(Map<String, dynamic> data, String docId) {
    try {
      return ReviewRequestModel(
        id: docId,
        requestKey: data['requestKey'] ?? docId,
        businessId: data['businessId'] ?? '',
        businessName: data['businessName'] ?? '',
        workerId: data['workerId'] ?? '',
        workerName: data['workerName'] ?? '',
        reviewYear: (data['reviewYear'] as num?)?.toInt() ?? 0,
        reviewMonth: (data['reviewMonth'] as num?)?.toInt() ?? 0,
        deadline: parseTimestamp(data['deadline']),
        adminStatus: _parseStatus(data['adminStatus']),
        workerStatus: _parseStatus(data['workerStatus']),
        adminReviewId: data['adminReviewId'],
        workerReviewId: data['workerReviewId'],
        isPublished: data['isPublished'] ?? false,
        publishedAt: parseTimestampNullable(data['publishedAt']),
        createdAt: parseTimestamp(data['createdAt']),
        eligibilitySuspendedAt:
            parseTimestampNullable(data['eligibilitySuspendedAt']),
      );
    } catch (e, st) {
      debugPrint('[ReviewRequestModel] tryFromMap 실패 id=$docId: $e\n$st');
      return null;
    }
  }

  // [R7-RER.2 §4] `eligibilitySuspendedAt` 은 **의도적으로 toMap 에 없다**.
  //   이 값은 서버(Admin SDK)만 쓰고, Firestore Rules 는 클라이언트 update 의
  //   affectedKeys 를 제출 필드로만 제한한다. toMap 으로 흘러나가면 보류를
  //   클라이언트가 지우는 모양의 쓰기가 만들어질 수 있다.
  Map<String, dynamic> toMap() => {
        'requestKey': requestKey,
        'businessId': businessId,
        'businessName': businessName,
        'workerId': workerId,
        'workerName': workerName,
        'reviewYear': reviewYear,
        'reviewMonth': reviewMonth,
        'deadline': Timestamp.fromDate(deadline),
        'adminStatus': adminStatus.name,
        'workerStatus': workerStatus.name,
        'adminReviewId': adminReviewId,
        'workerReviewId': workerReviewId,
        'isPublished': isPublished,
        'publishedAt': publishedAt != null ? Timestamp.fromDate(publishedAt!) : null,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  static ReviewPartyStatus _parseStatus(dynamic value) {
    if (value == 'submitted') return ReviewPartyStatus.submitted;
    return ReviewPartyStatus.pending;
  }

  bool get bothSubmitted =>
      adminStatus == ReviewPartyStatus.submitted &&
      workerStatus == ReviewPartyStatus.submitted;

  bool get isDeadlinePassed => DateTime.now().isAfter(deadline);

  /// [R7-RER.2 §3B·§5] 근무 정산이 다시 확인 중이어서 리뷰 작성이 보류된 상태.
  ///
  /// 영구 차단이 아니다 — 급여가 다시 확정되면 서버가 보류를 푼다.
  bool get isEligibilitySuspended => eligibilitySuspendedAt != null;

  bool get adminPending => adminStatus == ReviewPartyStatus.pending;
  bool get workerPending => workerStatus == ReviewPartyStatus.pending;

  String get periodText => '$reviewYear년 $reviewMonth월';
}
