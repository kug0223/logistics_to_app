import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/user_provider.dart';
import '../screens/user/user_root_screen.dart';
import '../screens/business_admin/business_admin_home_screen.dart';
import '../screens/super_admin/super_admin_home_screen.dart';
import 'admin_tab_switcher.dart';

/// 화면 이동 + 데이터 갱신 통합 헬퍼
/// 
/// 사용법:
/// ```dart
/// NavigationHelper.push(
///   context,
///   destination: SomeScreen(),
///   onReturn: (result) {
///     if (result == true) _loadData();
///   },
/// );
/// ```
class NavigationHelper {
  
  /// 기본 push + 결과 처리
  /// 
  /// [destination]: 이동할 화면
  /// [onReturn]: 돌아왔을 때 콜백 (result 전달)
  /// [onChanged]: result == true일 때만 호출되는 간편 콜백
  static Future<T?> push<T>(
    BuildContext context, {
    required Widget destination,
    FutureOr<void> Function(T? result)? onReturn,
    VoidCallback? onChanged,
    bool useRootNavigator = false,
  }) async {
    final result = await Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
      MaterialPageRoute(builder: (context) => destination),
    );
    
    // async gap 이후 context가 무효화될 수 있으므로 mounted 체크 후 콜백 호출
    if (!context.mounted) return result;

    if (onReturn != null) {
      onReturn(result);
    }

    if (onChanged != null && result == true) {
      onChanged();
    }
    
    return result;
  }

  /// pushReplacement + 결과 처리
  static Future<T?> pushReplacement<T, TO>(
    BuildContext context, {
    required Widget destination,
    TO? result,
  }) async {
    return Navigator.pushReplacement<T, TO>(
      context,
      MaterialPageRoute(builder: (context) => destination),
      result: result,
    );
  }

  /// pushAndRemoveUntil (로그인 화면 등)
  static Future<T?> pushAndRemoveAll<T>(
    BuildContext context, {
    required Widget destination,
  }) async {
    return Navigator.pushAndRemoveUntil<T>(
      context,
      MaterialPageRoute(builder: (context) => destination),
      (route) => false,
    );
  }

  /// pop with result
  /// 
  /// [changed]: 데이터 변경 여부 (true면 이전 화면에서 갱신)
  static void pop(BuildContext context, {bool changed = false}) {
    Navigator.pop(context, changed);
  }

  /// 변경 있음으로 pop (편의 메서드)
  static void popWithChange(BuildContext context) {
    Navigator.pop(context, true);
  }

  /// 변경 없음으로 pop (편의 메서드)
  static void popWithoutChange(BuildContext context) {
    Navigator.pop(context, false);
  }

  /// 역할에 맞는 홈 화면으로 이동 — 기존 스택 전체 제거
  /// [ADMIN.NAV.SUBADMIN-HOME-NESTED-SHELL-01]
  /// BusinessAdminShell이 active인 경우 tab 0(홈)으로 전환 — SUB_ADMIN 포함
  /// Shell inactive(지원자 모드 / SuperAdmin / 비관리자) 시 기존 role 분기 유지
  static Future<void> goHome(BuildContext context) async {
    // BusinessAdminShell active → tab Navigator에 UserRootScreen push 방지
    // AdminTabSwitcher.isRegistered == BusinessAdminShell currently mounted
    // role == USER(SUB_ADMIN 포함) / BUSINESS_ADMIN 모두 동일하게 처리
    if (AdminTabSwitcher.instance.isRegistered) {
      // [ADMIN.NAV.FCM-ROOT-HOME-01]
      // FCM/root Navigator로 push된 화면(AdminContractManagementScreen 등)에서
      // Home 버튼을 눌렀을 때 Shell은 mounted이지만 root route가 화면을 가리고 있음.
      // Navigator identity 비교로 Shell 내부 route vs root overlay route를 구분:
      //   - Shell tab 내부: Navigator.of(false) = tab sub-navigator ≠ root → skip
      //   - FCM root route: Navigator.of(false) = root navigator == root → popUntil
      // popUntil(isFirst): FCM screen 이후 추가 push된 route도 전부 제거
      final localNavigator = Navigator.of(context, rootNavigator: false);
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      if (identical(localNavigator, rootNavigator) && rootNavigator.canPop()) {
        rootNavigator.popUntil((route) => route.isFirst);
      }
      AdminTabSwitcher.instance.switchToTab(AdminTabSwitcher.homeTab);
      return;
    }

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final Widget home;
    if (userProvider.isSuperAdmin) {
      home = const AdminHomeScreen();
    } else if (userProvider.isBusinessAdmin) {
      home = const BusinessAdminHomeScreen();
    } else {
      home = const UserRootScreen();
    }
    await pushAndRemoveAll(context, destination: home);
  }
}