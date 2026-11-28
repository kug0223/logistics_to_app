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
    final next = RoleTheme.getThemeByRole(role);
    // [PERF-L13] 값이 같으면 알리지 않는다. 이 Provider 를 듣는 곳은 main 의 Consumer(MaterialApp 의
    //   theme) 하나뿐이고(역할 이름·아이콘은 context.read 로만 읽힌다), 지금은 모든 역할이 같은 통합 테마
    //   객체다 — 로그인마다 MaterialApp 전체를 다시 만들 이유가 없다. 테마가 실제로 달라지면 예전처럼 알린다.
    if (identical(next, _currentTheme)) return;
    _currentTheme = next;

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
    final next = RoleTheme.getThemeByRole(null);
    // [PERF-L13] AuthWrapper 의 로그아웃 분기가 build 마다 postFrame 으로 reset 을 부른다 — 같은 값이면 알리지 않는다.
    if (identical(next, _currentTheme)) return;
    _currentTheme = next;
    notifyListeners();
  }
}
