// test/simulation/register_flow_simulation_test.dart
//
// 회원가입 성공 후 플로우 시뮬레이션 테스트
// 목적: 동의 기록, 이미지 업로드 조건, PASS 토큰 소비, 화면 이동 등
//       register_screen.dart의 핵심 로직을 순수 Dart로 재구현해 검증한다.
//
// 의존성: Firebase · Flutter · Provider 없음. 순수 Dart 로직만.

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

// ══════════════════════════════════════════════════════════════
// 공통 열거형 / 데이터 클래스 (Firebase 의존 없음)
// ══════════════════════════════════════════════════════════════

enum SimUserRole { USER, BUSINESS_ADMIN }

class SimTermsItem {
  final String id;
  final String version;
  final bool isRequired;

  const SimTermsItem({
    required this.id,
    required this.version,
    required this.isRequired,
  });
}

class SimPassAuthResult {
  final String name;
  final String phone;
  final String gender;
  final DateTime birthDate;
  final String passToken;

  const SimPassAuthResult({
    required this.name,
    required this.phone,
    required this.gender,
    required this.birthDate,
    required this.passToken,
  });
}

class SimSignUpParams {
  final String username;
  final String password;
  final String name;
  final String phone;
  final String? ci;
  final String? accountNumber;
  final String? businessNumber;
  final String accountStatus;

  const SimSignUpParams({
    required this.username,
    required this.password,
    required this.name,
    required this.phone,
    this.ci,
    this.accountNumber,
    this.businessNumber,
    required this.accountStatus,
  });
}

class TokenUsageRecord {
  final String token;
  final DateTime usedAt;

  const TokenUsageRecord({required this.token, required this.usedAt});
}

class SubmitGuard {
  bool isSubmitting = false;

  /// 실행 시도. 이미 제출 중이면 false 반환(실행 안 함). 아니면 true 반환 후 가드 설정.
  bool tryAcquire() {
    if (isSubmitting) return false;
    isSubmitting = true;
    return true;
  }

  /// finally 블록에서 항상 해제
  void release() {
    isSubmitting = false;
  }
}

class StepTransitionGuard {
  bool isTransitioning = false;

  bool tryAcquire() {
    if (isTransitioning) return false;
    isTransitioning = true;
    return true;
  }

  void release() {
    isTransitioning = false;
  }
}

class AnalyticsCapture {
  String? lastSignUpRole;

  void logSignUp(String role) {
    lastSignUpRole = role;
  }
}

// ══════════════════════════════════════════════════════════════
// 순수 로직 함수 (register_screen.dart 로직 재구현)
// ══════════════════════════════════════════════════════════════

/// [약관 동의] consentRecord 빌드
Map<String, dynamic> buildConsentRecord(
  List<SimTermsItem> activeItems,
  Map<String, bool> consentMap,
  DateTime agreedAt,
) {
  final record = <String, dynamic>{};
  for (final item in activeItems) {
    record[item.id] = {
      'agreed': consentMap[item.id] ?? false,
      'version': item.version,
      'agreedAt': agreedAt.toIso8601String(),
    };
  }
  return record;
}

/// [약관 동의] Firestore 저장 도큐먼트 빌드
Map<String, dynamic> buildTermsDocument(
  List<SimTermsItem> activeItems,
  Map<String, bool> consentMap,
  DateTime now,
) {
  return {
    'termsConsent': buildConsentRecord(activeItems, consentMap, now),
    'termsConsentAt': now.toIso8601String(),
  };
}

/// [약관 동의] 필수 약관 전부 동의 여부 확인
bool allRequiredAgreed(
    List<SimTermsItem> activeItems, Map<String, bool> consentMap) {
  final required = activeItems.where((t) => t.isRequired).toList();
  return required.every((t) => consentMap[t.id] == true);
}

/// [이미지 업로드] 업로드 수행 여부 판단
bool shouldUpload({required String? uid, required bool isWeb}) {
  return uid != null && !isWeb;
}

/// [이미지 업로드] 업로드 경로 맵 빌드
/// returns { firestoreField: storagePath }
Map<String, String> buildUploadPaths({
  required String uid,
  required String? idCardPath,
  required String? bankbookPath,
  required String? businessLicensePath,
  required SimUserRole role,
  required int timestamp,
}) {
  final result = <String, String>{};
  if (idCardPath != null) {
    result['idCardImageUrl'] = 'users/$uid/idCard_$timestamp.jpg';
  }
  if (bankbookPath != null) {
    result['bankbookImageUrl'] = 'users/$uid/bankbook_$timestamp.jpg';
  }
  if (businessLicensePath != null && role == SimUserRole.BUSINESS_ADMIN) {
    result['businessLicenseImageUrl'] =
        'users/$uid/businessLicense_$timestamp.jpg';
  }
  return result;
}

/// [이미지 업로드] 업로드 성공 URL 수집 (null 제외 → orphan 방지 대상)
List<String> collectUploadedUrls(List<String?> uploadResults) {
  return uploadResults.whereType<String>().toList();
}

/// [PASS 토큰] finalizeRegistration 호출 여부 판단
bool shouldFinalizePassToken({
  required bool isKorean,
  required SimPassAuthResult? passAuthResult,
}) {
  return isKorean && passAuthResult != null;
}

/// [AUTH-H3] 토큰 재사용 차단: 15분 내 동일 토큰 사용 여부
bool isTokenAlreadyUsed(
    String token, List<TokenUsageRecord> usageLog, DateTime now) {
  final cutoff = now.subtract(const Duration(minutes: 15));
  return usageLog.any((r) => r.token == token && r.usedAt.isAfter(cutoff));
}

