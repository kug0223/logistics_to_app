// [DU357] 공용 오류 토스트 — 면/글자 대비 · 원문 보존 낱말 조판(소급 10 §2-2). 생성기 work/du357-toast-error/mk_test.py.
//   W 392x844@1.0 · B 320x640@2.0. 오류 토스트: 긴 한글 2문구(DU353 실제 · 2줄 문구) · 키보드(viewInsets) · ToastAvoidArea 하단 CTA.
//   보존 단언(항상): 오류 4초 뒤 사라짐 · 새 토스트가 이전 것을 바꿈 · 토스트 아래 버튼이 눌림(IgnorePointer) · 키보드 위 · CTA 윗변 위.
//   시각 단언(기본, 오류 토스트만): 대비 4.5 이상 · 피할 수 있는 끊김 0. 성공 · 안내 · 경고는 기록만(KNOWN 줄).
//   DU_BEFORE_OBSERVE=357 이면 오류 토스트 시각도 기록만.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/toast_helper.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';
import 'support/visible_text.dart';

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '357';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// 토스트 면 색(가장 가까운 장식 Container) — 불투명 면이라 그대로 쓴다.
Color _toastBg(Element e) {
  Color? found;
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color != null) {
      found = (w.decoration! as BoxDecoration).color;
      return false;
    }
    return true;
  });
  return found ?? Colors.white;
}

const _msgs = <String>[
  '템플릿 목록을 불러오지 못했습니다',
  '약관 동의 기록에 실패했습니다.\n다시 로그인하여 재시도해주세요.',
];

