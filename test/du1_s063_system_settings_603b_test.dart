// ignore_for_file: depend_on_referenced_packages
// [DU603b · 파일 셀 · 표시만] DU-S063 시스템 설정(슈퍼관리자 · lib/screens/super_admin/system_settings_screen.dart) 결정 미이행 1행 —
//   장부 147 · 판정114 §6 :110 'S063 비활성 메뉴 — 준비 중 설명/접근성 비활성 상태·화살표 처리 후보이며 기능 활성화0'(방향만 · J-SOON 보수안):
//     준비 중 행 '알림 설정' 의 꺾쇠 → '준비 중' 표시(슈퍼관리자 홈 메뉴 행 DU240 과 같은 꼴) · ListTile enabled 거짓(읽기 도구 '사용 불가') · 누르기 0 그대로.
//   before = 지금 A(system_settings_screen 04296b88 = DU502 후보) 기록 · strict = 후보(cand/ · mkcell 이 SHA 대조).
//   하네스 = 블록 재사용(prep/mk_test.py 가 원본 fullSHA · 블록 sha12 · 경계 줄 단언): DU595b suite(7e30c11e · 판정177 §5 수용) —
//     가짜 Firebase · 글꼴 · max 판 _fullShown · _textObs · _area · _lineCount · 보기 W/B/N · _halt · env 줄 · _DSeen · _txt · _bringBuilt · _semOf ·
//     _textLine · 색 도우미 · _fills · _inkOf / DU507 r3 suite(be8bc231 · DONE 5/5) — _Super(슈퍼관리자 대역).
//   새로 쓴 것: 이 머리 · 사례 1(MENU) · 글 상수 · 행 관측 _rowOf(켜짐 · 누름 · 꺾쇠 · 읽기 도구 상태) · 사례 본문 _caseOf · main.
//   누르는 것 0(ensureVisible · _bringBuilt 의 scrollUntilVisible 만) — 쓰기 · 토스트 · 이동 0.
//   기본 skip — TB before/du603bss-tb/DU_BEFORE_OBSERVE=603 · TA after/du603bss-ta/없음.
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
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/system_settings_screen.dart';
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

/// [DU603b] 사례 — MENU = 시스템 설정 첫 화면(1top) → 활성 기준 행 '최저시급 설정' → 준비 중 행 '알림 설정'(제목 · 부제 · '준비 중' 표시 · 행 · 2soon).
const _cases = <({String id, int shots})>[(id: 'MENU', shots: 2)];

/// [DU603b] 이 셀이 보는 글 — mkcell 이 base/후보 원문과 대조한다(제목 · 부제 · 기준 행은 두 모드 같음 · '준비 중' 표시는 strict 만).
const _kRef = '최저시급 설정';
const _kTitle = '알림 설정';
const _kSub = '푸시 알림 규칙';
const _kSoon = '준비 중';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '603';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du603bss-tb' && _env['DU_BEFORE_OBSERVE'] == '603') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du603bss-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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

// [DU603b] 아래 측정 도우미는 DU595b suite(7e30c11e · 판정177 §5 수용)에서 바이트 그대로 옮겼다 — :229–355(_txt · _bringBuilt · _semOf · _TO · _textLine —
//   ensureVisible 대상 = 잰 대상 · _lum · _contrast · _hex · _bgOf · _FillObs · _fills · _InkObs · _inkOf). DU597b(DONE 5/5)도 같은 범위를 썼다.
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

// [DU603b] 슈퍼관리자 대역 — DU507 r3 suite(be8bc231 · run DONE 5/5 16:35:11 · 판정119 §1 수용)의 :43–59 바이트 그대로(_Super · DU502 suite 의 대역과 같은 글).
/// RR57 과 같은 슈퍼관리자 대역.
class _Super extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'sa1', username: 'sa1', name: '운영자', email: 'sa@alfit.local',
        role: UserRole.SUPER_ADMIN, createdAt: DateTime(2026, 1, 1));
  @override
  bool get isSuperAdmin => true;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
}

// ───────────── [DU603b] 새로 쓴 부분 — 행 관측 · 사례 본문 ─────────────

typedef _RowObs = ({int n, bool en, bool tap, int chev, int sn, bool sd, bool se, double h});

