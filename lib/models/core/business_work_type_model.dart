import 'package:cloud_firestore/cloud_firestore.dart';

/// 사업장별 업무 유형 모델 (간소화 버전)
class BusinessWorkTypeModel {
  final String id;               // 문서 ID
  final String businessId;       // 소속 사업장 ID
  final String name;             // 업무 유형 이름 (예: 피킹, 패킹)
  final String icon;             // 이모지 아이콘 (예: 📦, 🚚)
  final String? color;           // 색상 코드 (예: #FF5733)
  final String? backgroundColor;
  final int displayOrder;        // 정렬 순서 (낮을수록 위)
  final bool isActive;           // 활성화 여부
  final DateTime createdAt;      // 생성 일시
  // ✅ 확장 필드
  final String? oneLineIntro;    // 한 줄 소개
  final String? description;     // 상세 설명
  final String? workEnvironment; // 근무 환경 (실내/실외/혼합)
  final String? requirements;    // 자격 요건 (자유 작성)
  final String? duties;          // 주요 업무 (자유 작성)
  final String? precautions;     // 주의사항
  final String? thumbnailUrl;    // 대표 이미지 URL
  final List<String>? images;    // 업무 사진 URL 목록

  BusinessWorkTypeModel({
    required this.id,
    required this.businessId,
    required this.name,
    required this.icon,
    this.color,
    this.backgroundColor,
    required this.displayOrder,
    this.isActive = true,
    required this.createdAt,
    // ✅ 확장 필드
    this.oneLineIntro,
    this.description,
    this.workEnvironment,
    this.requirements,
    this.duties,
    this.precautions,
    this.thumbnailUrl,
    this.images,
  });

  /// Firestore 문서 → 모델
  factory BusinessWorkTypeModel.fromMap(Map<String, dynamic> map, String id) {
    return BusinessWorkTypeModel(
      id: id,
      businessId: map['businessId'] ?? '',
      name: map['name'] ?? '',
      icon: map['icon'] ?? '📋',
      color: map['color'],
      backgroundColor: map['backgroundColor'],
      displayOrder: map['displayOrder'] ?? 0,
      isActive: map['isActive'] ?? true,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      // ✅ 확장 필드
      oneLineIntro: map['oneLineIntro'],
      description: map['description'],
      workEnvironment: map['workEnvironment'],
      requirements: map['requirements'],
      duties: map['duties'],
      precautions: map['precautions'],
      thumbnailUrl: map['thumbnailUrl'],
      images: map['images'] != null 
          ? List<String>.from(map['images']) 
          : null,
    );
  }

  /// Firestore DocumentSnapshot → 모델
  factory BusinessWorkTypeModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BusinessWorkTypeModel.fromMap(data, doc.id);
  }

  /// 모델 → Firestore 문서
  Map<String, dynamic> toMap() {
    return {
      'businessId': businessId,
      'name': name,
      'icon': icon,
      'color': color,
      'backgroundColor': backgroundColor,
      'displayOrder': displayOrder,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      // ✅ 확장 필드
      'oneLineIntro': oneLineIntro,
      'description': description,
      'workEnvironment': workEnvironment,
      'requirements': requirements,
      'duties': duties,
      'precautions': precautions,
      'thumbnailUrl': thumbnailUrl,
      'images': images,
    };
  }

  /// 복사본 생성 (일부 필드 변경)
  BusinessWorkTypeModel copyWith({
    String? id,
    String? businessId,
    String? name,
    String? icon,
    String? color,
    String? backgroundColor,
    int? displayOrder,
    bool? isActive,
    DateTime? createdAt,
    // ✅ 확장 필드
    String? oneLineIntro,
    String? description,
    String? workEnvironment,
    String? requirements,
    String? duties,
    String? precautions,
    String? thumbnailUrl,
    List<String>? images,
  }) {
    return BusinessWorkTypeModel(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      // ✅ 확장 필드
      oneLineIntro: oneLineIntro ?? this.oneLineIntro,
      description: description ?? this.description,
      workEnvironment: workEnvironment ?? this.workEnvironment,
      requirements: requirements ?? this.requirements,
      duties: duties ?? this.duties,
      precautions: precautions ?? this.precautions,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      images: images ?? this.images,
    );
  }
  @override
  String toString() {
    return 'BusinessWorkType(id: $id, name: $name, icon: $icon)';
  }
}