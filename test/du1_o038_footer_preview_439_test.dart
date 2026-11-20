// [DU439 · 자체 판정 셀 · 표시만] DU-O038 아이콘 선택 창 하단 선택 미리보기 — 좁으면 '선택 해제'를 아래 줄로 · 선택 이름 낱말 경계 · '선택 해제' textSecondary.
//   DU438 준비 진단에서 발견한 기존 결함(B 선택 뒤 '재/고/관/리…' 세로 쌓임 · 하단 넘침). before = 현재 A(b925bc47) / strict = 후보(24b98b46).
//   tok 접두 'S938OF' — O038(+900) · Footer. 값은 닿은 즉시 지역 값으로. 기본 skip — TB before/du439-tb/DU_BEFORE_OBSERVE=439 · TA after/du439-ta/없음.
import 'dart:convert';
import 'dart:io';

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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '439';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du439-tb' && _env['DU_BEFORE_OBSERVE'] == '439') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du439-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S938OF-${v.id}-PICK 아이콘 선택 창 하단 선택 미리보기 — 좁으면 선택 해제 아래 줄 · 이름 낱말 경계 · 넘침 0', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S938OF-${v.id}-PICK';
        final mode = _before ? 'before' : 'strict';
        _out('D439 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
          _out('D439 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'PICK',
            'state': state,
          });
          shots++;
        }

        final dlg = find.byType(Dialog);
        must('창 1', dlg.evaluate().length == 1, '창 ${dlg.evaluate().length}');
        Finder inD(Finder f) => find.descendant(of: dlg, matching: f, skipOffstage: false);

        await shot('1open', 'dialog-open');

        // ── 첫 칸 탭 → 아래 '… 선택됨' · 선택 완료 버튼(값은 즉시) ──
        final iconF = inD(find.byIcon(first.icon, skipOffstage: false));
        must('첫 아이콘 있음', iconF.evaluate().isNotEmpty, '아이콘 ${iconF.evaluate().length}');
        await t.tap(iconF.first);
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        // ── 선택 뒤 하단 미리보기(값은 즉시) ──
        final chosenF = inD(find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == '${first.label} 선택됨', skipOffstage: false));
        final chosenN = chosenF.evaluate().length;
        final clearF = inD(find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == '선택 해제', skipOffstage: false));
        final clearN = clearF.evaluate().length;
        var cLines = 0;
        var cOk = false;
        var cEx = true;
        var stackedClear = false;
        var clearColor = '-';
        var clearInView = false;
        if (chosenN == 1 && clearN == 1) {
          final rp = chosenF.evaluate().first.renderObject! as RenderParagraph;
          final j = _lines(rp);
          cLines = j.lines.length;
          cOk = j.ok;
          cEx = rp.didExceedMaxLines;
          final lr = t.getRect(chosenF.first);
          final cr = t.getRect(clearF.first);
          stackedClear = cr.top >= lr.bottom - 0.5;
          clearColor = _tok((t.widget(clearF.first) as RichText).text.style?.color);
          clearInView = cr.top >= -0.5 && cr.bottom <= v.h + 0.5;
        }
        final ovfAfterPick = overflows.length;
        await shot('2chosen', 'icon-chosen');
        _out('D439 $tok att pick chosenN=$chosenN clearN=$clearN lines=$cLines ok=$cOk exceeded=$cEx stackedClear=$stackedClear clear=$clearColor '
            'clearInView=$clearInView ovf=$ovfAfterPick');

        must('첫 칸 탭 → 선택됨 안내 1 · 선택 해제 1', chosenN == 1 && clearN == 1, '$chosenN $clearN');
        if (_before) {
          if (v.id == 'B') {
            // 음성 기대 — base B 선택 뒤 미리보기 글이 한 글자씩 세로로 쌓이고 하단이 넘친다(DU438 진단 원PNG 관측 · 같은 코드).
            must('before B 선택 이름 끊김 · 하단 넘침 검출', !cOk && ovfAfterPick >= 1, '$cOk $ovfAfterPick');
          }
        } else {
          must('strict 선택 이름 낱말 경계 · 말줄임 0', cOk && !cEx, '$cLines $cOk $cEx');
          must('strict 선택 해제 배치(W 같은 줄 · B 아래 줄) · 화면 안 · textSecondary', stackedClear == (v.id == 'B') && clearInView && clearColor == 'textSecondary',
              '$stackedClear $clearInView $clearColor');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D439 $tok done state=PICK mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