void main() {
  for (final c in const [(id: 'TOAST-W', w: 392.0, h: 844.0, s: 1.0), (id: 'TOAST-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 공용 토스트 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
      await t.runAsync(vqLoadFonts);
      t.view.physicalSize = Size(c.w, c.h);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      void out(String l) {
        // ignore: avoid_print
        print(l);
      }

      var underTaps = 0;
      var ctaTaps = 0;
      var withCta = false;
      late StateSetter setOuter;
      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: RoleTheme.workerTheme,
          builder: (ctx, child) =>
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
          home: StatefulBuilder(builder: (ctx, setState) {
            setOuter = setState;
            return Scaffold(
              appBar: AppBar(title: const Text('토스트 시험')),
              body: Stack(children: [
                // 토스트 자리 아래에 깔린 버튼(IgnorePointer 확인용)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 160,
                  child: GestureDetector(
                    key: const ValueKey('under'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => underTaps++,
                    child: const ColoredBox(color: Color(0xFFF6F7FA)),
                  ),
                ),
              ]),
              bottomNavigationBar: withCta
                  ? SafeArea(
                      top: false,
                      child: ToastAvoidArea(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: ElevatedButton(onPressed: () => ctaTaps++, child: const Text('공고 등록')),
                        ),
                      ),
                    )
                  : null,
            );
          }),
        ),
      ));
      await t.pump(const Duration(milliseconds: 100));

      final steps = <String, bool>{};
      final vis = <String, String>{};
      var errAvoid = 0, errLow = 0;
      Finder toastText(String m) => find.byWidgetPredicate((w) => w is RichText && visibleText(w.text.toPlainText()) == m);

      Future<void> measure(String kind, String m, {bool isError = false}) async {
        final f = toastText(m);
        if (f.evaluate().isEmpty) {
          vis['$kind:$m'] = 'missing';
          return;
        }
        final e = f.evaluate().first;
        final rp = e.renderObject! as RenderParagraph;
        final col = rp.text.style?.color ?? Colors.black;
        final bg = _toastBg(e);
        final cst = _contrast(Color.alphaBlend(col, bg), bg);
        final breaks = wordBreaks(rp).where((b) => !b.forced).toList();
        vis['$kind:${m.split('\n').first}'] = 'contrast=${cst.toStringAsFixed(2)} bg=0x${bg.toARGB32().toRadixString(16)} avoidable=${breaks.length}';
        for (final b in breaks) {
          out('${c.id} $kind avoidable $b');
        }
        if (isError) {
          errAvoid += breaks.length;
          if (cst < 4.5) errLow++;
        }
      }

      // ① 오류 토스트 두 문구
      for (var i = 0; i < _msgs.length; i++) {
        ToastHelper.showError(_msgs[i]);
        await t.pump(const Duration(milliseconds: 100));
        await measure('error', _msgs[i], isError: true);
        await vqCapture(t, key, '${c.id}_error_${i + 1}', conditions: {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'state': '오류 토스트 ${i + 1}'});
        if (i == 0) {
          steps['교체: 새 토스트가 이전 것을 지움'] = true;
        } else {
          steps['교체: 새 토스트가 이전 것을 지움'] = toastText(_msgs[0]).evaluate().isEmpty && toastText(_msgs[1]).evaluate().isNotEmpty;
        }
      }
      // ② IgnorePointer — 토스트 한가운데를 눌러도 아래 버튼이 눌린다
      final tr = t.getRect(toastText(_msgs[1]).first);
      await t.tapAt(tr.center);
      await t.pump(const Duration(milliseconds: 50));
      steps['IgnorePointer: 아래 버튼 눌림'] = underTaps == 1;
      // ③ 4초 뒤 사라짐
      await t.pump(const Duration(seconds: 4));
      await t.pump(const Duration(milliseconds: 100));
      steps['오류 4초 뒤 사라짐'] = toastText(_msgs[1]).evaluate().isEmpty;
      // ④ 키보드 위
      final kb = (c.h * 0.4).roundToDouble();
      t.view.viewInsets = FakeViewPadding(bottom: kb);
      await t.pump(const Duration(milliseconds: 100));
      ToastHelper.showError(_msgs[0]);
      await t.pump(const Duration(milliseconds: 100));
      final kr = t.getRect(find.ancestor(of: toastText(_msgs[0]).first, matching: find.byType(Container)).first);
      out('${c.id} keyboard toast=${kr.top.toStringAsFixed(1)}–${kr.bottom.toStringAsFixed(1)} limit=${(c.h - kb).toStringAsFixed(1)}');
      steps['키보드 위'] = kr.bottom <= c.h - kb + 0.5;
      await vqCapture(t, key, '${c.id}_error_keyboard', conditions: {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'state': '키보드 ${kb.toInt()} 위 오류 토스트'});
      await t.pump(const Duration(seconds: 5));
      t.view.resetViewInsets();
      await t.pump(const Duration(milliseconds: 100));
      // ⑤ ToastAvoidArea CTA 위
      setOuter(() => withCta = true);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));
      ToastHelper.showError(_msgs[1]);
      await t.pump(const Duration(milliseconds: 100));
      final ctaTop = t.getRect(find.byType(ElevatedButton)).top;
      final ar = t.getRect(find.ancestor(of: toastText(_msgs[1]).first, matching: find.byType(Container)).first);
      out('${c.id} avoid toastBottom=${ar.bottom.toStringAsFixed(1)} ctaTop=${ctaTop.toStringAsFixed(1)}');
      // 등록 윗변 = ToastAvoidArea 상자 윗변 = 버튼 윗변 - 패딩 16, 토스트 아래 끝은 그보다 8 위
      steps['ToastAvoidArea: CTA 윗변 위'] = ar.bottom <= ctaTop - 16 - 8 + 0.5;
      await vqCapture(t, key, '${c.id}_error_cta', conditions: {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'state': '하단 CTA 위 오류 토스트'});
      await t.pump(const Duration(seconds: 5));
      setOuter(() => withCta = false);
      await t.pump(const Duration(milliseconds: 100));
      // ⑥ 다른 토스트(기록만)
      for (final k in const ['success', 'info', 'warning']) {
        final m = _msgs[0];
        switch (k) {
          case 'success':
            ToastHelper.showSuccess(m);
          case 'info':
            ToastHelper.showInfo(m);
          default:
            ToastHelper.showWarning(m);
        }
        await t.pump(const Duration(milliseconds: 100));
        await measure(k, m);
        await vqCapture(t, key, '${c.id}_$k', conditions: {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'state': '$k 토스트(기록)'});
        await t.pump(const Duration(seconds: 3));
      }

      expect(t.takeException(), isNull);
      out('${c.id} steps=$steps');
      out('${c.id} vis=$vis');
      out('KNOWN ${steps.values.every((v) => v) ? 'ok' : 'NG'} ${c.id} 보존(교체 · IgnorePointer · 4초 · 키보드 · CTA)');
      out('KNOWN ${errAvoid == 0 && errLow == 0 ? 'ok' : 'NG'} ${c.id} 오류 토스트 끊김 $errAvoid · 대비 미달 $errLow');
      for (final k in const ['success', 'info', 'warning']) {
        final v = vis.entries.firstWhere((e) => e.key.startsWith('$k:'), orElse: () => const MapEntry('', '')).value;
        out('KNOWN ${v.contains('avoidable=0') && !v.contains('contrast=1.') && !v.contains('contrast=2.') && !v.contains('contrast=3.') ? 'ok' : 'NG'} ${c.id} 기록만 $k: $v');
      }
      for (final en in steps.entries) {
        expect(en.value, isTrue, reason: '${c.id} ${en.key}');
      }
      if (!_beforeObs) {
        expect(errAvoid, 0, reason: '${c.id} 오류 토스트 끊김');
        expect(errLow, 0, reason: '${c.id} 오류 토스트 대비');
      }
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 5));
    });
  }
}
