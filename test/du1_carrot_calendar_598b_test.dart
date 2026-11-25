// [DU598b · 파일 셀 · 표시만] 당근형 달력(lib/widgets/calendar/carrot_style_calendar.dart) — 판정138 §4 요청1 :63 · 요청6 :68.
//   ① 요일 머리 7칸 = 같은 중립 grey600(일요일 error · 토요일 info · 평일 textSecondary 갈래 없음).
//   ② 고를 수 있고 고르지 않은 이 달 주말 날짜 숫자 = 평일과 같은 textPrimary(불가 · 다른 달 grey300 · 선택 brand/흰 · 오늘 brand 테 · 범위 띠 흰/brand 그대로).
//   ③ 월 알약(현재 달로 가는 조작 · onTap 그대로) 면 = grey100 · 글 brand 그대로.
//   before = 지금 A(646ef6ba) 기록 · strict = 후보(cand/ · mkcell 이 SHA 대조).
//   실제 소비 시트 = DatePickerBottomSheet.show(단일) · DateRangePickerBottomSheet.show(범위) — 앱 문맥에서 연다(DU290 시험과 같은 공개 API).
//   하네스 = 블록 재사용(prep/mk_test.py 가 원본 fullSHA · 블록 sha12 단언): DU596b suite(79dbbbd8 · run DONE 5/5 04:56 · 그 블록은 DU595b 7e30c11e 바이트 사본) —
//     글꼴 · max 판 _fullShown · _textObs · _area · _lineCount · 보기 W/B/N · _halt · env 줄 · _DSeen · _txt · _bringBuilt · _semOf · _textLine · 색 도우미 ·
//     _fills · _inkOf · _iconInk.
//   새로 쓴 것: 이 머리 · 사례 2(SGL · RNG) · 격자 복원 _grid(숫자 글 42칸을 화면 위치 순서로 날짜에 맞춘다 · 색으로 고르지 않는다) · 칸 칠 _cellInk ·
//     머리 칠 _headOf · 주말 칠 _weekendOf · 알약 _pillOf · 사례 본문 _caseOf · main.
//   달력은 실행 달(DateTime.now)로 열린다(시트가 focusedMonth 를 넘기지 않는다) — 오늘 · 칸 배치는 실행일마다 달라 격자를 복원해 칸마다 분기를 가른다(README A7).
//   누르는 것 0(ensureVisible · _bringBuilt 의 scrollUntilVisible 만 · 시트는 닫지 않고 화면을 내린다). 쓰기 · CF · 서버 대역 0.
//   첫 줄 억제(판정172 §5 정형 ①)는 쓰지 않는다 — 이 suite 는 플랫폼 대역 import 가 없다(정형 ② avoid_print 1줄만).
//   기본 skip — TB before/du598bcc-tb/DU_BEFORE_OBSERVE=598 · TA after/du598bcc-ta/없음.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show BoxHeightStyle;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/calendar/carrot_style_calendar.dart';
import 'package:ALfit/widgets/pickers/date_picker_bottom_sheet.dart';

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

/// [DU598b] 사례 — SGL = 날짜 선택 시트(단일 · 이 달 평일 하루를 고른 채 · 지난 날 허용 = 이 달 칸 전부 고를 수 있다) ·
///   RNG = 기간 선택 시트(범위 · 이 달 첫 금요일 ~ 그다음 월요일 — 토 · 일이 범위 띠 안). 장수 = 첫 화면 + 격자 끝 줄(SGL) / 범위 줄(RNG).
const _cases = <({String id, int shots})>[(id: 'SGL', shots: 2), (id: 'RNG', shots: 2)];

/// [DU598b] 요일 머리 7 글 — mkcell 이 base/후보 원문 `const weekdays` 와 대조한다(두 모드 같은 글 · 색만 바뀐다).
const _kWeek = ['일', '월', '화', '수', '목', '금', '토'];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '598';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du598bcc-tb' && _env['DU_BEFORE_OBSERVE'] == '598') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du598bcc-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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

