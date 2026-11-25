// [DU602b · 파일 셀 · 표시만] DU-S047 근무자 앱 소개 투어(lib/screens/common/tour_screen.dart) 결정 미이행 2행 —
//   장부 047 · 판정156 Q4 :47: 4쪽 기능 줄 '노쇼 3회(90일) → 지원 제한' → '… → 이용 제한'(기간 제한의 일반 상태명).
//   장부 046 · 판정156 Q2 :31: 4쪽 제목 둘째 줄 '노쇼 없이 더 많은 기회 얻기' → '약속 지켜 더 많은 기회 얻기'(낙인 · 위협보다 약속을 앞세움 · J-TITLE 보수안).
//   before = 지금 A(tour_screen 08cd2161 = DU314 후보) 기록 · strict = 후보(cand/ · mkcell 이 SHA 대조).
//   하네스 = 블록 재사용(prep/mk_test.py 가 원본 fullSHA · 블록 sha12 · 경계 줄 단언): DU595b suite(7e30c11e · 판정177 §5 수용) —
//     글꼴 · max 판 _fullShown · _textObs · _area · _lineCount · 보기 W/B/N · _halt · env 줄 · _DSeen · _txt · _semOf · _textLine · 색 도우미 · _fills · _inkOf /
//     DU581 r3 suite(3f4a404a · DONE 5/5) — _hitWithin. 가짜 Firebase 0(투어는 Firebase · provider 를 쓰지 않는다 — 대역 import 0 · 파일 전체 억제 줄 0).
//   새로 쓴 것: 이 머리 · 사례 1(TOUR) · 글 상수 · 제목 끝줄 도달 _tail · 사례 본문 _caseOf · main.
//   누르는 것 = 시작 단추 'host'(S047 RG 와 같은 진입 helper pushTourScreen) · CTA '다음' 글 중심(tapAt · 잰 hit 와 같은 점) 3번뿐 — 쓰기 0.
//   기본 skip — TB before/du602btr-tb/DU_BEFORE_OBSERVE=602 · TA after/du602btr-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show BoxHeightStyle;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/common/tour_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';

Future<void> _loadFonts() async {
  Future<ByteData> b(String p) => File(p).readAsBytes().then((x) => ByteData.view(x.buffer));
  for (final fam in const ['NotoSansKR', 'Roboto']) {
    await (FontLoader(fam)
          ..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))
          ..addFont(b('assets/fonts/NotoSansKR-Bold.ttf')))
        .load();
  }
  await (FontLoader('FlutterTest')..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))).load();
  await (FontLoader('MaterialIcons')
        ..addFont(b('C:/Users/kug02/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')))
      .load();
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _enc(String s) => s.isEmpty ? '-' : base64Url.encode(utf8.encode(s)).replaceAll('=', '');

/// [a] 가 [b] **안**에 있는가(0.5px 허용).
bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

final String _wj = String.fromCharCode(0x2060);
final String _zw = String.fromCharCode(0x200B);

bool _gap(String ch) => ch == ' ' || ch == '\n' || ch == '\t' || ch == _zw;

/// 그려진 글(표시 제어 문자 포함) 기준 — 낱말(공백 · 개행 · ZWSP 사이) 안에서 줄이 바뀐 횟수. NBSP · WORD JOINER 로 묶은 덩어리는 한 낱말이다.
int _midBreaks(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  var n = 0;
  double? lastTop;
  var lastIdx = -1;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '\n') {
      lastTop = null;
      lastIdx = i;
      continue;
    }
    if (ch == _wj || ch == _zw) continue;
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = bx.first.top;
    final half = (bx.first.bottom - bx.first.top) / 2;
    final wrapped = lastTop != null && top > lastTop + half;
    if (wrapped) {
      var gap = _gap(ch) || (lastIdx >= 0 && _gap(s[lastIdx]));
      for (var k = lastIdx + 1; k < i; k++) {
        if (_gap(s[k])) gap = true;
      }
      if (!gap) n++;
    }
    if (lastTop == null || wrapped) lastTop = top;
    lastIdx = i;
  }
  return n;
}

