// ignore_for_file: depend_on_referenced_packages
// [DU588c · 파일 단위 장부 셀 · S052 all_users_screen 잔여] 장부 133 잔여 3문장(판정174 §3 :32) + F174-S052-DIALOG-REACH 관측(판정174 §2 :22).
//   바뀐 것: 목록 실패 제목 '사용자 목록을 불러오지 못했어요' · 실패 부제 '해당하는 사용자가 없다는 뜻은 아니에요.' · 빈 목록 제목 '해당하는 사용자가 없어요'
//     (오류/빈 목록 분기 · '다시 시도' · 데이터 그대로). before = 지금 A(all_users_screen 17cc06db = DU588b 후보) 문장 · strict = 후보 문장.
//   관측(기록만 · 단언 0): 노쇼 제한 해제 확인창 · 기한 없는 제한 해제 사유 창의 긴 본문 — 같은 본문 scroll owner 를 실제 끌어 말단 · 모든 줄 연속 도달
//     (동의 g6 du1 _lineRects · read() · 가시 구간 셈) · 최종 '해제' 받는 자리(DU562 r2 _btnReach — ensureVisible 대상 = 잰 InkWell · 48 · hit · 칸 안).
//   하네스 = DU588b 시험(86265c94 · DONE 5/5) 블록 그대로(DU571 r2 측정 블록 · max 판 _fullShown · _seeText · _btnLine · _bringBuilt · _DWire · setUpAll ·
//     DU575 색 도우미) — prep/mk_test.py 단언. 쓰기 0 · CF 0 · HTTP 0 · 누르기 = 진입(목록 행 · 행동 버튼) · '다시 시도' · '취소'뿐(최종 실행 버튼 0).
//   기본 skip — TB before/du588crs-tb/DU_BEFORE_OBSERVE=588 · TA after/du588crs-ta/없음.

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

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/all_users_reads.dart';
import 'package:ALfit/screens/super_admin/all_users_screen.dart';
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

/// CF Pigeon 채널 — RG 시험(offer_workdetail_roster · noshow_contract_dialog_gate)과 같은 'unavailable' 응답을 주고 센다.
const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// [DU526 과 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du588.fake.auth.';
const _authListeners = ['registerIdTokenListener', 'registerAuthStateListener'];

/// 원래 경로로 보내는 Flutter 기반 채널과 이유.
const _frameworkAllow = <String, String>{
  'flutter/assets': 'AssetBundle(아이콘 글꼴 · 이미지 매니페스트) 읽기',
  'flutter/platform': 'MaterialApp Title · SystemSound/Haptic(InkWell 탭 피드백)',
  'flutter/navigation': '루트 Navigator 경로 보고',
  'flutter/mousecursor': 'MouseRegion 커서 갱신(시험 포인터)',
  'flutter/restoration': 'RootRestorationScope 상태 복원 조회',
  'flutter/keyboard': 'HardwareKeyboard 상태 동기화',
  'flutter/accessibility': '의미 트리/알림 전달',
};

/// 모든 플랫폼 메시지 관찰 — 기반 채널은 원래 경로 · Auth 두 리스너는 setUpAll 모의 · CF 는 'unavailable' 응답 ·
///   그 밖은 이름을 기록하고 응답 null(플러그인 없음과 같은 결과). 예외를 삼키지 않는다 — 수는 줄로 남긴다.
class _Wire {
  final unexpected = <String>[];
  final cf = <String>[];
  final auth = <String>[];

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (channel == _cfChannel) {
      cf.add(channel);
      return Future<ByteData?>.value(const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'test harness', null]));
    }
    for (final name in _authListeners) {
      if (channel == '$_authBase$name' || channel == '$_authFake$name') {
        auth.add(name);
        return handler?.call(message);
      }
    }
    if (_frameworkAllow.containsKey(channel)) {
      return handler != null ? handler(message) : m.delegate.send(channel, message);
    }
    unexpected.add(channel);
    return null;
  }
}

/// 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다.
class _NoHttp extends HttpOverrides {
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    throw const SocketException('UXW1 관측 — 외부 HTTP 차단');
  }
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

/// 그려진 문단의 줄 수 — 글자 자리(box)의 서로 다른 top 개수.
int _lineCount(RenderParagraph rp) {
  final n = rp.text.toPlainText(includeSemanticsLabels: false).length;
  final tops = <int>{};
  for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: n))) {
    tops.add(b.top.round());
  }
  return tops.length;
}