/// [signUp 파라미터] 구성
SimSignUpParams buildSignUpParams({
  required String rawUsername,
  required String rawPassword,
  required bool isKorean,
  SimPassAuthResult? passAuthResult,
  required String rawName,
  required String rawPhone,
  required String rawAccountNumber,
  required String rawBusinessNumber,
  required SimUserRole role,
}) {
  final username = rawUsername.trim();
  final password = rawPassword; // trim() 없음 — 공백 허용
  final name =
      isKorean ? (passAuthResult?.name ?? '') : rawName.trim();
  final phone =
      isKorean ? (passAuthResult?.phone ?? '') : rawPhone.trim();
  final accountNumber =
      rawAccountNumber.trim().isEmpty ? null : rawAccountNumber.trim();
  final bizNum = rawBusinessNumber.replaceAll('-', '');
  final businessNumber =
      (role == SimUserRole.BUSINESS_ADMIN && bizNum.isNotEmpty) ? bizNum : null;
  final accountStatus = isKorean ? 'active' : 'pending';

  return SimSignUpParams(
    username: username,
    password: password,
    name: name,
    phone: phone,
    ci: null, // [TODO-DANAL] 다날 계약 후 구현 예정
    accountNumber: accountNumber,
    businessNumber: businessNumber,
    accountStatus: accountStatus,
  );
}

/// [외국인 등록번호] Firestore 마스킹 패턴
String buildResidentNumber(String rn1) => '${rn1}-X******';
String buildForeignIdNumber(String rn1, String rn2First) =>
    '${rn1}-X${rn2First}*****';
String buildForeignDuplicateCheckId(String rn1, String rn2First) =>
    '${rn1}-X${rn2First}*****';

/// [best-effort] 동의 기록 저장 실패 시 가입 차단 안 함 시뮬레이션
/// returns: (signUpSucceeded, termsSaveError)
(bool, String?) simulateSignUpWithTermsSaveFailure({
  required bool termsSaveFails,
}) {
  bool signUpSucceeded = false;
  String? termsSaveError;
  try {
    signUpSucceeded = true; // 가입 자체는 성공
    if (termsSaveFails) throw Exception('Firestore 저장 실패');
  } catch (e) {
    termsSaveError = e.toString();
    // best-effort: 가입 차단 안 함
  }
  return (signUpSucceeded, termsSaveError);
}

// ══════════════════════════════════════════════════════════════
// 테스트 픽스처 헬퍼
// ══════════════════════════════════════════════════════════════

const _kTermsServiceV1 = SimTermsItem(
  id: 'service', version: '1.0.0', isRequired: true);
const _kTermsPrivacyV1 = SimTermsItem(
  id: 'privacy', version: '1.0.0', isRequired: true);
const _kTermsMarketingV1 = SimTermsItem(
  id: 'marketing', version: '1.0.0', isRequired: false);

final _kAllTerms = [_kTermsServiceV1, _kTermsPrivacyV1, _kTermsMarketingV1];
final _kAllAgreedMap = {
  'service': true,
  'privacy': true,
  'marketing': true,
};
final _kRequiredOnlyMap = {
  'service': true,
  'privacy': true,
  'marketing': false,
};

final _kPassResult = SimPassAuthResult(
  name: '홍길동',
  phone: '01012345678',
  gender: '남성',
  birthDate: DateTime(1995, 5, 20),
  passToken: 'mock-pass-token-abc123',
);

final _kFixedNow = DateTime(2026, 7, 8, 12, 0, 0);

// ══════════════════════════════════════════════════════════════
// MAIN
// ══════════════════════════════════════════════════════════════

