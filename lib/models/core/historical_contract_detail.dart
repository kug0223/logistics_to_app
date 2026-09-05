import 'contract_template_model.dart';
import 'employment_contract_model.dart';
import '../../utils/firestore_helper.dart';

/// 보관된 계약서 슬롯 — applicationId 없는 5-필드 전용 모델.
/// ContractSlot(applicationId 포함)을 재사용하지 않는다.
class HistoricalContractSlot {
  final String? workDate;
  final String? startTime;
  final String? endTime;
  final int? wage;
  final String? wageType;

  const HistoricalContractSlot({
    this.workDate,
    this.startTime,
    this.endTime,
    this.wage,
    this.wageType,
  });

  factory HistoricalContractSlot.fromMap(Map<String, dynamic> map) {
    return HistoricalContractSlot(
      workDate: map['workDate'] as String?,
      startTime: map['startTime'] as String?,
      endTime: map['endTime'] as String?,
      wage: (map['wage'] as num?)?.toInt(),
      wageType: map['wageType'] as String?,
    );
  }
}

/// 보관된 계약서 상세 모델.
/// callableGetHistoricalContractById 응답에 대응.
class HistoricalContractDetail {
  final String contractId;
  final String? businessId;

  /// P3 DETAIL DTO 최상위 필드 — snapshot 파생 아님.
  final String? businessName;

  final String? workerId;

  /// P3 DETAIL DTO 최상위 필드 — snapshot 파생 아님.
  final String? workerName;

  /// 원시 status 문자열.
  final String? status;

  final bool? isLongTerm;
  final DateTime? createdAt;
  final DateTime? employerSignedAt;
  final DateTime? workerSignedAt;
  final DateTime? contractVoidedAt;
  final String? voidReason;

  /// PDF URL. null이면 다운로드 불가.
  final String? pdfUrl;

  /// 계약 체결 당시 스냅샷 (근로자명·사업장명·임금 조건 등).
  final ContractSnapshot? snapshot;

  /// 계약서 조항 목록.
  final List<ContractArticle> articles;

  /// 계약 슬롯 목록 (단기 공고 계약인 경우).
  final List<HistoricalContractSlot> slots;

  const HistoricalContractDetail({
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
    this.pdfUrl,
    this.snapshot,
    required this.articles,
    required this.slots,
  });

  factory HistoricalContractDetail.fromMap(Map<String, dynamic> map) {
    // snapshot — callable 응답은 Map<Object?, Object?>일 수 있으므로 정규화.
    ContractSnapshot? snapshot;
    final rawSnapshot = map['snapshot'];
    if (rawSnapshot is Map) {
      snapshot = ContractSnapshot.fromMap(
        Map<String, dynamic>.from(rawSnapshot),
      );
    }

    // articles
    final rawArticles = map['articles'];
    final List<ContractArticle> articles = rawArticles is List
        ? rawArticles
            .whereType<Map>()
            .map((e) => ContractArticle.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : [];

    // slots
    final rawSlots = map['slots'];
    final List<HistoricalContractSlot> slots = rawSlots is List
        ? rawSlots
            .whereType<Map>()
            .map((e) =>
                HistoricalContractSlot.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : [];

    return HistoricalContractDetail(
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
      pdfUrl: map['pdfUrl'] as String?,
      snapshot: snapshot,
      articles: articles,
      slots: slots,
    );
  }

  bool get hasPdf => pdfUrl != null && pdfUrl!.isNotEmpty;

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
