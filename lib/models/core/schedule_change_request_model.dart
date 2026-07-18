import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 스케줄 변경 요청 타입
enum RequestType {
  LEAVE,        // 지원자 → 관리자: 휴무 요청
  NO_WORK,      // 관리자 → 지원자: 미출근 요청
  EXTRA_WORK,   // 관리자 → 지원자: 추가 근무 요청
  CANCEL_LEAVE,    // 지원자 → 관리자: 휴무 취소 요청
  CANCEL_EXTRA,    // 지원자 → 관리자: 추가근무 취소 요청
}

/// 요청 상태
enum RequestStatus {
  PENDING,   // 대기중
  APPROVED,  // 승인됨
  REJECTED,  // 거절됨
  CANCELED,  // 취소됨
}

/// 요청자 타입
enum RequesterType {
  APPLICANT,  // 지원자
  ADMIN,      // 관리자
}

/// 스케줄 변경 요청 모델
class ScheduleChangeRequestModel {
  final String id;
  final String businessId;           // 사업장 ID
  final String applicationId;        // 지원서 ID
  final String applicantUid;         // 지원자 UID
  final String applicantName;        // 지원자 이름
  final DateTime targetDate;         // 대상 날짜

  // 요청 정보
  final RequestType requestType;     // 요청 타입
  final RequesterType requestedBy;   // 요청자 타입
  final String requestedByUid;       // 요청자 UID
  final DateTime requestedAt;        // 요청 시각
  final String? reason;              // 요청 사유

  // 응답 정보
  final RequestStatus status;        // 상태
  final String? respondedByUid;      // 응답자 UID
  final DateTime? respondedAt;       // 응답 시각
  final String? rejectReason;        // 거절 사유

  // 급여 영향
  final bool affectsSalary;          // 급여 영향 여부
  final int? wageAmount;             // 급여 금액

  ScheduleChangeRequestModel({
    required this.id,
    required this.businessId,
    required this.applicationId,
    required this.applicantUid,
    required this.applicantName,
    required this.targetDate,
    required this.requestType,
    required this.requestedBy,
    required this.requestedByUid,
    required this.requestedAt,
    this.reason,
    this.status = RequestStatus.PENDING,
    this.respondedByUid,
    this.respondedAt,
    this.rejectReason,
    this.affectsSalary = true,
    this.wageAmount,
  });

  // ── 편의 메서드 ──────────────────────────────────────────────

  /// 대기중인가?
  bool get isPending => status == RequestStatus.PENDING;

  /// 승인됨?
  bool get isApproved => status == RequestStatus.APPROVED;

  /// 거절됨?
  bool get isRejected => status == RequestStatus.REJECTED;

  /// 취소됨?
  bool get isCanceled => status == RequestStatus.CANCELED;

  /// 휴무 요청?
  bool get isLeaveRequest => requestType == RequestType.LEAVE;

  /// 미출근 요청?
  bool get isNoWorkRequest => requestType == RequestType.NO_WORK;

  /// 추가 근무 요청?
  bool get isExtraWorkRequest => requestType == RequestType.EXTRA_WORK;

  /// 지원자가 요청?
  bool get isApplicantRequest => requestedBy == RequesterType.APPLICANT;

  /// 관리자가 요청?
  bool get isAdminRequest => requestedBy == RequesterType.ADMIN;

  /// 요청 타입 한글
  String get requestTypeLabel {
    switch (requestType) {
      case RequestType.LEAVE:
        return '휴무 요청';
      case RequestType.NO_WORK:
        return '미출근 요청';
      case RequestType.EXTRA_WORK:
        return '추가 근무 요청';
      case RequestType.CANCEL_LEAVE:
        return '휴무 취소 요청';
      case RequestType.CANCEL_EXTRA:
        return '추가근무 취소 요청';
    }
  }

  /// 상태 한글
  String get statusLabel {
    switch (status) {
      case RequestStatus.PENDING:
        return '대기중';
      case RequestStatus.APPROVED:
        return '승인됨';
      case RequestStatus.REJECTED:
        return '거절됨';
      case RequestStatus.CANCELED:
        return '취소됨';
    }
  }

  // ── Firestore 변환 ───────────────────────────────────────────

  static ScheduleChangeRequestModel? tryFromMap(Map<String, dynamic> map, String id) {
    try {
      return ScheduleChangeRequestModel.fromMap(map, id);
    } catch (e) {
      debugPrint('[ScheduleChangeRequestModel] tryFromMap 실패 id=$id: $e');
      return null;
    }
  }

