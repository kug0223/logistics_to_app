// ignore_for_file: depend_on_referenced_packages
// [DU314] S047 TourScreen(가이드) — 지원자 4페이지 · 관리자 5페이지 렌더 관측(11-15 자체검토 셀).
//   진입: 실제 pushTourScreen(ctx, role:) — 설정/홈의 '가이드' 진입과 같은 helper. CTA 를 눌러 페이지를 넘긴다.
//   단언(전후 공통): 넘침 0 · CTA/건너뛰기 화면 안 · hit · 마지막 CTA 누르면 닫힘(원래 화면 복귀).
//   [DU314 r2] 기본 실행에서 늘(DU_BEFORE_OBSERVE=314 일 때만 기록): 넘침 0 · 건너뛰기 화면 안 · CTA 높이 ≥ 52 · 피할 수 있는 음절 끊김 0
//   (앞 줄에 공백이 있는데도 낱말 중간에서 끊긴 경우. 한 낱말이 줄보다 길어 강제로 갈린 경우는 forced 로 기록만).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/common/tour_screen.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

// [DU314 r2] 소급 2 결정 — 현재 제품 정답 단언은 기본 실행에서 건다. VQ 는 PNG 저장에만 쓴다.
//   알려진 옛 결함(넘침 · 건너뛰기 화면 밖 · CTA 52 · 낱말)은 명시 env DU_BEFORE_OBSERVE=314 에서만 기록으로 둔다.
final bool _strict = Platform.environment['DU_BEFORE_OBSERVE'] != '314';

({List<String> lines, List<String> avoidable, List<String> forced}) _lines(RenderParagraph rp) {
  final plain = rp.text.toPlainText();
  final lines = <StringBuffer>[];
  final avoidable = <String>[];
  final forced = <String>[];
  final ws = RegExp(r'[\s ]');
  double? lastTop;
  var lastIdx = -1;
  for (var i = 0; i < plain.length; i++) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = bx.first.top;
    if (lastTop == null || top > lastTop + 1) {
      if (lastTop != null && !ws.hasMatch(plain.substring(lastIdx, i + 1))) {
        final prevLine = lines.last.toString();
        final tag = '${visibleText(prevLine)}|${visibleText(plain.substring(i, (i + 3).clamp(0, plain.length)))}';
        // 앞 줄에 공백이 있으면 그 낱말 전체를 다음 줄로 보낼 수 있었다 — 피할 수 있는 끊김.
        (ws.hasMatch(prevLine.trim()) ? avoidable : forced).add(tag);
      }
      lines.add(StringBuffer());
      lastTop = top;
    }
    lines.last.write(plain[i]);
    lastIdx = i;
  }
  return (lines: [for (final b in lines) visibleText(b.toString())], avoidable: avoidable, forced: forced);
}

