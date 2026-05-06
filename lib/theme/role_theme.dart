// lib/theme/role_theme.dart

import 'package:flutter/material.dart';

/// 사용자 역할별 테마 설정
class RoleTheme {
  
  // ═══════════════════════════════════════════════════════════
  // 🟣 슈퍼 관리자 테마 (SUPER_ADMIN)
  // ═══════════════════════════════════════════════════════════
  
  static ThemeData get superAdminTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),

      // 기본 색상
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6A1B9A), // 딥 퍼플
        primary: const Color(0xFF6A1B9A),
        secondary: const Color(0xFF9C27B0),
        tertiary: const Color(0xFFBA68C8),
        surface: Colors.white,
        error: const Color(0xFFD32F2F),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: const Color(0xFF212121),
        brightness: Brightness.light,
      ),
      
      // AppBar 스타일
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF6A1B9A),
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
      
      // FloatingActionButton
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      
      // Card 스타일
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        // margin 삭제!
      ),
      
      // Chip 스타일
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFEDE7F6),
        selectedColor: const Color(0xFF9C27B0),
        labelStyle: const TextStyle(
          color: Color(0xFF6A1B9A),
          fontWeight: FontWeight.w600,
        ),
        side: const BorderSide(color: Color(0xFF9C27B0)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      
      // 버튼 스타일
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6A1B9A),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
        ),
      ),
      
      // 텍스트 버튼
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF6A1B9A),
        ),
      ),
      
      // Input 스타일
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF6A1B9A), width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFF6A1B9A)),
        floatingLabelStyle: const TextStyle(color: Color(0xFF6A1B9A)),
      ),
      
      // BottomNavigationBar
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: Color(0xFF6A1B9A),
        unselectedItemColor: Color(0xFF9E9E9E),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
  
  // ═══════════════════════════════════════════════════════════
  // 🔵 사업장 관리자 테마 (BUSINESS_ADMIN)
  // ═══════════════════════════════════════════════════════════
  
  static ThemeData get businessAdminTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),

      // 기본 색상
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1976D2), // 블루
        primary: const Color(0xFF1976D2),
        secondary: const Color(0xFF2196F3),
        tertiary: const Color(0xFF64B5F6),
        surface: Colors.white,
        error: const Color(0xFFD32F2F),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: const Color(0xFF212121),
        brightness: Brightness.light,
      ),
      
      // AppBar 스타일
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1976D2),
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
      
      // FloatingActionButton
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      
      // Card 스타일
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      
      // Chip 스타일
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFE3F2FD),
        selectedColor: const Color(0xFF2196F3),
        labelStyle: const TextStyle(
          color: Color(0xFF1976D2),
          fontWeight: FontWeight.w600,
        ),
        side: const BorderSide(color: Color(0xFF2196F3)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      
      // 버튼 스타일
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1976D2),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
        ),
      ),
      
      // 텍스트 버튼
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF1976D2),
        ),
      ),
      
      // Input 스타일
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1976D2), width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFF1976D2)),
        floatingLabelStyle: const TextStyle(color: Color(0xFF1976D2)),
      ),
      
      // BottomNavigationBar
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: Color(0xFF1976D2),
        unselectedItemColor: Color(0xFF9E9E9E),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
  
  // ═══════════════════════════════════════════════════════════
  // 🟢 지원자 테마 (WORKER)
  // ═══════════════════════════════════════════════════════════
  
  static ThemeData get workerTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),

      // 기본 색상
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF388E3C), // 그린
        primary: const Color(0xFF388E3C),
        secondary: const Color(0xFF4CAF50),
        tertiary: const Color(0xFF81C784),
        surface: Colors.white,
        error: const Color(0xFFD32F2F),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: const Color(0xFF212121),
        brightness: Brightness.light,
      ),
      
      // AppBar 스타일
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF388E3C),
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
      
      // FloatingActionButton
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF388E3C),
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      
      // Card 스타일
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
            
      // Chip 스타일
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFE8F5E9),
        selectedColor: const Color(0xFF4CAF50),
        labelStyle: const TextStyle(
          color: Color(0xFF388E3C),
          fontWeight: FontWeight.w600,
        ),
        side: const BorderSide(color: Color(0xFF4CAF50)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      
      // 버튼 스타일
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF388E3C),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
        ),
      ),
      
      // 텍스트 버튼
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF388E3C),
        ),
      ),
      
      // Input 스타일
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF388E3C), width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFF388E3C)),
        floatingLabelStyle: const TextStyle(color: Color(0xFF388E3C)),
      ),                                                                                                                                                                                                                                                                                                                                                                                                                                                             
      
      // BottomNavigationBar
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: Color(0xFF388E3C),
        unselectedItemColor: Color(0xFF9E9E9E),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
  
  // ═══════════════════════════════════════════════════════════
  // 🎨 역할별 색상 헬퍼
  // ═══════════════════════════════════════════════════════════
  
  /// 역할에 따른 테마 반환
  static ThemeData getThemeByRole(String? role, {bool dark = false}) {
    if (dark) return getDarkThemeByRole(role);
    switch (role?.toUpperCase()) {
      case 'SUPER_ADMIN':
        return superAdminTheme;
      case 'BUSINESS_ADMIN':
        return businessAdminTheme;
      case 'USER':
        return workerTheme;
      default:
        return businessAdminTheme;
    }
  }

  static ThemeData getDarkThemeByRole(String? role) {
    final primary = getPrimaryColor(role);
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
  
  /// 역할별 Primary 색상
  static Color getPrimaryColor(String? role) {
    switch (role?.toUpperCase()) {
      case 'SUPER_ADMIN':
        return const Color(0xFF6A1B9A); // 보라
      case 'BUSINESS_ADMIN':
        return const Color(0xFF1976D2); // 파랑
      case 'USER':
        return const Color(0xFF388E3C); // 녹색
      default:
        return const Color(0xFF1976D2);
    }
  }
  
  /// 역할별 Secondary 색상
  static Color getSecondaryColor(String? role) {
    switch (role?.toUpperCase()) {
      case 'SUPER_ADMIN':
        return const Color(0xFF9C27B0);
      case 'BUSINESS_ADMIN':
        return const Color(0xFF2196F3);
      case 'USER':
        return const Color(0xFF4CAF50);
      default:
        return const Color(0xFF2196F3);
    }
  }
  
  /// 역할별 배경 색상 (밝은 톤)
  static Color getBackgroundColor(String? role) {
    switch (role?.toUpperCase()) {
      case 'SUPER_ADMIN':
        return const Color(0xFFEDE7F6); // 연보라
      case 'BUSINESS_ADMIN':
        return const Color(0xFFE3F2FD); // 연파랑
      case 'USER':
        return const Color(0xFFE8F5E9); // 연녹색
      default:
        return const Color(0xFFE3F2FD);
    }
  }
  
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
  // 🎨 공통 색상 (역할 무관)
  // ═══════════════════════════════════════════════════════════
  
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFD32F2F);
  static const Color info = Color(0xFF2196F3);
  
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textDisabled = Color(0xFF9E9E9E);
  
  static const Color divider = Color(0xFFE0E0E0);
  static const Color background = Color(0xFFF5F5F5);
  
  // 상태별 색상
  static const Color statusPending = Color(0xFFFF9800); // 오렌지
  static const Color statusConfirmed = Color(0xFF4CAF50); // 녹색
  static const Color statusRejected = Color(0xFFD32F2F); // 빨강
  static const Color statusClosed = Color(0xFF757575); // 회색
}