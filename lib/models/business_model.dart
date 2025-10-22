import 'package:cloud_firestore/cloud_firestore.dart';

class BusinessModel {
  final String id;
  final String businessNumber;  // ✅ 사업자등록번호 추가!
  final String name;             // 사업장명
  final String category;         // 업종 카테고리 (회사/알바 매장/기타)
  final String subCategory;      // 세부 업종
  final String address;          // 주소
  final double? latitude;        // ✅ nullable로 변경 (주소 검색 전에는 null)
  final double? longitude;       // ✅ nullable로 변경
  final String ownerId;          // 사업장 관리자 UID
  final String? phone;           // 연락처 (선택)
  final String? description;     // 사업장 설명 (선택)
  final bool isApproved;         // 슈퍼관리자 승인 여부
  final DateTime createdAt;
  final DateTime? updatedAt;

  BusinessModel({
    required this.id,
    required this.businessNumber,  // ✅ 필수 필드
    required this.name,
    required this.category,
    required this.subCategory,
    required this.address,
    this.latitude,                 // ✅ nullable
    this.longitude,                // ✅ nullable
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
      businessNumber: map['businessNumber'] ?? '',  // ✅ 추가
      name: map['name'] ?? '',
      category: map['category'] ?? '',
      subCategory: map['subCategory'] ?? '',
      address: map['address'] ?? '',
      latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,  // ✅ nullable 처리
      longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,  // ✅ nullable 처리
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
      'businessNumber': businessNumber,  // ✅ 추가
      'name': name,
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

  // copyWith 메서드
  BusinessModel copyWith({
    String? id,
    String? businessNumber,  // ✅ 추가
    String? name,
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
      businessNumber: businessNumber ?? this.businessNumber,  // ✅ 추가
      name: name ?? this.name,
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

  // 승인 상태 텍스트
  String get approvalStatusText {
    return isApproved ? '승인됨' : '승인 대기';
  }

  // 사업자등록번호 포맷팅 (000-00-00000)
  String get formattedBusinessNumber {
    if (businessNumber.length == 10) {
      return '${businessNumber.substring(0, 3)}-${businessNumber.substring(3, 5)}-${businessNumber.substring(5)}';
    }
    return businessNumber;
  }
}