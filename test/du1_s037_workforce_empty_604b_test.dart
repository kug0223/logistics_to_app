// ignore_for_file: depend_on_referenced_packages
// [DU604b · 파일 단위 셀 · 장부 179 행 083 · 문구 + 줄바꿈] 근무자 관리 운영 보기(WorkforceOperationalView)의 빈 상태 글 —
//   판정156 Q2 :31('사람을 ‘노쇼 인원’으로 분류하지 않고 노쇼 기록/노쇼로 기록된 근무를 말한다 · 집계 단위를 먼저 대조 · 문구만으로 집계 단위를 바꾸지 않는다').
//   바뀐 것: 노쇼 필터 빈 상태 '노쇼 인원이 없습니다.' → '노쇼로 기록된 근무가 없습니다.'(칩 숫자 = 지원서 한 건 단위 · 합니다체 유지) ·
//            빈 상태 글 Text 에 TextLayout.keepWords + semanticsLabel 원문(같은 파일 오류 상태와 같은 꼴 — 큰 글자에서 음절 사이 줄바꿈 0 · 화면 읽기 원문).
//   before = 지금 A 원문(workforce_operational_view 372fee58) · strict = 후보 원문(76010663).
//   하네스 = DU583c 시험(du583c-help-menu-names/new/du1_s040_help_menu_names_583c_test.dart · 177df27b · 정규 1회 DONE 5/5 · 판정173 §1 수용)의
//     Firebase 대역 · 채널 관찰 · 글꼴 · 측정 블록(DU571 r2 바이트 그대로 — _midBreaks · max 판 _fullShown · _area · _lineCount · _seeText) ·
//     _srcCount · _reach · _hex · _fills · 사례 꼬리(정리 · 집계) · main 을 줄 범위 그대로 쓴다(출력 접두 D583/R583 → D604/R604 만 바꿈 · 개수 단언 prep/mk_test.py).
//     화면 대역(_Owner · _LoadedController · 사업장 맵 · 읽기 callable 5종 허용)은 DU236 suite · workforce_attendance_identity_test 와 같은 꼴.
//   잰다(읽기만): 빈 상태 글 RichText **하나를** ensureVisible 로 넣고 **같은 요소**로 전문 · 낱말 안 끊김 · 줄 수 · 이름(semantics) · 화면 ∩ 스크롤 칸 안 ·
//     점검표 A8 단추 채움(기록) · 제품 소스 문장 · 코드 조각 개수(src) · CF 대역 호출(srv).
//   칩 전환 = 요약 칩 GestureDetector 의 onTap 콜백 직접 호출(포인터 · hit-test 0). 목록 위치 = ScrollPosition.jumpTo(포인터 0).
//   쓰기 0 · HTTP 0 · CF 는 읽기 5종 대역 응답만. 기본 skip — TB before/du604bwfe-tb/DU_BEFORE_OBSERVE=604 · TA after/du604bwfe-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui show BoxHeightStyle;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/models/core/business_member_model.dart' show MemberPermissions;
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/workforce_management/workforce_operational_view.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
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
const _authFake = 'du571.fake.auth.';
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

const _kBiz = 'biz-local-d604b';
const _kOwner = 'owner-local-d604b';

/// 사업장 주인 대역 — DU236 suite `_Owner` · workforce_attendance_identity_test `_AdminP` 와 같은 꼴(실제 검증 아님).
class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: _kOwner, username: 'owner', name: 'QA 사장', email: 'o@test.local',
      role: UserRole.BUSINESS_ADMIN, businessId: _kBiz, managedBusinessIds: const [_kBiz], createdAt: DateTime(2026, 1, 1));
  @override
  String? get effectiveBusinessId => _kBiz;
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
}

/// 공고 탭 첫 로드를 거친 상태 — 이 화면은 그 전까지 스피너만 그린다(workforce_attendance_identity_test 와 같은 대역).
class _LoadedController extends WorkforceController {
  @override
  bool get hasLoadedOnce => true;
}