/// [동의 g6 du1 · 판정174 §6 기존 du1 증명 그대로] 아래 _sweep 이 쓴다.
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

typedef _V = ({String id, double w, double h, double s});

const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0), (id: 'N', w: 320.0, h: 640.0, s: 1.0)];

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

/// 모든 플랫폼 메시지 관찰 — 허용 Flutter 기반 채널은 원래 경로(센다) · Auth 정확 허용은 setUpAll 모의로(센다) ·
///   CF · 그 밖(Firestore · 저장소 · 허용 밖 flutter/*)은 이름을 기록하고 막는다(응답 null) · **막는 순간 tripped**(후속 UI 조작 중단).
class _DWire {
  final unexpected = <String>[];
  final cf = <String>[];
  final framework = <String, int>{};
  final auth = <String>[];
  var tripped = false;

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (channel == _cfChannel) {
      cf.add(channel);
      tripped = true;
      return null;
    }
    for (final name in _authListeners) {
      if (channel == '$_authBase$name') {
        auth.add('register:$name');
        return handler?.call(message);
      }
      if (channel == '$_authFake$name') {
        String method;
        try {
          method = const StandardMethodCodec().decodeMethodCall(message).method;
        } catch (_) {
          method = '?';
        }
        if (method == 'listen' || method == 'cancel') {
          auth.add('$method:$name');
          return handler?.call(message);
        }
        unexpected.add('$channel#$method');
        tripped = true;
        return null;
      }
    }
    // [DU581] 기반 채널 허용 = 'flutter/' 접두 전부(DU514 r4 TA 판 — 이 화면 사유 창 입력칸 autofocus 가 textinput 등을 쓴다 · 이름별 수는 raw).
    if (channel.startsWith('flutter/')) {
      framework.update(channel, (x) => x + 1, ifAbsent: () => 1);
      return handler != null ? handler(message) : m.delegate.send(channel, message);
    }
    unexpected.add(channel);
    tripped = true;
    return null;
  }
}

/// [F120-3] 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다(끝에 0 단언).
class _DNoHttp extends HttpOverrides {
  _DNoHttp(this.wire);
  final _DWire wire;
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    wire.tripped = true;
    throw const SocketException('NCB-12O 관측 — 외부 HTTP 차단');
  }
}

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

typedef _BtnObs = ({int n, bool dis, bool m48, bool vis, bool hit});

/// [DU571] 그 글이 든 버튼 — 그린 글이 [match] 에 맞고 ButtonStyleButton 조상이 있는 RichText 가 정확히 하나일 때 **그 버튼 한 요소로**
///   비활성(onPressed null · 행동 불변) · 받는 자리(48 기록) · 화면 ∩ 스크롤 칸 안 · 중심 hit 를 잰다(ensureVisible 0 · 누르지 않는다).
_BtnObs _btnLine(WidgetTester t, Finder host, bool Function(String s) match, Rect screen) {
  final btn = find.byWidgetPredicate((w) => w is ButtonStyleButton, skipOffstage: false);
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .where((e) {
        final ef = find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
        return find.ancestor(of: ef, matching: btn).evaluate().isNotEmpty;
      })
      .toList();
  if (es.length != 1) return (n: es.length, dis: false, m48: false, vis: false, hit: false);
  final el = es.first;
  final tf = find.byElementPredicate((x) => identical(x, el), skipOffstage: false);
  final bf = find.ancestor(of: tf, matching: btn).first;
  final r = t.getRect(bf);
  return (
    n: 1,
    dis: (t.widget(bf) as ButtonStyleButton).onPressed == null,
    m48: r.width >= 48 - 0.01 && r.height >= 48 - 0.01,
    vis: _inside(r, _area(bf, screen)),
    hit: _hitWithin(t, bf, r.center),
  );
}

/// 최고관리자 대역(RR57 · RM58 · DU514 와 같은 꼴 · 실제 권한 검증 아님).
class _Super extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'sa1', username: 'sa1', name: '운영자', email: 'sa@alfit.local', role: UserRole.SUPER_ADMIN, createdAt: DateTime(2026, 1, 1));
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

/// [DU514 과 같다] 그린 글(표시 제어 문자 제외).
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

