// ignore_for_file: depend_on_referenced_packages
// [DU296 공용 메뉴 시트(DU-O054 AppMenuSheet) baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU296_RUN=1 이고 DU296_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   실제 AppMenuSheet.show 로 연다.
//     A: 공고 그룹 카드(계약·열림·미공개) 메뉴와 같은 7그룹 8항목, 머리 없음
//     B: 멤버 관리와 같은 머리(이름·전화·아바타) + 권한 수정·멤버 제거
//   누르는 것은 없다. 조건 W360/1.0·M360/1.5·B320/2.0, B320 A 는 끝까지 끌어 한 장 더.
import 'dart:async';
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
import 'package:ALfit/widgets/common/app_menu_sheet.dart';

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

/// 글자 단위 줄 나눔 — '낱말 안에서 끊긴' 곳 수(DU286·288~295 시험과 같은 규칙).
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

void _noop() {}

/// 장면 A — admin_to_group_card 계약·열림·미공개 메뉴와 같은 순서·색.
List<List<AppMenuSheetItem>> _groupsA() => [
      [const AppMenuSheetItem(icon: Icons.visibility, label: '지원자 화면 미리보기', color: AppColors.info, onTap: _noop)],
      [const AppMenuSheetItem(icon: Icons.edit, label: '수정', color: AppColors.warning, onTap: _noop)],
      [const AppMenuSheetItem(icon: Icons.lock_outline, label: '공고 종료', color: AppColors.warning, onTap: _noop)],
      [const AppMenuSheetItem(icon: Icons.replay, label: '다시 모집하기', color: AppColors.info, onTap: _noop)],
      [const AppMenuSheetItem(icon: Icons.drive_file_rename_outline, label: '관리용 카드명 변경', color: AppColors.purple, onTap: _noop)],
      [
        const AppMenuSheetItem(icon: Icons.person_add_outlined, label: '인력 초대', color: AppColors.success, onTap: _noop),
        const AppMenuSheetItem(icon: Icons.mail_outline, label: '보낸 초대 관리', color: AppColors.info, onTap: _noop),
      ],
      [const AppMenuSheetItem(icon: Icons.delete, label: '미공개 공고 삭제', color: AppColors.error, isDanger: true, onTap: _noop)],
    ];

/// 장면 B — member_management_screen 과 같은 머리·항목.
List<List<AppMenuSheetItem>> _groupsB(Color brand) => [
      [AppMenuSheetItem(icon: Icons.tune, label: '권한 수정', color: brand, onTap: _noop)],
      [const AppMenuSheetItem(icon: Icons.person_remove_outlined, label: '멤버 제거', color: AppColors.error, isDanger: true, onTap: _noop)],
    ];

