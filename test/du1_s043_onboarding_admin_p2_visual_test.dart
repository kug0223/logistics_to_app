// [DU1 후속87] S043 OnboardingScreen(role:'BUSINESS_ADMIN') 마지막 페이지(index2) 정상 N 전체 시각.
//   host: MaterialApp(home: OnboardingScreen(...)) 직접(AuthWrapper 통과 아님) · Theme RoleTheme.getThemeByRole('BUSINESS_ADMIN') · prefs {} mock.
//   도달: page0/callback0 확인 → 공개 '다음' tapAt → page1/callback0 확인 → 공개 '다음' tapAt(총 2회) → page2 안정.
//   private seam·가로 jump 없음. 건너뛰기·'ALfit 시작하기' 는 누르지 않는다(완료 경로 — onComplete 0 단언, hitTest 만).
//   조건: 392×851 · DPR1 · padding/viewPadding 상30/하24 · viewInsets 0 · vqLoadFonts 근사.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/screens/common/onboarding_screen.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

void main() {
  testWidgets('S043-A2-N 관리자 온보딩 마지막 페이지 392×851@1.0 — 공개 다음 2회 · 전체·receiver·scroll', (t) async {
    await t.runAsync(vqLoadFonts);
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(392, 851);
    t.view.devicePixelRatio = 1.0;
    t.view.padding = const FakeViewPadding(top: 30, bottom: 24);
    t.view.viewPadding = const FakeViewPadding(top: 30, bottom: 24);
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
        theme: RoleTheme.getThemeByRole('BUSINESS_ADMIN'),
        builder: (ctx, child) =>
            MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
        home: OnboardingScreen(role: 'BUSINESS_ADMIN', onComplete: () => completes++),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    PageController ctl() => t.widget<PageView>(find.byType(PageView)).controller!;
    expect((ctl().page! - 0).abs() < 0.001 && completes == 0, isTrue, reason: 'page0 출발');
    Future<void> tapNext() async {
      final n = find.ancestor(of: findVisibleText('다음'), matching: find.byType(GestureDetector)).first;
      await t.tapAt(t.getRect(n).center);
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }
    await tapNext();
    expect((ctl().page! - 1).abs() < 0.001 && completes == 0, isTrue, reason: 'page1 경유');
    expect(find.text('지원은 관심,\n확정은 약속입니다'), findsOneWidget, reason: 'page1 제목');
    await tapNext();
    expect(t.takeException(), isNull);
    final screen = find.byType(OnboardingScreen);
    final mq = MediaQuery.of(t.element(screen));
    final page = ctl();
    final all = find.descendant(of: screen, matching: find.byType(Scrollable));
    final scrollInfo = [
      for (var i = 0; i < all.evaluate().length; i++)
        () {
          final s = t.state<ScrollableState>(all.at(i));
          return '[${s.position.axis.name}] ${t.getRect(all.at(i))} max=${s.position.maxScrollExtent.toStringAsFixed(1)} off=${s.position.pixels.toStringAsFixed(1)}';
        }()
    ].join(' · ');
    bool hits(Finder f, Offset p) {
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
      return hit.path.any((e) => e.target == t.renderObject(f));
    }
    final title = find.text('첫 공고 전에\n기본 준비가 필요해요');
    final desc = find.text('확정하면 바로 계약서가 만들어지기 때문에\n사업장·업무·계약서 양식·사업주 인감이 먼저 있어야 합니다.\n무엇이 남았는지는 홈에서 알려드려요.');
    final skip = find.widgetWithText(TextButton, '건너뛰기');
    final ctaText = findVisibleText('ALfit 시작하기');
    final cta = find.ancestor(of: ctaText, matching: find.byType(GestureDetector)).first;
    final rSkip = t.getRect(skip);
    final rCta = t.getRect(cta);
    String tr(Finder f) {
      if (f.evaluate().isEmpty) return '없음';
      final rich = find.descendant(of: f.first, matching: find.byType(RichText));
      final para = rich.evaluate().isEmpty ? t.renderObject<RenderParagraph>(f.first) : t.renderObject<RenderParagraph>(rich.first);
      final len = para.text.toPlainText().length;
      final lines = para.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len)).map((b) => b.top.round()).toSet().length;
      return '${t.getRect(f.first)} lines=$lines didExceed=${para.didExceedMaxLines}';
    }
    final ctaW = t.widget<Text>(ctaText.first);
    final report = 'mq padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} · '
        'page=${page.page?.toStringAsFixed(3)} offset=${page.offset.toStringAsFixed(1)} · scrollables: $scrollInfo · '
        '제목 ${tr(title)} · 설명 ${tr(desc)} · CTA 글 ${tr(ctaText)} semantics=${ctaW.semanticsLabel} · '
        '건너뛰기 TextButton $rSkip ${rSkip.width}×${rSkip.height} hit=${hits(skip, rSkip.center)} · '
        'ALfit 시작하기 GestureDetector $rCta ${rCta.width.toStringAsFixed(1)}×${rCta.height.toStringAsFixed(1)} hit=${hits(cta, rCta.center)} '
        'bottomIn=${rCta.bottom <= 851 - 24} · onComplete=$completes · overflows=${overflows.length}';
    // ignore: avoid_print
    print('S043-A2-N $report');
    expect((page.page! - 2).abs() < 0.001, isTrue, reason: 'page2');
    expect(title, findsOneWidget, reason: '마지막 제목');
    expect(desc, findsOneWidget, reason: '설명');
    expect(completes, 0);
    expect(rSkip.width >= 48 - 0.01 && rSkip.height >= 48 - 0.01 && hits(skip, rSkip.center), isTrue);
    expect(rCta.height >= 52 && rCta.width >= 48 && hits(cta, rCta.center) && rCta.bottom <= 851 - 24 && rCta.right <= 392, isTrue);
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    await vqCapture(t, key, 'S043-A2-N_onboarding_admin_p2_392x1', conditions: {
      'screen': "MaterialApp(home: OnboardingScreen(role:'BUSINESS_ADMIN')) 직접 — AuthWrapper 통과 아님",
      'theme': "RoleTheme.getThemeByRole('BUSINESS_ADMIN')", 'viewport': '392x851', 'dpr': 1.0, 'textScaler': 1.0,
      'inset': '선언 padding/viewPadding top30 bottom24 · viewInsets 0', 'prefs': '{}(mock)',
      'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) — 기기 글꼴 아님',
      'state': 'page0 → 다음 tapAt → page1 확인 → 다음 tapAt → page2 · 건너뛰기·ALfit 시작하기 미누름 · onComplete 0',
      'clock': '화면 소스 DateTime 사용 없음', 'measure': report});
  });
}
