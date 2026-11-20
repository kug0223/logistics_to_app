// ignore_for_file: depend_on_referenced_packages
// [DU299 알림 닫기 '확인' 버튼 brand 분리(DU-O071, 후속299) baseline/after] 감사298 다음 셀.
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU299_RUN=1 이고 DU299_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   공개 helper 4개(showError·showSuccess·showInfo·warning 아이콘 showAlert)로 실제로 열고, 버튼을 실제 tap 해 닫는다.
//   조건 W360×780/1.0·B320×640/2.0. baseline 은 의미색 버튼을 계측만 한다(사전 지정 차이). after 는 brand 를 단언한다.
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
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/styled_dialog.dart' show AppDialogColors;

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

/// 네트워크 guard — HTTP 클라이언트가 만들어지면 센다(만들어지면 실패로 드러나게 던진다).
class _NoNet extends HttpOverrides {
  int created = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    created++;
    throw StateError('DU299 network guard');
  }
}

const _host = 'DU299-HOST';
const _samples = [
  (id: 'ERR', title: '오류', msg: '사업장 정보를 찾을 수 없습니다.', icon: Icons.error_outline, sem: AppColors.error),
  (id: 'SUC', title: '완료', msg: '변경 내용을 저장했습니다.', icon: Icons.check_circle_outline, sem: AppColors.success),
  (id: 'INF', title: '알림', msg: '시간이 지난 업무는 수정할 수 없습니다.', icon: Icons.info_outline, sem: AppColors.info),
  (
    id: 'WRN',
    title: '이체 완료 처리를 하지 않았습니다',
    msg: '이 급여 건은 이체할 수 없는 상태입니다. 목록에서 상태를 확인해주세요.',
    icon: Icons.info_outline,
    sem: AppColors.warning
  ),
];

Future<void> _open(BuildContext ctx, String id, String title, String msg) {
  switch (id) {
    case 'ERR':
      return DialogHelper.showError(ctx, message: msg);
    case 'SUC':
      return DialogHelper.showSuccess(ctx, message: msg);
    case 'INF':
      return DialogHelper.showInfo(ctx, title: title, message: msg);
    default:
      return DialogHelper.showAlert(ctx, title: title, message: msg, icon: Icons.info_outline, iconColor: AppColors.warning);
  }
}

