// lib/widgets/auth/kakao_login_button.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1] '카카오로 시작하기' 주 행동 버튼.
//   카카오 로그인 디자인 가이드 색(AppColors.kakaoContainer/kakaoLabel) · 말풍선 표식 · 최소 높이 52.
//   앱 키가 없으면(준비 중) 누를 수 없는 회색 버튼 + '카카오 로그인 준비 중' 으로 보인다 — 눌러서 실패하게 두지 않는다.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';

class KakaoLoginButton extends StatelessWidget {
  const KakaoLoginButton({
    super.key,
    required this.onPressed,
    this.configured = true,
    this.loading = false,
    this.label = '카카오로 시작하기',
  });

  final VoidCallback? onPressed;
  final bool configured;
  final bool loading;
  final String label;

  static const String notConfiguredLabel = '카카오 로그인 준비 중';

  @override
  Widget build(BuildContext context) {
    final enabled = configured && !loading && onPressed != null;
    final text = configured ? label : notConfiguredLabel;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.kakaoContainer,
          foregroundColor: AppColors.kakaoLabel,
          disabledBackgroundColor: AppColors.disabledBackground,
          disabledForegroundColor: AppColors.textSecondary,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.kakaoLabel),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble,
                      size: 20,
                      color: configured ? AppColors.kakaoLabel : AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      TextLayout.keepWords(text),
                      semanticsLabel: text,
                      textAlign: TextAlign.center,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.w700,
                        color: configured ? AppColors.kakaoLabel : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
