// [DU438 · 자체 판정 셀 · 표시만] DU-O038 아이콘 선택 창 — 격자 이름(좁으면 접고 아이콘만 · 이름은 Semantics/선택됨 안내) · '선택 완료' 낱말 경계.
//   before = 현재 A(icon_picker_dialog b925bc47 = DU435 후보) / strict = 후보(9297b0ac). 사용자 11-18 '한도 초기화 전까지 계속' 자체 선정 셀.
//   tok 접두 'S938OG' — O038(+900) · Grid. 값은 닿은 즉시 지역 값으로. 기본 skip — TB before/du438-tb/DU_BEFORE_OBSERVE=438 · TA after/du438-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '438';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du438-tb' && _env['DU_BEFORE_OBSERVE'] == '438') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du438-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

final String _zwsp = String.fromCharCode(0x200B);
final String _wj = String.fromCharCode(0x2060);
final String _nbsp = String.fromCharCode(0x00A0);
bool _visible(String ch) => ch.trim().isNotEmpty && ch != _zwsp && ch != _wj && ch != _nbsp;

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

/// 글자 뒤 채움 — 가장 가까운 불투명 BoxDecoration/Material 색. 그 전에 그라데이션을 만나면 grad=true.

void main() {
  setUpAll(() async {});
  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  final first = IconPickerDialog.getAllIcons().first;
  for (final v in views) {
    testWidgets('S938OG-${v.id}-GRID 아이콘 선택 격자 이름 · 선택 완료 — 좁으면 아이콘만 · 낱말 경계 · 선택됨 안내', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S938OG-${v.id}-GRID';
        final mode = _before ? 'before' : 'strict';
        _out('D438 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
          _out('D438 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'GRID',
            'state': state,
          });
          shots++;
        }

        final dlg = find.byType(Dialog);
        must('창 1', dlg.evaluate().length == 1, '창 ${dlg.evaluate().length}');
        Finder inD(Finder f) => find.descendant(of: dlg, matching: f, skipOffstage: false);

        // ── 격자 첫 칸 이름(값은 즉시) ──
        final labelF = inD(find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == first.label, skipOffstage: false));
        final labelN = labelF.evaluate().length;
        var labelEx = false;
        var labelClip = false;
        var labelLines = 0;
        var labelOk = true;
        if (labelN >= 1) {
          final rp = labelF.evaluate().first.renderObject! as RenderParagraph;
          labelEx = rp.didExceedMaxLines;
          // 높이 30 상자 안에서 줄이 잘리면 didExceedMaxLines 가 false 여도 보이는 글이 모자란다 — 필요 높이 > 배정 높이도 잘림으로 본다.
          labelClip = labelEx || rp.size.height + 0.5 < rp.getMaxIntrinsicHeight(rp.size.width);
          final j = _lines(rp);
          labelLines = j.lines.length;
          labelOk = j.ok;
        }
        final semN = inD(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == first.label, skipOffstage: false)).evaluate().length;
        _out('D438 $tok att grid labelN=$labelN labelLines=$labelLines labelOk=$labelOk labelEx=$labelEx labelClip=$labelClip semN=$semN');
        await shot('1open', 'dialog-open');

        // ── 첫 칸 탭 → 아래 '… 선택됨' · 선택 완료 버튼(값은 즉시) ──
        final iconF = inD(find.byIcon(first.icon, skipOffstage: false));
        must('첫 아이콘 있음', iconF.evaluate().isNotEmpty, '아이콘 ${iconF.evaluate().length}');
        await t.tap(iconF.first);
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        final chosenN = inD(find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == '${first.label} 선택됨', skipOffstage: false)).evaluate().length;
        final okF = inD(find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == '선택 완료', skipOffstage: false));
        final okN = okF.evaluate().length;
        var okLines = 0;
        var okOk = false;
        var okEx = true;
        if (okN == 1) {
          final rp = okF.evaluate().first.renderObject! as RenderParagraph;
          final j = _lines(rp);
          okLines = j.lines.length;
          okOk = j.ok;
          okEx = rp.didExceedMaxLines;
        }
        await t.ensureVisible(okF.first);
        await t.pump(const Duration(milliseconds: 200));
        await shot('2chosen', 'icon-chosen');
        _out('D438 $tok att chosen chosenN=$chosenN okN=$okN okLines=$okLines okOk=$okOk okEx=$okEx');

        must('첫 칸 탭 → 선택됨 안내 1 · 선택 완료 1', chosenN == 1 && okN == 1, '$chosenN $okN');
        if (_before) {
          if (v.id == 'B') {
            // 음성 기대 — base B 격자 이름은 1–2 글자만 보이고 넘친다 · '선택 완 / 료' 음절 끊김(DU435 진단 원PNG 관측).
            must('before B 격자 이름 잘림 · 선택 완료 끊김 검출', labelN >= 1 && labelClip && !okOk, '$labelN $labelClip $okOk');
          }
        } else {
          if (v.id == 'W') {
            must('strict W 격자 이름 보임 · 잘림 0 · 경계', labelN == 1 && !labelClip && labelOk, '$labelN $labelClip $labelOk');
          } else {
            must('strict B 격자 이름 접힘 · 화면 읽기 이름 있음', labelN == 0 && semN >= 1, '$labelN $semN');
          }
          must('strict 선택 완료 낱말 경계 · 말줄임 0', okOk && !okEx, '$okLines $okOk $okEx');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D438 $tok done state=GRID mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