void main() {
  final phase = Platform.environment['DU299_PHASE'] ?? '';
  final run = Platform.environment['DU299_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);
  final wj = String.fromCharCode(0x2060);
  final zw = String.fromCharCode(0x200B);

  testWidgets('D299 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final prevHttp = HttpOverrides.current;
    final net = _NoNet();
    HttpOverrides.global = net;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nMount = 0, nPng = 0, nTap = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D299-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    void budget() => need(nPump + nMount <= 800 && nPng <= 8 && nTap <= 8, '한도 pump+mount ${nPump + nMount} png $nPng tap $nTap');

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        budget();
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> mount(Widget w) async {
      nMount++;
      budget();
      await t.pumpWidget(w);
    }

    void safe(String at) {
      final ex = t.takeException();
      need(ex == null, '$at 예외: $ex');
      need(errors.isEmpty, '$at 예외/overflow: $errors');
    }

    double r1(double v) => double.parse(v.toStringAsFixed(1));
    double r2(double v) => double.parse(v.toStringAsFixed(2));
    List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom].map(r1).toList();
    Finder fe(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
    bool inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

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
    final brand = RoleTheme.businessAdminTheme.primaryColor;
    final rows = <Map<String, Object?>>[];
    final visited = <String>[];
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        for (final s in _samples) {
          cur = '${c.id}_${s.id}';
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          await mount(const SizedBox.shrink());
          await frames(1);
          safe('비움');
          BuildContext? appCtx;
          await mount(RepaintBoundary(
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
                return const Center(child: Text(_host));
              })),
            ),
          ));
          await frames(2);
          need(appCtx != null, '앱 문맥 없음');
          var closed = 0;
          unawaited(_open(appCtx!, s.id, s.title, s.msg).then((_) => closed++));
          await frames(8);
          safe('열림');
          final dlg = find.byType(Dialog);
          need(dlg.evaluate().length == 1, '대화 수 ${dlg.evaluate().length}');
          final dlgRect = t.getRect(dlg);
          // 머리 의미 아이콘·면
          final iconF = find.descendant(of: dlg, matching: find.byWidgetPredicate((w) => w is Icon && w.icon == s.icon));
          need(iconF.evaluate().length == 1, '머리 아이콘 수 ${iconF.evaluate().length}');
          final iconW = t.widget<Icon>(iconF);
          final boxEl = nearest(iconF.evaluate().first, (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color != null);
          final boxColor = boxEl == null ? null : ((boxEl.widget as Container).decoration as BoxDecoration).color;
          // 확인 버튼(대화 안 누름 receiver 는 이것 하나여야 한다)
          final inks = find.descendant(of: dlg, matching: find.byType(InkWell));
          need(inks.evaluate().length == 1, '누름 receiver 수 ${inks.evaluate().length}');
          final inkRect = t.getRect(inks);
          final labelEls = find.descendant(of: inks, matching: find.byType(RichText)).evaluate().toList();
          need(labelEls.length == 1, '버튼 글 수 ${labelEls.length}');
          final labelRp = t.renderObject<RenderParagraph>(fe(labelEls.first));
          final labelPlain = TextLayout.plain(labelRp.text.toPlainText());
          final labelFg = labelRp.text.style?.color;
          final matEl = nearest(inks.evaluate().first, (w) => w is Material);
          final fill = matEl == null ? null : (matEl.widget as Material).color;
          final labelRect = t.getRect(fe(labelEls.first));
          final hit = inks.hitTestable().evaluate().length == 1;
          // 제목·본문(아이콘·버튼 밖 글)
          final texts = <Map<String, Object?>>[];
          for (final e in find.descendant(of: dlg, matching: find.byType(RichText)).evaluate()) {
            if (nearest(e, (w) => w is Icon) != null || nearest(e, (w) => w is InkWell) != null) continue;
            final rp = t.renderObject<RenderParagraph>(fe(e));
            final r = t.getRect(fe(e));
            texts.add({'text': TextLayout.plain(rp.text.toPlainText()), 'rect': lt(r), 'onScreen': inside(r, screen) && inside(r, dlgRect),
              'didExceedMaxLines': rp.didExceedMaxLines});
          }
          final titleOk = texts.where((x) => x['text'] == s.title).length == 1;
          final bodyOk = texts.where((x) => x['text'] == s.msg).length == 1;
          need(titleOk && bodyOk, '제목/본문 원문 ${texts.map((x) => x['text']).toList()}');
          var semBad = 0, semChecked = 0;
          for (final e in find.descendant(of: dlg, matching: find.byType(Text)).evaluate()) {
            final w = e.widget as Text;
            final d = w.data ?? w.textSpan?.toPlainText() ?? '';
            if (!d.contains(wj) && !d.contains(zw)) continue;
            semChecked++;
            final plain = TextLayout.plain(d);
            final semEl = nearest(e, (x) => x is Semantics && x.properties.label != null);
            final ok = w.semanticsLabel == plain || (semEl != null && (semEl.widget as Semantics).properties.label == plain);
            if (!ok) semBad++;
          }
          final row = <String, Object?>{
            'phase': phase, 'cond': c.id, 'sample': s.id,
            'icon': {'fg': iconW.color == null ? null : _hex(iconW.color!), 'box': boxColor == null ? null : _hex(Color.alphaBlend(boxColor, Colors.white)),
              'boxAlpha': boxColor == null ? null : r2(boxColor.a)},
            'button': {'label': labelPlain, 'fill': fill == null ? null : _hex(fill), 'fg': labelFg == null ? null : _hex(labelFg),
              'contrast': (fill == null || labelFg == null) ? null : r2(_contrast(labelFg, fill)), 'rect': lt(inkRect), 'h': r1(inkRect.height),
              'hitCenter': hit, 'onScreen': inside(inkRect, screen) && inside(labelRect, inkRect)},
            'texts': texts, 'semChecked': semChecked, 'semBad': semBad, 'dialog': lt(dlgRect),
          };
          nPng++;
          budget();
          await vqCapture(t, key, 'D299-$phase-${c.id}_${s.id}',
              conditions: {'phase': phase, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s, 'sample': s.id});
          // 실제 tap 으로 닫는다(Navigator.pop 대신 호출 없음).
          nTap++;
          budget();
          await t.tap(inks);
          await frames(8);
          safe('닫힘');
          row['afterTap'] = {'dialogs': find.byType(Dialog).evaluate().length, 'closed': closed, 'host': find.text(_host).evaluate().length};
          if (after) {
            need(fill != null && fill == brand && AppDialogColors.readableFill(brand) == brand, '버튼 채움 brand 아님 ${row['button']}');
            need(labelFg != null && fill != null && _contrast(labelFg, fill) >= 4.5, '버튼 글 대비 ${row['button']}');
            need(iconW.color == AppDialogColors.readableFill(s.sem), '머리 아이콘 색 ${row['icon']}');
            need(boxColor != null && boxColor.toARGB32() == AppDialogColors.readableFill(s.sem).withValues(alpha: 0.10).toARGB32(), '머리 면 ${row['icon']}');
            need(labelPlain == '확인', '버튼 이름 $labelPlain');
            need(inkRect.height >= 52 && hit, 'receiver ${row['button']}');
            need(row['button'] is Map && (row['button'] as Map)['onScreen'] == true, '버튼 화면 밖 ${row['button']}');
            need(texts.every((x) => x['onScreen'] == true && x['didExceedMaxLines'] != true), '글 화면 밖/말줄임 $texts');
            need(semBad == 0, '읽기 이름 원문 아님 $semBad');
            need(find.byType(Dialog).evaluate().isEmpty && closed == 1 && find.text(_host).evaluate().length == 1, '닫힘 ${row['afterTap']}');
          }
          visited.add(cur);
          rows.add(row);
          _out('D299 ${jsonEncode(row)}');
        }
      }
      need(visited.length == 8, '방문 표본 ${visited.length}');
      need(net.created == 0, 'HTTP 생성 ${net.created}');
      Map<String, int>? statics;
      if (after) {
        final src = File('lib/utils/dialog_helper.dart').readAsStringSync().replaceAll(String.fromCharCode(13), '');
        int cnt(String s) => s.allMatches(src).length;
        statics = {
          'ac1': cnt('_confirmBtn(dialogContext, () => Navigator.pop(dialogContext), buttonText, theme.primaryColor),'),
          'confirmPath': cnt('_confirmBtn(dialogContext, () => Navigator.pop(dialogContext, true), confirmText, accentColor),'),
          'headAccent': cnt('accentColor: accentColor,'),
          'headReadable': cnt('final accent = AppDialogColors.readableFill(accentColor);'),
        };
        need(statics['ac1'] == 1 && statics['confirmPath'] == 1 && statics['headAccent'] == 3 && statics['headReadable'] == 1, '정적 계약 $statics');
      }
      await mount(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D299-END ${jsonEncode({'pump': nPump, 'mount': nMount, 'png': nPng, 'tap': nTap, 'drag': 0, 'visited': visited, 'http': net.created, 'statics': statics})}');
    } finally {
      FlutterError.onError = prevOnError;
      HttpOverrides.global = prevHttp;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 3)));
}