// [DU598b] 아래 측정 도우미는 DU596b suite(79dbbbd8)에서 바이트 그대로 옮겼다 — :222–348(_txt · _bringBuilt · _semOf · _TO · _textLine — ensureVisible 대상 = 잰 대상 ·
//   _lum · _contrast · _hex · _bgOf · _FillObs · _fills · _InkObs · _inkOf). 그 블록은 DU595b(7e30c11e) :229–355 의 바이트 사본이다(DU596b mk_test 단언).

Finder _txt(Finder scope, String want, {bool onstage = true}) => find.descendant(
    of: scope,
    matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '') == want),
    skipOffstage: onstage);

/// [DU581 r3 _bringBuilt 와 같은 대비 · 판정167 교훈] [want] 글이 [host] 안에 아직 안 지어졌을 때만 그 host 의 세로 Scrollable 을 끌어 짓는다
///   (누르기 아님 · 찾는 식 = _txt 와 같은 정규화 · 단언 없음 — 개수 판정은 뒤 _textLine/_btnReach 출력과 cell 선언). 지어져 있으면 아무것도 하지 않는다.
Future<void> _bringBuilt(WidgetTester t, Finder host, String? want) async {
  final tf = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '') == want), skipOffstage: false);
  if (tf.evaluate().isNotEmpty) return;
  final sc = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down), skipOffstage: false);
  await t.scrollUntilVisible(tf, 120, scrollable: sc.first, maxScrolls: 40);
  await t.pump(const Duration(milliseconds: 50));
}

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

// [DU598b] 아이콘 칠 — DU596b suite(79dbbbd8) :351–360 바이트 그대로(DU595b :425–434 사본) · 월 이동 원 화살표(chevron) 두 개를 잰다.
typedef _IconObs = ({int n, String fill, String glyph, String cr, bool ok3});

_IconObs _iconInk(Finder f) {
  final es = f.evaluate().toList();
  if (es.length != 1) return (n: es.length, fill: '-', glyph: '-', cr: '0.00', ok3: false);
  final Color? g = (es.first.widget as Icon).color;
  final bg = _bgOf(es.first);
  final cr = g == null ? 0.0 : _contrast(g, bg);
  return (n: 1, fill: _hex(bg), glyph: g == null ? '-' : _hex(g), cr: cr.toStringAsFixed(2), ok3: cr >= 3.0);
}

// ───────────── [DU598b] 새로 쓴 부분 — 격자 복원 · 칸 칠 · 머리 칠 · 알약 · 사례 본문 ─────────────

/// [DU598b] 같은 날(연 · 월 · 일).
bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// [DU598b] 날짜 칸 하나 — 복원한 날짜 · 그 칸 숫자 글(Text) Element.
typedef _Cell = ({DateTime d, Element e});

/// [DU598b] 달력 격자 복원 — [cal](CarrotStyleCalendar) 안 숫자만인 Text 를 화면 위치(세로 묶음 → 가로 순서)로 줄 세우고,
///   carrot_style_calendar.dart _generateDaysInMonth 와 같은 규칙(이 달 1일의 요일만큼 앞달 칸 · 42칸)으로 날짜를 맞춘다.
///   칸을 색으로 고르지 않는다(색 = 잴 값). 42칸 · 6줄 × 7 · 모든 칸 글 = 그 날짜의 일(day)이면 ok.
({List<_Cell> cells, bool ok}) _grid(WidgetTester t, Finder cal, DateTime month) {
  final digit = RegExp(r'^\d{1,2}$');
  final es = find
      .descendant(of: cal, matching: find.byWidgetPredicate((w) => w is Text && digit.hasMatch(w.data ?? '')), skipOffstage: false)
      .evaluate()
      .toList();
  final pos = <({Element e, Offset c})>[
    for (final e in es) (e: e, c: t.getCenter(find.byElementPredicate((x) => identical(x, e), skipOffstage: false))),
  ];
  pos.sort((a, b) => a.c.dy.compareTo(b.c.dy));
  final rows = <List<({Element e, Offset c})>>[];
  for (final p in pos) {
    if (rows.isEmpty || p.c.dy - rows.last.first.c.dy > 8) {
      rows.add([p]);
    } else {
      rows.last.add(p);
    }
  }
  for (final r in rows) {
    r.sort((a, b) => a.c.dx.compareTo(b.c.dx));
  }
  final first = DateTime(month.year, month.month, 1);
  final lead = first.weekday % 7;
  final cells = <_Cell>[];
  var ok = es.length == 42 && rows.length == 6 && rows.every((r) => r.length == 7);
  var i = 0;
  for (final r in rows) {
    for (final p in r) {
      final d = DateTime(first.year, first.month, 1 - lead + i);
      cells.add((d: d, e: p.e));
      if ((p.e.widget as Text).data != d.day.toString()) ok = false;
      i++;
    }
  }
  return (cells: cells, ok: ok);
}

