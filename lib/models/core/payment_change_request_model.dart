//
// 지급방식 변경 요청 모델
// 근무자가 현재 지급 방식(주급/월급 등)을 변경 요청
// → 관리자 승인 후 다음 지급 주기부터 효력 발생

import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentChangeRequestModel {
  // ── 상태 상수 ────────────────────────────────────────────────
  static const String statusPending  = 'PENDING';
  static const String statusApproved = 'APPROVED';
  static const String statusRejected = 'REJECTED';

  final String id;
  final String applicationId;   // 해당 지원서 ID
  final String businessId;
  final String businessName;
  final String workerId;        // 요청자 (근무자) UID
  final String workerName;

  // 변경 내용
  final String currentPayScheduleType;   // 현재: 'same_day'|'next_day'|'weekly'|'monthly'
  final int?   currentPayScheduleDay;    // 현재 지급 요일/날짜
  final String requestedPayScheduleType; // 요청: 변경 원하는 유형
  final int?   requestedPayScheduleDay;  // 요청 지급 요일/날짜
  final String? requestReason;           // 변경 사유

  // 효력 시점 (항상 다음 지급 주기부터)
  final String effectiveFrom; // 'yyyy-MM-dd' 형식 (다음 주기 시작일)

  // 처리 정보
  final String status;         // PENDING | APPROVED | REJECTED
  final String? processedBy;   // 처리한 관리자 UID
  final DateTime? processedAt;
  final String? rejectReason;  // 거절 사유

  final DateTime createdAt;
  final DateTime? updatedAt;

  const PaymentChangeRequestModel({
    required this.id,
    required this.applicationId,
    required this.businessId,
    required this.businessName,
    required this.workerId,
    required this.workerName,
    required this.currentPayScheduleType,
    this.currentPayScheduleDay,
    required this.requestedPayScheduleType,
    this.requestedPayScheduleDay,
    this.requestReason,
    required this.effectiveFrom,
    required this.status,
    this.processedBy,
    this.processedAt,
    this.rejectReason,
    required this.createdAt,
    this.updatedAt,
  });

  // ── 정적 라벨 헬퍼 ──────────────────────────────────────────
  static String scheduleTypeLabel(String type) {
    switch (type) {
      case 'same_day': return '당일';
      case 'next_day': return '익일';
      case 'weekly':   return '주급';
      case 'monthly':  return '월급';
      default:         return type;
    }
  }

  factory PaymentChangeRequestModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) {
      throw ArgumentError('PaymentChangeRequestModel: document ${doc.id} has no data');
    }
    final d = raw as Map<String, dynamic>;
    return PaymentChangeRequestModel.fromMap(d, doc.id);
  }

  factory PaymentChangeRequestModel.fromMap(Map<String, dynamic> d, String id) {
    final createdAt = (d['createdAt'] as Timestamp?)?.toDate().toLocal();
    if (createdAt == null) {
      throw ArgumentError('PaymentChangeRequestModel: createdAt is missing (id=$id)');
    }
    return PaymentChangeRequestModel(
      id: id,
      applicationId:           d['applicationId']            ?? '',
      businessId:              d['businessId']               ?? '',
      businessName:            d['businessName']             ?? '',
      workerId:                d['workerId']                 ?? '',
      workerName:              d['workerName']               ?? '',
      currentPayScheduleType:  d['currentPayScheduleType']   ?? '',
      currentPayScheduleDay:   (d['currentPayScheduleDay']  as num?)?.toInt(),
      requestedPayScheduleType:d['requestedPayScheduleType'] ?? '',
      requestedPayScheduleDay: (d['requestedPayScheduleDay'] as num?)?.toInt(),
      requestReason:           d['requestReason'],
      effectiveFrom:           d['effectiveFrom']            ?? '',
      status:                  d['status']                   ?? statusPending,
      processedBy:             d['processedBy'],
      processedAt:            (d['processedAt']  as Timestamp?)?.toDate().toLocal(),
      rejectReason:            d['rejectReason'],
      createdAt:               createdAt,
      updatedAt:              (d['updatedAt']    as Timestamp?)?.toDate().toLocal(),
    );
  }

  Map<String, dynamic> toMap() => {
    'applicationId':            applicationId,
    'businessId':               businessId,
    'businessName':             businessName,
    'workerId':                 workerId,
    'workerName':               workerName,
    'currentPayScheduleType':   currentPayScheduleType,
    if (currentPayScheduleDay != null)
      'currentPayScheduleDay':  currentPayScheduleDay,
    'requestedPayScheduleType': requestedPayScheduleType,
    if (requestedPayScheduleDay != null)
      'requestedPayScheduleDay': requestedPayScheduleDay,
    if (requestReason != null) 'requestReason': requestReason,
    'effectiveFrom':            effectiveFrom,
    'status':                   status,
    if (processedBy != null)    'processedBy':   processedBy,
    if (processedAt != null)
      'processedAt': Timestamp.fromDate(processedAt!),
    if (rejectReason != null)   'rejectReason':  rejectReason,
    'createdAt': Timestamp.fromDate(createdAt),
    if (updatedAt != null)
      'updatedAt': Timestamp.fromDate(updatedAt!),
  };

  // ── getters ──────────────────────────────────────────────────
  bool get isPending  => status == statusPending;
  bool get isApproved => status == statusApproved;
  bool get isRejected => status == statusRejected;

  String get statusLabel {
    switch (status) {
      case statusPending:  return '처리 대기';
      case statusApproved: return '승인';
      case statusRejected: return '거절';
      default:             return status;
    }
  }

  String get changeDescription =>
      '${scheduleTypeLabel(currentPayScheduleType)} → ${scheduleTypeLabel(requestedPayScheduleType)}';
}
