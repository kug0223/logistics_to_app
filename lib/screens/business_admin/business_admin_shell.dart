// lib/screens/business_admin/business_admin_shell.dart
//
// 관리자 루트 화면 — 5탭 BottomNavigationBar + IndexedStack (PHASE 4B)
// UserRootScreen과 동일한 탭 독립 Navigator 패턴 적용.
//
// 탭 구조:
//   0: 홈     (BusinessAdminHomeScreen)  — 전체 운영 판단 + Action Queue
//   1: 공고   (JobsRootScreen)           — TO 생성/조회/수정/마감
//   2: 인력   (WorkforceRootScreen)      — 날짜/사람 중심 workforce 운영
//   3: 정산   (PayrollOverviewScreen)    — 사업장별 급여 관리
//   4: MY     (SettingsScreen)           — 계정·앱 설정
//
// [IntegratedWorkforceScreen]
//   삭제하지 않음 — FCM deep link 등 다른 route에서 사용 가능성 유지.
//   이 Shell에서는 직접 destination으로 사용하지 않음.
//
// [Controller 분리]
//   JobsRootScreen.WorkforceController ≠ WorkforceRootScreen.WorkforceController
//   각 Root가 전용 controller 인스턴스 보유 — filter/tab/loading state 격리.
//   IndexedStack으로 두 Root가 항상 alive → dispose는 로그아웃/Shell 제거 시.
//
// [FCM 딥링크]
//   FCMService는 MaterialApp.navigatorKey (루트 Navigator) 로 push.
//   탭 서브 Navigator와 독립 — 기존 FCM 경로 미변경.
//
// [SafeArea]
//   BottomNavigationBar가 MediaQuery.padding.bottom을 내부적으로 처리.
//   고정 pixel padding 없음.
//
// [Back stack]
//   PopScope(canPop: false) — 현재 탭 서브 Navigator에서 먼저 pop.
//   루트이면 SystemNavigator.pop() → system back 허용 (앱 종료/홈).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../services/fcm_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/admin_tab_switcher.dart';
import 'business_admin_home_screen.dart';
import 'jobs_root_screen.dart';
import 'workforce_management/workforce_root_screen.dart';
import 'payroll/payroll_overview_screen.dart';
import '../common/settings_screen.dart';

class BusinessAdminShell extends StatefulWidget {
  const BusinessAdminShell({super.key});

  @override
  State<BusinessAdminShell> createState() => _BusinessAdminShellState();
}

