import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 신분증 열람 요청 사유
enum IdCardAccessReason {
  incomeTax,        // 소득세 신고
  laborContract,    // 근로계약서 작성
  insurance,        // 4대보험 신고
  identityVerify,   // 본인 확인
  other,            // 기타 (직접 입력)
}

/// 신분증 열람 요청 상태
enum IdCardAccessStatus {
  pending,   // 대기 중
  approved,  // 승인됨
  rejected,  // 거절됨
  expired,   // 만료됨
  revoked,   // 폐기됨 (확정 취소 / TO 삭제 / Slot 삭제 시 자동 폐기)
}

/// 신분증 열람 요청 모델
class IdCardAccessRequestModel {
  final String id;
  final String requesterId;           // 요청자 (관리자 UID)
  final String requesterName;         // 요청자 이름
  final String requesterBusinessId;   // 사업장 ID
  final String requesterBusinessName; // 사업장 이름
  final String targetUserId;          // 대상자 (근무자 UID)
  final String targetUserName;        // 대상자 이름
  final IdCardAccessReason reason;    // 요청 사유
  final String? customReason;         // 기타 사유 (직접 입력)
  final IdCardAccessStatus status;    // 요청 상태
  final DateTime requestedAt;         // 요청 시각
  final DateTime? respondedAt;        // 응답 시각
  final DateTime? expiresAt;          // 만료 시각 (승인 후 7일)
  final String? applicationId;        // 관련 지원서 ID (선택)
  final String? rejectionReason;      // 거절 사유

  IdCardAccessRequestModel({
    required this.id,
    required this.requesterId,
    required this.requesterName,
    required this.requesterBusinessId,
    required this.requesterBusinessName,
    required this.targetUserId,
    required this.targetUserName,
    required this.reason,
    this.customReason,
    required this.status,
    required this.requestedAt,
    this.respondedAt,
    this.expiresAt,
    this.applicationId,
    this.rejectionReason,
  });

  /// Firestore에서 변환
  factory IdCardAccessRequestModel.fromMap(Map<String, dynamic> map, String id) {
    return IdCardAccessRequestModel(
      id: id,
      requesterId: map['requesterId'] ?? '',
      requesterName: map['requesterName'] ?? '',
      requesterBusinessId: map['requesterBusinessId'] ?? '',
      requesterBusinessName: map['requesterBusinessName'] ?? '',
      targetUserId: map['targetUserId'] ?? '',
      targetUserName: map['targetUserName'] ?? '',
      reason: _reasonFromString(map['reason'] ?? 'other'),
      customReason: map['customReason'],
      status: _statusFromString(map['status'] ?? 'pending'),
      requestedAt: map['requestedAt'] != null
          ? (map['requestedAt'] as Timestamp).toDate().toLocal()
          : (throw ArgumentError('IdCardAccessRequestModel: requestedAt 필드 누락 (id: $id)')),
      respondedAt: (map['respondedAt'] as Timestamp?)?.toDate().toLocal(),
      expiresAt: (map['expiresAt'] as Timestamp?)?.toDate().toLocal(),
      applicationId: map['applicationId'],
      rejectionReason: map['rejectionReason'],
    );
  }

