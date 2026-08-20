import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../utils/encryption_helper.dart';
import '../../utils/trust_score_helper.dart';
import 'user_region.dart';

// 사용자 권한 enum
enum UserRole {
  SUPER_ADMIN,    // 슈퍼관리자 (플랫폼 운영자)
  BUSINESS_ADMIN, // 사업장 관리자 (사장님)
  USER            // 일반 사용자 (지원자)
}

class UserModel {
  // ── 기본 인증 정보 ──
  final String uid;
  final String username;
  final String email;              // systemEmail로 사용됨 (username@ALfit-system.com)
  final UserRole role;
  final String? businessId;             // 대표 사업장 ID (하위 호환용)
  final List<String> managedBusinessIds; // 관리하는 모든 사업장 ID 목록
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  
  // ── 필수 개인 정보 ──
  final String name;
  final String? phone;
  final String? gender;                  // '남성' | '여성'
  final DateTime? birthDate;             // 생년월일
  final String? residentNumber;          // 주민등록번호 (암호화 저장)
  final String? address;                 // 주소
  final String? detailAddress;           // 상세 주소

  // ── PASS 본인인증 정보 ──
  final String? ci;                     // PASS CI값 (암호화 저장, 내국인 전용)
  final DateTime? passVerifiedAt;       // PASS 인증 시각 (내국인 전용)
  final String? foreignIdNumber;        // 외국인등록번호 (암호화 저장, 외국인 전용)
  // 'active' | 'pending' | 'rejected' — 외국인은 가입 후 pending, 슈퍼관리자 승인 시 active
  final String accountStatus;
  // CF rejectForeignWorker가 저장하는 필드명('rejectionReason')과 반드시 일치해야 함
  final String? rejectionReason;

  // ── 신분증 정보 ──
  final String? idCardImageUrl;         // 신분증 앞면 이미지 URL (legacy — 신규 flow는 idCardImagePath 사용)
  final String? idCardImagePath;        // [BUG-ID-01] authoritative Storage path (신규 flow)
  final DateTime? idCardVerifiedAt;     // 신분증 인증 시각
  final bool isIdVerified;              // 신분증 인증 여부
  
  // ── 전화번호 시스템 ──
  /// PASS 인증 시 통신사에서 확인된 전화번호 (= 기존 phone 역할 승계)
  final String? authPhone;
  /// 'identity_verified' (PASS 본인인증) | 'otp_verified' (OTP만)
  final String? phoneVerificationLevel;
  /// 연락처 전화번호 — OTP 인증 후 callableVerifyAndUpdatePhone CF로만 갱신
  final String? contactPhone;

  // ── 급여 통장 정보 ──
  final String? bankName;               // 은행명
  final String? accountNumber;          // 계좌번호 (암호화 저장)
  final String? accountHolder;          // 예금주
  final String? bankbookImageUrl;
  final bool isBankbookVerified;       // 통장사본 검증 여부 (CF Admin SDK로만 설정) — legacy, bankVerificationStatus로 대체 예정
  final DateTime? bankbookVerifiedAt;  // 통장사본 검증 시각 — legacy
  /// 계좌 인증 상태: 'verified' | 'review_required' | 'mismatch' | null(미등록)
  final String? bankVerificationStatus;
  /// 통장사본 최초 업로드 시각 (callableMarkBankbookVerified가 기록)
  final DateTime? bankbookUploadedAt;

  // ── 프로필 & 경력 ──
  final String? profileImageUrl;        // 프로필 사진 URL
  final String? bio;                    // 자기소개
  final List<String>? skills;           // 보유 스킬/자격증
  final List<String>? preferredWorkTypes; // 선호 업무 (예: ['피킹', '패킹'])
  
