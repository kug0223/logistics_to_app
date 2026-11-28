// [DU1 후속86] S043 OnboardingScreen(role:'BUSINESS_ADMIN') 둘째 페이지(index1) 정상 N 전체 시각.
//   host: MaterialApp(home: OnboardingScreen(...)) 직접(AuthWrapper 통과 아님) · Theme RoleTheme.getThemeByRole('BUSINESS_ADMIN') · prefs {} mock.
//   도달: page0/callback0 확인 → 공개 '다음' GestureDetector 중심 tapAt 1회 → page1 안정(400ms 이동 + 600ms scale + 300ms switcher).
//   private seam 없음. 건너뛰기·완료는 누르지 않는다(onComplete 0 단언).
//   조건: 392×851 · DPR1 · padding/viewPadding 상30/하24 · viewInsets 0 · vqLoadFonts 근사.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/screens/common/onboarding_screen.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

void main() {
  testWidgets('S043-A1-N 관리자 온보딩 둘째 페이지 392×851@1.0 — 공개 다음 1회 · 전체·receiver·scroll', (t) async {
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
    final c0 = t.widget<PageView>(find.byType(PageView)).controller!;
    expect((c0.page! - 0).abs() < 0.001 && completes == 0, isTrue, reason: 'page0 출발');
    final next0 = find.ancestor(of: findVisibleText('다음'), matching: find.byType(GestureDetector)).first;
    await t.tapAt(t.getRect(next0).center);
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.takeException(), isNull);
    final screen = find.byType(OnboardingScreen);
    final mq = MediaQuery.of(t.element(screen));
    final page = t.widget<PageView>(find.byType(PageView)).controller!;
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
    final title = find.text('지원은 관심,\n확정은 약속입니다');
    final desc = find.text('지원은 그 날 일하고 싶다는 관심 표현이에요.\n확정하는 순간 약속이 되고 계약서가 만들어집니다.');
    final f1 = find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == '지원 — 아직 약속이 아니에요');
    final f2 = find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == '확정 — 계약·일정·급여로 이어져요');
    final skip = find.widgetWithText(TextButton, '건너뛰기');
    final next = find.ancestor(of: findVisibleText('다음'), matching: find.byType(GestureDetector)).first;
    final rSkip = t.getRect(skip);
    final rNext = t.getRect(next);
    // r1: semanticsLabel 이 붙은 Text 는 렌더 루트가 RenderSemanticsAnnotations 라 RenderParagraph 캐스트가 실패했다 — 안쪽 RichText 에서 꺼낸다
    String tr(Finder f) {
      if (f.evaluate().isEmpty) return '없음';
      final para = t.renderObject<RenderParagraph>(find.descendant(of: f.first, matching: find.byType(RichText)).first);
      return '${t.getRect(f.first)} didExceed=${para.didExceedMaxLines}';
    }
    final report = 'mq padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} · '
        'page=${page.page?.toStringAsFixed(3)} offset=${page.offset.toStringAsFixed(1)} · scrollables: $scrollInfo · '
        '제목 ${tr(title)} · 설명 ${tr(desc)} · 기능1 ${tr(f1)} · 기능2 ${tr(f2)} · '
        '건너뛰기 TextButton $rSkip ${rSkip.width}×${rSkip.height} hit=${hits(skip, rSkip.center)} · '
        '다음 GestureDetector $rNext ${rNext.width.toStringAsFixed(1)}×${rNext.height.toStringAsFixed(1)} hit=${hits(next, rNext.center)} '
        'bottomIn=${rNext.bottom <= 851 - 24} · onComplete=$completes · overflows=${overflows.length}';
    // ignore: avoid_print
    print('S043-A1-N $report');
    expect((page.page! - 1).abs() < 0.001, isTrue, reason: 'page1');
    expect(title, findsOneWidget, reason: '둘째 제목');
    expect(desc, findsOneWidget);
    expect(f1, findsOneWidget);
    expect(f2, findsOneWidget);
    expect(completes, 0);
    expect(rSkip.width >= 48 - 0.01 && rSkip.height >= 48 - 0.01 && hits(skip, rSkip.center), isTrue);
    expect(rNext.height >= 52 && rNext.width >= 48 && hits(next, rNext.center) && rNext.bottom <= 851 - 24, isTrue);
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    await vqCapture(t, key, 'S043-A1-N_onboarding_admin_p1_392x1', conditions: {
      'screen': "MaterialApp(home: OnboardingScreen(role:'BUSINESS_ADMIN')) 직접 — AuthWrapper 통과 아님",
      'theme': "RoleTheme.getThemeByRole('BUSINESS_ADMIN')", 'viewport': '392x851', 'dpr': 1.0, 'textScaler': 1.0,
      'inset': '선언 padding/viewPadding top30 bottom24 · viewInsets 0', 'prefs': '{}(mock)',
      'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) — 기기 글꼴 아님',
      'state': 'page0 확인 → 공개 다음 tapAt 1회 → page1 · onComplete 0', 'clock': '화면 소스 DateTime 사용 없음',
      'measure': report});
  });
}
