/// [CROSS-DOMAIN-R5.3E.2] 확정 근로자 업무 변경 제안.
///
/// Application이 아니다. 제안은 **아직 아무것도 바꾸지 않은 상태**이고,
/// Application으로 표현하면 그 순간 목록·카운터·알림에 활성 관계로 섞인다.
/// 근로자가 수락한 순간에만 서버가 B Application을 만든다.
///
/// 화면은 이 객체에서 "무엇이 달라지는가"만 읽는다. 현재 확정 근무(A)의
/// 진짜 상태는 늘 Application에서 읽는다 — 여기 실린 snapshot은 제안 시점의
/// 값이고, 화면이 A를 그릴 때 쓰는 truth가 아니다.
library;

/// 제안의 한쪽 조건 — A(현재)와 B(제안) 모두 같은 모양으로 담긴다.
class ReassignmentPromise {
  final String? wdId;
  final String? workType;
  final String? startTime;
  final String? endTime;
  final int? wage;
  final String? wageType;
  final int? breakMinutes;
  final int? baseHourlyWage;
  final String? baseHourlyWageMode;

  const ReassignmentPromise({
    this.wdId,
    this.workType,
    this.startTime,
    this.endTime,
    this.wage,
    this.wageType,
    this.breakMinutes,
    this.baseHourlyWage,
    this.baseHourlyWageMode,
  });

  static int? _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : null);

  factory ReassignmentPromise.fromMap(Map<String, dynamic> m) {
    return ReassignmentPromise(
      wdId: m['wdId'] as String?,
      workType: m['workType'] as String?,
      startTime: m['startTime'] as String?,
      endTime: m['endTime'] as String?,
      wage: _int(m['wage']),
      wageType: m['wageType'] as String?,
      breakMinutes: _int(m['breakMinutes']),
      baseHourlyWage: _int(m['baseHourlyWage']),
      baseHourlyWageMode: m['baseHourlyWageMode'] as String?,
    );
  }

  String get timeRange {
    if (startTime == null || endTime == null) return '-';
    return '$startTime~$endTime';
  }
}

/// 제안 상태. 시간 경과만으로는 바뀌지 않는다 — 서버가 행동 시점에 정한다.
enum ReassignmentStatus {
  proposed,
  accepted,
  declined,
  canceledByManager,
  superseded,
  expired,
  unknown,
}

ReassignmentStatus _parseStatus(String? raw) {
  switch (raw) {
    case 'PROPOSED':
      return ReassignmentStatus.proposed;
    case 'ACCEPTED':
      return ReassignmentStatus.accepted;
    case 'DECLINED':
      return ReassignmentStatus.declined;
    case 'CANCELED_BY_MANAGER':
      return ReassignmentStatus.canceledByManager;
    case 'SUPERSEDED':
      return ReassignmentStatus.superseded;
    case 'EXPIRED':
      return ReassignmentStatus.expired;
    default:
      // 모르는 값을 '진행 중'으로 읽지 않는다.
      return ReassignmentStatus.unknown;
  }
}

class ConfirmedReassignmentProposal {
  final String proposalId;
  final ReassignmentStatus status;
  final String uid;
  final String businessId;
  final String businessName;
  final String sourceApplicationId;
  final ReassignmentPromise? current;
  final ReassignmentPromise? proposed;
  final String targetToId;
  final String targetSlotId;
  final String targetWdId;
  final String? compensationOption;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final String? supersededReason;
  final String? resultApplicationId;

  const ConfirmedReassignmentProposal({
    required this.proposalId,
    required this.status,
    required this.uid,
    required this.businessId,
    required this.businessName,
    required this.sourceApplicationId,
    required this.targetToId,
    required this.targetSlotId,
    required this.targetWdId,
    this.current,
    this.proposed,
    this.compensationOption,
    this.createdBy,
    this.createdAt,
    this.expiresAt,
    this.supersededReason,
    this.resultApplicationId,
  });

  static DateTime? _ms(dynamic v) =>
      v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;

  static ReassignmentPromise? _promise(dynamic v) =>
      v is Map ? ReassignmentPromise.fromMap(Map<String, dynamic>.from(v)) : null;

  factory ConfirmedReassignmentProposal.fromMap(Map<String, dynamic> m) {
    return ConfirmedReassignmentProposal(
      proposalId: (m['proposalId'] as String?) ?? '',
      status: _parseStatus(m['status'] as String?),
      uid: (m['uid'] as String?) ?? '',
      businessId: (m['businessId'] as String?) ?? '',
      businessName: (m['businessName'] as String?) ?? '',
      sourceApplicationId: (m['sourceApplicationId'] as String?) ?? '',
      current: _promise(m['sourcePromise']),
      proposed: _promise(m['targetPromise']),
      targetToId: (m['targetToId'] as String?) ?? '',
      targetSlotId: (m['targetSlotId'] as String?) ?? '',
      targetWdId: (m['targetWdId'] as String?) ?? '',
      compensationOption: m['compensationOption'] as String?,
      createdBy: m['createdBy'] as String?,
      createdAt: _ms(m['createdAtMs']),
      expiresAt: _ms(m['expiresAtMs']),
      supersededReason: m['supersededReason'] as String?,
      resultApplicationId: m['resultApplicationId'] as String?,
    );
  }

  /// 파싱 실패가 목록 전체를 깨뜨리지 않게 한다.
  static ConfirmedReassignmentProposal? tryFromMap(Map<String, dynamic> m) {
    try {
      return ConfirmedReassignmentProposal.fromMap(m);
    } catch (_) {
      return null;
    }
  }

  bool get isActionable => status == ReassignmentStatus.proposed;

  /// 이 사람에게만 적용되는 개별 급여인가 — 화면에서 따로 밝힌다.
  bool get hasIndividualCompensation =>
      compensationOption == 'MATCH_SOURCE_WAGE';

  bool get changesWorkType =>
      current?.workType != null &&
      proposed?.workType != null &&
      current!.workType != proposed!.workType;

  bool get changesTime =>
      current?.startTime != proposed?.startTime ||
      current?.endTime != proposed?.endTime;

  bool get changesWage =>
      current?.wage != proposed?.wage || current?.wageType != proposed?.wageType;

  /// 같은 업무명이 여럿일 수 있으므로 identity는 wdId다.
  bool get changesWorkDetail => current?.wdId != proposed?.wdId;
}