/// [DU598b] 칸 칠 — 숫자 글색(Text.style) · 그 글 뒤 면(_bgOf · 반투명은 아래 면과 섞는다) · 가장 가까운 칸 상자(Container + BoxDecoration)의 선 색(오늘 테).
typedef _CellObs = ({String fg, String bg, String line, double cr});

_CellObs _cellInk(Element e) {
  final Color? fg = (e.widget as Text).style?.color;
  final bg = _bgOf(e);
  Color? lc;
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Container && w.decoration is BoxDecoration) {
      final bb = (w.decoration as BoxDecoration).border;
      if (bb is Border) lc = bb.top.color;
      return false;
    }
    return true;
  });
  final line = lc;
  return (fg: fg == null ? '-' : _hex(fg), bg: _hex(bg), line: line == null ? '-' : _hex(line), cr: fg == null ? 0.0 : _contrast(fg, bg));
}

/// [DU598b] 요일 머리 7 글 — 글마다 칠(Text.style 색) · 뒤 면 대비. sun = 일 · sat = 토 · wk = 월–금이 한 값이면 그 값(아니면 mix) · same = 7 글 한 값.
typedef _HeadObs = ({int n, String sun, String sat, String wk, bool same, String cr});

_HeadObs _headOf(Finder cal) {
  final fg = <String>[];
  var minCr = 99.0;
  for (final w in _kWeek) {
    final es = find.descendant(of: cal, matching: find.text(w, skipOffstage: false), skipOffstage: false).evaluate().toList();
    final Color? c = es.length == 1 ? (es.first.widget as Text).style?.color : null;
    if (c == null) return (n: 0, sun: '-', sat: '-', wk: '-', same: false, cr: '0.00');
    fg.add(_hex(c));
    minCr = math.min(minCr, _contrast(c, _bgOf(es.first)));
  }
  final wd = fg.sublist(1, 6).toSet();
  return (n: fg.length, sun: fg.first, sat: fg.last, wk: wd.length == 1 ? wd.first : 'mix', same: fg.toSet().length == 1, cr: minCr.toStringAsFixed(2));
}

/// [DU598b] 이 달 주말 숫자 — 이 달 칸 중 오늘 · [skip](고른 날 · 범위 안) 을 뺀 일요일 · 토요일 칸 글색 집합과 평일 칸 글색 집합.
///   same = 일 · 토 · 평일 세 집합이 각각 한 값이고 서로 같다. n = 잰 주말 칸 수 · cr = 주말 칸 대비 최소.
typedef _WkObs = ({int n, String sun, String sat, String wk, bool same, String cr});

_WkObs _weekendOf(List<_Cell> cells, DateTime month, DateTime today, bool Function(DateTime) skip) {
  final sun = <String>{};
  final sat = <String>{};
  final wk = <String>{};
  var n = 0;
  var minCr = 99.0;
  for (final x in cells) {
    if (x.d.month != month.month || _sameDay(x.d, today) || skip(x.d)) continue;
    final o = _cellInk(x.e);
    if (x.d.weekday == DateTime.sunday) {
      sun.add(o.fg);
    } else if (x.d.weekday == DateTime.saturday) {
      sat.add(o.fg);
    } else {
      wk.add(o.fg);
      continue;
    }
    n++;
    minCr = math.min(minCr, o.cr);
  }
  String one(Set<String> s) => s.length == 1 ? s.first : (s.isEmpty ? '-' : 'mix');
  final same = sun.length == 1 && sat.length == 1 && wk.length == 1 && sun.first == wk.first && sat.first == wk.first;
  return (n: n, sun: one(sun), sat: one(sat), wk: one(wk), same: same, cr: (n == 0 ? 0.0 : minCr).toStringAsFixed(2));
}