/// [DU581 r2 · 판정167 시험 STOP 수리] 지연 생성 목록(사용자 목록 · 상세 시트 ListView) 안의 글이 아직 안 만들어졌을 때만
///   그 host 의 세로 목록을 끌어 만든다(누르기 아님 · 찾는 식 = _seeText 와 같은 _plainOf · 단언 없음 — 개수 판정은 _seeText 뒤 need).
Future<void> _bringBuilt(WidgetTester t, Finder host, String? want) async {
  final tf = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == want), skipOffstage: false);
  if (tf.evaluate().isNotEmpty) return;
  final sc = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down), skipOffstage: false);
  await t.scrollUntilVisible(tf, 120, scrollable: sc.first, maxScrolls: 40);
  await t.pump(const Duration(milliseconds: 50));
}

/// [DU562 r2 · DONE 5/5 그대로] Text 찾기(그린 글 = 표시 제어 문자를 뺀 원문) — _btnReach 가 쓴다.
Finder _txt(Finder scope, String want, {bool onstage = true}) => find.descendant(
    of: scope,
    matching: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? w.textSpan?.toPlainText() ?? '') == want),
    skipOffstage: onstage);

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

/// callable 응답 모양 그대로(RR57 · RM58 · DU514) — Timestamp 는 {_seconds, _nanoseconds}.
Map<String, int> _ts(DateTime t) => {'_seconds': t.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

/// 대역 끝 시각 — 2030-12-31 23:59 KST(늘 미래) · 기한 없음 = 서버 경계 KST 9999-01-01 00:00(all_users_screen _isPermanentInstant 와 같은 값 · DU571 과 같은 상수).
final DateTime _untilTime = DateTime.utc(2030, 12, 31, 14, 59);
final DateTime _untilPerm = DateTime.utc(9998, 12, 31, 15);

/// 세 사람 — 차단 + 노쇼 자동 제한(김지원) · 제한 없음(이정상) · 기한 없는 이용 제한(박기한). 사례마다 목록 둘.
Map<String, dynamic> _black() => {'uid': 'u1', 'username': 'worker01', 'name': '김지원', 'email': 'u1@alfit.local', 'role': 'USER',
      'createdAt': _ts(DateTime(2026, 1, 1)), 'noShowCount': 3, 'recentNoShowCount': 3, 'isBlacklisted': true, 'blacklistReason': '반복 노쇼',
      'restrictedUntil': _ts(_untilTime), 'restrictionSource': 'auto', 'restrictionParts': {'auto': _ts(_untilTime)}};
Map<String, dynamic> _normal() => {'uid': 'u2', 'username': 'worker02', 'name': '이정상', 'email': 'u2@alfit.local', 'role': 'USER',
      'createdAt': _ts(DateTime(2026, 2, 1))};
Map<String, dynamic> _perm() => {'uid': 'u3', 'username': 'worker03', 'name': '박기한', 'email': 'u3@alfit.local', 'role': 'USER',
      'createdAt': _ts(DateTime(2026, 3, 1)), 'restrictedUntil': _ts(_untilPerm), 'restrictionSource': 'permanent',
      'restrictionParts': {'base': _ts(_untilPerm), 'baseSource': 'permanent'}};

/// [DU581] 그 글이 든 버튼 한 요소(_btnLine 과 같은 찾기)를 **버튼 ∩ 보이는 칸 중심**으로 실제로 누른다(DU514 ⑤⑦ 진입 탭과 같은 점 · ensureVisible 0).
Future<bool> _tapBtn(WidgetTester t, Finder host, bool Function(String s) match, Rect screen) async {
  final btn = find.byWidgetPredicate((w) => w is ButtonStyleButton, skipOffstage: false);
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .where((e) {
        final ef = find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
        return find.ancestor(of: ef, matching: btn).evaluate().isNotEmpty;
      })
      .toList();
  if (es.length != 1) return false;
  final el = es.first;
  final tf = find.byElementPredicate((x) => identical(x, el), skipOffstage: false);
  final bf = find.ancestor(of: tf, matching: btn).first;
  final r = t.getRect(bf).intersect(_area(bf, screen));
  if (r.width <= 0 || r.height <= 0) return false;
  await t.tapAt(r.center);
  return true;
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

String _hex6(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

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

/// [DU588b · DU575 _paintOf 틀] 창 안 최종 단추 글([go]) 하나 — 그 글의 글자색 · 그 글 뒤 실제 바탕(_bgOf = 단추 면) · 대비 · brand/errorDark 채움 · 흰 글 ·
///   머리 아이콘(창 안 맨 위 Icon)이 brand 인가. 읽기만(누르지 않는다).
typedef _PaintObs = ({int n, String fill, String fg, String cr, bool ok45, bool brand, bool err, bool white, bool hic});

_PaintObs _paintOf(WidgetTester t, Finder host, String go) {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == go)
      .toList();
  final icons = find.descendant(of: host, matching: find.byType(Icon), skipOffstage: false).evaluate().toList()
    ..sort((x, y) => t.getRect(find.byElementPredicate((q) => identical(q, x), skipOffstage: false)).top
        .compareTo(t.getRect(find.byElementPredicate((q) => identical(q, y), skipOffstage: false)).top));
  final Color? ic = icons.isEmpty ? null : (icons.first.widget as Icon).color;
  final hic = ic != null && ic.toARGB32() == AppColors.brand.toARGB32();
  if (es.length != 1) return (n: es.length, fill: '-', fg: '-', cr: '0.00', ok45: false, brand: false, err: false, white: false, hic: hic);
  final el = es.first;
  final Color? fg = (el.widget as RichText).text.style?.color;
  final bg = _bgOf(el);
  final cr = fg == null ? 0.0 : _contrast(fg, bg);
  return (
    n: 1,
    fill: _hex6(bg),
    fg: fg == null ? '-' : _hex6(fg),
    cr: cr.toStringAsFixed(2),
    ok45: cr >= 4.5,
    brand: bg.toARGB32() == AppColors.brand.toARGB32(),
    err: bg.toARGB32() == AppColors.errorDark.toARGB32(),
    white: fg != null && fg.toARGB32() == Colors.white.toARGB32(),
    hic: hic,
  );
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
      rows.add('$lab:${_hex6(fc)}');
    }
  }
  return (n: rows.length, brand: b, err: er, none: no, other: ot, list: _enc(rows.join('|')));
}

