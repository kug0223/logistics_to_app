// ignore_for_file: depend_on_referenced_packages
// [DU595c · 같은 파일 표시 셀 · 판정177 §6] DU-S080 근로자 홈(lib/screens/user/user_home_screen.dart) 서류 보완 할 일 카드 배치 —
//   장부 084 의 남은 '배치' 부분: 카드 안쪽 Row(제목 · 부제 maxLines 2 · 말줄임) → 공용 배치 _taskCardRow(제목 낱말 · 부제 구분점 조각 · 급여 안내 셋째 줄 ·
//   본문 폭이 모자라면 `등록하기` 를 아래 오른쪽 줄로). 색(원 아이콘 warningDark · 행동 warningDark · 면/테두리 warning)은 DU595b 그대로.
//   before = 지금 A(user_home_screen 89ef05b7 = DU595b 채택 후보) 기록 · strict = 후보(cand/ · mkcell 이 SHA 대조).
//   하네스 = 블록 재사용(전체 바이트 동일 아님 · prep/mk_test.py 가 원본 fullSHA · 블록 sha12 단언):
//     DU595b g1 suite(7e30c11e · g1 TB/TA 공개 9 · hidden 3 성공 — work/du595b-user-home/g1/run/runs.txt:9 · :14) — 가짜 Firebase · 글꼴 · max 판 _fullShown ·
//       _textObs · _area · _lineCount · 보기 W/B/N · _halt · env 줄 · _DSeen · _txt · _bringBuilt · _semOf · _textLine · 색 도우미 · _fills · _inkOf ·
//       근로자 대역 _HUser · 고정 시계 · 원 아이콘 칠 _iconInk · _caseOf 의 진입/캡처/정리 뼈대.
//     DU562 r2 suite(b4029f2a · r2 DONE 5/5) — _hitWithin(받는 자리 hit · 누르지 않는다).
//   새로 쓴 것: 이 머리 · 사례 2(DOC · DOCI) · 글 상수 · 읽기 경계 대역(서류 보완만) · 사례 본문의 대상 측정(dt · ds · dn/dz · da · dc · di · dl · dr) · main.
//   누르는 것 0(ensureVisible · _bringBuilt 의 scrollUntilVisible · hit 계산만). 쓰기 · CF 0.
//   기본 skip — TB before/du595chm-tb/DU_BEFORE_OBSERVE=595 · TA after/du595chm-ta/없음.
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
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
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

/// [DU595c] 사례 — DOC = 서류 보완 2(급여 BANK_MISMATCH 긴 제목 · 긴 사업장 · 급여 안내 셋째 줄 + 지원 ID_CARD → '외 1건') ·
///   DOCI = 지원 ID_CARD 1(긴 사업장 · 셋째 줄 없음 = note null 분기). 각 2장(첫 화면 · 카드).
const _cases = <({String id, int shots})>[(id: 'DOC', shots: 2), (id: 'DOCI', shots: 2)];

/// [DU595c] 이 셀이 보는 글 — mkcell 이 base/후보 · 서비스 원문과 대조한다(두 모드 같은 글 · 배치만 바뀐다).
const _kDocBiz = '강남구 테헤란로 제2물류센터';
const _kDocTitle = '등록한 계좌와 통장사본이 다릅니다. 다시 등록해주세요.';
const _kDocSub = '강남구 테헤란로 제2물류센터 급여 지급을 위해 필요해요 · 외 1건';
const _kDocNote = '확정된 급여 금액은 그대로 유지돼요';
const _kDocAct = '등록하기';
const _kIdTitle = '신분증을 다시 등록해주세요.';
const _kIdSub = '강남구 테헤란로 제2물류센터에서 서류 재등록을 요청했어요';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '595';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du595chm-tb' && _env['DU_BEFORE_OBSERVE'] == '595') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du595chm-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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

// [DU595b] 아래 측정 도우미는 바이트 그대로 옮겼다 — DU592b(e415704a) :758–799(_txt · _bringBuilt · _semOf · _TO · _textLine — ensureVisible 대상 = 잰 대상) ·
//   :801–837(색 · 칠) · :839–871(화면 채움 단추 · A8) · :875–886(_inkOf — 같은 Finder 의 글 칠). 날짜별 창 대역 · 채널/HTTP guard 는 이 셀이 쓰지 않아 옮기지 않았다
//   (이 셀 사례는 홈 읽기 경계 대역만 쓴다 — HC · UHR · DU476 시험 하네스와 같다).

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

// [DU595c] 아래 _hitWithin 은 DU562 r2 suite(b4029f2a) :233–244 바이트 그대로(받는 자리 hit · 누르지 않는다).

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

