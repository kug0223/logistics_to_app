// [DU570 · UXW-3a · 문구만] O029 확정 취소 안내(ConfirmCancelDialog) — 판정156 Q2 · Q5 · §5 F156-PENALTY-SPELLING · F156-LIMIT-DURATION.
//   바뀐 글(보이는 글 · 읽는 이름): 정책 1 제목 · 정책 1 설명 · 정책 2 설명 · 현재 상태 두 갈래 · 경고 · 2회 경고(_wBefore → _wAfter · prep/mk_cand.py 와 같은 값).
//   before = 지금 A(confirm_cancel_dialog d289a926) 기록 · strict = 후보(b484a2cb).
//   하네스 = DU560 시험(6466c968 · TB 에서 W/B/N 확인창 사례 3/3 성공 실행) 공용 블록 재사용(prep/mk_test.py 단언 · 전체 바이트 동일 아님) +
//     DU265(O029) 의 여는 방식 — showDialog 의 builder 로 ConfirmCancelDialog 를 직접 만든다(show() 의 노쇼 구간 판정은 시각 의존이라 hasPenalty 를 사례로 고정).
//     DU265 는 하네스 단추를 눌러 열었고, 이 시험은 DU560 처럼 문맥에서 바로 연다(누르는 것 0). 닫기 = Navigator.pop(DU560 과 같다).
//   잰다(읽기만): 바뀐 글마다 그 RichText **하나를** ensureVisible 로 스크롤 칸 안에 넣고 **같은 요소**의 자리로 화면 ∩ 스크롤 칸 안(vis) · 전문 · 낱말 안 끊김(강제 포함) ·
//     줄 수 · 읽는 이름(가장 가까운 Semantics 조상 label = 원문)을 잰다. 하단 두 버튼(스크롤 밖 고정)은 InkWell 한 요소로 화면 안 · 중심 hit · 받는 자리(기록)를 잰다.
//   쓰기 0 · CF 0 · HTTP 0 · 누르는 것 0. 날짜 입력 고정(2026-11-24 · 표시만 · 벽시계 비의존).
//   기본 skip — TB before/du570uxw3-tb/DU_BEFORE_OBSERVE=570 · TA after/du570uxw3-ta/없음.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/apply/confirm_cancel_dialog.dart';

import 'support/du1_vq_capture.dart';

/// CF Pigeon 채널 — RG 시험(offer_workdetail_roster · noshow_contract_dialog_gate)과 같은 'unavailable' 응답을 주고 센다.
const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// [DU526 과 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du570.fake.auth.';
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
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    return bx.isNotEmpty && bx.first.bottom <= size.height + 0.5 && bx.first.right <= size.width + 0.5;
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

typedef _V = ({String id, double w, double h, double s});

const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0), (id: 'N', w: 320.0, h: 640.0, s: 1.0)];

/// 사례 — SAFE = 노쇼 구간 아님 · 최근 90일 0회 / PEN = 노쇼 구간 · 1회 / NEAR = 노쇼 구간 · 2회(이번 취소로 3회가 되는 경고가 보이는 유일한 값 · confirm_cancel_dialog `== 2`).
typedef _Case = ({String id, int shots, bool pen, int count});
const _cases = <_Case>[(id: 'SAFE', shots: 2, pen: false, count: 0), (id: 'PEN', shots: 2, pen: true, count: 1), (id: 'NEAR', shots: 2, pen: true, count: 2)];

/// 대역 — DU265(O029) 와 같은 긴 사업장 · 업무 이름. 날짜는 입력 고정(표시만 · 이 셀이 바꾸는 글과 무관).
const _biz = '강남 물류센터 제2물류동 야간 분류팀';
const _work = '냉장 분류 및 출고 검수 보조';
const _time = '18:00 ~ 22:30';
final DateTime _day = DateTime(2026, 11, 24);