  // ── 근무 이력 & 통계 ──
  final int totalWorkDays;              // 총 근무 일수
  final int totalWorkHours;             // 총 근무 시간
  final double averageRating;           // 평균 평점 (0.0~5.0)
  final int reviewCount;                // 받은 리뷰 수
  final int noShowCount;                // 무단 결근 횟수 (누적 전체)
  final int recentNoShowCount;          // 최근 90일 노쇼 횟수 (CF가 갱신, 없으면 noShowCount 폴백)
  final int lateCount;                  // 지각 횟수 (누적 전체)
  final Map<String, int> workTypeStats; // 업무 유형별 완료 횟수 (CF 누적, 나의 ALfit 표시용)
  final int recentLateCount;            // 최근 90일 지각 횟수 (CF가 갱신, 없으면 lateCount 폴백)
  // ── 상태 정보 ──
  final bool isAvailable;               // 근무 가능 여부
  final String? unavailableReason;      // 불가 사유
  final DateTime? availableFrom;        // 근무 가능 시작일
  final bool isBlacklisted;             // 블랙리스트 여부
  final String? blacklistReason;        // 블랙리스트 사유
  final String? businessNumber;         // 사업자등록번호 (관리자용)
  final String? businessName;           // 상호명 (관리자용)
  final String? businessLicenseImageUrl; // 사업자등록증 이미지
  final String? ceoName;                 // 대표자명
  // ── 신뢰도 시스템 ──
  final int? storedTrustScore;           // 저장된 신뢰도 점수
  final double rehireRate;               // 재고용 희망률 (0.0~1.0)
  final List<String> badges;             // 배지 ID 목록
  final DateTime? lastRestartAt;         // 마지막 재시작 프로그램 일시
  final String? signatureBase64;         // 사전 등록 서명 이미지 (base64)
  final String? sealBase64;             // 사업주 날인 이미지 (base64, 전역)
  final String sealType;               // 날인 방식: 'stamp' | 'signature'
  final List<String> subAdminBusinessIds; // 하위 관리자로 참여 중인 사업장 ID 목록 (복수 허용)
  final DateTime? restrictedUntil;       // 제재 만료 시각 (최근 90일 3회 이상 노쇼 시 1일 제재)
  final Map<String, bool> notifPrefs;    // 알림 종류별 수신 설정 (기본 모두 true)
  final List<String> favoriteToIds;      // 즐겨찾기 TO ID 목록
  final int? maxActiveTOs;               // 슈퍼관리자가 설정한 이 관리자의 공고 최대 등록 수 (null이면 전역 기본값)

  // ── 지역 정보 (추천 기능용) ──
  /// 집 주소 기반 지역 (address 파싱 — bootstrap 시 자동 생성)
  final UserRegion? homeRegion;
  /// 선호 근무 지역 목록 (실제 지원/근무로만 추가됨)
  final List<UserRegion> preferredJobRegions;
  /// 마지막으로 선택한 탐색 지역 (일자리 탭 필터용)
  final UserRegion? lastSelectedJobRegion;

  // 알림 카테고리 키 상수
  static const String notifWorkReminder    = 'workReminder';
  static const String notifApplicationUpdate = 'applicationUpdate';
  static const String notifReviewAlert     = 'reviewAlert';
  static const String notifContractAlert   = 'contractAlert';
  static const String notifWageAlert       = 'wageAlert';

  static const Map<String, bool> defaultNotifPrefs = {
    'workReminder':      true,
    'applicationUpdate': true,
    'reviewAlert':       true,
    'contractAlert':     true,
    'wageAlert':         true,
  };

