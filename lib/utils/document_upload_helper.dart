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
    // image를 try 바깥에 선언해야 catch에서도 delete() 가능.
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

      // rootNav를 async 이전에 캡처 — widget dispose 후에도 로딩 다이얼로그 정리 가능.
      // BUSINESS와 동일한 canonical 패턴으로 통일 (NATIVE-DIALOG-01 수정).
      final rootNav = Navigator.of(context, rootNavigator: true);
      _showLoadingDialog(context, '신분증 확인 중...');

      // ── OCR + 타임아웃 (30초) ────────────────────────────────────
      // finally에서 다이얼로그를 반드시 닫는다:
      //   rootNav.mounted + rootNav.canPop() — widget dispose와 무관하게 root dialog 정리 가능.
      //   ML Kit processImage() 무한 대기 시 30초 후 에러맵 반환으로 강제 탈출
      final Map<String, dynamic> result;
      try {
        result = await OcrVerificationHelper.verifyIdCardName(
          image.path,
          expectedName,
          expectedResidentNumber: expectedResidentNumber,
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () => {
            'error': '신분증 인식 시간이 초과되었습니다. 다시 시도해 주세요.',
            'isValid': false,
            'confidence': 0.0,
            'isNameValid': false,
            'isResidentNumberValid': false,
          },
        );
      } finally {
        // pre-captured rootNav 사용 — context.mounted와 독립적으로 root dialog 정리
        if (rootNav.mounted && rootNav.canPop()) rootNav.pop();
      }

      if (!context.mounted) {
        await image.delete();
        return null;
      }

      if (result['error'] != null) {
        // [FAIL-SOFT] OCR 기술 실패 — image를 먼저 삭제하지 않음.
        // "그대로 등록" 선택 시 현재 image를 업로드 경로로 반환해야 하므로
        // 다이얼로그 결과(action)를 먼저 받은 뒤 분기 처리.
        if (!context.mounted) {
          await image.delete();
          return null;
        }
        final action = await OcrVerificationDialog.showError(
          context: context,
          documentType: '신분증',
          errorMessage: result['error'],
          allowContinue: true,
        );

        if (action == true) {
          // 다시 시도 — 현재 임시 파일 정리 후 재귀 호출
          await image.delete();
          image = null;
          if (!context.mounted) return null;
          return await pickAndVerifyIdCard(
            context,
            expectedName,
            expectedResidentNumber: expectedResidentNumber,
          );
        } else if (action == null) {
          // 그대로 등록 — image 유지, 호출자가 업로드 후 delete() 책임
          return image.path;
        } else {
          // 취소
          await image.delete();
          image = null;
          return null;
        }
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

        // null-safe extractedInfo 구성 —
        // extractedName = null (P0-002 FIX), extractedResidentNumber = null or matched value.
        // 빈 문자열을 "인식 정보"로 표시하지 않도록 null 전달 → dialog '인식 실패' 표시.
        final String? ocrIdName = result['extractedName'] as String?;
        final String? ocrIdRn = result['extractedResidentNumber'] as String?;
        final bool hasOcrIdName = ocrIdName != null && ocrIdName.isNotEmpty;
        final bool hasOcrIdRn = ocrIdRn != null && ocrIdRn.isNotEmpty;
        final String? idExtractedInfo = (hasOcrIdName || hasOcrIdRn)
            ? [if (hasOcrIdName) ocrIdName, if (hasOcrIdRn) ocrIdRn]
                .join('\n')
            : null;

        final continueAnyway = await OcrVerificationDialog.showWarning(
          context: context,
          documentType: '신분증',
          expectedInfo: expectedName + (expectedResidentNumber != null ? '\n$expectedResidentNumber' : ''),
          extractedInfo: idExtractedInfo,
          reason: reason,
        );

        if (!continueAnyway) {
          await image.delete();
          return null;
        }
        return image.path; // 호출자가 업로드 후 delete() 책임
      }

    } catch (e) {
      // ⚠️ 이 catch는 pickAndCompressImage() 또는 그 이전 단계의 예외만 처리한다.
      //   OCR 단계의 예외는 OcrVerificationHelper 내부 try-catch + 위의 try-finally가 처리하므로
      //   여기서는 _showLoadingDialog가 열려 있지 않다 → Navigator.pop() 금지
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
    String? expectedName, {
    String? expectedAccountNumber,
    String? expectedBankName,
  }) async {
    // image를 try 바깥에 선언 — catch에서 임시 파일 삭제 가능하도록
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

      // rootNav를 async 이전에 캡처 — widget dispose 후에도 로딩 다이얼로그 정리 가능.
      // BUSINESS와 동일한 canonical 패턴으로 통일 (BANKBOOK-DIALOG-01 수정).
      final rootNav = Navigator.of(context, rootNavigator: true);
      _showLoadingDialog(context, '통장사본 확인 중...');

      // ── OCR + 타임아웃 (30초) ────────────────────────────────────
      // finally에서 다이얼로그를 반드시 닫는다:
      //   rootNav.mounted + rootNav.canPop() — widget dispose와 무관하게 root dialog 정리 가능.
      //   ML Kit processImage() 무한 대기 시 30초 후 에러맵 반환으로 강제 탈출
      final Map<String, dynamic> result;
      try {
        result = await OcrVerificationHelper.verifyBankbook(
          image.path,
          expectedName,
          expectedAccountNumber: expectedAccountNumber,
          expectedBankName: expectedBankName,
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () => {
            'error': '통장사본 인식 시간이 초과되었습니다. 다시 시도해 주세요.',
            'isValid': false,
            'confidence': 0.0,
            'isNameValid': false,
            'isAccountValid': false,
            'isBankValid': false,
          },
        );
      } finally {
        // pre-captured rootNav 사용 — context.mounted와 독립적으로 root dialog 정리
        if (rootNav.mounted && rootNav.canPop()) rootNav.pop();
      }

      if (!context.mounted) {
        await image.delete();
        return null;
      }

      if (result['error'] != null) {
        // [FAIL-SOFT] OCR 기술 실패 — image를 먼저 삭제하지 않음.
        // "그대로 등록" 선택 시 현재 image를 업로드 경로로 반환해야 하므로
        // 다이얼로그 결과(action)를 먼저 받은 뒤 분기 처리.
        if (!context.mounted) {
          await image.delete();
          return null;
        }
        final action = await OcrVerificationDialog.showError(
          context: context,
          documentType: '통장사본',
          errorMessage: result['error'],
          allowContinue: true,
        );

        if (action == true) {
          // 다시 시도 — 현재 임시 파일 정리 후 재귀 호출
          await image.delete();
          image = null;
          if (!context.mounted) return null;
          return await pickAndVerifyBankbook(
            context,
            expectedName,
            expectedAccountNumber: expectedAccountNumber,
            expectedBankName: expectedBankName,
          );
        } else if (action == null) {
          // 그대로 등록 — image 유지, 호출자가 업로드 후 delete() 책임
          return image.path;
        } else {
          // 취소
          await image.delete();
          image = null;
          return null;
        }
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
          reason += '  인식: ${result['extractedAccountNumber'] as String? ?? '확인 불가'}\n';
        }
        if (expectedBankName != null &&
            expectedBankName.isNotEmpty &&
            !result['isBankValid']) {
          reason += '• 은행명이 일치하지 않습니다\n';
        }

        reason += '\n사진이 선명하게 보이도록 다시 촬영해주세요';

        // null-safe extractedInfo 구성 —
        // extractedName/extractedAccountNumber = null 가능 (P1-001/P1-002 FIX).
        // 빈 문자열이나 선행 줄바꿈을 "인식 정보"로 표시하지 않도록 null-safe 처리.
        final String? ocrBkName = result['extractedName'] as String?;
        final String? ocrBkAcc = result['extractedAccountNumber'] as String?;
        final String? ocrBkBank = result['extractedBankName'] as String?;
        final List<String> bkExtractedParts = [
          if (ocrBkName != null && ocrBkName.isNotEmpty) ocrBkName,
          if (ocrBkAcc != null && ocrBkAcc.isNotEmpty) ocrBkAcc,
          if (ocrBkBank != null && ocrBkBank.isNotEmpty) ocrBkBank,
        ];
        final String? bkExtractedInfo =
            bkExtractedParts.isNotEmpty ? bkExtractedParts.join('\n') : null;

        final continueAnyway = await OcrVerificationDialog.showWarning(
          context: context,
          documentType: '통장사본',
          expectedInfo: '$expectedName${expectedAccountNumber != null ? '\n$expectedAccountNumber' : ''}${expectedBankName != null ? '\n$expectedBankName' : ''}',
          extractedInfo: bkExtractedInfo,
          reason: reason,
        );

        if (!continueAnyway) {
          await image.delete();
          return null;
        }
        return image.path; // 호출자가 업로드 후 delete() 책임
      }

    } catch (e) {
      // ⚠️ 이 catch는 ImageHelper.pickAndCompressImage() 또는 그 이전 단계의 예외만 처리한다.
      //   OCR 단계의 예외는 OcrVerificationHelper 내부 + 위의 inner try-finally가 처리하므로
      //   여기서는 _showLoadingDialog가 열려 있지 않다 → Navigator.pop() 금지
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
    // image를 try 바깥에 선언 — catch에서 임시 파일 삭제 가능하도록
    File? image;
    try {
      image = await ImageHelper.pickAndCompressImage(
        context,
        type: ImageType.document,
        useBottomSheet: true,
      );

      if (image == null) return null;

      // [FIX-BUSINESS-MOUNTED] both-null early return 전에 mounted 체크 필수.
      // image pick(await) 중 widget dispose → unmounted 상태로 image.path 반환 방지 (KL#1 수정).
      if (!context.mounted) {
        await image.delete();
        return null;
      }

      // 입력된 정보 없으면 검증 없이 바로 반환 — 호출자가 delete() 책임
      // (위 mounted 체크 통과 후이므로 ToastHelper 가드 불필요)
      if ((businessNumber == null || businessNumber.isEmpty) &&
          (ceoName == null || ceoName.isEmpty)) {
        ToastHelper.showSuccess('사업자등록증이 선택되었습니다');
        return image.path;
      }

      // 이 시점 mounted 보장 (위 체크 통과, await 없음)
      if (!context.mounted) {
        await image.delete();
        return null;
      }

      final rootNav = Navigator.of(context, rootNavigator: true);
      _showLoadingDialog(context, '사업자등록증 확인 중...');

      late final Map<String, dynamic> result;
      try {
        result = await OcrVerificationHelper.verifyBusinessLicense(
          image.path,
          businessNumber,
          ceoName,
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () => {'error': 'OCR 시간이 초과되었습니다. 다시 시도해 주세요.'},
        );
      } finally {
        if (rootNav.mounted && rootNav.canPop()) rootNav.pop();
      }

      if (!context.mounted) {
        await image.delete();
        return null;
      }

      if (result['error'] != null) {
        // [FAIL-SOFT] OCR 기술 실패 — image를 먼저 삭제하지 않음.
        // "그대로 등록" 선택 시 현재 image를 업로드 경로로 반환해야 하므로
        // 다이얼로그 결과(action)를 먼저 받은 뒤 분기 처리.
        if (!context.mounted) {
          await image.delete();
          return null;
        }
        final action = await OcrVerificationDialog.showError(
          context: context,
          documentType: '사업자등록증',
          errorMessage: result['error'],
          allowContinue: true,
        );

        if (action == true) {
          // 다시 시도 — 현재 임시 파일 정리 후 재귀 호출
          await image.delete();
          image = null;
          if (!context.mounted) return null;
          return await pickAndVerifyBusinessLicense(
            context,
            businessNumber: businessNumber,
            ceoName: ceoName,
            onCeoNameExtracted: onCeoNameExtracted,
          );
        } else if (action == null) {
          // 그대로 등록 — image 유지, 호출자가 업로드 후 delete() 책임
          return image.path;
        } else {
          // 취소
          await image.delete();
          image = null;
          return null;
        }
      }

      final hasBusinessNumber = businessNumber != null && businessNumber.isNotEmpty;
      final hasCeoName = ceoName != null && ceoName.isNotEmpty;

      final isValid = (hasBusinessNumber ? result['isValidNumber'] : true) &&
                      (hasCeoName ? result['isValidName'] : true);

      if (isValid && result['confidence'] >= 0.6) {
        final extracted = result['extractedName'] as String?;

        // [CEO-VERIFICATION-ONLY] CEO OCR callback은 검증 전용.
        // expected CEO가 없는 경우(hasCeoName=false) autofill 금지:
        //   _extractCeoName은 false-positive를 생성할 수 있으며,
        //   unknown autofill → _ceoNameController 오염 → Firestore persistence 위험.
        // isValidName=true 조건 추가: expected와 OCR 결과가 일치한 경우에만 callback.
        if (hasCeoName &&
            result['isValidName'] == true &&
            extracted != null &&
            extracted.trim().isNotEmpty) {
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
