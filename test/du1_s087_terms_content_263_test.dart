// ignore_for_file: depend_on_referenced_packages
// [DU263 S087 약관 읽기 — 본문 표시(after 만)] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   공용 TermsReadOnlyScreen 은 DU263 에서 생긴 위젯이라 교정 전 캡처가 없다 — after 만 돈다.
//   DU263_RUN=1 이고 DU263_PHASE=after 일 때만 실행한다(기본 skip). 긴 약관 본문 + 버전, W360/1.0·B320/2.0, 끝까지 drag.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/widgets/common/terms_read_only_screen.dart';
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
  final phase = Platform.environment['DU263_PHASE'] ?? '';
  final run = Platform.environment['DU263_RUN'] == '1' && phase == 'after';
  final nl = String.fromCharCode(10);
  final body = List.generate(
      12,
      (i) => '제${i + 1}조(목적과 적용 범위) 이 약관은 ALfit 이 제공하는 단기·장기 근무 연결 서비스의 이용 조건과 절차, '
          '회사와 회원의 권리·의무 및 책임 사항을 정합니다. 회원은 근무 지원·계약·급여 확인 기능을 이용할 수 있습니다.').join(nl + nl);

  testWidgets('D263C after', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var cur = '(시작)';
    var nPump = 0, nDrag = 0;
    Never stop(String why) {
      _out('D263C-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 600 && nDrag <= 40, '사용량 한도');
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    void safe(String at) {
      final ex = t.takeException();
      need(ex == null, '$at 예외: $ex');
      need(errors.isEmpty, '$at 예외/overflow: $errors');
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
        cur = c.id;
        await t.pumpWidget(const SizedBox.shrink());
        await frames(1);
        safe('장면 종료');
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
            home: TermsReadOnlyScreen(title: '서비스 이용약관', content: body, version: '2026.11.01'),
          ),
        ));
        await frames(8);
        safe('첫 화면');
        final verF = find.byWidgetPredicate(
            (w) => w is RichText && TextLayout.plain(w.text.toPlainText()) == '버전 2026.11.01', skipOffstage: false);
        need(verF.evaluate().isNotEmpty, '버전 줄 없음');
        final verRp = t.renderObject<RenderParagraph>(verF.first);
        final verFg = verRp.text.style!.color!;
        final verBg = bgOf(verF.evaluate().first);
        final sel = find.byType(SelectableText);
        need(sel.evaluate().length == 1, '본문 SelectableText 가 하나가 아니다');
        final st = t.widget<SelectableText>(sel.first).style!;
        final selBg = bgOf(sel.evaluate().first);
        String? radius, side, face;
        sel.evaluate().first.visitAncestorElements((a) {
          final w = a.widget;
          if (w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).borderRadius != null) {
            final d = w.decoration as BoxDecoration;
            radius = (d.borderRadius! as BorderRadius).topLeft.x.toString();
            side = d.border == null ? 'none' : _hex((d.border! as Border).top.color);
            face = d.color == null ? null : _hex(d.color!);
            return false;
          }
          return true;
        });
        final r = {
          'cond': c.id,
          'version': {'fg': _hex(verFg), 'bg': _hex(verBg), 'contrast': double.parse(_contrast(verFg, verBg).toStringAsFixed(2)),
            'fontSize': verRp.text.style?.fontSize},
          'body': {'fg': _hex(st.color!), 'bg': _hex(selBg), 'contrast': double.parse(_contrast(st.color!, selBg).toStringAsFixed(2)),
            'fontSize': st.fontSize, 'height': st.height},
          'card': {'radius': radius, 'side': side, 'face': face},
        };
        need(r['card'].toString() == {'radius': '16.0', 'side': '#EEEEEE', 'face': '#FFFFFF'}.toString(), '카드 면 $r');
        need(_hex(st.color!) == '#21242D' && _contrast(st.color!, selBg) >= 4.5, '본문 글자 $r');
        need(_hex(verFg) == '#60646F' && _contrast(verFg, verBg) >= 4.5, '버전 글자 $r');
        await vqCapture(t, key, 'D263C-after-${c.id}_content', conditions: {
          'phase': 'after', 'scene': 'content', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
        });
        // 끝까지 끈다(넘침·예외 확인).
        final sf = find.descendant(of: find.byType(TermsReadOnlyScreen), matching: find.byType(Scrollable)).first;
        var k = 0;
        while (k < 30) {
          final pos = t.state<ScrollableState>(sf).position;
          if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
          k++;
          nDrag++;
          final vp = t.getRect(sf);
          await t.dragFrom(Offset(vp.left + 24, vp.top + vp.height * 0.6), Offset(0, -(vp.height * 0.5)));
          await frames(6);
          safe('drag $k 뒤');
        }
        final pos = t.state<ScrollableState>(sf).position;
        need(pos.pixels >= pos.maxScrollExtent - 0.5, '끝 도달 실패');
        await vqCapture(t, key, 'D263C-after-${c.id}_content_end', conditions: {
          'phase': 'after', 'scene': 'content-end', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
        });
        _out('D263C ${jsonEncode({...r, 'drags': k})}');
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D263C-END');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 4)));
}
