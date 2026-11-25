// [CONSENT-R4d · F-R4C-3] du1_info_card_288 의 **동의 4항목 의미**를 새 중립 패널로 옮긴다.
//   r4d: 음절 끊김 판정을 옛 시험의 규칙 그대로 옮겼다(A test/du1_info_card_288_test.dart:135–173 —
//   WJ(U+2060) 건너뜀 · 공백/ZWSP/줄바꿈/기호[·,./()~-] 는 구분자 · 한글·영숫자 사이 끊김만 셈) ·
//   긴 낱말 예외(:374–377 · :414 — 가장 긴 낱말 폭 > 글 폭 + 0.5 이면 음절 끊김 단언을 하지 않는다).
//   r4c 판(ae76901a)의 '무조건 음절 끊김 0'은 옛 의미보다 강해 교체한다.
//   작성만 했다 — 실행 0. 통과 결과가 아니다.
//
//   옛 시험(A/test/du1_info_card_288_test.dart · ENV 전용)은 동의 카드를 StyledDialogInfoCard(warning)
//   1개로 잰다(:58–63 · :84–85 · :339–340). 후보 동의 카드는 공용 카드를 쓰지 않는 중립 패널이라
//   그 구조 기대가 맞지 않는다. 공용 StyledDialogInfoCard 의 나머지 항목 검증은 옛 시험에 그대로 남긴다
//   (그 파일은 바꾸지 않는다 · ENV 전체 재실행 배정 0).
//
//   옮기는 의미(항목 4 × 조건 3 = 12 장면)
//     항목  consent_long · consent_short · invite_long(시트 호스트) · alert_consent(AlertDialog scrollable · 소표면)
//     조건  W360 @1.0 · M360 @1.5 · B320 @2.0 (360×780 / 320×640 · devicePixelRatio 1)
//     문단  목적(문단 1)·기간(문단 2) 개수 = parts · 보이는 글자 = 원문 · 읽기 이름 = 원문 · 말줄임 0 ·
//           음절 끊김 0(긴 낱말 제외) · 큰 글자에서 글 폭 ≥ 패널 안쪽 − 0.5
//     아이콘 정보 아이콘 1개 · 기본 배율 = 글 옆 · 큰 글자 = 글 위. 첫 줄 가운데 정렬(iconDy)은 관측값
//           출력만 한다(옛 ±1.5 기준 — 후보 미구현 IC2 · Codex 판정 요청).
//     자세히 동의 전에 누를 수 있음 · 48×48 · 열면 상세 전부 · 닫힘 · 넘침 0
//     색    중립(D-CB-CONSENT) — 옛 warning 면/선/글자 기대는 교체(r4b copy C-G 와 같은 값)
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/utils/responsive_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';

const _bizLong = '강남 물류센터 제2물류동 야간 분류팀';
const _bizShort = 'QA';

typedef _Item = ({String id, String host, List<String> parts, List<String> details, Widget Function() build});
typedef _Cond = ({String id, double w, double h, double s});

