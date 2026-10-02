// lib/utils/ocr_verification_helper.dart

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'identity_identifier.dart';

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
        // [R7-P4.4E.10A] raw OCR 원문을 돌려주지 않는다 — debug 빌드에서도.
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
        // raw OCR 원문은 결과에 담지 않는다.
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
  /// 신분증에서 **라벨 옆의 이름**을 읽는다. 라벨이 없으면 추측하지 않는다.
  ///
  /// [R7-P4.4E.10A] 이름을 못 읽은 것과 다른 이름을 읽은 것을 가르기 위한
  ///   최소 구조다. 통장사본의 `_extractAccountHolder` 와 같은 축이다 —
  ///   **라벨 근거가 있을 때만** "읽었다" 고 말한다.
  ///   문서 전체에서 2~5자 한글을 주워 이름이라고 하지 않는다(그건 E9 에서
  ///   `보통예금`·`잔액확인` 을 예금주로 집어 왔던 실수다).
  static ({String? name, bool labeled}) _extractIdCardName(String rawText) {
    const labels = ['성명', '이름', '姓名', 'NAME', 'Name'];
    final lines = rawText.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final upper = line.toUpperCase();
      final hit = labels.firstWhere(
          (l) => upper.contains(l.toUpperCase()),
          orElse: () => '');
      if (hit.isEmpty) continue;

      // 같은 줄의 라벨 뒤, 없으면 다음 줄.
      final idx = upper.indexOf(hit.toUpperCase());
      final tail = line.substring(idx + hit.length);
      final sameLine = _firstNameToken(tail);
      if (sameLine != null) return (name: sameLine, labeled: true);
      if (i + 1 < lines.length) {
        final next = _firstNameToken(lines[i + 1]);
        if (next != null) return (name: next, labeled: true);
      }
    }
    return (name: null, labeled: false);
  }

  /// 이름으로 볼 수 있는 토큰 — 한글 2~5자 또는 영문 이름.
  static String? _firstNameToken(String s) {
    final ko = RegExp(r'[가-힣]{2,5}').firstMatch(s);
    if (ko != null) return ko.group(0);
    final en = RegExp(r'[A-Za-z]{2,}(?:\s+[A-Za-z]{2,})*').firstMatch(s);
    if (en != null) return en.group(0)!.trim();
    return null;
  }

  /// [R7-P4.4E.10A] 문서에서 읽은 **전체 13자리 후보**.
  ///
  ///   클라이언트는 이것으로 판정하지 않는다 — canonical 전체 번호는
  ///   서버에만 있고(`taxIdentities.identifierFingerprint`, 서버 HMAC),
  ///   클라이언트가 평문으로 복원할 수 없다. 그래서 **후보만** 서버에 넘기고
  ///   비교는 서버가 한다. 서버는 canonical 값을 돌려주지 않는다.
  ///
  ///   날짜·면허번호 같은 짧은 숫자는 13자리가 아니라 애초에 후보가 아니다.
  @visibleForTesting
  static List<String> fullIdentifierCandidates(String rawText) {
    final out = <String>{};
    // `YYMMDD-NNNNNNN` 또는 구분자 없는 13자리.
    //   구분자를 `[- ]` 로 제한한다 — `[-\s]` 는 **줄바꿈을 포함**해서
    //   서로 다른 줄의 `990101` 과 `1234567` 을 한 번호로 이어붙였다.
    //   (이 테스트가 그 거짓 후보를 잡아냈다.)
    for (final m in RegExp(r'(\d{6})[- ]?(\d{7})').allMatches(rawText)) {
      out.add('${m.group(1)}${m.group(2)}');
    }
    // OCR 이 숫자 사이에 잡음을 끼운 경우 — 한 줄 안의 숫자만 모아 본다.
    //   서로 무관한 숫자가 이어붙어 생기는 거짓 후보를 막기 위해 줄을 넘지
    //   않는다. 13자리가 정확히 될 때만 후보다.
    for (final line in rawText.split('\n')) {
      final digits = line.replaceAll(RegExp(r'\D'), '');
      if (digits.length == 13) out.add(digits);
    }
    return out.toList();
  }

  static Map<String, dynamic> _verifyIdCardFromText(
    String rawText,
    String expectedName, {
    String? expectedResidentNumber,
  }) {
    final cleanedOcr = _cleanText(rawText);
    final cleanedExpected = _cleanText(expectedName);

    // [PII-DOC-R1.2] 이름은 기대값이 없으면 비교하지 않는다.
    // [R7-P4.4E.10A] 못 읽은 것을 "다르다"고 말하지 않는다.
    //
    //   예전에는 `cleanedOcr.contains(expected)` 하나로 갈라서, 흐릿한
    //   사진이나 각도 때문에 이름을 못 읽으면 곧바로 **MISMATCH** 였다.
    //   서버는 `requireName: true` 로 그것을 그대로 `idCardMatchStatus =
    //   MISMATCH` 로 기록하고, 사용자는 정상 문서로 "일치하지 않습니다" 를
    //   봤다. 소비처(`document_upload_helper`)는 이미 `name == unreadable`
    //   분기를 갖고 있었지만 parser 가 그 값을 만들지 않아 **도달할 수 없는
    //   분기**였다.
    //
    //   MISMATCH 는 **라벨 옆에서 다른 이름을 읽어냈을 때만** 말한다.
    //   fuzzy 비교는 하지 않는다 — 비슷한 이름을 같다고 하지 않는다.
    final bool nameAssessable = cleanedExpected.isNotEmpty;
    final nameRead = _extractIdCardName(rawText);
    final isNameValid = nameAssessable && cleanedOcr.contains(cleanedExpected);
    final DocFieldOutcome nameOutcome;
    if (!nameAssessable) {
      nameOutcome = DocFieldOutcome.unassessed;
    } else if (isNameValid) {
      nameOutcome = DocFieldOutcome.matched;
    } else if (nameRead.labeled &&
        nameRead.name != null &&
        _cleanText(nameRead.name!) != cleanedExpected) {
      // 이름 칸에서 읽어낸 값이 기대와 다르다 — 근거 있는 불일치다.
      nameOutcome = DocFieldOutcome.mismatch;
    } else {
      // 이름 칸을 찾지 못했거나 읽어낸 것이 없다 — 다르다고 말할 근거가 없다.
      nameOutcome = DocFieldOutcome.unreadable;
    }

    // [PII-DOC-R1.2 / INV-1] 검사하지 않은 값을 true로 만들지 않는다.
    //
    //   여기 있던 `bool isResidentNumberValid = true;`가 R1-B3의 전부였다.
    //   기대값이 없으면 if 블록에 들어가지 않고 그 기본값이 그대로
    //   `identifierMatched = true`가 되어 SELF_CHECK_PASSED까지 올라갔다.
    //   V3 외국인은 birthDate·gender가 null이라 **항상** 이 경로였다.
    //
    //   이제 기대값이 없으면 UNASSESSED다. 비교하지 않았다는 사실이 남는다.
    DocFieldOutcome identifierOutcome = DocFieldOutcome.unassessed;
    bool isResidentNumberValid = false;
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

      // [R7-P4.4E.10A] **앞 7자리로는 일치를 선언하지 않는다.**
      //
      //   등록 경로가 넘기던 기대값은 `YYMMDD-C` 7자리였다(birthDate+gender
      //   파생). 그건 개인 식별값이 아니다 — 같은 날 태어난 같은 성별이면
      //   누구의 신분증이든 일치했다. 그런데도 `identifierOutcome = MATCHED`
      //   까지 올라가 canonical `idCardMatchStatus = MATCHED` 가 됐다.
      //
      //   그리고 7자리 패턴(`(\d{6})[-\s]?(\d)`)은 날짜·면허번호·전화 조각에
      //   거의 항상 걸려서 `anyCandidate` 가 늘 참이었다 — 못 읽어도
      //   UNREADABLE 이 아니라 MISMATCH 였다.
      //
      //   이제 전체 13자리 기대값이 없으면 **판정하지 않는다**(UNASSESSED).
      //   비교하지 않았다는 사실이 남고, 서버는 그것을 MATCHED 로 읽지 않는다.
      if (cleanedExpectedRN.length != 13) {
        return {
          'isValid': false,
          'isNameValid': isNameValid,
          'isResidentNumberValid': false,
          'nameOutcome': nameOutcome,
          'identifierOutcome': DocFieldOutcome.unassessed,
          'confidence': 0.0,
          'extractedName': null,
          'extractedResidentNumber': null,
          // 클라이언트는 판정하지 않는다 — **서버가** canonical 지문과
          //   대조한다. 여기서는 문서에서 읽은 13자리 후보만 넘긴다.
          'identifierCandidates': fullIdentifierCandidates(rawText),
        };
      }
      // [PII-B4-R1.4 §30·§31] 기대값이 전체 13자리면 전체를 대조한다.
      //
      //   기대값 길이로 분기하는 이유: 기준을 아는 쪽이 비교 범위를 정해야
      //   한다. 자유 추출로 "이게 주민번호겠지"를 고르면 운전면허증의
      //   면허번호를 집어 올 수 있다. 기대값과 같은 후보만 찾으면 그 위험이
      //   구조적으로 없다 — 다른 숫자군은 애초에 일치하지 않는다.
      //
      //   [R7-P4.4E.10A] 7자리 패턴은 **없앴다.** 위 early-return 이
      //   전체 13자리가 아닌 기대값을 이미 걸러내므로 여기 오는 기대값은
      //   항상 13자리다. 7자리 패턴을 남겨 두면 날짜·면허번호 조각이
      //   "번호를 읽었다" 로 세어져 UNREADABLE 이 가려진다.
      final residentPattern = RegExp(r'(\d{6})[- ]?(\d{7})');
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
      // [§31] 줄 단위 2차 대조 — OCR이 숫자 사이에 잡음을 끼워 넣으면
      //   위 패턴이 끊긴다. 한 줄 안에서만 숫자를 모아 보는 것이므로
      //   서로 무관한 숫자가 이어붙어 생기는 거짓 일치는 없다.
      if (matchedCandidate == null) {
        for (final line in rawText.split('\n')) {
          if (line.replaceAll(RegExp(r'\D'), '') == cleanedExpectedRN) {
            matchedCandidate = cleanedExpectedRN;
            break;
          }
        }
      }
      // [PII-DOC-R1.2 / §6] 비교는 했는데 서류에서 번호를 **하나도 못 읽은** 경우와
      //   읽었는데 다른 경우를 구분한다. 전자는 불일치가 아니라 인식 실패다.
      final anyCandidate = residentPattern.hasMatch(rawText);
      isResidentNumberValid = matchedCandidate != null;
      extractedResidentNumber = matchedCandidate;
      identifierOutcome = isResidentNumberValid
          ? DocFieldOutcome.matched
          : (anyCandidate
              ? DocFieldOutcome.mismatch
              : DocFieldOutcome.unreadable);
    }

    // isValid는 "전부 확인됐고 전부 일치" — UNASSESSED는 통과가 아니다.
    final isValid = nameOutcome == DocFieldOutcome.matched &&
        identifierOutcome == DocFieldOutcome.matched;

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
      // [PII-DOC-R1.2] 판정 결과 어휘 — bool 두 개로는 "안 맞음"과 "안 봄"이
      //   구분되지 않는다. consumer는 이 값을 쓴다.
      'nameOutcome': nameOutcome,
      'identifierOutcome': identifierOutcome,
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
        // [R7-P4.4E.10A] raw OCR 원문을 돌려주지 않는다 — debug 빌드에서도.
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [통장사본 OCR] 실패: $e');
      return {
        'isDocumentConsistent': false,
        // OCR 자체가 실패했다 — 판정한 것이 없다.
        'holderOutcome': DocFieldOutcome.unassessed,
        'accountOutcome': DocFieldOutcome.unassessed,
        'bankOutcome': DocFieldOutcome.unassessed,
        'isNameValid': false,
        'isAccountValid': false,
        'isBankValid': false,
        'confidence': 0.0,
        'extractedName': null,
        'extractedAccountNumber': null,
        'extractedBankName': null,
        // raw OCR 원문은 결과에 담지 않는다.
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
    final holderRead = _extractAccountHolder(rawText, recognizedText);
    final String? extractedName = holderRead.name;

    // ✅ 은행명 추출 — canonical 우선, 없으면 기존 패턴 폴백
    String? extractedBankName =
        canonicalBankOf(rawText) ?? _extractBankName(rawText);

    // ✅ 검증
    final cleanedOcr = _cleanText(rawText);

    // 1. 예금주 — [PII-DOC-R1.3 / PD-2] 명백한 불일치만 실패로 본다.
    //
    //   OCR로 사람 이름을 안정적으로 읽어내는 것은 어렵고, 외국인 영문/한글
    //   표기 차이를 음차로 억지 일치시키지도 않는다. 그래서 예금주는
    //   **supporting evidence**다 — 일치하면 힘을 보태고, 못 읽으면 그것으로
    //   전체를 실패시키지 않으며, 명백히 다를 때만 불일치다.
    //
    //   MISMATCH 판정은 보수적으로 한다: 예금주 칸을 읽어냈고, 그 값이 다르고,
    //   기대 이름이 문서 **어디에도** 없을 때만. label 기반 추출이 엉뚱한 줄을
    //   잡았을 수 있으므로 문서 전체를 한 번 더 본다.
    final DocFieldOutcome holderOutcome;
    if (expectedName == null || expectedName.isEmpty) {
      holderOutcome = DocFieldOutcome.unassessed;
    } else if (cleanedOcr.contains(_cleanText(expectedName))) {
      holderOutcome = DocFieldOutcome.matched;
    } else if (holderRead.labeled &&
        extractedName != null && extractedName.isNotEmpty) {
      // 라벨 옆에서 읽은 이름이 기대와 다르다 — 이건 근거 있는 불일치다.
      holderOutcome = DocFieldOutcome.mismatch;
    } else {
      // 못 읽었거나, 추측으로 집어온 값뿐이다 — 다르다고 말하지 않는다.
      holderOutcome = DocFieldOutcome.unreadable;
    }
    final isNameValid = holderOutcome == DocFieldOutcome.matched;
    if (kDebugMode) {
      debugPrint('📄 [통장사본 OCR] 예금주: ${holderOutcome.wire}');
    }

    // 2. 계좌번호 검증 — [R7-P4.4E.9A] 후보 수집 + 문맥 분류 + expected 대조
    //
    //   후보를 segment 개수에 고정하지 않고 모으고, 전화·고객센터·날짜로
    //   분류된 것은 "계좌번호를 읽었다" 로 세지 않는다. 그래서 계좌를
    //   못 읽었을 때 MISMATCH 가 아니라 UNREADABLE 이 된다.
    //   판정은 evaluateAccount 한 곳이 한다.
    final acct = evaluateAccount(
      rawText: rawText,
      expectedAccountNumber: expectedAccountNumber,
    );
    final DocFieldOutcome accountOutcome = acct.outcome;
    final String? extractedAccountNumber = acct.extracted;
    if (expectedAccountNumber != null && expectedAccountNumber.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('📄 [통장사본 OCR] 계좌번호: ${accountOutcome.wire}');
      }
    }
    final isAccountValid = accountOutcome == DocFieldOutcome.matched;

    // 3. 은행명 — [PD-3] supporting evidence. 성공 조건에 넣지 않는다.
    //   현재 은행명 인식 범위가 저축은행·신협·증권사 CMA 등에서 불완전하다.
    final DocFieldOutcome bankOutcome;
    if (expectedBankName == null || expectedBankName.isEmpty) {
      bankOutcome = DocFieldOutcome.unassessed;
    } else {
      final cleanedExpectedBank = _cleanText(expectedBankName);
      final cleanedExtractedBank = _cleanText(extractedBankName ?? '');
      final found = cleanedOcr.contains(cleanedExpectedBank) ||
          cleanedExtractedBank.contains(cleanedExpectedBank);
      bankOutcome = found
          ? DocFieldOutcome.matched
          : (extractedBankName == null
              ? DocFieldOutcome.unreadable
              : DocFieldOutcome.mismatch);
    }
    final isBankValid = bankOutcome != DocFieldOutcome.mismatch;

    // ── 종합 판정 ────────────────────────────────────────────────
    // [PII-DOC-R1.3 / INV-2] 점수 평균이 정오를 정하지 않는다.
    //
    //   이전 규칙은 `isValid = isNameValid`였고, 실제 성공 여부는
    //   `confidence >= 0.6`이 결정했다. 계좌번호가 달라도 분모가 커지면
    //   (예: 은행명을 expected에 추가하면 2/3 = 0.67) 다시 성공이 됐다.
    //   지금 걸리지 않는 것은 호출부가 은행명을 안 넘기기 때문일 뿐,
    //   구조가 막고 있던 게 아니다.
    //
    //   이름을 좁힌다: 이것은 "문서가 입력값과 일치한다"이지
    //   은행 실명인증도 계좌 소유 확인도 아니다. (INV-5)
    final isDocumentConsistent = accountOutcome == DocFieldOutcome.matched &&
        holderOutcome != DocFieldOutcome.mismatch;

    // confidence는 UI 참고용으로만 남긴다 — 판정에 쓰지 않는다.
    int assessed = 0, agreed = 0;
    for (final o in [holderOutcome, accountOutcome, bankOutcome]) {
      if (o == DocFieldOutcome.unassessed) continue;
      assessed++;
      if (o == DocFieldOutcome.matched) agreed++;
    }
    final confidence = assessed == 0 ? 0.0 : agreed / assessed;

    return {
      'isDocumentConsistent': isDocumentConsistent,
      'holderOutcome': holderOutcome,
      'accountOutcome': accountOutcome,
      'bankOutcome': bankOutcome,
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
      _extractAccountHolder(rawText).name;

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
  /// [PII-DOC-R1.3] 이름과 함께 **얼마나 믿을 만하게 찾았는지**를 돌려준다.
  ///
  ///   `labeled == true`는 '예금주'/'계좌주' 라벨 옆에서 읽었다는 뜻이다.
  ///   Step 2(첫 줄)·Step 3(단독 블록)은 추측이다 — 실제로 "국민은행"처럼
  ///   2~5자 한글 은행명을 예금주로 집어 온다. 그 추측으로 MISMATCH를
  ///   선언하면 멀쩡한 통장을 "예금주가 다릅니다"로 돌려보내게 된다. (INV-3)
  static ({String? name, bool labeled}) _extractAccountHolder(String rawText,
      [RecognizedText? recognizedText]) {
    final lines = rawText.split('\n');

    // 1. "예금주" 키워드 근처에서 찾기 — 유일하게 근거가 있는 경로
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('예금주') || line.contains('계좌주')) {
        // 같은 줄에서 이름 추출 (예: "예금주: 홍길동")
        final colonIndex = line.indexOf(':');
        if (colonIndex != -1) {
          final afterColon = line.substring(colonIndex + 1).trim();
          final nameMatch = RegExp(r'[가-힣]{2,5}').firstMatch(afterColon);
          if (nameMatch != null) {
            return (name: nameMatch.group(0), labeled: true);
          }
        }

        // 라벨 뒤에 바로 이름이 오는 경우 (예: "예금주 홍길동")
        final inline = RegExp(r'(?:예금주|계좌주)\s*[:：]?\s*([가-힣]{2,5})')
            .firstMatch(line);
        if (inline != null) {
          return (name: inline.group(1), labeled: true);
        }

        // 다음 줄에서 이름 찾기
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          final nameMatch = RegExp(r'^[가-힣]{2,5}$').firstMatch(nextLine);
          if (nameMatch != null) {
            return (name: nameMatch.group(0), labeled: true);
          }
        }
      }
    }

    // 2. 첫 번째 줄이 한글 이름(2-5자)인 경우 — **추측**
    if (lines.isNotEmpty) {
      final firstLine = lines[0].trim();
      if (RegExp(r'^[가-힣]{2,5}$').hasMatch(firstLine)) {
        return (name: firstLine, labeled: false);
      }
    }

    // 3. 블록 단위로 스캔 - 단독 한글 이름 찾기 — **추측**
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
            return (name: text, labeled: false);
          }
        }
      }
    }

    // Step 4 제거 — [OCR-P1-001 FIX]
    // 전체 텍스트에서 2~5자 한글을 추측하는 fallback 제거.
    // 제외 키워드 목록이 불완전하여 "보통예금", "잔액확인", "고객센터" 등 오인식.
    return (name: null, labeled: false);
  }

  /// ✅ 은행명 추출
  // ──────────────────────────────────────────────────────────────────────────
  // [R7-P4.4E.9A] 통장사본 숫자 후보 — 모으고, 분류하고, 대조한다
  //
  //   예전 구조는 **세 그룹 고정** 정규식 둘뿐이었다.
  //     (\d{3,4})[-\s](\d{4,6})[-\s](\d{4,6})
  //     (\d{2,4})[-\s](\d{2,4})[-\s](\d{4,7})
  //   그래서 구분자가 셋인 계좌번호(`010-123456-01-017`)는 **어떤 패턴에도
  //   맞지 않았다.** 게다가 `계좌번호` 라벨이 있는 줄에서는 greedy 패턴이
  //   `010-123456-01` 까지만 잘라 읽고 "계좌번호처럼 보이는 것을 읽었다"를
  //   세웠다 — 결과는 UNREADABLE 이 아니라 **MISMATCH** 였다.
  //   정상 서류·정상 입력으로 "통장사본의 계좌번호가 일치하지 않습니다 /
  //   인식: 확인 불가" 를 보게 되는 자리다.
  //
  //   두 번째 결함: 휴대전화 `010-1234-5678` 도 그 세 그룹 패턴에 맞아
  //   같은 플래그를 세웠다. 계좌를 못 읽었는데 MISMATCH 가 됐다 —
  //   `OCR 실패 != MISMATCH` 를 깨는 자리다.
  //
  //   여기서 바꾸는 것은 **후보를 모으는 방식과 "읽었다"의 뜻**이다.
  //   OCR 이 읽은 글자를 고쳐 쓰지는 않는다(O→0 같은 복원 금지) —
  //   확신이 없으면 "읽지 못했다" 가 원칙이다.

  /// 숫자 후보 하나.
  @visibleForTesting
  static const int accountMinDigits = 9;

  /// 계좌번호로 볼 수 있는 자릿수 상한. 너무 긴 것은 참조번호·카드번호다.
  @visibleForTesting
  static const int accountMaxDigits = 20;

  /// 계좌 의미가 확인되는 라벨.
  static const List<String> _accountPositiveLabels = [
    '계좌번호', '계좌 번호', '예금계좌', '입출금계좌', '평생계좌',
    'ACCOUNT', 'A/C',
  ];

  /// 계좌가 아니라고 말하는 문맥.
  static const List<String> _accountNegativeLabels = [
    '고객센터', '상담', '문의', '대표전화', '지점 전화', '전화',
    'TEL', 'FAX', 'T.', '콜센터',
  ];

  /// 날짜로 보이는 문맥·형태.
  static final RegExp _datePattern = RegExp(
      r'(19|20)\d{2}[-.\/](0?[1-9]|1[0-2])[-.\/](0?[1-9]|[12]\d|3[01])');

  /// 숫자 후보 — 구분자(하이픈·공백) 개수에 **고정되지 않는다.**
  ///
  ///   `010-123456-01-017` · `010 123456 01 017` · `01012345601017` ·
  ///   5-segment 까지 같은 규칙으로 모인다.
  static final RegExp _numericCandidatePattern =
      RegExp(r'\d[\d\-\s]{6,}\d');

  /// 후보 하나의 판정.
  static ({
    String raw,
    String digits,
    String line,
    bool positive,
    bool negative,
    bool dateLike,
  }) _classifyCandidate(String raw, String line) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final upper = line.toUpperCase();
    final positive =
        _accountPositiveLabels.any((l) => upper.contains(l.toUpperCase()));
    final negative =
        _accountNegativeLabels.any((l) => upper.contains(l.toUpperCase()));
    final dateLike = _datePattern.hasMatch(raw) || _datePattern.hasMatch(line);
    return (
      raw: raw.trim(),
      digits: digits,
      line: line.trim(),
      positive: positive,
      negative: negative,
      dateLike: dateLike,
    );
  }

  /// 전화번호로 **강하게** 보이는가.
  ///
  ///   `010-` 접두만으로 정하지 않는다 — 계좌번호가 그 접두를 쓸 수 있다
  ///   (실제로 기업은행 계좌가 `010-` 으로 시작한다). 번호 형태와 문맥을
  ///   **함께** 본다: 부정 라벨이 있거나, 휴대전화/대표번호의 전형적 자릿수다.
  static bool _looksLikePhone({
    required String digits,
    required bool negative,
    required bool positive,
  }) {
    if (positive) return false; // 계좌 라벨이 이긴다
    if (negative) return true; // 고객센터·전화 문맥이면 전화다
    // 라벨이 없을 때만 형태로 본다.
    if (digits.length == 11 && digits.startsWith('01')) return true; // 휴대전화
    if (digits.length == 10 && digits.startsWith('01')) return true;
    if (digits.length == 8) return true; // 1588-2588 류 대표번호
    if (digits.length == 9 && digits.startsWith('02')) return true;
    return false;
  }

  /// 통장사본 OCR 텍스트에서 **쓸 수 있는 계좌 후보**를 모은다.
  ///
  ///   돌려주는 것은 (계좌 후보, 제외된 후보) 두 묶음이다. 제외된 것만
  ///   남았다면 그것은 "계좌번호를 읽었다" 가 아니다 — UNREADABLE 이다.
  @visibleForTesting
  static ({
    List<String> usableAccountCandidates,
    List<String> rejectedNonAccountCandidates,
  }) collectAccountCandidates(String rawText) {
    final usable = <String>[];
    final rejected = <String>[];

    for (final line in rawText.split('\n')) {
      for (final m in _numericCandidatePattern.allMatches(line)) {
        final c = _classifyCandidate(m.group(0) ?? '', line);
        if (c.digits.length < accountMinDigits ||
            c.digits.length > accountMaxDigits) {
          rejected.add(c.digits);
          continue;
        }
        if (c.dateLike) {
          rejected.add(c.digits);
          continue;
        }
        if (_looksLikePhone(
            digits: c.digits, negative: c.negative, positive: c.positive)) {
          rejected.add(c.digits);
          continue;
        }
        usable.add(c.digits);
      }
    }
    return (
      usableAccountCandidates: usable,
      rejectedNonAccountCandidates: rejected,
    );
  }

  /// 계좌번호 판정. **expected 와의 정확 일치가 가장 강한 증거다.**
  ///
  ///   문서에서 "아무 계좌번호나 찾기" 가 목적이 아니다 — 사용자가 이미
  ///   입력한 계좌가 이 서류 안에 있는지 확인하는 것이다. 그래서 전화번호가
  ///   먼저 등장했다는 이유로 실패하지 않는다.
  @visibleForTesting
  static ({DocFieldOutcome outcome, String? extracted}) evaluateAccount({
    required String rawText,
    required String? expectedAccountNumber,
  }) {
    if (expectedAccountNumber == null || expectedAccountNumber.isEmpty) {
      return (outcome: DocFieldOutcome.unassessed, extracted: null);
    }
    final expected = expectedAccountNumber.replaceAll(RegExp(r'\D'), '');
    if (expected.isEmpty) {
      return (outcome: DocFieldOutcome.unassessed, extracted: null);
    }

    final found = collectAccountCandidates(rawText);

    // 1) expected 와 정확히 같은 **계좌 후보**가 있으면 그것이 답이다.
    //
    //    [R7-P4.4E.9A.1] 제외된 후보까지 보던 것을 걷었다. 그 경로는
    //    거짓 일치를 만들 수 있었다 — 통장 표지에 `고객센터 1588-2588` 만
    //    있고 사용자가 계좌번호를 `15882588` 로 잘못 입력하면, 숫자가 같다는
    //    이유만으로 MATCHED 가 됐다. **문서는 그 값을 계좌라고 말하지
    //    않았다.** 일치의 근거는 "같은 숫자가 어딘가 있다" 가 아니라
    //    "문서가 계좌번호라고 말한 값과 같다" 다.
    //
    //    계좌 라벨(`계좌번호`·`평생계좌`·`ACCOUNT` 등)이 붙은 숫자는 전화처럼
    //    생겼어도 usable 이다 — 계좌 의미가 형태 추정을 이긴다.
    if (found.usableAccountCandidates.contains(expected)) {
      return (outcome: DocFieldOutcome.matched, extracted: expectedAccountNumber);
    }

    // 2) 쓸 수 있는 계좌 후보를 하나도 못 모았다 — 다르다고 말할 근거가 없다.
    if (found.usableAccountCandidates.isEmpty) {
      return (outcome: DocFieldOutcome.unreadable, extracted: null);
    }

    // 3) 계좌 후보를 읽었는데 입력값과 다르다 — 근거 있는 불일치다.
    return (outcome: DocFieldOutcome.mismatch, extracted: null);
  }

  // ──────────────────────────────────────────────────────────────────────────

  /// [R7-P4.4E.9A] 은행 alias → canonical.
  ///
  ///   예전에는 substring 목록에서 **맞은 alias 문자열을 그대로** 돌려줬다.
  ///   그래서 사용자가 `IBK기업은행` 을 골랐고 서류에 `중소기업은행` 이
  ///   적혀 있으면 "은행명이 다르다" 가 됐다. 은행은 supporting evidence
  ///   이므로 사용자를 막지는 않았지만, 화면에 거짓을 말했다.
  ///   긴 alias 를 먼저 본다 — `기업은행` 이 `중소기업은행` 을 가로채지 않도록.
  ///   [R7-P4.4E.9A.1] canonical 은 **제품의 금융기관 목록**
  ///   (`document_management_screen.dart` 의 `AppSelectGroup`)에 실제로 있는
  ///   이름만 쓴다. 그 목록이 사용자가 고르고 `users.bankName` 에 저장되는
  ///   값이다 — bank code 는 없다.
  ///
  ///   **alias 는 같은 기관의 이름 차이만 합친다.** 편의를 위해 서로 다른
  ///   금융기관을 하나로 만들지 않는다. 그래서 다음을 뺐다:
  ///     · `KB` — 목록에 **`KB증권`** 이 따로 있다. 두 글자 토큰으로 묶으면
  ///       증권사 서류가 은행으로 정규화된다.
  ///     · `SC` — 두 글자 토큰이라 본문 아무 데나 걸린다.
  ///     · `단위농협` — 지역농축협은 `NH농협은행` 과 **다른 기관**이고
  ///       목록에도 항목이 없다. 합치면 기관 병합이 된다.
  ///   목록에 없는 기관(증권사·씨티·산업은행·신협·저축은행 등)은 여기 넣지
  ///   않는다 — 매칭이 안 되면 `UNREADABLE` 이 되고, 그게 엉뚱한 은행으로
  ///   정규화되는 것보다 낫다.
  static const Map<String, List<String>> bankAliases = {
    'KB국민은행': ['KB국민은행', '국민은행'],
    '신한은행': ['신한은행'],
    // 목록에는 `NH농협은행` 하나뿐이다. 지역농축협은 합치지 않는다.
    //   bare `농협` 은 쓰지 않는다 — `단위농협`·`지역농축협` 의 부분문자열이라
    //   substring 으로 묶으면 **다른 기관이 NH농협은행이 된다.**
    //   `농협` 만 적힌 서류는 은행을 못 읽은 것으로 둔다(supporting-only 이므로
    //   사용자를 막지 않는다).
    'NH농협은행': ['NH농협은행', '농협은행'],
    '우리은행': ['우리은행'],
    '하나은행': ['KEB하나은행', '하나은행'],
    'IBK기업은행': [
      'IBK Industrial Bank of Korea',
      'Industrial Bank of Korea',
      'IBK기업은행',
      '중소기업은행',
      '기업은행',
      'IBK',
    ],
    'SC제일은행': ['SC제일은행', '제일은행'],
    '카카오뱅크': ['카카오뱅크'],
    '토스뱅크': ['토스뱅크'],
    '케이뱅크': ['케이뱅크', 'K뱅크'],
    '새마을금고': ['MG새마을금고', '새마을금고'],
    '우체국': ['우체국예금', '우체국'],
    '수협은행': ['수협은행', '수협'],
    // 같은 기관의 브랜드 변경(DGB대구은행 → iM뱅크).
    '대구은행': ['DGB대구은행', 'iM뱅크', '대구은행'],
    '부산은행': ['부산은행'],
    '경남은행': ['경남은행'],
    '광주은행': ['광주은행'],
    '전북은행': ['전북은행'],
    '제주은행': ['제주은행'],
  };

  /// [rawText] 안의 은행을 canonical 이름으로 돌려준다.
  @visibleForTesting
  static String? canonicalBankOf(String rawText) {
    final upper = rawText.toUpperCase();
    String? best;
    int bestLen = 0;
    for (final entry in bankAliases.entries) {
      for (final alias in entry.value) {
        if (upper.contains(alias.toUpperCase()) && alias.length > bestLen) {
          best = entry.key;
          bestLen = alias.length;
        }
      }
    }
    return best;
  }

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
  // ────────────────────────────────────────────────────────────────────
  // [R7-P4.3B DOC-03] 사업자등록증 precheck
  //
  //   실기기에서 확인된 것: 사업장 등록에서 **아무 이미지나** 골라도
  //   그대로 다음 단계로 넘어갔다. 완료 조건이 `File != null` 이었기
  //   때문이다 — 무엇이 찍힌 이미지인지는 아무도 보지 않았다.
  //
  //   아래는 **공식 진위 확인이 아니다.** 국세청 조회도, 정부 인증도
  //   아니다. 목적은 셋뿐이다:
  //     ① 명백히 사업자등록증이 아닌 이미지를 거른다
  //     ② 읽을 수 없는 이미지는 재촬영을 유도한다
  //     ③ 읽힌 사업자등록번호를 사용자가 입력한 번호와 대조한다
  //   그래서 결과 이름에도 '인증·검증 완료' 라는 말을 쓰지 않는다.

  /// 사업자등록증 precheck 결과. 각각 **사용자가 할 일이 다르다.**
  static const String checkPassed = 'passed';

  /// 서류로는 보이는데 글자를 거의 읽지 못했다 → 다시 촬영.
  static const String checkUnreadable = 'unreadable';

  /// 사업자등록증으로 보기 어려운 이미지다 → 다른 서류를 등록.
  static const String checkNotDocument = 'not_document';

  /// 서류는 맞는데 번호가 입력값과 다르다 → 입력이나 서류를 확인.
  static const String checkNumberMismatch = 'number_mismatch';

  /// 서류는 맞는데 번호를 못 읽었다 → 다시 촬영.
  static const String checkNumberUnread = 'number_unread';

  /// [R7-P4.3B] 이 이미지가 사업자등록증으로 보이는가.
  ///
  ///   **문자 수로 판단하지 않는다.** 영수증·명함·배송라벨도 사업자등록
  ///   번호를 찍는 경우가 많아서, 번호가 있다는 사실만으로는 서류를
  ///   구별할 수 없다. 증서에만 나오는 항목을 본다.
  ///
  ///   - 제목(`사업자등록증`) 하나면 충분하다.
  ///   - 발급 주체(`세무서장`/`국세청`)도 증서에만 있다.
  ///   - 둘 다 못 읽었으면, 증서 고유 항목(`업태`·`종목`·`개업연월일`)이
  ///     둘 이상이면서 기본 항목(`상호`·`대표자`·`등록번호`·`소재지`)도
  ///     둘 이상일 때만 서류로 본다. 영수증은 보통 업태·종목·개업연월일을
  ///     함께 적지 않는다.
  static bool looksLikeBusinessLicense(String rawText) {
    final t = rawText.replaceAll(RegExp(r'\s+'), '');
    if (t.contains('사업자등록증')) return true;
    if (t.contains('세무서장') || t.contains('국세청')) return true;

    int count(List<String> tokens) =>
        tokens.where((k) => t.contains(k)).length;

    final certFields = count(const ['업태', '종목', '개업연월일', '개업일']);
    final basicFields =
        count(const ['상호', '법인명', '대표자', '등록번호', '소재지', '사업장']);
    return certFields >= 2 && basicFields >= 2;
  }

  /// [R7-P4.3B] OCR 원문 → precheck 상태. ML Kit 호출 없음(테스트 가능).
  static String businessLicenseCheckFromText(
    String rawText,
    String? expectedBusinessNumber,
  ) {
    final looksLike = looksLikeBusinessLicense(rawText);
    if (!looksLike) {
      // 글자 자체를 거의 못 읽은 것과 "다른 문서"를 구별한다.
      //   길이는 **통과 근거로 쓰지 않는다** — 둘 다 실패이고, 두 실패
      //   메시지를 가르는 데만 쓴다(재촬영이냐, 다른 서류냐).
      //
      //   기준을 10자로 둔 이유: 간판 하나 찍힌 풍경 사진도 스무 자쯤은
      //   읽힌다. 그건 "못 읽은" 것이 아니라 **사업자등록증이 아닌** 것이라
      //   다시 찍으라고 하면 안 된다. 열 자도 안 나온 경우만 재촬영이다.
      final dense = rawText.replaceAll(RegExp(r'\s+'), '');
      return dense.length < 10 ? checkUnreadable : checkNotDocument;
    }

    final extracted = _extractBusinessNumber(rawText);
    if (extracted == null) return checkNumberUnread;

    final expected = (expectedBusinessNumber ?? '').replaceAll(RegExp(r'\D'), '');
    if (expected.isEmpty) {
      // 비교할 입력이 없다 — 서류로는 보이므로 막지 않는다.
      return checkPassed;
    }
    return extracted.replaceAll(RegExp(r'\D'), '') == expected
        ? checkPassed
        : checkNumberMismatch;
  }

  /// [R7-P4.3B] 이미지 파일 → precheck 상태.
  ///
  /// 반환: `{'status': ..., 'extractedNumber': ...}`.
  /// OCR 원문은 돌려주지 않는다 — 사업정보가 로그·state 에 남지 않게.
  static Future<Map<String, dynamic>> precheckBusinessLicense(
    String imagePath,
    String? expectedBusinessNumber,
  ) async {
    TextRecognizer? textRecognizer;
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
      final recognized = await textRecognizer.processImage(inputImage);
      final rawText = recognized.text;
      if (kDebugMode) {
        debugPrint('📄 [사업자등록증 precheck] 텍스트 길이: ${rawText.length}');
      }
      final status =
          businessLicenseCheckFromText(rawText, expectedBusinessNumber);
      return {
        'status': status,
        // 뒷자리는 남기지 않는다 — 불일치 안내에만 쓰는 앞 3자리.
        'numberPrefix': _extractBusinessNumber(rawText)
            ?.replaceAll(RegExp(r'\D'), '')
            .padRight(3)
            .substring(0, 3),
      };
    } catch (e) {
      // OCR 자체가 실패했다. **통과로 바꾸지 않는다.**
      debugPrint('❌ [사업자등록증 precheck] 실패: $e');
      return {'status': checkUnreadable, 'numberPrefix': null};
    } finally {
      textRecognizer?.close();
    }
  }

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
        // [R7-P4.4E.10A] raw OCR 원문을 돌려주지 않는다 — debug 빌드에서도.
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [사업자등록증 OCR] 실패: $e');
      return {
        'isValidNumber': false,
        'isValidName': false,
        'confidence': 0.0,
        'extractedNumber': null,
        'extractedName': null,
        // raw OCR 원문은 결과에 담지 않는다.
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
