// ignore_for_file: depend_on_referenced_packages
// [DU287 두 공용 확인창 셸 채움·아이콘 색 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU287_RUN=1 이고 DU287_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   색 표: lib 호출부가 실제로 넘기는 색마다 DialogHelper·StyledDialog 대화를 하나씩 열어 채움 버튼 글·머리 아이콘 대비를 잰다.
//   조건 W360/1.0·B320/2.0. 누르는 것은 없다(Navigator.pop 으로 닫는다).
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
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';

import 'support/du1_vq_capture.dart';

/// 장면: (id, 셸, 넘기는 색 이름, 채움 버튼 글, 의미색 여부(단언 대상))
typedef _Sc = ({String id, String shell, String? color, String label, bool semantic});

const _colors = <String, Color>{
  'error': AppColors.error,
  'warning': AppColors.warning,
  'success': AppColors.success,
  'info': AppColors.info,
  'errorDark': AppColors.errorDark,
  'successDark': AppColors.successDark,
  'infoDark': AppColors.infoDark,
  'brand': AppColors.brand,
  'successMedium': AppColors.successMedium,
  'purple': AppColors.purple,
  'teal': AppColors.teal,
  'amber': AppColors.amber,
  'grey400': AppColors.grey400,
  'grey500': AppColors.grey500,
};

/// 대응표(after 에서 바탕이 이 짝이어야 한다)
const _pair = {'error': '#B42318', 'warning': '#946200', 'success': '#166534', 'info': '#1976D2'};

const List<_Sc> _scenes = [
  (id: 'hc_error', shell: 'confirm', color: 'error', label: '진행', semantic: true),
  (id: 'hc_warning', shell: 'confirm', color: 'warning', label: '진행', semantic: true),
  (id: 'hc_success', shell: 'confirm', color: 'success', label: '진행', semantic: true),
  (id: 'hc_info', shell: 'confirm', color: 'info', label: '진행', semantic: true),
  (id: 'hc_errorDark', shell: 'confirm', color: 'errorDark', label: '진행', semantic: true),
  (id: 'hc_successDark', shell: 'confirm', color: 'successDark', label: '진행', semantic: true),
  (id: 'hc_infoDark', shell: 'confirm', color: 'infoDark', label: '진행', semantic: true),
  (id: 'hc_brand', shell: 'confirm', color: 'brand', label: '진행', semantic: true),
  (id: 'hc_none', shell: 'confirm', color: null, label: '진행', semantic: true),
  (id: 'hp_danger', shell: 'danger', color: 'error', label: '삭제', semantic: true),
  (id: 'hp_cancelPreset', shell: 'cancelPreset', color: 'warning', label: '취소하기', semantic: true),
  (id: 'hp_logout', shell: 'logout', color: 'error', label: '로그아웃', semantic: true),
  (id: 'hp_decline', shell: 'decline', color: 'warning', label: '초대 거절', semantic: true),
  (id: 'hp_error', shell: 'error', color: 'error', label: '확인', semantic: true),
  (id: 'hp_success', shell: 'success', color: 'success', label: '확인', semantic: true),
  (id: 'hp_info', shell: 'info', color: 'info', label: '확인', semantic: true),
  (id: 'hp_alertWarn', shell: 'alert', color: 'warning', label: '확인', semantic: true),
  (id: 'sd_error', shell: 'styled', color: 'error', label: '진행', semantic: true),
  (id: 'sd_warning', shell: 'styled', color: 'warning', label: '진행', semantic: true),
  (id: 'sd_success', shell: 'styled', color: 'success', label: '진행', semantic: true),
  (id: 'sd_info', shell: 'styled', color: 'info', label: '진행', semantic: true),
  (id: 'sd_errorDark', shell: 'styled', color: 'errorDark', label: '진행', semantic: true),
  (id: 'sd_none', shell: 'styled', color: null, label: '진행', semantic: true),
  (id: 'sd_dangerPreset', shell: 'styledDanger', color: 'errorDark', label: '삭제', semantic: true),
  (id: 'sd_successMedium', shell: 'styled', color: 'successMedium', label: '진행', semantic: false),
  (id: 'sd_purple', shell: 'styled', color: 'purple', label: '진행', semantic: false),
  (id: 'sd_teal', shell: 'styled', color: 'teal', label: '진행', semantic: false),
  (id: 'sd_amber', shell: 'styled', color: 'amber', label: '진행', semantic: false),
  (id: 'sd_grey400', shell: 'styled', color: 'grey400', label: '진행', semantic: false),
  (id: 'sd_grey500', shell: 'styled', color: 'grey500', label: '진행', semantic: false),
];

const _shots = {'hc_warning', 'hp_error', 'hp_cancelPreset', 'sd_warning', 'sd_success'};
const _title = '색 확인';
const _msg = '색 대비를 잰다.';

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

