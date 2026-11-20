// ignore_for_file: depend_on_referenced_packages
// [DU286 공용 StyledDialog 셸 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU286_RUN=1 이고 DU286_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   앱 lib/ 의 StyledDialog 호출 중 글자 그대로인 것(제목·부제목·닫기·버튼 글, 생성: work/du286-styled-dialog-shell/src/extract286.py)을
//   showDialog(StyledDialog(...)) 로 실제 셸에 넣어 열고 재고 닫는다(Navigator.pop). 내용 자리는 짧은 글 하나다. 누르는 것은 없다.
//   조건 W360/1.0·M360/1.5·B320/2.0.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/responsive_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';

import 'support/du1_vq_capture.dart';

typedef _It = ({String id, String title, String? sub, bool close, List<(String, String)> btns, bool disabled, String src});

// 생성 구역 — extract286.py 결과(plan/strings286.json) 16개 + 비활성 변형 1. 손으로 고치지 않는다.
const List<_It> _items = [
  (id: 'business_form_screen_289', title: '수정 취소', sub: null, close: false, btns: [('cancel', '계속 수정'), ('danger', '나가기')], disabled: false, src: 'lib/screens/business_admin/business_form_screen.dart:289'),
  (id: 'business_form_screen_3456', title: '주소 직접 입력', sub: null, close: false, btns: [('cancel', '취소'), ('primary', '확인')], disabled: false, src: 'lib/screens/business_admin/business_form_screen.dart:3456'),
  (id: 'schedule_request_management_dialog_574', title: '요청 승인', sub: null, close: false, btns: [('cancel', '취소'), ('primary', '승인')], disabled: false, src: 'lib/screens/business_admin/dialogs/schedule_request_management_dialog.dart:574'),
  (id: 'schedule_request_management_dialog_721', title: '요청 거절', sub: null, close: false, btns: [('cancel', '취소'), ('danger', '거절')], disabled: false, src: 'lib/screens/business_admin/dialogs/schedule_request_management_dialog.dart:721'),
  (id: 'to_list_dialogs_99', title: '공고 종료', sub: '이 공고를 종료할까요?', close: false, btns: [('cancel', '취소'), ('primary', '종료')], disabled: false, src: 'lib/screens/business_admin/dialogs/to_list_dialogs.dart:99'),
  (id: 'to_list_dialogs_173', title: '공고 재오픈', sub: null, close: false, btns: [('cancel', '취소'), ('primary', '재오픈')], disabled: false, src: 'lib/screens/business_admin/dialogs/to_list_dialogs.dart:173'),
  (id: 'to_list_dialogs_263', title: '재오픈 불가', sub: null, close: false, btns: [('primary', '확인')], disabled: false, src: 'lib/screens/business_admin/dialogs/to_list_dialogs.dart:263'),
  (id: 'edit_to_screen_1607', title: '수정 내용 충돌', sub: '다른 관리자가 이미 저장했습니다', close: false, btns: [('primary', '확인 (뒤로가기)')], disabled: false, src: 'lib/screens/business_admin/to_management/edit_to_screen.dart:1607'),
  (id: 'work_type_management_screen_135', title: '등록 완료!', sub: '업무가 성공적으로 등록되었습니다', close: false, btns: [('cancel', '나중에'), ('primary', '상세 정보 입력')], disabled: false, src: 'lib/screens/business_admin/work_type_management_screen.dart:135'),
  (id: 'document_management_screen_2069', title: '급여정보 입력', sub: '급여 수령에 사용할 계좌 정보를 입력하세요', close: false, btns: [('cancel', '취소'), ('primary', '저장')], disabled: false, src: 'lib/screens/common/document_management_screen.dart:2069'),
  (id: 'document_management_screen_2069_disabled', title: '급여정보 입력', sub: '급여 수령에 사용할 계좌 정보를 입력하세요', close: false, btns: [('cancel', '취소'), ('primary', '저장')], disabled: true, src: 'lib/screens/common/document_management_screen.dart:2069'),
  (id: 'notification_screen_2060', title: '초대 수락 완료', sub: null, close: false, btns: [('cancel', '나중에'), ('primary', '관리자 모드로 전환')], disabled: false, src: 'lib/screens/common/notification_screen.dart:2060'),
  (id: 'insurance_rate_settings_screen_517', title: '연도 추가', sub: '보험료율을 새 연도로 추가합니다', close: false, btns: [('cancel', '취소'), ('primary', '추가')], disabled: false, src: 'lib/screens/super_admin/insurance_rate_settings_screen.dart:517'),
  (id: 'user_settings_screen_210', title: '회원탈퇴', sub: '이 작업은 되돌릴 수 없습니다', close: false, btns: [('cancel', '취소'), ('danger', '계속')], disabled: false, src: 'lib/screens/user/user_settings_screen.dart:210'),
  (id: 'user_settings_screen_775', title: '비밀번호 확인', sub: '탈퇴를 진행하려면 현재 비밀번호를 입력하세요', close: false, btns: [('cancel', '취소'), ('danger', '탈퇴')], disabled: false, src: 'lib/screens/user/user_settings_screen.dart:775'),
  (id: 'admin_to_group_card_2712', title: '관리용 카드명 변경', sub: '공고 카드에 표시될 관리용 이름을 설정합니다', close: false, btns: [('cancel', '취소'), ('primary', '저장')], disabled: false, src: 'lib/widgets/admin/cards/admin_to_group_card.dart:2712'),
  (id: 'daum_address_search_mobile_33', title: '주소 검색', sub: '우편번호 또는 도로명 주소를 검색하세요', close: true, btns: [], disabled: false, src: 'lib/widgets/inputs/daum_address_search_mobile.dart:33'),
];