  factory ScheduleChangeRequestModel.fromMap(Map<String, dynamic> map, String id) {
    final targetDate = (map['targetDate'] as Timestamp?)?.toDate().toLocal();
    if (targetDate == null) {
      throw ArgumentError('ScheduleChangeRequestModel: targetDate is missing (id=$id)');
    }
    final requestedAt = (map['requestedAt'] as Timestamp?)?.toDate().toLocal();
    if (requestedAt == null) {
      throw ArgumentError('ScheduleChangeRequestModel: requestedAt is missing (id=$id)');
    }
    return ScheduleChangeRequestModel(
      id: id,
      businessId: map['businessId'] ?? '',
      applicationId: map['applicationId'] ?? '',
      applicantUid: map['applicantUid'] ?? '',
      applicantName: map['applicantName'] ?? '',
      targetDate: targetDate,
      requestType: _requestTypeFromString(map['requestType'] as String? ?? 'LEAVE'),
      requestedBy: _requesterTypeFromString(map['requestedBy'] as String? ?? 'APPLICANT'),
      requestedByUid: map['requestedByUid'] ?? '',
      requestedAt: requestedAt,
      reason: map['reason'],
      status: _statusFromString(map['status'] as String? ?? 'PENDING'),
      respondedByUid: map['respondedByUid'],
      respondedAt: (map['respondedAt'] as Timestamp?)?.toDate().toLocal(),
      rejectReason: map['rejectReason'],
      affectsSalary: map['affectsSalary'] ?? true,
      wageAmount: (map['wageAmount'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'businessId': businessId,
      'applicationId': applicationId,
      'applicantUid': applicantUid,
      'applicantName': applicantName,
      'targetDate': Timestamp.fromDate(targetDate),
      'requestType': _requestTypeToString(requestType),
      'requestedBy': _requesterTypeToString(requestedBy),
      'requestedByUid': requestedByUid,
      'requestedAt': Timestamp.fromDate(requestedAt),
      'reason': reason,
      'status': _statusToString(status),
      'respondedByUid': respondedByUid,
      'respondedAt': respondedAt != null
          ? Timestamp.fromDate(respondedAt!)
          : null,
      'rejectReason': rejectReason,
      'affectsSalary': affectsSalary,
      'wageAmount': wageAmount,
    };
  }

  // ── Enum 변환 헬퍼 ───────────────────────────────────────────

  static RequestType _requestTypeFromString(String str) {
    switch (str) {
      case 'LEAVE': return RequestType.LEAVE;
      case 'NO_WORK': return RequestType.NO_WORK;
      case 'EXTRA_WORK': return RequestType.EXTRA_WORK;
      case 'CANCEL_LEAVE': return RequestType.CANCEL_LEAVE;
      case 'CANCEL_EXTRA': return RequestType.CANCEL_EXTRA;
      default: return RequestType.LEAVE;
    }
  }

  static String _requestTypeToString(RequestType type) {
    switch (type) {
      case RequestType.LEAVE: return 'LEAVE';
      case RequestType.NO_WORK: return 'NO_WORK';
      case RequestType.EXTRA_WORK: return 'EXTRA_WORK';
      case RequestType.CANCEL_LEAVE: return 'CANCEL_LEAVE';
      case RequestType.CANCEL_EXTRA: return 'CANCEL_EXTRA';
    }
  }

  static RequestStatus _statusFromString(String str) {
    switch (str) {
      case 'PENDING': return RequestStatus.PENDING;
      case 'APPROVED': return RequestStatus.APPROVED;
      case 'REJECTED': return RequestStatus.REJECTED;
      case 'CANCELED': return RequestStatus.CANCELED;
      default: return RequestStatus.PENDING;
    }
  }

  static String _statusToString(RequestStatus status) {
    switch (status) {
      case RequestStatus.PENDING: return 'PENDING';
      case RequestStatus.APPROVED: return 'APPROVED';
      case RequestStatus.REJECTED: return 'REJECTED';
      case RequestStatus.CANCELED: return 'CANCELED';
    }
  }

  static RequesterType _requesterTypeFromString(String str) {
    switch (str) {
      case 'APPLICANT': return RequesterType.APPLICANT;
      case 'ADMIN': return RequesterType.ADMIN;
      default: return RequesterType.APPLICANT;
    }
  }

  static String _requesterTypeToString(RequesterType type) {
    switch (type) {
      case RequesterType.APPLICANT: return 'APPLICANT';
      case RequesterType.ADMIN: return 'ADMIN';
    }
  }

  // ── copyWith ─────────────────────────────────────────────────

  ScheduleChangeRequestModel copyWith({
    String? id,
    String? businessId,
    String? applicationId,
    String? applicantUid,
    String? applicantName,
    DateTime? targetDate,
    RequestType? requestType,
    RequesterType? requestedBy,
    String? requestedByUid,
    DateTime? requestedAt,
    String? reason,
    RequestStatus? status,
    String? respondedByUid,
    DateTime? respondedAt,
    String? rejectReason,
    bool? affectsSalary,
    int? wageAmount,
  }) {
    return ScheduleChangeRequestModel(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      applicationId: applicationId ?? this.applicationId,
      applicantUid: applicantUid ?? this.applicantUid,
      applicantName: applicantName ?? this.applicantName,
      targetDate: targetDate ?? this.targetDate,
      requestType: requestType ?? this.requestType,
      requestedBy: requestedBy ?? this.requestedBy,
      requestedByUid: requestedByUid ?? this.requestedByUid,
      requestedAt: requestedAt ?? this.requestedAt,
      reason: reason ?? this.reason,
      status: status ?? this.status,
      respondedByUid: respondedByUid ?? this.respondedByUid,
      respondedAt: respondedAt ?? this.respondedAt,
      rejectReason: rejectReason ?? this.rejectReason,
      affectsSalary: affectsSalary ?? this.affectsSalary,
      wageAmount: wageAmount ?? this.wageAmount,
    );
  }
}
