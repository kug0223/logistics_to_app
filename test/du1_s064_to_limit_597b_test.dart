// ignore_for_file: depend_on_referenced_packages
// [DU597b · 파일 셀 · 표시만] DU-S064 공고 등록 개수 제한(lib/screens/super_admin/to_limit_settings_screen.dart) 결정 미이행 2행 —
//   장부 087 · 판정119 §6 :74 N119-1: 관리자별 '저장' 고정 높이 42 → 48(누르는 자리 ≥ 48) — 관리자 셋(값 있음 · 없음 · 있음) · 마지막 카드까지 실제 도달 ·
//     같은 단추 중심 hit · 켜짐 · 채움 brand · 단추 글 전문. 저장은 누르지 않는다(writer · CF 0).
//   장부 086 · 판정119 §6 :75 N119-2: 큰 글자(B 320@2.0) 탭 — 가로 스크롤(고른 탭 쪽으로 밀려 '전역 기본값' 이 반만 보임) → 고정 두 탭 · 낱말 단위 줄바꿈.
//     세 상태(첫 화면 · 오른쪽 고르기 · 왼쪽 되돌리기)마다 두 탭 이름 전문 · 화면 안 · 이름 중심 hit · 누르는 자리 ≥ 48 · 전환. 이름 축약 · 글자 축소 0.
//   before = 지금 A(to_limit_settings_screen 3664920c = DU507 r3 후보) 기록 · strict = 후보(cand/ · mkcell 이 SHA 대조).
//   하네스 = 블록 재사용(prep/mk_test.py 가 원본 fullSHA · 블록 sha12 · 경계 줄 단언): DU595b suite(7e30c11e · TB/TA 공개 9 success · 판정177 §5) —
//     가짜 Firebase · 글꼴 · max 판 _fullShown · _textObs · _area · _lineCount · 보기 W/B/N · _halt · env 줄 · _DSeen · _txt · _bringBuilt · _semOf ·
//     _textLine · 색 도우미 · _fills · _inkOf / DU581 r3 suite(3f4a404a · DONE 5/5) — _hitWithin / DU507 r3 suite(be8bc231 · DONE 5/5) — _Super.
//   새로 쓴 것: 이 머리 · 사례 2(TAB · SAVE) · 글 상수 · 읽기 경계(관리자 셋) · 탭 관측 _tabObs · 저장 관측 _cardBox/_saveObs · 사례 본문 _caseOf · main.
//   누르는 것 = 탭 이름 중심(tapAt · 잰 hit 와 같은 점)뿐 — 저장 0 · 쓰기 0.
//   기본 skip — TB before/du597btl-tb/DU_BEFORE_OBSERVE=597 · TA after/du597btl-ta/없음.
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
import 'package:ALfit/screens/super_admin/to_limit_reads.dart';
import 'package:ALfit/screens/super_admin/to_limit_settings_screen.dart';
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

/// [DU597b] 사례 — TAB = 첫 화면(전역 탭) → 오른쪽 탭 이름을 눌러 고르기 → 왼쪽 탭 이름을 눌러 되돌리기(세 상태마다 두 탭 이름 · 전환 · 한 장씩) ·
///   SAVE = 관리자별 탭 — 관리자 셋(값 있음 · 없음 · 있음)의 '저장' 누르는 자리 · 첫 카드 한 장 · 마지막 카드 도달 한 장(누르지 않음).
const _cases = <({String id, int shots})>[(id: 'TAB', shots: 3), (id: 'SAVE', shots: 2)];

/// [DU597b] 이 셀이 보는 글 — mkcell 이 base/후보 원문과 대조한다(두 모드 같은 글).
const _kTabL = '전역 기본값';
const _kTabR = '관리자별 한도';
const _kSave = '저장';
const _kGlobalHead = '한도는 한 관리자 계정이';
const _kAdminHead = '한도는 동시에 진행 중인 공고 수입니다';
const _kAdmins = ['박사장', '최사장', '이사장'];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '597';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du597btl-tb' && _env['DU_BEFORE_OBSERVE'] == '597') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du597btl-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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