/// [DU598b] 월 알약 — [tf](_textLine 이 ensureVisible 하고 잰 **같은 Finder** · 점검표 A1) 의 글 칠(_inkOf = 글자색 · 그 글 뒤 면) ·
///   가장 가까운 GestureDetector 의 onTap 있음(현재 달로 가는 조작 보존). 잰 즉시 값으로 굳힌다.
typedef _PillObs = ({int n, String fg, String face, String cr, bool ok45, bool tap});

_PillObs _pillOf(Finder tf) {
  final io = _inkOf(tf);
  final gd = find.ancestor(of: tf, matching: find.byType(GestureDetector)).evaluate().toList();
  final tap = gd.isNotEmpty && (gd.first.widget as GestureDetector).onTap != null;
  return (n: io.n, fg: io.fg, face: io.bg, cr: io.cr, ok45: io.ok45, tap: tap);
}

/// [DU598b] 이 달 평일 하루(오늘이 아닌 첫 월–금) — SGL 이 고른 채 여는 날.
DateTime _pickWeekday(DateTime month, DateTime today) {
  for (var d = 1; d <= 28; d++) {
    final x = DateTime(month.year, month.month, d);
    if (x.weekday <= DateTime.friday && !_sameDay(x, today)) return x;
  }
  return DateTime(month.year, month.month, 2);
}

/// [DU598b] 이 달 첫 금요일 — RNG 범위 시작(그다음 월요일까지 · 토 · 일이 띠 안 · 4일 모두 이 달).
DateTime _firstFriday(DateTime month) {
  for (var d = 1; d <= 7; d++) {
    final x = DateTime(month.year, month.month, d);
    if (x.weekday == DateTime.friday) return x;
  }
  return DateTime(month.year, month.month, 1);
}

