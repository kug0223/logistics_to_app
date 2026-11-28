// [DU1 후속85] S043 OnboardingScreen(role:'BUSINESS_ADMIN') 첫 페이지(index0) 초기 정상 전체 시각.
//   host: MaterialApp(home: OnboardingScreen(...)) 직접(AuthWrapper 통과 아님) · Theme RoleTheme.getThemeByRole('BUSINESS_ADMIN') · prefs {} mock.
//   초기: _currentPage=0 · PageController.page≈0/offset 0 · onComplete 0 — 다음/건너뛰기를 누르지 않는다(prefs/Tour writer 미실행).
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
  testWidgets('S043-A0-N 관리자 온보딩 첫 페이지 392×851@1.0 — 전체·receiver·scroll 실측', (t) async {
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
    // 600ms scale + switcher/CTA 안정
    for (var i = 0; i < 12; i++) {
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
    final title = find.text('필요한 날,\n필요한 사람을 맞춥니다');
    final desc = find.text('사람이 필요한 날과 일하고 싶은 날을 맞춥니다.\n확정된 근무는 계약·일정·근태·급여까지 이어집니다.');
    final skip = find.widgetWithText(TextButton, '건너뛰기');
    final next = find.ancestor(of: findVisibleText('다음'), matching: find.byType(GestureDetector)).first;
    final rSkip = t.getRect(skip);
    final rNext = t.getRect(next);
    String tr(Finder f) => f.evaluate().isEmpty
        ? '없음'
        : '${t.getRect(f)} didExceed=${t.renderObject<RenderParagraph>(f).didExceedMaxLines}';
    final report = 'mq padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} · '
        'page=${page.page?.toStringAsFixed(3)} offset=${page.offset.toStringAsFixed(1)} · scrollables: $scrollInfo · '
        '제목 ${tr(title)} · 설명 ${tr(desc)} · '
        '건너뛰기 TextButton $rSkip ${rSkip.width}×${rSkip.height} hit=${hits(skip, rSkip.center)} · '
        '다음 GestureDetector $rNext ${rNext.width.toStringAsFixed(1)}×${rNext.height.toStringAsFixed(1)} hit=${hits(next, rNext.center)} '
        'bottomIn=${rNext.bottom <= 851 - 24} · onComplete=$completes · overflows=${overflows.length}';
    // ignore: avoid_print
    print('S043-A0-N $report');
    expect((page.page! - 0).abs() < 0.001 && page.offset == 0, isTrue, reason: 'page0');
    expect(title, findsOneWidget, reason: '관리자 첫 제목');
    expect(desc, findsOneWidget, reason: '설명');
    expect(completes, 0, reason: '누르지 않았다');
    expect(rSkip.width >= 48 - 0.01 && rSkip.height >= 48 - 0.01 && hits(skip, rSkip.center), isTrue, reason: '건너뛰기 receiver');
    expect(rNext.height >= 52 && rNext.width >= 48 && hits(next, rNext.center) && rNext.bottom <= 851 - 24, isTrue,
        reason: '다음 주 행동');
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    await vqCapture(t, key, 'S043-A0-N_onboarding_admin_p0_392x1', conditions: {
      'screen': "MaterialApp(home: OnboardingScreen(role:'BUSINESS_ADMIN')) 직접 — AuthWrapper 통과 아님",
      'theme': "RoleTheme.getThemeByRole('BUSINESS_ADMIN')", 'viewport': '392x851', 'dpr': 1.0, 'textScaler': 1.0,
      'inset': '선언 padding/viewPadding top30 bottom24 · viewInsets 0', 'prefs': '{}(mock)',
      'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) — 기기 글꼴 아님',
      'state': 'page0 초기 · 누름 없음 · onComplete 0', 'clock': '화면 소스 DateTime 사용 없음', 'measure': report});
  });

  // [구현85] 관리자 일러스트 판 높이 200 고정(레이아웃 변경) — 320×640@2.0 에서 그림·본문 실제 drag 도달 · 고정 CTA · page0/callback0
  testWidgets('S043-A0-B 관리자 온보딩 첫 페이지 320×640@2.0 — 그림·본문 실제 drag · CTA', (t) async {
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
        theme: RoleTheme.getThemeByRole('BUSINESS_ADMIN'),
        builder: (ctx, child) =>
            MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(2.0)), child: child!),
        home: OnboardingScreen(role: 'BUSINESS_ADMIN', onComplete: () => completes++),
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
    final mq = MediaQuery.of(t.element(screen));
    final page = t.widget<PageView>(find.byType(PageView)).controller!;
    final all = find.descendant(of: screen, matching: find.byType(Scrollable));
    final verticals = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)].where((f) {
      final r = t.getRect(f);
      return t.state<ScrollableState>(f).position.axis == Axis.vertical && r.left >= -0.5 && r.right <= 320.5;
    }).toList();
    String sc(Finder f) {
      final p = t.state<ScrollableState>(f).position;
      return '${t.getRect(f)} max=${p.maxScrollExtent.toStringAsFixed(1)} off=${p.pixels.toStringAsFixed(1)}';
    }
    final illus = verticals.first;
    final body = verticals.last;
    final out = <String>['mq padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets}',
      '초기 일러스트 ${sc(illus)} · 본문 ${sc(body)}'];
    // 일러스트 세로 — max>0 이면 그 owner 만 실제 drag 해 판 아래 끝 도달
    final ip = t.state<ScrollableState>(illus).position;
    if (ip.maxScrollExtent > 0.5) {
      final ivp = t.getRect(illus);
      for (var k = 0; k < 20 && ip.pixels < ip.maxScrollExtent - 0.5; k++) {
        await t.dragFrom(Offset(ivp.left + 4, ivp.center.dy), const Offset(0, -60));
        await t.pump(const Duration(milliseconds: 100));
      }
    }
    out.add('일러스트 drag 뒤 ${sc(illus)}');
    // 본문 세로 실제 drag → 말단, 제목·설명이 지나가는지
    final bvp = t.getRect(body);
    final title = find.text('필요한 날,\n필요한 사람을 맞춥니다');
    final desc = find.text('사람이 필요한 날과 일하고 싶은 날을 맞춥니다.\n확정된 근무는 계약·일정·근태·급여까지 이어집니다.');
    final seen = <String>{};
    void look(String when) {
      for (final e in {'제목': title, '설명': desc}.entries) {
        final r = t.getRect(e.value);
        final v = r.intersect(bvp);
        if (v.width > 0 && v.height > 0) seen.add(e.key);
        out.add('$when ${e.key} $r 보임=${v.height > 0 && v.width > 0 ? v.height.toStringAsFixed(0) : 0}/${r.height.toStringAsFixed(0)}');
      }
    }
    look('초기');
    final bp = t.state<ScrollableState>(body).position;
    for (var k = 0; k < 30 && bp.pixels < bp.maxScrollExtent - 0.5; k++) {
      await t.dragFrom(Offset(bvp.left + 4, bvp.center.dy), const Offset(0, -70));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      look('drag${k + 1} off=${bp.pixels.toStringAsFixed(1)}');
    }
    final atEnd = (bp.pixels - bp.maxScrollExtent).abs() < 0.5;
    final rd = t.getRect(desc);
    final descEndVisible = rd.bottom <= bvp.bottom + 0.5 && rd.bottom >= bvp.top;
    final next = find.ancestor(of: findVisibleText('다음'), matching: find.byType(GestureDetector)).first;
    final skip = find.widgetWithText(TextButton, '건너뛰기');
    final rNext = t.getRect(next);
    final rSkip = t.getRect(skip);
    out.add('말단=$atEnd 설명 끝 보임=$descEndVisible · 다음 $rNext ${rNext.width.toStringAsFixed(1)}×${rNext.height.toStringAsFixed(1)} hit=${hits(next, rNext.center)} '
        'inScreen=${rNext.right <= 320 && rNext.bottom <= 640} · 건너뛰기 $rSkip hit=${hits(skip, rSkip.center)} · page=${page.page?.toStringAsFixed(3)} '
        'onComplete=$completes overflows=${overflows.length} seen=$seen');
    // ignore: avoid_print
    for (final l in out) { print('S043-A0-B $l'); }
    expect(atEnd, isTrue);
    expect(seen.containsAll(['제목', '설명']), isTrue);
    expect(descEndVisible, isTrue, reason: '설명 끝까지 읽힌다');
    expect((page.page! - 0).abs() < 0.001, isTrue);
    expect(completes, 0);
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(rNext.height >= 52 && rNext.width >= 48 && hits(next, rNext.center) && rNext.right <= 320 && rNext.bottom <= 640, isTrue);
    expect(hits(skip, rSkip.center), isTrue);
    expect(t.takeException(), isNull);
    await vqCapture(t, key, 'S043-A0-B_onboarding_admin_p0_320x2_end', conditions: {
      'screen': "MaterialApp(home: OnboardingScreen(role:'BUSINESS_ADMIN'))", 'theme': "RoleTheme.getThemeByRole('BUSINESS_ADMIN')",
      'viewport': '320x640', 'dpr': 1.0, 'textScaler': 2.0, 'inset': 0, 'fonts': 'vqLoadFonts 근사',
      'scroll': '일러스트(max>0 시)·본문 세로 실제 dragFrom → 말단', 'measure': out.join(' | ')});
  });
}
