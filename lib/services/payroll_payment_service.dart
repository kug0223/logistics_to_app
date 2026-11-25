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

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/core/attendance_model.dart';
import '../models/core/payment_change_request_model.dart';
import '../models/core/interim_settlement_request_model.dart';
import '../utils/format_helper.dart';
import '../utils/payroll_due_scope.dart';

/// [PAYROLL-BANNER-COMPLETENESS] 미이체 조회를 끝까지 하지 못했다 — "0건"도 "N건"도 아니다.
class PayrollQueryIncomplete implements Exception {
  const PayrollQueryIncomplete(this.reason, {this.unreadable = const []});
  final String reason;

  /// [PAYROLL-INCOMPLETE-STALE-ACTION] 읽지 못한 급여 기록 — 근태 문서 id 와 오류 **유형**만.
  ///   값·이름·계좌는 담지 않는다. 재시도로 풀리지 않는 데이터 오류를 찾는 재료다.
  final List<({String id, String type})> unreadable;

  /// 관리자에게 보일 짧은 참조 코드(문제 기록 id 들의 해시 앞 6자) — 지원 요청 시 로그와 맞춘다.
  String? get reference {
    if (unreadable.isEmpty) return null;
    final ids = unreadable.map((u) => u.id).toList()..sort();
    return sha256.convert(utf8.encode(ids.join(','))).toString().substring(0, 6);
  }

