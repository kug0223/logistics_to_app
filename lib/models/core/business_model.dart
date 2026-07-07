import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 사업장 근태 처리 규칙
///
/// 출퇴근 펀치 시점에 자동 반올림 적용 기준.
/// null인 사업장은 [AttendanceRules.defaults()]로 폴백.
class AttendanceRules {
  /// 출근 N분 이내 조기 도착 → 정시 처리 (기본 30분)
  final int earlyWindow;
  /// 조출 올림 단위 (기본 30분) — ceil 방향
  final int earlyArrivalUnit;
  /// 지각 유예 (기본 5분) — 이내면 정시 처리
  final int lateGrace;
  /// 지각 올림 단위 (기본 30분) — ceil 방향
  final int lateUnit;
  /// 퇴근 후 N분 이내 → 정시 퇴근 (기본 30분)
  final int lateWindow;
  /// 연장 내림 단위 (기본 10분) — floor 방향
  final int overtimeUnit;
  /// 조퇴 내림 단위 (기본 30분) — floor 방향
  final int earlyLeaveUnit;
  /// 규칙 마지막 변경 일시
  final DateTime? rulesUpdatedAt;
  /// 규칙 마지막 변경자 UID
  final String? rulesUpdatedBy;

  const AttendanceRules({
    this.earlyWindow      = 30,
    this.earlyArrivalUnit = 30,
    this.lateGrace        = 5,
    this.lateUnit         = 30,
    this.lateWindow       = 30,
    this.overtimeUnit     = 10,
    this.earlyLeaveUnit   = 30,
    this.rulesUpdatedAt,
    this.rulesUpdatedBy,
  });

  factory AttendanceRules.defaults() => const AttendanceRules();

