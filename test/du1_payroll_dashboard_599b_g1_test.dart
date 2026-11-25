// [DU599b g1 · 파일 셀 · 표시만 · 판정179 §3 P1–P4] 급여 지급 현황(lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart) — 판정156 Q3 :39 · :41(+Q1 :25) 화면 안내 호칭.
//   ① 통장사본 검토 뒤 토스트(재등록 요청 갈래) ② 이체자료 준비 시트 '일부 건만 포함된 … N명' 안내(+ P1 낱말 줄바꿈 · 원문 접근성 이름) ③ 중간정산 승인 확인창 끝 줄 — 옛 호칭 → '근무자'.
//   (장부 136 :792 · 137 :970 은 화면을 그리지 않는 문구라 이 suite 대상 밖 — 기존 시험 PAO-B4/C2/C3 · recovery 23 이 RG 로 본다.)
//   before = 지금 A(98b6ce96) · strict = 후보(g1/cand · mkcell 이 SHA 대조) — 세 글과 시트 부제 표시 규칙은 **실행 순간 A 원문에서 꺼낸다**(_texts · _xfrRule ·
//     TB = base 글 · plain 규칙 / TA = 후보 글 · keepWords 규칙 — 시험 상수로 덮지 않는다 · TB 에 후보 조판을 미리 넣지 않는다).
//   그리는 것 = 제품이 그 글을 넘기는 같은 공용 부품: ToastHelper.showSuccess(그 글) · DialogHelper.showConfirm(같은 제목 · 단추 · 같은 줄 구성 · 대역 값) ·
//     DialogHelper.showSheet(같은 SafeArea · ConstrainedBox 0.8 · SingleChildScrollView(20,20,20,16) · Column(stretch) · 제목 · tinyStyle grey600 안내 글).
//     실제 대시보드 경로(통장사본 열람 · 판정 기록 · 이체 계획 · 날짜 고르기)는 그리지 않는다(README §1 한계 · XFR 은 축약 재현).
//   하네스 = 블록 재사용(g1/prep/mk_test_g1.py 가 원본 fullSHA · 블록 sha12 단언): DU596b suite(79dbbbd8 · 원 DU599b 와 같은 세 블록) +
//     DU593c suite(d8244c5c · run DONE 5/5 04:21) 의 _hitWithin · _lineRects · _btnReach · _sweep(→ _reach: 바뀐 끝 문장 글자 범위 줄을 같은 read() 에서 더 센다).
//   원 DU599b suite(e882277c) 대비 새로 쓴 것: 시트 부제 표시 규칙 _xfrRule(P1) · 해석된 접근성 이름 _anOf(P2) · CFM 연속 도달 rch · 주 행동 cta · 끝 화면 2end ·
//     before 기록 계약(P3 — XFR 끊김 · CFM 본문 동시 가시 · Text-local 이름은 기록만 · 그 밖은 두 모드 정확).
//   누르는 것 0(ensureVisible · _bringBuilt · 본문 끌기 1 — 버튼 위가 아니라 본문 글 위에서만). 쓰기 · CF · 서버 대역 0. 첫 줄 억제 0(정형 ② avoid_print 1줄만).
//   기본 skip — TB before/du599bg1-tb/DU_BEFORE_OBSERVE=599 · TA after/du599bg1-ta/없음.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show BoxHeightStyle;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/responsive_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/utils/toast_helper.dart';

import 'support/du1_vq_capture.dart';

// [DU599b g1 · 판정179 P2] 아래 도달 도우미는 DU593c suite(d8244c5c · run DONE 5/5 04:21)에서 옮겼다 — :199–210 _hitWithin · :222–242 _lineRects(문서 줄 낱말 1개만
//   '_sweep 이' → '_reach 가') · 같은 블록을 글자 범위로 좁힌 _lineRectsIn(정규화 3) · :830–853 _BO · _btnReach(바이트 그대로) · :860–943 _sweep → _reach(정규화 6:
//   이름 · 끝 문장 인자 · 끝 문장 글자 범위 줄 tl 을 같은 read() 에서 함께 센다 · 반환 3 필드). 걸음 · 끌기 · 놓기 · 구멍 셈 · 가로 잘림 셈 식은 그대로다(mk_test_g1.py 단언).

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

