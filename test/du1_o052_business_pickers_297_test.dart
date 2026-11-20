// ignore_for_file: depend_on_referenced_packages
// [DU297 사업장 고르기 시트 2종(DU-O052 BusinessPickerHelper 시트·DU-O080 BusinessSelectorSheet) baseline/after]
//   Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU297_RUN=1 이고 DU297_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   P: BusinessPickerHelper.pickFromList(실제 진입) — 사업장 3(긴 이름 1·운영 종료 1)
//   S: 홈 배지와 같은 DialogHelper.showSheet + BusinessSelectorSheet — 사업장 5(긴 이름 1, 둘째 선택)
//   누르는 것은 없다. 조건 W360/1.0·M360/1.5·B320/2.0, 스크롤이 있으면 끝까지 끌어 마지막 항목 도달을 본다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/business_picker_helper.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/common/business_selector_sheet.dart';

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

/// 글자 단위 줄 나눔 — '낱말 안에서 끊긴' 곳 수(DU286·288~296 시험과 같은 규칙).
///   identity 가 긴 이름 가운데에 둔 ZWSP 에서 끊긴 것은 허용된 자리다(sep).
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

double _tpWidth(String text, TextStyle? style, TextScaler scaler, Locale? locale) {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: scaler, locale: locale)
    ..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

BusinessModel _biz(String id, String name, {bool closed = false}) => BusinessModel(
      id: id,
      businessNumber: '123-45-67890',
      name: name,
      category: '물류',
      subCategory: '분류',
      address: '경기도 평택시',
      ownerId: 'owner-d297',
      isApproved: true,
      createdAt: DateTime(2026, 1, 1),
      deactivatedAt: closed ? DateTime(2026, 10, 1) : null,
    );

const _long = '평택 냉장 물류센터 제2공장 야간동';
const _closedTag = '운영 종료';