void main() {
  final phase = Platform.environment['DU296_PHASE'] ?? '';
  final run = Platform.environment['DU296_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  testWidgets('D296 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nPng = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D296-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 1000 && nPng <= 10, '사용량 한도');
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
    final brand = RoleTheme.businessAdminTheme.primaryColor;
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'M360', w: 360.0, h: 780.0, s: 1.5),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        for (final scene in const ['A', 'B']) {
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
          final groups = scene == 'A' ? _groupsA() : _groupsB(brand);
          final labels = [for (final g in groups) for (final i in g) i.label];
          const headTitle = '김민수';
          const headSub = '010-1234-5678';
          if (scene == 'A') {
            unawaited(AppMenuSheet.show(context: appCtx!, itemGroups: groups));
          } else {
            unawaited(AppMenuSheet.show(
              context: appCtx!,
              headerTitle: headTitle,
              headerSubtitle: headSub,
              headerAvatarLetter: '김',
              headerAvatarColor: brand,
              itemGroups: groups,
            ));
          }
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
            final kind = labels.contains(plain)
                ? 'label'
                : plain == headTitle
                    ? 'title'
                    : plain == headSub
                        ? 'subtitle'
                        : plain == '김'
                            ? 'avatar'
                            : 'other';
            final r = t.getRect(fe(e));
            texts.add({
              'text': plain, 'kind': kind, 'rect': lt(r), 'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'contrast': fg == null ? null : r2(_contrast(fg, bg)), 'lines': li.lines, 'sylBreaks': li.sylBreaks,
              'avail': avail.isFinite ? r1(avail) : -1, 'maxTok': r1(maxTok), 'longToken': avail.isFinite && maxTok > avail + 0.5,
              'didExceedMaxLines': rp.didExceedMaxLines, 'w': r1(r.width), 'textW': r1(rp.textSize.width),
            });
          }
          final icons = <Map<String, Object?>>[];
          for (final e in find.descendant(of: sheet, matching: find.byType(Icon), skipOffstage: false).evaluate()) {
            final ic = e.widget as Icon;
            final col = ic.color ?? IconTheme.of(e).color;
            final bg = bgOf(e);
            icons.add({
              'kind': ic.icon == Icons.chevron_right ? 'chevron' : 'item',
              'fg': col == null ? null : _hex(col), 'bg': _hex(bg),
              'contrast': col == null ? null : r2(_contrast(col, bg)),
            });
          }
          final itemH = <double>[
            for (final e in find.descendant(of: sheet, matching: find.byType(InkWell), skipOffstage: false).evaluate())
              r1(t.getRect(fe(e)).height),
          ];
          var wjTexts = 0, semBad = 0;
          for (final w in t.widgetList<Text>(find.descendant(of: sheet, matching: find.byType(Text), skipOffstage: false))) {
            final d = w.data ?? '';
            if (!d.contains(String.fromCharCode(0x2060)) && !d.contains(String.fromCharCode(0x200B))) continue;
            wjTexts++;
            if (w.semanticsLabel != TextLayout.plain(d)) semBad++;
          }
          final shownLabels = [for (final x in texts) if (x['kind'] == 'label') x['text'] as String];
          final row = {
            'phase': phase, 'cond': c.id, 'scene': scene, 'labelsMatch': shownLabels.join(nl) == labels.join(nl),
            'nLabels': shownLabels.length, 'itemH': itemH, 'icons': icons, 'wjTexts': wjTexts, 'semBad': semBad,
            'overflowSoFar': overflow.length, 'texts': texts,
          };
          nPng++;
          await vqCapture(t, key, 'D296-$phase-${c.id}_$scene',
              conditions: {'phase': phase, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s, 'scene': scene});
          if (c.id == 'B320' && scene == 'A') {
            final sf = find.descendant(of: sheet, matching: find.byType(Scrollable));
            if (sf.evaluate().isNotEmpty) {
              final pos = t.state<ScrollableState>(sf.first).position;
              pos.jumpTo(pos.maxScrollExtent);
              await frames(3);
              safe('끝까지');
              row['scrollMax'] = r1(pos.maxScrollExtent);
            }
            final last = find.descendant(
                of: sheet,
                matching: find.byWidgetPredicate((w) => w is RichText && TextLayout.plain(w.text.toPlainText()) == labels.last));
            final lr = last.evaluate().isEmpty ? null : t.getRect(last);
            row['lastVisibleAtEnd'] = lr != null && lr.bottom <= screen.bottom + 0.5 && last.hitTestable().evaluate().isNotEmpty;
            nPng++;
            await vqCapture(t, key, 'D296-$phase-${c.id}_${scene}_end',
                conditions: {'phase': phase, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s, 'scene': scene, 'scroll': 'end'});
          }
          if (after) {
            need(row['labelsMatch'] == true, '메뉴 글 원문 $shownLabels');
            if (scene == 'B') {
              need(texts.any((x) => x['kind'] == 'title') && texts.any((x) => x['kind'] == 'subtitle'), '머리 원문');
            }
            for (final x in texts) {
              final at = '${x['kind']} ${x['text']}';
              need(x['didExceedMaxLines'] != true, '$at 말줄임 $x');
              if (x['longToken'] != true) need(x['sylBreaks'] == 0, '$at 음절 끊김 $x');
              final cst = x['contrast'];
              need(cst is double && cst >= 4.5, '$at 대비 $x');
              need((x['textW'] as double) <= (x['w'] as double) + 0.5, '$at 글이 칸보다 넓다 $x');
            }
            for (final ic in icons) {
              if (ic['kind'] != 'chevron') continue;
              final cst = ic['contrast'];
              need(cst is double && cst >= 3.0, '화살표 대비 $ic');
            }
            need(itemH.length == labels.length && itemH.every((h) => h >= 48), '행 높이 $itemH');
            need(semBad == 0, '읽기 이름 원문 아님 $semBad');
            if (c.id == 'B320' && scene == 'A') need(row['lastVisibleAtEnd'] == true, '끝에서 마지막 항목 도달');
          }
          rows.add(row);
          _out('D296 ${jsonEncode(rows.last)}');
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
      _out('D296-END ${jsonEncode({'pump': nPump, 'png': nPng, 'rows': rows.length, 'overflow': overflow})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 6)));
}
