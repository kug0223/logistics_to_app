// ignore_for_file: depend_on_referenced_packages
// [DU627b · 조화 트랙 화면 셀 · 표시만] 내 서류 관리(lib/screens/common/document_management_screen.dart) 색 역할 — 판정207 §4 · D-SCREEN-BG.
//   ① 화면 바탕 grey50 → background(앱 화면 바탕) ② 관리자 '재업로드' 외곽 단추 글/아이콘/선 grey600·infoDark → brand(행동)
//   ③ 문서 상태 칩 '확인 완료' success · '다시 등록 필요' error · '관리자 확인 중' warning → successDark/errorDark/warningDark(같은 의미의 읽히는 짝)
//   ④ 항목 식별 아이콘(신분증 · 세무 · 급여 계좌) 등록 시 infoDark → textSecondary(장식 = 중립).
//   유지 대조(두 모드 같음): '제출 완료' 칩 infoDark(정보 상태) · 세무 '등록 완료' successDark · 미등록 아이콘 grey400 · 관리자 '삭제' 외곽(글 grey600 · 아이콘/선 error) ·
//     관리자 안내 띠 글 warningDark.
//   before = 지금 A(document_management_screen 648c47d9) 기록 · strict = 후보(cand/ · mkcell 이 SHA 대조).
//   하네스 = 블록 재사용(prep/mk_suite.py 가 원본 fullSHA · 줄 범위 바이트 단언): DU596b suite(79dbbbd8 · 글꼴 · max 판 _fullShown · _textObs · _area ·
//     _lineCount · 보기 W/B/N · _halt · env 줄 · _DSeen · _txt · _bringBuilt · _semOf · _textLine · 색 도우미 · _fills · _inkOf · _iconInk) +
//     렌더 방식 = du1_s038_document_unregistered_visual_test · du1_s038_admin_docs_485_test(가짜 Firebase storageBucket 포함 · 세무상태 Functions 대역 · Firestore 10 op 막음).
//   새로 쓴 것: 이 머리 · 가짜 Firebase(S038 와 같은 값) · 사례 3(UREV · UREJ · ADM) · 글 상수 · 사용자 대역 · 채널 대역 · 칩/단추/바탕 칠 · 사례 본문 · main.
//   누르는 것 0(ensureVisible · _bringBuilt 의 scrollUntilVisible 만 · 화면 = MaterialApp home 직접). 쓰기 · 업로드 · 삭제 0.
//   기본 skip — TB before/du627bdm-tb/DU_BEFORE_OBSERVE=627 · TA after/du627bdm-ta/없음.
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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/document_management_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';

/// [DU627b] 가짜 Firebase — du1_s038_document_unregistered_visual_test :35–:50 과 같은 값(StorageService 필드가 storageBucket 을 읽는다).
class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p', storageBucket: 'p.appspot.com');
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

/// [DU627b] 사례 — UREV = 국내 USER 제출(신분증 관리자 확인 중 · 통장사본 확인 완료 · 세무 등록 일치) · UREJ = 국내 USER 제출(신분증 다시 등록 필요 · 통장사본 제출 완료 ·
///   세무 미등록) · ADM = 사업장 관리자(사업자 정보 저장 · 사업자등록증 등록). 장수 = 첫 화면 + 대상(UREV/UREJ 급여 계좌 카드 · ADM 등록증 단추).
const _cases = <({String id, int shots})>[(id: 'UREV', shots: 2), (id: 'UREJ', shots: 2), (id: 'ADM', shots: 2)];

/// [DU627b] 이 셀이 보는 글 — mkcell 이 base/후보 원문과 대조한다(두 모드 같은 글 · 색만 바뀐다).
const _kReview = '관리자 확인 중';
const _kOk = '확인 완료';
const _kRej = '다시 등록 필요';
const _kSub = '제출 완료';
const _kTaxOk = '등록 완료';
const _kIdTitle = '신분증';
const _kTaxTitle = '세무정보';
const _kBankTitle = '급여 계좌';
const _kReup = '재업로드';
const _kDel = '삭제';
const _kBanner = '사업자등록증이 승인되어야 \n사업장 등록이 가능합니다.\n아래 정보와 사업자등록증이 일치해야 합니다.';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '627';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du627bdm-tb' && _env['DU_BEFORE_OBSERVE'] == '627') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du627bdm-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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

// ───────────── [DU627b] 새로 쓴 부분 — 사용자 대역 · 채널 대역 · 칩/단추/바탕/아이콘 칠 · 사례 본문 ─────────────

