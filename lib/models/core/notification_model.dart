import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'application_model.dart';

/// 알림 카테고리 — 수신 맥락 기반 (account role이 아닌 이벤트별 결정)
/// 같은 type도 수신자(관리자/근로자)에 따라 다른 category로 저장 가능.
/// Phase 2: CF가 각 알림 document에 명시적으로 저장. Phase 1은 resolvedCategory fallback.
enum NotificationCategory {
  personal, // 근로자 개인 자격 수신 (지원·근무·급여·계약 결과 등)
  admin,    // 관리자 역할 수신 (지원서 접수·계약 검토·인력 관리 등)
  system,   // 시스템 공지·기타
}

/// 알림 중요도 — 카드 UI 강조 수준 및 CTA 표시 기준
/// Phase 2: CF가 각 알림 document에 명시적으로 저장. Phase 1은 resolvedImportance fallback.
enum NotificationImportance {
  actionRequired, // 사용자 액션이 필요 → 단일 CTA 버튼 표시, 제목 w600
  statusUpdate,   // 상태 변경 안내 → 제목 w600(미읽음)/w500(읽음)
  reminderInfo,   // 정보 전달·리마인더 → 제목 w500, 아이콘 neutral (opacity 낮추지 않음)
}

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

  // 중간정산 관련
  interimSettlementRequested, // 중간정산 요청됨 (관리자에게)
  interimSettlementApproved,  // 중간정산 승인됨 + 이체예정일 (근로자에게)
  interimSettlementRejected,  // 중간정산 거절됨 (근로자에게)
  
  // 리뷰 관련
  reviewReceived,          // 리뷰 받음
  reviewRequest,           // 리뷰 작성 요청 (CF: "REVIEW_REQUEST")
  
  // 신분증 열람 관련
  idCardAccessRequested,   // 신분증 열람 요청됨 (지원자에게)
  idCardAccessApproved,    // 신분증 열람 승인됨 (관리자에게)
  idCardAccessRejected,    // 신분증 열람 거절됨 (관리자에게)
  // 발송 로직 미구현 — CF 스케줄러 추가 필요
  idCardAccessExpiringSoon,// 신분증 열람 권한 만료 임박
  // [ID-CONSENT] 사전동의 자동 Grant 활성화 알림 (근로자에게)
  idCardConsentGranted,    // 근무 확정으로 신분증 열람 권한 활성화됨 (지원자에게)
  
  // 멤버 관리
  memberInvitationReceived, // 하위 관리자 초대 받음 (근무자에게)
  memberInvitationAccepted, // 초대 수락됨 (관리자에게)
  memberInvitationRejected, // 초대 거절됨 (관리자에게)

  // 퇴사 리마인더 (관리자)
  resignReminder,            // 퇴사 요청 미처리 D+1/D+2 알림 (관리자에게, CF: "resignReminder", screen:"fixedWorker")

  // 공고 관련 (관리자)
  toPostingExpiringTomorrow, // 공고 게시 만료 D-1 (관리자에게, CF: "toPostingExpiringTomorrow")
  toPostingExpired,          // 공고 게시 만료됨 (관리자에게, CF: "toPostingExpired")

  // TO 초대 관련
  toInvite,               // TO 초대 받음 (근로자에게, CF: "toInvite")
  toInviteAccepted,       // 초대 수락됨 (초대한 관리자에게, CF: "toInviteAccepted")
  toInviteDeclined,       // 초대 거절됨 (초대한 관리자에게, CF: "toInviteDeclined")
  toInviteCanceled,       // 초대 취소됨 (근로자에게, CF: "toInviteCanceled")

  // 출퇴근 재확인 관련 (근무 당일 H-2/H-1 스케줄러)
  reconfirmRequest,        // 오늘 근무 확인 요청 (근로자에게, CF: "reconfirmRequest")
  reconfirmAdminWarning,   // 출근 미확인 경고 (관리자에게, CF: "reconfirmAdminWarning")
  reconfirmDeclined,       // 근무 취소됨 — 재확인 거절 (관리자에게, CF: "reconfirmDeclined")

  // 중간정산 완료 (관리자 직접 처리 경로)
  interimSettlementCompleted, // 중간정산 완료됨 (근로자에게, CF: "interimSettlementCompleted")

  // [Phase 8.1C] JOB→WORKER 매칭 알림 (근로자에게)
  toMatch,                 // 가능일에 새 일자리 발견 알림 (CF: "toMatch", screen: "toMatch")

  // 시스템
  systemNotice,            // 시스템 공지
  other,                   // 기타
}