/// [동의 g6 du1 · 판정174 §6 기존 du1 증명 그대로] 아래 _reach 가 쓴다.
/// [g5] 문단의 줄 상자(문단 좌표) — 보이는 글자마다 max 상자(줄 배치 세로 · tight 가로)를 같은 줄끼리 합친다(공백 · 낱말 묶음 문자 제외).
List<Rect> _lineRects(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final out = <Rect>[];
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == _wj || _gap(ch)) continue;
    for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1), boxHeightStyle: ui.BoxHeightStyle.max)) {
      final r = b.toRect();
      final k = out.indexWhere((x) => (x.top - r.top).abs() <= 0.5);
      if (k < 0) {
        out.add(r);
      } else {
        out[k] = out[k].expandToInclude(r);
      }
    }
  }
  out.sort((a, b) => a.top.compareTo(b.top));
  return out;
}

/// [DU599b g1] 아래 _reach 가 바뀐 끝 문장 줄을 셀 때 쓴다 — 위 _lineRects 와 같은 식을 글자 범위 [from, to) 로만 좁혔다.
/// [g5] 문단의 줄 상자(문단 좌표) — 보이는 글자마다 max 상자(줄 배치 세로 · tight 가로)를 같은 줄끼리 합친다(공백 · 낱말 묶음 문자 제외).
List<Rect> _lineRectsIn(RenderParagraph rp, int from, int to) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final out = <Rect>[];
  for (var i = from; i < to && i < s.length; i++) {
    final ch = s[i];
    if (ch == _wj || _gap(ch)) continue;
    for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1), boxHeightStyle: ui.BoxHeightStyle.max)) {
      final r = b.toRect();
      final k = out.indexWhere((x) => (x.top - r.top).abs() <= 0.5);
      if (k < 0) {
        out.add(r);
      } else {
        out[k] = out[k].expandToInclude(r);
      }
    }
  }
  out.sort((a, b) => a.top.compareTo(b.top));
  return out;
}

/// [DU562 r2 · DONE 5/5 그대로] 아래 _btnReach 는 DU581 _bringBuilt(같은 이름 · 같은 인자 String?) 와 함께 쓴다(지어져 있으면 아무것도 하지 않는다).
typedef _BO = ({int n, bool vis, bool hit, bool m48});