class _BusinessAdminShellState extends State<BusinessAdminShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // [P2-B] FCMService가 Shell 탭 전환을 호출할 수 있도록 콜백 등록
    AdminTabSwitcher.instance.register(switchToTab);
    // [NAV-POLICY-N1] Home Task deep-link용 tab normalize + push 콜백 등록
    AdminTabSwitcher.instance.registerSwitchAndPush(_switchAndPush);
    // [Phase 9D] cold-start pending payload 소비
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FCMService().consumePendingColdStartPayload();
    });
  }

  @override
  void dispose() {
    AdminTabSwitcher.instance.unregister();
    super.dispose();
  }

  /// 탭별 독립 Navigator 키 — 탭 내 라우트 스택이 서로 독립됨
  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(), // 0: 홈
    GlobalKey<NavigatorState>(), // 1: 공고
    GlobalKey<NavigatorState>(), // 2: 인력
    GlobalKey<NavigatorState>(), // 3: 정산
    GlobalKey<NavigatorState>(), // 4: MY
  ];

  /// 탭 전환 — 이미 선택된 탭을 다시 탭하면 해당 탭 루트로 복귀
  /// PD-02: 권한 없는 탭은 BottomNav에서 숨김 처리 (Toast 차단 제거)
  /// [AUDIT.2R1-M001] AdminTabSwitcher 경로 포함 — 비가시 탭 전환 차단
  void switchToTab(int index) {
    if (_currentIndex == index) {
      _navigatorKeys[index].currentState?.popUntil((r) => r.isFirst);
    } else {
      if (!mounted) return;
      final up = context.read<UserProvider>();
      if (!_visibleTabIndices(up).contains(index)) return; // 권한 없는 탭 차단
      setState(() => _currentIndex = index);
    }
  }

  /// [NAV-POLICY-N1] Home Task deep-link — target tab을 root normalize 후 route push.
  /// 1. mounted / index bounds / 권한 확인 → fail closed
  /// 2. target Navigator popUntil(isFirst) — stale stack 제거
  /// 3. tab selected (bottom nav = target)
  /// 4. post-frame push — IndexedStack 전환 이후 실행
  /// [return] true = push scheduled; false = fail closed (no side effect)
  bool _switchAndPush(int index, Route<dynamic> route) {
    if (!mounted) return false;
    if (index < 0 || index >= _navigatorKeys.length) return false;
    final up = context.read<UserProvider>();
    if (!_visibleTabIndices(up).contains(index)) return false;

    final targetNav = _navigatorKeys[index].currentState;
    if (targetNav == null) return false;

    // target tab stack root 정규화 — stale 월별/Dashboard 제거
    targetNav.popUntil((r) => r.isFirst);

    // bottom nav target tab으로 전환
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }

    // IndexedStack 전환 완료 이후 push
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = _navigatorKeys[index].currentState;
      if (nav == null) return;
      nav.push(route);
    });

    return true;
  }

  /// 권한 기반 표시 탭 인덱스 목록 — 홈(0)·MY(4)는 항상 포함
  List<int> _visibleTabIndices(UserProvider up) => [
        0, // 홈 — 항상 표시
        if (up.can((p) => p.canManageTo)) 1,      // 공고
        if (up.can((p) => p.canManageWorkers)) 2, // 인력
        if (up.can((p) => p.canManageWage)) 3,    // 정산
        4, // MY — 항상 표시
      ];

  BottomNavigationBarItem _navItemAt(int index) {
    switch (index) {
      case 1:
        return const BottomNavigationBarItem(
            icon: Icon(Icons.work_outline_rounded),
            activeIcon: Icon(Icons.work_rounded),
            label: '공고');
      case 2:
        return const BottomNavigationBarItem(
            icon: Icon(Icons.people_outline_rounded),
            activeIcon: Icon(Icons.people_rounded),
            label: '인력');
      case 3:
        return const BottomNavigationBarItem(
            icon: Icon(Icons.payments_outlined),
            activeIcon: Icon(Icons.payments_rounded),
            label: '정산');
      case 4:
        return const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: 'MY');
      default: // 0: 홈
        return const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: '홈');
    }
  }

  Widget _buildTabNavigator(int index, Widget root) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (_) => root,
        settings: settings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final up = context.watch<UserProvider>();

    // PD-02: 권한 기반 표시 탭 계산
    final visibleIndices = _visibleTabIndices(up);

    // 권한 회수로 현재 탭이 숨겨지면 홈(0)으로 자동 이동
    if (!visibleIndices.contains(_currentIndex)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentIndex = 0);
      });
    }

    final currentVisibleIdx =
        visibleIndices.indexOf(_currentIndex).clamp(0, visibleIndices.length - 1);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // 현재 탭 내 라우트가 있으면 탭 안에서 pop, 루트이면 system back 허용
        final navKey = _navigatorKeys[_currentIndex];
        if (navKey.currentState?.canPop() == true) {
          navKey.currentState!.pop();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildTabNavigator(0, const BusinessAdminHomeScreen()),
            _buildTabNavigator(1, const JobsRootScreen()),
            _buildTabNavigator(2, const WorkforceRootScreen()),
            _buildTabNavigator(3, const PayrollOverviewScreen()),
            _buildTabNavigator(4, const SettingsScreen()),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: currentVisibleIdx,
          onTap: (i) => switchToTab(visibleIndices[i]),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: theme.primaryColor,
          unselectedItemColor: AppColors.grey500,
          selectedLabelStyle: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 10),
          elevation: 0,
          backgroundColor: Colors.white,
          items: [for (final idx in visibleIndices) _navItemAt(idx)],
        ),
      ),
    );
  }
}
