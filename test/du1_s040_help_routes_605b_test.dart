// ignore_for_file: depend_on_referenced_packages
// [DU605b · 파일 단위 셀 · 장부 179 행 059(F156-HELP-ROUTE '다른 경로' 일부) · 문구만] 시드 FAQ(help_faq_service)의 경로 사실 정합 —
//   판정156 §5 :97(정적 대상/권한/탭 이름·실제 가능한 경로를 대조 · 문자열만 바꾸어 종료하지 않음) · 판정173 §1 :10(DU583c 수용 · 다른 경로 OPEN).
//   바뀐 글: E1 근로자 '공고에 어떻게 지원하나요?' — '홈 화면 → "공고 찾기"를 눌러 날짜·업종별로' → '하단 "일자리" 탭에서 날짜·지역별로' ·
//            E2 근로자 '계약서 서명 요청이 왔어요.' — '홈 하단 "미서명 계약서 N건" 배너' → '화면 하단에 나타나는 계약서 서명 안내 배너' ·
//            E3 관리자 '근무자가 계약서 서명을 아직 안 했어요.' — 관리자에게 없는 서명 띠 문장 삭제(남는 문장 원문 그대로).
//   before = 지금 A 원문(help_faq_service 3a7c9d77 = DU583c 후보) · strict = 후보 원문(9f87c5cc) — prep/test_check.py 가 base/후보 인접 리터럴 이음과 정확 대조.
//   하네스 = DU583c 시험(du583c-help-menu-names/new/du1_s040_help_menu_names_583c_test.dart · 177df27b · 정규 1회 DONE 5/5 · 판정173 §1 수용)의
//     Firebase 대역 · 채널 관찰 · 글꼴 · 측정 블록(DU571 r2 바이트 그대로 — _midBreaks · max 판 _fullShown · _area · _lineCount · _seeText) ·
//     _srcCount · _reach · _open · _toEnd · _hex · _fills · 사례 틀(_helpCase 머리 · see · ends · fills · 정리 · 집계) · main 을 줄 범위 그대로 쓴다
//     (출력 접두 D583/R583 → D605/R605 만 바꿈 · 개수 단언 prep/mk_test.py). 사례는 시드 둘(SEEDU · SEEDA) — 내장 FAQ 는 이 셀이 바꾸지 않는다.
//   잰다(읽기만): 바뀐 답변 RichText **하나를** ensureVisible 로 넣고 **같은 요소**로 전문 · 낱말 안 끊김 · 줄 수 · 화면 ∩ 스크롤 칸 안(기록) ·
//     점검표 A8 단추 채움(기록) · 시드 소스 문장 개수(src).
//   펼침 = 질문 행 InkWell 의 onTap 콜백 직접 호출(포인터 · hit-test 0 · 누르는 것 0). 목록 내리기 = ScrollPosition.jumpTo(포인터 0 · 아래로만).
//   쓰기 0 · CF 0 · HTTP 0. 기본 skip — TB before/du605bfaq-tb/DU_BEFORE_OBSERVE=605 · TA after/du605bfaq-ta/없음.
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

import 'package:ALfit/models/core/help_faq_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/help_screen.dart';
import 'package:ALfit/services/help_faq_service.dart';
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

/// 역할 대역 — DU583c · DU583b · DU580 · help_faq_65 시험과 같은 꼴(실제 검증 아님).
class _Role extends UserProvider {
  _Role(this.role);
  final UserRole role;
  @override
  UserModel? get currentUser => UserModel(uid: 'u-d605b', username: 'qa', name: 'QA', email: 'qa@test.local', role: role, accountStatus: 'active',
      createdAt: DateTime(2026, 1, 1));
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => false;
}

HelpFaqModel _h(int o, String c) =>
    HelpFaqModel(id: 'h$o', role: 'user', order: o, category: c, question: c, answer: '', isHeader: true, isActive: true);
HelpFaqModel _q(int o, String c, String q, String a) =>
    HelpFaqModel(id: 'q$o', role: 'user', order: o, category: c, question: q, answer: a, isHeader: false, isActive: true);

/// 사례 — SEEDU · SEEDA = 시드 FAQ(근로자 · 관리자) 문장을 서버 항목으로 + 시드 소스 대조.
typedef _Case = ({String id, int shots, bool admin, bool seed});
const _cases = <_Case>[(id: 'SEEDU', shots: 4, admin: false, seed: true), (id: 'SEEDA', shots: 2, admin: true, seed: true)];

// ── 이 셀이 바꾸는 시드 답변 — B = 지금 A 원문 · A = 후보 원문(바꾸지 않은 앞뒤 문장은 원문 그대로 둔다) ──
const _aplB = '홈 화면 → "공고 찾기"를 눌러 날짜·업종별로 공고를 탐색할 수 있습니다. '
    '원하는 공고를 선택한 뒤 "지원하기" 버튼을 누르면 됩니다. '
    '관리자가 확정하면 알림과 함께 근로계약서 서명 요청이 전송됩니다.';
