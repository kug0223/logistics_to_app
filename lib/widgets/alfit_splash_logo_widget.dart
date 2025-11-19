import 'package:flutter/material.dart';

/// ALfit 스플래시 로고 위젯 (한글 폰트 문제 해결)
/// SVG 대신 Flutter 위젯으로 직접 그리기
class ALfitSplashLogo extends StatelessWidget {
  final bool isDark;
  final double width;

  const ALfitSplashLogo({
    super.key,
    this.isDark = false,
    this.width = 300,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = isDark ? Colors.white : const Color(0xFF1976D2);
    final secondaryColor = const Color(0xFF2196F3);
    final taglineColor = isDark ? const Color(0xFFE0E0E0) : const Color(0xFF0D47A1);

    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ALfit 로고
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'ALfit',
                style: TextStyle(
                  fontSize: width * 0.22, // 반응형 크기
                  fontWeight: FontWeight.w800,
                  color: primaryColor,
                  letterSpacing: 2,
                  height: 1.2,
                ),
              ),
              SizedBox(width: width * 0.02),
              // 작은 연결점
              Container(
                width: width * 0.02,
                height: width * 0.02,
                decoration: BoxDecoration(
                  color: secondaryColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          
          SizedBox(height: width * 0.04),
          
          // 태그라인
          Text(
            '나에게 딱 맞는 알바',
            style: TextStyle(
              fontSize: width * 0.052, // 반응형 크기
              fontWeight: FontWeight.w400,
              color: taglineColor,
              letterSpacing: 3,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}