// ───────────── [DU595c] 홈 대역(근로자 · 고정 시계는 DU595b g1 바이트) · 서류 보완 읽기 경계 · 사례 본문 ─────────────

const _hRegion = UserRegion(province: '서울특별시', city: '강남구', district: '역삼동');

/// [DU595b] 근로자 — DU476 _UserDouble 꼴(passVerifiedAt 은 고정일 · 계약 새로고침은 아무것도 하지 않는다).
class _HUser extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
        homeRegion: _hRegion, accountStatus: 'active', passVerifiedAt: DateTime(2026, 10, 1),
      );
  @override
  Future<void> refreshPendingContracts({bool joinInFlight = false}) async {}
}

/// [DU595b] 고정 시계 — KST 2026-10-13 11:30(user_home_attendance_cta_test HC-8/HC-9 와 같은 시각). 실행 시각 무관(A7).
final DateTime _hClock = DateTime.utc(2026, 10, 13, 11, 30).subtract(const Duration(hours: 9));

/// [DU595c] 읽기 경계 — 홈이 읽는 원시 호출만 채운다(DU595b g1 _hReads 꼴 · 지원 0 · 근태 0 · 계약 0 · 공고 0 · 요청 0 · 연장 0 · 서류 보완만 사례별).
UserHomeReads _hReads(DocumentCorrectionSurface corr) => UserHomeReads(
      slotsForTO: (toId) async => const <SlotModel>[],
      myContracts: (uid) async => const [],
      myApplications: (uid) async => const <ApplicationModel>[],
      myMonthlyAttendances: ({required String userId, required int year, required int month}) async => const <AttendanceModel>[],
      publishedTOs: () async => const <TOModel>[],
      pendingIdCardRequests: (uid) async => const <IdCardAccessRequestModel>[],
      invalidatePublishedTOsCache: () {},
      documentCorrections: () async => corr,
      myRenewalProposals: () async => const <RenewalProposalModel>[],
      businessById: (id) async => null,
    );

/// [DU595c] 사례 대역 — DOC = DU595b g1 DOC 와 같은 두 할 일(첫째 급여 BANK_MISMATCH = 앞에 서는 할 일 · 둘째 지원 ID_CARD) ·
///   DOCI = 지원 ID_CARD 하나(긴 사업장 · 급여 아님 → 셋째 줄 없음).
UserHomeReads _hFx(String id) {
  if (id == 'DOCI') {
    return _hReads(const DocumentCorrectionSurface.loaded([
      DocumentCorrectionTask(requestId: 'cr3', businessId: 'biz1', businessName: _kDocBiz, documentType: 'ID_CARD', sourceDomain: 'APPLICATION'),
    ]));
  }
  return _hReads(const DocumentCorrectionSurface.loaded([
    DocumentCorrectionTask(requestId: 'cr1', businessId: 'biz1', businessName: _kDocBiz, documentType: 'BANKBOOK', sourceDomain: 'PAYROLL',
        payrollReadinessState: 'BANK_MISMATCH'),
    DocumentCorrectionTask(requestId: 'cr2', businessId: 'biz2', businessName: '강남 물류센터', documentType: 'ID_CARD', sourceDomain: 'APPLICATION'),
  ]));
}

/// [DU595b] 원 아이콘 칠 — [f] 의 Icon 글리프 색 · 그 뒤 실제 면(_bgOf — 가장 가까운 칠한 조상 = 원) · 대비(비글자 3:1 기준). 잰 즉시 값으로 굳힌다.
typedef _IconObs = ({int n, String fill, String glyph, String cr, bool ok3});

_IconObs _iconInk(Finder f) {
  final es = f.evaluate().toList();
  if (es.length != 1) return (n: es.length, fill: '-', glyph: '-', cr: '0.00', ok3: false);
  final Color? g = (es.first.widget as Icon).color;
  final bg = _bgOf(es.first);
  final cr = g == null ? 0.0 : _contrast(g, bg);
  return (n: 1, fill: _hex(bg), glyph: g == null ? '-' : _hex(g), cr: cr.toStringAsFixed(2), ok3: cr >= 3.0);
}

String _rectS(Rect r) => '${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)},${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}';