/// 사업장 1곳 — callable(JSON) 응답 꼴(DU236 suite bizMap 과 같은 필드 · createdAt 은 Timestamp 직렬형).
Map<String, Object?> _bizMap() => {
      'id': _kBiz, 'name': 'QA 물류센터', 'businessNumber': '000-00-00000', 'category': '물류', 'subCategory': '상하차',
      'address': '서울시 QA구 1', 'ownerId': _kOwner, 'adminIds': const [_kOwner], 'isApproved': true,
      'createdAt': {'_seconds': DateTime.utc(2026, 10, 1).millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0},
    };

/// CF 대역 — 읽기 callable 5종(DU236 suite 'zero' 장면과 같은 허용 목록)만 빈 응답(사업장은 1곳)으로 돌려주고 센다.
///   그 밖 이름은 not-found 로 막고 센다(unknown) · 지역이 asia-northeast3 이 아니면 센다(region).
class _Srv {
  final calls = <String>[];
  final unknown = <String>[];
  var region = 0;

  Future<ByteData?> handle(ByteData? message) async {
    const c = StandardMessageCodec();
    final args = (c.decodeMessage(message) as List).first as Map;
    final name = (args['functionName'] ?? '').toString();
    if (args['region'] != 'asia-northeast3') region++;
    calls.add(name);
    ByteData? ok(Object? data) => c.encodeMessage(<Object?>[data]);
    switch (name) {
      case 'callableGetAdminTOs':
        return ok(<String, Object?>{'items': const <Object?>[]});
      case 'callableGetMyBusiness':
        return ok(<String, Object?>{'businesses': [_bizMap()]});
      case 'callableGetApplicationsByBiz':
        return ok(<String, Object?>{'applications': const <Object?>[], 'hasMore': false});
      case 'callableGetAdminAttendances':
        return ok(<String, Object?>{'items': const <Object?>[], 'limitReached': false});
      case 'callableGetUsersBatch':
        return ok(<String, Object?>{'users': const <String, Object?>{}});
    }
    unknown.add(name);
    return c.encodeMessage(<Object?>['not-found', 'du604b-blocked $name', <String, Object?>{'code': 'not-found'}]);
  }
}

/// 사례 — ZERO = 사업장 1 · 그 날 확정 근무 0(빈 상태 네 필터).
typedef _Case = ({String id, int shots});
const _cases = <_Case>[(id: 'ZERO', shots: 4)];

// ── 빈 상태 글 — 노쇼 필터만 이 셀이 바꾼다(B = 지금 A 원문 · A = 후보 원문) · 나머지 셋은 문구 그대로(keepWords 만 함께 받는다) ──
const _allMsg = '오늘 확정된 인력이 없습니다.';
const _inMsg = '출근한 인원이 없습니다.';
const _notMsg = '미출근 인원이 없습니다.';
const _nsB = '노쇼 인원이 없습니다.';
const _nsA = '노쇼로 기록된 근무가 없습니다.';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '604';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du604bwfe-tb' && _env['DU_BEFORE_OBSERVE'] == '604') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du604bwfe-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

/// before = 지금 A 원문 · strict = 후보 원문.
String _w(String before, String after) => _before ? before : after;

final RegExp _seqRe = RegExp(r"'(?:[^'\\\n]|\\.)*'(?:\s*'(?:[^'\\\n]|\\.)*')*");
final RegExp _litRe = RegExp(r"'((?:[^'\\\n]|\\.)*)'");
final RegExp _escRe = RegExp(r'\\(.)');

/// [DU580] 시드 소스에서 인접 문자열 리터럴 이음(줄 사이 공백 포함 · 쉼표로 끊김)의 값이 [s] 와 정확히 같은 곳의 수.
int _srcCount(String src, String s) => _seqRe
    .allMatches(src)
    .where((m) => _litRe.allMatches(m[0]!).map((x) => x[1]!.replaceAllMapped(_escRe, (e) => e[1] == 'n' ? '\n' : e[1]!)).join() == s)
    .length;

