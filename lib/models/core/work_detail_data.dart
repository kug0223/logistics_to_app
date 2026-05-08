import 'package:cloud_firestore/cloud_firestore.dart';

/// TO 문서 내 배열로 저장되는 업무 상세 데이터 (경량 모델)
///
/// WorkDetailModel(Firestore 서브컬렉션)을 대체.
/// TOModel.workDetails 배열의 원소로 사용되며 별도 문서를 생성하지 않음.
class WorkDetailData {
  final String workType;
  final String workTypeIcon;
  final String workTypeColor;
  final String workTypeBackgroundColor;
  final int wage;
  final String wageType; // 'hourly' | 'daily' | 'monthly'
  final int requiredCount;
  final String startTime; // 'HH:mm'
  final String endTime;   // 'HH:mm'
  final int order;

  /// 업무 시작시간 기준으로 계산된 지원 마감 시각
  /// 슬롯 생성/수정 시 자동 계산되어 Firestore에 저장됨
  final DateTime? applicationDeadline;

  // 런타임 전용 상태 (Firestore에 저장하지 않음)
  final bool isManualClosed;
  final bool isEmergencyOpen;
  final DateTime? closedAt;
  final String? closedBy;
  final DateTime? emergencyOpenedAt;

  const WorkDetailData({
    required this.workType,
    this.workTypeIcon = '📋',
    this.workTypeColor = '#2196F3',
    this.workTypeBackgroundColor = '#E3F2FD',
    required this.wage,
    this.wageType = 'hourly',
    required this.requiredCount,
    required this.startTime,
    required this.endTime,
    this.order = 0,
    this.applicationDeadline,
    this.isManualClosed = false,
    this.isEmergencyOpen = false,
    this.closedAt,
    this.closedBy,
    this.emergencyOpenedAt,
  });

  factory WorkDetailData.fromMap(Map<String, dynamic> map, [String? id]) {
    return WorkDetailData(
      workType: map['workType'] as String? ?? id ?? '',
      workTypeIcon: map['workTypeIcon'] as String? ?? '📋',
      workTypeColor: map['workTypeColor'] as String? ?? '#2196F3',
      workTypeBackgroundColor: map['workTypeBackgroundColor'] as String? ?? '#E3F2FD',
      wage: map['wage'] as int? ?? 0,
      wageType: map['wageType'] as String? ?? 'hourly',
      requiredCount: map['requiredCount'] as int? ?? 0,
      startTime: map['startTime'] as String? ?? '09:00',
      endTime: map['endTime'] as String? ?? '18:00',
      order: map['order'] as int? ?? 0,
      applicationDeadline:
          (map['applicationDeadline'] as Timestamp?)?.toDate().toLocal(),
      isManualClosed: map['isManualClosed'] as bool? ?? false,
      isEmergencyOpen: map['isEmergencyOpen'] as bool? ?? false,
      closedAt: (map['closedAt'] as Timestamp?)?.toDate().toLocal(),
      closedBy: map['closedBy'] as String?,
      emergencyOpenedAt: (map['emergencyOpenedAt'] as Timestamp?)?.toDate().toLocal(),
    );
  }

  Map<String, dynamic> toMap() => {
    'workType': workType,
    'workTypeIcon': workTypeIcon,
    'workTypeColor': workTypeColor,
    'workTypeBackgroundColor': workTypeBackgroundColor,
    'wage': wage,
    'wageType': wageType,
    'requiredCount': requiredCount,
    'startTime': startTime,
    'endTime': endTime,
    'order': order,
    if (applicationDeadline != null)
      'applicationDeadline': Timestamp.fromDate(applicationDeadline!.toUtc()),
    if (isManualClosed) 'isManualClosed': true,
    if (closedAt != null) 'closedAt': Timestamp.fromDate(closedAt!.toUtc()),
    if (closedBy != null) 'closedBy': closedBy,
    if (isEmergencyOpen) 'isEmergencyOpen': true,
    if (emergencyOpenedAt != null)
      'emergencyOpenedAt': Timestamp.fromDate(emergencyOpenedAt!.toUtc()),
  };