/// [Phase 1 Legacy Fallback] 관리자(BUSINESS_ADMIN / SubAdmin)가 관리 업무로서 받는 알림 타입 집합.
///
/// ⚠️  이 Set은 category 필드가 없는 구형 Firestore 알림 문서를 위한 fallback 전용입니다.
/// Phase 2 이후 신규 알림에는 CF가 category 필드를 명시 저장하므로, resolvedCategory getter는
/// category 필드를 우선하고 이 Set은 category == null인 경우에만 참조합니다.
///
/// ❌ 신규 알림 type 분류 기준으로 사용하지 마세요.
/// ✅ 올바른 분류: factory 메서드의 category 파라미터 또는 CF의 category 필드를 사용하세요.
///
/// [제거된 타입 - 근로자 수신 또는 양방향이므로 legacy fallback에도 포함하지 않음]
/// - terminationRequested: CF가 근로자에게만 발송 → personal
/// - confirmationCanceled: CF 스케줄러가 근로자에게만 발송 → personal
/// - reviewReceived: CF 미구현 (Dead), 수신자는 리뷰를 받는 근로자 → personal
/// - reviewRequest: 관리자·근로자 양방향 → category 필드로만 구분
const Set<NotificationType> kAdminNotifTypes = {
  // 지원·채용 관련
  NotificationType.newApplication,
  NotificationType.applicationCanceled,
  // confirmationCanceled 제거: CF 스케줄러가 근로자(d.uid)에게만 발송 → personal

  // 계약 관련
  NotificationType.contractSigned,
  NotificationType.contractExpiringReminder,
  // terminationRequested 제거: callableRequestTermination이 workerUid에게만 발송 → personal
  NotificationType.resignRequested,
  NotificationType.contractRequested,
  NotificationType.resignReminder,

  // 스케줄 변경
  NotificationType.scheduleChangeRequested,

  // 신분증 열람
  NotificationType.idCardAccessApproved,
  NotificationType.idCardAccessRejected,

  // 멤버 관리
  NotificationType.memberInvitationAccepted,
  NotificationType.memberInvitationRejected,

  // 급여·정산
  NotificationType.interimSettlementRequested,

  // 리뷰 (양방향 타입 제거: category 필드로만 구분)
  // reviewReceived 제거: CF 미구현, 수신자는 리뷰 받은 근로자 → personal
  // reviewRequest 제거: 관리자·근로자 양방향 → CF category 필드로 분류

  // 공고 관련 (관리자/creatorUID에게 발송)
  NotificationType.toPostingExpiringTomorrow,
  NotificationType.toPostingExpired,

  // TO 초대 결과 (초대한 관리자에게)
  NotificationType.toInviteAccepted,
  NotificationType.toInviteDeclined,

  // 출퇴근 재확인 (관리자 수신)
  NotificationType.reconfirmAdminWarning,
  NotificationType.reconfirmDeclined,
};

/// 앱 내 알림 모델
class NotificationModel {
  static final _commaRe = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');

