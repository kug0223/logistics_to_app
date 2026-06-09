// lib/services/payroll_payment_service.dart
//
// 급여 지급(송금) 관리 서비스
// - 단건/일괄 이체 완료 처리
// - 지급방식 변경 요청 CRUD
// - 중간정산 요청 CRUD
// - CSV 내보내기 데이터 생성
//
// 비용 최적화:
//   - 이체 처리는 WriteBatch (최대 500건 분할)
//   - 목록 조회는 pageSize=30 기본
//   - 상태 필터는 서버사이드 where()

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/core/attendance_model.dart';
import '../models/core/payment_change_request_model.dart';
import '../models/core/interim_settlement_request_model.dart';
import '../utils/format_helper.dart';

class PayrollPaymentService {
  static final PayrollPaymentService _instance =
      PayrollPaymentService._internal();
  factory PayrollPaymentService() => _instance;
  PayrollPaymentService._internal();

  final _db = FirebaseFirestore.instance;

  // ══════════════════════════════════════════════════════════
  // 송금 처리 (이체 완료 처리)
  // ══════════════════════════════════════════════════════════

  /// 단건 이체 완료 처리
  Future<void> markTransferred({
    required String attendanceId,
    required String processedBy,
    String? transferNote,
  }) async {
    await _db.collection('attendance').doc(attendanceId).update({
      'wageStatus':    AttendanceModel.wageTransferred,
      'transferDate':  FieldValue.serverTimestamp(),
      if (transferNote != null && transferNote.isNotEmpty)
        'transferNote': transferNote,
      'transferredBy': processedBy,
      'updatedAt':     FieldValue.serverTimestamp(),
    });
  }

  /// 일괄 이체 완료 처리 (최대 500건, 초과 시 분할)
  Future<void> markTransferredBatch({
    required List<String> attendanceIds,
    required String processedBy,
    String? transferNote,
  }) async {
    final now = Timestamp.now();
    for (int i = 0; i < attendanceIds.length; i += 450) {
      final chunk = attendanceIds.skip(i).take(450);
      final batch = _db.batch();
      for (final id in chunk) {
        batch.update(_db.collection('attendance').doc(id), {
          'wageStatus':    AttendanceModel.wageTransferred,
          'transferDate':  now,
          if (transferNote != null && transferNote.isNotEmpty)
            'transferNote': transferNote,
          'transferredBy': processedBy,
          'updatedAt':     now,
        });
      }
      await batch.commit();
    }
  }

  /// 이체 완료 취소 (confirmed 상태로 되돌림)
  Future<void> cancelTransfer({
    required String attendanceId,
    required String processedBy,
  }) async {
    await _db.collection('attendance').doc(attendanceId).update({
      'wageStatus':    AttendanceModel.wageConfirmed,
      'transferDate':  FieldValue.delete(),
      'transferNote':  FieldValue.delete(),
      'transferredBy': FieldValue.delete(),
      'updatedAt':     FieldValue.serverTimestamp(),
    });
    debugPrint('✅ 이체 취소 완료: $attendanceId by $processedBy');
  }

  // ══════════════════════════════════════════════════════════
  // 급여 지급 현황 조회
  // ══════════════════════════════════════════════════════════

