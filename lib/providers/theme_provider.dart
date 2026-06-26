import 'package:flutter/material.dart';
import '../theme/role_theme.dart';

/// 역할별 테마를 관리하는 Provider
class ThemeProvider extends ChangeNotifier {
  String? _currentRole;
  ThemeData _currentTheme;

  ThemeProvider() : _currentTheme = RoleTheme.businessAdminTheme;

  /// 현재 테마
  ThemeData get theme => _currentTheme;

  /// 현재 역할
  String? get currentRole => _currentRole;

  /// 역할 설정 및 테마 변경
  // _disposed 가드 없음 — 루트 Provider라 앱 생명주기 내내 살아있으므로 실질 위험 낮음
  void setRole(String? role) {
    if (_currentRole == role) return;

    _currentRole = role;
    _currentTheme = RoleTheme.getThemeByRole(role);

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
    _currentTheme = RoleTheme.getThemeByRole(null);
    notifyListeners();
  }
}
