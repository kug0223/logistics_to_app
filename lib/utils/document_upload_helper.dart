// lib/utils/document_upload_helper.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/dialogs/ocr_verification_dialog.dart';
import 'ocr_verification_helper.dart';
import 'responsive_helper.dart';
import 'image_helper.dart';

/// 📄 서류 업로드 통합 헬퍼
/// 
/// 어디서든 재사용 가능:
/// - 회원가입 화면
/// - 설정 > 내 정보 화면
/// - 프로필 수정 화면
class DocumentUploadHelper {  
  /// 🔄 로딩 다이얼로그 표시
  static void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Text(
                message,
                style: ResponsiveHelper.bodyStyle(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// 📸 신분증 업로드 + OCR 검증
  /// 
  /// [context]: BuildContext
  /// [expectedName]: 검증할 이름
  /// [expectedResidentNumber]: 검증할 주민번호 앞7자리 (예: "990101-1")
  /// 
  /// Returns: 업로드 성공 시 이미지 경로, 실패/취소 시 null
  static Future<String?> pickAndVerifyIdCard(
    BuildContext context,
    String expectedName, {
    String? expectedResidentNumber,
  }) async {
    try {
      // ✅ ImageHelper 사용 (선택 + 압축)
      final File? image = await ImageHelper.pickAndCompressImage(
        context,
        type: ImageType.document,  // OCR용 고품질
      );
      
      if (image == null) return null;
      
      // OCR 검증 시작
      if (!context.mounted) return null;
      
      _showLoadingDialog(context, '신분증 확인 중...');
      
      final result = await OcrVerificationHelper.verifyIdCardName(
        image.path,
        expectedName,
        expectedResidentNumber: expectedResidentNumber,
      );
      
      // 로딩 닫기
      if (!context.mounted) return null;
      Navigator.pop(context);
      
      // 결과 처리
      if (result['error'] != null) {
        // OCR 오류
        final retry = await OcrVerificationDialog.showError(
          context: context,
          documentType: '신분증',
          errorMessage: result['error'],
        );
        
        if (retry) {
          return await pickAndVerifyIdCard(
            context, 
            expectedName,
            expectedResidentNumber: expectedResidentNumber,
          );
        }
        return null;
      }
      
      if (result['isValid'] && result['confidence'] >= 0.7) {
        // 검증 성공
        String extractedInfo = '이름: $expectedName';
        if (expectedResidentNumber != null && expectedResidentNumber.isNotEmpty) {
          extractedInfo += '\n주민번호: ${expectedResidentNumber.replaceAll(RegExp(r'(\d{6})-(\d)'), r'$1-$2******')}';
        }
        
        await OcrVerificationDialog.showSuccess(
          context: context,
          documentType: '신분증',
          extractedInfo: extractedInfo,
          confidence: result['confidence'],
        );
        
        return image.path;
        
      } else {
        // 검증 실패
        String reason = '';
        if (!result['isNameValid']) {
          reason += '• 이름이 일치하지 않습니다\n';
        }
        if (expectedResidentNumber != null && !result['isResidentNumberValid']) {
          reason += '• 주민번호가 일치하지 않습니다\n';
        }
        reason += '사진이 흐리거나 조명이 부족할 수 있습니다';
        
        final continueAnyway = await OcrVerificationDialog.showWarning(
          context: context,
          documentType: '신분증',
          expectedInfo: expectedName + (expectedResidentNumber != null ? '\n$expectedResidentNumber' : ''),
          extractedInfo: result['extractedName'] + (result['extractedResidentNumber'].isNotEmpty ? '\n${result['extractedResidentNumber']}' : ''),
          reason: reason,
        );
        
        return continueAnyway ? image.path : null;
      }
      
    } catch (e) {
      print('❌ 신분증 업로드 실패: $e');
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Text('이미지를 선택할 수 없습니다'),
              ],
            ),
            backgroundColor: AppColors.errorMedium,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      
      return null;
    }
  }
  
