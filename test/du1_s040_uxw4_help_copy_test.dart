// ignore_for_file: depend_on_referenced_packages
// [DU580 · UXW-4 · 문구만] 도움말 두 원천(내장 FAQ = help_screen · 시드 FAQ = help_faq_service)의 노쇼 · 이용 제한 안내 — 판정156 Q2 · Q4 · Q5 · 어투 · §5 F156-LIMIT-DURATION.
//   바뀐 글: 내장 FAQ — 분류 제목 · '지원 취소' 답변 끝 세 문장 · '지원이 제한됐어요' 답변 앞 두 문장 · 관리자 '노쇼 처리' 답변 뒤 두 문장 /
//            시드 FAQ — 분류 제목(3곳) · '지원 취소' 답변 끝 세 문장 · '노쇼 기록은 언제 남나요?' 답변 · '지원이 막혔어요' 답변 앞 두 문장 · 관리자 '노쇼 처리' 답변 뒤 두 문장.
//   before = 지금 A 원문(help_screen 88859667 · help_faq_service c3604ce4) · strict = 후보 원문 — prep/test_check.py 가 base/후보 인접 리터럴 이음과 정확 대조.
//   내장 FAQ(USR · ADM) = HelpScreen(load: 문서 없음 → 내장 목록) · 시드 FAQ(SEEDU · SEEDA) = HelpScreen(load: 시드 문장을 서버 항목으로) + 시드 소스
//     (lib/services/help_faq_service.dart)에 같은 문장이 정확한 수만큼 있는지 소스 대조(src). 이미 저장된 원격 FAQ 는 이 시험 밖이다(바뀌지 않는다).
//   하네스 = DU571 r2 시험(du571-uxw3b-limit-notice/r2/new/du1_s065_uxw3b_limit_notice_test.dart · 정규 1회 DONE 5/5)의 Firebase 대역 · 채널 관찰 · 글꼴 ·
//     측정 블록(_midBreaks · max 판 _fullShown · _area · _lineCount · _seeText)을 바이트 그대로 쓴다(prep/mk_test.py 가 줄 범위를 그대로 붙인다).
//   잰다(읽기만): 바뀐 글 RichText **하나를** ensureVisible 로 넣고 **같은 요소**로 전문 · 낱말 안 끊김 · 줄 수 · 화면 ∩ 스크롤 칸 안(vis) · 읽는 이름(기록).
//   펼침 = 질문 행 InkWell 의 onTap 콜백 직접 호출(포인터 · hit-test 0 · 누르는 것 0). 목록 내리기 = ScrollPosition.jumpTo(포인터 0 · 아래로만).
//   쓰기 0 · CF 0 · HTTP 0. 기본 skip — TB before/du580uxw4-tb/DU_BEFORE_OBSERVE=580 · TA after/du580uxw4-ta/없음.
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