/// 글 전문이 그려졌는가 — 마지막 글자까지 자리(box)가 문단 크기 안에 있다(말줄임으로 잘린 글자는 자리가 없다).
bool _fullShown(RenderParagraph rp, Size size) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  for (var i = s.length - 1; i >= 0; i--) {
    final ch = s[i];
    if (ch == _wj || _gap(ch)) continue;
    // [DU560 repair 3 proposed / decision168] Vertical max selection box; horizontal tight right; tolerance unchanged.
    // This measures selection-box placement, not ink bounds or ancestor clipping.
    final sel = TextSelection(baseOffset: i, extentOffset: i + 1);
    final tight = rp.getBoxesForSelection(sel);
    final mx = rp.getBoxesForSelection(sel, boxHeightStyle: ui.BoxHeightStyle.max);
    return tight.isNotEmpty && mx.isNotEmpty && mx.first.bottom <= size.height + 0.5 && tight.first.right <= size.width + 0.5;
  }
  return false;
}

typedef _TextObs = ({bool shown, bool name, bool full, bool ell0, int brk, Size size});

/// Text 하나의 관측값(잰 즉시 값으로 굳힌다) — 그려진 글(표시 제어 문자를 뺀 것) · 읽는 이름이 각각 [want] 원문과 같은가 · 전문 · 말줄임 설정 · 낱말 안 끊김 수.
_TextObs _textObs(WidgetTester t, Finder textF, String want) {
  final rp = t.renderObject<RenderParagraph>(find.descendant(of: textF, matching: find.byType(RichText), skipOffstage: true).first);
  final size = rp.size;
  final shown = TextLayout.plain(rp.text.toPlainText(includeSemanticsLabels: false));
  final name = rp.text.toPlainText();
  return (shown: shown == want, name: name == want, full: _fullShown(rp, size), ell0: rp.overflow != TextOverflow.ellipsis, brk: _midBreaks(rp), size: size);
}

/// [f] 가 실제로 보일 수 있는 칸 — 화면 ∩ 조상 스크롤 칸 전부.
Rect _area(Finder f, Rect screen) {
  var a = screen;
  for (final e in find.ancestor(of: f, matching: find.byType(Scrollable)).evaluate()) {
    final ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize) a = a.intersect(ro.localToGlobal(Offset.zero) & ro.size);
  }
  return a;
}

/// 그려진 문단의 줄 수 — 글자 자리(box)의 서로 다른 top 개수.
int _lineCount(RenderParagraph rp) {
  final n = rp.text.toPlainText(includeSemanticsLabels: false).length;
  final tops = <int>{};
  for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: n))) {
    tops.add(b.top.round());
  }
  return tops.length;
}

typedef _V = ({String id, double w, double h, double s});

const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0), (id: 'N', w: 320.0, h: 640.0, s: 1.0)];

/// [DU602b] 사례 — TOUR = 근무자 투어를 열고 '다음' 3번 → 4쪽('급여 & 근무 이력') · 제목 끝줄(1title) · 기능 줄(2feature).
const _cases = <({String id, int shots})>[(id: 'TOUR', shots: 2)];

/// [DU602b] 이 셀이 보는 글 — mkcell 이 base/후보 원문과 대조한다(before = 옛 글 · strict = 새 글 · 설명은 두 모드 같음).
const _kTitleOld = '급여 명세서 확인,\n노쇼 없이 더 많은 기회 얻기';
const _kTitleNew = '급여 명세서 확인,\n약속 지켜 더 많은 기회 얻기';
const _kFeatOld = '노쇼 3회(90일) → 지원 제한';
const _kFeatNew = '노쇼 3회(90일) → 이용 제한';
const _kDesc = '임금명세서를 앱에서 바로 확인하고\n근무 이력과 노쇼 기록이 투명하게 쌓여요.';
const _kNext = '다음';
const _kLast = '확인';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '602';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du602btr-tb' && _env['DU_BEFORE_OBSERVE'] == '602') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du602btr-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

/// 시각 오류 수집 — 넘침은 원문 전체 + 위치 두 줄, 그 밖 framework 오류도 원문 전체(DU516 r1 과 같다).
class _DSeen {
  final overflows = <String>[];
  final other = <String>[];

  void add(FlutterErrorDetails d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      final full = d.toString();
      final k = full.indexOf('The relevant error-causing widget was');
      final loc = k < 0
          ? ''
          : full.substring(k).split('\n').skip(1).where((l) => l.trim().isNotEmpty).take(2).map((l) => l.trim()).join(' ');
      overflows.add('${m.split('\n').first} @ $loc\n$m');
    } else {
      other.add(m);
    }
  }
}

