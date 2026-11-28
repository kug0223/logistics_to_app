// [DU1 후속80] S043 OnboardingScreen(role:'USER') 첫 페이지(index0) 정상 전체 시각.
//   host: MaterialApp(home: OnboardingScreen(...)) 직접 — AuthWrapper 가 같은 root 자리에 반환하는 구조와 같다(실제 AuthWrapper/auth 분기 통과 아님).
//   Theme: RoleTheme.getThemeByRole('USER'). Provider/Core fake/약관 loader 불필요(화면이 읽지 않는다 — 소스).
//   초기: _currentPage=0 · PageController offset 0 · onComplete 호출 0(다음/건너뛰기를 누르지 않는다 — prefs/투어 writer 미실행).
//   조건: 392×851 · DPR1 · padding/viewPadding 상30/하24 · viewInsets 0 · prefs {}(mock) · vqLoadFonts 근사.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/screens/common/onboarding_screen.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

void main() {
  testWidgets('S043-N 지원자 온보딩 첫 페이지 392×851@1.0 — 전체·receiver·scroll 실측', (t) async {
    await t.runAsync(vqLoadFonts);
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(392, 851);
    t.view.devicePixelRatio = 1.0;
    t.view.padding = const FakeViewPadding(top: 30, bottom: 24);
    t.view.viewPadding = const FakeViewPadding(top: 30, bottom: 24);
    addTearDown(t.view.reset);
    var completes = 0;
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.getThemeByRole('USER'),
        builder: (ctx, child) =>
            MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
        home: OnboardingScreen(role: 'USER', onComplete: () => completes++),
      ),
    ));
    // 600ms scale animation 이후 안정 프레임
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.takeException(), isNull);
    final screen = find.byType(OnboardingScreen);
    final mq = MediaQuery.of(t.element(screen));
    final page = t.widget<PageView>(find.byType(PageView));
    final pageOffset = page.controller!.hasClients ? page.controller!.offset : -1;
    final scrolls = find.descendant(of: screen, matching: find.byType(Scrollable));
    final scrollInfo = [
      for (var i = 0; i < scrolls.evaluate().length; i++)
        () {
          final s = t.state<ScrollableState>(scrolls.at(i));
          return '[${s.position.axis.name}] ${t.getRect(scrolls.at(i))} max=${s.position.maxScrollExtent.toStringAsFixed(1)} off=${s.position.pixels.toStringAsFixed(1)}';
        }()
    ].join(' · ');
    bool hits(Finder f, Offset p) {
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
      return hit.path.any((e) => e.target == t.renderObject(f));
    }
    final skip = find.widgetWithText(TextButton, '건너뛰기');
    final next = find.ancestor(of: findVisibleText('다음'), matching: find.byType(GestureDetector)).first;
    final rSkip = t.getRect(skip);
    final rNext = t.getRect(next);
    String tr(String s) => find.text(s).evaluate().isEmpty ? '-' : t.getRect(find.text(s).first).toString();
    final report = 'mq padding=${mq.padding} viewPadding=${mq.viewPadding} · PageView offset=${pageOffset.toStringAsFixed(1)} · scrollables: $scrollInfo · '
        '건너뛰기 TextButton $rSkip ${rSkip.width.toStringAsFixed(1)}×${rSkip.height.toStringAsFixed(1)} hit=${hits(skip, rSkip.center)} · '
        '다음 GestureDetector $rNext ${rNext.width.toStringAsFixed(1)}×${rNext.height.toStringAsFixed(1)} hit=${hits(next, rNext.center)} bottomIn=${rNext.bottom <= 851 - 24} · '
        '제목 ${tr('일하고 싶은 날을\n직접 선택하세요')} · 설명 ${tr('원하는 날짜를 선택하면\n그날 지원할 수 있는 일자리를 확인할 수 있어요.')} · onComplete=$completes';
    // ignore: avoid_print
    print('S043-N $report');
    expect(completes, 0, reason: '누르지 않았다 — 완료 callback 0');
    expect(pageOffset, 0, reason: '첫 페이지');
    expect(hits(skip, rSkip.center) && hits(next, rNext.center), isTrue);
    // [구현80 after] current r1 실측(다음 49) 뒤 교정 — 단언
    // r1: 출력 48.0 인데 단언 실패 — Material TextButton 기본 탭 영역 48 이 부동소수 47.99… 로 계산된다(측정 반올림, production 무관). 허용 0.01.
    // ignore: avoid_print
    print('S043-N 건너뛰기 정밀 ${rSkip.width}×${rSkip.height}');
    expect(rSkip.width >= 48 - 0.01 && rSkip.height >= 48 - 0.01, isTrue, reason: '건너뛰기 receiver');
    expect(rNext.height, greaterThanOrEqualTo(52), reason: '주 행동 52');
    expect(rNext.bottom <= 851 - 24, isTrue, reason: '하단 SafeArea 위');
    await vqCapture(t, key, 'S043-N_onboarding_user_p0_392x1', conditions: {
      'screen': "MaterialApp(home: OnboardingScreen(role:'USER')) 직접 — AuthWrapper 통과 아님",
      'theme': "RoleTheme.getThemeByRole('USER')", 'viewport': '392x851', 'dpr': 1.0, 'textScaler': 1.0,
      'inset': 'padding/viewPadding top30 bottom24 · viewInsets 0', 'prefs': '{}(mock)',
      'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) — 기기 글꼴 아님',
      'state': 'page0 · 누름 없음 · onComplete 0', 'clock': '화면 소스에 DateTime 사용 없음(grep 0) — 예시 날짜는 고정 문자열',
      'measure': report});
  });

  // [후속80 §3.3] 바뀐 다음 버튼·설명 — 320×640@2.0 읽기·본문 세로 scroll 마지막 정보·행동 도달
  testWidgets('S043-B 지원자 온보딩 첫 페이지 320×640@2.0 — 마지막 기능행·다음 도달', (t) async {
    await t.runAsync(vqLoadFonts);
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    var completes = 0;
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
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.getThemeByRole('USER'),
        builder: (ctx, child) =>
            MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(2.0)), child: child!),
        home: OnboardingScreen(role: 'USER', onComplete: () => completes++),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    bool hits(Finder f, Offset p) {
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
      return hit.path.any((e) => e.target == t.renderObject(f));
    }
    final screen = find.byType(OnboardingScreen);
    final next = find.ancestor(of: findVisibleText('다음'), matching: find.byType(GestureDetector)).first;
    final skip = find.widgetWithText(TextButton, '건너뛰기');
    final rNext = t.getRect(next);
    final rSkip = t.getRect(skip);
    // 본문(제목·설명·기능행) 세로 scroll — 가로 PageView·일러스트 세로 scroll 과 구별(마지막 vertical Scrollable)
    final verticals = [
      for (var i = 0; i < find.descendant(of: screen, matching: find.byType(Scrollable)).evaluate().length; i++)
        find.descendant(of: screen, matching: find.byType(Scrollable)).at(i)
    ].where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical).toList();
    final body = verticals.last;
    final bodyPos = t.state<ScrollableState>(body).position;
    final lastFeature = find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == '원하는 일자리에 지원');
    final before = bodyPos.pixels;
    await t.scrollUntilVisible(lastFeature, 60, scrollable: body);
    await t.pump(const Duration(milliseconds: 100));
    final vp = t.getRect(body);
    final rLast = t.getRect(lastFeature);
    final page = t.widget<PageView>(find.byType(PageView));
    final out = '본문 viewport=$vp max=${bodyPos.maxScrollExtent.toStringAsFixed(1)} offset ${before.toStringAsFixed(1)}→${bodyPos.pixels.toStringAsFixed(1)} · '
        '마지막 기능행 $rLast inside=${rLast.top >= vp.top && rLast.bottom <= vp.bottom} · PageView offset=${page.controller!.offset.toStringAsFixed(1)} · '
        '다음 $rNext ${rNext.width.toStringAsFixed(1)}×${rNext.height.toStringAsFixed(1)} hit=${hits(next, rNext.center)} bottomIn=${rNext.bottom <= 640} · '
        '건너뛰기 $rSkip hit=${hits(skip, rSkip.center)} · overflows=${overflows.length} · onComplete=$completes';
    // ignore: avoid_print
    print('S043-B $out');
    expect(rLast.top >= vp.top && rLast.bottom <= vp.bottom, isTrue, reason: '마지막 기능행 도달');
    expect(page.controller!.offset, 0, reason: '세로 scroll 이 페이지를 바꾸지 않았다');
    expect(rNext.height >= 52 && rNext.bottom <= 640 && hits(next, rNext.center), isTrue);
    expect(hits(skip, rSkip.center), isTrue);
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(completes, 0);
    expect(t.takeException(), isNull);
    await vqCapture(t, key, 'S043-B_onboarding_user_p0_320x2', conditions: {
      'screen': "MaterialApp(home: OnboardingScreen(role:'USER'))", 'theme': "RoleTheme.getThemeByRole('USER')",
      'viewport': '320x640', 'dpr': 1.0, 'textScaler': 2.0, 'inset': 0, 'fonts': 'vqLoadFonts 근사',
      'scroll': '본문 세로 scrollUntilVisible(원하는 일자리에 지원, 60)', 'measure': out});
  });
}