/// [DU588c] 사례 — ERR = 목록 읽기 실패(제목 · 부제 · '대상 없음' 문장 0 · '다시 시도' 받는 자리 → 실제 탭 → 다시 읽기 1번 더 · 실패 그대로) ·
///   EMPTY = 정말 0명(빈 목록 제목 · 실패 제목 0) · RESET = 노쇼 제한 해제 확인창 · PERM = 기한 없는 제한 해제 사유 창(긴 본문 도달 · 최종 '해제' 받는 자리 관측).
typedef _Case = ({String id, int shots, String who});
const _cases = <_Case>[(id: 'ERR', shots: 1, who: '-'), (id: 'EMPTY', shots: 1, who: '-'), (id: 'RESET', shots: 2, who: '김지원'), (id: 'PERM', shots: 2, who: '박기한')];

/// 사례별 읽기(callable 응답 모양 · CF 0) — 부른 횟수를 센다(ERR '다시 시도' 가 다시 읽는지).
var _calls = 0;

Future<List<Object?>> _read(_Case c) async {
  _calls++;
  if (c.id == 'ERR') throw Exception('unavailable');
  return switch (c.id) {
    'EMPTY' => <Object?>[],
    'PERM' => [_normal(), _perm()],
    _ => [_black(), _normal()],
  };
}