  UserModel({
    required this.uid,
    required this.username,
    required this.name,
    required this.email,           // systemEmail
    this.phone,
    required this.role,
    this.businessId,
    List<String>? managedBusinessIds,
    this.createdAt,
    this.lastLoginAt,
    // PASS 본인인증 필드
    this.ci,
    this.passVerifiedAt,
    this.foreignIdNumber,
    this.accountStatus = 'active',
    this.rejectionReason,
    // 전화번호 시스템
    this.authPhone,
    this.phoneVerificationLevel,
    this.contactPhone,
    // 신규 필드
    this.gender,
    this.birthDate,
    this.residentNumber,
    this.address,
    this.detailAddress,
    this.idCardImageUrl,
    this.idCardImagePath,
    this.idCardVerifiedAt,
    this.isIdVerified = false,
    this.bankName,
    this.accountNumber,
    this.accountHolder,
    this.bankbookImageUrl,
    this.isBankbookVerified = false,
    this.bankbookVerifiedAt,
    this.bankVerificationStatus,
    this.bankbookUploadedAt,
    this.profileImageUrl,
    this.bio,
    this.skills,
    this.preferredWorkTypes,
    this.totalWorkDays = 0,
    this.totalWorkHours = 0,
    this.averageRating = 0.0,
    this.reviewCount = 0,
    this.noShowCount = 0,
    this.recentNoShowCount = 0,
    this.lateCount = 0,
    this.recentLateCount = 0,
    this.workTypeStats = const {},
    this.isAvailable = true,
    this.unavailableReason,
    this.availableFrom,
    this.isBlacklisted = false,
    this.blacklistReason,
    this.businessNumber,
    this.businessName,
    this.businessLicenseImageUrl,
    this.ceoName,
    // ── 신뢰도 시스템 ──
    this.storedTrustScore,
    this.rehireRate = 0.0,
    this.badges = const [],
    this.lastRestartAt,
    this.signatureBase64,
    this.sealBase64,
    this.sealType = 'stamp',
    List<String>? subAdminBusinessIds,
    this.restrictedUntil,
    Map<String, bool>? notifPrefs,
    List<String>? favoriteToIds,
    this.maxActiveTOs,
    // ── 지역 정보 ──
    this.homeRegion,
    List<UserRegion>? preferredJobRegions,
    this.lastSelectedJobRegion,
  }) : notifPrefs = notifPrefs ?? defaultNotifPrefs,
       favoriteToIds = favoriteToIds ?? const [],
       managedBusinessIds = managedBusinessIds ??
           (businessId != null ? [businessId] : const []),
       subAdminBusinessIds = subAdminBusinessIds ?? const [],
       preferredJobRegions = preferredJobRegions ?? const [];


  // ── 편의 메서드 ──
  
  /// 슈퍼관리자인지 확인
  bool get isSuperAdmin => role == UserRole.SUPER_ADMIN;
  
  /// 사업장 관리자인지 확인
  bool get isBusinessAdmin => role == UserRole.BUSINESS_ADMIN;
  
  /// 일반 사용자인지 확인
  bool get isUser => role == UserRole.USER;
  
  /// 하위 관리자인지 (근무자이면서 특정 사업장 관리 권한 보유)
  bool get isSubAdmin => role == UserRole.USER && subAdminBusinessIds.isNotEmpty;

  /// 특정 사업장의 하위 관리자인지
  bool isSubAdminOf(String businessId) => subAdminBusinessIds.contains(businessId);

  /// 외국인 여부
  bool get isForeign => foreignIdNumber != null;

  // ── 전화번호 getter ──

  /// 실제 연락처 — OTP 인증 contactPhone 우선, 없으면 PASS 인증 authPhone, 없으면 legacy phone
  String? get effectivePhone => contactPhone ?? authPhone ?? phone;

  /// PASS 인증으로 확인된 전화번호 — authPhone 우선, 없으면 legacy phone
  String? get effectiveAuthPhone => authPhone ?? phone;

  /// PASS 인증(본인확인)으로 전화번호가 검증되었는지
  bool get isPhoneIdentityVerified => phoneVerificationLevel == 'identity_verified';

  /// PASS recovery 필요 여부 (내국인 활성 계정 + passVerifiedAt 없음)
  /// Restricted State: 공고 조회/홈은 허용, 지원 생성은 서버 gate로 차단
  bool get needsPassAuthRecovery =>
      role == UserRole.USER &&
      accountStatus == 'active' &&
      !isForeign &&
      passVerifiedAt == null;

