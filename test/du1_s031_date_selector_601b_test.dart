// [DU601b · 파일 셀 · 표시만] DU-S031 공고 날짜 선택기(lib/screens/business_admin/to_management/widgets/to_date_selector.dart) 결정 미이행 —
//   장부 077 · 판정145 §5 :76 F138-DATESELECTOR-B-LAYOUT: B 요일 7칸 글자 잘림/겹침 → reflow(숨김 · 축소 · 말줄임 0) · 다음 날짜 선택기 셀 최우선.
//     요일 글자 상자(렌더와 같은 글 · 스타일 · 배율)가 칸(폭 − 48)/7 에 들어가면 예전 한 줄 7칸 그대로 · 안 들어가면 같은 모양 칸을 여러 줄로.
//   before = 지금 A(to_date_selector b062e68c = DU549 후보) 기록 · strict = 후보(cand/ · mkcell 이 SHA 대조).
//   하네스 = 블록 재사용(prep/mk_test.py 가 원본 fullSHA · 블록 sha12 · 경계 줄 단언): DU595b suite(7e30c11e · 판정177 §5 수용) —
//     글꼴 · max 판 _fullShown · _textObs · _area · _lineCount · 보기 W/B/N · _halt · env 줄 · _DSeen · _txt · 색 도우미 · _fills · _inkOf /
//     DU581 r3 suite(3f4a404a · DONE 5/5) — _hitWithin. 위젯 직접 pump 틀 = DU542/DU542b/DU549 시험(MaterialApp → Scaffold → SingleChildScrollView(좌우 16) → 선택기).
//   새로 쓴 것: 이 머리 · 사례 1(WEEK) · 요일 상수 · 상태 부모 _Host(작성 화면처럼 요일을 고르고 풀며 콜백을 센다) · 요일 칸 관측 _dayObs · 사례 본문 _caseOf · main.
//   Firebase · Firestore 대역 0(이 위젯은 읽기 · 쓰기 경계가 없다) — 그래서 파일 전체 억제 줄도 없다(억제 = 출력 함수 한 줄뿐).
//   누르는 것 = '일' 칸 중심(tapAt · 잰 hit 와 같은 점) 1번뿐 — 저장 · 게시 0.
//   기본 skip — TB before/du601btd-tb/DU_BEFORE_OBSERVE=601 · TA after/du601btd-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show BoxHeightStyle;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/business_admin/to_management/widgets/to_date_selector.dart';
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

/// [DU601b] 사례 — WEEK = 장기 근무 선택기(기간 유형 아직 안 고름 · 요일 월 · 수 · 금 · 토 고름) 요일 7칸 → 1week · '일' 칸을 눌러 고름 → 2tap.
const _cases = <({String id, int shots})>[(id: 'WEEK', shots: 2)];

/// [DU601b] 이 셀이 보는 글 — mkcell 이 base/후보 원문(_buildWeekdayButtons 의 const weekdays)과 대조한다.
const _kDays = ['월', '화', '수', '목', '금', '토', '일'];
const _kPicked = ['월', '수', '금', '토'];
const _kTapDay = '일';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '601';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du601btd-tb' && _env['DU_BEFORE_OBSERVE'] == '601') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du601btd-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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

// [DU601b] 아래 측정 도우미는 DU595b suite(7e30c11e · 판정177 §5 수용)에서 바이트 그대로 옮겼다 — :229–232(_txt) ·
//   :272–355(_lum · _contrast · _hex · _bgOf · _FillObs · _fills · _InkObs · _inkOf). 지연 목록 · 글 줄 측정 도우미(_bringBuilt · _semOf · _TO · _textLine)는 이 셀이 쓰지 않아 옮기지 않았다.

Finder _txt(Finder scope, String want, {bool onstage = true}) => find.descendant(
    of: scope,
    matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '') == want),
    skipOffstage: onstage);

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

// [DU601b] 누르는 자리 hit — DU581 r3 suite(3f4a404a · run DONE 5/5 19:35:21)의 :193–204 바이트 그대로(_hitWithin).

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

