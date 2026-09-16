import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/fcm_service.dart';
import '../../theme/app_colors.dart';
import 'my_schedule_screen.dart';
import 'user_home_screen.dart';
import '../../widgets/user/pending_contract_bar.dart';
import 'user_tab_scope.dart';
import 'tabs/user_job_tab.dart';
import 'tabs/user_my_tab.dart';

/// 지원자 루트 화면 — 4탭 BottomNavigationBar + IndexedStack
///
/// 탭 구조:
///   0: 홈 (UserHomeScreen)
///   1: 일자리 (UserJobTab)
///   2: 일정 (MyScheduleScreen)
///   3: MY (UserMyTab)
///
/// 각 탭은 독립 Navigator를 가져 탭별 라우트 스택이 분리된다.
/// 탭 간 이동 시 상태가 유지된다 (IndexedStack).
class UserRootScreen extends StatefulWidget {
  const UserRootScreen({super.key});

  @override
  State<UserRootScreen> createState() => _UserRootScreenState();
}

class _UserRootScreenState extends State<UserRootScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // [Phase 9D] cold-start pending payload 소비
    // role root가 실제 마운트된 후 첫 프레임에서 1회 실행 — back stack이 올바르게 구성된 상태에서 navigate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FCMService().consumePendingColdStartPayload();
    });
  }

  /// 홈에서 날짜 지정 후 일자리 탭으로 이동할 때 임시 보관하는 날짜.
  /// UserJobTab이 소비(_clearPendingJobDate 호출)하면 null이 된다.
  DateTime? _pendingJobDate;

  /// 홈 "근무 기록 보기" → 일정 탭 이동 시 현재 달 리셋을 요청하는 날짜.
  /// MyScheduleScreen이 소비(_clearPendingScheduleMonth 호출)하면 null이 된다.
  DateTime? _pendingScheduleMonth;

  /// 탭별 독립 네비게이터 키 — 각 탭이 자체 라우트 스택을 관리한다
  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(), // 0: 홈
    GlobalKey<NavigatorState>(), // 1: 일자리
    GlobalKey<NavigatorState>(), // 2: 일정
    GlobalKey<NavigatorState>(), // 3: MY
  ];

  /// 일반 탭 전환 — 이미 선택된 탭 재탭 시 해당 탭 루트로 복귀.
  /// 날짜를 전달하지 않으므로 _pendingJobDate는 건드리지 않는다.
  void switchToTab(int index) {
    if (_currentIndex == index) {
      _navigatorKeys[index].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _currentIndex = index);
    }
  }

  /// 날짜를 지정하여 일자리 탭(index=1)으로 전환.
  /// 홈의 날짜 선택 CTA 버튼에서만 호출된다.
  void _switchToTabWithDate(int index, DateTime date) {
    if (_currentIndex == index) {
      _navigatorKeys[index].currentState?.popUntil((r) => r.isFirst);
    }
    setState(() {
      _currentIndex = index;
      _pendingJobDate = date;
    });
  }

  /// UserJobTab이 pendingJobDate를 소비한 후 호출.
  /// root 상태에서 _pendingJobDate를 null로 초기화한다.
  void _clearPendingJobDate() {
    if (_pendingJobDate != null) {
      setState(() => _pendingJobDate = null);
    }
  }

  /// 홈 "근무 기록 보기" → 일정 탭(index=2) 전환 + 현재 달 리셋 요청.
  void _switchToScheduleNow() {
    if (_currentIndex == 2) {
      _navigatorKeys[2].currentState?.popUntil((r) => r.isFirst);
    }
    setState(() {
      _currentIndex = 2;
      _pendingScheduleMonth = DateTime.now();
    });
  }

  /// MyScheduleScreen이 pendingScheduleMonth를 소비한 후 호출.
  void _clearPendingScheduleMonth() {
    if (_pendingScheduleMonth != null) {
      setState(() => _pendingScheduleMonth = null);
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
      child: UserTabScope(
        switchToTab: switchToTab,
        switchToTabWithDate: _switchToTabWithDate,
        pendingJobDate: _pendingJobDate,
        clearPendingJobDate: _clearPendingJobDate,
        pendingScheduleMonth: _pendingScheduleMonth,
        clearPendingScheduleMonth: _clearPendingScheduleMonth,
        switchToScheduleNow: _switchToScheduleNow,
        child: Scaffold(
          body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildTabNavigator(0, const UserHomeScreen()),
            _buildTabNavigator(1, const UserJobTab()),
            _buildTabNavigator(2, const MyScheduleScreen()),
            _buildTabNavigator(3, const UserMyTab()),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 미서명 계약서 배너 — UserHomeScreen에서 이동
            // (내부에서 isAdminMode·hasPendingContract 체크하여 자체 표시 제어)
            const PendingContractBar(),
            BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: switchToTab,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: AppColors.infoDark,
              unselectedItemColor: AppColors.grey400,
              selectedLabelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
              elevation: 0,
              backgroundColor: Colors.white,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home_rounded),
                  label: '홈',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.work_outline_rounded),
                  activeIcon: Icon(Icons.work_rounded),
                  label: '일자리',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.calendar_month_outlined),
                  activeIcon: Icon(Icons.calendar_month_rounded),
                  label: '일정',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline_rounded),
                  activeIcon: Icon(Icons.person_rounded),
                  label: 'MY',
                ),
              ],
            ),
          ],
        ),
        ),       // UserTabScope
      ),
    );
  }
}