/// [DU627b] 사용자 대역 — du1_s038_document_unregistered_visual_test _UserDouble(registered) · du1_s038_admin_docs_485_test _Admin 과 같은 꼴 + 문서 상태(서버 기록값).
class _U extends UserProvider {
  _U(this.kind);
  final String kind;
  @override
  UserModel? get currentUser => kind == 'ADM'
      ? UserModel(
          uid: 'a1', username: 'a1', name: '김사장', email: 'a1@alfit.local', role: UserRole.BUSINESS_ADMIN,
          accountStatus: 'active', businessNumber: '1234567890', businessName: '중앙물류', ceoName: '김사장',
          businessLicenseImagePath: 'business_licenses/a1/license.jpg')
      : UserModel(
          uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
          accountStatus: 'active', isIdVerified: true,
          idCardImagePath: 'id_cards/u1/id.jpg',
          bankName: '국민은행', accountNumber: '123456789012', accountHolder: '김근로',
          bankbookImagePath: 'bankbooks/u1/bb.jpg',
          idCardDocumentState: kind == 'UREV' ? 'MANUAL_REVIEW_REQUIRED' : 'MANUAL_REJECTED',
          bankbookDocumentState: kind == 'UREV' ? 'MANUAL_APPROVED' : 'SELF_CHECK_PASSED');
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => kind == 'ADM';
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => kind == 'ADM';
  @override
  bool get permissionsLoaded => true;
}

const _fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
const _fsOps = ['documentReferenceGet', 'queryGet', 'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit',
  'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot'];

/// [DU627b] 채널 대역 — 세무상태만 성공 응답(UREV = 등록 일치 · 그 밖 = 미등록 · 수집 켜짐 — du1_s038 _cell :100–:122 과 같은 값) · 다른 Functions not-found ·
///   Firestore 10 op 막고 센다. 호출 수는 기록(att wire).
Map<String, int> _stubChannels(String kind) {
  final calls = <String, int>{};
  void inc(String k) => calls[k] = (calls[k] ?? 0) + 1;
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMessageHandler(_fnChannel, (msg) async {
    const c = StandardMessageCodec();
    final args = (c.decodeMessage(msg) as List).first as Map;
    final name = args['functionName'];
    inc('fn $name');
    if (name == 'callableGetTaxIdentityStatus' && args['region'] == 'asia-northeast3') {
      return c.encodeMessage(<Object?>[
        kind == 'UREV'
            ? <String, Object?>{
                'registered': true, 'collectionEnabled': true, 'identifierType': 'KOREAN_RRN',
                'foreignRecoveryAvailable': false, 'documentMatch': 'MATCHED', 'documentMatchCurrent': true,
              }
            : <String, Object?>{
                'registered': false, 'collectionEnabled': true, 'identifierType': null,
                'foreignRecoveryAvailable': false, 'documentMatch': 'UNASSESSED', 'documentMatchCurrent': false,
              }
      ]);
    }
    return c.encodeMessage(<Object?>['not-found', 'blocked', <String, Object?>{'code': 'not-found'}]);
  });
  for (final op in _fsOps) {
    m.setMockMessageHandler('$_fsBase.$op', (msg) async {
      inc('fs $op');
      return null;
    });
  }
  addTearDown(() {
    m.setMockMessageHandler(_fnChannel, null);
    for (final op in _fsOps) {
      m.setMockMessageHandler('$_fsBase.$op', null);
    }
  });
  return calls;
}

Finder _fe(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);

/// [DU627b] 화면 바탕 — 내 서류 관리 화면의 Scaffold.backgroundColor(화면이 지정한 값 · 기록 대상).
typedef _BgObs = ({int n, String col});

_BgObs _scafBg(Finder host) {
  final ss = find.descendant(of: host, matching: find.byType(Scaffold), skipOffstage: false).evaluate().toList();
  if (ss.isEmpty) return (n: 0, col: '-');
  final c = (ss.first.widget as Scaffold).backgroundColor;
  return (n: 1, col: c == null ? 'null' : _hex(c));
}

/// [DU627b] 항목 식별 아이콘 — 카드 머리의 22 크기 Icon([d]) 하나(개인정보 고지의 같은 아이콘은 크기가 달라 들지 않는다).
Finder _icon22(IconData d) => find.byWidgetPredicate((w) => w is Icon && w.icon == d && w.size == 22, skipOffstage: false);

