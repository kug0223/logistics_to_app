// lib/providers/theme_provider.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/role_theme.dart';

/// 역할별 테마를 관리하는 Provider
class ThemeProvider extends ChangeNotifier {
  String? _currentRole;
  ThemeData _currentTheme;
  bool _isDarkMode = false;

  ThemeProvider() : _currentTheme = RoleTheme.businessAdminTheme {
    _loadDarkMode();
  }

  /// 현재 테마
  ThemeData get theme => _currentTheme;

  /// 다크모드 여부
  bool get isDarkMode => _isDarkMode;

  /// 현재 역할
  String? get currentRole => _currentRole;

  Future<void> _loadDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('dark_mode') ?? false;
    _currentTheme = RoleTheme.getThemeByRole(_currentRole, dark: _isDarkMode);
    notifyListeners();
  }

  /// 다크모드 토글
  Future<void> toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    _currentTheme = RoleTheme.getThemeByRole(_currentRole, dark: _isDarkMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', _isDarkMode);
    notifyListeners();
  }

  /// 역할 설정 및 테마 변경
  void setRole(String? role) {
    if (_currentRole == role) return;

    _currentRole = role;
    _currentTheme = RoleTheme.getThemeByRole(role, dark: _isDarkMode);

    debugPrint('🎨 [ThemeProvider] 테마 변경: $role');
    notifyListeners();
  }
  
  /// Primary 색상
  Color get primaryColor => RoleTheme.getPrimaryColor(_currentRole);
  
  /// Secondary 색상
  Color get secondaryColor => RoleTheme.getSecondaryColor(_currentRole);
  
  /// 배경 색상
  Color get backgroundColor => RoleTheme.getBackgroundColor(_currentRole);
  
  /// 역할 아이콘
  IconData get roleIcon => RoleTheme.getRoleIcon(_currentRole);
  
  /// 역할 라벨
  String get roleLabel => RoleTheme.getRoleLabel(_currentRole);
  
  /// 테마 초기화 (로그아웃 시)
  void reset() {
    _currentRole = null;
    _currentTheme = RoleTheme.getThemeByRole(null, dark: _isDarkMode);
    notifyListeners();
  }
}