// [DU597b] 아래 측정 도우미는 DU595b suite(7e30c11e · 판정177 §5 수용)에서 바이트 그대로 옮겼다 — :229–355(_txt · _bringBuilt · _semOf · _TO · _textLine —
//   ensureVisible 대상 = 잰 대상 · _lum · _contrast · _hex · _bgOf · _FillObs · _fills · _InkObs · _inkOf). 그 원본도 DU592b(e415704a) :758–886 의 바이트 사본이다.

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

// [DU597b] 누르는 자리 hit — DU581 r3 suite(3f4a404a · run DONE 5/5 19:35:21 · 슈퍼관리자 사용자 관리)의 :193–204 바이트 그대로(_hitWithin).

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

// [DU597b] 슈퍼관리자 대역 — DU507 r3 suite(be8bc231 · run DONE 5/5 16:35:11 · 판정119 §1 수용 · 같은 화면)의 :43–59 바이트 그대로(_Super).

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

// ───────────── [DU597b] 새로 쓴 부분 — 읽기 경계 · 탭 관측 · 저장 관측 · 사례 본문 ─────────────

/// [DU597b] 읽기 경계 — 전역 7 · 관리자 셋(박사장 개별 3 · 사업장 2 / 최사장 값 없음 = 전역 / 이사장 개별 5 · 마지막 카드).
///   TOL · DU507 r3 대역(_ok)에 셋째(마지막 카드 · 값 있음)를 더했다. 쓰기 경계(CF · Firestore set)는 부르지 않는다(저장을 누르지 않는다).
ToLimitReads _reads() => ToLimitReads(
      globalConfigRaw: () async => {'maxActiveTOPerBusiness': 7},
      businessAdminsRaw: () async => [
        {'uid': 'a1', 'name': '박사장', 'businessName': '강남 물류센터', 'managedBizCount': 2, 'maxActiveTOs': 3},
        {'uid': 'a2', 'name': '최사장', 'businessName': '성수 창고', 'managedBizCount': 1},
        {'uid': 'a3', 'name': '이사장', 'businessName': '평택 물류센터', 'managedBizCount': 1, 'maxActiveTOs': 5},
      ],
    );

typedef _TabObs = ({int n, bool shown, bool sem, bool full, bool ell0, int brk, int lines, bool vis, bool hit, bool r48, double h, String fg, String cr});

/// [DU597b · N119-2] 탭 이름 하나 — **그려진 그대로** 잰다(ensureVisible 0 · 가로 스크롤 탭이 밀린 상태를 숨기지 않는다).
///   글 = _textObs(max 판 _fullShown 그대로) · 줄 = _lineCount · 보임 = 화면 ∩ 조상 스크롤 칸 안 · hit = 이름 중심을 누르면 그 탭 InkWell(누르는 자리)
///   안이 맞는가 · r48 · h = 그 InkWell 크기 · 칠 = _inkOf(같은 Finder). n ≠ 1 이면 재지 않는다. 잰 즉시 값으로 굳힌다.
_TabObs _tabObs(WidgetTester t, Finder bar, String label, Rect screen) {
  final tf = _txt(bar, label, onstage: false);
  final n = tf.evaluate().length;
  if (n != 1) {
    return (n: n, shown: false, sem: false, full: false, ell0: false, brk: 0, lines: 0, vis: false, hit: false, r48: false, h: 0.0, fg: '-', cr: '0.00');
  }
  final o = _textObs(t, tf, label);
  final nLines = _lineCount(t.renderObject<RenderParagraph>(find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: true).first));
  final r = t.getRect(tf);
  final ink = find.ancestor(of: tf, matching: find.byType(InkWell)).first;
  final ri = t.getRect(ink);
  final io = _inkOf(tf);
  return (
    n: n,
    shown: o.shown,
    sem: _semOf(t.widget<Text>(tf)) == label,
    full: o.full,
    ell0: o.ell0,
    brk: o.brk,
    lines: nLines,
    vis: _inside(r, _area(tf, screen)),
    hit: _hitWithin(t, ink, r.center),
    r48: ri.width >= 48 - 0.01 && ri.height >= 48 - 0.01,
    h: ri.height,
    fg: io.fg,
    cr: io.cr,
  );
}