// [DU602b] 아래 측정 도우미는 DU595b suite(7e30c11e · 판정177 §5 수용)에서 바이트 그대로 옮겼다 — :229–232(_txt) · :246–247(_semOf) ·
//   :249–270(_TO · _textLine — ensureVisible 대상 = 잰 대상) · :272–355(_lum · _contrast · _hex · _bgOf · _FillObs · _fills · _InkObs · _inkOf).
//   투어 본문은 SingleChildScrollView(지연 생성 0)라 _bringBuilt 는 옮기지 않았다(unused_element 0).
Finder _txt(Finder scope, String want, {bool onstage = true}) => find.descendant(
    of: scope,
    matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '') == want),
    skipOffstage: onstage);

/// 읽는 이름 — Text.semanticsLabel(있으면) · 없으면 span 의 읽는 이름을 포함한 평문 · 그다음 data.
String _semOf(Text w) => w.semanticsLabel ?? w.textSpan?.toPlainText() ?? w.data ?? '';

typedef _TO = ({int n, bool shown, bool sem, bool full, bool ell0, int brk, int lines, bool vis});

/// 글 하나 — [tf] 를 ensureVisible 로 화면 안에 넣고 **같은 [tf]** 를 잰다(점검표 A1 · 판정169a §5).
///   shown · full · ell0 · brk = DU560 r3 _textObs(max 판 _fullShown 그대로) · lines = _lineCount · vis = 화면 ∩ 조상 스크롤 칸 안 · n ≠ 1 이면 재지 않는다.
Future<_TO> _textLine(WidgetTester t, Finder tf, String want, Rect screen) async {
  final n = tf.evaluate().length;
  _TextObs o = (shown: false, name: false, full: false, ell0: false, brk: 0, size: Size.zero);
  var sem = false;
  var lines = 0;
  var vis = false;
  if (n == 1) {
    await t.ensureVisible(tf);
    for (var m = 0; m < 4; m++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    o = _textObs(t, tf, want);
    sem = _semOf(t.widget<Text>(tf)) == want;
    lines = _lineCount(t.renderObject<RenderParagraph>(find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: true).first));
    vis = _inside(t.getRect(tf), _area(tf, screen));
  }
  return (n: n, shown: o.shown, sem: sem, full: o.full, ell0: o.ell0, brk: o.brk, lines: lines, vis: vis);
}

// [DU575] 색 도우미 — DU309 시험(du1_confirm_color_split_309_test :84–95 · :162–183)과 같은 식(bgOf 는 main 안 지역 함수를 최상위 _bgOf 로만 옮김).

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

Color _bgOf(Element e) {
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

/// [DU575 · 점검표 A8] 화면에 그려진(onstage) ButtonStyleButton 전부의 채움 — 단추 자신의 Material 색(투명 · 없음 = none) · 글 = 첫 RichText(Icon 글리프 제외).
///   기록만(브랜드 밖 채움은 보고서 색 조화 표 '후보'). 카드 행 단추(_inviteActionButton = GestureDetector + Container)는 여기 들지 않는다 — README A8 표.
typedef _FillObs = ({int n, int brand, int err, int none, int other, String list});

_FillObs _fills(WidgetTester t) {
  final rows = <String>[];
  var b = 0, er = 0, no = 0, ot = 0;
  for (final e in find.byWidgetPredicate((w) => w is ButtonStyleButton).evaluate()) {
    final bf = find.byElementPredicate((x) => identical(x, e));
    final mats = find.descendant(of: bf, matching: find.byType(Material), skipOffstage: false).evaluate().toList();
    final Color? fc = mats.isEmpty ? null : (mats.first.widget as Material).color;
    final texts = find
        .descendant(of: bf, matching: find.byType(RichText), skipOffstage: false)
        .evaluate()
        .where((r) => find.ancestor(of: find.byElementPredicate((x) => identical(x, r), skipOffstage: false), matching: find.byType(Icon)).evaluate().isEmpty)
        .toList();
    final lab = texts.isEmpty ? '-' : TextLayout.plain((texts.first.widget as RichText).text.toPlainText(includeSemanticsLabels: false));
    if (fc == null || fc.a == 0) {
      no++;
      rows.add('$lab:none');
    } else {
      if (fc.toARGB32() == AppColors.brand.toARGB32()) {
        b++;
      } else if (fc.toARGB32() == AppColors.errorDark.toARGB32()) {
        er++;
      } else {
        ot++;
      }
      rows.add('$lab:${_hex(fc)}');
    }
  }
  return (n: rows.length, brand: b, err: er, none: no, other: ot, list: _enc(rows.join('|')));
}

/// [DU592b] 칩 · 배지 글의 칠 — [tf](_textLine 이 ensureVisible 하고 잰 **같은 Finder** · 점검표 A1) 안 글(RichText)의 글자색 ·
///   그 글 뒤 실제 바탕(_bgOf — 면이 반투명이면 아래 면과 섞는다) · 대비. 잰 즉시 값으로 굳힌다(뒤에 UI 를 다시 읽지 않는다).
typedef _InkObs = ({int n, String fg, String bg, String cr, bool ok45});

_InkObs _inkOf(Finder tf) {
  final es = find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: false).evaluate().toList();
  if (es.length != 1) return (n: es.length, fg: '-', bg: '-', cr: '0.00', ok45: false);
  final Color? fg = (es.first.widget as RichText).text.style?.color;
  final bg = _bgOf(es.first);
  final cr = fg == null ? 0.0 : _contrast(fg, bg);
  return (n: 1, fg: fg == null ? '-' : _hex(fg), bg: _hex(bg), cr: cr.toStringAsFixed(2), ok45: cr >= 4.5);
}

