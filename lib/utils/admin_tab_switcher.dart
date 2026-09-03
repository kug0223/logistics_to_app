// lib/utils/admin_tab_switcher.dart
//
// 관리자 Shell 탭 전환 싱글턴 — FCMService ↔ BusinessAdminShell 연결
//
import 'package:flutter/widgets.dart';
// [설계 원칙]
//   - Shell 없이도 안전하게 호출 가능 (isRegistered 체크 또는 무시)
//   - Shell initState에서 register, dispose에서 unregister
//   - FCMService는 isRegistered 체크 후 탭 전환, 미등록 시 fallback 경로 사용
//   - InheritedWidget 불필요 — 단순 콜백 패턴으로 충분
//
// [탭 인덱스]
//   BusinessAdminShell 기준:
//     0: 홈, 1: 공고(Jobs), 2: 인력(Workforce), 3: 정산, 4: MY
//
// [사용 예]
//   // Shell initState:
//     AdminTabSwitcher.instance.register(switchToTab);
//   // Shell dispose:
//     AdminTabSwitcher.instance.unregister();
//   // FCMService:
//     if (AdminTabSwitcher.instance.isRegistered) {
//       AdminTabSwitcher.instance.switchToTab(AdminTabSwitcher.jobsTab);
//     } else { /* fallback */ }

class AdminTabSwitcher {
  static final AdminTabSwitcher _instance = AdminTabSwitcher._();
  AdminTabSwitcher._();
  static AdminTabSwitcher get instance => _instance;

  /// BusinessAdminShell 탭 인덱스 상수
  static const int homeTab = 0;
  static const int jobsTab = 1;
  static const int workforceTab = 2;
  static const int payrollTab = 3;
  static const int settingsTab = 4;

  bool Function(int)? _switchFn;

  // [NAV-POLICY-N1] Home Task deep-link — target tab root normalize + push
  bool Function(int, Route<dynamic>)? _switchAndPushFn;

  /// Shell이 활성화되어 탭 전환 가능한 상태인지 여부
  bool get isRegistered => _switchFn != null;

  /// [Shell 전용] initState에서 호출 — 탭 전환 콜백 등록
  void register(bool Function(int) fn) => _switchFn = fn;

  /// [Shell 전용] initState에서 호출 — tab normalize + push 콜백 등록
  void registerSwitchAndPush(bool Function(int, Route<dynamic>) fn) =>
      _switchAndPushFn = fn;

  /// [Shell 전용] dispose에서 호출 — 모든 콜백 해제
  void unregister() {
    _switchFn = null;
    _switchAndPushFn = null;
  }

  /// Shell을 지정 탭으로 전환.
  /// Shell이 활성화되지 않은 경우(앱 재시작 등) 무시됨.
  /// isRegistered 확인 후 호출하거나, 반환값을 확인해 fallback 처리할 것.
  /// [return] true = Shell이 요청을 실제로 accept (visible + mounted + valid index)
  ///          false = Shell 미등록·unmounted·hidden·invalid index
  bool switchToTab(int index) {
    final fn = _switchFn;
    if (fn == null) return false;
    return fn(index);
  }

  /// [Home Task Navigation] target tab을 root normalize 후 route push.
  /// 권한/비가시 탭이면 false 반환 — fail closed.
  /// [return] true = push scheduled; false = shell 미등록·tab 불가·권한 없음
  bool switchToTabAndPush(int index, Route<dynamic> route) {
    if (_switchAndPushFn == null) return false;
    return _switchAndPushFn!(index, route);
  }
}
