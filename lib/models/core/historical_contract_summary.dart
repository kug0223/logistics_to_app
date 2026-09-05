import '../../utils/firestore_helper.dart';

/// 보관된 계약서 목록(페이지네이션) 아이템 모델.
/// callableGetHistoricalContracts 응답의 contracts[] 요소에 대응.
class HistoricalContractSummary {
  final String contractId;
  final String? businessId;
  final String? businessName;
  final String? workerId;
  final String? workerName;

  /// 원시 status 문자열 — CF 응답값을 그대로 보존.
  /// 표시용은 [displayStatus]를 사용한다.
  final String? status;

  final bool? isLongTerm;
  final DateTime? createdAt;
  final DateTime? employerSignedAt;
  final DateTime? workerSignedAt;
  final DateTime? contractVoidedAt;
  final String? voidReason;

  /// CF가 pdfUrl 존재 여부로 계산한 값. null이면 false로 취급.
  final bool pdfAvailable;

  const HistoricalContractSummary({
    required this.contractId,
    this.businessId,
    this.businessName,
    this.workerId,
    this.workerName,
    this.status,
    this.isLongTerm,
    this.createdAt,
    this.employerSignedAt,
    this.workerSignedAt,
    this.contractVoidedAt,
    this.voidReason,
    required this.pdfAvailable,
  });

  factory HistoricalContractSummary.fromMap(Map<String, dynamic> map) {
    return HistoricalContractSummary(
      contractId: map['contractId'] as String? ?? '',
      businessId: map['businessId'] as String?,
      businessName: map['businessName'] as String?,
      workerId: map['workerId'] as String?,
      workerName: map['workerName'] as String?,
      status: map['status'] as String?,
      isLongTerm: map['isLongTerm'] as bool?,
      createdAt: parseTimestampNullable(map['createdAt']),
      employerSignedAt: parseTimestampNullable(map['employerSignedAt']),
      workerSignedAt: parseTimestampNullable(map['workerSignedAt']),
      contractVoidedAt: parseTimestampNullable(map['contractVoidedAt']),
      voidReason: map['voidReason'] as String?,
      pdfAvailable: map['pdfAvailable'] as bool? ?? false,
    );
  }

  /// 계약 상태 표시 문자열.
  /// 알 수 없는 값(null·미래 신규 상태 포함)은 "보존됨"으로 표시한다.
  /// 원시 값은 [status] 필드에 그대로 보존된다.
  String get displayStatus {
    switch (status) {
      case 'completed':
        return '계약 완료';
      case 'voided':
        return '계약 무효화';
      case 'pending_employer':
      case 'pending_worker':
        return '서명 대기';
      default:
        return '보존됨';
    }
  }
}