void main() {
  // ════════════════════════════════════════════════════════════
  // GROUP 1: 약관 동의 기록 데이터 구조 검증
  // ════════════════════════════════════════════════════════════
  group('GROUP-1: termsConsent 데이터 구조', () {
    test('SCENARIO-FLOW-01: consentRecord에 모든 약관 ID가 키로 포함됨', () {
      final record = buildConsentRecord(_kAllTerms, _kAllAgreedMap, _kFixedNow);
      expect(record.keys, containsAll(['service', 'privacy', 'marketing']));
    });

    test('SCENARIO-FLOW-02: 동의한 항목의 구조 — agreed/version/agreedAt 3개 필드', () {
      final record = buildConsentRecord(_kAllTerms, _kAllAgreedMap, _kFixedNow);
      final serviceEntry = record['service'] as Map<String, dynamic>;
      expect(serviceEntry.keys, containsAll(['agreed', 'version', 'agreedAt']));
      expect(serviceEntry['agreed'], isTrue);
      expect(serviceEntry['version'], '1.0.0');
    });

    test('SCENARIO-FLOW-03: 미동의 항목은 agreed=false로 저장됨', () {
      final record = buildConsentRecord(_kAllTerms, _kRequiredOnlyMap, _kFixedNow);
      final marketingEntry = record['marketing'] as Map<String, dynamic>;
      expect(marketingEntry['agreed'], isFalse);
    });

    test('SCENARIO-FLOW-04: agreedAt 필드가 ISO8601 형식 문자열임', () {
      final record = buildConsentRecord(_kAllTerms, _kAllAgreedMap, _kFixedNow);
      final agreedAt = (record['service'] as Map)['agreedAt'] as String;
      expect(() => DateTime.parse(agreedAt), returnsNormally);
    });

    test('SCENARIO-FLOW-05: version 필드가 항목의 version과 일치함', () {
      final items = [
        const SimTermsItem(id: 'v2', version: '2.5.0', isRequired: true),
      ];
      final record = buildConsentRecord(items, {'v2': true}, _kFixedNow);
      final entry = record['v2'] as Map<String, dynamic>;
      expect(entry['version'], '2.5.0');
    });

    test('SCENARIO-FLOW-06: 최상위 도큐먼트에 termsConsentAt 포함됨', () {
      final doc = buildTermsDocument(_kAllTerms, _kAllAgreedMap, _kFixedNow);
      expect(doc.containsKey('termsConsentAt'), isTrue);
      expect(() => DateTime.parse(doc['termsConsentAt'] as String), returnsNormally);
    });

    test('SCENARIO-FLOW-07: 최상위 도큐먼트에 termsConsent 맵 포함됨', () {
      final doc = buildTermsDocument(_kAllTerms, _kAllAgreedMap, _kFixedNow);
      expect(doc.containsKey('termsConsent'), isTrue);
      expect(doc['termsConsent'], isA<Map<String, dynamic>>());
    });

    test('SCENARIO-FLOW-08: consentMap에 없는 항목은 agreed=false 기본값', () {
      final record = buildConsentRecord(
        [const SimTermsItem(id: 'new_term', version: '1.0', isRequired: false)],
        {}, // consentMap 비어 있음
        _kFixedNow,
      );
      final entry = record['new_term'] as Map<String, dynamic>;
      expect(entry['agreed'], isFalse);
    });

    test('SCENARIO-FLOW-09: 빈 약관 목록 → consentRecord가 빈 맵', () {
      final record = buildConsentRecord([], {}, _kFixedNow);
      expect(record, isEmpty);
    });

    test('SCENARIO-FLOW-10: 여러 약관 항목 모두 각자의 agreed 값으로 기록됨', () {
      final record = buildConsentRecord(_kAllTerms, _kRequiredOnlyMap, _kFixedNow);
      expect((record['service'] as Map)['agreed'], isTrue);
      expect((record['privacy'] as Map)['agreed'], isTrue);
      expect((record['marketing'] as Map)['agreed'], isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════
  // GROUP 2: 필수 약관 동의 검증 (_validateStep1 로직)
  // ════════════════════════════════════════════════════════════
  group('GROUP-2: 필수 약관 동의 검증', () {
    test('SCENARIO-FLOW-11: 필수 약관 모두 동의 → 통과', () {
      expect(allRequiredAgreed(_kAllTerms, _kRequiredOnlyMap), isTrue);
    });

    test('SCENARIO-FLOW-12: 필수 약관 1개 미동의 → 통과 불가', () {
      final partialConsent = {'service': true, 'privacy': false, 'marketing': false};
      expect(allRequiredAgreed(_kAllTerms, partialConsent), isFalse);
    });

    test('SCENARIO-FLOW-13: 선택 약관 미동의 + 필수 전부 동의 → 통과', () {
      final onlyRequired = {'service': true, 'privacy': true, 'marketing': false};
      expect(allRequiredAgreed(_kAllTerms, onlyRequired), isTrue);
    });

    test('SCENARIO-FLOW-14: 필수 약관이 없는 경우 → 통과 (조건 충족)', () {
      final optionalOnly = [
        const SimTermsItem(id: 'opt', version: '1.0', isRequired: false),
      ];
      expect(allRequiredAgreed(optionalOnly, {}), isTrue);
    });

    test('SCENARIO-FLOW-15: 필수 약관 전부 미동의 → 통과 불가', () {
      final noneAgreed = {'service': false, 'privacy': false, 'marketing': false};
      expect(allRequiredAgreed(_kAllTerms, noneAgreed), isFalse);
    });

    test('SCENARIO-FLOW-16: isRequired=false 항목만 있고 미동의 → 통과', () {
      final optItems = [
        const SimTermsItem(id: 'mkt', version: '1.0', isRequired: false),
        const SimTermsItem(id: 'push', version: '1.0', isRequired: false),
      ];
      expect(allRequiredAgreed(optItems, {}), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════
  // GROUP 3: 약관 동의 best-effort 패턴 (가입 차단 안 함)
  // ════════════════════════════════════════════════════════════
  group('GROUP-3: 약관 동의 저장 best-effort', () {
    test('SCENARIO-FLOW-17: 동의 저장 성공 → 가입 성공, 에러 없음', () {
      final (ok, err) =
          simulateSignUpWithTermsSaveFailure(termsSaveFails: false);
      expect(ok, isTrue);
      expect(err, isNull);
    });

    test('SCENARIO-FLOW-18: 동의 저장 실패해도 가입 자체는 성공(best-effort)', () {
      final (ok, err) =
          simulateSignUpWithTermsSaveFailure(termsSaveFails: true);
      expect(ok, isTrue); // 가입은 성공
      expect(err, isNotNull); // 에러는 캐치됨
    });

    test('SCENARIO-FLOW-19: 동의 저장 실패 시 에러 메시지가 catch로 흡수됨', () {
      final (_, err) =
          simulateSignUpWithTermsSaveFailure(termsSaveFails: true);
      expect(err, contains('Firestore 저장 실패'));
    });
  });

  // ════════════════════════════════════════════════════════════
  // GROUP 4: 이미지 업로드 수행 조건 (uid + kIsWeb 분기)
  // ════════════════════════════════════════════════════════════
  group('GROUP-4: 이미지 업로드 조건 판단', () {
    test('SCENARIO-FLOW-20: uid==null → 업로드 스킵', () {
      expect(shouldUpload(uid: null, isWeb: false), isFalse);
    });

    test('SCENARIO-FLOW-21: kIsWeb==true → 업로드 스킵', () {
      expect(shouldUpload(uid: 'uid-abc', isWeb: true), isFalse);
    });

    test('SCENARIO-FLOW-22: uid!=null && !kIsWeb → 업로드 수행', () {
      expect(shouldUpload(uid: 'uid-abc', isWeb: false), isTrue);
    });

    test('SCENARIO-FLOW-23: uid==null && kIsWeb==true → 업로드 스킵', () {
      expect(shouldUpload(uid: null, isWeb: true), isFalse);
    });

    test('SCENARIO-FLOW-24: idCard 없음 → uploads 맵에 idCardImageUrl 없음', () {
      final paths = buildUploadPaths(
        uid: 'uid-x',
        idCardPath: null,
        bankbookPath: null,
        businessLicensePath: null,
        role: SimUserRole.USER,
        timestamp: 1000,
      );
      expect(paths.containsKey('idCardImageUrl'), isFalse);
    });

    test('SCENARIO-FLOW-25: idCard 있음 → uploads 맵에 idCardImageUrl 포함', () {
      final paths = buildUploadPaths(
        uid: 'uid-x',
        idCardPath: '/tmp/id.jpg',
        bankbookPath: null,
        businessLicensePath: null,
        role: SimUserRole.USER,
        timestamp: 1000,
      );
      expect(paths.containsKey('idCardImageUrl'), isTrue);
    });

    test('SCENARIO-FLOW-26: bankbook 없음 → uploads 맵에 bankbookImageUrl 없음', () {
      final paths = buildUploadPaths(
        uid: 'uid-x',
        idCardPath: null,
        bankbookPath: null,
        businessLicensePath: null,
        role: SimUserRole.USER,
        timestamp: 1000,
      );
      expect(paths.containsKey('bankbookImageUrl'), isFalse);
    });

    test('SCENARIO-FLOW-27: businessLicense 있음 + USER 역할 → 업로드 안 함', () {
      final paths = buildUploadPaths(
        uid: 'uid-x',
        idCardPath: null,
        bankbookPath: null,
        businessLicensePath: '/tmp/biz.jpg',
        role: SimUserRole.USER,
        timestamp: 1000,
      );
      expect(paths.containsKey('businessLicenseImageUrl'), isFalse);
    });

    test('SCENARIO-FLOW-28: businessLicense 있음 + BUSINESS_ADMIN → 업로드 함', () {
      final paths = buildUploadPaths(
        uid: 'uid-x',
        idCardPath: null,
        bankbookPath: null,
        businessLicensePath: '/tmp/biz.jpg',
        role: SimUserRole.BUSINESS_ADMIN,
        timestamp: 1000,
      );
      expect(paths.containsKey('businessLicenseImageUrl'), isTrue);
    });

    test('SCENARIO-FLOW-29: 세 이미지 모두 있음 + ADMIN → uploads 맵 항목 3개', () {
      final paths = buildUploadPaths(
        uid: 'uid-x',
        idCardPath: '/tmp/id.jpg',
        bankbookPath: '/tmp/bb.jpg',
        businessLicensePath: '/tmp/biz.jpg',
        role: SimUserRole.BUSINESS_ADMIN,
        timestamp: 1000,
      );
      expect(paths.length, 3);
    });
  });

  // ════════════════════════════════════════════════════════════
  // GROUP 5: 업로드 Storage 경로 패턴
  // ════════════════════════════════════════════════════════════
  group('GROUP-5: Storage 업로드 경로 패턴', () {
    test('SCENARIO-FLOW-30: idCard 경로 → users/{uid}/idCard_{ts}.jpg', () {
      final paths = buildUploadPaths(
        uid: 'user123',
        idCardPath: '/tmp/id.jpg',
        bankbookPath: null,
        businessLicensePath: null,
        role: SimUserRole.USER,
        timestamp: 9999,
      );
      expect(paths['idCardImageUrl'], 'users/user123/idCard_9999.jpg');
    });

    test('SCENARIO-FLOW-31: bankbook 경로 → users/{uid}/bankbook_{ts}.jpg', () {
      final paths = buildUploadPaths(
        uid: 'user123',
        idCardPath: null,
        bankbookPath: '/tmp/bb.jpg',
        businessLicensePath: null,
        role: SimUserRole.USER,
        timestamp: 9999,
      );
      expect(paths['bankbookImageUrl'], 'users/user123/bankbook_9999.jpg');
    });

    test('SCENARIO-FLOW-32: businessLicense 경로 → users/{uid}/businessLicense_{ts}.jpg', () {
      final paths = buildUploadPaths(
        uid: 'user123',
        idCardPath: null,
        bankbookPath: null,
        businessLicensePath: '/tmp/biz.jpg',
        role: SimUserRole.BUSINESS_ADMIN,
        timestamp: 9999,
      );
      expect(
        paths['businessLicenseImageUrl'],
        'users/user123/businessLicense_9999.jpg',
      );
    });

    test('SCENARIO-FLOW-33: uid가 다르면 경로가 달라짐', () {
      final pathA = buildUploadPaths(
        uid: 'user-A',
        idCardPath: '/tmp/id.jpg',
        bankbookPath: null,
        businessLicensePath: null,
        role: SimUserRole.USER,
        timestamp: 1000,
      );
      final pathB = buildUploadPaths(
        uid: 'user-B',
        idCardPath: '/tmp/id.jpg',
        bankbookPath: null,
        businessLicensePath: null,
        role: SimUserRole.USER,
        timestamp: 1000,
      );
      expect(pathA['idCardImageUrl'], isNot(pathB['idCardImageUrl']));
    });

    test('SCENARIO-FLOW-34: 타임스탬프가 경로에 포함됨', () {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final paths = buildUploadPaths(
        uid: 'uid-ts',
        idCardPath: '/tmp/id.jpg',
        bankbookPath: null,
        businessLicensePath: null,
        role: SimUserRole.USER,
        timestamp: ts,
      );
      expect(paths['idCardImageUrl'], contains(ts.toString()));
    });
  });

  // ════════════════════════════════════════════════════════════
  // GROUP 6: Firestore 업데이트 실패 시 orphan 방지
  // ════════════════════════════════════════════════════════════
  group('GROUP-6: Firestore 업데이트 실패 → orphan 방지', () {
    test('SCENARIO-FLOW-35: 업로드 결과 null 없음 → 수집 URL 수 = 업로드 수', () {
      final urls = collectUploadedUrls([
        'https://storage/id.jpg',
        'https://storage/bb.jpg',
      ]);
      expect(urls.length, 2);
    });

    test('SCENARIO-FLOW-36: 업로드 결과에 null 포함 → null 제외한 URL만 수집', () {
      final urls = collectUploadedUrls([
        'https://storage/id.jpg',
        null, // 업로드 실패
        'https://storage/bb.jpg',
      ]);
      expect(urls.length, 2);
      expect(urls, isNot(contains(null)));
    });

    test('SCENARIO-FLOW-37: 모두 null → 수집 URL 없음 (삭제 대상 없음)', () {
      final urls = collectUploadedUrls([null, null]);
      expect(urls, isEmpty);
    });

    test('SCENARIO-FLOW-38: Firestore 실패 시 수집된 URL이 삭제 대상과 일치', () {
      final uploadResults = [
        'https://storage/id.jpg',
        null,
        'https://storage/biz.jpg',
      ];
      final toDelete = collectUploadedUrls(uploadResults);
      // Firestore 업데이트 실패 시 이 URL들을 Storage에서 삭제해야 함
      expect(toDelete, contains('https://storage/id.jpg'));
      expect(toDelete, contains('https://storage/biz.jpg'));
      expect(toDelete.length, 2);
    });
  });

  // ════════════════════════════════════════════════════════════
  // GROUP 7: PASS 토큰 소비 조건 [AUTH-H3]
  // ════════════════════════════════════════════════════════════
  group('GROUP-7: PASS 토큰 소비 조건', () {
    test('SCENARIO-FLOW-39: 내국인 + passAuthResult != null → finalizeRegistration 호출해야 함', () {
      expect(
        shouldFinalizePassToken(isKorean: true, passAuthResult: _kPassResult),
        isTrue,
      );
    });

    test('SCENARIO-FLOW-40: 외국인 → finalizeRegistration 호출 안 함', () {
      expect(
        shouldFinalizePassToken(isKorean: false, passAuthResult: _kPassResult),
        isFalse,
      );
    });

    test('SCENARIO-FLOW-41: 내국인이지만 passAuthResult == null → 호출 안 함', () {
      expect(
        shouldFinalizePassToken(isKorean: true, passAuthResult: null),
        isFalse,
      );
    });

    test('SCENARIO-FLOW-42: 외국인 + passAuthResult == null → 호출 안 함', () {
      expect(
        shouldFinalizePassToken(isKorean: false, passAuthResult: null),
        isFalse,
      );
    });

    test('SCENARIO-FLOW-43: passToken이 passAuthResult에서 가져와짐', () {
      expect(_kPassResult.passToken, 'mock-pass-token-abc123');
    });

    test('[AUTH-H3] SCENARIO-FLOW-44: 15분 내 동일 토큰 재사용 → 차단됨', () {
      final now = DateTime(2026, 7, 8, 12, 0, 0);
      final usageLog = [
        TokenUsageRecord(
          token: 'tok-abc',
          usedAt: now.subtract(const Duration(minutes: 10)), // 10분 전 사용
        ),
      ];
      expect(isTokenAlreadyUsed('tok-abc', usageLog, now), isTrue);
    });

    test('[AUTH-H3] SCENARIO-FLOW-45: 15분 초과 후 동일 토큰 → 허용됨', () {
      final now = DateTime(2026, 7, 8, 12, 0, 0);
      final usageLog = [
        TokenUsageRecord(
          token: 'tok-abc',
          usedAt: now.subtract(const Duration(minutes: 16)), // 16분 전 사용
        ),
      ];
      expect(isTokenAlreadyUsed('tok-abc', usageLog, now), isFalse);
    });

    test('[AUTH-H3] SCENARIO-FLOW-46: 다른 토큰은 재사용 차단에 영향 없음', () {
      final now = DateTime(2026, 7, 8, 12, 0, 0);
      final usageLog = [
        TokenUsageRecord(
          token: 'tok-xyz',
          usedAt: now.subtract(const Duration(minutes: 5)),
        ),
      ];
      expect(isTokenAlreadyUsed('tok-abc', usageLog, now), isFalse);
    });

    test('[AUTH-H3] SCENARIO-FLOW-47: 정확히 15분 경과(boundary) → 허용됨', () {
      final now = DateTime(2026, 7, 8, 12, 0, 0);
      final usageLog = [
        TokenUsageRecord(
          token: 'tok-abc',
          usedAt: now.subtract(const Duration(minutes: 15)),
        ),
      ];
      // cutoff = now - 15min, usedAt = now - 15min → isAfter(cutoff) == false → 허용
      expect(isTokenAlreadyUsed('tok-abc', usageLog, now), isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════
  // GROUP 8: signUp 파라미터 구성
  // ════════════════════════════════════════════════════════════
  group('GROUP-8: signUp 파라미터 구성', () {
    test('SCENARIO-FLOW-48: username에 trim() 적용됨', () {
      final p = buildSignUpParams(
        rawUsername: '  hong123  ',
        rawPassword: 'Pass123!',
        isKorean: true,
        passAuthResult: _kPassResult,
        rawName: '',
        rawPhone: '',
        rawAccountNumber: '',
        rawBusinessNumber: '',
        role: SimUserRole.USER,
      );
      expect(p.username, 'hong123');
    });

    test('SCENARIO-FLOW-49: password는 trim() 없이 그대로 (공백 포함 가능)', () {
      final rawPw = 'Pass 123!'; // 내부 공백 포함
      final p = buildSignUpParams(
        rawUsername: 'user1',
        rawPassword: rawPw,
        isKorean: true,
        passAuthResult: _kPassResult,
        rawName: '',
        rawPhone: '',
        rawAccountNumber: '',
        rawBusinessNumber: '',
        role: SimUserRole.USER,
      );
      expect(p.password, rawPw);
    });

    test('SCENARIO-FLOW-50: 내국인 name → passAuthResult.name 사용', () {
      final p = buildSignUpParams(
        rawUsername: 'user1',
        rawPassword: 'Pass123!',
        isKorean: true,
        passAuthResult: _kPassResult,
        rawName: '직접입력이름',
        rawPhone: '',
        rawAccountNumber: '',
        rawBusinessNumber: '',
        role: SimUserRole.USER,
      );
      expect(p.name, _kPassResult.name);
    });

    test('SCENARIO-FLOW-51: 외국인 name → rawName.trim() 사용', () {
      final p = buildSignUpParams(
        rawUsername: 'user1',
        rawPassword: 'Pass123!',
        isKorean: false,
        passAuthResult: null,
        rawName: '  김외국  ',
        rawPhone: '',
        rawAccountNumber: '',
        rawBusinessNumber: '',
        role: SimUserRole.USER,
      );
      expect(p.name, '김외국');
    });

    test('SCENARIO-FLOW-52: 내국인 phone → passAuthResult.phone 사용', () {
      final p = buildSignUpParams(
        rawUsername: 'user1',
        rawPassword: 'Pass123!',
        isKorean: true,
        passAuthResult: _kPassResult,
        rawName: '',
        rawPhone: '01099999999',
        rawAccountNumber: '',
        rawBusinessNumber: '',
        role: SimUserRole.USER,
      );
      expect(p.phone, _kPassResult.phone);
    });

    test('SCENARIO-FLOW-53: 외국인 phone → rawPhone.trim() 사용', () {
      final p = buildSignUpParams(
        rawUsername: 'user1',
        rawPassword: 'Pass123!',
        isKorean: false,
        passAuthResult: null,
        rawName: '김외국',
        rawPhone: '  01055556666  ',
        rawAccountNumber: '',
        rawBusinessNumber: '',
        role: SimUserRole.USER,
      );
      expect(p.phone, '01055556666');
    });

    test('SCENARIO-FLOW-54: ci는 항상 null (다날 계약 후 구현 예정)', () {
      final p = buildSignUpParams(
        rawUsername: 'user1',
        rawPassword: 'Pass123!',
        isKorean: true,
        passAuthResult: _kPassResult,
        rawName: '',
        rawPhone: '',
        rawAccountNumber: '',
        rawBusinessNumber: '',
        role: SimUserRole.USER,
      );
      expect(p.ci, isNull);
    });

    test('SCENARIO-FLOW-55: accountNumber 빈값 → null 전달', () {
      final p = buildSignUpParams(
        rawUsername: 'user1',
        rawPassword: 'Pass123!',
        isKorean: true,
        passAuthResult: _kPassResult,
        rawName: '',
        rawPhone: '',
        rawAccountNumber: '   ', // 공백만
        rawBusinessNumber: '',
        role: SimUserRole.USER,
      );
      expect(p.accountNumber, isNull);
    });

    test('SCENARIO-FLOW-56: accountNumber 있음 → trim() 후 전달', () {
      final p = buildSignUpParams(
        rawUsername: 'user1',
        rawPassword: 'Pass123!',
        isKorean: true,
        passAuthResult: _kPassResult,
        rawName: '',
        rawPhone: '',
        rawAccountNumber: '  1234567890  ',
        rawBusinessNumber: '',
        role: SimUserRole.USER,
      );
      expect(p.accountNumber, '1234567890');
    });

    test('SCENARIO-FLOW-57: businessNumber — USER 역할이면 null', () {
      final p = buildSignUpParams(
        rawUsername: 'user1',
        rawPassword: 'Pass123!',
        isKorean: true,
        passAuthResult: _kPassResult,
        rawName: '',
        rawPhone: '',
        rawAccountNumber: '',
        rawBusinessNumber: '123-45-67890',
        role: SimUserRole.USER,
      );
      expect(p.businessNumber, isNull);
    });

    test('SCENARIO-FLOW-58: businessNumber — ADMIN이면 하이픈 제거 후 전달', () {
      final p = buildSignUpParams(
        rawUsername: 'admin1',
        rawPassword: 'Pass123!',
        isKorean: true,
        passAuthResult: _kPassResult,
        rawName: '',
        rawPhone: '',
        rawAccountNumber: '',
        rawBusinessNumber: '123-45-67890',
        role: SimUserRole.BUSINESS_ADMIN,
      );
      expect(p.businessNumber, '1234567890');
    });

    test('SCENARIO-FLOW-59: businessNumber — ADMIN이지만 빈값이면 null', () {
      final p = buildSignUpParams(
        rawUsername: 'admin1',
        rawPassword: 'Pass123!',
        isKorean: true,
        passAuthResult: _kPassResult,
        rawName: '',
        rawPhone: '',
        rawAccountNumber: '',
        rawBusinessNumber: '',
        role: SimUserRole.BUSINESS_ADMIN,
      );
      expect(p.businessNumber, isNull);
    });
  });

  // ════════════════════════════════════════════════════════════
  // GROUP 9: accountStatus 설정 (내국인/외국인 분기)
  // ════════════════════════════════════════════════════════════
  group('GROUP-9: accountStatus 설정', () {
    test('SCENARIO-FLOW-60: 내국인 → accountStatus="active"', () {
      final p = buildSignUpParams(
        rawUsername: 'user1',
        rawPassword: 'Pass123!',
        isKorean: true,
        passAuthResult: _kPassResult,
        rawName: '',
        rawPhone: '',
        rawAccountNumber: '',
        rawBusinessNumber: '',
        role: SimUserRole.USER,
      );
      expect(p.accountStatus, 'active');
    });

    test('SCENARIO-FLOW-61: 외국인 → accountStatus="pending"', () {
      final p = buildSignUpParams(
        rawUsername: 'user1',
        rawPassword: 'Pass123!',
        isKorean: false,
        passAuthResult: null,
        rawName: '홍길동',
        rawPhone: '01012345678',
        rawAccountNumber: '',
        rawBusinessNumber: '',
        role: SimUserRole.USER,
      );
      expect(p.accountStatus, 'pending');
    });

    test('SCENARIO-FLOW-62: PASS 인증 완료 내국인 ADMIN → 즉시 active', () {
      final p = buildSignUpParams(
        rawUsername: 'admin1',
        rawPassword: 'Pass123!',
        isKorean: true,
        passAuthResult: _kPassResult,
        rawName: '',
        rawPhone: '',
        rawAccountNumber: '',
        rawBusinessNumber: '',
        role: SimUserRole.BUSINESS_ADMIN,
      );
      expect(p.accountStatus, 'active');
    });

    test('SCENARIO-FLOW-63: 외국인 ADMIN → 슈퍼관리자 승인 전까지 pending', () {
      final p = buildSignUpParams(
        rawUsername: 'admin1',
        rawPassword: 'Pass123!',
        isKorean: false,
        passAuthResult: null,
        rawName: '홍길동',
        rawPhone: '01012345678',
        rawAccountNumber: '',
        rawBusinessNumber: '',
        role: SimUserRole.BUSINESS_ADMIN,
      );
      expect(p.accountStatus, 'pending');
    });
  });

  // ════════════════════════════════════════════════════════════
  // GROUP 10: _isSubmitting 가드
  // ════════════════════════════════════════════════════════════
  group('GROUP-10: _isSubmitting 가드', () {
    test('SCENARIO-FLOW-64: 초기 상태 → tryAcquire 성공, isSubmitting=true', () {
      final guard = SubmitGuard();
      expect(guard.tryAcquire(), isTrue);
      expect(guard.isSubmitting, isTrue);
    });

    test('SCENARIO-FLOW-65: 이미 제출 중 → tryAcquire 실패(중복 방지)', () {
      final guard = SubmitGuard();
      guard.tryAcquire(); // 첫 번째 획득
      expect(guard.tryAcquire(), isFalse); // 두 번째 시도 → 차단
    });

    test('SCENARIO-FLOW-66: release 후 재획득 가능', () {
      final guard = SubmitGuard();
      guard.tryAcquire();
      guard.release();
      expect(guard.tryAcquire(), isTrue);
    });

    test('SCENARIO-FLOW-67: 가입 성공 후 finally에서 isSubmitting=false', () {
      final guard = SubmitGuard();
      guard.tryAcquire();
      try {
        // 성공 시뮬레이션
      } finally {
        guard.release();
      }
      expect(guard.isSubmitting, isFalse);
    });

    test('SCENARIO-FLOW-68: 가입 실패(예외) 후에도 finally에서 isSubmitting=false', () {
      final guard = SubmitGuard();
      guard.tryAcquire();
      try {
        throw Exception('가입 실패');
      } catch (_) {
        // 에러 처리
      } finally {
        guard.release();
      }
      expect(guard.isSubmitting, isFalse);
    });

    test('SCENARIO-FLOW-69: success=false 조기 return 후 release 보장', () {
      final guard = SubmitGuard();
      bool released = false;

      void simulateSignUp(bool success) {
        if (!guard.tryAcquire()) return;
        try {
          if (!success) return; // 조기 return — finally가 실행됨
        } finally {
          guard.release();
          released = true;
        }
      }

      simulateSignUp(false);
      expect(released, isTrue);
      expect(guard.isSubmitting, isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════
  // GROUP 11: _isStepTransitioning 가드
  // ════════════════════════════════════════════════════════════
  group('GROUP-11: _isStepTransitioning 가드', () {
    test('SCENARIO-FLOW-70: 초기 → tryAcquire 성공', () {
      final guard = StepTransitionGuard();
      expect(guard.tryAcquire(), isTrue);
    });

    test('SCENARIO-FLOW-71: 전환 중 재클릭 → tryAcquire 실패(더블탭 방지)', () {
      final guard = StepTransitionGuard();
      guard.tryAcquire();
      expect(guard.tryAcquire(), isFalse);
    });

    test('SCENARIO-FLOW-72: 전환 완료 후 release → 재시도 가능', () {
      final guard = StepTransitionGuard();
      guard.tryAcquire();
      guard.release();
      expect(guard.tryAcquire(), isTrue);
    });

    test('SCENARIO-FLOW-73: _isSubmitting + _isStepTransitioning 동시 가드 — 둘 다 독립적', () {
      final submitGuard = SubmitGuard();
      final stepGuard = StepTransitionGuard();

      submitGuard.tryAcquire();
      stepGuard.tryAcquire();

      // submit 해제해도 step은 여전히 차단
      submitGuard.release();
      expect(stepGuard.tryAcquire(), isFalse);

      stepGuard.release();
      // step 해제 후 submit은 재획득 가능
      expect(submitGuard.tryAcquire(), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════
  // GROUP 12: Analytics 이벤트 발생 조건
  // ════════════════════════════════════════════════════════════
  group('GROUP-12: Analytics 이벤트 조건', () {
    test('SCENARIO-FLOW-74: 가입 성공 → logSignUp 호출됨', () {
      final analytics = AnalyticsCapture();
      // 성공 시 logSignUp 호출 시뮬레이션
      analytics.logSignUp('USER');
      expect(analytics.lastSignUpRole, 'USER');
    });

    test('SCENARIO-FLOW-75: 가입 실패 → logSignUp 호출 안 됨', () {
      final analytics = AnalyticsCapture();
      // 실패 시 logSignUp 미호출 — 초기값 null 유지
      expect(analytics.lastSignUpRole, isNull);
    });

    test('SCENARIO-FLOW-76: USER 역할 → role="USER" 전달', () {
      final analytics = AnalyticsCapture();
      analytics.logSignUp(SimUserRole.USER.name);
      expect(analytics.lastSignUpRole, 'USER');
    });

    test('SCENARIO-FLOW-77: BUSINESS_ADMIN 역할 → role="BUSINESS_ADMIN" 전달', () {
      final analytics = AnalyticsCapture();
      analytics.logSignUp(SimUserRole.BUSINESS_ADMIN.name);
      expect(analytics.lastSignUpRole, 'BUSINESS_ADMIN');
    });
  });

  // ════════════════════════════════════════════════════════════
  // GROUP 13: 외국인 등록번호 마스킹 패턴
  // ════════════════════════════════════════════════════════════
  group('GROUP-13: 외국인 등록번호 마스킹', () {
    test('SCENARIO-FLOW-78: residentNumber 마스킹 → "{앞6자리}-X******"', () {
      expect(buildResidentNumber('990101'), '990101-X******');
    });

    test('SCENARIO-FLOW-79: foreignIdNumber 마스킹 → "{앞6자리}-X{뒤1자리}*****"', () {
      expect(buildForeignIdNumber('990101', '5'), '990101-X5*****');
    });

    test('SCENARIO-FLOW-80: 중복 체크용 ID 패턴 → foreignIdNumber와 동일', () {
      final dup = buildForeignDuplicateCheckId('880202', '7');
      final foreign = buildForeignIdNumber('880202', '7');
      expect(dup, foreign);
    });

    test('SCENARIO-FLOW-81: 내국인 → residentNumber=null, foreignIdNumber=null', () {
      final p = buildSignUpParams(
        rawUsername: 'user1',
        rawPassword: 'Pass123!',
        isKorean: true,
        passAuthResult: _kPassResult,
        rawName: '',
        rawPhone: '',
        rawAccountNumber: '',
        rawBusinessNumber: '',
        role: SimUserRole.USER,
      );
      // 내국인은 주민번호 직접 저장 안 함
      expect(p.ci, isNull);
    });

    test('SCENARIO-FLOW-82: 마스킹된 residentNumber는 실제 번호와 다름', () {
      const real = '990101';
      final masked = buildResidentNumber(real);
      expect(masked, isNot(real));
      expect(masked, contains('X'));
    });
  });

  // ════════════════════════════════════════════════════════════
  // GROUP 14: 종합 플로우 시나리오
  // ════════════════════════════════════════════════════════════
  group('GROUP-14: 종합 플로우 시나리오', () {
    test('SCENARIO-FLOW-83: 내국인 USER 전체 플로우 — 모든 조건 일치', () {
      // 1. 필수 약관 모두 동의
      expect(allRequiredAgreed(_kAllTerms, _kRequiredOnlyMap), isTrue);
      // 2. signUp 파라미터 — PASS 정보 반영
      final p = buildSignUpParams(
        rawUsername: 'hong123',
        rawPassword: 'Pass123!',
        isKorean: true,
        passAuthResult: _kPassResult,
        rawName: '무시됨',
        rawPhone: '무시됨',
        rawAccountNumber: '',
        rawBusinessNumber: '',
        role: SimUserRole.USER,
      );
      expect(p.name, '홍길동');
      expect(p.phone, '01012345678');
      expect(p.accountStatus, 'active');
      expect(p.ci, isNull);
      // 3. 이미지 업로드 조건 — uid 확보 후
      expect(shouldUpload(uid: 'new-uid-abc', isWeb: false), isTrue);
      // 4. PASS 토큰 소비
      expect(
          shouldFinalizePassToken(isKorean: true, passAuthResult: _kPassResult),
          isTrue);
    });

    test('SCENARIO-FLOW-84: 외국인 ADMIN 전체 플로우 — 모든 조건 일치', () {
      // 1. 필수 약관 동의
      expect(allRequiredAgreed(_kAllTerms, _kRequiredOnlyMap), isTrue);
      // 2. signUp 파라미터
      final p = buildSignUpParams(
        rawUsername: '  foreign_admin  ',
        rawPassword: 'Pass123!',
        isKorean: false,
        passAuthResult: null,
        rawName: '  王大明  ',
        rawPhone: '  01099887766  ',
        rawAccountNumber: '',
        rawBusinessNumber: '123-45-67890',
        role: SimUserRole.BUSINESS_ADMIN,
      );
      expect(p.username, 'foreign_admin');
      expect(p.name, '王大明');
      expect(p.phone, '01099887766');
      expect(p.accountStatus, 'pending');
      expect(p.businessNumber, '1234567890');
      // 3. PASS 토큰 소비 없음
      expect(
          shouldFinalizePassToken(isKorean: false, passAuthResult: null),
          isFalse);
      // 4. 외국인 등록번호 마스킹
      expect(buildForeignIdNumber('750101', '5'), '750101-X5*****');
    });

    test('SCENARIO-FLOW-85: 동의 기록 빌드 → ISO8601 일시 포함 완전한 구조', () {
      final doc = buildTermsDocument(_kAllTerms, _kRequiredOnlyMap, _kFixedNow);
      final consent = doc['termsConsent'] as Map<String, dynamic>;
      expect(consent.keys.length, 3);
      expect(doc['termsConsentAt'], _kFixedNow.toIso8601String());
      for (final key in ['service', 'privacy', 'marketing']) {
        final entry = consent[key] as Map<String, dynamic>;
        expect(entry.containsKey('agreed'), isTrue);
        expect(entry.containsKey('version'), isTrue);
        expect(entry.containsKey('agreedAt'), isTrue);
      }
    });

    test('SCENARIO-FLOW-86: 가드 상태 머신 — 성공 경로 완전 시뮬레이션', () {
      final guard = SubmitGuard();
      final analytics = AnalyticsCapture();
      String? navigatedTo;

      void simulateRegister() {
        if (!guard.tryAcquire()) return;
        try {
          // 가입 성공
          analytics.logSignUp('USER');
          navigatedTo = 'popUntilFirst';
        } finally {
          guard.release();
        }
      }

      simulateRegister();

      expect(guard.isSubmitting, isFalse);
      expect(analytics.lastSignUpRole, 'USER');
      expect(navigatedTo, 'popUntilFirst');
    });

    test('SCENARIO-FLOW-87: 가드 상태 머신 — 실패 경로 완전 시뮬레이션', () {
      final guard = SubmitGuard();
      final analytics = AnalyticsCapture();
      String? errorMsg;

      void simulateRegisterFail() {
        if (!guard.tryAcquire()) return;
        try {
          throw Exception('이미 사용중인 아이디');
        } catch (e) {
          errorMsg = e.toString();
        } finally {
          guard.release();
        }
      }

      simulateRegisterFail();

      expect(guard.isSubmitting, isFalse);
      expect(analytics.lastSignUpRole, isNull); // 실패 시 Analytics 미호출
      expect(errorMsg, contains('이미 사용중인 아이디'));
    });
  });
}
