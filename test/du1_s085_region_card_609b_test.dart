// ignore_for_file: depend_on_referenced_packages
// [DU609b · 파일 단위 셀 · 장부 182 행 142(S085 B 지역명 4줄 카드 높이 — 판정105 §1-3 :9 '다음 표시 선택 후보 · 폭/배치로 낱말·전체 정보 보존하며 비교')] 표시만.
//   바뀐 것: lib/main.dart _HomeRegionRecoveryScreenState.build 의 SingleChildScrollView 좌우 여백 24 고정 → ResponsiveHelper.screenPadding(context).left
//     (공용 helper 그대로 — 폭 < 360 이면 16 · < 600 이면 24 = W 390 는 24 그대로 · B/N 320 은 16). 세로 32 · 카드 · 글 · 색 · 콜백 · 분기 그대로.
//   before = 지금 A(main 70a548ee = DU424 후보) · strict = 후보. 고정 두 줄 · 말줄임 · 배율 축소 · 지역 데이터/중복 삭제를 성공 조건으로 쓰지 않는다(판정105 :9).
//   host = DU424 시험(du424-vc-wordbreak/new/du1_vc_wordbreak_424_test.dart · run2 DONE 5/5 · 판정105 §1-2 수용)의 AuthWrapper host(_Prov · ThemeProvider 'USER' ·
//     prefs onboarding_completed_u1 · homeRegion null → 실제 복구 화면) · 세종특별자치시 실제 시트 선택(:402–:413 그대로).
//   측정 블록 = DU605b 시험(du605b-help-faq/new/du1_s040_help_routes_605b_test.dart · 정규 1회 DONE 5/5 · 판정183 §1 수용)의 Firebase 대역 · 글꼴 · _midBreaks ·
//     max 판 _fullShown · _area · _lineCount · _views · _DSeen · _seeText · _hex · _fills 바이트 그대로. 새 것 = _zwBreaks(가운데 ZWSP 줄바꿈 수 · 기록) · _cardObs(카드 높이 · 좌우).
//   잰다(읽기만): 제목 · 설명 · 지역 카드 글 · 저장 단추 글 — 각 RichText 하나를 ensureVisible 로 넣고 같은 요소로 전문 · 낱말 안 끊김 · 줄 · 보임 · 읽는 이름.
//     카드: 가운데 끊김 수(zw) · 높이(ch) · 좌우 여백(l · r) — 좌우는 사례 안에서 모드별 기대(before 24 · strict = 폭 < 360 ? 16 : 24)를 단언한다.
//   저장 · 로그아웃은 누르지 않는다(쓰기 0). 기본 skip — TB before/du609bmain-tb/DU_BEFORE_OBSERVE=609 · TA after/du609bmain-ta/없음.
import 'dart:convert';
import 'dart:io';
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

import 'package:ALfit/main.dart' show AuthWrapper;
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/theme_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
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
    // [DU571 r2 · 판정167 시험 STOP 수리 · 판정159/161/162 방식] 세로는 줄 배치(max 상자) · 가로는 tight right(종전) · 공차 0.5 그대로.
    //   tight 세로는 run 글꼴 높이라 줄 높이 1.3 < 글꼴 원래 1.448em 이면 줄 상자 밖으로 나온다(DU559 nmraw: h+1.258). 잉크/clip 증명 아님.
    final sel = TextSelection(baseOffset: i, extentOffset: i + 1);
    final tight = rp.getBoxesForSelection(sel);
    final mx = rp.getBoxesForSelection(sel, boxHeightStyle: ui.BoxHeightStyle.max);
    return tight.isNotEmpty && mx.isNotEmpty && mx.first.bottom <= size.height + 0.5 && tight.first.right <= size.width + 0.5;
  }
  return false;
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

typedef _SeeObs = ({int n, bool name, bool full, int brk, int lines, bool vis});

