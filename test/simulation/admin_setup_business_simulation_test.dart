// test/simulation/admin_setup_business_simulation_test.dart
//
// BUSINESS_ADMIN이 사업장을 등록/수정하는 시나리오 시뮬레이션 테스트
// 목적: BusinessFormScreen의 핵심 로직(유효성 검사·저장·상태 흐름)을
//       순수 Dart로 재구현해 검증한다.
//
// 의존성: Firebase · Flutter · Provider 없음. 순수 Dart 로직만.

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

// ══════════════════════════════════════════════════════════════
// 테스트용 데이터 모델 (Firebase Timestamp 의존 제거)
// ══════════════════════════════════════════════════════════════

/// 업종 카테고리 상수 (constants.dart와 동일)
const Map<String, List<String>> kJobCategories = {
  '회사': ['일반 회사', '제조, 생산, 건설', '물류센터'],
  '매장': [
    '카페 (카페, 음료, 베이커리)',
    '외식업 (음식, 외식업)',
    '판매-서비스 (편의점, 유통, 호텔 등)',
    '매장관리 (PC방, 스터디카페 등)',
  ],
  '기타': ['교육, 의료, 기관', '기타'],
};

/// 근태 반올림 규칙 (AttendanceRules 순수 Dart 재구현)
class SimAttendanceRules {
  final int earlyWindow;      // 0~120
  final int earlyArrivalUnit; // 5~60
  final int lateGrace;        // 0~30
  final int lateUnit;         // 5~60
  final int lateWindow;       // 0~60
  final int overtimeUnit;     // 5~30
  final int earlyLeaveUnit;   // 5~60

  const SimAttendanceRules({
    this.earlyWindow = 30,
    this.earlyArrivalUnit = 30,
    this.lateGrace = 5,
    this.lateUnit = 30,
    this.lateWindow = 30,
    this.overtimeUnit = 10,
    this.earlyLeaveUnit = 30,
  });

  factory SimAttendanceRules.defaults() => const SimAttendanceRules();

  factory SimAttendanceRules.fromMap(Map<String, dynamic> map) {
    return SimAttendanceRules(
      earlyWindow:      (map['earlyWindow']      as num?)?.toInt().clamp(0, 120) ?? 30,
      earlyArrivalUnit: (map['earlyArrivalUnit'] as num?)?.toInt().clamp(5, 60)  ?? 30,
      lateGrace:        (map['lateGrace']        as num?)?.toInt().clamp(0, 30)  ?? 5,
      lateUnit:         (map['lateUnit']         as num?)?.toInt().clamp(5, 60)  ?? 30,
      lateWindow:       (map['lateWindow']       as num?)?.toInt().clamp(0, 60)  ?? 30,
      overtimeUnit:     (map['overtimeUnit']     as num?)?.toInt().clamp(5, 30)  ?? 10,
      earlyLeaveUnit:   (map['earlyLeaveUnit']   as num?)?.toInt().clamp(5, 60)  ?? 30,
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
  };
}

/// 사업장 모델 (Firestore 의존 제거 버전)
class SimBusinessModel {
  final String id;
  final String name;
  final String businessNumber; // 숫자만 10자리
  final String? companyName;
  final String category;
  final String subCategory;
  final String address;
  final String? phone;
  final bool isApproved;
  final String ownerId;
  final List<String> managedBusinessIds;
  final String? mainImageUrl;
  final SimAttendanceRules? attendanceRules;
  final DateTime createdAt;

  SimBusinessModel({
    required this.id,
    required this.name,
    required this.businessNumber,
    this.companyName,
    required this.category,
    required this.subCategory,
    required this.address,
    this.phone,
    this.isApproved = false,
    required this.ownerId,
    List<String>? managedBusinessIds,
    this.mainImageUrl,
    this.attendanceRules,
    required this.createdAt,
  }) : managedBusinessIds = managedBusinessIds ?? [];
}

/// 유저 모델 (테스트용 슬림 버전)
class SimUserModel {
  final String uid;
  final String? businessNumber;
  final String? businessName;
  final String? ceoName;
  final String? businessLicenseImageUrl;
  final String? businessId;
  final List<String> managedBusinessIds;

  SimUserModel({
    required this.uid,
    this.businessNumber,
    this.businessName,
    this.ceoName,
    this.businessLicenseImageUrl,
    this.businessId,
    List<String>? managedBusinessIds,
  }) : managedBusinessIds = managedBusinessIds ?? [];

