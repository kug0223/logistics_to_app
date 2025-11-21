// lib/models/core/user_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

// 사용자 권한 enum
enum UserRole {
  SUPER_ADMIN,    // 슈퍼관리자 (플랫폼 운영자)
  BUSINESS_ADMIN, // 사업장 관리자 (사장님)
  USER            // 일반 사용자 (지원자)
}

class UserModel {
  // ━━━ 기본 인증 정보 ━━━
  final String uid;
  final String username;
  final String email;              // ⚠️ 이건 systemEmail로 사용됨
  final String? userEmail;         // ⭐ 실제 이메일 추가
  final UserRole role;
  final String? businessId;  // 사업장 관리자의 경우 사업장 ID
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  
  // ━━━ 필수 개인 정보 ━━━
  final String name;
  final String? phone;
  final String? gender;                  // '남성' | '여성'
  final DateTime? birthDate;             // 생년월일
  final String? residentNumber;          // 주민등록번호 (⚠️ 실제론 암호화 필요!)
  final String? address;                 // 주소
  final String? detailAddress;           // 상세 주소
  
  // ━━━ 신분증 정보 ━━━
  final String? idCardImageUrl;         // 신분증 앞면 이미지 URL
  final DateTime? idCardVerifiedAt;     // 신분증 인증 시각
  final bool isIdVerified;              // 신분증 인증 여부
  
  // ━━━ 급여 통장 정보 ━━━
  final String? bankName;               // 은행명
  final String? accountNumber;          // 계좌번호 (⚠️ 실제론 암호화 필요!)
  final String? accountHolder;          // 예금주
  final String? bankbookImageUrl;
  
  // ━━━ 프로필 & 경력 ━━━
  final String? profileImageUrl;        // 프로필 사진 URL
  final String? bio;                    // 자기소개
  final List<String>? skills;           // 보유 스킬/자격증
  final List<String>? preferredWorkTypes; // 선호 업무 (예: ['피킹', '패킹'])
  
  // ━━━ 근무 이력 & 통계 ━━━
  final int totalWorkDays;              // 총 근무 일수
  final int totalWorkHours;             // 총 근무 시간
  final double averageRating;           // 평균 평점 (0.0~5.0)
  final int reviewCount;                // 받은 리뷰 수
  final int noShowCount;                // 무단 결근 횟수
  final int lateCount;                  // 지각 횟수
  
  // ━━━ 상태 정보 ━━━
  final bool isAvailable;               // 근무 가능 여부
  final String? unavailableReason;      // 불가 사유
  final DateTime? availableFrom;        // 근무 가능 시작일
  final bool isBlacklisted;             // 블랙리스트 여부
  final String? blacklistReason;        // 블랙리스트 사유

  UserModel({
    required this.uid,
    required this.username,
    required this.name,
    required this.email,           // systemEmail
    this.userEmail,                // ⭐ 추가
    this.phone,
    required this.role,
    this.businessId,
    this.createdAt,
    this.lastLoginAt,
    // 신규 필드
    this.gender,
    this.birthDate,
    this.residentNumber,
    this.address,
    this.detailAddress,
    this.idCardImageUrl,
    this.idCardVerifiedAt,
    this.isIdVerified = false,
    this.bankName,
    this.accountNumber,
    this.accountHolder,
    this.bankbookImageUrl,
    this.profileImageUrl,
    this.bio,
    this.skills,
    this.preferredWorkTypes,
    this.totalWorkDays = 0,
    this.totalWorkHours = 0,
    this.averageRating = 0.0,
    this.reviewCount = 0,
    this.noShowCount = 0,
    this.lateCount = 0,
    this.isAvailable = true,
    this.unavailableReason,
    this.availableFrom,
    this.isBlacklisted = false,
    this.blacklistReason,
  });

  // ━━━ 편의 메서드 ━━━
  
  /// 슈퍼관리자인지 확인
  bool get isSuperAdmin => role == UserRole.SUPER_ADMIN;
  
  /// 사업장 관리자인지 확인
  bool get isBusinessAdmin => role == UserRole.BUSINESS_ADMIN;
  
  /// 일반 사용자인지 확인
  bool get isUser => role == UserRole.USER;
  
  /// 관리자 권한이 있는지 (슈퍼 또는 사업장 관리자)
  bool get isAdmin => role == UserRole.SUPER_ADMIN || role == UserRole.BUSINESS_ADMIN;

  /// 역할 문자열
  String get roleString => _roleToString(role);