  final String id;
  final String userId;              // 알림 받는 사용자 UID
  final NotificationType type;      // 알림 유형
  final String title;               // 알림 제목
  final String body;                // 알림 내용
  final Map<String, dynamic>? data; // 추가 데이터 (이동할 화면 정보 등)
  final bool isRead;                // 읽음 여부
  final DateTime createdAt;         // 생성 시각
  final DateTime? readAt;           // 읽은 시각
  /// 수신 맥락 카테고리 — CF가 명시적으로 저장 (Phase 2). 없으면 resolvedCategory fallback
  final NotificationCategory? category;
  /// 중요도 — CF가 명시적으로 저장 (Phase 2). 없으면 resolvedImportance fallback
  final NotificationImportance? importance;

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
    this.category,
    this.importance,
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
      category: _categoryFromString(map['category']?.toString()),
      importance: _importanceFromString(map['importance']?.toString()),
    );
  }

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) throw ArgumentError('Document ${doc.id} has no data');
    return NotificationModel.fromMap(raw as Map<String, dynamic>, doc.id);
  }

  // [SCHEMA-09] 역직렬화 실패 격리 — 손상 문서 1건이 목록 전체 크래시 방지
  static NotificationModel? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return NotificationModel.fromFirestore(doc);
    } catch (e, st) {
      debugPrint('[NotificationModel] 역직렬화 실패 id=${doc.id}: $e\n$st');
      return null;
    }
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
      if (category != null) 'category': _categoryToString(category!),
      if (importance != null) 'importance': _importanceToString(importance!),
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
    NotificationCategory? category,
    NotificationImportance? importance,
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
      category: category ?? this.category,
      importance: importance ?? this.importance,
    );
  }

  // ── Category / Importance Getters ──────────────────────────────────────────

  /// ACTION_REQUIRED 알림 type 집합 (resolvedImportance fallback용)
  static const Set<NotificationType> _actionRequiredTypes = {
    NotificationType.contractSignRequested,
    NotificationType.memberInvitationReceived,
    NotificationType.idCardAccessRequested,
    NotificationType.reviewRequest,
    NotificationType.reconfirmRequest,
    NotificationType.terminationRequested,
    NotificationType.scheduleChangeRequested,
    NotificationType.resignRequested,
    NotificationType.contractRequested,
    NotificationType.interimSettlementRequested,
  };

  /// REMINDER_INFO 알림 type 집합 (resolvedImportance fallback용)
  static const Set<NotificationType> _reminderInfoTypes = {
    NotificationType.workReminder,
    NotificationType.contractExpiringReminder,
    NotificationType.toPostingExpiringTomorrow,
    NotificationType.toPostingExpired,
    NotificationType.resignReminder,
    NotificationType.idCardAccessExpiringSoon,
    NotificationType.systemNotice,
    NotificationType.retroactiveDeductionAlert,
    NotificationType.reconfirmAdminWarning,
    NotificationType.toMatch,          // [Phase 8.1C] 일자리 발견 알림
  };

  /// 알림 카테고리 — category 필드가 없으면 kAdminNotifTypes 기반 fallback
  /// 한계: 같은 type을 양방향으로 사용하는 경우(reviewReceived 등)에 부정확할 수 있음.
  /// CF가 category를 명시적으로 저장하면 그 값이 우선.
  NotificationCategory get resolvedCategory {
    if (category != null) return category!;
    if (type == NotificationType.systemNotice || type == NotificationType.other) {
      return NotificationCategory.system;
    }
    if (kAdminNotifTypes.contains(type)) return NotificationCategory.admin;
    return NotificationCategory.personal;
  }

  /// 알림 중요도 — importance 필드가 없으면 type 기반 fallback
  NotificationImportance get resolvedImportance {
    if (importance != null) return importance!;
    if (_actionRequiredTypes.contains(type)) return NotificationImportance.actionRequired;
    if (_reminderInfoTypes.contains(type)) return NotificationImportance.reminderInfo;
    return NotificationImportance.statusUpdate;
  }

  /// 사업장명 스냅샷 — CF가 data에 저장, 없으면 null (카드마다 Firestore 조회 금지)
  String? get businessName =>
      data?['businessName']?.toString() ??
      data?['displayBusinessName']?.toString();

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
      // 중간정산 관련
      case NotificationType.interimSettlementRequested:
        return 'account_balance_wallet';
      case NotificationType.interimSettlementApproved:
        return 'event_available';
      case NotificationType.interimSettlementRejected:
        return 'event_busy';
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
      case NotificationType.idCardConsentGranted: // [ID-CONSENT]
        return 'lock_open';
      // 멤버 관리
      case NotificationType.memberInvitationReceived:
        return 'group_add';
      case NotificationType.memberInvitationAccepted:
        return 'how_to_reg';
      case NotificationType.memberInvitationRejected:
        return 'person_remove';
      // 퇴사 리마인더
      case NotificationType.resignReminder:
        return 'alarm';
      // 공고 관련
      case NotificationType.toPostingExpiringTomorrow:
      case NotificationType.toPostingExpired:
        return 'event_note';
      // TO 초대 관련
      case NotificationType.toInvite:
      case NotificationType.toInviteCanceled:
        return 'mail';
      case NotificationType.toInviteAccepted:
        return 'how_to_reg';
      case NotificationType.toInviteDeclined:
        return 'person_remove';
      // 출퇴근 재확인 관련
      case NotificationType.reconfirmRequest:
        return 'check_circle_outline';
      case NotificationType.reconfirmAdminWarning:
      case NotificationType.reconfirmDeclined:
        return 'warning_amber';
      // 중간정산 완료
      case NotificationType.interimSettlementCompleted:
        return 'account_balance_wallet';
      // [Phase 8.1C] 일자리 매칭 알림
      case NotificationType.toMatch:
        return 'work_outline';
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

  static NotificationCategory? _categoryFromString(String? value) {
    switch (value) {
      case 'personal': return NotificationCategory.personal;
      case 'admin':    return NotificationCategory.admin;
      case 'system':   return NotificationCategory.system;
      default:         return null;
    }
  }

  static String _categoryToString(NotificationCategory cat) {
    switch (cat) {
      case NotificationCategory.personal: return 'personal';
      case NotificationCategory.admin:    return 'admin';
      case NotificationCategory.system:   return 'system';
    }
  }

  static NotificationImportance? _importanceFromString(String? value) {
    switch (value) {
      case 'actionRequired': return NotificationImportance.actionRequired;
      case 'statusUpdate':   return NotificationImportance.statusUpdate;
      case 'reminderInfo':   return NotificationImportance.reminderInfo;
      default:               return null;
    }
  }

  static String _importanceToString(NotificationImportance imp) {
    switch (imp) {
      case NotificationImportance.actionRequired: return 'actionRequired';
      case NotificationImportance.statusUpdate:   return 'statusUpdate';
      case NotificationImportance.reminderInfo:   return 'reminderInfo';
    }
  }

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
      // 중간정산 관련
      case 'interimSettlementRequested': return NotificationType.interimSettlementRequested;
      case 'interimSettlementApproved': return NotificationType.interimSettlementApproved;
      case 'interimSettlementRejected': return NotificationType.interimSettlementRejected;
      // 리뷰
      case 'reviewReceived': return NotificationType.reviewReceived;
      case 'REVIEW_REQUEST': return NotificationType.reviewRequest; // 레거시 — 기존 Firestore 문서 역직렬화 호환
      case 'reviewRequest': return NotificationType.reviewRequest; // 신규 camelCase (CF 통일 후)
      // 신분증
      case 'idCardAccessRequested': return NotificationType.idCardAccessRequested;
      case 'idCardAccessApproved': return NotificationType.idCardAccessApproved;
      case 'idCardAccessRejected': return NotificationType.idCardAccessRejected;
      case 'idCardAccessExpiringSoon': return NotificationType.idCardAccessExpiringSoon;
      case 'idCardConsentGranted': return NotificationType.idCardConsentGranted; // [ID-CONSENT]
      // 멤버 관리
      case 'memberInvitationReceived': return NotificationType.memberInvitationReceived;
      case 'memberInvitationAccepted': return NotificationType.memberInvitationAccepted;
      case 'memberInvitationRejected': return NotificationType.memberInvitationRejected;
      // 퇴사 리마인더
      case 'resignReminder': return NotificationType.resignReminder;
      // 공고 관련
      case 'toPostingExpiringTomorrow': return NotificationType.toPostingExpiringTomorrow;
      case 'toPostingExpired': return NotificationType.toPostingExpired;
      // TO 초대 관련
      case 'toInvite': return NotificationType.toInvite;
      case 'toInviteAccepted': return NotificationType.toInviteAccepted;
      case 'toInviteDeclined': return NotificationType.toInviteDeclined;
      case 'toInviteCanceled': return NotificationType.toInviteCanceled;
      // 출퇴근 재확인 관련
      case 'reconfirmRequest': return NotificationType.reconfirmRequest;
      case 'reconfirmAdminWarning': return NotificationType.reconfirmAdminWarning;
      case 'reconfirmDeclined': return NotificationType.reconfirmDeclined;
      // 중간정산 완료
      case 'interimSettlementCompleted': return NotificationType.interimSettlementCompleted;
      // [Phase 8.1C] 일자리 매칭 알림
      case 'toMatch': return NotificationType.toMatch;
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
      // 중간정산 관련
      case NotificationType.interimSettlementRequested: return 'interimSettlementRequested';
      case NotificationType.interimSettlementApproved: return 'interimSettlementApproved';
      case NotificationType.interimSettlementRejected: return 'interimSettlementRejected';
      // 리뷰
      case NotificationType.reviewReceived: return 'reviewReceived';
      case NotificationType.reviewRequest: return 'reviewRequest'; // 구버전 'REVIEW_REQUEST' → 신규 camelCase 통일
      // 신분증
      case NotificationType.idCardAccessRequested: return 'idCardAccessRequested';
      case NotificationType.idCardAccessApproved: return 'idCardAccessApproved';
      case NotificationType.idCardAccessRejected: return 'idCardAccessRejected';
      case NotificationType.idCardAccessExpiringSoon: return 'idCardAccessExpiringSoon';
      case NotificationType.idCardConsentGranted: return 'idCardConsentGranted'; // [ID-CONSENT]
      // 멤버 관리
      case NotificationType.memberInvitationReceived: return 'memberInvitationReceived';
      case NotificationType.memberInvitationAccepted: return 'memberInvitationAccepted';
      case NotificationType.memberInvitationRejected: return 'memberInvitationRejected';
      // 퇴사 리마인더
      case NotificationType.resignReminder: return 'resignReminder';
      // 공고 관련
      case NotificationType.toPostingExpiringTomorrow: return 'toPostingExpiringTomorrow';
      case NotificationType.toPostingExpired: return 'toPostingExpired';
      // TO 초대 관련
      case NotificationType.toInvite: return 'toInvite';
      case NotificationType.toInviteAccepted: return 'toInviteAccepted';
      case NotificationType.toInviteDeclined: return 'toInviteDeclined';
      case NotificationType.toInviteCanceled: return 'toInviteCanceled';
      // 출퇴근 재확인 관련
      case NotificationType.reconfirmRequest: return 'reconfirmRequest';
      case NotificationType.reconfirmAdminWarning: return 'reconfirmAdminWarning';
      case NotificationType.reconfirmDeclined: return 'reconfirmDeclined';
      // 중간정산 완료
      case NotificationType.interimSettlementCompleted: return 'interimSettlementCompleted';
      // [Phase 8.1C] 일자리 매칭 알림
      case NotificationType.toMatch: return 'toMatch';
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
      category: NotificationCategory.personal,
      createdAt: DateTime.now(),
    );
  }

  /// 신분증 열람 승인 알림 생성
  static NotificationModel createIdCardAccessApproved({
    required String userId,
    required String targetUserName,
    required String businessId,
    required String requestId,
    required String workerId,
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
        'workerId': workerId,
        'action': 'idCardAccessApproved',
      },
      category: NotificationCategory.admin,
      createdAt: DateTime.now(),
    );
  }

  /// 신분증 열람 거절 알림 생성
  static NotificationModel createIdCardAccessRejected({
    required String userId,
    required String targetUserName,
    required String businessId,
    required String requestId,
    required String workerId,
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
        'workerId': workerId,
        'action': 'idCardAccessRejected',
      },
      category: NotificationCategory.admin,
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
      category: NotificationCategory.personal,
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
      category: NotificationCategory.personal,
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
      category: NotificationCategory.personal,
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
        'workDate': workDate.toIso8601String(),
        'action': 'applicantDetail',
      },
      category: NotificationCategory.admin,
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
        'workDate': workDate.toIso8601String(),
        'action': 'applicantDetail',
      },
      category: NotificationCategory.admin,
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
        'workDate': workDate.toIso8601String(),
        'action': 'applicantDetail',
      },
      category: NotificationCategory.admin,
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
      category: NotificationCategory.personal,
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
      category: NotificationCategory.admin,
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
      category: NotificationCategory.personal,
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
      category: NotificationCategory.personal,
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
      category: NotificationCategory.personal,
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
      category: NotificationCategory.admin,
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
      category: NotificationCategory.personal,
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
      category: NotificationCategory.personal,
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
      category: NotificationCategory.personal,
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
      category: NotificationCategory.personal,
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
      category: NotificationCategory.personal,
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
      category: NotificationCategory.personal,
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
      category: NotificationCategory.personal,
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
      _commaRe,
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
      category: NotificationCategory.personal,
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
      _commaRe,
      (Match m) => '${m[1]},',
    );
    final netFormatted = netWage.toString().replaceAllMapped(
      _commaRe,
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
      category: NotificationCategory.personal,
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
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.wageTransferred,
      title: '급여 송금 완료',
      body: '[$businessName] $workerName님의 급여가 송금 처리되었습니다. 앱에서 확인하세요.',
      createdAt: DateTime.now(),
      data: {
        if (applicationId != null) 'applicationId': applicationId,
        'businessId': businessId,
        'screen': 'wageTransferred',
      },
      category: NotificationCategory.personal,
    );
  }

  /// 중간정산 요청 알림 생성 (관리자에게)
  static NotificationModel createInterimSettlementRequested({
    required String userId,       // 관리자 uid
    required String workerName,
    required String businessName,
    required String businessId,
    required String settlementRequestId,
    required int recordCount,
    required int netAmount,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    final periodText =
        '${periodStart.month}/${periodStart.day}~${periodEnd.month}/${periodEnd.day}';
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.interimSettlementRequested,
      title: '중간정산 요청',
      body: '[$businessName] $workerName 님이 $periodText $recordCount건 중간정산을 요청했습니다.',
      createdAt: DateTime.now(),
      data: {
        'businessId': businessId,
        'settlementRequestId': settlementRequestId,
        'screen': 'interimSettlementAdmin',
      },
      category: NotificationCategory.admin,
    );
  }

  /// 중간정산 승인 알림 생성 (근로자에게) — 이체예정일 포함
  static NotificationModel createInterimSettlementApproved({
    required String userId,       // 근로자 uid
    required String businessName,
    required String businessId,
    required String settlementRequestId,
    required int netAmount,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime scheduledTransferDate,
  }) {
    final periodText =
        '${periodStart.month}/${periodStart.day}~${periodEnd.month}/${periodEnd.day}';
    final transferText =
        '${scheduledTransferDate.month}/${scheduledTransferDate.day}';
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.interimSettlementApproved,
      title: '중간정산 승인됨',
      body: '[$businessName] $periodText 중간정산이 승인되었습니다. $transferText에 이체될 예정입니다.',
      createdAt: DateTime.now(),
      data: {
        'businessId': businessId,
        'settlementRequestId': settlementRequestId,
        'scheduledTransferDate': scheduledTransferDate.toIso8601String(),
        'netAmount': netAmount,
        'screen': 'interimSettlement',
      },
      category: NotificationCategory.personal,
    );
  }

  /// 중간정산 거절 알림 생성 (근로자에게)
  static NotificationModel createInterimSettlementRejected({
    required String userId,       // 근로자 uid
    required String businessName,
    required String businessId,
    required String settlementRequestId,
    required DateTime periodStart,
    required DateTime periodEnd,
    String? rejectReason,
  }) {
    final periodText =
        '${periodStart.month}/${periodStart.day}~${periodEnd.month}/${periodEnd.day}';
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.interimSettlementRejected,
      title: '중간정산 거절됨',
      body: '[$businessName] $periodText 중간정산 요청이 거절되었습니다.${rejectReason != null ? '\n사유: $rejectReason' : ''}',
      createdAt: DateTime.now(),
      data: {
        'businessId': businessId,
        'settlementRequestId': settlementRequestId,
        'screen': 'interimSettlement',
      },
      category: NotificationCategory.personal,
    );
  }

  /// 중간정산 완료 알림 생성 (근로자에게)
  static NotificationModel createInterimSettlementCompleted({
    required String userId,
    required String workerName,
    required String businessName,
    required String businessId,
    required int netAmount,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String settlementRequestId,
  }) {
    final periodText =
        '${periodStart.month}/${periodStart.day}~${periodEnd.month}/${periodEnd.day}';
    return NotificationModel(
      id: '',
      userId: userId,
      // [BUG-FIX] 이전: wageTransferred (오류). 올바른 타입: interimSettlementCompleted
      // CF callableAdminDirectInterimSettlement는 이미 interimSettlementCompleted를 사용하고 있음.
      // 이 factory를 통해 createNotification callable을 호출하는 경우도 올바른 type으로 저장됨.
      type: NotificationType.interimSettlementCompleted,
      title: '중간정산 완료',
      body: '[$businessName] $periodText 기간 중간정산이 완료되었습니다. 실수령액을 앱에서 확인하세요.',
      createdAt: DateTime.now(),
      data: {
        'businessId': businessId,
        'settlementRequestId': settlementRequestId,
        'screen': 'interimSettlement',
        'netAmount': netAmount,
      },
      category: NotificationCategory.personal,
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
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.wageConfirmed,
      title: '급여 정산 완료',
      body: '$businessName ${workDate.month}/${workDate.day} 근무 급여가 정산되었습니다. 앱에서 확인하세요.',
      data: {
        'attendanceId': attendanceId,
        'businessId': businessId,
        'action': 'wageDetail',
      },
      category: NotificationCategory.personal,
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
      category: NotificationCategory.admin,
      createdAt: DateTime.now(),
    );
  }

  /// 계약 연장 확정 알림 (근무자에게)
  static NotificationModel createContractRenewed({
    required String userId,
    required String businessName,
    required String businessId,
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
        'businessId': businessId,
        'screen': 'mySchedule',
      },
      category: NotificationCategory.personal,
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
      category: NotificationCategory.personal,
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
      category: NotificationCategory.personal,
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
      category: NotificationCategory.personal,
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
      category: NotificationCategory.admin,
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
      category: NotificationCategory.admin,
      createdAt: DateTime.now(),
    );
  }
}
