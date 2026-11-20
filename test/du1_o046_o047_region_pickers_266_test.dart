// ignore_for_file: depend_on_referenced_packages
// [DU266 O046·O047 지역 선택 시트 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU266_RUN=1 이고 DU266_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   실제처럼 각 show() 로 연다(선택·반환 없음). 장면 5(h-prov·h-city·r-city·r-dist·r-empty) × W360/1.0·B320/2.0.
//   측정 lines 기본 true.
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
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/widgets/inputs/home_region_picker_sheet.dart';
import 'package:ALfit/widgets/inputs/region_picker_sheet.dart';

import 'support/du1_vq_capture.dart';

const _cities = ['강남구', '수원시 영통구', '포항시 남구'];
List<String> _districtOf(String c) => c == '강남구' ? const ['역삼동', '삼성동', '대치동', '개포동'] : const [];

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

/// 글자 단위 줄 나눔 — 줄마다 보이는 글자, 그리고 '낱말 안에서 끊긴' 곳 수.
///   끊긴 자리 앞뒤가 모두 한글 음절·영숫자이고 그 사이에 공백·ZWSP·줄바꿈·구두점이 없으면 음절 끊김으로 센다.
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

void main() {
  final phase = Platform.environment['DU266_PHASE'] ?? '';
  final run = Platform.environment['DU266_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('D266 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nDrag = 0, nPng = 0, nTap = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D266-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 1400 && nDrag <= 80 && nPng <= 100 && nTap <= 12, '사용량 한도'); // [r1] B320 세로 배치로 길어짐
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

    Finder rich(bool Function(String p) f) =>
        find.byWidgetPredicate((w) => w is RichText && f(TextLayout.plain(w.text.toPlainText())), skipOffstage: false);
    Finder? nth(Finder f, int i) {
      final els = f.evaluate().toList();
      if (els.isEmpty) return null;
      final e = i < 0 ? els.last : (i < els.length ? els[i] : null);
      if (e == null) return null;
      return find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
    }

    Finder? glyph(IconData icon, int i) {
      final f = find.descendant(of: find.byIcon(icon, skipOffstage: false), matching: find.byType(RichText), skipOffstage: false);
      return nth(f, i);
    }

    double r1(double v) => double.parse(v.toStringAsFixed(1));
    List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom].map(r1).toList();
    bool inside(Rect r, Rect b) => r.left >= b.left - 0.5 && r.top >= b.top - 0.5 && r.right <= b.right + 0.5 && r.bottom <= b.bottom + 0.5;

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

    final key = GlobalKey();
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        for (final sc in const ['h-prov', 'h-city', 'r-city', 'r-dist', 'r-empty']) {
          cur = '${c.id} $sc';
          await t.pumpWidget(const SizedBox.shrink());
          await frames(1);
          safe('장면 종료');
          overflow.clear();
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
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
                body: Center(
                  child: Builder(
                    builder: (ctx) => TextButton(
                      onPressed: () {
                        if (sc.startsWith('h-')) {
                          HomeRegionPickerSheet.show(
                            context: ctx,
                            selectedRegion: sc == 'h-city' ? const UserRegion(province: '경상북도', city: '포항시') : null,
                          );
                        } else {
                          RegionPickerSheet.show(
                            context: ctx,
                            cities: sc == 'r-empty' ? const <String>[] : _cities,
                            districtOf: _districtOf,
                            selectedCity: sc == 'r-dist' ? '강남구' : null,
                            selectedDistrict: sc == 'r-dist' ? '삼성동' : null,
                          );
                        }
                      },
                      child: const Text('열기'),
                    ),
                  ),
                ),
              ),
            ),
          ));
          await frames(2);
          nTap++;
          await t.tap(find.text('열기'));
          await frames(14);
          safe('시트 열림');
          need(find.byType(HomeRegionPickerSheet).evaluate().length + find.byType(RegionPickerSheet).evaluate().length == 1, '시트가 열리지 않았다');

          Finder? sfOf() {
            final host = sc.startsWith('h-') ? find.byType(HomeRegionPickerSheet) : find.byType(RegionPickerSheet);
            final f = find.descendant(of: host, matching: find.byType(Scrollable), skipOffstage: false);
            return f.evaluate().isEmpty ? null : nth(f, 0);
          }

          Map<String, Object?> info(String nm, Finder? f, {String? kind, bool lines = true, Finder? box}) {
            if (f == null) return {'name': nm, 'kind': kind, 'present': false};
            final rp = t.renderObject<RenderParagraph>(f);
            final r = t.getRect(f);
            final fg = rp.text.style?.color;
            final bg = bgOf(f.evaluate().first);
            final sf = sfOf();
            final inSf = sf != null && find.descendant(of: sf, matching: f, skipOffstage: false).evaluate().isNotEmpty;
            final vp = inSf ? t.getRect(sf) : screen;
            final li = lines ? _lineInfo(rp) : null;
            Rect? br;
            if (box != null && box.evaluate().isNotEmpty) br = t.getRect(box.first);
            return {
              'name': nm, 'kind': kind, 'present': true, 'rect': lt(r), 'visible': inside(r, screen) && inside(r, vp),
              'fontSize': rp.text.style?.fontSize, 'weight': rp.text.style?.fontWeight?.value,
              'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
              'didExceedMaxLines': rp.didExceedMaxLines, 'maxLines': rp.maxLines,
              if (li != null) 'lines': li.lines,
              if (li != null) 'sylBreaks': li.sylBreaks,
              if (br != null) 'boxH': r1(br.height),
            };
          }

          Finder? anc(Finder? f, bool Function(Widget w) p) =>
              f == null ? null : find.ancestor(of: f, matching: find.byWidgetPredicate(p, skipOffstage: false));

          List<Map<String, Object?>> measure() {
            final close = nth(rich((p) => p == '닫기'), -1);
            final back = glyph(Icons.arrow_back_ios, 0);
            final all = nth(rich((p) => p == '강남구 전체'), 0);
            final title = switch (sc) {
              'h-prov' => '시/도 선택',
              'h-city' => '경상북도 — 시/군/구 선택',
              'r-dist' => '강남구 — 동 선택',
              _ => '지역 선택',
            };
            final first = switch (sc) {
              'h-prov' => '서울특별시',
              'h-city' => '경산시',
              'r-city' => '수원시 영통구',
              'r-dist' => '역삼동',
              _ => '__none__',
            };
            final selected = switch (sc) { 'h-city' => '포항시', 'r-dist' => '삼성동', _ => '__none__' };
            return [
              info('제목', nth(rich((p) => p == title), 0), kind: 'title'),
              info('닫기', close, kind: 'aux', box: anc(close, (w) => w is ButtonStyleButton)),
              info('뒤로', back, kind: 'icon1', box: anc(back, (w) => w is IconButton)),
              info('꺾쇠', glyph(Icons.chevron_right, 0), kind: 'chev'),
              info('첫 항목', nth(rich((p) => p == first), 0), kind: 'value'),
              info('선택 항목', nth(rich((p) => p == selected), 0), kind: 'sel'),
              info('선택 체크', glyph(Icons.check, 0), kind: 'selIcon'),
              info('전체 버튼', all, kind: 'brandBtn', box: anc(all, (w) => w is ButtonStyleButton)),
              info('빈 제목', nth(rich((p) => p == '아직 등록된 지역 정보가 없습니다'), 0), kind: 'empty'),
              info('빈 부제', nth(rich((p) => p == '공고가 등록되면 지역이 자동으로 나타납니다'), 0), kind: 'empty'),
            ];
          }

          void afterChecks(List<Map<String, Object?>> xs, String at) {
            if (!after) return;
            for (final x in xs) {
              if (x['present'] != true || x['visible'] != true) continue;
              final k = x['kind'];
              final cst = x['contrast'];
              need(x['didExceedMaxLines'] != true, '$at 말줄임/잘림 $x');
              final sb = x['sylBreaks'];
              if (sb is int && k != 'body') need(sb == 0, '$at 음절 끊김 $x');
              final h = x['boxH'] as double?;
              switch (k) {
                case 'title' || 'value':
                  need(x['fg'] == '#21242D' && cst is double && cst >= 4.5, '$at 본문색 $x');
                  // [r1] 줄표가 한 줄에 홀로 남지 않는다
                  need(!((x['lines'] as List?) ?? const []).contains('—'), '$at 줄표 홀로 $x');
                case 'aux':
                  need(x['fg'] == '#60646F' && cst is double && cst >= 4.5 && (h ?? 0) >= 48, '$at 닫기 $x');
                case 'icon1':
                  need(x['fg'] == '#21242D' && (h ?? 0) >= 48, '$at 뒤로 $x');
                case 'chev':
                  need(x['fg'] == '#686C77', '$at 꺾쇠 $x');
                case 'sel':
                  need(x['fg'] == '#3859E8' && x['bg'] == '#EEF2FF' && cst is double && cst >= 4.5, '$at 선택 $x');
                case 'selIcon':
                  need(x['fg'] == '#3859E8', '$at 선택 체크 $x');
                case 'brandBtn':
                  need(x['fg'] == '#3859E8' && (h ?? 0) >= 48, '$at 전체 버튼 $x');
                case 'empty':
                  need(cst is double && cst >= 4.5, '$at 빈 상태 $x');
              }
            }
          }

          final shots = <Map<String, Object?>>[];
          Future<void> snap(String suffix) async {
            final xs = measure();
            afterChecks(xs, suffix.isEmpty ? '첫 화면' : suffix);
            // [v2] 고정 머리글이 시트를 차지하지 않는다 — 상세 시트의 스크롤 영역이 화면 높이의 60% 이상(v1 B320 은 약 34%).
            if (after && sc == '_none_' && suffix.isEmpty) {
              final vh = t.getRect(sfOf()!).height;
              need(vh >= c.h * 0.6, '스크롤 영역이 좁다 ${r1(vh)} / ${c.h}');
            }
            nPng++;
            await vqCapture(t, key, 'D266-$phase-${c.id}_$sc$suffix', conditions: {
              'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
            });
            final sf = sfOf();
            shots.add({'shot': suffix.isEmpty ? 'top' : suffix, 'texts': xs,
              'pixels': sf == null ? null : r1(t.state<ScrollableState>(sf).position.pixels)});
          }

          await snap('');
          var atEnd = true;
          if (sfOf() != null) {
            var k = 0;
            while (k < 30) { // [r1] 14 → 30(B320 after 는 세로 배치로 내용이 길다)
              final sf = sfOf()!;
              final vp = t.getRect(sf);
              final pos = t.state<ScrollableState>(sf).position;
              if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
              k++;
              nDrag++;
              await t.dragFrom(Offset(vp.left + 24, vp.top + vp.height * 0.6), Offset(0, -(vp.height * 0.5)));
              await frames(8);
              safe('drag $k 뒤');
              await snap('_d$k');
            }
            final pos = t.state<ScrollableState>(sfOf()!).position;
            atEnd = pos.pixels >= pos.maxScrollExtent - 0.5;
          }
          if (after) need(atEnd, '끝 도달 실패');
          _out('D266 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'overflow': overflow, 'atEnd': atEnd, 'shots': shots,
                'counts': {'pump': nPump, 'drag': nDrag, 'png': nPng, 'tap': nTap}})}');
        }
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D266-END ${jsonEncode({'pump': nPump, 'drag': nDrag, 'png': nPng, 'tap': nTap})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 5)));
}
