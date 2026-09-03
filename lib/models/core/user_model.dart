import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../utils/encryption_helper.dart';
// trust_score_helper: [5A.2A] 신뢰도 점수 시스템 폐기
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
  final String? foreignIdNumber;        // 외국인등록번호 레거시 sentinel (backward-compat 전용)
  final String? foreignIdentityFingerprint; // HMAC-SHA256(전체 외국인등록번호, 서버 시크릿) — 고유성 식별 키 (서버 기록)
  // [TODO-FOREIGN-ENCRYPT] 향후 원천징수영수증/근로소득 지급명세서 기능 구현 시 활성화 예정.
  // 현재 CF에서 미기록(TODO 주석), toMap()에도 미포함 → DB에 이 값이 저장된 계정 없음.
  // 실제 기능에서 사용 전까지 불필요한 전체번호 저장 없음 (Legal/Tax requirement 확정 후 구현).
  final String? foreignIdNumberEncrypted;
  // 'active' | 'pending' | 'rejected' — 외국인은 가입 후 pending, 슈퍼관리자 승인 시 active
  final String accountStatus;
  // CF rejectForeignWorker가 저장하는 필드명('rejectionReason')과 반드시 일치해야 함
  final String? rejectionReason;

  // ── V3 외국인 Document-First 필드 ──
  /// 외국인등록증에 기재된 공식 이름 (OCR + 사용자 최종 확인).
  /// 공식 계약서·임금명세서에서 외국인의 경우 name 대신 이 값 우선 사용.
  /// OCR 실패 시 USER 직접 입력. "외국인등록증 진위 인증 완료"와 무관.
  final String? legalName;

  /// 앱 표시용 한국어 이름 (선택 입력).
  /// 예: 외국인등록증 이름 NGUYEN VAN AN → 한국어 이름 응우옌반안.
  /// displayName getter에서 legalName보다 우선 표시됨.
  final String? koreanName;

  /// 체류자격 / 비자 종류 (예: E-9, F-4, H-2).
  /// 외국인등록증 OCR + 사용자 확인. 법무부 조회 아님.
  /// "취업자격 인증 완료" 의미 없음.
  final String? visaType;

  /// 체류기간 만료일 (외국인등록증 기재 정보. 법무부 실시간 조회 아님).
  final DateTime? stayExpiryDate;

  // ── 신분증 정보 ──
  final String? idCardImageUrl;         // 신분증 앞면 이미지 URL (legacy — 신규 flow는 idCardImagePath 사용)
  final String? idCardImagePath;        // [BUG-ID-01] authoritative Storage path (신규 flow)
  final DateTime? idCardVerifiedAt;     // 신분증 인증 시각
  // [PRODUCT-POLICY] isIdVerified
  //   "USER가 자신의 허용된 Storage 경로에 신분증 이미지를 정상 업로드했다"는 상태.
  //   SUPER_ADMIN의 신분증 진위 심사 결과가 아니다.
  //   단기(슬롯 있는) 공고 지원 시 서버 gate로 사용됨 (callableApplyToTO).
  //   장기(슬롯 없는) 공고에는 이 gate가 적용되지 않는다.
  final bool isIdVerified;
  
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
  final String? bankbookImageUrl;       // legacy Download URL (V3 이전 방식)
  /// [V3] 통장사본 Storage 경로 — Signed URL 발급(callableGetBankbookSignedUrl)에 사용.
  /// V3 이전 등록 사용자는 null이며 bankbookImageUrl을 통해 접근.
  final String? bankbookImagePath;
  final DateTime? bankbookVerifiedAt;  // 통장사본 검증 시각 — legacy
  // [PRODUCT-POLICY] bankVerificationStatus — canonical 상태 정의
  //
  //   null
  //     계좌 미등록 상태, 또는 계좌 변경(callableUpdateBankAccount) 후 초기화된 상태.
  //
  //   'review_required'
  //     계좌/통장사본 제출 완료.
  //     현재 금융기관 자동 명의확인 API가 없어 SUPER_ADMIN 육안 검토가 진행 중인 상태.
  //     [PRODUCT-POLICY] 신규 Application 지원 가능 — review_required = 정상 제출 완료로 간주.
  //     hasWageDocumentsReady getter 참고 (review_required ≠ 지원 차단).
  //
  //   'verified'
  //     현재 정책상 SUPER_ADMIN이 통장사본을 확인하고 승인한 상태.
  //     신규 Application 지원 가능 (review_required와 동일).
  //     [PRODUCT-POLICY][CURRENT] 현재는 SUPER_ADMIN manual review 경로만 존재.
  //     향후 금융기관 API 도입 시 자동 verified 경로 추가 가능.
  //
  //   'mismatch'
  //     SUPER_ADMIN이 통장사본 명의 불일치 판정.
  //     USER가 통장사본을 재업로드해야 한다.
  //     신규 Application 지원 불가.
  //
  // stale 값 주의: 'pending', 'approved', 'rejected' 등은 canonical 상태가 아니다.
  // isBankbookVerified(bool)는 legacy 필드 — bankVerificationStatus로 대체됨.
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
  // ── 신뢰도 시스템 — [5A.2A] storedTrustScore 제거 ──
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
  static const String notifWorkReminder      = 'workReminder';
  static const String notifApplicationUpdate = 'applicationUpdate';
  static const String notifReviewAlert       = 'reviewAlert';
  static const String notifContractAlert     = 'contractAlert';
  static const String notifWageAlert         = 'wageAlert';
  static const String notifToMatchAlert      = 'toMatchAlert';  // [Phase 9B] 구인공고 매칭 알림

  static const Map<String, bool> defaultNotifPrefs = {
    'workReminder':      true,
    'applicationUpdate': true,
    'reviewAlert':       true,
    'contractAlert':     true,
    'wageAlert':         true,
    'toMatchAlert':      true,  // [Phase 9B] 구인공고 매칭 알림 (USER only)
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
    this.foreignIdentityFingerprint,
    this.foreignIdNumberEncrypted,
    this.accountStatus = 'active',
    this.rejectionReason,
    // V3 외국인 Document-First 필드
    this.legalName,
    this.koreanName,
    this.visaType,
    this.stayExpiryDate,
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
    this.bankbookImagePath,
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

  /// 외국인 여부 — 신규: foreignIdentityFingerprint(CF 기록), 레거시: foreignIdNumber 폴백
  bool get isForeign => foreignIdentityFingerprint != null || foreignIdNumber != null;

  /// 앱 표시용 이름 — koreanName → legalName → name 순서.
  /// 기존 name 필드 사용처의 호환성을 위해 직접 변경 대신 이 getter 사용 권장.
  String get displayName => koreanName ?? legalName ?? name;

  /// 공식 서류(계약서·임금명세서)에 사용할 이름.
  /// 외국인: legalName 우선, 없으면 name. 내국인: name.
  String get officialName => (isForeign && legalName != null && legalName!.isNotEmpty)
      ? legalName!
      : name;

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

  // ─────────────────────────────────────────────────────────────────
  // [PRODUCT-POLICY 2026-08-21] Canonical 지원 준비 Getter
  //
  // 목적: 각 화면이 서로 다른 기준으로 계산하던 "지원 준비 완료"를
  //       단일 위치에서 정의하여 정책 불일치를 방지한다.
  //
  // bankVerificationStatus 의미:
  //   null            → 미제출 상태
  //   'review_required' → 정상 제출, background 관리자 검토 중 → 지원 가능
  //   'verified'      → 관리자 검토 완료 → 지원 가능
  //   'mismatch'      → 관리자가 명시적 문제 발견 → 재등록 전 지원 차단
  //
  // isIdVerified 의미:
  //   PASS 본인인증 완료 사용자가 신분증 이미지를 정상 업로드했음.
  //   SUPER_ADMIN 사전 승인이 아님. callableMarkIdCardVerified가 업로드 후 설정.
  //
  // OCR:
  //   금융기관 실명조회가 아님. 입력 정보와 이미지의 1차 일치 확인 보조 수단.
  // ─────────────────────────────────────────────────────────────────

  /// 급여계좌 기본 정보 등록 여부 (bankName + accountNumber + accountHolder 존재).
  /// [V3 FOREIGN HOLDER] accountHolder 포함 — 외국인은 실제 예금주명 직접 입력.
  /// 계좌번호는 암호화 저장이지만 null 여부로만 확인한다.
  bool get hasBankAccount =>
      (bankName != null && bankName!.isNotEmpty) &&
      (accountNumber != null && accountNumber!.isNotEmpty) &&
      (accountHolder != null && accountHolder!.isNotEmpty);

  /// 통장사본 제출 여부 (bankbookImagePath 또는 bankbookImageUrl 중 하나 이상 존재).
  /// V3 이후: bankbookImagePath 우선. V3 이전 사용자: bankbookImageUrl 폴백.
  bool get hasBankbookDocument =>
      (bankbookImagePath != null && bankbookImagePath!.isNotEmpty) ||
      (bankbookImageUrl != null && bankbookImageUrl!.isNotEmpty);

  /// [PRODUCT-POLICY V3] 지원자 관점에서 급여정보 준비 완료 여부.
  /// bankName + accountNumber + accountHolder 존재 + 통장사본 제출.
  /// [Phase 6] bankVerificationStatus mismatch gate 제거됨 — V3에서 해당 status 미발급.
  bool get hasWageDocumentsReady =>
      hasBankAccount && hasBankbookDocument;

  /// [PRODUCT-POLICY] 신규 지원에 필요한 서류 준비 완료 여부.
  /// 장기 공고: hasIdDocument + hasWageDocumentsReady
  /// 단기(슬롯) 공고는 isIdVerified 추가 필요 — 이 getter는 공통 기반값.
  ///
  /// TODO: job_posting_screen, apply_prerequisites_screen을 이 getter로 통일할 것.
  bool get hasApplicationDocumentsReady => hasIdDocument && hasWageDocumentsReady;

  /// 가입 승인 대기 중 (레거시 'pending' 또는 V3 'registration_pending')
  bool get isPending => accountStatus == 'pending' || accountStatus == 'registration_pending';

  /// V3 Document-First 가입 미완료 상태.
  /// registration_pending 상태 = Auth 계정 생성됐으나 외국인등록증 등록 or fingerprint or termsConsent 미완료.
  bool get isRegistrationPending => accountStatus == 'registration_pending';

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

  // [5A.2A] trustScore / trustGrade / trustGradeEmoji getter 제거 — 신뢰도 점수 시스템 폐기

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
      foreignIdentityFingerprint: map['foreignIdentityFingerprint'] as String?,
      foreignIdNumberEncrypted: map['foreignIdNumberEncrypted'] as String?,
      accountStatus: map['accountStatus'] ?? 'active',
      rejectionReason: map['rejectionReason'] as String?,
      // V3 외국인 Document-First 필드
      legalName: map['legalName'] as String?,
      koreanName: map['koreanName'] as String?,
      visaType: map['visaType'] as String?,
      stayExpiryDate: _parseDateTime(map['stayExpiryDate']),
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
      bankbookImagePath: map['bankbookImagePath'],
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
      // ── 신뢰도 시스템 — [5A.2A] storedTrustScore 제거 (Firestore의 trustScore 필드는 읽지 않음)
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
      // V3 외국인 Document-First 필드
      'legalName': legalName,
      'koreanName': koreanName,
      'visaType': visaType,
      'stayExpiryDate': stayExpiryDate != null ? Timestamp.fromDate(stayExpiryDate!) : null,
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
      'bankbookImagePath': bankbookImagePath,
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
      // ── 신뢰도 시스템 — [5A.2A] trustScore write 제거
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
    // V3 외국인 Document-First
    String? legalName,
    bool clearLegalName = false,
    String? koreanName,
    bool clearKoreanName = false,
    String? visaType,
    DateTime? stayExpiryDate,
    bool clearStayExpiryDate = false,
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
    String? bankbookImagePath,
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
      legalName: clearLegalName ? null : (legalName ?? this.legalName),
      koreanName: clearKoreanName ? null : (koreanName ?? this.koreanName),
      visaType: visaType ?? this.visaType,
      stayExpiryDate: clearStayExpiryDate ? null : (stayExpiryDate ?? this.stayExpiryDate),
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
      bankbookImagePath: bankbookImagePath ?? this.bankbookImagePath,
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