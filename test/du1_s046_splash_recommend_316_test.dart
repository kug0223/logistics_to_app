// ignore_for_file: depend_on_referenced_packages
// [DU316] S046 스플래시 — 권장 업데이트 다이얼로그 렌더 관측(11-15 자체검토 셀).
//   진입: 실제 SplashScreen(versionEvaluator 주입: supported + recommendUpdate) → _runGate → 권장 업데이트 다이얼로그.
//   버튼은 누르지 않는다(나중에 → AuthWrapper 는 Firebase 가 필요하고, 업데이트 → Remote Config · url_launcher).
//   단언(전후 공통): 다이얼로그 1개 · 제목 · 본문 · '나중에' · '업데이트' 보임 · 버튼 화면 안 · hit · 넘침 0 · 아직 홈으로 가지 않음.
//   after 단계(DU1_VQ_PHASE 가 after 로 끝남)에서만 피할 수 있는 음절 끊김 0.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/common/splash_screen.dart';
import 'package:ALfit/services/app_version_service.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

const kRecommend = VersionGateResult(
  status: VersionGateStatus.supported,
  source: VersionPolicySource.remote,
  fromCache: false,
  currentVersion: '1.4.0',
  minVersion: '1.0.0',
  recommendUpdate: true,
  updateUrl: 'https://store.example/app',
);

bool get _strict => (vqPhase ?? '').endsWith('after');

({List<String> lines, List<String> avoidable}) _lines(RenderParagraph rp) {
  final plain = rp.text.toPlainText();
  final lines = <StringBuffer>[];
  final avoidable = <String>[];
  final ws = RegExp(r'[\s ]');
  double? lastTop;
  var lastIdx = -1;
  for (var i = 0; i < plain.length; i++) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = bx.first.top;
    if (lastTop == null || top > lastTop + 1) {
      if (lastTop != null && !ws.hasMatch(plain.substring(lastIdx, i + 1)) && ws.hasMatch(lines.last.toString().trim())) {
        avoidable.add('${visibleText(lines.last.toString())}|${visibleText(plain.substring(i, (i + 3).clamp(0, plain.length)))}');
      }
      lines.add(StringBuffer());
      lastTop = top;
    }
    lines.last.write(plain[i]);
    lastIdx = i;
  }
  return (lines: [for (final b in lines) visibleText(b.toString())], avoidable: avoidable);
}

void main() {
  for (final c in const [(id: 'S046-A', w: 392.0, h: 844.0, s: 1.0), (id: 'S046-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 권장 업데이트 다이얼로그 ${c.w.toInt()}×${c.h.toInt()}@${c.s}', (t) async {
      await t.runAsync(vqLoadFonts);
      final overflows = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        if (m.contains('overflowed')) {
          overflows.add(m.split('\n').first);
        } else {
          prev?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prev);
      try {
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        void out(String l) {
          // ignore: avoid_print
          print(l);
        }

        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) =>
                MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: SplashScreen(versionEvaluator: () async => kRecommend),
          ),
        ));
        for (var i = 0; i < 24; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(Dialog), findsOneWidget, reason: '권장 업데이트 다이얼로그 1개');
        expect(find.byType(SplashScreen), findsOneWidget, reason: '아직 홈으로 가지 않았다(다이얼로그를 기다린다)');
        expect(overflows, isEmpty, reason: '${c.id} 넘침');
        bool hits(Finder f) {
          final hit = HitTestResult();
          WidgetsBinding.instance.hitTestInView(hit, t.getRect(f).center, t.view.viewId);
          return hit.path.any((e) => e.target == t.renderObject(f));
        }

        bool inScreen(Rect x) => x.top >= -0.5 && x.bottom <= c.h + 0.5 && x.left >= -0.5 && x.right <= c.w + 0.5;
        final dlg = find.byType(Dialog);
        out('${c.id} dialog rect=${t.getRect(dlg)} '
            'bg=${t.widget<Dialog>(dlg).backgroundColor} shape=${t.widget<Dialog>(dlg).shape}');
        for (final s in const ['업데이트 안내', '새 버전이 출시됐습니다. 업데이트를 권장합니다.']) {
          expect(find.descendant(of: dlg, matching: findVisibleText(s)), findsOneWidget, reason: '$s 보임');
        }
        for (final b in const ['나중에', '업데이트']) {
          final txt = find.descendant(of: dlg, matching: findVisibleText(b));
          expect(txt, findsOneWidget, reason: '$b 버튼 글자');
          final btn = find.ancestor(of: txt, matching: find.byWidgetPredicate((w) => w is InkWell || w is ButtonStyleButton)).first;
          final r = t.getRect(btn);
          final rp = t.renderObject<RenderParagraph>(find.descendant(of: txt, matching: find.byType(RichText)));
          out('${c.id} button "$b" rect=$r h=${r.height.toStringAsFixed(1)} w=${r.width.toStringAsFixed(1)} hit=${hits(btn)} '
              'inScreen=${inScreen(r)} color=${rp.text.style?.color} weight=${rp.text.style?.fontWeight} '
              'type=${t.widget(btn).runtimeType}');
          expect(inScreen(r), isTrue, reason: '$b 화면 안');
          expect(hits(btn), isTrue, reason: '$b hit');
        }
        for (final e in find.descendant(of: dlg, matching: find.byType(RichText)).evaluate()) {
          final rp = e.renderObject! as RenderParagraph;
          final s = visibleText(rp.text.toPlainText());
          if (s.length < 2) continue;
          final l = _lines(rp);
          out('${c.id} text "$s" rect=${t.getRect(find.byElementPredicate((x) => identical(x, e)))} lines=${l.lines} '
              'avoidable=${l.avoidable} color=${rp.text.style?.color} size=${rp.text.style?.fontSize} w=${rp.text.style?.fontWeight}');
          if (_strict) expect(l.avoidable, isEmpty, reason: '${c.id} 낱말 중간 끊김: "$s"');
        }
        final icons = find.descendant(of: dlg, matching: find.byType(Icon));
        out('${c.id} icons=${icons.evaluate().map((e) => '${(e.widget as Icon).icon?.codePoint.toRadixString(16)}/${(e.widget as Icon).color}').toList()}');
        await vqCapture(t, key, '${c.id}_recommend', conditions: {
          'entry': 'SplashScreen(versionEvaluator → supported+recommendUpdate) → _runGate → 권장 업데이트 다이얼로그',
          'theme': 'RoleTheme.workerTheme', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
          'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK)',
          'pump': '50ms × 24(진입 애니메이션 500ms 이후)', 'buttons': '누르지 않음'});
        out('${c.id} strict=$_strict phase=$vqPhase');
        await t.pumpWidget(const SizedBox.shrink());
      } finally {
        FlutterError.onError = prev;
      }
    });
  }
}
