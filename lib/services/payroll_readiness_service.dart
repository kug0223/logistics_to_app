import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/core/attendance_model.dart';

/// [PII-DOC-R1.6.1] 이 문제를 누가 풀 수 있는가.
enum PayrollActor {
  /// 풀 것이 없다 — 지급 준비 완료.
  none,

  /// 근로자가 서류를 고쳐야 한다.
  worker,

  /// 근로자 보완 또는 권한자 수동 확인.
  workerOrReview,

  /// 지급정보는 멀쩡하다 — 관리자가 스냅샷만 갱신하면 된다.
  managerRefresh,
}

PayrollActor _actorOf(String? wire) => switch (wire) {
      'NONE' => PayrollActor.none,
      'WORKER' => PayrollActor.worker,
      'MANAGER_REFRESH' => PayrollActor.managerRefresh,
      _ => PayrollActor.workerOrReview,
    };

/// 한 근로자의 **현재** 지급 준비 상태.
///
///   attendance 문서는 확정 **당시**만 안다. 근로자가 그 뒤 서류를
///   고쳤는지는 여기서만 알 수 있다.
class PayrollReadinessInfo {
  const PayrollReadinessInfo({
    required this.ready,
    required this.state,
    required this.actor,
    required this.accountVersion,
    required this.bankbookVersion,
    this.reason,
  });

  final bool ready;

  /// READY_AUTO | READY_MANUAL | MISSING_* | BANK_* | STALE_*
  final String state;
  final PayrollActor actor;
  final int accountVersion;
  final int bankbookVersion;
  final String? reason;

  static PayrollReadinessInfo fromMap(Map<String, dynamic> m) =>
      PayrollReadinessInfo(
        ready: m['ready'] == true,
        state: (m['state'] ?? 'UNKNOWN') as String,
        actor: _actorOf(m['actor'] as String?),
        accountVersion: (m['accountVersion'] as num?)?.toInt() ?? 0,
        bankbookVersion: (m['bankbookVersion'] as num?)?.toInt() ?? 0,
        reason: m['reason'] as String?,
      );

  /// 이 급여 기록의 지급 스냅샷이 **지금** 기준으로 낡았는가.
  ///
  ///   근거 버전이 없으면 낡았는지 알 수 없다 — 갱신 대상으로 본다.
  ///   (R1.6 이전에 확정된 건)
  bool snapshotNeedsRefresh(AttendanceModel a) {
    if (a.wageStatus == AttendanceModel.wageTransferred) return false;
    if (a.wageStatus != AttendanceModel.wageConfirmed) return false;
    final srcAcc = a.wageAccountSourceBankAccountVersion;
    final srcBb = a.wageAccountSourceBankbookDocumentVersion;
    if (srcAcc == null || srcBb == null) return true;
    return srcAcc != accountVersion || srcBb != bankbookVersion;
  }
}

/// 조회 실패를 "확인 필요"로 바꾸지 않는다 — 별도 목록으로 남긴다.
class PayrollReadinessBatch {
  const PayrollReadinessBatch(this.byUid, this.failedUids, this.loadFailed);

  final Map<String, PayrollReadinessInfo> byUid;
  final List<String> failedUids;

  /// 호출 자체가 실패 — 아무것도 모른다.
  final bool loadFailed;

  static const PayrollReadinessBatch empty = PayrollReadinessBatch(
      <String, PayrollReadinessInfo>{}, <String>[], false);
  static const PayrollReadinessBatch failed = PayrollReadinessBatch(
      <String, PayrollReadinessInfo>{}, <String>[], true);
}

class PayrollReadinessService {
  PayrollReadinessService._();

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// 현재 지급 준비 상태를 근로자 단위로 조회. 최대 200명.
  static Future<PayrollReadinessBatch> loadBatch({
    required String businessId,
    required List<String> workerUids,
  }) async {
    if (workerUids.isEmpty) return PayrollReadinessBatch.empty;
    try {
      final res = await _fn
          .httpsCallable('callableGetPayrollReadinessBatch')
          .call<Map<String, dynamic>>({
        'businessId': businessId,
        'workerUids': workerUids.toSet().take(200).toList(),
      });
      final raw = (res.data['readiness'] as Map?) ?? const {};
      final out = <String, PayrollReadinessInfo>{};
      raw.forEach((k, v) {
        if (v is Map) {
          out['$k'] = PayrollReadinessInfo.fromMap(
              Map<String, dynamic>.from(v));
        }
      });
      final failed = ((res.data['failed'] as List?) ?? const [])
          .map((e) => '$e')
          .toList();
      return PayrollReadinessBatch(out, failed, false);
    } catch (e) {
      debugPrint('❌ 지급 준비 조회 실패: $e');
      return PayrollReadinessBatch.failed;
    }
  }

  /// 확정된 급여의 지급 스냅샷만 현재 계좌로 갱신한다.
  /// 금액·근태는 바뀌지 않는다.
  ///
  /// @return (갱신된 id 목록, 건너뛴 id → 사유)
  static Future<({List<String> refreshed, Map<String, String> skipped})>
      refreshSnapshots({
    required String businessId,
    required List<String> attendanceIds,
  }) async {
    final res = await _fn
        .httpsCallable('callableRefreshWagePaymentSnapshot')
        .call<Map<String, dynamic>>({
      'businessId': businessId,
      'attendanceIds': attendanceIds,
    });
    final refreshed =
        ((res.data['refreshed'] as List?) ?? const []).map((e) => '$e').toList();
    final skippedRaw = (res.data['skipped'] as Map?) ?? const {};
    final skipped = <String, String>{};
    skippedRaw.forEach((k, v) => skipped['$k'] = '$v');
    return (refreshed: refreshed, skipped: skipped);
  }
}
