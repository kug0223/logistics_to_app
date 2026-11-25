// [DU607b · 파일 셀 · 표시만] 당근형 달력(lib/widgets/calendar/carrot_style_calendar.dart) — 판정179 §4 F179-CALENDAR-B-GRID CORRECTION_OPEN.
//   B(320 · 2.0) 오늘 '22' 숫자/테 겹침 · 날짜칸 붙음 → 글 상자를 재서 지금 원 칸에 안 들어가면 큰 판(요일 머리 · 격자 가로 여백 0 · 칸 가로 여백 0 ·
//   칸 높이 = 글 줄 + 테 + 2 · 둥근 칸). 글자 크기 · 원문 · 7요일 대응 · 선택/범위/오늘/불가 · 반환/취소 보존을 함께 잰다.
//   before = 지금 A(5cc6bd9b = DU598b 후보) 기록 · strict = 후보(cand/ · mkcell 이 SHA 대조).
//   실제 소비 시트 = DatePickerBottomSheet.show(단일) · DateRangePickerBottomSheet.show(범위) — 앱 문맥에서 연다(DU598b · DU290 시험과 같은 공개 API).
//   하네스 = 블록 재사용(prep/mk_test.py 가 원본 fullSHA · 블록 sha12 · 경계 줄 단언): DU596b suite(79dbbbd8 · 그 블록은 DU595b 7e30c11e 바이트 사본) —
//     글꼴 · max 판 _fullShown · _textObs · _area · _lineCount · 보기 W/B/N · _halt · env 줄 · _DSeen · _txt · _bringBuilt · _semOf · _textLine · 색 도우미 ·
//     _fills · _inkOf / DU598b g1 suite(c67984ed · 판정179 g1 수리 수용) — _sameDay · _Cell · _grid(격자 복원) · _CellObs · _cellInk.
//   새로 쓴 것: 이 머리 · 사례 2(SGL · RNG) · 글 상자 _labelOf · 칸 장식 _decoOf · 격자 배치 _geoOf · 날 고르기 · 사례 본문 _caseOf · main.
//   달력은 실행 달(DateTime.now)로 열린다 — 격자를 복원해 칸마다 분기를 가른다(README A7 · KST 자정 걸쳐 돌리지 않는다).
//   누르는 것 = (SGL) 다른 날 칸 1 · '선택 완료' 1 / (RNG) '취소' 1 — 모두 ensureVisible 한 같은 글 중심 · 잰 hit 먼저(tapAt). 쓰기 · CF · 서버 대역 0.
//   첫 줄 억제(판정172 §5 정형 ①)는 쓰지 않는다 — 플랫폼 대역 import 0(정형 ② avoid_print 1줄만).
//   기본 skip — TB before/du607bcg-tb/DU_BEFORE_OBSERVE=607 · TA after/du607bcg-ta/없음.
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

/// [DU607b] 사례 — SGL = 날짜 선택 시트(단일 · 이 달 10일 이후 첫 평일(오늘 아님)을 고른 채 · 지난 날 허용) → 이웃 날 칸을 눌러 고른 뒤 '선택 완료' 반환 ·
///   RNG = 기간 선택 시트(범위 · 이 달 10일 이후 첫 금요일 ~ 그다음 월요일 — 시작 칸 두 자리 · 토 · 일이 띠 안) → '취소' 반환 null.
///   장수 = 첫 화면(1top) · 오늘(SGL) / 범위 시작(RNG) 줄 격자(2grid) · (SGL) 다른 날을 고른 뒤(3pick).
const _cases = <({String id, int shots})>[(id: 'SGL', shots: 3), (id: 'RNG', shots: 2)];

/// [DU607b] 요일 머리 7 글 · 시트 단추 글 — mkcell 이 base/후보 원문과 대조한다(두 모드 같은 글).
const _kWeek = ['일', '월', '화', '수', '목', '금', '토'];
const _kDone = '선택 완료';
const _kCancel = '취소';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '607';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du607bcg-tb' && _env['DU_BEFORE_OBSERVE'] == '607') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du607bcg-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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