  @override
  String toString() => 'PayrollQueryIncomplete: $reason'
      '${unreadable.isEmpty ? '' : ' ref=$reference unreadable=${unreadable.length}'}';
}

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

  /// [PERF-A1.F] 급여 근태 **읽기** 한 번을 기다리는 최대 시간.
  ///
  ///   `HttpsCallableOptions(timeout:)` 은 연결이 성립하지 않는 동안에는 적용되지
  ///   않았다 — 서버에 닿지 못하면 기기 TCP 재시도가 끝날 때까지 기다렸다
  ///   (LOCAL 실측 135초, .38 84초). 같은 30초를 화면 쪽에서도 지킨다.
  ///   기다리기만 멈춘다 — 늦게 온 응답은 버려지고 화면은 오류·다시 시도를 보인다.
  ///   읽기 전용이다. 쓰기(이체·정산)에는 쓰지 않는다 — 결과 불명을 실패로 단정하지 않는다.
  static const readWait = Duration(seconds: 30);

  Future<HttpsCallableResult<Map<String, dynamic>>> _readAttendances(
          Map<String, dynamic> data) =>
      _cf
          .httpsCallable('callableGetAdminAttendances',
              options: HttpsCallableOptions(timeout: readWait))
          .call<Map<String, dynamic>>(data)
          .timeout(readWait);

  // ══════════════════════════════════════════════════════════
  // 송금 처리 (이체 완료 처리) — CF callableMarkTransferredBatch 경유
  // confirmed→transferred 법적 상태 전이: Trust Boundary Charter 기준 CF 필수
  // ══════════════════════════════════════════════════════════

  /// 단건 이체 완료 처리 — callableMarkTransferredBatch(attendanceIds 1건) 위임
  ///
  /// [SIM-XFER-COUNT] 서버가 말한 결과(이번에 바꾼 건수·이미 이체된 건)를 돌려준다.
  ///   제외는 여전히 [TransferBlockedException] 으로 올라온다.
  Future<MarkTransferResult> markTransferred({
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
    // [PAYROLL-V3-NAME · O1] 이름은 알림 문구의 장식일 뿐 수신자·대상이 아니다.
    //   이름을 모르면 알림을 빼지 않고 이름 칸만 뺀다 — 화면 대체 문구('이름 확인 불가')나
    //   uid 를 사람 이름처럼 서버로 보내지 않는다. 문구는 서버가 이름 유무로 고른다.
    final name = workerName?.trim();
    final notifications = (workerUserId != null &&
            businessName != null &&
            finalWage != null)
        ? [
            {
              'userId': workerUserId,
              if (name != null && name.isNotEmpty) 'workerName': name,
              'businessName': businessName,
              'businessId': businessId,
              'finalWage': finalWage,
              'attendanceId': attendanceId,
              if (applicationId != null && applicationId.isNotEmpty)
                'applicationId': applicationId,
            }
          ]
        : null;

    final result = await _cf.httpsCallable('callableMarkTransferredBatch').call({
      'businessId': businessId,
      'attendanceIds': [attendanceId],
      if (transferNote != null && transferNote.isNotEmpty) 'transferNote': transferNote,
      if (notifications != null) 'notifications': notifications,
    });
    // [PII-DOC-R0.2] 단건 경로도 제외를 **성공으로 읽지 않는다.**
    //
    //   예전에는 여기서 lockedBySettlement만 봤다. 그래서 다른 이유로
    //   제외된 건은 아무것도 바뀌지 않았는데 화면이 "1건 이체 완료 처리되었습니다"를
    //   띄웠다. legacy를 fail-close하는 순간 이 침묵은 곧바로 거짓말이 된다.
    final data = result.data as Map<dynamic, dynamic>? ?? {};
    final skipped = (data['skipped'] as List?)?.cast<String>() ?? [];
    final already = (data['alreadyTransferred'] as List?)?.cast<String>() ?? [];
    final blocked = (data['blocked'] as Map?) ?? {};

    final processed = (data['processed'] as int?) ?? 0;
    final outcome = MarkTransferResult(
      bankSkipped: const [],
      settlementLocked: const [],
      transferredNow: processed,
      alreadyTransferred: already,
    );
    if (already.contains(attendanceId)) return outcome; // 멱등 — 이미 이체됨
    if (!skipped.contains(attendanceId)) return outcome; // 정상 처리

    final reason = blocked[attendanceId];
    throw TransferBlockedException(
      attendanceId: attendanceId,
      code: reason is String ? reason : null,
    );
  }

  /// 일괄 이체 완료 처리 — callableMarkTransferredBatch(최대 200건/청크) 위임
  // 재시도 시: 이미 transferred된 건은 CF에서 멱등 처리(processed++ 후 skip)
  // 알림은 첫 번째 청크에만 포함 (알림은 attendanceIds 순서와 무관)
  /// [PAY-08] [반환값] CF 처리 결과 — skip 원인 구분 포함
  Future<MarkTransferResult> markTransferredBatch({
    required List<String> attendanceIds,
    required String businessId,
    String? transferNote,
    List<TransferNotificationInfo>? notificationInfos,
  }) async {
    final allNotifications = notificationInfos
        ?.map((n) => {
              'userId': n.workerUserId,
              // [PAYROLL-V3-NAME · O1] 모르는 이름은 보내지 않는다(단건 경로와 같은 규칙).
              if (n.workerName != null && n.workerName!.trim().isNotEmpty)
                'workerName': n.workerName!.trim(),
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
    final List<String> allSkipped = [];             // 전체 skip attendanceId
    final List<String> allLockedBySettlement = [];  // [PAY-08] ISR lock으로 skip된 ID
    // [PREDEVICE-TRANSFER-TRUTH] 이미 이체돼 있던 건 — 새로 처리한 것이 아니다.
    final List<String> allAlreadyTransferred = [];
    // [PII-DOC-R0.2] attendanceId → 제외 사유 토큰
    final Map<String, String> allBlocked = {};
    // [GAP-PAYROLL-BATCH-PARTIAL-FEEDBACK-01] 서버 성공 응답을 받은 청크의 처리 건수 누적
    // 실패 청크는 0건으로 처리 (클라이언트에서 추정 불가)
    int confirmedCount = 0;
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
        // [PAY-08] CF 응답에서 skip 원인 구분 수집
        final data = result.data as Map<dynamic, dynamic>? ?? {};
        final skipped = (data['skipped'] as List?)?.cast<String>() ?? [];
        final locked = (data['lockedBySettlement'] as List?)?.cast<String>() ?? [];
        allSkipped.addAll(skipped);
        allLockedBySettlement.addAll(locked);
        // [PII-DOC-R0.2] 사유를 그대로 옮긴다 — 화면에서 다시 추측하지 않도록.
        final blocked = (data['blocked'] as Map?) ?? {};
        blocked.forEach((k, v) {
          if (k is String && v is String) allBlocked[k] = v;
        });
        // [PREDEVICE-TRANSFER-TRUTH] 서버가 실제로 바꾼 건수를 그대로 쓴다.
        //   예전에는 chunk 크기에서 skip을 뺐는데, 이미 이체돼 있던 건은
        //   skip도 아니어서 새로 처리한 것처럼 세어졌다. 같은 목록을 다시
        //   보내도 늘 "N건 처리"로 보이던 이유다.
        confirmedCount += (data['processed'] as int?) ?? 0;
        allAlreadyTransferred
            .addAll((data['alreadyTransferred'] as List?)?.cast<String>() ?? []);
      } catch (e) {
        final msg = e is FirebaseFunctionsException
            ? (e.message ?? e.code)
            : e.toString();
        debugPrint('⚠️ [markTransferredBatch] 청크 ${i ~/ 200 + 1} 실패: $msg');
        chunkErrors.add('청크 ${i ~/ 200 + 1}: $msg');
      }
    }
    if (chunkErrors.isNotEmpty) {
      // [GAP-PAYROLL-BATCH-PARTIAL-FEEDBACK-01] 부분 성공 정보를 포함한 예외로 throw
      // confirmedCount > 0이면 이전 청크가 성공 완료됨 — caller가 구분하여 표시
      throw PartialBatchException(
        confirmedProcessedCount: confirmedCount,
        chunkErrors: chunkErrors,
      );
    }
    // [PAY-08] bank skip = allSkipped에서 locked 제외
    final bankSkipped = allSkipped.where((id) => !allLockedBySettlement.contains(id)).toList();
    return MarkTransferResult(
      bankSkipped: bankSkipped,
      settlementLocked: allLockedBySettlement,
      transferredNow: confirmedCount,
      alreadyTransferred: allAlreadyTransferred,
      blockedReasons: allBlocked,
    );
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

      final result = await _readAttendances({
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

  /// 오늘(KST)까지 지급 예정인 미이체 건수 (급여 탭 배너)
  ///
  /// [PAYROLL-BANNER-DUE-SCOPE] 배너를 누르면 여는 목록(전체 미이체 + 오늘까지 지급
  ///   예정)과 **같은 조회·같은 조건**으로 센다. 예전에는 기기 로컬 23:59:59 를 기준으로
  ///   서버에 따로 물었고(`paymentDueDateLteMs`), 0원 노쇼도 걸러내지 않았다.
  Future<int?> getTodayPaymentCount({
    required String businessId,
    DateTime? referenceDate,
  }) async {
    try {
      final records = await getAllOutstandingWages(businessId: businessId);
      return PayrollDueScope.dueByToday(
              records, referenceDate ?? PayrollDueScope.now())
          .length;
    } catch (e) {
      debugPrint('❌ 오늘 지급 건수 조회 실패: $e');
      return null; // 0 반환 시 지급 건 없는 것으로 오인 → null로 미조회 상태 구분
    }
  }

  /// 전체 미이체 근태 기록 조회 (홈 "급여 미이체" Action 진입용)
  /// [PHASE-2C] 월 필터 없이 wageStatus=confirmed 전체 조회
  /// 기간: 2020-01-01 ~ 내일 (충분히 넓은 범위, 실제 미이체는 수개월 이내)
  /// [PATCH-R1] CF TWO_YEARS_MS(730일) 제한 준수: 단일 oversized request →
  ///            730일 단위 sequential chunk + merge. calendar-year +2 금지.
  ///            half-open [start, end): next_start = previous_end → gap/duplicate 없음.
  Future<List<AttendanceModel>> getAllOutstandingWages({
    required String businessId,
  }) async {
    try {
      final farPast = DateTime(2020, 1, 1);
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      // 730일 = CF TWO_YEARS_MS(2*365*24*60*60*1000ms)와 정확히 일치.
      // 서버 조건이 > 이므로 730일 == TWO_YEARS_MS는 통과.
      const chunkDuration = Duration(days: 730);

      // [PAYROLL-ALL-UNTRANSFERRED] 구간 경계는 예전과 같다 — 먼저 전부 정한다.
      final ranges = <(DateTime, DateTime)>[];
      DateTime chunkStart = farPast;
      while (chunkStart.isBefore(tomorrow)) {
        DateTime chunkEnd = chunkStart.add(chunkDuration);
        if (chunkEnd.isAfter(tomorrow)) {
          chunkEnd = tomorrow;
        }
        ranges.add((chunkStart, chunkEnd));
        chunkStart = chunkEnd; // half-open: next start = previous end
      }

      // 구간끼리는 서로의 결과를 쓰지 않는다(사업장·구간·급여상태만 입력, 서버는
      //   workDate >= start AND < end). 그래서 함께 보낸다 — 예전에는 앞 구간
      //   응답을 기다려 왕복이 구간 수만큼 쌓였다.
      //   결과는 구간 순서대로 이어 붙인다(각 구간은 서버가 workDate 오름차순) —
      //   직렬일 때와 같은 목록이다. 하나라도 실패하면 전체가 실패다(부분 목록 없음).
      final perRange = await Future.wait(ranges
          .map((r) => _fetchConfirmedRangeComplete(businessId, r.$1, r.$2)));

      return [for (final items in perRange) ...items];
    } catch (e) {
      debugPrint('[PayrollService] getAllOutstandingWages 실패: $e');
      rethrow; // [ERROR-EMPTY-01] caller가 success-empty와 failure를 구분할 수 있도록
    }
  }

  /// [PAYROLL-BANNER-COMPLETENESS] 한 구간을 **끝까지** 읽는다.
  ///
  ///   서버(callableGetAdminAttendances)는 workDate 오름차순으로 최대 10,000건을 주고,
  ///   더 있으면 `limitReached: true` 만 알린다(커서 없음). 예전에는 그 신호를 버려
  ///   잘린 목록이 배너 숫자·전체 미이체 금액이 됐다.
  ///   잘렸으면 받은 마지막 workDate 부터 다시 묻고(그 시각 포함 — id 로 중복 제거),
  ///   더 나아갈 수 없으면(한 시각에 10,000건 초과, 쪽수 상한) 또는 받은 항목을
  ///   읽지 못하면 [PayrollQueryIncomplete] 를 던진다 — 일부를 전체처럼 쓰지 않는다.
  Future<List<AttendanceModel>> _fetchConfirmedRangeComplete(
      String businessId, DateTime start, DateTime end) async {
    const maxPages = 20;
    final byId = <String, AttendanceModel>{};
    var cursorMs = start.millisecondsSinceEpoch;
    for (var page = 0;; page++) {
      if (page >= maxPages) {
        throw const PayrollQueryIncomplete('조회 쪽수 상한을 넘었습니다');
      }
      final result = await _readAttendances({
        'businessId': businessId,
        'startMs': cursorMs,
        'endMs': end.millisecondsSinceEpoch,
        'wageStatus': AttendanceModel.wageConfirmed,
      });
      final rawItems = (result.data['items'] as List? ?? []).whereType<Map>().toList();
      var lastMs = cursorMs;
      final unreadable = <({String id, String type})>[];
      for (final m in rawItems) {
        final raw = _cfHydrate(Map<String, dynamic>.from(m));
        final id = raw.remove('id') as String? ?? '';
        if (id.isEmpty) {
          unreadable.add((id: '(id 없음)', type: 'MISSING_ID'));
          continue;
        }
        AttendanceModel rec;
        try {
          rec = AttendanceModel.fromMap(raw, id);
        } catch (e) {
          // 오류 **유형**만 남긴다 — 메시지에는 값이 섞일 수 있다.
          unreadable.add((id: id, type: e.runtimeType.toString()));
          continue;
        }
        byId[id] = rec;
        final w = rec.workDate.millisecondsSinceEpoch;
        if (w > lastMs) lastMs = w;
      }
      if (unreadable.isNotEmpty) {
        // 읽지 못한 급여를 빼고 세면 그 숫자는 전체가 아니다.
        final err = PayrollQueryIncomplete('읽지 못한 급여 기록이 있습니다', unreadable: unreadable);
        debugPrint('[PAYROLL-INCOMPLETE] ref=${err.reference} biz=$businessId '
            'unreadable=${unreadable.length} '
            '${unreadable.map((u) => '${u.id}:${u.type}').join(',')}');
        throw err;
      }
      if (result.data['limitReached'] != true) break;
      if (lastMs <= cursorMs) {
        throw const PayrollQueryIncomplete('한 시각에 조회 상한을 넘는 기록이 있습니다');
      }
      cursorMs = lastMs;
    }
    final out = byId.values.toList()
      ..sort((a, b) => a.workDate.compareTo(b.workDate));
    return out;
  }

  // [R7-P1-5 후속] `getTotalNotTransferredCount` 를 제거했다.
  //   같은 '미이체' 를 **월 없이 전 기간**으로 세는 세 번째 정의였고, 호출부가
  //   하나도 없었다(홈 배지는 canonical summary 의 unpaidWage 로 옮겨간 뒤였다).
  //   남겨 두면 다음 호출부가 개요·월 상세와 다른 수를 같은 단어로 보여준다.
  //   서버 `callableGetNotTransferredCount` 는 배포 범위라 그대로 두었다(사용 0).

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
  /// [5C.1-PCR-02] CF callableApprovePaymentChangeRequest 경유 (권한+트랜잭션 서버 검증)
  Future<void> approveChangeRequest({
    required String requestId,
    required String businessId,
  }) async {
    await _cf
        .httpsCallable(
          'callableApprovePaymentChangeRequest',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
        )
        .call<Map<String, dynamic>>({
      'businessId': businessId,
      'requestId':  requestId,
    });
  }

  /// 변경 요청 거절
  /// [5C.1-PCR-03] CF callableRejectPaymentChangeRequest 경유 (권한+트랜잭션 서버 검증)
  Future<void> rejectChangeRequest({
    required String requestId,
    required String businessId,
    required String rejectReason,
  }) async {
    await _cf
        .httpsCallable(
          'callableRejectPaymentChangeRequest',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
        )
        .call<Map<String, dynamic>>({
      'businessId':   businessId,
      'requestId':    requestId,
      'rejectReason': rejectReason,
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
    return result.data['settlementRequestId'] as String;
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
      // [R8-P7.2] 빈 목록을 돌려주지 않는다. 이건 돈이다 —
      //   조회가 실패했는데 "중간정산 없음"이라고 말하면 근로자는 신청이
      //   사라진 줄 안다. 실제로 이 경로는 workerId+createdAt 복합 인덱스가
      //   없어 계속 INTERNAL 이었고, 그 사실이 빈 목록에 가려져 있었다.
      debugPrint('❌ 내 중간정산 목록 조회 실패: $e');
      rethrow;
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
      // [R8-P7.2] 돈이다. 조회가 실패했는데 "정산 요청 없음"으로 보이면
      //   관리자가 처리해야 할 요청이 화면에서 사라진다.
      debugPrint('❌ 중간정산 요청 조회 실패: $e');
      rethrow;
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

  /// [PAY-08] APPROVED 중간정산 취소 — attendance lock 해제 + APPROVED → CANCELED
  Future<void> cancelApprovedSettlement({
    required InterimSettlementRequestModel req,
    String? cancelReason,
  }) async {
    final callable = _cf.httpsCallable(
      'callableCancelApprovedInterimSettlement',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    await callable.call({
      'settlementRequestId': req.id,
      'businessId': req.businessId,
      if (cancelReason != null && cancelReason.isNotEmpty) 'cancelReason': cancelReason,
    });
  }

  /// 중간정산 거절
  /// [5C.1-ISR-03] CF callableRejectInterimSettlement 경유 (권한+트랜잭션+알림 서버 처리)
  Future<void> rejectInterimSettlement({
    required InterimSettlementRequestModel req,
    required String rejectReason,
  }) async {
    await _cf
        .httpsCallable(
          'callableRejectInterimSettlement',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
        )
        .call<Map<String, dynamic>>({
      'businessId':   req.businessId,
      'requestId':    req.id,
      'rejectReason': rejectReason,
    });
  }
}

// ─── 이체 처리 결과 ───────────────────────────────────────────────

/// [GAP-PAYROLL-BATCH-PARTIAL-FEEDBACK-01] 일괄 이체 부분 실패 예외
/// 일부 청크가 성공한 뒤 후속 청크가 실패할 때 throw.
/// [confirmedProcessedCount] = 서버 성공 응답을 받은 청크에서 실제 처리된 건수 합계
///   (실패 청크 내부 결과는 클라이언트에서 알 수 없으므로 0으로 처리)
/// [chunkErrors] = 실패한 청크 에러 메시지 목록
class PartialBatchException implements Exception {
  final int confirmedProcessedCount;
  final List<String> chunkErrors;

  const PartialBatchException({
    required this.confirmedProcessedCount,
    required this.chunkErrors,
  });

  @override
  String toString() =>
      '이체 일괄처리 실패 (${chunkErrors.length}개 청크):\n${chunkErrors.join('\n')}';
}

/// [PII-DOC-R0.2] 단건 이체가 서버에서 거절됐다.
///
///   기술 오류가 아니라 **관리자가 복구할 수 있는 업무 상태**다.
///   그래서 예외 메시지를 그대로 토스트에 붙이지 않고, 화면이 [code]로
///   무엇을 해야 하는지 안내한다.
class TransferBlockedException implements Exception {
  final String attendanceId;

  /// 서버 사유 토큰. 구버전 서버 응답이면 null일 수 있다 — 그때도 '알 수 없음'을
  /// '성공'으로 바꾸지는 않는다.
  final String? code;

  const TransferBlockedException({required this.attendanceId, this.code});

  @override
  String toString() =>
      'TransferBlockedException($attendanceId, ${code ?? 'unknown'})';
}

/// [PAY-08] markTransferredBatch 처리 결과 — skip 원인 구분
class MarkTransferResult {
  /// 계좌 정보 미확인으로 제외된 attendanceId 목록
  final List<String> bankSkipped;
  /// 승인된 중간정산 lock으로 제외된 attendanceId 목록 [PAY-08]
  final List<String> settlementLocked;

  /// [PREDEVICE-TRANSFER-TRUTH] 이번 호출에서 실제로 이체 처리된 건수.
  ///
  /// 선택 수에서 skip을 뺀 값이 아니다 — 이미 이체돼 있던 건은 skip도 아니라
  /// 그렇게 세면 재시도가 늘 새 이체처럼 보인다.
  final int transferredNow;

  /// 이미 이체돼 있어 아무것도 바뀌지 않은 건.
  final List<String> alreadyTransferred;

  /// [PII-DOC-R0.2] attendanceId → 서버가 말한 제외 **사유** 토큰.
  ///
  ///   예전에는 id만 돌아와서 화면이 전부 "계좌 정보 미확인"이라는 한 문장으로
  ///   번역했다. legacy 급여와 낡은 검토와 중간정산 lock은 각각 관리자가
  ///   할 일이 다른데 같은 말을 듣고 있었다.
  final Map<String, String> blockedReasons;

  const MarkTransferResult({
    required this.bankSkipped,
    required this.settlementLocked,
    this.transferredNow = 0,
    this.alreadyTransferred = const [],
    this.blockedReasons = const {},
  });

  /// 전체 제외된 attendanceId 목록
  List<String> get allSkipped => [...bankSkipped, ...settlementLocked];

  /// 사유별 건수 — 화면이 사유마다 다른 안내를 하기 위한 집계.
  Map<String, int> get reasonCounts {
    final m = <String, int>{};
    for (final r in blockedReasons.values) {
      m[r] = (m[r] ?? 0) + 1;
    }
    return m;
  }
}

// ─── 이체 완료 알림 정보 ──────────────────────────────────────────
// [BUG-수정] 급여 이체 완료 후 지원자 알림 발송

/// markTransferredBatch 알림 발송용 개별 근무자 정보
class TransferNotificationInfo {
  final String workerUserId;
  /// 알림 문구용 이름. 모르면 null — 서버가 이름 없는 문구를 쓴다(uid·대체 문구를 넣지 않는다).
  final String? workerName;
  final String businessName;
  final String businessId;
  final int finalWage;
  final String? applicationId;
  // [MEDIUM-3] CF에서 실제 처리된 attendanceId에만 알림 발송하도록 필터링
  final String attendanceId;

  const TransferNotificationInfo({
    required this.workerUserId,
    this.workerName,
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
      // [PAYROLL-V3-NAME · O1] 예전: `?? r.userId` — 이름을 모르면 근로자 uid 가 알림 본문에 들어갔다.
      workerName: workerNameByUid[r.userId],
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
@Deprecated(
  '[PII-DOC-R0.1 / INV-2] 이 함수는 현재 User 프로필 계좌로 이체 행을 만든다. '
  '확정된 급여의 지급 계좌는 Attendance 스냅샷이다. '
  'buildTransferExportPlan(transfer_export_plan.dart)을 사용할 것.',
)
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
