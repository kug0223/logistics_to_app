// ignore_for_file: depend_on_referenced_packages
// [DU596b · 파일 셀 · 표시만] 결근 짝 다른 파일 2 — 판정177 §6 :60 · 판정139 §3 :44 PP-STATUS-PAIR(명시 결근 결과 = errorBg/errorDark · 노쇼와 같은 짝).
//   ① 출퇴근 화면(lib/screens/user/attendance_check_screen.dart) 확정 결근 배너의 면/선/아이콘/글 warning 짝 → error 짝(노쇼 배너와 같은 네 값).
//   ② 지급 상태(lib/utils/worker_wage_status.dart) absent 색 warningDark → errorDark — 소비 화면 = 수입 현황 목록 행 · 급여 상세 지급 상태 배지.
//   before = 지금 A(attendance_check_screen 676f3105 · worker_wage_status 2848152f) 기록 · strict = 후보(cand/ · mkcell 이 SHA 대조).
//   대조(두 모드 같음): 노쇼 배너 · 노쇼 행 = error 짝 · 결근+이체 완료 행 = '이체 처리 완료' successDark(이체 완료 우선) · 급여 상세 '지급 예정일' 줄 0.
//   하네스 = 블록 재사용(prep/mk_test.py 가 원본 fullSHA · 블록 sha12 단언): DU595b suite(7e30c11e · TB/TA 공개 9 success · 판정177 §5 수용) —
//     가짜 Firebase · 글꼴 · max 판 _fullShown · _textObs · _area · _lineCount · 보기 W/B/N · _halt · env 줄 · _DSeen · _txt · _bringBuilt · _semOf ·
//     _textLine · 색 도우미 · _fills · _inkOf · _iconInk.
//   새로 쓴 것: 이 머리 · 사례 3(CHK · INC · WAGE) · 글 상수 · 근로자 대역(_P = attendance_shift_ended_lock_test · worker_wage_date_status_test 와 같은 값) ·
//     세 화면 픽스처(읽기 경계 · 고정 시계) · 배너 상자 선 _banOf · 사례 본문 _caseOf · main.
//   누르는 것 0(ensureVisible · _bringBuilt 의 scrollUntilVisible 만). 쓰기 · CF 0.
//   기본 skip — TB before/du596bap-tb/DU_BEFORE_OBSERVE=596 · TA after/du596bap-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show BoxHeightStyle;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/attendance_check_reads.dart';
import 'package:ALfit/screens/user/attendance_check_screen.dart';
import 'package:ALfit/screens/user/income_detail_reads.dart';
import 'package:ALfit/screens/user/income_detail_screen.dart';
import 'package:ALfit/screens/user/wage_detail_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
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

/// [DU596b] 사례 — CHK = 출퇴근 화면(오늘 확정 2건: 명시 결근 a1 · 노쇼 a2 — 배너 2 · 결근 카드가 위) · INC = 수입 현황 2026-10 목록(결근 a1 · 노쇼 a2 ·
///   결근+이체 완료 a3) · WAGE = 급여 상세(명시 결근 · 급여 확정 0원 · 지급 예정일 값 있음). 장수 = 첫 화면 + 대상(CHK 는 노쇼 배너 한 장 더).
const _cases = <({String id, int shots})>[(id: 'CHK', shots: 3), (id: 'INC', shots: 2), (id: 'WAGE', shots: 2)];

/// [DU596b] 이 셀이 보는 글 — mkcell 이 base/후보 원문과 대조한다(두 모드 같은 글 · 색만 바뀐다).
const _kAbsent = '결근 처리됨';
const _kNoShow = '노쇼 처리됨';
const _kXfer = '이체 처리 완료';
const _kDue = '지급 예정일';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '596';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du596bap-tb' && _env['DU_BEFORE_OBSERVE'] == '596') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du596bap-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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

// [DU596b] 아래 측정 도우미는 DU595b suite(7e30c11e)에서 바이트 그대로 옮겼다 — :229–355(_txt · _bringBuilt · _semOf · _TO · _textLine — ensureVisible 대상 = 잰 대상 ·
//   _lum · _contrast · _hex · _bgOf · _FillObs · _fills · _InkObs · _inkOf). 그 원본도 DU592b(e415704a) :758–886 의 바이트 사본이다.

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

