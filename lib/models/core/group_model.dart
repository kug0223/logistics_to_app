import 'package:cloud_firestore/cloud_firestore.dart';

/// @deprecated Phase 2 리팩토링에서 삭제 예정.
/// groups 컬렉션은 slots 서브컬렉션 구조로 대체됨.
/// firestore_service.dart, admin_to_list_ui_models.dart 참조 제거 후 삭제.
class GroupModel {
  final String id;                  // 문서 ID (group_xxx)
  final String groupName;           // 그룹 표시명 (예: "12월 셋째주")
  
  // 사업장 정보
  final String businessId;
  final String businessName;
  final String? businessAddress;
  final String? businessCity;
  final String? businessDistrict;
  
  // 공고 정보
  final String title;               // 공고 제목
  final String? description;
  final DateTime startDate;         // 그룹 시작일
  final DateTime endDate;           // 그룹 종료일
  
  // 상태 (그룹 전체 상태)
  final String status;              // ACTIVE | CLOSED | EXPIRED | SCHEDULED
  final DateTime? statusUpdatedAt;
  
  // 통계 (그룹 전체 합산)
  final int totalRequired;
  final int totalConfirmed;
  final int totalPending;
  final int actualDaysCount;        // 실제 TO 개수
  
  // 급여 정보
  final int? minWage;
  final int? maxWage;
  final String? wageType;
  final int workDetailCount;
  
  // 예약 공개
  final String publishMode;         // 'immediate' | 'scheduled'
  final DateTime? publishAt;
  final bool isPublished;
  final int? publishDaysBefore;
  final String? publishTime;
  
  // 마감 관리
  final bool isManualClosed;
  final DateTime? closedAt;
  final String? closedBy;
  final DateTime? reopenedAt;
  final String? reopenedBy;
  
  // 메타
  final String creatorUID;
  final DateTime createdAt;

  GroupModel({
    required this.id,
    required this.groupName,
    required this.businessId,
    required this.businessName,
    this.businessAddress,
    this.businessCity,
    this.businessDistrict,
    required this.title,
    this.description,
    required this.startDate,
    required this.endDate,
    this.status = 'ACTIVE',
    this.statusUpdatedAt,
    this.totalRequired = 0,
    this.totalConfirmed = 0,
    this.totalPending = 0,
    this.actualDaysCount = 0,
    this.minWage,
    this.maxWage,
    this.wageType,
    this.workDetailCount = 1,
    this.publishMode = 'immediate',
    this.publishAt,
    this.isPublished = true,
    this.publishDaysBefore,
    this.publishTime,
    this.isManualClosed = false,
    this.closedAt,
    this.closedBy,
    this.reopenedAt,
    this.reopenedBy,
    required this.creatorUID,
    required this.createdAt,
  });