// [DU602b] 누르는 자리 hit — DU581 r3 suite(3f4a404a · run DONE 5/5 19:35:21)의 :193–204 바이트 그대로(_hitWithin).
/// [pos] 를 눌렀을 때 맞는 대상 중에 [f] 의 위젯(자손 포함)이 만든 render object 가 있는가.
bool _hitWithin(WidgetTester t, Finder f, Offset pos) {
  final own = <Object>{};
  void walk(Element e) {
    final ro = e.renderObject;
    if (ro != null) own.add(ro);
    e.visitChildren(walk);
  }

  walk(f.evaluate().first);
  return t.hitTestOnBinding(pos).path.any((x) => own.contains(x.target));
}

// ───────────── [DU602b] 새로 쓴 부분 — 제목 끝줄 도달 · 사례 본문 ─────────────

typedef _TailObs = ({bool tail, bool tall});

/// [DU602b] 긴 글(B 4쪽 제목은 스크롤 칸보다 높다 — DU314 B 합성) — [tf] 를 칸 **아래**에 맞춰 넣고(Scrollable.ensureVisible alignment 1.0 · 같은 [tf] · A1)
///   마지막 줄(바뀐 둘째 줄의 끝)이 화면 ∩ 조상 스크롤 칸 안인가 · 글 높이가 칸보다 높은가. 잰 즉시 값으로 굳힌다.
Future<_TailObs> _tail(WidgetTester t, Finder tf, Rect screen) async {
  await Scrollable.ensureVisible(t.element(tf), alignment: 1.0);
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final r = t.getRect(tf);
  final a = _area(tf, screen);
  return (tail: r.bottom <= a.bottom + 0.5 && r.bottom >= a.top + 0.5, tall: r.height > a.height + 0.5);
}

