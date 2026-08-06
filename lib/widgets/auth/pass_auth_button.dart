import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

/// PASS 본인인증 버튼
///
/// 내국인 가입, 비밀번호 찾기 등 PASS 인증이 필요한 모든 화면에서 사용.
class PassAuthButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isCompleted;
  final String? completedLabel;  // 인증 완료 후 표시할 텍스트 (기본: "본인인증 완료")

  const PassAuthButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
    this.isCompleted = false,
    this.completedLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (isCompleted) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.successBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.success),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 20),
            const SizedBox(width: 8),
            Text(
              completedLabel ?? '본인인증 완료',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: AppColors.successDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF005BAC), // PASS 공식 색상
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.verified_user, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '휴대폰 본인인증',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