/// [DU571] 바뀐 글 하나 — 그린 글(표시 제어 문자 제외)이 [match] 에 맞는 RichText 가 정확히 하나일 때 **그 RichText 를** ensureVisible 로 넣고,
///   같은 요소로 읽는 이름(가장 가까운 Semantics 조상 label = 그 글 원문) · 전문 · 낱말 안 끊김(강제 포함) · 줄 수 · 화면 ∩ 스크롤 칸 안을 잰다
///   (DU570 의 같은 이름 도우미와 같은 잣대 · 찾는 조건만 함수 · await 뒤에는 Element 를 직접 읽지 않고 같은 finder 로 다시 잡는다).
Future<_SeeObs> _seeText(WidgetTester t, Finder host, bool Function(String s) match, Rect screen) async {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .toList();
  if (es.length != 1) return (n: es.length, name: false, full: false, brk: 0, lines: 0, vis: false);
  final el = es.first;
  final want = TextLayout.plain((el.widget as RichText).text.toPlainText(includeSemanticsLabels: false));
  final tf = find.byElementPredicate((x) => identical(x, el), skipOffstage: false);
  await t.ensureVisible(tf);
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  final rp = t.renderObject<RenderParagraph>(tf);
  final sem = find.ancestor(of: tf, matching: find.byType(Semantics, skipOffstage: false)).evaluate();
  final label = sem.isEmpty ? null : (sem.first.widget as Semantics).properties.label;
  return (
    n: 1,
    name: label == want,
    full: _fullShown(rp, rp.size),
    brk: _midBreaks(rp),
    lines: _lineCount(rp),
    vis: _inside(t.getRect(tf), _area(tf, screen)),
  );
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

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

/// [DU609b] 낱말 가운데 끊을 자리(ZWSP · TextLayout.identity)에서 줄이 바뀐 횟수 — 공백 · 개행에서 바뀐 것은 세지 않는다(_midBreaks 와 같은 줄 판정).
int _zwBreaks(RenderParagraph rp) {
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
      var space = ch == ' ' || (lastIdx >= 0 && s[lastIdx] == ' ');
      var mid = false;
      for (var k = lastIdx + 1; k < i; k++) {
        if (s[k] == ' ') space = true;
        if (s[k] == _zw) mid = true;
      }
      if (mid && !space) n++;
    }
    if (lastTop == null || wrapped) lastTop = top;
    lastIdx = i;
  }
  return n;
}

typedef _CardObs = ({int n, int zw, double ch, double l, double r});

/// [DU609b] 지역 카드 — 그린 글이 [text] 인 RichText 하나(_seeText 가 방금 ensureVisible 한 같은 글)를 다시 잡아(스크롤 · 포인터 0)
///   가운데 끊김 수 · 가장 가까운 InkWell(카드 눌림 칸 = Material 안 전체) 높이 · 화면 왼쪽 · 오른쪽 여백을 즉시 읽는다.
_CardObs _cardObs(WidgetTester t, Finder host, String text, double screenW) {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == text)
      .toList();
  if (es.length != 1) return (n: es.length, zw: 0, ch: 0.0, l: 0.0, r: 0.0);
  final tf = find.byElementPredicate((x) => identical(x, es.first), skipOffstage: false);
  final zw = _zwBreaks(t.renderObject<RenderParagraph>(tf));
  final ink = find.ancestor(of: tf, matching: find.byType(InkWell));
  if (ink.evaluate().isEmpty) return (n: 0, zw: zw, ch: 0.0, l: 0.0, r: 0.0);
  final cr = t.getRect(ink.first);
  return (n: 1, zw: zw, ch: cr.height, l: cr.left, r: screenW - cr.right);
}

/// AuthWrapper 대역(DU424 :83–90 · DU422 와 같음) — 로그아웃은 즉시 완료(이 시험은 누르지 않는다).
class _Prov extends UserProvider {
  int signOutCalls = 0;
  @override
  Future<void> signOut() {
    signOutCalls++;
    return Future<void>.value();
  }
}