  bool get hasBusinessLicense => businessLicenseImageUrl != null;
  bool get isFirstBusiness => managedBusinessIds.isEmpty;
}

// ══════════════════════════════════════════════════════════════
// Step 1 유효성 검사 로직 (BusinessFormScreen._validateStep1 재구현)
// ══════════════════════════════════════════════════════════════

class Step1ValidationResult {
  final bool isValid;
  final String? errorMessage;
  const Step1ValidationResult({required this.isValid, this.errorMessage});
}

Step1ValidationResult validateStep1({
  required String? selectedCategory,
  required String? selectedSubCategory,
}) {
  if (selectedCategory == null || selectedCategory.isEmpty) {
    return const Step1ValidationResult(isValid: false, errorMessage: '업종을 선택해주세요');
  }
  if (selectedSubCategory == null || selectedSubCategory.isEmpty) {
    return const Step1ValidationResult(isValid: false, errorMessage: '업종을 선택해주세요');
  }
  // 카테고리-서브카테고리 조합 유효성
  final subs = kJobCategories[selectedCategory];
  if (subs == null || !subs.contains(selectedSubCategory)) {
    return const Step1ValidationResult(isValid: false, errorMessage: '잘못된 업종 조합입니다');
  }
  return const Step1ValidationResult(isValid: true);
}

// ══════════════════════════════════════════════════════════════
// Step 2 유효성 검사 로직 (폼 validator 재구현)
// ══════════════════════════════════════════════════════════════

class FieldValidationResult {
  final bool isValid;
  final String? error;
  const FieldValidationResult({required this.isValid, this.error});
}

/// 사업장명 validator (BusinessFormScreen._buildBasicInfoStep)
FieldValidationResult validateBusinessName(String? value) {
  if (value == null || value.trim().isEmpty) {
    return const FieldValidationResult(isValid: false, error: '사업장명을 입력하세요');
  }
  if (value.trim().length > 100) {
    return const FieldValidationResult(isValid: false, error: '사업장명은 100자 이하로 입력해주세요');
  }
  return const FieldValidationResult(isValid: true);
}

/// 사업자번호 validator (하이픈 제거 후 10자리)
FieldValidationResult validateBusinessNumber(String? value) {
  if (value == null || value.isEmpty) {
    return const FieldValidationResult(isValid: false, error: '사업자번호를 입력하세요');
  }
  final cleaned = value.replaceAll('-', '');
  if (cleaned.length != 10) {
    return const FieldValidationResult(isValid: false, error: '10자리를 입력하세요');
  }
  return const FieldValidationResult(isValid: true);
}

/// 상호명 validator
FieldValidationResult validateCompanyName(String? value) {
  if (value == null || value.trim().isEmpty) {
    return const FieldValidationResult(isValid: false, error: '상호명을 입력하세요');
  }
  if (value.trim().length > 100) {
    return const FieldValidationResult(isValid: false, error: '상호명은 100자 이하로 입력해주세요');
  }
  return const FieldValidationResult(isValid: true);
}

/// 전화번호 validator (숫자/하이픈/+/()/ 외 거부)
FieldValidationResult validatePhone(String? value) {
  if (value == null || value.isEmpty) {
    return const FieldValidationResult(isValid: true); // 선택 필드
  }
  if (!RegExp(r'^[\d\-\+\(\)\s]+$').hasMatch(value)) {
    return const FieldValidationResult(isValid: false, error: '숫자, 하이픈(-), 공백만 입력 가능합니다');
  }
  return const FieldValidationResult(isValid: true);
}

/// Step2 전체 유효성 검사
class Step2ValidationResult {
  final bool isValid;
  final Map<String, String> fieldErrors;
  const Step2ValidationResult({required this.isValid, this.fieldErrors = const {}});
}

Step2ValidationResult validateStep2({
  required String name,
  required String businessNumber,
  required String companyName,
  required String phone,
  required String address,
}) {
  final errors = <String, String>{};
  final nameResult = validateBusinessName(name);
  if (!nameResult.isValid) errors['name'] = nameResult.error!;

  final bizNumResult = validateBusinessNumber(businessNumber);
  if (!bizNumResult.isValid) errors['businessNumber'] = bizNumResult.error!;

  final companyResult = validateCompanyName(companyName);
  if (!companyResult.isValid) errors['companyName'] = companyResult.error!;

  final phoneResult = validatePhone(phone);
  if (!phoneResult.isValid) errors['phone'] = phoneResult.error!;

  if (address.trim().isEmpty) errors['address'] = '주소를 입력하세요';

  return Step2ValidationResult(isValid: errors.isEmpty, fieldErrors: errors);
}

// ══════════════════════════════════════════════════════════════
// Step 3 저장 사전 조건 검사 (_saveBusiness 진입부 재구현)
// ══════════════════════════════════════════════════════════════

class SavePreCheckResult {
  final bool canSave;
  final String? blockReason;
  const SavePreCheckResult({required this.canSave, this.blockReason});
}

SavePreCheckResult checkSavePreConditions({
  required SimUserModel? user,
}) {
  if (user == null) {
    return const SavePreCheckResult(canSave: false, blockReason: '로그인이 필요합니다.');
  }
  if (user.businessLicenseImageUrl == null) {
    return const SavePreCheckResult(canSave: false, blockReason: '사업자등록증 미등록');
  }
  return const SavePreCheckResult(canSave: true);
}

// ══════════════════════════════════════════════════════════════
// 사업장 Firestore 문서 빌더 (_saveBusiness 로직 재구현)
// ══════════════════════════════════════════════════════════════

class SimWriteBatchEntry {
  final String operation; // 'set' | 'update'
  final String collection;
  final String docId;
  final Map<String, dynamic> data;
  const SimWriteBatchEntry({
    required this.operation,
    required this.collection,
    required this.docId,
    required this.data,
  });
}

class SimWriteBatch {
  final List<SimWriteBatchEntry> _entries = [];
  bool _committed = false;
  bool _shouldFail = false;

  SimWriteBatch({bool shouldFail = false}) : _shouldFail = shouldFail;

  void set(String collection, String docId, Map<String, dynamic> data) {
    _entries.add(SimWriteBatchEntry(
      operation: 'set',
      collection: collection,
      docId: docId,
      data: data,
    ));
  }

  void update(String collection, String docId, Map<String, dynamic> data) {
    _entries.add(SimWriteBatchEntry(
      operation: 'update',
      collection: collection,
      docId: docId,
      data: data,
    ));
  }

  /// commit() 성공 시 true, 실패 시 예외 throw
  Future<void> commit() async {
    if (_shouldFail) throw Exception('Firestore WriteBatch commit 실패 (테스트용)');
    _committed = true;
  }

  bool get isCommitted => _committed;
  List<SimWriteBatchEntry> get entries => List.unmodifiable(_entries);
}

/// 신규 사업장 WriteBatch 빌드
SimWriteBatch buildNewBusinessBatch({
  required String newBizId,
  required String ownerId,
  required Map<String, dynamic> businessData,
  required bool isFirstBusiness,
  bool shouldFail = false,
}) {
  final batch = SimWriteBatch(shouldFail: shouldFail);
  batch.set('businesses', newBizId, {
    ...businessData,
    'isApproved': false, // 신규 등록 시 항상 false
    'ownerId': ownerId,
    'adminIds': [ownerId],
    'createdAt': DateTime.now().toIso8601String(), // 실제는 serverTimestamp
  });
  batch.update('users', ownerId, {
    'managedBusinessIds_arrayUnion': [newBizId],
    if (isFirstBusiness) 'businessId': newBizId,
  });
  return batch;
}

/// 수정 사업장 WriteBatch 빌드
SimWriteBatch buildEditBusinessBatch({
  required String bizId,
  required String ownerId,
  required Map<String, dynamic> businessData,
  bool shouldFail = false,
}) {
  final batch = SimWriteBatch(shouldFail: shouldFail);
  batch.update('businesses', bizId, businessData);
  batch.update('users', ownerId, {
    'managedBusinessIds_arrayUnion': [bizId], // 누락 시 보정
  });
  return batch;
}

// ══════════════════════════════════════════════════════════════
// 자동완성 로직 (_loadUserBusinessNumber 재구현)
// ══════════════════════════════════════════════════════════════

class AutoFillResult {
  final String businessNumber;
  final String companyName;
  final String ownerName;

