// [DU250 S070 나의 활동 시안 정렬 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU250_RUN=1 이고 DU250_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   standalone(MaterialApp home: MyActivityScreen) + BadgeProvider 대역(기본 배지 목록). 외부 채널 없음.
//   장면 3(all·tab('출근' 칩 tap 1회)·empty) × W360/1.0·B320/2.0.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/settings/trust_settings_model.dart';
import 'package:ALfit/providers/badge_provider.dart';
import 'package:ALfit/screens/user/my_activity_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';

class _Badges extends ChangeNotifier implements BadgeProvider {
  _Badges(this._list);
  final List<BadgeModel> _list;
  @override
  List<BadgeModel> get badges => _list;
}

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
  final phase = Platform.environment['DU250_PHASE'] ?? '';
  final run = Platform.environment['DU250_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  final all = BadgeModel.defaultBadges();
  final earnedIds = [for (final b in all) if (b.type != BadgeType.trustScore) b.id];
  const groups = ['근무 성취', '출근 기록', '특별 경험'];
  const chips = ['전체', '근무', '출근', '경험'];

  testWidgets('D250 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nTap = 0, nDrag = 0, nPng = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D250-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 800 && nTap <= 2 && nDrag <= 40 && nPng <= 40, '사용량 한도');
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
      final e = i < 0 ? els.last : els[i];
      return find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
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
        for (final sc in const ['all', 'tab', 'empty']) {
          cur = '${c.id} $sc';
          await t.pumpWidget(const SizedBox.shrink());
          await frames(1);
          safe('장면 종료');
          overflow.clear();
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          await t.pumpWidget(ChangeNotifierProvider<BadgeProvider>(
            create: (_) => _Badges(all),
            child: RepaintBoundary(
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
                home: MyActivityScreen(userBadgeIds: sc == 'empty' ? const [] : earnedIds),
              ),
            ),
          ));
          await frames(8);
          safe('첫 화면');
          if (sc == 'tab') {
            final chip = nth(rich((p) => p == '출근'), 0);
            need(chip != null, '출근 칩 없음');
            nTap++;
            await t.tap(chip!);
            await frames(6);
            safe('칩 tap 뒤');
          }
          Finder? listSf() {
            final f = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable));
            return f.evaluate().isEmpty ? null : nth(f, 0);
          }

          Map<String, Object?> textInfo(String nm, Finder? f) {
            if (f == null) return {'name': nm, 'present': false};
            final rp = t.renderObject<RenderParagraph>(f);
            final r = t.getRect(f);
            final fg = rp.text.style?.color;
            final bg = bgOf(f.evaluate().first);
            final scr = find.ancestor(of: f, matching: find.byType(Scrollable));
            final vp = scr.evaluate().isEmpty ? screen : t.getRect(scr.first);
            return {
              'name': nm, 'present': true, 'rect': lt(r), 'visible': inside(r, screen) && inside(r, vp),
              'fontSize': rp.text.style?.fontSize, 'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
            };
          }

          Map<String, Object?> shapeOf(Finder f) {
            String? radius, side, face;
            f.evaluate().first.visitAncestorElements((a) {
              final w = a.widget;
              if (w is Material && w.shape is RoundedRectangleBorder) {
                final s = w.shape! as RoundedRectangleBorder;
                radius = (s.borderRadius as BorderRadius).topLeft.x.toString();
                side = _hex(s.side.color);
                face = w.color == null ? null : _hex(w.color!);
                return false;
              }
              if (w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).borderRadius != null) {
                final d = w.decoration as BoxDecoration;
                radius = (d.borderRadius! as BorderRadius).topLeft.x.toString();
                side = d.border == null ? 'none' : _hex((d.border! as Border).top.color);
                face = d.color == null ? null : _hex(d.color!);
                return false;
              }
              return true;
            });
            return {'radius': radius, 'side': side, 'face': face};
          }

          Map<String, Object?> recv(String nm, Finder? f) {
            if (f == null) return {'name': nm, 'present': false};
            final r = t.getRect(f);
            final ro = t.renderObject(f);
            bool hitsAt(Offset p) {
              final h = HitTestResult();
              WidgetsBinding.instance.hitTestInView(h, p, t.view.viewId);
              return h.path.any((e) => e.target == ro);
            }

            final vis = inside(r, screen);
            final inner = r.deflate(2);
            return {
              'name': nm, 'present': true, 'rect': lt(r), 'w': r1(r.width), 'h': r1(r.height), 'visible': vis,
              'centerHit': vis && hitsAt(r.center),
              'edgeMidHits': vis && [inner.topCenter, inner.bottomCenter, inner.centerLeft, inner.centerRight].every(hitsAt),
              'ge48': r.width >= 48 - 0.01 && r.height >= 48 - 0.01,
            };
          }

          // 배지 행 글자 — 목록(ListView) 안의 RichText 중 묶음 제목이 아닌 것. 14 = 제목, 12 = 설명.
          List<Map<String, Object?>> badgeTexts() {
            final out = <Map<String, Object?>>[];
            final lv = find.byType(ListView);
            if (lv.evaluate().isEmpty) return out;
            final els = find.descendant(of: lv, matching: find.byType(RichText), skipOffstage: false).evaluate().toList();
            for (final e in els) {
              final f = find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
              final plain = TextLayout.plain(t.widget<RichText>(f).text.toPlainText());
              if (groups.contains(plain)) continue;
              final info = textInfo(plain, f);
              // [r1] Icon 글리프도 RichText 다(크기 20) — 14 = 제목, 12 = 설명, 그 밖 = 아이콘(그래픽 3:1 기준).
              final fs = info['fontSize'];
              out.add({...info, ...shapeOf(f), 'kind': fs == 14.0 ? 'title' : fs == 12.0 ? 'desc' : 'icon'});
            }
            return out;
          }

          List<Map<String, Object?>> measure() => [
                for (final g in groups) textInfo('묶음 $g', nth(rich((p) => p == g), 0)),
                for (final ch in chips) {...textInfo('칩 $ch', nth(rich((p) => p == ch), 0)),
                  'selected': (sc == 'tab' ? '출근' : '전체') == ch},
                textInfo('요약', nth(rich((p) => p.endsWith('배지를 획득했어요') || p == '아직 획득한 활동 배지가 없어요'), 0)),
                if (sc == 'empty') textInfo('빈 제목', nth(rich((p) => p == '아직 획득한 활동 배지가 없어요'), -1)),
              ];
          List<Map<String, Object?>> recvs() => [
                for (final ch in chips)
                  () {
                    final tf = nth(rich((p) => p == ch), 0);
                    if (tf == null) return {'name': '칩 $ch', 'present': false};
                    final gd = find.ancestor(of: tf, matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null));
                    return recv('칩 $ch', gd.evaluate().isEmpty ? null : nth(gd, 0));
                  }(),
              ];

          void afterChecks(List<Map<String, Object?>> xs, List<Map<String, Object?>> bs, List<Map<String, Object?>> vs, String at) {
            if (!after) return;
            for (final x in xs) {
              if (x['present'] != true || x['visible'] != true) continue;
              final n = x['name']! as String;
              final cst = x['contrast'];
              String? want;
              if (n.startsWith('묶음')) {
                want = '#21242D';
                need(x['fontSize'] == 16, '$at 묶음 제목 크기 $x');
              } else if (n.startsWith('칩')) {
                want = x['selected'] == true ? '#FFFFFF' : '#60646F';
                if (x['selected'] == true) need(x['bg'] == '#3859E8', '$at 선택 칩 바탕 $x');
              } else if (n == '빈 제목') {
                want = '#60646F';
              }
              need(cst is double && cst >= 4.5 && (want == null || x['fg'] == want), '$at 읽기색 $x');
            }
            for (final b in bs) {
              if (b['visible'] != true) continue;
              final cst = b['contrast'];
              if (b['kind'] == 'icon') {
                need(cst is double && cst >= 3.0, '$at 배지 아이콘(그래픽 3:1) $b');
              } else {
                need(b['fg'] == (b['kind'] == 'title' ? '#21242D' : '#60646F') && cst is double && cst >= 4.5, '$at 배지 글자 $b');
              }
              need(b['radius'] == '16.0' && b['side'] == '#EEEEEE' && b['face'] == '#FFFFFF', '$at 묶음 면 $b');
            }
            for (final v in vs) {
              if (v['present'] != true || v['visible'] != true) continue;
              need(v['ge48'] == true && v['centerHit'] == true && v['edgeMidHits'] == true, '$at 칩 수신자 $v');
            }
          }

          // [v2] 칩 줄의 흰 띠 폭 — v1 은 Wrap 이 내용 폭만 써서 띠가 칩 폭에서 끝났다(합성 열람으로 발견).
          Map<String, Object?> strip() {
            final tf = nth(rich((p) => p == '전체'), 0);
            if (tf == null) return {'present': false};
            final cb = find.ancestor(of: tf, matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == Colors.white));
            if (cb.evaluate().isEmpty) return {'present': false};
            return {'present': true, 'w': r1(t.getRect(cb.first).width)};
          }

          final shots = <Map<String, Object?>>[];
          Future<void> snap(String suffix) async {
            final xs = measure();
            final bs = badgeTexts();
            final vs = recvs();
            final st = strip();
            afterChecks(xs, bs, vs, suffix.isEmpty ? '첫 화면' : suffix);
            if (after) need(st['present'] == true && st['w'] == c.w, '칩 띠 폭 $st');
            nPng++;
            await vqCapture(t, key, 'D250-$phase-${c.id}_$sc$suffix', conditions: {
              'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
            });
            final sf = listSf();
            shots.add({'shot': suffix.isEmpty ? 'top' : suffix, 'texts': xs, 'badges': bs, 'recv': vs, 'strip': st,
              'pixels': sf == null ? null : r1(t.state<ScrollableState>(sf).position.pixels)});
          }

          await snap('');
          var atEnd = true;
          if (listSf() != null) {
            var k = 0;
            while (k < 14) { // [r2] B320 에서 칩 줄이 두 줄이 되어 목록이 길어졌다 — 8회로 끝에 닿지 않았다
              final sf = listSf()!;
              final vp = t.getRect(sf);
              final pos = t.state<ScrollableState>(sf).position;
              if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
              k++;
              nDrag++;
              await t.dragFrom(Offset(vp.left + 24, vp.bottom - 12), Offset(0, -(vp.height * 0.7)));
              await frames(6);
              safe('drag $k 뒤');
              await snap('_d$k');
            }
            final pos = t.state<ScrollableState>(listSf()!).position;
            atEnd = pos.pixels >= pos.maxScrollExtent - 0.5;
          }
          final seen = <String>{};
          for (final s in shots) {
            for (final x in (s['texts']! as List).cast<Map<String, Object?>>()) {
              if (x['visible'] == true) seen.add(x['name']! as String);
            }
          }
          final wantSeen = sc == 'empty' ? <String>[] : sc == 'tab' ? ['묶음 출근 기록'] : [for (final g in groups) '묶음 $g'];
          final missed = [for (final w in wantSeen) if (!seen.contains(w)) w];
          if (after) need(atEnd && missed.isEmpty, '끝 도달/관측 누락 atEnd=$atEnd missed=$missed');
          _out('D250 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'overflow': overflow, 'atEnd': atEnd, 'missed': missed,
                'shots': shots, 'counts': {'pump': nPump, 'tap': nTap, 'drag': nDrag, 'png': nPng}})}');
        }
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D250-END ${jsonEncode({'pump': nPump, 'tap': nTap, 'drag': nDrag, 'png': nPng})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 4)));
}
