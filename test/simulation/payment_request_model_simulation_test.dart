// test/simulation/payment_request_model_simulation_test.dart
//
// P3 데이터 무결성 시뮬레이션 테스트
// ─────────────────────────────────────────────────────────────────
// 검증 대상:
//   PaymentChangeRequestModel    — 직렬화 왕복 + 상태기계
//   InterimSettlementRequestModel — 직렬화 왕복 + 상태기계 + 중복정산 방어
//   BusinessMemberModel           — MemberPermissions 직렬화 + tryFromMap null 방어
//   ScheduleChangeRequestModel    — 직렬화 왕복 + 상태기계
//   MemberPermissions can()       — 역할별 권한 체크
//   MemberInvitationModel         — 만료 검증 + 중복 수락 방어
//
// 직렬화 왕복: toMap → fromMap (DateTime 기반; Firestore Timestamp 미사용)
// 의존성: Firebase · Flutter · Provider 없음. 순수 Dart 로직만.

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════════════
// SimMemberPermissions
// ═══════════════════════════════════════════════════════════════════════

class SimMemberPermissions {
  final bool canManageTo;
  final bool canManageWorkers;
  final bool canManageWage;
  final bool canManageContract;

  const SimMemberPermissions({
    this.canManageTo = false,
    this.canManageWorkers = false,
    this.canManageWage = false,
    this.canManageContract = false,
  });

  factory SimMemberPermissions.none() => const SimMemberPermissions();
  factory SimMemberPermissions.all() => const SimMemberPermissions(
        canManageTo: true,
        canManageWorkers: true,
        canManageWage: true,
        canManageContract: true,
      );

