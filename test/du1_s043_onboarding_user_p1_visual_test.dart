// [DU1 후속81] S043 OnboardingScreen(role:'USER') 둘째 페이지(index1) 정상 전체 시각.
//   host: MaterialApp(home: OnboardingScreen(...)) 직접(AuthWrapper 통과 아님) · Theme RoleTheme.getThemeByRole('USER') · prefs {} mock.
//   도달: page0 안정 뒤 공개 '다음' receiver 를 실제 tapAt 1회 → 400ms 페이지 이동 + 600ms scale + 300ms AnimatedSwitcher 안정.
//   private state/초기 index seam 없음. 완료·건너뛰기·마지막 CTA 는 누르지 않는다(onComplete 0 단언).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/screens/common/onboarding_screen.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';

Future<({GlobalKey key, int Function() completes, List<String> overflows})> _toPage1(
    WidgetTester t, Size size, double scale, {bool insets = true}) async {
  await t.runAsync(vqLoadFonts);
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  if (insets) {
    t.view.padding = const FakeViewPadding(top: 30, bottom: 24);
    t.view.viewPadding = const FakeViewPadding(top: 30, bottom: 24);
  }
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
          MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: OnboardingScreen(role: 'USER', onComplete: () => completes++),
    ),
  ));
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  final next = find.ancestor(of: find.text('다음'), matching: find.byType(GestureDetector)).first;
  await t.tapAt(t.getRect(next).center);
  // 400ms 이동 + 600ms scale + 300ms switcher
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  return (key: key, completes: () => completes, overflows: overflows);
}

bool _hits(WidgetTester t, Finder f, Offset p) {
  final hit = HitTestResult();
  WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
  return hit.path.any((e) => e.target == t.renderObject(f));
}

void main() {
  testWidgets('S043-P1-N 지원자 온보딩 둘째 페이지 392×851@1.0 — 공개 다음 1회 · 전체·receiver·scroll', (t) async {
    const size = Size(392, 851);
    final o = await _toPage1(t, size, 1.0);
    expect(t.takeException(), isNull);
    final screen = find.byType(OnboardingScreen);
    final mq = MediaQuery.of(t.element(screen));
    final page = t.widget<PageView>(find.byType(PageView)).controller!;
    final scrolls = find.descendant(of: screen, matching: find.byType(Scrollable));
    final scrollInfo = [
      for (var i = 0; i < scrolls.evaluate().length; i++)
        () {
          final s = t.state<ScrollableState>(scrolls.at(i));
          return '[${s.position.axis.name}] ${t.getRect(scrolls.at(i))} max=${s.position.maxScrollExtent.toStringAsFixed(1)} off=${s.position.pixels.toStringAsFixed(1)}';
        }()
    ].join(' · ');
    final title = find.text('지원한 일자리의\n진행 상황을 한눈에');
    final skip = find.widgetWithText(TextButton, '건너뛰기');
    final next = find.ancestor(of: find.text('다음'), matching: find.byType(GestureDetector)).first;
    final rSkip = t.getRect(skip);
    final rNext = t.getRect(next);
    final report = 'mq padding=${mq.padding} viewPadding=${mq.viewPadding} · page=${page.page?.toStringAsFixed(3)} offset=${page.offset.toStringAsFixed(1)} · '
        'scrollables: $scrollInfo · 제목 ${title.evaluate().isEmpty ? '없음' : t.getRect(title)} · '
        '건너뛰기 $rSkip ${rSkip.width}×${rSkip.height} hit=${_hits(t, skip, rSkip.center)} · '
        '다음 $rNext ${rNext.width.toStringAsFixed(1)}×${rNext.height.toStringAsFixed(1)} hit=${_hits(t, next, rNext.center)} bottomIn=${rNext.bottom <= 851 - 24} · '
        'onComplete=${o.completes()} · overflows=${o.overflows.length}';
    // ignore: avoid_print
    print('S043-P1-N $report');
    expect((page.page! - 1).abs() < 0.001, isTrue, reason: 'page1');
    expect(title, findsOneWidget, reason: '둘째 제목');
    expect(o.completes(), 0, reason: '완료 callback 0');
    expect(rSkip.width >= 48 - 0.01 && rSkip.height >= 48 - 0.01 && _hits(t, skip, rSkip.center), isTrue);
    expect(rNext.height >= 52 && _hits(t, next, rNext.center) && rNext.bottom <= 851 - 24, isTrue);
    expect(o.overflows, isEmpty, reason: o.overflows.join(' | '));
    await vqCapture(t, o.key, 'S043-P1-N_onboarding_user_p1_392x1', conditions: {
      'screen': "MaterialApp(home: OnboardingScreen(role:'USER')) 직접 — AuthWrapper 통과 아님",
      'theme': "RoleTheme.getThemeByRole('USER')", 'viewport': '392x851', 'dpr': 1.0, 'textScaler': 1.0,
      'inset': 'padding/viewPadding top30 bottom24 · viewInsets 0', 'prefs': '{}(mock)',
      'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) — 기기 글꼴 아님',
      'state': 'page0 안정 → 공개 다음 tapAt 1회 → page1 · onComplete 0', 'clock': '화면 소스 DateTime 사용 없음',
      'measure': report});
  });
}