  /// PASS 인증 완료 여부 (내국인)
  /// SUPER_ADMIN은 시스템 계정이므로 항상 true
  /// [FIX] ci(암호화 원문)는 CF가 저장하지 않음 — ciHash(해시)만 저장.
  ///   passVerifiedAt만 체크하도록 수정 (finalizeRegistration/finalizePassReauth CF가 저장)
  bool get isPassVerified => isSuperAdmin || passVerifiedAt != null;

  /// 신분증 서류 등록 여부.
  /// 신규 flow(idCardImagePath)와 legacy(idCardImageUrl) 양쪽을 모두 허용한다.
  /// CF(callableApplyToTO 등)도 동일한 OR 조건을 사용한다.
  bool get hasIdDocument =>
      (idCardImagePath != null && idCardImagePath!.isNotEmpty) ||
      (idCardImageUrl != null && idCardImageUrl!.isNotEmpty);

  /// 가입 승인 대기 중 (외국인)
  bool get isPending => accountStatus == 'pending';

  /// 가입 거절됨 (외국인)
  bool get isRejected => accountStatus == 'rejected';

  /// 현재 제재 중인지 (noShow 페널티)
  bool get isRestricted =>
      restrictedUntil != null && restrictedUntil!.isAfter(DateTime.now());

  /// 관리자 권한이 있는지 (슈퍼 또는 사업장 관리자 또는 하위 관리자)
  // [주의] SubAdmin(role==USER, subAdminOf!=null)도 포함한다.
  // Firestore isAdmin() 함수는 SubAdmin을 포함하지 않으므로 규칙과 동일 기준이 아님.
  // 순수 BUSINESS_ADMIN 여부가 필요하면 isBusinessAdmin을 사용하라.
  bool get isAdmin => role == UserRole.SUPER_ADMIN || role == UserRole.BUSINESS_ADMIN || isSubAdmin;

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

  /// 신뢰도 점수 (0~100).
  ///
  /// 저장된 값([storedTrustScore]) 우선.
  /// 없으면 [TrustScoreHelper.calculate]로 폴백 — 단일 공식 원칙.
  int get trustScore {
    if (storedTrustScore != null) return storedTrustScore!;
    return TrustScoreHelper.calculate(this);
  }
  
  /// 신뢰도 등급
  String get trustGrade {
    final s = trustScore;
    if (s >= 90) return '최우수';
    if (s >= 70) return '우수';
    if (s >= 50) return '보통';
    if (s >= 30) return '주의';
    return '경고';
  }
  
  /// 신뢰도 등급 이모지
  String get trustGradeEmoji {
    final s = trustScore;
    if (s >= 90) return '🌟';
    if (s >= 70) return '✅';
    if (s >= 50) return '😐';
    if (s >= 30) return '⚠️';
    return '🚨';
  }

  // ── Firestore 변환 ──

