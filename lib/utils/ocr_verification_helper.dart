// lib/utils/ocr_verification_helper.dart

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// 📄 OCR 기반 서류 검증 헬퍼 클래스
class OcrVerificationHelper {
  
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
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      
      final rawText = recognizedText.text;
      print('📄 [신분증 OCR] 원본: $rawText');
      
      final cleanedOcr = _cleanText(rawText);
      final cleanedExpected = _cleanText(expectedName);
      
      print('📄 [신분증 OCR] 정제됨: $cleanedOcr');
      print('📄 [신분증 OCR] 예상 이름: $cleanedExpected');
      
      final isNameValid = cleanedOcr.contains(cleanedExpected);
      
      bool isResidentNumberValid = true;
      String? extractedResidentNumber;
      
      if (expectedResidentNumber != null && expectedResidentNumber.isNotEmpty) {
        final residentPattern = RegExp(r'(\d{6})[-\s]?(\d)');
        final matches = residentPattern.allMatches(rawText);
        
        if (matches.isNotEmpty) {
          final match = matches.first;
          final front = match.group(1);
          final back = match.group(2);
          extractedResidentNumber = '$front-$back';
          
          print('📄 [신분증 OCR] 추출된 주민번호: $extractedResidentNumber');
          
          final cleanedExtracted = extractedResidentNumber.replaceAll(RegExp(r'\D'), '');
          final cleanedExpectedRN = expectedResidentNumber.replaceAll(RegExp(r'\D'), '');
          
          isResidentNumberValid = cleanedExtracted == cleanedExpectedRN;
          
          print('📄 [신분증 OCR] 주민번호 검증: ${isResidentNumberValid ? "✅" : "❌"}');
        } else {
          isResidentNumberValid = false;
          print('📄 [신분증 OCR] 주민번호 인식 실패');
        }
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
        'extractedName': cleanedExpected,
        'extractedResidentNumber': extractedResidentNumber ?? '',
        'rawText': rawText,
      };
      
    } catch (e) {
      print('❌ [신분증 OCR] 실패: $e');
      return {
        'isValid': false,
        'isNameValid': false,
        'isResidentNumberValid': false,
        'confidence': 0.0,
        'extractedName': '',
        'extractedResidentNumber': '',
        'rawText': '',
        'error': e.toString(),
      };
    } finally {
      textRecognizer?.close();
    }
  }
  
  /// 💳 통장사본 검증 (예금주 + 계좌번호 + 은행명)
  /// 
  /// [imagePath]: 통장사본 이미지 경로
  /// [expectedName]: 예상 예금주명
  /// [expectedAccountNumber]: 예상 계좌번호 (선택)
  /// [expectedBankName]: 예상 은행명 (선택)
  static Future<Map<String, dynamic>> verifyBankbook(
    String imagePath,
    String expectedName, {
    String? expectedAccountNumber,
    String? expectedBankName,
  }) async {
    TextRecognizer? textRecognizer;
    
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      
      final rawText = recognizedText.text;
      print('📄 [통장사본 OCR] 원본: $rawText');
      
      // ✅ 예금주명 추출
      String? extractedName = _extractAccountHolder(rawText, recognizedText);
      
      // ✅ 계좌번호 추출
      String? extractedAccountNumber = _extractAccountNumber(rawText);
      
      // ✅ 은행명 추출
      String? extractedBankName = _extractBankName(rawText);
      
      print('📄 [통장사본 OCR] 추출된 예금주: $extractedName');
      print('📄 [통장사본 OCR] 추출된 계좌번호: $extractedAccountNumber');
      print('📄 [통장사본 OCR] 추출된 은행명: $extractedBankName');
      print('📄 [통장사본 OCR] 예상 예금주: $expectedName');
      
      // ✅ 검증
      final cleanedOcr = _cleanText(rawText);
      final cleanedExpectedName = _cleanText(expectedName);
      
      // 1. 예금주명 검증 (전체 텍스트에서 이름 포함 여부)
      final isNameValid = cleanedOcr.contains(cleanedExpectedName);
      print('📄 [통장사본 OCR] 예금주 검증: ${isNameValid ? "✅" : "❌"}');
      
      // 2. 계좌번호 검증 (선택)
      bool isAccountValid = true;
      if (expectedAccountNumber != null && expectedAccountNumber.isNotEmpty) {
        final cleanedExpectedAccount = expectedAccountNumber.replaceAll(RegExp(r'\D'), '');
        final cleanedExtractedAccount = (extractedAccountNumber ?? '').replaceAll(RegExp(r'\D'), '');
        isAccountValid = cleanedExtractedAccount == cleanedExpectedAccount;
        print('📄 [통장사본 OCR] 계좌번호 검증: $cleanedExtractedAccount == $cleanedExpectedAccount → ${isAccountValid ? "✅" : "❌"}');
      }
      
      // 3. 은행명 검증 (선택)
      bool isBankValid = true;
      if (expectedBankName != null && expectedBankName.isNotEmpty) {
        final cleanedExpectedBank = _cleanText(expectedBankName);
        final cleanedExtractedBank = _cleanText(extractedBankName ?? '');
        // 은행명이 포함되어 있으면 OK (예: "하나은행" in "하나멤버스")
        isBankValid = cleanedOcr.contains(cleanedExpectedBank) ||
                      cleanedExtractedBank.contains(cleanedExpectedBank);
        print('📄 [통장사본 OCR] 은행명 검증: ${isBankValid ? "✅" : "❌"}');
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
        'extractedName': extractedName ?? '',
        'extractedAccountNumber': extractedAccountNumber ?? '',
        'extractedBankName': extractedBankName ?? '',
        'rawText': rawText,
      };
      
    } catch (e) {
      print('❌ [통장사본 OCR] 실패: $e');
      return {
        'isValid': false,
        'isNameValid': false,
        'isAccountValid': false,
        'isBankValid': false,
        'confidence': 0.0,
        'extractedName': '',
        'extractedAccountNumber': '',
        'extractedBankName': '',
        'rawText': '',
        'error': e.toString(),
      };
    } finally {
      textRecognizer?.close();
    }
  }
  
  /// 💳 통장사본 예금주명만 검증 (기존 호환용)
  static Future<Map<String, dynamic>> verifyBankbookName(
    String imagePath,
    String expectedName,
  ) async {
    return verifyBankbook(imagePath, expectedName);
  }
  
  /// ✅ 예금주명 추출
  static String? _extractAccountHolder(String rawText, RecognizedText recognizedText) {
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
    
    // 3. 블록 단위로 스캔 - 단독 한글 이름 찾기
    for (TextBlock block in recognizedText.blocks) {
      final text = block.text.trim();
      // 한글 2-5자리 이름만 있는 블록
      if (RegExp(r'^[가-힣]{2,5}$').hasMatch(text)) {
        // "님", "은행" 등 제외
        if (!text.contains('님') && !text.contains('은행') && 
            !text.contains('과목') && !text.contains('통장')) {
          return text;
        }
      }
    }
    
    // 4. 전체 텍스트에서 첫 번째 한글 이름 패턴 찾기
    final namePattern = RegExp(r'([가-힣]{2,5})(?:\s|님|$)');
    final matches = namePattern.allMatches(rawText);
    for (final match in matches) {
      final name = match.group(1);
      if (name != null && 
          !name.contains('은행') && 
          !name.contains('통장') &&
          !name.contains('과목') &&
          !name.contains('계좌')) {
        return name;
      }
    }
    
    return null;
  }
  
  /// ✅ 계좌번호 추출
  static String? _extractAccountNumber(String rawText) {
    // 1. "계좌번호" 키워드 근처에서 찾기
    final lines = rawText.split('\n');
    for (final line in lines) {
      if (line.contains('계좌번호') || line.contains('계좌 번호')) {
        // 숫자와 하이픈으로 된 계좌번호 패턴
        final accountPattern = RegExp(r'[\d]+[-\s]*[\d]+[-\s]*[\d]+');
        final match = accountPattern.firstMatch(line);
        if (match != null) {
          return match.group(0)?.replaceAll(' ', '');
        }
      }
    }
    
    // 2. 일반적인 계좌번호 패턴 (하이픈으로 구분된 숫자들)
    // 예: 288-910548-10807, 1234-56-789012
    final patterns = [
      RegExp(r'(\d{3,4})[-\s](\d{4,6})[-\s](\d{4,6})'),  // 3-4-5 또는 4-6-5
      RegExp(r'(\d{2,4})[-\s](\d{2,4})[-\s](\d{4,7})'),  // 일반 패턴
    ];
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(rawText);
      if (match != null) {
        final g1 = match.group(1) ?? '';
        final g2 = match.group(2) ?? '';
        final g3 = match.group(3) ?? '';
        return '$g1-$g2-$g3';
      }
    }
    
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
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      
      final rawText = recognizedText.text;
      print('📄 [사업자등록증 OCR] 원본: $rawText');
      
      String? extractedNumber = _extractBusinessNumber(rawText);
      String? extractedName = _extractCeoName(rawText);
      
      print('📄 [사업자등록증 OCR] 추출된 번호: $extractedNumber');
      print('📄 [사업자등록증 OCR] 추출된 대표자: $extractedName');
      
      bool isValidNumber = false;
      bool isValidName = false;
      
      if (expectedBusinessNumber != null && extractedNumber != null) {
        final cleanedExtracted = extractedNumber.replaceAll(RegExp(r'\D'), '');
        final cleanedExpected = expectedBusinessNumber.replaceAll(RegExp(r'\D'), '');
        isValidNumber = cleanedExtracted == cleanedExpected;
        print('📄 [사업자등록증 OCR] 번호 비교: $cleanedExtracted == $cleanedExpected → $isValidNumber');
      }
      
      if (expectedCeoName != null && extractedName != null) {
        final cleanedExtracted = _cleanText(extractedName);
        final cleanedExpected = _cleanText(expectedCeoName);
        isValidName = cleanedExtracted.contains(cleanedExpected) || 
                      cleanedExpected.contains(cleanedExtracted);
        print('📄 [사업자등록증 OCR] 이름 비교: $cleanedExtracted vs $cleanedExpected → $isValidName');
      }
      
      double confidence = 0.0;
      if (isValidNumber && isValidName) confidence = 1.0;
      else if (isValidNumber || isValidName) confidence = 0.6;
      
      return {
        'isValidNumber': isValidNumber,
        'isValidName': isValidName,
        'confidence': confidence,
        'extractedNumber': extractedNumber ?? '',
        'extractedName': extractedName ?? '',
        'rawText': rawText,
      };
      
    } catch (e) {
      print('❌ [사업자등록증 OCR] 실패: $e');
      return {
        'isValidNumber': false,
        'isValidName': false,
        'confidence': 0.0,
        'extractedNumber': '',
        'extractedName': '',
        'rawText': '',
        'error': e.toString(),
      };
    } finally {
      textRecognizer?.close();
    }
  }
  
  /// ✅ 사업자등록번호 추출 (법인등록번호 제외)
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
          final number = '${match.group(1)}${match.group(2)}${match.group(3)}';
          if (number.length == 10) {
            return number;
          }
        }
      }
    }
    
    final regExp = RegExp(r'(\d{3})[-\s]?(\d{2})[-\s]?(\d{5})');
    for (final match in regExp.allMatches(text)) {
      final number = '${match.group(1)}${match.group(2)}${match.group(3)}';
      if (number.length == 10) {
        final fullMatch = match.group(0) ?? '';
        if (!fullMatch.contains(RegExp(r'\d{6}[-\s]?\d{7}'))) {
          return number;
        }
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
          final nextMatch = RegExp(r'[:\s]*([가-힣]{2,5})').firstMatch(nextLine);
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
  
  /// 🧹 텍스트 정제
  static String _cleanText(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[^\w가-힣]'), '')
        .toLowerCase();
  }
}