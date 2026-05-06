import 'package:flutter/material.dart';

/// ALfit 로고 위젯 — 로그인 화면 등 밝은 배경에서 사용
class ALfitSplashLogo extends StatelessWidget {
  final bool isDark;
  final double width;

  const ALfitSplashLogo({
    super.key,
    this.isDark = false,
    this.width = 200,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = isDark ? Colors.white : const Color(0xFF1976D2);
    final taglineColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF1976D2).withValues(alpha: 0.55);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 앱 이름
        Text(
          'ALfit',
          style: TextStyle(
            fontSize: width * 0.22,
            fontWeight: FontWeight.w800,
            color: primaryColor,
            letterSpacing: 1.5,
            height: 1,
          ),
        ),

        SizedBox(height: width * 0.03),

        // 태그라인
        Text(
          '나에게 딱 맞는 알바 매칭',
          style: TextStyle(
            fontSize: width * 0.068,
            fontWeight: FontWeight.w400,
            color: taglineColor,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
