import 'package:cloud_firestore/cloud_firestore.dart';

/// 사업장별 업무 유형 모델 (간소화 버전)
class BusinessWorkTypeModel {
  final String id;               // 문서 ID
  final String businessId;       // 소속 사업장 ID
  final String name;             // 업무 유형 이름 (예: 피킹, 패킹)
  final String icon;             // 이모지 아이콘 (예: 📦, 🚚)
  final String? color;           // 색상 코드 (예: #FF5733)
  final String? backgroundColor;
  final String wageType;         // ✅ NEW: 급여 타입 ('hourly', 'daily', 'monthly')
  final int displayOrder;        // 정렬 순서 (낮을수록 위)
  final bool isActive;           // 활성화 여부
  final DateTime createdAt;      // 생성 일시

  BusinessWorkTypeModel({
    required this.id,
    required this.businessId,
    required this.name,
    required this.icon,
    this.color,
    this.backgroundColor,
    this.wageType = 'hourly',     // ✅ NEW: 기본값 시급
    required this.displayOrder,
    this.isActive = true,
    required this.createdAt,
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
      wageType: map['wageType'] ?? 'hourly', // ✅ NEW
      displayOrder: map['displayOrder'] ?? 0,
      isActive: map['isActive'] ?? true,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
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
      'wageType': wageType,        // ✅ NEW
      'displayOrder': displayOrder,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
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
    String? wageType,              // ✅ NEW
    int? displayOrder,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return BusinessWorkTypeModel(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      wageType: wageType ?? this.wageType, // ✅ NEW
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// ✅ NEW: 급여 타입 라벨 반환
  String get wageTypeLabel {
    switch (wageType) {
      case 'hourly':
        return '시급';
      case 'daily':
        return '일급';
      case 'monthly':
        return '월급';
      default:
        return '시급';
    }
  }

  /// ✅ NEW: 금액 포맷팅 (천단위 콤마)
  String formatWage(int wage) {
    return '${wage.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )}원';
  }

  @override
  String toString() {
    return 'BusinessWorkType(id: $id, name: $name, icon: $icon, wageType: $wageType)';
  }
}