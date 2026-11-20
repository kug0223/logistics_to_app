import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

/// 휴대폰 본인인증 버튼 (KG이니시스 통합인증)
///
/// 내국인 가입, 비밀번호 찾기 등 본인인증이 필요한 모든 화면에서 사용.
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
            // [DU1 C0 S004] 320dp·2.0 에서 Row 가 16px 넘쳤다 — 글자를 줄이지 않고 남은 폭 안에서 줄바꿈을 허용한다(완료 상태는 CODE 만, 렌더 미확인)
            Flexible(
              child: Text(
                completedLabel ?? '본인인증 완료',
                textAlign: TextAlign.center,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: AppColors.successDark,
                  fontWeight: FontWeight.w600,
                ),
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
          backgroundColor: AppColors.brand, // [DU1] 브랜드 토큰(이전 하드코딩 #1565C0)
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          // [DU1 구현77 S003] 기본 글자에서 50 이었다(실측) — 공통 기준 주 버튼 최소 52. 최소값만 두고 글자 확대 시엔 여백대로 커진다.
          minimumSize: const Size.fromHeight(52),
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
                  // [DU1 C0 S004] 320dp·2.0 에서 Row 가 16px 넘쳤다(가입 1단계 실측) — 글자를 줄이지 않고 남은 폭 안에서 줄바꿈을 허용한다
                  Flexible(
                    child: Text(
                      '휴대폰 본인인증',
                      textAlign: TextAlign.center,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
