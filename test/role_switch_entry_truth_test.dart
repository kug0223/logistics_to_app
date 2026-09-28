// [R7-P3-1 P31-D / VJ11] 서브관리자 **역할 전환**의 양방향 진입점을 실제로 렌더한다.
//
// 지금까지 VJ11 은 "전환·해제 경로 관찰 미착수" 였다. 두 입구는 서로 다른
// 화면에 있다 — 들어가는 문은 지원자 **MY 탭**, 나오는 문은 **설정** 안이다.
// 권한을 부여·해제하지 않고, 현재 provider 상태만으로 무엇이 보이는지 잰다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/theme_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/settings_screen.dart';
import 'package:ALfit/screens/user/tabs/user_my_tab.dart';

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

/// 권한을 바꾸지 않는다 — 이미 서브관리자인 계정과 아닌 계정을 나란히 둔다.
class _P extends UserProvider {
  _P({required this.sub, this.adminMode = false, this.bizIds = const ['biz1']});
  final bool sub;
  final bool adminMode;
  final List<String> bizIds;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        // 서브관리자는 별도 role 이 아니다 — `USER` + 비어있지 않은
        // `subAdminBusinessIds` 가 곧 서브관리자다(`UserModel.isSubAdmin`).
        role: UserRole.USER,
        subAdminBusinessIds: sub ? bizIds : const [],
        createdAt: DateTime(2026, 1, 1),
      );
  @override
  bool get isSubAdmin => sub;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => adminMode;
  @override
  bool get permissionsLoaded => true;
}

Future<void> _pumpMy(WidgetTester tester, {required bool sub}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _P(sub: sub),
      child: const MaterialApp(home: Scaffold(body: UserMyTab())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('[RSW-1] 서브관리자의 MY 탭에는 관리자 모드로 들어가는 입구가 보인다',
      (tester) async {
    await _pumpMy(tester, sub: true);
    expect(tester.takeException(), isNull);

    // 들어가는 문 — 섹션명 `관리자`, 항목 `관리자 모드로 전환`.
    expect(find.text('관리자'), findsOneWidget);
    expect(find.text('관리자 모드로 전환'), findsOneWidget);
  });

  testWidgets('[RSW-2] 서브관리자가 아니면 그 입구가 아예 없다', (tester) async {
    await _pumpMy(tester, sub: false);
    expect(tester.takeException(), isNull);

    expect(find.text('관리자 모드로 전환'), findsNothing);

    // 헛도는 대조가 아님을 보이는 양성 대조 — 같은 탭의 다른 항목은 살아 있다.
    expect(find.text('프로필 관리'), findsOneWidget);
  });

  testWidgets('[RSW-3] 나오는 문은 MY 탭에 없다 — 비대칭을 사실로 고정한다',
      (tester) async {
    await _pumpMy(tester, sub: true);

    // `지원자 모드로 전환` 은 설정 화면의 `서브관리자 관리` 섹션에만 있다.
    // 들어가는 문(MY 1단계)과 나오는 문(설정 2단계)의 깊이가 다르다.
    // 이것은 결함 판정이 아니라 **발견성 후보(P31-F)** 의 근거다.
    expect(find.text('지원자 모드로 전환'), findsNothing);
  });

  testWidgets('[RSW-4] 나오는 문은 설정의 `서브관리자 관리` 안에 있고, 관리자 모드일 때만 뜬다',
      (tester) async {
    for (final adminMode in [true, false]) {
      tester.view.physicalSize = const Size(390, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(
                create: (_) => _P(sub: true, adminMode: adminMode)),
            ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
            ChangeNotifierProvider<NotificationProvider>(
                create: (_) => NotificationProvider()),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 섹션은 서브관리자면 항상 있다 — `서브관리자 탈퇴` 가 그 증거(양성 대조).
      expect(find.text('서브관리자 관리'), findsOneWidget,
          reason: 'adminMode=$adminMode');
      expect(find.text('서브관리자 탈퇴'), findsOneWidget,
          reason: 'adminMode=$adminMode');

      // 복귀 CTA 는 **관리자 모드일 때만** 나타난다.
      expect(find.text('지원자 모드로 전환'),
          adminMode ? findsOneWidget : findsNothing,
          reason: 'adminMode=$adminMode');
    }
  });
}
