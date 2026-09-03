// lib/widgets/dialogs/ocr_verification_dialog.dart

import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';

/// 📄 OCR 검증 결과 다이얼로그
class OcrVerificationDialog {
  
  /// ✅ OCR 이미지-입력 일치 확인 다이얼로그
  ///
  /// [PRODUCT-POLICY 2026-08-21] OCR 정책:
  ///   - OCR = 금융기관 실명조회/계좌인증이 아님
  ///   - OCR = 입력 정보와 제출 이미지의 1차 일치 확인 보조 수단
  ///   - "검증 완료", "신뢰도 N%" 등 공적 인증처럼 보이는 표현 금지
  ///   - extractedInfo를 \n으로 분리하여 필드별 일치 항목으로 표시
  ///
  /// [documentType] "신분증" | "통장사본" | "사업자등록증"
  /// [extractedInfo] 일치 확인된 필드 목록 (예: "예금주: 홍길동\n계좌번호: 1234")
  /// [confidence] OCR 엔진 신뢰도 — UI에 퍼센트로 표시하지 않음 (오해 방지)
  static Future<bool> showSuccess({
    required BuildContext context,
    required String documentType,
    required String extractedInfo,
    required double confidence,
  }) async {
    // 제목 — documentType별로 다름 (공적 인증 표현 금지)
    final String title = documentType == '통장사본'
        ? '입력 정보와 일치해요'
        : '이미지 확인됨';

    // 설명 — documentType별로 다름
    final String description = documentType == '통장사본'
        ? '등록한 급여계좌 정보와 통장사본을 비교했어요.'
        : '신분증 이미지와 입력 정보를 비교했어요.';

    // extractedInfo를 \n으로 분리 → 필드명만 추출 (콜론 앞)
    // 예: "예금주: 홍길동\n계좌번호: 1234" → ["예금주", "계좌번호"]
    final List<String> fieldNames = extractedInfo
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map((line) {
          final colonIdx = line.indexOf(':');
          return colonIdx > 0 ? line.substring(0, colonIdx).trim() : line.trim();
        })
        .toList();

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                color: AppColors.successDark,
                size: ResponsiveHelper.iconSize(context, 32),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: Text(
                title,
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  // 필드별 일치 항목 표시 (퍼센트 제거)
                  ...fieldNames.map((fieldName) => Padding(
                    padding: EdgeInsets.only(
                        bottom: ResponsiveHelper.spacing(context, 6)),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: ResponsiveHelper.iconSize(context, 16),
                          color: AppColors.successDark,
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        SizedBox(
                          width: ResponsiveHelper.spacing(context, 64),
                          child: Text(
                            fieldName,
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.grey700),
                          ),
                        ),
                        Text(
                          '일치',
                          style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.successDeep,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.successMedium,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '등록하기',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ) ?? false;
  }
  
  /// ⚠️ 검증 실패 다이얼로그 (계속 진행 가능)
  static Future<bool> showWarning({
    required BuildContext context,
    required String documentType,
    required String expectedInfo,
    String? extractedInfo,
    String? reason,
  }) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warningDark,
                size: ResponsiveHelper.iconSize(context, 32),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: Text(
                '정보 불일치',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: ResponsiveHelper.cardPadding(context),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$documentType의 정보가 입력하신 정보와 일치하지 않습니다',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                    _buildInfoRow(
                      context,
                      '입력 정보',
                      expectedInfo,
                      AppColors.infoDark,
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    _buildInfoRow(
                      context,
                      '인식 정보',
                      extractedInfo ?? '인식 실패',
                      AppColors.warningDark,
                    ),
                    if (reason != null) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                      Text(
                        '💡 $reason',
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: AppColors.grey700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Text(
                '계속 진행하시겠습니까?',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              Text(
                '• 나중에 설정에서 다시 업로드할 수 있습니다\n'
                '• 정확한 정보 입력을 위해 다시 촬영을 권장합니다',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: AppColors.grey600,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '다시 촬영',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warningMedium,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '계속 진행',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ) ?? false;
  }
  
  /// ❌ 검증 오류 다이얼로그 (OCR 기술 실패)
  ///
  /// [allowContinue] true일 때 "그대로 등록" 버튼을 추가로 표시한다.
  ///   OCR 기술 실패(엔진 오류·타임아웃)는 문서 업로드 자체를 막지 않도록 설계.
  ///
  /// Returns:
  ///   true  = 다시 시도 (재귀 호출)
  ///   null  = 그대로 등록 (image.path 반환, 호출자가 업로드 진행)
  ///   false = 취소 (image 삭제, null 반환)
  static Future<bool?> showError({
    required BuildContext context,
    required String documentType,
    String? errorMessage,
    bool allowContinue = false,
  }) async {
    return await showDialog<bool?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                color: AppColors.errorDark,
                size: ResponsiveHelper.iconSize(context, 32),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: Text(
                '인식 실패',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$documentType를 인식할 수 없습니다',
              style: ResponsiveHelper.bodyStyle(context),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📸 촬영 가이드',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  _buildTipRow(context, '밝은 조명에서 촬영해주세요'),
                  _buildTipRow(context, '서류가 전체적으로 보이도록'),
                  _buildTipRow(context, '흔들림 없이 선명하게'),
                  _buildTipRow(context, '반사광이 없도록'),
                ],
              ),
            ),
            if (allowContinue) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Text(
                '인식에 실패했지만 현재 이미지를 그대로 등록할 수 있습니다.',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: AppColors.grey700,
                ),
              ),
            ],
            if (errorMessage != null) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Text(
                '오류: $errorMessage',
                style: ResponsiveHelper.tinyStyle(
                  context,
                  color: AppColors.errorDark,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '취소',
              style: ResponsiveHelper.bodyStyle(context),
            ),
          ),
          if (allowContinue)
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(
                '그대로 등록',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: AppColors.warningDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '다시 시도',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ) ?? false;
  }
  
  /// 정보 표시 행
  static Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        SizedBox(
          width: ResponsiveHelper.spacing(context, 80),
          child: Text(
            label,
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.grey600,
            ),
          ),
        ),
        Text(
          ':  ',
          style: ResponsiveHelper.smallStyle(context),
        ),
        Expanded(
          child: Text(
            value,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
  
  /// 팁 표시 행
  static Widget _buildTipRow(BuildContext context, String tip) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 4),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: ResponsiveHelper.iconSize(context, 14),
            color: AppColors.grey600,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            tip,
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.grey700,
            ),
          ),
        ],
      ),
    );
  }
}
