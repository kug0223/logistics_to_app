// ignore_for_file: depend_on_referenced_packages
// [DU1 후속79] S004 RegisterScreen 초기 step0 '이용 방법 선택' · 역할 미선택 전체 시각.
//   host: LOCAL dummy route → 보통 MaterialPageRoute push(Login 가입 진입과 같은 route 종류 — 실제 Login 버튼·root 아님).
//   Theme: RoleTheme.getThemeByRole(null)(비로그인). UserProvider(loading=false) · Core fake + Firebase.initializeApp.
//   약관: termsLoaderForTest 에 필수 1·선택 1 의 고정 LOCAL EffectiveLegalTerms(serverNow 2026-11-01) — 서버 callable 미호출.
//   초기 상태: initialUserTermsStepForTest=false → _currentStep=0 · _selectedRole=null. 역할 선택·다음·PASS·SMS·가입 writer 를 실행하지 않는다.
//   전체 외부 채널 deny/호출0 계측은 없다(Core fake + 고정 loader 만).
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/register_screen.dart';
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

LegalTermsItem _item(String id, String title, bool required_) => LegalTermsItem(
      id: id, title: title, content: '$title 본문입니다.\n' * 3, isRequired: required_,
      version: 'b', revisionId: '${id}__b', order: 1);

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('S004-N 회원가입 step0 392×851@1.0 — 역할 미선택 전체·receiver 실측', (t) async {
    await t.runAsync(vqLoadFonts);
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(392, 851);
    t.view.devicePixelRatio = 1.0;
    t.view.padding = const FakeViewPadding(top: 30, bottom: 24);
    t.view.viewPadding = const FakeViewPadding(top: 30, bottom: 24);
    addTearDown(t.view.reset);
    var loaderCalls = 0;
    Future<EffectiveLegalTerms> loader() async {
      loaderCalls++;
      return EffectiveLegalTerms(serverNow: DateTime.utc(2026, 11, 1), upcoming: const [], items: [
        _item('service_terms', '서비스 이용약관', true),
        _item('marketing', '마케팅 정보 수신', false),
      ]);
    }
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
          home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => RegisterScreen(termsLoaderForTest: loader, initialUserTermsStepForTest: false))),
              child: const Text('host'))))),
        ),
      ),
    ));
    await t.tap(find.text('host'));
    // 약관 loader 완료 + 400ms focus 예약 이후 안정 프레임
    for (var i = 0; i < 16; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.takeException(), isNull);
    expect(loaderCalls, 1, reason: '고정 loader 1회');
    final screen = find.byType(RegisterScreen);
    expect(find.text('어떻게 이용하시나요?'), findsOneWidget, reason: 'step0');
    final mq = MediaQuery.of(t.element(screen));
    final scroll = find.descendant(of: screen, matching: find.byType(Scrollable));
    final scrollInfo = scroll.evaluate().isEmpty
        ? 'Scrollable 없음'
        : () {
            final p = t.state<ScrollableState>(scroll.first).position;
            return 'viewport=${t.getRect(scroll.first)} maxScroll=${p.maxScrollExtent.toStringAsFixed(1)} offset=${p.pixels.toStringAsFixed(1)}';
          }();
    bool hits(Finder f, Offset p) {
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
      return hit.path.any((e) => e.target == t.renderObject(f));
    }
    String rr(String name, Finder f) {
      final r = t.getRect(f);
      return '$name $r ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} centerHit=${hits(f, r.center)}';
    }
    final back = find.ancestor(of: find.byIcon(Icons.arrow_back), matching: find.byType(GestureDetector)).first;
    final userCard = find.ancestor(of: find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == '지원자로 이용'), matching: find.byType(InkWell)).first;
    final bizCard = find.ancestor(of: find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == '사업장 관리자로 이용'), matching: find.byType(InkWell)).first;
    final next = find.widgetWithText(ElevatedButton, '다음');
    final nextW = t.widget<ElevatedButton>(next);
    final rBack = t.getRect(back);
    final rUser = t.getRect(userCard);
    final rBiz = t.getRect(bizCard);
    final rNext = t.getRect(next);
    final report = 'mq padding=${mq.padding} viewPadding=${mq.viewPadding} · $scrollInfo · ${rr('뒤로 GestureDetector', back)} · '
        '${rr('지원자 카드 InkWell', userCard)} · ${rr('사업장 관리자 카드 InkWell', bizCard)} · '
        '다음 ElevatedButton $rNext ${rNext.width.toStringAsFixed(1)}×${rNext.height.toStringAsFixed(1)} onPressed=${nextW.onPressed == null ? 'null(비활성)' : '활성'} '
        'bottomInScreen=${rNext.bottom <= 851 - 24}';
    // ignore: avoid_print
    print('S004-N $report');
    expect(rUser.height >= 48 && rUser.width >= 48 && hits(userCard, rUser.center), isTrue, reason: '지원자 카드 receiver');
    expect(rBiz.height >= 48 && rBiz.width >= 48 && hits(bizCard, rBiz.center), isTrue, reason: '사업장 관리자 카드 receiver');
    expect(nextW.onPressed, isNull, reason: '역할 미선택 → 다음 비활성');
    expect(rNext.bottom <= 851 - 24, isTrue, reason: '다음이 하단 SafeArea 위');
    // ignore: avoid_print
    print('S004-N 뒤로 48 기준 ${rBack.width >= 48 && rBack.height >= 48 ? '충족' : '미달'}');
    // [구현79 after] current r1 실측(뒤로 34.2·다음 48) 뒤 교정 — 이제 단언
    expect(rBack.width >= 48 && rBack.height >= 48 && hits(back, rBack.center), isTrue, reason: '뒤로 receiver ≥48·hit');
    expect(rNext.height, greaterThanOrEqualTo(52), reason: '주 버튼 52');
    // 지원자 카드 설명 줄 수(낱말 단위) — 표시 문자열은 keepWords, 원문은 semanticsLabel
    final desc = find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == '원하는 날짜의 일자리에 지원하고 일정을 관리해요.');
    // ignore: avoid_print
    print('S004-N 지원자 설명 Text=${desc.evaluate().length} rect=${desc.evaluate().isEmpty ? '-' : t.getRect(desc.first)}');
    await vqCapture(t, key, 'S004-N_register_step0_392x1', conditions: {
      'screen': 'RegisterScreen step0 — LOCAL dummy route → MaterialPageRoute push(Login 버튼·root 아님)',
      'theme': 'RoleTheme.getThemeByRole(null)', 'viewport': '392x851', 'dpr': 1.0, 'textScaler': 1.0,
      'inset': 'padding/viewPadding top30 bottom24 · viewInsets 0', 'prefs': '{}',
      'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) — 기기 글꼴 아님',
      'terms': 'termsLoaderForTest 고정 LOCAL(필수 service_terms·선택 marketing, serverNow 2026-11-01) · 호출 $loaderCalls',
      'state': 'initialUserTermsStepForTest=false · step0 · 역할 미선택 · 제출 false',
      'clock': '초기 경로에서 시계 미사용(주민번호/나이 함수의 DateTime.now 는 미실행) · 미주입', 'measure': report});
  });

  // [후속79 §4.3] 바뀐 뒤로·다음·카드 설명 — 320×640@2.0 읽기·도달·receiver
  testWidgets('S004-B 회원가입 step0 320×640@2.0 — 뒤로·카드·다음 도달·크기', (t) async {
    await t.runAsync(vqLoadFonts);
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    Future<EffectiveLegalTerms> loader() async => EffectiveLegalTerms(
        serverNow: DateTime.utc(2026, 11, 1), upcoming: const [], items: [_item('service_terms', '서비스 이용약관', true)]);
    final key = GlobalKey();
    final overflows = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = d.exceptionAsString();
      if (s.contains('overflowed')) {
        overflows.add(s.split('\n').first);
      } else {
        prev?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prev);
    await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
      create: (_) => UserProvider(),
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.getThemeByRole(null),
          builder: (ctx, child) =>
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(2.0)), child: child!),
          home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => RegisterScreen(termsLoaderForTest: loader, initialUserTermsStepForTest: false))),
              child: const Text('host'))))),
        ),
      ),
    ));
    await t.tap(find.text('host'));
    for (var i = 0; i < 16; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    bool hits(Finder f, Offset p) {
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
      return hit.path.any((e) => e.target == t.renderObject(f));
    }
    final screen = find.byType(RegisterScreen);
    final scroll = find.descendant(of: screen, matching: find.byType(Scrollable)).first;
    final pos = t.state<ScrollableState>(scroll).position;
    final back = find.ancestor(of: find.byIcon(Icons.arrow_back), matching: find.byType(GestureDetector)).first;
    final rBack = t.getRect(back);
    final next = find.widgetWithText(ElevatedButton, '다음');
    final rNext = t.getRect(next);
    final bizCard = find.ancestor(of: find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == '사업장 관리자로 이용'), matching: find.byType(InkWell)).first;
    final before = pos.pixels;
    await t.scrollUntilVisible(bizCard, 80, scrollable: scroll);
    await t.pump(const Duration(milliseconds: 100));
    final vp = t.getRect(scroll);
    final rBiz = t.getRect(bizCard);
    final inside = rBiz.top >= vp.top && rBiz.bottom <= vp.bottom;
    final out = 'viewport=$vp maxScroll=${pos.maxScrollExtent.toStringAsFixed(1)} offset ${before.toStringAsFixed(1)}→${pos.pixels.toStringAsFixed(1)} · '
        '뒤로 $rBack ${rBack.width.toStringAsFixed(1)}×${rBack.height.toStringAsFixed(1)} hit=${hits(back, rBack.center)} · '
        '사업장 관리자 카드(스크롤 뒤) $rBiz inside=$inside hit=${hits(bizCard, rBiz.center)} · 다음 $rNext ${rNext.height.toStringAsFixed(1)} bottomIn=${rNext.bottom <= 640} · overflows=${overflows.length}';
    // ignore: avoid_print
    print('S004-B $out');
    expect(rBack.width >= 48 && rBack.height >= 48 && hits(back, rBack.center), isTrue);
    expect(inside && hits(bizCard, rBiz.center), isTrue, reason: '마지막 선택지 도달');
    expect(rNext.height >= 52 && rNext.bottom <= 640, isTrue, reason: '다음 52·화면 안');
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await vqCapture(t, key, 'S004-B_register_step0_320x2', conditions: {
      'screen': 'RegisterScreen step0 MaterialPageRoute push', 'theme': 'RoleTheme.getThemeByRole(null)', 'viewport': '320x640',
      'dpr': 1.0, 'textScaler': 2.0, 'inset': 0, 'fonts': 'vqLoadFonts 근사', 'scroll': 'scrollUntilVisible(사업장 관리자 카드, 80)',
      'measure': out});
  });
}
