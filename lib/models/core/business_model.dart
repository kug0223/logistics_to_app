import 'package:cloud_firestore/cloud_firestore.dart';

class BusinessModel {
  final String id;
  final String businessNumber;  // 사업자등록번호
  final String name;             // 사업장명 (정식 명칭)
  
  // ✅ NEW: 공개 표시명
  final String? displayName;     // 공개용 표시명 (예: "주식회사 위워커")
  final bool useDisplayName;     // displayName 사용 여부
  
  final String category;         // 업종 카테고리
  final String subCategory;      // 세부 업종
  final String address;          // 주소
  final double? latitude;
  final double? longitude;
  final String ownerId;          // 사업장 관리자 UID
  final String? phone;           // 연락처
  final String? description;     // 사업장 설명
  final bool isApproved;         // 슈퍼관리자 승인 여부
  final DateTime createdAt;
  final DateTime? updatedAt;

  BusinessModel({
    required this.id,
    required this.businessNumber,
    required this.name,
    this.displayName,              // ✅ NEW
    this.useDisplayName = false,   // ✅ NEW (기본값: 사용 안함)
    required this.category,
    required this.subCategory,
    required this.address,
    this.latitude,
    this.longitude,
    required this.ownerId,
    this.phone,
    this.description,
    this.isApproved = false,
    required this.createdAt,
    this.updatedAt,
  });

  // Firestore에서 데이터 가져올 때
  factory BusinessModel.fromMap(Map<String, dynamic> map, String id) {
    return BusinessModel(
      id: id,
      businessNumber: map['businessNumber'] ?? '',
      name: map['name'] ?? '',
      displayName: map['displayName'],              // ✅ NEW
      useDisplayName: map['useDisplayName'] ?? false, // ✅ NEW
      category: map['category'] ?? '',
      subCategory: map['subCategory'] ?? '',
      address: map['address'] ?? '',
      latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,
      longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,
      ownerId: map['ownerId'] ?? '',
      phone: map['phone'],
      description: map['description'],
      isApproved: map['isApproved'] ?? false,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      updatedAt: map['updatedAt'] != null 
          ? (map['updatedAt'] as Timestamp).toDate() 
          : null,
    );
  }

  // Firestore에 저장할 때
  Map<String, dynamic> toMap() {
    return {
      'businessNumber': businessNumber,
      'name': name,
      'displayName': displayName,              // ✅ NEW
      'useDisplayName': useDisplayName,        // ✅ NEW
      'category': category,
      'subCategory': subCategory,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'ownerId': ownerId,
      'phone': phone,
      'description': description,
      'isApproved': isApproved,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  // ✅ NEW: TO 공고에 표시할 이름 반환
  String get publicName {
    if (useDisplayName && displayName != null && displayName!.isNotEmpty) {
      return displayName!;
    }
    return name;
  }

  // ✅ NEW: 전체 표시명 (displayName + name 조합)
  String get fullDisplayName {
    if (useDisplayName && displayName != null && displayName!.isNotEmpty) {
      return '$displayName - $name';
    }
    return name;
  }
  String get formattedBusinessNumber {
    if (businessNumber.length == 10) {
      return '${businessNumber.substring(0, 3)}-${businessNumber.substring(3, 5)}-${businessNumber.substring(5)}';
    }
    return businessNumber;
  }

  // copyWith 메서드
  BusinessModel copyWith({
    String? id,
    String? businessNumber,
    String? name,
    String? displayName,           // ✅ NEW
    bool? useDisplayName,          // ✅ NEW
    String? category,
    String? subCategory,
    String? address,
    double? latitude,
    double? longitude,
    String? ownerId,
    String? phone,
    String? description,
    bool? isApproved,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BusinessModel(
      id: id ?? this.id,
      businessNumber: businessNumber ?? this.businessNumber,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,           // ✅ NEW
      useDisplayName: useDisplayName ?? this.useDisplayName,  // ✅ NEW
      category: category ?? this.category,
      subCategory: subCategory ?? this.subCategory,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      ownerId: ownerId ?? this.ownerId,
      phone: phone ?? this.phone,
      description: description ?? this.description,
      isApproved: isApproved ?? this.isApproved,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'BusinessModel(id: $id, name: $name, displayName: $displayName, '
        'useDisplayName: $useDisplayName, publicName: $publicName)';
  }
}