/// 이 셀이 바꾸는 글(모드별) — before = 지금 A 리터럴 · after = 후보 리터럴(prep/mk_cand.py 와 같은 값 · mkcell 이 대조한다).
typedef _W = ({String p1t, String p1d, String p2d, String stPen, String stSafe, String warn, String near});
const _W _wBefore = (p1t: '근무 1일 전까지', p1d: '패널티 없음', p2d: '노쇼 1회 기록\n→ 3회 누적 시 1일 지원 제한', stPen: '현재 시점: 패널티 적용 구간', stSafe: '현재 시점: 패널티 없이 취소 가능', warn: '이 취소는 패널티가 적용됩니다.', near: '⚠️ 이 취소 후 90일 기준 3회가 되어 1일간 지원이 제한됩니다!');
const _W _wAfter = (p1t: '근무 시작 5분 전까지 취소', p1d: '노쇼 기록 없음', p2d: '노쇼 1회 기록\n→ 최근 90일 3회 이상이면 24시간 이용 제한', stPen: '지금 취소하면 노쇼로 기록돼요', stSafe: '지금 취소하면 노쇼로 기록되지 않아요', warn: '최근 90일 노쇼 기록에 1회가 더해져요.', near: '⚠️ 이번 취소로 3회가 되면 취소한 때부터 24시간 동안 이용이 제한돼요.');

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '570';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du570uxw3-tb' && _env['DU_BEFORE_OBSERVE'] == '570') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du570uxw3-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');
final _W _w = _before ? _wBefore : _wAfter;

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
    if (_frameworkAllow.containsKey(channel)) {
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

/// [DU570] 확인창 안 바뀐 글 하나 — 그린 글(표시 제어 문자 제외)이 [want] 인 RichText 가 정확히 하나일 때 **그 RichText 를** ensureVisible 로
///   스크롤 칸 안에 넣고, 같은 요소로 읽는 이름(가장 가까운 Semantics 조상 label) · 전문 · 낱말 안 끊김(강제 포함) · 줄 수 · 화면 ∩ 스크롤 칸 안을 잰다(잰 즉시 값).
Future<_SeeObs> _seeText(WidgetTester t, Finder host, String want, Rect screen) async {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == want)
      .toList();
  if (es.length != 1) return (n: es.length, name: false, full: false, brk: 0, lines: 0, vis: false);
  final el = es.first;
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

typedef _ActObs = ({int n, bool m48, bool vis, bool hit, int lines});

/// [DU570] 하단 행동 버튼(스크롤 밖 고정 · 누르지 않는다) — 그린 글이 [label] 인 RichText 의 가장 가까운 InkWell 조상 **한 요소로**
///   받는 자리(48 기록) · 화면 ∩ 스크롤 칸 안 · 중심 hit 를 잰다(ensureVisible 0 — 잰 요소와 다른 요소를 움직이지 않는다).
_ActObs _actLine(WidgetTester t, Finder host, String label, Rect screen) {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == label)
      .toList();
  if (es.length != 1) return (n: es.length, m48: false, vis: false, hit: false, lines: 0);
  final el = es.first;
  final tf = find.byElementPredicate((x) => identical(x, el), skipOffstage: false);
  final ink = find.ancestor(of: tf, matching: find.byType(InkWell, skipOffstage: false)).first;
  final r = t.getRect(ink);
  return (
    n: 1,
    m48: r.width >= 48 - 0.01 && r.height >= 48 - 0.01,
    vis: _inside(r, _area(ink, screen)),
    hit: _hitWithin(t, ink, r.center),
    lines: _lineCount(el.renderObject as RenderParagraph),
  );
}

