// ignore_for_file: depend_on_referenced_packages
// [DU309 공용 확인창 아이콘 · 버튼 색 분리 before/after] 11-15 자체검토 허브(reports/DU_self_review_hub_2026-11-15.md).
//   같은 시험을 교정 전(before) · 후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU309_RUN=1 이고 DU309_PHASE 가 before 또는 after 일 때만 실행한다(기본 skip).
//   장면: 감사309 approved 6파일이 고친 호출부 9곳의 실제 인자(phase 별 — before 는 base, after 는 후보 호출부 인자 그대로 복사)
//     + helper 프리셋 2(로그아웃 · 지원 취소) + 아이콘 색만 넘기는 일반 호출 1. DialogHelper 를 직접 연다(화면 진입 경로는 관측 밖).
//   after 단언: 버튼 바탕 = 행동 결과(일반 진행 brand · 퇴사 승인 errorDark), 머리 아이콘 = 의미색(지정 시) 또는 brand,
//     버튼 글 대비 ≥4.5 · 아이콘 대비 ≥3.0. before 는 같은 측정을 기록만 한다. 조건 W360/1.0 · B320/2.0, PNG 는 W360 만.
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

import 'support/du1_vq_capture.dart';

/// 장면 인자(phase 별). kind: confirm | input | logout | cancelPreset
typedef _Args = ({String kind, String label, Color? confirm, Color? iconColor, IconData? icon});
typedef _Sc = ({String id, String where, _Args before, _Args after, Color wantBtn, Color wantIcon});

const _brand = AppColors.brand;
final List<_Sc> _scenes = [
  (id: 'resign_approve', where: 'resign_request_management_dialog:396',
    before: (kind: 'confirm', label: '승인', confirm: AppColors.success, iconColor: null, icon: null),
    after: (kind: 'confirm', label: '승인', confirm: AppColors.errorDark, iconColor: null, icon: null),
    wantBtn: AppColors.errorDark, wantIcon: AppColors.errorDark),
  (id: 'work_close', where: 'work_detail_management_dialog:547',
    before: (kind: 'confirm', label: '마감', confirm: AppColors.warning, iconColor: null, icon: null),
    after: (kind: 'confirm', label: '마감', confirm: null, iconColor: AppColors.warning, icon: null),
    wantBtn: _brand, wantIcon: AppColors.warning),
  (id: 'work_reopen', where: 'work_detail_management_dialog:613',
    before: (kind: 'confirm', label: '재오픈', confirm: AppColors.success, iconColor: null, icon: null),
    after: (kind: 'confirm', label: '재오픈', confirm: null, iconColor: null, icon: null),
    wantBtn: _brand, wantIcon: _brand),
  (id: 'urgent_end', where: 'work_detail_management_dialog:674',
    before: (kind: 'confirm', label: '종료', confirm: AppColors.warning, iconColor: null, icon: null),
    after: (kind: 'confirm', label: '종료', confirm: null, iconColor: AppColors.warning, icon: null),
    wantBtn: _brand, wantIcon: AppColors.warning),
  (id: 'id_view_approve', where: 'my_requests_dialog:626',
    before: (kind: 'confirm', label: '승인', confirm: AppColors.successDark, iconColor: AppColors.infoDark, icon: Icons.badge),
    after: (kind: 'confirm', label: '승인', confirm: null, iconColor: null, icon: Icons.badge),
    wantBtn: _brand, wantIcon: _brand),
  (id: 'term_reject_input', where: 'my_requests_dialog:743',
    before: (kind: 'input', label: '거절', confirm: AppColors.infoDark, iconColor: AppColors.errorDark, icon: Icons.cancel),
    after: (kind: 'input', label: '거절', confirm: null, iconColor: null, icon: Icons.cancel),
    wantBtn: _brand, wantIcon: _brand),
  (id: 'bulk_extend', where: 'fixed_worker_management_dialog:1494',
    before: (kind: 'confirm', label: '일괄 연장', confirm: AppColors.success, iconColor: AppColors.success, icon: Icons.autorenew),
    after: (kind: 'confirm', label: '일괄 연장', confirm: null, iconColor: AppColors.success, icon: Icons.autorenew),
    wantBtn: _brand, wantIcon: AppColors.success),
  (id: 'term_request_cancel', where: 'fixed_worker_management_dialog:2813',
    before: (kind: 'confirm', label: '취소하기', confirm: AppColors.warning, iconColor: null, icon: null),
    after: (kind: 'confirm', label: '취소하기', confirm: null, iconColor: null, icon: null),
    wantBtn: _brand, wantIcon: _brand),
  (id: 'capacity_save', where: 'create_edit_work_detail_dialog:2599',
    before: (kind: 'confirm', label: '저장', confirm: AppColors.warning, iconColor: AppColors.warning, icon: Icons.warning_amber),
    after: (kind: 'confirm', label: '저장', confirm: null, iconColor: AppColors.warning, icon: Icons.warning_amber),
    wantBtn: _brand, wantIcon: AppColors.warning),
  (id: 'logout_preset', where: 'dialog_helper.showLogoutConfirm',
    before: (kind: 'logout', label: '로그아웃', confirm: null, iconColor: null, icon: null),
    after: (kind: 'logout', label: '로그아웃', confirm: null, iconColor: null, icon: null),
    wantBtn: _brand, wantIcon: _brand),
  (id: 'apply_cancel_preset', where: 'dialog_helper.showCancelConfirm',
    before: (kind: 'cancelPreset', label: '취소하기', confirm: null, iconColor: null, icon: null),
    after: (kind: 'cancelPreset', label: '취소하기', confirm: null, iconColor: null, icon: null),
    wantBtn: _brand, wantIcon: AppColors.warning),
  (id: 'icon_only_generic', where: '일반 호출(iconColor 만) — helper 분리 효과',
    before: (kind: 'confirm', label: '설정으로 이동', confirm: null, iconColor: AppColors.warning, icon: Icons.warning_amber),
    after: (kind: 'confirm', label: '설정으로 이동', confirm: null, iconColor: AppColors.warning, icon: Icons.warning_amber),
    wantBtn: _brand, wantIcon: AppColors.warning),
];
const _title = '색 확인';
const _msg = '확인창 색을 잰다.';

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