/// [DU595b suite :424 꼴 · DU596b 재사용] 아이콘 칠 — [f] 의 Icon 글리프 색 · 그 뒤 실제 면(_bgOf — 가장 가까운 칠한 조상) · 대비(비글자 3:1 기준). 잰 즉시 값으로 굳힌다.
typedef _IconObs = ({int n, String fill, String glyph, String cr, bool ok3});

_IconObs _iconInk(Finder f) {
  final es = f.evaluate().toList();
  if (es.length != 1) return (n: es.length, fill: '-', glyph: '-', cr: '0.00', ok3: false);
  final Color? g = (es.first.widget as Icon).color;
  final bg = _bgOf(es.first);
  final cr = g == null ? 0.0 : _contrast(g, bg);
  return (n: 1, fill: _hex(bg), glyph: g == null ? '-' : _hex(g), cr: cr.toStringAsFixed(2), ok3: cr >= 3.0);
}

// ───────────── [DU596b] 새로 쓴 부분 — 근로자 대역 · 세 화면 픽스처 · 배너 상자 선 · 사례 본문 ─────────────

/// [DU596b] 근로자 — attendance_shift_ended_lock_test · worker_wage_date_status_test 의 _P 와 같은 값(출퇴근 · 수입 화면이 읽는 uid · 서버 읽기 0).
class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시'),
        accountStatus: 'active',
      );
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
}

/// [DU596b] 출퇴근 고정 시계 — KST 2026-10-13 11:30(DU595b ABS · user_home_attendance_cta_test HC-9 와 같은 시각). 실행 시각 무관(A7).
final DateTime _now = DateTime.utc(2026, 10, 13, 11, 30).subtract(const Duration(hours: 9));

/// KST 달력일 2026-[m]-[d] 의 KST 자정 instant(기기 local) — worker_wage_date_status_test _kstMidnight 와 같은 꼴(저장소 workDate 관례).
DateTime _kstDay(int m, int d) => DateTime.utc(2026, m, d - 1, 15).toLocal();

/// [DU596b] 확정 단기 근무(10:00–11:00 · 시급) — 출퇴근 · 수입 · 급여 상세 세 화면이 같은 꼴을 읽는다.
ApplicationModel _app(String id, int day) => ApplicationModel(
      id: id,
      toId: 'to_$id',
      uid: 'u1',
      businessId: 'biz1',
      businessName: '골든패스 사업장',
      toTitle: '당일 QA',
      selectedWorkType: 'QA 분류',
      startTime: '10:00',
      endTime: '11:00',
      workDate: _kstDay(10, day),
      status: AppStatus.confirmed,
      appliedAt: _kstDay(10, 1),
      wage: 12000,
      wageType: 'hourly',
    );

/// [DU596b] 근태 — 명시 상태 [status](결근 · 노쇼) · 급여 단계 [wageStatus] · 0원 · 지급 예정일 [due](급여 상세 사례만).
AttendanceModel _att(String appId, int day, {required String status, required String wageStatus, DateTime? due}) => AttendanceModel(
      id: '${appId}_att',
      applicationId: appId,
      userId: 'u1',
      businessId: 'biz1',
      businessName: '골든패스 사업장',
      workDate: _kstDay(10, day),
      workType: 'QA 분류',
      status: status,
      wageStatus: wageStatus,
      adminConfirmed: true,
      finalWage: 0,
      paymentDueDate: due,
      createdAt: _kstDay(10, day),
    );

/// [DU596b] 출퇴근 읽기 경계 — 오늘 확정 2건(a1 명시 결근 · a2 노쇼) · 근태 = 지원서 id 로 · 계약 0(배너 갈래는 계약을 보지 않는다 · 쓰기 0).
AttendanceCheckReads _chkReads() {
  final atts = <String, AttendanceModel>{
    'a1': _att('a1', 13, status: AttendanceModel.statusAbsent, wageStatus: AttendanceModel.wagePending),
    'a2': _att('a2', 13, status: AttendanceModel.statusNoShow, wageStatus: AttendanceModel.wagePending),
  };
  return AttendanceCheckReads(
    myApplications: (uid) async => [_app('a1', 13), _app('a2', 13)],
    todayAttendance: ({required String userId, required String applicationId}) async => atts[applicationId],
    myContracts: (uid) async => const <EmploymentContractModel>[],
  );
}