// [DU607b] 아래 측정 도우미는 DU596b suite(79dbbbd8)에서 바이트 그대로 옮겼다 — :222–348(_txt · _bringBuilt · _semOf · _TO · _textLine — ensureVisible 대상 = 잰 대상 ·
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

// [DU607b] 누르는 자리 hit — DU581 r3 suite(3f4a404a · run DONE 5/5 19:35:21)의 :193–204 바이트 그대로(_hitWithin · DU600b 가 같은 범위를 옮겼다).

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

// [DU607b] 격자 복원 · 칸 칠 — DU598b g1 suite(c67984ed · 판정179 g1 수리 수용 · A test/ 사본과 같은 바이트)의 :334–398 바이트 그대로(_sameDay · _Cell · _grid · _CellObs · _cellInk).

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

// ───────────── [DU607b] 새로 쓴 부분 — 글 상자 · 칸 장식 · 격자 배치 · 날 고르기 · 사례 본문 ─────────────

/// [DU607b] 숫자 글 하나 — 그린 자리 · 줄 수(_lineCount) · 전문(max 판 _fullShown — 칸 높이에 잘린 줄은 전문 아님). 잰 즉시 값.
typedef _LabelObs = ({Rect r, int lines, bool full});

_LabelObs _labelOf(WidgetTester t, Element e) {
  final f = find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
  final rp = t.renderObject<RenderParagraph>(find.descendant(of: f, matching: find.byType(RichText), skipOffstage: false).first);
  return (r: t.getRect(f), lines: _lineCount(rp), full: _fullShown(rp, rp.size));
}

/// [DU607b] 숫자 글을 감싼 칸 장식 — 글에서 위로 칸 뿌리(가장 가까운 GestureDetector)까지 올라간 뒤 그 칸 안 DecoratedBox(BoxDecoration) 중 [pick] 에 맞는
///   것(여럿이면 가장 작은 것). inner = 그린 상자에서 테 두께를 뺀 칸(원이면 짧은 변 정사각형 가운데 · 둥근 칸이면 사각 그대로) · inside = 글 자리가 inner 안.
typedef _BoxObs = ({int n, Rect inner, bool inside});

_BoxObs _decoOf(WidgetTester t, Element label, bool Function(BoxDecoration d) pick) {
  Element? root;
  label.visitAncestorElements((a) {
    if (a.widget is GestureDetector) {
      root = a;
      return false;
    }
    return true;
  });
  final r0 = root;
  if (r0 == null) return (n: 0, inner: Rect.zero, inside: false);
  final rootF = find.byElementPredicate((x) => identical(x, r0), skipOffstage: false);
  final boxes = find
      .descendant(
          of: rootF,
          matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && pick(w.decoration as BoxDecoration)),
          skipOffstage: false)
      .evaluate()
      .toList();
  if (boxes.isEmpty) return (n: 0, inner: Rect.zero, inside: false);
  final cands = <({Rect r, BoxDecoration d})>[];
  for (final e in boxes) {
    cands.add((r: t.getRect(find.byElementPredicate((x) => identical(x, e), skipOffstage: false)), d: (e.widget as DecoratedBox).decoration as BoxDecoration));
  }
  cands.sort((a, b) => (a.r.width * a.r.height).compareTo(b.r.width * b.r.height));
  final box = cands.first.r;
  final deco = cands.first.d;
  final bw = deco.border is Border ? (deco.border as Border).top.width : 0.0;
  final side = math.min(box.width, box.height) - bw * 2;
  final inner = deco.shape == BoxShape.circle ? Rect.fromCenter(center: box.center, width: side, height: side) : box.deflate(bw);
  final lr = t.getRect(find.byElementPredicate((x) => identical(x, label), skipOffstage: false));
  return (n: boxes.length, inner: inner, inside: _inside(lr, inner));
}

