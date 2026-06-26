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
import '../models/core/notification_model.dart';
import '../models/core/payment_change_request_model.dart';
import '../models/core/interim_settlement_request_model.dart';
import '../utils/format_helper.dart';
import 'firestore_service.dart';

/// 커서 기반 페이지네이션 결과
class PayrollPage<T> {
  final List<T> records;
  /// 다음 페이지 시작 커서 — null이면 마지막 페이지
  final DocumentSnapshot? cursor;
  final bool hasMore;

  PayrollPage({required this.records, this.cursor, required this.hasMore});
}

class PayrollPaymentService {
  static final PayrollPaymentService _instance =
      PayrollPaymentService._internal();
  factory PayrollPaymentService() => _instance;
  PayrollPaymentService._internal();

  final _db = FirebaseFirestore.instance;
  final _firestoreService = FirestoreService();

  // ══════════════════════════════════════════════════════════
  // 송금 처리 (이체 완료 처리)
  // ══════════════════════════════════════════════════════════

  /// 단건 이체 완료 처리
  // [BUG-수정] 급여 이체 완료 후 지원자 알림 발송
  Future<void> markTransferred({
    required String attendanceId,
    required String processedBy,
    String? transferNote,
    // 알림 발송용 — null이면 알림 생략
    String? workerUserId,
    String? workerName,
    String? businessName,
    int? finalWage,
    String? applicationId,
  }) async {
    final attRef = _db.collection('attendance').doc(attendanceId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(attRef);
      final currentStatus = snap.data()?['wageStatus'] as String?;
      if (currentStatus != AttendanceModel.wageConfirmed) {
        throw Exception('확정된 급여만 이체 처리할 수 있습니다. (현재 상태: $currentStatus)');
      }
      tx.update(attRef, {
        'wageStatus':    AttendanceModel.wageTransferred,
        'transferDate':  FieldValue.serverTimestamp(),
        if (transferNote != null && transferNote.isNotEmpty)
          'transferNote': transferNote,
        'transferredBy': processedBy,
        'updatedAt':     FieldValue.serverTimestamp(),
      });
    });

