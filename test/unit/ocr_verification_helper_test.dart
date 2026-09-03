// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/ocr_verification_helper.dart';

// OcrVerificationHelper Production Verification Logic 단위 테스트
//
// ══════════════════════════════════════════════════════════════
// CALL GRAPH (모든 테스트에 동일하게 적용)
// ══════════════════════════════════════════════════════════════
//
//   TEST FIXTURE (synthetic raw OCR text)
//     → OcrVerificationHelper.verify*ForTesting()   [public @visibleForTesting wrapper]
//     → OcrVerificationHelper._verify*FromText()    [production verification logic — private]
//       → _extractAccountHolder() / _extractAccountNumber() / _extractBusinessNumber()
//       → _cleanText()
//     → Map<String, dynamic> or String?
//     → expect()
//
// ML Kit TextRecognizer 호출 없음 — raw text만 사용.
// RecognizedText 없음 → _extractAccountHolder Step 3(블록 스캔) 생략 (알려진 한계).
//
// ══════════════════════════════════════════════════════════════
// 테스트 데이터 정책
// ══════════════════════════════════════════════════════════════
// 테스트 fixture에는 가상/합성된 값만 사용.
// 실제 주민번호, 계좌번호, 사업자번호, 개인정보를 포함하지 않는다.
//
// ══════════════════════════════════════════════════════════════
// TEST FIDELITY DECLARATION
// ══════════════════════════════════════════════════════════════
// STRONG:
//   - 모든 테스트는 @visibleForTesting 래퍼를 통해 production 로직 직접 실행.
//   - 테스트 내 regex/parser/helper 복사 없음 (mirror implementation 금지).
//
// KNOWN LIMITATION (PARTIAL):
//   - _extractAccountHolder Step 3 (ML Kit RecognizedText 블록 스캔) 미테스트.
//     RecognizedText 객체 생성에 실기기 ML Kit 필요 → 단위 테스트 환경에서 불가.
//   - E2E: 실제 카메라/기기/실물 서류 → ML Kit → 검증 흐름은 NOT TESTED.
//
// ══════════════════════════════════════════════════════════════
// PHASE 2 BUG FIX 반영 (2026-08-24)
// ══════════════════════════════════════════════════════════════
// OCR-P0-001 FIXED: matches.first → any-match (주민번호 위치 무관 검증)
// OCR-P0-002 FIXED: extractedName = null (더 이상 expectedName 정제값 반환 안 함)
// OCR-P1-001 FIXED: Step 4 fallback 제거 → label 없으면 extractedName null
// OCR-P1-002 FIXED: firstMatch → any-match (계좌번호 위치 무관 검증)
// OCR-P1-003 FIXED: boundary check → 법인등록번호 내부 substring 오추출 방지
// ══════════════════════════════════════════════════════════════