/// 항상 PNG 를 찍는 고정 표본
const _fixedShots = {
  'user_settings_screen_210',
  'user_settings_screen_775',
  'admin_to_group_card_2712',
  'notification_screen_2060',
  'work_type_management_screen_135',
  'daum_address_search_mobile_33',
};

const _content = '내용 자리';

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

/// 글자 단위 줄 나눔 — 줄마다 보이는 글자, 그리고 '낱말 안에서 끊긴' 곳 수(DU275 시험과 같은 규칙).
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

double _tpWidth(String text, TextStyle? style, TextScaler scaler, Locale? locale) {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: scaler, locale: locale)
    ..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

void _open(BuildContext ctx, _It it) {
  VoidCallback? on() => it.disabled ? null : () {};
  unawaited(showDialog<void>(
    context: ctx,
    builder: (dc) => StyledDialog(
      title: it.title,
      subtitle: it.sub,
      icon: Icons.info_outline,
      showCloseButton: it.close,
      content: const Text(_content),
      actions: it.btns.isEmpty
          ? null
          : [
              for (final b in it.btns)
                switch (b.$1) {
                  'cancel' => StyledDialogButton.cancel(text: b.$2, onPressed: () {}),
                  'danger' => StyledDialogButton.danger(text: b.$2, onPressed: on()),
                  _ => StyledDialogButton.primary(text: b.$2, onPressed: on()),
                },
            ],
    ),
  ));
}