/// [DU596b] 수입 현황 2026-10 읽기 경계 — a1 10/13 명시 결근(급여 확정 0원) · a2 10/14 노쇼(대조) · a3 10/15 결근 + 이체 완료(이체 완료 우선 분기 대조).
IncomeDetailReads _incReads() => IncomeDetailReads(
      myApplications: (uid) async => [_app('a1', 13), _app('a2', 14), _app('a3', 15)],
      myMonthlyAttendances: ({required String userId, required int year, required int month}) async => year == 2026 && month == 10
          ? [
              _att('a1', 13, status: AttendanceModel.statusAbsent, wageStatus: AttendanceModel.wageConfirmed),
              _att('a2', 14, status: AttendanceModel.statusNoShow, wageStatus: AttendanceModel.wageConfirmed),
              _att('a3', 15, status: AttendanceModel.statusAbsent, wageStatus: AttendanceModel.wageTransferred),
            ]
          : const <AttendanceModel>[],
    );

/// [DU596b] 급여 상세 근태 — 명시 결근 · 급여 확정 · 지급 예정일 값 있음(10/18) → 지급 상태 배지 '결근 처리됨' · '지급 예정일' 줄 0(showsDueDate 갈래 그대로).
AttendanceModel _wageAtt() =>
    _att('a1', 13, status: AttendanceModel.statusAbsent, wageStatus: AttendanceModel.wageConfirmed, due: DateTime.utc(2026, 10, 18).toLocal());