/// [DU607b] 격자 배치 — 42 칸 숫자 글 상자(_grid 줄 순서): wr = 줄이 갈렸거나 전문이 아닌 칸 수 · gx = 같은 줄 이웃 글 사이 최소 ·
///   gy = 이웃 줄 같은 열 글 사이 최소 · al = 요일 머리 7 글 가운데 ↔ 그 열 날짜 글 가운데(6 줄 평균) 차의 최대(7칸 대응).
typedef _GeoObs = ({int n, int wr, double gx, double gy, double al});

_GeoObs _geoOf(WidgetTester t, Finder cal, List<_Cell> cells) {
  final ls = [for (final x in cells) _labelOf(t, x.e)];
  var wr = 0;
  for (final l in ls) {
    if (l.lines != 1 || !l.full) wr++;
  }
  var gx = 1e9;
  var gy = 1e9;
  for (var i = 0; i + 6 < ls.length; i += 7) {
    for (var j = 0; j < 6; j++) {
      gx = math.min(gx, ls[i + j + 1].r.left - ls[i + j].r.right);
    }
    if (i + 13 < ls.length) {
      for (var j = 0; j < 7; j++) {
        gy = math.min(gy, ls[i + 7 + j].r.top - ls[i + j].r.bottom);
      }
    }
  }
  var al = 0.0;
  for (var j = 0; j < 7; j++) {
    final hs = find.descendant(of: cal, matching: find.text(_kWeek[j], skipOffstage: false), skipOffstage: false).evaluate().toList();
    if (hs.length != 1 || ls.length != 42) return (n: ls.length, wr: wr, gx: gx, gy: gy, al: 99.0);
    final hx = t.getCenter(find.byElementPredicate((x) => identical(x, hs.first), skipOffstage: false)).dx;
    var sx = 0.0;
    for (var i = j; i < ls.length; i += 7) {
      sx += ls[i].r.center.dx;
    }
    al = math.max(al, (hx - sx / 6).abs());
  }
  return (n: ls.length, wr: wr, gx: gx, gy: gy, al: al);
}

/// [DU607b] 이 달 [from]일부터 첫 평일(월–금 · 오늘 아님) — SGL 이 고른 채 여는 두 자리 날.
DateTime _weekdayFrom(DateTime month, DateTime today, int from) {
  for (var d = from; d <= 28; d++) {
    final x = DateTime(month.year, month.month, d);
    if (x.weekday <= DateTime.friday && !_sameDay(x, today)) return x;
  }
  return DateTime(month.year, month.month, from);
}

/// [DU607b] 이 달 [from]일부터 첫 금요일 — RNG 범위 시작(두 자리 · 그다음 월요일까지 4일 모두 이 달 · 토 · 일이 띠 안).
DateTime _fridayFrom(DateTime month, int from) {
  for (var d = from; d <= from + 6; d++) {
    final x = DateTime(month.year, month.month, d);
    if (x.weekday == DateTime.friday) return x;
  }
  return DateTime(month.year, month.month, from);
}

