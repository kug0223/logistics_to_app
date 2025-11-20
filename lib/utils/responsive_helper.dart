import 'package:flutter/material.dart';

/// 반응형 레이아웃 헬퍼
class ResponsiveHelper {
  /// 화면 크기에 따른 scale 계산
  static double getScale(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 360) return 0.85;
    if (width < 400) return 0.9;
    return 1.0;
  }
  
  /// 반응형 간격
  static double spacing(BuildContext context, double baseSpacing) {
    final scale = getScale(context);
    return baseSpacing * scale;
  }
  
  /// 반응형 패딩 (균등)
  static EdgeInsets cardPadding(BuildContext context) {
    final scale = getScale(context);
    return EdgeInsets.all(16 * scale);
  }
  
  /// 반응형 패딩 (가로/세로 다름)
  static EdgeInsets symmetricPadding(BuildContext context, {
    required double horizontal,
    required double vertical,
  }) {
    final scale = getScale(context);
    return EdgeInsets.symmetric(
      horizontal: horizontal * scale,
      vertical: vertical * scale,
    );
  }
  
  /// 반응형 텍스트 스타일 - 큰 제목 (사업장명 등)
  static TextStyle titleStyle(BuildContext context, {Color? color, FontWeight? fontWeight}) {
    final scale = getScale(context);
    return TextStyle(
      fontSize: 18 * scale,
      fontWeight: fontWeight ?? FontWeight.bold,
      color: color,
    );
  }
  
  /// 반응형 텍스트 스타일 - 중간 제목 (TO 제목 등)
  static TextStyle subtitleStyle(BuildContext context, {Color? color, FontWeight? fontWeight}) {
    final scale = getScale(context);
    return TextStyle(
      fontSize: 16 * scale,
      fontWeight: fontWeight ?? FontWeight.bold,
      color: color ?? Colors.black87,
    );
  }
  
  /// 반응형 텍스트 스타일 - 본문 (날짜, 정보 등)
  static TextStyle bodyStyle(BuildContext context, {Color? color, FontWeight? fontWeight}) {
    final scale = getScale(context);
    return TextStyle(
      fontSize: 14 * scale,
      color: color ?? Colors.grey[700],
      fontWeight: fontWeight,
    );
  }
  
  /// 반응형 텍스트 스타일 - 작은 텍스트 (배지, 라벨 등)
  static TextStyle smallStyle(BuildContext context, {Color? color, FontWeight? fontWeight}) {
    final scale = getScale(context);
    return TextStyle(
      fontSize: 12 * scale,
      color: color ?? Colors.grey[600],
      fontWeight: fontWeight,
    );
  }

  /// 반응형 텍스트 스타일 - 매우 작은 텍스트 (통계 등)
  static TextStyle tinyStyle(BuildContext context, {Color? color, FontWeight? fontWeight}) {
    final scale = getScale(context);
    return TextStyle(
      fontSize: 11 * scale,
      color: color ?? Colors.grey[600],
      fontWeight: fontWeight,
    );
}
  /// 반응형 텍스트 스타일 - 캡션 (힌트, 설명 등)
  static TextStyle captionStyle(BuildContext context, {Color? color, FontWeight? fontWeight}) {
    final scale = getScale(context);
    return TextStyle(
      fontSize: 11 * scale,
      color: color ?? Colors.grey[600],
      fontWeight: fontWeight,
      height: 1.4,
    );
  }
  
  /// 반응형 아이콘 크기
  static double iconSize(BuildContext context, double baseSize) {
    final scale = getScale(context);
    return baseSize * scale;
  }

  /// 반응형 폰트 크기 (일반)  // ⭐ 추가!
  static double getFontSize(BuildContext context, double baseSize) {
    final scale = getScale(context);
    return baseSize * scale;
  }
  static double buttonHeight(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (size.width < 600) return 48.0;  // 모바일
    if (size.width < 1200) return 52.0; // 태블릿
    return 56.0;                         // 데스크톱
  }
  static double dialogHeight(BuildContext context) {
    final size = MediaQuery.of(context).size;
    if (size.width < 600) return 600.0;  // 500 → 600 (100px 증가)
    if (size.width < 1200) return 650.0; // 550 → 650 (100px 증가)
    return 700.0;                         // 600 → 700 (100px 증가)
  }
  /// 화면 전체 패딩 (좌우)
  static EdgeInsets screenPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    
    if (width < 360) {
      return const EdgeInsets.symmetric(horizontal: 16, vertical: 20);
    } else if (width < 600) {
      return const EdgeInsets.symmetric(horizontal: 24, vertical: 24);
    } else if (width < 1200) {
      return const EdgeInsets.symmetric(horizontal: 40, vertical: 32);
    } else {
      return const EdgeInsets.symmetric(horizontal: 60, vertical: 40);
    }
  }
}