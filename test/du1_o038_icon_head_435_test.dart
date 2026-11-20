// [DU435 · 후속113 N3 · 자체 판정 셀 · 표시만] DU-O038 업무 유형 아이콘 선택 창 머리.
//   후보: 넓은 brand 그라데이션 띠 · 흰 제목/개수/닫기 → 창과 같은 면 · 작은 brand 타일(brandSurface/brand) · 진한 제목(textPrimary) ·
//     보조 글(textSecondary) · 중립 닫기(grey600). 제목 · 개수는 keepWords + 원문 semantics. 검색/카테고리/격자/선택/반환/닫기 동작은 그대로다.
//   before = 현재 A(icon_picker_dialog c4edbeb7) / strict = 후보(b925bc47). 준비 렌더 진단 diag(1회) W/B/M 3/3 통과.
//   tok 접두 'S938OI' — 공용 lkit tok_prefix 형식(^S\d{3}[A-Z]{1,2}$)에 맞추려고 O038 을 900 더한 번호로 적었다(DU-S038 은 실제 화면이라 피함 · S938 화면 없음).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du435-tb/DU_BEFORE_OBSERVE=435 · TA after/du435-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/pickers/icon_picker_dialog.dart';

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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '435';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du435-tb' && _env['DU_BEFORE_OBSERVE'] == '435') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du435-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
  'brandSurface': AppColors.brandSurface, 'grey600': AppColors.grey600,
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

String _w(List<String> lines) => lines.map((x) => x.replaceAll(' ', '_')).join('|');

/// 글자 뒤 채움 — 가장 가까운 불투명 BoxDecoration/Material 색. 그 전에 그라데이션을 만나면 grad=true.
({Color? c, bool grad}) _fillBehind(Element e) {
  Color? c;
  var grad = false;
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Container && w.decoration is BoxDecoration) {
      final d = w.decoration! as BoxDecoration;
      if (d.gradient != null) {
        grad = true;
        return false;
      }
      if (d.color != null && d.color!.a > 0.99) {
        c = d.color;
        return false;
      }
    }
    if (w is Material && w.color != null && w.color!.a > 0.99) {
      c = w.color;
      return false;
    }
    return true;
  });
  return (c: c, grad: grad);
}

