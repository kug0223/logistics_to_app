import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/apply_prerequisites_screen.dart';
import 'package:ALfit/widgets/common/app_page_scaffold.dart';
import 'package:ALfit/widgets/common/gradient_scaffold.dart';

/// [R7-P2-2 P22-G] 지원 준비 화면의 shell 전환이 **헤더·본문·행동을 유지**하는지.

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

class _P extends UserProvider {
  _P({this.ready = false});
  final bool ready;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
        accountStatus: 'active',
        passVerifiedAt: DateTime.now().subtract(const Duration(days: 10)),
        isIdVerified: ready,
        idCardImagePath: ready ? 'users/u1/id.png' : null,
        bankName: ready ? '국민은행' : null,
        accountNumber: ready ? '1234' : null,
        bankbookImagePath: ready ? 'users/u1/bb.png' : null,
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
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 1400),
  double textScale = 1.0,
  bool ready = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P(ready: ready)),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () =>
                  ApplyPrerequisitesScreen.show(ctx, isFlexType: true),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('APS-1 flat shell 로 열리고 헤더 문구와 본문이 유지된다', (tester) async {
    await _pump(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(AppPageScaffold), findsOneWidget);
    expect(find.byType(GradientScaffold), findsNothing,
        reason: '이 화면은 flat shell 로 전환됐다');
    expect(find.text('지원하기'), findsWidgets, reason: '헤더 제목이 남아 있어야 한다');
    expect(find.text('지원 전 준비사항'), findsOneWidget, reason: '본문이 그대로여야 한다');
  });

  testWidgets('APS-2 뒤로가 동작한다 — 호출 화면으로 돌아온다', (tester) async {
    await _pump(tester);
    expect(find.text('지원 전 준비사항'), findsOneWidget);

    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.pop();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('지원 전 준비사항'), findsNothing);
    expect(find.text('열기'), findsOneWidget);
  });

  testWidgets('APS-3 준비 완료 계정에서는 지원하기 CTA 가 살아 있다', (tester) async {
    await _pump(tester, ready: true);

    expect(tester.takeException(), isNull);
    // '지원하기' 는 헤더 제목과 CTA 라벨 둘 다 — CTA 버튼이 존재하는지 본다.
    expect(find.text('다시 확인'), findsOneWidget, reason: '버튼 줄이 그려져야 한다');
    // CTA 는 헤더 제목과 같은 문구라 **버튼 줄의 존재**로 확인한다.
    expect(find.byIcon(Icons.send_outlined), findsOneWidget);
  });

  for (final size in const [Size(320, 1400), Size(412, 1400)]) {
    for (final scale in const [1.3, 2.0]) {
      testWidgets(
          'APS-R ${size.width.toInt()}dp × $scale — 제목·준비사항이 예외 없이 그려진다',
          (tester) async {
        await _pump(tester, size: size, textScale: scale);
        expect(tester.takeException(), isNull);
        expect(find.text('지원 전 준비사항'), findsOneWidget);
      });
    }
  }
}
