// ignore_for_file: depend_on_referenced_packages
// [DU295 지원 당시 기준 확인 시트(DU-O016) baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU295_RUN=1 이고 DU295_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   실제 ApplicationPolicyAcknowledgeSheet.show 로 연다(지원서 snapshot = DU264 _rules(), 현재 기준 = defaults → 두 블록).
//   누르는 것은 없다(확인 호출 없음). 조건 W360/1.0·M360/1.5·B320/2.0, B320 은 끝까지 끌어 한 장 더.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart' show AttendanceRules;
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/attendance_policy_disclosure.dart' show attendancePolicyLines;
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/application_policy_acknowledge_sheet.dart';

import 'support/du1_vq_capture.dart';

AttendanceRules _rules() => AttendanceRules.defaults().copyWith(
      earlyWindow: 30,
      earlyArrivalUnit: 30,
      lateGrace: 5,
      lateUnit: 30,
      lateWindow: 30,
      overtimeUnit: 30,
      earlyLeaveUnit: 30,
    );

const _titleNow = '현재 사업장 기준 (이 근무에는 적용되지 않음)';
const _titleSnap = '지원 당시 기준 (이 근무에 적용)';
const _primary = '지원 당시 기준으로 확정';
const _later = '나중에';

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

/// 글자 단위 줄 나눔 — '낱말 안에서 끊긴' 곳 수(DU286·288~294 시험과 같은 규칙).
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