void main() {
  const roles = [(role: 'USER', n: 4, tag: 'U'), (role: 'BUSINESS_ADMIN', n: 5, tag: 'M')];
  for (final c in const [(id: 'S047-A', w: 392.0, h: 844.0, s: 1.0), (id: 'S047-B', w: 320.0, h: 640.0, s: 2.0)]) {
    for (final r in roles) {
      testWidgets('${c.id}${r.tag} 가이드 ${r.role} ${c.w.toInt()}×${c.h.toInt()}@${c.s} — ${r.n}페이지 → 닫힘', (t) async {
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
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => pushTourScreen(ctx, role: r.role),
                    child: const Text('가이드 열기'),
                  ),
                ),
              ),
            ),
          ),
        ));
        await t.pump();
        await t.tap(find.text('가이드 열기'));
        Future<void> settle([int n = 24]) async {
          for (var i = 0; i < n; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        }

        await settle();
        expect(find.byType(TourScreen), findsOneWidget);

        Map<String, Object?> cond(String state) => {
              'entry': 'pushTourScreen(ctx, role: ${r.role}) — 실제 helper(fullscreenDialog)',
              'theme': 'RoleTheme.workerTheme', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
              'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK)',
              'pump': '진입 · 페이지 넘김 뒤 50ms × 24(전환 400ms · 탄성 600ms 이후)', 'state': state};

        bool hits(Finder f) {
          final hit = HitTestResult();
          WidgetsBinding.instance.hitTestInView(hit, t.getRect(f).center, t.view.viewId);
          return hit.path.any((e) => e.target == t.renderObject(f));
        }

        bool inScreen(Rect x) => x.top >= -0.5 && x.bottom <= c.h + 0.5 && x.left >= -0.5 && x.right <= c.w + 0.5;
        // CTA = TourScreen 안의 GestureDetector 중 '다음' / '확인' 글자를 품은 가장 안쪽 것
        Finder cta() => find
            .ancestor(
                of: find.descendant(
                    of: find.byType(TourScreen),
                    matching: find.byWidgetPredicate((w) => w is Text && ['다음', '확인'].contains(visibleText(w.data ?? '')))),
                matching: find.byType(GestureDetector))
            .first;
        Finder skip() => find.descendant(of: find.byType(TourScreen), matching: find.byType(TextButton));

        for (var p = 1; p <= r.n; p++) {
          final tag = '${c.id}${r.tag}_p$p';
          // 넘침은 늘 기록하고 after 단계에서만 단언한다(before 의 결함을 캡처로 남기기 위해).
          final ov = List.of(overflows);
          overflows.clear();
          out('$tag overflows=${ov.length} $ov');
          if (_strict) expect(ov, isEmpty, reason: '$tag 넘침');
          final cr = t.getRect(cta());
          final sr = t.getRect(skip());
          final label = visibleText(t
                  .widget<Text>(find.descendant(of: cta(), matching: find.byWidgetPredicate((w) => w is Text && w.data != null)))
                  .data ??
              '');
          final deco = t.widget<AnimatedContainer>(find.descendant(of: cta(), matching: find.byType(AnimatedContainer)).first).decoration
              as BoxDecoration?;
          out('$tag cta rect=$cr h=${cr.height.toStringAsFixed(1)} label="$label" color=${deco?.color} '
              'shadow=${deco?.boxShadow?.map((b) => '${b.color.a.toStringAsFixed(2)}/${b.blurRadius}/${b.offset.dy}').join(',')} '
              'hit=${hits(cta())} inScreen=${inScreen(cr)}');
          out('$tag skip rect=$sr h=${sr.height.toStringAsFixed(1)} hit=${hits(skip())} inScreen=${inScreen(sr)} '
              'color=${t.widget<Text>(find.descendant(of: skip(), matching: find.byType(Text))).style?.color}');
          expect(inScreen(cr), isTrue, reason: '$tag CTA 화면 안');
          expect(hits(cta()), isTrue, reason: '$tag CTA hit');
          // before 의 상단 칩 넘침(320·2.0 뒷페이지)은 건너뛰기를 화면 밖으로 민다 — 넘침과 같이 after 에서만 단언.
          if (_strict) expect(inScreen(sr), isTrue, reason: '$tag 건너뛰기 화면 안');
          expect(hits(skip()), isTrue, reason: '$tag 건너뛰기 hit');
          expect(sr.height, greaterThanOrEqualTo(48 - 1e-6), reason: '$tag 건너뛰기 높이 48');
          if (_strict) {
            expect(cr.height, greaterThanOrEqualTo(52 - 1e-6), reason: '$tag CTA 높이 52(공통 주 버튼 기준)');
          }
          final paras = find.descendant(of: find.byType(TourScreen), matching: find.byType(RichText));
          for (final e in paras.evaluate()) {
            final rp = e.renderObject! as RenderParagraph;
            final s = visibleText(rp.text.toPlainText());
            if (s.length < 2) continue; // 아이콘 글리프
            final l = _lines(rp);
            final rect = t.getRect(find.byElementPredicate((x) => identical(x, e)));
            // PageView 의 화면 밖 페이지(일러스트)는 빼고 본다
            if (rect.right < 0 || rect.left > c.w) continue;
            out('$tag text "$s" rect=$rect lines=${l.lines.length} ${l.lines} avoidable=${l.avoidable} forced=${l.forced} '
                'color=${rp.text.style?.color} size=${rp.text.style?.fontSize}');
            if (_strict) {
              expect(l.avoidable, isEmpty, reason: '$tag 피할 수 있는 낱말 중간 끊김: "$s"');
            }
          }
          await vqCapture(t, key, '${tag}', conditions: cond('${r.role} 가이드 $p/${r.n}페이지'));
          await t.tap(cta());
          await settle();
        }
        // 마지막 CTA → 닫히고 원래 화면
        expect(find.byType(TourScreen), findsNothing, reason: '마지막 CTA 로 닫힘');
        expect(find.text('가이드 열기'), findsOneWidget);
        out('${c.id}${r.tag} closed strict=$_strict beforeObserve=${Platform.environment['DU_BEFORE_OBSERVE'] ?? '(unset)'} phase=$vqPhase');
        await t.pumpWidget(const SizedBox.shrink());
        } finally {
          // 단언 실패 때도 오류 처리기를 먼저 되돌린다 — 안 그러면 binding 단언 뒤 10분 시간 초과까지 멈춘다(TB 실측).
          FlutterError.onError = prev;
        }
      });
    }
  }
}