/// [r1] 공용 셸은 의미 원색을 읽히는 짙은 짝으로 그린다(DU287 대응표: warning → #946200 · success → #166534 · error → #B42318 · info → #1976D2).
///   t0 은 기대값을 원색(#FF9800)으로 적어 after 첫 장면에서 멈췄다(실제 #946200 · 대비 4.59) — 기대값만 셸 표시색으로 고친다.
const _shownPair = {'#FF9800': '#946200', '#4CAF50': '#166534', '#F44336': '#B42318', '#2196F3': '#1976D2'};
String _shown(Color c) => _shownPair[_hex(c)] ?? _hex(c);

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

void _open(BuildContext ctx, _Args a) {
  switch (a.kind) {
    case 'confirm':
      unawaited(DialogHelper.showConfirm(ctx, title: _title, message: _msg, confirmText: a.label,
          confirmColor: a.confirm, icon: a.icon, iconColor: a.iconColor));
    case 'input':
      unawaited(DialogHelper.showTextInput(ctx, title: _title, hintText: '거절 사유 (선택)', maxLines: 2, confirmText: a.label,
          confirmColor: a.confirm, icon: a.icon, iconColor: a.iconColor));
    case 'logout':
      unawaited(DialogHelper.showLogoutConfirm(ctx));
    case 'cancelPreset':
      unawaited(DialogHelper.showCancelConfirm(ctx, title: _title, message: _msg));
    default:
      throw StateError(a.kind);
  }
}

void main() {
  final phase = Platform.environment['DU309_PHASE'] ?? '';
  final run = Platform.environment['DU309_RUN'] == '1' && (phase == 'before' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  testWidgets('D309 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nPng = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D309-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
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
          final a = after ? s.after : s.before;
          _open(appCtx!, a);
          await frames(8);
          safe('열림');
          final host = find.byType(Dialog);
          need(host.evaluate().length == 1, '대화가 열리지 않았다');
          Finder fe(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
          final labels = find
              .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
              .evaluate()
              .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText()) == a.label)
              .toList()
            ..sort((x, y) => t.getRect(fe(x)).top.compareTo(t.getRect(fe(y)).top));
          need(labels.isNotEmpty, '채움 버튼 글 없음');
          final lab = labels.last; // 제목과 같은 글(로그아웃)이 있으면 가장 아래가 버튼이다
          final fg = t.renderObject<RenderParagraph>(fe(lab)).text.style!.color!;
          final bg = bgOf(lab);
          final icons = find.descendant(of: host, matching: find.byType(Icon), skipOffstage: false).evaluate().toList()
            ..sort((x, y) => t.getRect(fe(x)).top.compareTo(t.getRect(fe(y)).top));
          need(icons.isNotEmpty, '머리 아이콘 없음');
          final ic = icons.first;
          final icColor = (ic.widget as Icon).color!;
          final icBg = bgOf(ic);
          final row = {
            'phase': phase, 'cond': c.id, 'id': s.id, 'where': s.where,
            'btnFg': _hex(fg), 'btnBg': _hex(bg), 'btnContrast': double.parse(_contrast(fg, bg).toStringAsFixed(2)),
            'iconFg': _hex(icColor), 'iconBg': _hex(icBg), 'iconContrast': double.parse(_contrast(icColor, icBg).toStringAsFixed(2)),
          };
          rows.add(row);
          _out('D309 ${jsonEncode(row)}');
          if (after) {
            need(row['btnBg'] == _shown(s.wantBtn), '버튼 바탕이 행동 결과 색이 아님(want ${_shown(s.wantBtn)}) $row');
            need(row['iconFg'] == _shown(s.wantIcon), '머리 아이콘이 의미색/기본이 아님(want ${_shown(s.wantIcon)}) $row');
            need((row['btnContrast'] as double) >= 4.5, '채움 버튼 글 대비 $row');
            need((row['iconContrast'] as double) >= 3.0, '머리 아이콘 대비 $row');
          }
          if (c.id == 'W360') {
            nPng++;
            await vqCapture(t, key, 'D309-$phase-${c.id}_${s.id}', conditions: {'phase': phase, 'scene': s.id, 'where': s.where, 'viewport': '360x780', 'textScaleFactor(기기)': c.s});
          }
          Navigator.of(t.element(host)).pop();
          await frames(8);
          safe('닫힘');
          need(find.byType(Dialog).evaluate().isEmpty, '대화가 닫히지 않았다');
        }
      }
      need(rows.length == _scenes.length * 2, '장면 수 ${rows.length}');
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D309-END ${jsonEncode({'pump': nPump, 'png': nPng, 'rows': rows.length})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 5)));
}
