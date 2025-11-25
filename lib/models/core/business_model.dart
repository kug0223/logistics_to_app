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
  // ⭐ 출퇴근 설정 추가
  final String attendanceType;   // "gps" | "beacon" | "manual"
  final int gpsRadius;            // GPS 반경 (미터)
  
  // ═══════════════════════════════════════════════════════════
  // 📸 이미지
  // ═══════════════════════════════════════════════════════════
  final String? mainImageUrl;          // 대표 이미지
  final List<String>? imageUrls;       // 사업장 사진들 (최대 5장)
  
  // ═══════════════════════════════════════════════════════════
  // 💬 소개
  // ═══════════════════════════════════════════════════════════
  final String? oneLineIntro;          // 한 줄 소개
  final String? detailedDescription;   // 상세 소개
  
  // ═══════════════════════════════════════════════════════════
  // 🚗 시설 및 환경
  // ═══════════════════════════════════════════════════════════
  final bool parkingAvailable;         // 주차 가능 여부
  final List<String>? mealsProvided;       // 식사 제공 (조식/중식/석식/간식/없음)
  final String? uniformProvided;       // 복장 (유니폼제공/자유복/정장/없음)
  final List<String>? facilities;      // 편의시설 [휴게실, 사물함, 탈의실, 샤워실]
  
  // ═══════════════════════════════════════════════════════════
  // 🗺️ 교통편
  // ═══════════════════════════════════════════════════════════
  final String? nearestStation;        // 가까운 역 (예: 강남역 3번 출구)
  final int? walkingMinutes;           // 역에서 도보 시간 (분)
  final String? busInfo;               // 버스 정보 (예: 146, 740)
  
  // ═══════════════════════════════════════════════════════════
  // 📝 기타
  // ═══════════════════════════════════════════════════════════
  final String? precautions;           // 준비사항/주의사항
  final double? rating;                // 평점
  final int? reviewCount;              // 리뷰 수

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
    this.attendanceType = 'gps',
    this.gpsRadius = 100,  // ⭐ 기본값 100m
    // 이미지
    this.mainImageUrl,
    this.imageUrls,
    // 소개
    this.oneLineIntro,
    this.detailedDescription,
    // 시설 및 환경
    this.parkingAvailable = false,
    this.mealsProvided,
    this.uniformProvided,
    this.facilities,
    // 교통편
    this.nearestStation,
    this.walkingMinutes,
    this.busInfo,
    // 기타
    this.precautions,
    this.rating,
    this.reviewCount,
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
      attendanceType: map['attendanceType'] ?? 'gps',
      gpsRadius: map['gpsRadius'] ?? 100,
      // 이미지
      mainImageUrl: map['mainImageUrl'],
      imageUrls: map['imageUrls'] != null 
          ? List<String>.from(map['imageUrls']) 
          : null,
      // 소개
      oneLineIntro: map['oneLineIntro'],
      detailedDescription: map['detailedDescription'],
      // 시설 및 환경
      parkingAvailable: map['parkingAvailable'] ?? false,
      mealsProvided: map['mealsProvided'] != null 
      ? List<String>.from(map['mealsProvided']) 
      : null,
      uniformProvided: map['uniformProvided'],
      facilities: map['facilities'] != null 
          ? List<String>.from(map['facilities']) 
          : null,
      // 교통편
      nearestStation: map['nearestStation'],
      walkingMinutes: map['walkingMinutes'],
      busInfo: map['busInfo'],
      // 기타
      precautions: map['precautions'],
      rating: map['rating']?.toDouble(),
      reviewCount: map['reviewCount'],
    );
  }
  /// ⭐ Firestore DocumentSnapshot에서 변환 (추가!)
  factory BusinessModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BusinessModel.fromMap(data, doc.id);
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
      'attendanceType': attendanceType,
      'gpsRadius': gpsRadius,
      // 이미지
      'mainImageUrl': mainImageUrl,
      'imageUrls': imageUrls,
      // 소개
      'oneLineIntro': oneLineIntro,
      'detailedDescription': detailedDescription,
      // 시설 및 환경
      'parkingAvailable': parkingAvailable,
      'mealsProvided': mealsProvided,
      'uniformProvided': uniformProvided,
      'facilities': facilities,
      // 교통편
      'nearestStation': nearestStation,
      'walkingMinutes': walkingMinutes,
      'busInfo': busInfo,
      // 기타
      'precautions': precautions,
      'rating': rating,
      'reviewCount': reviewCount,
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
    // 새 파라미터 추가
    String? mainImageUrl,
    List<String>? imageUrls,
    String? oneLineIntro,
    String? detailedDescription,
    bool? parkingAvailable,
    String? mealProvided,
    String? uniformProvided,
    List<String>? facilities,
    String? nearestStation,
    int? walkingMinutes,
    String? busInfo,
    String? precautions,
    double? rating,
    int? reviewCount,
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
      // 새 필드 추가
      mainImageUrl: mainImageUrl ?? this.mainImageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      oneLineIntro: oneLineIntro ?? this.oneLineIntro,
      detailedDescription: detailedDescription ?? this.detailedDescription,
      parkingAvailable: parkingAvailable ?? this.parkingAvailable,
      mealsProvided: mealsProvided ?? this.mealsProvided,
      uniformProvided: uniformProvided ?? this.uniformProvided,
      facilities: facilities ?? this.facilities,
      nearestStation: nearestStation ?? this.nearestStation,
      walkingMinutes: walkingMinutes ?? this.walkingMinutes,
      busInfo: busInfo ?? this.busInfo,
      precautions: precautions ?? this.precautions,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
    );
  }

  @override
  String toString() {
    return 'BusinessModel(id: $id, name: $name, displayName: $displayName, '
        'useDisplayName: $useDisplayName, publicName: $publicName)';
  }
}