// ignore_for_file: depend_on_referenced_packages
// [DU288 공용 안내 카드(StyledDialogInfoCard) baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU288_RUN=1 이고 DU288_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   lib/ 의 StyledDialogInfoCard 쓰임 중 글자 그대로인 것 + 서류 열람 동의 카드(실제 DocumentAccessConsent.card/inviteCard)를
//   실제 쓰임과 같은 호스트(시트형 스크롤·StyledDialog content·AlertDialog content)에 넣어 재고 닫는다. 누르는 것은 없다.
//   조건 W360/1.0·M360/1.5·B320/2.0. 글 안의 '¶' 는 줄바꿈(10)으로 바꾼다(소스 문자열과 같다).
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
import 'package:ALfit/utils/attendance_policy_disclosure.dart';
import 'package:ALfit/utils/responsive_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';

import 'support/du1_vq_capture.dart';

typedef _It = ({String id, String host, String kind, String src, List<String> parts, Widget Function() build});

const _bizLong = '강남 물류센터 제2물류동 야간 분류팀';
const _bizShort = 'QA 사업장';

String _n(String s) => s.replaceAll('¶', String.fromCharCode(10));

List<_It> _items() {
  _It msg(String id, String host, String kind, String src, String raw) {
    final m = _n(raw);
    return (
      id: id,
      host: host,
      kind: kind,
      src: src,
      parts: [m],
      build: () => switch (kind) {
            'info' => StyledDialogInfoCard.info(m),
            'warning' => StyledDialogInfoCard.warning(m),
            'success' => StyledDialogInfoCard.success(m),
            _ => StyledDialogInfoCard.error(m),
          },
    );
  }

  const dac = 'lib/widgets/dialogs/apply/document_access_consent.dart';
  const acd = 'lib/widgets/dialogs/apply/apply_confirm_dialog.dart';
  const agc = 'lib/widgets/admin/cards/admin_to_group_card.dart';
  const tld = 'lib/screens/business_admin/dialogs/to_list_dialogs.dart';
  return [
    (id: 'consent_long', host: 'sheet', kind: 'warning', src: '$dac:59', parts: DocumentAccessConsent.partsFor(_bizLong),
      build: () => DocumentAccessConsent.card(_bizLong)),
    (id: 'consent_short', host: 'sheet', kind: 'warning', src: '$dac:59', parts: DocumentAccessConsent.partsFor(_bizShort),
      build: () => DocumentAccessConsent.card(_bizShort)),
    (id: 'invite_long', host: 'sheet', kind: 'warning', src: '$dac:103', parts: DocumentAccessConsent.invitePartsFor(_bizLong),
      build: () => DocumentAccessConsent.inviteCard(_bizLong)),
    msg('acd_105', 'sheet', 'info', '$acd:105',
        '희망 시작일부터 계약 종료일까지 일괄 지원됩니다.¶첫 근무 전까지는 확정취소 가능, 근무 시작 후에는 퇴사 요청을 통해 퇴사 가능합니다.'),
    msg('acd_109', 'sheet', 'info', '$acd:109', '지원 후 관리자 승인을 기다려주세요.¶확정 전까지는 자유롭게 취소 가능합니다.'),
    msg('acd_304a', 'sheet', 'info', '$acd:304 kAttendancePolicyUnavailableNote', kAttendancePolicyUnavailableNote),
    msg('acd_304b', 'sheet', 'info', '$acd:304 kAttendancePolicyLoadFailedNote', kAttendancePolicyLoadFailedNote),
    msg('uss_215', 'dialog', 'error', 'lib/screens/user/user_settings_screen.dart:215',
        '탈퇴하면 모든 데이터가 영구 삭제되며 복구할 수 없습니다.¶계속하려면 비밀번호를 입력해주세요.'),
    msg('agc_2420', 'dialog', 'warning', '$agc:2420',
        '종료한 날짜는 신규 지원을 받지 않으며, 대기 중인 지원자는 거절 처리됩니다.¶확정된 근무 기록은 유지됩니다.¶¶근무 전 날짜는 종료 후 다시 열 수 있습니다.'),
    msg('agc_2497', 'dialog', 'info', '$agc:2497', '선택한 날짜가 모집 중으로 전환됩니다.¶이미 거절된 지원자는 재지원이 필요합니다.'),
    msg('agc_2594', 'dialog', 'warning', '$agc:2594 hasMalformedSelected=false',
        '삭제한 날짜는 복구할 수 없습니다.¶지원·초대·근무 기록이 있는 날짜는 삭제할 수 없습니다.¶¶삭제 후 남은 날짜가 없으면 미공개 공고도 함께 삭제됩니다.'),
    msg('wtm_143', 'dialog', 'info', 'lib/screens/business_admin/work_type_management_screen.dart:143',
        '상세 정보(설명, 이미지 등)를 추가하면 지원자에게 더 많은 정보를 제공할 수 있어요!'),
    msg('tld_50', 'dialog', 'warning', '$tld:50', '삭제한 공고는 복구할 수 없습니다.¶지원·초대·근무 기록이 있는 공고는 삭제할 수 없습니다.'),
    msg('tld_104', 'dialog', 'warning', '$tld:104',
        '신규 지원을 받지 않습니다.¶기존 지원자는 그대로 유지되며, 확정된 근무 일정은 변경되지 않습니다.¶¶재오픈으로 언제든 다시 활성화할 수 있습니다.'),
    msg('tld_185', 'dialog', 'warning', '$tld:185', '이미 인원이 충족된 공고입니다.¶추가 지원자를 받으시겠습니까?'),
    msg('tld_189', 'dialog', 'success', '$tld:189', '• 지원자가 다시 지원할 수 있습니다¶• 기존 확정 지원자는 유지됩니다'),
    msg('tld_285s', 'dialog', 'error', '$tld:285 (보간 견본)', '근무일: 2026-11-12 (목)¶근무 시간: 09:00 ~ 18:00'),
    (id: 'alert_consent', host: 'alert', kind: 'warning', src: '$dac:59 in AlertDialog(scrollable)',
      parts: DocumentAccessConsent.partsFor(_bizShort), build: () => DocumentAccessConsent.card(_bizShort)),
    msg('alert_185', 'alert', 'warning', '$tld:185 in AlertDialog(scrollable)', '이미 인원이 충족된 공고입니다.¶추가 지원자를 받으시겠습니까?'),
  ];
}