/// [DU602b] 사례 — 근무자 투어를 연다(시작 단추 'host' → pushTourScreen(ctx, role: 'USER') · S047 RG 와 같은 진입 helper) → CTA '다음' 글 중심을 3번 눌러
///   (잰 hit 와 같은 점) 4쪽 → ① 도달 · CTA 채움(A8) · 채움 단추 · 첫 화면 보임(fold) ② 제목(그린 글 · 칠 · 끝줄 도달) · 1title
///   ③ 기능 줄(ensureVisible = 잰 대상) · 채움 단추 · 2feature.
Future<void> _caseOf(WidgetTester t, _V v, ({String id, int shots}) c, String tok) async {
  final prevOnError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = prevOnError);
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D602 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
  final seen = _DSeen();
  final checks = <(String, bool, String)>[];
  void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));
  Object? failure;
  StackTrace? failureSt;
  var shots = 0;
  var raw = '';
  // 모은 단언 재료 — 측정 즉시 값(뒤에 UI 를 다시 읽지 않는다).
  var okBefore = false;
  var okStrict = false;
  try {
    FlutterError.onError = seen.add;
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.workerTheme,
        builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
        home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
            onPressed: () => pushTourScreen(ctx, role: 'USER'),
            child: const Text('host'))))),
      ),
    ));
    Future<void> settle(int n) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await t.pump();
    await t.tap(find.text('host'));
    await settle(24);
    final tour = find.byType(TourScreen);
    final nTour = tour.evaluate().length;
    if (nTour != 1) throw StateError('투어 화면 $nTour');
    Future<void> shot(String id, String state) async {
      _out('D602 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    final screen = Offset.zero & Size(v.w, v.h);
    // CTA = 그 글을 품은 가장 안쪽 GestureDetector(S047 RG cta() 와 같은 기준). 누르는 점 = 글 중심 = hit 점 — hit 거짓이면 누르지 않는다.
    Finder ctaOf(Finder lab) => find.ancestor(of: lab, matching: find.byType(GestureDetector)).first;
    for (var p = 1; p <= 3; p++) {
      final nx = _txt(tour, _kNext);
      final nNx = nx.evaluate().length;
      if (nNx != 1) throw StateError('$p쪽 다음 $nNx');
      final np = t.getRect(nx).center;
      if (!_hitWithin(t, ctaOf(nx), np)) throw StateError('$p쪽 다음 중심 hit 거짓');
      await t.tapAt(np);
      await settle(24);
    }
    // ① 4쪽 도달 — 설명 글 1 · 마지막 CTA '확인'('다음' 0) · CTA 채움(A8) · 중심 hit(누르지 않는다).
    final nDesc = _txt(tour, _kDesc, onstage: false).evaluate().length;
    final lastF = _txt(tour, _kLast);
    final nLast = lastF.evaluate().length;
    final last = nLast == 1 && _txt(tour, _kNext).evaluate().isEmpty;
    var fill = '-';
    var hit = false;
    if (nLast == 1) {
      final deco = t.widget<AnimatedContainer>(find.descendant(of: ctaOf(lastF), matching: find.byType(AnimatedContainer)).first).decoration as BoxDecoration?;
      final fc = deco?.color;
      fill = fc == null ? '-' : _hex(fc);
      hit = _hitWithin(t, ctaOf(lastF), t.getRect(lastF).center);
    }
    _out('D602 $tok att pg n=$nDesc last=$last fill=$fill hit=$hit');
    final f0 = _fills(t);
    _out('D602 $tok att f0 n=${f0.n} brand=${f0.brand} err=${f0.err} none=${f0.none} other=${f0.other} list=${f0.list}');
    // 4쪽 첫 화면(스크롤 0)에서 제목 전체 · 기능 줄이 보이는가 — 기록만(작은 화면은 본문 스크롤 · README 설계 전제 위험 자료).
    final tWant = _before ? _kTitleOld : _kTitleNew;
    final fWant = _before ? _kFeatOld : _kFeatNew;
    final ttF = _txt(tour, tWant, onstage: false);
    final ftF = _txt(tour, fWant, onstage: false);
    final nTt = ttF.evaluate().length;
    final nFt = ftF.evaluate().length;
    var tv = false;
    var fv = false;
    if (nTt == 1) tv = _inside(t.getRect(ttF), _area(ttF, screen));
    if (nFt == 1) fv = _inside(t.getRect(ftF), _area(ftF, screen));
    _out('D602 $tok att fold tv=$tv fv=$fv');
    // ② 제목 — 옛/새 글 수 · 그린 글(전문 · 읽는 이름 · 낱말 안 끊김 · 줄) · 칠/대비(_inkOf 같은 Finder) · 끝줄 도달(_tail: 같은 Finder 를 칸 아래에 맞춤).
    final nTOld = _txt(tour, _kTitleOld, onstage: false).evaluate().length;
    final nTNew = _txt(tour, _kTitleNew, onstage: false).evaluate().length;
    _TextObs to = (shown: false, name: false, full: false, ell0: false, brk: 0, size: Size.zero);
    var tSem = false;
    var tLines = 0;
    _TailObs tl = (tail: false, tall: false);
    final ti = _inkOf(ttF);
    if (nTt == 1) {
      to = _textObs(t, ttF, tWant);
      tSem = _semOf(t.widget<Text>(ttF)) == tWant;
      tLines = _lineCount(t.renderObject<RenderParagraph>(find.descendant(of: ttF, matching: find.byType(RichText), skipOffstage: true).first));
      tl = await _tail(t, ttF, screen);
    }
    _out('D602 $tok att tt n=$nTt od=$nTOld nw=$nTNew shown=${to.shown} sem=$tSem full=${to.full} brk=${to.brk} lines=$tLines tall=${tl.tall} tail=${tl.tail} '
        'fg=${ti.fg} c45=${ti.ok45}');
    await shot('1title', 'page4-title-tail');
    // ③ 기능 줄 — ensureVisible 로 넣은 **같은 Finder** 를 잰다(_textLine · A1) · 칠/대비.
    final nFOld = _txt(tour, _kFeatOld, onstage: false).evaluate().length;
    final nFNew = _txt(tour, _kFeatNew, onstage: false).evaluate().length;
    final fo = await _textLine(t, ftF, fWant, screen);
    final fi = _inkOf(ftF);
    _out('D602 $tok att ft n=${fo.n} od=$nFOld nw=$nFNew shown=${fo.shown} sem=${fo.sem} full=${fo.full} brk=${fo.brk} lines=${fo.lines} vis=${fo.vis} '
        'fg=${fi.fg} c45=${fi.ok45}');
    final fs = _fills(t);
    _out('D602 $tok att fs n=${fs.n} brand=${fs.brand} err=${fs.err} none=${fs.none} other=${fs.other} list=${fs.list}');
    await shot('2feature', 'page4-feature');
    final same = nDesc == 1 && last && fill == _hex(AppColors.brand) && hit &&
        nTt == 1 && to.shown && tSem && to.full && to.brk == 0 && tl.tail && ti.fg == _hex(AppColors.grey900) && ti.ok45 &&
        fo.n == 1 && fo.shown && fo.sem && fo.full && fo.brk == 0 && fo.vis && fi.fg == _hex(AppColors.grey800) && fi.ok45;
    okBefore = same && nTOld == 1 && nTNew == 0 && nFOld == 1 && nFNew == 0;
    okStrict = same && nTOld == 0 && nTNew == 1 && nFOld == 0 && nFNew == 1;
    raw = 'pg $nDesc $last $fill $hit f0 $f0 fold $tv $fv tt $nTt $nTOld $nTNew $to $tSem $tLines $tl $ti ft $fo $nFOld $nFNew $fi fs $fs';
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // ④ 성공 · 실패 공통 정리 — 화면을 내리고 남은 timer · 애니메이션이 끝날 시간을 준다.
  var cleanupErr = '';
  try {
    await t.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(seconds: 1));
    }
  } catch (e, st) {
    cleanupErr = e.toString();
    if (failure == null) {
      failure = e;
      failureSt = st;
    }
  }
  final exc = t.takeException();
  if (exc != null && failure == null) {
    failure = exc;
    failureSt = StackTrace.current;
  }
  final nOvf = seen.overflows.length;
  final nFw = seen.other.length;
  final ovfRaw = seen.overflows.join('\n----\n');
  final fwRaw = seen.other.join('\n----\n');
  _out('R602 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D602 $tok att fw n=$nFw');
  _out('D602 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

  final f1 = failure;
  if (f1 != null) {
    _halt ??= '$tok ${f1.toString().split('\n').first}';
    Error.throwWithStackTrace(f1, failureSt ?? StackTrace.current);
  }
  if (_before) {
    chk('before 대상 = 지금 A(4쪽 도달 · CTA brand · 제목 옛 글 1/새 글 0 · 기능 줄 옛 글 1/새 글 0 · 두 글 전문 · 읽는 이름 · 낱말 안 끊김 0 · '
        '제목 끝줄 도달 · 기능 줄 보임 · 칠 grey900/grey800 ≥ 4.5)', okBefore, raw);
  } else {
    chk('strict 대상 = 후보(4쪽 도달 · CTA brand · 제목 새 글 1/옛 글 0 · 기능 줄 새 글 1/옛 글 0 · 두 글 전문 · 읽는 이름 · 낱말 안 끊김 0 · '
        '제목 끝줄 도달 · 기능 줄 보임 · 칠 grey900/grey800 ≥ 4.5)', okStrict, raw);
    chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
    chk('strict 넘침 0', nOvf == 0, ovfRaw);
  }
  chk('캡처 수 = 선언', shots == c.shots, 'shots $shots want ${c.shots}');
  final bad = checks.where((x) => !x.$2).toList();
  if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
  for (final x in checks) {
    expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
  }
}

void main() {
  setUpAll(() async {
    await _loadFonts();
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S602TR-${v.id}-${c.id} 근무자 투어 4쪽 — 약속 제목 · 이용 제한', (t) async {
        final tok = 'S602TR-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _caseOf(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