/// [DU580] 목록 아래쪽 항목을 트리에 올린다 — 그린 글이 [match] 에 맞는 RichText 가 생길 때까지 스크롤 위치를 화면 0.8 만큼씩 **아래로만** 옮긴다
///   (ScrollPosition.jumpTo · 포인터 0 · 위로 되돌아가지 않아 펼친 행이 해제되지 않는다). 측정은 하지 않는다 — _seeText 가 같은 요소로 다시 잡는다.
Future<int> _reach(WidgetTester t, Finder host, bool Function(String s) match) async {
  int count() => find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .length;
  var k = 0;
  while (count() == 0 && k < 40) {
    final pos = t.state<ScrollableState>(find.descendant(of: host, matching: find.byType(Scrollable), skipOffstage: false).first).position;
    if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
    final next = pos.pixels + pos.viewportDimension * 0.8;
    pos.jumpTo(next < pos.maxScrollExtent ? next : pos.maxScrollExtent);
    await t.pump(const Duration(milliseconds: 50));
    k++;
  }
  return count();
}

/// [DU604b] 보기 스크롤을 맨 위로 — 칩 줄(맨 위 sliver)이 트리에 있게 한다(ScrollPosition.jumpTo · 포인터 0 · 측정 0).
Future<void> _top(WidgetTester t, Finder host) async {
  final sc = find.descendant(of: host, matching: find.byType(Scrollable), skipOffstage: false);
  if (sc.evaluate().isEmpty) return;
  t.state<ScrollableState>(sc.first).position.jumpTo(0);
  for (var m = 0; m < 2; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// [DU604b] 요약 칩 하나를 고른다 — 그린 글이 [label] 인 RichText 하나의 GestureDetector(child AnimatedContainer) 조상 onTap 콜백을 직접 부른다
///   (포인터 · hit-test 0 · DU583c `_open` 과 같은 꼴). 고른 수(0 또는 1).
Future<int> _chip(WidgetTester t, Finder host, String label) async {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == label)
      .toList();
  if (es.length != 1) return 0;
  final lf = find.byElementPredicate((x) => identical(x, es.first), skipOffstage: false);
  final gd = find.ancestor(of: lf, matching: find.byWidgetPredicate((w) => w is GestureDetector && w.child is AnimatedContainer, skipOffstage: false));
  if (gd.evaluate().isEmpty) return 0;
  final tap = (t.widget(gd.first) as GestureDetector).onTap;
  if (tap == null) return 0;
  tap();
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  return 1;
}

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

/// [DU604b] 근무 운영 보기 빈 상태 사례 — DU583c `_helpCase` 머리(guard · 앱 · host · shot · fills)의 꼴을 따르고, 화면 · CF 대역 · 칩 전환 · 재는 글만 바꿨다.
///   꼬리(catch · 정리 · wire · raw · fw · done · 캡처 수)는 DU583c 줄 범위 그대로다.
Future<void> _wfCase(WidgetTester t, _V v, _Case c, String tok) async {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final wire = _DWire();
  final net = _DNoHttp(wire);
  final srv = _Srv();
  final prevAll = messenger.allMessagesHandler;
  final prevHttp = HttpOverrides.current;
  final prevOnError = FlutterError.onError;
  // CF 채널만 읽기 대역(_Srv)으로 · 그 밖 모든 채널은 DU583c 관찰(_DWire — 허용 밖이면 막고 센다).
  messenger.allMessagesHandler =
      (channel, handler, message) => channel == _cfChannel ? srv.handle(message) : wire.route(messenger, channel, handler, message);
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
  _out('D604 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
    final ctl = _LoadedController();
    addTearDown(ctl.dispose);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Owner()),
        ChangeNotifierProvider<WorkforceController>.value(value: ctl),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.businessAdminTheme,
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
          home: const Scaffold(body: WorkforceOperationalView()),
        ),
      ),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final host = find.byType(WorkforceOperationalView);
    final nScr = host.evaluate().length;
    _out('D604 $tok att scr n=$nScr');
    need('화면 1', nScr == 1, '개수 $nScr');
    Future<void> shot(String id, String state) async {
      _out('D604 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    // [점검표 A8] 화면에 그려진 단추 채움(기록).
    void fills() {
      final f = _fills(t);
      _out('D604 $tok att fills n=${f.n} brand=${f.brand} err=${f.err} none=${f.none} other=${f.other} list=${f.list}');
      raw = '$raw | fills $f';
    }

    // 빈 상태 글 하나 재기 — 아래로만 내려 그 글을 트리에 올리고(_reach) → 같은 RichText 하나를 잰다(_seeText). 출력 줄은 sub 를 글자 그대로 쓴다.
    Future<_SeeObs> see(String text) async {
      await _reach(t, host, (s) => s == text);
      final o = await _seeText(t, host, (s) => s == text, screen);
      raw = '$raw | $o';
      return o;
    }

    var tapped = 0;
    // ① 확정(전체) 필터 — 처음 화면.
    final eall = await see(_allMsg);
    _out('D604 $tok att eall n=${eall.n} name=${eall.name} full=${eall.full} brk=${eall.brk} lines=${eall.lines} vis=${eall.vis}');
    await shot('1all', 'empty-all');
    fills();
    // ② 출근 필터.
    await _top(t, host);
    tapped += await _chip(t, host, '출근');
    final ein = await see(_inMsg);
    _out('D604 $tok att ein n=${ein.n} name=${ein.name} full=${ein.full} brk=${ein.brk} lines=${ein.lines} vis=${ein.vis}');
    await shot('2in', 'empty-checked-in');
    // ③ 미출근 필터.
    await _top(t, host);
    tapped += await _chip(t, host, '미출근');
    final enot = await see(_notMsg);
    _out('D604 $tok att enot n=${enot.n} name=${enot.name} full=${enot.full} brk=${enot.brk} lines=${enot.lines} vis=${enot.vis}');
    await shot('3not', 'empty-not-checked-in');
    // ④ 노쇼 필터 — 이 셀이 바꾸는 문구.
    await _top(t, host);
    tapped += await _chip(t, host, '노쇼');
    final ens = await see(_w(_nsB, _nsA));
    _out('D604 $tok att ens n=${ens.n} name=${ens.name} full=${ens.full} brk=${ens.brk} lines=${ens.lines} vis=${ens.vis}');
    await shot('4ns', 'empty-no-show');
    _out('D604 $tok att tap n=$tapped');
    // 제품 소스 대조 — 지금 모드의 노쇼 문구 1곳 · 다른 모드 문구 0 · 형제 셋 1곳씩 · keepWords/semanticsLabel 조각(before 0 · strict 1).
    final src = File('lib/screens/business_admin/workforce_management/workforce_operational_view.dart').readAsStringSync();
    final kw = 'TextLayout.keepWords(message),'.allMatches(src).length;
    final sl = 'semanticsLabel: message,'.allMatches(src).length;
    final ok = _srcCount(src, _w(_nsB, _nsA)) == 1 && [_allMsg, _inMsg, _notMsg].every((m) => _srcCount(src, m) == 1);
    final old = _srcCount(src, _w(_nsA, _nsB));
    _out('D604 $tok att src ok=$ok old=$old kw=$kw sl=$sl');
    raw = '$raw src ok=$ok old=$old kw=$kw sl=$sl';
    _out('D604 $tok att srv n=${srv.calls.length} unknown=${srv.unknown.length} region=${srv.region}');
    raw = '$raw srv ${srv.calls.join(',')} unknown ${srv.unknown.join(',')}';
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // 성공 · 실패 공통 정리 — DU580 _helpCase 와 같다.
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
  _out('D604 $tok att wire cf=$nCf unexpected=$nUnexp http=$nHttp');
  messenger.allMessagesHandler = prevAll;
  HttpOverrides.global = prevHttp;
  final exc = t.takeException();
  if (exc != null && failure == null) {
    failure = exc;
    failureSt = StackTrace.current;
  }
  final nOvf = seen.overflows.length;
  final nFw = seen.other.length;
  _out('R604 $tok raw m64=${_enc(raw)} ovf64=${_enc(seen.overflows.join('\n----\n'))} fw64=${_enc(seen.other.join('\n----\n'))} '
      'un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D604 $tok att fw n=$nFw');
  _out('D604 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');
  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  expect(shots == c.shots, isTrue, reason: '$tok 캡처 수 = 선언 shots $shots want ${c.shots}');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
    _out('R604 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S604WE-${v.id}-${c.id} 근무 운영 보기 빈 상태 문구 · 낱말 줄바꿈(장부 083)', (t) async {
        final tok = 'S604WE-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _wfCase(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
