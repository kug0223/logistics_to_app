// lib/theme/role_theme.dart

import 'package:flutter/material.dart';

/// 통합 앱 테마 (역할 무관 단일 색상 체계)
///
/// Primary  : #1565C0 (Blue[800]) — 스플래시·로그인과 동일한 브랜드 기준색
/// Secondary: #1E88E5 (Blue[600]) — 그라디언트 끝색, 밝은 강조
class RoleTheme {

  // ─── 브랜드 색상 상수 ──────────────────────────────────────────
  static const Color _primary   = Color(0xFF1565C0); // Blue[800]
  static const Color _secondary = Color(0xFF1E88E5); // Blue[600]
  static const Color _tertiary  = Color(0xFF90CAF9); // Blue[200]
  static const Color _chipBg    = Color(0xFFE3F2FD); // Blue[50]

  // ═══════════════════════════════════════════════════════════
  // 통합 테마 (모든 역할 공통)
  // ═══════════════════════════════════════════════════════════

  static ThemeData get _unifiedTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),

      colorScheme: ColorScheme.fromSeed(
        seedColor: _primary,
        primary: _primary,
        secondary: _secondary,
        tertiary: _tertiary,
        surface: Colors.white,
        error: const Color(0xFFD32F2F),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: const Color(0xFF212121),
        brightness: Brightness.light,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: _chipBg,
        selectedColor: _secondary,
        labelStyle: const TextStyle(
          color: _primary,
          fontWeight: FontWeight.w600,
        ),
        side: const BorderSide(color: _secondary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _primary,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _primary, width: 2),
        ),
        // 미입력 상태 레이블: 중립 회색 (파란색은 링크/선택 완료처럼 오독될 수 있음)
        labelStyle: const TextStyle(color: Color(0xFF757575)),
        // 포커스 또는 내용 있을 때 플로팅 레이블: 브랜드 블루 유지
        floatingLabelStyle: const TextStyle(color: _primary),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: _primary,
        unselectedItemColor: Color(0xFF9E9E9E),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
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