// ───────────── [DU601b] 새로 쓴 부분 — 상태 부모 · 요일 칸 관측 · 사례 본문 ─────────────

/// [DU601b] 상태 부모 — 작성 화면(create_to_screen 의 _selectedWeekdays)처럼 요일 콜백이 오면 고르고/푼다. 받은 요일을 [calls] 에 차례로 남긴다.
///   기간 유형은 아직 안 고른 상태(contractPeriodType null) — 날짜 칸 · 날짜 글이 없어 벽시계 · 날짜 형식(로캘)과 무관하다(A7).
class _Host extends StatefulWidget {
  const _Host({required this.calls});
  final List<String> calls;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final List<String> _days = List<String>.of(_kPicked);

  @override
  Widget build(BuildContext context) {
    return TODateSelector(
      isLongTerm: true,
      selectedWeekdays: List<String>.of(_days),
      onWeekdayToggle: (d) {
        widget.calls.add(d);
        setState(() {
          if (!_days.remove(d)) _days.add(d);
        });
      },
    );
  }
}

typedef _DayObs = ({int n, bool shown, bool full, int lines, bool vis, bool hit, String face, String fg, Rect r});

/// [DU601b · F138] 요일 칸 하나 — 칸(AnimatedContainer)을 ensureVisible 로 화면 안에 넣고 **같은 칸**의 자리 · 보임 · 중심 hit(그 칸의 GestureDetector)를 잰다(A1).
///   글 = 그 칸 안 요일 글의 _textObs(max 판 _fullShown — 칸보다 큰 글 줄은 full 거짓 · 잘린 글) · 칠 = 칸 면(decoration 목표값) · 글 칠(_inkOf 같은 Finder).
///   n ≠ 1 이면 재지 않는다. 잰 즉시 값으로 굳힌다.
Future<_DayObs> _dayObs(WidgetTester t, Finder selF, String day, Rect screen) async {
  final tf = _txt(selF, day, onstage: false);
  final n = tf.evaluate().length;
  if (n != 1) {
    return (n: n, shown: false, full: false, lines: 0, vis: false, hit: false, face: '-', fg: '-', r: Rect.zero);
  }
  final cellF = find.ancestor(of: tf, matching: find.byType(AnimatedContainer)).first;
  final gdF = find.ancestor(of: tf, matching: find.byType(GestureDetector)).first;
  await t.ensureVisible(cellF);
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final o = _textObs(t, tf, day);
  final r = t.getRect(cellF);
  final dec = t.widget<AnimatedContainer>(cellF).decoration;
  final Color? fc = dec is BoxDecoration ? dec.color : null;
  final io = _inkOf(tf);
  return (
    n: n,
    shown: o.shown,
    full: o.full,
    lines: _lineCount(t.renderObject<RenderParagraph>(find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: true).first)),
    vis: _inside(r, _area(cellF, screen)),
    hit: _hitWithin(t, gdF, r.center),
    face: fc == null ? '-' : _hex(fc),
    fg: io.fg,
    r: r,
  );
}

