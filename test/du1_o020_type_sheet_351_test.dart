// ignore_for_file: depend_on_referenced_packages
// [DU351] O020 계약서 양식 유형 선택 시트 렌더 — 세 목적(기본 조항으로 시작 · 가져오기 분류 · 빈 양식 분류) × W 392x844 1.0 / B 320x640 2.0.
//   시트를 화면 아래에 직접 띄운다(공용 showSheet 경로는 기존 시험이 본다). 대비 · 바탕 도우미는 du1_s018_template_list_344_test 와 같다.
//   단언(기본): 예외 0 · 넘침 0 · 피할 수 있는 끊김 0 · 대비 미달 0 · 유형 행 탭 → 반환값(daily/period). DU_BEFORE_OBSERVE=351 이면 끊김 · 대비 기록만.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/widgets/dialogs/contract_template_type_selector_sheet.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';
import 'support/visible_text.dart';

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '351';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

Color _overWhite(Color c) => Color.alphaBlend(c, Colors.white);

Color _bgOf(Element e) {
  Color? found;
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is ButtonStyleButton) {
      c = w.style?.backgroundColor?.resolve(w.enabled ? <WidgetState>{} : {WidgetState.disabled});
      if (c == null && w is ElevatedButton) c = Theme.of(a).colorScheme.primary;
      if (c == null) return true;
    } else if (w is Container && w.decoration is BoxDecoration) {
      c = (w.decoration! as BoxDecoration).color;
    } else if (w is Container && w.color != null) {
      c = w.color;
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      c = (w.decoration as BoxDecoration).color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color ?? Theme.of(a).colorScheme.surface;
    } else if (w is ColoredBox) {
      c = w.color;
    }
    if (c == null || c.a == 0) return true;
    found = _overWhite(c);
    return false;
  });
  return found ?? Colors.white;
}

void main() {
  for (final c in const [(id: 'O020-W', w: 392.0, h: 844.0, s: 1.0), (id: 'O020-B', w: 320.0, h: 640.0, s: 2.0)]) {
    for (final p in ContractTemplateTypePurpose.values) {
      testWidgets('${c.id} 유형 선택 시트 ${p.name} ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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

          String? picked = 'unset';
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.businessAdminTheme,
              builder: (ctx, child) =>
                  MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
              home: Builder(
                builder: (ctx) => Scaffold(
                  backgroundColor: Colors.black54,
                  body: Center(
                    child: TextButton(
                      onPressed: () async {
                        picked = await showModalBottomSheet<String>(
                            context: ctx, isScrollControlled: true, useSafeArea: true,
                            builder: (_) => ContractTemplateTypeSelectorSheet(purpose: p));
                      },
                      child: const Text('열기'),
                    ),
                  ),
                ),
              ),
            ),
          ));
          await t.tap(find.text('열기'));
          for (var i = 0; i < 12; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(t.takeException(), isNull);
          var avoid = 0, low = 0;
          final seen = <String>{};
          for (final e in find.descendant(of: find.byType(ContractTemplateTypeSelectorSheet), matching: find.byType(RichText)).evaluate()) {
            final rp = e.renderObject! as RenderParagraph;
            final s = visibleText(rp.text.toPlainText());
            if (s.isEmpty) continue;
            final self = find.byElementPredicate((x) => identical(x, e));
            if (find.ancestor(of: self, matching: find.byType(Icon)).evaluate().isNotEmpty) continue;
            final col = rp.text.style?.color;
            final bg = _bgOf(e);
            final k = '$s@${bg.toARGB32()}@${col?.toARGB32()}';
            if (seen.contains(k)) continue;
            seen.add(k);
            for (final b in wordBreaks(rp)) {
              if (!b.forced) {
                avoid++;
                out('${c.id}_${p.name} avoidable $b');
              }
            }
            final cst = col == null ? 99.0 : _contrast(_overWhite(col), bg);
            if (cst < 4.5) {
              low++;
              out('${c.id}_${p.name} low "$s" color=0x${col?.toARGB32().toRadixString(16)} bg=0x${bg.toARGB32().toRadixString(16)} contrast=${cst.toStringAsFixed(2)}');
            }
          }
          await vqCapture(t, key, '${c.id}_${p.name}', conditions: {'purpose': p.name, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
          // 단기 행 탭 → 반환값 daily
          final daily = findVisibleText(ContractTemplateType.label(ContractTemplateType.daily));
          await t.ensureVisible(daily);
          await t.pump(const Duration(milliseconds: 50));
          await t.tap(daily);
          for (var i = 0; i < 10; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(picked, ContractTemplateType.daily, reason: '${c.id} 단기 행 → daily');
          expect(t.takeException(), isNull);
          out('${c.id}_${p.name} summary overflows=${overflows.length} avoidable=$avoid low=$low picked=$picked beforeObs=$_beforeObs');
          out('KNOWN ${avoid == 0 && low == 0 ? 'ok' : 'NG'} ${c.id}_${p.name} 끊김 $avoid · 대비 $low');
          expect(overflows, isEmpty, reason: '${c.id} 넘침');
          if (!_beforeObs) {
            expect(avoid, 0, reason: '${c.id} 피할 수 있는 끊김');
            expect(low, 0, reason: '${c.id} 대비 미달');
          }
          await t.pumpWidget(const SizedBox.shrink());
        } finally {
          FlutterError.onError = prev;
        }
      });
    }
  }
}