  /// Firestore 문서를 GroupModel로 변환
  factory GroupModel.fromMap(Map<String, dynamic> data, String documentId) {
    return GroupModel(
      id: documentId,
      groupName: data['groupName'] ?? '',
      businessId: data['businessId'] ?? '',
      businessName: data['businessName'] ?? '',
      businessAddress: data['businessAddress'],
      businessCity: data['businessCity'],
      businessDistrict: data['businessDistrict'],
      title: data['title'] ?? '제목 없음',
      description: data['description'],
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp).toDate(),
      status: data['status'] ?? 'ACTIVE',
      statusUpdatedAt: data['statusUpdatedAt'] != null
          ? (data['statusUpdatedAt'] as Timestamp).toDate()
          : null,
      totalRequired: data['totalRequired'] ?? 0,
      totalConfirmed: data['totalConfirmed'] ?? 0,
      totalPending: data['totalPending'] ?? 0,
      actualDaysCount: data['actualDaysCount'] ?? 0,
      minWage: data['minWage'],
      maxWage: data['maxWage'],
      wageType: data['wageType'],
      workDetailCount: data['workDetailCount'] ?? 1,
      publishMode: data['publishMode'] ?? 'immediate',
      publishAt: data['publishAt'] != null
          ? (data['publishAt'] as Timestamp).toDate().toLocal()
          : null,
      isPublished: data['isPublished'] ?? true,
      publishDaysBefore: data['publishDaysBefore'],
      publishTime: data['publishTime'],
      isManualClosed: data['isManualClosed'] ?? false,
      closedAt: data['closedAt'] != null
          ? (data['closedAt'] as Timestamp).toDate()
          : null,
      closedBy: data['closedBy'],
      reopenedAt: data['reopenedAt'] != null
          ? (data['reopenedAt'] as Timestamp).toDate()
          : null,
      reopenedBy: data['reopenedBy'],
      creatorUID: data['creatorUID'] ?? '',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  /// GroupModel을 Firestore 문서로 변환
  Map<String, dynamic> toMap() {
    return {
      'groupName': groupName,
      'businessId': businessId,
      'businessName': businessName,
      'businessAddress': businessAddress,
      'businessCity': businessCity,
      'businessDistrict': businessDistrict,
      'title': title,
      'description': description,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'status': status,
      'statusUpdatedAt': statusUpdatedAt != null 
          ? Timestamp.fromDate(statusUpdatedAt!) 
          : null,
      'totalRequired': totalRequired,
      'totalConfirmed': totalConfirmed,
      'totalPending': totalPending,
      'actualDaysCount': actualDaysCount,
      'minWage': minWage,
      'maxWage': maxWage,
      'wageType': wageType,
      'workDetailCount': workDetailCount,
      'publishMode': publishMode,
      'publishAt': publishAt != null ? Timestamp.fromDate(publishAt!) : null,
      'isPublished': isPublished,
      'publishDaysBefore': publishDaysBefore,
      'publishTime': publishTime,
      'isManualClosed': isManualClosed,
      'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
      'closedBy': closedBy,
      'reopenedAt': reopenedAt != null ? Timestamp.fromDate(reopenedAt!) : null,
      'reopenedBy': reopenedBy,
      'creatorUID': creatorUID,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// 복사본 생성
  GroupModel copyWith({
    String? id,
    String? groupName,
    String? businessId,
    String? businessName,
    String? businessAddress,
    String? businessCity,
    String? businessDistrict,
    String? title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    DateTime? statusUpdatedAt,
    int? totalRequired,
    int? totalConfirmed,
    int? totalPending,
    int? actualDaysCount,
    int? minWage,
    int? maxWage,
    String? wageType,
    int? workDetailCount,
    String? publishMode,
    DateTime? publishAt,
    bool? isPublished,
    int? publishDaysBefore,
    String? publishTime,
    bool? isManualClosed,
    DateTime? closedAt,
    String? closedBy,
    DateTime? reopenedAt,
    String? reopenedBy,
    String? creatorUID,
    DateTime? createdAt,
  }) {
    return GroupModel(
      id: id ?? this.id,
      groupName: groupName ?? this.groupName,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      businessAddress: businessAddress ?? this.businessAddress,
      businessCity: businessCity ?? this.businessCity,
      businessDistrict: businessDistrict ?? this.businessDistrict,
      title: title ?? this.title,
      description: description ?? this.description,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
      totalRequired: totalRequired ?? this.totalRequired,
      totalConfirmed: totalConfirmed ?? this.totalConfirmed,
      totalPending: totalPending ?? this.totalPending,
      actualDaysCount: actualDaysCount ?? this.actualDaysCount,
      minWage: minWage ?? this.minWage,
      maxWage: maxWage ?? this.maxWage,
      wageType: wageType ?? this.wageType,
      workDetailCount: workDetailCount ?? this.workDetailCount,
      publishMode: publishMode ?? this.publishMode,
      publishAt: publishAt ?? this.publishAt,
      isPublished: isPublished ?? this.isPublished,
      publishDaysBefore: publishDaysBefore ?? this.publishDaysBefore,
      publishTime: publishTime ?? this.publishTime,
      isManualClosed: isManualClosed ?? this.isManualClosed,
      closedAt: closedAt ?? this.closedAt,
      closedBy: closedBy ?? this.closedBy,
      reopenedAt: reopenedAt ?? this.reopenedAt,
      reopenedBy: reopenedBy ?? this.reopenedBy,
      creatorUID: creatorUID ?? this.creatorUID,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Getter 메서드
  // ═══════════════════════════════════════════════════════════

  /// 그룹화 여부 (항상 true)
  bool get isGrouped => true;

  /// 마감 여부
  bool get isClosed {
    return isManualClosed || status == 'CLOSED' || status == 'EXPIRED';
  }

  /// 활성 여부
  bool get isActive => status == 'ACTIVE';

  /// 예약 공개 대기 중 여부
  bool get isPendingPublish {
    if (publishMode != 'scheduled') return false;
    if (isPublished) return false;
    if (publishAt == null) return false;
    return DateTime.now().isBefore(publishAt!);
  }

  /// 인원 충족 여부
  bool get isFull => totalConfirmed >= totalRequired && totalRequired > 0;

  /// 남은 자리 수
  int get availableSlots => totalRequired - totalConfirmed;

  /// 날짜 범위 문자열 (예: "12/15 (월) 외 6일")
  String get dateRangeString {
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final startWeekday = weekdays[startDate.weekday - 1];
    final days = endDate.difference(startDate).inDays + 1;
    return '${startDate.month}/${startDate.day} ($startWeekday) 외 $days일';
  }

  /// 날짜 범위 (예: "12/15~12/21")
  String get periodString {
    return '${startDate.month}/${startDate.day}~${endDate.month}/${endDate.day}';
  }

  /// 마감 시간 포맷
  String? get formattedDeadline {
    if (publishAt == null) return null;
    return '${publishAt!.month}/${publishAt!.day} '
           '${publishAt!.hour.toString().padLeft(2, '0')}:'
           '${publishAt!.minute.toString().padLeft(2, '0')}';
  }

  @override
  String toString() {
    return 'GroupModel(id: $id, groupName: $groupName, title: $title, '
        'status: $status, period: $periodString, '
        'stats: $totalConfirmed/$totalRequired)';
  }
}