  static UserModel? tryFromMap(Map<String, dynamic> map, String uid) {
    try {
      return UserModel.fromMap(map, uid);
    } catch (e, st) {
      debugPrint('[UserModel] tryFromMap 실패 uid=$uid: $e\n$st');
      return null;
    }
  }

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
      phone: map['phone'],
      role: role,
      businessId: map['businessId'],
      managedBusinessIds: map['managedBusinessIds'] != null
          ? List<String>.from(map['managedBusinessIds'])
          : null,
      createdAt: _parseDateTime(map['createdAt']),
      lastLoginAt: _parseDateTime(map['lastLoginAt']),
      // PASS 본인인증 필드
      ci: EncryptionHelper.decrypt(map['ci']),
      passVerifiedAt: _parseDateTime(map['passVerifiedAt']),
      foreignIdNumber: EncryptionHelper.decrypt(map['foreignIdNumber']),
      accountStatus: map['accountStatus'] ?? 'active',
      rejectionReason: map['rejectionReason'] as String?,
      // 전화번호 시스템
      authPhone: map['authPhone'] as String?,
      // MIGRATION-TEMP: phoneVerificationLevel 없는 기존 사용자 추론
      // passVerifiedAt이 있으면 PASS 본인인증 완료 → identity_verified
      // 없으면 OTP만 또는 알 수 없음 → otp_verified
      // migration 완료 후 fallback 제거 (null 허용)
      phoneVerificationLevel: map['phoneVerificationLevel'] as String?
          ?? (map['passVerifiedAt'] != null ? 'identity_verified' : 'otp_verified'),
      contactPhone: map['contactPhone'] as String?,
      // 신규 필드
      gender: map['gender'],
      birthDate: _parseDateTime(map['birthDate']),
      residentNumber: EncryptionHelper.decrypt(map['residentNumber']),
      address: map['address'],
      detailAddress: map['detailAddress'],
      idCardImageUrl: map['idCardImageUrl'],
      idCardImagePath: map['idCardImagePath'],
      idCardVerifiedAt: _parseDateTime(map['idCardVerifiedAt']),
      isIdVerified: map['isIdVerified'] ?? false,
      bankName: map['bankName'],
      accountNumber: EncryptionHelper.decrypt(map['accountNumber']),
      accountHolder: map['accountHolder'],
      bankbookImageUrl: map['bankbookImageUrl'],
      isBankbookVerified: map['isBankbookVerified'] ?? false,
      bankbookVerifiedAt: _parseDateTime(map['bankbookVerifiedAt']),
      bankVerificationStatus: map['bankVerificationStatus'] as String?,
      bankbookUploadedAt: _parseDateTime(map['bankbookUploadedAt']),
      profileImageUrl: map['profileImageUrl'],
      bio: map['bio'],
      skills: map['skills'] != null ? List<String>.from(map['skills']) : null,
      preferredWorkTypes: map['preferredWorkTypes'] != null 
          ? List<String>.from(map['preferredWorkTypes']) 
          : null,
      totalWorkDays: (map['totalWorkDays'] as num?)?.toInt() ?? 0,
      totalWorkHours: (map['totalWorkHours'] as num?)?.toInt() ?? 0,
      averageRating: (map['averageRating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (map['reviewCount'] as num?)?.toInt() ?? 0,
      noShowCount: (map['noShowCount'] as num?)?.toInt() ?? 0,
      recentNoShowCount: (map['recentNoShowCount'] as num?)?.toInt() ??
          (map['noShowCount'] as num?)?.toInt() ?? 0,
      lateCount: (map['lateCount'] as num?)?.toInt() ?? 0,
      workTypeStats: (map['workTypeStats'] as Map<Object?, Object?>?)
              ?.map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0)) ??
          const {},
      recentLateCount: (map['recentLateCount'] as num?)?.toInt() ??
          (map['lateCount'] as num?)?.toInt() ?? 0,
      isAvailable: map['isAvailable'] ?? true,
      unavailableReason: map['unavailableReason'],
      availableFrom: _parseDateTime(map['availableFrom']),
      isBlacklisted: map['isBlacklisted'] ?? false,
      blacklistReason: map['blacklistReason'],
      businessNumber: map['businessNumber'],
      businessName: map['businessName'],
      businessLicenseImageUrl: map['businessLicenseImageUrl'],
      ceoName: map['ceoName'],
      // ── 신뢰도 시스템 ──
      storedTrustScore: (map['trustScore'] as num?)?.toInt(),
      rehireRate: (map['rehireRate'] as num?)?.toDouble() ?? 0.0,
      badges: map['badges'] != null ? List<String>.from(map['badges']) : [],
      lastRestartAt: _parseDateTime(map['lastRestartAt']),
      signatureBase64: map['signatureBase64'],
      sealBase64: map['sealBase64'],
      sealType: map['sealType'] as String? ?? 'stamp',
      subAdminBusinessIds: _parseSubAdminBusinessIds(map),
      restrictedUntil: _parseDateTime(map['restrictedUntil']),
      notifPrefs: map['notifPrefs'] != null
          ? Map<String, bool>.from(
              (map['notifPrefs'] as Map).map((k, v) => MapEntry(k.toString(), v == true)))
          : null,
      favoriteToIds: map['favoriteToIds'] != null
          ? List<String>.from(map['favoriteToIds'])
          : null,
      maxActiveTOs: (map['maxActiveTOs'] as num?)?.toInt(),
      // ── 지역 정보 ──
      homeRegion: UserRegion.tryFromMap(map['homeRegion']),
      preferredJobRegions: (map['preferredJobRegions'] as List? ?? [])
          .map(UserRegion.tryFromMap)
          .whereType<UserRegion>()
          .toList(),
      lastSelectedJobRegion: UserRegion.tryFromMap(map['lastSelectedJobRegion']),
    );
  }

  /// Firestore에 저장할 때
  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'name': name,
      'email': email,              // systemEmail
      'phone': phone,
      'role': _roleToString(role),
      'businessId': businessId,
      'managedBusinessIds': managedBusinessIds,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'lastLoginAt': lastLoginAt != null ? Timestamp.fromDate(lastLoginAt!) : null,
      // 전화번호 시스템
      'authPhone': authPhone,
      'phoneVerificationLevel': phoneVerificationLevel,
      'contactPhone': contactPhone,
      // 신규 필드
      'gender': gender,
      'birthDate': birthDate != null ? Timestamp.fromDate(birthDate!) : null,
      'residentNumber': EncryptionHelper.encrypt(residentNumber),
      'address': address,
      'detailAddress': detailAddress,
      'ci': EncryptionHelper.encrypt(ci),
      'passVerifiedAt': passVerifiedAt != null ? Timestamp.fromDate(passVerifiedAt!) : null,
      'foreignIdNumber': EncryptionHelper.encrypt(foreignIdNumber),
      'accountStatus': accountStatus,
      'rejectionReason': rejectionReason,
      'idCardImageUrl': idCardImageUrl,
      'idCardImagePath': idCardImagePath,
      'idCardVerifiedAt': idCardVerifiedAt != null
          ? Timestamp.fromDate(idCardVerifiedAt!)
          : null,
      'isIdVerified': isIdVerified,
      'bankName': bankName,
      'accountNumber': EncryptionHelper.encrypt(accountNumber),
      'accountHolder': accountHolder,
      'bankbookImageUrl': bankbookImageUrl,
      'isBankbookVerified': isBankbookVerified,
      'bankbookVerifiedAt': bankbookVerifiedAt != null
          ? Timestamp.fromDate(bankbookVerifiedAt!)
          : null,
      'bankVerificationStatus': bankVerificationStatus,
      'bankbookUploadedAt': bankbookUploadedAt != null
          ? Timestamp.fromDate(bankbookUploadedAt!)
          : null,
      'profileImageUrl': profileImageUrl,
      'bio': bio,
      'skills': skills,
      'preferredWorkTypes': preferredWorkTypes,
      'totalWorkDays': totalWorkDays,
      'totalWorkHours': totalWorkHours,
      'averageRating': averageRating,
      'reviewCount': reviewCount,
      'noShowCount': noShowCount,
      'recentNoShowCount': recentNoShowCount,
      'lateCount': lateCount,
      'recentLateCount': recentLateCount,
      'workTypeStats': workTypeStats,
      'isAvailable': isAvailable,
      'unavailableReason': unavailableReason,
      'availableFrom': availableFrom != null 
          ? Timestamp.fromDate(availableFrom!) 
          : null,
      'isBlacklisted': isBlacklisted,
      'blacklistReason': blacklistReason,
      'businessNumber': businessNumber,
      'businessName': businessName,
      'businessLicenseImageUrl': businessLicenseImageUrl,
      'ceoName': ceoName,
      // ── 신뢰도 시스템 ──
      'trustScore': storedTrustScore,
      'rehireRate': rehireRate,
      'badges': badges,
      'lastRestartAt': lastRestartAt != null
          ? Timestamp.fromDate(lastRestartAt!)
          : null,
      'signatureBase64': signatureBase64,
      'sealBase64': sealBase64,
      'sealType': sealType,
      'subAdminBusinessIds': subAdminBusinessIds,
      'restrictedUntil': restrictedUntil != null
          ? Timestamp.fromDate(restrictedUntil!)
          : null,
      'notifPrefs': notifPrefs,
      'favoriteToIds': favoriteToIds,
      'maxActiveTOs': maxActiveTOs,
      // ── 지역 정보 ──
      if (homeRegion != null) 'homeRegion': homeRegion!.toMap(),
      'preferredJobRegions': preferredJobRegions.map((r) => r.toMap()).toList(),
      if (lastSelectedJobRegion != null)
        'lastSelectedJobRegion': lastSelectedJobRegion!.toMap(),
    };
  }

  // ── 내부 헬퍼 메서드 ──

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
    String? phone,
    UserRole? role,
    String? ci,
    DateTime? passVerifiedAt,
    String? foreignIdNumber,
    String? accountStatus,
    String? rejectionReason,
    String? authPhone,
    String? phoneVerificationLevel,
    String? contactPhone,
    String? businessId,
    List<String>? managedBusinessIds,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    String? gender,
    DateTime? birthDate,
    String? residentNumber,
    String? address,
    String? detailAddress,
    String? idCardImageUrl,
    String? idCardImagePath,
    DateTime? idCardVerifiedAt,
    bool? isIdVerified,
    String? bankName,
    String? accountNumber,
    String? accountHolder,
    String? bankbookImageUrl,
    bool? isBankbookVerified,
    DateTime? bankbookVerifiedAt,
    String? bankVerificationStatus,
    DateTime? bankbookUploadedAt,
    String? profileImageUrl,
    String? bio,
    List<String>? skills,
    List<String>? preferredWorkTypes,
    int? totalWorkDays,
    int? totalWorkHours,
    double? averageRating,
    int? reviewCount,
    int? noShowCount,
    int? recentNoShowCount,
    int? lateCount,
    int? recentLateCount,
    Map<String, int>? workTypeStats,
    bool? isAvailable,
    String? unavailableReason,
    DateTime? availableFrom,
    bool? isBlacklisted,
    String? blacklistReason,
    String? businessNumber,
    String? businessName,
    String? businessLicenseImageUrl,
    String? ceoName,
    // ── 신뢰도 시스템 ──
    int? storedTrustScore,
    double? rehireRate,
    List<String>? badges,
    DateTime? lastRestartAt,
    String? signatureBase64,
    bool clearSignature = false,
    String? sealBase64,
    bool clearSeal = false,
    String? sealType,
    List<String>? subAdminBusinessIds,
    DateTime? restrictedUntil,
    bool clearRestriction = false,
    Map<String, bool>? notifPrefs,
    List<String>? favoriteToIds,
    int? maxActiveTOs,
    bool clearMaxActiveTOs = false,
    // ── 지역 정보 ──
    UserRegion? homeRegion,
    bool clearHomeRegion = false,
    List<UserRegion>? preferredJobRegions,
    UserRegion? lastSelectedJobRegion,
    bool clearLastSelectedJobRegion = false,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      username: username ?? this.username,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      ci: ci ?? this.ci,
      passVerifiedAt: passVerifiedAt ?? this.passVerifiedAt,
      foreignIdNumber: foreignIdNumber ?? this.foreignIdNumber,
      accountStatus: accountStatus ?? this.accountStatus,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      authPhone: authPhone ?? this.authPhone,
      phoneVerificationLevel: phoneVerificationLevel ?? this.phoneVerificationLevel,
      contactPhone: contactPhone ?? this.contactPhone,
      businessId: businessId ?? this.businessId,
      managedBusinessIds: managedBusinessIds ?? this.managedBusinessIds,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      gender: gender ?? this.gender,
      birthDate: birthDate ?? this.birthDate,
      residentNumber: residentNumber ?? this.residentNumber,
      address: address ?? this.address,
      detailAddress: detailAddress ?? this.detailAddress,
      idCardImageUrl: idCardImageUrl ?? this.idCardImageUrl,
      idCardImagePath: idCardImagePath ?? this.idCardImagePath,
      idCardVerifiedAt: idCardVerifiedAt ?? this.idCardVerifiedAt,
      isIdVerified: isIdVerified ?? this.isIdVerified,
      bankName: bankName ?? this.bankName,
      accountNumber: accountNumber ?? this.accountNumber,
      accountHolder: accountHolder ?? this.accountHolder,
      bankbookImageUrl: bankbookImageUrl ?? this.bankbookImageUrl,
      isBankbookVerified: isBankbookVerified ?? this.isBankbookVerified,
      bankbookVerifiedAt: bankbookVerifiedAt ?? this.bankbookVerifiedAt,
      bankVerificationStatus: bankVerificationStatus ?? this.bankVerificationStatus,
      bankbookUploadedAt: bankbookUploadedAt ?? this.bankbookUploadedAt,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      bio: bio ?? this.bio,
      skills: skills ?? this.skills,
      preferredWorkTypes: preferredWorkTypes ?? this.preferredWorkTypes,
      totalWorkDays: totalWorkDays ?? this.totalWorkDays,
      totalWorkHours: totalWorkHours ?? this.totalWorkHours,
      averageRating: averageRating ?? this.averageRating,
      reviewCount: reviewCount ?? this.reviewCount,
      noShowCount: noShowCount ?? this.noShowCount,
      recentNoShowCount: recentNoShowCount ?? this.recentNoShowCount,
      lateCount: lateCount ?? this.lateCount,
      recentLateCount: recentLateCount ?? this.recentLateCount,
      workTypeStats: workTypeStats ?? this.workTypeStats,
      isAvailable: isAvailable ?? this.isAvailable,
      unavailableReason: unavailableReason ?? this.unavailableReason,
      availableFrom: availableFrom ?? this.availableFrom,
      isBlacklisted: isBlacklisted ?? this.isBlacklisted,
      blacklistReason: blacklistReason ?? this.blacklistReason,
      businessNumber: businessNumber ?? this.businessNumber,
      businessName: businessName ?? this.businessName,
      businessLicenseImageUrl: businessLicenseImageUrl ?? this.businessLicenseImageUrl,
      ceoName: ceoName ?? this.ceoName,
      // ── 신뢰도 시스템 ──
      storedTrustScore: storedTrustScore ?? this.storedTrustScore,
      rehireRate: rehireRate ?? this.rehireRate,
      badges: badges ?? this.badges,
      lastRestartAt: lastRestartAt ?? this.lastRestartAt,
      signatureBase64: clearSignature ? null : (signatureBase64 ?? this.signatureBase64),
      sealBase64: clearSeal ? null : (sealBase64 ?? this.sealBase64),
      sealType: sealType ?? this.sealType,
      subAdminBusinessIds: subAdminBusinessIds ?? this.subAdminBusinessIds,
      restrictedUntil: clearRestriction ? null : (restrictedUntil ?? this.restrictedUntil),
      notifPrefs: notifPrefs ?? this.notifPrefs,
      favoriteToIds: favoriteToIds ?? this.favoriteToIds,
      maxActiveTOs: clearMaxActiveTOs ? null : (maxActiveTOs ?? this.maxActiveTOs),
      // ── 지역 정보 ──
      homeRegion: clearHomeRegion ? null : (homeRegion ?? this.homeRegion),
      preferredJobRegions: preferredJobRegions ?? this.preferredJobRegions,
      lastSelectedJobRegion: clearLastSelectedJobRegion
          ? null
          : (lastSelectedJobRegion ?? this.lastSelectedJobRegion),
    );
  }
  /// subAdminBusinessIds 파싱 — 구 subAdminOf(String) 하위 호환 읽기 포함
  static List<String> _parseSubAdminBusinessIds(Map<String, dynamic> map) {
    if (map['subAdminBusinessIds'] is List) {
      return List<String>.from(map['subAdminBusinessIds']);
    }
    final old = map['subAdminOf'];
    if (old is String && old.isNotEmpty) return [old];
    return const [];
  }

  /// 안전한 DateTime 파싱
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toLocal();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}