/// 이 셀이 바꾸는 글 — after = 후보 문장(prep/mk_cand.py 와 같은 값 · 판정174 §3 :32 원문) · before = 지금 A 문장.
///   ERR.eno · EMPTY.emf 는 '그 상태에 없어야 하는' 반대쪽 문장(개수 0). 해제 창 4 문장은 이 셀이 바꾸지 않는다(DU588b after = 지금 A · 두 모드 같은 글).
const _after = <String, String>{
  'ERR.ett': '사용자 목록을 불러오지 못했어요',
  'ERR.ets': '해당하는 사용자가 없다는 뜻은 아니에요.',
  'ERR.eno': '해당하는 사용자가 없어요',
  'EMPTY.emt': '해당하는 사용자가 없어요',
  'EMPTY.emf': '사용자 목록을 불러오지 못했어요',
  'RESET.act': '노쇼 제한 해제 (기록 초기화)',
  'RESET.dbd': '김지원 · @worker01 · 지원자\n\n풀리는 것: 노쇼 자동 제한(2030년 12월 31일 오후 11시 59분까지)\n노쇼 기록 초기화: 3회(최근 90일 3회) → 0회\n남는 것: 계정 이용 차단 — 이 버튼으로는 풀리지 않아요\n해제 뒤에도 로그인·지원이 제한돼요.',
  'PERM.act': '이용 제한(기한 없음) 해제',
  'PERM.dbd': '해제할 것: 이용 제한(기한 없음)\n해제 뒤 바로 로그인·지원할 수 있어요.\n사유는 감사 기록에만 남고 이 사용자에게는 보이지 않아요.',
};
const _beforeTx = <String, String>{
  'ERR.ett': '사용자 목록을 불러오지 못했습니다',
  'ERR.ets': '해당하는 사용자가 없다는 뜻이 아닙니다.',
  'ERR.eno': '해당하는 사용자가 없습니다',
  'EMPTY.emt': '해당하는 사용자가 없습니다',
  'EMPTY.emf': '사용자 목록을 불러오지 못했습니다',
  'RESET.act': '노쇼 제한 해제 (기록 초기화)',
  'RESET.dbd': '김지원 · @worker01 · 지원자\n\n풀리는 것: 노쇼 자동 제한(2030년 12월 31일 오후 11시 59분까지)\n노쇼 기록 초기화: 3회(최근 90일 3회) → 0회\n남는 것: 계정 이용 차단 — 이 버튼으로는 풀리지 않아요\n해제 뒤에도 로그인·지원이 제한돼요.',
  'PERM.act': '이용 제한(기한 없음) 해제',
  'PERM.dbd': '해제할 것: 이용 제한(기한 없음)\n해제 뒤 바로 로그인·지원할 수 있어요.\n사유는 감사 기록에만 남고 이 사용자에게는 보이지 않아요.',
};
const _retry = '다시 시도';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '588';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du588crs-tb' && _env['DU_BEFORE_OBSERVE'] == '588') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du588crs-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// [DU588b 와 같다] 사례의 바뀐 글 — before = 지금 A 문장 · strict = 후보 문장.
String? _tx(_Case c, String k) => (_before ? _beforeTx : _after)['${c.id}.$k'];

/// [DU588c · 판정174 §2 :22 F174-S052-DIALOG-REACH · 관측 = 기록만(단언 0)] 창 본문 문단 RichText [tf] 하나 — 말단 · 모든 줄 연속 도달.
///   동의 g6 du1(:218–:287 · 판정174 §6 '기존 du1 의 모든 줄 도달 + 문단 좌표 가시 구간 연속성 증명')의 read()(줄마다 온전히 보인 프레임 · 문단 ≤ 칸이면
///   문단 전체 한 프레임 · 가시 구간 [vTop, vBot] 모으기 · 구멍 셈)와 걸음(stepPx · 터치 슬롭 24 · 놓기 전 멈춤)을 옮기고, 가로 잘림은 단언 대신 센다(hcut).
///   끌기 방향만 반대 — _seeText 의 ensureVisible 로 문단 윗끝이 칸 윗끝에 온 자리에서 같은 본문 scroll owner 를 실제 끌어(손가락 위 = 내용 위) 끝(max)까지 보낸다.
///   손가락 시작점 = 문단 ∩ 칸 가운데(사유 창 입력칸 위에서 끌지 않는다). 칸에 다 들어가면(max 0) 끌지 않고 한 프레임만 읽는다.
typedef _SwObs = ({int n, int lines, int seen, bool top, bool last, bool whole, bool need, bool cont, int hcut, bool fit, bool end, bool moved});

Future<_SwObs> _sweep(WidgetTester t, Finder tf, Rect screen) async {
  final n = tf.evaluate().length;
  if (n != 1) return (n: n, lines: 0, seen: 0, top: false, last: false, whole: false, need: false, cont: false, hcut: 0, fit: false, end: false, moved: false);
  final swRp = t.renderObject<RenderParagraph>(tf);
  final lines = _lineRects(swRp);
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
  );
}