const _aplA = '하단 "일자리" 탭에서 날짜·지역별로 공고를 탐색할 수 있습니다. '
    '원하는 공고를 선택한 뒤 "지원하기" 버튼을 누르면 됩니다. '
    '관리자가 확정하면 알림과 함께 근로계약서 서명 요청이 전송됩니다.';
const _sigB = '홈 하단 "미서명 계약서 N건" 배너를 탭하거나, '
    '"내 일정" → 해당 근무 카드 → "계약서 확인"을 눌러 내용을 확인한 뒤 서명하세요.\n'
    '계약서 화면에서 바로 서명을 그릴 수 있습니다. '
    '"내 정보" 탭 → 근무 관리 → "내 서명"에 미리 등록해두면 다음 계약서부터 편리하게 사용할 수 있습니다.\n'
    '서명 후 관리자와 본인 모두 서명된 계약서를 PDF로 확인할 수 있습니다.';
const _sigA = '화면 하단에 나타나는 계약서 서명 안내 배너를 탭하거나, '
    '"내 일정" → 해당 근무 카드 → "계약서 확인"을 눌러 내용을 확인한 뒤 서명하세요.\n'
    '계약서 화면에서 바로 서명을 그릴 수 있습니다. '
    '"내 정보" 탭 → 근무 관리 → "내 서명"에 미리 등록해두면 다음 계약서부터 편리하게 사용할 수 있습니다.\n'
    '서명 후 관리자와 본인 모두 서명된 계약서를 PDF로 확인할 수 있습니다.';
const _unsB = '홈 하단 "미서명 계약서 N건" 배너를 확인하거나, '
    '해당 지원자 카드에서 서명 대기 상태를 볼 수 있습니다. '
    '근무자에게 직접 안내하거나, 알림이 자동 발송됩니다.';
const _unsA = '해당 지원자 카드에서 서명 대기 상태를 볼 수 있습니다. '
    '근무자에게 직접 안내하거나, 알림이 자동 발송됩니다.';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '605';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du605bfaq-tb' && _env['DU_BEFORE_OBSERVE'] == '605') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du605bfaq-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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

/// [DU580] 질문 행을 펼친다 — 그린 글이 [q] 인 RichText 하나의 InkWell 조상 onTap 콜백을 직접 부른다(포인터 · hit-test 0). 펼친 수(0 또는 1).
Future<int> _open(WidgetTester t, Finder host, String q) async {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == q)
      .toList();
  if (es.length != 1) return 0;
  final qf = find.byElementPredicate((x) => identical(x, es.first), skipOffstage: false);
  final ink = find.ancestor(of: qf, matching: find.byType(InkWell, skipOffstage: false));
  if (ink.evaluate().isEmpty) return 0;
  final tap = (t.widget(ink.first) as InkWell).onTap;
  if (tap == null) return 0;
  tap();
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  return 1;
}

