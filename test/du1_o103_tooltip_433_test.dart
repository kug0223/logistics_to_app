// [DU433 · 자체 판정 셀 · 표시만] DU-O103 첫 사용 안내 창(_TooltipDialog).
//   후보: 넓은 그라데이션 머리 · 흰 제목 → 흰 머리 · 작은 의미색 타일(배지 Bg/Dark 짝) · 진한 제목.
//     - 좁은 창 · 큰 글자에서는 타일을 제목 위로 올린다.
//     - 팁 묶음은 그림자 0 · background 면 · textSecondary 글자.
//     - 확인은 CommonWidgets.primaryButton(브랜드)이다.
//   before = 현재 A(tooltip_service 6e6c796e) / strict = 후보(28b023a8). 준비 렌더 진단 diag(1회) 10/10 통과.
//   사례: REVIEW(TooltipContents.showFirstReview · amber · 팁 3) · APPLY(showFirstApplication · 색 없음 · 팁 2).
//     실제 진입 경로(TooltipService.showOnce → showDialog)로 연다.
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du433-tb/DU_BEFORE_OBSERVE=433 · TA after/du433-ta/없음.
//   tok 접두 'S103OT' — 공용 lkit 이 tok_prefix 를 ^S\d{3}[A-Z]{1,2}$(화면용)로 강제해 O103 을 'S103' + OT(Overlay Tooltip)로 적었다. S103 화면은 없다.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/services/tooltip_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';

Future<void> _loadFonts() async {
  Future<ByteData> b(String p) => File(p).readAsBytes().then((x) => ByteData.view(x.buffer));
  for (final fam in const ['NotoSansKR', 'Roboto']) {
    final l = FontLoader(fam)
      ..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))
      ..addFont(b('assets/fonts/NotoSansKR-Bold.ttf'));
    await l.load();
  }
  final testDefault = FontLoader('FlutterTest')..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'));
  await testDefault.load();
  final icons = FontLoader('MaterialIcons')..addFont(b('C:/Users/kug02/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf'));
  await icons.load();
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '433';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du433-tb' && _env['DU_BEFORE_OBSERVE'] == '433') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du433-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f2(double v) => v.toStringAsFixed(2);
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

final String _zwsp = String.fromCharCode(0x200B);
final String _wj = String.fromCharCode(0x2060);
final String _nbsp = String.fromCharCode(0x00A0);
bool _visible(String ch) => ch.trim().isNotEmpty && ch != _zwsp && ch != _wj && ch != _nbsp;

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textPrimary': AppColors.textPrimary, 'textSecondary': AppColors.textSecondary, 'brand': AppColors.brand,
  'brandSurface': AppColors.brandSurface, 'warningBg': AppColors.warningBg, 'warningDark': AppColors.warningDark,
  'successBg': AppColors.successBg, 'successDark': AppColors.successDark, 'infoBg': AppColors.infoBg, 'infoDark': AppColors.infoDark,
  'background': AppColors.background, 'grey600': AppColors.grey600, 'grey700': AppColors.grey700, 'amber': AppColors.amber,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${c.toARGB32().toRadixString(16).padLeft(8, '0')}';
}

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// 줄 나눔(DU432 진단 · DU433 진단과 같은 방식) — 줄 글자 · 낱말 경계 ok(명시 줄바꿈 '\n' 은 경계로 본다).
({List<String> lines, bool ok}) _lines(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final tops = <double>[];
  final lineOf = List<int>.filled(s.length, -1);
  var missing = 0;
  for (var i = 0; i < s.length; i++) {
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (boxes.isEmpty) {
      if (_visible(s[i])) missing++;
      continue;
    }
    var k = tops.indexWhere((x) => (x - boxes.first.top).abs() < 0.5);
    if (k < 0) {
      tops.add(boxes.first.top);
      k = tops.length - 1;
    }
    lineOf[i] = k;
  }
  if (tops.isEmpty) return (lines: const <String>[], ok: false);
  final order = List<int>.generate(tops.length, (i) => i)..sort((a, b) => tops[a].compareTo(tops[b]));
  final rank = List<int>.filled(tops.length, 0);
  for (var r = 0; r < order.length; r++) {
    rank[order[r]] = r;
  }
  final buf = List<StringBuffer>.generate(tops.length, (_) => StringBuffer());
  var ok = true;
  var prev = -1;
  var cur = 0;
  for (var i = 0; i < s.length; i++) {
    if (lineOf[i] >= 0) {
      final ln = rank[lineOf[i]];
      if (prev >= 0 && ln != prev) {
        final b = i > 0 ? s[i - 1] : '';
        if (!(b == ' ' || b == _zwsp || b == '\n' || s[i] == ' ' || s[i] == '\n')) ok = false;
      }
      prev = ln;
      cur = ln;
    }
    buf[cur].write(s[i]);
  }
  return (lines: [for (final b in buf) TextLayout.plain(b.toString()).trim()], ok: ok && missing == 0);
}