  /// 💳 통장사본 업로드 + OCR 검증 (계좌번호, 은행명 추가)
  static Future<String?> pickAndVerifyBankbook(
    BuildContext context,
    String expectedName, {
    String? expectedAccountNumber,
    String? expectedBankName,
  }) async {
    try {
      // ✅ ImageHelper 사용 (선택 + 압축)
      final File? image = await ImageHelper.pickAndCompressImage(
        context,
        type: ImageType.document,  // OCR용 고품질
      );
      
      if (image == null) return null;
      
      if (!context.mounted) return null;
      
      _showLoadingDialog(context, '통장사본 확인 중...');
      
      // ✅ 새로운 verifyBankbook 함수 호출 (계좌번호, 은행명 포함)
      final result = await OcrVerificationHelper.verifyBankbook(
        image.path,
        expectedName,
        expectedAccountNumber: expectedAccountNumber,
        expectedBankName: expectedBankName,
      );
      
      if (!context.mounted) return null;
      Navigator.pop(context);
      
      if (result['error'] != null) {
        final retry = await OcrVerificationDialog.showError(
          context: context,
          documentType: '통장사본',
          errorMessage: result['error'],
        );
        
        if (retry) {
          return await pickAndVerifyBankbook(
            context, 
            expectedName,
            expectedAccountNumber: expectedAccountNumber,
            expectedBankName: expectedBankName,
          );
        }
        return null;
      }
      
      // ✅ 검증 성공
      if (result['isValid'] && result['confidence'] >= 0.6) {
        // 성공 메시지 구성
        String extractedInfo = '예금주: $expectedName';
        if (expectedAccountNumber != null && expectedAccountNumber.isNotEmpty) {
          extractedInfo += '\n계좌번호: $expectedAccountNumber';
        }
        if (expectedBankName != null && expectedBankName.isNotEmpty) {
          extractedInfo += '\n은행: $expectedBankName';
        }
        
        await OcrVerificationDialog.showSuccess(
          context: context,
          documentType: '통장사본',
          extractedInfo: extractedInfo,
          confidence: result['confidence'],
        );
        
        return image.path;
        
      } else {
        // ✅ 검증 실패 - 상세 이유 표시
        String reason = '';
        
        if (!result['isNameValid']) {
          reason += '• 예금주명이 일치하지 않습니다\n';
        }
        if (expectedAccountNumber != null && 
            expectedAccountNumber.isNotEmpty && 
            !result['isAccountValid']) {
          reason += '• 계좌번호가 일치하지 않습니다\n';
          reason += '  입력: $expectedAccountNumber\n';
          reason += '  인식: ${result['extractedAccountNumber']}\n';
        }
        if (expectedBankName != null && 
            expectedBankName.isNotEmpty && 
            !result['isBankValid']) {
          reason += '• 은행명이 일치하지 않습니다\n';
        }
        
        reason += '\n사진이 선명하게 보이도록 다시 촬영해주세요';
        
        final continueAnyway = await OcrVerificationDialog.showWarning(
          context: context,
          documentType: '통장사본',
          expectedInfo: '$expectedName${expectedAccountNumber != null ? '\n$expectedAccountNumber' : ''}${expectedBankName != null ? '\n$expectedBankName' : ''}',
          extractedInfo: '${result['extractedName']}${result['extractedAccountNumber'].isNotEmpty ? '\n${result['extractedAccountNumber']}' : ''}${result['extractedBankName'].isNotEmpty ? '\n${result['extractedBankName']}' : ''}',
          reason: reason,
        );
        
        return continueAnyway ? image.path : null;
      }
      
    } catch (e) {
      print('❌ 통장사본 업로드 실패: $e');
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Text('이미지를 선택할 수 없습니다'),
              ],
            ),
            backgroundColor: AppColors.errorMedium,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      
      return null;
    }
  }
  
  /// 🏢 사업자등록증 업로드 + OCR 검증
  static Future<String?> pickAndVerifyBusinessLicense(
    BuildContext context, {
    String? businessNumber,
    String? ceoName,
  }) async {
    try {
      // ✅ ImageHelper 사용 (선택 + 압축)
      final File? image = await ImageHelper.pickAndCompressImage(
        context,
        type: ImageType.document,  // OCR용 고품질
      );
      
      if (image == null) return null;
      
      // 입력된 정보 없으면 검증 없이 바로 반환
      if ((businessNumber == null || businessNumber.isEmpty) &&
          (ceoName == null || ceoName.isEmpty)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('사업자등록증이 선택되었습니다'),
              backgroundColor: AppColors.successMedium,
            ),
          );
        }
        return image.path;
      }
      
      if (!context.mounted) return null;
      
      _showLoadingDialog(context, '사업자등록증 확인 중...');
      
      final result = await OcrVerificationHelper.verifyBusinessLicense(
        image.path,
        businessNumber,
        ceoName,
      );
      
      if (!context.mounted) return null;
      Navigator.pop(context);
      
      if (result['error'] != null) {
        final retry = await OcrVerificationDialog.showError(
          context: context,
          documentType: '사업자등록증',
          errorMessage: result['error'],
        );
        
        if (retry) {
          return await pickAndVerifyBusinessLicense(
            context,
            businessNumber: businessNumber,
            ceoName: ceoName,
          );
        }
        return null;
      }
      
      final hasBusinessNumber = businessNumber != null && businessNumber.isNotEmpty;
      final hasCeoName = ceoName != null && ceoName.isNotEmpty;
      
      final isValid = (hasBusinessNumber ? result['isValidNumber'] : true) &&
                      (hasCeoName ? result['isValidName'] : true);
      
      if (isValid && result['confidence'] >= 0.6) {
        String extractedInfo = '';
        if (hasBusinessNumber) {
          extractedInfo += '사업자번호: $businessNumber\n';
        }
        if (hasCeoName) {
          extractedInfo += '대표자: $ceoName';
        }
        
        await OcrVerificationDialog.showSuccess(
          context: context,
          documentType: '사업자등록증',
          extractedInfo: extractedInfo.trim(),
          confidence: result['confidence'],
        );
        
        return image.path;
        
      } else {
        String expectedInfo = '';
        String extractedInfo = '';
        
        if (hasBusinessNumber) {
          expectedInfo += '사업자번호: $businessNumber\n';
          extractedInfo += '사업자번호: ${result['extractedNumber'] ?? '인식실패'}\n';
        }
        if (hasCeoName) {
          expectedInfo += '대표자: $ceoName';
          extractedInfo += '대표자: ${result['extractedName'] ?? '인식실패'}';
        }
        
        final continueAnyway = await OcrVerificationDialog.showWarning(
          context: context,
          documentType: '사업자등록증',
          expectedInfo: expectedInfo.trim(),
          extractedInfo: extractedInfo.trim(),
          reason: '사업자등록증 전체가 선명하게 보이도록 다시 촬영해주세요',
        );
        
        return continueAnyway ? image.path : null;
      }
      
    } catch (e) {
      print('❌ 사업자등록증 업로드 실패: $e');
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Text('이미지를 선택할 수 없습니다'),
              ],
            ),
            backgroundColor: AppColors.errorMedium,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      
      return null;
    }
  }
}