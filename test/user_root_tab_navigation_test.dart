import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_schedule_screen.dart';
import 'package:ALfit/screens/user/tabs/user_job_tab.dart';
import 'package:ALfit/screens/user/tabs/user_my_tab.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/screens/user/user_root_screen.dart';

/// [R7-P2-1 P21-N] **실제 지원자 루트**의 네 탭 선택과 뒤로 경로.
///
///   탭 루트가 무엇인지·탭별 스택이 분리되는지·시스템 뒤로가 탭 안에서
///   먼저 소비되는지를 소스가 아니라 **행동**으로 본다.

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _UserProviderDouble extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
        accountStatus: 'active',
      );
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
  @override
  bool get hasPendingContract => false;
}

Future<void> _pump(WidgetTester tester,
    {Size size = const Size(390, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(
            create: (_) => _UserProviderDouble()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: const MaterialApp(home: UserRootScreen()),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tour_completed_user_home': true,
    });
  });

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('URN-1 네 탭의 루트는 홈·일자리·일정·MY 이고 홈이 처음 선택된다',
      (tester) async {
    await _pump(tester);

    // IndexedStack 이므로 네 루트가 모두 만들어져 있다(상태 유지 구조).
    //   선택되지 않은 탭은 Offstage 라 skipOffstage 를 꺼야 보인다.
    expect(find.byType(UserHomeScreen), findsOneWidget);
    expect(find.byType(UserJobTab, skipOffstage: false), findsOneWidget);
    expect(find.byType(MyScheduleScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(UserMyTab, skipOffstage: false), findsOneWidget);

    final bar = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar));
    expect(bar.currentIndex, 0, reason: '첫 화면은 홈이다');
    expect(bar.items.map((i) => i.label).toList(),
        ['홈', '일자리', '일정', 'MY']);
  });

  testWidgets('URN-2 탭을 누르면 그 탭이 선택된다', (tester) async {
    await _pump(tester);

    for (final entry in const {'일자리': 1, '일정': 2, 'MY': 3, '홈': 0}.entries) {
      await tester.tap(find.text(entry.key).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final bar = tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(bar.currentIndex, entry.value,
          reason: '${entry.key} 탭을 눌렀는데 다른 탭이 선택됐다');
    }
  });

  testWidgets('URN-3 시스템 뒤로는 탭 안쪽 스택을 먼저 소비한다', (tester) async {
    await _pump(tester);

    // 홈 탭의 내부 Navigator 에 화면 하나를 쌓는다.
    final homeNav = find.byType(Navigator);
    expect(homeNav, findsWidgets);
    final navState = tester.state<NavigatorState>(
        find.descendant(of: find.byType(IndexedStack), matching: homeNav).first);
    navState.push(MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('탭 안쪽 화면'))));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('탭 안쪽 화면'), findsOneWidget);

    // 시스템 뒤로 — 앱이 종료되는 대신 탭 안쪽에서 pop 돼야 한다.
    final popped =
        await tester.binding.handlePopRoute().then((_) => true).catchError(
              (Object _) => false,
            );
    expect(popped, isTrue);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('탭 안쪽 화면'), findsNothing,
        reason: '탭 안에 쌓인 화면이 있는데 시스템 뒤로가 앱을 닫으면 안 된다');
    expect(find.byType(UserHomeScreen), findsOneWidget);
  });
}