/// [DU595c] 근로자 홈 서류 보완 카드 사례 — 홈을 그리고(누르기 0) ① 첫 화면 채움 단추(A8 · 기록만) · 1top ② 카드 글: _bringBuilt(지연 목록 대비 · A4) →
///   _textLine(ensureVisible 대상 = 잰 대상 · A1) — 제목 · 부제 · (DOC) 급여 안내 / (DOCI) 셋째 줄 없음 · 행동 · 같은 Finder 의 칠 · 원 아이콘 칠 ·
///   배치(행동이 본문 아래 줄인가 · 카드 안인가) · 받는 자리(행동 글 중심 hit → 카드 GestureDetector · 카드 48 이상 — 누르지 않는다) · 카드를 맞춰 2장째.
Future<void> _caseOf(WidgetTester t, _V v, ({String id, int shots}) c, String tok) async {
  final prevOnError = FlutterError.onError;
  addTearDown(() => FlutterError.onError = prevOnError);
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D595 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: _HUser()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.workerTheme,
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
          home: UserTabScope(
            switchToTab: (_) {},
            switchToTabWithDate: (i, d) {},
            pendingJobDate: null,
            clearPendingJobDate: () {},
            pendingScheduleMonth: null,
            clearPendingScheduleMonth: () {},
            switchToScheduleNow: () {},
            child: UserHomeScreen(reads: _hFx(c.id), clock: () => _hClock),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final home = find.byType(UserHomeScreen);
    final nHome = home.evaluate().length;
    if (nHome != 1) throw StateError('홈 $nHome');
    Future<void> shot(String id, String state) async {
      _out('D595 $tok shot $id ovf=${seen.overflows.length}');
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
    _out('D595 $tok att ftop n=${ftp.n} brand=${ftp.brand} err=${ftp.err} none=${ftp.none} other=${ftp.other} list=${ftp.list}');
    await shot('1top', 'home-top');
    // ② 카드 — 지연 목록이면 먼저 짓고(_bringBuilt) · 같은 Finder 를 ensureVisible 해 잰다(_textLine) · 그 Finder 의 칠(_inkOf).
    final doc = c.id == 'DOC';
    final wTitle = doc ? _kDocTitle : _kIdTitle;
    final wSub = doc ? _kDocSub : _kIdSub;
    await _bringBuilt(t, home, wTitle);
    final tf = _txt(home, wTitle, onstage: false);
    final nT = tf.evaluate().length;
    // 카드 = 제목에서 가장 가까운 GestureDetector 조상(카드 전체 탭 · 다른 '등록하기' 와 섞이지 않게).
    final cardF = nT == 1 ? find.ancestor(of: tf, matching: find.byType(GestureDetector)).first : home;
    final lt = await _textLine(t, tf, wTitle, screen);
    _out('D595 $tok att dt n=${lt.n} shown=${lt.shown} sem=${lt.sem} full=${lt.full} ell0=${lt.ell0} brk=${lt.brk} lines=${lt.lines} vis=${lt.vis}');
    await _bringBuilt(t, home, wSub);
    final sf = _txt(cardF, wSub, onstage: false);
    final ls = await _textLine(t, sf, wSub, screen);
    _out('D595 $tok att ds n=${ls.n} shown=${ls.shown} sem=${ls.sem} full=${ls.full} ell0=${ls.ell0} brk=${ls.brk} lines=${ls.lines} vis=${ls.vis}');
    // 셋째 줄 — DOC 는 급여 안내 전문(같은 카드 안) · DOCI 는 카드 안에 그 글이 없어야 한다(note null 분기 · 새 줄 0).
    _TO ln = (n: 0, shown: false, sem: false, full: false, ell0: false, brk: 0, lines: 0, vis: false);
    var nz = -1;
    if (doc) {
      await _bringBuilt(t, home, _kDocNote);
      final nf = _txt(cardF, _kDocNote, onstage: false);
      ln = await _textLine(t, nf, _kDocNote, screen);
      _out('D595 $tok att dn n=${ln.n} shown=${ln.shown} sem=${ln.sem} full=${ln.full} ell0=${ln.ell0} brk=${ln.brk} lines=${ln.lines} vis=${ln.vis}');
    } else {
      nz = _txt(cardF, _kDocNote, onstage: false).evaluate().length;
      _out('D595 $tok att dz n=$nz');
    }
    // 행동 글자 — 전문 · 보임(마지막 ensureVisible 대상 = 이 af) · 칠(DU476 warningDark 그대로) · 원 아이콘 칠(DU595b warningDark 그대로).
    await _bringBuilt(t, home, _kDocAct);
    final af = _txt(cardF, _kDocAct, onstage: false);
    final la = await _textLine(t, af, _kDocAct, screen);
    _out('D595 $tok att da n=${la.n} shown=${la.shown} sem=${la.sem} full=${la.full} ell0=${la.ell0} brk=${la.brk} lines=${la.lines} vis=${la.vis}');
    final ai = _inkOf(af);
    final wdark = ai.fg == _hex(AppColors.warningDark);
    _out('D595 $tok att dc n=${ai.n} fg=${ai.fg} bg=${ai.bg} cr=${ai.cr} ok45=${ai.ok45} wdark=$wdark');
    final ic = _iconInk(find.descendant(of: cardF, matching: find.byIcon(Icons.assignment_late_outlined, skipOffstage: false), skipOffstage: false));
    final idark = ic.fill == _hex(AppColors.warningDark);
    _out('D595 $tok att di n=${ic.n} fill=${ic.fill} glyph=${ic.glyph} cr=${ic.cr} ok3=${ic.ok3} dark=$idark');
    // 배치 · 받는 자리 — 같은 프레임(마지막 ensureVisible = af 뒤)의 전역 사각형. 행동 글이 본문(제목의 가장 가까운 Column) 아래 줄인가 · 카드 안인가 ·
    //   행동 글 중심을 누르면(누르지 않는다 · hit 계산만) 카드(GestureDetector)가 받는가 · 카드 48 이상.
    final na = af.evaluate().length;
    var ar = Rect.zero;
    var br = Rect.zero;
    var kr = Rect.zero;
    var stack = false;
    var inCard = false;
    var rVis = false;
    var rHit = false;
    var r48 = false;
    if (na == 1 && nT == 1) {
      ar = t.getRect(af);
      br = t.getRect(find.ancestor(of: tf, matching: find.byType(Column)).first);
      kr = t.getRect(cardF);
      stack = ar.top >= br.bottom - 0.5;
      inCard = _inside(ar, kr);
      rVis = _inside(ar, _area(af, screen));
      rHit = _hitWithin(t, cardF, ar.center);
      r48 = kr.width >= 48 - 0.01 && kr.height >= 48 - 0.01;
    }
    _out('D595 $tok att dl stack=$stack inCard=$inCard');
    _out('D595 $tok att dr n=$na vis=$rVis hit=$rHit m48=$r48');
    bool okL(_TO o) => o.n == 1 && o.shown && o.sem && o.full && o.ell0 && o.brk == 0 && o.vis;
    final third = doc ? ln.n == 1 : nz == 0;
    okBefore = lt.n == 1 && ls.n == 1 && la.n == 1 && third && ai.n == 1 && wdark && ic.n == 1 && idark && ic.glyph == '#FFFFFF';
    okStrict = okL(lt) && okL(ls) && okL(la) && (doc ? okL(ln) : nz == 0) && ai.n == 1 && wdark && ic.n == 1 && idark && ic.glyph == '#FFFFFF' &&
        ic.ok3 && inCard && na == 1 && rVis && rHit && r48;
    final fo = _fills(t);
    _out('D595 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
    await t.ensureVisible(cardF);
    await settle();
    await shot('2task', doc ? 'doc-task' : 'id-task');
    raw = 'top $ftp dt $lt ds $ls dn $ln dz $nz da $la dc $ai di $ic dl $stack/$inCard dr $na/$rVis/$rHit/$r48 '
        'rects ${_rectS(ar)}|${_rectS(br)}|${_rectS(kr)} fills $fo';
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // ③ 성공 · 실패 공통 정리 — 홈을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다.
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
  _out('R595 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D595 $tok att fw n=$nFw');
  _out('D595 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  if (_before) {
    chk('before 대상 = 지금 A(카드 글 1개씩 · DOC 급여 안내 1 / DOCI 셋째 줄 0 · 행동 warningDark · 원 warningDark · 흰 글리프)', okBefore, raw);
  } else {
    chk('strict 대상 = 후보(제목 · 부제 · (DOC) 급여 안내 · 행동 전문 · 말줄임 0 · 낱말 안 끊김 0 · 보임 / (DOCI) 셋째 줄 0 · 행동 warningDark · '
        '원 warningDark · 흰 글리프 ≥ 3 · 행동 카드 안 · 행동 글 중심 hit = 카드 · 카드 48 이상)', okStrict, raw);
    chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
    chk('strict 넘침 0(사례 전체 — 바뀐 카드 배치)', nOvf == 0, ovfRaw);
  }
  chk('캡처 수 = 선언', shots == c.shots, 'shots $shots want ${c.shots}');
  final bad = checks.where((x) => !x.$2).toList();
  if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
  for (final x in checks) {
    expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'tour_completed_user_home': true}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    await _loadFonts();
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S595HC-${v.id}-${c.id} 근로자 홈 서류 보완 카드 배치 — 제목 · 사업장 · 급여 안내 전문 · 좁으면 행동 아래 줄', (t) async {
        final tok = 'S595HC-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _caseOf(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
