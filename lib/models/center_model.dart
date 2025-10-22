import 'package:cloud_firestore/cloud_firestore.dart';

/// 센터(사업장) 모델
class CenterModel {
  final String? id;
  final String name;
  final String code;
  
  // 위치 정보
  final String address;
  final double? latitude;
  final double? longitude;
  
  // 상세 정보
  final String? description;
  final List<String> features;
  final String? notes;
  
  // 이미지
  final List<String> images;
  final String? thumbnailUrl;
  
  // 연락처
  final String? managerName;
  final String? managerPhone;
  
  // 상태
  final bool isActive;
  
  // 메타데이터
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;

  CenterModel({
    this.id,
    required this.name,
    required this.code,
    required this.address,
    this.latitude,
    this.longitude,
    this.description,
    this.features = const [],
    this.notes,
    this.images = const [],
    this.thumbnailUrl,
    this.managerName,
    this.managerPhone,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });

  /// Firestore 문서를 CenterModel로 변환
  factory CenterModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CenterModel.fromMap(data, doc.id);
  }

  /// Map을 CenterModel로 변환
  factory CenterModel.fromMap(Map<String, dynamic> map, String id) {
    return CenterModel(
      id: id,
      name: map['name'] ?? '',
      code: map['code'] ?? '',
      address: map['address'] ?? '',
      latitude: map['latitude']?.toDouble(),
      longitude: map['longitude']?.toDouble(),
      description: map['description'],
      features: List<String>.from(map['features'] ?? []),
      notes: map['notes'],
      images: List<String>.from(map['images'] ?? []),
      thumbnailUrl: map['thumbnailUrl'],
      managerName: map['managerName'],
      managerPhone: map['managerPhone'],
      isActive: map['isActive'] ?? true,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      updatedAt: (map['updatedAt'] as Timestamp).toDate(),
      createdBy: map['createdBy'] ?? '',
    );
  }

  /// CenterModel을 Map으로 변환
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'code': code,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'description': description,
      'features': features,
      'notes': notes,
      'images': images,
      'thumbnailUrl': thumbnailUrl,
      'managerName': managerName,
      'managerPhone': managerPhone,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdBy': createdBy,
    };
  }

  /// CenterModel 복사 (일부 필드 변경)
  CenterModel copyWith({
    String? id,
    String? name,
    String? code,
    String? address,
    double? latitude,
    double? longitude,
    String? description,
    List<String>? features,
    String? notes,
    List<String>? images,
    String? thumbnailUrl,
    String? managerName,
    String? managerPhone,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return CenterModel(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      description: description ?? this.description,
      features: features ?? this.features,
      notes: notes ?? this.notes,
      images: images ?? this.images,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      managerName: managerName ?? this.managerName,
      managerPhone: managerPhone ?? this.managerPhone,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  /// 디버깅용 문자열
  @override
  String toString() {
    return 'CenterModel(id: $id, name: $name, code: $code, address: $address)';
  }
}