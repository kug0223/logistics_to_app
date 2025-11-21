// lib/widgets/dialogs/ocr_verification_dialog.dart

import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';

/// 📄 OCR 검증 결과 다이얼로그
class OcrVerificationDialog {
  
  /// ✅ 검증 성공 다이얼로그
  static Future<bool> showSuccess({
    required BuildContext context,
    required String documentType, // "신분증", "통장사본", "사업자등록증"
    required String extractedInfo, // 추출된 정보
    required double confidence,
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
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                color: Colors.green[700],
                size: ResponsiveHelper.iconSize(context, 32),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: Text(
                '검증 완료',
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
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$documentType 정보가 확인되었습니다',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  Row(
                    children: [
                      Icon(
                        Icons.check,
                        size: ResponsiveHelper.iconSize(context, 18),
                        color: Colors.green[700],
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Expanded(
                        child: Text(
                          extractedInfo,
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: Colors.green[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  LinearProgressIndicator(
                    value: confidence,
                    backgroundColor: Colors.grey[300],
                    color: Colors.green[700],
                    minHeight: 4,
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    '신뢰도: ${(confidence * 100).toInt()}%',
                    style: ResponsiveHelper.tinyStyle(
                      context,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[600],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '확인',
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
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange[700],
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
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
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
                      Colors.blue[700]!,
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    _buildInfoRow(
                      context,
                      '인식 정보',
                      extractedInfo ?? '인식 실패',
                      Colors.orange[700]!,
                    ),
                    if (reason != null) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                      Text(
                        '💡 $reason',
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: Colors.grey[700],
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
                  color: Colors.grey[600],
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
              backgroundColor: Colors.orange[600],
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
  
  /// ❌ 검증 오류 다이얼로그 (OCR 실패)
  static Future<bool> showError({
    required BuildContext context,
    required String documentType,
    String? errorMessage,
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
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                color: Colors.red[700],
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
                color: Colors.grey[100],
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
            if (errorMessage != null) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Text(
                '오류: $errorMessage',
                style: ResponsiveHelper.tinyStyle(
                  context,
                  color: Colors.red[700],
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
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '다시 촬영',
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
        Container(
          width: ResponsiveHelper.spacing(context, 80),
          child: Text(
            label,
            style: ResponsiveHelper.smallStyle(
              context,
              color: Colors.grey[600],
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
            color: Colors.grey[600],
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            tip,
            style: ResponsiveHelper.smallStyle(
              context,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}