/// [DU588c] 운영자 사례 — DU588b `_opsCase` 의 틀(guard · 캡처 · 정리 · 집계 블록 그대로)에 사례별 측정만 바꿨다.
///   ERR · EMPTY = 목록 화면에서 끝(ERR 은 '다시 시도' 실제 탭까지) · RESET · PERM = 목록 행 실제 탭 → 시트 → 행동 진입 → 창 → 도달 관측 → '취소'(최종 실행 버튼 0).
Future<void> _opsCase(WidgetTester t, _V v, _Case c, String tok) async {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final wire = _DWire();
  final net = _DNoHttp(wire);
  final prevAll = messenger.allMessagesHandler;
  final prevHttp = HttpOverrides.current;
  final prevOnError = FlutterError.onError;
  messenger.allMessagesHandler = (channel, handler, message) => wire.route(messenger, channel, handler, message);
  HttpOverrides.global = net;
  addTearDown(() {
    messenger.allMessagesHandler = prevAll;
    HttpOverrides.global = prevHttp;
    FlutterError.onError = prevOnError;
  });
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D588 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
  final seen = _DSeen();
  void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
  final screen = Offset.zero & Size(v.w, v.h);

  Object? failure;
  StackTrace? failureSt;
  var shots = 0;
  var raw = '';
  try {
    FlutterError.onError = seen.add;
    _calls = 0;
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: ChangeNotifierProvider<UserProvider>(
        create: (_) => _Super(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.superAdminTheme,
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
          home: AllUsersScreen(reads: AllUsersReads(allUsersRaw: () => _read(c))),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final appF = find.byType(AllUsersScreen);
    final nScr = appF.evaluate().length;
    _out('D588 $tok att scr n=$nScr');
    need('화면 1', nScr == 1, '개수 $nScr');
    Future<void> shot(String id, String state) async {
      _out('D588 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    // ① 실패 상태(ERR) — 바뀐 글 하나를 넣고 같은 요소로 잰다(같은 host 찾기/측정 앞 지연 생성 대비 · A4) · 반대쪽 문장 0 · '다시 시도' 받는 자리 → 실제 탭.
    if (c.id == 'ERR') {
      await _bringBuilt(t, appF, _tx(c, 'ett'));
      final ett = await _seeText(t, appF, (s) => s == _tx(c, 'ett'), screen);
      _out('D588 $tok att ett n=${ett.n} name=${ett.name} full=${ett.full} brk=${ett.brk} lines=${ett.lines} vis=${ett.vis}');
      need('실패 제목 1', ett.n == 1, '개수 ${ett.n}');
      await _bringBuilt(t, appF, _tx(c, 'ets'));
      final ets = await _seeText(t, appF, (s) => s == _tx(c, 'ets'), screen);
      _out('D588 $tok att ets n=${ets.n} name=${ets.name} full=${ets.full} brk=${ets.brk} lines=${ets.lines} vis=${ets.vis}');
      need('실패 부제 1', ets.n == 1, '개수 ${ets.n}');
      final eno = find.descendant(of: appF, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == _tx(c, 'eno')), skipOffstage: false)
          .evaluate()
          .length;
      _out('D588 $tok att eno n=$eno');
      need('빈 목록 제목 0', eno == 0, '개수 $eno');
      await _bringBuilt(t, appF, _retry);
      final rtbF = find.ancestor(
          of: find.descendant(of: appF, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == _retry), skipOffstage: false),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton, skipOffstage: false));
      final nRtb = rtbF.evaluate().length;
      need('다시 시도 버튼 1', nRtb == 1, '개수 $nRtb');
      await t.ensureVisible(rtbF.first); // A1 — 넣는 대상 = 아래 _btnLine 이 재는 ButtonStyleButton 한 요소
      for (var m = 0; m < 4; m++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      final rtb = _btnLine(t, appF, (s) => s == _retry, screen);
      _out('D588 $tok att rtb n=${rtb.n} dis=${rtb.dis} m48=${rtb.m48} vis=${rtb.vis} hit=${rtb.hit}');
      need('다시 시도 1 · 활성', rtb.n == 1 && !rtb.dis, '개수 ${rtb.n} 비활성 ${rtb.dis}');
      final fl = _fills(t);
      _out('D588 $tok att fills n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
      await shot('0err', 'load-error-state');
      raw += 'ett $ett ets $ets eno $eno rtb $rtb fills $fl ';
      final c0 = _calls;
      final tapped = await _tapBtn(t, appF, (s) => s == _retry, screen);
      need('다시 시도 탭', tapped, '버튼 ∩ 보이는 칸 없음');
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final c1 = _calls;
      final again = find.descendant(of: appF, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == _tx(c, 'ett')), skipOffstage: false)
          .evaluate()
          .length;
      _out('D588 $tok att rty c0=$c0 c1=$c1 n=$again');
      need('다시 읽기 1번 더 · 실패 제목 그대로', c1 == c0 + 1 && again == 1, '읽기 $c0 → $c1 · 제목 $again');
      raw += 'rty $c0 $c1 $again ';
    }

    // ② 빈 목록(EMPTY) — 빈 목록 제목 하나 · 실패 제목 0.
    if (c.id == 'EMPTY') {
      await _bringBuilt(t, appF, _tx(c, 'emt'));
      final emt = await _seeText(t, appF, (s) => s == _tx(c, 'emt'), screen);
      _out('D588 $tok att emt n=${emt.n} name=${emt.name} full=${emt.full} brk=${emt.brk} lines=${emt.lines} vis=${emt.vis}');
      need('빈 목록 제목 1', emt.n == 1, '개수 ${emt.n}');
      final emf = find.descendant(of: appF, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == _tx(c, 'emf')), skipOffstage: false)
          .evaluate()
          .length;
      _out('D588 $tok att emf n=$emf');
      need('실패 제목 0', emf == 0, '개수 $emf');
      final fl = _fills(t);
      _out('D588 $tok att fills n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
      await shot('0empty', 'empty-list-state');
      raw += 'emt $emt emf $emf fills $fl ';
    }

    // ③ 해제 창(RESET · PERM) — DU588b ②④ 경로(목록 행 실제 탭 → 시트 → 행동 진입 → 창 · 취소만) + F174 관측(본문 말단 · 모든 줄 연속 도달 · 최종 '해제' 받는 자리).
    if (c.id == 'RESET' || c.id == 'PERM') {
      // ② 목록 행 실제 탭 → 상세 시트(DU581 r3 ② · DU514 ① 경로 · 행 InkWell ∩ 보이는 칸 중심).
      final listF = find.descendant(
          of: appF, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down), skipOffstage: false);
      final rowNameF = find.descendant(of: appF, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == c.who), skipOffstage: false);
      await t.scrollUntilVisible(rowNameF, 120, scrollable: listF.first, maxScrolls: 40);
      await t.pump(const Duration(milliseconds: 50));
      final rowCardF = find.ancestor(of: rowNameF, matching: find.byType(Card));
      final rowInkF = find.descendant(of: rowCardF, matching: find.byType(InkWell), skipOffstage: false);
      final nRowInk = rowInkF.evaluate().length;
      need('목록 행 InkWell 1', nRowInk == 1, '개수 $nRowInk');
      final rowPt = t.getRect(rowInkF).intersect(t.getRect(listF.first).intersect(screen)).center;
      await t.tapAt(rowPt);
      await t.pump();
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final sheetF = find.byType(BottomSheet);
      final nSheet = sheetF.evaluate().length;
      _out('D588 $tok att sheet n=$nSheet');
      need('상세 시트 1', nSheet == 1, '개수 $nSheet');
      await _bringBuilt(t, sheetF, _tx(c, 'act'));
      final act = await _seeText(t, sheetF, (s) => s == _tx(c, 'act'), screen);
      _out('D588 $tok att act n=${act.n} name=${act.name} full=${act.full} brk=${act.brk} lines=${act.lines} vis=${act.vis}');
      need('행동 이름 1', act.n == 1, '개수 ${act.n}');
      final actb = _btnLine(t, sheetF, (s) => s == _tx(c, 'act'), screen);
      _out('D588 $tok att actb n=${actb.n} dis=${actb.dis} m48=${actb.m48} vis=${actb.vis} hit=${actb.hit}');
      need('행동 버튼 1 · 활성', actb.n == 1 && !actb.dis, '개수 ${actb.n} 비활성 ${actb.dis}');
      final tapped = await _tapBtn(t, sheetF, (s) => s == _tx(c, 'act'), screen);
      need('행동 진입 탭', tapped, '버튼 ∩ 보이는 칸 없음');
      await t.pump();
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final dlgF = find.byType(Dialog);
      final nDlg = dlgF.evaluate().length;
      _out('D588 $tok att dlg n=$nDlg');
      need('창 1', nDlg == 1, '개수 $nDlg');
      final dbd = await _seeText(t, dlgF, (s) => s == _tx(c, 'dbd'), screen);
      _out('D588 $tok att dbd n=${dbd.n} name=${dbd.name} full=${dbd.full} brk=${dbd.brk} lines=${dbd.lines} vis=${dbd.vis}');
      need('창 본문 1', dbd.n == 1, '개수 ${dbd.n}');
      final pt = _paintOf(t, dlgF, '해제');
      _out('D588 $tok att paint n=${pt.n} fill=${pt.fill} fg=${pt.fg} cr=${pt.cr} ok45=${pt.ok45} brand=${pt.brand} err=${pt.err} white=${pt.white} hic=${pt.hic}');
      need('최종 단추 1', pt.n == 1, '개수 ${pt.n}');
      final fl = _fills(t);
      _out('D588 $tok att fills n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
      await shot('3dialog', 'confirm-or-reason-dialog');
      final dbdF = find.descendant(of: dlgF, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == _tx(c, 'dbd')), skipOffstage: false);
      final rch = await _sweep(t, dbdF, screen);
      _out('D588 $tok att rch n=${rch.n} lines=${rch.lines} seen=${rch.seen} top=${rch.top} last=${rch.last} whole=${rch.whole} need=${rch.need} cont=${rch.cont} hcut=${rch.hcut} fit=${rch.fit} end=${rch.end} moved=${rch.moved}');
      need('창 본문 문단 1(도달 관측)', rch.n == 1, '개수 ${rch.n}');
      final fin = await _btnReach(t, dlgF, '해제', screen);
      _out('D588 $tok att fin n=${fin.n} m48=${fin.m48} vis=${fin.vis} hit=${fin.hit}');
      need('최종 해제 1', fin.n == 1, '개수 ${fin.n}');
      await shot('4end', 'dialog-body-end-final-button');
      raw += 'act $act actb $actb dbd $dbd paint $pt fills $fl rch $rch fin $fin ';

      // '취소' 실제 탭 → 창 닫힘(시트는 진입 때 이미 닫힘 · 쓰기 0).
      final cancelF = find.descendant(of: dlgF, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == '취소'));
      final nCancel = cancelF.evaluate().length;
      need('취소 1', nCancel == 1, '개수 $nCancel');
      await t.tap(cancelF);
      await t.pump();
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final closed = find.byType(Dialog).evaluate().isEmpty && find.byType(BottomSheet).evaluate().isEmpty;
      _out('D588 $tok att cls n=$nCancel closed=$closed');
      need('창 · 시트 닫힘', closed, '');
    }
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // 성공 · 실패 공통 정리 — DU535 _dayCase ⑤ 와 같다.
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
  final nUnexp = wire.unexpected.length;
  final nCf = wire.cf.length;
  final nHttp = net.tries.length;
  final unText = wire.unexpected.join(' | ');
  _out('D588 $tok att wire cf=$nCf unexpected=$nUnexp http=$nHttp');
  messenger.allMessagesHandler = prevAll;
  HttpOverrides.global = prevHttp;
  final exc = t.takeException();
  if (exc != null && failure == null) {
    failure = exc;
    failureSt = StackTrace.current;
  }
  final nOvf = seen.overflows.length;
  final nFw = seen.other.length;
  _out('R588 $tok raw m64=${_enc(raw)} ovf64=${_enc(seen.overflows.join('\n----\n'))} fw64=${_enc(seen.other.join('\n----\n'))} '
      'un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D588 $tok att fw n=$nFw');
  _out('D588 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');
  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  expect(shots == c.shots, isTrue, reason: '$tok 캡처 수 = 선언 shots $shots want ${c.shots}');
}