  const AutoFillResult({
    required this.businessNumber,
    required this.companyName,
    required this.ownerName,
  });
}

/// 하이픈 포맷 (FormatHelper.formatBusinessNumber 재구현)
String formatBusinessNumber(String raw) {
  final digits = raw.replaceAll('-', '');
  if (digits.length != 10) return raw;
  return '${digits.substring(0, 3)}-${digits.substring(3, 5)}-${digits.substring(5)}';
}

AutoFillResult loadUserAutoFill(SimUserModel? user) {
  if (user == null) {
    return const AutoFillResult(businessNumber: '', companyName: '', ownerName: '');
  }
  final bizNum = user.businessNumber;
  final formattedBizNum = (bizNum != null && bizNum.isNotEmpty)
      ? formatBusinessNumber(bizNum)
      : '';
  final companyName = user.businessName ?? '';
  final ownerName = user.ceoName ?? '';
  return AutoFillResult(
    businessNumber: formattedBizNum,
    companyName: companyName,
    ownerName: ownerName,
  );
}

// ══════════════════════════════════════════════════════════════
// isApproved 상태 흐름 로직
// ══════════════════════════════════════════════════════════════

/// TO 생성 사전조건: isApproved 여부
bool canCreateTO({required SimBusinessModel business}) {
  return business.isApproved;
}

/// 슈퍼관리자 승인 시뮬레이션
SimBusinessModel approveBusinessBySuperAdmin(SimBusinessModel business) {
  return SimBusinessModel(
    id: business.id,
    name: business.name,
    businessNumber: business.businessNumber,
    companyName: business.companyName,
    category: business.category,
    subCategory: business.subCategory,
    address: business.address,
    phone: business.phone,
    isApproved: true, // 승인 완료
    ownerId: business.ownerId,
    managedBusinessIds: business.managedBusinessIds,
    mainImageUrl: business.mainImageUrl,
    attendanceRules: business.attendanceRules,
    createdAt: business.createdAt,
  );
}

// ══════════════════════════════════════════════════════════════
// 이미지 orphan 방지 로직
// ══════════════════════════════════════════════════════════════

class SimStorageService {
  final List<String> _deletedUrls = [];
  bool _shouldFailUpload = false;
  bool _shouldFailDelete = false;

  SimStorageService({bool shouldFailUpload = false, bool shouldFailDelete = false})
      : _shouldFailUpload = shouldFailUpload,
        _shouldFailDelete = shouldFailDelete;

  Future<String?> uploadImage(String path, String storagePath) async {
    if (_shouldFailUpload) return null;
    return 'https://storage.example.com/$storagePath';
  }

  Future<void> deleteMultipleByUrls(List<String> urls) async {
    if (_shouldFailDelete) throw Exception('Storage 삭제 실패 (테스트용)');
    _deletedUrls.addAll(urls);
  }