/// [DU603b] 메뉴 행 하나 — [tf](_textLine 이 ensureVisible 하고 잰 **같은 Finder** · A1)를 품은 ListTile 의 켜짐(enabled) · 누름(onTap ≠ null) · 꺾쇠 수 ·
///   읽기 도구 마디(라벨 평문에 [title] 을 담은 마디 수 · 그중 '사용 불가'(hasEnabledState · !isEnabled) 마디 있음 · '켜짐' 마디 있음) · 행 높이. 잰 즉시 값으로 굳힌다.
_RowObs _rowOf(WidgetTester t, Finder tf, String title) {
  final rowF = find.ancestor(of: tf, matching: find.byType(ListTile));
  final n = rowF.evaluate().length;
  if (n != 1) return (n: n, en: false, tap: false, chev: 0, sn: 0, sd: false, se: false, h: 0.0);
  final w = t.widget<ListTile>(rowF);
  final chev = find.descendant(of: rowF, matching: find.byIcon(Icons.chevron_right), skipOffstage: false).evaluate().length;
  final nodes = find.semantics.byPredicate((s) => TextLayout.plain(s.label).contains(title)).evaluate().toList();
  final sd = nodes.any((s) => containsSemantics(hasEnabledState: true, isEnabled: false).matches(s, <dynamic, dynamic>{}));
  final se = nodes.any((s) => containsSemantics(hasEnabledState: true, isEnabled: true).matches(s, <dynamic, dynamic>{}));
  return (n: n, en: w.enabled, tap: w.onTap != null, chev: chev, sn: nodes.length, sd: sd, se: se, h: t.getSize(rowF).height);
}

