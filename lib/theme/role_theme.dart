// lib/theme/role_theme.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// 통합 앱 테마 (역할 무관 단일 색상 체계)
///
/// Primary  : AppColors.brand #3859E8 (코발트) — [DU1] 사용자 선택 시안 방향
/// Secondary: AppColors.brandDark #2A45C4 — 눌림·진한 강조
class RoleTheme {

  // ─── 브랜드 색상 상수 ──────────────────────────────────────────
  static const Color _primary   = AppColors.brand;     // [DU1] #3859E8 코발트 (이전 #1565C0)
  static const Color _secondary = AppColors.brandDark; // [DU1] 이전 #1E88E5
  static const Color _tertiary  = Color(0xFF90CAF9); // Blue[200]
  static const Color _chipBg    = AppColors.brandSurface; // [DU1] #EEF2FF

  // ═══════════════════════════════════════════════════════════
  // 통합 테마 (모든 역할 공통)
  // ═══════════════════════════════════════════════════════════

  static ThemeData get _unifiedTheme {
    // [DU1] 공통 기준 v1 — 의미색 정본은 AppColors. 흰 헤더·낮은 경계, 평면 주 버튼, 반경 12, 번들 NotoSansKR.
    //   AppBar 를 흰 배경으로 바꿨다: 이전에는 테마가 파란 배경이라 흰 배경 화면이 LightAppBarStyle 로
    //   제목·아이콘 색을 덮어야 했다(그 보호 코드는 그대로 둔다 — 같은 값이 된다).
    const fg = AppColors.textPrimary;
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansKR',
      scaffoldBackgroundColor: AppColors.background,

      colorScheme: ColorScheme.fromSeed(
        seedColor: _primary,
        primary: _primary,
        secondary: _secondary,
        tertiary: _tertiary,
        surface: Colors.white,
        error: AppColors.errorDark,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: fg,
        brightness: Brightness.light,
      ),

      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      // [DU640 · T0-b · 판정258 Q-A1] 팝업 메뉴 · 날짜/시간 선택 창도 창 · 시트와 같은 흰 면(M3 fromSeed 연보라 면 대신).
      //   시간 선택 창은 바탕만 — tint 는 위 dialogTheme(투명)을 따른다(SDK TimePickerThemeData 에 tint 인자 없음).
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      timePickerTheme: const TimePickerThemeData(
        backgroundColor: Colors.white,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: fg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontFamily: 'NotoSansKR',
          color: fg,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: fg),
        actionsIconTheme: IconThemeData(color: fg),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 2,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.borderLight),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: _chipBg,
        selectedColor: _chipBg,
        // [DU260] Chip 은 테마 labelStyle 이 있으면 기본(앱 글꼴·14)을 버리고 이것만 쓴다(SDK chip.dart:
        //   `chipTheme.labelStyle ?? defaults.labelStyle`). 글꼴 이름·크기가 없어 스타일 없는 칩과 글꼴 없는
        //   자체 TextStyle 칩의 라벨이 앱 글꼴(NotoSansKR)이 아니었다(시험 캡처에서는 네모). 화면이 넘기는
        //   labelStyle 은 이것 위에 merge 되므로 화면의 크기·색이 이긴다.
        labelStyle: const TextStyle(
          fontFamily: 'NotoSansKR',
          fontSize: 14,
          color: _primary,
          fontWeight: FontWeight.w600,
        ),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          // 터치 최소 48dp — 높이는 글자 배율에 따라 늘어난다(고정 높이 아님)
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontFamily: 'NotoSansKR', fontSize: 16, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _primary,
          minimumSize: const Size(64, 48),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _primary,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary, width: 2),
        ),
        // 미입력 상태 레이블: 중립 회색 (파란색은 링크/선택 완료처럼 오독될 수 있음)
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        // 포커스 또는 내용 있을 때 플로팅 레이블: 브랜드 블루 유지
        floatingLabelStyle: const TextStyle(color: _primary),
      ),

      dividerTheme: const DividerThemeData(color: AppColors.borderLight, thickness: 1, space: 1),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: _primary,
        unselectedItemColor: AppColors.textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  // ─── 역할별 getter (모두 통합 테마 반환) ─────────────────────────
  static ThemeData get superAdminTheme    => _unifiedTheme;
  static ThemeData get businessAdminTheme => _unifiedTheme;
  static ThemeData get workerTheme        => _unifiedTheme;

  // ═══════════════════════════════════════════════════════════
  // 다크 테마
  // ═══════════════════════════════════════════════════════════

  static ThemeData getDarkThemeByRole(String? role) {
    const primary = _primary;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        color: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2C2C2C),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerColor: const Color(0xFF2C2C2C),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 역할별 색상·아이콘·라벨 헬퍼
  // ═══════════════════════════════════════════════════════════

  /// 역할에 따른 테마 반환
  static ThemeData getThemeByRole(String? role, {bool dark = false}) {
    if (dark) return getDarkThemeByRole(role);
    return _unifiedTheme;
  }

  /// Primary 색상 (전 역할 통일)
  static Color getPrimaryColor(String? role) => _primary;

  /// Secondary 색상 (전 역할 통일)
  static Color getSecondaryColor(String? role) => _secondary;

  /// 밝은 배경 색상 (전 역할 통일)
  static Color getBackgroundColor(String? role) => _chipBg;

  /// 역할별 아이콘
  static IconData getRoleIcon(String? role) {
    switch (role?.toUpperCase()) {
      case 'SUPER_ADMIN':
        return Icons.admin_panel_settings;
      case 'BUSINESS_ADMIN':
        return Icons.business_center;
      case 'USER':
        return Icons.person;
      default:
        return Icons.person;
    }
  }

  /// 역할별 라벨
  static String getRoleLabel(String? role) {
    switch (role?.toUpperCase()) {
      case 'SUPER_ADMIN':
        return '슈퍼 관리자';
      case 'BUSINESS_ADMIN':
        return '사업장 관리자';
      case 'USER':
        return '지원자';
      default:
        return '사용자';
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 공통 상태 색상 (역할 무관)
  // ═══════════════════════════════════════════════════════════

  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error   = Color(0xFFD32F2F);
  static const Color info    = Color(0xFF2196F3);

  static const Color textPrimary   = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textDisabled  = Color(0xFF9E9E9E);

  static const Color divider    = Color(0xFFE0E0E0);
  static const Color background = Color(0xFFF5F5F5);

  static const Color statusPending   = Color(0xFFFF9800);
  static const Color statusConfirmed = Color(0xFF4CAF50);
  static const Color statusRejected  = Color(0xFFD32F2F);
  static const Color statusClosed    = Color(0xFF757575);
}