/// 사례 — UNSEL = 첫 진입(미선택 · 힌트 글) · SEL = 실제 시트에서 세종특별자치시(가장 긴 표시 '세종특별자치시 세종특별자치시').
typedef _Case = ({String id, int shots, bool pick});
const _cases = <_Case>[(id: 'UNSEL', shots: 2, pick: false), (id: 'SEL', shots: 2, pick: true)];

// ── 화면 글(main.dart :725–:726 · :800 · :841 · 바꾸지 않음) ──
const _title = '주로 일할 지역을 알려주세요';
const _body = '맞춤 일자리 추천에 활용됩니다.\n나중에 MY에서 언제든지 변경할 수 있어요.';
const _hint = '지역 선택하기';
const _sejong = '세종특별자치시';
const _save = '저장하고 시작하기';
const _logout = '로그아웃';
const _marker = '🔄 USER homeRegion 없음 → 복구 화면 (강제)';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '609';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du609bmain-tb' && _env['DU_BEFORE_OBSERVE'] == '609') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du609bmain-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

String _f1(double v) => v.toStringAsFixed(1);

/// [DU609b] 지역 복구 사례 — 틀(실패 보관 · 정리 · 집계 · R/D 줄)은 DU605b `_helpCase` 꼴 · host 와 선택 조작은 DU424 :378–:413.
Future<void> _regionCase(WidgetTester t, _V v, _Case c, String tok) async {
  final prevOnError = FlutterError.onError;
  final origPrint = debugPrint;
  addTearDown(() {
    FlutterError.onError = prevOnError;
    debugPrint = origPrint;
  });
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D609 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
  final seen = _DSeen();
  void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
  final screen = Offset.zero & Size(v.w, v.h);

  Object? failure;
  StackTrace? failureSt;
  var shots = 0;
  var raw = '';
  var marker = 0;
  try {
    await t.runAsync(_loadFonts);
    debugPrint = (String? m, {int? wrapWidth}) {
      origPrint(m, wrapWidth: wrapWidth);
      if (m == _marker) marker++;
    };
    FlutterError.onError = seen.add;
    final key = GlobalKey();
    final prov = _Prov()
      ..debugSetCurrentUser(UserModel(
          uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
          accountStatus: 'active', passVerifiedAt: DateTime.utc(2026, 10, 1)));
    final theme = ThemeProvider()..setRole('USER');
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: prov),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
            home: const AuthWrapper()),
      ),
    ));
    Finder titleF() => find.byWidgetPredicate(
        (w) => w is RichText && TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) == _title,
        skipOffstage: false);
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 16));
      if (titleF().evaluate().isNotEmpty) break;
    }
    final nScr = titleF().evaluate().length;
    _out('D609 $tok att scr n=$nScr');
    need('복구 화면 도달(제목 1)', nScr == 1, '개수 $nScr · 표지 $marker');
    final host = find.byType(Scaffold).first;
    Finder richOf(String s) => find.descendant(
        of: host,
        matching: find.byWidgetPredicate(
            (w) => w is RichText && TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) == s,
            skipOffstage: false),
        skipOffstage: false);

    Future<void> shot(String id, String state) async {
      _out('D609 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    // SEL — 실제 시트에서 고른다(DU424 :403–:413 · 탭 = ensureVisible 한 같은 글).
    var cardText = _hint;
    if (c.pick) {
      final hf = richOf(_hint);
      need('힌트 1', hf.evaluate().length == 1, 'n=${hf.evaluate().length}');
      await t.ensureVisible(hf);
      await t.pump();
      await t.tap(hf);
      await t.pumpAndSettle();
      final item = find.byWidgetPredicate(
          (w) => w is RichText && TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) == _sejong);
      await t.scrollUntilVisible(item, 120, scrollable: find.byType(Scrollable).last);
      await t.pumpAndSettle();
      need('시트 세종특별자치시 항목 1', item.evaluate().length == 1, 'n=${item.evaluate().length}');
      await t.tap(item);
      await t.pumpAndSettle();
      cardText = '$_sejong $_sejong';
      need('선택 반영(카드 글 1)', richOf(cardText).evaluate().length == 1, 'n=${richOf(cardText).evaluate().length}');
    }

    // 위 → 아래 순서로 잰다(SingleChildScrollView · 지연 생성 0 — 그래도 찾기는 skipOffstage: false).
    final ttl = await _seeText(t, host, (s) => s == _title, screen);
    _out('D609 $tok att ttl n=${ttl.n} name=${ttl.name} full=${ttl.full} brk=${ttl.brk} lines=${ttl.lines} vis=${ttl.vis}');
    raw = '$raw | ttl $ttl';
    final body = await _seeText(t, host, (s) => s == _body, screen);
    _out('D609 $tok att body n=${body.n} name=${body.name} full=${body.full} brk=${body.brk} lines=${body.lines} vis=${body.vis}');
    raw = '$raw | body $body';
    final reg = await _seeText(t, host, (s) => s == cardText, screen);
    final card = _cardObs(t, host, cardText, v.w);
    _out('D609 $tok att reg n=${reg.n} name=${reg.name} full=${reg.full} brk=${reg.brk} lines=${reg.lines} vis=${reg.vis} zw=${card.zw} ch=${_f1(card.ch)}');
    _out('D609 $tok att gut l=${_f1(card.l)} r=${_f1(card.r)}');
    raw = '$raw | reg $reg card $card';
    // 좌우 여백 — before = 지금 A 고정 24 · strict = ResponsiveHelper.screenPadding(폭 < 360 → 16 · < 600 → 24).
    final wantG = _before ? 24.0 : (v.w < 360 ? 16.0 : 24.0);
    need('카드 1', card.n == 1, 'n=${card.n}');
    need('카드 좌우 여백 = 기대 $wantG', (card.l - wantG).abs() <= 0.5 && (card.r - wantG).abs() <= 0.5, '${_f1(card.l)}/${_f1(card.r)}');
    await shot('1card', 'card-visible');
    final sav = await _seeText(t, host, (s) => s == _save, screen);
    _out('D609 $tok att sav n=${sav.n} name=${sav.name} full=${sav.full} brk=${sav.brk} lines=${sav.lines} vis=${sav.vis}');
    raw = '$raw | sav $sav';
    final lo = richOf(_logout);
    need('로그아웃 1', lo.evaluate().length == 1, 'n=${lo.evaluate().length}');
    await Scrollable.ensureVisible(lo.evaluate().first, alignment: 1.0);
    for (var m = 0; m < 4; m++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    // [점검표 A8] 화면에 그려진 단추 채움(기록) — 저장(ElevatedButton · theme.primaryColor) · 로그아웃(TextButton · 채움 없음).
    final f = _fills(t);
    _out('D609 $tok att fills n=${f.n} brand=${f.brand} err=${f.err} none=${f.none} other=${f.other} list=${f.list}');
    raw = '$raw | fills $f';
    await shot('2end', 'end-visible');
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
    debugPrint = origPrint;
  }

  // 성공 · 실패 공통 정리 — DU605b _helpCase 와 같다.
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
  _out('R609 $tok raw m64=${_enc(raw)} ovf64=${_enc(seen.overflows.join('\n----\n'))} fw64=${_enc(seen.other.join('\n----\n'))} '
      'marker=$marker cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D609 $tok att fw n=$nFw');
  _out('D609 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');
  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  expect(shots == c.shots, isTrue, reason: '$tok 캡처 수 = 선언 shots $shots want ${c.shots}');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'onboarding_completed_u1': true}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S609RC-${v.id}-${c.id} 지역 복구 카드 좌우 여백(장부 142)', (t) async {
        final tok = 'S609RC-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _regionCase(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