/// [DU601b] 사례 — 선택기를 그리고 ① 채움 단추(A8 · 기록만) · 요일 7칸(d1–d7 · 칸마다 ensureVisible → 같은 칸) · 모둠(wk: 줄 수 · 겹침 · 칸 사이) · 1week
///   ② '일' 칸 중심을 눌러(잰 hit 와 같은 점 · hit 거짓이면 누르지 않음) 고름 → 콜백 · 고른 칸 면(tp) · 2tap.
Future<void> _caseOf(WidgetTester t, _V v, ({String id, int shots}) c, String tok) async {
  final prevOnError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = prevOnError);
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D601 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
    final calls = <String>[];
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.businessAdminTheme,
        builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _Host(calls: calls),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final selF = find.byType(TODateSelector);
    final nSel = selF.evaluate().length;
    if (nSel != 1) throw StateError('날짜 선택기 $nSel');
    Future<void> shot(String id, String state) async {
      _out('D601 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    final screen = Offset.zero & Size(v.w, v.h);
    final f0 = _fills(t);
    _out('D601 $tok att f0 n=${f0.n} brand=${f0.brand} err=${f0.err} none=${f0.none} other=${f0.other} list=${f0.list}');
    // ① 요일 7칸 — 칸마다 그 칸을 ensureVisible 한 뒤 같은 칸을 잰다(마지막 = '일' 칸이 화면 안에 남는다).
    //   [r1 · 판정181 §3] 출력을 칸마다 리터럴 'att d1' … 'att d7' 로 풀었다(preflight 정적 대조) — 잰 함수 · 순서 · 키 · 값 · 단언은 1판과 같다.
    final d1 = await _dayObs(t, selF, _kDays[0], screen);
    _out('D601 $tok att d1 n=${d1.n} shown=${d1.shown} full=${d1.full} lines=${d1.lines} vis=${d1.vis} hit=${d1.hit} face=${d1.face} fg=${d1.fg} w=${d1.r.width.toStringAsFixed(1)} h=${d1.r.height.toStringAsFixed(1)}');
    final d2 = await _dayObs(t, selF, _kDays[1], screen);
    _out('D601 $tok att d2 n=${d2.n} shown=${d2.shown} full=${d2.full} lines=${d2.lines} vis=${d2.vis} hit=${d2.hit} face=${d2.face} fg=${d2.fg} w=${d2.r.width.toStringAsFixed(1)} h=${d2.r.height.toStringAsFixed(1)}');
    final d3 = await _dayObs(t, selF, _kDays[2], screen);
    _out('D601 $tok att d3 n=${d3.n} shown=${d3.shown} full=${d3.full} lines=${d3.lines} vis=${d3.vis} hit=${d3.hit} face=${d3.face} fg=${d3.fg} w=${d3.r.width.toStringAsFixed(1)} h=${d3.r.height.toStringAsFixed(1)}');
    final d4 = await _dayObs(t, selF, _kDays[3], screen);
    _out('D601 $tok att d4 n=${d4.n} shown=${d4.shown} full=${d4.full} lines=${d4.lines} vis=${d4.vis} hit=${d4.hit} face=${d4.face} fg=${d4.fg} w=${d4.r.width.toStringAsFixed(1)} h=${d4.r.height.toStringAsFixed(1)}');
    final d5 = await _dayObs(t, selF, _kDays[4], screen);
    _out('D601 $tok att d5 n=${d5.n} shown=${d5.shown} full=${d5.full} lines=${d5.lines} vis=${d5.vis} hit=${d5.hit} face=${d5.face} fg=${d5.fg} w=${d5.r.width.toStringAsFixed(1)} h=${d5.r.height.toStringAsFixed(1)}');
    final d6 = await _dayObs(t, selF, _kDays[5], screen);
    _out('D601 $tok att d6 n=${d6.n} shown=${d6.shown} full=${d6.full} lines=${d6.lines} vis=${d6.vis} hit=${d6.hit} face=${d6.face} fg=${d6.fg} w=${d6.r.width.toStringAsFixed(1)} h=${d6.r.height.toStringAsFixed(1)}');
    final d7 = await _dayObs(t, selF, _kDays[6], screen);
    _out('D601 $tok att d7 n=${d7.n} shown=${d7.shown} full=${d7.full} lines=${d7.lines} vis=${d7.vis} hit=${d7.hit} face=${d7.face} fg=${d7.fg} w=${d7.r.width.toStringAsFixed(1)} h=${d7.r.height.toStringAsFixed(1)}');
    final obs = <_DayObs>[d1, d2, d3, d4, d5, d6, d7];
    // 모둠 — 줄 수(칸 top 의 서로 다른 값) · 칸끼리 겹침 수 · 같은 줄 이웃 칸 사이 최소 · 칸 한 변.
    final rs = [for (final o in obs) o.r];
    final tops = <int>{for (final r in rs) r.top.round()};
    var ovl = 0;
    for (var i = 0; i < rs.length; i++) {
      for (var j = i + 1; j < rs.length; j++) {
        final x = rs[i].intersect(rs[j]);
        if (x.width > 0.5 && x.height > 0.5) ovl++;
      }
    }
    var gap = double.infinity;
    for (var i = 0; i + 1 < rs.length; i++) {
      if ((rs[i].top - rs[i + 1].top).abs() < 0.5) gap = math.min(gap, rs[i + 1].left - rs[i].right);
    }
    final nOk = obs.where((o) => o.n == 1).length;
    _out('D601 $tok att wk n=$nOk rows=${tops.length} ovl=$ovl gap=${gap.isFinite ? gap.toStringAsFixed(1) : '0.0'} side=${rs.first.width.toStringAsFixed(1)}');
    await shot('1week', 'weekdays');
    // ② '일' 칸 중심을 누른다 — 잰 hit 와 같은 점. 그 점이 그 칸 GestureDetector 에 맞지 않으면 누르지 않는다(tap 거짓 · 콜백 0 으로 기록).
    final last = obs.last;
    var tapped = false;
    if (last.n == 1 && last.hit) {
      await t.tapAt(last.r.center);
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      tapped = true;
    }
    final after = await _dayObs(t, selF, _kTapDay, screen);
    final picked = after.face == _hex(AppColors.brand);
    _out('D601 $tok att tp tap=$tapped n=${calls.length} day=${calls.isEmpty ? '-' : calls.last} sel=$picked');
    await shot('2tap', 'weekday-picked');
    final allFull = obs.every((o) => o.full);
    final same = nOk == 7 &&
        obs.every((o) => o.shown && o.vis && o.hit) &&
        [for (var i = 0; i < 7; i++) obs[i].face == _hex(_kPicked.contains(_kDays[i]) ? AppColors.brand : AppColors.grey100)].every((x) => x) &&
        [for (var i = 0; i < 7; i++) obs[i].fg == _hex(_kPicked.contains(_kDays[i]) ? AppColors.surface : AppColors.textPrimary)].every((x) => x) &&
        tapped && calls.length == 1 && calls.last == _kTapDay && picked;
    okBefore = same && tops.length == 1 && (v.id == 'B' ? !allFull : allFull);
    okStrict = same && allFull && ovl == 0 && obs.every((o) => (o.r.width - o.r.height).abs() < 0.01) && (v.id == 'B' ? tops.length >= 2 : tops.length == 1);
    raw = 'f0 $f0 obs $obs tops $tops ovl $ovl gap $gap after $after calls $calls';
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // ③ 성공 · 실패 공통 정리 — 화면을 내리고 남은 timer 가 끝날 시간을 준다.
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
  _out('R601 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D601 $tok att fw n=$nFw');
  _out('D601 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

  final f1 = failure;
  if (f1 != null) {
    _halt ??= '$tok ${f1.toString().split('\n').first}';
    Error.throwWithStackTrace(f1, failureSt ?? StackTrace.current);
  }
  if (_before) {
    chk('before 대상 = 지금 A(요일 7칸 한 줄 · 글 1개씩 · 칸 보임 · 중심 hit · 고른 칸 brand/흰 글 · 안 고른 칸 grey100/textPrimary · '
        '일 칸 눌러 콜백 1 · 고름 / B: 요일 글 줄이 칸보다 커서 어느 칸에선가 잘림(full 거짓) / W · N: 7칸 모두 전문)', okBefore, raw);
  } else {
    chk('strict 대상 = 후보(요일 7칸 모두 전문 · 정사각 · 겹침 0 · 칸 보임 · 중심 hit · 색 그대로 · W · N 한 줄 · B 여러 줄 · '
        '일 칸 눌러 콜백 1 · 고름)', okStrict, raw);
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
      testWidgets('S601TD-${v.id}-${c.id} 공고 날짜 선택기 — 큰 글자 요일 칸 줄바꿈 · 글자 잘림 0', (t) async {
        final tok = 'S601TD-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _caseOf(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