/// [DU598b] 사례 — 시트를 앱 문맥에서 열고(누르기 0) ① 첫 화면 채움 단추(A8 · 기록만) · 1top ② 요일 머리 · 월 알약(_bringBuilt → _textLine — ensureVisible 대상 =
///   잰 대상 · A1/A4) · 월 이동 원 · 격자 복원 · 주말 숫자 · 고른 날/오늘/다른 달(SGL) 또는 범위 띠 주말(RNG) · 화면 채움 단추(A8) · 격자 끝 줄/범위 줄이 보이게 맞춰 2장째.
Future<void> _caseOf(WidgetTester t, _V v, ({String id, int shots}) c, String tok) async {
  final prevOnError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = prevOnError);
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D598 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
  final now = DateTime.now();
  final month = DateTime(now.year, now.month);
  final today = DateTime(now.year, now.month, now.day);
  final sel = _pickWeekday(month, today);
  final rs = _firstFriday(month);
  final re = DateTime(rs.year, rs.month, rs.day + 3);
  bool inRange(DateTime d) => !d.isBefore(rs) && !d.isAfter(re);
  final hBrand = _hex(AppColors.brand);
  final hG100 = _hex(AppColors.grey100);
  final hG600 = _hex(AppColors.grey600);
  final hText = _hex(AppColors.textPrimary);
  final hErr = _hex(AppColors.error);
  final hInfo = _hex(AppColors.info);
  final hWhite = _hex(AppColors.surface);
  final hG300 = _hex(AppColors.grey300);
  try {
    FlutterError.onError = seen.add;
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.workerTheme,
        builder: (bc, child) => MediaQuery(data: MediaQuery.of(bc).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final appEl = t.element(find.byType(Scaffold).first);
    if (!appEl.mounted) throw StateError('앱 문맥 없음');
    if (c.id == 'SGL') {
      unawaited(DatePickerBottomSheet.show(context: appEl, initialDate: sel, allowPastDates: true));
    } else {
      unawaited(DateRangePickerBottomSheet.show(context: appEl, initialStart: rs, initialEnd: re, allowPastDates: true));
    }
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final host = find.byType(BottomSheet);
    final nHost = host.evaluate().length;
    if (nHost != 1) throw StateError('시트 $nHost');
    final cal = find.descendant(of: host, matching: find.byType(CarrotStyleCalendar), skipOffstage: false);
    final nCal = cal.evaluate().length;
    if (nCal != 1) throw StateError('달력 $nCal');
    Future<void> shot(String id, String state) async {
      _out('D598 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    Future<void> settle() async {
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    final screen = Offset.zero & Size(v.w, v.h);
    // ① 첫 화면 — 화면에 그려진 채움 단추(A8 · 기록만) · 1top.
    final ftp = _fills(t);
    _out('D598 $tok att ftop n=${ftp.n} brand=${ftp.brand} err=${ftp.err} none=${ftp.none} other=${ftp.other} list=${ftp.list}');
    await shot('1top', 'sheet-top');
    // ② 요일 머리 7 글 칠.
    final wh = _headOf(cal);
    _out('D598 $tok att wh n=${wh.n} sun=${wh.sun} sat=${wh.sat} wk=${wh.wk} same=${wh.same} cr=${wh.cr}');
    // ③ 월 알약 — 지연 생성 대비(_bringBuilt · 같은 host · 같은 글) 뒤 같은 Finder 를 ensureVisible 해 잰다(_textLine) · 그 Finder 의 칠(_pillOf).
    final ym = FormatHelper.formatYearMonth(month);
    await _bringBuilt(t, host, ym);
    final tf = _txt(host, ym, onstage: false);
    final pt = await _textLine(t, tf, ym, screen);
    _out('D598 $tok att pt n=${pt.n} shown=${pt.shown} sem=${pt.sem} full=${pt.full} ell0=${pt.ell0} brk=${pt.brk} lines=${pt.lines} vis=${pt.vis}');
    final pl = _pillOf(tf);
    _out('D598 $tok att pl n=${pl.n} fg=${pl.fg} face=${pl.face} cr=${pl.cr} ok45=${pl.ok45} tap=${pl.tap}');
    // ④ 월 이동 원(이전 · 다음 달) — 알약과 같은 grey100 면 · brand 화살표(교차 일관 대조 · 두 모드 같음).
    final li = _iconInk(find.descendant(of: cal, matching: find.byIcon(Icons.chevron_left, skipOffstage: false), skipOffstage: false));
    final ri = _iconInk(find.descendant(of: cal, matching: find.byIcon(Icons.chevron_right, skipOffstage: false), skipOffstage: false));
    final nvN = li.n == 1 && ri.n == 1 ? 2 : 0;
    final nvFace = li.fill == ri.fill ? li.fill : 'mix';
    final nvIcon = li.glyph == ri.glyph ? li.glyph : 'mix';
    final nvCr = math.min(double.parse(li.cr), double.parse(ri.cr)).toStringAsFixed(2);
    _out('D598 $tok att nv n=$nvN face=$nvFace icon=$nvIcon cr=$nvCr');
    // ⑤ 격자 복원(위치 순서 → 날짜) · 이 달 주말 숫자 칠.
    final g = _grid(t, cal, month);
    _out('D598 $tok att gd n=${g.cells.length} ok=${g.ok}');
    final wn = _weekendOf(g.cells, month, today, (d) => c.id == 'SGL' ? _sameDay(d, sel) : inRange(d));
    _out('D598 $tok att wn n=${wn.n} sun=${wn.sun} sat=${wn.sat} wk=${wn.wk} same=${wn.same} cr=${wn.cr}');
    var keep = nvN == 2 && nvFace == hG100 && nvIcon == hBrand && g.ok;
    Element? endEl;
    if (c.id == 'SGL') {
      // ⑥ 고른 날(흰 글 · brand 면) · 오늘(brand 글 · brand 테) · 다른 달(grey300) — 두 모드 같은 분기 우선순위.
      _CellObs? selO;
      _CellObs? todayO;
      _CellObs? adjO;
      for (final x in g.cells) {
        if (_sameDay(x.d, sel)) selO = _cellInk(x.e);
        if (_sameDay(x.d, today)) todayO = _cellInk(x.e);
        if (adjO == null && x.d.month != month.month) adjO = _cellInk(x.e);
      }
      final sd = (sel: selO?.fg ?? '-', selbg: selO?.bg ?? '-', today: todayO?.fg ?? '-', tline: todayO?.line ?? '-', adj: adjO?.fg ?? '-');
      _out('D598 $tok att sd sel=${sd.sel} selbg=${sd.selbg} today=${sd.today} tline=${sd.tline} adj=${sd.adj}');
      keep = keep && sd.sel == hWhite && sd.selbg == hBrand && sd.today == hBrand && sd.tline == hBrand && sd.adj == hG300;
      endEl = g.cells.isEmpty ? null : g.cells.last.e;
      raw = 'wh $wh pt $pt pl $pl nv $nvN/$nvFace/$nvIcon/$nvCr gd ${g.ok} wn $wn sd $sd';
    } else {
      // ⑥ 범위 띠 안 토 · 일 — 흰 글 · brand 띠(주말이어도 범위 분기가 먼저 · 두 모드 같음).
      final inr = <_CellObs>[];
      for (final x in g.cells) {
        if (inRange(x.d) && (x.d.weekday == DateTime.saturday || x.d.weekday == DateTime.sunday)) {
          inr.add(_cellInk(x.e));
          endEl ??= x.e;
        }
      }
      final fgs = inr.map((o) => o.fg).toSet();
      final bgs = inr.map((o) => o.bg).toSet();
      final rg = (n: inr.length, fg: fgs.length == 1 ? fgs.first : 'mix', bg: bgs.length == 1 ? bgs.first : 'mix');
      _out('D598 $tok att rg n=${rg.n} fg=${rg.fg} bg=${rg.bg}');
      keep = keep && rg.n == 2 && rg.fg == hWhite && rg.bg == hBrand;
      raw = 'wh $wh pt $pt pl $pl nv $nvN/$nvFace/$nvIcon/$nvCr gd ${g.ok} wn $wn rg $rg';
    }
    okBefore = wh.n == 7 && wh.sun == hErr && wh.sat == hInfo && !wh.same && pl.n == 1 && pl.fg == hBrand && pl.tap && wn.n >= 1 && wn.sun == hErr &&
        wn.sat == hInfo && wn.wk == hText && keep;
    okStrict = wh.n == 7 && wh.same && wh.sun == hG600 && pt.n == 1 && pt.shown && pt.full && pt.vis && pt.brk == 0 && pl.n == 1 && pl.face == hG100 &&
        pl.fg == hBrand && pl.ok45 && pl.tap && wn.n >= 1 && wn.same && wn.sun == hText && keep;
    final fo = _fills(t);
    _out('D598 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
    final ee = endEl;
    if (ee != null) await t.ensureVisible(find.byElementPredicate((x) => identical(x, ee), skipOffstage: false));
    await settle();
    await shot(c.id == 'SGL' ? '2end' : '2range', c.id == 'SGL' ? 'grid-end' : 'range-weekend');
    raw = '$raw fills $fo top $ftp';
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // ⑦ 성공 · 실패 공통 정리 — 화면을 내리고 남은 timer · 애니메이션이 끝날 시간을 준다.
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
  _out('R598 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D598 $tok att fw n=$nFw');
  _out('D598 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  if (_before) {
    chk('before 대상 = 지금 A(요일 머리 일 error · 토 info · 평일 textSecondary / 이 달 주말 숫자 일 error · 토 info · 평일 textPrimary / 월 알약 글 brand · onTap 있음 / '
        '월 이동 원 grey100 · brand · 격자 42 / SGL 고른 날 흰/brand · 오늘 brand 테 · 다른 달 grey300 · RNG 범위 띠 주말 흰/brand)', okBefore, raw);
  } else {
    chk('strict 대상 = 후보(요일 머리 7 글 grey600 한 값 / 이 달 주말 숫자 = 평일 textPrimary / 월 알약 면 grey100 · 글 brand · 대비 ≥ 4.5 · onTap 있음 · 전문 · 보임 / '
        '월 이동 원 · 격자 · 고른 날 · 오늘 · 다른 달 · 범위 띠 그대로)', okStrict, raw);
    chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
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
    await initializeDateFormatting('ko_KR');
    await _loadFonts();
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S598CC-${v.id}-${c.id} 당근 달력 — 요일 머리 · 주말 숫자 중립 · 월 알약 grey100', (t) async {
        final tok = 'S598CC-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _caseOf(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