  /// 특정 사업장 + 월의 확정/이체 출근기록 조회
  Future<List<AttendanceModel>> getPayrollRecords({
    required String businessId,
    required int year,
    required int month,
    String? wageStatus, // null = 전체 (confirmed + transferred)
  }) async {
    try {
      final monthStart = DateTime(year, month, 1);
      final monthEnd   = DateTime(year, month + 1, 1);

      Query query = _db
          .collection('attendance')
          .where('businessId', isEqualTo: businessId)
          .where('workDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('workDate', isLessThan: Timestamp.fromDate(monthEnd));

      if (wageStatus != null) {
        query = query.where('wageStatus', isEqualTo: wageStatus);
      } else {
        // 확정 + 이체 모두 조회
        query = query.where('wageStatus',
            whereIn: [AttendanceModel.wageConfirmed, AttendanceModel.wageTransferred]);
      }

      // 월 단위 최대 2,000건 제한 (사업장 1곳 기준 충분)
      final snap = await query.orderBy('workDate').limit(2000).get();
      return snap.docs.map(AttendanceModel.fromFirestore).toList();
    } catch (e) {
      debugPrint('❌ 급여 현황 조회 실패: $e');
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════
  // 오늘 처리할 송금 조회
  // ══════════════════════════════════════════════════════════

  /// 오늘 지급 예정일이 도래한 미이체 출근기록 조회
  /// - paymentDueDate <= today AND wageStatus = 'confirmed'
  /// - 사업장 단위 (businessId 필수)
  Future<List<AttendanceModel>> getTodayPayments({
    required String businessId,
    DateTime? referenceDate,
  }) async {
    try {
      final ref = referenceDate ?? DateTime.now();
      final today = DateTime(ref.year, ref.month, ref.day, 23, 59, 59);
      final snap = await _db
          .collection('attendance')
          .where('businessId', isEqualTo: businessId)
          .where('wageStatus', isEqualTo: AttendanceModel.wageConfirmed)
          .where('paymentDueDate',
              isLessThanOrEqualTo: Timestamp.fromDate(today))
          .orderBy('paymentDueDate')
          .orderBy('workDate')
          .get();
      return snap.docs.map(AttendanceModel.fromFirestore).toList();
    } catch (e) {
      debugPrint('❌ 오늘 지급 조회 실패: $e');
      return [];
    }
  }

  /// 오늘 지급 예정 건수 (배지용 — count 쿼리)
  Future<int> getTodayPaymentCount({
    required String businessId,
    DateTime? referenceDate,
  }) async {
    try {
      final ref = referenceDate ?? DateTime.now();
      final today = DateTime(ref.year, ref.month, ref.day, 23, 59, 59);
      final snap = await _db
          .collection('attendance')
          .where('businessId', isEqualTo: businessId)
          .where('wageStatus', isEqualTo: AttendanceModel.wageConfirmed)
          .where('paymentDueDate',
              isLessThanOrEqualTo: Timestamp.fromDate(today))
          .count()
          .get();
      return snap.count ?? 0;
    } catch (e) {
      debugPrint('❌ 오늘 지급 건수 조회 실패: $e');
      return 0;
    }
  }

  // ══════════════════════════════════════════════════════════
  // CSV 내보내기
  // ══════════════════════════════════════════════════════════

  /// 이체 목록 CSV 생성 (미이체 근무자만)
  /// 형식: 은행, 계좌번호, 예금주, 금액, 메모
  static String generateTransferCsv(List<TransferRow> rows) {
    final buf = StringBuffer();
    buf.writeln('이름,은행명,계좌번호,예금주,이체금액,메모');
    for (final r in rows) {
      buf.writeln(
          '"${r.workerName}","${r.bankName}","${r.accountNumber}",'
          '"${r.accountHolder}",${r.netAmount},"${r.memo}"');
    }
    return buf.toString();
  }

  // ══════════════════════════════════════════════════════════
  // 지급방식 변경 요청
  // ══════════════════════════════════════════════════════════

  /// 지급방식 변경 요청 생성 (근무자 또는 관리자 대신)
  Future<String> createPaymentChangeRequest(
      PaymentChangeRequestModel req) async {
    final ref = _db.collection('payment_change_requests').doc();
    final data = req.toMap()
      ..['createdAt'] = FieldValue.serverTimestamp();
    await ref.set(data);
    return ref.id;
  }

  /// 사업장의 미처리 변경 요청 목록
  Future<List<PaymentChangeRequestModel>> getPendingChangeRequests(
      String businessId) async {
    try {
      final snap = await _db
          .collection('payment_change_requests')
          .where('businessId', isEqualTo: businessId)
          .where('status',
              isEqualTo: PaymentChangeRequestModel.statusPending)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      return snap.docs
          .map(PaymentChangeRequestModel.fromFirestore)
          .toList();
    } catch (e) {
      debugPrint('❌ 변경 요청 조회 실패: $e');
      return [];
    }
  }

  /// 변경 요청 승인
  Future<void> approveChangeRequest({
    required String requestId,
    required String processedBy,
  }) async {
    await _db.collection('payment_change_requests').doc(requestId).update({
      'status':      PaymentChangeRequestModel.statusApproved,
      'processedBy': processedBy,
      'processedAt': FieldValue.serverTimestamp(),
      'updatedAt':   FieldValue.serverTimestamp(),
    });
  }

  /// 변경 요청 거절
  Future<void> rejectChangeRequest({
    required String requestId,
    required String processedBy,
    required String rejectReason,
  }) async {
    await _db.collection('payment_change_requests').doc(requestId).update({
      'status':       PaymentChangeRequestModel.statusRejected,
      'processedBy':  processedBy,
      'processedAt':  FieldValue.serverTimestamp(),
      'rejectReason': rejectReason,
      'updatedAt':    FieldValue.serverTimestamp(),
    });
  }

  // ══════════════════════════════════════════════════════════
  // 중간정산 요청
  // ══════════════════════════════════════════════════════════

  /// 중간정산 요청 생성
  Future<String> createInterimSettlementRequest(
      InterimSettlementRequestModel req) async {
    final ref = _db.collection('interim_settlement_requests').doc();
    final data = req.toMap()
      ..['createdAt'] = FieldValue.serverTimestamp();
    await ref.set(data);
    return ref.id;
  }

  /// 사업장의 미처리 중간정산 요청 목록
  Future<List<InterimSettlementRequestModel>> getPendingSettlementRequests(
      String businessId) async {
    try {
      final snap = await _db
          .collection('interim_settlement_requests')
          .where('businessId', isEqualTo: businessId)
          .where('status',
              whereIn: [
                InterimSettlementRequestModel.statusPending,
                InterimSettlementRequestModel.statusApproved,
              ])
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      return snap.docs
          .map(InterimSettlementRequestModel.fromFirestore)
          .toList();
    } catch (e) {
      debugPrint('❌ 중간정산 요청 조회 실패: $e');
      return [];
    }
  }

  /// 중간정산 승인 → 해당 출근기록 일괄 이체 완료 처리
  Future<void> approveInterimSettlement({
    required InterimSettlementRequestModel req,
    required String processedBy,
    String? transferNote,
  }) async {
    // 1. 출근기록 이체 처리 먼저 — attendance 성공 후 요청 상태 변경
    // (역순 시 실패 모드: attendance=미이체인데 status=processed → 미지급 상태 숨김)
    await markTransferredBatch(
      attendanceIds: req.attendanceIds,
      processedBy: processedBy,
      transferNote: transferNote ?? '중간정산 처리',
    );

    // 2. 요청 상태 변경 (출근기록 이체 완료 후)
    await _db
        .collection('interim_settlement_requests')
        .doc(req.id)
        .update({
      'status':      InterimSettlementRequestModel.statusProcessed,
      'processedBy': processedBy,
      'processedAt': FieldValue.serverTimestamp(),
      if (transferNote != null) 'transferNote': transferNote,
      'updatedAt':   FieldValue.serverTimestamp(),
    });
  }

  /// 중간정산 거절
  Future<void> rejectInterimSettlement({
    required String requestId,
    required String processedBy,
    required String rejectReason,
  }) async {
    await _db
        .collection('interim_settlement_requests')
        .doc(requestId)
        .update({
      'status':       InterimSettlementRequestModel.statusRejected,
      'processedBy':  processedBy,
      'processedAt':  FieldValue.serverTimestamp(),
      'rejectReason': rejectReason,
      'updatedAt':    FieldValue.serverTimestamp(),
    });
  }
}

// ─── CSV 이체 행 ──────────────────────────────────────────────────

class TransferRow {
  final String workerName;
  final String bankName;
  final String accountNumber;
  final String accountHolder;
  final int netAmount;
  final String memo;

  const TransferRow({
    required this.workerName,
    required this.bankName,
    required this.accountNumber,
    required this.accountHolder,
    required this.netAmount,
    required this.memo,
  });
}

/// 출근기록 리스트 + 사용자 계좌 정보로 이체 행 생성
List<TransferRow> buildTransferRows(
  List<AttendanceModel> records,
  Map<String, Map<String, String>> userBankInfo, // uid → {bankName, accountNumber, accountHolder}
) {
  // 근무자별로 그룹화하여 합산
  final grouped = <String, List<AttendanceModel>>{};
  for (final r in records) {
    (grouped[r.userId] ??= []).add(r);
  }

  final rows = <TransferRow>[];
  for (final entry in grouped.entries) {
    final uid = entry.key;
    final recs = entry.value;
    final bank = userBankInfo[uid];
    if (bank == null) continue;

    final totalNet = recs.fold<int>(0, (acc, r) {
      final wd = r.wageDetail;
      if (wd == null) return acc;
      return acc + (wd.netWage > 0 ? wd.netWage : wd.totalAmount - wd.totalInsuranceDeduction);
    });

    if (totalNet <= 0) continue;

    final firstName = recs.first;
    final dateRange = recs.length == 1
        ? FormatHelper.formatDateDot(recs.first.workDate)
        : '${FormatHelper.formatDateDot(recs.first.workDate)}~'
            '${FormatHelper.formatDateDot(recs.last.workDate)}';

    rows.add(TransferRow(
      workerName: bank['name'] ?? uid,
      bankName: bank['bankName'] ?? '',
      accountNumber: bank['accountNumber'] ?? '',
      accountHolder: bank['accountHolder'] ?? '',
      netAmount: totalNet,
      memo: '${firstName.businessName} 급여 $dateRange',
    ));
  }
  return rows;
}