  WorkDetailData copyWith({
    String? workType,
    String? workTypeIcon,
    String? workTypeColor,
    String? workTypeBackgroundColor,
    int? wage,
    String? wageType,
    int? requiredCount,
    String? startTime,
    String? endTime,
    int? order,
    bool? isManualClosed,
    bool? isEmergencyOpen,
    DateTime? closedAt,
    String? closedBy,
    DateTime? emergencyOpenedAt,
    DateTime? applicationDeadline,
    bool clearClosedAt = false,
    bool clearEmergency = false,
  }) {
    return WorkDetailData(
      workType: workType ?? this.workType,
      workTypeIcon: workTypeIcon ?? this.workTypeIcon,
      workTypeColor: workTypeColor ?? this.workTypeColor,
      workTypeBackgroundColor: workTypeBackgroundColor ?? this.workTypeBackgroundColor,
      wage: wage ?? this.wage,
      wageType: wageType ?? this.wageType,
      requiredCount: requiredCount ?? this.requiredCount,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      order: order ?? this.order,
      isManualClosed: clearClosedAt ? false : (isManualClosed ?? this.isManualClosed),
      isEmergencyOpen: clearEmergency ? false : (isEmergencyOpen ?? this.isEmergencyOpen),
      closedAt: clearClosedAt ? null : (closedAt ?? this.closedAt),
      closedBy: clearClosedAt ? null : (closedBy ?? this.closedBy),
      emergencyOpenedAt: clearEmergency ? null : (emergencyOpenedAt ?? this.emergencyOpenedAt),
      applicationDeadline: applicationDeadline ?? this.applicationDeadline,
    );
  }

  // ── 헬퍼 ──────────────────────────────────────────

  String get timeRange => '$startTime ~ $endTime';

  // ── 하위 호환성 getters (구 WorkDetailModel 기반 화면용) ──────

  /// 합성 ID — workType 기반 (구 Firestore 서브컬렉션 ID 대체)
  String get id => workType;

  /// 마감 여부
  bool get isClosed => isManualClosed || closedAt != null;

  /// 마감시간(applicationDeadline) 초과 여부
  bool get isTimeExpired =>
      applicationDeadline != null && DateTime.now().isAfter(applicationDeadline!);

  /// 인원 충족 여부 — 런타임에 설정되지 않으면 false
  bool get isFull => false;

  /// 확정 인원 — 구 아키텍처 제거됨, 항상 0
  int get currentCount => 0;

  /// 대기 인원 — 구 아키텍처 제거됨, 항상 0
  int get pendingCount => 0;

  /// 인원 정보 표시 — 구 아키텍처: "확정/필요" (지금은 "0/$requiredCount")
  String get countInfo => '0/$requiredCount';

  String get wageTypeLabel {
    switch (wageType) {
      case 'hourly': return '시급';
      case 'daily':  return '일급';
      case 'monthly': return '월급';
      default: return '급여';
    }
  }

  String get formattedWage =>
      '${wage.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원';

  /// WorkDetailModel(구 서브컬렉션 모델)에서 변환 — 마이그레이션용
  static WorkDetailData fromLegacyMap(Map<String, dynamic> map) =>
      WorkDetailData.fromMap(map);

  /// Timestamp 없이 순수 Map만 사용하므로 Timestamp 변환 불필요
  static List<WorkDetailData> listFromFirestore(dynamic raw) {
    if (raw == null) return [];
    return (raw as List).map((e) => WorkDetailData.fromMap(Map<String, dynamic>.from(e as Map))).toList();
  }

  static List<Map<String, dynamic>> listToFirestore(List<WorkDetailData> list) =>
      list.map((e) => e.toMap()).toList();
}