/// 글자 버튼(누르지 않는다) — 글 [label] 의 InkWell 조상을 ensureVisible 로 화면 안에 넣고 **같은 InkWell** 을 잰다(DU560 r3 _btnLine 과 같은 대상).
Future<_BO> _btnReach(WidgetTester t, Finder scope, String label, Rect screen) async {
  await _bringBuilt(t, scope, label);
  final tf = _txt(scope, label, onstage: false);
  final n = tf.evaluate().length;
  var vis = false;
  var hit = false;
  var m48 = false;
  if (n == 1) {
    final ink = find.ancestor(of: tf, matching: find.byType(InkWell)).first;
    await t.ensureVisible(ink);
    for (var m = 0; m < 4; m++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final r = t.getRect(ink);
    m48 = r.width >= 48 - 0.01 && r.height >= 48 - 0.01;
    vis = _inside(r, _area(ink, screen));
    hit = _hitWithin(t, ink, r.center);
  }
  return (n: n, vis: vis, hit: hit, m48: m48);
}

/// [DU599b g1 · 판정179 P2] 확인창 본문 RichText [tf] 하나 — DU593c _sweep(동의 g6 du1 read() · 걸음 · 터치 슬롭 24 · 놓기 전 멈춤 · 구멍 셈 · 가로 잘림 셈)을 그대로 쓰고,
///   [tail](바뀐 끝 문장 = 원문에서 꺼낸 글)의 글자 범위(그린 글의 마지막 '\n' 뒤)를 그 범위의 줄 상자(_lineRectsIn)로 같은 read() 에서 함께 센다(tseen · 가로까지 칸 안).
///   tsrc = 그 범위 글(표시 제어 문자 뺀 것) = [tail]. _textLine 의 ensureVisible 로 문단 윗끝이 칸 윗끝에 온 자리에서 같은 본문 scroll owner 를 끝(max)까지 실제로 끈다.
///   칸에 다 들어가면(max 0) 끌지 않고 한 프레임만 읽는다. 단언은 부르는 쪽(사례 본문 · cell lines 두 모드 정확).
typedef _RchObs = ({int n, int lines, int seen, bool top, bool last, bool whole, bool need, bool cont, int hcut, bool fit, bool end, bool moved, int tlines, int tseen, bool tsrc});

Future<_RchObs> _reach(WidgetTester t, Finder tf, Rect screen, String tail) async {
  final n = tf.evaluate().length;
  if (n != 1) return (n: n, lines: 0, seen: 0, top: false, last: false, whole: false, need: false, cont: false, hcut: 0, fit: false, end: false, moved: false, tlines: 0, tseen: 0, tsrc: false);
  final swRp = t.renderObject<RenderParagraph>(tf);
  final lines = _lineRects(swRp);
  final ps = swRp.text.toPlainText(includeSemanticsLabels: false);
  final tk = ps.lastIndexOf('\n') + 1;
  final tsrc = TextLayout.plain(ps.substring(tk)) == tail;
  final tl = _lineRectsIn(swRp, tk, ps.length);
  final tseen = List<bool>.filled(tl.length, false);
  final h = swRp.size.height;
  final sc = find.ancestor(of: tf, matching: find.byType(Scrollable)).first;
  final pos = t.state<ScrollableState>(sc).position;
  final p0 = pos.pixels;
  final fit = pos.maxScrollExtent <= 0.5;
  final a0 = _area(tf, screen);
  final needWhole = h <= a0.height + 0.5;
  final stepPx = needWhole ? ((a0.height - h) / 2).clamp(1.0, 8.0).toDouble() : 8.0;
  final seen = List<bool>.filled(lines.length, false);
  final spans = <(double, double)>[];
  var wholeSeen = false;
  var topSeen = false;
  var hcut = 0;
  void read() {
    final a = _area(tf, screen);
    if (a.isEmpty) return;
    final o = swRp.localToGlobal(Offset.zero);
    final vTop = (a.top - o.dy).clamp(0.0, h).toDouble();
    final vBot = (a.bottom - o.dy).clamp(0.0, h).toDouble();
    if (vBot > vTop) {
      spans.add((vTop, vBot));
      if (vTop <= 0.5) topSeen = true;
    }
    for (var i = 0; i < lines.length; i++) {
      final g = lines[i].shift(o);
      if (!(g.left >= a.left - 0.5 && g.right <= a.right + 0.5)) hcut++;
      if (g.top >= a.top - 0.5 && g.bottom <= a.bottom + 0.5) seen[i] = true;
    }
    for (var i = 0; i < tl.length; i++) {
      final g = tl[i].shift(o);
      if (g.top >= a.top - 0.5 && g.bottom <= a.bottom + 0.5 && g.left >= a.left - 0.5 && g.right <= a.right + 0.5) tseen[i] = true;
    }
    if (_inside(o & swRp.size, a)) wholeSeen = true;
  }

  read();
  if (!fit) {
    final start = t.getRect(tf).intersect(a0).center;
    final drag = await t.startGesture(start);
    await drag.moveBy(const Offset(0, -24)); // 끌기 인식(터치 슬롭 넘김)
    await t.pump(const Duration(milliseconds: 16));
    read();
    var moves = 0;
    while (moves < 600 && pos.pixels < pos.maxScrollExtent - 0.5) {
      await drag.moveBy(Offset(0, -stepPx));
      await t.pump(const Duration(milliseconds: 16));
      moves++;
      read();
    }
    await t.pump(const Duration(milliseconds: 150)); // 놓기 전 멈춤 — 튕김 없이 놓는다
    await drag.up();
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    read();
  }
  spans.sort((x, y) => x.$1.compareTo(y.$1));
  var covered = 0.0;
  var hole = -1.0;
  for (final s in spans) {
    if (s.$1 > covered + 0.5) {
      hole = covered;
      break;
    }
    if (s.$2 > covered) covered = s.$2;
  }
  return (
    n: 1,
    lines: lines.length,
    seen: seen.where((x) => x).length,
    top: topSeen,
    last: seen.isNotEmpty && seen.last,
    whole: wholeSeen,
    need: needWhole,
    cont: hole < 0 && covered >= h - 0.5,
    hcut: hcut,
    fit: fit,
    end: pos.pixels >= pos.maxScrollExtent - 0.5,
    moved: (pos.pixels - p0).abs() > 0.5,
    tlines: tl.length,
    tseen: tseen.where((x) => x).length,
    tsrc: tsrc,
  );
}

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

/// [DU599b g1] 사례 — TST = 토스트(통장사본 재등록 요청 · successDark 면) · XFR = 이체자료 준비 시트(일부 포함 안내 · 대역 N=2) ·
///   CFM = 중간정산 승인 확인창(대역 이름 · 기간 · 금액 · 예정일 + 원문 끝 줄). 장수 = TST/XFR 1 · CFM 2(첫 화면 · 본문 끝까지 끈 끝 화면).
const _cases = <({String id, int shots})>[(id: 'TST', shots: 1), (id: 'XFR', shots: 1), (id: 'CFM', shots: 2)];

/// [DU599b] 실행 순간 읽는 원문 경로(TB = base · TA = 후보) · 바뀌는 낱말 두 개(mkcell 이 원문과 대조).
const _kDash = 'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
const _kOld = '근로자';
const _kNew = '근무자';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '599';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du599bg1-tb' && _env['DU_BEFORE_OBSERVE'] == '599') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du599bg1-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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

// [DU599b] 아래 측정 도우미는 DU596b suite(79dbbbd8)에서 바이트 그대로 옮겼다 — :222–348(_txt · _bringBuilt · _semOf · _TO · _textLine — ensureVisible 대상 = 잰 대상 ·
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

// ───────────── [DU599b g1] 새로 쓴 부분 — 원문 글 꺼내기 · 시트 부제 표시 규칙(P1) · 접근성 이름(P2) · 세 부품 그리기 · 사례 본문 ─────────────

/// [DU599b] 원문 [src] 의 [anchor] 첫 위치 뒤에서 [rx] 첫 일치의 1번 묶음(못 찾으면 '').
String _fromSrc(String src, String anchor, RegExp rx) {
  final i = src.indexOf(anchor);
  if (i < 0) return '';
  final m = rx.firstMatch(src.substring(i));
  return m == null ? '' : (m.group(1) ?? '');
}

/// [DU599b] 세 글 — 토스트(재등록 요청 갈래 글) · 시트 안내(대역 N=2 를 넣은 완성 문장 — 원문 두 조각 이어 붙임) · 확인창 끝 줄.
({String toast, String part, String last}) _texts(String src) {
  final toast = _fromSrc(src, 'ToastHelper.showSuccess(r.correctionOpened', RegExp(r"\?\s*'([^'\n]+)'"));
  final i = src.indexOf('if (plan.partialWorkers > 0) ...[');
  final m = i < 0 ? null : RegExp(r"'(일부 건만 포함된 [^'$\n]*)\$\{plan\.partialWorkers\}(명 — )'\s*'([^'\n]*)'").firstMatch(src.substring(i));
  final part = m == null ? '' : '${m.group(1)}2${m.group(2)}${m.group(3)}';
  final last = _fromSrc(src, "title: '중간정산 승인',", RegExp(r"'(승인 시 [^'\n]+)'"));
  return (toast: toast, part: part, last: last);
}

/// [DU599b g1 · 판정179 P1] 제품 이체자료 시트 부제 Text 의 표시 규칙 — 실행 순간 A 원문의 그 Text 블록이 base 꼴(plain 두 조각)인지
///   후보 꼴(TextLayout.keepWords(같은 두 조각) + semanticsLabel(같은 두 조각) · 앞 주석 줄 허용)인지 본다(TB = base → 'plain' · TA = 후보 → 'kw').
///   앵커가 하나가 아니거나 두 꼴 중 정확히 하나가 아니면 ''(사례가 멈춘다 — 다른 꼴을 plain 으로 대신 그리지 않는다). mkcell 이 같은 식을 base · 후보에 대입해 단언한다.
final _kKw = RegExp(
    r"^\s*const SizedBox\(height: 6\),\s*(?://[^\n]*\s*)*Text\(\s*TextLayout\.keepWords\(\s*'(일부 건만 포함된 [^'$\n]*)\$\{plan\.partialWorkers\}(명 — )'\s*'([^'\n]*)'\),\s*semanticsLabel:\s*'\1\$\{plan\.partialWorkers\}\2'\s*'\3',\s*style: ResponsiveHelper\.tinyStyle\(ctx,");
final _kPlain = RegExp(
    r"^\s*const SizedBox\(height: 6\),\s*(?://[^\n]*\s*)*Text\(\s*'(일부 건만 포함된 [^'$\n]*)\$\{plan\.partialWorkers\}(명 — )'\s*'([^'\n]*)',\s*style: ResponsiveHelper\.tinyStyle\(ctx,");

String _xfrRule(String src) {
  const anchor = 'if (plan.partialWorkers > 0) ...[';
  final i = src.indexOf(anchor);
  if (i < 0 || src.indexOf(anchor, i + 1) >= 0) return '';
  final s = src.substring(i + anchor.length);
  final kw = _kKw.hasMatch(s);
  final plain = _kPlain.hasMatch(s);
  if (kw == plain) return '';
  return kw ? 'kw' : 'plain';
}

/// [DU599b] 확인창 본문 — 제품 _approveSettlement 의 message 와 같은 줄 구성(대역 이름 · 기간 · 건수 · 금액 · 예정일 · 끝 줄 = 원문에서 꺼낸 글).
String _cfmMessage(String last) => '김지현님의 중간정산을 승인합니다.\n'
    '기간: 11월 1일 ~ 11월 15일 (3건)\n'
    '금액: ${FormatHelper.formatWage(345000)}\n'
    '이체 예정일: ${DateFormat('yyyy년 MM월 dd일').format(DateTime(2026, 11, 25))}\n\n$last';

/// [DU599b g1 · 판정179 P1] 이체자료 준비 시트 그릇 — 원 DU599b _xfrSheet(제품 _showTransferPlanSheet 와 같은 SafeArea · ConstrainedBox(높이 0.8) ·
///   SingleChildScrollView(20,20,20,16) · Column(stretch) · 제목 '이체자료 준비'(titleStyle w800) · 일부 포함 안내(tinyStyle grey600)) 그대로이고, 안내 Text 만
///   제품 표시 규칙 [kw](= _xfrRule 이 원문에서 읽은 값)를 따른다: kw = TextLayout.keepWords(글) + semanticsLabel(원문) · 아니면 plain 글. 건수 · 금액 행 · 확인 필요 목록 · 단추는 넣지 않는다.
Widget _xfrSheet(BuildContext ctx, String part, bool kw) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('이체자료 준비', style: ResponsiveHelper.titleStyle(ctx).copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              const SizedBox(height: 6),
              Text(kw ? TextLayout.keepWords(part) : part, semanticsLabel: kw ? part : null, style: ResponsiveHelper.tinyStyle(ctx, color: AppColors.grey600)),
            ],
          ),
        ),
      ),
    );