/// [DU627b] 상태 칩 — [tf](같은 Finder · 점검표 A1)의 글 칠(_inkOf) + 가장 가까운 Row(_docStatusChip) 안 Icon 하나의 색. 잰 즉시 값으로 굳힌다.
typedef _ChipObs = ({int n, String fg, String bg, String cr, bool ok45, String icon});

_ChipObs _chipOf(Finder tf) {
  final io = _inkOf(tf);
  final rows = find.ancestor(of: tf, matching: find.byType(Row)).evaluate().toList();
  if (io.n != 1 || rows.isEmpty) return (n: 0, fg: io.fg, bg: io.bg, cr: io.cr, ok45: io.ok45, icon: '-');
  final ics = find.descendant(of: _fe(rows.first), matching: find.byType(Icon), skipOffstage: false).evaluate().toList();
  final Color? c = ics.length == 1 ? (ics.first.widget as Icon).color : null;
  return (n: ics.length == 1 ? 1 : 0, fg: io.fg, bg: io.bg, cr: io.cr, ok45: io.ok45, icon: c == null ? '-' : _hex(c));
}

/// [DU627b] 외곽 단추 — [tf] 글 칠 · 가장 가까운 ButtonStyleButton 의 선 색(style.side) · 그 안 Icon 의 실제 색(지정 없으면 IconTheme = 단추 전경색).
typedef _BtnObs = ({int n, String fg, String icon, String side, String cr, bool ok45});

_BtnObs _btnOf(Finder tf) {
  final io = _inkOf(tf);
  final bs = find.ancestor(of: tf, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).evaluate().toList();
  if (io.n != 1 || bs.isEmpty) return (n: 0, fg: io.fg, icon: '-', side: '-', cr: io.cr, ok45: false);
  final b = bs.first.widget as ButtonStyleButton;
  final sideC = b.style?.side?.resolve(<WidgetState>{})?.color;
  final ics = find.descendant(of: _fe(bs.first), matching: find.byType(Icon), skipOffstage: false).evaluate().toList();
  final Color? ic = ics.length == 1 ? ((ics.first.widget as Icon).color ?? IconTheme.of(ics.first).color) : null;
  return (n: ics.length == 1 ? 1 : 0, fg: io.fg, icon: ic == null ? '-' : _hex(ic), side: sideC == null ? '-' : _hex(sideC), cr: io.cr, ok45: io.ok45);
}