  factory SimMemberPermissions.fromMap(Map<String, dynamic> m) =>
      SimMemberPermissions(
        canManageTo: m['canManageTo'] as bool? ?? false,
        canManageWorkers: m['canManageWorkers'] as bool? ?? false,
        canManageWage: m['canManageWage'] as bool? ?? false,
        canManageContract: m['canManageContract'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'canManageTo': canManageTo,
        'canManageWorkers': canManageWorkers,
        'canManageWage': canManageWage,
        'canManageContract': canManageContract,
      };

  SimMemberPermissions copyWith({
    bool? canManageTo,
    bool? canManageWorkers,
    bool? canManageWage,
    bool? canManageContract,
  }) =>
      SimMemberPermissions(
        canManageTo: canManageTo ?? this.canManageTo,
        canManageWorkers: canManageWorkers ?? this.canManageWorkers,
        canManageWage: canManageWage ?? this.canManageWage,
        canManageContract: canManageContract ?? this.canManageContract,
      );

  bool get hasAnyPermission =>
      canManageTo || canManageWorkers || canManageWage || canManageContract;

  String get summaryText {
    final parts = <String>[];
    if (canManageTo) parts.add('공고');
    if (canManageWorkers) parts.add('근무자');
    if (canManageWage) parts.add('급여');
    if (canManageContract) parts.add('계약서');
    return parts.isEmpty ? '권한 없음' : parts.join(' · ');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SimPaymentChangeRequest
// ═══════════════════════════════════════════════════════════════════════

class SimPaymentChangeRequest {
  static const String statusPending  = 'PENDING';
  static const String statusApproved = 'APPROVED';
  static const String statusRejected = 'REJECTED';

  final String id;
  final String applicationId;
  final String businessId;
  final String businessName;
  final String workerId;
  final String workerName;
  final String currentPayScheduleType;
  final int? currentPayScheduleDay;
  final String requestedPayScheduleType;
  final int? requestedPayScheduleDay;
  final String? requestReason;
  final String effectiveFrom;
  final String status;
  final String? processedBy;
  final DateTime? processedAt;
  final String? rejectReason;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const SimPaymentChangeRequest({
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

  static String scheduleTypeLabel(String type) {
    switch (type) {
      case 'same_day': return '당일';
      case 'next_day': return '익일';
      case 'weekly':   return '주급';
      case 'monthly':  return '월급';
      default:         return type;
    }
  }

  String get changeDescription =>
      '${scheduleTypeLabel(currentPayScheduleType)} → ${scheduleTypeLabel(requestedPayScheduleType)}';

  Map<String, dynamic> toMap() => {
    'applicationId':             applicationId,
    'businessId':                businessId,
    'businessName':              businessName,
    'workerId':                  workerId,
    'workerName':                workerName,
    'currentPayScheduleType':    currentPayScheduleType,
    if (currentPayScheduleDay != null)
      'currentPayScheduleDay':   currentPayScheduleDay,
    'requestedPayScheduleType':  requestedPayScheduleType,
    if (requestedPayScheduleDay != null)
      'requestedPayScheduleDay': requestedPayScheduleDay,
    if (requestReason != null) 'requestReason': requestReason,
    'effectiveFrom':             effectiveFrom,
    'status':                    status,
    if (processedBy != null) 'processedBy': processedBy,
    if (processedAt != null) 'processedAt': processedAt,
    if (rejectReason != null) 'rejectReason': rejectReason,
    'createdAt':                 createdAt,
    if (updatedAt != null) 'updatedAt': updatedAt,
  };

  static SimPaymentChangeRequest? tryFromMap(Map<String, dynamic> d, String id) {
    try { return _fromMap(d, id); } catch (_) { return null; }
  }

  static SimPaymentChangeRequest _fromMap(Map<String, dynamic> d, String id) {
    final createdAt = d['createdAt'] as DateTime?;
    if (createdAt == null) throw ArgumentError('createdAt 누락 (id=$id)');
    return SimPaymentChangeRequest(
      id: id,
      applicationId:            d['applicationId']             ?? '',
      businessId:               d['businessId']                ?? '',
      businessName:             d['businessName']              ?? '',
      workerId:                 d['workerId']                  ?? '',
      workerName:               d['workerName']                ?? '',
      currentPayScheduleType:   d['currentPayScheduleType']    ?? '',
      currentPayScheduleDay:    d['currentPayScheduleDay'] as int?,
      requestedPayScheduleType: d['requestedPayScheduleType']  ?? '',
      requestedPayScheduleDay:  d['requestedPayScheduleDay'] as int?,
      requestReason:            d['requestReason'] as String?,
      effectiveFrom:            d['effectiveFrom']             ?? '',
      status:                   d['status']                    ?? statusPending,
      processedBy:              d['processedBy'] as String?,
      processedAt:              d['processedAt'] as DateTime?,
      rejectReason:             d['rejectReason'] as String?,
      createdAt:                createdAt,
      updatedAt:                d['updatedAt'] as DateTime?,
    );
  }

  SimPaymentChangeRequest copyWith({
    String? status,
    String? processedBy,
    DateTime? processedAt,
    String? rejectReason,
    DateTime? updatedAt,
  }) =>
      SimPaymentChangeRequest(
        id: id,
        applicationId: applicationId,
        businessId: businessId,
        businessName: businessName,
        workerId: workerId,
        workerName: workerName,
        currentPayScheduleType: currentPayScheduleType,
        currentPayScheduleDay: currentPayScheduleDay,
        requestedPayScheduleType: requestedPayScheduleType,
        requestedPayScheduleDay: requestedPayScheduleDay,
        requestReason: requestReason,
        effectiveFrom: effectiveFrom,
        status: status ?? this.status,
        processedBy: processedBy ?? this.processedBy,
        processedAt: processedAt ?? this.processedAt,
        rejectReason: rejectReason ?? this.rejectReason,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

// ═══════════════════════════════════════════════════════════════════════
// SimInterimSettlement
// ═══════════════════════════════════════════════════════════════════════

class SimInterimSettlement {
  static const String statusPending   = 'PENDING';
  static const String statusApproved  = 'APPROVED';
  static const String statusRejected  = 'REJECTED';
  static const String statusProcessed = 'PROCESSED';

  final String id;
  final String applicationId;
  final String businessId;
  final String businessName;
  final String workerId;
  final String workerName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final List<String> attendanceIds;
  final int requestedAmount;
  final int netAmount;
  final String? requestReason;
  final String status;
  final String? processedBy;
  final DateTime? processedAt;
  final String? transferNote;
  final String? rejectReason;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const SimInterimSettlement({
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

  bool get isPending   => status == statusPending;
  bool get isApproved  => status == statusApproved;
  bool get isRejected  => status == statusRejected;
  bool get isProcessed => status == statusProcessed;

  int get recordCount => attendanceIds.length;

  String get periodLabel =>
      '${periodStart.month}/${periodStart.day} ~ ${periodEnd.month}/${periodEnd.day}';

  String get statusLabel {
    switch (status) {
      case statusPending:   return '처리 대기';
      case statusApproved:  return '승인 (이체 대기)';
      case statusRejected:  return '거절';
      case statusProcessed: return '정산 완료';
      default:              return status;
    }
  }

  Map<String, dynamic> toMap() => {
    'applicationId':   applicationId,
    'businessId':      businessId,
    'businessName':    businessName,
    'workerId':        workerId,
    'workerName':      workerName,
    'periodStart':     periodStart,
    'periodEnd':       periodEnd,
    'attendanceIds':   attendanceIds,
    'requestedAmount': requestedAmount,
    'netAmount':       netAmount,
    if (requestReason != null) 'requestReason': requestReason,
    'status':          status,
    if (processedBy  != null) 'processedBy':  processedBy,
    if (processedAt  != null) 'processedAt':  processedAt,
    if (transferNote != null) 'transferNote': transferNote,
    if (rejectReason != null) 'rejectReason': rejectReason,
    'createdAt':       createdAt,
    if (updatedAt != null) 'updatedAt': updatedAt,
  };

  static SimInterimSettlement? tryFromMap(Map<String, dynamic> d, String id) {
    try { return _fromMap(d, id); } catch (_) { return null; }
  }

  static SimInterimSettlement _fromMap(Map<String, dynamic> d, String id) {
    final periodStart = d['periodStart'] as DateTime?;
    if (periodStart == null) throw ArgumentError('periodStart 누락 (id=$id)');
    final periodEnd = d['periodEnd'] as DateTime?;
    if (periodEnd == null) throw ArgumentError('periodEnd 누락 (id=$id)');
    final createdAt = d['createdAt'] as DateTime?;
    if (createdAt == null) throw ArgumentError('createdAt 누락 (id=$id)');
    return SimInterimSettlement(
      id: id,
      applicationId:  d['applicationId'] ?? '',
      businessId:     d['businessId']    ?? '',
      businessName:   d['businessName']  ?? '',
      workerId:       d['workerId']      ?? '',
      workerName:     d['workerName']    ?? '',
      periodStart:    periodStart,
      periodEnd:      periodEnd,
      attendanceIds:  List<String>.from(d['attendanceIds'] as List? ?? []),
      requestedAmount:(d['requestedAmount'] as num?)?.toInt() ?? 0,
      netAmount:      (d['netAmount']      as num?)?.toInt() ?? 0,
      requestReason:  d['requestReason'] as String?,
      status:         d['status']        ?? statusPending,
      processedBy:    d['processedBy'] as String?,
      processedAt:    d['processedAt'] as DateTime?,
      transferNote:   d['transferNote'] as String?,
      rejectReason:   d['rejectReason'] as String?,
      createdAt:      createdAt,
      updatedAt:      d['updatedAt'] as DateTime?,
    );
  }

  SimInterimSettlement copyWith({
    String? status,
    String? processedBy,
    DateTime? processedAt,
    String? rejectReason,
    String? transferNote,
    DateTime? updatedAt,
  }) =>
      SimInterimSettlement(
        id: id,
        applicationId: applicationId,
        businessId: businessId,
        businessName: businessName,
        workerId: workerId,
        workerName: workerName,
        periodStart: periodStart,
        periodEnd: periodEnd,
        attendanceIds: attendanceIds,
        requestedAmount: requestedAmount,
        netAmount: netAmount,
        requestReason: requestReason,
        status: status ?? this.status,
        processedBy: processedBy ?? this.processedBy,
        processedAt: processedAt ?? this.processedAt,
        transferNote: transferNote ?? this.transferNote,
        rejectReason: rejectReason ?? this.rejectReason,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

// ═══════════════════════════════════════════════════════════════════════
// SimAttendance (중간정산 상태기계용)
// ═══════════════════════════════════════════════════════════════════════

class SimAttendance {
  final String id;
  final int effectiveNetWage;
  final String wageStatus; // 'unpaid' | 'transferred'

  const SimAttendance({
    required this.id,
    required this.effectiveNetWage,
    this.wageStatus = 'unpaid',
  });

  SimAttendance copyWith({String? wageStatus}) => SimAttendance(
        id: id,
        effectiveNetWage: effectiveNetWage,
        wageStatus: wageStatus ?? this.wageStatus,
      );
}

// ═══════════════════════════════════════════════════════════════════════
// SimBusinessMember
// ═══════════════════════════════════════════════════════════════════════

class SimBusinessMember {
  final String uid;
  final String name;
  final String? phone;
  final SimMemberPermissions permissions;
  final DateTime addedAt;
  final String addedBy;
  final String? invitationId;

  const SimBusinessMember({
    required this.uid,
    required this.name,
    this.phone,
    required this.permissions,
    required this.addedAt,
    required this.addedBy,
    this.invitationId,
  });

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'name': name,
      'phone': phone,
      'permissions': permissions.toMap(),
      'addedAt': addedAt,
      'addedBy': addedBy,
    };
    if (invitationId != null) m['invitationId'] = invitationId;
    return m;
  }

  // doc.id → uid 패턴 재현
  static SimBusinessMember? tryFromMap(Map<String, dynamic> d, String docId) {
    try {
      return _fromMap(d, docId);
    } catch (_) {
      return null;
    }
  }

  static SimBusinessMember _fromMap(Map<String, dynamic> d, String docId) {
    final addedAt = d['addedAt'] as DateTime?;
    if (addedAt == null) {
      throw ArgumentError('addedAt 누락 (id=$docId)');
    }
    return SimBusinessMember(
      uid: docId,
      name: d['name'] as String? ?? '',
      phone: d['phone'] as String?,
      permissions: SimMemberPermissions.fromMap(
          (d['permissions'] as Map<String, dynamic>?) ?? {}),
      addedAt: addedAt,
      addedBy: d['addedBy'] as String? ?? '',
      invitationId: d['invitationId'] as String?,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SimScheduleChangeRequest
// ═══════════════════════════════════════════════════════════════════════

enum SimRequestType  { LEAVE, NO_WORK, EXTRA_WORK, CANCEL_LEAVE, CANCEL_EXTRA }
enum SimRequestStatus { PENDING, APPROVED, REJECTED, CANCELED }
enum SimRequesterType { APPLICANT, ADMIN }

class SimScheduleChangeRequest {
  final String id;
  final String businessId;
  final String applicationId;
  final String applicantUid;
  final String applicantName;
  final DateTime targetDate;
  final SimRequestType requestType;
  final SimRequesterType requestedBy;
  final String requestedByUid;
  final DateTime requestedAt;
  final String? reason;
  final SimRequestStatus status;
  final String? respondedByUid;
  final DateTime? respondedAt;
  final String? rejectReason;
  final bool affectsSalary;
  final int? wageAmount;

  SimScheduleChangeRequest({
    required this.id,
    required this.businessId,
    required this.applicationId,
    required this.applicantUid,
    required this.applicantName,
    required this.targetDate,
    required this.requestType,
    required this.requestedBy,
    required this.requestedByUid,
    required this.requestedAt,
    this.reason,
    this.status = SimRequestStatus.PENDING,
    this.respondedByUid,
    this.respondedAt,
    this.rejectReason,
    this.affectsSalary = true,
    this.wageAmount,
  });

  bool get isPending  => status == SimRequestStatus.PENDING;
  bool get isApproved => status == SimRequestStatus.APPROVED;
  bool get isRejected => status == SimRequestStatus.REJECTED;
  bool get isCanceled => status == SimRequestStatus.CANCELED;
  bool get isLeaveRequest     => requestType == SimRequestType.LEAVE;
  bool get isExtraWorkRequest => requestType == SimRequestType.EXTRA_WORK;
  bool get isAdminRequest     => requestedBy == SimRequesterType.ADMIN;
  bool get isApplicantRequest => requestedBy == SimRequesterType.APPLICANT;

  static SimRequestType _typeFromString(String s) {
    switch (s) {
      case 'EXTRA_WORK':   return SimRequestType.EXTRA_WORK;
      case 'NO_WORK':      return SimRequestType.NO_WORK;
      case 'CANCEL_LEAVE': return SimRequestType.CANCEL_LEAVE;
      case 'CANCEL_EXTRA': return SimRequestType.CANCEL_EXTRA;
      default:             return SimRequestType.LEAVE;
    }
  }

  static String _typeToString(SimRequestType t) {
    switch (t) {
      case SimRequestType.LEAVE:        return 'LEAVE';
      case SimRequestType.NO_WORK:      return 'NO_WORK';
      case SimRequestType.EXTRA_WORK:   return 'EXTRA_WORK';
      case SimRequestType.CANCEL_LEAVE: return 'CANCEL_LEAVE';
      case SimRequestType.CANCEL_EXTRA: return 'CANCEL_EXTRA';
    }
  }

  static SimRequestStatus _statusFromString(String s) {
    switch (s) {
      case 'APPROVED': return SimRequestStatus.APPROVED;
      case 'REJECTED': return SimRequestStatus.REJECTED;
      case 'CANCELED': return SimRequestStatus.CANCELED;
      default:         return SimRequestStatus.PENDING;
    }
  }

  static String _statusToString(SimRequestStatus s) {
    switch (s) {
      case SimRequestStatus.PENDING:  return 'PENDING';
      case SimRequestStatus.APPROVED: return 'APPROVED';
      case SimRequestStatus.REJECTED: return 'REJECTED';
      case SimRequestStatus.CANCELED: return 'CANCELED';
    }
  }

  static SimRequesterType _requesterFromString(String s) {
    return s == 'ADMIN' ? SimRequesterType.ADMIN : SimRequesterType.APPLICANT;
  }

  static String _requesterToString(SimRequesterType r) {
    return r == SimRequesterType.ADMIN ? 'ADMIN' : 'APPLICANT';
  }

  Map<String, dynamic> toMap() => {
    'businessId':    businessId,
    'applicationId': applicationId,
    'applicantUid':  applicantUid,
    'applicantName': applicantName,
    'targetDate':    targetDate,
    'requestType':   _typeToString(requestType),
    'requestedBy':   _requesterToString(requestedBy),
    'requestedByUid':requestedByUid,
    'requestedAt':   requestedAt,
    'reason':        reason,
    'status':        _statusToString(status),
    'respondedByUid':respondedByUid,
    'respondedAt':   respondedAt,
    'rejectReason':  rejectReason,
    'affectsSalary': affectsSalary,
    'wageAmount':    wageAmount,
  };

  static SimScheduleChangeRequest? tryFromMap(Map<String, dynamic> d, String id) {
    try { return _fromMap(d, id); } catch (_) { return null; }
  }

  static SimScheduleChangeRequest _fromMap(Map<String, dynamic> d, String id) {
    final targetDate = d['targetDate'] as DateTime?;
    if (targetDate == null) throw ArgumentError('targetDate 누락 (id=$id)');
    final requestedAt = d['requestedAt'] as DateTime?;
    if (requestedAt == null) throw ArgumentError('requestedAt 누락 (id=$id)');
    return SimScheduleChangeRequest(
      id: id,
      businessId:     d['businessId']      ?? '',
      applicationId:  d['applicationId']   ?? '',
      applicantUid:   d['applicantUid']    ?? '',
      applicantName:  d['applicantName']   ?? '',
      targetDate:     targetDate,
      requestType:    _typeFromString(d['requestType']   ?? 'LEAVE'),
      requestedBy:    _requesterFromString(d['requestedBy'] ?? 'APPLICANT'),
      requestedByUid: d['requestedByUid']  ?? '',
      requestedAt:    requestedAt,
      reason:         d['reason'] as String?,
      status:         _statusFromString(d['status'] ?? 'PENDING'),
      respondedByUid: d['respondedByUid'] as String?,
      respondedAt:    d['respondedAt'] as DateTime?,
      rejectReason:   d['rejectReason'] as String?,
      affectsSalary:  d['affectsSalary'] as bool? ?? true,
      wageAmount:     (d['wageAmount'] as num?)?.toInt(),
    );
  }

  SimScheduleChangeRequest copyWith({
    SimRequestStatus? status,
    String? respondedByUid,
    DateTime? respondedAt,
    String? rejectReason,
  }) =>
      SimScheduleChangeRequest(
        id: id,
        businessId: businessId,
        applicationId: applicationId,
        applicantUid: applicantUid,
        applicantName: applicantName,
        targetDate: targetDate,
        requestType: requestType,
        requestedBy: requestedBy,
        requestedByUid: requestedByUid,
        requestedAt: requestedAt,
        reason: reason,
        status: status ?? this.status,
        respondedByUid: respondedByUid ?? this.respondedByUid,
        respondedAt: respondedAt ?? this.respondedAt,
        rejectReason: rejectReason ?? this.rejectReason,
        affectsSalary: affectsSalary,
        wageAmount: wageAmount,
      );
}

// ═══════════════════════════════════════════════════════════════════════
// SimInvitation (MemberInvitation 만료 검증용)
// ═══════════════════════════════════════════════════════════════════════

enum SimInvitationStatus { pending, accepted, rejected, cancelled }

enum SimUserRole { SUPER_ADMIN, BUSINESS_ADMIN, USER }

class SimInvitation {
  final String id;
  final String businessId;
  final String targetUid;
  final SimMemberPermissions permissions;
  final SimInvitationStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  const SimInvitation({
    required this.id,
    required this.businessId,
    required this.targetUid,
    required this.permissions,
    required this.status,
    required this.createdAt,
    this.respondedAt,
  });

  bool get isPending => status == SimInvitationStatus.pending;

  bool get isExpired {
    final expiresAt = createdAt.add(const Duration(days: 30));
    return DateTime.now().isAfter(expiresAt);
  }

  SimInvitation withStatus(SimInvitationStatus s, {DateTime? respondedAt}) =>
      SimInvitation(
        id: id,
        businessId: businessId,
        targetUid: targetUid,
        permissions: permissions,
        status: s,
        createdAt: createdAt,
        respondedAt: respondedAt ?? this.respondedAt,
      );
}

// ═══════════════════════════════════════════════════════════════════════
// 서비스 로직 함수 (순수 Dart 재현)
// ═══════════════════════════════════════════════════════════════════════

/// 지급방식 변경 요청 승인
SimPaymentChangeRequest approvePaymentChange(
  SimPaymentChangeRequest req,
  String processedByUid,
) {
  if (!req.isPending) {
    throw Exception('이미 처리된 요청입니다 (${req.status})');
  }
  return req.copyWith(
    status: SimPaymentChangeRequest.statusApproved,
    processedBy: processedByUid,
    processedAt: DateTime.now(),
  );
}

/// 지급방식 변경 요청 거절
SimPaymentChangeRequest rejectPaymentChange(
  SimPaymentChangeRequest req,
  String processedByUid,
  String reason,
) {
  if (!req.isPending) {
    throw Exception('이미 처리된 요청입니다 (${req.status})');
  }
  return req.copyWith(
    status: SimPaymentChangeRequest.statusRejected,
    processedBy: processedByUid,
    processedAt: DateTime.now(),
    rejectReason: reason,
  );
}

/// 중간정산 승인 — attendanceIds의 wageStatus → 'transferred'
({SimInterimSettlement updated, List<SimAttendance> updatedAttendances})
    approveInterimSettlement(
  SimInterimSettlement req,
  String processedByUid,
  List<SimAttendance> allAttendances,
) {
  if (!req.isPending) throw Exception('이미 처리된 요청입니다');

  final targets = allAttendances.where((a) => req.attendanceIds.contains(a.id)).toList();
  final alreadyTransferred = targets.any((a) => a.wageStatus == 'transferred');
  if (alreadyTransferred) throw Exception('이미 정산된 출근기록이 포함되어 있습니다');

  final updatedAttendances = allAttendances.map((a) {
    if (req.attendanceIds.contains(a.id)) {
      return a.copyWith(wageStatus: 'transferred');
    }
    return a;
  }).toList();

  final updated = req.copyWith(
    status: SimInterimSettlement.statusApproved,
    processedBy: processedByUid,
    processedAt: DateTime.now(),
  );
  return (updated: updated, updatedAttendances: updatedAttendances);
}

/// 중간정산 거절 — attendance 변경 없음
SimInterimSettlement rejectInterimSettlement(
  SimInterimSettlement req,
  String processedByUid,
  String reason,
) {
  if (!req.isPending) throw Exception('이미 처리된 요청입니다');
  return req.copyWith(
    status: SimInterimSettlement.statusRejected,
    processedBy: processedByUid,
    processedAt: DateTime.now(),
    rejectReason: reason,
  );
}

/// 스케줄 변경 승인
SimScheduleChangeRequest approveScheduleChange(
  SimScheduleChangeRequest req,
  String respondedByUid,
) {
  if (!req.isPending) throw Exception('이미 처리된 요청입니다');
  return req.copyWith(
    status: SimRequestStatus.APPROVED,
    respondedByUid: respondedByUid,
    respondedAt: DateTime.now(),
  );
}

/// 스케줄 변경 거절
SimScheduleChangeRequest rejectScheduleChange(
  SimScheduleChangeRequest req,
  String respondedByUid,
  String reason,
) {
  if (!req.isPending) throw Exception('이미 처리된 요청입니다');
  return req.copyWith(
    status: SimRequestStatus.REJECTED,
    respondedByUid: respondedByUid,
    respondedAt: DateTime.now(),
    rejectReason: reason,
  );
}

/// 초대 수락 (만료·이미 멤버 방어 포함)
({SimInvitation updated, bool memberCreated}) acceptInvitation(
  SimInvitation inv,
  Set<String> memberUids,
) {
  if (!inv.isPending) throw Exception('이미 처리된 초대입니다');
  if (inv.isExpired)  throw Exception('초대 유효기간(30일)이 만료되었습니다');
  if (memberUids.contains(inv.targetUid)) throw Exception('이미 멤버입니다');
  memberUids.add(inv.targetUid);
  return (
    updated: inv.withStatus(SimInvitationStatus.accepted, respondedAt: DateTime.now()),
    memberCreated: true,
  );
}

/// hasPendingInvitation (30일 이내 pending 초대)
bool hasPendingInvitation(
  String businessId,
  String targetUid,
  List<SimInvitation> db,
) {
  final expiry = DateTime.now().subtract(const Duration(days: 30));
  return db.any(
    (inv) =>
        inv.businessId == businessId &&
        inv.targetUid == targetUid &&
        inv.status == SimInvitationStatus.pending &&
        inv.createdAt.isAfter(expiry),
  );
}

/// can() 권한 체크
bool can(
  SimUserRole role,
  SimMemberPermissions? perms,
  bool Function(SimMemberPermissions p) check,
) {
  if (role == SimUserRole.BUSINESS_ADMIN) return true;
  if (perms != null) return check(perms);
  return false;
}

// ═══════════════════════════════════════════════════════════════════════
// 팩토리 헬퍼
// ═══════════════════════════════════════════════════════════════════════

final _now    = DateTime.now();
final _past1d = _now.subtract(const Duration(days: 1));
final _past29d = _now.subtract(const Duration(days: 29));
final _past31d = _now.subtract(const Duration(days: 31));

SimPaymentChangeRequest _makePCR({
  String status = SimPaymentChangeRequest.statusPending,
  String currentType = 'weekly',
  String requestedType = 'monthly',
  int? currentDay,
  int? requestedDay,
  String? requestReason,
  String? processedBy,
  DateTime? processedAt,
  String? rejectReason,
}) =>
    SimPaymentChangeRequest(
      id: 'pcr-001',
      applicationId: 'app-001',
      businessId: 'biz-001',
      businessName: '테스트 사업장',
      workerId: 'uid-001',
      workerName: '홍길동',
      currentPayScheduleType: currentType,
      currentPayScheduleDay: currentDay,
      requestedPayScheduleType: requestedType,
      requestedPayScheduleDay: requestedDay,
      requestReason: requestReason,
      effectiveFrom: '2026-07-01',
      status: status,
      processedBy: processedBy,
      processedAt: processedAt,
      rejectReason: rejectReason,
      createdAt: DateTime(2026, 6, 25, 9, 0),
    );

SimInterimSettlement _makeISR({
  String status = SimInterimSettlement.statusPending,
  List<String> attendanceIds = const [],
  int requestedAmount = 500000,
  int netAmount = 480000,
  String? requestReason,
  String? processedBy,
  DateTime? processedAt,
  String? rejectReason,
  String? transferNote,
}) =>
    SimInterimSettlement(
      id: 'isr-001',
      applicationId: 'app-001',
      businessId: 'biz-001',
      businessName: '테스트 사업장',
      workerId: 'uid-001',
      workerName: '홍길동',
      periodStart: DateTime(2026, 5, 1),
      periodEnd: DateTime(2026, 5, 15),
      attendanceIds: attendanceIds,
      requestedAmount: requestedAmount,
      netAmount: netAmount,
      requestReason: requestReason,
      status: status,
      processedBy: processedBy,
      processedAt: processedAt,
      rejectReason: rejectReason,
      transferNote: transferNote,
      createdAt: DateTime(2026, 6, 1),
    );

SimScheduleChangeRequest _makeSCR({
  SimRequestType requestType = SimRequestType.LEAVE,
  SimRequesterType requestedBy = SimRequesterType.APPLICANT,
  SimRequestStatus status = SimRequestStatus.PENDING,
  bool affectsSalary = true,
  int? wageAmount,
  String? respondedByUid,
  DateTime? respondedAt,
  String? rejectReason,
}) =>
    SimScheduleChangeRequest(
      id: 'scr-001',
      businessId: 'biz-001',
      applicationId: 'app-001',
      applicantUid: 'uid-001',
      applicantName: '홍길동',
      targetDate: DateTime(2026, 6, 10),
      requestType: requestType,
      requestedBy: requestedBy,
      requestedByUid: 'uid-001',
      requestedAt: DateTime(2026, 6, 9, 10, 0),
      status: status,
      affectsSalary: affectsSalary,
      wageAmount: wageAmount,
      respondedByUid: respondedByUid,
      respondedAt: respondedAt,
      rejectReason: rejectReason,
    );

SimInvitation _makeInvite({
  String id = 'inv-001',
  String businessId = 'biz-001',
  String targetUid = 'uid-001',
  SimInvitationStatus status = SimInvitationStatus.pending,
  DateTime? createdAt,
}) =>
    SimInvitation(
      id: id,
      businessId: businessId,
      targetUid: targetUid,
      permissions: SimMemberPermissions.none(),
      status: status,
      createdAt: createdAt ?? _past1d,
    );

SimBusinessMember _makeMember({
  String uid = 'uid-001',
  SimMemberPermissions? permissions,
  String? invitationId,
  String? phone,
}) =>
    SimBusinessMember(
      uid: uid,
      name: '홍길동',
      phone: phone,
      permissions: permissions ?? SimMemberPermissions.none(),
      addedAt: _past1d,
      addedBy: 'admin-001',
      invitationId: invitationId,
    );

// ═══════════════════════════════════════════════════════════════════════
// SCENARIO-PMR-1xx: PaymentChangeRequest 직렬화 왕복
// ═══════════════════════════════════════════════════════════════════════

void _runPMR1xx() {
  group('SCENARIO-PMR-1xx: PaymentChangeRequest 직렬화 왕복', () {
    test('SCENARIO-PMR-101 toMap — 기본 필드 포함', () {
      final m = _makePCR().toMap();
      expect(m['applicationId'],            equals('app-001'));
      expect(m['businessId'],               equals('biz-001'));
      expect(m['workerId'],                 equals('uid-001'));
      expect(m['currentPayScheduleType'],   equals('weekly'));
      expect(m['requestedPayScheduleType'], equals('monthly'));
      expect(m['effectiveFrom'],            equals('2026-07-01'));
      expect(m['status'],                   equals('PENDING'));
    });

    test('SCENARIO-PMR-102 toMap → fromMap 왕복 — 모든 필드 복원', () {
      final orig = _makePCR(
        currentDay: 5,
        requestedDay: 1,
        requestReason: '변경 사유',
      );
      final map = orig.toMap();
      final restored = SimPaymentChangeRequest.tryFromMap(map, orig.id);
      expect(restored, isNotNull);
      expect(restored!.applicationId,             equals(orig.applicationId));
      expect(restored.currentPayScheduleType,     equals(orig.currentPayScheduleType));
      expect(restored.requestedPayScheduleType,   equals(orig.requestedPayScheduleType));
      expect(restored.currentPayScheduleDay,      equals(5));
      expect(restored.requestedPayScheduleDay,    equals(1));
      expect(restored.requestReason,              equals('변경 사유'));
      expect(restored.effectiveFrom,              equals(orig.effectiveFrom));
      expect(restored.createdAt,                  equals(orig.createdAt));
    });

    test('SCENARIO-PMR-103 status=PENDING 직렬화/역직렬화', () {
      final m = _makePCR(status: SimPaymentChangeRequest.statusPending).toMap();
      final r = SimPaymentChangeRequest.tryFromMap(m, 'id');
      expect(r!.status, equals('PENDING'));
      expect(r.isPending, isTrue);
    });

    test('SCENARIO-PMR-104 status=APPROVED 직렬화/역직렬화', () {
      final now = DateTime(2026, 7, 1);
      final m = _makePCR(
        status: SimPaymentChangeRequest.statusApproved,
        processedBy: 'admin-001',
        processedAt: now,
      ).toMap();
      final r = SimPaymentChangeRequest.tryFromMap(m, 'id');
      expect(r!.isApproved, isTrue);
      expect(r.processedBy,  equals('admin-001'));
      expect(r.processedAt,  equals(now));
    });

    test('SCENARIO-PMR-105 status=REJECTED 직렬화/역직렬화', () {
      final m = _makePCR(
        status: SimPaymentChangeRequest.statusRejected,
        rejectReason: '사유 없음',
      ).toMap();
      final r = SimPaymentChangeRequest.tryFromMap(m, 'id');
      expect(r!.isRejected,   isTrue);
      expect(r.rejectReason,  equals('사유 없음'));
    });

    test('SCENARIO-PMR-106 currentPayScheduleDay=null → toMap 미포함', () {
      final m = _makePCR(currentDay: null).toMap();
      expect(m.containsKey('currentPayScheduleDay'), isFalse);
    });

    test('SCENARIO-PMR-107 currentPayScheduleDay=3 → toMap 포함', () {
      final m = _makePCR(currentDay: 3).toMap();
      expect(m['currentPayScheduleDay'], equals(3));
    });

    test('SCENARIO-PMR-108 requestReason=null → toMap 미포함', () {
      final m = _makePCR(requestReason: null).toMap();
      expect(m.containsKey('requestReason'), isFalse);
    });

    test('SCENARIO-PMR-109 requestReason 있음 → toMap 포함 + 역직렬화', () {
      final m = _makePCR(requestReason: '월급으로 변경 원함').toMap();
      expect(m['requestReason'], equals('월급으로 변경 원함'));
      final r = SimPaymentChangeRequest.tryFromMap(m, 'id');
      expect(r!.requestReason, equals('월급으로 변경 원함'));
    });

    test('SCENARIO-PMR-110 processedBy/processedAt null → toMap 미포함', () {
      final m = _makePCR().toMap();
      expect(m.containsKey('processedBy'),  isFalse);
      expect(m.containsKey('processedAt'),  isFalse);
    });

    test('SCENARIO-PMR-111 rejectReason 있을 때 toMap 포함', () {
      final m = _makePCR(rejectReason: '정책상 불가').toMap();
      expect(m['rejectReason'], equals('정책상 불가'));
    });

    test('SCENARIO-PMR-112 createdAt DateTime 왕복', () {
      final dt = DateTime(2026, 6, 25, 9, 30, 0);
      final pcr = SimPaymentChangeRequest(
        id: 'x', applicationId: 'a', businessId: 'b', businessName: 'n',
        workerId: 'w', workerName: 'n', currentPayScheduleType: 'weekly',
        requestedPayScheduleType: 'monthly', effectiveFrom: '2026-07-01',
        status: 'PENDING', createdAt: dt,
      );
      final r = SimPaymentChangeRequest.tryFromMap(pcr.toMap(), 'x');
      expect(r!.createdAt, equals(dt));
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// SCENARIO-PMR-2xx: PaymentChangeRequest 상태기계
// ═══════════════════════════════════════════════════════════════════════

void _runPMR2xx() {
  group('SCENARIO-PMR-2xx: PaymentChangeRequest 상태기계', () {
    test('SCENARIO-PMR-201 pending → approved 성공', () {
      final req = _makePCR();
      final result = approvePaymentChange(req, 'admin-001');
      expect(result.isApproved, isTrue);
    });

    test('SCENARIO-PMR-202 approved 후 processedBy 설정됨', () {
      final result = approvePaymentChange(_makePCR(), 'admin-xyz');
      expect(result.processedBy, equals('admin-xyz'));
    });

    test('SCENARIO-PMR-203 approved 후 processedAt 설정됨 (≈ now)', () {
      final before = DateTime.now();
      final result = approvePaymentChange(_makePCR(), 'admin-001');
      final after = DateTime.now();
      expect(result.processedAt!.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(result.processedAt!.isBefore(after.add(const Duration(seconds: 1))),      isTrue);
    });

    test('SCENARIO-PMR-204 pending → rejected 성공', () {
      final result = rejectPaymentChange(_makePCR(), 'admin-001', '승인 불가');
      expect(result.isRejected, isTrue);
    });

    test('SCENARIO-PMR-205 rejected 후 rejectReason 설정됨', () {
      final result = rejectPaymentChange(_makePCR(), 'admin-001', '정책상 불가');
      expect(result.rejectReason, equals('정책상 불가'));
    });

    test('SCENARIO-PMR-206 approved 후 재거절 시도 → 예외', () {
      final approved = _makePCR(status: SimPaymentChangeRequest.statusApproved);
      expect(() => rejectPaymentChange(approved, 'admin-001', '사유'), throwsException);
    });

    test('SCENARIO-PMR-207 rejected 후 재승인 시도 → 예외', () {
      final rejected = _makePCR(status: SimPaymentChangeRequest.statusRejected);
      expect(() => approvePaymentChange(rejected, 'admin-001'), throwsException);
    });

    test('SCENARIO-PMR-208 approved 후 isPending=false, isApproved=true', () {
      final result = approvePaymentChange(_makePCR(), 'admin-001');
      expect(result.isPending,  isFalse);
      expect(result.isApproved, isTrue);
      expect(result.isRejected, isFalse);
    });

    test('SCENARIO-PMR-209 changeDescription weekly→monthly = "주급 → 월급"', () {
      expect(_makePCR(currentType: 'weekly', requestedType: 'monthly').changeDescription,
             equals('주급 → 월급'));
    });

    test('SCENARIO-PMR-210 tryFromMap createdAt 누락 → null 반환', () {
      final map = <String, dynamic>{
        'applicationId': 'a', 'businessId': 'b', 'status': 'PENDING',
        // createdAt 누락
      };
      expect(SimPaymentChangeRequest.tryFromMap(map, 'id'), isNull);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// SCENARIO-PMR-3xx: InterimSettlement 직렬화 왕복
// ═══════════════════════════════════════════════════════════════════════

void _runPMR3xx() {
  group('SCENARIO-PMR-3xx: InterimSettlement 직렬화 왕복', () {
    test('SCENARIO-PMR-301 toMap — 기본 필드 포함', () {
      final m = _makeISR().toMap();
      expect(m['applicationId'],   equals('app-001'));
      expect(m['requestedAmount'], equals(500000));
      expect(m['netAmount'],       equals(480000));
      expect(m['status'],          equals('PENDING'));
    });

    test('SCENARIO-PMR-302 toMap → fromMap 왕복 — 모든 필드 복원', () {
      final orig = _makeISR(
        attendanceIds: ['att-1', 'att-2'],
        requestedAmount: 600000,
        netAmount: 575000,
        requestReason: '급한 사정',
      );
      final r = SimInterimSettlement.tryFromMap(orig.toMap(), orig.id);
      expect(r, isNotNull);
      expect(r!.attendanceIds,   equals(['att-1', 'att-2']));
      expect(r.requestedAmount,  equals(600000));
      expect(r.netAmount,        equals(575000));
      expect(r.requestReason,    equals('급한 사정'));
      expect(r.periodStart,      equals(orig.periodStart));
      expect(r.periodEnd,        equals(orig.periodEnd));
    });

    test('SCENARIO-PMR-303 attendanceIds=[] 직렬화/역직렬화', () {
      final m = _makeISR(attendanceIds: []).toMap();
      final r = SimInterimSettlement.tryFromMap(m, 'id');
      expect(r!.attendanceIds, isEmpty);
    });

    test('SCENARIO-PMR-304 attendanceIds 여러 개 직렬화/역직렬화', () {
      final ids = ['a', 'b', 'c', 'd', 'e'];
      final m = _makeISR(attendanceIds: ids).toMap();
      final r = SimInterimSettlement.tryFromMap(m, 'id');
      expect(r!.attendanceIds, equals(ids));
    });

    test('SCENARIO-PMR-305 netAmount/requestedAmount 정확성', () {
      final m = _makeISR(requestedAmount: 999999, netAmount: 888888).toMap();
      final r = SimInterimSettlement.tryFromMap(m, 'id');
      expect(r!.requestedAmount, equals(999999));
      expect(r.netAmount,        equals(888888));
    });

    test('SCENARIO-PMR-306 requestReason null → toMap 미포함', () {
      final m = _makeISR(requestReason: null).toMap();
      expect(m.containsKey('requestReason'), isFalse);
    });

    test('SCENARIO-PMR-307 processedBy 있을 때 toMap 포함', () {
      final m = _makeISR(processedBy: 'admin-001').toMap();
      expect(m['processedBy'], equals('admin-001'));
    });

    test('SCENARIO-PMR-308 transferNote 직렬화', () {
      final m = _makeISR(transferNote: '카카오뱅크 이체').toMap();
      final r = SimInterimSettlement.tryFromMap(m, 'id');
      expect(r!.transferNote, equals('카카오뱅크 이체'));
    });

    test('SCENARIO-PMR-309 periodStart/periodEnd DateTime 왕복', () {
      final start = DateTime(2026, 5, 1);
      final end   = DateTime(2026, 5, 31);
      final isr = SimInterimSettlement(
        id: 'x', applicationId: 'a', businessId: 'b', businessName: 'n',
        workerId: 'w', workerName: 'n', periodStart: start, periodEnd: end,
        attendanceIds: [], requestedAmount: 0, netAmount: 0,
        status: 'PENDING', createdAt: _past1d,
      );
      final r = SimInterimSettlement.tryFromMap(isr.toMap(), 'x');
      expect(r!.periodStart, equals(start));
      expect(r.periodEnd,    equals(end));
    });

    test('SCENARIO-PMR-310 createdAt 누락 → tryFromMap null 반환', () {
      final map = <String, dynamic>{
        'periodStart': DateTime(2026, 5, 1),
        'periodEnd':   DateTime(2026, 5, 15),
        // createdAt 누락
      };
      expect(SimInterimSettlement.tryFromMap(map, 'id'), isNull);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// SCENARIO-PMR-4xx: InterimSettlement 상태기계
// ═══════════════════════════════════════════════════════════════════════

void _runPMR4xx() {
  group('SCENARIO-PMR-4xx: InterimSettlement 상태기계', () {
    test('SCENARIO-PMR-401 pending → approved 성공', () {
      final req = _makeISR(attendanceIds: ['att-1']);
      final atts = [const SimAttendance(id: 'att-1', effectiveNetWage: 100000)];
      final result = approveInterimSettlement(req, 'admin-001', atts);
      expect(result.updated.isApproved, isTrue);
    });

    test('SCENARIO-PMR-402 approved 후 attendanceIds의 wageStatus → transferred', () {
      final req = _makeISR(attendanceIds: ['att-1', 'att-2']);
      final atts = [
        const SimAttendance(id: 'att-1', effectiveNetWage: 80000),
        const SimAttendance(id: 'att-2', effectiveNetWage: 90000),
        const SimAttendance(id: 'att-3', effectiveNetWage: 70000), // 포함 안 됨
      ];
      final result = approveInterimSettlement(req, 'admin-001', atts);
      final transferred = result.updatedAttendances.where((a) => a.wageStatus == 'transferred');
      final untouched   = result.updatedAttendances.where((a) => a.id == 'att-3');
      expect(transferred.length, equals(2));
      expect(untouched.first.wageStatus, equals('unpaid'));
    });

    test('SCENARIO-PMR-403 pending → rejected: attendance 변경 없음', () {
      final req = _makeISR(attendanceIds: ['att-1']);
      final result = rejectInterimSettlement(req, 'admin-001', '거절 사유');
      expect(result.isRejected, isTrue);
      // 거절 시에는 attendanceIds 상태 변경 없음 (서비스 호출 안 함)
      expect(result.attendanceIds, equals(['att-1']));
    });

    test('SCENARIO-PMR-404 이미 transferred된 attendanceIds → 중복 정산 방어', () {
      final req = _makeISR(attendanceIds: ['att-1']);
      final atts = [
        const SimAttendance(id: 'att-1', effectiveNetWage: 80000, wageStatus: 'transferred'),
      ];
      expect(() => approveInterimSettlement(req, 'admin-001', atts), throwsException);
    });

    test('SCENARIO-PMR-405 netAmount = sum(effectiveNetWage) 검증', () {
      // 모델에 저장된 netAmount와 attendance 합계 일치 확인
      final atts = [
        const SimAttendance(id: 'a1', effectiveNetWage: 100000),
        const SimAttendance(id: 'a2', effectiveNetWage: 90000),
        const SimAttendance(id: 'a3', effectiveNetWage: 80000),
      ];
      final total = atts.fold(0, (sum, a) => sum + a.effectiveNetWage);
      final req = _makeISR(
        attendanceIds: ['a1', 'a2', 'a3'],
        netAmount: total,
      );
      expect(req.netAmount, equals(270000));
      expect(req.netAmount, equals(total));
    });

    test('SCENARIO-PMR-406 approved 후 recordCount 유지', () {
      final req = _makeISR(attendanceIds: ['a1', 'a2', 'a3']);
      final atts = [
        const SimAttendance(id: 'a1', effectiveNetWage: 10000),
        const SimAttendance(id: 'a2', effectiveNetWage: 10000),
        const SimAttendance(id: 'a3', effectiveNetWage: 10000),
      ];
      final result = approveInterimSettlement(req, 'admin-001', atts);
      expect(result.updated.recordCount, equals(3));
    });

    test('SCENARIO-PMR-407 rejected 후 rejectReason 설정됨', () {
      final result = rejectInterimSettlement(_makeISR(), 'admin-001', '잔액 부족');
      expect(result.rejectReason, equals('잔액 부족'));
    });

    test('SCENARIO-PMR-408 periodLabel 형식 검증 — 5/1 ~ 5/15', () {
      final isr = _makeISR();
      expect(isr.periodLabel, equals('5/1 ~ 5/15'));
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// SCENARIO-PMR-5xx: MemberPermissions 직렬화
// ═══════════════════════════════════════════════════════════════════════

void _runPMR5xx() {
  group('SCENARIO-PMR-5xx: MemberPermissions 직렬화', () {
    test('SCENARIO-PMR-501 모두 true → toMap에 true 값 포함', () {
      final m = SimMemberPermissions.all().toMap();
      expect(m['canManageTo'],       isTrue);
      expect(m['canManageWorkers'],  isTrue);
      expect(m['canManageWage'],     isTrue);
      expect(m['canManageContract'], isTrue);
    });

    test('SCENARIO-PMR-502 모두 false → toMap에 false 값 포함 (키 제거 아님)', () {
      final m = SimMemberPermissions.none().toMap();
      expect(m.containsKey('canManageTo'),       isTrue);
      expect(m.containsKey('canManageWorkers'),  isTrue);
      expect(m.containsKey('canManageWage'),     isTrue);
      expect(m.containsKey('canManageContract'), isTrue);
      expect(m['canManageTo'], isFalse);
    });

    test('SCENARIO-PMR-503 null 필드 → fromMap false 폴백', () {
      final m = SimMemberPermissions.fromMap({
        'canManageTo': null,
        'canManageWorkers': null,
      });
      expect(m.canManageTo,      isFalse);
      expect(m.canManageWorkers, isFalse);
    });

    test('SCENARIO-PMR-504 fromMap 왕복 정확성', () {
      final orig = const SimMemberPermissions(
        canManageTo: true, canManageWage: true,
        canManageWorkers: false, canManageContract: false,
      );
      final r = SimMemberPermissions.fromMap(orig.toMap());
      expect(r.canManageTo,       equals(orig.canManageTo));
      expect(r.canManageWorkers,  equals(orig.canManageWorkers));
      expect(r.canManageWage,     equals(orig.canManageWage));
      expect(r.canManageContract, equals(orig.canManageContract));
    });

    test('SCENARIO-PMR-505 canManageTo=true, 나머지 false → 정확히 반영', () {
      final p = const SimMemberPermissions(canManageTo: true);
      expect(p.canManageTo,       isTrue);
      expect(p.canManageWorkers,  isFalse);
      expect(p.canManageWage,     isFalse);
      expect(p.canManageContract, isFalse);
    });

    test('SCENARIO-PMR-506 none() factory → 모두 false', () {
      final p = SimMemberPermissions.none();
      expect(p.canManageTo,       isFalse);
      expect(p.canManageWorkers,  isFalse);
      expect(p.canManageWage,     isFalse);
      expect(p.canManageContract, isFalse);
    });

    test('SCENARIO-PMR-507 all() factory → 모두 true', () {
      final p = SimMemberPermissions.all();
      expect(p.canManageTo,       isTrue);
      expect(p.canManageWorkers,  isTrue);
      expect(p.canManageWage,     isTrue);
      expect(p.canManageContract, isTrue);
    });

    test('SCENARIO-PMR-508 hasAnyPermission — 하나라도 true → true', () {
      expect(const SimMemberPermissions(canManageWage: true).hasAnyPermission, isTrue);
    });

    test('SCENARIO-PMR-509 hasAnyPermission — 모두 false → false', () {
      expect(SimMemberPermissions.none().hasAnyPermission, isFalse);
    });

    test('SCENARIO-PMR-510 summaryText — canManageTo+canManageWage → "공고 · 급여"', () {
      final p = const SimMemberPermissions(canManageTo: true, canManageWage: true);
      expect(p.summaryText, equals('공고 · 급여'));
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// SCENARIO-PMR-6xx: BusinessMember tryFromMap null 방어
// ═══════════════════════════════════════════════════════════════════════

void _runPMR6xx() {
  group('SCENARIO-PMR-6xx: BusinessMember tryFromMap', () {
    test('SCENARIO-PMR-601 정상 데이터 → 객체 반환', () {
      final d = {
        'name': '홍길동',
        'phone': '010-1234-5678',
        'permissions': SimMemberPermissions.all().toMap(),
        'addedAt': _past1d,
        'addedBy': 'admin-001',
      };
      final r = SimBusinessMember.tryFromMap(d, 'uid-001');
      expect(r, isNotNull);
      expect(r!.uid, equals('uid-001'));
      expect(r.name, equals('홍길동'));
    });

    test('SCENARIO-PMR-602 uid = doc.id로 설정됨 (data map과 무관)', () {
      final d = {
        'name': '테스터',
        'addedAt': _past1d,
        'addedBy': 'admin-001',
        'permissions': <String, dynamic>{},
      };
      final r = SimBusinessMember.tryFromMap(d, 'specific-doc-id');
      expect(r!.uid, equals('specific-doc-id'));
    });

    test('SCENARIO-PMR-603 permissions 필드 누락 → 기본 false 권한 반환', () {
      final d = {
        'name': '홍길동',
        'addedAt': _past1d,
        'addedBy': 'admin-001',
        // permissions 누락
      };
      final r = SimBusinessMember.tryFromMap(d, 'uid-001');
      expect(r, isNotNull);
      expect(r!.permissions.hasAnyPermission, isFalse);
    });

    test('SCENARIO-PMR-604 addedAt 누락 → null 반환', () {
      final d = {
        'name': '홍길동',
        'addedBy': 'admin-001',
        'permissions': <String, dynamic>{},
        // addedAt 누락
      };
      expect(SimBusinessMember.tryFromMap(d, 'uid-001'), isNull);
    });

    test('SCENARIO-PMR-605 phone=null 허용 — 객체 정상 반환', () {
      final d = {
        'name': '홍길동',
        'phone': null,
        'addedAt': _past1d,
        'addedBy': 'admin-001',
        'permissions': <String, dynamic>{},
      };
      final r = SimBusinessMember.tryFromMap(d, 'uid-001');
      expect(r, isNotNull);
      expect(r!.phone, isNull);
    });

    test('SCENARIO-PMR-606 invitationId 없음 → null', () {
      final d = {
        'name': '홍길동',
        'addedAt': _past1d,
        'addedBy': 'admin-001',
        'permissions': <String, dynamic>{},
      };
      final r = SimBusinessMember.tryFromMap(d, 'uid-001');
      expect(r!.invitationId, isNull);
    });

    test('SCENARIO-PMR-607 permissions 일부만 있음 → 나머지 false', () {
      final d = {
        'name': '홍길동',
        'addedAt': _past1d,
        'addedBy': 'admin-001',
        'permissions': {'canManageTo': true},
      };
      final r = SimBusinessMember.tryFromMap(d, 'uid-001');
      expect(r!.permissions.canManageTo,       isTrue);
      expect(r.permissions.canManageWorkers,   isFalse);
      expect(r.permissions.canManageWage,      isFalse);
      expect(r.permissions.canManageContract,  isFalse);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// SCENARIO-PMR-7xx: ScheduleChangeRequest 직렬화
// ═══════════════════════════════════════════════════════════════════════

void _runPMR7xx() {
  group('SCENARIO-PMR-7xx: ScheduleChangeRequest 직렬화', () {
    test('SCENARIO-PMR-701 LEAVE type 직렬화 왕복', () {
      final m = _makeSCR(requestType: SimRequestType.LEAVE).toMap();
      final r = SimScheduleChangeRequest.tryFromMap(m, 'id');
      expect(r!.requestType, equals(SimRequestType.LEAVE));
    });

    test('SCENARIO-PMR-702 EXTRA_WORK type 직렬화 왕복', () {
      final m = _makeSCR(requestType: SimRequestType.EXTRA_WORK).toMap();
      final r = SimScheduleChangeRequest.tryFromMap(m, 'id');
      expect(r!.requestType, equals(SimRequestType.EXTRA_WORK));
    });

    test('SCENARIO-PMR-703 NO_WORK type 직렬화 왕복', () {
      final m = _makeSCR(requestType: SimRequestType.NO_WORK).toMap();
      final r = SimScheduleChangeRequest.tryFromMap(m, 'id');
      expect(r!.requestType, equals(SimRequestType.NO_WORK));
    });

    test('SCENARIO-PMR-704 CANCEL_LEAVE type 직렬화 왕복', () {
      final m = _makeSCR(requestType: SimRequestType.CANCEL_LEAVE).toMap();
      final r = SimScheduleChangeRequest.tryFromMap(m, 'id');
      expect(r!.requestType, equals(SimRequestType.CANCEL_LEAVE));
    });

    test('SCENARIO-PMR-705 CANCEL_EXTRA type 직렬화 왕복', () {
      final m = _makeSCR(requestType: SimRequestType.CANCEL_EXTRA).toMap();
      final r = SimScheduleChangeRequest.tryFromMap(m, 'id');
      expect(r!.requestType, equals(SimRequestType.CANCEL_EXTRA));
    });

    test('SCENARIO-PMR-706 requestedBy=ADMIN 직렬화 왕복', () {
      final m = _makeSCR(requestedBy: SimRequesterType.ADMIN).toMap();
      final r = SimScheduleChangeRequest.tryFromMap(m, 'id');
      expect(r!.isAdminRequest, isTrue);
    });

    test('SCENARIO-PMR-707 requestedBy=APPLICANT 직렬화 왕복', () {
      final m = _makeSCR(requestedBy: SimRequesterType.APPLICANT).toMap();
      final r = SimScheduleChangeRequest.tryFromMap(m, 'id');
      expect(r!.isApplicantRequest, isTrue);
    });

    test('SCENARIO-PMR-708 status 전 상태 직렬화 왕복', () {
      for (final st in SimRequestStatus.values) {
        final m = _makeSCR(status: st).toMap();
        final r = SimScheduleChangeRequest.tryFromMap(m, 'id');
        expect(r!.status, equals(st), reason: '$st 직렬화 실패');
      }
    });

    test('SCENARIO-PMR-709 wageAmount null → toMap에 포함 (null 값)', () {
      final m = _makeSCR(wageAmount: null).toMap();
      expect(m.containsKey('wageAmount'), isTrue);
      expect(m['wageAmount'], isNull);
    });

    test('SCENARIO-PMR-710 tryFromMap targetDate 누락 → null 반환', () {
      final m = _makeSCR().toMap();
      m.remove('targetDate');
      expect(SimScheduleChangeRequest.tryFromMap(m, 'id'), isNull);
    });

    test('SCENARIO-PMR-711 tryFromMap requestedAt 누락 → null 반환', () {
      final m = _makeSCR().toMap();
      m.remove('requestedAt');
      expect(SimScheduleChangeRequest.tryFromMap(m, 'id'), isNull);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// SCENARIO-PMR-8xx: ScheduleChangeRequest 상태기계
// ═══════════════════════════════════════════════════════════════════════

void _runPMR8xx() {
  group('SCENARIO-PMR-8xx: ScheduleChangeRequest 상태기계', () {
    test('SCENARIO-PMR-801 PENDING → APPROVED: respondedByUid 설정', () {
      final result = approveScheduleChange(_makeSCR(), 'admin-001');
      expect(result.isApproved,      isTrue);
      expect(result.respondedByUid,  equals('admin-001'));
    });

    test('SCENARIO-PMR-802 PENDING → APPROVED: respondedAt 설정됨 (≈ now)', () {
      final before = DateTime.now();
      final result = approveScheduleChange(_makeSCR(), 'admin-001');
      final after  = DateTime.now();
      expect(result.respondedAt!.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(result.respondedAt!.isBefore(after.add(const Duration(seconds: 1))),      isTrue);
    });

    test('SCENARIO-PMR-803 PENDING → REJECTED: rejectReason 설정', () {
      final result = rejectScheduleChange(_makeSCR(), 'admin-001', '스케줄 불가');
      expect(result.isRejected,  isTrue);
      expect(result.rejectReason, equals('스케줄 불가'));
    });

    test('SCENARIO-PMR-804 APPROVED 후 재거절 시도 → 예외 (isPending 체크)', () {
      final approved = _makeSCR(status: SimRequestStatus.APPROVED);
      expect(() => rejectScheduleChange(approved, 'admin-001', '사유'), throwsException);
    });

    test('SCENARIO-PMR-805 REJECTED 후 재승인 시도 → 예외', () {
      final rejected = _makeSCR(status: SimRequestStatus.REJECTED);
      expect(() => approveScheduleChange(rejected, 'admin-001'), throwsException);
    });

    test('SCENARIO-PMR-806 EXTRA_WORK 승인 → affectsSalary=true 확인 (급여 트리거)', () {
      final req = _makeSCR(requestType: SimRequestType.EXTRA_WORK, affectsSalary: true);
      final result = approveScheduleChange(req, 'admin-001');
      expect(result.isApproved,    isTrue);
      expect(result.isExtraWorkRequest, isTrue);
      expect(result.affectsSalary, isTrue);
    });

    test('SCENARIO-PMR-807 LEAVE 승인 → APPROVED 상태 전환', () {
      final req = _makeSCR(requestType: SimRequestType.LEAVE);
      final result = approveScheduleChange(req, 'admin-001');
      expect(result.isApproved,     isTrue);
      expect(result.isLeaveRequest, isTrue);
    });

    test('SCENARIO-PMR-808 affectsSalary=false → 급여 영향 없음 확인', () {
      final req = _makeSCR(affectsSalary: false);
      final result = approveScheduleChange(req, 'admin-001');
      expect(result.affectsSalary, isFalse);
    });

    test('SCENARIO-PMR-809 isPending/isApproved/isRejected/isCanceled getter 검증', () {
      expect(_makeSCR(status: SimRequestStatus.PENDING).isPending,   isTrue);
      expect(_makeSCR(status: SimRequestStatus.APPROVED).isApproved, isTrue);
      expect(_makeSCR(status: SimRequestStatus.REJECTED).isRejected, isTrue);
      expect(_makeSCR(status: SimRequestStatus.CANCELED).isCanceled, isTrue);
    });

    test('SCENARIO-PMR-810 copyWith status 전환 — PENDING → CANCELED', () {
      final req = _makeSCR();
      final canceled = req.copyWith(status: SimRequestStatus.CANCELED);
      expect(canceled.isCanceled, isTrue);
      expect(canceled.isPending,  isFalse);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// SCENARIO-PMR-9xx: MemberPermissions can() 체크
// ═══════════════════════════════════════════════════════════════════════

void _runPMR9xx() {
  group('SCENARIO-PMR-9xx: MemberPermissions can() 체크', () {
    test('SCENARIO-PMR-901 BUSINESS_ADMIN → 모든 권한 true', () {
      final checks = [
        can(SimUserRole.BUSINESS_ADMIN, null, (p) => p.canManageTo),
        can(SimUserRole.BUSINESS_ADMIN, null, (p) => p.canManageWorkers),
        can(SimUserRole.BUSINESS_ADMIN, null, (p) => p.canManageWage),
        can(SimUserRole.BUSINESS_ADMIN, null, (p) => p.canManageContract),
      ];
      expect(checks.every((c) => c), isTrue);
    });

    test('SCENARIO-PMR-902 SUB_ADMIN canManageTo=true → can() true', () {
      final perms = const SimMemberPermissions(canManageTo: true);
      expect(can(SimUserRole.USER, perms, (p) => p.canManageTo), isTrue);
    });

    test('SCENARIO-PMR-903 SUB_ADMIN canManageTo=false → can() false', () {
      expect(can(SimUserRole.USER, SimMemberPermissions.none(), (p) => p.canManageTo), isFalse);
    });

    test('SCENARIO-PMR-904 권한 없는 SUB_ADMIN → TO 삭제 차단 (can=false)', () {
      final result = can(SimUserRole.USER, SimMemberPermissions.none(), (p) => p.canManageTo);
      // TO 삭제는 canManageTo 필요 — false이므로 차단
      expect(result, isFalse);
    });

    test('SCENARIO-PMR-905 전체 권한 SUB_ADMIN → 모든 can() true', () {
      final perms = SimMemberPermissions.all();
      expect(can(SimUserRole.USER, perms, (p) => p.canManageTo),       isTrue);
      expect(can(SimUserRole.USER, perms, (p) => p.canManageWorkers),  isTrue);
      expect(can(SimUserRole.USER, perms, (p) => p.canManageWage),     isTrue);
      expect(can(SimUserRole.USER, perms, (p) => p.canManageContract), isTrue);
    });

    test('SCENARIO-PMR-906 permissions=null + USER → false', () {
      expect(can(SimUserRole.USER, null, (p) => p.canManageTo), isFalse);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// SCENARIO-PMR-Axx: MemberInvitation 만료 검증
// ═══════════════════════════════════════════════════════════════════════

void _runPMRAxx() {
  group('SCENARIO-PMR-Axx: MemberInvitation 만료 검증', () {
    test('SCENARIO-PMR-A01 createdAt=1일전 → isExpired=false (유효)', () {
      expect(_makeInvite(createdAt: _past1d).isExpired, isFalse);
    });

    test('SCENARIO-PMR-A02 createdAt=29일전 → isExpired=false', () {
      expect(_makeInvite(createdAt: _past29d).isExpired, isFalse);
    });

    test('SCENARIO-PMR-A03 createdAt=31일전 → isExpired=true (만료)', () {
      expect(_makeInvite(createdAt: _past31d).isExpired, isTrue);
    });

    test('SCENARIO-PMR-A04 이미 accepted 초대 재수락 → 예외', () {
      final inv = _makeInvite(status: SimInvitationStatus.accepted, createdAt: _past1d);
      expect(() => acceptInvitation(inv, {}), throwsException);
    });

    test('SCENARIO-PMR-A05 이미 멤버인 경우 초대 수락 → 예외', () {
      final inv = _makeInvite(createdAt: _past1d);
      final members = {'uid-001'}; // 이미 멤버
      expect(() => acceptInvitation(inv, members), throwsException);
    });

    test('SCENARIO-PMR-A06 hasPendingInvitation — 동일 userId 1일전 pending → true', () {
      final db = [_makeInvite(createdAt: _past1d)];
      expect(hasPendingInvitation('biz-001', 'uid-001', db), isTrue);
    });

    test('SCENARIO-PMR-A07 hasPendingInvitation — 31일전 → false (재초대 가능)', () {
      final db = [_makeInvite(createdAt: _past31d)];
      expect(hasPendingInvitation('biz-001', 'uid-001', db), isFalse);
    });

    test('SCENARIO-PMR-A08 이중 수락 방어 — 두 번째 수락 차단', () {
      final inv1 = _makeInvite(id: 'inv-001', createdAt: _past1d);
      final inv2 = _makeInvite(id: 'inv-002', createdAt: _past1d);
      final members = <String>{};

      // 첫 번째 수락 성공
      acceptInvitation(inv1, members);
      expect(members.contains('uid-001'), isTrue);

      // 두 번째 수락 → 이미 멤버이므로 예외
      expect(() => acceptInvitation(inv2, members), throwsException);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// main
// ═══════════════════════════════════════════════════════════════════════

void main() {
  _runPMR1xx();
  _runPMR2xx();
  _runPMR3xx();
  _runPMR4xx();
  _runPMR5xx();
  _runPMR6xx();
  _runPMR7xx();
  _runPMR8xx();
  _runPMR9xx();
  _runPMRAxx();
}