void main() {
  final phase = Platform.environment['DU286_PHASE'] ?? '';
  final run = Platform.environment['DU286_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);
  final wj = String.fromCharCode(0x2060);

  testWidgets('D286 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nPng = 0, nOpen = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D286-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 2000 && nPng <= 60 && nOpen <= 80, '사용량 한도');
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
        } else if (w is Container && w.decoration is BoxDecoration) {
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
    final rows = <Map<String, Object?>>[];
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'M360', w: 360.0, h: 780.0, s: 1.5),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        cur = c.id;
        await t.pumpWidget(const SizedBox.shrink());
        await frames(1);
        safe('조건 시작');
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        t.platformDispatcher.textScaleFactorTestValue = c.s;
        final screen = Rect.fromLTWH(0, 0, c.w, c.h);
        final enlarged = c.s > 1.0;
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
            home: Scaffold(
              body: Builder(builder: (ctx) {
                appCtx = ctx;
                return const SizedBox.expand();
              }),
            ),
          ),
        ));
        await frames(2);
        need(appCtx != null, '앱 문맥 없음');
        for (final it in _items) {
          cur = '${c.id} ${it.id}';
          nOpen++;
          _open(appCtx!, it);
          await frames(8);
          safe('열림');
          Finder host() => find.byType(StyledDialog);
          need(host().evaluate().length == 1, '대화가 열리지 않았다');
          final ctxIn = t.element(host());
          Finder fe(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
          final texts = find
              .descendant(of: host(), matching: find.byType(RichText), skipOffstage: false)
              .evaluate()
              .toList()
            ..sort((a, b) => t.getRect(fe(a)).top.compareTo(t.getRect(fe(b)).top));
          Element? nearest(Element e, Type type) {
            final xs = find.ancestor(of: fe(e), matching: find.byType(type)).evaluate().toList();
            if (xs.isEmpty) return null;
            xs.sort((a, b) => b.depth.compareTo(a.depth));
            return xs.first;
          }

          String plainOf(Element e) => TextLayout.plain((e.widget as RichText).text.toPlainText());
          final used = <Element>{};
          Element? pick(String s, {bool last = false}) {
            final xs = texts.where((e) => plainOf(e) == s && !used.contains(e)).toList();
            if (xs.isEmpty) return null;
            final e = last ? xs.last : xs.first;
            used.add(e);
            return e;
          }

          final eTitle = pick(TextLayout.plain(it.title));
          need(eTitle != null, '제목 없음');
          final eSub = it.sub == null ? null : pick(it.sub!);
          need(it.sub == null || eSub != null, '부제목 없음');
          final eBtns = <(String, Element)>[];
          for (final b in it.btns.reversed) {
            final e = pick(b.$2, last: true);
            need(e != null, '버튼 글 없음 ${b.$2}');
            eBtns.insert(0, (b.$1, e!));
          }
          final scaler = MediaQuery.textScalerOf(ctxIn);
          final loc = Localizations.maybeLocaleOf(ctxIn);
          final dlgW = t.getSize(find.descendant(of: host(), matching: find.byType(Material)).first).width;
          double sp(double v) => ResponsiveHelper.spacing(ctxIn, v);
          final hdrW = dlgW - sp(20) - sp(16);
          final besideW = hdrW - 44 - sp(12) - (it.close ? 48 : 0);
          final actW = dlgW - ResponsiveHelper.cardPadding(ctxIn).horizontal;
          final n = it.btns.length;
          final per = n == 0 ? actW : (actW - sp(12) * (n - 1)) / n;
          final iconEl = find
              .descendant(of: host(), matching: find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.info_outline))
              .evaluate()
              .first;
          final iconR = t.getRect(fe(iconEl));
          final titleR = t.getRect(fe(eTitle!));
          final titleLayout = titleR.left > iconR.right - 1 ? 'beside' : (titleR.top >= iconR.bottom - 1 ? 'above' : '?');
          String btnLayout = n == 0 ? 'none' : (n == 1 ? 'single' : 'row');
          if (n >= 2) {
            final r0 = t.getRect(fe(eBtns[0].$2));
            final r1x = t.getRect(fe(eBtns[1].$2));
            if (!(r0.top < r1x.bottom && r1x.top < r0.bottom)) btnLayout = 'col';
          }

          Map<String, Object?> info(String nm, Element e, double availNow) {
            final rp = t.renderObject<RenderParagraph>(fe(e));
            final raw = plainOf(e);
            final r = t.getRect(fe(e));
            final st = rp.text.style;
            final fg = st?.color;
            final bg = bgOf(e);
            final li = _lineInfo(rp);
            final joined = rp.text.toPlainText().contains(wj);
            final wDraw = rp.getMaxIntrinsicWidth(double.infinity);
            var maxTok = 0.0;
            for (final tok in raw.split(RegExp('[ $nl]+'))) {
              if (tok.isEmpty) continue;
              maxTok = math.max(maxTok, _tpWidth(joined ? TextLayout.keepWords(tok) : tok, st, scaler, loc));
            }
            final ink = nearest(e, InkWell);
            final box = ink == null ? null : t.getRect(fe(ink));
            return {
              'name': nm, 'rect': lt(r), 'visible': inside(r, screen),
              'fontSize': st?.fontSize, 'weight': st?.fontWeight?.value,
              'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
              'didExceedMaxLines': rp.didExceedMaxLines, 'maxLines': rp.maxLines,
              'lines': li.lines, 'sylBreaks': li.sylBreaks, 'joined': joined,
              'wDraw': r1(wDraw), 'availNow': r1(availNow), 'maxTok': r1(maxTok), 'longToken': maxTok > availNow + 0.5,
              if (box != null) 'boxH': r1(box.height),
            };
          }

          final textW = titleLayout == 'beside' ? besideW : hdrW;
          final xs = <Map<String, Object?>>[];
          xs.add(info('제목', eTitle, textW)..['kind'] = 'title');
          if (eSub != null) xs.add(info('부제목', eSub, textW)..['kind'] = 'sub');
          final btnW = btnLayout == 'col' ? actW : per;
          for (final (k, e) in eBtns) {
            xs.add(info('버튼 ${plainOf(e)}', e, btnW)..['kind'] = (it.disabled && k != 'cancel') ? 'disabled' : k);
          }
          Map<String, Object?>? closeInfo;
          if (it.close) {
            final ib = find.descendant(of: host(), matching: find.byType(IconButton)).evaluate().first;
            final ic = find.descendant(of: fe(ib), matching: find.byType(Icon)).evaluate().first;
            final col = (ic.widget as Icon).color;
            final r = t.getRect(fe(ib));
            closeInfo = {
              'w': r1(r.width), 'h': r1(r.height), 'fg': col == null ? null : _hex(col), 'bg': _hex(bgOf(ic)),
              'contrast': col == null ? null : double.parse(_contrast(col, bgOf(ic)).toStringAsFixed(2)),
              'size': (ic.widget as Icon).size,
            };
          }

          if (after) {
            for (final x in xs) {
              final at = '${x['name']}';
              final cst = x['contrast'];
              final ok45 = cst is double && cst >= 4.5;
              need(x['didExceedMaxLines'] != true, '$at 말줄임 $x');
              need(x['visible'] == true, '$at 화면 밖 $x');
              if (x['longToken'] != true) need(x['sylBreaks'] == 0, '$at 음절 끊김 $x');
              final k = x['kind'];
              if (k == 'title') need(x['fg'] == '#111827' && ok45, '$at 제목색 $x');
              if (k == 'sub') need(x['fg'] == '#60646F' && ok45, '$at 부제목색 $x');
              if (k == 'cancel' || k == 'primary' || k == 'danger' || k == 'custom') {
                need(ok45, '$at 버튼 대비 $x');
                need(((x['boxH'] as double?) ?? 0) >= 52, '$at 버튼 높이 $x');
              }
              if (k == 'disabled') {
                need(x['fg'] == '#60646F' && x['bg'] == '#EEEEEE' && ok45, '$at 비활성 $x');
                need(((x['boxH'] as double?) ?? 0) >= 52, '$at 비활성 높이 $x');
              }
            }
            if (closeInfo != null) {
              final cc = closeInfo['contrast'];
              need(closeInfo['fg'] == '#60646F' && cc is double && cc >= 3.0, '닫기 색 $closeInfo');
              need((closeInfo['w'] as double) >= 48 && (closeInfo['h'] as double) >= 48, '닫기 터치 $closeInfo');
            }
            if (enlarged && titleLayout == 'beside') {
              need((xs[0]['wDraw'] as double) <= besideW + 0.5, '제목 가로인데 옆 폭보다 넓다 ${xs[0]} besideW=$besideW');
            }
            if (enlarged && btnLayout == 'row') {
              for (final x in xs.where((x) => '${x['name']}'.startsWith('버튼 '))) {
                if (x['joined'] != true) need((x['wDraw'] as double) <= per + 0.5, '행동 가로인데 칸보다 넓다 $x');
              }
            }
          }

          final shot = _fixedShots.contains(it.id);
          if (shot) {
            nPng++;
            await vqCapture(t, key, 'D286-$phase-${c.id}_${it.id}', conditions: {
              'phase': phase, 'item': it.id, 'src': it.src, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
            });
          }
          rows.add({'phase': phase, 'cond': c.id, 'id': it.id, 'src': it.src, 'titleLayout': titleLayout, 'btnLayout': btnLayout,
            'shot': shot, 'dlgW': r1(dlgW), 'hdrW': r1(hdrW), 'besideW': r1(besideW), 'actW': r1(actW), 'per': r1(per),
            'close': closeInfo, 'texts': xs});
          _out('D286 ${jsonEncode(rows.last)}');
          Navigator.of(ctxIn).pop();
          await frames(8);
          safe('닫힘');
          need(find.byType(StyledDialog).evaluate().isEmpty, '대화가 닫히지 않았다');
        }
      }
      if (after) {
        need(rows.length == _items.length * 3, '열린 수 ${rows.length}');
        need(overflow.isEmpty, 'overflow $overflow');
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D286-END ${jsonEncode({'pump': nPump, 'png': nPng, 'open': nOpen, 'rows': rows.length, 'overflow': overflow})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 6)));
}
