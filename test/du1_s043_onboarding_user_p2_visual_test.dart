// [DU1 후속82] S043 OnboardingScreen(role:'USER') 마지막 페이지(index2) 정상 전체 시각.
//   host: MaterialApp(home: OnboardingScreen(...)) 직접(AuthWrapper 통과 아님) · Theme RoleTheme.getThemeByRole('USER') · prefs {} mock.
//   도달: page0 안정 → 공개 '다음' tapAt 1회 → page1 안정·확인 → 공개 '다음' tapAt 1회(총 2회) → page2 안정
//     (각 400ms 이동 + 600ms scale + 300ms switcher). private state/초기 index seam 없음.
//   건너뛰기·마지막 'ALfit 시작하기' 는 누르지 않는다(완료 경로) — hitTest 만, onComplete 0 단언.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/screens/common/onboarding_screen.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

Future<({GlobalKey key, int Function() completes, List<String> overflows, String p1})> _toPage2(
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
      // ignore: avoid_print
      print('OVERFLOW-DETAIL ${d.toString().split('\n').where((l) => l.contains('file:///') || l.contains('overflowed') || l.contains('Row') || l.contains('creator')).take(8).join(' / ')}');
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
  final next = find.ancestor(of: findVisibleText('다음'), matching: find.byType(GestureDetector)).first;
  await t.tapAt(t.getRect(next).center);
  // 400ms 이동 + 600ms scale + 300ms switcher
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  final c1 = t.widget<PageView>(find.byType(PageView)).controller!;
  final p1 = 'page1 확인: page=${c1.page?.toStringAsFixed(3)} '
      '제목=${find.text('지원한 일자리의\n진행 상황을 한눈에').evaluate().length} onComplete=$completes';
  expect((c1.page! - 1).abs() < 0.001 && completes == 0, isTrue, reason: 'page1 경유');
  // [후속83 §2.3] 구현82 에서는 page1 제목 1개가 로그 관측뿐이었다 — 단언으로 올린다
  expect(find.text('지원한 일자리의\n진행 상황을 한눈에'), findsOneWidget, reason: 'page1 제목');
  final next2 = find.ancestor(of: findVisibleText('다음'), matching: find.byType(GestureDetector)).first;
  await t.tapAt(t.getRect(next2).center);
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  return (key: key, completes: () => completes, overflows: overflows, p1: p1);
}

bool _hits(WidgetTester t, Finder f, Offset p) {
  final hit = HitTestResult();
  WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
  return hit.path.any((e) => e.target == t.renderObject(f));
}

void main() {
  testWidgets('S043-P2-N 지원자 온보딩 마지막 페이지 392×851@1.0 — 공개 다음 2회 · 전체·receiver·scroll', (t) async {
    const size = Size(392, 851);
    final o = await _toPage2(t, size, 1.0);
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
    final title = find.text('출근부터 급여 확인까지\nALfit에서 관리하세요');
    final skip = find.widgetWithText(TextButton, '건너뛰기');
    final next = find.ancestor(of: findVisibleText('ALfit 시작하기'), matching: find.byType(GestureDetector)).first;
    final rSkip = t.getRect(skip);
    final rNext = t.getRect(next);
    // [후속83 §2.3] 실제 mq.viewInsets 도 기록(구현82 누락)
    final example = find.text('출퇴근 체크 예시');
    final oldCta = findVisibleText('출근하기');
    final report = 'mq padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} · '
        '예시행 \'출퇴근 체크 예시\'=${example.evaluate().length} ${example.evaluate().isEmpty ? '' : t.getRect(example)} · 구 \'출근하기\'=${oldCta.evaluate().length} · page=${page.page?.toStringAsFixed(3)} offset=${page.offset.toStringAsFixed(1)} · '
        'scrollables: $scrollInfo · 제목 ${title.evaluate().isEmpty ? '없음' : t.getRect(title)} · '
        '건너뛰기 $rSkip ${rSkip.width}×${rSkip.height} hit=${_hits(t, skip, rSkip.center)} · '
        '${o.p1} · ALfit 시작하기 $rNext ${rNext.width.toStringAsFixed(1)}×${rNext.height.toStringAsFixed(1)} hit=${_hits(t, next, rNext.center)} bottomIn=${rNext.bottom <= 851 - 24} · '
        'onComplete=${o.completes()} · overflows=${o.overflows.length}';
    // ignore: avoid_print
    print('S043-P2-N $report');
    expect((page.page! - 2).abs() < 0.001, isTrue, reason: 'page2');
    expect(title, findsOneWidget, reason: '셋째 제목');
    expect(o.completes(), 0, reason: '완료 callback 0');
    expect(rSkip.width >= 48 - 0.01 && rSkip.height >= 48 - 0.01 && _hits(t, skip, rSkip.center), isTrue);
    expect(rNext.height >= 52 && _hits(t, next, rNext.center) && rNext.bottom <= 851 - 24, isTrue);
    expect(o.overflows, isEmpty, reason: o.overflows.join(' | '));
    await vqCapture(t, o.key, 'S043-P2-N_onboarding_user_p2_392x1', conditions: {
      'screen': "MaterialApp(home: OnboardingScreen(role:'USER')) 직접 — AuthWrapper 통과 아님",
      'theme': "RoleTheme.getThemeByRole('USER')", 'viewport': '392x851', 'dpr': 1.0, 'textScaler': 1.0,
      'inset': 'padding/viewPadding top30 bottom24 · viewInsets 0', 'prefs': '{}(mock)',
      'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) — 기기 글꼴 아님',
      'state': 'page0 → 공개 다음 tapAt → page1 확인 → 공개 다음 tapAt → page2 · 건너뛰기·ALfit 시작하기 미누름 · onComplete 0',
      'clock': '화면 소스 DateTime 사용 없음 — 예시 날짜·금액은 고정 문자열',
      'measure': report});
  });

  // [구현83] 예시 문구가 '출근하기'→'출퇴근 체크 예시' 로 길어졌다 — 고정 높이 32 행이 320×640@2.0 에서 넘치지 않는지(넘침 0·문구 존재·rect)
  testWidgets('S043-P2-B 지원자 온보딩 마지막 페이지 320×640@2.0 — 예시행 넘침 0 · 최종 CTA', (t) async {
    final o = await _toPage2(t, const Size(320, 640), 2.0, insets: false);
    expect(t.takeException(), isNull);
    final page = t.widget<PageView>(find.byType(PageView)).controller!;
    final example = find.text('출퇴근 체크 예시');
    final next = find.ancestor(of: findVisibleText('ALfit 시작하기'), matching: find.byType(GestureDetector)).first;
    final rNext = t.getRect(next);
    final out = 'page=${page.page?.toStringAsFixed(3)} · 예시행=${example.evaluate().length} ${example.evaluate().isEmpty ? '' : t.getRect(example)} '
        'didExceed=${example.evaluate().isEmpty ? '-' : t.renderObject<RenderParagraph>(example).didExceedMaxLines} · '
        'ALfit 시작하기 $rNext ${rNext.height.toStringAsFixed(1)} hit=${_hits(t, next, rNext.center)} bottomIn=${rNext.bottom <= 640} · '
        '${o.p1} · onComplete=${o.completes()} · overflows=${o.overflows.length} ${o.overflows.join(' | ')}';
    // ignore: avoid_print
    print('S043-P2-B $out');
    expect((page.page! - 2).abs() < 0.001, isTrue);
    expect(example, findsOneWidget);
    expect(o.overflows, isEmpty, reason: o.overflows.join(' | '));
    expect(rNext.height >= 52 && rNext.bottom <= 640 && _hits(t, next, rNext.center), isTrue);
    expect(o.completes(), 0);
    await vqCapture(t, o.key, 'S043-P2-B_onboarding_user_p2_320x2', conditions: {
      'screen': "MaterialApp(home: OnboardingScreen(role:'USER'))", 'theme': "RoleTheme.getThemeByRole('USER')",
      'viewport': '320x640', 'dpr': 1.0, 'textScaler': 2.0, 'inset': 0, 'fonts': 'vqLoadFonts 근사',
      'state': '공개 다음 2회 → page2', 'measure': out});
  });

  // [DU1 후속84] C0-S043-P2-B-REACH — 같은 B 에서 본문 세로 scroll 을 **실제 drag** 로 내려 제목 하단·설명·세 기능행 읽기와 말단 도달,
  //   일러스트 세로(max>0 이면 그 owner 만) 확인, 끝에서 고정 CTA 재측정. production 무변경.
  testWidgets('S043-P2-B-REACH 320×640@2.0 — 본문 실제 drag 읽기·말단·일러스트·CTA', (t) async {
    final o = await _toPage2(t, const Size(320, 640), 2.0, insets: false);
    expect(t.takeException(), isNull);
    final screen = find.byType(OnboardingScreen);
    final mq = MediaQuery.of(t.element(screen));
    final page = t.widget<PageView>(find.byType(PageView)).controller!;
    // 활성 페이지(page2) 안의 세로 Scrollable 만 — PageView 는 화면 밖 페이지도 들고 있을 수 있어 화면 안 rect 로 고른다
    final all = find.descendant(of: screen, matching: find.byType(Scrollable));
    final verticals = [
      for (var i = 0; i < all.evaluate().length; i++) all.at(i)
    ].where((f) {
      final s = t.state<ScrollableState>(f);
      final r = t.getRect(f);
      return s.position.axis == Axis.vertical && r.left >= -0.5 && r.right <= 320.5;
    }).toList();
    final horizontal = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
        .firstWhere((f) => t.state<ScrollableState>(f).position.axis == Axis.horizontal);
    String sc(Finder f) {
      final p = t.state<ScrollableState>(f).position;
      return '${t.getRect(f)} max=${p.maxScrollExtent.toStringAsFixed(1)} off=${p.pixels.toStringAsFixed(1)}';
    }
    final illus = verticals.first;
    final body = verticals.last;
    final out = <String>[
      'mq padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets}',
      '가로 PageView ${sc(horizontal)} · 일러스트 세로 ${sc(illus)} · 본문 세로 ${sc(body)}',
    ];
    final vp = t.getRect(body);
    final items = <String, Finder>{
      '제목': find.text('출근부터 급여 확인까지\nALfit에서 관리하세요'),
      '설명': find.text('확정된 근무 일정을 확인하고\n출퇴근 기록과 급여 내역을 관리할 수 있어요.'),
      '기능1': find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == '확정된 근무 일정 확인'),
      '기능2': find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == '간편한 출퇴근 체크'),
      '기능3': find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == '급여 · 임금명세서 확인'),
    };
    final seen = <String, String>{};
    String frame(String when) {
      final parts = <String>[];
      for (final e in items.entries) {
        if (e.value.evaluate().isEmpty) {
          parts.add('${e.key}=없음');
          continue;
        }
        final r = t.getRect(e.value.first);
        final vis = r.intersect(vp);
        final visible = vis.width > 0 && vis.height > 0;
        final full = r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5;
        if (visible) seen.putIfAbsent(e.key, () => when);
        parts.add('${e.key} $r 보임=${visible ? (full ? '전체' : '일부 ${vis.height.toStringAsFixed(0)}/${r.height.toStringAsFixed(0)}') : '아님'}');
      }
      return '$when off=${t.state<ScrollableState>(body).position.pixels.toStringAsFixed(1)} · ${parts.join(' · ')}';
    }
    out.add(frame('초기'));
    // 실제 drag — 본문 viewport 왼쪽 여백 근처에서 위로 끈다(프로그램 jump 아님)
    final bodyPos = t.state<ScrollableState>(body).position;
    var shot = 0;
    for (var k = 0; k < 30 && bodyPos.pixels < bodyPos.maxScrollExtent - 0.5; k++) {
      await t.dragFrom(Offset(vp.left + 4, vp.center.dy), const Offset(0, -70));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      out.add(frame('drag${k + 1}'));
      if (k == 1 && shot == 0) {
        shot++;
        await vqCapture(t, o.key, 'S043-P2-B-REACH_mid_320x2', conditions: {
          'screen': "MaterialApp(home: OnboardingScreen(role:'USER')) · page2", 'viewport': '320x640', 'textScaler': 2.0,
          'scroll': '본문 세로 실제 dragFrom(left+4, center) -70 × 2', 'measure': out.last});
      }
    }
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final endFrame = frame('말단');
    out.add(endFrame);
    final atEnd = (bodyPos.pixels - bodyPos.maxScrollExtent).abs() < 0.5;
    // 일러스트 세로 — max>0 일 때만 그 owner 를 실제 drag
    final illusPos = t.state<ScrollableState>(illus).position;
    if (illusPos.maxScrollExtent > 0.5) {
      final ivp = t.getRect(illus);
      for (var k = 0; k < 20 && illusPos.pixels < illusPos.maxScrollExtent - 0.5; k++) {
        await t.dragFrom(Offset(ivp.left + 4, ivp.center.dy), const Offset(0, -60));
        await t.pump(const Duration(milliseconds: 100));
      }
      final ex = find.text('임금명세서');
      out.add('일러스트 drag 뒤 ${sc(illus)} · 임금명세서 ${ex.evaluate().isEmpty ? '없음' : t.getRect(ex.first)}');
    } else {
      out.add('일러스트 세로 max 0 — drag 없음');
    }
    final next = find.ancestor(of: findVisibleText('ALfit 시작하기'), matching: find.byType(GestureDetector)).first;
    final rNext = t.getRect(next);
    out.add('끝 CTA $rNext ${rNext.width.toStringAsFixed(1)}×${rNext.height.toStringAsFixed(1)} hit=${_hits(t, next, rNext.center)} inScreen=${rNext.left >= 0 && rNext.right <= 320 && rNext.bottom <= 640} · '
        'page=${page.page?.toStringAsFixed(3)} onComplete=${o.completes()} overflows=${o.overflows.length} · 처음 보인 시점=$seen · 말단 도달=$atEnd');
    // ignore: avoid_print
    for (final l in out) { print('S043-P2-B-REACH $l'); }
    expect(atEnd, isTrue, reason: '본문 말단까지 실제 drag 로 도달');
    for (final k in items.keys) {
      expect(seen.containsKey(k), isTrue, reason: '$k 가 scroll 중 보였다');
    }
    final f3 = t.getRect(items['기능3']!.first);
    expect(f3.top >= vp.top - 0.5 && f3.bottom <= vp.bottom + 0.5, isTrue, reason: '마지막 기능행 전체가 말단에서 보인다');
    expect((page.page! - 2).abs() < 0.001, isTrue, reason: '세로 drag 가 페이지를 바꾸지 않았다');
    expect(o.completes(), 0);
    expect(o.overflows, isEmpty, reason: o.overflows.join(' | '));
    expect(rNext.height >= 52 && rNext.width >= 48 && _hits(t, next, rNext.center) && rNext.right <= 320 && rNext.bottom <= 640, isTrue);
    expect(t.takeException(), isNull);
    await vqCapture(t, o.key, 'S043-P2-B-REACH_end_320x2', conditions: {
      'screen': "MaterialApp(home: OnboardingScreen(role:'USER')) · page2", 'theme': "RoleTheme.getThemeByRole('USER')",
      'viewport': '320x640', 'dpr': 1.0, 'textScaler': 2.0, 'inset': 0, 'fonts': 'vqLoadFonts 근사',
      'scroll': '본문 세로 실제 dragFrom -70 반복 → 말단', 'measure': out.join(' | ')});
  });
}