/// [DU627b] 사례 — 화면을 그리고(누르기 0) ① 첫 화면 채움 단추(A8) · 화면 바탕 · 1top ② 위에서 아래로(지연 목록 폐기 전) 대상 칠 · 2장째.
Future<void> _caseOf(WidgetTester t, _V v, ({String id, int shots}) c, String tok) async {
  final prevOnError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = prevOnError);
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D627 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
  final seen = _DSeen();
  final checks = <(String, bool, String)>[];
  void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));
  Object? failure;
  StackTrace? failureSt;
  var shots = 0;
  var raw = '';
  var okBefore = false;
  var okStrict = false;
  final calls = _stubChannels(c.id);
  try {
    FlutterError.onError = seen.add;
    final key = GlobalKey();
    await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
      create: (_) => _U(c.id),
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.getThemeByRole(c.id == 'ADM' ? 'BUSINESS_ADMIN' : 'USER'),
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
          home: const DocumentManagementScreen(),
        ),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final host = find.byType(DocumentManagementScreen);
    final nHost = host.evaluate().length;
    if (nHost != 1) throw StateError('화면 $nHost');
    Future<void> shot(String id, String state) async {
      _out('D627 $tok shot $id ovf=${seen.overflows.length}');
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

    // ① 첫 화면 — 채움 단추(A8 · 기록만) · 화면 바탕 · 1top.
    final ftp = _fills(t);
    _out('D627 $tok att ftop n=${ftp.n} brand=${ftp.brand} err=${ftp.err} none=${ftp.none} other=${ftp.other} list=${ftp.list}');
    final bg = _scafBg(host);
    _out('D627 $tok att bg n=${bg.n} col=${bg.col}');
    await shot('1top', 'screen-top');
    final bgBefore = bg.n == 1 && bg.col == _hex(AppColors.grey50);
    final bgStrict = bg.n == 1 && bg.col == _hex(AppColors.background);
    if (c.id == 'ADM') {
      // ② 관리자 — 안내 띠 글(유지 대조) · 등록증 '재업로드'(교정) · '삭제'(유지 대조 — 진입 색은 검토 갈래).
      await _bringBuilt(t, host, _kBanner);
      final ab = _inkOf(_txt(host, _kBanner, onstage: false));
      _out('D627 $tok att ab n=${ab.n} fg=${ab.fg} bg=${ab.bg} cr=${ab.cr} ok45=${ab.ok45}');
      await _bringBuilt(t, host, _kReup);
      final rf = _txt(host, _kReup, onstage: false);
      final rl = await _textLine(t, rf, _kReup, Offset.zero & Size(v.w, v.h));
      _out('D627 $tok att rl n=${rl.n} shown=${rl.shown} sem=${rl.sem} full=${rl.full} ell0=${rl.ell0} brk=${rl.brk} lines=${rl.lines} vis=${rl.vis}');
      final ru = _btnOf(rf);
      _out('D627 $tok att ru n=${ru.n} fg=${ru.fg} icon=${ru.icon} side=${ru.side} cr=${ru.cr} ok45=${ru.ok45}');
      await _bringBuilt(t, host, _kDel);
      final rd = _btnOf(_txt(host, _kDel, onstage: false));
      _out('D627 $tok att rd n=${rd.n} fg=${rd.fg} icon=${rd.icon} side=${rd.side} cr=${rd.cr} ok45=${rd.ok45}');
      final fo = _fills(t);
      _out('D627 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
      await t.ensureVisible(rf);
      await settle();
      await shot('2btn', 'license-buttons');
      final keep = ab.n == 1 && ab.fg == _hex(AppColors.warningDark) && rd.n == 1 && rd.fg == _hex(AppColors.grey600) && rd.icon == _hex(AppColors.error) &&
          rd.side == _hex(AppColors.error);
      okBefore = bgBefore && ru.n == 1 && ru.fg == _hex(AppColors.grey600) && ru.icon == _hex(AppColors.infoDark) && ru.side == _hex(AppColors.infoDark) && keep;
      okStrict = bgStrict && ru.n == 1 && ru.fg == _hex(AppColors.brand) && ru.icon == _hex(AppColors.brand) && ru.side == _hex(AppColors.brand) && ru.ok45 && keep;
      raw = 'top $ftp bg $bg ab $ab ru $ru rd $rd fills $fo';
    } else {
      // ② 근로자 — 신분증 카드(아이콘 · 상태 칩) → 세무 카드 → 급여 계좌 카드(위에서 아래로).
      await _bringBuilt(t, host, _kIdTitle);
      final iid = _iconInk(_icon22(Icons.badge_outlined));
      _out('D627 $tok att iid n=${iid.n} fill=${iid.fill} glyph=${iid.glyph} cr=${iid.cr} ok3=${iid.ok3}');
      final idWant = c.id == 'UREV' ? _kReview : _kRej;
      await _bringBuilt(t, host, idWant);
      final idf = _txt(host, idWant, onstage: false);
      final il = await _textLine(t, idf, idWant, Offset.zero & Size(v.w, v.h));
      _out('D627 $tok att il n=${il.n} shown=${il.shown} sem=${il.sem} full=${il.full} ell0=${il.ell0} brk=${il.brk} lines=${il.lines} vis=${il.vis}');
      final ic = _chipOf(idf);
      if (c.id == 'UREV') {
        _out('D627 $tok att cw n=${ic.n} fg=${ic.fg} bg=${ic.bg} cr=${ic.cr} ok45=${ic.ok45} icon=${ic.icon}');
      } else {
        _out('D627 $tok att ce n=${ic.n} fg=${ic.fg} bg=${ic.bg} cr=${ic.cr} ok45=${ic.ok45} icon=${ic.icon}');
      }
      await _bringBuilt(t, host, _kTaxTitle);
      final iit = _iconInk(_icon22(Icons.receipt_long_outlined));
      _out('D627 $tok att iit n=${iit.n} fill=${iit.fill} glyph=${iit.glyph} cr=${iit.cr} ok3=${iit.ok3}');
      var tcOk = true;
      var tcRaw = '-';
      if (c.id == 'UREV') {
        await _bringBuilt(t, host, _kTaxOk);
        final tc = _chipOf(_txt(host, _kTaxOk, onstage: false));
        _out('D627 $tok att tc n=${tc.n} fg=${tc.fg} bg=${tc.bg} cr=${tc.cr} ok45=${tc.ok45} icon=${tc.icon}');
        tcOk = tc.n == 1 && tc.fg == _hex(AppColors.successDark) && tc.icon == _hex(AppColors.successDark);
        tcRaw = tc.toString();
      }
      await _bringBuilt(t, host, _kBankTitle);
      final iib = _iconInk(_icon22(Icons.account_balance_wallet_outlined));
      _out('D627 $tok att iib n=${iib.n} fill=${iib.fill} glyph=${iib.glyph} cr=${iib.cr} ok3=${iib.ok3}');
      final bkWant = c.id == 'UREV' ? _kOk : _kSub;
      await _bringBuilt(t, host, bkWant);
      final bf = _txt(host, bkWant, onstage: false);
      final bc = _chipOf(bf);
      if (c.id == 'UREV') {
        _out('D627 $tok att cs n=${bc.n} fg=${bc.fg} bg=${bc.bg} cr=${bc.cr} ok45=${bc.ok45} icon=${bc.icon}');
      } else {
        _out('D627 $tok att cp n=${bc.n} fg=${bc.fg} bg=${bc.bg} cr=${bc.cr} ok45=${bc.ok45} icon=${bc.icon}');
      }
      final fo = _fills(t);
      _out('D627 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
      await t.ensureVisible(bf);
      await settle();
      await shot('2chip', 'bank-card');
      final oldIcon = _hex(AppColors.infoDark);
      final newIcon = _hex(AppColors.textSecondary);
      final taxIconB = c.id == 'UREV' ? oldIcon : _hex(AppColors.grey400);
      final taxIconS = c.id == 'UREV' ? newIcon : _hex(AppColors.grey400);
      final idB = c.id == 'UREV' ? _hex(AppColors.warning) : _hex(AppColors.error);
      final idS = c.id == 'UREV' ? _hex(AppColors.warningDark) : _hex(AppColors.errorDark);
      final bkB = c.id == 'UREV' ? _hex(AppColors.success) : _hex(AppColors.infoDark);
      final bkS = c.id == 'UREV' ? _hex(AppColors.successDark) : _hex(AppColors.infoDark);
      final icons = iid.n == 1 && iit.n == 1 && iib.n == 1;
      okBefore = bgBefore && icons && iid.glyph == oldIcon && iit.glyph == taxIconB && iib.glyph == oldIcon && ic.n == 1 && ic.fg == idB && ic.icon == idB &&
          bc.n == 1 && bc.fg == bkB && bc.icon == bkB && tcOk;
      okStrict = bgStrict && icons && iid.glyph == newIcon && iit.glyph == taxIconS && iib.glyph == newIcon && ic.n == 1 && ic.fg == idS && ic.icon == idS &&
          ic.ok45 && bc.n == 1 && bc.fg == bkS && bc.icon == bkS && bc.ok45 && tcOk;
      raw = 'top $ftp bg $bg iid $iid id $ic iit $iit tc $tcRaw iib $iib bk $bc fills $fo';
    }
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // 성공 · 실패 공통 정리 — 화면을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다(DU596b 와 같다).
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
  final nTax = calls['fn callableGetTaxIdentityStatus'] ?? 0;
  final nOtherFn = calls.entries.where((e) => e.key.startsWith('fn ') && e.key != 'fn callableGetTaxIdentityStatus').fold<int>(0, (a, e) => a + e.value);
  final nFs = calls.entries.where((e) => e.key.startsWith('fs ')).fold<int>(0, (a, e) => a + e.value);
  _out('D627 $tok att wire tax=$nTax fn=$nOtherFn fs=$nFs');
  final nOvf = seen.overflows.length;
  final nFw = seen.other.length;
  final ovfRaw = seen.overflows.join('\n----\n');
  final fwRaw = seen.other.join('\n----\n');
  _out('R627 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D627 $tok att fw n=$nFw');
  _out('D627 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  if (_before) {
    chk('before 대상 = 지금 A(바탕 grey50 · 아이콘 infoDark · 칩 warning/error/success · 재업로드 grey600 글 + infoDark 아이콘/선) · 유지 갈래 그대로', okBefore, raw);
  } else {
    chk('strict 대상 = 후보(바탕 background · 아이콘 textSecondary · 칩 *Dark 대비 ≥ 4.5 · 재업로드 brand 한 짝) · 유지 갈래 그대로', okStrict, raw);
    chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
  }
  chk('세무상태 1회 · 다른 Functions 0 · Firestore 0', nTax == 1 && nOtherFn == 0 && nFs == 0, 'tax $nTax fn $nOtherFn fs $nFs');
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
    await _loadFonts();
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S627DM-${v.id}-${c.id} 내 서류 관리 색 역할(판정207 §4) — 바탕 · 상태 칩 짝 · 항목 아이콘 중립 · 재업로드 brand', (t) async {
        final tok = 'S627DM-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _caseOf(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
