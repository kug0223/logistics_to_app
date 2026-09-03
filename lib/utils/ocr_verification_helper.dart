// lib/utils/ocr_verification_helper.dart

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// 📄 OCR 기반 서류 검증 헬퍼 클래스
///
/// [설계 원칙] OcrVerificationHelper는 "이미 알고 있는 expected value가
/// 문서 OCR에서 확인되는지 검사하는 Verifier"이다.
/// ForeignIdOcrService(field extraction)와 역할을 혼동하지 마세요.
///
/// 계좌번호·주민번호 검증은 ALL candidates any-match 방식:
///   expected 기준으로 OCR 후보 전체를 스캔 → 정확히 일치하는 candidate 존재 시 valid.
///   첫 번째 candidate를 임의 추출하여 비교하는 방식 금지 (전화번호 오인식 방지).
class OcrVerificationHelper {

  // ──────────────────────────────────────────────────────────────────────────
  // 신분증
  // ──────────────────────────────────────────────────────────────────────────

  /// 📸 신분증 이름 + 주민번호 검증
  static Future<Map<String, dynamic>> verifyIdCardName(
    String imagePath,
    String expectedName, {
    String? expectedResidentNumber,
  }) async {
    TextRecognizer? textRecognizer;

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);

      final rawText = recognizedText.text;
      // PII 보호: rawText 원본 출력 금지 — 텍스트 길이만 로그
      if (kDebugMode) debugPrint('📄 [신분증 OCR] 텍스트 길이: ${rawText.length}');

      final result = _verifyIdCardFromText(
        rawText,
        expectedName,
        expectedResidentNumber: expectedResidentNumber,
      );

