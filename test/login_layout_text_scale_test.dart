// [UI-INTEGRATION.33] 로그인 화면 — 큰 글자에서 '아이디 저장 · 아이디 찾기 · 비밀번호 찾기' 줄과
//   '계정이 없으신가요? 회원가입' 줄이 넘치지 않는다.
//   기기(392dp·글자 2.0): 각각 RIGHT OVERFLOWED BY 132 / 4.2 PIXELS 였다.
//   측정 자: 번들 NotoSansKR. 배치: 360·1.0(회귀) / 320·1.3 / 392·2.0.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/login_screen.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options =>
      const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

const _font = 'NotoSansKR';

Future<void> _loadFont() async {
  final loader = FontLoader(_font);
  for (final f in const ['Regular', 'Bold']) {
    loader.addFont(rootBundle
        .load('assets/fonts/NotoSansKR-$f.ttf')
        .then((b) => ByteData.sublistView(b.buffer.asUint8List())));
  }
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await _loadFont();
  });

  for (final (size, scale) in const [(Size(360, 900), 1.0), (Size(320, 900), 1.3), (Size(392, 900), 2.0)]) {
    testWidgets('LG-1 ${size.width.toInt()}·$scale 로그인 카드 — 넘침 없음, 세 행동이 모두 보인다', (t) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => UserProvider(),
        child: MaterialApp(
          theme: ThemeData(fontFamily: _font),
          builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: const LoginScreen(),
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull, reason: '로그인 카드 넘침');
      final card = t.getRect(find.ancestor(of: find.text('아이디 저장'), matching: find.byType(Wrap)).first);
      for (final label in const ['아이디 저장', '아이디 찾기', '비밀번호 찾기', '계정이 없으신가요?', '회원가입']) {
        final r = t.getRect(find.text(label));
        expect(r.right, lessThanOrEqualTo(size.width + 0.01), reason: '$label 가 화면 밖');
        if (label != '계정이 없으신가요?' && label != '회원가입') {
          expect(r.right, lessThanOrEqualTo(card.right + 0.01), reason: '$label 가 줄 밖');
        }
      }
    });
  }

  // [LOGIN-ONE-SCREEN.34] 좁은 화면·큰 글자에서도 스크롤 없이 한 화면에 — 상태 막대·내비게이션 막대 높이 포함.
  //   기기 실측 크기: 392x851(1080x2340·440dpi), 320x693(540dpi), 작은 폰 360x640.
  //   LG-2 각 조건에서 스크롤 범위 0 + 로그인 버튼·회원가입이 화면 안
  //   LG-3 넉넉한 화면·기본 글자는 예전 배치 그대로(소개 문구 보임 = 압축 배치 아님)
  Future<void> pumpDevice(WidgetTester t, Size size, double scale) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    t.view.padding = const FakeViewPadding(top: 30, bottom: 24);
    t.view.viewPadding = const FakeViewPadding(top: 30, bottom: 24);
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
      create: (_) => UserProvider(),
      child: MaterialApp(
        theme: ThemeData(fontFamily: _font),
        builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: const LoginScreen(),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  for (final (size, scale) in const [
    (Size(392, 851), 1.0), (Size(392, 851), 1.3), (Size(392, 851), 2.0),
    (Size(320, 693), 1.3), (Size(320, 693), 1.0), (Size(360, 640), 1.0), (Size(360, 640), 1.3),
  ]) {
    testWidgets('LG-2 ${size.width.toInt()}x${size.height.toInt()}·$scale 로그인 한 화면 — 스크롤 없음', (t) async {
      await pumpDevice(t, size, scale);
      expect(t.takeException(), isNull);
      final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(pos.maxScrollExtent, 0, reason: '스크롤해야 보이는 부분 ${pos.maxScrollExtent.toStringAsFixed(1)}dp');
      for (final label in const ['로그인', '회원가입']) {
        final r = t.getRect(find.text(label).last);
        expect(r.bottom, lessThanOrEqualTo(size.height - 24 + 0.01), reason: '$label 가 화면 아래로 잘림');
      }
    });
  }

  testWidgets('LG-3 392x851·1.0 넉넉하면 예전 배치 그대로(소개 문구 보임)', (t) async {
    await pumpDevice(t, const Size(392, 851), 1.0);
    expect(find.text('나에게 딱 맞는 알바 매칭'), findsOneWidget);
  });

  // [.34-A1] 키보드가 열린 상태 — 세로 가운데 배치 때문에 스크롤이 막히지 않는다.
  //   LG-4 키보드(300dp)가 열려도 로그인 버튼까지 스크롤로 닿고, 눌러 생긴 빈 칸 오류 안내가 넘치지 않으며
  //   오류 안내까지 다시 스크롤로 닿는다.
  for (final (size, scale) in const [(Size(392, 851), 2.0), (Size(320, 693), 1.3), (Size(360, 640), 1.0)]) {
    testWidgets('LG-4 ${size.width.toInt()}x${size.height.toInt()}·$scale 키보드 열림 — 버튼·오류 안내에 닿는다', (t) async {
      await pumpDevice(t, size, scale);
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final btn = find.widgetWithText(ElevatedButton, '로그인');
      await t.scrollUntilVisible(btn, 60, scrollable: find.byType(Scrollable).first);
      await t.tap(btn);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '오류 안내가 생겨도 넘치지 않는다');
      for (final msg in const ['아이디를 입력해주세요', '비밀번호를 입력해주세요']) {
        final f = find.text(msg);
        expect(f, findsOneWidget);
        await t.scrollUntilVisible(f, -60, scrollable: find.byType(Scrollable).first);
        final r = t.getRect(f);
        expect(r.right, lessThanOrEqualTo(size.width + 0.01), reason: '$msg 가 화면 밖');
        expect(r.bottom, lessThanOrEqualTo(size.height - 300 + 0.01), reason: '$msg 가 키보드 뒤');
      }
    });
  }
}
