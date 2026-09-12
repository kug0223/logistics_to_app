import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 반응형 레이아웃 헬퍼
///
/// [TYPO-01] **폰트 크기에는 이 스케일을 쓰지 않는다.**
///   Flutter의 logical pixel은 이미 기기 해상도를 흡수하므로, 화면 폭으로
///   fontSize를 한 번 더 줄이면 기기마다 글자 크기가 달라진다.
///   실제로 400dp 임계값이 실사용 기기 폭 분포(360~412dp) 한가운데를 갈라
///   같은 앱이 폰에 따라 body 12.6px / 14px로 보였다.
///   글꼴 크기는 base logical size × OS TextScaler 만으로 정한다.
///
///   이 스케일은 spacing·padding·icon 등 **레이아웃 치수 전용**이다.
class ResponsiveHelper {
  /// 화면 크기에 따른 레이아웃 scale 계산 (폰트 제외)
  static double getScale(BuildContext context) {
    // sizeOf: 화면 크기(가로폭) 변경에만 구독 — viewInsets(키보드) 변경 시 rebuild 안 함
    final width = MediaQuery.sizeOf(context).width;
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

  /// ListView / CustomScrollView 전용 패딩
  /// 하단에 홈 인디케이터·네비게이션 바 높이를 자동으로 더해 마지막 항목 잘림 방지
  /// paddingOf.bottom 사용: SafeArea가 이미 소비한 경우 0, 미소비 시 내비게이션 바 높이
  /// → GradientScaffold(내부 SafeArea(top:false) 포함)와 이중 패딩 없이 동작
  static EdgeInsets listPadding(BuildContext context, {double extra = 0}) {
    final scale  = getScale(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return EdgeInsets.fromLTRB(
      16 * scale, 16 * scale, 16 * scale,
      16 * scale + bottom + extra,
    );
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
    return TextStyle(
      fontSize: 18,
      fontWeight: fontWeight ?? FontWeight.bold,
      color: color,
    );
  }
  
  /// 반응형 텍스트 스타일 - 중간 제목 (TO 제목 등)
  static TextStyle subtitleStyle(BuildContext context, {Color? color, FontWeight? fontWeight}) {
    return TextStyle(
      fontSize: 16,
      fontWeight: fontWeight ?? FontWeight.bold,
      color: color ?? AppColors.textPrimary,
    );
  }
  
  /// 반응형 텍스트 스타일 - 본문 (날짜, 정보 등)
  static TextStyle bodyStyle(BuildContext context, {Color? color, FontWeight? fontWeight}) {
    return TextStyle(
      fontSize: 14,
      color: color ?? AppColors.grey700,
      fontWeight: fontWeight,
    );
  }
  
  /// 반응형 텍스트 스타일 - 작은 텍스트 (배지, 라벨 등)
  static TextStyle smallStyle(BuildContext context, {Color? color, FontWeight? fontWeight}) {
    return TextStyle(
      fontSize: 12,
      color: color ?? AppColors.grey600,
      fontWeight: fontWeight,
    );
  }

  /// 반응형 텍스트 스타일 - 매우 작은 텍스트 (통계 등)
  static TextStyle tinyStyle(BuildContext context, {Color? color, FontWeight? fontWeight}) {
    return TextStyle(
      fontSize: 11,
      color: color ?? AppColors.grey600,
      fontWeight: fontWeight,
    );
}
  /// 반응형 텍스트 스타일 - 캡션 (힌트, 설명 등)
  static TextStyle captionStyle(BuildContext context, {Color? color, FontWeight? fontWeight}) {
    return TextStyle(
      fontSize: 11,
      color: color ?? AppColors.grey600,
      fontWeight: fontWeight,
      height: 1.4,
    );
  }
  
  /// 반응형 아이콘 크기
  static double iconSize(BuildContext context, double baseSize) {
    final scale = getScale(context);
    return baseSize * scale;
  }

  /// [TYPO-01] 폰트 크기 — 화면 폭 스케일을 적용하지 않는다.
  /// base logical size를 그대로 돌려주고, 확대·축소는 OS TextScaler가 맡는다.
  /// 호출부(29곳) 시그니처 유지를 위해 context 인자는 남겨 둔다.
  static double getFontSize(BuildContext context, double baseSize) => baseSize;
  static double buttonHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width < 600) return 48.0;  // 모바일
    if (size.width < 1200) return 52.0; // 태블릿
    return 56.0;                         // 데스크톱
  }
  static double dialogHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width < 600) return 600.0;
    if (size.width < 1200) return 650.0;
    return 700.0;
  }
  /// 화면 전체 패딩 (좌우)
  static EdgeInsets screenPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    
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