String _w(List<String> lines) => lines.map((x) => x.replaceAll(' ', '_').replaceAll('\n', '/')).join('|');

/// 글자 뒤 채움색 — 가장 가까운 불투명 Material · Container/DecoratedBox 의 BoxDecoration 색.
Color? _fillBehind(Element e) {
  Color? c;
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Material && w.color != null && w.color!.a > 0) {
      c = w.color;
      return false;
    }
    if (w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color != null) {
      c = (w.decoration! as BoxDecoration).color;
      return false;
    }
    if (w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color != null) {
      c = (w.decoration as BoxDecoration).color;
      return false;
    }
    return true;
  });
  return c;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'REVIEW', title: '첫 리뷰 작성이시네요!', icon: Icons.rate_review, tileBg: AppColors.warningBg, tileFg: AppColors.warningDark,
        tip: '평점과 태그는 지원자가 볼 수 있어요.', caption: '첫 리뷰 안내 창(amber · 팁 3) — 머리 · 확인 버튼 · 팁 묶음'),
    (key: 'APPLY', title: '첫 지원이시네요!', icon: Icons.assignment_turned_in, tileBg: AppColors.brandSurface, tileFg: AppColors.brand,
        tip: '불참이 예상되면 미리 연락해주세요.', caption: '첫 지원 안내 창(브랜드 · 팁 2) — 머리 · 확인 버튼 · 팁 묶음'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S103OT-${v.id}-${st.key} ${st.caption}', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        try {
          final tok = 'S103OT-${v.id}-${st.key}';
          final mode = _before ? 'before' : 'strict';
          _out('D433 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
          await t.runAsync(_loadFonts);
          final overflows = <String>[];
          final fwErrors = <String>[];
          final prev = FlutterError.onError;
          FlutterError.onError = (d) {
            final m = d.exceptionAsString();
            if (m.contains('overflowed')) {
              overflows.add(m.split('\n').first);
            } else {
              fwErrors.add(m.split('\n').first);
              prev?.call(d);
            }
          };
          addTearDown(() => FlutterError.onError = prev);
          t.view.physicalSize = Size(v.w, v.h);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          SharedPreferences.setMockInitialValues(<String, Object>{});
          void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');

          final key = GlobalKey();
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.businessAdminTheme,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => Center(
                    child: TextButton(
                      onPressed: () {
                        if (st.key == 'REVIEW') {
                          TooltipContents.showFirstReview(ctx);
                        } else {
                          TooltipContents.showFirstApplication(ctx);
                        }
                      },
                      child: const Text('열기'),
                    ),
                  ),
                ),
              ),
            ),
          ));
          await t.pump();
          await t.tap(find.text('열기'));
          for (var i = 0; i < 10; i++) {
            await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
            await t.pump(const Duration(milliseconds: 100));
          }
          var shots = 0;
          Future<void> shot(String sub, String state) async {
            _out('D433 $tok shot $sub ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_$sub', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key,
              'state': state,
            });
            shots++;
          }

          final dlg = find.byType(Dialog);
          must('창 1', dlg.evaluate().length == 1, '${dlg.evaluate().length}개');
          Finder inD(Finder f) => find.descendant(of: dlg, matching: f, skipOffstage: false);
          final titleF = inD(find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == st.title, skipOffstage: false));
          final iconF = inD(find.byIcon(st.icon, skipOffstage: false));
          must('제목 · 아이콘 1', titleF.evaluate().length == 1 && iconF.evaluate().length == 1,
              '${titleF.evaluate().length} ${iconF.evaluate().length}');
          await shot('1open', 'dialog-open');

          // ── 머리 — 타일(아이콘 위 BoxDecoration Container) · 제목 · 배치(값은 즉시 지역 값) ──
          Element? tileEl;
          iconF.evaluate().first.visitAncestorElements((a) {
            final w = a.widget;
            if (w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color != null) {
              tileEl = a;
              return false;
            }
            return true;
          });
          final tileR = tileEl == null ? Rect.zero : t.getRect(find.byElementPredicate((e) => identical(e, tileEl), skipOffstage: false));
          final tileBg = tileEl == null ? null : ((tileEl!.widget as Container).decoration! as BoxDecoration).color;
          final iconColor = (t.widget(iconF) as Icon).color;
          final titleR = t.getRect(titleF);
          final titleColor = (t.widget(titleF) as RichText).text.style?.color;
          final titleJ = _lines(t.renderObject(titleF) as RenderParagraph);
          final titleExceeded = (t.renderObject(titleF) as RenderParagraph).didExceedMaxLines;
          final titleMaxW = (t.renderObject(titleF) as RenderParagraph).constraints.maxWidth;
          final stacked = titleR.top >= tileR.bottom - 0.5;
          _out('D433 $tok att head stacked=$stacked titleLines=${titleJ.lines.length} ok=${titleJ.ok} exceeded=$titleExceeded '
              'titleColor=${_tok(titleColor)} tileBg=${_tok(tileBg)} icon=${_tok(iconColor)} titleMaxW=${_f2(titleMaxW)} text=${_w(titleJ.lines)}');

          // ── 모든 문단 — 낱말 경계 · 말줄임 ──
          final bad = <String>[];
          var paraN = 0;
          for (final e in inD(find.byWidgetPredicate((w) => w is RichText && _plainOf(w).trim().isNotEmpty, skipOffstage: false)).evaluate()) {
            final rp = e.renderObject;
            if (rp is! RenderParagraph) continue;
            paraN++;
            final j = _lines(rp);
            if (!j.ok || rp.didExceedMaxLines) bad.add(_w(j.lines));
          }
          _out('D433 $tok att paras n=$paraN bad=${bad.length} badText=${bad.isEmpty ? '-' : base64Url.encode(utf8.encode(bad.join(';'))).replaceAll('=', '')}');

          // ── 색 — 팁 글자 · 면, 그라데이션 · 그림자 ──
          final tipF = inD(find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == st.tip, skipOffstage: false));
          final tipN = tipF.evaluate().length;
          final tipColor = tipN == 1 ? (t.widget(tipF) as RichText).text.style?.color : null;
          final tipFill = tipN == 1 ? _fillBehind(tipF.evaluate().first) : null;
          final gradN = inD(find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).gradient != null,
              skipOffstage: false)).evaluate().length;
          final shadowN = inD(find.byWidgetPredicate(
              (w) => w is Container && w.decoration is BoxDecoration && ((w.decoration! as BoxDecoration).boxShadow ?? const <BoxShadow>[]).isNotEmpty,
              skipOffstage: false)).evaluate().length;
          _out('D433 $tok att color tipN=$tipN tip=${_tok(tipColor)} tipFill=${_tok(tipFill)} tipCr=${_f2(_cr(tipColor, tipFill))} gradN=$gradN shadowN=$shadowN');

          // ── 확인 — 도달 · 채움 · 대비 · 높이 · 닫기 ──
          final okF = inD(find.text('확인', skipOffstage: false));
          must('확인 1', okF.evaluate().length == 1, '${okF.evaluate().length}개');
          await t.ensureVisible(okF);
          await t.pump(const Duration(milliseconds: 300));
          final okRich = find.descendant(of: okF, matching: find.byType(RichText, skipOffstage: false), skipOffstage: false);
          final okText = (t.widget(okRich.first) as RichText).text.style?.color;
          final okFill = _fillBehind(okRich.evaluate().first);
          final okCr = _cr(okText, okFill);
          final inkR = t.getRect(find.ancestor(of: okF, matching: find.byType(InkWell, skipOffstage: false)).first);
          final okInView = inkR.top >= -0.5 && inkR.bottom <= v.h + 0.5;
          await shot('2ok', 'ok-visible');
          await t.tap(okF);
          for (var i = 0; i < 5; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          final closed = find.byType(Dialog).evaluate().isEmpty;
          _out('D433 $tok att ok h=${_f2(inkR.height)} text=${_tok(okText)} fill=${_tok(okFill)} cr=${_f2(okCr)} inView=$okInView closed=$closed');

          must('확인 화면 안 · 탭 → 닫힘', okInView && closed, '$okInView $closed');
          if (_before) {
            // 음성 기대 — base 머리는 넓은 그라데이션 띠(코드 확정)이고, REVIEW 확인은 흰 글자 / amber 채움(1.63)이다.
            must('before 그라데이션 머리 검출', gradN >= 1, '그라데이션 $gradN');
            if (st.key == 'REVIEW') must('before REVIEW 확인 대비 미달 검출', okCr < 4.5, _f2(okCr));
          } else {
            must('strict 머리 배치(W 가로 · B 쌓기)', stacked == (v.id == 'B'), '쌓기 $stacked');
            must('strict 제목 진한 글자 · 낱말 경계 · 말줄임 0', titleColor == AppColors.textPrimary && titleJ.ok && !titleExceeded,
                '${_tok(titleColor)} ${titleJ.ok} $titleExceeded');
            must('strict 타일 짝', tileBg == st.tileBg && iconColor == st.tileFg, '${_tok(tileBg)} ${_tok(iconColor)}');
            must('strict 타일 아이콘 대비 ≥ 3', _cr(iconColor, tileBg) >= 3.0, _f2(_cr(iconColor, tileBg)));
            must('strict 모든 문단 경계 · 말줄임 0', bad.isEmpty, bad.join(' ; '));
            must('strict 팁 textSecondary / background · 대비 ≥ 4.5', tipN == 1 && tipColor == AppColors.textSecondary && tipFill == AppColors.background &&
                _cr(tipColor, tipFill) >= 4.5, '$tipN ${_tok(tipColor)} ${_tok(tipFill)}');
            must('strict 그라데이션 · 그림자 0', gradN == 0 && shadowN == 0, '$gradN $shadowN');
            must('strict 확인 브랜드 · 흰 글자 · 대비 ≥ 4.5 · 높이 ≥ 51.5', okFill == AppColors.brand && okText == const Color(0xFFFFFFFF) && okCr >= 4.5 &&
                inkR.height >= 51.5, '${_tok(okFill)} ${_tok(okText)} ${_f2(okCr)} ${_f2(inkR.height)}');
            must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
          }
          must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
          final exc = t.takeException();
          _out('D433 $tok done state=${st.key} mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
          must('끝 예외 0', exc == null, '예외 $exc');
        } catch (e) {
          _anyFail = true;
          rethrow;
        }
      }, skip: !_optIn);
    }
  }
}
