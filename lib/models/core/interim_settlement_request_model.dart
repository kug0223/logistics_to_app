// lib/models/core/interim_settlement_request_model.dart
//
// 중간정산 요청 모델 (패턴 A)
// 근무자가 특정 날짜까지 쌓인 출근기록을 지금 정산해달라고 요청
// 관리자 승인 → 해당 출근기록 wageStatus = 'transferred'로 일괄 처리

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class InterimSettlementRequestModel {
  // ── 상태 상수 ────────────────────────────────────────────────
  static const String statusPending   = 'PENDING';
  static const String statusApproved  = 'APPROVED';
  static const String statusRejected  = 'REJECTED';
  static const String statusProcessed = 'PROCESSED'; // 실제 송금 완료

  final String id;
  final String applicationId;
  final String businessId;
  final String businessName;
  final String workerId;
  final String workerName;

  // 정산 대상 기간 (패턴 A: 날짜 범위)
  final DateTime periodStart;
  final DateTime periodEnd;

  // 정산 대상 출근기록 ID 목록
  final List<String> attendanceIds;

  // 정산 금액 (요청 시점 집계)
  final int requestedAmount; // 총 정산 요청 금액 (세전)
  final int netAmount;       // 실수령 예상액 (공제 후)

  final String? requestReason;

  // 처리 정보
  final String status;
  final String? processedBy;
  final DateTime? processedAt;
  final String? transferNote; // 실제 이체 메모
  final String? rejectReason;

  final DateTime createdAt;
  final DateTime? updatedAt;

  const InterimSettlementRequestModel({
    required this.id,
    required this.applicationId,
    required this.businessId,
    required this.businessName,
    required this.workerId,
    required this.workerName,
    required this.periodStart,
    required this.periodEnd,
    required this.attendanceIds,
    required this.requestedAmount,
    required this.netAmount,
    this.requestReason,
    required this.status,
    this.processedBy,
    this.processedAt,
    this.transferNote,
    this.rejectReason,
    required this.createdAt,
    this.updatedAt,
  });

  factory InterimSettlementRequestModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) {
      throw ArgumentError('InterimSettlementRequestModel.fromFirestore: 문서 데이터 없음 (id: ${doc.id})');
    }
    return InterimSettlementRequestModel.fromMap(raw as Map<String, dynamic>, doc.id);
  }

  // [SCHEMA-09] 역직렬화 실패 격리 — 손상 문서 1건이 목록 전체 크래시 방지
  static InterimSettlementRequestModel? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return InterimSettlementRequestModel.fromFirestore(doc);
    } catch (e, st) {
      debugPrint('[InterimSettlementRequestModel] 역직렬화 실패 id=${doc.id}: $e\n$st');
      return null;
    }
  }

  factory InterimSettlementRequestModel.fromMap(Map<String, dynamic> d, String id) {
    return InterimSettlementRequestModel(
      id: id,
      applicationId:  d['applicationId'] ?? '',
      businessId:     d['businessId']    ?? '',
      businessName:   d['businessName']  ?? '',
      workerId:       d['workerId']      ?? '',
      workerName:     d['workerName']    ?? '',
      periodStart: d['periodStart'] != null
          ? (d['periodStart'] as Timestamp).toDate().toLocal()
          : (throw ArgumentError('InterimSettlementRequestModel: periodStart 누락 (id: $id)')),
      periodEnd: d['periodEnd'] != null
          ? (d['periodEnd'] as Timestamp).toDate().toLocal()
          : (throw ArgumentError('InterimSettlementRequestModel: periodEnd 누락 (id: $id)')),
      attendanceIds: List<String>.from(d['attendanceIds'] as List? ?? []),
      requestedAmount:(d['requestedAmount'] as num?)?.toInt() ?? 0,
      netAmount:      (d['netAmount']      as num?)?.toInt() ?? 0,
      requestReason:  d['requestReason'],
      status:         d['status']        ?? statusPending,
      processedBy:    d['processedBy'],
      processedAt:   (d['processedAt']   as Timestamp?)?.toDate().toLocal(),
      transferNote:   d['transferNote'],
      rejectReason:   d['rejectReason'],
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate().toLocal()
          : (throw ArgumentError('InterimSettlementRequestModel: createdAt 누락 (id: $id)')),
      updatedAt:     (d['updatedAt']     as Timestamp?)?.toDate().toLocal(),
    );
  }

  Map<String, dynamic> toMap() => {
    'applicationId':  applicationId,
    'businessId':     businessId,
    'businessName':   businessName,
    'workerId':       workerId,
    'workerName':     workerName,
    'periodStart':    Timestamp.fromDate(periodStart),
    'periodEnd':      Timestamp.fromDate(periodEnd),
    'attendanceIds':  attendanceIds,
    'requestedAmount':requestedAmount,
    'netAmount':      netAmount,
    if (requestReason != null) 'requestReason': requestReason,
    'status':         status,
    if (processedBy  != null) 'processedBy':  processedBy,
    if (processedAt  != null)
      'processedAt': Timestamp.fromDate(processedAt!),
    if (transferNote != null) 'transferNote': transferNote,
    if (rejectReason != null) 'rejectReason': rejectReason,
    'createdAt': Timestamp.fromDate(createdAt),
    if (updatedAt != null)
      'updatedAt': Timestamp.fromDate(updatedAt!),
  };

  // ── getters ──────────────────────────────────────────────────
  bool get isPending   => status == statusPending;
  bool get isApproved  => status == statusApproved;
  bool get isRejected  => status == statusRejected;
  bool get isProcessed => status == statusProcessed;

  String get statusLabel {
    switch (status) {
      case statusPending:   return '처리 대기';
      case statusApproved:  return '승인 (이체 대기)';
      case statusRejected:  return '거절';
      case statusProcessed: return '정산 완료';
      default:              return status;
    }
  }

  /// 정산 기간 레이블 (예: "5/1 ~ 5/15")
  String get periodLabel =>
      '${periodStart.month}/${periodStart.day} ~ ${periodEnd.month}/${periodEnd.day}';

  /// 정산 출근기록 건수
  int get recordCount => attendanceIds.length;
}
