// lib/models/core/notification_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// 알림 유형
enum NotificationType {
  // 지원 관련
  applicationConfirmed,    // 지원 확정됨
  applicationRejected,     // 지원 거절됨
  
  // 근무 관련
  workReminder,            // 근무 리마인더 (내일 근무 있음)
  workCanceled,            // 근무 취소됨
  
  // 리뷰 관련
  reviewReceived,          // 리뷰 받음
  
  // 신분증 열람 관련
  idCardAccessRequested,   // 신분증 열람 요청됨 (지원자에게)
  idCardAccessApproved,    // 신분증 열람 승인됨 (관리자에게)
  idCardAccessRejected,    // 신분증 열람 거절됨 (관리자에게)
  idCardAccessExpiringSoon,// 신분증 열람 권한 만료 임박
  
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
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      readAt: (map['readAt'] as Timestamp?)?.toDate(),
    );
  }

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    return NotificationModel.fromMap(
      doc.data() as Map<String, dynamic>, 
      doc.id,
    );
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
      'createdAt': Timestamp.fromDate(createdAt),
      'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
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

  // ═══════════════════════════════════════════════════════════
  // Getter
  // ═══════════════════════════════════════════════════════════

  /// 알림 아이콘
  String get iconName {
    switch (type) {
      case NotificationType.applicationConfirmed:
        return 'check_circle';
      case NotificationType.applicationRejected:
        return 'cancel';
      case NotificationType.workReminder:
        return 'alarm';
      case NotificationType.workCanceled:
        return 'event_busy';
      case NotificationType.reviewReceived:
        return 'star';
      case NotificationType.idCardAccessRequested:
        return 'badge';
      case NotificationType.idCardAccessApproved:
        return 'verified';
      case NotificationType.idCardAccessRejected:
        return 'block';
      case NotificationType.idCardAccessExpiringSoon:
        return 'schedule';
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

  // ═══════════════════════════════════════════════════════════
  // Static Helper
  // ═══════════════════════════════════════════════════════════

  static NotificationType _typeFromString(String value) {
    switch (value) {
      case 'applicationConfirmed': return NotificationType.applicationConfirmed;
      case 'applicationRejected': return NotificationType.applicationRejected;
      case 'workReminder': return NotificationType.workReminder;
      case 'workCanceled': return NotificationType.workCanceled;
      case 'reviewReceived': return NotificationType.reviewReceived;
      case 'idCardAccessRequested': return NotificationType.idCardAccessRequested;
      case 'idCardAccessApproved': return NotificationType.idCardAccessApproved;
      case 'idCardAccessRejected': return NotificationType.idCardAccessRejected;
      case 'idCardAccessExpiringSoon': return NotificationType.idCardAccessExpiringSoon;
      case 'systemNotice': return NotificationType.systemNotice;
      default: return NotificationType.other;
    }
  }

  static String _typeToString(NotificationType type) {
    switch (type) {
      case NotificationType.applicationConfirmed: return 'applicationConfirmed';
      case NotificationType.applicationRejected: return 'applicationRejected';
      case NotificationType.workReminder: return 'workReminder';
      case NotificationType.workCanceled: return 'workCanceled';
      case NotificationType.reviewReceived: return 'reviewReceived';
      case NotificationType.idCardAccessRequested: return 'idCardAccessRequested';
      case NotificationType.idCardAccessApproved: return 'idCardAccessApproved';
      case NotificationType.idCardAccessRejected: return 'idCardAccessRejected';
      case NotificationType.idCardAccessExpiringSoon: return 'idCardAccessExpiringSoon';
      case NotificationType.systemNotice: return 'systemNotice';
      case NotificationType.other: return 'other';
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Factory Methods (알림 생성 헬퍼)
  // ═══════════════════════════════════════════════════════════

  /// 신분증 열람 요청 알림 생성
  static NotificationModel createIdCardAccessRequest({
    required String userId,
    required String businessName,
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
        'action': 'idCardAccessRequest',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 신분증 열람 승인 알림 생성
  static NotificationModel createIdCardAccessApproved({
    required String userId,
    required String targetUserName,
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
        'action': 'idCardAccessApproved',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 신분증 열람 거절 알림 생성
  static NotificationModel createIdCardAccessRejected({
    required String userId,
    required String targetUserName,
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
        'action': 'idCardAccessRejected',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 지원 확정 알림 생성
  static NotificationModel createApplicationConfirmed({
    required String userId,
    required String businessName,
    required String workType,
    required DateTime workDate,
    required String applicationId,
  }) {
    return NotificationModel(
      id: '',
      userId: userId,
      type: NotificationType.applicationConfirmed,
      title: '지원 확정',
      body: '$businessName의 $workType 근무가 확정되었습니다.\n근무일: ${workDate.month}/${workDate.day}',
      data: {
        'applicationId': applicationId,
        'action': 'applicationDetail',
      },
      createdAt: DateTime.now(),
    );
  }

  /// 리뷰 받음 알림 생성
  static NotificationModel createReviewReceived({
    required String userId,
    required String businessName,
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
        'action': 'reviewDetail',
      },
      createdAt: DateTime.now(),
    );
  }
}