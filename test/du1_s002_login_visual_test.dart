// ignore_for_file: depend_on_referenced_packages
// [DU1 후속75 §3] S002 LoginScreen 정상 기본 시각 — 현재 production 비로그인 Theme.
//   실제 root 는 ThemeProvider.theme 이고 AuthWrapper 비로그인은 reset() → RoleTheme.getThemeByRole(null) = 통합 밝은 Theme.
//   기존 LG(login_layout_text_scale_test)의 ThemeData(fontFamily:) 와 다르다 — 이 셀은 getThemeByRole(null) 을 직접 쓴다.
//   host: LOCAL MaterialApp(home: LoginScreen()) 직접 — 실제 root/AuthWrapper/인증 성공이 아니다.
//   조건: 392×851 · DPR1 · padding/viewPadding 상30/하24 · viewInsets 0 · prefs {} · 입력 비어 있음 · isLoading=false(초기).
//   글꼴: vqLoadFonts(NotoSansKR Regular+Bold, Roboto=NotoSansKR, MaterialIcons) — 기기 글꼴 근사.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/login_screen.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('S002-N 로그인 392×851@1.0 정상 기본 — production 비로그인 Theme', (t) async {
    await t.runAsync(vqLoadFonts);
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(392, 851);
    t.view.devicePixelRatio = 1.0;
    t.view.padding = const FakeViewPadding(top: 30, bottom: 24);
    t.view.viewPadding = const FakeViewPadding(top: 30, bottom: 24);
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
      create: (_) => UserProvider(),
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.getThemeByRole(null),
          builder: (ctx, child) =>
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
          home: const LoginScreen(),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.takeException(), isNull);
    final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    final btn = find.widgetWithText(ElevatedButton, '로그인');
    final rects = {
      for (final l in const ['나에게 딱 맞는 알바 매칭', '아이디 저장', '아이디 찾기', '비밀번호 찾기', '회원가입'])
        l: find.text(l).evaluate().isEmpty ? null : t.getRect(find.text(l).last),
      '로그인 버튼': btn.evaluate().isEmpty ? null : t.getRect(btn),
    };
    // ignore: avoid_print
    print('S002-N maxScroll=${pos.maxScrollExtent.toStringAsFixed(1)} rects=$rects');
    await vqCapture(t, key, 'S002-N_login_392x1', conditions: {
      'screen': 'LoginScreen (LOCAL MaterialApp 직접 host — root/AuthWrapper/인증 아님)',
      'theme': 'RoleTheme.getThemeByRole(null) — AuthWrapper 비로그인 reset() 경로와 같은 통합 밝은 Theme',
      'viewport': '392x851', 'dpr': 1.0, 'textScaler': 1.0, 'inset': 'padding/viewPadding top30 bottom24 · viewInsets 0',
      'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) — 기기 글꼴 아님',
      'prefs': '{}', 'state': '입력 비어 있음 · 초기 isLoading=false', 'clock': '미주입(화면이 시계를 쓰지 않음 — 소스 확인 필요 시 보고)',
      'maxScroll': pos.maxScrollExtent.toStringAsFixed(1), 'rects': rects.toString()});
  });
}
