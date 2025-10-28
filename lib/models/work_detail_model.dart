import 'package:cloud_firestore/cloud_firestore.dart';

/// TO의 업무 상세 정보 모델
/// 하나의 TO에 여러 업무유형(분류, 피킹 등)이 포함될 수 있음
class WorkDetailModel {
  final String id; // Firestore 문서 ID
  final String workType; // 업무 유형 (예: "분류", "피킹", "인덕션")
  final String workTypeIcon; // ✅ NEW: 업무 아이콘 (예: "📦")
  final String workTypeColor; // ✅ NEW: 업무 색상 (예: "#FF5733")
  final int wage; // 시급 또는 일급 (원)
  final int requiredCount; // 필요 인원
  final int currentCount; // 현재 확정된 인원
  final String startTime; // 시작 시간 (예: "09:00")
  final String endTime; // 종료 시간 (예: "18:00")
  final int order; // 표시 순서 (0부터 시작)
  final DateTime createdAt; // 생성 시각

  WorkDetailModel({
    required this.id,
    required this.workType,
    this.workTypeIcon = '📋', // ✅ NEW: 기본값
    this.workTypeColor = '#2196F3', // ✅ NEW: 기본값 (파란색)
    required this.wage,
    required this.requiredCount,
    this.currentCount = 0,
    required this.startTime,
    required this.endTime,
    required this.order,
    required this.createdAt,
  });

  /// Firestore 문서를 WorkDetailModel로 변환
  factory WorkDetailModel.fromMap(Map<String, dynamic> map, String id) {
    return WorkDetailModel(
      id: id,
      workType: map['workType'] ?? '',
      workTypeIcon: map['workTypeIcon'] ?? '📋', // ✅ NEW
      workTypeColor: map['workTypeColor'] ?? '#2196F3', // ✅ NEW
      wage: map['wage'] ?? 0,
      requiredCount: map['requiredCount'] ?? 0,
      currentCount: map['currentCount'] ?? 0,
      startTime: map['startTime'] ?? '09:00',
      endTime: map['endTime'] ?? '18:00',
      order: map['order'] ?? 0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// WorkDetailModel을 Firestore 문서로 변환
  Map<String, dynamic> toMap() {
    return {
      'workType': workType,
      'workTypeIcon': workTypeIcon, // ✅ NEW
      'workTypeColor': workTypeColor, // ✅ NEW
      'wage': wage,
      'requiredCount': requiredCount,
      'currentCount': currentCount,
      'startTime': startTime,
      'endTime': endTime,
      'order': order,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// 복사본 생성 (일부 필드만 변경)
  WorkDetailModel copyWith({
    String? id,
    String? workType,
    String? workTypeIcon, // ✅ NEW
    String? workTypeColor, // ✅ NEW
    int? wage,
    int? requiredCount,
    int? currentCount,
    String? startTime,
    String? endTime,
    int? order,
    DateTime? createdAt,
  }) {
    return WorkDetailModel(
      id: id ?? this.id,
      workType: workType ?? this.workType,
      workTypeIcon: workTypeIcon ?? this.workTypeIcon, // ✅ NEW
      workTypeColor: workTypeColor ?? this.workTypeColor, // ✅ NEW
      wage: wage ?? this.wage,
      requiredCount: requiredCount ?? this.requiredCount,
      currentCount: currentCount ?? this.currentCount,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
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

  /// 인원 정보 문자열 (예: "3/5명")
  String get countInfo => '$currentCount/$requiredCount명';

  @override
  String toString() {
    return 'WorkDetailModel(id: $id, workType: $workType, '
        'workTypeIcon: $workTypeIcon, workTypeColor: $workTypeColor, '
        'wage: $wage, requiredCount: $requiredCount, currentCount: $currentCount, '
        'timeRange: $timeRange, order: $order)';
  }
}