  List<String> get deletedUrls => List.unmodifiable(_deletedUrls);
}

/// Firestore 저장 실패 시 orphan URL 정리 시뮬레이션
Future<bool> saveWithOrphanCleanup({
  required List<String> newlyUploadedUrls,
  required bool firestoreShouldFail,
  required SimStorageService storageService,
}) async {
  try {
    if (firestoreShouldFail) {
      throw Exception('Firestore 저장 실패 (테스트용)');
    }
    return true; // 저장 성공
  } catch (_) {
    if (newlyUploadedUrls.isNotEmpty) {
      await storageService.deleteMultipleByUrls(newlyUploadedUrls);
    }
    return false; // 저장 실패
  }
}

// ══════════════════════════════════════════════════════════════
// managedBusinessIds 관리 로직
// ══════════════════════════════════════════════════════════════

List<String> applyArrayUnion(List<String> current, List<String> toAdd) {
  final result = List<String>.from(current);
  for (final id in toAdd) {
    if (!result.contains(id)) result.add(id);
  }
  return result;
}

List<String> applyArrayRemove(List<String> current, String toRemove) {
  return current.where((id) => id != toRemove).toList();
}

// ══════════════════════════════════════════════════════════════
// isFromSignUp 화면이동 로직
// ══════════════════════════════════════════════════════════════

enum SimNavigationAction { pushAndRemoveAll, popWithChange }

SimNavigationAction resolveNavigationAfterSave({required bool isFromSignUp}) {
  return isFromSignUp
      ? SimNavigationAction.pushAndRemoveAll  // 회원가입 후 → 로그인 화면으로
      : SimNavigationAction.popWithChange;    // 일반 등록/수정 → 뒤로가기
}

// ══════════════════════════════════════════════════════════════
// 사업장명 포맷 헬퍼
// ══════════════════════════════════════════════════════════════

String formatDisplayBusinessNumber(String raw) {
  final digits = raw.replaceAll('-', '');
  if (digits.length == 10) {
    return '${digits.substring(0, 3)}-${digits.substring(3, 5)}-${digits.substring(5)}';
  }
  return raw;
}

// ══════════════════════════════════════════════════════════════
// 메인 테스트
// ══════════════════════════════════════════════════════════════

void main() {
  // ────────────────────────────────────────────────────────────
  // Group 1: Step1 유효성 검사
  // ────────────────────────────────────────────────────────────
  group('Step1 유효성 검사', () {
    test('SCENARIO-BIZ-001: 카테고리 미선택 → 차단', () {
      final result = validateStep1(
        selectedCategory: null,
        selectedSubCategory: null,
      );
      expect(result.isValid, false);
      expect(result.errorMessage, isNotNull);
    });

    test('SCENARIO-BIZ-002: 카테고리만 선택, 서브카테고리 미선택 → 차단', () {
      final result = validateStep1(
        selectedCategory: '회사',
        selectedSubCategory: null,
      );
      expect(result.isValid, false);
    });

    test('SCENARIO-BIZ-003: 카테고리 빈 문자열 → 차단', () {
      final result = validateStep1(
        selectedCategory: '',
        selectedSubCategory: '물류센터',
      );
      expect(result.isValid, false);
    });

    test('SCENARIO-BIZ-004: 서브카테고리 빈 문자열 → 차단', () {
      final result = validateStep1(
        selectedCategory: '회사',
        selectedSubCategory: '',
      );
      expect(result.isValid, false);
    });

    test('SCENARIO-BIZ-005: 회사/물류센터 → 통과', () {
      final result = validateStep1(
        selectedCategory: '회사',
        selectedSubCategory: '물류센터',
      );
      expect(result.isValid, true);
    });

    test('SCENARIO-BIZ-006: 매장/카페 → 통과', () {
      final result = validateStep1(
        selectedCategory: '매장',
        selectedSubCategory: '카페 (카페, 음료, 베이커리)',
      );
      expect(result.isValid, true);
    });

    test('SCENARIO-BIZ-007: 기타/기타 → 통과', () {
      final result = validateStep1(
        selectedCategory: '기타',
        selectedSubCategory: '기타',
      );
      expect(result.isValid, true);
    });

    test('SCENARIO-BIZ-008: 잘못된 카테고리-서브카테고리 조합 → 차단', () {
      final result = validateStep1(
        selectedCategory: '회사',
        selectedSubCategory: '카페 (카페, 음료, 베이커리)', // 매장 하위 카테고리
      );
      expect(result.isValid, false);
    });

    test('SCENARIO-BIZ-009: 존재하지 않는 카테고리 → 차단', () {
      final result = validateStep1(
        selectedCategory: '없는카테고리',
        selectedSubCategory: '물류센터',
      );
      expect(result.isValid, false);
    });

    test('SCENARIO-BIZ-010: 카테고리 null, 서브카테고리 있음 → 차단', () {
      final result = validateStep1(
        selectedCategory: null,
        selectedSubCategory: '물류센터',
      );
      expect(result.isValid, false);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 2: Step2 사업장명 유효성 검사
  // ────────────────────────────────────────────────────────────
  group('Step2 사업장명 유효성 검사', () {
    test('SCENARIO-BIZ-011: 사업장명 빈 문자열 → 차단', () {
      final result = validateBusinessName('');
      expect(result.isValid, false);
      expect(result.error, '사업장명을 입력하세요');
    });

    test('SCENARIO-BIZ-012: 사업장명 공백만 → 차단', () {
      final result = validateBusinessName('   ');
      expect(result.isValid, false);
    });

    test('SCENARIO-BIZ-013: 사업장명 null → 차단', () {
      final result = validateBusinessName(null);
      expect(result.isValid, false);
    });

    test('SCENARIO-BIZ-014: 사업장명 100자 → 통과', () {
      final name = 'A' * 100;
      final result = validateBusinessName(name);
      expect(result.isValid, true);
    });

    test('SCENARIO-BIZ-015: 사업장명 101자 → 차단', () {
      final name = 'A' * 101;
      final result = validateBusinessName(name);
      expect(result.isValid, false);
      expect(result.error, contains('100자'));
    });

    test('SCENARIO-BIZ-016: 사업장명 앞뒤 공백 포함 100자 넘는 실제 문자 → 차단', () {
      final name = ' ${'A' * 101} '; // trim 후 101자
      final result = validateBusinessName(name);
      expect(result.isValid, false);
    });

    test('SCENARIO-BIZ-017: 사업장명 정상 입력 → 통과', () {
      final result = validateBusinessName('OOO물류센터');
      expect(result.isValid, true);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 3: Step2 사업자번호 유효성 검사
  // ────────────────────────────────────────────────────────────
  group('Step2 사업자번호 유효성 검사', () {
    test('SCENARIO-BIZ-018: 사업자번호 빈 문자열 → 차단', () {
      final result = validateBusinessNumber('');
      expect(result.isValid, false);
    });

    test('SCENARIO-BIZ-019: 사업자번호 9자리 → 차단', () {
      final result = validateBusinessNumber('123456789');
      expect(result.isValid, false);
      expect(result.error, contains('10자리'));
    });

    test('SCENARIO-BIZ-020: 사업자번호 11자리 → 차단', () {
      final result = validateBusinessNumber('12345678901');
      expect(result.isValid, false);
    });

    test('SCENARIO-BIZ-021: 사업자번호 하이픈 포함 형식 → 통과 (하이픈 제거 후 10자리)', () {
      final result = validateBusinessNumber('123-45-67890');
      expect(result.isValid, true);
    });

    test('SCENARIO-BIZ-022: 사업자번호 숫자만 10자리 → 통과', () {
      final result = validateBusinessNumber('1234567890');
      expect(result.isValid, true);
    });

    test('SCENARIO-BIZ-023: 하이픈 2개 포함 + 숫자 10자리 포맷 → 통과', () {
      final result = validateBusinessNumber('000-00-00000');
      expect(result.isValid, true);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 4: Step2 상호명 유효성 검사
  // ────────────────────────────────────────────────────────────
  group('Step2 상호명 유효성 검사', () {
    test('SCENARIO-BIZ-024: 상호명 빈 문자열 → 차단', () {
      final result = validateCompanyName('');
      expect(result.isValid, false);
    });

    test('SCENARIO-BIZ-025: 상호명 100자 → 통과', () {
      final result = validateCompanyName('A' * 100);
      expect(result.isValid, true);
    });

    test('SCENARIO-BIZ-026: 상호명 101자 → 차단', () {
      final result = validateCompanyName('A' * 101);
      expect(result.isValid, false);
      expect(result.error, contains('100자'));
    });

    test('SCENARIO-BIZ-027: 상호명 공백만 → 차단', () {
      final result = validateCompanyName('   ');
      expect(result.isValid, false);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 5: Step2 전화번호 유효성 검사
  // ────────────────────────────────────────────────────────────
  group('Step2 전화번호 유효성 검사', () {
    test('SCENARIO-BIZ-028: 전화번호 비어있음 → 통과 (선택 필드)', () {
      final result = validatePhone('');
      expect(result.isValid, true);
    });

    test('SCENARIO-BIZ-029: 전화번호 숫자+하이픈 → 통과', () {
      final result = validatePhone('02-1234-5678');
      expect(result.isValid, true);
    });

    test('SCENARIO-BIZ-030: 전화번호 한글 포함 → 차단', () {
      final result = validatePhone('02-1234가나다');
      expect(result.isValid, false);
    });

    test('SCENARIO-BIZ-031: 전화번호 특수문자 포함 → 차단', () {
      final result = validatePhone('010-1234-5678!');
      expect(result.isValid, false);
    });

    test('SCENARIO-BIZ-032: 전화번호 숫자만 → 통과', () {
      final result = validatePhone('01012345678');
      expect(result.isValid, true);
    });

    test('SCENARIO-BIZ-033: 전화번호 국제번호 형식 (+82) → 통과', () {
      final result = validatePhone('+82-10-1234-5678');
      expect(result.isValid, true);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 6: Step3 저장 사전조건 (사업자등록증 체크)
  // ────────────────────────────────────────────────────────────
  group('Step3 저장 사전조건 검사', () {
    test('SCENARIO-BIZ-034: 로그인 안된 상태 → 차단', () {
      final result = checkSavePreConditions(user: null);
      expect(result.canSave, false);
      expect(result.blockReason, contains('로그인'));
    });

    test('SCENARIO-BIZ-035: 사업자등록증 미등록 → 차단', () {
      final user = SimUserModel(
        uid: 'user1',
        businessLicenseImageUrl: null, // 미등록
      );
      final result = checkSavePreConditions(user: user);
      expect(result.canSave, false);
      expect(result.blockReason, contains('사업자등록증'));
    });

    test('SCENARIO-BIZ-036: 사업자등록증 등록됨 → 통과', () {
      final user = SimUserModel(
        uid: 'user1',
        businessLicenseImageUrl: 'https://storage.example.com/license.jpg',
      );
      final result = checkSavePreConditions(user: user);
      expect(result.canSave, true);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 7: 신규 사업장 WriteBatch 구성
  // ────────────────────────────────────────────────────────────
  group('신규 사업장 WriteBatch 구성', () {
    test('SCENARIO-BIZ-037: 신규 등록 시 isApproved=false 설정', () {
      final batch = buildNewBusinessBatch(
        newBizId: 'biz001',
        ownerId: 'user1',
        businessData: {'name': '테스트 사업장'},
        isFirstBusiness: true,
      );

      final bizEntry = batch.entries.firstWhere((e) => e.collection == 'businesses');
      expect(bizEntry.data['isApproved'], false);
    });

    test('SCENARIO-BIZ-038: 신규 등록 시 adminIds=[ownerId] 설정', () {
      final batch = buildNewBusinessBatch(
        newBizId: 'biz001',
        ownerId: 'user1',
        businessData: {},
        isFirstBusiness: true,
      );

      final bizEntry = batch.entries.firstWhere((e) => e.collection == 'businesses');
      expect(bizEntry.data['adminIds'], ['user1']);
    });

    test('SCENARIO-BIZ-039: 최초 사업장이면 businessId 설정', () {
      final batch = buildNewBusinessBatch(
        newBizId: 'biz001',
        ownerId: 'user1',
        businessData: {},
        isFirstBusiness: true, // 첫 사업장
      );

      final userEntry = batch.entries.firstWhere((e) => e.collection == 'users');
      expect(userEntry.data['businessId'], 'biz001');
    });

    test('SCENARIO-BIZ-040: 추가 사업장이면 businessId 변경하지 않음', () {
      final batch = buildNewBusinessBatch(
        newBizId: 'biz002',
        ownerId: 'user1',
        businessData: {},
        isFirstBusiness: false, // 이미 사업장 있음
      );

      final userEntry = batch.entries.firstWhere((e) => e.collection == 'users');
      expect(userEntry.data.containsKey('businessId'), false);
    });

    test('SCENARIO-BIZ-041: WriteBatch는 businesses + users 두 entry 포함', () {
      final batch = buildNewBusinessBatch(
        newBizId: 'biz001',
        ownerId: 'user1',
        businessData: {},
        isFirstBusiness: true,
      );
      expect(batch.entries.length, 2);
    });

    test('SCENARIO-BIZ-042: WriteBatch commit 성공 시 isCommitted=true', () async {
      final batch = buildNewBusinessBatch(
        newBizId: 'biz001',
        ownerId: 'user1',
        businessData: {},
        isFirstBusiness: true,
      );
      await batch.commit();
      expect(batch.isCommitted, true);
    });

    test('SCENARIO-BIZ-043: WriteBatch commit 실패 시 예외 발생 (원자적 롤백)', () async {
      final batch = buildNewBusinessBatch(
        newBizId: 'biz001',
        ownerId: 'user1',
        businessData: {},
        isFirstBusiness: true,
        shouldFail: true,
      );
      expect(() async => await batch.commit(), throwsException);
      expect(batch.isCommitted, false);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 8: 수정 사업장 WriteBatch 구성
  // ────────────────────────────────────────────────────────────
  group('수정 사업장 WriteBatch 구성', () {
    test('SCENARIO-BIZ-044: 수정 시 businesses update + users arrayUnion 포함', () {
      final batch = buildEditBusinessBatch(
        bizId: 'biz001',
        ownerId: 'user1',
        businessData: {'name': '수정된 사업장'},
      );
      expect(batch.entries.length, 2);
      expect(
        batch.entries.any((e) => e.collection == 'businesses' && e.operation == 'update'),
        true,
      );
      expect(
        batch.entries.any((e) => e.collection == 'users' && e.operation == 'update'),
        true,
      );
    });

    test('SCENARIO-BIZ-045: 수정 시 isApproved 기존 값 유지 (false→false)', () {
      // 수정 시 businessData에 isApproved를 기존 값으로 전달해야 함
      final batch = buildEditBusinessBatch(
        bizId: 'biz001',
        ownerId: 'user1',
        businessData: {'isApproved': false},
      );
      final bizEntry = batch.entries.firstWhere((e) => e.collection == 'businesses');
      expect(bizEntry.data['isApproved'], false);
    });

    test('SCENARIO-BIZ-046: 수정 시 isApproved 기존 값 유지 (true→true)', () {
      final batch = buildEditBusinessBatch(
        bizId: 'biz001',
        ownerId: 'user1',
        businessData: {'isApproved': true}, // 이미 승인된 사업장
      );
      final bizEntry = batch.entries.firstWhere((e) => e.collection == 'businesses');
      expect(bizEntry.data['isApproved'], true);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 9: isFromSignUp 화면 이동 로직
  // ────────────────────────────────────────────────────────────
  group('isFromSignUp 화면 이동 로직', () {
    test('SCENARIO-BIZ-047: isFromSignUp=true → 로그인 화면으로 (pushAndRemoveAll)', () {
      final action = resolveNavigationAfterSave(isFromSignUp: true);
      expect(action, SimNavigationAction.pushAndRemoveAll);
    });

    test('SCENARIO-BIZ-048: isFromSignUp=false → 뒤로가기 (popWithChange)', () {
      final action = resolveNavigationAfterSave(isFromSignUp: false);
      expect(action, SimNavigationAction.popWithChange);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 10: 자동완성 (_loadUserBusinessNumber)
  // ────────────────────────────────────────────────────────────
  group('자동완성 로직 (_loadUserBusinessNumber)', () {
    test('SCENARIO-BIZ-049: user null → 모두 빈 값 반환', () {
      final result = loadUserAutoFill(null);
      expect(result.businessNumber, '');
      expect(result.companyName, '');
      expect(result.ownerName, '');
    });

    test('SCENARIO-BIZ-050: user businessNumber 있으면 하이픈 포맷으로 자동완성', () {
      final user = SimUserModel(uid: 'u1', businessNumber: '1234567890');
      final result = loadUserAutoFill(user);
      expect(result.businessNumber, '123-45-67890');
    });

    test('SCENARIO-BIZ-051: user businessNumber null → 빈 문자열', () {
      final user = SimUserModel(uid: 'u1', businessNumber: null);
      final result = loadUserAutoFill(user);
      expect(result.businessNumber, '');
    });

    test('SCENARIO-BIZ-052: user businessName 있으면 자동완성', () {
      final user = SimUserModel(uid: 'u1', businessName: '(주)테스트물류');
      final result = loadUserAutoFill(user);
      expect(result.companyName, '(주)테스트물류');
    });

    test('SCENARIO-BIZ-053: user businessName null → 빈 문자열', () {
      final user = SimUserModel(uid: 'u1', businessName: null);
      final result = loadUserAutoFill(user);
      expect(result.companyName, '');
    });

    test('SCENARIO-BIZ-054: user ceoName 있으면 자동완성', () {
      final user = SimUserModel(uid: 'u1', ceoName: '홍길동');
      final result = loadUserAutoFill(user);
      expect(result.ownerName, '홍길동');
    });

    test('SCENARIO-BIZ-055: user ceoName null → 빈 문자열', () {
      final user = SimUserModel(uid: 'u1', ceoName: null);
      final result = loadUserAutoFill(user);
      expect(result.ownerName, '');
    });

    test('SCENARIO-BIZ-056: businessNumber 빈 문자열 → 자동완성 없음', () {
      final user = SimUserModel(uid: 'u1', businessNumber: '');
      final result = loadUserAutoFill(user);
      expect(result.businessNumber, '');
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 11: isApproved 상태 흐름
  // ────────────────────────────────────────────────────────────
  group('isApproved 상태 흐름', () {
    final now = DateTime(2026, 7, 8);

    test('SCENARIO-BIZ-057: 신규 등록 시 isApproved=false', () {
      final biz = SimBusinessModel(
        id: 'biz001',
        name: '테스트 사업장',
        businessNumber: '1234567890',
        category: '회사',
        subCategory: '물류센터',
        address: '서울시 강남구',
        ownerId: 'user1',
        isApproved: false,
        createdAt: now,
      );
      expect(biz.isApproved, false);
    });

    test('SCENARIO-BIZ-058: isApproved=false 상태에서는 TO 생성 불가', () {
      final biz = SimBusinessModel(
        id: 'biz001',
        name: '테스트 사업장',
        businessNumber: '1234567890',
        category: '회사',
        subCategory: '물류센터',
        address: '서울시 강남구',
        ownerId: 'user1',
        isApproved: false,
        createdAt: now,
      );
      expect(canCreateTO(business: biz), false);
    });

    test('SCENARIO-BIZ-059: 슈퍼관리자 승인 후 isApproved=true', () {
      final biz = SimBusinessModel(
        id: 'biz001',
        name: '테스트 사업장',
        businessNumber: '1234567890',
        category: '회사',
        subCategory: '물류센터',
        address: '서울시 강남구',
        ownerId: 'user1',
        isApproved: false,
        createdAt: now,
      );
      final approvedBiz = approveBusinessBySuperAdmin(biz);
      expect(approvedBiz.isApproved, true);
    });

    test('SCENARIO-BIZ-060: 승인 후 TO 생성 가능', () {
      final biz = SimBusinessModel(
        id: 'biz001',
        name: '테스트 사업장',
        businessNumber: '1234567890',
        category: '회사',
        subCategory: '물류센터',
        address: '서울시 강남구',
        ownerId: 'user1',
        isApproved: true,
        createdAt: now,
      );
      expect(canCreateTO(business: biz), true);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 12: AttendanceRules 클램핑 및 defaults
  // ────────────────────────────────────────────────────────────
  group('AttendanceRules 클램핑 및 defaults', () {
    test('SCENARIO-BIZ-061: defaults() 반환값 확인', () {
      final rules = SimAttendanceRules.defaults();
      expect(rules.earlyWindow, 30);
      expect(rules.lateGrace, 5);
      expect(rules.earlyArrivalUnit, 30);
      expect(rules.lateUnit, 30);
      expect(rules.lateWindow, 30);
      expect(rules.overtimeUnit, 10);
      expect(rules.earlyLeaveUnit, 30);
    });

    test('SCENARIO-BIZ-062: earlyWindow 0 이하 → clamp(0)', () {
      final rules = SimAttendanceRules.fromMap({'earlyWindow': -5});
      expect(rules.earlyWindow, 0);
    });

    test('SCENARIO-BIZ-063: earlyWindow 120 초과 → clamp(120)', () {
      final rules = SimAttendanceRules.fromMap({'earlyWindow': 999});
      expect(rules.earlyWindow, 120);
    });

    test('SCENARIO-BIZ-064: lateGrace 0 → 허용', () {
      final rules = SimAttendanceRules.fromMap({'lateGrace': 0});
      expect(rules.lateGrace, 0);
    });

    test('SCENARIO-BIZ-065: lateGrace 30 초과 → clamp(30)', () {
      final rules = SimAttendanceRules.fromMap({'lateGrace': 100});
      expect(rules.lateGrace, 30);
    });

    test('SCENARIO-BIZ-066: earlyArrivalUnit 4 이하 → clamp(5)', () {
      final rules = SimAttendanceRules.fromMap({'earlyArrivalUnit': 4});
      expect(rules.earlyArrivalUnit, 5);
    });

    test('SCENARIO-BIZ-067: earlyArrivalUnit 60 초과 → clamp(60)', () {
      final rules = SimAttendanceRules.fromMap({'earlyArrivalUnit': 70});
      expect(rules.earlyArrivalUnit, 60);
    });

    test('SCENARIO-BIZ-068: lateUnit 4 이하 → clamp(5)', () {
      final rules = SimAttendanceRules.fromMap({'lateUnit': 1});
      expect(rules.lateUnit, 5);
    });

    test('SCENARIO-BIZ-069: lateUnit 60 초과 → clamp(60)', () {
      final rules = SimAttendanceRules.fromMap({'lateUnit': 90});
      expect(rules.lateUnit, 60);
    });

    test('SCENARIO-BIZ-070: lateWindow 0 → 허용', () {
      final rules = SimAttendanceRules.fromMap({'lateWindow': 0});
      expect(rules.lateWindow, 0);
    });

    test('SCENARIO-BIZ-071: lateWindow 60 초과 → clamp(60)', () {
      final rules = SimAttendanceRules.fromMap({'lateWindow': 120});
      expect(rules.lateWindow, 60);
    });

    test('SCENARIO-BIZ-072: overtimeUnit 4 이하 → clamp(5)', () {
      final rules = SimAttendanceRules.fromMap({'overtimeUnit': 3});
      expect(rules.overtimeUnit, 5);
    });

    test('SCENARIO-BIZ-073: overtimeUnit 30 초과 → clamp(30)', () {
      final rules = SimAttendanceRules.fromMap({'overtimeUnit': 60});
      expect(rules.overtimeUnit, 30);
    });

    test('SCENARIO-BIZ-074: earlyLeaveUnit 4 이하 → clamp(5)', () {
      final rules = SimAttendanceRules.fromMap({'earlyLeaveUnit': 0});
      expect(rules.earlyLeaveUnit, 5);
    });

    test('SCENARIO-BIZ-075: earlyLeaveUnit 60 초과 → clamp(60)', () {
      final rules = SimAttendanceRules.fromMap({'earlyLeaveUnit': 100});
      expect(rules.earlyLeaveUnit, 60);
    });

    test('SCENARIO-BIZ-076: 모든 필드 null → defaults() 폴백 값', () {
      final rules = SimAttendanceRules.fromMap({});
      expect(rules.earlyWindow, 30);
      expect(rules.lateGrace, 5);
      expect(rules.earlyArrivalUnit, 30);
      expect(rules.lateUnit, 30);
      expect(rules.lateWindow, 30);
      expect(rules.overtimeUnit, 10);
      expect(rules.earlyLeaveUnit, 30);
    });

    test('SCENARIO-BIZ-077: businessModel.attendanceRules==null → defaults() 폴백', () {
      // BusinessFormScreen._loadBusinessData: business.attendanceRules ?? AttendanceRules.defaults()
      final SimAttendanceRules? rulesFromBusiness = null;
      final effectiveRules = rulesFromBusiness ?? SimAttendanceRules.defaults();
      expect(effectiveRules.earlyWindow, 30);
      expect(effectiveRules.overtimeUnit, 10);
    });

    test('SCENARIO-BIZ-078: toMap() 후 fromMap() 왕복 직렬화 일치', () {
      final original = const SimAttendanceRules(
        earlyWindow: 45,
        earlyArrivalUnit: 15,
        lateGrace: 10,
        lateUnit: 15,
        lateWindow: 20,
        overtimeUnit: 15,
        earlyLeaveUnit: 15,
      );
      final map = original.toMap();
      final restored = SimAttendanceRules.fromMap(map);
      expect(restored.earlyWindow, original.earlyWindow);
      expect(restored.earlyArrivalUnit, original.earlyArrivalUnit);
      expect(restored.lateGrace, original.lateGrace);
      expect(restored.lateUnit, original.lateUnit);
      expect(restored.lateWindow, original.lateWindow);
      expect(restored.overtimeUnit, original.overtimeUnit);
      expect(restored.earlyLeaveUnit, original.earlyLeaveUnit);
    });

    test('SCENARIO-BIZ-079: earlyWindow 경계값 0 허용', () {
      final rules = SimAttendanceRules.fromMap({'earlyWindow': 0});
      expect(rules.earlyWindow, 0);
    });

    test('SCENARIO-BIZ-080: earlyWindow 경계값 120 허용', () {
      final rules = SimAttendanceRules.fromMap({'earlyWindow': 120});
      expect(rules.earlyWindow, 120);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 13: 이미지 orphan 방지
  // ────────────────────────────────────────────────────────────
  group('이미지 orphan 방지 (Storage 정리)', () {
    test('SCENARIO-BIZ-081: Firestore 저장 실패 시 업로드된 URL 삭제', () async {
      final storageService = SimStorageService();
      final uploadedUrls = [
        'https://storage.example.com/img1.jpg',
        'https://storage.example.com/img2.jpg',
      ];

      final saved = await saveWithOrphanCleanup(
        newlyUploadedUrls: uploadedUrls,
        firestoreShouldFail: true,
        storageService: storageService,
      );

      expect(saved, false);
      expect(storageService.deletedUrls, containsAll(uploadedUrls));
    });

    test('SCENARIO-BIZ-082: Firestore 저장 성공 시 업로드된 URL 삭제 안 함', () async {
      final storageService = SimStorageService();
      final uploadedUrls = ['https://storage.example.com/img1.jpg'];

      final saved = await saveWithOrphanCleanup(
        newlyUploadedUrls: uploadedUrls,
        firestoreShouldFail: false,
        storageService: storageService,
      );

      expect(saved, true);
      expect(storageService.deletedUrls, isEmpty);
    });

    test('SCENARIO-BIZ-083: 업로드된 URL이 없으면 Storage 삭제 호출 안 함 (빈 리스트)', () async {
      final storageService = SimStorageService();

      final saved = await saveWithOrphanCleanup(
        newlyUploadedUrls: [],
        firestoreShouldFail: true,
        storageService: storageService,
      );

      expect(saved, false);
      expect(storageService.deletedUrls, isEmpty);
    });

    test('SCENARIO-BIZ-084: Firestore 저장 실패 시 3개 URL 모두 삭제됨', () async {
      final storageService = SimStorageService();
      final uploadedUrls = [
        'https://storage.example.com/main.jpg',
        'https://storage.example.com/additional1.jpg',
        'https://storage.example.com/transport1.jpg',
      ];

      await saveWithOrphanCleanup(
        newlyUploadedUrls: uploadedUrls,
        firestoreShouldFail: true,
        storageService: storageService,
      );

      expect(storageService.deletedUrls.length, 3);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 14: managedBusinessIds 관리
  // ────────────────────────────────────────────────────────────
  group('managedBusinessIds 관리', () {
    test('SCENARIO-BIZ-085: 최초 사업장 등록 시 businessId AND managedBusinessIds=[newId] 설정', () {
      final batch = buildNewBusinessBatch(
        newBizId: 'biz001',
        ownerId: 'user1',
        businessData: {},
        isFirstBusiness: true,
      );
      final userEntry = batch.entries.firstWhere((e) => e.collection == 'users');
      expect(userEntry.data['businessId'], 'biz001');
      expect(userEntry.data['managedBusinessIds_arrayUnion'], contains('biz001'));
    });

    test('SCENARIO-BIZ-086: 추가 사업장 등록 시 managedBusinessIds에 arrayUnion만 (businessId 불변)', () {
      final batch = buildNewBusinessBatch(
        newBizId: 'biz002',
        ownerId: 'user1',
        businessData: {},
        isFirstBusiness: false,
      );
      final userEntry = batch.entries.firstWhere((e) => e.collection == 'users');
      expect(userEntry.data.containsKey('businessId'), false);
      expect(userEntry.data['managedBusinessIds_arrayUnion'], contains('biz002'));
    });

    test('SCENARIO-BIZ-087: arrayUnion - 중복 추가 시 리스트에 한 번만 존재', () {
      final current = ['biz001', 'biz002'];
      final result = applyArrayUnion(current, ['biz001']); // 중복
      expect(result.where((id) => id == 'biz001').length, 1);
    });

    test('SCENARIO-BIZ-088: arrayUnion - 신규 ID 추가 시 포함됨', () {
      final current = ['biz001'];
      final result = applyArrayUnion(current, ['biz002']);
      expect(result, containsAll(['biz001', 'biz002']));
    });

    test('SCENARIO-BIZ-089: arrayRemove - 삭제 시 해당 ID 제거됨', () {
      final current = ['biz001', 'biz002', 'biz003'];
      final result = applyArrayRemove(current, 'biz002');
      expect(result, containsAll(['biz001', 'biz003']));
      expect(result.contains('biz002'), false);
    });

    test('SCENARIO-BIZ-090: arrayRemove - 존재하지 않는 ID 제거 → 원본 유지', () {
      final current = ['biz001', 'biz002'];
      final result = applyArrayRemove(current, 'biz999');
      expect(result, containsAll(['biz001', 'biz002']));
      expect(result.length, 2);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 15: Step2 통합 유효성 검사
  // ────────────────────────────────────────────────────────────
  group('Step2 통합 유효성 검사', () {
    test('SCENARIO-BIZ-091: 모든 필드 정상 입력 → 통과', () {
      final result = validateStep2(
        name: '정상 사업장',
        businessNumber: '123-45-67890',
        companyName: '(주)정상회사',
        phone: '02-1234-5678',
        address: '서울시 강남구 테헤란로 123',
      );
      expect(result.isValid, true);
      expect(result.fieldErrors, isEmpty);
    });

    test('SCENARIO-BIZ-092: 여러 필드 동시 오류 → 모든 오류 수집', () {
      final result = validateStep2(
        name: '', // 오류
        businessNumber: '123', // 오류
        companyName: '', // 오류
        phone: '가나다', // 오류
        address: '', // 오류
      );
      expect(result.isValid, false);
      expect(result.fieldErrors.length, 5);
    });

    test('SCENARIO-BIZ-093: 전화번호 빈 문자열(선택 필드) + 나머지 정상 → 통과', () {
      final result = validateStep2(
        name: '사업장',
        businessNumber: '1234567890',
        companyName: '회사명',
        phone: '', // 선택 필드 — 빈값 허용
        address: '서울시',
      );
      expect(result.isValid, true);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 16: 사업자번호 하이픈 포맷
  // ────────────────────────────────────────────────────────────
  group('사업자번호 하이픈 포맷', () {
    test('SCENARIO-BIZ-094: 10자리 숫자 → 000-00-00000 포맷', () {
      expect(formatBusinessNumber('1234567890'), '123-45-67890');
    });

    test('SCENARIO-BIZ-095: 이미 하이픈 있는 경우 → 동일 포맷 유지', () {
      // 하이픈 제거 후 재포맷
      final digits = '123-45-67890'.replaceAll('-', '');
      expect(formatBusinessNumber(digits), '123-45-67890');
    });

    test('SCENARIO-BIZ-096: 10자리 아닌 경우 → 원본 반환', () {
      expect(formatBusinessNumber('12345'), '12345');
    });

    test('SCENARIO-BIZ-097: 저장 시 하이픈 제거 후 10자리 저장', () {
      // _saveBusiness: _businessNumberController.text.replaceAll('-', '')
      final input = '123-45-67890';
      final stored = input.replaceAll('-', '');
      expect(stored, '1234567890');
      expect(stored.length, 10);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 17: PopScope 취소 동작
  // ────────────────────────────────────────────────────────────
  group('PopScope canPop 로직', () {
    test('SCENARIO-BIZ-098: isFromSignUp=true, isEditMode=false → canPop=false', () {
      // canPop: !widget.isFromSignUp && !_isEditMode
      final isFromSignUp = true;
      final isEditMode = false;
      final canPop = !isFromSignUp && !isEditMode;
      expect(canPop, false);
    });

    test('SCENARIO-BIZ-099: isFromSignUp=false, isEditMode=true → canPop=false', () {
      final isFromSignUp = false;
      final isEditMode = true;
      final canPop = !isFromSignUp && !isEditMode;
      expect(canPop, false);
    });

    test('SCENARIO-BIZ-100: isFromSignUp=false, isEditMode=false → canPop=true', () {
      final isFromSignUp = false;
      final isEditMode = false;
      final canPop = !isFromSignUp && !isEditMode;
      expect(canPop, true);
    });

    test('SCENARIO-BIZ-101: isFromSignUp=true, isEditMode=true → canPop=false', () {
      final isFromSignUp = true;
      final isEditMode = true;
      final canPop = !isFromSignUp && !isEditMode;
      expect(canPop, false);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Group 18: 엣지 케이스 / 복합 시나리오
  // ────────────────────────────────────────────────────────────
  group('복합 시나리오 및 엣지 케이스', () {
    test('SCENARIO-BIZ-102: 사업자번호 하이픈만 입력 → 차단', () {
      final result = validateBusinessNumber('---');
      // 숫자 제거 후 0자리
      expect(result.isValid, false);
    });

    test('SCENARIO-BIZ-103: 사업장명 앞뒤 공백만 trim 시 빈 값 → 차단', () {
      final result = validateBusinessName('   \t\n   ');
      expect(result.isValid, false);
    });

    test('SCENARIO-BIZ-104: AttendanceRules 경계값 전체 정상 → 클램핑 없음', () {
      final rules = SimAttendanceRules.fromMap({
        'earlyWindow': 60,
        'earlyArrivalUnit': 30,
        'lateGrace': 15,
        'lateUnit': 30,
        'lateWindow': 30,
        'overtimeUnit': 15,
        'earlyLeaveUnit': 30,
      });
      expect(rules.earlyWindow, 60);
      expect(rules.earlyArrivalUnit, 30);
      expect(rules.lateGrace, 15);
      expect(rules.lateUnit, 30);
      expect(rules.lateWindow, 30);
      expect(rules.overtimeUnit, 15);
      expect(rules.earlyLeaveUnit, 30);
    });

    test('SCENARIO-BIZ-105: 수정 모드에서 신규 데이터를 WriteBatch로 저장', () async {
      final batch = buildEditBusinessBatch(
        bizId: 'biz001',
        ownerId: 'user1',
        businessData: {
          'name': '수정된 사업장명',
          'attendanceRules': SimAttendanceRules.defaults().toMap(),
        },
      );
      await batch.commit();
      expect(batch.isCommitted, true);
      final bizEntry = batch.entries.firstWhere((e) => e.collection == 'businesses');
      expect(bizEntry.data['name'], '수정된 사업장명');
    });

    test('SCENARIO-BIZ-106: Stepper 0→1→2 순서 시뮬레이션 (전체 통과)', () {
      // Step1
      final step1 = validateStep1(
        selectedCategory: '회사',
        selectedSubCategory: '물류센터',
      );
      expect(step1.isValid, true);

      // Step2
      final step2 = validateStep2(
        name: '테스트물류센터',
        businessNumber: '1234567890',
        companyName: '(주)테스트',
        phone: '031-123-4567',
        address: '경기도 화성시',
      );
      expect(step2.isValid, true);

      // Step3 사전조건
      final user = SimUserModel(
        uid: 'admin1',
        businessLicenseImageUrl: 'https://storage.example.com/license.jpg',
      );
      final step3 = checkSavePreConditions(user: user);
      expect(step3.canSave, true);
    });

    test('SCENARIO-BIZ-107: Step1 실패 시 Step2로 넘어가지 않음 (플래그 검사)', () {
      final step1 = validateStep1(
        selectedCategory: null,
        selectedSubCategory: null,
      );
      // step1 실패 → currentStep은 0 유지
      var currentStep = 0;
      if (step1.isValid) currentStep = 1;
      expect(currentStep, 0); // Step1에서 차단됨
    });

    test('SCENARIO-BIZ-108: 사업자등록증 없는 상태에서 저장 시도 → 차단 후 문서 등록 안내', () {
      final user = SimUserModel(
        uid: 'admin1',
        businessLicenseImageUrl: null,
      );
      final result = checkSavePreConditions(user: user);
      expect(result.canSave, false);
      expect(result.blockReason, contains('사업자등록증'));
    });

    test('SCENARIO-BIZ-109: 첫 사업장 판단 로직 — managedBusinessIds 빈 배열', () {
      final user = SimUserModel(uid: 'u1', managedBusinessIds: []);
      expect(user.isFirstBusiness, true);
    });

    test('SCENARIO-BIZ-110: 추가 사업장 판단 로직 — managedBusinessIds 1개 이상', () {
      final user = SimUserModel(uid: 'u1', managedBusinessIds: ['biz001']);
      expect(user.isFirstBusiness, false);
    });
  });
}