final List<_Item> _items = [
  (id: 'consent_long', host: 'sheet', parts: DocumentAccessConsent.partsFor(_bizLong),
    details: DocumentAccessConsent.detailsFor(_bizLong), build: () => DocumentAccessConsent.card(_bizLong)),
  (id: 'consent_short', host: 'sheet', parts: DocumentAccessConsent.partsFor(_bizShort),
    details: DocumentAccessConsent.detailsFor(_bizShort), build: () => DocumentAccessConsent.card(_bizShort)),
  (id: 'invite_long', host: 'sheet', parts: DocumentAccessConsent.invitePartsFor(_bizLong),
    details: DocumentAccessConsent.inviteDetailsFor(_bizLong), build: () => DocumentAccessConsent.inviteCard(_bizLong)),
  (id: 'alert_consent', host: 'alert', parts: DocumentAccessConsent.partsFor(_bizShort),
    details: DocumentAccessConsent.detailsFor(_bizShort), build: () => DocumentAccessConsent.card(_bizShort)),
];
const List<_Cond> _conds = [
  (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
  (id: 'M360', w: 360.0, h: 780.0, s: 1.5),
  (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
];

/// 옛 시험 _lineInfo 의 끊김 규칙(du1_info_card_288_test.dart:135–173)을 그대로 옮긴 것.
int _syllableBreaks(RenderParagraph rp) {
  final raw = rp.text.toPlainText();
  final wj = String.fromCharCode(0x2060);
  final zw = String.fromCharCode(0x200B);
  bool word(String ch) {
    final u = ch.codeUnitAt(0);
    return (u >= 0xAC00 && u <= 0xD7A3) || (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) ||
        (u >= 0x61 && u <= 0x7A);
  }

  int? lastTop;
  var lastIdx = -1;
  var breaks = 0;
  for (var i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (ch == wj) continue;
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty || ch == ' ' || ch == zw) continue;
    final top = bx.first.top.round();
    if (lastTop != null && top != lastTop) {
      final gap = raw.substring(lastIdx, i + 1);
      final sep = gap.contains(' ') || gap.contains(zw) || gap.contains(String.fromCharCode(10)) ||
          RegExp('[·,./()~-]').hasMatch(gap);
      if (!sep && word(raw[lastIdx]) && word(ch)) breaks++;
    }
    lastTop = top;
    lastIdx = i;
  }
  return breaks;
}

/// 옛 시험 _tpWidth(:175–181) — 낱말 하나의 그려진 폭.
double _tpWidth(String text, TextStyle? style, TextScaler scaler, Locale? locale) {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr,
      textScaler: scaler, locale: locale)
    ..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

/// 가장 긴 낱말 폭(옛 :374–377 — WJ 로 묶인 글이면 낱말도 묶어 잰다).
double _maxTokenWidth(RenderParagraph rp, BuildContext ctx) {
  final rawShown = rp.text.toPlainText();
  final shown = TextLayout.plain(rawShown);
  final joined = rawShown.contains(String.fromCharCode(0x2060));
  final scaler = MediaQuery.textScalerOf(ctx);
  final loc = Localizations.maybeLocaleOf(ctx);
  var maxTok = 0.0;
  for (final tok in shown.split(RegExp('[ \n]+'))) {
    if (tok.isEmpty) continue;
    maxTok = math.max(maxTok, _tpWidth(joined ? TextLayout.keepWords(tok) : tok, rp.text.style, scaler, loc));
  }
  return maxTok;
}

void main() {
  for (final c in _conds) {
    for (final it in _items) {
      testWidgets('PNL ${c.id} ${it.id}', (t) async {
        final overflow = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            overflow.add(m.split('\n').first);
          } else {
            prev?.call(d);
          }
        };
        addTearDown(() => FlutterError.onError = prev);
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        Widget app(Widget home) => MaterialApp(
              builder: (ctx, child) => MediaQuery(
                  data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
              home: home,
            );
        if (it.host == 'sheet') {
          await t.pumpWidget(app(Scaffold(body: SingleChildScrollView(child: Builder(
              builder: (ctx) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(ctx, 16), vertical: 16),
                  child: it.build()))))));
        } else {
          await t.pumpWidget(app(Scaffold(body: Builder(builder: (ctx) => Center(child: ElevatedButton(
              onPressed: () => showDialog<void>(context: ctx, builder: (_) => AlertDialog(
                  scrollable: true, content: it.build(),
                  actions: [TextButton(onPressed: () {}, child: const Text('확인'))])),
              child: const Text('열기')))))));
          await t.tap(find.text('열기'));
        }
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        final body = find.byKey(const ValueKey('documentAccessConsentBody'));
        expect(body, findsOneWidget);
        final bodyR = t.getRect(body);
        final ctxIn = t.element(body);
        final inner = bodyR.width - 2 * ResponsiveHelper.spacing(ctxIn, 14) - 2.0;
        final texts = find.descendant(of: body, matching: find.byType(Text)).evaluate().toList()
          ..sort((a, b) => t.getRect(find.byElementPredicate((e) => e == a)).top
              .compareTo(t.getRect(find.byElementPredicate((e) => e == b)).top));
        expect(texts.length, it.parts.length, reason: '문단 수(목적·기간)');
        final enlarged = c.s > 1.0;
        Rect? firstR;
        double? lineCy;
        for (var i = 0; i < texts.length; i++) {
          final e = texts[i];
          final tw = e.widget as Text;
          final rpF = find.descendant(of: find.byElementPredicate((x) => x == e), matching: find.byType(RichText)).first;
          final rp = t.renderObject<RenderParagraph>(rpF);
          final r = t.getRect(rpF);
          final shown = TextLayout.plain(rp.text.toPlainText());
          expect(shown, it.parts[i], reason: '문단 ${i + 1} 보이는 글자');
          expect(tw.semanticsLabel ?? tw.data, it.parts[i], reason: '문단 ${i + 1} 읽기 이름');
          expect(rp.didExceedMaxLines, isFalse, reason: '문단 ${i + 1} 말줄임');
          // 옛 :414 — 긴 낱말(가장 긴 낱말 폭 > 글 폭 + 0.5)이면 음절 끊김을 단언하지 않는다(관측만).
          final longToken = _maxTokenWidth(rp, ctxIn) > rp.constraints.maxWidth + 0.5;
          final syl = _syllableBreaks(rp);
          if (!longToken) expect(syl, 0, reason: '문단 ${i + 1} 음절 끊김');
          // ignore: avoid_print
          print('CONSENT-R4d PNL ${c.id} ${it.id} part${i + 1} longToken=$longToken sylBreaks=$syl');
          expect(rp.text.style?.color, AppColors.textPrimary, reason: '중립 본문');
          if (enlarged) {
            expect(rp.constraints.maxWidth, greaterThanOrEqualTo(inner - 0.5), reason: '큰 글자 글 폭');
          }
          if (i == 0) {
            firstR = r;
            final bx = rp.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1));
            if (bx.isNotEmpty) lineCy = r.top + (bx.first.top + bx.first.bottom) / 2;
          }
        }
        final iconF = find.descendant(of: body, matching: find.byType(Icon));
        expect(iconF, findsOneWidget);
        expect(t.widget<Icon>(iconF).icon, Icons.info_outline);
        final iconR = t.getRect(iconF);
        if (enlarged) {
          expect(iconR.bottom, lessThanOrEqualTo(firstR!.top + 0.5), reason: '큰 글자 = 아이콘이 글 위');
        } else {
          expect(iconR.right, lessThanOrEqualTo(firstR!.left + 0.5), reason: '기본 배율 = 아이콘이 글 옆');
        }
        // ignore: avoid_print
        print('CONSENT-R4c PNL ${c.id} ${it.id} iconDy=${lineCy == null ? null : (iconR.center.dy - lineCy).toStringAsFixed(2)}');
        final toggle = find.byKey(const ValueKey('documentAccessConsentDetailsToggle'));
        await t.ensureVisible(toggle);
        await t.pump();
        expect(toggle.hitTestable(), findsOneWidget, reason: '자세히 — 동의 전에 누를 수 있다');
        final ts = t.getSize(toggle);
        expect(ts.height >= 48 - 0.01 && ts.width >= 48 - 0.01, isTrue, reason: '자세히 48 $ts');
        await t.tap(toggle);
        await t.pump();
        for (final d in it.details) {
          expect(find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == d), findsOneWidget, reason: d);
        }
        await t.ensureVisible(toggle);
        await t.pump();
        await t.tap(toggle);
        await t.pump();
        expect(find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == it.details.first), findsNothing);
        expect(overflow, isEmpty, reason: '넘침 ${overflow.join(' | ')}');
      });
    }
  }
}