void _open(BuildContext ctx, _Sc s) {
  final c = s.color == null ? null : _colors[s.color]!;
  switch (s.shell) {
    case 'confirm':
      unawaited(DialogHelper.showConfirm(ctx, title: _title, message: _msg, confirmText: s.label, confirmColor: c, iconColor: c));
    case 'danger':
      unawaited(DialogHelper.showDangerConfirm(ctx, title: _title, message: _msg));
    case 'cancelPreset':
      unawaited(DialogHelper.showCancelConfirm(ctx, title: _title, message: _msg));
    case 'logout':
      unawaited(DialogHelper.showLogoutConfirm(ctx));
    case 'decline':
      unawaited(DialogHelper.showDeclineInviteConfirm(ctx));
    case 'error':
      unawaited(DialogHelper.showError(ctx, title: _title, message: _msg));
    case 'success':
      unawaited(DialogHelper.showSuccess(ctx, title: _title, message: _msg));
    case 'info':
      unawaited(DialogHelper.showInfo(ctx, title: _title, message: _msg));
    case 'alert':
      unawaited(DialogHelper.showAlert(ctx, title: _title, message: _msg, iconColor: c));
    case 'styled':
    case 'styledDanger':
      unawaited(showDialog<void>(
        context: ctx,
        builder: (_) => StyledDialog(
          title: _title,
          icon: Icons.info_outline,
          headerColor: c,
          content: const Text(_msg),
          actions: [
            StyledDialogButton.cancel(onPressed: () {}),
            if (s.shell == 'styledDanger')
              StyledDialogButton.danger(text: s.label, onPressed: () {})
            else
              StyledDialogButton.primary(text: s.label, onPressed: () {}, backgroundColor: c),
          ],
        ),
      ));
    default:
      throw StateError(s.shell);
  }
}

void main() {
  final phase = Platform.environment['DU287_PHASE'] ?? '';
  final run = Platform.environment['DU287_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  testWidgets('D287 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nPng = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D287-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 1500 && nPng <= 20, '사용량 한도');
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
          // [v1 TB 뒤 보정] Container 는 안에 DecoratedBox 를 만든다 — Container 도 세면 10% 면이 두 번 겹친다(v0 아이콘 바탕 19%).
          c = (w.decoration as BoxDecoration).color;
        } else if (w is Material && w.type != MaterialType.transparency) {
          c = w.color ?? Theme.of(a).canvasColor;
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
    final rows = <Map<String, Object?>>[];
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        cur = c.id;
        await t.pumpWidget(const SizedBox.shrink());
        await frames(1);
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        t.platformDispatcher.textScaleFactorTestValue = c.s;
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
        for (final s in _scenes) {
          cur = '${c.id} ${s.id}';
          _open(appCtx!, s);
          await frames(8);
          safe('열림');
          final host = find.byType(Dialog);
          need(host.evaluate().length == 1, '대화가 열리지 않았다');
          Finder fe(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
          final labels = find
              .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
              .evaluate()
              .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText()) == s.label)
              .toList()
            ..sort((a, b) => t.getRect(fe(a)).top.compareTo(t.getRect(fe(b)).top));
          need(labels.isNotEmpty, '채움 버튼 글 없음');
          // 제목과 같은 글(로그아웃·초대 거절)이 있으면 가장 아래가 버튼이다
          final lab = labels.last;
          final rp = t.renderObject<RenderParagraph>(fe(lab));
          final fg = rp.text.style!.color!;
          final bg = bgOf(lab);
          final icons = find.descendant(of: host, matching: find.byType(Icon), skipOffstage: false).evaluate().toList()
            ..sort((a, b) => t.getRect(fe(a)).top.compareTo(t.getRect(fe(b)).top));
          final ic = icons.first;
          final icColor = (ic.widget as Icon).color!;
          final icBg = bgOf(ic);
          final row = {
            'phase': phase, 'cond': c.id, 'id': s.id, 'shell': s.shell, 'color': s.color, 'semantic': s.semantic,
            'btnFg': _hex(fg), 'btnBg': _hex(bg), 'btnContrast': double.parse(_contrast(fg, bg).toStringAsFixed(2)),
            'iconFg': _hex(icColor), 'iconBg': _hex(icBg), 'iconContrast': double.parse(_contrast(icColor, icBg).toStringAsFixed(2)),
          };
          rows.add(row);
          _out('D287 ${jsonEncode(row)}');
          if (after) {
            if (s.semantic) {
              need((row['btnContrast'] as double) >= 4.5, '채움 버튼 글 대비 $row');
              need((row['iconContrast'] as double) >= 3.0, '머리 아이콘 대비 $row');
              final want = _pair[s.color];
              if (want != null) need(row['btnBg'] == want && row['iconFg'] == want, '대응표 짝 아님 $row');
            } else {
              need(row['btnBg'] == _hex(_colors[s.color]!), '대응표 밖 색이 바뀌었다 $row');
            }
          }
          if (c.id == 'W360' && _shots.contains(s.id)) {
            nPng++;
            await vqCapture(t, key, 'D287-$phase-${c.id}_${s.id}', conditions: {'phase': phase, 'scene': s.id, 'viewport': '360x780', 'textScaleFactor(기기)': c.s});
          }
          Navigator.of(t.element(host)).pop();
          await frames(8);
          safe('닫힘');
          need(find.byType(Dialog).evaluate().isEmpty, '대화가 닫히지 않았다');
        }
      }
      if (after) need(rows.length == _scenes.length * 2, '장면 수 ${rows.length}');
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D287-END ${jsonEncode({'pump': nPump, 'png': nPng, 'rows': rows.length})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 5)));
}