/// 항상 PNG 를 찍는 고정 표본(항목 → 조건)
const Map<String, Set<String>> _shots = {
  'consent_long': {'W360', 'M360', 'B320'},
  'invite_long': {'W360', 'B320'},
  'tld_189': {'W360', 'B320'},
  'uss_215': {'B320'},
  'acd_105': {'W360'},
  'alert_consent': {'W360', 'B320'},
};

Color _kindColor(String k) => switch (k) {
      'info' => AppColors.info,
      'warning' => AppColors.warning,
      'success' => AppColors.success,
      _ => AppColors.error,
    };

Color _expectText(String k) => switch (k) {
      'info' => AppColors.infoDeep,
      'warning' => AppColors.warningDark,
      'success' => AppColors.successDark,
      _ => AppColors.errorDark,
    };

/// production `_getShade(color, 700)` 의 MaterialColor 아닌 경우(검정 쪽 0.4 × 0.3 = 12%)
Color _expectIcon(String k) => Color.lerp(_kindColor(k), Colors.black, 0.4 * 0.3)!;

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

/// 글자 단위 줄 나눔 — 줄마다 보이는 글자, 그리고 '낱말 안에서 끊긴' 곳 수(DU286 시험과 같은 규칙).
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

void main() {
  final phase = Platform.environment['DU288_PHASE'] ?? '';
  final run = Platform.environment['DU288_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);
  final wj = String.fromCharCode(0x2060);

  testWidgets('D288 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nPng = 0, nOpen = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D288-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 3000 && nPng <= 40 && nOpen <= 80, '사용량 한도');
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

    final key = GlobalKey();
    final rows = <Map<String, Object?>>[];
    final items = _items();
    Widget app(Widget home) => RepaintBoundary(
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
            home: home,
          ),
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
        final enlarged = c.s > 1.0;
        for (final it in items) {
          cur = '${c.id} ${it.id}';
          nOpen++;
          await t.pumpWidget(const SizedBox.shrink());
          await frames(1);
          safe('비움');
          BuildContext? appCtx;
          if (it.host == 'sheet') {
            await t.pumpWidget(app(Scaffold(
              body: SingleChildScrollView(
                child: Builder(
                  builder: (ctx) => Padding(
                    padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(ctx, 16), vertical: 16),
                    child: it.build(),
                  ),
                ),
              ),
            )));
            await frames(3);
          } else {
            await t.pumpWidget(app(Scaffold(
              body: Builder(builder: (ctx) {
                appCtx = ctx;
                return const SizedBox.expand();
              }),
            )));
            await frames(2);
            need(appCtx != null, '앱 문맥 없음');
            unawaited(showDialog<void>(
              context: appCtx!,
              builder: (dc) => it.host == 'dialog'
                  ? StyledDialog(
                      title: '확인',
                      icon: Icons.info_outline,
                      content: it.build(),
                      actions: [
                        StyledDialogButton.cancel(text: '취소', onPressed: () {}),
                        StyledDialogButton.primary(text: '확인', onPressed: () {}),
                      ],
                    )
                  : AlertDialog(
                      scrollable: true,
                      content: it.build(),
                      actions: [TextButton(onPressed: () {}, child: const Text('확인'))],
                    ),
            ));
            await frames(8);
          }
          safe('열림');

          final cardF = find.byType(StyledDialogInfoCard, skipOffstage: false);
          need(cardF.evaluate().length == 1, '카드 수 ${cardF.evaluate().length}');
          final ctxIn = t.element(cardF);
          final cardR = t.getRect(cardF);
          final iconF = find.descendant(of: cardF, matching: find.byType(Icon), skipOffstage: false);
          need(iconF.evaluate().length == 1, '아이콘 수');
          final iconR = t.getRect(iconF);
          final iconW = t.widget<Icon>(iconF);
          final iconBg = bgOf(iconF.evaluate().first);
          final deco = (t.widget<DecoratedBox>(find.descendant(of: cardF, matching: find.byType(DecoratedBox), skipOffstage: false).first)
              .decoration as BoxDecoration);
          final borderC = (deco.border as Border?)?.top.color;
          final textEls = find.descendant(of: cardF, matching: find.byType(Text), skipOffstage: false).evaluate().toList()
            ..sort((a, b) => t.getRect(fe(a)).top.compareTo(t.getRect(fe(b)).top));
          need(textEls.length == it.parts.length, '문단 수 ${textEls.length} != ${it.parts.length}');
          final scaler = MediaQuery.textScalerOf(ctxIn);
          final loc = Localizations.maybeLocaleOf(ctxIn);
          final inner = cardR.width - 2 * ResponsiveHelper.spacing(ctxIn, 14) - 2.0;

          final paras = <Map<String, Object?>>[];
          Rect? firstR;
          double? lineCy;
          for (var i = 0; i < textEls.length; i++) {
            final e = textEls[i];
            final tw = e.widget as Text;
            final rpF = find.descendant(of: fe(e), matching: find.byType(RichText), skipOffstage: false).first;
            final rp = t.renderObject<RenderParagraph>(rpF);
            final r = t.getRect(rpF);
            final rawShown = rp.text.toPlainText();
            final shown = TextLayout.plain(rawShown);
            final sem = tw.semanticsLabel ?? tw.data;
            final li = _lineInfo(rp);
            final joined = rawShown.contains(wj);
            final avail = rp.constraints.maxWidth;
            final st = rp.text.style;
            var maxTok = 0.0;
            for (final tok in shown.split(RegExp('[ $nl]+'))) {
              if (tok.isEmpty) continue;
              maxTok = math.max(maxTok, _tpWidth(joined ? TextLayout.keepWords(tok) : tok, st, scaler, loc));
            }
            final fg = st?.color;
            final bg = bgOf(e);
            if (i == 0) {
              firstR = r;
              final bx = rp.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1));
              if (bx.isNotEmpty) lineCy = r.top + (bx.first.top + bx.first.bottom) / 2;
            }
            paras.add({
              'i': i, 'shownOk': shown == it.parts[i], 'semOk': sem == it.parts[i], 'joined': joined,
              'rect': lt(r), 'avail': r1(avail), 'maxTok': r1(maxTok), 'longToken': maxTok > avail + 0.5,
              'lines': li.lines, 'sylBreaks': li.sylBreaks, 'didExceedMaxLines': rp.didExceedMaxLines,
              'fontSize': st?.fontSize, 'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'contrast': fg == null ? null : r2(_contrast(fg, bg)),
            });
          }
          final layout = iconR.right <= firstR!.left + 0.5
              ? 'beside'
              : (iconR.bottom <= firstR.top + 0.5 ? 'above' : '?');
          final iconDy = lineCy == null ? null : r2(iconR.center.dy - lineCy);
          final iconFg = iconW.color;
          final card = {
            'layout': layout, 'iconDy': iconDy, 'iconRect': lt(iconR), 'iconSize': iconW.size, 'cardRect': lt(cardR), 'inner': r1(inner),
            'face': deco.color?.toARGB32().toRadixString(16),
            'border': borderC?.toARGB32().toRadixString(16),
            'iconFg': iconFg == null ? null : _hex(iconFg), 'iconBg': _hex(iconBg),
            'iconContrast': iconFg == null ? null : r2(_contrast(iconFg, iconBg)),
          };

          if (after) {
            final k = it.kind;
            for (final p in paras) {
              final at = '문단 ${p['i']}';
              need(p['shownOk'] == true, '$at 보이는 글자가 원문과 다르다 $p');
              need(p['semOk'] == true, '$at 읽기 이름이 원문과 다르다 $p');
              need(p['didExceedMaxLines'] != true, '$at 말줄임 $p');
              if (p['longToken'] != true) need(p['sylBreaks'] == 0, '$at 음절 끊김 $p');
              need(p['fg'] == _hex(_expectText(k)), '$at 글자색이 바뀌었다 $p');
              if (enlarged) need((p['avail'] as double) >= r1(inner) - 0.5, '$at 큰 글자인데 글 폭이 카드 안쪽보다 좁다 $p inner=$inner');
            }
            need(deco.color?.toARGB32() == _kindColor(k).withValues(alpha: 0.07).toARGB32(), '면 색이 바뀌었다 $card');
            need(borderC?.toARGB32() == _kindColor(k).withValues(alpha: 0.22).toARGB32(), '테두리 색이 바뀌었다 $card');
            need(iconFg?.toARGB32() == _expectIcon(k).toARGB32(), '아이콘 색이 바뀌었다 $card');
            if (enlarged) {
              need(layout == 'above', '큰 글자인데 아이콘이 글 위가 아니다 $card');
            } else {
              need(layout == 'beside', '기본 배율인데 아이콘이 옆이 아니다 $card');
              need(iconDy != null && iconDy.abs() <= 1.5, '아이콘이 첫 줄에 맞지 않는다 $card');
            }
          }

          final shot = _shots[it.id]?.contains(c.id) ?? false;
          if (shot) {
            nPng++;
            await vqCapture(t, key, 'D288-$phase-${c.id}_${it.id}', conditions: {
              'phase': phase, 'item': it.id, 'host': it.host, 'src': it.src, 'viewport': '${c.w.toInt()}x${c.h.toInt()}',
              'textScaleFactor(기기)': c.s,
            });
            if (it.id == 'consent_long' && c.id == 'B320') {
              final sf = find.byType(Scrollable, skipOffstage: false).first;
              final pos = t.state<ScrollableState>(sf).position;
              pos.jumpTo(math.min(360.0, pos.maxScrollExtent));
              await frames(2);
              safe('끌기');
              nPng++;
              await vqCapture(t, key, 'D288-$phase-${c.id}_${it.id}_d1', conditions: {
                'phase': phase, 'item': it.id, 'host': it.host, 'src': it.src, 'viewport': '${c.w.toInt()}x${c.h.toInt()}',
                'textScaleFactor(기기)': c.s, 'scroll': r1(pos.pixels),
              });
            }
          }
          rows.add({'phase': phase, 'cond': c.id, 'id': it.id, 'host': it.host, 'kind': it.kind, 'src': it.src, 'shot': shot,
            'card': card, 'paras': paras});
          _out('D288 ${jsonEncode(rows.last)}');
          if (it.host != 'sheet') {
            Navigator.of(ctxIn).pop();
            await frames(8);
            safe('닫힘');
            need(find.byType(StyledDialogInfoCard, skipOffstage: false).evaluate().isEmpty, '대화가 닫히지 않았다');
          }
        }
      }
      if (after) {
        need(rows.length == items.length * 3, '장면 수 ${rows.length}');
        need(overflow.isEmpty, 'overflow $overflow');
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D288-END ${jsonEncode({'pump': nPump, 'png': nPng, 'open': nOpen, 'rows': rows.length, 'overflow': overflow})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 8)));
}
