import 'package:cloud_firestore/cloud_firestore.dart';

/// 업무 유형 모델
class WorkTypeModel {
  final String? id;
  final String name;
  final String code;
  
  // UI 표시
  final String icon;
  final String color;
  
  // 상세 정보
  final String description;
  final List<String> requirements;
  final List<String> duties;
  
  // 근무 조건
  final String difficulty;        // "쉬움", "보통", "어려움"
  final String physicalDemand;    // "낮음", "보통", "높음"
  
  // 이미지/영상
  final List<String> images;
  final String? thumbnailUrl;
  final String? videoUrl;
  
  // 급여 정보
  final double? baseHourlyRate;
  
  // 상태
  final bool isActive;
  final int displayOrder;
  
  // 메타데이터
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;

  WorkTypeModel({
    this.id,
    required this.name,
    required this.code,
    this.icon = 'work',
    this.color = '#2196F3',
    this.description = '',
    this.requirements = const [],
    this.duties = const [],
    this.difficulty = '보통',
    this.physicalDemand = '보통',
    this.images = const [],
    this.thumbnailUrl,
    this.videoUrl,
    this.baseHourlyRate,
    this.isActive = true,
    this.displayOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });

  /// Firestore 문서를 WorkTypeModel로 변환
  factory WorkTypeModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return WorkTypeModel.fromMap(data, doc.id);
  }

  /// Map을 WorkTypeModel로 변환
  factory WorkTypeModel.fromMap(Map<String, dynamic> map, String id) {
    return WorkTypeModel(
      id: id,
      name: map['name'] ?? '',
      code: map['code'] ?? '',
      icon: map['icon'] ?? 'work',
      color: map['color'] ?? '#2196F3',
      description: map['description'] ?? '',
      requirements: List<String>.from(map['requirements'] ?? []),
      duties: List<String>.from(map['duties'] ?? []),
      difficulty: map['difficulty'] ?? '보통',
      physicalDemand: map['physicalDemand'] ?? '보통',
      images: List<String>.from(map['images'] ?? []),
      thumbnailUrl: map['thumbnailUrl'],
      videoUrl: map['videoUrl'],
      baseHourlyRate: map['baseHourlyRate']?.toDouble(),
      isActive: map['isActive'] ?? true,
      displayOrder: map['displayOrder'] ?? 0,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      updatedAt: (map['updatedAt'] as Timestamp).toDate(),
      createdBy: map['createdBy'] ?? '',
    );
  }

  /// WorkTypeModel을 Map으로 변환
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'code': code,
      'icon': icon,
      'color': color,
      'description': description,
      'requirements': requirements,
      'duties': duties,
      'difficulty': difficulty,
      'physicalDemand': physicalDemand,
      'images': images,
      'thumbnailUrl': thumbnailUrl,
      'videoUrl': videoUrl,
      'baseHourlyRate': baseHourlyRate,
      'isActive': isActive,
      'displayOrder': displayOrder,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdBy': createdBy,
    };
  }

  /// WorkTypeModel 복사 (일부 필드 변경)
  WorkTypeModel copyWith({
    String? id,
    String? name,
    String? code,
    String? icon,
    String? color,
    String? description,
    List<String>? requirements,
    List<String>? duties,
    String? difficulty,
    String? physicalDemand,
    List<String>? images,
    String? thumbnailUrl,
    String? videoUrl,
    double? baseHourlyRate,
    bool? isActive,
    int? displayOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return WorkTypeModel(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      description: description ?? this.description,
      requirements: requirements ?? this.requirements,
      duties: duties ?? this.duties,
      difficulty: difficulty ?? this.difficulty,
      physicalDemand: physicalDemand ?? this.physicalDemand,
      images: images ?? this.images,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      baseHourlyRate: baseHourlyRate ?? this.baseHourlyRate,
      isActive: isActive ?? this.isActive,
      displayOrder: displayOrder ?? this.displayOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  /// 난이도 아이콘
  String get difficultyIcon {
    switch (difficulty) {
      case '쉬움':
        return '😊';
      case '어려움':
        return '😰';
      default:
        return '😐';
    }
  }

  /// 체력 요구도 아이콘
  String get physicalDemandIcon {
    switch (physicalDemand) {
      case '낮음':
        return '💚';
      case '높음':
        return '💪';
      default:
        return '💛';
    }
  }

  /// 디버깅용 문자열
  @override
  String toString() {
    return 'WorkTypeModel(id: $id, name: $name, code: $code, difficulty: $difficulty)';
  }
}