  factory AttendanceRules.fromMap(Map<String, dynamic> map) {
    return AttendanceRules(
      earlyWindow:      (map['earlyWindow']      as num?)?.toInt().clamp(0,  120) ?? 30,
      earlyArrivalUnit: (map['earlyArrivalUnit'] as num?)?.toInt().clamp(5,  60)  ?? 30,
      lateGrace:        (map['lateGrace']        as num?)?.toInt().clamp(0,  30)  ?? 5,
      lateUnit:         (map['lateUnit']         as num?)?.toInt().clamp(5,  60)  ?? 30,
      lateWindow:       (map['lateWindow']       as num?)?.toInt().clamp(0,  60)  ?? 30,
      overtimeUnit:     (map['overtimeUnit']     as num?)?.toInt().clamp(5,  30)  ?? 10,
      earlyLeaveUnit:   (map['earlyLeaveUnit']   as num?)?.toInt().clamp(5,  60)  ?? 30,
      rulesUpdatedAt: map['rulesUpdatedAt'] != null
          ? (map['rulesUpdatedAt'] as Timestamp).toDate().toLocal()
          : null,
      rulesUpdatedBy: map['rulesUpdatedBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'earlyWindow':      earlyWindow,
    'earlyArrivalUnit': earlyArrivalUnit,
    'lateGrace':        lateGrace,
    'lateUnit':         lateUnit,
    'lateWindow':       lateWindow,
    'overtimeUnit':     overtimeUnit,
    'earlyLeaveUnit':   earlyLeaveUnit,
    if (rulesUpdatedAt != null)
      'rulesUpdatedAt': Timestamp.fromDate(rulesUpdatedAt!.toUtc()),
    if (rulesUpdatedBy != null) 'rulesUpdatedBy': rulesUpdatedBy,
  };

  AttendanceRules copyWith({
    int? earlyWindow,
    int? earlyArrivalUnit,
    int? lateGrace,
    int? lateUnit,
    int? lateWindow,
    int? overtimeUnit,
    int? earlyLeaveUnit,
    DateTime? rulesUpdatedAt,
    String? rulesUpdatedBy,
  }) {
    return AttendanceRules(
      earlyWindow:      earlyWindow      ?? this.earlyWindow,
      earlyArrivalUnit: earlyArrivalUnit ?? this.earlyArrivalUnit,
      lateGrace:        lateGrace        ?? this.lateGrace,
      lateUnit:         lateUnit         ?? this.lateUnit,
      lateWindow:       lateWindow       ?? this.lateWindow,
      overtimeUnit:     overtimeUnit     ?? this.overtimeUnit,
      earlyLeaveUnit:   earlyLeaveUnit   ?? this.earlyLeaveUnit,
      rulesUpdatedAt:   rulesUpdatedAt   ?? this.rulesUpdatedAt,
      rulesUpdatedBy:   rulesUpdatedBy   ?? this.rulesUpdatedBy,
    );
  }

  /// 지원자/근무자용 한 줄 요약 문구
  String get summary =>
      '출근 $earlyWindow분 이내 정시 · 지각 유예 $lateGrace분 · $lateUnit분 단위 처리';
}

class BusinessModel {
  final String id;
  final String businessNumber;  // 사업자등록번호
  final String name;             // 사업장명 (정식 명칭)
  
  final String category;         // 업종 카테고리
  final String subCategory;      // 세부 업종
  final String address;          // 주소
  final String? city;            // 시/구 (예: 오산시, 강남구)
  final String? district;        // 동/읍/면 (예: 세교동, 역삼동)
  final String? detailAddress;   // 세부주소
  final double? latitude;
  final double? longitude;
  final String ownerId;          // 사업장 최초 생성자 UID (알림 대상 등 기본값)
  final List<String> adminIds;   // 이 사업장을 관리할 수 있는 모든 관리자 UID 목록
  final String? phone;           // 연락처
  final String? description;     // 사업장 설명
  final bool isApproved;         // 슈퍼관리자 승인 여부
  final DateTime createdAt;
  final DateTime? updatedAt;
  // ── 출퇴근 설정 ──────────────────────────────────────────
  final String attendanceType;   // "gps" | "beacon" | "both" | "manual"
  final int gpsRadius;            // GPS 반경 (미터, 기본 100)

  // 비콘 설정 (attendanceType == 'beacon' || 'both' 일 때 사용)
  final String? beaconUUID;       // 비콘 UUID (ex: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0')
  final int? beaconMajor;         // Major 값 (0~65535)
  final int? beaconMinor;         // Minor 값 (0~65535)
  final int beaconRssiThreshold;  // 신호 강도 임계값 (dBm, 기본 -75 = 약 3~5m 이내)
  
  // ── 이미지 ──────────────────────────────────────────────────
  final String? mainImageUrl;          // 대표 이미지
  final List<String>? imageUrls;       // 사업장 사진들 (최대 5장)
  
  // ── 소개 ──────────────────────────────────────────────────
  final String? oneLineIntro;          // 한 줄 소개
  final String? detailedDescription;   // 상세 소개
  
  // ── 시설 및 환경 ────────────────────────────────────────────
  final bool parkingAvailable;         // 주차 가능 여부
  final List<String>? mealsProvided;       // 식사 제공 (조식/중식/석식/간식/없음)
  final String? uniformProvided;       // 복장 (유니폼제공/자유복/정장/없음)
  final List<String>? facilities;      // 편의시설 [휴게실, 사물함, 탈의실, 샤워실]
  
  // ── 교통편 ──────────────────────────────────────────────────
  final String? nearestStation;        // 가까운 역 (예: 강남역 3번 출구) — 레거시
  final int? walkingMinutes;           // 역에서 도보 시간 (분) — 레거시
  final String? busInfo;               // 버스 정보 (예: 146, 740) — 레거시
  final List<String>? transportImageUrls;  // 교통편 사진 (최대 5장)
  final String? transportDescription;     // 찾아오는 방법 상세설명
  
  // ── 기타 ──────────────────────────────────────────────────
  final String? precautions;           // 준비사항/주의사항
  final double? rating;                // 평점
  final int? reviewCount;              // 리뷰 수
  final String? companyName;

  // ── 근로계약서용 추가 정보 ────────────────────────────────

  /// 대표자 성명 (근로계약서 갑 서명란)
  final String? ownerName;

  /// 급여 지급일 (1~31, 예: 10 → 매월 10일 지급)
  final int? wagePaymentDay;

  // [분리 완료] sealBase64는 users/{uid} 문서에만 저장한다.
  // businesses 문서에는 더 이상 sealBase64를 저장하지 않는다.
  // 계약서 날인은 UserModel.sealBase64 (currentUser?.sealBase64)를 사용한다.

  /// 날인 방식: 'stamp'(도장 이미지 업로드) | 'signature'(직접 서명)
  final String sealType;

  /// 슈퍼관리자 또는 단독 관리자 탈퇴로 비활성화된 시각
  final DateTime? deactivatedAt;

  // ── 근태 처리 규칙 ────────────────────────────────────────
  /// null이면 AttendanceRules.defaults() 로 폴백
  final AttendanceRules? attendanceRules;

  bool get isDeactivated => deactivatedAt != null;

  BusinessModel({
    required this.id,
    required this.businessNumber,
    required this.name,
    required this.category,
    required this.subCategory,
    required this.address,
    this.detailAddress,
    this.city,
    this.district,
    this.latitude,
    this.longitude,
    required this.ownerId,
    List<String>? adminIds,
    this.phone,
    this.description,
    this.isApproved = false,
    required this.createdAt,
    this.updatedAt,
    this.attendanceType = 'gps',
    this.gpsRadius = 100,
    this.beaconUUID,
    this.beaconMajor,
    this.beaconMinor,
    this.beaconRssiThreshold = -75,
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
    this.transportImageUrls,
    this.transportDescription,
    // 기타
    this.precautions,
    this.rating,
    this.reviewCount,
    this.companyName,
    this.ownerName,
    this.wagePaymentDay,
    this.sealType = 'stamp',
    this.deactivatedAt,
    this.attendanceRules,
  }) : adminIds = (adminIds != null && adminIds.isNotEmpty)
           ? adminIds
           : [ownerId];

  // Firestore에서 데이터 가져올 때
  factory BusinessModel.fromMap(Map<String, dynamic> map, String id) {
    return BusinessModel(
      id: id,
      businessNumber: map['businessNumber'] ?? '',
      name: map['name'] ?? '',
      category: map['category'] ?? '',
      subCategory: map['subCategory'] ?? '',
      address: map['address'] ?? '',
      detailAddress: map['detailAddress'],
      city: map['city'],
      district: map['district'],
      latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,
      longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,
      ownerId: map['ownerId'] ?? '',
      adminIds: map['adminIds'] != null
          ? List<String>.from(map['adminIds'])
          : null, // null이면 생성자에서 [ownerId]로 초기화됨
      phone: map['phone'],
      description: map['description'],
      isApproved: map['isApproved'] ?? false,
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate().toLocal()
          : (throw ArgumentError('BusinessModel: createdAt 필드 누락 (id: $id)')),
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] as Timestamp).toDate().toLocal()
          : null,
      attendanceType: map['attendanceType'] ?? 'gps',
      gpsRadius: (map['gpsRadius'] as num?)?.toInt() ?? 100,
      beaconUUID: map['beaconUUID'],
      beaconMajor: (map['beaconMajor'] as num?)?.toInt(),
      beaconMinor: (map['beaconMinor'] as num?)?.toInt(),
      beaconRssiThreshold: (map['beaconRssiThreshold'] as num?)?.toInt() ?? -75,
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
      walkingMinutes: (map['walkingMinutes'] as num?)?.toInt(),
      busInfo: map['busInfo'],
      transportImageUrls: map['transportImageUrls'] != null
          ? List<String>.from(map['transportImageUrls'])
          : null,
      transportDescription: map['transportDescription'],
      // 기타
      precautions: map['precautions'],
      rating: (map['rating'] as num?)?.toDouble(),
      reviewCount: (map['reviewCount'] as num?)?.toInt(),
      companyName: map['companyName'],
      ownerName: map['ownerName'],
      wagePaymentDay: (map['wagePaymentDay'] as num?)?.toInt(),
      sealType: map['sealType'] as String? ?? 'stamp',
      deactivatedAt: map['deactivatedAt'] != null
          ? (map['deactivatedAt'] as Timestamp).toDate().toLocal()
          : null,
      attendanceRules: map['attendanceRules'] != null
          ? AttendanceRules.fromMap(
              Map<String, dynamic>.from(map['attendanceRules'] as Map))
          : null,
    );
  }
  factory BusinessModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) {
      throw ArgumentError('BusinessModel.fromFirestore: 문서 데이터 없음 (id: ${doc.id})');
    }
    return BusinessModel.fromMap(raw as Map<String, dynamic>, doc.id);
  }

  // [SCHEMA-09] 역직렬화 실패 격리 — 손상 문서 1건이 목록 전체 크래시 방지
  static BusinessModel? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return BusinessModel.fromFirestore(doc);
    } catch (e, st) {
      debugPrint('[BusinessModel] 역직렬화 실패 id=${doc.id}: $e\n$st');
      return null;
    }
  }

  // Firestore에 저장할 때
  Map<String, dynamic> toMap() {
    return {
      'businessNumber': businessNumber,
      'name': name,
      'category': category,
      'subCategory': subCategory,
      'address': address,
      'detailAddress': detailAddress,
      'city': city,
      'district': district,
      'latitude': latitude,
      'longitude': longitude,
      'ownerId': ownerId,
      'adminIds': adminIds,
      'phone': phone,
      'description': description,
      'isApproved': isApproved,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'attendanceType': attendanceType,
      'gpsRadius': gpsRadius,
      if (beaconUUID != null) 'beaconUUID': beaconUUID,
      if (beaconMajor != null) 'beaconMajor': beaconMajor,
      if (beaconMinor != null) 'beaconMinor': beaconMinor,
      'beaconRssiThreshold': beaconRssiThreshold,
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
      'transportImageUrls': transportImageUrls,
      'transportDescription': transportDescription,
      // 기타
      'precautions': precautions,
      'rating': rating,
      'reviewCount': reviewCount,
      'companyName': companyName,
      'ownerName': ownerName,
      'wagePaymentDay': wagePaymentDay,
      'sealType': sealType,
      'deactivatedAt': deactivatedAt != null ? Timestamp.fromDate(deactivatedAt!) : null,
      if (attendanceRules != null) 'attendanceRules': attendanceRules!.toMap(),
    };
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
    String? category,
    String? subCategory,
    String? address,
    String? detailAddress,
    String? city,
    String? district,
    double? latitude,
    double? longitude,
    String? ownerId,
    List<String>? adminIds,
    String? phone,
    String? description,
    bool? isApproved,
    DateTime? createdAt,
    DateTime? updatedAt,

    String? mainImageUrl,
    List<String>? imageUrls,
    String? oneLineIntro,
    String? detailedDescription,
    bool? parkingAvailable,
    List<String>? mealsProvided,
    String? uniformProvided,
    List<String>? facilities,
    String? nearestStation,
    int? walkingMinutes,
    String? busInfo,
    List<String>? transportImageUrls,
    String? transportDescription,
    String? precautions,
    double? rating,
    int? reviewCount,
    String? companyName,
    String? ownerName,
    int? wagePaymentDay,
    String? sealType,
    String? attendanceType,
    int? gpsRadius,
    String? beaconUUID,
    bool clearBeaconUUID = false,
    int? beaconMajor,
    int? beaconMinor,
    int? beaconRssiThreshold,
    DateTime? deactivatedAt,
    bool clearDeactivatedAt = false,
    AttendanceRules? attendanceRules,
  }) {
    return BusinessModel(
      id: id ?? this.id,
      businessNumber: businessNumber ?? this.businessNumber,
      name: name ?? this.name,
      category: category ?? this.category,
      subCategory: subCategory ?? this.subCategory,
      address: address ?? this.address,
      detailAddress: detailAddress ?? this.detailAddress,
      city: city ?? this.city,
      district: district ?? this.district,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      ownerId: ownerId ?? this.ownerId,
      adminIds: adminIds ?? this.adminIds,
      phone: phone ?? this.phone,
      description: description ?? this.description,
      isApproved: isApproved ?? this.isApproved,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
      transportImageUrls: transportImageUrls ?? this.transportImageUrls,
      transportDescription: transportDescription ?? this.transportDescription,
      precautions: precautions ?? this.precautions,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      companyName: companyName ?? this.companyName,
      ownerName: ownerName ?? this.ownerName,
      wagePaymentDay: wagePaymentDay ?? this.wagePaymentDay,
      sealType: sealType ?? this.sealType,
      attendanceType: attendanceType ?? this.attendanceType,
      gpsRadius: gpsRadius ?? this.gpsRadius,
      beaconUUID: clearBeaconUUID ? null : (beaconUUID ?? this.beaconUUID),
      beaconMajor: beaconMajor ?? this.beaconMajor,
      beaconMinor: beaconMinor ?? this.beaconMinor,
      beaconRssiThreshold: beaconRssiThreshold ?? this.beaconRssiThreshold,
      deactivatedAt: clearDeactivatedAt ? null : (deactivatedAt ?? this.deactivatedAt),
      attendanceRules: attendanceRules ?? this.attendanceRules,
    );
  }

  @override
  String toString() {
    return 'BusinessModel(id: $id, name: $name)';
  }
}