  factory IdCardAccessRequestModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) {
      throw ArgumentError('IdCardAccessRequestModel.fromFirestore: 문서 데이터 없음 (id: ${doc.id})');
    }
    return IdCardAccessRequestModel.fromMap(raw as Map<String, dynamic>, doc.id);
  }

  static IdCardAccessRequestModel? tryFromMap(Map<String, dynamic> map, String id) {
    try {
      return IdCardAccessRequestModel.fromMap(map, id);
    } catch (e, st) {
      debugPrint('[IdCardAccessRequestModel] tryFromMap 실패 id=$id: $e\n$st');
      return null;
    }
  }

  // [SCHEMA-09] 역직렬화 실패 격리 — 손상 문서 1건이 목록 전체 크래시 방지
  static IdCardAccessRequestModel? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return IdCardAccessRequestModel.fromFirestore(doc);
    } catch (e, st) {
      debugPrint('[IdCardAccessRequestModel] 역직렬화 실패 id=${doc.id}: $e\n$st');
      return null;
    }
  }

  /// Firestore에 저장
  Map<String, dynamic> toMap() {
    return {
      'requesterId': requesterId,
      'requesterName': requesterName,
      'requesterBusinessId': requesterBusinessId,
      'requesterBusinessName': requesterBusinessName,
      'targetUserId': targetUserId,
      'targetUserName': targetUserName,
      'reason': _reasonToString(reason),
      'customReason': customReason,
      'status': _statusToString(status),
      'requestedAt': Timestamp.fromDate(requestedAt),
      'respondedAt': respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'applicationId': applicationId,
      'rejectionReason': rejectionReason,
    };
  }

  // ── Getter ────────────────────────────────────────────────

  /// 승인되었고 아직 유효한지
  bool get isValidAccess {
    if (status != IdCardAccessStatus.approved) return false;
    if (expiresAt == null) return false;
    return DateTime.now().isBefore(expiresAt!);
  }

  /// 만료되었는지
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// 대기 중인지
  bool get isPending => status == IdCardAccessStatus.pending;

  /// 요청 사유 텍스트
  String get reasonText {
    switch (reason) {
      case IdCardAccessReason.incomeTax:
        return '소득세 신고';
      case IdCardAccessReason.laborContract:
        return '근로계약서 작성';
      case IdCardAccessReason.insurance:
        return '4대보험 신고';
      case IdCardAccessReason.identityVerify:
        return '본인 확인';
      case IdCardAccessReason.other:
        return customReason ?? '기타';
    }
  }

  /// 상태 텍스트
  String get statusText {
    switch (status) {
      case IdCardAccessStatus.pending:
        return '승인 대기';
      case IdCardAccessStatus.approved:
        return isExpired ? '만료됨' : '승인됨';
      case IdCardAccessStatus.rejected:
        return '거절됨';
      case IdCardAccessStatus.expired:
        return '만료됨';
      case IdCardAccessStatus.revoked:
        return '열람 권한 폐기됨';
    }
  }

  /// 남은 유효 기간 (일)
  int? get remainingDays {
    if (expiresAt == null) return null;
    final diff = expiresAt!.difference(DateTime.now()).inDays;
    return diff > 0 ? diff : 0;
  }

  // ── Static Helper ─────────────────────────────────────────

  /// 요청 사유 목록 (선택용)
  static List<Map<String, dynamic>> get reasonOptions => [
    {'value': IdCardAccessReason.incomeTax, 'label': '소득세 신고'},
    {'value': IdCardAccessReason.laborContract, 'label': '근로계약서 작성'},
    {'value': IdCardAccessReason.insurance, 'label': '4대보험 신고'},
    {'value': IdCardAccessReason.identityVerify, 'label': '본인 확인'},
    {'value': IdCardAccessReason.other, 'label': '기타 (직접 입력)'},
  ];

  static IdCardAccessReason _reasonFromString(String value) {
    switch (value) {
      case 'incomeTax': return IdCardAccessReason.incomeTax;
      case 'laborContract': return IdCardAccessReason.laborContract;
      case 'insurance': return IdCardAccessReason.insurance;
      case 'identityVerify': return IdCardAccessReason.identityVerify;
      default: return IdCardAccessReason.other;
    }
  }

  static String _reasonToString(IdCardAccessReason reason) {
    switch (reason) {
      case IdCardAccessReason.incomeTax: return 'incomeTax';
      case IdCardAccessReason.laborContract: return 'laborContract';
      case IdCardAccessReason.insurance: return 'insurance';
      case IdCardAccessReason.identityVerify: return 'identityVerify';
      case IdCardAccessReason.other: return 'other';
    }
  }

  static IdCardAccessStatus _statusFromString(String value) {
    switch (value) {
      case 'approved': return IdCardAccessStatus.approved;
      case 'rejected': return IdCardAccessStatus.rejected;
      case 'expired': return IdCardAccessStatus.expired;
      case 'revoked': return IdCardAccessStatus.revoked;
      // 알 수 없는 상태는 rejected로 fallback — pending 오표시 방지
      default: return IdCardAccessStatus.pending;
    }
  }

  static String _statusToString(IdCardAccessStatus status) {
    switch (status) {
      case IdCardAccessStatus.pending: return 'pending';
      case IdCardAccessStatus.approved: return 'approved';
      case IdCardAccessStatus.rejected: return 'rejected';
      case IdCardAccessStatus.expired: return 'expired';
      case IdCardAccessStatus.revoked: return 'revoked';
    }
  }
}