/// [DU599b g1 · 판정179 P2] 해석된 접근성 이름 — [tf](_textLine 이 잰 같은 Text Finder)의 바로 위 요소가 ExcludeSemantics(excluding)이고 그 위가 Semantics 면
///   (공용 확인창 _wordSafeText 꼴: Semantics(label: 원문) → ExcludeSemantics → Text(keepWords)) 그 label · 아니면 Text 자신의 읽는 이름(_semOf).
///   문자열 정규화 0 — 제어문자가 남아 있으면 원문과 다르다. Text-local 이름(_textLine sem)은 따로 기록한다.
String _anOf(Finder tf) {
  final te = tf.evaluate().first;
  Element? up;
  te.visitAncestorElements((a) {
    up = a;
    return false;
  });
  final x = up;
  if (x != null && x.widget is ExcludeSemantics && (x.widget as ExcludeSemantics).excluding) {
    Element? up2;
    x.visitAncestorElements((a) {
      up2 = a;
      return false;
    });
    final y = up2;
    return y != null && y.widget is Semantics ? ((y.widget as Semantics).properties.label ?? '') : '';
  }
  return _semOf(te.widget as Text);
}

/// [DU599b] 낱말 셈 — 그린 글(= 원문 글 · shown 으로 대조)의 옛 호칭 · 새 호칭 수.
typedef _WordObs = ({int old, int neu});

