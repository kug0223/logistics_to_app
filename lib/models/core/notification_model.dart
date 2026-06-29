import 'package:cloud_firestore/cloud_firestore.dart';

import 'application_model.dart';

/// 알림 유형
enum NotificationType {
  // 지원 관련 (지원자용)
  applicationConfirmed,    // 지원 확정됨
  applicationRejected,     // 지원 거절됨
  workTypeChanged,         // 파트(업무유형) 변경됨

  // 지원 관련 (관리자용)
  newApplication,          // 새 지원서 접수
  applicationCanceled,     // 지원자가 지원 취소

  // 확정 취소
  confirmationCanceled,    // 확정 취소됨 (관리자가 취소)
  
  // 근무 관련
  workReminder,            // 근무 리마인더 (내일 근무 있음)
  workCanceled,            // 근무 취소됨
  
  // 스케줄 변경 관련
  scheduleChangeRequested, // 스케줄 변경 요청
  scheduleChangeApproved,  // 스케줄 변경 승인
  scheduleChangeRejected,  // 스케줄 변경 거절
  
  // 계약 관련
  contractSignRequested,    // 계약서 서명 요청됨 (근무자에게)
  contractSigned,           // 근무자 서명 완료됨 (관리자에게)
  contractVoided,           // 계약서 무효화됨 (근무자에게) — H-34
  contractExpiringReminder, // 계약 만료 D-15 알림 (관리자에게)
  contractRenewed,          // 계약 연장 확정됨 (근무자에게)
  contractTerminating,      // 계약 종료 통보됨 (근무자에게)
  terminationRequested,     // 계약해지 요청됨
  terminationApproved,      // 계약해지 승인됨
  // terminationRejected: 계약해지 거절 전용 타입 — resignRejected와 라우팅은 같지만 알림 표시 분리
  terminationRejected,      // 계약해지 거절됨 (근무자→관리자)
  resignRequested,          // 퇴사 요청됨 (근무자→관리자)
  resignApproved,           // 퇴사 승인됨 (관리자→근무자)
  resignRejected,           // 퇴사 거절됨 (관리자→근무자)
  // contractRequested: 역방향 알림 — 다른 계약 관련 알림은 관리자→근무자지만
  // 이 타입만 근무자→관리자 방향. CONTRACT_PENDING 상태에서 근무자가 계약서 발송을 독촉할 때 발송.
  contractRequested,        // 계약서 작성 요청됨 (근무자→관리자)

  // 급여 관련
  wageConfirmed,              // 급여 정산 완료
  // [BUG-수정] 급여 이체 완료 후 지원자 알림 발송
  wageTransferred,            // 급여 송금 완료
  wageCancelConfirmed,        // 급여 마감 취소
  retroactiveDeductionAlert,  // 4대보험 소급 공제 안내
  
  // 리뷰 관련
  reviewReceived,          // 리뷰 받음
  reviewRequest,           // 리뷰 작성 요청 (CF: "REVIEW_REQUEST")
  
  // 신분증 열람 관련
  idCardAccessRequested,   // 신분증 열람 요청됨 (지원자에게)
  idCardAccessApproved,    // 신분증 열람 승인됨 (관리자에게)
  idCardAccessRejected,    // 신분증 열람 거절됨 (관리자에게)
  // 발송 로직 미구현 — CF 스케줄러 추가 필요
  idCardAccessExpiringSoon,// 신분증 열람 권한 만료 임박
  
  // 멤버 관리
  memberInvitationReceived, // 하위 관리자 초대 받음 (근무자에게)
  memberInvitationAccepted, // 초대 수락됨 (관리자에게)
  memberInvitationRejected, // 초대 거절됨 (관리자에게)

  // 시스템
  systemNotice,            // 시스템 공지
  other,                   // 기타
}

/// 앱 내 알림 모델
class NotificationModel {
  final String id;
  final String userId;              // 알림 받는 사용자 UID
  final NotificationType type;      // 알림 유형
  final String title;               // 알림 제목
  final String body;                // 알림 내용
  final Map<String, dynamic>? data; // 추가 데이터 (이동할 화면 정보 등)
  final bool isRead;                // 읽음 여부
  final DateTime createdAt;         // 생성 시각
  final DateTime? readAt;           // 읽은 시각

  NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.data,
    this.isRead = false,
    required this.createdAt,
    this.readAt,
  });

  /// Firestore에서 변환
  factory NotificationModel.fromMap(Map<String, dynamic> map, String id) {
    return NotificationModel(
      id: id,
      userId: map['userId'] ?? '',
      type: _typeFromString(map['type'] ?? 'other'),
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      data: map['data'],
      isRead: map['isRead'] ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate().toLocal() ?? DateTime.now(),
      readAt: (map['readAt'] as Timestamp?)?.toDate().toLocal(),
    );
  }

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) throw ArgumentError('Document ${doc.id} has no data');
    return NotificationModel.fromMap(raw as Map<String, dynamic>, doc.id);
  }

  /// Firestore에 저장
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'type': _typeToString(type),
      'title': title,
      'body': body,
      'data': data,
      'isRead': isRead,
      // CF callable 파라미터는 JSON-serializable만 허용 — Timestamp 불가, ISO 8601 문자열 사용
      'createdAt': createdAt.toUtc().toIso8601String(),
      'readAt': readAt?.toUtc().toIso8601String(),
    };
  }

  /// 복사본 생성
  NotificationModel copyWith({
    String? id,
    String? userId,
    NotificationType? type,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    bool? isRead,
    DateTime? createdAt,
    DateTime? readAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      data: data ?? this.data,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
    );
  }

  // ── Getter ──

  /// 알림 아이콘
  String get iconName {
    switch (type) {
      // 지원 관련
      case NotificationType.applicationConfirmed:
        return 'check_circle';
      case NotificationType.workTypeChanged:
        return 'swap_horiz';
      case NotificationType.applicationRejected:
        return 'cancel';
      case NotificationType.newApplication:
        return 'person_add';
      case NotificationType.applicationCanceled:
        return 'person_remove';
      case NotificationType.confirmationCanceled:
        return 'event_busy';
      // 근무 관련
      case NotificationType.workReminder:
        return 'alarm';
      case NotificationType.workCanceled:
        return 'event_busy';
      // 스케줄 변경
      case NotificationType.scheduleChangeRequested:
        return 'edit_calendar';
      case NotificationType.scheduleChangeApproved:
        return 'event_available';
      case NotificationType.scheduleChangeRejected:
        return 'event_busy';
      // 계약 관련
      case NotificationType.contractSignRequested:
        return 'draw';
      case NotificationType.contractSigned:
        return 'task_alt';
      case NotificationType.contractVoided:
        return 'block';
      case NotificationType.contractExpiringReminder:
        return 'event_note';
      case NotificationType.contractRenewed:
        return 'autorenew';
      case NotificationType.contractTerminating:
        return 'event_busy';
      case NotificationType.terminationRequested:
        return 'exit_to_app';
      case NotificationType.terminationApproved:
        return 'logout';
      // terminationRejected: 계약해지 거절 전용 타입 — resignRejected와 라우팅은 같지만 알림 표시 분리
      case NotificationType.terminationRejected:
        return 'block';
      // 퇴사 관련
      case NotificationType.resignRequested:
        return 'exit_to_app';
      case NotificationType.resignApproved:
        return 'logout';
      case NotificationType.resignRejected:
        return 'do_not_disturb_on';
      case NotificationType.contractRequested:
        return 'mail';
      // 급여 관련
      case NotificationType.wageConfirmed:
        return 'payments';
      // [BUG-수정] 급여 이체 완료 후 지원자 알림 발송
      case NotificationType.wageTransferred:
        return 'payments';
      case NotificationType.wageCancelConfirmed:
        return 'payments';
      case NotificationType.retroactiveDeductionAlert:
        return 'warning_amber';
      // 리뷰
      case NotificationType.reviewReceived:
      case NotificationType.reviewRequest:
        return 'star';
      // 신분증
      case NotificationType.idCardAccessRequested:
        return 'badge';
      case NotificationType.idCardAccessApproved:
        return 'verified';
      case NotificationType.idCardAccessRejected:
        return 'block';
      case NotificationType.idCardAccessExpiringSoon:
        return 'schedule';
      // 멤버 관리
      case NotificationType.memberInvitationReceived:
        return 'group_add';
      case NotificationType.memberInvitationAccepted:
        return 'how_to_reg';
      case NotificationType.memberInvitationRejected:
        return 'person_remove';
      // 시스템
      case NotificationType.systemNotice:
        return 'campaign';
      case NotificationType.other:
        return 'notifications';
    }
  }

  /// 상대 시간 텍스트
  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inMinutes < 1) {
      return '방금 전';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}분 전';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}시간 전';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}일 전';
    } else {
      return '${createdAt.month}/${createdAt.day}';
    }
  }

  // ── Static Helper ──

  static NotificationType _typeFromString(String value) {
    switch (value) {
      // 지원 관련
      case 'applicationConfirmed': return NotificationType.applicationConfirmed;
      case 'workTypeChanged': return NotificationType.workTypeChanged;
      case 'applicationRejected': return NotificationType.applicationRejected;
      case 'newApplication': return NotificationType.newApplication;
      case 'applicationCanceled': return NotificationType.applicationCanceled;
      case 'confirmationCanceled': return NotificationType.confirmationCanceled;
      // 근무 관련
      case 'workReminder': return NotificationType.workReminder;
      case 'workCanceled': return NotificationType.workCanceled;
      // 스케줄 변경
      case 'scheduleChangeRequested': return NotificationType.scheduleChangeRequested;
      case 'scheduleChangeApproved': return NotificationType.scheduleChangeApproved;
      case 'scheduleChangeRejected': return NotificationType.scheduleChangeRejected;
      // 계약 관련
      case 'contractSignRequested': return NotificationType.contractSignRequested;
      case 'contractSigned': return NotificationType.contractSigned;
      case 'contractVoided': return NotificationType.contractVoided;
      case 'contractExpiringReminder': return NotificationType.contractExpiringReminder;
      case 'contractRenewed': return NotificationType.contractRenewed;
      case 'contractTerminating': return NotificationType.contractTerminating;
      case 'terminationRequested': return NotificationType.terminationRequested;
      case 'terminationApproved': return NotificationType.terminationApproved;
      // terminationRejected: 계약해지 거절 전용 타입 — resignRejected와 라우팅은 같지만 알림 표시 분리
      case 'terminationRejected': return NotificationType.terminationRejected;
      // 퇴사 관련
      case 'resignRequested': return NotificationType.resignRequested;
      case 'resignApproved': return NotificationType.resignApproved;
      case 'resignRejected': return NotificationType.resignRejected;
      case 'contractRequested': return NotificationType.contractRequested;
      // 급여 관련
      case 'wageConfirmed': return NotificationType.wageConfirmed;
      // [BUG-수정] 급여 이체 완료 후 지원자 알림 발송
      case 'wageTransferred': return NotificationType.wageTransferred;
      case 'wageCancelConfirmed': return NotificationType.wageCancelConfirmed;
      case 'retroactiveDeductionAlert': return NotificationType.retroactiveDeductionAlert;
      // 리뷰
      case 'reviewReceived': return NotificationType.reviewReceived;
      case 'REVIEW_REQUEST': return NotificationType.reviewRequest;
      case 'reviewRequest': return NotificationType.reviewRequest; // 구버전 레코드 역직렬화 호환
      // 신분증
      case 'idCardAccessRequested': return NotificationType.idCardAccessRequested;
      case 'idCardAccessApproved': return NotificationType.idCardAccessApproved;
      case 'idCardAccessRejected': return NotificationType.idCardAccessRejected;
      case 'idCardAccessExpiringSoon': return NotificationType.idCardAccessExpiringSoon;
      // 멤버 관리
      case 'memberInvitationReceived': return NotificationType.memberInvitationReceived;
      case 'memberInvitationAccepted': return NotificationType.memberInvitationAccepted;
      case 'memberInvitationRejected': return NotificationType.memberInvitationRejected;
      // 시스템
      case 'systemNotice': return NotificationType.systemNotice;
      default: return NotificationType.other;
    }
  }

  static String _typeToString(NotificationType type) {
    switch (type) {
      // 지원 관련
      case NotificationType.applicationConfirmed: return 'applicationConfirmed';
      case NotificationType.workTypeChanged: return 'workTypeChanged';
      case NotificationType.applicationRejected: return 'applicationRejected';
      case NotificationType.newApplication: return 'newApplication';
      case NotificationType.applicationCanceled: return 'applicationCanceled';
      case NotificationType.confirmationCanceled: return 'confirmationCanceled';
      // 근무 관련
      case NotificationType.workReminder: return 'workReminder';
      case NotificationType.workCanceled: return 'workCanceled';
      // 스케줄 변경
      case NotificationType.scheduleChangeRequested: return 'scheduleChangeRequested';
      case NotificationType.scheduleChangeApproved: return 'scheduleChangeApproved';
      case NotificationType.scheduleChangeRejected: return 'scheduleChangeRejected';
      // 계약 관련
      case NotificationType.contractSignRequested: return 'contractSignRequested';
      case NotificationType.contractSigned: return 'contractSigned';
      case NotificationType.contractVoided: return 'contractVoided';
      case NotificationType.contractExpiringReminder: return 'contractExpiringReminder';
      case NotificationType.contractRenewed: return 'contractRenewed';
      case NotificationType.contractTerminating: return 'contractTerminating';
      case NotificationType.terminationRequested: return 'terminationRequested';
      case NotificationType.terminationApproved: return 'terminationApproved';
      // terminationRejected: 계약해지 거절 전용 타입 — resignRejected와 라우팅은 같지만 알림 표시 분리
      case NotificationType.terminationRejected: return 'terminationRejected';
      // 퇴사 관련
      case NotificationType.resignRequested: return 'resignRequested';
      case NotificationType.resignApproved: return 'resignApproved';
      case NotificationType.resignRejected: return 'resignRejected';
      case NotificationType.contractRequested: return 'contractRequested';
      // 급여 관련
      case NotificationType.wageConfirmed: return 'wageConfirmed';
      // [BUG-수정] 급여 이체 완료 후 지원자 알림 발송
      case NotificationType.wageTransferred: return 'wageTransferred';
      case NotificationType.wageCancelConfirmed: return 'wageCancelConfirmed';
      case NotificationType.retroactiveDeductionAlert: return 'retroactiveDeductionAlert';
      // 리뷰
      case NotificationType.reviewReceived: return 'reviewReceived';
      case NotificationType.reviewRequest: return 'REVIEW_REQUEST';
      // 신분증
      case NotificationType.idCardAccessRequested: return 'idCardAccessRequested';
      case NotificationType.idCardAccessApproved: return 'idCardAccessApproved';
      case NotificationType.idCardAccessRejected: return 'idCardAccessRejected';
      case NotificationType.idCardAccessExpiringSoon: return 'idCardAccessExpiringSoon';
      // 멤버 관리
      case NotificationType.memberInvitationReceived: return 'memberInvitationReceived';
      case NotificationType.memberInvitationAccepted: return 'memberInvitationAccepted';
      case NotificationType.memberInvitationRejected: return 'memberInvitationRejected';
      // 시스템
      case NotificationType.systemNotice: return 'systemNotice';
      case NotificationType.other: return 'other';
    }
  }

  // ── Factory Methods (알림 생성 헬퍼) ──

  /// 신분증 열람 요청 알림 생성
  static NotificationModel createIdCardAccessRequest({
    required String userId,
    required String businessName,
    required String businessId,
    required String reason,
    required String requestId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.idCardAccessRequested,
      title: '신분증 열람 요청',
      body: '$businessName에서 신분증 열람을 요청했습니다.\n사유: $reason',
      data: {
        'requestId': requestId,
        'businessId': businessId,
        'action': 'idCardAccessRequest',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 신분증 열람 승인 알림 생성
  static NotificationModel createIdCardAccessApproved({
    required String userId,
    required String targetUserName,
    required String businessId,
    required String requestId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.idCardAccessApproved,
      title: '신분증 열람 승인됨',
      body: '$targetUserName님이 신분증 열람을 승인했습니다.\n7일간 열람 가능합니다.',
      data: {
        'requestId': requestId,
        'businessId': businessId,
        'action': 'idCardAccessApproved',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 신분증 열람 거절 알림 생성
  static NotificationModel createIdCardAccessRejected({
    required String userId,
    required String targetUserName,
    required String businessId,
    required String requestId,
    String? rejectionReason,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.idCardAccessRejected,
      title: '신분증 열람 거절됨',
      body: '$targetUserName님이 신분증 열람을 거절했습니다.${rejectionReason != null ? '\n사유: $rejectionReason' : ''}',
      data: {
        'requestId': requestId,
        'businessId': businessId,
        'action': 'idCardAccessRejected',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 지원 승인 알림 생성
  static NotificationModel createApplicationConfirmed({
    required String userId,
    required String businessName,
    required String businessId,
    required String workType,
    required DateTime workDate,
    required String applicationId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.applicationConfirmed,
      title: '지원 승인',
      body: '$businessName의 $workType 지원이 승인되었습니다. 관리자가 곧 계약서를 발송할 예정입니다.\n근무일: ${workDate.month}/${workDate.day}',
      data: {
        'applicationId': applicationId,
        'businessId': businessId,
        'action': 'applicationDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 리뷰 받음 알림 생성
  static NotificationModel createReviewReceived({
    required String userId,
    required String businessName,
    required String businessId,
    required int rating,
    required String reviewId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.reviewReceived,
      title: '새 리뷰가 등록되었습니다',
      body: '$businessName에서 ${'⭐' * rating} 평가를 받았습니다.',
      data: {
        'reviewId': reviewId,
        'businessId': businessId,
        'action': 'reviewDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 지원 거절 알림 생성 (지원자에게)
  static NotificationModel createApplicationRejected({
    required String userId,
    required String businessName,
    required String businessId,
    required String workType,
    required DateTime workDate,
    required String applicationId,
    String? rejectReason,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.applicationRejected,
      title: '지원 거절',
      body: '$businessName의 $workType 지원이 거절되었습니다.${rejectReason != null ? '\n사유: $rejectReason' : ''}\n근무일: ${workDate.month}/${workDate.day}',
      data: {
        'applicationId': applicationId,
        'businessId': businessId,
        'action': 'applicationDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 신규 지원 알림 생성 (관리자에게)
  static NotificationModel createNewApplication({
    required String userId,
    required String applicantName,
    required String workType,
    required DateTime workDate,
    required String applicationId,
    required String toId,
    required String businessId,
    required String workDetailId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.newApplication,
      title: '새 지원서 접수',
      body: '$applicantName님이 $workType에 지원했습니다.\n근무일: ${workDate.month}/${workDate.day}',
      data: {
        'applicationId': applicationId,
        'toId': toId,
        'businessId': businessId,
        'workDetailId': workDetailId,
        'workType': workType,
        'action': 'applicantDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 지원 취소 알림 생성 (관리자에게)
  static NotificationModel createApplicationCanceled({
    required String userId,
    required String applicantName,
    required String workType,
    required DateTime workDate,
    required String applicationId,
    required String businessId,
    required String toId,
    required String workDetailId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.applicationCanceled,
      title: '지원 취소',
      body: '$applicantName님이 $workType 지원을 취소했습니다.\n근무일: ${workDate.month}/${workDate.day}',
      data: {
        'applicationId': applicationId,
        'businessId': businessId,
        'toId': toId,
        'workDetailId': workDetailId,
        'workType': workType,
        'action': 'applicantDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 근무자 자기 확정 취소 알림 생성 (관리자에게)
  static NotificationModel createConfirmationCanceledByWorker({
    required String userId,       // 관리자 uid
    required String workerName,
    required String workType,
    required DateTime workDate,
    required String applicationId,
    required String businessId,
    required String toId,
    required String workDetailId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.confirmationCanceled,
      title: '확정 취소',
      body: '$workerName님이 $workType 확정 근무를 취소했습니다.\n근무일: ${workDate.month}/${workDate.day}',
      data: {
        'applicationId': applicationId,
        'businessId': businessId,
        'toId': toId,
        'workDetailId': workDetailId,
        'workType': workType,
        'action': 'applicantDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 확정 취소 알림 생성 (지원자에게)
  static NotificationModel createConfirmationCanceled({
    required String userId,
    required String businessName,
    required String businessId,
    required String workType,
    required DateTime workDate,
    required String applicationId,
    String? cancelReason,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.confirmationCanceled,
      title: '확정 취소',
      body: '$businessName의 $workType 확정이 취소되었습니다.${cancelReason != null ? '\n사유: $cancelReason' : ''}\n근무일: ${workDate.month}/${workDate.day}',
      data: {
        'applicationId': applicationId,
        'businessId': businessId,
        'action': 'applicationDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 스케줄 변경 요청 알림 생성
  static NotificationModel createScheduleChangeRequested({
    required String userId,
    required String requesterName,
    required String requestType,
    required DateTime targetDate,
    required String requestId,
    required String businessId,
    String? reason,
  }) {
    String typeText;
    switch (requestType) {
      case 'LEAVE':
        typeText = '휴무';
        break;
      case 'NO_WORK':
        typeText = '미출근';
        break;
      case 'EXTRA_WORK':
        typeText = '추가근무';
        break;
      case 'CANCEL_LEAVE':
        typeText = '휴무취소';
        break;
      case 'CANCEL_EXTRA':
        typeText = '추가근무취소';
        break;
      default:
        typeText = '스케줄변경';
    }
    
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.scheduleChangeRequested,
      title: '$typeText 요청',
      body: '$requesterName님이 ${targetDate.month}/${targetDate.day} $typeText을(를) 요청했습니다.${reason != null ? '\n사유: $reason' : ''}',
      data: {
        'requestId': requestId,
        'businessId': businessId,
        'action': 'scheduleChangeRequest',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 스케줄 변경 승인 알림 생성 (요청자에게)
  static NotificationModel createScheduleChangeApproved({
    required String userId,
    required String requestType,
    required DateTime targetDate,
    required String requestId,
    required String businessName,
    required String businessId,
  }) {
    String typeText;
    switch (requestType) {
      case 'LEAVE':
        typeText = '휴무';
        break;
      case 'NO_WORK':
        typeText = '미출근';
        break;
      case 'EXTRA_WORK':
        typeText = '추가근무';
        break;
      case 'CANCEL_LEAVE':
        typeText = '휴무취소';
        break;
      case 'CANCEL_EXTRA':
        typeText = '추가근무취소';
        break;
      default:
        typeText = '스케줄변경';
    }
    
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.scheduleChangeApproved,
      title: '$typeText 승인',
      body: '$businessName에서 ${targetDate.month}/${targetDate.day} $typeText 요청을 승인했습니다.',
      data: {
        'requestId': requestId,
        'businessId': businessId,
        'action': 'scheduleDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 스케줄 변경 거절 알림 생성 (요청자에게)
  static NotificationModel createScheduleChangeRejected({
    required String userId,
    required String requestType,
    required DateTime targetDate,
    required String requestId,
    required String businessName,
    required String businessId,
    String? rejectReason,
  }) {
    String typeText;
    switch (requestType) {
      case 'LEAVE':
        typeText = '휴무';
        break;
      case 'NO_WORK':
        typeText = '미출근';
        break;
      case 'EXTRA_WORK':
        typeText = '추가근무';
        break;
      case 'CANCEL_LEAVE':
        typeText = '휴무취소';
        break;
      case 'CANCEL_EXTRA':
        typeText = '추가근무취소';
        break;
      default:
        typeText = '스케줄변경';
    }
    
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.scheduleChangeRejected,
      title: '$typeText 거절',
      body: '$businessName에서 ${targetDate.month}/${targetDate.day} $typeText 요청을 거절했습니다.${rejectReason != null ? '\n사유: $rejectReason' : ''}',
      data: {
        'requestId': requestId,
        'businessId': businessId,
        'action': 'scheduleDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 계약서 서명 요청 알림 생성 (근무자에게)
  static NotificationModel createContractSignRequested({
    required String userId,
    required String businessName,
    required String businessId,
    required String contractId,
    required String applicationId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.contractSignRequested,
      title: '근로계약서 서명 요청',
      body: '계약서가 도착했습니다. 서명 후 최종 확정됩니다.',
      data: {
        'contractId': contractId,
        'applicationId': applicationId,
        'businessId': businessId,
        'screen': 'contractSign',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 계약서 작성 요청 알림 생성 (근무자→관리자)
  /// 근무자가 CONTRACT_PENDING 상태에서 "계약서 요청하기" 버튼을 누를 때 사업장 오너에게 발송.
  // 수신자(userId)가 근무자가 아닌 사업장 ownerId — 발송 전 businesses/{businessId}.ownerId 조회 필요.
  // 클라이언트에서 24시간 쿨다운(SharedPreferences key: contract_req_{applicationId})을 강제하므로
  //           서버 중복 발송 방어는 없음. 관리자 UX 과부하 방지 목적의 소프트 제한이다.
  static NotificationModel createContractRequested({
    required String userId,
    required String workerName,
    required String businessId,
    required String applicationId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.contractRequested,
      title: '계약서 발송 요청',
      body: '$workerName님이 계약서 발송을 요청했습니다.',
      data: {
        'applicationId': applicationId,
        'businessId': businessId,
        'action': 'applicationDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 계약서 서명 완료 알림 생성 (관리자에게)
  /// 근무자가 서명을 완료하면 사업장 오너에게 발송.
  static NotificationModel createContractSigned({
    required String userId,
    required String workerName,
    required String businessId,
    required String contractId,
    required String applicationId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.contractSigned,
      title: '계약서 서명 완료',
      body: '$workerName님이 근로계약서 서명을 완료했습니다.',
      data: {
        'contractId': contractId,
        'applicationId': applicationId,
        'businessId': businessId,
        'screen': 'contractSigned',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 계약서 무효화 알림 생성 (근무자에게) — H-34
  /// voidContract() 호출 시 근무자에게 발송해 계약서가 무효화됐음을 알린다.
  static NotificationModel createContractVoided({
    required String userId,
    required String businessName,
    required String businessId,
    required String contractId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.contractVoided,
      title: '계약서 무효 처리',
      body: '$businessName의 근로계약서가 무효 처리되었습니다. 계약서 목록을 확인해 주세요.',
      data: {
        'contractId': contractId,
        'businessId': businessId,
        'screen': 'userContracts',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 계약해지 요청 알림 생성 (지원자에게)
  static NotificationModel createTerminationRequested({
    required String userId,
    required String businessName,
    required String businessId,
    required DateTime terminationDate,
    required String applicationId,
    String? reason,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.terminationRequested,
      title: '계약해지 요청',
      body: '$businessName에서 계약해지를 요청했습니다.${reason != null ? '\n사유: $reason' : ''}\n해지 예정일: ${terminationDate.month}/${terminationDate.day}',
      data: {
        'applicationId': applicationId,
        'businessId': businessId,
        'action': 'terminationRequest',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 계약해지 승인 알림 생성 (지원자에게)
  static NotificationModel createTerminationApproved({
    required String userId,
    required String businessName,
    required String businessId,
    required String applicationId,
    required DateTime actualResignDate,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.terminationApproved,
      title: '계약해지 완료',
      body: '$businessName과의 계약이 해지되었습니다.\n해지일: ${actualResignDate.month}/${actualResignDate.day}',
      data: {
        'applicationId': applicationId,
        'businessId': businessId,
        'action': 'applicationDetail',
      },
      createdAt: DateTime.now(),
    );
  }
  /// 퇴사 요청 알림 생성 (관리자에게)
  static NotificationModel createResignRequested({
    required String userId,
    required String workerName,
    required String businessName,
    required String businessId,
    required DateTime resignDate,
    required String applicationId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.resignRequested,
      title: '퇴사 요청',
      body: '$workerName님이 ${resignDate.month}/${resignDate.day}자 퇴사를 요청했습니다.',
      data: {
        'applicationId': applicationId,
        'businessId': businessId,
        'action': 'resignRequest',
        'businessName': businessName,
      },
      createdAt: DateTime.now(),
    );
  }

  /// 퇴사 승인 알림 생성 (근무자에게)
  static NotificationModel createResignApproved({
    required String userId,
    required String businessName,
    required String businessId,
    required DateTime actualResignDate,
    required String applicationId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.resignApproved,
      title: '퇴사 승인',
      body: '$businessName에서 퇴사 요청을 승인했습니다.\n퇴사일: ${actualResignDate.month}/${actualResignDate.day}',
      data: {
        'applicationId': applicationId,
        'businessId': businessId,
        'action': 'applicationDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 계약해지 거절 알림 생성 (해지 요청자·관리자에게)
  /// terminationRejected: 계약해지 거절 전용 타입 — resignRejected와 라우팅은 같지만 알림 표시 분리
  static NotificationModel createTerminationRejected({
    required String userId,
    required String businessName,
    required String businessId,
    required String applicationId,
    String? rejectReason,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.terminationRejected,
      title: '계약해지 거절',
      body: '$businessName의 계약해지 요청이 거절되었습니다.${rejectReason != null ? '\n사유: $rejectReason' : ''}',
      data: {
        'applicationId': applicationId,
        'businessId': businessId,
        'action': 'applicationDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 퇴사 거절 알림 생성 (근무자에게)
  static NotificationModel createResignRejected({
    required String userId,
    required String businessName,
    required String businessId,
    required String applicationId,
    String? rejectReason,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.resignRejected,
      title: '퇴사 거절',
      body: '$businessName에서 퇴사 요청을 거절했습니다.${rejectReason != null ? '\n사유: $rejectReason' : ''}',
      data: {
        'applicationId': applicationId,
        'businessId': businessId,
        'action': 'applicationDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 지원 자동 취소 알림 생성 (시간 충돌로 인한 자동취소)
  static NotificationModel createApplicationAutoCanceled({
    required String userId,
    required String businessName,
    required String businessId,
    required String workType,
    required DateTime workDate,
    required String applicationId,
    required String conflictingBusinessName,
    required String conflictingTime,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.confirmationCanceled,  // 기존 타입 재사용
      title: '지원 자동 취소',
      body: '$businessName $workType 지원이 시간 충돌로 자동 취소되었습니다.\n확정된 근무: $conflictingBusinessName ($conflictingTime)',
      data: {
        'applicationId': applicationId,
        'businessId': businessId,
        'reason': 'SCHEDULE_CONFLICT',
        'action': 'applicationDetail',
      },
      createdAt: DateTime.now(),
    );
  }
  /// TO 취소/삭제 알림 생성 (지원자에게)
  static NotificationModel createTOCanceled({
    required String userId,
    required String businessName,
    required String businessId,
    required String toTitle,
    required DateTime workDate,
    required String status,  // AppStatus.pending 또는 AppStatus.confirmed
  }) {
    final statusText = AppStatus.confirmedStatuses.contains(status) ? '확정된 근무' : '지원';
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.workCanceled,
      title: '공고 취소',
      body: '$businessName의 "$toTitle" 공고가 취소되어 $statusText이(가) 무효화되었습니다.\n근무일: ${workDate.month}/${workDate.day}',
      data: {
        'businessId': businessId,
        'action': 'toList',
        'reason': 'TO_DELETED',
      },
      createdAt: DateTime.now(),
    );
  }
  /// 파트(업무유형) 변경 알림 생성 (지원자에게)
  static NotificationModel createWorkTypeChanged({
    required String userId,
    required String businessName,
    required String businessId,
    required DateTime workDate,
    required String originalWorkType,
    required String newWorkType,
    required int newWage,
    required String applicationId,
  }) {
    final formattedWage = newWage.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.workTypeChanged,
      title: '파트 변경',
      body: '$businessName에서 귀하의 파트가 변경되었습니다.\n$originalWorkType → $newWorkType ($formattedWage원)\n근무일: ${workDate.month}/${workDate.day}',
      data: {
        'applicationId': applicationId,
        'businessId': businessId,
        'action': 'applicationDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 8일차 4대보험 소급 공제 알림 생성 (근로자에게)
  static NotificationModel createRetroactiveDeductionAlert({
    required String userId,
    required String businessName,
    required String businessId,
    required DateTime workDate,
    required int retroactiveAmount,
    required int grossWage,
    required int netWage,
    required String attendanceId,
  }) {
    final retroFormatted = retroactiveAmount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    final netFormatted = netWage.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.retroactiveDeductionAlert,
      title: '4대보험 소급 공제 안내',
      body: '$businessName ${workDate.month}/${workDate.day} 근무 포함 이번 달 근무 횟수가 8회를 넘어 '
          '4대보험이 첫 근무부터 적용됩니다. 이전 근무분 보험료 $retroFormatted원이 이번 급여에서 함께 공제됩니다.\n실수령액: $netFormatted원',
      data: {
        'attendanceId': attendanceId,
        'businessId': businessId,
        'action': 'wageDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 급여 송금 완료 알림 생성 (지원자에게) — [BUG-수정] 급여 이체 완료 후 지원자 알림 발송
  static NotificationModel createWageTransferred({
    required String userId,
    required String workerName,
    required String businessName,
    required String businessId,
    required int finalWage,
    String? applicationId,
  }) {
    final formattedWage = finalWage.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.wageTransferred,
      title: '급여 송금 완료',
      body: '[$businessName] $workerName님의 급여 $formattedWage원이 송금 처리되었습니다.',
      createdAt: DateTime.now(),
      data: {
        if (applicationId != null) 'applicationId': applicationId,
        'businessId': businessId,
        'screen': 'wageTransferred',
      },
    );
  }

  /// 급여 정산 완료 알림 생성 (지원자에게)
  static NotificationModel createWageConfirmed({
    required String userId,
    required String businessName,
    required String businessId,
    required DateTime workDate,
    required int totalWage,
    required String attendanceId,
  }) {
    final formattedWage = totalWage.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );

    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.wageConfirmed,
      title: '급여 정산 완료',
      body: '$businessName ${workDate.month}/${workDate.day} 근무 급여가 정산되었습니다.\n정산 금액: $formattedWage원',
      data: {
        'attendanceId': attendanceId,
        'businessId': businessId,
        'action': 'wageDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 계약 만료 D-15 알림 (관리자에게)
  static NotificationModel createContractExpiringReminder({
    required String userId,
    required String workerName,
    required String businessName,
    required String businessId,
    required DateTime expiryDate,
    required String applicationId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.contractExpiringReminder,
      title: '계약 만료 임박',
      body: '$workerName님의 계약이 ${expiryDate.month}/${expiryDate.day}에 만료됩니다. 연장 또는 종료를 선택해 주세요.',
      // businessId를 data에 포함 — 다중 사업장 관리자가 다른 사업장 선택 중일 때도
      //           notification.data['businessId']를 우선 사용해 올바른 사업장 컨텍스트로 라우팅.
      data: {
        'applicationId': applicationId,
        'businessId': businessId,
        'expiryDate': expiryDate.toIso8601String(),
        'screen': 'contractRenewal',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 계약 연장 확정 알림 (근무자에게)
  static NotificationModel createContractRenewed({
    required String userId,
    required String businessName,
    required DateTime newEndDate,
    required String applicationId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.contractRenewed,
      title: '계약 연장 확정',
      body: '$businessName과의 계약이 ${newEndDate.month}/${newEndDate.day}까지 연장되었습니다.',
      data: {
        'applicationId': applicationId,
        'screen': 'mySchedule',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 계약 종료 통보 알림 (근무자에게)
  static NotificationModel createContractTerminating({
    required String userId,
    required String businessName,
    required String businessId,
    required DateTime endDate,
    required String applicationId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.contractTerminating,
      title: '계약 종료 통보',
      body: '$businessName과의 계약이 ${endDate.month}/${endDate.day}에 종료됩니다.',
      data: {
        'applicationId': applicationId,
        'businessId': businessId,
        'screen': 'mySchedule',
      },
      createdAt: DateTime.now(),
    );
  }

  static NotificationModel createWageCancelConfirmed({
    required String userId,
    required String businessName,
    required String businessId,
    required DateTime workDate,
    required String attendanceId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.wageCancelConfirmed,
      title: '급여 확정 취소',
      body: '$businessName ${workDate.month}/${workDate.day} 근무 급여 확정이 취소되었습니다. 급여 조정 후 다시 안내드릴 예정입니다.',
      data: {
        'attendanceId': attendanceId,
        'businessId': businessId,
        'action': 'wageDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 멤버 초대 알림 생성 (초대받은 근무자에게)
  static NotificationModel createMemberInvitation({
    required String targetUid,
    required String businessName,
    required String businessId,
    required String invitedByName,
    required String invitationId,
  }) {
    return NotificationModel(
      id: '',
      userId: targetUid,
      type: NotificationType.memberInvitationReceived,
      title: '관리자 초대',
      body: '$invitedByName님이 $businessName의 관리자로 초대했습니다.',
      data: {
        'invitationId': invitationId,
        'businessId': businessId,
        'action': 'memberInvitation',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 초대 수락 알림 (초대한 관리자에게)
  static NotificationModel createMemberInvitationAccepted({
    required String adminUid,
    required String acceptedName,
    required String businessName,
    required String businessId,
  }) {
    return NotificationModel(
      id: '',
      userId: adminUid,
      type: NotificationType.memberInvitationAccepted,
      title: '초대 수락됨',
      body: '$acceptedName님이 $businessName 관리자 초대를 수락했습니다.',
      data: {'action': 'memberManagement', 'businessId': businessId},
      createdAt: DateTime.now(),
    );
  }

  /// 초대 거절 알림 (초대한 관리자에게)
  static NotificationModel createMemberInvitationRejected({
    required String adminUid,
    required String rejectedName,
    required String businessName,
    required String businessId,
  }) {
    return NotificationModel(
      id: '',
      userId: adminUid,
      type: NotificationType.memberInvitationRejected,
      title: '초대 거절됨',
      body: '$rejectedName님이 $businessName 관리자 초대를 거절했습니다.',
      data: {'action': 'memberManagement', 'businessId': businessId},
      createdAt: DateTime.now(),
    );
  }
}
