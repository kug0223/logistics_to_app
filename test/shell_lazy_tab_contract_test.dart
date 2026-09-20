// [R8-P1A] 셸에 들어오는 것만으로 안 보이는 탭까지 로드되지 않는다.
//
//   IndexedStack은 자식을 전부 만든다. 그래서 관리자가 홈에 들어오는 순간
//   공고·급여·관리의 initState가 함께 돌았고, 보이지도 않는 탭 셋이 첫 화면과
//   같은 네트워크 대역을 나눠 썼다.
//
//   숨기는 것이 목적이 아니라 로드를 미루는 것이 목적이다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _shell() => File(
    'lib/screens/business_admin/business_admin_shell.dart').readAsStringSync();
String _workforceRoot() => File(
    'lib/screens/business_admin/workforce_management/workforce_root_screen.dart')
    .readAsStringSync();

/// 주석으로 시작하는 줄만 제거한다 (문서 주석은 남는다).
String _codeOf(String raw) => raw
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  final shell = _shell();
  final code = _codeOf(shell);
  final f = _flat(code);

  group('SL-1 — 방문한 탭만 만든다', () {
    test('SL-10 방문 집합이 존재하고 최초 탭만 들어간다', () {
      expect(f, contains('final Set<int> _visitedTabs = <int>{}'));
      expect(f, contains('_visitedTabs.add(_currentIndex)'));
    });

    test('SL-11 미방문 탭 자리에는 아무것도 하지 않는 위젯이 들어간다', () {
      expect(f, contains(
          'if (!_visitedTabs.contains(index)) return const SizedBox.shrink()'));
    });

    test('SL-12 자식을 빌더로 받아 방문 시점에만 만든다 — eager init 방지', () {
      expect(f, contains('Widget _lazyTab(int index, Widget Function() root)'));
      expect(f, contains('return _buildTabNavigator(index, root())'));
    });

    test('SL-13 다섯 탭 전부 lazy 경로를 쓴다', () {
      for (final t in [
        '_lazyTab(0, () => const BusinessAdminHomeScreen())',
        '_lazyTab( 1, () => JobsRootScreen(postingController: _postingController))',
        '_lazyTab(2, () => WorkforceRootScreen(postingController: _postingController))',
        '_lazyTab(3, () => const PayrollOverviewScreen())',
        '_lazyTab(4, () => const SettingsScreen())',
      ]) {
        expect(f, contains(t), reason: t);
      }
      // 직접 생성 경로가 남아 있지 않다
      expect(f, isNot(contains('_buildTabNavigator(0, const BusinessAdminHomeScreen())')));
      expect(f, isNot(contains('_buildTabNavigator(3, const PayrollOverviewScreen())')));
    });
  });

  group('SL-2 — 상태 보존은 그대로다', () {
    test('SL-20 IndexedStack 을 유지한다 — 탭 전환마다 만들지 않는다', () {
      expect(f, contains('IndexedStack( index: _currentIndex'));
    });

    test('SL-21 한 번 방문하면 집합에서 빠지지 않는다', () {
      expect(code, isNot(contains('_visitedTabs.remove')));
      expect(code, isNot(contains('_visitedTabs.clear')));
    });

    test('SL-22 Navigator key 는 탭마다 고정 유지', () {
      expect(f, contains('key: _navigatorKeys[index]'));
    });
  });

  group('SL-3 — 프로그램적 전환·딥링크도 lazy 로 열린다', () {
    test('SL-30 탭 전환이 방문 처리한다', () {
      final sw = code.substring(code.indexOf('bool switchToTab(int index)'));
      expect(_flat(sw.substring(0, sw.indexOf('bool _switchAndPush'))),
          contains('_visitedTabs.add(index)'));
    });

    test('SL-31 딥링크가 미방문 탭에서 fail closed 되지 않는다', () {
      expect(f, contains('final firstOpen = !_visitedTabs.contains(index)'));
      expect(f, contains('if (!firstOpen && targetNav == null) return false'));
      expect(f, contains('targetNav?.popUntil((r) => r.isFirst)'));
    });

    test('SL-32 딥링크도 방문 처리 후 전환한다', () {
      expect(f, contains('if (_currentIndex != index || firstOpen)'));
    });

    test('SL-33 권한 검사는 전환보다 먼저다 — 숨은 탭을 만들지 않는다', () {
      final sp = code.substring(code.indexOf('bool _switchAndPush(int index'));
      final permAt = sp.indexOf('_visibleTabIndices(up).contains(index)');
      final visitAt = sp.indexOf('_visitedTabs.add(index)');
      expect(permAt, greaterThan(-1));
      expect(visitAt, greaterThan(permAt));
    });
  });

  group('SL-4 — Workforce 첫 방문 회귀 방지', () {
    final wf = _codeOf(_workforceRoot());
    final wff = _flat(wf);

    test('SL-40 공유 controller 가 비어 있으면 첫 방문에서 로드한다', () {
      expect(wff, contains('if (_ownsController || !_controller.hasLoadedOnce)'));
      expect(wff, contains('_controller.load(context)'));
    });

    test('SL-41 이미 로드된 뒤에는 다시 돌지 않는다', () {
      // hasLoadedOnce 가 조건에 포함되어 재방문 중복 조회를 막는다
      expect(wff, contains('!_controller.hasLoadedOnce'));
    });

    test('SL-42 controller 소유권은 그대로 Shell 이다', () {
      expect(wff, contains('bool get _ownsController => widget.postingController == null'));
      expect(wff, contains('if (_ownsController) _controller.dispose()'));
    });
  });
}
