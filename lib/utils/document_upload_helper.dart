// lib/utils/document_upload_helper.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/dialogs/ocr_verification_dialog.dart';
import 'ocr_verification_helper.dart';
import 'responsive_helper.dart';
import 'image_helper.dart';
import 'toast_helper.dart';

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
  ///
  /// ⚠️ 호출자 책임: 반환된 경로 파일을 업로드 완료 후 delete()로 삭제해야 한다.
  ///    null 반환 시에는 이 함수 내부에서 이미 삭제 처리됨.
  static Future<String?> pickAndVerifyIdCard(
    BuildContext context,
    String expectedName, {
    String? expectedResidentNumber,
  }) async {
    // [특이사항] image를 try 바깥에 선언해야 catch에서도 delete() 가능.
    // try 안에서 선언하면 예외 발생 시 임시 압축 파일이 /tmp에 영구 누적된다.
    File? image;
    try {
      image = await ImageHelper.pickAndCompressImage(
        context,
        type: ImageType.document,
        useBottomSheet: true,
      );

      if (image == null) return null;

      if (!context.mounted) {
        await image.delete();
        return null;
      }

      _showLoadingDialog(context, '신분증 확인 중...');

      final result = await OcrVerificationHelper.verifyIdCardName(
        image.path,
        expectedName,
        expectedResidentNumber: expectedResidentNumber,
      );

      if (!context.mounted) {
        await image.delete();
        return null;
      }
      Navigator.pop(context);

      if (result['error'] != null) {
        // 재시도 전에 현재 임시 파일 정리 — 재시도 시 새 파일이 생성됨
        await image.delete();
        image = null;

        if (!context.mounted) return null;
        final retry = await OcrVerificationDialog.showError(
          context: context,
          documentType: '신분증',
          errorMessage: result['error'],
        );

        if (retry && context.mounted) {
          return await pickAndVerifyIdCard(
            context,
            expectedName,
            expectedResidentNumber: expectedResidentNumber,
          );
        }
        return null;
      }

      if (result['isValid'] && result['confidence'] >= 0.7) {
        String extractedInfo = '이름: $expectedName';
        if (expectedResidentNumber != null && expectedResidentNumber.isNotEmpty) {
          extractedInfo += '\n주민번호: ${expectedResidentNumber.replaceAll(RegExp(r'(\d{6})-(\d)'), r'$1-$2******')}';
        }

        if (!context.mounted) {
          await image.delete();
          return null;
        }
        await OcrVerificationDialog.showSuccess(
          context: context,
          documentType: '신분증',
          extractedInfo: extractedInfo,
          confidence: result['confidence'],
        );

        return image.path; // 호출자가 업로드 후 delete() 책임

      } else {
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

        if (!continueAnyway) {
          await image.delete();
          return null;
        }
        return image.path; // 호출자가 업로드 후 delete() 책임
      }

    } catch (e) {
      debugPrint('❌ 신분증 업로드 실패: $e');
      await image?.delete();
      if (context.mounted) ToastHelper.showError('이미지를 선택할 수 없습니다');
      return null;
    }
  }

  /// 💳 통장사본 업로드 + OCR 검증 (계좌번호, 은행명 추가)
  ///
  /// ⚠️ 호출자 책임: 반환된 경로 파일을 업로드 완료 후 delete()로 삭제해야 한다.
  ///    null 반환 시에는 이 함수 내부에서 이미 삭제 처리됨.
  static Future<String?> pickAndVerifyBankbook(
    BuildContext context,
    String expectedName, {
    String? expectedAccountNumber,
    String? expectedBankName,
  }) async {
    // [특이사항] image를 try 바깥에 선언 — catch에서 임시 파일 삭제 가능하도록
    File? image;
    try {
      image = await ImageHelper.pickAndCompressImage(
        context,
        type: ImageType.document,
        useBottomSheet: true,
      );

      if (image == null) return null;

      if (!context.mounted) {
        await image.delete();
        return null;
      }

      _showLoadingDialog(context, '통장사본 확인 중...');

      final result = await OcrVerificationHelper.verifyBankbook(
        image.path,
        expectedName,
        expectedAccountNumber: expectedAccountNumber,
        expectedBankName: expectedBankName,
      );

      if (!context.mounted) {
        await image.delete();
        return null;
      }
      Navigator.pop(context);

      if (result['error'] != null) {
        // 재시도 전에 현재 임시 파일 정리
        await image.delete();
        image = null;

        if (!context.mounted) return null;
        final retry = await OcrVerificationDialog.showError(
          context: context,
          documentType: '통장사본',
          errorMessage: result['error'],
        );

        if (retry && context.mounted) {
          return await pickAndVerifyBankbook(
            context,
            expectedName,
            expectedAccountNumber: expectedAccountNumber,
            expectedBankName: expectedBankName,
          );
        }
        return null;
      }

      if (result['isValid'] && result['confidence'] >= 0.6) {
        String extractedInfo = '예금주: $expectedName';
        if (expectedAccountNumber != null && expectedAccountNumber.isNotEmpty) {
          extractedInfo += '\n계좌번호: $expectedAccountNumber';
        }
        if (expectedBankName != null && expectedBankName.isNotEmpty) {
          extractedInfo += '\n은행: $expectedBankName';
        }

        if (!context.mounted) {
          await image.delete();
          return null;
        }
        await OcrVerificationDialog.showSuccess(
          context: context,
          documentType: '통장사본',
          extractedInfo: extractedInfo,
          confidence: result['confidence'],
        );

        return image.path; // 호출자가 업로드 후 delete() 책임

      } else {
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

        if (!continueAnyway) {
          await image.delete();
          return null;
        }
        return image.path; // 호출자가 업로드 후 delete() 책임
      }

    } catch (e) {
      debugPrint('❌ 통장사본 업로드 실패: $e');
      await image?.delete();
      if (context.mounted) ToastHelper.showError('이미지를 선택할 수 없습니다');
      return null;
    }
  }

  /// 🏢 사업자등록증 업로드 + OCR 검증
  ///
  /// ⚠️ 호출자 책임: 반환된 경로 파일을 업로드 완료 후 delete()로 삭제해야 한다.
  ///    null 반환 시에는 이 함수 내부에서 이미 삭제 처리됨.
  static Future<String?> pickAndVerifyBusinessLicense(
    BuildContext context, {
    String? businessNumber,
    String? ceoName,
    void Function(String)? onCeoNameExtracted,
  }) async {
    // [특이사항] image를 try 바깥에 선언 — catch에서 임시 파일 삭제 가능하도록
    File? image;
    try {
      image = await ImageHelper.pickAndCompressImage(
        context,
        type: ImageType.document,
        useBottomSheet: true,
      );

      if (image == null) return null;

      // 입력된 정보 없으면 검증 없이 바로 반환 — 호출자가 delete() 책임
      if ((businessNumber == null || businessNumber.isEmpty) &&
          (ceoName == null || ceoName.isEmpty)) {
        if (context.mounted) ToastHelper.showSuccess('사업자등록증이 선택되었습니다');
        return image.path;
      }

      if (!context.mounted) {
        await image.delete();
        return null;
      }

      _showLoadingDialog(context, '사업자등록증 확인 중...');

      final result = await OcrVerificationHelper.verifyBusinessLicense(
        image.path,
        businessNumber,
        ceoName,
      );

      if (!context.mounted) {
        await image.delete();
        return null;
      }
      Navigator.pop(context);

      if (result['error'] != null) {
        // 재시도 전에 현재 임시 파일 정리
        await image.delete();
        image = null;

        if (!context.mounted) return null;
        final retry = await OcrVerificationDialog.showError(
          context: context,
          documentType: '사업자등록증',
          errorMessage: result['error'],
        );

        if (retry && context.mounted) {
          return await pickAndVerifyBusinessLicense(
            context,
            businessNumber: businessNumber,
            ceoName: ceoName,
            onCeoNameExtracted: onCeoNameExtracted,
          );
        }
        return null;
      }

      final hasBusinessNumber = businessNumber != null && businessNumber.isNotEmpty;
      final hasCeoName = ceoName != null && ceoName.isNotEmpty;

      final isValid = (hasBusinessNumber ? result['isValidNumber'] : true) &&
                      (hasCeoName ? result['isValidName'] : true);

      if (isValid && result['confidence'] >= 0.6) {
        final extracted = result['extractedName'] as String?;
        if (extracted != null && extracted.trim().isNotEmpty) {
          onCeoNameExtracted?.call(extracted.trim());
        }

        String extractedInfo = '';
        if (hasBusinessNumber) {
          extractedInfo += '사업자번호: $businessNumber\n';
        }
        if (hasCeoName) {
          extractedInfo += '대표자: $ceoName';
        }

        if (!context.mounted) {
          await image.delete();
          return null;
        }
        await OcrVerificationDialog.showSuccess(
          context: context,
          documentType: '사업자등록증',
          extractedInfo: extractedInfo.trim(),
          confidence: result['confidence'],
        );

        return image.path; // 호출자가 업로드 후 delete() 책임

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

        if (!continueAnyway) {
          await image.delete();
          return null;
        }
        return image.path; // 호출자가 업로드 후 delete() 책임
      }

    } catch (e) {
      debugPrint('❌ 사업자등록증 업로드 실패: $e');
      await image?.delete();
      if (context.mounted) ToastHelper.showError('이미지를 선택할 수 없습니다');
      return null;
    }
  }
}
