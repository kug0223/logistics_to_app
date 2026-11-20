// [DU248 공용 AppEmptyState 읽기색 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU248_RUN=1 이고 DU248_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   AppEmptyState 를 화면 바탕(Scaffold background)·흰 면 두 곳에 놓는다(기본 제목·부제·동작). W360/1.0·B320/2.0.
//   외부 채널 없음. tap 0.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/common/app_empty_state.dart';

import 'support/du1_vq_capture.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

void main() {
  final phase = Platform.environment['DU248_PHASE'] ?? '';
  final run = Platform.environment['DU248_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  const kTitle = '표시할 항목이 없습니다';
  const kSub = '조건을 바꾸거나 잠시 후 다시 확인해 주세요.';
  const kLongTitle = '선택한 기간에 확정된 근무 기록이 아직 없습니다';

  testWidgets('D248 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPng = 0;
    final key = GlobalKey();

    Finder? firstOf(Finder f) {
      final els = f.evaluate().toList();
      if (els.isEmpty) return null;
      final e = els.first;
      return find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
    }

    Finder rich(String s) =>
        find.byWidgetPredicate((w) => w is RichText && TextLayout.plain(w.text.toPlainText()) == s, skipOffstage: false);
    Color bgOf(Element e) {
      Color? out;
      e.visitAncestorElements((a) {
        final w = a.widget;
        Color? c;
        if (w is ColoredBox) {
          c = w.color;
        } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
          c = (w.decoration as BoxDecoration).color;
        } else if (w is Material && w.type != MaterialType.transparency) {
          c = w.color ?? Theme.of(a).canvasColor;
        } else if (w is Scaffold) {
          c = w.backgroundColor ?? Theme.of(a).scaffoldBackgroundColor;
        }
        if (c == null || c.a < 1.0) return true;
        out = c;
        return false;
      });
      return out ?? Colors.white;
    }

    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        for (final sc in const ['bg', 'white']) {
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          await t.pumpWidget(const SizedBox.shrink());
          Widget state(String title) => AppEmptyState(
                icon: Icons.inbox_outlined,
                title: title,
                subtitle: kSub,
                action: TextButton(onPressed: () {}, child: const Text('다시 시도')),
              );
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.workerTheme,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('ko', 'KR')],
              home: Scaffold(
                appBar: AppBar(title: const Text('빈 상태')),
                // [r1] AppEmptyState(비 sliver)는 LayoutBuilder 로 부모 높이를 최소 높이로 쓴다 — 높이가 정해진 칸에 둔다
                //   (실제 화면 body 와 같다). 무한 높이 스크롤 안에 두면 배치가 실패했다(TB v0).
                //   장면마다 상태 하나를 body 전체에 둔다(bg = 짧은 제목, white = 긴 제목) — 큰 글자에서 잘린 채 재지 않게.
                body: sc == 'white'
                    ? ColoredBox(color: AppColors.surface, child: state(kLongTitle))
                    : state(kTitle),
              ),
            ),
          ));
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          final ex = t.takeException();
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          Map<String, Object?> info(String nm, Finder? f) {
            if (f == null) return {'name': nm, 'present': false};
            final rp = t.renderObject<RenderParagraph>(f);
            final fg = rp.text.style?.color;
            final bg = bgOf(f.evaluate().first);
            final r = t.getRect(f);
            bool inBox(Rect b) => r.left >= b.left - 0.5 && r.right <= b.right + 0.5 && r.top >= b.top - 0.5 && r.bottom <= b.bottom + 0.5;
            // [r1] 위젯 안쪽 스크롤(작은 공간에서 스크롤로 바뀜)의 viewport 안이어야 보인다.
            final sc0 = find.ancestor(of: f, matching: find.byType(Scrollable));
            final vp = sc0.evaluate().isEmpty ? screen : t.getRect(sc0.first);
            return {
              'name': nm, 'present': true, 'rect': [r.left, r.top, r.right, r.bottom], 'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'fontSize': rp.text.style?.fontSize,
              'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
              'visible': inBox(screen) && inBox(vp),
              'didExceedMaxLines': rp.didExceedMaxLines,
            };
          }

          final xs = [
            info('제목', firstOf(rich(kTitle))),
            info('부제', firstOf(rich(kSub))),
            info('긴 제목', firstOf(rich(kLongTitle))),
            info('동작', firstOf(rich('다시 시도'))),
          ];
          final errs = [...errors];
          errors.clear();
          if (after) {
            if (ex != null || errs.isNotEmpty) fail('${c.id} $sc 예외/overflow: $ex $errs');
            for (final x in xs) {
              if (x['present'] != true || x['visible'] != true) continue;
              final n = x['name'];
              final cst = x['contrast'];
              if (n == '동작') continue;
              final want = n == '부제' ? '#686C77' : '#60646F';
              if (x['fg'] != want || cst is! double || cst < 4.5) fail('${c.id} $sc 읽기색 $x');
            }
          }
          nPng++;
          await vqCapture(t, key, 'D248-$phase-${c.id}_$sc', conditions: {
            'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
          });
          _out('D248 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'exception': ex?.toString(), 'errors': errs, 'texts': xs})}');
        }
      }
      await t.pumpWidget(const SizedBox.shrink());
      _out('D248-END ${jsonEncode({'png': nPng})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 3)));
}