/// [DU580] 답변 끝 화면 — 그린 글이 [match] 에 맞는 RichText 하나를 아래 맞춤(alignment 1.0)으로 스크롤한다(측정 0 · 포인터 0 · 캡처용).
Future<void> _toEnd(WidgetTester t, Finder host, bool Function(String s) match) async {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .toList();
  if (es.length != 1) return;
  await Scrollable.ensureVisible(es.first, alignment: 1.0);
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// 시드 FAQ 항목 — 저장 순서 · 이 셀이 바꾸는 답변과 그 분류만. 분류 값은 그림 문자를 뺀 이름이다(HelpScreen 이 그림 문자를 떼고 그린다 ·
///   보이지 않는 변형 선택자 U+FE0F 를 시험 소스에 넣지 않으려고). 질문은 시드 원문 그대로(:133 · :160 · :220). 시드 소스와의 정확 대조는 답변 문장(src)으로 한다.
List<HelpFaqModel> _seedItems(bool admin) => admin
    ? [
        _h(0, '근로계약서'),
        _q(1, '근로계약서', '근무자가 계약서 서명을 아직 안 했어요.', _w(_unsB, _unsA)),
      ]
    : [
        _h(0, '공고 & 지원'),
        _q(1, '공고 & 지원', '공고에 어떻게 지원하나요?', _w(_aplB, _aplA)),
        _h(2, '근로계약서'),
        _q(3, '근로계약서', '계약서 서명 요청이 왔어요. 어떻게 하나요?', _w(_sigB, _sigA)),
      ];

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

/// [DU605b] 도움말 시드 사례 — DU583c `_helpCase` 의 틀(guard · 캡처 · 정리 · 집계 · see · ends · fills)을 줄 범위 그대로 쓰고(출력 접두만 D605/R605), 재는 답변 · 소스 대조만 바꿨다.
Future<void> _helpCase(WidgetTester t, _V v, _Case c, String tok) async {
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
  _out('D605 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
    Future<HelpFaqLoad> load(String role) async =>
        c.seed ? HelpFaqLoad(_seedItems(c.admin), configured: true) : const HelpFaqLoad([], configured: false);
    await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
      create: (_) => _Role(c.admin ? UserRole.BUSINESS_ADMIN : UserRole.USER),
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: c.admin ? RoleTheme.businessAdminTheme : RoleTheme.workerTheme,
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
          home: HelpScreen(load: load),
        ),
      ),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final host = find.byType(HelpScreen);
    final nScr = host.evaluate().length;
    _out('D605 $tok att scr n=$nScr');
    need('화면 1', nScr == 1, '개수 $nScr');
    Future<void> shot(String id, String state) async {
      _out('D605 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    var opened = 0;
    // 답변 하나 재기 — 질문까지 아래로만 내리고 → 펼치고 → 바뀐 답변 RichText 하나를 잰다(_seeText). 출력 줄은 부르는 자리에서 sub 를 글자 그대로 쓴다
    //   (preflight 가 '$tok att <sub> k=…' 를 소스에서 정적으로 대조한다).
    Future<_SeeObs> see(String q, String text) async {
      await _reach(t, host, (s) => s == q);
      opened += await _open(t, host, q);
      final o = await _seeText(t, host, (s) => s == text, screen);
      raw = '$raw | $o';
      return o;
    }

    // 답변 위 캡처 → 답변 끝으로(측정 0) → 끝 캡처.
    Future<void> ends(String text, String top, String end) async {
      await shot(top, 'answer-top');
      await _toEnd(t, host, (s) => s == text);
      await shot(end, 'answer-end');
    }

    // [점검표 A8] 화면에 그려진 단추 채움(기록) — 도움말 목록에는 ButtonStyleButton 이 없다(빈 목록이면 n=0).
    void fills() {
      final f = _fills(t);
      _out('D605 $tok att fills n=${f.n} brand=${f.brand} err=${f.err} none=${f.none} other=${f.other} list=${f.list}');
      raw = '$raw | fills $f';
    }

    if (!c.admin) {
      // 근로자 시드 — 공고 & 지원(지원 방법 · E1) → 근로계약서(서명 요청 · E2). 아래로만.
      final apl = await see('공고에 어떻게 지원하나요?', _w(_aplB, _aplA));
      _out('D605 $tok att apl n=${apl.n} name=${apl.name} full=${apl.full} brk=${apl.brk} lines=${apl.lines} vis=${apl.vis}');
      await ends(_w(_aplB, _aplA), '1apl', '1aple');
      fills();
      final sig = await see('계약서 서명 요청이 왔어요. 어떻게 하나요?', _w(_sigB, _sigA));
      _out('D605 $tok att sig n=${sig.n} name=${sig.name} full=${sig.full} brk=${sig.brk} lines=${sig.lines} vis=${sig.vis}');
      await ends(_w(_sigB, _sigA), '2sig', '2sige');
    } else {
      // 관리자 시드 — 근로계약서(서명을 아직 안 한 근무자 · E3).
      final uns = await see('근무자가 계약서 서명을 아직 안 했어요.', _w(_unsB, _unsA));
      _out('D605 $tok att uns n=${uns.n} name=${uns.name} full=${uns.full} brk=${uns.brk} lines=${uns.lines} vis=${uns.vis}');
      await ends(_w(_unsB, _unsA), '1uns', '1unse');
      fills();
    }
    _out('D605 $tok att open n=$opened');
    // 시드 소스 대조 — 지금 모드의 답변은 정확히 1곳 · 다른 모드의 값은 0.
    final src = File('lib/services/help_faq_service.dart').readAsStringSync();
    final pairs = c.admin ? [(_unsB, _unsA)] : [(_aplB, _aplA), (_sigB, _sigA)];
    final ok = pairs.every((p) => _srcCount(src, _w(p.$1, p.$2)) == 1);
    final old = pairs.fold<int>(0, (a, p) => a + _srcCount(src, _w(p.$2, p.$1)));
    _out('D605 $tok att src ok=$ok old=$old');
    raw = '$raw src ok=$ok old=$old';
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
  _out('D605 $tok att wire cf=$nCf unexpected=$nUnexp http=$nHttp');
  messenger.allMessagesHandler = prevAll;
  HttpOverrides.global = prevHttp;
  final exc = t.takeException();
  if (exc != null && failure == null) {
    failure = exc;
    failureSt = StackTrace.current;
  }
  final nOvf = seen.overflows.length;
  final nFw = seen.other.length;
  _out('R605 $tok raw m64=${_enc(raw)} ovf64=${_enc(seen.overflows.join('\n----\n'))} fw64=${_enc(seen.other.join('\n----\n'))} '
      'un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D605 $tok att fw n=$nFw');
  _out('D605 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');
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
    _out('R605 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S605HF-${v.id}-${c.id} 도움말 시드 경로 사실 정합(장부 059)', (t) async {
        final tok = 'S605HF-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _helpCase(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