_WordObs _words(String s) => (old: _kOld.allMatches(s).length, neu: _kNew.allMatches(s).length);

/// [DU599b] 확인창 주 행동 채움 — [label] 글(정확 일치 1개) 뒤 실제 면(_bgOf — _DialogAction 의 Material 채움). ButtonStyleButton 이 아니라 _fills 에 잡히지 않는다(A8).
typedef _BtnObs = ({int n, String fill, bool brand});

_BtnObs _btnOf(Finder host, String label) {
  final es = find.descendant(of: host, matching: find.text(label, skipOffstage: false), skipOffstage: false).evaluate().toList();
  if (es.length != 1) return (n: es.length, fill: '-', brand: false);
  final bg = _bgOf(es.first);
  return (n: 1, fill: _hex(bg), brand: bg.toARGB32() == AppColors.brand.toARGB32());
}

/// [DU599b g1] 사례 — 앱 문맥에서 부품을 띄우고 ① 첫 화면 채움 단추(A8 · 기록만) ② (XFR) 원문 시트 부제 표시 규칙(xr) ③ 대상 글: 원문에서 꺼낸 글 → _bringBuilt(A4) →
///   _textLine(ensureVisible 대상 = 잰 대상 · A1) · 같은 Finder 의 접근성 이름(an) · 칠(_inkOf) · 낱말 셈 · (CFM) 확인 단추 채움 · 화면 채움 단추(A8) · 첫 화면 1장
///   ④ (CFM) 같은 본문 RenderParagraph 를 끝까지 끌어 연속 도달(rch) · 주 행동 '승인' 48 · 칸 안 · hit(cta) · 끝 화면 1장.
Future<void> _caseOf(WidgetTester t, _V v, ({String id, int shots}) c, String tok) async {
  final prevOnError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = prevOnError);
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D599 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
    final src = File(_kDash).readAsStringSync();
    final tx = _texts(src);
    final want = c.id == 'TST' ? tx.toast : (c.id == 'XFR' ? tx.part : (tx.last.isEmpty ? '' : _cfmMessage(tx.last)));
    if (want.isEmpty) throw StateError('원문 글 못 찾음 ${c.id} — toast ${tx.toast.length} part ${tx.part.length} last ${tx.last.length}');
    // [g1 · P1] 시트 부제 표시 규칙(XFR 만) — 못 읽으면 멈춘다(plain 으로 대신 그리지 않는다).
    final rule = c.id == 'XFR' ? _xfrRule(src) : '-';
    if (rule.isEmpty) throw StateError('시트 부제 표시 규칙 못 읽음 — base 꼴 · 후보 꼴 중 정확히 하나가 아님');
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.businessAdminTheme,
        builder: (bc, child) => MediaQuery(data: MediaQuery.of(bc).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final ftp = _fills(t);
    _out('D599 $tok att ftop n=${ftp.n} brand=${ftp.brand} err=${ftp.err} none=${ftp.none} other=${ftp.other} list=${ftp.list}');
    final appEl = t.element(find.byType(Scaffold).first);
    if (!appEl.mounted) throw StateError('앱 문맥 없음');
    if (c.id == 'TST') {
      ToastHelper.showSuccess(want);
    } else if (c.id == 'XFR') {
      _out('D599 $tok att xr rule=$rule');
      unawaited(DialogHelper.showSheet<void>(appEl, isScrollControlled: true, builder: (ctx) => _xfrSheet(ctx, want, rule == 'kw')));
    } else {
      unawaited(DialogHelper.showConfirm(appEl, title: '중간정산 승인', message: want, confirmText: '승인', cancelText: '취소'));
    }
    // 토스트는 2초 뒤 사라진다 — 띄운 뒤 0.3초 · 잰 뒤 바로 찍는다(합 1초 안). 창 · 시트는 열림 애니메이션 1초.
    for (var i = 0; i < (c.id == 'TST' ? 3 : 10); i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final host = find.byType(MaterialApp);
    Future<void> shot(String id, String state) async {
      _out('D599 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    final screen = Offset.zero & Size(v.w, v.h);
    // ③ 대상 글 — 지어졌는지 대비(_bringBuilt · 같은 host · 같은 글) 뒤 같은 Finder 를 ensureVisible 해 잰다(_textLine) · 그 Finder 의 이름 · 칠.
    await _bringBuilt(t, host, want);
    final tf = _txt(host, want, onstage: false);
    final lo = await _textLine(t, tf, want, screen);
    // [g1 · P2] 해석된 접근성 이름(같은 Finder · 잰 즉시) — 조상 Semantics 원문 또는 Text 자신의 이름. Text-local sem 은 그대로 기록한다.
    final an = lo.n == 1 && _anOf(tf) == want;
    if (c.id == 'CFM') {
      _out('D599 $tok att cl n=${lo.n} shown=${lo.shown} sem=${lo.sem} an=$an full=${lo.full} ell0=${lo.ell0} brk=${lo.brk} lines=${lo.lines} vis=${lo.vis}');
    } else {
      _out('D599 $tok att tl n=${lo.n} shown=${lo.shown} sem=${lo.sem} full=${lo.full} ell0=${lo.ell0} brk=${lo.brk} lines=${lo.lines} vis=${lo.vis}');
    }
    final io = _inkOf(tf);
    _out('D599 $tok att tk n=${io.n} fg=${io.fg} bg=${io.bg} cr=${io.cr} ok45=${io.ok45}');
    final w = _words(want);
    _out('D599 $tok att tw old=${w.old} new=${w.neu}');
    var btnOk = true;
    if (c.id == 'CFM') {
      final cb = _btnOf(host, '승인');
      _out('D599 $tok att cb n=${cb.n} fill=${cb.fill} brand=${cb.brand}');
      btnOk = cb.n == 1 && cb.brand;
      raw = 'cb $cb ';
    }
    final fo = _fills(t);
    _out('D599 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
    if (c.id == 'TST') {
      await shot('1toast', 'toast');
    } else if (c.id == 'XFR') {
      await shot('1sheet', 'transfer-plan-sheet');
    } else {
      await shot('1confirm', 'interim-approve-confirm');
    }
    // ④ [g1 · 판정179 P2] CFM — 같은 본문 RenderParagraph · 실제 조상 Scrollable 을 끝까지 끌어 모든 줄 · 바뀐 끝 문장 줄 · 말단 · 가로 잘림 /
    //   주 행동 '승인' 받는 자리 48 · 칸 안 · 중심 hit. before · strict 같은 뜻(두 모드 정확) — 실제 도달 실패면 이 사례에서 멈춘다(기록형으로 넘기지 않는다).
    var reachOk = true;
    if (c.id == 'CFM') {
      final r = await _reach(t, find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: false).first, screen, tx.last);
      _out('D599 $tok att rch n=${r.n} lines=${r.lines} miss=${r.lines - r.seen} top=${r.top} cont=${r.cont} last=${r.last} end=${r.end} hcut=${r.hcut} tlines=${r.tlines} tmiss=${r.tlines - r.tseen} tsrc=${r.tsrc} fit=${r.fit} moved=${r.moved} whole=${r.whole}');
      final k = await _btnReach(t, host, '승인', screen);
      _out('D599 $tok att cta n=${k.n} m48=${k.m48} vis=${k.vis} hit=${k.hit}');
      reachOk = an && r.n == 1 && r.seen == r.lines && r.top && r.cont && r.last && r.end && r.hcut == 0 && r.tlines > 0 && r.tseen == r.tlines && r.tsrc &&
          k.n == 1 && k.m48 && k.vis && k.hit;
      raw = '${raw}rch $r cta $k ';
      await shot('2end', 'interim-approve-confirm-end');
    }
    // [g1 · 판정179 P3] 모은 단언 = cell lines 의 두 모드 정확 + 그 모드 정확. before 는 XFR 끊김 · CFM 본문 동시 가시(vis) · CFM Text-local 이름(sem)을 기록만 한다.
    final both = lo.n == 1 && lo.shown && lo.full && io.n == 1 && io.ok45 && btnOk && reachOk &&
        (c.id == 'CFM' ? lo.brk == 0 : lo.sem && lo.vis) && (c.id != 'TST' || lo.brk == 0);
    okBefore = both && w.old == 1 && w.neu == 0 && (c.id != 'XFR' || rule == 'plain');
    okStrict = both && w.old == 0 && w.neu == 1 && (c.id != 'XFR' || (rule == 'kw' && lo.brk == 0));
    raw = '${raw}top $ftp line $lo an $an rule $rule ink $io words $w fills $fo want ${want.length}';
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // ⑤ 성공 · 실패 공통 정리 — 화면을 내리고 토스트 2초 타이머 · 열림 애니메이션이 끝날 시간을 준다.
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
  _out('R599 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D599 $tok att fw n=$nFw');
  _out('D599 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  if (_before) {
    chk('before 대상 = 지금 A(원문 글 그대로 · 전문 · 대비 ≥ 4.5 · 옛 호칭 1 · 새 0 / TST 끊김 0 · 이름 · 보임 / XFR plain 규칙 · 이름 · 보임 / '
        'CFM 끊김 0 · 이름 원문 · 연속 도달 · 끝 문장 · 단추 brand · 48 · hit)', okBefore, raw);
  } else {
    chk('strict 대상 = 후보(원문 글 그대로 · 전문 · 대비 ≥ 4.5 · 옛 호칭 0 · 새 1 / TST 끊김 0 · 이름 · 보임 / XFR kw 규칙 · 끊김 0 · 이름 · 보임 / '
        'CFM 끊김 0 · 이름 원문 · 연속 도달 · 끝 문장 · 단추 brand · 48 · hit)', okStrict, raw);
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
    await _loadFonts();
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S599PG-${v.id}-${c.id} 급여 지급 현황 g1 — 화면 안내 호칭 근무자 · 시트 부제 낱말 줄바꿈 · 확인창 끝까지 도달(토스트 · 이체자료 시트 · 중간정산 확인창)', (t) async {
        final tok = 'S599PG-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _caseOf(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