    // 트랜잭션 커밋 후 지원자에게 알림 발송
    if (workerUserId != null &&
        workerName != null &&
        businessName != null &&
        finalWage != null) {
      try {
        await _firestoreService.createNotification(
          NotificationModel.createWageTransferred(
            userId: workerUserId,
            workerName: workerName,
            businessName: businessName,
            finalWage: finalWage,
            applicationId: applicationId,
          ),
        );
      } catch (e) {
        debugPrint('⚠️ 이체 완료 알림 발송 실패 (attendanceId: $attendanceId): $e');
      }
    }
  }

  /// 일괄 이체 완료 처리 (최대 500건, 초과 시 분할)
  // 450건 단위 WriteBatch로 처리하므로, N번째 batch 성공 후 N+1번째 실패 시
  // 앞서 처리된 건만 transferred 상태가 되는 부분 성공이 발생할 수 있다.
  // Firestore는 다중 batch 간 원자성을 보장하지 않으며, 월간 450건 초과 사업장은
  // 극히 드무므로 현재 규모에서는 허용된 트레이드오프다.
  // 재시도 시: 이미 transferred된 건은 동일 상태로 덮어쓰여 멱등하게 처리된다.
  // [BUG-수정] 급여 이체 완료 후 지원자 알림 발송
  Future<void> markTransferredBatch({
    required List<String> attendanceIds,
    required String processedBy,
    String? transferNote,
    // 알림 발송용 — null이면 알림 생략. 각 항목은 attendanceIds와 동일 순서여야 함
    List<TransferNotificationInfo>? notificationInfos,
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

    // 배치 커밋 후 각 항목별로 지원자에게 알림 발송 — Future.wait으로 병렬 처리
    // 각 알림을 개별 try-catch로 감싸 하나 실패해도 나머지 발송이 보장됨
    if (notificationInfos != null) {
      await Future.wait(
        notificationInfos.map((info) async {
          try {
            await _firestoreService.createNotification(
              NotificationModel.createWageTransferred(
                userId: info.workerUserId,
                workerName: info.workerName,
                businessName: info.businessName,
                finalWage: info.finalWage,
                applicationId: info.applicationId,
              ),
            );
          } catch (e) {
            debugPrint('⚠️ 일괄 이체 완료 알림 발송 실패 (userId: ${info.workerUserId}): $e');
          }
        }),
      );
    }
  }

  /// 이체 완료 취소 (confirmed 상태로 되돌림)
  ///
  /// 트랜잭션 미사용: 호출부(payroll_payment_dashboard_screen)에서
  /// UI 레벨로 wageTransferred 상태 항목에만 취소 버튼을 노출하므로
  /// 서비스 레이어에서 상태 재확인 생략. 트랜잭션 추가 시 읽기 비용이 생기므로 현재 생략.
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

  /// 특정 사업장 + 월의 확정/이체 출근기록 조회 (커서 페이지네이션)
  /// - [cursor]: 직전 페이지의 마지막 문서 (최초 조회 시 null)
  /// - [pageSize]: 페이지당 레코드 수 (기본 200)
  /// - 반환된 [PayrollPage.hasMore]=true 이면 cursor를 넘겨 다음 페이지 조회 가능
  Future<PayrollPage<AttendanceModel>> getPayrollRecords({
    required String businessId,
    required int year,
    required int month,
    String? wageStatus,
    int pageSize = 200,
    DocumentSnapshot? cursor,
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
        query = query.where('wageStatus',
            whereIn: [AttendanceModel.wageConfirmed, AttendanceModel.wageTransferred]);
      }

      query = query.orderBy('workDate');
      if (cursor != null) query = query.startAfterDocument(cursor);

      // pageSize+1 건 조회하여 다음 페이지 존재 여부 확인 (실제 반환은 pageSize건)
      final snap = await query.limit(pageSize + 1).get();
      final hasMore = snap.docs.length > pageSize;
      final docs = hasMore ? snap.docs.take(pageSize).toList() : snap.docs;

      return PayrollPage(
        records: docs.map(AttendanceModel.fromFirestore).toList(),
        cursor: docs.isNotEmpty ? docs.last : null,
        hasMore: hasMore,
      );
    } catch (e) {
      debugPrint('❌ 급여 현황 조회 실패: $e');
      return PayrollPage(records: [], hasMore: false);
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
      // paymentDueDate 범위필터 제거 — 등호+범위 복합쿼리에서 request.query.filters 미작동
      // businessId + wageStatus 등호필터만 사용, 날짜 필터링은 클라이언트에서 처리
      final snap = await _db
          .collection('attendance')
          .where('businessId', isEqualTo: businessId)
          .where('wageStatus', isEqualTo: AttendanceModel.wageConfirmed)
          .get();
      return snap.docs.where((doc) {
        final dueDate = doc.data()['paymentDueDate'];
        if (dueDate == null) return false;
        return !(dueDate as Timestamp).toDate().isAfter(today);
      }).length;
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

  /// 사업장의 미처리 변경 요청 전체 조회 (내부 커서 페이지네이션으로 한도 제거)
  Future<List<PaymentChangeRequestModel>> getPendingChangeRequests(
      String businessId) async {
    final results = <PaymentChangeRequestModel>[];
    DocumentSnapshot? cursor;
    bool hasMore = true;
    while (hasMore) {
      final page = await _fetchChangeRequestPage(businessId, cursor: cursor);
      results.addAll(page.records);
      hasMore = page.hasMore;
      cursor = page.cursor;
    }
    return results;
  }

  Future<PayrollPage<PaymentChangeRequestModel>> _fetchChangeRequestPage(
      String businessId, {DocumentSnapshot? cursor, int pageSize = 30}) async {
    try {
      Query query = _db
          .collection('payment_change_requests')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: PaymentChangeRequestModel.statusPending)
          .orderBy('createdAt', descending: true);
      if (cursor != null) query = query.startAfterDocument(cursor);
      final snap = await query.limit(pageSize + 1).get();
      final hasMore = snap.docs.length > pageSize;
      final docs = hasMore ? snap.docs.take(pageSize).toList() : snap.docs;
      return PayrollPage(
        records: docs.map(PaymentChangeRequestModel.fromFirestore).toList(),
        cursor: docs.isNotEmpty ? docs.last : null,
        hasMore: hasMore,
      );
    } catch (e) {
      debugPrint('❌ 변경 요청 조회 실패: $e');
      return PayrollPage(records: [], hasMore: false);
    }
  }

  /// 변경 요청 승인
  ///
  /// 상태 체크(PENDING 확인) 트랜잭션 없음: 동시 처리 가능성이 낮고
  /// 이미 승인된 건을 재승인해도 status 덮어쓰기에 그쳐 데이터 손상 없음.
  /// 엄격한 멱등성이 필요하면 runTransaction으로 PENDING 체크 후 update 패턴으로 전환.
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
  // [특이사항] 동일 attendanceIds로 중복 요청이 생성될 수 있음.
  // approveInterimSettlement()에서 이미 transferred인 건은 skip하므로
  // 이중 지급은 방어되지만, 불필요한 중복 요청이 pending 상태로 남을 수 있음.
  // UI 레이어에서 동일 기간의 미완료 요청이 있으면 생성을 차단한다.
  Future<String> createInterimSettlementRequest(
      InterimSettlementRequestModel req) async {
    final ref = _db.collection('interim_settlement_requests').doc();
    final data = req.toMap()
      ..['createdAt'] = FieldValue.serverTimestamp();
    await ref.set(data);
    return ref.id;
  }

  /// 사업장의 미처리 중간정산 요청 전체 조회 (내부 커서 페이지네이션으로 한도 제거)
  Future<List<InterimSettlementRequestModel>> getPendingSettlementRequests(
      String businessId) async {
    final results = <InterimSettlementRequestModel>[];
    DocumentSnapshot? cursor;
    bool hasMore = true;
    while (hasMore) {
      final page = await _fetchSettlementRequestPage(businessId, cursor: cursor);
      results.addAll(page.records);
      hasMore = page.hasMore;
      cursor = page.cursor;
    }
    return results;
  }

  Future<PayrollPage<InterimSettlementRequestModel>> _fetchSettlementRequestPage(
      String businessId, {DocumentSnapshot? cursor, int pageSize = 30}) async {
    try {
      Query query = _db
          .collection('interim_settlement_requests')
          .where('businessId', isEqualTo: businessId)
          .where('status', whereIn: [
            InterimSettlementRequestModel.statusPending,
            InterimSettlementRequestModel.statusApproved,
          ])
          .orderBy('createdAt', descending: true);
      if (cursor != null) query = query.startAfterDocument(cursor);
      final snap = await query.limit(pageSize + 1).get();
      final hasMore = snap.docs.length > pageSize;
      final docs = hasMore ? snap.docs.take(pageSize).toList() : snap.docs;
      return PayrollPage(
        records: docs.map(InterimSettlementRequestModel.fromFirestore).toList(),
        cursor: docs.isNotEmpty ? docs.last : null,
        hasMore: hasMore,
      );
    } catch (e) {
      debugPrint('❌ 중간정산 요청 조회 실패: $e');
      return PayrollPage(records: [], hasMore: false);
    }
  }

  /// 중간정산 승인 → 해당 출근기록 일괄 이체 완료 처리
  Future<void> approveInterimSettlement({
    required InterimSettlementRequestModel req,
    required String processedBy,
    String? transferNote,
  }) async {
    // [087] 멱등성 보호 — 이미 처리된 요청 이중 처리 방지
    final reqSnap = await _db
        .collection('interim_settlement_requests')
        .doc(req.id)
        .get(const GetOptions(source: Source.server));
    final currentStatus = reqSnap.data()?['status'] as String?;
    // [BUG-수정] S-1: APPROVED 상태도 멱등성 체크에 포함 — 재호출 시 1단계 중복 실행 방지
    if (currentStatus == InterimSettlementRequestModel.statusProcessed ||
        currentStatus == InterimSettlementRequestModel.statusApproved) {
      // [D-002] silent return 대신 exception throw — 호출자가 성공으로 오인하는 버그 수정
      throw Exception('이미 처리된 중간정산 요청입니다. 중복 처리가 차단되었습니다.');
    }

    if (req.attendanceIds.isEmpty) {
      throw Exception('중간정산 요청에 출근기록이 없습니다. 처리할 항목이 없습니다.');
    }

    // [BUG-수정] S-2: 2단계 실패 후 재시도 시 복구 경로
    // 1단계 성공 + 2단계 실패 → status=PENDING 잔류 상태에서 관리자가 재승인 시
    // attendanceIds 중 이미 transferred인 건이 있으면 1단계를 건너뛰고 status만 PROCESSED로 갱신
    //
    // 요청 생성 후 승인 전에 관리자가 일부 항목을 취소(wagePending 복원)하면
    // 원래 req.attendanceIds를 그대로 쓸 경우 취소된 항목도 wageTransferred로 덮어쓰는 버그.
    // 현재 wageStatus를 서버 조회 후 wageConfirmed 항목만 필터링해서 이체.
    bool skipMarkTransferred = false;
    List<String> idsToTransfer = List.from(req.attendanceIds);

    if (req.attendanceIds.isNotEmpty) {
      // attendanceIds의 현재 wageStatus를 서버에서 조회
      final attSnaps = await Future.wait(
        req.attendanceIds.map(
          (id) => _db
              .collection('attendance')
              .doc(id)
              .get(const GetOptions(source: Source.server)),
        ),
      );
      final allTransferred = attSnaps
          .every((s) => s.data()?['wageStatus'] == AttendanceModel.wageTransferred);
      if (allTransferred) {
        // 모든 항목이 이미 transferred → 1단계 건너뛰고 status만 PROCESSED로 복구
        skipMarkTransferred = true;
      } else {
        // wageConfirmed 항목만 이체 처리 — 취소된(wagePending 등) 항목 제외
        idsToTransfer = attSnaps
            .where((s) => s.data()?['wageStatus'] == AttendanceModel.wageConfirmed)
            .map((s) => s.id)
            .toList();
        if (idsToTransfer.isEmpty) skipMarkTransferred = true;
      }
    }

    // 1단계: 출근기록 이체 처리 먼저 — attendance 성공 후 요청 상태 변경
    // (역순 시 실패 모드: attendance=미이체인데 status=processed → 미지급 상태 숨김)
    // ⚠️ 원자성 없음: 1단계 성공 + 2단계 실패 시 attendance=transferred, status=pending 불일치 발생.
    // 단, markTransferredBatch는 멱등(이미 transferred인 건을 덮어써도 안전)하므로,
    // 재시도 시 1단계가 재실행되어도 중복 이체 없이 2단계까지 정상 완료된다.
    if (!skipMarkTransferred) {
      await markTransferredBatch(
        attendanceIds: idsToTransfer,
        processedBy: processedBy,
        transferNote: transferNote ?? '중간정산 처리',
      );
    }

    // 2단계: 요청 상태 변경 (출근기록 이체 완료 후)
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

// ─── 이체 완료 알림 정보 ──────────────────────────────────────────
// [BUG-수정] 급여 이체 완료 후 지원자 알림 발송

/// markTransferredBatch 알림 발송용 개별 근무자 정보
class TransferNotificationInfo {
  final String workerUserId;
  final String workerName;
  final String businessName;
  final int finalWage;
  final String? applicationId;

  const TransferNotificationInfo({
    required this.workerUserId,
    required this.workerName,
    required this.businessName,
    required this.finalWage,
    this.applicationId,
  });
}

/// [BUG-수정] 급여 이체 완료 후 지원자 알림 발송
/// markTransferredBatch에 전달할 알림 정보 목록을 생성하는 헬퍼
/// - attendanceIds 리스트와 동일 순서로 반환
/// - workerName은 호출 측에서 보유한 캐시(Map[uid, name])를 활용해 채운다
List<TransferNotificationInfo> buildTransferNotificationInfos({
  required List<AttendanceModel> records,
  required Map<String, String> workerNameByUid, // uid → 표시 이름
}) {
  return records.map((r) {
    final wd = r.wageDetail;
    final net = wd?.effectiveNetWage ?? 0;
    return TransferNotificationInfo(
      workerUserId: r.userId,
      workerName: workerNameByUid[r.userId] ?? r.userId,
      businessName: r.businessName,
      finalWage: net,
      applicationId: r.applicationId,
    );
  }).toList();
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
    if (bank == null) {
      // [D-001] 은행정보 누락 — 해당 근무자 급여가 이체 목록에서 제외됨
      debugPrint('⚠️ [이체] 은행정보 없음 — uid: $uid, 해당 급여 ${recs.length}건 이체 목록 제외');
      continue;
    }

    final totalNet = recs.fold<int>(0, (acc, r) {
      final wd = r.wageDetail;
      if (wd == null) return acc;
      return acc + wd.effectiveNetWage;
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
