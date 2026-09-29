// [R7-P4.2C] 같은 목적지는 같은 위치로 말한다 — 그리고 준비 상태의 owner.
//
// ── 무엇이 잘못됐었나 ───────────────────────────────────────────────
//   Home 헤더의 사람 아이콘은 `const SettingsScreen()` 을 push 했다.
//   하단 '관리' 탭의 root 도 **같은 위젯, 같은 파라미터**다.
//   그래서 누르면:
//       화면 제목       = '관리'
//       하단 선택 탭    = '홈'
//   같은 목적지인데 내가 어느 top-level 영역에 있는지를 shell 이 다르게
//   말했다.
//
//   그런데 그 push 는 복귀 시 `_reloadReadiness()` 를 부르고 있었다.
//   단순히 탭 전환으로 바꾸면 그 갱신이 사라진다 — 그래서 **함께** 옮긴다.
//
// ── 이번에 드러난 더 큰 사실 ────────────────────────────────────────
//   그 갱신은 원래부터 **반쪽**이었다. 같은 화면에 하단 '관리' 탭으로
//   들어간 경우에는 아무도 readiness 를 다시 읽지 않았다.
//   갱신 owner 가 화면이 아니라 **한쪽 입구**에 붙어 있었기 때문이다.
//
// ── 무엇을 여기서 볼 수 있고 무엇을 못 보는가 ────────────────────────
//   `AdminTabSwitcher` 는 Firebase 가 필요 없는 실제 production 클래스라
//   그대로 돌린다(NAV-C 묶음).
//   `BusinessAdminShell` 은 UserProvider·FCMService 때문에 pump 할 수
//   없어서, 어느 index 에서 알림을 쏘는지는 **소스 계약**으로 고정한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/admin_tab_switcher.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: '$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

const _home = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _shell = 'lib/screens/business_admin/business_admin_shell.dart';
const _switcher = 'lib/utils/admin_tab_switcher.dart';

