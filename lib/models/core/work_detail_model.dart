import 'package:cloud_firestore/cloud_firestore.dart';

/// TO의 업무 상세 정보 모델
/// 하나의 TO에 여러 업무유형(분류, 피킹 등)이 포함될 수 있음
class WorkDetailModel {
  final String id; // Firestore 문서 ID
  final String workType; // 업무 유형 (예: "분류", "피킹", "인덕션")
  final String workTypeIcon; // 업무 아이콘 (예: "📦")
  final String workTypeColor; // 업무 색상 (예: "#FF5733")
  final String? workTypeBackgroundColor;
  final int wage; // 시급 또는 일급 (원)
  final String wageType;
  final int requiredCount; // 필요 인원
  final int currentCount; // 현재 확정된 인원
  final String startTime; // 시작 시간 (예: "09:00")
  final String endTime; // 종료 시간 (예: "18:00")
  final int order; // 표시 순서 (0부터 시작)
  final DateTime createdAt; // 생성 시각
  
  // 🔥 NEW: 업무별 마감 관련
  final DateTime? applicationDeadline;  // 지원 마감 시간
  final DateTime? closedAt;              // 마감된 시간
  final String? closedBy;                // 마감한 관리자 UID
  final bool isManualClosed;             // 수동 마감 여부
  
  // 🔥 NEW: 긴급 모집 관련
  final bool isEmergencyOpen;            // 긴급 모집 모드
  final DateTime? emergencyOpenedAt;     // 긴급 모집 시작 시간
  final String? emergencyOpenedBy;       // 긴급 모집 시작한 관리자

  int pendingCount;

  WorkDetailModel({
    required this.id,
    required this.workType,
    this.workTypeIcon = '📋',
    this.workTypeColor = '#2196F3',
    this.workTypeBackgroundColor,
    required this.wage,
    this.wageType = 'hourly',
    required this.requiredCount,
    this.currentCount = 0,
    required this.startTime,
    required this.endTime,
    required this.order,
    required this.createdAt,
    this.pendingCount = 0,
    this.applicationDeadline,
    this.closedAt,
    this.closedBy,
    this.isManualClosed = false,
    this.isEmergencyOpen = false,
    this.emergencyOpenedAt,
    this.emergencyOpenedBy,
  });
  
  // 🔥 Getter 추가
  bool get isClosed => closedAt != null && !isEmergencyOpen;
  
  bool get isTimeExpired {
    if (applicationDeadline == null) return false;
    return DateTime.now().isAfter(applicationDeadline!) && !isEmergencyOpen;
  }
  
  bool get isInEmergencyMode => isEmergencyOpen && closedAt != null;

  /// Firestore 문서를 WorkDetailModel로 변환
  factory WorkDetailModel.fromMap(Map<String, dynamic> map, String id) {
    return WorkDetailModel(
      id: id,
      workType: map['workType'] ?? '',
      workTypeIcon: map['workTypeIcon'] ?? '📋',
      workTypeColor: map['workTypeColor'] ?? '#2196F3',
      workTypeBackgroundColor: map['workTypeBackgroundColor'],
      wage: map['wage'] ?? 0,
      wageType: map['wageType'] ?? 'hourly',
      requiredCount: map['requiredCount'] ?? 0,
      currentCount: map['currentCount'] ?? 0,
      startTime: map['startTime'] ?? '09:00',
      endTime: map['endTime'] ?? '18:00',
      order: map['order'] ?? 0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      pendingCount: map['pendingCount'] ?? 0,
      applicationDeadline: (map['applicationDeadline'] as Timestamp?)?.toDate(),
      closedAt: (map['closedAt'] as Timestamp?)?.toDate(),
      closedBy: map['closedBy'],
      isManualClosed: map['isManualClosed'] ?? false,
      isEmergencyOpen: map['isEmergencyOpen'] ?? false,
      emergencyOpenedAt: (map['emergencyOpenedAt'] as Timestamp?)?.toDate(),
      emergencyOpenedBy: map['emergencyOpenedBy'],
    );
  }