void main() {
  // ─────────────────────────────────────────────
  // GROUP 1: 신분증 (Native ID)
  // ─────────────────────────────────────────────
  group('신분증 OCR 검증 (NativeId)', () {

    // NATIVE-ID-01
    // 정상 케이스: 이름 + 주민번호 모두 텍스트에 존재
    // Expected: isValid=true, confidence=1.0
    test('NATIVE-ID-01: 정상 이름 + 주민번호 — isValid true', () {
      const raw = '''
주민등록증
홍길동
900101-1234567
''';
      final result = OcrVerificationHelper.verifyIdCardForTesting(
        raw,
        '홍길동',
        expectedResidentNumber: '900101-1',
      );

      expect(result['isValid'], isTrue,
          reason: '이름과 주민번호가 모두 OCR 텍스트에 존재하면 isValid = true');
      expect(result['isNameValid'], isTrue);
      expect(result['isResidentNumberValid'], isTrue);
      expect(result['confidence'], equals(1.0));
      expect(result['extractedResidentNumber'], equals('900101-1'));
    });

    // NATIVE-ID-02
    // OCR-P0-001 FIXED:
    //   이전: matches.first 가 앞의 "123456-1" 를 주민번호로 오인식 → false-negative.
    //   수정 후: any-match 가 "900101-1" 를 발견 → isResidentNumberValid = true.
    test('NATIVE-ID-02: any-match — 앞의 유사 패턴 무관하게 실제 주민번호 인식 [P0-001 FIXED]', () {
      const raw = '''
주민등록증
계좌번호 123456-1789012
홍길동
900101-1234567
''';
      final result = OcrVerificationHelper.verifyIdCardForTesting(
        raw,
        '홍길동',
        expectedResidentNumber: '900101-1',
      );

      // FIXED: any-match 가 "900101-1" 을 발견 → true
      expect(result['isResidentNumberValid'], isTrue,
          reason: '[P0-001 FIXED] any-match: "900101-1" 발견 → VALID (앞의 "123456-1" 무관)');
      expect(result['isValid'], isTrue);
      expect(result['extractedResidentNumber'], equals('900101-1'),
          reason: 'expected와 일치하는 candidate 반환');
      expect(result['isNameValid'], isTrue);
    });

    // NATIVE-ID-03
    // OCR-P0-002 FIXED:
    //   이전: extractedName = cleanedExpected (expectedName 정제값) — OCR 값 아님.
    //   수정 후: extractedName = null (신뢰 가능한 추출 로직 없음).
    test('NATIVE-ID-03: extractedName null — OCR 이름 추출 없음 [P0-002 FIXED]', () {
      const raw = '''
주민등록증
박민준
990101-1234567
''';
      final result = OcrVerificationHelper.verifyIdCardForTesting(
        raw,
        '홍길동',
        expectedResidentNumber: '990101-9',
      );

      // 이름 불일치 (정상 동작)
      expect(result['isNameValid'], isFalse,
          reason: '"홍길동" 은 OCR 텍스트에 없음');

      // FIXED: extractedName = null (더 이상 expectedName "홍길동" 정제값 반환 안 함)
      expect(result['extractedName'], isNull,
          reason: '[P0-002 FIXED] 신분증 이름 추출 로직 없음 → null. '
              '이전: expectedName 정제값 반환으로 Warning 다이얼로그 오표시');
    });

    // NATIVE-ID-04 (신규)
    // any-match 검증: 유사 패턴 여러 개가 앞에 있어도 실제 주민번호 인식
    test('NATIVE-ID-04: 다중 유사 패턴 + expected 주민번호 — any-match VALID', () {
      const raw = '''
주민등록증
전화 010-9876-5432
계좌 123456-1234567
고객번호 654321-1999999
홍길동
900101-1234567
''';
      final result = OcrVerificationHelper.verifyIdCardForTesting(
        raw,
        '홍길동',
        expectedResidentNumber: '900101-1',
      );

      expect(result['isResidentNumberValid'], isTrue,
          reason: 'any-match 가 "900101-1" 을 발견. 앞의 유사 패턴 무관');
      expect(result['isValid'], isTrue);
      expect(result['extractedResidentNumber'], equals('900101-1'));
    });
  });

  // ─────────────────────────────────────────────
  // GROUP 2: 통장사본 (Bankbook)
  // ─────────────────────────────────────────────
  group('통장사본 OCR 검증 (Bankbook)', () {

    // BANK-01
    // 정상 케이스: 예금주 키워드 탐색(Step 1) 성공, 계좌번호 키워드 탐색 성공
    test('BANK-01: 정상 예금주 + 계좌번호 + 은행명 — isValid true', () {
      const raw = '''
국민은행
예금주: 홍길동
계좌번호: 288-910548-10807
''';
      final result = OcrVerificationHelper.verifyBankbookForTesting(
        raw,
        '홍길동',
        expectedAccountNumber: '288-910548-10807',
        expectedBankName: '국민은행',
      );

      expect(result['isValid'], isTrue);
      expect(result['isNameValid'], isTrue,
          reason: '"홍길동" 이 전체 OCR 텍스트에 포함됨');
      expect(result['isAccountValid'], isTrue,
          reason: '"계좌번호" 키워드 뒤에서 288-910548-10807 정상 추출');
      expect(result['isBankValid'], isTrue,
          reason: '"국민은행" 이 전체 텍스트에 포함됨');
      expect(result['extractedName'], equals('홍길동'));
      expect(result['extractedBankName'], equals('국민은행'));
    });

    // BANK-02
    // OCR-P1-002 FIXED:
    //   이전: firstMatch 가 "010-1234-5678" (전화번호) 를 계좌번호로 오인식.
    //   수정 후: any-match 가 "288-910548-10807" 를 발견 → isAccountValid = true.
    test('BANK-02: any-match — 전화번호 무관하게 expected 계좌번호 인식 [P1-002 FIXED]', () {
      const raw = '''
국민은행 고객센터 010-1234-5678
홍길동
288-910548-10807
''';
      final result = OcrVerificationHelper.verifyBankbookForTesting(
        raw,
        '홍길동',
        expectedAccountNumber: '288-910548-10807',
      );

      // FIXED: any-match 가 "288-910548-10807" 을 발견 → true
      expect(result['isAccountValid'], isTrue,
          reason: '[P1-002 FIXED] any-match: "288-910548-10807" 발견');
      expect(result['extractedAccountNumber'], equals('288-910548-10807'));
      // 전화번호를 계좌번호로 반환하지 않음
      expect(result['extractedAccountNumber'], isNot(equals('010-1234-5678')));
    });

    // BANK-03
    // OCR-P1-001 FIXED:
    //   이전: Step 4 fallback 이 "보통예금" (4자 한글) 을 예금주로 오인식.
    //   수정 후: Step 4 제거 → label 없으면 extractedName = null.
    test('BANK-03: Step 4 제거 — label 없으면 extractedName null [P1-001 FIXED]', () {
      // Step 1: "예금주"/"계좌주" 없음 → skip
      // Step 2: 첫줄 "하나은행 보통예금" → 공백 포함, 순수 한글 아님 → skip
      // Step 3: recognizedText=null → skip (test limitation)
      // Step 4: 제거됨 → null 반환
      const raw = '하나은행 보통예금\n잔액확인 서비스\n홍길동님';

      final extracted =
          OcrVerificationHelper.extractAccountHolderForTesting(raw);

      // FIXED: Step 4 제거 → null (이전: "보통예금" 반환)
      expect(extracted, isNull,
          reason: '[P1-001 FIXED] Step 4 fallback 제거. label-based 추출 실패 → null');

      final result = OcrVerificationHelper.verifyBankbookForTesting(
        raw,
        '홍길동',
      );
      expect(result['isNameValid'], isTrue,
          reason: 'isNameValid = cleanedOcr.contains("홍길동") — "홍길동님" 포함');
      // FIXED: extractedName = null (이전: "보통예금")
      expect(result['extractedName'], isNull,
          reason: '[P1-001 FIXED] label 없는 경우 null 반환');
    });

    // BANK-04 (신규)
    // any-match 검증: 다수 distractors + expected 계좌번호 → VALID
    test('BANK-04: 다중 distractors + expected 계좌번호 — any-match VALID', () {
      const raw = '''
국민은행
고객센터 1588-9999
전화번호 010-1234-5678
고객번호 123-45-12345
등록일 2024-01-15
예금주 홍길동
288-910548-10807
''';
      final result = OcrVerificationHelper.verifyBankbookForTesting(
        raw,
        '홍길동',
        expectedAccountNumber: '288-910548-10807',
      );

      expect(result['isAccountValid'], isTrue,
          reason: 'any-match 가 "288-910548-10807" 을 발견');
      expect(result['isValid'], isTrue);
    });

    // BANK-05 (신규)
    // expected 계좌번호 있지만 전화번호만 존재 — isAccountValid=false, extractedAccountNumber=null
    test('BANK-05: 전화번호만 있고 expected 계좌번호 불일치 — null, isAccountValid false', () {
      const raw = '''
고객센터 010-1234-5678
전화 02-111-2222
''';
      final result = OcrVerificationHelper.verifyBankbookForTesting(
        raw,
        '홍길동',
        expectedAccountNumber: '288-910548-10807',
      );

      expect(result['isAccountValid'], isFalse,
          reason: 'expected "288-910548-10807" 과 일치하는 candidate 없음');
      // 전화번호를 계좌번호로 반환하지 않음
      expect(result['extractedAccountNumber'], isNull,
          reason: 'any-match 실패 → null (전화번호 반환 금지)');
    });
  });

  // ─────────────────────────────────────────────
  // GROUP 3: 사업자등록증 (Business License)
  // ─────────────────────────────────────────────
  group('사업자등록증 OCR 검증 (BusinessLicense)', () {

    // BUSINESS-01
    // 정상 케이스: 사업자등록번호 + 대표자 모두 정상 추출
    test('BUSINESS-01: 정상 사업자등록번호 + 대표자 — isValidNumber/Name true', () {
      const raw = '''
사업자등록증
등록번호 123-45-67890
대표자: 홍길동
''';
      final result = OcrVerificationHelper.verifyBusinessLicenseForTesting(
        raw,
        '1234567890',
        '홍길동',
      );

      expect(result['isValidNumber'], isTrue,
          reason: '"등록번호" 레이블 탐색 → "1234567890" 정상 추출');
      expect(result['isValidName'], isTrue,
          reason: '"대표자:" 레이블 탐색 → "홍길동" 정상 추출');
      expect(result['confidence'], equals(1.0));
      expect(result['extractedNumber'], equals('1234567890'));
      expect(result['extractedName'], equals('홍길동'));
    });

    // BUSINESS-02
    // 법인등록번호 레이블 + 사업자등록번호 레이블 공존.
    // line-by-line skip: "법인등록번호" 줄은 건너뜀 → "등록번호" 줄에서 정상 추출.
    test('BUSINESS-02: 법인등록번호 + 사업자번호 공존 — 사업자번호만 정상 추출', () {
      const raw = '''
법인등록번호 110111-1234567
등록번호 123-45-67890
대표자: 홍길동
''';
      final extracted =
          OcrVerificationHelper.extractBusinessNumberForTesting(raw);

      expect(extracted, equals('1234567890'),
          reason: 'line-by-line skip 이 법인등록번호를 올바르게 제외. 사업자번호 정상 추출.');

      final result = OcrVerificationHelper.verifyBusinessLicenseForTesting(
        raw,
        '1234567890',
        '홍길동',
      );
      expect(result['isValidNumber'], isTrue);
    });

    // BUSINESS-03
    // OCR-P1-003 FIXED:
    //   이전: fallback regex 가 "110111-1234567" 에서 "1011112345" 오추출.
    //   수정 후: boundary check → before='1'(digit) → SKIP → null 반환.
    test('BUSINESS-03: 법인등록번호만 — boundary check로 오추출 방지 [P1-003 FIXED]', () {
      const raw = '''
법인등록번호 110111-1234567
대표자: 홍길동
''';
      final extracted =
          OcrVerificationHelper.extractBusinessNumberForTesting(raw);

      // FIXED: boundary check → before='1'(digit) → SKIP → null
      expect(extracted, isNull,
          reason: '[P1-003 FIXED] 법인등록번호 내부 매칭 → before/after 경계 체크로 제거');

      final result = OcrVerificationHelper.verifyBusinessLicenseForTesting(
        raw,
        '9876543210',
        null,
      );
      expect(result['isValidNumber'], isFalse,
          reason: 'extraction null → expectedBusinessNumber != null && extractedNumber == null → false');
      expect(result['extractedNumber'], isNull);
    });

    // BUSINESS-04 (신규)
    // 법인등록번호만 + expected 사업자번호 → extraction null → INVALID
    test('BUSINESS-04: 법인등록번호만 + expected 사업자번호 → INVALID', () {
      const raw = '''
법인등록번호 110111-1234567
대표자: 홍길동
''';
      final result = OcrVerificationHelper.verifyBusinessLicenseForTesting(
        raw,
        '1234567890',
        '홍길동',
      );

      expect(result['isValidNumber'], isFalse,
          reason: '법인등록번호만 있고 사업자번호 추출 불가 → isValidNumber false');
      expect(result['extractedNumber'], isNull);
      // 대표자는 정상 추출됨
      expect(result['isValidName'], isTrue);
    });

    // BUSINESS-05 (신규)
    // 법인번호 + 전화번호 + 정상 사업자번호 → label-based 추출 성공 → VALID
    test('BUSINESS-05: 법인번호 + 전화번호 + 사업자번호 — label 기반 추출 VALID', () {
      const raw = '''
법인등록번호 110111-1234567
전화 02-1234-5678
등록번호 123-45-67890
대표자: 홍길동
''';
      final result = OcrVerificationHelper.verifyBusinessLicenseForTesting(
        raw,
        '1234567890',
        '홍길동',
      );

      expect(result['isValidNumber'], isTrue,
          reason: '법인등록번호 skip → "등록번호" 레이블에서 사업자번호 정상 추출');
      expect(result['extractedNumber'], equals('1234567890'));
      expect(result['isValidName'], isTrue);
      expect(result['confidence'], equals(1.0));
    });

    // BUSINESS-CEO-01
    // _extractCeoName 과도매칭 재현 — 비레이블 줄 "대표적인 서비스 자동화"가
    // '대', '표', '자' 포함 → trigger → 같은줄 regex가 "서비스" 추출 (false positive).
    // isValidName = false (오추출값 ≠ expectedCeoName "홍길동") → WARNING 경로.
    // onCeoNameExtracted 미호출 → Firestore 미기록.
    //
    // [VERDICT] REPRODUCED as extraction inaccuracy. NOT a Firestore persistence issue.
    test('BUSINESS-CEO-01: 비레이블 줄 과도매칭 — 오추출은 WARNING 경로, Firestore 미기록 [VERIFIED]', () {
      // "대표적인 서비스 자동화" — '대'+'표'+'자' 포함, 대표자 레이블 아님
      // 같은줄 RegExp(r'[:\s]+([가-힣]{2,5})') → " 서비스" 매칭 → extractedName = "서비스"
      // expectedCeoName = "홍길동" → isValidName = false → WARNING 경로
      const raw = '대표적인 서비스 자동화\n김테스트\n등록번호 123-45-67890';

      final result = OcrVerificationHelper.verifyBusinessLicenseForTesting(
        raw,
        '1234567890',
        '홍길동',
      );

      // [REPRODUCED] 비레이블 줄에서 한글 단어 오추출됨 — extractedName is non-null
      expect(result['extractedName'], isNotNull,
          reason: 'REPRODUCED: "대표적인 서비스 자동화"가 대표자 trigger → 오추출 발생');
      // 오추출값이 expectedCeoName("홍길동")과 불일치 → isValidName = false
      expect(result['isValidName'], isFalse,
          reason: '오추출값 ≠ "홍길동" → isValidName false → WARNING 경로 (onCeoNameExtracted 미호출)');
      // 정상 사업자번호는 추출됨
      expect(result['isValidNumber'], isTrue,
          reason: '"등록번호 123-45-67890" 레이블 추출 정상');
      // isValid = isValidNumber && isValidName = true && false = false
      // → SUCCESS 경로 아님 → onCeoNameExtracted NOT called → Firestore 미기록
    });

    // BUSINESS-CEO-02
    // _extractCeoName nextLine 과도매칭 — 비레이블 줄 "대표자서류"(콜론/공백 없음)가
    // 같은줄 regex 실패 → nextLine "김테스트" 오추출.
    // 마찬가지로 expectedCeoName "홍길동"과 불일치 → isValidName = false → WARNING 경로.
    test('BUSINESS-CEO-02: 비레이블 nextLine 과도매칭 — 오추출은 WARNING 경로 [VERIFIED]', () {
      // "대표자서류" — '대'+'표'+'자' 포함, 레이블 아님, 내부 공백·콜론 없음
      // 같은줄 regex 실패 → nextLine "김테스트" 오추출
      const raw = '대표자서류\n김테스트\n등록번호 123-45-67890';

      final result = OcrVerificationHelper.verifyBusinessLicenseForTesting(
        raw,
        '1234567890',
        '홍길동',
      );

      // [REPRODUCED] nextLine "김테스트" 오추출
      expect(result['extractedName'], equals('김테스트'),
          reason: 'REPRODUCED: "대표자서류" trigger → nextLine "김테스트" 오추출');
      // 오추출값 ≠ "홍길동" → isValidName = false → WARNING 경로
      expect(result['isValidName'], isFalse,
          reason: '"김테스트" ≠ "홍길동" → isValidName false → onCeoNameExtracted 미호출');
      // Firestore persistence 안전: SUCCESS path 진입 불가 (isValidName false)
    });

    // ──────────────────────────────────────────────────────────
    // BUSINESS-CEO-NULL-01 / NULL-02
    // [GAP-NULL → FIXED] ceoName=null/empty → hasCeoName=false → callback BLOCKED
    //
    // Phase 3.1 감사에서 발견된 DATA POLLUTION 경로:
    //   이전: hasCeoName=false + false-positive extractedName → SUCCESS → callback CALLED
    //   수정 (Option B): callback 진입 조건에 hasCeoName && isValidName==true 추가
    //     → hasCeoName=false 시 callback 무조건 차단
    //
    // 수정 후 경로:
    //   _verifyBusinessLicenseFromText(raw, '1234567890', null):
    //     extractedName = "서비스" (false-positive — 추출 자체는 유지)
    //     isValidName = false (expectedCeoName=null → 블록 스킵)
    //     isValidNumber = true, confidence = 0.6
    //   pickAndVerifyBusinessLicense (ceoName=null):
    //     hasCeoName = false
    //     isValid = true (hasCeoName=false → RHS=true)
    //     SUCCESS PATH 진입 — 문서 업로드 성공
    //     if (hasCeoName && isValidName == true && ...) → hasCeoName=false → BLOCKED
    //     onCeoNameExtracted: NOT CALLED ← ✅ DATA POLLUTION BLOCKED
    //
    // NOTE: verifyBusinessLicenseForTesting은 _verifyBusinessLicenseFromText만 테스트.
    //       hasCeoName 체크 및 callback 가드는 pickAndVerifyBusinessLicense에 있으므로
    //       중간 상태(helper 반환값) 검증 + 수정 후 경로를 주석으로 문서화.
    // ──────────────────────────────────────────────────────────

    // BUSINESS-CEO-NULL-01
    // [FIXED] ceoName=null → hasCeoName=false → callback BLOCKED
    // helper: extractedName non-null (false-positive), isValidName=false, confidence=0.6
    // pickAndVerifyBusinessLicense: hasCeoName=false → callback guard → NOT CALLED
    test('BUSINESS-CEO-NULL-01: ceoName=null + 사업자번호 정상 → false-positive 추출되나 callback BLOCKED [FIXED]', () {
      // CEO-01과 동일 fixture: "대표적인 서비스 자동화" → _extractCeoName → "서비스" (false-positive)
      const raw = '대표적인 서비스 자동화\n등록번호 123-45-67890';

      final result = OcrVerificationHelper.verifyBusinessLicenseForTesting(
        raw,
        '1234567890',
        null, // expectedCeoName=null → hasCeoName=false in pickAndVerifyBusinessLicense
      );

      // _extractCeoName은 여전히 false-positive를 추출 (parser 수정 없음, 의도적)
      expect(result['extractedName'], isNotNull,
          reason: '"대표적인 서비스 자동화" trigger → "서비스" false-positive 추출 (parser 미수정)');

      // expectedCeoName=null → isValidName 체크 블록 스킵 → false 유지
      expect(result['isValidName'], isFalse,
          reason: 'expectedCeoName=null → isValidName=false (블록 스킵)');

      // 사업자번호 정상 일치
      expect(result['isValidNumber'], isTrue);

      // confidence=0.6 (isValidNumber=true, isValidName=false)
      expect(result['confidence'], equals(0.6));

      // ✅ FIXED (pickAndVerifyBusinessLicense 단):
      //   hasCeoName=false → if(hasCeoName && isValidName==true && ...) → false → NOT CALLED
      //   _ceoNameController.text 변경 없음 → Firestore persistence 불가
      // [STATUS] BLOCKED
    });

    // BUSINESS-CEO-NULL-02
    // [FIXED] ceoName='' → hasCeoName=false → callback BLOCKED (NULL-01과 동일)
    test('BUSINESS-CEO-NULL-02: ceoName="" + 사업자번호 정상 → hasCeoName=false, callback BLOCKED [FIXED]', () {
      const raw = '대표적인 서비스 자동화\n등록번호 123-45-67890';

      final result = OcrVerificationHelper.verifyBusinessLicenseForTesting(
        raw,
        '1234567890',
        '', // expectedCeoName='' → hasCeoName=false (''.isNotEmpty=false)
      );

      // '' != null → 블록 진입, "서비스" != "" → isValidName=false
      expect(result['isValidName'], isFalse,
          reason: '"서비스" != "" → isValidName=false');

      expect(result['isValidNumber'], isTrue);
      expect(result['confidence'], equals(0.6));
      expect(result['extractedName'], isNotNull,
          reason: 'false-positive 추출 자체는 유지 (parser 미수정)');

      // ✅ FIXED (pickAndVerifyBusinessLicense 단):
      //   hasCeoName = '' != null && ''.isNotEmpty = false
      //   callback guard: hasCeoName=false → NOT CALLED
      // [STATUS] BLOCKED
    });

    // ──────────────────────────────────────────────────────────
    // BUSINESS-CEO-VALID-01 / CEO-MISMATCH-01
    // 수정 후 기존 검증 기능 회귀 방지
    // ──────────────────────────────────────────────────────────

    // BUSINESS-CEO-VALID-01
    // ceoName 존재 + OCR 일치 → isValidName=true → callback ALLOWED (수정 전후 동일)
    // pickAndVerifyBusinessLicense:
    //   hasCeoName=true, isValidName=true → callback guard 통과 → onCeoNameExtracted("홍길동") CALLED
    test('BUSINESS-CEO-VALID-01: expectedCeoName="홍길동" + OCR 일치 → isValidName=true, callback ALLOWED [회귀방지]', () {
      const raw = '사업자등록증\n등록번호 123-45-67890\n대표자: 홍길동';

      final result = OcrVerificationHelper.verifyBusinessLicenseForTesting(
        raw,
        '1234567890',
        '홍길동',
      );

      // 검증 성공
      expect(result['isValidName'], isTrue,
          reason: '"홍길동" == "홍길동" → isValidName=true');
      expect(result['isValidNumber'], isTrue);
      expect(result['confidence'], equals(1.0),
          reason: 'isValidNumber=true && isValidName=true → confidence=1.0');
      expect(result['extractedName'], equals('홍길동'));

      // ✅ pickAndVerifyBusinessLicense:
      //   hasCeoName=true, isValidName=true, extracted="홍길동" (non-null, non-empty)
      //   callback guard 통과 → onCeoNameExtracted("홍길동") CALLED — 정상 autofill
    });

    // BUSINESS-CEO-MISMATCH-01
    // ceoName 존재 + OCR 불일치 → isValidName=false → callback BLOCKED (mismatch → warning 경로)
    // pickAndVerifyBusinessLicense:
    //   hasCeoName=true, isValidName=false → callback guard 차단 → NOT CALLED
    test('BUSINESS-CEO-MISMATCH-01: expectedCeoName="홍길동" + OCR="김철수" → isValidName=false, callback BLOCKED [회귀방지]', () {
      const raw = '사업자등록증\n등록번호 123-45-67890\n대표자: 김철수';

      final result = OcrVerificationHelper.verifyBusinessLicenseForTesting(
        raw,
        '1234567890',
        '홍길동', // expected
      );

      // 불일치
      expect(result['isValidName'], isFalse,
          reason: '"김철수" != "홍길동" → isValidName=false');
      expect(result['isValidNumber'], isTrue);
      expect(result['extractedName'], equals('김철수'));
      expect(result['confidence'], equals(0.6),
          reason: 'isValidNumber=true, isValidName=false → confidence=0.6');

      // ✅ pickAndVerifyBusinessLicense:
      //   isValid = (true ? isValidNumber : true) && (true ? isValidName : true)
      //           = true && false = false → SUCCESS 진입 불가 → WARNING 경로
      //   callback guard에 도달조차 않음 (isValid=false → else 분기)
      // [STATUS] BLOCKED — warning dialog 표시
    });
  });
}