/// 역할 대역 — DU246 · help_faq_65 시험과 같은 꼴(실제 검증 아님).
class _Role extends UserProvider {
  _Role(this.role);
  final UserRole role;
  @override
  UserModel? get currentUser => UserModel(uid: 'u-d580', username: 'qa', name: 'QA', email: 'qa@test.local', role: role, accountStatus: 'active',
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

/// 사례 — USR · ADM = 내장 FAQ(사용자 · 관리자) / SEEDU · SEEDA = 시드 FAQ(사용자 · 관리자) 문장을 서버 항목으로 + 시드 소스 대조.
typedef _Case = ({String id, int shots, bool admin, bool seed});
const _cases = <_Case>[(id: 'USR', shots: 5, admin: false, seed: false), (id: 'ADM', shots: 2, admin: true, seed: false), (id: 'SEEDU', shots: 7, admin: false, seed: true), (id: 'SEEDA', shots: 2, admin: true, seed: true)];

// ── 이 셀이 바꾸는 글 — B = 지금 A 원문 · A = 후보 원문(바꾸지 않은 경로 · 문의 문장은 원문 그대로 앞뒤에 둔다) ──
// 내장 FAQ(help_screen) — 분류 제목은 그린 글(앞 그림 문자 뺀 값)
const _hdrB = '노쇼 & 제재';
const _hdrA = '노쇼 & 이용 제한';
const _canB = '"일정" 탭에서 해당 날짜를 선택한 후 일정 카드의 "지원 취소" 버튼을 누르세요.\n'
    '• 대기 중(미확정): 즉시 취소됩니다.\n'
    '• 확정 후: 취소 요청을 보내야 하며, 관리자 승인 후 취소됩니다.\n'
    '근무 시작 5분 전 이후에 취소하거나 출근하지 않으면 노쇼 기록이 남을 수 있습니다. 90일 이내 3회 이상이면 지원이 제한됩니다.';
const _canA = '"일정" 탭에서 해당 날짜를 선택한 후 일정 카드의 "지원 취소" 버튼을 누르세요.\n'
    '• 대기 중(미확정): 즉시 취소됩니다.\n'
    '• 확정 후: 취소 요청을 보내야 하며, 관리자 승인 후 취소됩니다.\n'
    '확정된 근무를 시작 5분 전부터 취소하면 노쇼 1회로 기록돼요.\n'
    '출근하지 않은 근무도 노쇼로 기록될 수 있어요.\n'
    '최근 90일 동안 노쇼 기록이 3회 이상이 되면 24시간 동안 이용이 제한돼 로그인하거나 지원할 수 없어요.';
const _limB = '최근 90일 이내 노쇼 기록이 3회 이상이면 24시간 지원 제한이 적용됩니다. '
    '제한 기간이 지나면 자동으로 해제됩니다. '
    '이의가 있으면 앱 내 "문의하기"로 고객센터에 문의하세요.';
const _limA = '최근 90일 동안 노쇼 기록이 3회 이상이 되면 24시간 동안 이용이 제한돼 로그인하거나 지원할 수 없어요.\n'
    '24시간이 지나면 제한이 자동으로 풀려요.\n'
    '이의가 있으면 앱 내 "문의하기"로 고객센터에 문의하세요.';
const _nspB = '당일명단 → 해당 근무자 → "노쇼 처리" 버튼을 누르세요. '
    '노쇼 처리 시 해당 근무자의 노쇼 기록이 남고 90일 이내 3회 누적 시 지원 제한이 적용됩니다.';
const _nspA = '당일명단 → 해당 근무자 → "노쇼 처리" 버튼을 누르세요. '
    '노쇼로 처리하면 그 근무자에게 노쇼 기록이 1회 남아요.\n'
    '최근 90일 동안 노쇼 기록이 3회 이상이 되면 그 근무자는 24시간 동안 이용이 제한돼 로그인하거나 지원할 수 없어요.';
// 시드 FAQ(help_faq_service) — 분류는 저장 값(앞 그림 문자 포함) · 그린 제목은 _sHdrPlainB / _hdrA
const _sHdrB = '📛 노쇼 & 지원 제한';
const _sHdrA = '📛 노쇼 & 이용 제한';
const _sHdrPlainB = '노쇼 & 지원 제한';
const _sCanB = '"내 스케줄" → 해당 일정 카드 → "지원 취소" 버튼을 누르세요.\n'
    '• 대기 중(미확정): 즉시 취소됩니다.\n'
    '• 확정 후: 취소 요청을 보내야 하며, 관리자 승인 후 취소됩니다.\n'
    '근무 시작 5분 전 이후에 취소하거나 출근하지 않으면 노쇼 기록이 남을 수 있습니다.\n'
    '최근 90일 내 3회 이상이면 1일 지원이 제한됩니다.';
const _sCanA = '"내 스케줄" → 해당 일정 카드 → "지원 취소" 버튼을 누르세요.\n'
    '• 대기 중(미확정): 즉시 취소됩니다.\n'
    '• 확정 후: 취소 요청을 보내야 하며, 관리자 승인 후 취소됩니다.\n'
    '확정된 근무를 시작 5분 전부터 취소하면 노쇼 1회로 기록돼요.\n'
    '출근하지 않은 근무도 노쇼로 기록될 수 있어요.\n'
    '최근 90일 동안 노쇼 기록이 3회 이상이 되면 24시간 동안 이용이 제한돼 로그인하거나 지원할 수 없어요.';
const _sRecB = '근무 시작 5분 전 이후에 취소하거나 출근하지 않으면 노쇼 기록이 남습니다.\n'
    '최근 90일 이내 3회 이상 누적되면 24시간 지원이 제한됩니다.\n'
    '제한 기간이 지나면 자동으로 해제됩니다.';
const _sRecA = '확정된 근무를 시작 5분 전부터 취소하면 노쇼 1회로 기록돼요.\n'
    '출근하지 않은 근무도 노쇼로 기록될 수 있어요.\n'
    '최근 90일 동안 노쇼 기록이 3회 이상이 되면 24시간 동안 이용이 제한돼 로그인하거나 지원할 수 없어요.\n'
    '24시간이 지나면 제한이 자동으로 풀려요.';
const _sLimB = '최근 90일 노쇼 기록이 3회 이상이면 24시간 지원이 제한됩니다.\n'
    '제한 기간이 지나면 자동으로 해제되니 기다려 주세요.\n'
    '이의가 있으면 앱 내 "문의하기"로 고객센터에 문의하세요.';
const _sLimA = '최근 90일 동안 노쇼 기록이 3회 이상이 되면 24시간 동안 이용이 제한돼 로그인하거나 지원할 수 없어요.\n'
    '24시간이 지나면 제한이 자동으로 풀리니 기다려 주세요.\n'
    '이의가 있으면 앱 내 "문의하기"로 고객센터에 문의하세요.';
const _sNspB = '당일명단 → 해당 근무자 → "노쇼 처리" 버튼을 누르세요. '
    '노쇼 처리 시 해당 근무자의 노쇼 기록이 1회 누적됩니다. '
    '최근 90일 3회 이상이면 근무자의 지원이 1일 제한됩니다.';
const _sNspA = '당일명단 → 해당 근무자 → "노쇼 처리" 버튼을 누르세요. '
    '노쇼로 처리하면 그 근무자에게 노쇼 기록이 1회 남아요.\n'
    '최근 90일 동안 노쇼 기록이 3회 이상이 되면 그 근무자는 24시간 동안 이용이 제한돼 로그인하거나 지원할 수 없어요.';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '580';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du580uxw4-tb' && _env['DU_BEFORE_OBSERVE'] == '580') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du580uxw4-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

/// before = 지금 A 원문 · strict = 후보 원문.
String _w(String before, String after) => _before ? before : after;

/// 시드 FAQ 항목 — 저장 순서 · 분류는 help_faq_service 와 같은 값(이 셀이 바꾸는 항목과 그 분류 제목만).
List<HelpFaqModel> _seedItems(bool admin) => admin
    ? [_h(0, '📅 당일 출퇴근 관리'), _q(1, '📅 당일 출퇴근 관리', '노쇼 처리는 어떻게 하나요?', _w(_sNspB, _sNspA))]
    : [
        _h(0, '📋 공고 & 지원'),
        _q(1, '📋 공고 & 지원', '지원 취소는 어떻게 하나요?', _w(_sCanB, _sCanA)),
        _h(2, _w(_sHdrB, _sHdrA)),
        _q(3, _w(_sHdrB, _sHdrA), '노쇼 기록은 언제 남나요?', _w(_sRecB, _sRecA)),
        _q(4, _w(_sHdrB, _sHdrA), '지원이 막혔어요. 어떻게 하나요?', _w(_sLimB, _sLimA)),
      ];

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

/// [DU580] 도움말 사례 — DU571 `_limitCase` 의 틀(guard · 캡처 · 정리 · 집계)을 그대로 쓰고, 앱 · 여는 것 · 재는 글만 바꿨다
///   (UserProvider 역할 대역 · home = HelpScreen(load 주입) · 질문 펼침 = onTap 콜백 · 누르는 것 0).
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
  _out('D580 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
    _out('D580 $tok att scr n=$nScr');
    need('화면 1', nScr == 1, '개수 $nScr');
    Future<void> shot(String id, String state) async {
      _out('D580 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    var opened = 0;
    if (!c.seed && !c.admin) {
      // 내장 FAQ 사용자 — '공고 & 지원' 둘째 질문(지원 취소) → 아래로 '노쇼 & 이용 제한' 분류 제목 → 그 둘째 질문(지원이 제한됐어요).
      await _reach(t, host, (s) => s == '지원 취소는 어떻게 하나요?');
      opened += await _open(t, host, '지원 취소는 어떻게 하나요?');
      final can = await _seeText(t, host, (s) => s == _w(_canB, _canA), screen);
      _out('D580 $tok att can n=${can.n} name=${can.name} full=${can.full} brk=${can.brk} lines=${can.lines} vis=${can.vis}');
      await shot('1can', 'answer-top');
      await _toEnd(t, host, (s) => s == _w(_canB, _canA));
      await shot('2cane', 'answer-end');
      await _reach(t, host, (s) => s == _w(_hdrB, _hdrA));
      final hdr = await _seeText(t, host, (s) => s == _w(_hdrB, _hdrA), screen);
      _out('D580 $tok att hdr n=${hdr.n} name=${hdr.name} full=${hdr.full} brk=${hdr.brk} lines=${hdr.lines} vis=${hdr.vis}');
      await shot('3hdr', 'category');
      await _reach(t, host, (s) => s == '지원이 제한됐어요. 원인이 뭔가요?');
      opened += await _open(t, host, '지원이 제한됐어요. 원인이 뭔가요?');
      final lim = await _seeText(t, host, (s) => s == _w(_limB, _limA), screen);
      _out('D580 $tok att lim n=${lim.n} name=${lim.name} full=${lim.full} brk=${lim.brk} lines=${lim.lines} vis=${lim.vis}');
      await shot('4lim', 'answer-top');
      await _toEnd(t, host, (s) => s == _w(_limB, _limA));
      await shot('5lime', 'answer-end');
      raw = 'can $can hdr $hdr lim $lim';
    } else if (!c.seed) {
      // 내장 FAQ 관리자 — '당일 출퇴근 관리' 셋째 질문(노쇼 처리).
      await _reach(t, host, (s) => s == '노쇼 처리는 어떻게 하나요?');
      opened += await _open(t, host, '노쇼 처리는 어떻게 하나요?');
      final nsp = await _seeText(t, host, (s) => s == _w(_nspB, _nspA), screen);
      _out('D580 $tok att nsp n=${nsp.n} name=${nsp.name} full=${nsp.full} brk=${nsp.brk} lines=${nsp.lines} vis=${nsp.vis}');
      await shot('1nsp', 'answer-top');
      await _toEnd(t, host, (s) => s == _w(_nspB, _nspA));
      await shot('2nspe', 'answer-end');
      raw = 'nsp $nsp';
    } else if (!c.admin) {
      // 시드 FAQ 사용자 — 지원 취소 → 분류 제목 → 노쇼 기록은 언제 남나요? → 지원이 막혔어요.
      await _reach(t, host, (s) => s == '지원 취소는 어떻게 하나요?');
      opened += await _open(t, host, '지원 취소는 어떻게 하나요?');
      final can = await _seeText(t, host, (s) => s == _w(_sCanB, _sCanA), screen);
      _out('D580 $tok att can n=${can.n} name=${can.name} full=${can.full} brk=${can.brk} lines=${can.lines} vis=${can.vis}');
      await shot('1can', 'answer-top');
      await _toEnd(t, host, (s) => s == _w(_sCanB, _sCanA));
      await shot('2cane', 'answer-end');
      await _reach(t, host, (s) => s == _w(_sHdrPlainB, _hdrA));
      final hdr = await _seeText(t, host, (s) => s == _w(_sHdrPlainB, _hdrA), screen);
      _out('D580 $tok att hdr n=${hdr.n} name=${hdr.name} full=${hdr.full} brk=${hdr.brk} lines=${hdr.lines} vis=${hdr.vis}');
      await shot('3hdr', 'category');
      await _reach(t, host, (s) => s == '노쇼 기록은 언제 남나요?');
      opened += await _open(t, host, '노쇼 기록은 언제 남나요?');
      final rec = await _seeText(t, host, (s) => s == _w(_sRecB, _sRecA), screen);
      _out('D580 $tok att rec n=${rec.n} name=${rec.name} full=${rec.full} brk=${rec.brk} lines=${rec.lines} vis=${rec.vis}');
      await shot('4rec', 'answer-top');
      await _toEnd(t, host, (s) => s == _w(_sRecB, _sRecA));
      await shot('5rece', 'answer-end');
      await _reach(t, host, (s) => s == '지원이 막혔어요. 어떻게 하나요?');
      opened += await _open(t, host, '지원이 막혔어요. 어떻게 하나요?');
      final lim = await _seeText(t, host, (s) => s == _w(_sLimB, _sLimA), screen);
      _out('D580 $tok att lim n=${lim.n} name=${lim.name} full=${lim.full} brk=${lim.brk} lines=${lim.lines} vis=${lim.vis}');
      await shot('6lim', 'answer-top');
      await _toEnd(t, host, (s) => s == _w(_sLimB, _sLimA));
      await shot('7lime', 'answer-end');
      raw = 'can $can hdr $hdr rec $rec lim $lim';
    } else {
      // 시드 FAQ 관리자 — 노쇼 처리.
      await _reach(t, host, (s) => s == '노쇼 처리는 어떻게 하나요?');
      opened += await _open(t, host, '노쇼 처리는 어떻게 하나요?');
      final nsp = await _seeText(t, host, (s) => s == _w(_sNspB, _sNspA), screen);
      _out('D580 $tok att nsp n=${nsp.n} name=${nsp.name} full=${nsp.full} brk=${nsp.brk} lines=${nsp.lines} vis=${nsp.vis}');
      await shot('1nsp', 'answer-top');
      await _toEnd(t, host, (s) => s == _w(_sNspB, _sNspA));
      await shot('2nspe', 'answer-end');
      raw = 'nsp $nsp';
    }
    _out('D580 $tok att open n=$opened');
    if (c.seed) {
      // 시드 소스 대조 — 지금 모드의 글은 정확한 수만큼 · 다른 모드의 글은 0.
      final src = File('lib/services/help_faq_service.dart').readAsStringSync();
      final want = c.admin
          ? {_w(_sNspB, _sNspA): 1}
          : {_w(_sCanB, _sCanA): 1, _w(_sRecB, _sRecA): 1, _w(_sLimB, _sLimA): 1, _w(_sHdrB, _sHdrA): 3};
      final other = c.admin ? [_w(_sNspA, _sNspB)] : [_w(_sCanA, _sCanB), _w(_sRecA, _sRecB), _w(_sLimA, _sLimB), _w(_sHdrA, _sHdrB)];
      final ok = want.entries.every((e) => _srcCount(src, e.key) == e.value);
      final old = other.fold<int>(0, (a, s) => a + _srcCount(src, s));
      _out('D580 $tok att src ok=$ok old=$old');
      raw = '$raw src ok=$ok old=$old';
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
  _out('D580 $tok att wire cf=$nCf unexpected=$nUnexp http=$nHttp');
  messenger.allMessagesHandler = prevAll;
  HttpOverrides.global = prevHttp;
  final exc = t.takeException();
  if (exc != null && failure == null) {
    failure = exc;
    failureSt = StackTrace.current;
  }
  final nOvf = seen.overflows.length;
  final nFw = seen.other.length;
  _out('R580 $tok raw m64=${_enc(raw)} ovf64=${_enc(seen.overflows.join('\n----\n'))} fw64=${_enc(seen.other.join('\n----\n'))} '
      'un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D580 $tok att fw n=$nFw');
  _out('D580 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');
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
    _out('R580 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S580HC-${v.id}-${c.id} 도움말 노쇼 · 이용 제한 안내(UXW-4)', (t) async {
        final tok = 'S580HC-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _helpCase(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