void main() {
  // ══════════════════════════════════════════════════════════════
  // DEST-01. 같은 목적지 — 그러면 같은 위치로 말해야 한다
  // ══════════════════════════════════════════════════════════════
  group('DEST-01 목적지 동일성', () {
    test('DEST-01a 관리 탭 root 와 헤더 목적지가 같은 위젯이었다 (전제)', () {
      // 이 전제가 깨지면(예: 관리 탭이 다른 root 를 쓰게 되면) 아래 판정의
      // 근거가 사라진다 — 그때 다시 판단해야 한다.
      expect(_src(_shell).contains('_lazyTab(4, () => const SettingsScreen())'),
          isTrue);
    });

    test('DEST-01b 헤더는 이제 push 하지 않고 그 탭으로 간다', () {
      final s = _src(_home);
      final i = s.indexOf('[P4.2C-NAV-01]');
      expect(i, greaterThan(-1));
      final block = s.substring(i, i + 1600);
      expect(block.contains('switchToTab(AdminTabSwitcher.settingsTab)'),
          isTrue);
      expect(block.contains('MaterialPageRoute(builder: (_) => const SettingsScreen())'),
          isFalse, reason: '같은 root 를 한 번 더 쌓지 않는다');
    });

    test('DEST-01c 아이콘이 목적지를 따라간다', () {
      final s = _src(_home);
      // person_outline 은 이 제품에서 '프로필 관리'(지원자 MY 탭 →
      // ProfileEditScreen)를 뜻한다. 여기 목적지는 프로필이 아니라
      // 관리 영역 전체이므로 관리 탭과 같은 아이콘을 쓴다.
      expect(s.contains('_headerBtn(context, s, Icons.settings_outlined,'),
          isTrue);
      expect(s.contains('_headerBtn(context, s, Icons.person_outline,'),
          isFalse);
      expect(_src(_shell).contains('Icon(Icons.settings_outlined)'), isTrue,
          reason: '관리 탭 아이콘과 같은 것을 쓴다');
    });

    test('DEST-01d 버튼을 숨기거나 지우지 않았다', () {
      // 증상(탭 불일치)을 없애는 가장 쉬운 방법은 버튼을 빼는 것이다.
      // 그건 진입점을 잃는 것이지 고친 것이 아니다.
      final s = _src(_home);
      final i = s.indexOf('[P4.2C-NAV-01]');
      final block = s.substring(i, i + 1600);
      expect(block.contains('_headerBtn('), isTrue);
      // 알림 버튼은 그대로 push 다 — 알림은 top-level 탭이 아니다.
      expect(s.contains('builder: (_) => const NotificationScreen()'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // READY-01. 준비 상태 갱신의 owner
  // ══════════════════════════════════════════════════════════════
  group('READY-01 readiness refresh owner', () {
    late final String s;
    setUpAll(() => s = _src(_home));

    test('READY-01a 재활성화 핸들러를 등록하고 해제한다', () {
      expect(
          s.contains(
              'AdminTabSwitcher.instance.registerHomeReactivation(_onHomeReactivated)'),
          isTrue);
      expect(
          s.contains(
              'AdminTabSwitcher.instance.unregisterHomeReactivation(_onHomeReactivated)'),
          isTrue,
          reason: '해제하지 않으면 dispose 된 화면이 계속 불린다');
    });

    test('READY-01b 관리 탭에서 왔을 때만 다시 읽는다', () {
      final i = s.indexOf('void _onHomeReactivated(int fromTab) {');
      expect(i, greaterThan(-1));
      final end = s.indexOf('bool _isReloadingReadiness', i);
      expect(end, greaterThan(i));
      final body = s.substring(i, end);
      expect(body.contains('fromTab != AdminTabSwitcher.settingsTab'), isTrue,
          reason: '모든 탭 전환이 Home reload 가 되면 안 된다');
      expect(body.contains('_reloadReadinessGuarded()'), isTrue);
      // 전체 refresh 가 아니다 — readiness 두 loader 만이다.
      expect(body.contains('_refresh()'), isFalse);
      expect(body.contains('_autoRefresh()'), isFalse);
    });

    test('READY-01c 겹쳐 돌지 않는다', () {
      expect(s.contains('if (_isReloadingReadiness) return;'), isTrue);
      final i = s.indexOf('Future<void> _reloadReadinessGuarded() async {');
      expect(i, greaterThan(-1));
      final body = s.substring(i, i + 320);
      expect(body.contains('_isReloadingReadiness = true;'), isTrue);
      expect(body.contains('} finally {'), isTrue,
          reason: '실패해도 플래그가 남으면 이후 갱신이 영영 막힌다');
    });

    test('READY-01d 시간 쿨다운을 두지 않았다', () {
      // "방금 읽었으니 건너뛴다" 는 관리 탭에서 막 인감을 저장하고 돌아온
      // 바로 그 순간을 건너뛸 수 있다 — 이 수정이 고치려는 상태다.
      final i = s.indexOf('void _onHomeReactivated(int fromTab) {');
      final body = s.substring(i, s.indexOf('bool _isReloadingReadiness', i));
      expect(body.contains('Duration('), isFalse);
      expect(body.contains('difference('), isFalse);
    });

    test('READY-01e 기존 갱신 경로는 하나도 사라지지 않았다', () {
      // Home 체크리스트의 네 항목은 여전히 자기 복귀에서 다시 읽는다.
      expect('_reloadReadiness()'.allMatches(s).length,
          greaterThanOrEqualTo(6));
      expect(s.contains('Future<void> _reloadReadiness() async {'), isTrue);
      // 당겨서 새로고침도 그대로.
      final i = s.indexOf('Future<void> _refresh() async {');
      expect(s.substring(i, i + 700).contains('_reloadReadiness()'), isTrue);
    });

    test('READY-01f 새 listener·polling 을 만들지 않았다', () {
      expect(s.contains('Timer.periodic'), isFalse);
      // 기존 신호 두 개(FCM, dataRevision)는 그대로고 종류를 늘리지 않았다.
      expect(s.contains('WorkforceController.dataRevision.addListener'), isTrue);
      expect(s.contains('FCMService().addAdminRefreshListener'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // SHELL-01. 누가 언제 알리는가 (소스 계약 — Shell 은 pump 불가)
  // ══════════════════════════════════════════════════════════════
  group('SHELL-01 Shell 배선', () {
    late final String s;
    setUpAll(() => s = _src(_shell));

    test('SHELL-01a 홈으로 전환될 때만 알린다', () {
      expect(s.contains('if (index == AdminTabSwitcher.homeTab) {'), isTrue);
      expect(s.contains('AdminTabSwitcher.instance.notifyHomeReactivated(from)'),
          isTrue);
    });

    test('SHELL-01b 같은 탭 재탭은 재활성화가 아니다', () {
      // `_currentIndex == index` 는 popUntil 후 early return 한다 —
      // 그 위에서 끝나므로 알림이 나가지 않는다.
      final i = s.indexOf('if (_currentIndex == index) {');
      final notify = s.indexOf('notifyHomeReactivated');
      expect(i, greaterThan(-1));
      expect(notify, greaterThan(i));
      final between = s.substring(i, notify);
      expect(between.contains('return true;'), isTrue);
    });

    test('SHELL-01c 어디서 왔는지를 전환 **전에** 잡는다', () {
      final i = s.indexOf('final from = _currentIndex;');
      final set = s.indexOf('_currentIndex = index;', i);
      expect(i, greaterThan(-1));
      expect(set, greaterThan(i), reason: '전환 후에 읽으면 항상 홈이 된다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // NAV-C. AdminTabSwitcher 실물 동작
  // ══════════════════════════════════════════════════════════════
  group('NAV-C AdminTabSwitcher', () {
    tearDown(() {
      AdminTabSwitcher.instance.unregister();
    });

    test('NAV-C1 탭 상수가 5탭 순서 그대로다', () {
      expect(AdminTabSwitcher.homeTab, 0);
      expect(AdminTabSwitcher.jobsTab, 1);
      expect(AdminTabSwitcher.workforceTab, 2);
      expect(AdminTabSwitcher.payrollTab, 3);
      expect(AdminTabSwitcher.settingsTab, 4);
    });

    test('NAV-C2 헤더가 요청하는 탭은 관리(4)다', () {
      final asked = <int>[];
      AdminTabSwitcher.instance.register((i) {
        asked.add(i);
        return true;
      });
      final ok =
          AdminTabSwitcher.instance.switchToTab(AdminTabSwitcher.settingsTab);
      expect(ok, isTrue);
      expect(asked, [4]);
    });

    test('NAV-C3 Shell 이 거부하면 그대로 false 로 돌아온다', () {
      // 권한 없는 탭·unmounted 는 Shell 이 판단한다. 스위처가 임의로
      // 성공이라고 말하지 않는다.
      AdminTabSwitcher.instance.register((_) => false);
      expect(AdminTabSwitcher.instance.switchToTab(4), isFalse);
    });

    test('NAV-C4 Shell 미등록이면 조용히 실패한다', () {
      expect(AdminTabSwitcher.instance.switchToTab(4), isFalse);
    });

    test('NAV-C5 재활성화 알림이 출발 탭을 그대로 전달한다', () {
      final got = <int>[];
      void handler(int from) => got.add(from);
      AdminTabSwitcher.instance.registerHomeReactivation(handler);
      AdminTabSwitcher.instance.notifyHomeReactivated(4);
      AdminTabSwitcher.instance.notifyHomeReactivated(1);
      expect(got, [4, 1]);
      AdminTabSwitcher.instance.unregisterHomeReactivation(handler);
      AdminTabSwitcher.instance.notifyHomeReactivated(4);
      expect(got, [4, 1], reason: '해제 후에는 오지 않는다');
    });

    test('NAV-C6 해제는 identity 기준이다', () {
      // 같은 화면이 다시 만들어진 뒤 **예전 인스턴스**의 dispose 가 늦게
      // 돌아도 새 등록을 지우지 않아야 한다.
      final got = <int>[];
      void oldHandler(int f) => got.add(-1);
      void newHandler(int f) => got.add(f);
      AdminTabSwitcher.instance.registerHomeReactivation(oldHandler);
      AdminTabSwitcher.instance.registerHomeReactivation(newHandler);
      AdminTabSwitcher.instance.unregisterHomeReactivation(oldHandler);
      AdminTabSwitcher.instance.notifyHomeReactivated(4);
      expect(got, [4]);
      AdminTabSwitcher.instance.unregisterHomeReactivation(newHandler);
    });

    test('NAV-C7 핸들러가 없어도 알림이 터지지 않는다', () {
      expect(() => AdminTabSwitcher.instance.notifyHomeReactivated(4),
          returnsNormally);
    });

    test('NAV-C8 빠르게 여러 번 눌러도 같은 탭만 요청된다', () {
      final asked = <int>[];
      AdminTabSwitcher.instance.register((i) {
        asked.add(i);
        return true;
      });
      for (var i = 0; i < 5; i++) {
        AdminTabSwitcher.instance.switchToTab(AdminTabSwitcher.settingsTab);
      }
      expect(asked, [4, 4, 4, 4, 4],
          reason: '중복 요청 흡수는 Shell 의 same-index early return 이 한다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // ROLE-01. 이 변경이 닿는 역할
  // ══════════════════════════════════════════════════════════════
  group('ROLE-01 역할 경계', () {
    test('ROLE-01a 지원자 Home 에는 이 버튼이 없다', () {
      // 같은 widget/caller 가 있는 역할만 본다. 지원자 Home 헤더에는
      // 알림 버튼 하나뿐이고 설정/프로필 진입은 MY 탭이 담당한다.
      final u = _src('lib/screens/user/user_home_screen.dart');
      expect(u.contains('SettingsScreen()'), isFalse);
      expect(u.contains('Icons.notifications_outlined'), isTrue);
    });

    test('ROLE-01b SUPER_ADMIN 은 이 Shell 에 들어오지 않는다', () {
      final m = _src('lib/main.dart');
      final i = m.indexOf('case UserRole.SUPER_ADMIN:');
      expect(i, greaterThan(-1));
      final block = m.substring(i, i + 200);
      expect(block.contains('AdminHomeScreen()'), isTrue);
      expect(block.contains('BusinessAdminShell()'), isFalse);
    });

    test('ROLE-01c SubAdmin 관리자 모드도 같은 Shell 을 쓴다', () {
      final m = _src('lib/main.dart');
      expect(m.contains('user.isSubAdmin && userProvider.isAdminMode'), isTrue);
      expect(
          'BusinessAdminShell()'.allMatches(m).length, greaterThanOrEqualTo(2));
    });

    test('ROLE-01d 역할 전환 semantics 를 건드리지 않았다', () {
      // 모드 토글은 헤더의 **다른** 위젯이고, 관리 화면 안의 전환 항목도
      // 그대로다. 목적지가 같으므로 두 경로 모두 여전히 닿는다.
      final s = _src(_home);
      expect(s.contains('_buildSubAdminModeToggle(context, s, up, theme)'),
          isTrue);
      expect(
          _src('lib/screens/common/settings_screen.dart')
              .contains("title: '지원자 모드로 전환'"),
          isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // BACK-01. 뒤로가기 계약
  // ══════════════════════════════════════════════════════════════
  group('BACK-01 back semantics', () {
    test('BACK-01a top-level root 에서의 back 은 Shell 계약 그대로다', () {
      // 바뀐 것: 예전에는 push 였으므로 back 이 Home 으로 돌아왔다.
      // 지금은 관리 탭 root 이므로 다른 root 와 **같은 규칙**을 따른다 —
      // 탭 안에 쌓인 route 가 있으면 그것부터, 없으면 시스템 back.
      // 이 규칙 자체는 이번에 만들지 않았다.
      final s = _src(_shell);
      expect(s.contains('canPop: false'), isTrue);
      expect(s.contains('navKey.currentState?.canPop() == true'), isTrue);
      expect(s.contains('SystemNavigator.pop();'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // SWITCHER-01. 범위 밖 무변경
  // ══════════════════════════════════════════════════════════════
  test('SWITCHER-01 기존 핸들러 종류를 늘리거나 줄이지 않았다', () {
    final s = _src(_switcher);
    for (final fn in const [
      'registerSwitchAndPush',
      'registerJobsNavHandler',
      'registerJobsTargetHandler',
      'switchToJobsWithTarget',
      'switchToJobsWithIntent',
      'switchToTabAndPush',
    ]) {
      expect(s.contains(fn), isTrue, reason: fn);
    }
  });
}