  /// WorkDetailModel을 Firestore 문서로 변환
  Map<String, dynamic> toMap() {
    return {
      'workType': workType,
      'workTypeIcon': workTypeIcon,
      'workTypeColor': workTypeColor,
      'workTypeBackgroundColor': workTypeBackgroundColor,
      'wage': wage,
      'wageType': wageType,
      'requiredCount': requiredCount,
      'currentCount': currentCount,
      'startTime': startTime,
      'endTime': endTime,
      'order': order,
      'createdAt': Timestamp.fromDate(createdAt),
      'applicationDeadline': applicationDeadline != null 
          ? Timestamp.fromDate(applicationDeadline!) 
          : null,
      'closedAt': closedAt != null 
          ? Timestamp.fromDate(closedAt!) 
          : null,
      'closedBy': closedBy,
      'isManualClosed': isManualClosed,
      'isEmergencyOpen': isEmergencyOpen,
      'emergencyOpenedAt': emergencyOpenedAt != null 
          ? Timestamp.fromDate(emergencyOpenedAt!) 
          : null,
      'emergencyOpenedBy': emergencyOpenedBy,
    };
  }

  /// 복사본 생성 (일부 필드만 변경)
  WorkDetailModel copyWith({
    String? id,
    String? workType,
    String? workTypeIcon,
    String? workTypeColor,
    String? workTypeBackgroundColor,
    int? wage,
    String? wageType,
    int? requiredCount,
    int? currentCount,
    String? startTime,
    String? endTime,
    int? order,
    DateTime? createdAt,
    int? pendingCount,
    DateTime? applicationDeadline,
    DateTime? closedAt,
    String? closedBy,
    bool? isManualClosed,
    bool? isEmergencyOpen,
    DateTime? emergencyOpenedAt,
    String? emergencyOpenedBy,
  }) {
    return WorkDetailModel(
      id: id ?? this.id,
      workType: workType ?? this.workType,
      workTypeIcon: workTypeIcon ?? this.workTypeIcon,
      workTypeColor: workTypeColor ?? this.workTypeColor,
      workTypeBackgroundColor: workTypeBackgroundColor ?? this.workTypeBackgroundColor,
      wage: wage ?? this.wage,
      wageType: wageType ?? this.wageType,
      requiredCount: requiredCount ?? this.requiredCount,
      currentCount: currentCount ?? this.currentCount,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
      pendingCount: pendingCount ?? this.pendingCount,
      applicationDeadline: applicationDeadline ?? this.applicationDeadline,
      closedAt: closedAt ?? this.closedAt,
      closedBy: closedBy ?? this.closedBy,
      isManualClosed: isManualClosed ?? this.isManualClosed,
      isEmergencyOpen: isEmergencyOpen ?? this.isEmergencyOpen,
      emergencyOpenedAt: emergencyOpenedAt ?? this.emergencyOpenedAt,
      emergencyOpenedBy: emergencyOpenedBy ?? this.emergencyOpenedBy,
    );
  }

  /// 근무시간 범위 문자열 (예: "09:00 ~ 18:00")
  String get timeRange => '$startTime ~ $endTime';

  /// 마감 여부 (확정 인원이 필요 인원에 도달)
  bool get isFull => currentCount >= requiredCount;

  /// 남은 인원
  int get remainingCount => requiredCount - currentCount;

  /// 포맷팅된 금액 (예: "50,000원")
  String get formattedWage {
    return '${wage.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )}원';
  }
  /// ⭐ 추가! 급여 타입 라벨 (예: "시급")
  String get wageTypeLabel {
    switch (wageType) {
      case 'hourly':
        return '시급';
      case 'daily':
        return '일급';
      case 'monthly':
        return '월급';
      default:
        return '급여';
    }
  }

  /// 인원 정보 문자열 (예: "3/5명")
  String get countInfo => '$currentCount/$requiredCount명';

  @override
  String toString() {
    return 'WorkDetailModel(id: $id, workType: $workType, '
        'workTypeIcon: $workTypeIcon, workTypeColor: $workTypeColor, '
        'wage: $wage, requiredCount: $requiredCount, currentCount: $currentCount, '
        'timeRange: $timeRange, order: $order, isClosed: $isClosed, isEmergencyOpen: $isEmergencyOpen)';
  }
}