void main() {
  final phase = Platform.environment['DU297_PHASE'] ?? '';
  final run = Platform.environment['DU297_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  testWidgets('D297 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nPng = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D297-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 1000 && nPng <= 14, '사용량 한도');
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    final overflow = <String>[];
    void safe(String at) {
      final ex = t.takeException();
      need(ex == null || (!after && '$ex'.contains('overflowed')), '$at 예외: $ex');
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
    final pickList = [_biz('b1', 'QA 물류센터'), _biz('b2', _long), _biz('b3', '한빛 분류센터', closed: true)];
    final selIds = ['s1', 's2', 's3', 's4', 's5'];
    final selNames = {
      's1': 'QA 물류센터',
      's2': _long,
      's3': '한빛 분류센터',
      's4': '안성 신선 물류센터',
      's5': '이천 상온 분류센터 2동',
    };
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'M360', w: 360.0, h: 780.0, s: 1.5),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        for (final scene in const ['P', 'S']) {
          cur = '${c.id}_$scene';
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
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
          final names = scene == 'P' ? [for (final b in pickList) b.name] : [for (final id in selIds) selNames[id]!];
          if (scene == 'P') {
            unawaited(BusinessPickerHelper.pickFromList(appCtx!, pickList, dialogTitle: '사업장 선택'));
          } else {
            unawaited(DialogHelper.showSheet<String>(
              appCtx!,
              builder: (ctx) => BusinessSelectorSheet(businessIds: selIds, businessNames: selNames, selectedBusinessId: 's2'),
            ));
          }
          await frames(10);
          safe('열림');
          final sheet = find.byType(BottomSheet);
          need(sheet.evaluate().length == 1, '시트 수 ${sheet.evaluate().length}');
          final ctxIn = t.element(sheet);
          final scaler = MediaQuery.textScalerOf(ctxIn);
          final loc = Localizations.maybeLocaleOf(ctxIn);
          final sheetRect = t.getRect(sheet);
          final texts = <Map<String, Object?>>[];
          for (final e in find.descendant(of: sheet, matching: find.byType(RichText), skipOffstage: false).evaluate()) {
            if (nearest(e, (w) => w is Icon) != null) continue;
            final rp = t.renderObject<RenderParagraph>(fe(e));
            final plain = TextLayout.plain(rp.text.toPlainText());
            final st = rp.text.style;
            final fg = st?.color;
            final bg = bgOf(e);
            final li = _lineInfo(rp);
            final avail = rp.constraints.maxWidth;
            var maxTok = 0.0;
            for (final tok in plain.split(RegExp('[ $nl]+'))) {
              if (tok.isEmpty) continue;
              maxTok = math.max(maxTok, _tpWidth(tok, st, scaler, loc));
            }
            final kind = names.contains(plain)
                ? 'name'
                : plain == _closedTag
                    ? 'tag'
                    : plain == '사업장 선택'
                        ? 'title'
                        : 'other';
            final r = t.getRect(fe(e));
            texts.add({
              'text': plain, 'kind': kind, 'rect': lt(r), 'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'contrast': fg == null ? null : r2(_contrast(fg, bg)), 'lines': li.lines, 'sylBreaks': li.sylBreaks,
              'avail': avail.isFinite ? r1(avail) : -1, 'maxTok': r1(maxTok), 'longToken': avail.isFinite && maxTok > avail + 0.5,
              'didExceedMaxLines': rp.didExceedMaxLines,
            });
          }
          final icons = <Map<String, Object?>>[];
          for (final e in find.descendant(of: sheet, matching: find.byType(Icon), skipOffstage: false).evaluate()) {
            final ic = e.widget as Icon;
            final col = ic.color ?? IconTheme.of(e).color;
            final bg = bgOf(e);
            final kind = ic.icon == Icons.chevron_right
                ? 'chevron'
                : ic.icon == Icons.close
                    ? 'close'
                    : ic.icon == Icons.check_rounded
                        ? 'check'
                        : 'other';
            icons.add({'kind': kind, 'fg': col == null ? null : _hex(col), 'bg': _hex(bg), 'contrast': col == null ? null : r2(_contrast(col, bg))});
          }
          final closeBtn = find.descendant(of: sheet, matching: find.byType(IconButton));
          final closeSize = closeBtn.evaluate().isEmpty ? null : t.getSize(closeBtn.first);
          final rowH = <double>[
            for (final e in find.descendant(of: sheet, matching: find.byWidgetPredicate((w) => w is InkWell || w is ListTile), skipOffstage: false).evaluate())
              if (e.widget is ListTile || nearest(e, (w) => w is ListTile) == null && nearest(e, (w) => w is IconButton) == null && e.widget is! IconButton)
                r1(t.getRect(fe(e)).height),
          ];
          var semBad = 0, wjTexts = 0;
          for (final w in t.widgetList<Text>(find.descendant(of: sheet, matching: find.byType(Text), skipOffstage: false))) {
            final d = w.data ?? '';
            if (!d.contains(String.fromCharCode(0x2060)) && !d.contains(String.fromCharCode(0x200B))) continue;
            wjTexts++;
            if (w.semanticsLabel != TextLayout.plain(d)) semBad++;
          }
          final shownNames = [for (final x in texts) if (x['kind'] == 'name') x['text'] as String];
          final row = <String, Object?>{
            'phase': phase, 'cond': c.id, 'scene': scene, 'sheetRect': lt(sheetRect), 'namesMatch': shownNames.join(nl) == names.join(nl),
            'nNames': shownNames.length, 'tags': texts.where((x) => x['kind'] == 'tag').length, 'rowH': rowH,
            'close': closeSize == null ? null : [r1(closeSize.width), r1(closeSize.height)], 'icons': icons,
            'wjTexts': wjTexts, 'semBad': semBad, 'overflowSoFar': overflow.length, 'texts': texts,
          };
          nPng++;
          await vqCapture(t, key, 'D297-$phase-${c.id}_$scene',
              conditions: {'phase': phase, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s, 'scene': scene});
          // 마지막 항목 도달 — 스크롤이 있으면 끝까지 끈다.
          final sf = find.descendant(of: sheet, matching: find.byType(Scrollable));
          var scrolled = false;
          if (sf.evaluate().isNotEmpty) {
            final pos = t.state<ScrollableState>(sf.first).position;
            row['scrollMax'] = r1(pos.maxScrollExtent);
            if (pos.maxScrollExtent > 0) {
              pos.jumpTo(pos.maxScrollExtent);
              await frames(3);
              safe('끝까지');
              scrolled = true;
            }
          } else {
            row['scrollMax'] = null;
          }
          final last = find.descendant(
              of: sheet, matching: find.byWidgetPredicate((w) => w is RichText && TextLayout.plain(w.text.toPlainText()) == names.last));
          final lr = last.evaluate().isEmpty ? null : t.getRect(last);
          row['lastVisible'] = lr != null && lr.bottom <= screen.bottom + 0.5 && lr.bottom <= sheetRect.bottom + 0.5 && last.hitTestable().evaluate().isNotEmpty;
          if (scrolled) {
            nPng++;
            await vqCapture(t, key, 'D297-$phase-${c.id}_${scene}_end',
                conditions: {'phase': phase, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s, 'scene': scene, 'scroll': 'end'});
          }
          if (after) {
            need(row['namesMatch'] == true, '사업장 이름 원문 $shownNames');
            if (scene == 'P') need(row['tags'] == 1, '운영 종료 표시 ${row['tags']}');
            for (final x in texts) {
              final at = '${x['kind']} ${x['text']}';
              need(x['didExceedMaxLines'] != true, '$at 말줄임 $x');
              if (x['longToken'] != true) need(x['sylBreaks'] == 0, '$at 음절 끊김 $x');
              final cst = x['contrast'];
              need(cst is double && cst >= 4.5, '$at 대비 $x');
            }
            for (final ic in icons) {
              if (ic['kind'] == 'other') continue;
              final cst = ic['contrast'];
              need(cst is double && cst >= 3.0, '아이콘 대비 $ic');
            }
            if (closeSize != null) need(closeSize.width >= 48 && closeSize.height >= 48, '닫기 크기 $closeSize');
            need(rowH.length == names.length && rowH.every((h) => h >= 48), '행 높이 $rowH');
            need(semBad == 0, '읽기 이름 원문 아님 $semBad');
            need(row['lastVisible'] == true, '마지막 항목 도달');
          }
          rows.add(row);
          _out('D297 ${jsonEncode(rows.last)}');
          Navigator.of(ctxIn).pop();
          await frames(8);
          safe('닫힘');
        }
      }
      if (after) {
        need(rows.length == 6, '장면 수 ${rows.length}');
        need(overflow.isEmpty, 'overflow $overflow');
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D297-END ${jsonEncode({'pump': nPump, 'png': nPng, 'rows': rows.length, 'overflow': overflow})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 6)));
}