/// [DU596b] 배너 상자 — 테두리 있는 BoxDecoration 을 가진 Container(_buildNoShowBanner 의 그릇 · 근무 카드는 Card shape 라 들지 않는다).
bool _bannerBox(Widget w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null;

typedef _BanObs = ({int n, String fg, String face, String line, String icon, String cr, String icr, bool ok45, bool pair, bool warn});

/// [DU596b] 배너 하나 — [tf](_textLine 이 ensureVisible 하고 잰 **같은 Finder** · 점검표 A1)의 글 칠(_inkOf = 글자색 · 그 글 뒤 면) ·
///   그 글에서 가장 가까운 배너 상자의 선 색(Border.top) · 상자 안 Icons.block 칠(_iconInk = 글리프 · 뒤 면) · 대비.
///   pair = 면/선/아이콘/글 = errorBg/errorLight/errorDark/errorDark · warn = warningBg/warningLight/warningDark/warningDark. 잰 즉시 값으로 굳힌다.
_BanObs _banOf(Finder tf) {
  final io = _inkOf(tf);
  final boxes = find.ancestor(of: tf, matching: find.byWidgetPredicate(_bannerBox, skipOffstage: false)).evaluate().toList();
  if (io.n != 1 || boxes.isEmpty) {
    return (n: 0, fg: io.fg, face: io.bg, line: '-', icon: '-', cr: io.cr, icr: '0.00', ok45: false, pair: false, warn: false);
  }
  final deco = (boxes.first.widget as Container).decoration as BoxDecoration;
  final BoxBorder? bb = deco.border;
  final Color? lc = bb is Border ? bb.top.color : null;
  final boxF = find.byElementPredicate((x) => identical(x, boxes.first), skipOffstage: false);
  final ic = _iconInk(find.descendant(of: boxF, matching: find.byIcon(Icons.block, skipOffstage: false), skipOffstage: false));
  final line = lc == null ? '-' : _hex(lc);
  final pair = io.fg == _hex(AppColors.errorDark) && io.bg == _hex(AppColors.errorBg) && line == _hex(AppColors.errorLight) &&
      ic.glyph == _hex(AppColors.errorDark) && ic.fill == _hex(AppColors.errorBg);
  final warn = io.fg == _hex(AppColors.warningDark) && io.bg == _hex(AppColors.warningBg) && line == _hex(AppColors.warningLight) &&
      ic.glyph == _hex(AppColors.warningDark) && ic.fill == _hex(AppColors.warningBg);
  return (n: ic.n, fg: io.fg, face: io.bg, line: line, icon: ic.glyph, cr: io.cr, icr: ic.cr, ok45: io.ok45, pair: pair, warn: warn);
}

/// [DU596b] 사례 — 화면을 그리고(누르기 0) ① 첫 화면 채움 단추(A8 · 기록만) · 1top ② 대상 글: _bringBuilt(지연 목록 대비 · A4) →
///   _textLine(ensureVisible 대상 = 잰 대상 · A1) · 같은 Finder 의 칠(_inkOf · _banOf) · 화면 채움 단추(A8) · 대상이 보이게 맞춰 2장째(CHK 는 노쇼 배너 3장째).
Future<void> _caseOf(WidgetTester t, _V v, ({String id, int shots}) c, String tok) async {
  final prevOnError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = prevOnError);
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D596 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
    final Widget screenW = c.id == 'CHK'
        ? AttendanceCheckScreen(reads: _chkReads(), clock: () => _now)
        : c.id == 'INC'
            ? IncomeDetailScreen(initialYear: 2026, initialMonth: 10, reads: _incReads())
            : WageDetailScreen(application: _app('a1', 13), attendance: _wageAtt());
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.workerTheme,
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
          home: screenW,
        ),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final host = c.id == 'CHK'
        ? find.byType(AttendanceCheckScreen)
        : c.id == 'INC'
            ? find.byType(IncomeDetailScreen)
            : find.byType(WageDetailScreen);
    final nHost = host.evaluate().length;
    if (nHost != 1) throw StateError('화면 $nHost');
    Future<void> shot(String id, String state) async {
      _out('D596 $tok shot $id ovf=${seen.overflows.length}');
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
    _out('D596 $tok att ftop n=${ftp.n} brand=${ftp.brand} err=${ftp.err} none=${ftp.none} other=${ftp.other} list=${ftp.list}');
    await shot('1top', 'screen-top');
    // ② 대상 — 지연 목록이면 먼저 짓고(_bringBuilt) · 같은 Finder 를 ensureVisible 해 잰다(_textLine) · 그 Finder 의 칠(_inkOf · _banOf).
    if (c.id == 'CHK') {
      await _bringBuilt(t, host, _kAbsent);
      final tf = _txt(host, _kAbsent, onstage: false);
      final lo = await _textLine(t, tf, _kAbsent, screen);
      _out('D596 $tok att al n=${lo.n} shown=${lo.shown} sem=${lo.sem} full=${lo.full} ell0=${lo.ell0} brk=${lo.brk} lines=${lo.lines} vis=${lo.vis}');
      final ab = _banOf(tf);
      _out('D596 $tok att ab n=${ab.n} fg=${ab.fg} face=${ab.face} line=${ab.line} icon=${ab.icon} cr=${ab.cr} icr=${ab.icr} ok45=${ab.ok45} pair=${ab.pair} warn=${ab.warn}');
      final fo = _fills(t);
      _out('D596 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
      final abox = find.ancestor(of: tf, matching: find.byWidgetPredicate(_bannerBox, skipOffstage: false));
      await t.ensureVisible(abox.evaluate().isEmpty ? tf : abox.first);
      await settle();
      await shot('2abs', 'absent-banner');
      // 노쇼 배너(대조 · 두 모드 같은 error 짝) — 둘째 카드라 지연 목록 대비 뒤 같은 잣대로 잰다.
      await _bringBuilt(t, host, _kNoShow);
      final nf = _txt(host, _kNoShow, onstage: false);
      final ln = await _textLine(t, nf, _kNoShow, screen);
      _out('D596 $tok att nl n=${ln.n} shown=${ln.shown} sem=${ln.sem} full=${ln.full} ell0=${ln.ell0} brk=${ln.brk} lines=${ln.lines} vis=${ln.vis}');
      final nb = _banOf(nf);
      _out('D596 $tok att nb n=${nb.n} fg=${nb.fg} face=${nb.face} line=${nb.line} icon=${nb.icon} cr=${nb.cr} icr=${nb.icr} ok45=${nb.ok45} pair=${nb.pair} warn=${nb.warn}');
      final nbox = find.ancestor(of: nf, matching: find.byWidgetPredicate(_bannerBox, skipOffstage: false));
      await t.ensureVisible(nbox.evaluate().isEmpty ? nf : nbox.first);
      await settle();
      await shot('3ns', 'noshow-banner');
      okBefore = lo.n == 1 && ab.n == 1 && ab.warn && ln.n == 1 && nb.n == 1 && nb.pair;
      okStrict = lo.n == 1 && lo.shown && lo.full && lo.vis && lo.brk == 0 && ab.n == 1 && ab.pair && ab.ok45 && ln.n == 1 && nb.n == 1 && nb.pair;
      raw = 'top $ftp al $lo ab $ab fills $fo nl $ln nb $nb';
    } else if (c.id == 'INC') {
      await _bringBuilt(t, host, _kAbsent);
      final tf = _txt(host, _kAbsent, onstage: false);
      final lo = await _textLine(t, tf, _kAbsent, screen);
      _out('D596 $tok att il n=${lo.n} shown=${lo.shown} sem=${lo.sem} full=${lo.full} ell0=${lo.ell0} brk=${lo.brk} lines=${lo.lines} vis=${lo.vis}');
      final io = _inkOf(tf);
      final dark = io.fg == _hex(AppColors.errorDark);
      final warn = io.fg == _hex(AppColors.warningDark);
      _out('D596 $tok att ic n=${io.n} fg=${io.fg} bg=${io.bg} cr=${io.cr} ok45=${io.ok45} dark=$dark warn=$warn');
      // 대조 — 노쇼 행(errorDark 그대로) · 결근 + 이체 완료 행('이체 처리 완료' successDark — 이체 완료 우선 분기 그대로).
      await _bringBuilt(t, host, _kNoShow);
      final ni = _inkOf(_txt(host, _kNoShow, onstage: false));
      _out('D596 $tok att in n=${ni.n} fg=${ni.fg} bg=${ni.bg} cr=${ni.cr}');
      await _bringBuilt(t, host, _kXfer);
      final xi = _inkOf(_txt(host, _kXfer, onstage: false));
      _out('D596 $tok att ix n=${xi.n} fg=${xi.fg} bg=${xi.bg} cr=${xi.cr}');
      final keep = ni.n == 1 && ni.fg == _hex(AppColors.errorDark) && xi.n == 1 && xi.fg == _hex(AppColors.successDark);
      okBefore = lo.n == 1 && io.n == 1 && warn && keep;
      okStrict = lo.n == 1 && lo.shown && lo.full && lo.vis && lo.brk == 0 && io.n == 1 && dark && keep;
      final fo = _fills(t);
      _out('D596 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
      final rowF = find.ancestor(of: tf, matching: find.byType(InkWell));
      await t.ensureVisible(rowF.evaluate().isEmpty ? tf : rowF.first);
      await settle();
      await shot('2row', 'absent-row');
      raw = 'top $ftp il $lo ic $io in $ni ix $xi fills $fo';
    } else {
      await _bringBuilt(t, host, _kAbsent);
      final tf = _txt(host, _kAbsent, onstage: false);
      final lo = await _textLine(t, tf, _kAbsent, screen);
      _out('D596 $tok att wl n=${lo.n} shown=${lo.shown} sem=${lo.sem} full=${lo.full} ell0=${lo.ell0} brk=${lo.brk} lines=${lo.lines} vis=${lo.vis}');
      final io = _inkOf(tf);
      final dark = io.fg == _hex(AppColors.errorDark);
      final warn = io.fg == _hex(AppColors.warningDark);
      _out('D596 $tok att wc n=${io.n} fg=${io.fg} bg=${io.bg} cr=${io.cr} ok45=${io.ok45} dark=$dark warn=$warn');
      // 결근은 지급 예정일을 말하지 않는다(showsDueDate 갈래 그대로 · 예정일 값이 있어도 줄 0).
      final nDue = _txt(host, _kDue, onstage: false).evaluate().length;
      _out('D596 $tok att wd n=$nDue');
      okBefore = lo.n == 1 && io.n == 1 && warn && nDue == 0;
      okStrict = lo.n == 1 && lo.shown && lo.full && lo.vis && lo.brk == 0 && io.n == 1 && dark && nDue == 0;
      final fo = _fills(t);
      _out('D596 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
      await t.ensureVisible(tf);
      await settle();
      await shot('2badge', 'absent-badge');
      raw = 'top $ftp wl $lo wc $io wd $nDue fills $fo';
    }
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // ③ 성공 · 실패 공통 정리 — 화면을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다.
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
  _out('R596 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D596 $tok att fw n=$nFw');
  _out('D596 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  if (_before) {
    chk('before 대상 = 지금 A(CHK 결근 배너 warning 짝 · 노쇼 배너 error 짝 / INC 결근 행 warningDark · 노쇼 errorDark · 결근+이체 완료 successDark / '
        'WAGE 결근 배지 warningDark · 지급 예정일 줄 0)', okBefore, raw);
  } else {
    chk('strict 대상 = 후보(CHK 결근 배너 error 짝 · 대비 ≥ 4.5 · 전문 · 보임 · 노쇼 배너 그대로 / INC 결근 행 errorDark · 노쇼 · 이체 완료 그대로 / '
        'WAGE 결근 배지 errorDark · 지급 예정일 줄 0)', okStrict, raw);
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
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    await _loadFonts();
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S596AP-${v.id}-${c.id} 결근 짝 — 출퇴근 배너 · 지급 상태 글 errorDark(노쇼와 같은 짝)', (t) async {
        final tok = 'S596AP-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _caseOf(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