/// [DU607b] 사례 — 시트를 앱 문맥에서 열고 ① 첫 화면 채움 단추(A8) · 1top ② 격자 복원 · 격자 배치(42 글 전문 · 줄 · 이웃 사이 · 7칸 대응) · 다른 달 칠(대비 잔여 기록)
///   ③ SGL: 오늘(테) · 고른 날(채움) 글이 칸 장식 안 · 칠 그대로 · 2grid → 이웃 날 칸을 눌러 고름 · 3pick → '선택 완료' 반환 = 누른 날
///      RNG: 범위 시작(테) 글이 칸 장식 안 · 띠 주말 칠 그대로 · 2grid → '취소' 반환 null. 누르기 = ensureVisible(_textLine)한 같은 글 중심 · hit 먼저.
Future<void> _caseOf(WidgetTester t, _V v, ({String id, int shots}) c, String tok) async {
  final prevOnError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = prevOnError);
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D607 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
  final sel = _weekdayFrom(month, today, 10);
  final nx = DateTime(sel.year, sel.month, sel.day + 1);
  final pick = _sameDay(nx, today) ? DateTime(sel.year, sel.month, sel.day - 1) : nx;
  final rs = _fridayFrom(month, 10);
  final re = DateTime(rs.year, rs.month, rs.day + 3);
  bool inRange(DateTime d) => !d.isBefore(rs) && !d.isAfter(re);
  final hBrand = _hex(AppColors.brand);
  final hWhite = _hex(AppColors.surface);
  final hG300 = _hex(AppColors.grey300);
  Object? got;
  var completed = false;
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
      unawaited(DatePickerBottomSheet.show(context: appEl, initialDate: sel, allowPastDates: true).then((x) {
        got = x;
        completed = true;
      }));
    } else {
      unawaited(DateRangePickerBottomSheet.show(context: appEl, initialStart: rs, initialEnd: re, allowPastDates: true).then((x) {
        got = x;
        completed = true;
      }));
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
      _out('D607 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    Future<void> settle(int n) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    final screen = Offset.zero & Size(v.w, v.h);
    // ① 첫 화면 — 채움 단추(A8 · 기록만) · 1top.
    final ftp = _fills(t);
    _out('D607 $tok att ftop n=${ftp.n} brand=${ftp.brand} err=${ftp.err} none=${ftp.none} other=${ftp.other} list=${ftp.list}');
    await shot('1top', 'sheet-top');
    // ② 격자 복원(위치 순서 → 날짜) · 격자 배치 · 다른 달 칠(대비 잔여 — 판정179 §4 '유지').
    final g = _grid(t, cal, month);
    _out('D607 $tok att gd n=${g.cells.length} ok=${g.ok}');
    if (!g.ok) throw StateError('격자 복원 실패');
    final geo = _geoOf(t, cal, g.cells);
    _out('D607 $tok att gb n=${geo.n} wr=${geo.wr} gx=${geo.gx.toStringAsFixed(1)} gy=${geo.gy.toStringAsFixed(1)} al=${geo.al.toStringAsFixed(1)}');
    Element? adjEl;
    Element? todayEl;
    Element? selEl;
    Element? rsEl;
    for (final x in g.cells) {
      if (adjEl == null && x.d.month != month.month) adjEl = x.e;
      if (_sameDay(x.d, today)) todayEl = x.e;
      if (_sameDay(x.d, sel)) selEl = x.e;
      if (_sameDay(x.d, rs)) rsEl = x.e;
    }
    final ae = adjEl;
    final adFg = ae == null ? '-' : _cellInk(ae).fg;
    _out('D607 $tok att ad fg=$adFg');
    var cellOk = false;
    var keep = false;
    var tail = true;
    var rtOk = false;
    var closed = false;
    if (c.id == 'SGL') {
      // ③ 오늘(테) · 고른 날(채움) — 오늘 글 Finder 를 ensureVisible 해 잰다(_textLine · A1) · 칸 장식 안 · 칠 그대로.
      final te = todayEl;
      final se = selEl;
      if (te == null || se == null) throw StateError('오늘/고른 날 칸 없음');
      final tdF = find.byElementPredicate((x) => identical(x, te), skipOffstage: false);
      await _bringBuilt(t, host, today.day.toString());
      final tl = await _textLine(t, tdF, today.day.toString(), screen);
      final tb = _decoOf(t, te, (d) => d.border != null);
      final ti = _cellInk(te);
      final tk = _inkOf(tdF);
      _out('D607 $tok att td n=${tl.n} lines=${tl.lines} full=${tl.full} tin=${tb.inside} vis=${tl.vis} fg=${ti.fg} line=${ti.line} c45=${tk.ok45}');
      final sl = _labelOf(t, se);
      final sb = _decoOf(t, se, (d) => d.color != null && d.border == null);
      final si = _cellInk(se);
      _out('D607 $tok att sl n=${sb.n} lines=${sl.lines} full=${sl.full} sin=${sb.inside} fg=${si.fg} bg=${si.bg}');
      final tdOk = tl.n == 1 && tl.lines == 1 && tl.full && tb.inside && tl.vis;
      final slOk = sb.n == 1 && sl.lines == 1 && sl.full && sb.inside;
      cellOk = tdOk && slOk;
      tail = !tdOk && !slOk;
      keep = tl.n == 1 && tb.n == 1 && ti.fg == hBrand && ti.line == hBrand && tk.ok45 && sb.n == 1 && si.fg == hWhite && si.bg == hBrand;
      await shot('2grid', 'grid-today');
      final fo = _fills(t);
      _out('D607 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
      // ④ 이웃 날 칸 — 같은 글 Finder 를 ensureVisible(_textLine) 하고 그 글 중심이 칸(GestureDetector)에 맞을 때만 누른다.
      Element? pe;
      for (final x in g.cells) {
        if (_sameDay(x.d, pick)) pe = x.e;
      }
      final pe0 = pe;
      if (pe0 == null) throw StateError('이웃 날 칸 없음');
      final pF = find.byElementPredicate((x) => identical(x, pe0), skipOffstage: false);
      await _bringBuilt(t, host, pick.day.toString());
      final pl = await _textLine(t, pF, pick.day.toString(), screen);
      final pp = t.getRect(pF).center;
      final pg = find.ancestor(of: pF, matching: find.byType(GestureDetector)).first;
      final pHit = pl.n == 1 && pl.vis && _hitWithin(t, pg, pp);
      if (!pHit) throw StateError('이웃 날 칸 hit 거짓');
      await t.tapAt(pp);
      await settle(8);
      final g2 = _grid(t, cal, month);
      var pSel = false;
      for (final x in g2.cells) {
        if (_sameDay(x.d, pick)) pSel = _cellInk(x.e).fg == hWhite;
      }
      _out('D607 $tok att px hit=$pHit sel=$pSel');
      await shot('3pick', 'picked');
      // ⑤ '선택 완료' — ensureVisible(_textLine) · 단추 hit 먼저 · 반환 = 누른 날 · 시트 닫힘.
      await _bringBuilt(t, host, _kDone);
      final dF = _txt(host, _kDone, onstage: false);
      final dl = await _textLine(t, dF, _kDone, screen);
      final dp = t.getRect(dF).center;
      final dBtn = find.ancestor(of: dF, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
      if (!(dl.n == 1 && dl.vis && _hitWithin(t, dBtn, dp))) throw StateError('선택 완료 hit 거짓');
      await t.tapAt(dp);
      await settle(16);
      final gv = got;
      rtOk = completed && gv is DateTime && _sameDay(gv, pick);
      closed = find.byType(BottomSheet).evaluate().isEmpty;
      _out('D607 $tok att rt done=$completed ok=$rtOk closed=$closed');
      keep = keep && pSel;
      raw = 'gd ${g.ok} gb $geo ad $adFg td $tl $tb $ti $tk sl $sl $sb $si px $pHit $pSel rt $completed $rtOk $closed fills $fo top $ftp';
    } else {
      // ③ 범위 시작(테) — 시작 글 Finder 를 ensureVisible 해 잰다(_textLine · A1) · 칸 장식 안 · 칠 그대로 · 띠 안 토 · 일 칠 그대로.
      final r0 = rsEl;
      if (r0 == null) throw StateError('범위 시작 칸 없음');
      final rF = find.byElementPredicate((x) => identical(x, r0), skipOffstage: false);
      await _bringBuilt(t, host, rs.day.toString());
      final rl = await _textLine(t, rF, rs.day.toString(), screen);
      final rb = _decoOf(t, r0, (d) => d.border != null);
      final ri = _cellInk(r0);
      final rk = _inkOf(rF);
      _out('D607 $tok att rs n=${rb.n} lines=${rl.lines} full=${rl.full} rin=${rb.inside} vis=${rl.vis} fg=${ri.fg} bg=${ri.bg} c45=${rk.ok45}');
      final inr = <_CellObs>[];
      for (final x in g.cells) {
        if (inRange(x.d) && (x.d.weekday == DateTime.saturday || x.d.weekday == DateTime.sunday)) inr.add(_cellInk(x.e));
      }
      final fgs = inr.map((o) => o.fg).toSet();
      final bgs = inr.map((o) => o.bg).toSet();
      final rg = (n: inr.length, fg: fgs.length == 1 ? fgs.first : 'mix', bg: bgs.length == 1 ? bgs.first : 'mix');
      _out('D607 $tok att rg n=${rg.n} fg=${rg.fg} bg=${rg.bg}');
      final rsOk = rl.n == 1 && rb.n == 1 && rl.lines == 1 && rl.full && rb.inside && rl.vis;
      cellOk = rsOk;
      tail = !rsOk;
      keep = rb.n == 1 && ri.fg == hWhite && ri.bg == hBrand && rk.ok45 && rg.n == 2 && rg.fg == hWhite && rg.bg == hBrand;
      await shot('2grid', 'grid-range-start');
      final fo = _fills(t);
      _out('D607 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
      // ④ '취소' — ensureVisible(_textLine) · 단추 hit 먼저 · 반환 = null · 시트 닫힘.
      await _bringBuilt(t, host, _kCancel);
      final cF = _txt(host, _kCancel, onstage: false);
      final cl = await _textLine(t, cF, _kCancel, screen);
      final cp = t.getRect(cF).center;
      final cBtn = find.ancestor(of: cF, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
      if (!(cl.n == 1 && cl.vis && _hitWithin(t, cBtn, cp))) throw StateError('취소 hit 거짓');
      await t.tapAt(cp);
      await settle(16);
      rtOk = completed && got == null;
      closed = find.byType(BottomSheet).evaluate().isEmpty;
      _out('D607 $tok att rt done=$completed ok=$rtOk closed=$closed');
      raw = 'gd ${g.ok} gb $geo ad $adFg rs $rl $rb $ri $rk rg $rg rt $completed $rtOk $closed fills $fo top $ftp';
    }
    final same = g.ok && geo.n == 42 && geo.al <= 1.0 && adFg == hG300 && keep && rtOk && closed;
    okBefore = same && (v.id == 'B' ? (geo.wr >= 1 && tail) : (geo.wr == 0 && cellOk));
    okStrict = same && geo.wr == 0 && geo.gx > 0 && geo.gy >= 0 && cellOk;
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // ⑥ 성공 · 실패 공통 정리 — 화면을 내리고 남은 timer · 애니메이션이 끝날 시간을 준다.
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
  _out('R607 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D607 $tok att fw n=$nFw');
  _out('D607 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  if (_before) {
    chk('before 대상 = 지금 A(격자 42 · 7칸 대응 · 다른 달 grey300 · 오늘 brand 글/테 · 고른 날 흰/brand · 범위 띠 흰/brand · 반환/취소 그대로 / '
        'W · N: 42 글 전문 한 줄 · 오늘 · 고른 날 · 범위 시작 글이 칸 장식 안 / B: 칸 높이에 잘린 글 ≥ 1 · 두 자리 고른 날 · 오늘 · 범위 시작 글이 칸 장식을 벗어남)', okBefore, raw);
  } else {
    chk('strict 대상 = 후보(42 글 전문 한 줄 · 이웃 글 겹침 0 · 7칸 대응 · 오늘 테 · 고른 날 채움 · 범위 시작 테 안에 글 · 색 · 분기 · 반환/취소 그대로)', okStrict, raw);
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
    await initializeDateFormatting('ko_KR');
    await _loadFonts();
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S607CG-${v.id}-${c.id} 당근 달력 — 큰 글자 날짜 칸 · 오늘 테 · 7칸 대응 · 반환/취소', (t) async {
        final tok = 'S607CG-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _caseOf(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