void main() {
  setUpAll(() async {});
  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S938OI-${v.id}-HEAD 아이콘 선택 창 머리 — 띠 제거 · 진한 제목 · brand 타일 · 중립 닫기 · 낱말 경계', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S938OI-${v.id}-HEAD';
        final mode = _before ? 'before' : 'strict';
        _out('D435 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
                  child: TextButton(onPressed: () => IconPickerDialog.show(context: ctx), child: const Text('열기')),
                ),
              ),
            ),
          ),
        ));
        await t.pump();
        await t.tap(find.text('열기'));
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D435 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'HEAD',
            'state': state,
          });
          shots++;
        }

        final dlg = find.byType(Dialog);
        must('창 1', dlg.evaluate().length == 1, '창 ${dlg.evaluate().length}');
        Finder inD(Finder f) => find.descendant(of: dlg, matching: f, skipOffstage: false);
        final titleF = inD(find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == '아이콘 선택', skipOffstage: false));
        final countF = inD(find.byWidgetPredicate((w) => w is RichText && RegExp(r'^\d+개 아이콘$').hasMatch(_plainOf(w)), skipOffstage: false));
        // 격자 목록에도 Icons.close 항목이 있어, 머리(제목을 담은 가장 가까운 Row) 안에서만 찾는다.
        final headF = find.ancestor(of: titleF, matching: find.byType(Row, skipOffstage: false)).first;
        final tileIconF = find.descendant(of: headF, matching: find.byIcon(Icons.auto_awesome, skipOffstage: false), skipOffstage: false);
        final closeF = find.descendant(of: headF, matching: find.byIcon(Icons.close, skipOffstage: false), skipOffstage: false);
        final searchN = inD(find.byType(TextField, skipOffstage: false)).evaluate().length;
        final ns = '${titleF.evaluate().length}/${countF.evaluate().length}/${tileIconF.evaluate().length}/${closeF.evaluate().length}/$searchN';
        must('머리 요소 · 검색 1', ns == '1/1/1/1/1', ns);
        await shot('1open', 'dialog-open');

        // ── 머리 측정(값은 즉시) ──
        final trp = t.renderObject(titleF) as RenderParagraph;
        final tj = _lines(trp);
        final tEx = trp.didExceedMaxLines;
        final tMax = trp.constraints.maxWidth;
        final crp = t.renderObject(countF) as RenderParagraph;
        final cj = _lines(crp);
        final cEx = crp.didExceedMaxLines;
        final tColor = (t.widget(titleF) as RichText).text.style?.color;
        final cColor = (t.widget(countF) as RichText).text.style?.color;
        final tFill = _fillBehind(titleF.evaluate().first);
        final cFill = _fillBehind(countF.evaluate().first);
        Color? tileBg;
        tileIconF.evaluate().first.visitAncestorElements((a) {
          final w = a.widget;
          if (w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color != null) {
            tileBg = (w.decoration! as BoxDecoration).color;
            return false;
          }
          return true;
        });
        final tileFg = (t.widget(tileIconF) as Icon).color;
        final closeColor = (t.widget(closeF) as Icon).color;
        final closeFill = _fillBehind(closeF.evaluate().first);
        final gradN = inD(find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).gradient != null,
            skipOffstage: false)).evaluate().length;
        final titleCr = tFill.grad ? 0.0 : _cr(tColor, tFill.c);
        final countCr = cFill.grad ? 0.0 : _cr(cColor, cFill.c);
        final closeCr = closeFill.grad ? 0.0 : _cr(closeColor, closeFill.c);
        _out('D435 $tok att head lines=${tj.lines.length} ok=${tj.ok} exceeded=$tEx maxW=${_f2(tMax)} text=${_w(tj.lines)} '
            'countLines=${cj.lines.length} countOk=${cj.ok} countEx=$cEx gradN=$gradN');
        _out('D435 $tok att color title=${_tok(tColor)} titleGrad=${tFill.grad} titleCr=${_f2(titleCr)} count=${_tok(cColor)} countCr=${_f2(countCr)} '
            'tile=${_tok(tileBg)} tileIcon=${_tok(tileFg)} tileCr=${_f2(_cr(tileFg, tileBg))} close=${_tok(closeColor)} closeCr=${_f2(closeCr)}');

        // ── 닫기 → 창 닫힘 ──
        await t.tap(closeF);
        for (var i = 0; i < 5; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        final closed = find.byType(Dialog).evaluate().isEmpty;
        _out('D435 $tok att close closed=$closed');

        must('닫기 → 창 닫힘', closed, '닫힘 $closed');
        if (_before) {
          // 음성 기대 — base 머리는 넓은 그라데이션 띠(코드 확정) · 제목 흰 글자.
          must('before 그라데이션 머리 · 흰 제목 검출', gradN >= 1 && tFill.grad && tColor == const Color(0xFFFFFFFF), '그라데이션 $gradN ${_tok(tColor)}');
        } else {
          must('strict 그라데이션 0', gradN == 0, '그라데이션 $gradN');
          must('strict 제목 · 개수 낱말 경계 · 말줄임 0', tj.ok && !tEx && cj.ok && !cEx, '${_w(tj.lines)} $tEx ${_w(cj.lines)} $cEx');
          must('strict 제목 textPrimary · 대비 ≥ 4.5', tColor == AppColors.textPrimary && titleCr >= 4.5, '${_tok(tColor)} ${_f2(titleCr)}');
          must('strict 개수 textSecondary · 대비 ≥ 4.5', cColor == AppColors.textSecondary && countCr >= 4.5, '${_tok(cColor)} ${_f2(countCr)}');
          must('strict 타일 brandSurface/brand · 대비 ≥ 3', tileBg == AppColors.brandSurface && tileFg == AppColors.brand && _cr(tileFg, tileBg) >= 3,
              '${_tok(tileBg)} ${_tok(tileFg)}');
          must('strict 닫기 grey600 · 대비 ≥ 3', closeColor == AppColors.grey600 && closeCr >= 3, '${_tok(closeColor)} ${_f2(closeCr)}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D435 $tok done state=HEAD mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