void main() {
  setUpAll(() async {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final wire = _Wire();
    final net = _NoHttp();
    final prevAll = m.allMessagesHandler;
    final prevHttp = HttpOverrides.current;
    m.allMessagesHandler = (channel, handler, message) => wire.route(m, channel, handler, message);
    HttpOverrides.global = net;
    try {
      FirebasePlatform.instance = _FakeCore();
      await Firebase.initializeApp();
      await initializeDateFormatting('ko_KR');
      await _loadFonts();
      // FirebaseAuth 생성 때의 두 listener 등록 채널 모의(이벤트 0 · 로그인 상태 불변) — 창이 읽지 않으면 쓰이지 않는다.
      const codec = StandardMessageCodec();
      for (final name in _authListeners) {
        m.setMockMessageHandler('$_authBase$name', (_) async => codec.encodeMessage(<Object?>['$_authFake$name']));
        m.setMockMethodCallHandler(MethodChannel('$_authFake$name'), (_) async => null);
      }
    } finally {
      m.allMessagesHandler = prevAll;
      HttpOverrides.global = prevHttp;
    }
    final nCf = wire.cf.length;
    final nUnexp = wire.unexpected.length;
    final nHttp = net.tries.length;
    _out('R588 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S588RS-${v.id}-${c.id} 운영자 전체 사용자 빈/실패 해요체 · 해제 창 도달 관측', (t) async {
        final tok = 'S588RS-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _opsCase(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
