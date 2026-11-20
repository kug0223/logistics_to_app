// ignore_for_file: depend_on_referenced_packages
// [DU290 공용 날짜 선택 시트(DU-O035) baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU290_RUN=1 이고 DU290_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   실제 DatePickerBottomSheet.show / DateRangePickerBottomSheet.show 를 앱 문맥에서 호출해 연다(문구는 lib 호출부 원문).
//   장면 S1·S2·S3(단일)·R1·R2·R3(기간) × W360/1.0·M360/1.5·B320/2.0. 누르는 것은 없다(닫기는 Navigator.pop).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/calendar/carrot_style_calendar.dart';
import 'package:ALfit/widgets/pickers/date_picker_bottom_sheet.dart';

import 'support/du1_vq_capture.dart';

typedef _Sc = ({String id, bool range, String title, String? sub, int? a, int? b});

String _n(String s) => s.replaceAll('¶', String.fromCharCode(10));

const List<_Sc> _scenes = [
  (id: 'S1', range: false, title: '퇴사 희망일 선택', sub: null, a: null, b: null),
  (id: 'S2', range: false, title: '새 계약 시작일', sub: '기존 계약기간이 종료되었습니다.¶계약 시작일부터 새로운 근무 일정이 적용됩니다.', a: 3, b: null),
  (id: 'S3', range: false, title: '시작 가능 마지막날', sub: '지원자가 선택 가능한 가장 늦은 시작일입니다', a: 5, b: null),
  (id: 'R1', range: true, title: '날짜 범위 선택', sub: null, a: null, b: null),
  (id: 'R2', range: true, title: '날짜 범위 선택', sub: '조회할 기간을 선택해주세요', a: 3, b: null),
  (id: 'R3', range: true, title: '날짜 범위 선택', sub: '조회할 기간을 선택해주세요', a: 3, b: 10),
];

const Map<String, Set<String>> _shots = {
  'S1': {'W360', 'B320'},
  'S2': {'W360', 'M360', 'B320'},
  'S3': {'W360', 'B320'},
  'R1': {'W360', 'B320'},
  'R2': {'W360', 'B320'},
  'R3': {'W360', 'M360', 'B320'},
};

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

/// 글자 단위 줄 나눔 — 줄마다 보이는 글자, '낱말 안에서 끊긴' 곳 수(DU286·288·289 시험과 같은 규칙).
({List<String> lines, int sylBreaks}) _lineInfo(RenderParagraph rp) {
  final raw = rp.text.toPlainText();
  final wj = String.fromCharCode(0x2060);
  final zw = String.fromCharCode(0x200B);
  bool word(String ch) {
    final u = ch.codeUnitAt(0);
    return (u >= 0xAC00 && u <= 0xD7A3) || (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
  }

  final lines = <String>[];
  var buf = StringBuffer();
  int? lastTop;
  var lastIdx = -1;
  var breaks = 0;
  for (var i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (ch == wj) continue;
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty || ch == ' ' || ch == zw) {
      buf.write(ch);
      continue;
    }
    final top = bx.first.top.round();
    if (lastTop != null && top != lastTop) {
      lines.add(TextLayout.plain(buf.toString()).trim());
      buf = StringBuffer();
      final gap = raw.substring(lastIdx, i + 1);
      final sep = gap.contains(' ') || gap.contains(zw) || gap.contains(String.fromCharCode(10)) ||
          RegExp('[·,./()~-]').hasMatch(gap);
      if (!sep && word(raw[lastIdx]) && word(ch)) breaks++;
    }
    buf.write(ch);
    lastTop = top;
    lastIdx = i;
  }
  lines.add(TextLayout.plain(buf.toString()).trim());
  return (lines: lines, sylBreaks: breaks);
}

double _tpWidth(String text, TextStyle? style, TextScaler scaler, Locale? locale) {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: scaler, locale: locale)
    ..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