      return {
        ...result,
        'rawText': kDebugMode ? rawText : '',
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [신분증 OCR] 실패: $e');
      return {
        'isValid': false,
        'isNameValid': false,
        'isResidentNumberValid': false,
        'confidence': 0.0,
        'extractedName': null,
        'extractedResidentNumber': null,
        'rawText': '',
        'error': e.toString(),
      };
    } finally {
      textRecognizer?.close();
    }
  }

  /// 신분증 검증 로직 (ML Kit 호출 없음 — raw OCR text 입력)
  ///
  /// [verifyIdCardName] 에서 ML Kit 이후 로직을 분리한 private 메서드.
  /// [verifyIdCardForTesting] 을 통해 테스트에서 직접 호출된다.
  ///
  /// [주민번호 검증] any-match: expected와 일치하는 candidate가 존재하는지 확인.
  ///   앞에 전화번호·계좌번호 등 유사 패턴이 있어도 expected가 뒤에 있으면 valid.
  /// [extractedName] 신뢰 가능한 신분증 이름 추출 로직 없음 → null 반환.
  static Map<String, dynamic> _verifyIdCardFromText(
    String rawText,
    String expectedName, {
    String? expectedResidentNumber,
  }) {
    final cleanedOcr = _cleanText(rawText);
    final cleanedExpected = _cleanText(expectedName);

    final isNameValid = cleanedOcr.contains(cleanedExpected);

    bool isResidentNumberValid = true;
    String? extractedResidentNumber;

    if (expectedResidentNumber != null && expectedResidentNumber.isNotEmpty) {
      // [OCR-P0-001 FIX] any-match 방식 교체 —
      // 텍스트 내 모든 '6자리[-]1자리' 패턴을 수집하여
      // expected와 정확히 일치하는 candidate가 존재하는지 검증.
      // 앞에 계좌번호·전화번호 등 유사 패턴이 있어도
      // expected 값이 텍스트 어딘가에 있으면 isResidentNumberValid = true.
      //
      // 이전 버전(matches.first)의 문제:
      //   텍스트 내 첫 번째 '6자리+1자리' 패턴을 주민번호로 간주 →
      //   계좌번호·전화번호 등이 앞에 있으면 false-negative 발생.
      final cleanedExpectedRN =
          expectedResidentNumber.replaceAll(RegExp(r'\D'), '');
      final residentPattern = RegExp(r'(\d{6})[-\s]?(\d)');
      String? matchedCandidate;
      for (final match in residentPattern.allMatches(rawText)) {
        final front = match.group(1)!;
        final back = match.group(2)!;
        final cleanedCandidate = '$front$back';
        if (cleanedCandidate == cleanedExpectedRN) {
          matchedCandidate = '$front-$back';
          break;
        }
      }
      isResidentNumberValid = matchedCandidate != null;
      extractedResidentNumber = matchedCandidate;
    }

    final isValid = isNameValid && isResidentNumberValid;

    double confidence = 0.0;
    if (isNameValid && isResidentNumberValid) {
      confidence = 1.0;
    } else if (isNameValid) {
      confidence = 0.6;
    } else if (isResidentNumberValid) {
      confidence = 0.5;
    }

    return {
      'isValid': isValid,
      'isNameValid': isNameValid,
      'isResidentNumberValid': isResidentNumberValid,
      'confidence': confidence,
      // [OCR-P0-002 FIX] null 반환 —
      // 신뢰 가능한 OCR 이름 추출 로직이 없으므로 null.
      // 이전 버전의 cleanedExpected 반환은 OCR 추출값이 아닌 expectedName 정제값이었음.
      // Consumer는 null을 '확인 불가'/'인식 실패'로 처리.
      'extractedName': null,
      'extractedResidentNumber': extractedResidentNumber,
    };
  }

  /// 테스트 전용 — 신분증 검증 로직 직접 실행 (ML Kit 없음)
  ///
  /// [visibleForTesting]: unit test에서만 호출. Production 경로는 변경 없음.
  ///
  /// CALL GRAPH:
  ///   verifyIdCardForTesting(rawText, expectedName)
  ///     → _verifyIdCardFromText()               [production logic]
  ///       → _cleanText()
  ///       → RegExp(r'(\d{6})[-\s]?(\d)').allMatches() → any-match [P0-001 FIX]
  ///       → 'extractedName': null               [P0-002 FIX]
  @visibleForTesting
  static Map<String, dynamic> verifyIdCardForTesting(
    String rawText,
    String expectedName, {
    String? expectedResidentNumber,
  }) =>
      _verifyIdCardFromText(rawText, expectedName,
          expectedResidentNumber: expectedResidentNumber);

  // ──────────────────────────────────────────────────────────────────────────
  // 통장사본
  // ──────────────────────────────────────────────────────────────────────────

  /// 💳 통장사본 검증 (예금주 + 계좌번호 + 은행명)
  ///
  /// [imagePath]: 통장사본 이미지 경로
  /// [expectedName]: 예상 예금주명
  /// [expectedAccountNumber]: 예상 계좌번호 (선택)
  /// [expectedBankName]: 예상 은행명 (선택)
  static Future<Map<String, dynamic>> verifyBankbook(
    String imagePath,
    String? expectedName, {
    String? expectedAccountNumber,
    String? expectedBankName,
  }) async {
    TextRecognizer? textRecognizer;

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);

      final rawText = recognizedText.text;
      // PII 보호: rawText 원본 출력 금지 — 텍스트 길이만 로그
      if (kDebugMode) debugPrint('📄 [통장사본 OCR] 텍스트 길이: ${rawText.length}');

      final result = _verifyBankbookFromText(
        rawText,
        expectedName,
        expectedAccountNumber: expectedAccountNumber,
        expectedBankName: expectedBankName,
        recognizedText: recognizedText,
      );

      return {
        ...result,
        'rawText': kDebugMode ? rawText : '',
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [통장사본 OCR] 실패: $e');
      return {
        'isValid': false,
        'isNameValid': false,
        'isAccountValid': false,
        'isBankValid': false,
        'confidence': 0.0,
        'extractedName': null,
        'extractedAccountNumber': null,
        'extractedBankName': null,
        'rawText': '',
        'error': e.toString(),
      };
    } finally {
      textRecognizer?.close();
    }
  }

  /// 통장사본 검증 로직 (ML Kit 호출 없음 — raw OCR text 입력)
  ///
  /// [계좌번호 검증] any-match: expectedAccountNumber 기준으로 OCR 후보 전체 스캔.
  ///   전화번호 등 다른 숫자 패턴이 먼저 나타나도 expected와 정확히 일치하는
  ///   candidate가 존재하면 isAccountValid = true.
  ///
  /// [예금주명 추출] label-based(Step 1/2/3)만 실행. Step 4 fallback 제거.
  ///   근거 없는 경우 null 반환.
  ///
  /// [recognizedText]: Step 3(블록 스캔)에만 사용. null이면 Step 3 생략.
  /// 테스트 경로에서는 null 전달 — Step 3 생략이 테스트의 알려진 한계.
  static Map<String, dynamic> _verifyBankbookFromText(
    String rawText,
    String? expectedName, {
    String? expectedAccountNumber,
    String? expectedBankName,
    RecognizedText? recognizedText,
  }) {
    // ✅ 예금주명 추출 (label-based: Step 1 키워드 / Step 2 첫줄 / Step 3 블록)
    // Step 4 전체 텍스트 fallback 제거 — [OCR-P1-001 FIX]
    String? extractedName = _extractAccountHolder(rawText, recognizedText);

    // ✅ 은행명 추출
    String? extractedBankName = _extractBankName(rawText);

    // ✅ 검증
    final cleanedOcr = _cleanText(rawText);

    // 1. 예금주명 검증 (전체 텍스트에서 이름 포함 여부)
    // [V3 FOREIGN HOLDER] expectedName == null → 이름 검증 skip (외국인 통장 오탐 방지)
    final isNameValid = expectedName == null ||
        cleanedOcr.contains(_cleanText(expectedName));
    if (kDebugMode) {
      if (expectedName == null) {
        debugPrint('📄 [통장사본 OCR] 예금주 검증 skip (expectedName null)');
      } else {
        debugPrint('📄 [통장사본 OCR] 예금주 검증: ${isNameValid ? "✅" : "❌"}');
      }
    }

    // 2. 계좌번호 검증 — [OCR-P1-002 FIX] any-match 방식
    // expectedAccountNumber 기준으로 OCR 후보 전체를 스캔하여 일치 여부 확인.
    // 이전 버전(firstMatch)의 문제:
    //   전화번호 등 패턴이 먼저 나타나면 오인식 → false-negative.
    bool isAccountValid = true;
    String? extractedAccountNumber;

    if (expectedAccountNumber != null && expectedAccountNumber.isNotEmpty) {
      final cleanedExpectedAccount =
          expectedAccountNumber.replaceAll(RegExp(r'\D'), '');

      // Step 1: "계좌번호" 키워드 근처에서 keyword-match
      bool foundByKeyword = false;
      for (final line in rawText.split('\n')) {
        if (line.contains('계좌번호') || line.contains('계좌 번호')) {
          final accountPattern = RegExp(r'[\d]+[-\s]*[\d]+[-\s]*[\d]+');
          final match = accountPattern.firstMatch(line);
          if (match != null) {
            final candidate =
                (match.group(0) ?? '').replaceAll(RegExp(r'\D'), '');
            if (candidate == cleanedExpectedAccount) {
              isAccountValid = true;
              extractedAccountNumber = match.group(0)?.replaceAll(' ', '');
              foundByKeyword = true;
              break;
            }
          }
        }
      }

      // Step 2: 전체 텍스트에서 계좌번호 패턴 후보 전체 스캔 — any-match
      if (!foundByKeyword) {
        final patterns = [
          RegExp(r'(\d{3,4})[-\s](\d{4,6})[-\s](\d{4,6})'),
          RegExp(r'(\d{2,4})[-\s](\d{2,4})[-\s](\d{4,7})'),
        ];
        bool anyMatch = false;
        for (final pattern in patterns) {
          for (final match in pattern.allMatches(rawText)) {
            final g1 = match.group(1) ?? '';
            final g2 = match.group(2) ?? '';
            final g3 = match.group(3) ?? '';
            final candidate = '$g1$g2$g3';
            if (candidate == cleanedExpectedAccount) {
              isAccountValid = true;
              extractedAccountNumber = '$g1-$g2-$g3';
              anyMatch = true;
              break;
            }
          }
          if (anyMatch) break;
        }
        if (!anyMatch) {
          isAccountValid = false;
          extractedAccountNumber = null;
        }
      }

      if (kDebugMode) {
        debugPrint(
            '📄 [통장사본 OCR] 계좌번호 검증: ${isAccountValid ? "✅" : "❌"}');
      }
    }

    // 3. 은행명 검증 (선택)
    bool isBankValid = true;
    if (expectedBankName != null && expectedBankName.isNotEmpty) {
      final cleanedExpectedBank = _cleanText(expectedBankName);
      final cleanedExtractedBank = _cleanText(extractedBankName ?? '');
      isBankValid = cleanedOcr.contains(cleanedExpectedBank) ||
          cleanedExtractedBank.contains(cleanedExpectedBank);
      if (kDebugMode) {
        debugPrint('📄 [통장사본 OCR] 은행명 검증: ${isBankValid ? "✅" : "❌"}');
      }
    }

    // 종합 검증
    final isValid = isNameValid; // 예금주명은 필수

    // 신뢰도 계산
    double confidence = 0.0;
    int validCount = 0;
    int totalCount = 1; // 예금주명은 필수

    if (isNameValid) validCount++;

    if (expectedAccountNumber != null && expectedAccountNumber.isNotEmpty) {
      totalCount++;
      if (isAccountValid) validCount++;
    }

    if (expectedBankName != null && expectedBankName.isNotEmpty) {
      totalCount++;
      if (isBankValid) validCount++;
    }

    confidence = validCount / totalCount;

    return {
      'isValid': isValid,
      'isNameValid': isNameValid,
      'isAccountValid': isAccountValid,
      'isBankValid': isBankValid,
      'confidence': confidence,
      'extractedName': extractedName,
      'extractedAccountNumber': extractedAccountNumber,
      'extractedBankName': extractedBankName,
    };
  }

  /// 테스트 전용 — 통장사본 검증 로직 직접 실행 (ML Kit 없음)
  ///
  /// [visibleForTesting]: unit test에서만 호출.
  /// RecognizedText 없이 호출 → Step 3(블록 스캔) 생략.
  ///
  /// KNOWN LIMITATION: _extractAccountHolder Step 3 미실행.
  /// Step 1(예금주 키워드) / Step 2(첫 줄) 만 테스트됨.
  ///
  /// CALL GRAPH:
  ///   verifyBankbookForTesting(rawText, expectedName)
  ///     → _verifyBankbookFromText(..., recognizedText: null)  [production logic]
  ///       → _extractAccountHolder(rawText, null)   ← Step 3 skipped
  ///       → any-match account verification         [P1-002 FIX]
  ///       → _extractBankName(rawText)
  @visibleForTesting
  static Map<String, dynamic> verifyBankbookForTesting(
    String rawText,
    String expectedName, {
    String? expectedAccountNumber,
    String? expectedBankName,
  }) =>
      _verifyBankbookFromText(
        rawText,
        expectedName,
        expectedAccountNumber: expectedAccountNumber,
        expectedBankName: expectedBankName,
      );

  /// 테스트 전용 — _extractAccountHolder 직접 호출 (Step 3 생략)
  ///
  /// [visibleForTesting]: unit test에서만 호출.
  /// Step 4 제거 이후: label-based 추출(Step 1, 2)만 실행.
  /// Step 3(블록 스캔)도 RecognizedText 없이는 생략됨.
  @visibleForTesting
  static String? extractAccountHolderForTesting(String rawText) =>
      _extractAccountHolder(rawText);

  /// 💳 통장사본 예금주명만 검증 (기존 호환용)
  static Future<Map<String, dynamic>> verifyBankbookName(
    String imagePath,
    String expectedName,
  ) async {
    return verifyBankbook(imagePath, expectedName);
  }

  /// ✅ 예금주명 추출
  ///
  /// [OCR-P1-001 FIX] Step 4 전체 텍스트 fallback 제거.
  ///   이전 Step 4: 전체 텍스트에서 2~5자 한글 임의 선택 → "보통예금" 등 오인식.
  ///   수정 후: label-based 추출(Step 1/2/3)만 실행. 근거 없는 경우 null.
  ///
  /// [recognizedText] ML Kit 블록 스캔용 (Step 3). null이면 Step 3 생략.
  static String? _extractAccountHolder(String rawText,
      [RecognizedText? recognizedText]) {
    final lines = rawText.split('\n');

    // 1. "예금주" 키워드 근처에서 찾기
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('예금주') || line.contains('계좌주')) {
        // 같은 줄에서 이름 추출 (예: "예금주: 홍길동")
        final colonIndex = line.indexOf(':');
        if (colonIndex != -1) {
          final afterColon = line.substring(colonIndex + 1).trim();
          final nameMatch = RegExp(r'[가-힣]{2,5}').firstMatch(afterColon);
          if (nameMatch != null) {
            return nameMatch.group(0);
          }
        }

        // 다음 줄에서 이름 찾기
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          final nameMatch = RegExp(r'^[가-힣]{2,5}$').firstMatch(nextLine);
          if (nameMatch != null) {
            return nameMatch.group(0);
          }
        }
      }
    }

    // 2. 첫 번째 줄이 한글 이름(2-5자)인 경우
    if (lines.isNotEmpty) {
      final firstLine = lines[0].trim();
      if (RegExp(r'^[가-힣]{2,5}$').hasMatch(firstLine)) {
        return firstLine;
      }
    }

    // 3. 블록 단위로 스캔 - 단독 한글 이름 찾기 (RecognizedText 있을 때만)
    if (recognizedText != null) {
      for (TextBlock block in recognizedText.blocks) {
        final text = block.text.trim();
        // 한글 2-5자리 이름만 있는 블록
        if (RegExp(r'^[가-힣]{2,5}$').hasMatch(text)) {
          // "님", "은행" 등 제외
          if (!text.contains('님') &&
              !text.contains('은행') &&
              !text.contains('과목') &&
              !text.contains('통장')) {
            return text;
          }
        }
      }
    }

    // Step 4 제거 — [OCR-P1-001 FIX]
    // 전체 텍스트에서 2~5자 한글을 추측하는 fallback 제거.
    // 제외 키워드 목록이 불완전하여 "보통예금", "잔액확인", "고객센터" 등 오인식.
    // label-based 추출(Step 1/2/3)로만 반환. 근거 없는 경우 null.
    return null;
  }

  /// ✅ 은행명 추출
  static String? _extractBankName(String rawText) {
    // 주요 은행 목록
    final banks = [
      'KB국민은행', '국민은행',
      '신한은행',
      'NH농협은행', '농협은행', '농협',
      '우리은행',
      '하나은행',
      'IBK기업은행', '기업은행',
      'SC제일은행', '제일은행',
      '카카오뱅크',
      '토스뱅크',
      '케이뱅크', 'K뱅크',
      '새마을금고',
      '우체국', '우체국예금',
      '수협', '수협은행',
      '대구은행',
      '부산은행',
      '경남은행',
      '광주은행',
      '전북은행',
      '제주은행',
    ];

    for (final bank in banks) {
      if (rawText.contains(bank)) {
        return bank;
      }
    }

    // 일반적인 "XX은행" 패턴
    final bankPattern = RegExp(r'([가-힣]+은행)');
    final match = bankPattern.firstMatch(rawText);
    if (match != null) {
      return match.group(1);
    }

    return null;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 사업자등록증
  // ──────────────────────────────────────────────────────────────────────────

  /// 🏢 사업자등록증 검증
  static Future<Map<String, dynamic>> verifyBusinessLicense(
    String imagePath,
    String? expectedBusinessNumber,
    String? expectedCeoName,
  ) async {
    TextRecognizer? textRecognizer;

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);

      final rawText = recognizedText.text;
      // PII 보호: rawText 원본 출력 금지 — 텍스트 길이만 로그
      if (kDebugMode) debugPrint('📄 [사업자등록증 OCR] 텍스트 길이: ${rawText.length}');

      final result = _verifyBusinessLicenseFromText(
          rawText, expectedBusinessNumber, expectedCeoName);

      return {
        ...result,
        'rawText': kDebugMode ? rawText : '',
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [사업자등록증 OCR] 실패: $e');
      return {
        'isValidNumber': false,
        'isValidName': false,
        'confidence': 0.0,
        'extractedNumber': null,
        'extractedName': null,
        'rawText': '',
        'error': e.toString(),
      };
    } finally {
      textRecognizer?.close();
    }
  }

  /// 사업자등록증 검증 로직 (ML Kit 호출 없음 — raw OCR text 입력)
  static Map<String, dynamic> _verifyBusinessLicenseFromText(
    String rawText,
    String? expectedBusinessNumber,
    String? expectedCeoName,
  ) {
    String? extractedNumber = _extractBusinessNumber(rawText);
    String? extractedName = _extractCeoName(rawText);

    bool isValidNumber = false;
    bool isValidName = false;

    if (expectedBusinessNumber != null && extractedNumber != null) {
      final cleanedExtracted = extractedNumber.replaceAll(RegExp(r'\D'), '');
      final cleanedExpected =
          expectedBusinessNumber.replaceAll(RegExp(r'\D'), '');
      isValidNumber = cleanedExtracted == cleanedExpected;
      if (kDebugMode) {
        debugPrint(
            '📄 [사업자등록증 OCR] 번호 검증: ${isValidNumber ? "✅" : "❌"}');
      }
    }

    if (expectedCeoName != null && extractedName != null) {
      final cleanedExtracted = _cleanText(extractedName);
      final cleanedExpected = _cleanText(expectedCeoName);
      isValidName = cleanedExtracted == cleanedExpected;
      if (kDebugMode) {
        debugPrint(
            '📄 [사업자등록증 OCR] 이름 검증: ${isValidName ? "✅" : "❌"}');
      }
    }

    double confidence = 0.0;
    if (isValidNumber && isValidName) {
      confidence = 1.0;
    } else if (isValidNumber || isValidName) {
      confidence = 0.6;
    }

    return {
      'isValidNumber': isValidNumber,
      'isValidName': isValidName,
      'confidence': confidence,
      'extractedNumber': extractedNumber, // null if not found
      'extractedName': extractedName,     // null if not found
    };
  }

  /// 테스트 전용 — 사업자등록증 검증 로직 직접 실행 (ML Kit 없음)
  ///
  /// [visibleForTesting]: unit test에서만 호출.
  ///
  /// CALL GRAPH:
  ///   verifyBusinessLicenseForTesting(rawText, ...)
  ///     → _verifyBusinessLicenseFromText()   [production logic]
  ///       → _extractBusinessNumber(rawText)  [P1-003 FIX: boundary check]
  ///       → _extractCeoName(rawText)
  @visibleForTesting
  static Map<String, dynamic> verifyBusinessLicenseForTesting(
    String rawText,
    String? expectedBusinessNumber,
    String? expectedCeoName,
  ) =>
      _verifyBusinessLicenseFromText(
          rawText, expectedBusinessNumber, expectedCeoName);

  /// 테스트 전용 — _extractBusinessNumber 직접 호출
  ///
  /// [visibleForTesting]: unit test에서만 호출.
  @visibleForTesting
  static String? extractBusinessNumberForTesting(String rawText) =>
      _extractBusinessNumber(rawText);

  /// ✅ 사업자등록번호 추출 (법인등록번호 제외)
  ///
  /// [OCR-P1-003 FIX] fallback regex boundary check 추가:
  ///   매칭 전후에 연속 숫자가 이어지면 더 긴 숫자열(법인등록번호 13자리 등)의 일부 → 제외.
  ///   이전 버전: fullMatch.contains(\d{6}[-\s]?\d{7}) 방어만 존재 →
  ///     "110111-1234567"에서 index 1 시작 매칭 "101-11-12345"이 통과되는 버그.
  static String? _extractBusinessNumber(String text) {
    final lines = text.split('\n');

    for (final line in lines) {
      if (line.contains('법인') && line.contains('등록')) {
        continue;
      }

      if (line.contains('등록번호') || line.contains('등 록 번 호')) {
        final regExp = RegExp(r'(\d{3})[-\s]?(\d{2})[-\s]?(\d{5})');
        final match = regExp.firstMatch(line);
        if (match != null) {
          final number =
              '${match.group(1)}${match.group(2)}${match.group(3)}';
          if (number.length == 10) {
            return number;
          }
        }
      }
    }

    // [OCR-P1-003 FIX] 법인등록번호(13자리) 내부 substring 방어:
    // 매칭 전후에 연속 숫자가 이어지면 더 긴 숫자열의 일부 → 사업자번호 아님.
    // 예: "110111-1234567"에서 index 1 시작 → before='1'(digit) → SKIP.
    final regExp = RegExp(r'(\d{3})[-\s]?(\d{2})[-\s]?(\d{5})');
    for (final match in regExp.allMatches(text)) {
      final number = '${match.group(1)}${match.group(2)}${match.group(3)}';
      if (number.length == 10) {
        final before = match.start > 0 ? text[match.start - 1] : ' ';
        final after = match.end < text.length ? text[match.end] : ' ';
        if (RegExp(r'\d').hasMatch(before) || RegExp(r'\d').hasMatch(after)) {
          continue; // 더 긴 숫자열의 일부 → 사업자번호 아님
        }
        return number;
      }
    }

    return null;
  }

  /// ✅ 대표자명 추출
  static String? _extractCeoName(String text) {
    final lines = text.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.contains('대') && line.contains('표') && line.contains('자')) {
        final regExp = RegExp(r'[:\s]+([가-힣]{2,5})');
        final match = regExp.firstMatch(line);
        if (match != null) {
          return match.group(1)?.trim();
        }

        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1];
          final nextMatch =
              RegExp(r'[:\s]*([가-힣]{2,5})').firstMatch(nextLine);
          if (nextMatch != null) {
            return nextMatch.group(1)?.trim();
          }
        }
      }

      if (line.trim().startsWith('자') && line.contains(':')) {
        final regExp = RegExp(r'자\s*[:\s]+([가-힣]{2,5})');
        final match = regExp.firstMatch(line);
        if (match != null) {
          return match.group(1)?.trim();
        }
      }
    }

    return null;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 공통 유틸
  // ──────────────────────────────────────────────────────────────────────────

  /// 🧹 텍스트 정제
  static String _cleanText(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[^\w가-힣]'), '')
        .toLowerCase();
  }
}
