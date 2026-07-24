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
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/core/attendance_model.dart';
import '../models/core/notification_model.dart';
import '../models/core/payment_change_request_model.dart';
import '../models/core/interim_settlement_request_model.dart';
import '../utils/format_helper.dart';

// CF 응답에서 {_seconds, _nanoseconds} 맵을 Timestamp로 재수화
Map<String, dynamic> _cfHydrate(Map<String, dynamic> m) {
  return m.map((k, v) {
    if (v is Map) {
      final vm = Map<String, dynamic>.from(v);
      if (vm.containsKey('_seconds')) {
        try {
          return MapEntry(k, Timestamp(
            (vm['_seconds'] as num).toInt(),
            (vm['_nanoseconds'] as num? ?? 0).toInt(),
          ));
        } catch (_) {}
      }
      return MapEntry(k, _cfHydrate(vm));
    } else if (v is List) {
      return MapEntry(k, v.map((e) =>
        e is Map ? _cfHydrate(Map<String, dynamic>.from(e)) : e
      ).toList());
    }
    return MapEntry(k, v);
  });
}

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
  final _cf = FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  // ══════════════════════════════════════════════════════════
  // 송금 처리 (이체 완료 처리) — CF callableMarkTransferredBatch 경유
  // confirmed→transferred 법적 상태 전이: Trust Boundary Charter 기준 CF 필수
  // ══════════════════════════════════════════════════════════

  /// 단건 이체 완료 처리 — callableMarkTransferredBatch(attendanceIds 1건) 위임
  Future<void> markTransferred({
    required String attendanceId,
    required String businessId,
    String? transferNote,
    // 알림 발송용 — null이면 CF에서 알림 생략
    String? workerUserId,
    String? workerName,
    String? businessName,
    int? finalWage,
    String? applicationId,
  }) async {
    final notifications = (workerUserId != null &&
            workerName != null &&
            businessName != null &&
            finalWage != null)
        ? [
            {
              'userId': workerUserId,
              'workerName': workerName,
              'businessName': businessName,
              'businessId': businessId,
              'finalWage': finalWage,
              'attendanceId': attendanceId,
              if (applicationId != null && applicationId.isNotEmpty)
                'applicationId': applicationId,
            }
          ]
        : null;

    await _cf.httpsCallable('callableMarkTransferredBatch').call({
      'businessId': businessId,
      'attendanceIds': [attendanceId],
      if (transferNote != null && transferNote.isNotEmpty) 'transferNote': transferNote,
      if (notifications != null) 'notifications': notifications,
    });
  }

  /// 일괄 이체 완료 처리 — callableMarkTransferredBatch(최대 200건/청크) 위임
  // 재시도 시: 이미 transferred된 건은 CF에서 멱등 처리(processed++ 후 skip)
  // 알림은 첫 번째 청크에만 포함 (알림은 attendanceIds 순서와 무관)
  Future<void> markTransferredBatch({
    required List<String> attendanceIds,
    required String businessId,
    String? transferNote,
    List<TransferNotificationInfo>? notificationInfos,
  }) async {
    final allNotifications = notificationInfos
        ?.map((n) => {
              'userId': n.workerUserId,
              'workerName': n.workerName,
              'businessName': n.businessName,
              'businessId': n.businessId,
              'finalWage': n.finalWage,
              'attendanceId': n.attendanceId,
              if (n.applicationId != null && n.applicationId!.isNotEmpty)
                'applicationId': n.applicationId!,
            })
        .toList();

    bool notificationsSent = false;
    final List<String> chunkErrors = [];
    for (int i = 0; i < attendanceIds.length; i += 200) {
      final chunk = attendanceIds.skip(i).take(200).toList();
      // [FIX] 알림 포함 여부를 await 이전에 결정·잠금:
      // 이전 코드는 CF 실패 시 notificationsSent=false 유지 → 다음 청크가
      // 전체 근로자에게 허위 이체완료 알림 발송하는 버그
      // [BUG-FIX] null 체크만으로는 빈 배열([])도 통과 → 0건 알림 발송 버그
      final bool sendNotifs = !notificationsSent && (allNotifications?.isNotEmpty ?? false);
      try {
        await _cf.httpsCallable('callableMarkTransferredBatch').call({
          'businessId': businessId,
          'attendanceIds': chunk,
          if (transferNote != null && transferNote.isNotEmpty) 'transferNote': transferNote,
          if (sendNotifs) 'notifications': allNotifications,
        });
        // [BUG-FIX] notificationsSent = true를 await 성공 후로 이동
        // await 이전에 설정하면 첫 청크 실패 시 이후 청크에서 알림을 전혀 발송하지 않음
        if (sendNotifs) notificationsSent = true;
      } catch (e) {
        final msg = e is FirebaseFunctionsException
            ? (e.message ?? e.code)
            : e.toString();
        debugPrint('⚠️ [markTransferredBatch] 청크 ${i ~/ 200 + 1} 실패: $msg');
        chunkErrors.add('청크 ${i ~/ 200 + 1}: $msg');
      }
    }
    if (chunkErrors.isNotEmpty) {
      throw Exception('이체 일괄처리 실패 (${chunkErrors.length}개 청크):\n${chunkErrors.join('\n')}');
    }
  }

  // cancelTransfer() 제거 — firestore.rules에서 transferred→confirmed 역전환을 전면 차단함
  // (슈퍼어드민 포함 클라이언트 경로 불가, Admin SDK CF 경유만 가능)

  // ══════════════════════════════════════════════════════════
  // 급여 지급 현황 조회
  // ══════════════════════════════════════════════════════════

  /// 특정 사업장 + 월의 확정/이체 출근기록 조회 (커서 페이지네이션)
  /// - [cursor]: 직전 페이지의 마지막 문서 (최초 조회 시 null)
  /// - [pageSize]: 페이지당 레코드 수 (기본 200)
  /// - 반환된 [PayrollPage.hasMore]=true 이면 cursor를 넘겨 다음 페이지 조회 가능
  ///
  /// [직접 Firestore 유지 — 의도적 결정]
  /// startAfterDocument(cursor)는 DocumentSnapshot을 커서로 사용하므로
  /// CF 반환값(직렬화된 Map)으로 커서를 재구성할 수 없어 CF 이전 불가.
  /// 단, businessId isEqualTo 단일 등호필터는 request.query.filters.businessId를
  /// [CF 이전 2026-07-13] callableGetAdminAttendances (startMs/endMs + wageStatus)
  /// cursor 기반 페이지네이션은 CF에서 미지원 → pageSize 단위 전체 조회 후 클라이언트 슬라이싱
  Future<PayrollPage<AttendanceModel>> getPayrollRecords({
    required String businessId,
    required int year,
    required int month,
    String? wageStatus,
    int pageSize = 200,
    DocumentSnapshot? cursor,  // CF 이전 후 미사용 (하위 호환 유지)
  }) async {
    try {
      final monthStart = DateTime(year, month, 1);
      final monthEnd   = DateTime(year, month + 1, 1);

      final result = await _cf.httpsCallable('callableGetAdminAttendances',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
          .call<Map<String, dynamic>>({
        'businessId': businessId,
        'startMs': monthStart.millisecondsSinceEpoch,
        'endMs': monthEnd.millisecondsSinceEpoch,
        if (wageStatus != null) 'wageStatus': wageStatus,
      });

      final rawItems = (result.data['items'] as List? ?? []);
      final allRecords = rawItems.whereType<Map>().map((m) {
        final raw = _cfHydrate(Map<String, dynamic>.from(m));
        final id = raw.remove('id') as String? ?? '';
        return AttendanceModel.tryFromMap(raw, id);
      }).whereType<AttendanceModel>().toList();

      // [FIX-MEDIUM-01] CF는 전체 레코드 반환 — cursor 기반 슬라이싱 제거
      // 이전 버그: cursor!=null에서도 첫 페이지 재반환 → load more 시 중복 데이터 누적
      return PayrollPage(records: allRecords, hasMore: false);
    } catch (e) {
      debugPrint('❌ 급여 현황 조회 실패: $e');
      rethrow; // 0건 반환 시 관리자가 급여 없는 것으로 오인 → 에러 전파
    }
  }

  // ══════════════════════════════════════════════════════════
  // 오늘 처리할 송금 조회
  // ══════════════════════════════════════════════════════════

  /// 오늘 지급 예정 건수 (배지용)
  /// [CF 이전 2026-07-13] callableGetAdminAttendances (paymentDueDateLteMs + wageStatus)
  Future<int?> getTodayPaymentCount({
    required String businessId,
    DateTime? referenceDate,
  }) async {
    try {
      final ref = referenceDate ?? DateTime.now();
      final todayEnd = DateTime(ref.year, ref.month, ref.day, 23, 59, 59);
      final result = await _cf.httpsCallable('callableGetAdminAttendances',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
          .call<Map<String, dynamic>>({
        'businessId': businessId,
        'paymentDueDateLteMs': todayEnd.millisecondsSinceEpoch,
        'wageStatus': AttendanceModel.wageConfirmed,
      });
      return (result.data['items'] as List? ?? []).length;
    } catch (e) {
      debugPrint('❌ 오늘 지급 건수 조회 실패: $e');
      return null; // 0 반환 시 지급 건 없는 것으로 오인 → null로 미조회 상태 구분
    }
  }

  // ══════════════════════════════════════════════════════════
  // CSV 내보내기
  // ══════════════════════════════════════════════════════════

  /// CSV Injection 방지: =, +, -, @ 시작 데이터에 작은따옴표 접두어 추가
  /// [BUG-FIX] RFC 4180: 필드 내 큰따옴표(") → "" 이스케이프 추가
  static String _sanitizeCsvField(String value) {
    if (value.isEmpty) return value;
    // RFC 4180: 큰따옴표를 포함하는 필드는 "" 로 이스케이프 (generateTransferCsv가 필드를 " "로 감싸므로 필수)
    final escaped = value.replaceAll('"', '""');
    final c = escaped[0];
    if (c == '=' || c == '+' || c == '-' || c == '@') return "'$escaped";
    return escaped;
  }

  /// 이체 목록 CSV 생성 (미이체 근무자만)
  /// 형식: 은행, 계좌번호, 예금주, 금액, 메모
  static String generateTransferCsv(List<TransferRow> rows) {
    final buf = StringBuffer();
    buf.writeln('이름,은행명,계좌번호,예금주,이체금액,메모');
    for (final r in rows) {
      buf.writeln(
          '"${_sanitizeCsvField(r.workerName)}","${_sanitizeCsvField(r.bankName)}","${r.accountNumber}",'
          '"${_sanitizeCsvField(r.accountHolder)}",${r.netAmount},"${_sanitizeCsvField(r.memo)}"');
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

  // [RULE-FIX-CF 2026-07-13] Firestore 직접 쿼리 → CF 이전
  // filters.businessId null 반환 PERMISSION_DENIED 방지
  Future<List<PaymentChangeRequestModel>> getPendingChangeRequests(
      String businessId) async {
    try {
      final callable = _cf.httpsCallable(
        'callableGetPaymentChangeRequests',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': businessId,
        'status': PaymentChangeRequestModel.statusPending,
      });
      final rawItems = (result.data['items'] as List? ?? []);
      return rawItems
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return PaymentChangeRequestModel.tryFromMap(raw, id);
          })
          .whereType<PaymentChangeRequestModel>()
          .toList();
    } catch (e) {
      debugPrint('❌ 변경 요청 조회 실패: $e');
      return [];
    }
  }

  /// 변경 요청 승인
  /// [PAY-H2] 트랜잭션으로 PENDING 상태 확인 후 update — 동시 이중 승인 + 감사 추적 오염 차단
  Future<void> approveChangeRequest({
    required String requestId,
    required String processedBy,
  }) async {
    final ref = _db.collection('payment_change_requests').doc(requestId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('변경 요청 문서가 존재하지 않습니다.');
      final currentStatus = snap.data()?['status'] as String?;
      if (currentStatus != PaymentChangeRequestModel.statusPending) {
        throw Exception('이미 처리된 요청입니다. (현재 상태: $currentStatus)');
      }
      tx.update(ref, {
        'status':      PaymentChangeRequestModel.statusApproved,
        'processedBy': processedBy,
        'processedAt': FieldValue.serverTimestamp(),
        'updatedAt':   FieldValue.serverTimestamp(),
      });
    });
  }

  /// 변경 요청 거절
  // [M2-FIX] approveChangeRequest와 동일하게 트랜잭션 래핑
  //   approve(트랜잭션) vs reject(직접 update) 비대칭 → 동시 approve+reject 시 APPROVED 문서를 REJECTED로 덮어쓰는 race condition.
  //   트랜잭션 내 status == PENDING 확인으로 방어.
  Future<void> rejectChangeRequest({
    required String requestId,
    required String processedBy,
    required String rejectReason,
  }) async {
    await _db.runTransaction((tx) async {
      final ref = _db.collection('payment_change_requests').doc(requestId);
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('변경 요청을 찾을 수 없습니다.');
      final currentStatus = snap.data()?['status'] as String? ?? '';
      if (currentStatus != PaymentChangeRequestModel.statusPending) {
        throw Exception('이미 처리된 요청입니다. (현재 상태: $currentStatus)');
      }
      tx.update(ref, {
        'status':       PaymentChangeRequestModel.statusRejected,
        'processedBy':  processedBy,
        'processedAt':  FieldValue.serverTimestamp(),
        'rejectReason': rejectReason,
        'updatedAt':    FieldValue.serverTimestamp(),
      });
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

  /// 중간정산 요청 생성 (CF 경유) — [SECURITY-1 수정] 서버사이드 ownership 검증
  Future<String> requestInterimSettlement({
    required String applicationId,
    required String businessId,
    required List<String> attendanceIds,
    required int requestedAmount,
    required int netAmount,
    String? requestReason,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final callable = _cf.httpsCallable(
      'callableRequestInterimSettlement',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    final result = await callable.call<Map<String, dynamic>>({
      'applicationId': applicationId,
      'businessId': businessId,
      'attendanceIds': attendanceIds,
      'requestedAmount': requestedAmount,
      'netAmount': netAmount,
      if (requestReason != null && requestReason.isNotEmpty)
        'requestReason': requestReason,
      'periodStart': periodStart.toIso8601String(),
      'periodEnd': periodEnd.toIso8601String(),
    });
    return result.data['requestId'] as String;
  }

  /// 내 중간정산 요청 목록 조회 (근로자용 CF 경유)
  Future<List<InterimSettlementRequestModel>> getMyInterimSettlements({
    String? businessId,
  }) async {
    try {
      final callable = _cf.httpsCallable(
        'callableGetMyInterimSettlements',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final result = await callable.call<Map<String, dynamic>>({
        if (businessId != null) 'businessId': businessId,
      });
      final rawItems = (result.data['items'] as List? ?? []);
      return rawItems
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return InterimSettlementRequestModel.tryFromMap(raw, id);
          })
          .whereType<InterimSettlementRequestModel>()
          .toList();
    } catch (e) {
      debugPrint('❌ 내 중간정산 목록 조회 실패: $e');
      return [];
    }
  }

  /// 중간정산 승인 (CF 경유) — PENDING → APPROVED + 이체예정일 설정 + 근로자 FCM
  Future<void> approveInterimSettlementWithDate({
    required InterimSettlementRequestModel req,
    required DateTime scheduledTransferDate,
    String? transferNote,
  }) async {
    final callable = _cf.httpsCallable(
      'callableApproveInterimSettlement',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    await callable.call({
      'settlementRequestId': req.id,
      'businessId': req.businessId,
      // CF는 YYYY-MM-DD 형식만 허용 (시간대 혼선 방지)
      'scheduledTransferDate':
          '${scheduledTransferDate.year}-'
          '${scheduledTransferDate.month.toString().padLeft(2, '0')}-'
          '${scheduledTransferDate.day.toString().padLeft(2, '0')}',
      if (transferNote != null && transferNote.isNotEmpty) 'transferNote': transferNote,
    });
  }

  /// 중간정산 이체 처리 (CF 경유) — APPROVED → PROCESSED + attendance wageTransferred (원자적)
  Future<void> processInterimSettlement({
    required InterimSettlementRequestModel req,
    String? transferNote,
  }) async {
    final callable = _cf.httpsCallable(
      'callableProcessInterimSettlement',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );
    await callable.call({
      'settlementRequestId': req.id,
      'businessId': req.businessId,
      if (transferNote != null && transferNote.isNotEmpty) 'transferNote': transferNote,
    });
  }

  // [RULE-FIX-CF 2026-07-13] Firestore 직접 쿼리 → CF 이전
  // PENDING+APPROVED 병렬 쿼리 → CF 서버사이드 병합으로 교체
  Future<List<InterimSettlementRequestModel>> getPendingSettlementRequests(
      String businessId) async {
    try {
      final callable = _cf.httpsCallable(
        'callableGetInterimSettlements',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final result = await callable.call<Map<String, dynamic>>({'businessId': businessId});
      final rawItems = (result.data['items'] as List? ?? []);
      return rawItems
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return InterimSettlementRequestModel.tryFromMap(raw, id);
          })
          .whereType<InterimSettlementRequestModel>()
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
    // [087] 멱등성 보호 — 이미 처리된 요청 이중 처리 방지
    final reqSnap = await _db
        .collection('interim_settlement_requests')
        .doc(req.id)
        .get(const GetOptions(source: Source.server));
    if (!reqSnap.exists) {
      throw Exception('중간정산 요청을 찾을 수 없습니다.');
    }
    final currentStatus = reqSnap.data()!['status'] as String?;
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
    bool zeroTransfer = false; // 실질 이체 0건(모든 항목 취소) 여부
    List<String> idsToTransfer = List.from(req.attendanceIds);

    // attendanceIds의 현재 wageStatus를 서버에서 조회 (L454에서 isEmpty 시 throw하므로 항상 비어있지 않음)
    final attSnaps = await Future.wait(
      req.attendanceIds.map(
        (id) => _db
            .collection('attendance')
            .doc(id)
            .get(const GetOptions(source: Source.server)),
      ),
    );
    {
      // [HIGH-BUG1] userId 교차검증 — 요청의 workerId와 attendance.userId 일치 여부 검사
      // 다른 워커의 attendanceId가 포함된 경우 필터링
      final validSnaps = attSnaps
          .where((s) => s.data()?['userId'] == req.workerId)
          .toList();
      final allTransferred = validSnaps.isNotEmpty &&
          validSnaps.every((s) => s.data()?['wageStatus'] == AttendanceModel.wageTransferred);
      if (allTransferred) {
        // 모든 항목이 이미 transferred → 1단계 건너뛰고 status만 PROCESSED로 복구
        skipMarkTransferred = true;
        // [BUG-FIX-A006] allTransferred=true 시 idsToTransfer를 validSnaps 기반으로 갱신
        // 초기값 List.from(req.attendanceIds)는 타 워커 attendanceId를 포함할 수 있어
        // FCM 금액 계산(아래 actualNetAmount)에서 타 워커 finalWage가 합산되는 버그
        idsToTransfer = validSnaps.map((s) => s.id).toList();
      } else {
        // wageConfirmed 항목만 이체 처리 — 취소된(wagePending 등) 항목 및 타 워커 항목 제외
        idsToTransfer = validSnaps
            .where((s) => s.data()?['wageStatus'] == AttendanceModel.wageConfirmed)
            .map((s) => s.id)
            .toList();
        if (idsToTransfer.isEmpty) { skipMarkTransferred = true; zeroTransfer = true; }
      }
    }
    // [I-01] skipMarkTransferred=true 시 이체 0건인데도 status=PROCESSED 마킹됨.
    // 요청 생성 후 관리자가 모든 attendances를 wagePending으로 취소한 케이스가 해당.
    // UI 레이어(payroll_worker_detail_screen)에서 settleableRecords 차단이 있으나
    // 서비스 직접 호출 경로에서는 방어 없음. 운영상 발생 빈도 낮음.

    // 1단계: 출근기록 이체 처리 먼저 — attendance 성공 후 요청 상태 변경
    // (역순 시 실패 모드: attendance=미이체인데 status=processed → 미지급 상태 숨김)
    // ⚠️ 원자성 없음: 1단계 성공 + 2단계 실패 시 attendance=transferred, status=pending 불일치 발생.
    // 단, markTransferredBatch는 멱등(이미 transferred인 건을 덮어써도 안전)하므로,
    // 재시도 시 1단계가 재실행되어도 중복 이체 없이 2단계까지 정상 완료된다.
    if (!skipMarkTransferred) {
      await markTransferredBatch(
        attendanceIds: idsToTransfer,
        businessId: req.businessId,
        transferNote: transferNote ?? '중간정산 처리',
      );
    }

    // 2단계: 요청 상태 변경 (트랜잭션) — 동시 승인 경합 시 FCM 중복 발송 방지
    // ⚠️ 1단계 성공 후 여기서 실패하면 attendance=transferred, status=pending 불일치.
    //   단, 멱등 재시도로 안전하게 복구되므로 관리자에게 "재시도 안내" 메시지 전달.
    // [MEDIUM-FIX] 동시 승인: 두 번째 관리자는 트랜잭션 내에서 statusTransitioned=false로
    //   종료 → 3단계 FCM 발송 건너뜀 (이미 처리된 경우)
    bool statusTransitioned = false;
    try {
      final docRef = _db.collection('interim_settlement_requests').doc(req.id);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        final current = snap.data()?['status'] as String?;
        if (current == InterimSettlementRequestModel.statusProcessed) return;
        tx.update(docRef, {
          'status':      InterimSettlementRequestModel.statusProcessed,
          'processedBy': processedBy,
          'processedAt': FieldValue.serverTimestamp(),
          if (transferNote != null) 'transferNote': transferNote,
          'updatedAt':   FieldValue.serverTimestamp(),
        });
        statusTransitioned = true;
      });
    } catch (e) {
      // 이체 자체는 완료됐으므로 재시도 시 중복 이체 없이 안전하게 복구됨
      throw Exception(
        '이체는 완료되었으나 상태 업데이트에 실패했습니다.\n'
        '다시 시도하면 안전하게 처리됩니다. ($e)',
      );
    }

    // 3단계: 근로자에게 중간정산 완료 알림 발송 (실패해도 이체 자체에 영향 없음)
    try {
      // 동시 승인 경합에서 두 번째 승인자 또는 실질 이체 0건 — FCM 발송 생략
      if (!statusTransitioned || zeroTransfer) return;

      // 실제 이체된 항목의 finalWage 합산 — req.netAmount(요청 시점 추정치)보다 정확
      final actualNetAmount = idsToTransfer.isNotEmpty
          ? attSnaps
              .where((s) => idsToTransfer.contains(s.id))
              .fold<int>(0, (acc, s) => acc + ((s.data()?['finalWage'] as num?)?.toInt() ?? 0))
          : req.netAmount; // 전부 이미 transferred인 재시도 케이스 — req.netAmount 재사용
      final notification = NotificationModel.createInterimSettlementCompleted(
        userId: req.workerId,
        workerName: req.workerName,
        businessName: req.businessName,
        businessId: req.businessId,
        netAmount: actualNetAmount,
        periodStart: req.periodStart,
        periodEnd: req.periodEnd,
        settlementRequestId: req.id,
      );
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('createNotification',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
          .call(notification.toMap());
    } catch (e) {
      debugPrint('⚠️ 중간정산 완료 알림 발송 실패 (이체는 완료): $e');
    }
  }

  /// 중간정산 거절
  // [BUG-2 FIX] 거절 시 근로자에게 FCM 알림 발송 추가 (이전 구현에서 누락됨)
  Future<void> rejectInterimSettlement({
    required InterimSettlementRequestModel req,
    required String processedBy,
    required String rejectReason,
  }) async {
    final ref = _db.collection('interim_settlement_requests').doc(req.id);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw Exception('중간정산 요청을 찾을 수 없습니다.');
      }
      if (snap.data()!['status'] != InterimSettlementRequestModel.statusPending) {
        throw Exception('이미 처리된 요청입니다.');
      }
      tx.update(ref, {
        'status':       InterimSettlementRequestModel.statusRejected,
        'processedBy':  processedBy,
        'processedAt':  FieldValue.serverTimestamp(),
        'rejectReason': rejectReason,
        'updatedAt':    FieldValue.serverTimestamp(),
      });
    });
    // 거절 알림 발송 (실패해도 거절 자체에 영향 없음)
    try {
      final notification = NotificationModel.createInterimSettlementRejected(
        userId: req.workerId,
        businessName: req.businessName,
        businessId: req.businessId,
        settlementRequestId: req.id,
        periodStart: req.periodStart,
        periodEnd: req.periodEnd,
        rejectReason: rejectReason.isNotEmpty ? rejectReason : null,
      );
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('createNotification',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
          .call(notification.toMap());
    } catch (e) {
      debugPrint('⚠️ 중간정산 거절 알림 발송 실패 (거절 자체는 완료): $e');
    }
  }
}

// ─── 이체 완료 알림 정보 ──────────────────────────────────────────
// [BUG-수정] 급여 이체 완료 후 지원자 알림 발송

/// markTransferredBatch 알림 발송용 개별 근무자 정보
class TransferNotificationInfo {
  final String workerUserId;
  final String workerName;
  final String businessName;
  final String businessId;
  final int finalWage;
  final String? applicationId;
  // [MEDIUM-3] CF에서 실제 처리된 attendanceId에만 알림 발송하도록 필터링
  final String attendanceId;

  const TransferNotificationInfo({
    required this.workerUserId,
    required this.workerName,
    required this.businessName,
    required this.businessId,
    required this.finalWage,
    required this.attendanceId,
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
      businessId: r.businessId,
      finalWage: net,
      attendanceId: r.id,
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
      if (kDebugMode) debugPrint('⚠️ [이체] 은행정보 없음 — uid 해시: ${uid.hashCode}, 급여 ${recs.length}건 제외');
      continue;
    }

    final totalNet = recs.fold<int>(0, (acc, r) {
      final wd = r.wageDetail;
      if (wd == null) return acc;
      return acc + wd.effectiveNetWage;
    });

    if (totalNet <= 0) continue;

    // [MEDIUM-3-FIX] CF 반환 순서에 의존하지 않도록 workDate 오름차순 정렬
    recs.sort((a, b) => a.workDate.compareTo(b.workDate));
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
