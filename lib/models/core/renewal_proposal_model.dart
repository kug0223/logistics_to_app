// [RENEWAL-PROPOSAL-COMMITMENT] 연장 제안.
//
//   관리자가 연장 버튼을 누르면 곧바로 새 계약(CONTRACT_PENDING)이
//   만들어졌다. 그런데 그 상태는 좌석이 있고, 출근할 수 있고, 결근
//   대상이 되는 상태다 — 근로자는 아직 아무 말도 하지 않았는데.
//
//     관리자 제안   = 약속 아님
//     근로자 수락   = 약속 성립
//     전자계약 서명 = 약속의 문서화
//
//   이 문서는 그 가운데 단계를 담는다.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/format_helper.dart';
import '../../utils/firestore_helper.dart';

class RenewalProposalStatus {
  static const pending = 'PENDING';
  static const accepted = 'ACCEPTED';
  static const declined = 'DECLINED';
  static const stale = 'STALE';
  static const superseded = 'SUPERSEDED';
  static const canceled = 'CANCELED';
}

class RenewalProposalModel {
  final String id;
  final String businessId;
  final String businessName;
  final String workerUid;
  final String oldApplicationId;

  /// 저장된 상태. **행동 가능 여부는 [effectiveStatus] 로 판단한다.**
  final String status;

  final DateTime effectiveStart;
  final DateTime effectiveEnd;

  // ── 약속 snapshot — 원본 계약에서 승계한 값 ──────────────────────
  final String? selectedWorkType;
  final List<String>? workDays;
  final String? startTime;
  final String? endTime;
  final int? breakMinutes;
  final int? wage;
  final String? wageType;
  final String? taxDeductionType;
  final String? toId;
  final String? toTitle;

  final String? proposedByUid;
  final DateTime? proposedAt;
  final DateTime? respondedAt;
  final String? newApplicationId;

  const RenewalProposalModel({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.workerUid,
    required this.oldApplicationId,
    required this.status,
    required this.effectiveStart,
    required this.effectiveEnd,
    this.selectedWorkType,
    this.workDays,
    this.startTime,
    this.endTime,
    this.breakMinutes,
    this.wage,
    this.wageType,
    this.taxDeductionType,
    this.toId,
    this.toTitle,
    this.proposedByUid,
    this.proposedAt,
    this.respondedAt,
    this.newApplicationId,
  });

  /// 지금 정말 응답할 수 있는 상태인가.
  ///
  /// 저장이 PENDING 이어도 효력일이 지났으면 수락할 수 없다 — 수락하면
  /// 아무도 근무하지 않은 날이 근무일이 된다. 서버가 같은 판정을 하고
  /// 거절하므로, 화면이 먼저 알려 준다.
  ///
  /// 시작일이 **오늘**이면 그 날의 근무 시작시각까지만 유효하다.
  String effectiveStatusAt(DateTime now) {
    if (status != RenewalProposalStatus.pending) return status;
    final startOnly = FormatHelper.toKstDate(effectiveStart);
    final todayOnly = FormatHelper.toKstDate(now);
    if (startOnly.isBefore(todayOnly)) return RenewalProposalStatus.stale;
    if (startOnly.isAfter(todayOnly)) return RenewalProposalStatus.pending;

    final days = workDays;
    if (days != null &&
        days.isNotEmpty &&
        !days.contains(FormatHelper.weekday(now))) {
      return RenewalProposalStatus.pending;
    }
    final t = startTime;
    if (t == null) return RenewalProposalStatus.pending;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
    if (m == null) return RenewalProposalStatus.pending;
    final kstNow = now.toUtc().add(const Duration(hours: 9));
    final nowMinutes = kstNow.hour * 60 + kstNow.minute;
    final shiftMinutes =
        int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
    return nowMinutes > shiftMinutes
        ? RenewalProposalStatus.stale
        : RenewalProposalStatus.pending;
  }

  bool isActionableAt(DateTime now) =>
      effectiveStatusAt(now) == RenewalProposalStatus.pending;

  /// 한 건이 깨졌다고 목록 전체를 잃지 않는다.
  static RenewalProposalModel? tryFromMap(Map<String, dynamic> m, String id) {
    try {
      final start = parseTimestampNullable(m['effectiveStart']);
      final end = parseTimestampNullable(m['effectiveEnd']);
      if (start == null || end == null) return null;
      return RenewalProposalModel(
        id: id,
        businessId: m['businessId'] as String? ?? '',
        businessName: m['businessName'] as String? ?? '',
        workerUid: m['workerUid'] as String? ?? '',
        oldApplicationId: m['oldApplicationId'] as String? ?? '',
        status: m['status'] as String? ?? RenewalProposalStatus.pending,
        effectiveStart: start,
        effectiveEnd: end,
        selectedWorkType: m['selectedWorkType'] as String?,
        workDays: (m['workDays'] as List?)?.whereType<String>().toList(),
        startTime: m['startTime'] as String?,
        endTime: m['endTime'] as String?,
        breakMinutes: (m['breakMinutes'] as num?)?.toInt(),
        wage: (m['wage'] as num?)?.toInt(),
        wageType: m['wageType'] as String?,
        taxDeductionType: m['taxDeductionType'] as String?,
        toId: m['toId'] as String?,
        toTitle: m['toTitle'] as String?,
        proposedByUid: m['proposedByUid'] as String?,
        proposedAt: parseTimestampNullable(m['proposedAt']),
        respondedAt: parseTimestampNullable(m['respondedAt']),
        newApplicationId: m['newApplicationId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  static RenewalProposalModel? tryFromFirestore(DocumentSnapshot doc) {
    final data = doc.data();
    if (data is! Map<String, dynamic>) return null;
    return tryFromMap(data, doc.id);
  }
}
