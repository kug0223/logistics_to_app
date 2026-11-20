// ignore_for_file: depend_on_referenced_packages
// [DU294 공용 필터 대화(DU-O045 FilterDialog) baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU294_RUN=1 이고 DU294_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   호출부(WorkforceListView)와 같이 DialogHelper.showSheet(isScrollControlled·useRootNavigator)로 연다. 누르는 것은 없다(닫기는 Navigator.pop).
//   장면 A 선택 없음 · B 사업장·직접 선택 기간·유형 선택(적용 (3)) × W360/1.0·M360/1.5·B320/2.0.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/inputs/filter_dialog.dart';

import 'support/du1_vq_capture.dart';

const _sections = {'사업장', '공고 유형', '공개 상태', '날짜'};

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

/// 글자 단위 줄 나눔 — '낱말 안에서 끊긴' 곳 수(DU286·288~293 시험과 같은 규칙).
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
          RegExp('[·,./()~:-]').hasMatch(gap);
      if (!sep && word(raw[lastIdx]) && word(ch)) breaks++;
    }
    buf.write(ch);
    lastTop = top;
    lastIdx = i;
  }
  lines.add(TextLayout.plain(buf.toString()).trim());
  return (lines: lines, sylBreaks: breaks);
}

void main() {
  final phase = Platform.environment['DU294_PHASE'] ?? '';
  final run = Platform.environment['DU294_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('D294 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nPng = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D294-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 1500 && nPng <= 10, '사용량 한도');
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
        for (final sc in const ['A', 'B']) {
          cur = '${c.id} $sc';
          await t.pumpWidget(const SizedBox.shrink());
          await frames(1);
          safe('비움');
          BuildContext? appCtx;
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.businessAdminTheme,
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
          final b = sc == 'B';
          unawaited(DialogHelper.showSheet(
            appCtx!,
            isScrollControlled: true,
            useRootNavigator: true,
            builder: (_) => FilterDialog(
              selectedBusinessId: b ? 'b2' : null,
              selectedDateRange: b ? DateTimeRange(start: today.add(const Duration(days: 3)), end: today.add(const Duration(days: 10))) : null,
              selectedTOType: b ? 'flex' : null,
              businessOptions: const {'b1': '강남 물류센터', 'b2': '평택 냉장 물류센터 제2공장 야간동', 'b3': 'QA 매장'},
              isUserMode: false,
              showTOTypeFilter: true,
              showPublishStatusFilter: true,
              onBusinessChanged: (_) {},
              onDateRangeChanged: (_) {},
              onTOTypeChanged: (_) {},
              onPublishStatusChanged: (_) {},
            ),
          ));
          await frames(10);
          safe('열림');
          final sheet = find.byType(FilterDialog);
          need(sheet.evaluate().length == 1, '대화 수 ${sheet.evaluate().length}');
          final bodySv = find.descendant(of: sheet, matching: find.byType(SingleChildScrollView), skipOffstage: false);
          final bodyEl = bodySv.evaluate().isEmpty ? null : bodySv.evaluate().first;
          final texts = <Map<String, Object?>>[];
          for (final e in find.descendant(of: sheet, matching: find.byType(RichText), skipOffstage: false).evaluate()) {
            if (nearest(e, (w) => w is Icon) != null) continue;
            final rp = t.renderObject<RenderParagraph>(fe(e));
            final plain = TextLayout.plain(rp.text.toPlainText());
            final st = rp.text.style;
            final fg = st?.color;
            final bg = bgOf(e);
            final li = _lineInfo(rp);
            final inBody = bodyEl != null && nearest(e, (w) => identical(w, bodyEl.widget)) != null;
            final kind = _sections.contains(plain)
                ? 'section'
                : plain == '초기화'
                    ? 'reset'
                    : plain == '필터'
                        ? 'title'
                        : plain == '취소'
                            ? 'cancel'
                            : plain.startsWith('적용')
                                ? 'apply'
                                : inBody
                                    ? 'chip'
                                    : 'other';
            Rect? box;
            Rect? vis;
            if (kind == 'chip') {
              final gd = nearest(e, (w) => w is GestureDetector);
              if (gd != null) box = t.getRect(fe(gd));
            } else if (kind == 'reset') {
              final tb = nearest(e, (w) => w is TextButton);
              if (tb != null) box = t.getRect(fe(tb));
            } else if (kind == 'cancel' || kind == 'apply') {
              final bb = nearest(e, (w) => w is OutlinedButton || w is ElevatedButton);
              if (bb != null) {
                box = t.getRect(fe(bb));
                final m = find.descendant(of: fe(bb), matching: find.byType(Material)).evaluate();
                if (m.isNotEmpty) vis = t.getRect(fe(m.first));
              }
            }
            final r = t.getRect(fe(e));
            texts.add({
              'text': plain, 'kind': kind, 'rect': lt(r), 'fontSize': st?.fontSize, 'weight': st?.fontWeight?.value,
              'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg), 'contrast': fg == null ? null : r2(_contrast(fg, bg)),
              'lines': li.lines.length, 'sylBreaks': li.sylBreaks, 'didExceedMaxLines': rp.didExceedMaxLines,
              if (box != null) 'boxH': r1(box.height),
              if (box != null) 'onScreen': box.top >= screen.top - 0.5 && box.bottom <= screen.bottom + 0.5,
              if (vis != null) 'visH': r1(vis.height),
              if (kind == 'apply') 'dataRaw': (t.widget<Text>(find.ancestor(of: fe(e), matching: find.byType(Text)).first)).data,
            });
          }
          final icons = <Map<String, Object?>>[];
          for (final e in find.descendant(of: sheet, matching: find.byType(Icon), skipOffstage: false).evaluate()) {
            final w = e.widget as Icon;
            final fg = w.color ?? IconTheme.of(e).color;
            final bg = bgOf(e);
            final ib = nearest(e, (x) => x is IconButton);
            final inChip = nearest(e, (x) => x is GestureDetector) != null && ib == null;
            final r = ib == null ? null : t.getRect(fe(ib));
            icons.add({
              'icon': w.icon?.codePoint, 'close': w.icon == Icons.close, 'inChip': inChip, 'fg': fg == null ? null : _hex(fg),
              'contrast': fg == null ? null : r2(_contrast(fg, bg)), if (r != null) 'hitW': r1(r.width), if (r != null) 'hitH': r1(r.height),
            });
          }
          final row = {'phase': phase, 'cond': c.id, 'scene': sc, 'sheetRect': lt(t.getRect(sheet)), 'overflowSoFar': overflow.length, 'texts': texts, 'icons': icons};
          if (after) {
            for (final x in texts) {
              final at = '${x['kind']} ${x['text']}';
              final cst = x['contrast'];
              need(x['didExceedMaxLines'] != true, '$at 말줄임 $x');
              need(x['sylBreaks'] == 0, '$at 음절 끊김 $x');
              switch (x['kind']) {
                case 'section':
                  need(x['fontSize'] == 16 && x['weight'] == 700 && x['fg'] == _hex(AppColors.textPrimary), '$at 구역 제목 $x');
                case 'chip':
                  need(((x['boxH'] as double?) ?? 0) >= 48, '$at 칩 높이 $x');
                  need(cst is double && cst >= 4.5, '$at 칩 대비 $x');
                case 'reset':
                  need(((x['boxH'] as double?) ?? 0) >= 48 && x['fg'] == _hex(AppColors.textSecondary), '$at 초기화 $x');
                case 'cancel' || 'apply':
                  need(((x['visH'] as double?) ?? 0) >= 52 && x['onScreen'] == true, '$at 아래 버튼 $x');
              }
            }
            final ap = texts.where((x) => x['kind'] == 'apply').toList();
            need(ap.length == 1 && ap.first['dataRaw'] == (sc == 'B' ? '적용 (3)' : '적용'), '적용 글 ${ap.map((x) => x['dataRaw']).toList()}');
            for (final i in icons) {
              need((i['contrast'] as double) >= 3, '아이콘 대비 $i');
              if (i['close'] == true) {
                need((i['hitW'] as double) >= 48 && (i['hitH'] as double) >= 48 && i['fg'] == _hex(AppColors.textSecondary), '닫기 $i');
              }
            }
          }
          nPng++;
          await vqCapture(t, key, 'D294-$phase-${c.id}_$sc', conditions: {
            'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
          });
          rows.add(row);
          _out('D294 ${jsonEncode(rows.last)}');
          Navigator.of(t.element(sheet)).pop();
          await frames(8);
          safe('닫힘');
          need(find.byType(FilterDialog).evaluate().isEmpty, '대화가 닫히지 않았다');
        }
      }
      if (after) {
        need(rows.length == 6, '장면 수 ${rows.length}');
        need(overflow.isEmpty, 'overflow $overflow');
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D294-END ${jsonEncode({'pump': nPump, 'png': nPng, 'rows': rows.length, 'overflow': overflow})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 8)));
}
