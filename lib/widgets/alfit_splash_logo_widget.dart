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
          // ALfit 로고 + 점 (A-2 기준: 우측 상단)
          Stack(
            clipBehavior: Clip.none,
            children: [
              Text(
                'ALfit',
                style: TextStyle(
                  fontSize: width * 0.22,
                  fontWeight: FontWeight.w800,
                  color: primaryColor,
                  letterSpacing: 2,
                  height: 1.2,
                ),
              ),
              // 파란 점 (A-2 비율: cx=820, cy=420 → 텍스트 우측 상단)
              Positioned(
                right: -(width * 0.02),
                top: width * 0.06,
                child: Container(
                  width: width * 0.025,
                  height: width * 0.025,
                  decoration: BoxDecoration(
                    color: secondaryColor.withOpacity(0.9),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: width * 0.04),
          
          // 태그라인
          Text(
            '나에게 딱 맞는 알바, 알핏!',
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