void main() {
  final phase = Platform.environment['DU290_PHASE'] ?? '';
  final run = Platform.environment['DU290_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('D290 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nPng = 0, nOpen = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D290-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 3000 && nPng <= 20 && nOpen <= 30, '사용량 한도');
        await t.pump(const Duration(milliseconds: 50));
      }
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

    double r1(double v) => double.parse(v.toStringAsFixed(1));
    double r2(double v) => double.parse(v.toStringAsFixed(2));
    List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom].map(r1).toList();
    Finder fe(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);

    Color bgOf(Element e) {
      final layers = <Color>[];
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

    Element? nearest(Element e, bool Function(Widget w) p) {
      Element? hit;
      e.visitAncestorElements((a) {
        if (p(a.widget)) {
          hit = a;
          return false;
        }
        return true;
      });
      return hit;
    }

    final key = GlobalKey();
    final rows = <Map<String, Object?>>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'M360', w: 360.0, h: 780.0, s: 1.5),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        t.platformDispatcher.textScaleFactorTestValue = c.s;
        final screen = Rect.fromLTWH(0, 0, c.w, c.h);
        for (final sc in _scenes) {
          cur = '${c.id} ${sc.id}';
          nOpen++;
          await t.pumpWidget(const SizedBox.shrink());
          await frames(1);
          safe('비움');
          BuildContext? appCtx;
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
              home: Scaffold(body: Builder(builder: (ctx) {
                appCtx = ctx;
                return const SizedBox.expand();
              })),
            ),
          ));
          await frames(2);
          need(appCtx != null, '앱 문맥 없음');
          final sub = sc.sub == null ? null : _n(sc.sub!);
          final a = sc.a == null ? null : today.add(Duration(days: sc.a!));
          final b = sc.b == null ? null : today.add(Duration(days: sc.b!));
          if (sc.range) {
            unawaited(DateRangePickerBottomSheet.show(
              context: appCtx!, initialStart: a, initialEnd: b, title: sc.title, subtitle: sub,
              minDate: today, maxDate: today.add(const Duration(days: 365)),
            ));
          } else {
            unawaited(DatePickerBottomSheet.show(
              context: appCtx!, initialDate: a, title: sc.title, subtitle: sub,
              minDate: today, maxDate: today.add(const Duration(days: 365)),
            ));
          }
          await frames(10);
          safe('열림');
          final sheet = find.byType(BottomSheet);
          need(sheet.evaluate().length == 1, '시트 수 ${sheet.evaluate().length}');
          final ctxIn = t.element(sheet);
          final scaler = MediaQuery.textScalerOf(ctxIn);
          final loc = Localizations.maybeLocaleOf(ctxIn);
          final cal = find.descendant(of: sheet, matching: find.byType(CarrotStyleCalendar));
          final calEl = cal.evaluate().isEmpty ? null : cal.evaluate().first;

          final texts = <Map<String, Object?>>[];
          for (final e in find.descendant(of: sheet, matching: find.byType(RichText), skipOffstage: false).evaluate()) {
            if (nearest(e, (w) => w is Icon) != null) continue;
            // [r2] 달력 안 글자도 끊김·말줄임 측정에 넣는다(kind 'calendar', 대비 단언 대상은 아님)
            final inCal = calEl != null && nearest(e, (w) => identical(w, calEl.widget)) != null;
            final rp = t.renderObject<RenderParagraph>(fe(e));
            final plain = TextLayout.plain(rp.text.toPlainText());
            final st = rp.text.style;
            final fg = st?.color;
            final bg = bgOf(e);
            final r = t.getRect(fe(e));
            final li = _lineInfo(rp);
            final avail = rp.constraints.maxWidth;
            var maxTok = 0.0;
            for (final tok in plain.split(RegExp('[ $nl]+'))) {
              if (tok.isEmpty) continue;
              maxTok = math.max(maxTok, _tpWidth(tok, st, scaler, loc));
            }
            final kind = inCal
                ? 'calendar'
                : plain == sc.title
                ? 'title'
                : (sub != null && plain == sub)
                    ? 'sub'
                    : plain == '선택 완료'
                        ? 'confirm'
                        : plain == '취소'
                            ? 'cancel'
                            : plain == '선택'
                                ? 'placeholder'
                                : (plain == '시작일' || plain == '종료일')
                                    ? 'rangeLabel'
                                    : 'other';
            texts.add({
              'text': plain, 'kind': kind, 'rect': lt(r), 'fontSize': st?.fontSize, 'weight': st?.fontWeight?.value,
              'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg), 'contrast': fg == null ? null : r2(_contrast(fg, bg)),
              'lines': li.lines, 'sylBreaks': li.sylBreaks, 'avail': avail.isFinite ? r1(avail) : -1, 'maxTok': r1(maxTok),
              'longToken': avail.isFinite && maxTok > avail + 0.5, 'didExceedMaxLines': rp.didExceedMaxLines,
            });
          }
          final okF = find.descendant(of: sheet, matching: find.widgetWithText(ElevatedButton, '선택 완료'));
          final cancelF = find.descendant(of: sheet, matching: find.byWidgetPredicate((w) => w is OutlinedButton));
          final nOk = okF.evaluate().length;
          Map<String, Object?> btn(Finder f) {
            if (f.evaluate().length != 1) return {'n': f.evaluate().length};
            final r = t.getRect(f);
            final m = find.descendant(of: f, matching: find.byType(Material)).evaluate();
            final vis = m.isEmpty ? r : t.getRect(fe(m.first));
            return {
              'rect': lt(r), 'visH': r1(vis.height), 'onScreen': r.top >= screen.top - 0.5 && r.bottom <= screen.bottom + 0.5,
              'hit': f.hitTestable().evaluate().isNotEmpty,
            };
          }

          final ok = btn(okF);
          final cancel = btn(cancelF);
          final okEnabled = nOk == 1 && t.widget<ElevatedButton>(okF).onPressed != null;
          final closeF = find.descendant(of: sheet, matching: find.byType(IconButton));
          final closeR = closeF.evaluate().length == 1 ? t.getRect(closeF) : Rect.zero;
          final row = {
            'phase': phase, 'cond': c.id, 'scene': sc.id, 'range': sc.range, 'sheetRect': lt(t.getRect(sheet)),
            'calRect': calEl == null ? null : lt(t.getRect(fe(calEl))), 'nOk': nOk, 'okEnabled': okEnabled, 'ok': ok, 'cancel': cancel,
            'close': [r1(closeR.width), r1(closeR.height)], 'overflowSoFar': overflow.length, 'texts': texts,
          };

          if (after) {
            need(nOk == 1, "'선택 완료' ElevatedButton 수 $nOk");
            need(okEnabled == (sc.a != null && (!sc.range || sc.b != null)), '활성 $okEnabled');
            for (final x in [ok, cancel]) {
              need(x['onScreen'] == true && x['hit'] == true, '버튼이 첫 화면 밖/누를 수 없음 $x');
              need(((x['visH'] as double?) ?? 0) >= 48, '버튼 높이 $x');
            }
            for (final x in texts) {
              final at = '${x['kind']} ${x['text']}';
              final cst = x['contrast'];
              need(x['didExceedMaxLines'] != true, '$at 말줄임 $x');
              if (x['longToken'] != true) need(x['sylBreaks'] == 0, '$at 음절 끊김 $x');
              if (x['kind'] == 'confirm' || x['kind'] == 'cancel' || x['kind'] == 'placeholder' || x['kind'] == 'sub' ||
                  x['kind'] == 'title' || x['kind'] == 'rangeLabel') {
                need(cst is double && cst >= 4.5, '$at 대비 $x');
              }
            }
            need(closeR.width >= 48 && closeR.height >= 48, '닫기 누름 $closeR');
          }

          final shot = _shots[sc.id]?.contains(c.id) ?? false;
          if (shot) {
            nPng++;
            await vqCapture(t, key, 'D290-$phase-${c.id}_${sc.id}', conditions: {
              'phase': phase, 'scene': sc.id, 'title': sc.title, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
            });
          }
          rows.add(row..['shot'] = shot);
          _out('D290 ${jsonEncode(rows.last)}');
          Navigator.of(ctxIn).pop();
          await frames(8);
          safe('닫힘');
          need(find.byType(BottomSheet).evaluate().isEmpty, '시트가 닫히지 않았다');
        }
      }
      if (after) {
        need(rows.length == _scenes.length * 3, '장면 수 ${rows.length}');
        need(overflow.isEmpty, 'overflow $overflow');
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D290-END ${jsonEncode({'pump': nPump, 'png': nPng, 'open': nOpen, 'rows': rows.length, 'overflow': overflow})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 8)));
}