void main() {
  final phase = Platform.environment['DU295_PHASE'] ?? '';
  final run = Platform.environment['DU295_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  testWidgets('D295 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nPng = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D295-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 1000 && nPng <= 8, '사용량 한도');
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
    final app = ApplicationModel(
      id: 'app-d295', toId: 'to-d295', uid: 'u-d295', businessId: 'biz-d295', businessName: 'QA 물류센터', toTitle: '야간 분류',
      status: 'CONFIRMED', selectedWorkType: '분류', startTime: '22:00', endTime: '23:30',
      workDate: DateTime(2026, 11, 20), wage: 12000, appliedAt: DateTime(2026, 11, 10, 9),
      attendancePolicySnapshot: _rules(),
    );
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'M360', w: 360.0, h: 780.0, s: 1.5),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        cur = c.id;
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        t.platformDispatcher.textScaleFactorTestValue = c.s;
        final screen = Rect.fromLTWH(0, 0, c.w, c.h);
        final enlarged = c.s > 1.0;
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
        unawaited(ApplicationPolicyAcknowledgeSheet.show(appCtx!, application: app, workerName: '김민수', currentBusinessRules: AttendanceRules.defaults()));
        await frames(10);
        safe('열림');
        final sheet = find.byType(BottomSheet);
        need(sheet.evaluate().length == 1, '시트 수 ${sheet.evaluate().length}');
        final ctxIn = t.element(sheet);
        final scaler = MediaQuery.textScalerOf(ctxIn);
        final loc = Localizations.maybeLocaleOf(ctxIn);
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
          final kind = (plain == _titleNow || plain == _titleSnap)
              ? 'blockTitle'
              : (plain == _primary || plain == _later)
                  ? 'button'
                  : 'other';
          texts.add({
            'text': plain, 'kind': kind, 'rect': lt(t.getRect(fe(e))), 'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
            'contrast': fg == null ? null : r2(_contrast(fg, bg)), 'lines': li.lines, 'sylBreaks': li.sylBreaks,
            'avail': avail.isFinite ? r1(avail) : -1, 'maxTok': r1(maxTok), 'longToken': avail.isFinite && maxTok > avail + 0.5,
            'didExceedMaxLines': rp.didExceedMaxLines,
          });
        }
        Map<String, Object?> btn(Finder f) {
          if (f.evaluate().length != 1) return {'n': f.evaluate().length};
          final r = t.getRect(f);
          final m = find.descendant(of: f, matching: find.byType(Material)).evaluate();
          final vis = m.isEmpty ? r : t.getRect(fe(m.first));
          return {'rect': lt(r), 'visH': r1(vis.height), 'w': r1(vis.width)};
        }

        final pBtn = btn(find.descendant(of: sheet, matching: find.byWidgetPredicate((w) => w is ElevatedButton)));
        final lBtn = btn(find.descendant(of: sheet, matching: find.byWidgetPredicate((w) => w is OutlinedButton)));
        // [TB v2 보정] 배치는 가로로 겹치는지로 판정한다(v1 은 위쪽 좌표만 봐서 높이가 다른 옆 배치를 세로로 읽었다).
        final pR = pBtn['rect'] as List?;
        final lR = lBtn['rect'] as List?;
        var layout = '?';
        if (pR != null && lR != null) {
          final hOverlap = math.min(pR[2] as double, lR[2] as double) - math.max(pR[0] as double, lR[0] as double);
          layout = hOverlap <= 0 ? 'row' : ((pR[1] as double) < (lR[1] as double) ? 'colPrimaryFirst' : 'colLaterFirst');
        }
        final prF = find.descendant(of: sheet, matching: find.byWidgetPredicate((w) => w is ElevatedButton));
        final primaryVisibleTop = prF.evaluate().length == 1 &&
            t.getRect(prF).bottom <= screen.bottom + 0.5 &&
            t.getRect(prF).top >= screen.top - 0.5 &&
            prF.hitTestable().evaluate().isNotEmpty;
        // 기준 줄: 라벨 다음 글이 값이다. 값이 라벨 아래 같은 왼쪽이면 stacked, 라벨 오른쪽이면 side.
        final snapLines = attendancePolicyLines(_rules());
        final nowLines = attendancePolicyLines(AttendanceRules.defaults());
        final labelSet = {...snapLines.map((l) => l.label), ...nowLines.map((l) => l.label)};
        var stacked = 0, side = 0, odd = 0;
        final values = <String>[];
        for (var i = 0; i + 1 < texts.length; i++) {
          if (!labelSet.contains(texts[i]['text'])) continue;
          texts[i]['kind'] = 'label';
          texts[i + 1]['kind'] = 'value';
          values.add(texts[i + 1]['text'] as String);
          final a = texts[i]['rect'] as List;
          final b = texts[i + 1]['rect'] as List;
          if (((b[0] as double) - (a[0] as double)).abs() < 1 && (b[1] as double) >= (a[3] as double) - 0.5) {
            stacked++;
          } else if ((b[0] as double) >= (a[2] as double) - 0.5) {
            side++;
          } else {
            odd++;
          }
        }
        final expectValues = [...snapLines.map((l) => l.value), ...nowLines.map((l) => l.value)];
        // 화면 글자에 묶음 문자가 있으면 접근성 이름은 원문이어야 한다.
        var wjTexts = 0, semBad = 0;
        for (final w in t.widgetList<Text>(find.descendant(of: sheet, matching: find.byType(Text), skipOffstage: false))) {
          final d = w.data ?? '';
          if (!d.contains(String.fromCharCode(0x2060))) continue;
          wjTexts++;
          if (w.semanticsLabel != TextLayout.plain(d)) semBad++;
        }
        final body = texts.where((x) => (x['text'] as String).contains('조건은 바뀌지 않습니다')).length;
        final row = {'phase': phase, 'cond': c.id, 'primary': pBtn, 'later': lBtn, 'btnLayout': layout, 'bodyFound': body,
          'primaryVisibleTop': primaryVisibleTop, 'labelLayout': {'stacked': stacked, 'side': side, 'odd': odd},
          'valuesMatch': values.join(nl) == expectValues.join(nl), 'nValues': values.length, 'wjTexts': wjTexts, 'semBad': semBad,
          'overflowSoFar': overflow.length, 'texts': texts};
        nPng++;
        await vqCapture(t, key, 'D295-$phase-${c.id}_top', conditions: {'phase': phase, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s});
        if (c.id == 'B320') {
          final sf = find.descendant(of: sheet, matching: find.byType(Scrollable)).first;
          final pos = t.state<ScrollableState>(sf).position;
          pos.jumpTo(pos.maxScrollExtent);
          await frames(3);
          safe('끝까지');
          row['scrollMax'] = r1(pos.maxScrollExtent);
          final pr = find.descendant(of: sheet, matching: find.byWidgetPredicate((w) => w is ElevatedButton));
          row['primaryVisibleAtEnd'] = pr.evaluate().isNotEmpty && t.getRect(pr).bottom <= screen.bottom + 0.5 && pr.hitTestable().evaluate().isNotEmpty;
          nPng++;
          await vqCapture(t, key, 'D295-$phase-${c.id}_end', conditions: {'phase': phase, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s, 'scroll': 'end'});
        }
        if (after) {
          need(body >= 1, '본문 계약 문구');
          need(texts.any((x) => x['text'] == _titleNow) && texts.any((x) => x['text'] == _titleSnap), '블록 제목 원문');
          for (final x in texts) {
            final at = '${x['kind']} ${x['text']}';
            need(x['didExceedMaxLines'] != true, '$at 말줄임 $x');
            if (x['longToken'] != true) need(x['sylBreaks'] == 0, '$at 음절 끊김 $x');
            final cst = x['contrast'];
            need(cst is double && cst >= 4.5, '$at 대비 $x');
          }
          need(((pBtn['visH'] as double?) ?? 0) >= 52 && ((lBtn['visH'] as double?) ?? 0) >= 52, '버튼 높이 $pBtn $lBtn');
          need(enlarged ? layout == 'colPrimaryFirst' : layout == 'row', '버튼 배치 $layout');
          need(primaryVisibleTop, '첫 화면 주 버튼 도달');
          if (c.id == 'B320') need(row['primaryVisibleAtEnd'] == true, '끝에서 주 버튼 도달');
          need(values.length == 14 && row['valuesMatch'] == true, '기준 값 원문 $values');
          need(odd == 0 && (enlarged ? stacked == 14 : side == 14), '기준 줄 배치 ${row['labelLayout']}');
          need(semBad == 0, '접근성 이름 원문 아님 $semBad');
        }
        rows.add(row);
        _out('D295 ${jsonEncode(rows.last)}');
        Navigator.of(ctxIn).pop();
        await frames(8);
        safe('닫힘');
      }
      if (after) {
        need(rows.length == 3, '장면 수 ${rows.length}');
        need(overflow.isEmpty, 'overflow $overflow');
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D295-END ${jsonEncode({'pump': nPump, 'png': nPng, 'rows': rows.length, 'overflow': overflow})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 6)));
}
