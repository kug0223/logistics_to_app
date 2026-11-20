// [DU1 후속77 §2] S003 PassAuthRecoveryScreen 초기 정상 안내 기본 시각.
//   host: LOCAL MaterialApp 의 dummy 이전 route 에서 MaterialPageRoute(fullscreenDialog: true) 로 const PassAuthRecoveryScreen() push
//     (홈 배너 '인증하기' 와 같은 route 조건 — 실제 홈/배너 탭·인증 실행이 아니다).
//   Theme: RoleTheme.workerTheme(로그인 USER 의 production 밝은 Theme). 글꼴: vqLoadFonts(근사).
//   조건: 392×851 · DPR1 · padding/viewPadding 상30/하24 · viewInsets 0 · 초기 상태(_authResult=null·로딩 false).
//   의존성: 화면 build/initState 는 Provider·Firebase 를 읽지 않는다(소스: initState 없음, Provider·PassVerificationService 는 탭 핸들러 안) —
//     그래서 Provider/Core fake 를 두지 않는다. 행동(PASS·나중에 하기)은 누르지 않고 hitTest 만 한다. 전체 채널 deny 계측은 없다.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/auth/pass_auth_recovery_screen.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';

void main() {
  testWidgets('S003-N 본인인증 복구 초기 안내 392×851@1.0 — 전체·행동 실측', (t) async {
    await t.runAsync(vqLoadFonts);
    t.view.physicalSize = const Size(392, 851);
    t.view.devicePixelRatio = 1.0;
    t.view.padding = const FakeViewPadding(top: 30, bottom: 24);
    t.view.viewPadding = const FakeViewPadding(top: 30, bottom: 24);
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.workerTheme,
        builder: (ctx, child) =>
            MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
        home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                fullscreenDialog: true, builder: (_) => const PassAuthRecoveryScreen())),
            child: const Text('host'))))),
      ),
    ));
    await t.tap(find.text('host'));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(PassAuthRecoveryScreen), findsOneWidget);
    expect(t.takeException(), isNull);
    final screen = find.byType(PassAuthRecoveryScreen);
    final scroll = find.descendant(of: screen, matching: find.byType(Scrollable)).first;
    final pos = t.state<ScrollableState>(scroll).position;
    final vp = t.getRect(scroll);
    final mq = MediaQuery.of(t.element(screen));
    bool hits(Finder f, Offset p) {
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
      return hit.path.any((e) => e.target == t.renderObject(f));
    }
    final close = find.byIcon(Icons.close);
    final passText = find.textContaining('휴대폰 본인인증').last;
    final pass = find.ancestor(of: passText, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton || w is InkWell)).first;
    final later = find.widgetWithText(TextButton, '나중에 하기');
    final rPass = t.getRect(pass);
    final rLater = t.getRect(later);
    final rClose = close.evaluate().isEmpty ? null : t.getRect(find.ancestor(of: close, matching: find.byType(IconButton)).first);
    final report = 'mq padding=${mq.padding} viewPadding=${mq.viewPadding} · 본문 viewport=$vp maxScroll=${pos.maxScrollExtent.toStringAsFixed(1)} · '
        '닫기(leading close)=${rClose ?? '없음'} · PASS receiver=${pass.evaluate().first.widget.runtimeType} $rPass '
        '${rPass.width.toStringAsFixed(1)}×${rPass.height.toStringAsFixed(1)} centerHit=${hits(pass, rPass.center)} · '
        '나중에 하기 TextButton $rLater ${rLater.width.toStringAsFixed(1)}×${rLater.height.toStringAsFixed(1)} centerHit=${hits(later, rLater.center)}';
    // ignore: avoid_print
    print('S003-N $report');
    expect(rPass.height, greaterThanOrEqualTo(52), reason: '주 행동 높이 52(공통 기준)');
    expect(rLater.height, greaterThanOrEqualTo(48), reason: '보조 행동 터치 높이');
    expect(rLater.width, greaterThanOrEqualTo(48), reason: '보조 행동 터치 폭');
    expect(hits(pass, rPass.center) && hits(later, rLater.center), isTrue);
    expect(rPass.bottom <= vp.bottom && rLater.bottom <= vp.bottom, isTrue, reason: '두 행동이 첫 화면 본문 안');
    await vqCapture(t, key, 'S003-N_pass_recovery_392x1', conditions: {
      'screen': 'PassAuthRecoveryScreen — LOCAL dummy route → MaterialPageRoute(fullscreenDialog:true) push(홈 배너 탭 아님)',
      'theme': 'RoleTheme.workerTheme', 'viewport': '392x851', 'dpr': 1.0, 'textScaler': 1.0,
      'inset': 'padding/viewPadding top30 bottom24 · viewInsets 0',
      'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) — 기기 글꼴 아님',
      'state': '초기 _authResult=null · _isPassLoading=false · _isFinalizing=false', 'clock': '화면 소스에 DateTime 사용 없음(grep 0)',
      'measure': report});
  });

  // [후속77 §3-3] 바뀐 주 행동(최소 52)·보조 행동의 320×640@2.0 실제 도달·hit
  testWidgets('S003-B 본인인증 복구 320×640@2.0 — 두 행동 실제 도달·hit·크기', (t) async {
    await t.runAsync(vqLoadFonts);
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.workerTheme,
        builder: (ctx, child) =>
            MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(2.0)), child: child!),
        home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                fullscreenDialog: true, builder: (_) => const PassAuthRecoveryScreen())),
            child: const Text('host'))))),
      ),
    ));
    await t.tap(find.text('host'));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.takeException(), isNull);
    final screen = find.byType(PassAuthRecoveryScreen);
    final scroll = find.descendant(of: screen, matching: find.byType(Scrollable)).first;
    final pos = t.state<ScrollableState>(scroll).position;
    bool hits(Finder f, Offset p) {
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
      return hit.path.any((e) => e.target == t.renderObject(f));
    }
    final later = find.widgetWithText(TextButton, '나중에 하기');
    final pass = find.ancestor(of: find.textContaining('휴대폰 본인인증').last, matching: find.byType(InkWell)).first;
    final before = pos.pixels;
    final rPass0 = t.getRect(pass);
    await t.scrollUntilVisible(later, 80, scrollable: scroll);
    await t.pump(const Duration(milliseconds: 100));
    final vp = t.getRect(scroll);
    final rLater = t.getRect(later);
    final inside = rLater.top >= vp.top && rLater.bottom <= vp.bottom;
    final out = 'viewport=$vp maxScroll=${pos.maxScrollExtent.toStringAsFixed(1)} offset ${before.toStringAsFixed(1)}→${pos.pixels.toStringAsFixed(1)} · '
        'PASS(스크롤 전) $rPass0 ${rPass0.width.toStringAsFixed(1)}×${rPass0.height.toStringAsFixed(1)} · '
        '나중에 하기 $rLater ${rLater.width.toStringAsFixed(1)}×${rLater.height.toStringAsFixed(1)} inside=$inside centerHit=${hits(later, rLater.center)}';
    // ignore: avoid_print
    print('S003-B $out');
    expect(rPass0.height, greaterThanOrEqualTo(52));
    expect(inside, isTrue);
    expect(hits(later, rLater.center), isTrue);
    expect(rLater.height, greaterThanOrEqualTo(48));
    await vqCapture(t, key, 'S003-B_pass_recovery_320x2_later', conditions: {
      'screen': 'PassAuthRecoveryScreen fullscreenDialog push', 'theme': 'RoleTheme.workerTheme', 'viewport': '320x640',
      'dpr': 1.0, 'textScaler': 2.0, 'inset': 0, 'fonts': 'vqLoadFonts 근사', 'scroll': 'scrollUntilVisible(나중에 하기, 80)',
      'measure': out});
  });
}
