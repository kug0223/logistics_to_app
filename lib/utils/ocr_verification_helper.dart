// lib/utils/ocr_verification_helper.dart

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// 📄 OCR 기반 서류 검증 헬퍼 클래스
class OcrVerificationHelper {
  
  /// 📸 신분증 이름 + 주민번호 검증
  /// 
  /// [imagePath]: 신분증 이미지 경로
  /// [expectedName]: 예상 이름 (예: "홍길동")
  /// [expectedResidentNumber]: 예상 주민번호 앞7자리 (예: "990101-1")
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
      
      // 공백/특수문자 제거 후 비교
      final cleanedOcr = _cleanText(rawText);
      final cleanedExpected = _cleanText(expectedName);
      
      print('📄 [신분증 OCR] 정제됨: $cleanedOcr');
      print('📄 [신분증 OCR] 예상 이름: $cleanedExpected');
      
      // 이름 검증
      final isNameValid = cleanedOcr.contains(cleanedExpected);
      
      // 주민번호 검증 (선택사항)
      bool isResidentNumberValid = true;
      String? extractedResidentNumber;
      
      if (expectedResidentNumber != null && expectedResidentNumber.isNotEmpty) {
        // 주민번호 패턴 찾기: 6자리-1자리 또는 6자리 1자리
        final residentPattern = RegExp(r'(\d{6})[-\s]?(\d)');
        final matches = residentPattern.allMatches(rawText);
        
        if (matches.isNotEmpty) {
          final match = matches.first;
          final front = match.group(1); // 앞 6자리
          final back = match.group(2);  // 뒷 1자리
          extractedResidentNumber = '$front-$back';
          
          print('📄 [신분증 OCR] 추출된 주민번호: $extractedResidentNumber');
          
          // 예상 주민번호와 비교
          final cleanedExtracted = extractedResidentNumber.replaceAll(RegExp(r'\D'), '');
          final cleanedExpectedRN = expectedResidentNumber.replaceAll(RegExp(r'\D'), '');
          
          isResidentNumberValid = cleanedExtracted == cleanedExpectedRN;
          
          print('📄 [신분증 OCR] 주민번호 검증: ${isResidentNumberValid ? "✅" : "❌"}');
        } else {
          // 주민번호를 찾지 못함
          isResidentNumberValid = false;
          print('📄 [신분증 OCR] 주민번호 인식 실패');
        }
      }
      
      // 종합 검증
      final isValid = isNameValid && isResidentNumberValid;
      
      // 신뢰도 계산
      double confidence = 0.0;
      if (isNameValid && isResidentNumberValid) {
        confidence = 1.0;
      } else if (isNameValid) {
        confidence = 0.6; // 이름만 맞음
      } else if (isResidentNumberValid) {
        confidence = 0.5; // 주민번호만 맞음
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
  
  /// 💳 통장사본 예금주명 검증
  static Future<Map<String, dynamic>> verifyBankbookName(
    String imagePath,
    String expectedName,
  ) async {
    TextRecognizer? textRecognizer;
    
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      
      final rawText = recognizedText.text;
      print('📄 [통장사본 OCR] 원본: $rawText');
      
      // "예금주" 키워드 근처에서 이름 찾기
      final List<String> lines = [];
      for (TextBlock block in recognizedText.blocks) {
        lines.add(block.text);
      }
      
      String? extractedName;
      
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('예금주') || lines[i].contains('계좌주')) {
          final currentLine = _cleanText(lines[i]);
          final nextLine = i + 1 < lines.length ? _cleanText(lines[i + 1]) : '';
          
          extractedName = currentLine.replaceAll('예금주', '').replaceAll('계좌주', '').trim();
          if (extractedName.isEmpty && nextLine.isNotEmpty) {
            extractedName = nextLine;
          }
          break;
        }
      }
      
      final cleanedOcr = _cleanText(rawText);
      final cleanedExpected = _cleanText(expectedName);
      
      print('📄 [통장사본 OCR] 추출된 예금주: $extractedName');
      print('📄 [통장사본 OCR] 예상: $cleanedExpected');
      
      final isValid = cleanedOcr.contains(cleanedExpected);
      
      double confidence = 0.0;
      if (isValid) {
        confidence = (extractedName == cleanedExpected) ? 1.0 : 0.7;
      }
      
      return {
        'isValid': isValid,
        'confidence': confidence,
        'extractedName': extractedName ?? '',
        'rawText': rawText,
      };
      
    } catch (e) {
      print('❌ [통장사본 OCR] 실패: $e');
      return {
        'isValid': false,
        'confidence': 0.0,
        'extractedName': '',
        'rawText': '',
        'error': e.toString(),
      };
    } finally {
      textRecognizer?.close();
    }
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
      
      // 사업자번호 패턴 찾기
      final businessNumberPattern = RegExp(r'\d{3}-?\d{2}-?\d{5}');
      final matches = businessNumberPattern.allMatches(rawText);
      
      String? extractedNumber;
      if (matches.isNotEmpty) {
        extractedNumber = matches.first.group(0)?.replaceAll('-', '');
      }
      
      // 대표자명 찾기
      final List<String> lines = [];
      for (TextBlock block in recognizedText.blocks) {
        lines.add(block.text);
      }
      
      String? extractedName;
      
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('대표자') || lines[i].contains('성명')) {
          final currentLine = _cleanText(lines[i]);
          final nextLine = i + 1 < lines.length ? _cleanText(lines[i + 1]) : '';
          
          extractedName = currentLine
              .replaceAll('대표자', '')
              .replaceAll('성명', '')
              .replaceAll(':', '')
              .trim();
          
          if (extractedName.isEmpty && nextLine.isNotEmpty) {
            extractedName = nextLine;
          }
          break;
        }
      }
      
      print('📄 [사업자등록증 OCR] 추출된 번호: $extractedNumber');
      print('📄 [사업자등록증 OCR] 추출된 대표자: $extractedName');
      
      // 검증
      bool isValidNumber = false;
      bool isValidName = false;
      
      if (expectedBusinessNumber != null && extractedNumber != null) {
        final cleanedExtracted = extractedNumber.replaceAll(RegExp(r'\D'), '');
        final cleanedExpected = expectedBusinessNumber.replaceAll(RegExp(r'\D'), '');
        isValidNumber = cleanedExtracted == cleanedExpected;
      }
      
      if (expectedCeoName != null && extractedName != null) {
        final cleanedExtracted = _cleanText(extractedName);
        final cleanedExpected = _cleanText(expectedCeoName);
        isValidName = cleanedExtracted.contains(cleanedExpected) || 
                      cleanedExpected.contains(cleanedExtracted);
      }
      
      // 신뢰도 계산
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
  
  /// 🧹 텍스트 정제
  static String _cleanText(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[^\w가-힣]'), '')
        .toLowerCase();
  }
}