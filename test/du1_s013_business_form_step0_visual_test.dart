// ignore_for_file: depend_on_referenced_packages
// [DU1 후속88] S013 BusinessFormScreen 신규 등록 초기 step0 '업종 선택' 정상 N 전체 시각.
//   host: LOCAL dummy route → 보통 MaterialPageRoute push(관리자 홈의 신규 등록 진입과 같은 route 종류 — 실제 홈/auth/readiness 아님).
//   Theme: RoleTheme.getThemeByRole('BUSINESS_ADMIN'). Firebase Core fake(storageBucket 포함 — StorageService 필드), BUSINESS_ADMIN UserProvider,
//     NotificationProvider(setUser 미호출 — 구독 시작 안 함). 원격 auth/Firestore/Storage 연결 없음(전체 외부 호출 0 계측은 아님).
//   초기: BusinessFormScreen(business:null, isFromSignUp:false) · step0 · 업종 미선택 · 그룹 접힘. 선택/확장·다음·홈·알림·뒤로는 누르지 않는다(hitTest 만).
//   조건: 392×851 · DPR1 · padding/viewPadding 상30/하24 · viewInsets 0 · prefs {} · vqLoadFonts 근사.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_form_screen.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p', storageBucket: 'p.appspot.com');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _AdminProvider extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'admin1', username: 'admin1', name: 'QA 사장', email: 'admin1@alfit.local',
        role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const []);
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('S013-N 사업장 신규 등록 step0 업종 선택 392×851@1.0 — 전체·receiver·scroll', (t) async {
    await t.runAsync(vqLoadFonts);
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(392, 851);
    t.view.devicePixelRatio = 1.0;
    t.view.padding = const FakeViewPadding(top: 30, bottom: 24);
    t.view.viewPadding = const FakeViewPadding(top: 30, bottom: 24);
    addTearDown(t.view.reset);
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
    final key = GlobalKey();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _AdminProvider()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.getThemeByRole('BUSINESS_ADMIN'),
          builder: (ctx, child) =>
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
          home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => const BusinessFormScreen(business: null, isFromSignUp: false))),
              child: const Text('host'))))),
        ),
      ),
    ));
    await t.tap(find.text('host'));
    for (var i = 0; i < 14; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.takeException(), isNull);
    final screen = find.byType(BusinessFormScreen);
    expect(screen, findsOneWidget);
    final mq = MediaQuery.of(t.element(screen));
    bool hits(Finder f, Offset p) {
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
      return hit.path.any((e) => e.target == t.renderObject(f));
    }
    String rr(String n, Finder f) {
      if (f.evaluate().isEmpty) return '$n 없음';
      final r = t.getRect(f.first);
      return '$n $r ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} hit=${hits(f.first, r.center)}';
    }
    final scrolls = find.descendant(of: screen, matching: find.byType(Scrollable));
    final scrollInfo = [
      for (var i = 0; i < scrolls.evaluate().length; i++)
        () {
          final s = t.state<ScrollableState>(scrolls.at(i));
          return '[${s.position.axis.name}] ${t.getRect(scrolls.at(i))} max=${s.position.maxScrollExtent.toStringAsFixed(1)} off=${s.position.pixels.toStringAsFixed(1)}';
        }()
    ].join(' · ');
    // r2: 첫 조상이 IconButton 안쪽 InkWell(잉크 40×40)이었다 — Material IconButton 의 터치 영역(tap target 48)은 IconButton 자체 rect 다.
    //   홈·알림과 같은 기준(IconButton)으로 재고, 48 상자 가장자리(2px 안쪽) hit 도 본다.
    final back = find.ancestor(of: find.byIcon(Icons.arrow_back), matching: find.byType(IconButton));
    final backInk = find.ancestor(of: find.byIcon(Icons.arrow_back), matching: find.byType(InkWell));
    final home = find.ancestor(of: find.byIcon(Icons.home_outlined), matching: find.byType(IconButton));
    final noti = find.ancestor(of: find.byIcon(Icons.notifications_outlined), matching: find.byType(IconButton));
    final tiles = find.byType(ExpansionTile);
    final tileHeaders = [
      for (var i = 0; i < tiles.evaluate().length; i++)
        find.descendant(of: tiles.at(i), matching: find.byType(ListTile)).first
    ];
    // r1: CommonWidgets.primaryButton 은 ButtonStyleButton 이 아니라 Container > InkWell 이다 — InkWell 을 receiver 로 본다
    final next = find.ancestor(of: findVisibleText('다음'), matching: find.byType(InkWell)).first;
    final nextW = t.widget<InkWell>(next);
    // [DU322] 단계 라벨이 낱말 묶음 표시라 보이는 글자로 센다(DU255)
    final steps = ['업종 선택', '기본 정보', '상세 정보'].map((s) => '$s=${findVisibleText(s).evaluate().length}').join(',');
    final cats = ['회사', '매장', '기타'].map((s) => '$s=${find.text(s).evaluate().length}').join(',');
    final report = 'mq padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} · scrollables: $scrollInfo · '
        '제목 사업장 등록=${findVisibleText('사업장 등록').evaluate().length} 수정=${findVisibleText('사업장 수정').evaluate().length} · 단계 $steps · 안내=${findVisibleText('사업장의 업종을 선택해주세요').evaluate().length} · 업종 $cats · '
        'ExpansionTile=${tiles.evaluate().length} · ${rr('뒤로 IconButton', back)} · ${rr('뒤로 잉크(InkWell)', backInk)} · 뒤로 가장자리 hit=${() { final r = t.getRect(back.first); return [Offset(r.left + 2, r.center.dy), Offset(r.right - 2, r.center.dy), Offset(r.center.dx, r.top + 2), Offset(r.center.dx, r.bottom - 2)].map((p) => hits(back.first, p)).toList(); }()} · ${rr('홈', home)} · ${rr('알림', noti)} · '
        '${[for (var i = 0; i < tileHeaders.length; i++) rr('업종행$i', tileHeaders[i])].join(' · ')} · '
        '${rr('다음', next)} onTap=${nextW.onTap == null ? 'null' : '활성'} bottomIn=${t.getRect(next).bottom <= 851 - 24} · overflows=${overflows.length}';
    // ignore: avoid_print
    print('S013-N $report');
    expect(findVisibleText('사업장 등록'), findsOneWidget, reason: '신규(수정 모드 아님)');
    expect(find.text('사업장의 업종을 선택해주세요'), findsOneWidget, reason: 'step0');
    expect(tiles, findsNWidgets(3));
    for (final h in tileHeaders) {
      final r = t.getRect(h);
      expect(r.height >= 48 && r.width >= 48 && hits(h, r.center), isTrue, reason: '업종행 receiver');
    }
    for (final f in [back, home, noti]) {
      final r = t.getRect(f.first);
      expect(r.width >= 48 - 0.01 && r.height >= 48 - 0.01 && hits(f.first, r.center), isTrue, reason: '헤더 행동');
    }
    expect(nextW.onTap, isNotNull, reason: '초기 다음은 활성 callback(source)');
    final rNext = t.getRect(next);
    expect(rNext.height >= 52 - 0.01 && hits(next, rNext.center), isTrue, reason: '다음 주 행동');
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    await vqCapture(t, key, 'S013-N_business_form_step0_392x1', conditions: {
      'screen': 'BusinessFormScreen(business:null, isFromSignUp:false) — LOCAL dummy route → MaterialPageRoute push(관리자 홈·auth 아님)',
      'theme': "RoleTheme.getThemeByRole('BUSINESS_ADMIN')", 'viewport': '392x851', 'dpr': 1.0, 'textScaler': 1.0,
      'inset': '선언 padding/viewPadding top30 bottom24 · viewInsets 0', 'prefs': '{}',
      'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) — 기기 글꼴 아님',
      'state': 'step0 · 업종 미선택 · 그룹 접힘 · 누름 없음', 'measure': report});
  });
}