  /// 나이 계산 (생년월일 기준)
  int? get age {
    if (birthDate == null) return null;
    final now = DateTime.now();
    int calculatedAge = now.year - birthDate!.year;
    if (now.month < birthDate!.month ||
        (now.month == birthDate!.month && now.day < birthDate!.day)) {
      calculatedAge--;
    }
    return calculatedAge;
  }

  /// 신뢰도 점수 (0~100)
  int get trustScore {
    if (totalWorkDays == 0) return 0;
    
    // 기본 점수 60
    int score = 60;
    
    // 평균 평점 가산 (최대 20점)
    if (averageRating > 0) {
      score += (averageRating * 4).toInt(); // 5.0 = 20점
    }
    
    // 근무 일수 가산 (최대 15점)
    score += (totalWorkDays / 10).clamp(0, 15).toInt();
    
    // 무단결근 감점 (-5점/회)
    score -= noShowCount * 5;
    
    // 지각 감점 (-2점/회)
    score -= lateCount * 2;
    
    return score.clamp(0, 100);
  }

  // ━━━ Firestore 변환 ━━━

  /// Firestore에서 데이터 가져올 때
  factory UserModel.fromMap(Map<String, dynamic> map, String uid) {
    // 기존 isAdmin 필드가 있는 경우 호환성 유지
    UserRole role;
    if (map.containsKey('role')) {
      role = _roleFromString(map['role']);
    } else if (map['isAdmin'] == true) {
      role = UserRole.SUPER_ADMIN;
    } else {
      role = UserRole.USER;
    }

    return UserModel(
      uid: uid,
      username: map['username'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',           // systemEmail
      userEmail: map['userEmail'],         // ⭐ 추가
      phone: map['phone'],
      role: role,
      businessId: map['businessId'],
      createdAt: map['createdAt']?.toDate(),
      lastLoginAt: map['lastLoginAt']?.toDate(),
      // 신규 필드
      gender: map['gender'],
      birthDate: map['birthDate']?.toDate(),
      residentNumber: map['residentNumber'],
      address: map['address'],
      detailAddress: map['detailAddress'],
      idCardImageUrl: map['idCardImageUrl'],
      idCardVerifiedAt: map['idCardVerifiedAt']?.toDate(),
      isIdVerified: map['isIdVerified'] ?? false,
      bankName: map['bankName'],
      accountNumber: map['accountNumber'],
      accountHolder: map['accountHolder'],
      bankbookImageUrl: map['bankbookImageUrl'],
      profileImageUrl: map['profileImageUrl'],
      bio: map['bio'],
      skills: map['skills'] != null ? List<String>.from(map['skills']) : null,
      preferredWorkTypes: map['preferredWorkTypes'] != null 
          ? List<String>.from(map['preferredWorkTypes']) 
          : null,
      totalWorkDays: map['totalWorkDays'] ?? 0,
      totalWorkHours: map['totalWorkHours'] ?? 0,
      averageRating: (map['averageRating'] ?? 0.0).toDouble(),
      reviewCount: map['reviewCount'] ?? 0,
      noShowCount: map['noShowCount'] ?? 0,
      lateCount: map['lateCount'] ?? 0,
      isAvailable: map['isAvailable'] ?? true,
      unavailableReason: map['unavailableReason'],
      availableFrom: map['availableFrom']?.toDate(),
      isBlacklisted: map['isBlacklisted'] ?? false,
      blacklistReason: map['blacklistReason'],
    );
  }

  /// Firestore에 저장할 때
  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'name': name,
      'email': email,              // systemEmail
      'userEmail': userEmail,      // ⭐ 추가
      'phone': phone,
      'role': _roleToString(role),
      'businessId': businessId,
      'createdAt': createdAt,
      'lastLoginAt': lastLoginAt,
      // 신규 필드
      'gender': gender,
      'birthDate': birthDate != null ? Timestamp.fromDate(birthDate!) : null,
      'residentNumber': residentNumber, // ⚠️ 실제론 암호화 필요!
      'address': address,
      'detailAddress': detailAddress,
      'idCardImageUrl': idCardImageUrl,
      'idCardVerifiedAt': idCardVerifiedAt != null 
          ? Timestamp.fromDate(idCardVerifiedAt!) 
          : null,
      'isIdVerified': isIdVerified,
      'bankName': bankName,
      'accountNumber': accountNumber, // ⚠️ 실제론 암호화 필요!
      'accountHolder': accountHolder,
      'bankbookImageUrl': bankbookImageUrl, 
      'profileImageUrl': profileImageUrl,
      'bio': bio,
      'skills': skills,
      'preferredWorkTypes': preferredWorkTypes,
      'totalWorkDays': totalWorkDays,
      'totalWorkHours': totalWorkHours,
      'averageRating': averageRating,
      'reviewCount': reviewCount,
      'noShowCount': noShowCount,
      'lateCount': lateCount,
      'isAvailable': isAvailable,
      'unavailableReason': unavailableReason,
      'availableFrom': availableFrom != null 
          ? Timestamp.fromDate(availableFrom!) 
          : null,
      'isBlacklisted': isBlacklisted,
      'blacklistReason': blacklistReason,
    };
  }

  // ━━━ 내부 헬퍼 메서드 ━━━

  /// UserRole을 String으로 변환
  static String _roleToString(UserRole role) {
    switch (role) {
      case UserRole.SUPER_ADMIN:
        return 'SUPER_ADMIN';
      case UserRole.BUSINESS_ADMIN:
        return 'BUSINESS_ADMIN';
      case UserRole.USER:
        return 'USER';
    }
  }

  /// String을 UserRole로 변환
  static UserRole _roleFromString(String roleString) {
    switch (roleString) {
      case 'SUPER_ADMIN':
        return UserRole.SUPER_ADMIN;
      case 'BUSINESS_ADMIN':
        return UserRole.BUSINESS_ADMIN;
      case 'USER':
        return UserRole.USER;
      default:
        return UserRole.USER;
    }
  }

  /// copyWith 메서드 (사용자 정보 업데이트 시 편리)
  UserModel copyWith({
    String? uid,
    String? username,
    String? name,
    String? email,
    String? userEmail,             // ⭐ 추가
    String? phone,
    UserRole? role,
    String? businessId,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    String? gender,
    DateTime? birthDate,
    String? residentNumber,
    String? address,
    String? detailAddress,
    String? idCardImageUrl,
    DateTime? idCardVerifiedAt,
    bool? isIdVerified,
    String? bankName,
    String? accountNumber,
    String? accountHolder,
    String? bankbookImageUrl,
    String? profileImageUrl,
    String? bio,
    List<String>? skills,
    List<String>? preferredWorkTypes,
    int? totalWorkDays,
    int? totalWorkHours,
    double? averageRating,
    int? reviewCount,
    int? noShowCount,
    int? lateCount,
    bool? isAvailable,
    String? unavailableReason,
    DateTime? availableFrom,
    bool? isBlacklisted,
    String? blacklistReason,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      username: username ?? this.username,
      name: name ?? this.name,
      email: email ?? this.email,
      userEmail: userEmail ?? this.userEmail,  // ⭐ 추가
      phone: phone ?? this.phone,
      role: role ?? this.role,
      businessId: businessId ?? this.businessId,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      gender: gender ?? this.gender,
      birthDate: birthDate ?? this.birthDate,
      residentNumber: residentNumber ?? this.residentNumber,
      address: address ?? this.address,
      detailAddress: detailAddress ?? this.detailAddress,
      idCardImageUrl: idCardImageUrl ?? this.idCardImageUrl,
      idCardVerifiedAt: idCardVerifiedAt ?? this.idCardVerifiedAt,
      isIdVerified: isIdVerified ?? this.isIdVerified,
      bankName: bankName ?? this.bankName,
      accountNumber: accountNumber ?? this.accountNumber,
      accountHolder: accountHolder ?? this.accountHolder,
      bankbookImageUrl: bankbookImageUrl ?? this.bankbookImageUrl,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      bio: bio ?? this.bio,
      skills: skills ?? this.skills,
      preferredWorkTypes: preferredWorkTypes ?? this.preferredWorkTypes,
      totalWorkDays: totalWorkDays ?? this.totalWorkDays,
      totalWorkHours: totalWorkHours ?? this.totalWorkHours,
      averageRating: averageRating ?? this.averageRating,
      reviewCount: reviewCount ?? this.reviewCount,
      noShowCount: noShowCount ?? this.noShowCount,
      lateCount: lateCount ?? this.lateCount,
      isAvailable: isAvailable ?? this.isAvailable,
      unavailableReason: unavailableReason ?? this.unavailableReason,
      availableFrom: availableFrom ?? this.availableFrom,
      isBlacklisted: isBlacklisted ?? this.isBlacklisted,
      blacklistReason: blacklistReason ?? this.blacklistReason,
    );
  }
}