/// [DU603b] 사례 — 시스템 설정(슈퍼관리자 대역)을 그린다 → ① 첫 화면 채움 단추(A8) · 1top ② 활성 기준 행 '최저시급 설정'(지어 넣고 · 같은 글로 행)
///   ③ 준비 중 행 '알림 설정' — 제목 · 부제 · '준비 중' 표시(ensureVisible = 잰 대상 · 칠/대비) · 행(켜짐 · 누름 · 꺾쇠 · 읽기 도구) · 채움 단추 · 2soon.
Future<void> _caseOf(WidgetTester t, _V v, ({String id, int shots}) c, String tok) async {
  final prevOnError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = prevOnError);
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D603 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
      child: ChangeNotifierProvider<UserProvider>(
        create: (_) => _Super(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.superAdminTheme,
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
          home: const SystemSettingsScreen(),
        ),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final host = find.byType(SystemSettingsScreen);
    final nHost = host.evaluate().length;
    if (nHost != 1) throw StateError('시스템 설정 화면 $nHost');
    Future<void> shot(String id, String state) async {
      _out('D603 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    final screen = Offset.zero & Size(v.w, v.h);
    // ① 첫 화면 — 채움 단추(A8 · 기록만) · 1top.
    final f0 = _fills(t);
    _out('D603 $tok att f0 n=${f0.n} brand=${f0.brand} err=${f0.err} none=${f0.none} other=${f0.other} list=${f0.list}');
    await shot('1top', 'system-menu-top');
    // ② 활성 기준 행 — 지연 목록이면 먼저 짓고(_bringBuilt) · ensureVisible 로 넣은 같은 글(_textLine)의 행(_rowOf)을 읽는다(후보가 바꾸지 않는 갈래).
    await _bringBuilt(t, host, _kRef);
    final refF = _txt(host, _kRef, onstage: false);
    final ro = await _textLine(t, refF, _kRef, screen);
    final rf = _rowOf(t, refF, _kRef);
    _out('D603 $tok att ok n=${rf.n} en=${rf.en} tap=${rf.tap} chev=${rf.chev} sn=${rf.sn} sd=${rf.sd} se=${rf.se}');
    // ③ 준비 중 행 — 제목 · 부제를 지어 넣고(_bringBuilt — 같은 ListTile 이라 '준비 중' 표시도 함께 지어진다 · before 에는 그 글이 없어 짓기 대상으로 쓰지 않는다)
    //   ensureVisible = 잰 대상(_textLine · A1) · 칠/대비(_inkOf 같은 Finder) → 그 행(_rowOf 같은 제목 Finder).
    await _bringBuilt(t, host, _kTitle);
    final dtF = _txt(host, _kTitle, onstage: false);
    final dt = await _textLine(t, dtF, _kTitle, screen);
    final di = _inkOf(dtF);
    _out('D603 $tok att dt n=${dt.n} shown=${dt.shown} sem=${dt.sem} full=${dt.full} brk=${dt.brk} lines=${dt.lines} vis=${dt.vis} fg=${di.fg} c45=${di.ok45}');
    await _bringBuilt(t, host, _kSub);
    final dsF = _txt(host, _kSub, onstage: false);
    final ds = await _textLine(t, dsF, _kSub, screen);
    final si = _inkOf(dsF);
    _out('D603 $tok att ds n=${ds.n} shown=${ds.shown} sem=${ds.sem} full=${ds.full} brk=${ds.brk} lines=${ds.lines} vis=${ds.vis} fg=${si.fg} c45=${si.ok45}');
    final rowF = find.ancestor(of: dtF, matching: find.byType(ListTile));
    final snF = _txt(rowF, _kSoon, onstage: false);
    final sn = await _textLine(t, snF, _kSoon, screen);
    final ni = _inkOf(snF);
    _out('D603 $tok att sn n=${sn.n} shown=${sn.shown} full=${sn.full} brk=${sn.brk} lines=${sn.lines} vis=${sn.vis} fg=${ni.fg} bg=${ni.bg} c45=${ni.ok45}');
    final tl = _rowOf(t, dtF, _kTitle);
    _out('D603 $tok att tl n=${tl.n} en=${tl.en} tap=${tl.tap} chev=${tl.chev} sn=${tl.sn} sd=${tl.sd} se=${tl.se} h=${tl.h.toStringAsFixed(1)}');
    final fs = _fills(t);
    _out('D603 $tok att fs n=${fs.n} brand=${fs.brand} err=${fs.err} none=${fs.none} other=${fs.other} list=${fs.list}');
    await shot('2soon', 'system-menu-soon-row');
    final same = rf.n == 1 && rf.en && rf.tap && rf.chev == 1 && !rf.sd && rf.se &&
        dt.n == 1 && dt.shown && dt.full && dt.brk == 0 && dt.vis && di.fg == _hex(AppColors.textTertiary) && di.ok45 &&
        ds.n == 1 && ds.shown && ds.full && ds.brk == 0 && ds.vis && si.fg == _hex(AppColors.textSecondary) && si.ok45 &&
        tl.n == 1 && !tl.tap;
    okBefore = same && tl.en && tl.chev == 1 && !tl.sd && tl.se && sn.n == 0;
    okStrict = same && !tl.en && tl.chev == 0 && tl.sd && !tl.se && sn.n == 1 && sn.shown && sn.full && sn.brk == 0 && sn.vis &&
        ni.fg == _hex(AppColors.textSecondary) && ni.bg == _hex(AppColors.grey100) && ni.ok45;
    raw = 'f0 $f0 ref $ro $rf dt $dt $di ds $ds $si sn $sn $ni tl $tl fs $fs';
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // ④ 성공 · 실패 공통 정리 — 화면을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다.
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
  _out('R603 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D603 $tok att fw n=$nFw');
  _out('D603 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

  final f1 = failure;
  if (f1 != null) {
    _halt ??= '$tok ${f1.toString().split('\n').first}';
    Error.throwWithStackTrace(f1, failureSt ?? StackTrace.current);
  }
  if (_before) {
    chk('before 대상 = 지금 A(기준 행 켜짐 · 누름 · 꺾쇠 1 · 읽기 도구 켜짐 / 준비 중 행 제목 · 부제 전문 · 끊김 0 · 보임 · 칠 textTertiary/textSecondary ≥ 4.5 · '
        '누름 없음 · 꺾쇠 1 · 준비 중 표시 0 · ListTile 켜짐 · 읽기 도구 켜짐)', okBefore, raw);
  } else {
    chk('strict 대상 = 후보(기준 행 그대로 · 준비 중 행 제목 · 부제 그대로 · 누름 없음 · 꺾쇠 0 · 준비 중 표시 1(전문 · 끊김 0 · 보임 · textSecondary on grey100 ≥ 4.5) · '
        'ListTile 꺼짐 · 읽기 도구 사용 불가)', okStrict, raw);
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
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await _loadFonts();
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S603SS-${v.id}-${c.id} 시스템 설정 준비 중 행 — 표시 · 비활성 상태', (t) async {
        final tok = 'S603SS-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _caseOf(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