/// [DU597b · N119-1] 관리자 카드 — 테두리 있는 BoxDecoration 을 가진 Container(_buildAdminCard 의 그릇 · 위 안내 띠 · 배지는 테두리 0).
bool _cardBox(Widget w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null;

typedef _SaveObs = ({int n, bool filled, double fh, double h, double w, bool m48, bool vis, bool hit, bool on, String fill, bool lfull, int lbrk, bool lvis});

/// [DU597b · N119-1] 관리자 [name] 카드의 '저장' — 이름이 안 지어졌으면 짓고(_bringBuilt · 지연 목록 대비 A4) 그 카드 안 ElevatedButton 을
///   ensureVisible 한 뒤 **같은 단추**의 크기 · 화면 안 · 중심 hit · 켜짐(onPressed) · 채움을 잰다(A1 · 누르지 않음 · writer 0).
///   단추 글 '저장' 은 _textLine(ensureVisible 대상 = 잰 대상)으로 전문 · 낱말 안 끊김 · 보임. 입력칸 높이 · 값 있음은 같은 카드에서 기록.
Future<_SaveObs> _saveObs(WidgetTester t, Finder list, String name, Rect screen) async {
  await _bringBuilt(t, list, name);
  final nf = _txt(list, name, onstage: false);
  final cards = find.ancestor(of: nf, matching: find.byWidgetPredicate(_cardBox, skipOffstage: false));
  if (nf.evaluate().length != 1 || cards.evaluate().isEmpty) {
    return (n: 0, filled: false, fh: 0.0, h: 0.0, w: 0.0, m48: false, vis: false, hit: false, on: false, fill: '-', lfull: false, lbrk: 0, lvis: false);
  }
  final card = cards.first;
  final bf = find.descendant(of: card, matching: find.byType(ElevatedButton, skipOffstage: false), skipOffstage: false);
  final n = bf.evaluate().length;
  if (n != 1) {
    return (n: n, filled: false, fh: 0.0, h: 0.0, w: 0.0, m48: false, vis: false, hit: false, on: false, fill: '-', lfull: false, lbrk: 0, lvis: false);
  }
  final lo = await _textLine(t, _txt(card, _kSave, onstage: false), _kSave, screen);
  await t.ensureVisible(bf);
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final r = t.getRect(bf);
  final mats = find.descendant(of: bf, matching: find.byType(Material), skipOffstage: false).evaluate().toList();
  final Color? fc = mats.isEmpty ? null : (mats.first.widget as Material).color;
  final fieldF = find.descendant(of: card, matching: find.byType(InputDecorator, skipOffstage: false), skipOffstage: false);
  final tfF = find.descendant(of: card, matching: find.byType(TextField, skipOffstage: false), skipOffstage: false);
  final nField = fieldF.evaluate().length;
  final nTf = tfF.evaluate().length;
  return (
    n: n,
    filled: nTf == 1 && (t.widget<TextField>(tfF).controller?.text.isNotEmpty ?? false),
    fh: nField == 1 ? t.getSize(fieldF).height : 0.0,
    h: r.height,
    w: r.width,
    m48: r.width >= 48 - 0.01 && r.height >= 48 - 0.01,
    vis: _inside(r, _area(bf, screen)),
    hit: _hitWithin(t, bf, r.center),
    on: t.widget<ElevatedButton>(bf).onPressed != null,
    fill: fc == null ? '-' : _hex(fc),
    lfull: lo.n == 1 && lo.full,
    lbrk: lo.brk,
    lvis: lo.vis,
  );
}

/// [DU597b] 사례 — 화면을 그리고(누르는 것 = 탭 이름 중심뿐 · 저장 0)
///   TAB: ① 첫 화면 채움 단추(A8 · 기록만) · 두 탭 이름 · 전환 상태 · 1global ② 오른쪽 이름 중심을 눌러 고르기 · 두 이름 · 2admins ③ 왼쪽 이름 중심을 눌러 되돌리기 · 3back.
///   SAVE: 오른쪽 이름을 눌러 관리자별 탭 → 관리자 셋의 '저장'(_saveObs) · 첫 카드 1first · 마지막 카드 2last · 채움(A8 · 기록만).
Future<void> _caseOf(WidgetTester t, _V v, ({String id, int shots}) c, String tok) async {
  final prevOnError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = prevOnError);
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D597 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
    await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
      create: (_) => _Super(),
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.superAdminTheme,
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
          home: TOLimitSettingsScreen(reads: _reads()),
        ),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final host = find.byType(TOLimitSettingsScreen);
    final nHost = host.evaluate().length;
    if (nHost != 1) throw StateError('화면 $nHost');
    final bar = find.byType(TabBar);
    final nBar = bar.evaluate().length;
    if (nBar != 1) throw StateError('탭 바 $nBar');
    Future<void> shot(String id, String state) async {
      _out('D597 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    final screen = Offset.zero & Size(v.w, v.h);
    int tabIndex() => t.widget<TabBar>(bar).controller!.index;
    int headCount(String head) => find
        .descendant(
            of: host,
            matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '').startsWith(head)),
            skipOffstage: false)
        .evaluate()
        .length;
    // 탭 이름 중심을 누른다 — _tabObs 의 hit 와 같은 점(A1). 그 점이 그 탭 InkWell 에 맞지 않으면 누르지 않는다(전환 실패로 기록).
    Future<bool> tapName(String label) async {
      final nameF = _txt(bar, label, onstage: false);
      if (nameF.evaluate().length != 1) return false;
      final p = t.getRect(nameF).center;
      final inkF = find.ancestor(of: nameF, matching: find.byType(InkWell)).first;
      if (!_hitWithin(t, inkF, p)) return false;
      await t.tapAt(p);
      await settle();
      return true;
    }

    if (c.id == 'TAB') {
      // ① 첫 화면(전역 탭) — 채움 단추(A8 · 기록만) · 두 탭 이름(그려진 그대로) · 전환 상태(고른 탭 · 보이는 탭 본문 머리글 수).
      final fa = _fills(t);
      _out('D597 $tok att f0 n=${fa.n} brand=${fa.brand} err=${fa.err} none=${fa.none} other=${fa.other} list=${fa.list}');
      final l0 = _tabObs(t, bar, _kTabL, screen);
      _out('D597 $tok att l0 n=${l0.n} shown=${l0.shown} sem=${l0.sem} full=${l0.full} ell0=${l0.ell0} brk=${l0.brk} lines=${l0.lines} vis=${l0.vis} hit=${l0.hit} r48=${l0.r48} h=${l0.h.toStringAsFixed(1)} fg=${l0.fg} cr=${l0.cr}');
      final r0 = _tabObs(t, bar, _kTabR, screen);
      _out('D597 $tok att r0 n=${r0.n} shown=${r0.shown} sem=${r0.sem} full=${r0.full} ell0=${r0.ell0} brk=${r0.brk} lines=${r0.lines} vis=${r0.vis} hit=${r0.hit} r48=${r0.r48} h=${r0.h.toStringAsFixed(1)} fg=${r0.fg} cr=${r0.cr}');
      final w0 = (idx: tabIndex(), g: headCount(_kGlobalHead), a: headCount(_kAdminHead));
      _out('D597 $tok att w0 idx=${w0.idx} g=${w0.g} a=${w0.a}');
      await shot('1global', 'tab-global');
      // ② 오른쪽 이름 중심을 눌러 고른다.
      final p1 = await tapName(_kTabR);
      final l1 = _tabObs(t, bar, _kTabL, screen);
      _out('D597 $tok att l1 n=${l1.n} shown=${l1.shown} sem=${l1.sem} full=${l1.full} ell0=${l1.ell0} brk=${l1.brk} lines=${l1.lines} vis=${l1.vis} hit=${l1.hit} r48=${l1.r48} h=${l1.h.toStringAsFixed(1)} fg=${l1.fg} cr=${l1.cr}');
      final r1 = _tabObs(t, bar, _kTabR, screen);
      _out('D597 $tok att r1 n=${r1.n} shown=${r1.shown} sem=${r1.sem} full=${r1.full} ell0=${r1.ell0} brk=${r1.brk} lines=${r1.lines} vis=${r1.vis} hit=${r1.hit} r48=${r1.r48} h=${r1.h.toStringAsFixed(1)} fg=${r1.fg} cr=${r1.cr}');
      final w1 = (tap: p1, idx: tabIndex(), g: headCount(_kGlobalHead), a: headCount(_kAdminHead));
      _out('D597 $tok att w1 tap=${w1.tap} idx=${w1.idx} g=${w1.g} a=${w1.a}');
      await shot('2admins', 'tab-admins');
      // ③ 왼쪽 이름 중심을 눌러 되돌린다.
      final p2 = await tapName(_kTabL);
      final l2 = _tabObs(t, bar, _kTabL, screen);
      _out('D597 $tok att l2 n=${l2.n} shown=${l2.shown} sem=${l2.sem} full=${l2.full} ell0=${l2.ell0} brk=${l2.brk} lines=${l2.lines} vis=${l2.vis} hit=${l2.hit} r48=${l2.r48} h=${l2.h.toStringAsFixed(1)} fg=${l2.fg} cr=${l2.cr}');
      final r2 = _tabObs(t, bar, _kTabR, screen);
      _out('D597 $tok att r2 n=${r2.n} shown=${r2.shown} sem=${r2.sem} full=${r2.full} ell0=${r2.ell0} brk=${r2.brk} lines=${r2.lines} vis=${r2.vis} hit=${r2.hit} r48=${r2.r48} h=${r2.h.toStringAsFixed(1)} fg=${r2.fg} cr=${r2.cr}');
      final w2 = (tap: p2, idx: tabIndex(), g: headCount(_kGlobalHead), a: headCount(_kAdminHead));
      _out('D597 $tok att w2 tap=${w2.tap} idx=${w2.idx} g=${w2.g} a=${w2.a}');
      await shot('3back', 'tab-back');
      final names = [l0, r0, l1, r1, l2, r2];
      final allVis = names.every((o) => o.vis);
      final same = names.every((o) => o.n == 1 && o.shown && o.sem && o.full && o.brk == 0 && o.hit && o.r48) &&
          w0.idx == 0 && w0.g == 1 && w1.tap && w1.idx == 1 && w1.a == 1 && w2.tap && w2.idx == 0 && w2.g == 1;
      okBefore = same && (v.id == 'B' ? !allVis : allVis);
      okStrict = same && allVis;
      raw = 'f0 $fa l0 $l0 r0 $r0 w0 $w0 l1 $l1 r1 $r1 w1 $w1 l2 $l2 r2 $r2 w2 $w2';
    } else {
      // 오른쪽 이름 중심을 눌러 관리자별 탭으로(누르는 것 = 탭 이름뿐) — 목록 맨 위(첫 항목 = 안내 띠 · 스크롤 0)에서 머리글 수를 센다.
      final p1 = await tapName(_kTabR);
      final sw = (tap: p1, idx: tabIndex(), a: headCount(_kAdminHead));
      _out('D597 $tok att sw tap=${sw.tap} idx=${sw.idx} a=${sw.a}');
      final list = find.byType(ListView);
      final nList = list.evaluate().length;
      if (nList != 1) throw StateError('관리자 목록 $nList');
      final s1 = await _saveObs(t, list, _kAdmins[0], screen);
      _out('D597 $tok att s1 n=${s1.n} filled=${s1.filled} fh=${s1.fh.toStringAsFixed(1)} h=${s1.h.toStringAsFixed(1)} w=${s1.w.toStringAsFixed(1)} m48=${s1.m48} vis=${s1.vis} hit=${s1.hit} on=${s1.on} fill=${s1.fill} lfull=${s1.lfull} lbrk=${s1.lbrk} lvis=${s1.lvis}');
      await shot('1first', 'save-first');
      final s2 = await _saveObs(t, list, _kAdmins[1], screen);
      _out('D597 $tok att s2 n=${s2.n} filled=${s2.filled} fh=${s2.fh.toStringAsFixed(1)} h=${s2.h.toStringAsFixed(1)} w=${s2.w.toStringAsFixed(1)} m48=${s2.m48} vis=${s2.vis} hit=${s2.hit} on=${s2.on} fill=${s2.fill} lfull=${s2.lfull} lbrk=${s2.lbrk} lvis=${s2.lvis}');
      final s3 = await _saveObs(t, list, _kAdmins[2], screen);
      _out('D597 $tok att s3 n=${s3.n} filled=${s3.filled} fh=${s3.fh.toStringAsFixed(1)} h=${s3.h.toStringAsFixed(1)} w=${s3.w.toStringAsFixed(1)} m48=${s3.m48} vis=${s3.vis} hit=${s3.hit} on=${s3.on} fill=${s3.fill} lfull=${s3.lfull} lbrk=${s3.lbrk} lvis=${s3.lvis}');
      final fs = _fills(t);
      _out('D597 $tok att fs n=${fs.n} brand=${fs.brand} err=${fs.err} none=${fs.none} other=${fs.other} list=${fs.list}');
      await shot('2last', 'save-last');
      final saves = [s1, s2, s3];
      final same = sw.tap && sw.idx == 1 && sw.a == 1 && s1.filled && !s2.filled && s3.filled &&
          saves.every((s) => s.n == 1 && s.vis && s.hit && s.on && s.fill == _hex(AppColors.brand) && s.lfull && s.lbrk == 0 && s.lvis);
      okBefore = same && saves.every((s) => (s.h - 42).abs() < 0.01 && !s.m48);
      okStrict = same && saves.every((s) => (s.h - 48).abs() < 0.01 && s.m48);
      raw = 'sw $sw s1 $s1 s2 $s2 s3 $s3 fs $fs';
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
  _out('R597 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D597 $tok att fw n=$nFw');
  _out('D597 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  if (_before) {
    chk('before 대상 = 지금 A(TAB 두 이름 전문 · 이름 중심 hit · 누르는 자리 ≥ 48 · 고르기/되돌리기 전환 · W/N 늘 화면 안 · B 가로 스크롤로 어느 상태에선가 이름이 화면 밖으로 밀림 / '
        'SAVE 관리자 셋 저장 높이 42 · m48 거짓 · 도달 · hit · 켜짐 · brand · 글 전문)', okBefore, raw);
  } else {
    chk('strict 대상 = 후보(TAB 세 상태 두 이름 전문 · 화면 안 · 이름 중심 hit · 누르는 자리 ≥ 48 · 고르기/되돌리기 전환 / '
        'SAVE 관리자 셋 저장 높이 48 · 도달 · hit · 켜짐 · brand · 글 전문)', okStrict, raw);
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
      testWidgets('S597TL-${v.id}-${c.id} 공고 등록 개수 제한 — 탭 이름 전문 · 관리자별 저장 48', (t) async {
        final tok = 'S597TL-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _caseOf(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