/// [DU570] 확정 취소 안내 사례 — DU560 `_confirmCase` 의 틀(guard · 앱 · 캡처 · 닫기 · 정리 · 집계)을 블록 그대로 쓰고,
///   여는 것만 DU265 와 같은 ConfirmCancelDialog 생성으로 바꿨다(hasPenalty · currentNoShowCount = 사례 값 · 누르는 것 0).
Future<void> _cancelCase(WidgetTester t, _V v, _Case c, String tok) async {
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
  _out('D570 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
  final seen = _DSeen();
  void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
  final screen = Offset.zero & Size(v.w, v.h);

  Object? failure;
  StackTrace? failureSt;
  var shots = 0;
  var raw = '';
  try {
    FlutterError.onError = seen.add;
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: RoleTheme.workerTheme,
        locale: const Locale('ko', 'KR'),
        supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    // 문맥은 마지막 pump 뒤에 바로 얻어 바로 쓴다(비동기 틈을 건너지 않는다 · use_build_context_synchronously).
    final scaffoldF = find.byType(Scaffold);
    need('앱 문맥(Scaffold 1)', scaffoldF.evaluate().length == 1, '개수 ${scaffoldF.evaluate().length}');
    unawaited(showDialog<ConfirmCancelResult>(
      context: t.element(scaffoldF),
      barrierDismissible: false,
      builder: (_) => ConfirmCancelDialog(
        workDate: _day,
        workType: _work,
        timeRange: _time,
        businessName: _biz,
        currentNoShowCount: c.count,
        hasPenalty: c.pen,
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final host = find.byType(Dialog);
    final nDlg = host.evaluate().length;
    _out('D570 $tok att dlg n=$nDlg');
    need('확인창 1', nDlg == 1, '개수 $nDlg');
    Future<void> shot(String id, String state) async {
      _out('D570 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    await shot('1top', 'dialog-open');
    // 바뀐 글 — 창 위에서 아래 순서(마지막 ensureVisible 이 창 끝 쪽이라 2end 캡처가 끝을 보인다).
    final p1t = await _seeText(t, host, _w.p1t, screen);
    _out('D570 $tok att p1t n=${p1t.n} name=${p1t.name} full=${p1t.full} brk=${p1t.brk} lines=${p1t.lines} vis=${p1t.vis}');
    final p1d = await _seeText(t, host, _w.p1d, screen);
    _out('D570 $tok att p1d n=${p1d.n} name=${p1d.name} full=${p1d.full} brk=${p1d.brk} lines=${p1d.lines} vis=${p1d.vis}');
    final p2d = await _seeText(t, host, _w.p2d, screen);
    _out('D570 $tok att p2d n=${p2d.n} name=${p2d.name} full=${p2d.full} brk=${p2d.brk} lines=${p2d.lines} vis=${p2d.vis}');
    final stv = await _seeText(t, host, c.pen ? _w.stPen : _w.stSafe, screen);
    _out('D570 $tok att st n=${stv.n} name=${stv.name} full=${stv.full} brk=${stv.brk} lines=${stv.lines} vis=${stv.vis}');
    var more = '';
    if (c.pen) {
      final warn = await _seeText(t, host, _w.warn, screen);
      _out('D570 $tok att warn n=${warn.n} name=${warn.name} full=${warn.full} brk=${warn.brk} lines=${warn.lines} vis=${warn.vis}');
      more = '$more warn $warn';
    }
    if (c.pen && c.count == 2) {
      final near = await _seeText(t, host, _w.near, screen);
      _out('D570 $tok att near n=${near.n} name=${near.name} full=${near.full} brk=${near.brk} lines=${near.lines} vis=${near.vis}');
      more = '$more near $near';
    }
    await shot('2end', 'dialog-end');
    // 하단 두 버튼(스크롤 밖 고정 · 누르지 않는다).
    final back = _actLine(t, host, '돌아가기', screen);
    _out('D570 $tok att back n=${back.n} m48=${back.m48} vis=${back.vis} hit=${back.hit} lines=${back.lines}');
    final go = _actLine(t, host, '취소 진행', screen);
    _out('D570 $tok att go n=${go.n} m48=${go.m48} vis=${go.vis} hit=${go.hit} lines=${go.lines}');
    raw = 'p1t $p1t p1d $p1d p2d $p2d st $stv$more back $back go $go';
    Navigator.of(t.element(host)).pop();
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    need('확인창 닫힘', find.byType(Dialog).evaluate().isEmpty);
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
  _out('D570 $tok att wire cf=$nCf unexpected=$nUnexp http=$nHttp');
  messenger.allMessagesHandler = prevAll;
  HttpOverrides.global = prevHttp;
  final exc = t.takeException();
  if (exc != null && failure == null) {
    failure = exc;
    failureSt = StackTrace.current;
  }
  final nOvf = seen.overflows.length;
  final nFw = seen.other.length;
  _out('R570 $tok raw m64=${_enc(raw)} ovf64=${_enc(seen.overflows.join('\n----\n'))} fw64=${_enc(seen.other.join('\n----\n'))} '
      'un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D570 $tok att fw n=$nFw');
  _out('D570 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');
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
      await initializeDateFormatting('ko_KR');
      await _loadFonts();
    } finally {
      m.allMessagesHandler = prevAll;
      HttpOverrides.global = prevHttp;
    }
    final nCf = wire.cf.length;
    final nUnexp = wire.unexpected.length;
    final nHttp = net.tries.length;
    _out('R570 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S570UC-${v.id}-${c.id} 확정 취소 안내 문구(UXW-3a)', (t) async {
        final tok = 'S570UC-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _cancelCase(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
