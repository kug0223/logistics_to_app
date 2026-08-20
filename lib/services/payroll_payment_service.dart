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
  /// [반환값] CF가 계좌 정보 미확인으로 건너뛴 attendanceId 목록 (비어 있으면 전원 이체 완료)
  Future<List<String>> markTransferredBatch({
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
    final List<String> allSkipped = [];   // 계좌 미확인으로 건너뛴 attendanceId
    for (int i = 0; i < attendanceIds.length; i += 200) {
      final chunk = attendanceIds.skip(i).take(200).toList();
      // [FIX] 알림 포함 여부를 await 이전에 결정·잠금:
      // 이전 코드는 CF 실패 시 notificationsSent=false 유지 → 다음 청크가
      // 전체 근로자에게 허위 이체완료 알림 발송하는 버그
      // [BUG-FIX] null 체크만으로는 빈 배열([])도 통과 → 0건 알림 발송 버그
      final bool sendNotifs = !notificationsSent && (allNotifications?.isNotEmpty ?? false);
      try {
        final result = await _cf.httpsCallable('callableMarkTransferredBatch').call({
          'businessId': businessId,
          'attendanceIds': chunk,
          if (transferNote != null && transferNote.isNotEmpty) 'transferNote': transferNote,
          if (sendNotifs) 'notifications': allNotifications,
        });
        // [BUG-FIX] notificationsSent = true를 await 성공 후로 이동
        // await 이전에 설정하면 첫 청크 실패 시 이후 청크에서 알림을 전혀 발송하지 않음
        if (sendNotifs) notificationsSent = true;
        // CF 응답에서 계좌 미확인 skip 목록 수집
        final data = result.data as Map<dynamic, dynamic>? ?? {};
        final skipped = (data['skipped'] as List?)?.cast<String>() ?? [];
        allSkipped.addAll(skipped);
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
    return allSkipped;
  }

  /// 이체 취소 — transferred → confirmed (CF callableCancelTransfer 경유)
  /// firestore.rules 클라이언트 직접 역전환 전면 차단 → Admin SDK CF 경유만 가능
  Future<void> cancelTransfer({
    required String attendanceId,
    required String businessId,
    required String cancelNote,
  }) async {
    await _cf
        .httpsCallable(
          'callableCancelTransfer',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
        )
        .call({
      'attendanceId': attendanceId,
      'businessId': businessId,
      'cancelNote': cancelNote,
    });
  }

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

  /// 미이체(wageStatus=confirmed) 건수 (홈 배지용) — callableGetNotTransferredCount 경유
  /// attendance.businessId 단일 필터 → wageStatus만 읽고 서버 카운트 (복합 인덱스 불필요)
  Future<int?> getTotalNotTransferredCount({required String businessId}) async {
    try {
      final result = await _cf
          .httpsCallable('callableGetNotTransferredCount',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 20)))
          .call<Map<String, dynamic>>({'businessId': businessId});
      return (result.data['count'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('❌ 미이체 건수 조회 실패: $e');
      return null;
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

  // [CF-MIGRATION 2026-08-10] createInterimSettlementRequest 제거
  // → 관리자 직접 정산은 callableAdminDirectInterimSettlement CF 경유
  // → 근로자 요청은 callableRequestInterimSettlement CF 경유 (requestInterimSettlement 참고)

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

  // [CF-MIGRATION 2026-08-10] approveInterimSettlement 제거
  // → 관리자 직접 정산 경로는 adminDirectSettlement()로 일원화
  // → 근로자 요청 승인 경로는 PayrollPaymentDashboard에서 callableApproveInterimSettlement 직접 호출

  /// 관리자 직접 중간정산 — CF callableAdminDirectInterimSettlement 경유
  /// [Trust Boundary] attendance 이체 + 정산 문서 생성을 서버에서 원자적으로 처리
  Future<void> adminDirectSettlement({
    required String businessId,
    required String workerId,
    required String workerName,
    required String businessName,
    required String applicationId,
    required List<String> attendanceIds,
    required int netAmount,
  }) async {
    final callable = _cf.httpsCallable(
      'callableAdminDirectInterimSettlement',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    await callable.call<Map<String, dynamic>>({
      'businessId':    businessId,
      'workerId':      workerId,
      'workerName':    workerName,
      'businessName':  businessName,
      'applicationId': applicationId,
      'attendanceIds': attendanceIds,
      'netAmount':     netAmount,
    });
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
