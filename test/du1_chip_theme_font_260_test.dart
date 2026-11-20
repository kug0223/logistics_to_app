// ignore_for_file: depend_on_referenced_packages
// [DU260 테마 chipTheme 라벨 글꼴 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU260_RUN=1 이고 DU260_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   부품 장면 1(앱에 있는 Material 칩 모양 5개) × W360/1.0·B320/2.0, workerTheme. 외부 채널 없음, tap 0.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/responsive_helper.dart';
import 'package:ALfit/utils/text_layout.dart';

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
  final phase = Platform.environment['DU260_PHASE'] ?? '';
  final run = Platform.environment['DU260_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  testWidgets('D260 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var cur = '(시작)';
    Never stop(String why) {
      _out('D260-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    final overflow = <String>[];
    void safe(String at) {
      final ex = t.takeException();
      need(ex == null, '$at 예외: $ex');
      for (final e in errors) {
        if (!after && e.startsWith('A RenderFlex overflowed by')) {
          overflow.add('$at $e');
        } else {
          stop('$at 예외/overflow: $e');
        }
      }
      errors.clear();
    }

    Color bgOf(Element e) {
      final layers = <Color>[];
      e.visitAncestorElements((a) {
        final w = a.widget;
        Color? c;
        if (w is ColoredBox) {
          c = w.color;
        } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
          c = (w.decoration as BoxDecoration).color;
        } else if (w is DecoratedBox && w.decoration is ShapeDecoration) {
          c = (w.decoration as ShapeDecoration).color; // 칩 면은 ShapeDecoration 으로 칠해진다
        } else if (w is Material && w.type != MaterialType.transparency) {
          c = w.color ?? Theme.of(a).canvasColor;
        } else if (w is Scaffold) {
          c = w.backgroundColor ?? Theme.of(a).scaffoldBackgroundColor;
        }
        if (c == null || c.a == 0) return true;
        layers.add(c);
        return c.a < 1.0;
      });
      var out = layers.isEmpty ? Colors.white : layers.last;
      for (final c in layers.reversed.skip(1)) {
        out = Color.alphaBlend(c, out);
      }
      return out;
    }

    // 칩 라벨의 실제 렌더 색: 칩 Material 의 면 색이 안 잡히면 ink 면을 찾는다 — 여기서는 칩 바탕 대신 RenderParagraph 의 색만 쓴다.
    final key = GlobalKey();
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        cur = c.id;
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump();
        safe('장면 종료');
        overflow.clear();
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        t.platformDispatcher.textScaleFactorTestValue = c.s;
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
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Builder(
                    builder: (ctx) => Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // 초대 지역 추천(S069) 모양 — 스타일 없음
                        ActionChip(
                          avatar: const Icon(Icons.home_outlined, size: 16),
                          label: const Text('포항시 남구 추가'),
                          onPressed: () {},
                        ),
                        // 지원 검토 대기열 모양 — 글꼴 없는 자체 TextStyle 13
                        FilterChip(
                          label: const Text('확인 필요',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brand)),
                          selected: true,
                          onSelected: (_) {},
                          backgroundColor: AppColors.grey100,
                          selectedColor: AppColors.infoBg,
                          checkmarkColor: AppColors.brand,
                        ),
                        FilterChip(
                          label: const Text('보류',
                              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                          selected: false,
                          onSelected: (_) {},
                          backgroundColor: AppColors.grey100,
                        ),
                        // 대조군 — 화면이 ResponsiveHelper 스타일(글꼴 명시)을 넘기는 모양(알림·SA 목록)
                        FilterChip(
                          label: const Text('전체 알림'),
                          labelStyle: ResponsiveHelper.smallStyle(ctx, color: AppColors.textPrimary),
                          selected: false,
                          onSelected: (_) {},
                        ),
                        // 스타일 없는 ChoiceChip
                        ChoiceChip(
                          label: const Text('2027년'),
                          selected: true,
                          onSelected: (_) {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        safe('첫 화면');

        Map<String, Object?> info(String nm, String text, {String? kind}) {
          final f = find.byWidgetPredicate(
              (w) => w is RichText && TextLayout.plain(w.text.toPlainText()) == text, skipOffstage: false);
          if (f.evaluate().isEmpty) return {'name': nm, 'present': false};
          final rp = t.renderObject<RenderParagraph>(f.first);
          final st = rp.text.style;
          final fg = st?.color;
          final bg = bgOf(f.evaluate().first);
          final chip = find.ancestor(of: f.first, matching: find.byWidgetPredicate((w) => w is ChipAttributes));
          final h = chip.evaluate().isEmpty ? null : t.getRect(chip.first).height;
          return {
            'name': nm, 'kind': kind, 'present': true, 'fontFamily': st?.fontFamily, 'fontSize': st?.fontSize,
            'weight': st?.fontWeight?.value, 'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
            'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
            'chipH': h == null ? null : double.parse(h.toStringAsFixed(1)),
          };
        }

        final xs = [
          info('ActionChip 스타일 없음', '포항시 남구 추가', kind: 'theme'),
          info('FilterChip 자체 13 선택', '확인 필요', kind: 'own13'),
          info('FilterChip 자체 13 미선택', '보류', kind: 'own13'),
          info('FilterChip 대조 smallStyle', '전체 알림', kind: 'control'),
          info('ChoiceChip 스타일 없음', '2027년', kind: 'theme'),
        ];
        if (after) {
          for (final x in xs) {
            need(x['present'] == true, '칩 없음 $x');
            need(x['fontFamily'] == 'NotoSansKR', '앱 글꼴 아님 $x');
            final cst = x['contrast'];
            need(cst is double && cst >= 4.5, '대비 $x');
            if (x['kind'] == 'theme') need(x['fontSize'] == 14.0, '테마 크기 $x');
            if (x['kind'] == 'own13') need(x['fontSize'] == 13.0, '화면 크기 유지 $x');
            if (x['kind'] == 'control') need(x['fontSize'] == 13.0, '대조군 크기 유지 $x');
          }
        }
        await vqCapture(t, key, 'D260-$phase-${c.id}_chips', conditions: {
          'phase': phase, 'scene': 'chips', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
        });
        _out('D260 ${jsonEncode({'phase': phase, 'cond': c.id, 'overflow': overflow, 'chips': xs})}');
      }
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      safe('END 전');
      _out('D260-END');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 3)));
}
