// ignore_for_file: depend_on_referenced_packages
// [DU560 · UXW-1a · 문구만] DU-O002 '빈자리 다시 모집'(좌석 반납 · 정원 복구 행동) + F156-RAW-STATE(확인창 'NO_SHOW' 원문 노출) — 판정156 Q1 · §5 · 판정160 §3–§4.
//   바뀐 글: 확정 카드 버튼 '대체 인력 충원' → '빈자리 다시 모집' · 배지 '대체 충원 진행 중' → '자리 비움'(staffingReleasedAt 존재만 읽는 사실 칩 · '(노쇼)' 없음) ·
//     확인창 제목/본문/확인('빈자리 다시 모집' · '○○님의 오늘 근무가 노쇼로 기록됐어요. 이 자리를 비우고 다시 모집해요.' ·
//     '확정 기록은 그대로 남고, 이 근무가 차지하던 1자리를 모집 정원으로 돌려요.' · '다시 모집') · 성공 토스트 '자리 비움 처리를 완료했어요' ·
//     서비스(application_firestore) 처리 중 '빈자리 다시 모집 처리 중...'(유지) · 실패 기본 문구 2 '빈자리 다시 모집 처리 결과를 확인하지 못했어요'.
//   before = 지금 A(day_applicants_dialog 4618577d · application_firestore 7108a251) 기록 · strict = 후보(a215de81 · bd7407c8).
//   하네스 = DU535 시험(7894ebcf) 날짜별 창 부분(DU526 계보 · 홈 → '인원 현황 보기' → 창)의 **블록 재사용**(prep/mk_test.py 단언 · 전체 바이트 동일 아님) —
//     바뀐 것: 머리 주석 · 보기 N(320×640@1.0) 추가 · 시계 M1(실제 KST 오늘 10:00 → 그날 자정 · DU535 _day/NCG kDay 의 'KST 오늘+3일 자정'과 다른 식) ·
//     대역 M2–M6(좌석 반납 시각 · 이름 2 · 노쇼 읽기 값 · NOSHOW 대역) · 측정 구간(title · btn · badge) ·
//     확인창 사례(DU285 방식 — 실제 DialogHelper.showConfirm 으로 열고 Navigator.pop 으로 닫는다 · O002 업무 버튼 경로가 아닌 같은 식 재구성 · _tpWidth = DU285 299ab572).
//   누르는 것: 홈 '인원 현황 보기' · 하단 '닫기'(DU535 와 같다). 빈자리 다시 모집 버튼 · 확인창 두 버튼은 누르지 않는다(쓰기 0 · CF 0).
//   토스트 · 처리 중 덮개(서버 응답 뒤에만 뜬다)는 그리지 않는다 — 확인창 사례의 `att src` 는 지금 A 소스에 대한 contains 판정 10개의 충족 수다
//     (이 모드 10 · 다른 모드 0 · 리터럴 발생 횟수 전수검사 아님 · 판정160 §5).
//   기본 skip — TB before/du560uxw1-tb/DU_BEFORE_OBSERVE=560 · TA after/du560uxw1-ta/없음.
import 'dart:async';
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
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_home_summary_model.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/models/ui/staffing_readiness_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_home_reads.dart';
import 'package:ALfit/screens/business_admin/business_admin_home_screen.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_reads.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';

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
const _authFake = 'du560.fake.auth.';
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

/// [DU285 du1_dialog_words_285_test.dart:152–158 그대로] TextPainter 한 줄 폭.
double _tpWidth(String text, TextStyle style, TextScaler scaler, Locale? locale) {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: scaler, locale: locale)
    ..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

typedef _V = ({String id, double w, double h, double s});

const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0), (id: 'N', w: 320.0, h: 640.0, s: 1.0)];
const _cases = <({String id, int shots})>[(id: 'NOSHOW', shots: 2), (id: 'CONFIRM', shots: 1)];

/// 이 셀이 바꾸는 글(모드별) — before = 지금 A 리터럴 · after = 후보 리터럴(prep/mk_cand.py 와 같은 값 · mkcell 이 대조한다).
typedef _W = ({String btn, String badge, String title, String msg1, String msg2, String ok, String toast, String load, String fail});
const _W _wBefore = (
  btn: '대체 인력 충원', badge: '대체 충원 진행 중', title: '대체 인력 충원',
  msg1: '의 NO_SHOW 자리를 반납하여 대체 인력 모집을 시작합니다.', msg2: '기존 확정 이력은 유지되며, 모집 정원이 복구됩니다.',
  ok: '충원 시작', toast: '대체 인력 모집이 시작되었습니다', load: '대체 인력 충원 처리 중...', fail: '대체 충원 처리에 실패했습니다',
);
const _W _wAfter = (
  btn: '빈자리 다시 모집', badge: '자리 비움', title: '빈자리 다시 모집',
  msg1: '님의 오늘 근무가 노쇼로 기록됐어요. 이 자리를 비우고 다시 모집해요.', msg2: '확정 기록은 그대로 남고, 이 근무가 차지하던 1자리를 모집 정원으로 돌려요.',
  ok: '다시 모집', toast: '자리 비움 처리를 완료했어요', load: '빈자리 다시 모집 처리 중...', fail: '빈자리 다시 모집 처리 결과를 확인하지 못했어요',
);

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '560';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du560uxw1-tb' && _env['DU_BEFORE_OBSERVE'] == '560') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du560uxw1-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

final _W _w = _before ? _wBefore : _wAfter;
final _W _wOther = _before ? _wAfter : _wBefore;

/// 확인창 이름 — NOSHOW 대역 n1 과 같은 사람.
const _dName = '최노쇼';

/// 판정156 Q1 제목안 — 이 셀은 바꾸지 않는다(판정160 §3-1: 제목은 UXW-2 시작 명칭 셀). 머리 제목 칸에서 같은 글꼴 · 배율의 한 줄 폭만 잰다(기록만 · 후보 렌더 아님).
const _altTitle = '지원·근무 현황';

/// 소스 원문에서 `//` 로 시작하는 줄(주석)을 뺀다(connection_journey · past_noshow 시험의 `_codeOf` 와 같은 식).
String _code(String s) => s.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// 소스 대조 틀의 작은따옴표 한 글자.
const _q = "'";

// [UXW-1a] 아래 날짜별 창 대역 · 읽기 경계 · guard 는 DU535 시험(7894ebcf) :792–1271 을 바이트 그대로 옮기고 [UXW-1a M1–M6] 표시 6곳만 바꿨다.
// ───────────── 날짜별 창(DU-O002) 대역 · 읽기 경계 · guard — DU526 시험(3b30a391)에서 가져왔다(private 이름 앞에 d · 값은 그대로) ─────────────
const _dBiz1 = 'biz1';
const _dBiz2 = 'biz2';
const _dBizName = '강남 물류센터';
const _dLongBiz = '강남구 테헤란로 제2물류센터 야간 상하차 전용 창고'; // CP04 · CP01 인계 긴 사업장
const _dLongName = '응우옌 티 프엉 타오 쩐'; // CP01-C1 · CP04 인계 긴 이름(띄어쓰기 있음)
const _dLatinName = 'KHAMPHOUVONGSOUKSAVANH'; // 띄어쓰기 없는 긴 로마자 이름
const _dLongTitle = '수도권 남부 통합 물류센터 야간 상하차 및 분류 보조 단기 모집';
const _dLongWork = '냉장·냉동 식품 분류 및 출고 검수 보조';
const _dNightTitle = '야간 상하차 단기';

/// 소유자(BUSINESS_ADMIN) — 홈(CP04 _DOwner)과 창(ARO _DOwner · PCL _DAdminP)이 실제로 부르는 판정을 허용으로 준다.
///   창은 `canForBusiness`(private _dCurrentUser 를 읽는다) · `watchBusinessPermissions` 를 부르므로 둘 다 대역에서 답한다.
class _DOwner extends UserProvider {
  _DOwner({this.bizIds = const [_dBiz1]});
  final List<String> bizIds;
  final watched = <String>[];
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: bizIds, sealBase64: 'seal');
  @override
  bool get isSubAdmin => false;
  @override
  String? get effectiveBusinessId => null;
  @override
  bool get subAdminPermissionsLoaded => true;
  @override
  PermissionWatchState get currentBusinessPermissionHealth => PermissionWatchState.verified;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForAnyBusiness(bool Function(MemberPermissions p) check, {required bool whenUnknown}) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  VoidCallback watchBusinessPermissions(String businessId) {
    watched.add(businessId);
    return () {};
  }
}

// ── [UXW-1a M1 · F160-DAY-REUSE-DOC 정정] 시각(KST) — **실제 KST 오늘** 10:00 을 시계로 두고, 창 날짜는 그날 KST 자정(_dToday = FormatHelper.toKstDate)이다.
//   씨앗의 DU535 _day · noshow_contract_dialog_gate kDay 는 'KST 오늘+3일 자정'이라 이 식과 **다르다**(같은 식 아님 · 판정160 §5). 빈자리 다시 모집 버튼은
//   창 날짜 = 실제 KST 오늘일 때만 선다(day_applicants_dialog _isReplacementActionable · CF 도 workDate 가 있으면 당일만). DU1_VQ_DATE 고정일은 실행일과 달라 쓰지 않는다. ──
final DateTime _dClock = () {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day, 10).subtract(const Duration(hours: 9));
}();
final DateTime _dToday = FormatHelper.toKstDate(_dClock);
final String _dYmd = '${_dToday.year}-${_dToday.month.toString().padLeft(2, '0')}-${_dToday.day.toString().padLeft(2, '0')}';
// 상대 시각은 창이 실제 DateTime.now() 로 센다(day_applicants_dialog.dart:4415) — 실행 시각 기준 3시간 전으로 둔다.
final DateTime _dApplied = DateTime.now().subtract(const Duration(hours: 3));
final DateTime _dInvAt = DateTime.now().subtract(const Duration(hours: 5));

BusinessModel _dBusiness(String id, String name) => BusinessModel(
    id: id, name: name, ownerId: 'admin1', businessNumber: '000-00-00000', address: '서울시 어딘가',
    category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));

Map<String, dynamic> _dBiz(String id, String name, int req, int conf, int short) =>
    {'businessId': id, 'businessName': name, 'requiredCount': req, 'confirmedCount': conf, 'shortageCount': short};

Map<String, dynamic> _dDay(int req, int conf, int short, {int? pending, List<Map<String, dynamic>> byBusiness = const []}) => {
      'date': _dYmd, 'requiredCount': req, 'confirmedCount': conf, 'shortageCount': short,
      if (pending != null) 'pendingCount': pending, 'pendingAvailable': pending != null, 'byBusiness': byBusiness,
    };

StaffingReadinessModel _dStaffing(Map<String, dynamic> d) =>
    StaffingReadinessModel(available: true, publishedPostingCount: 1, days: [StaffingDayData.fromMap(d)]);

class _DTemplate extends Fake implements ContractTemplateModel {
  @override
  bool get isSupportedForNewUse => true;
}

Map<String, BusinessPostingReadiness> _dReady(List<BusinessModel> bizs) => {
      for (final b in bizs)
        b.id: BusinessPostingReadiness(
            bizId: b.id, isApproved: true, hasCanonicalLicense: true, hasOwnerLegacyLicense: false,
            hasActiveWorkTypes: true, hasEmployerSeal: true),
    };

/// 할 일 canonical — 전부 0(CP04 _dSummary 와 같은 CF 직렬화 모양 · 파싱은 production).
AdminHomeSummaryModel _dSummary() {
  Map<String, dynamic> s() => {'available': true, 'count': 0, 'byBusiness': [{'businessId': _dBiz1, 'count': 0}]};
  return AdminHomeSummaryModel.fromMap({
    'actions': {
      'resignRequest': {...s(), 'soonCount': 0, 'manualReviewCount': null},
      'approval': {...s(), 'overdueCount': 0},
      'scheduleChangeRequest': s(),
      'unsentContract': s(),
      'unclosed': {...s(), 'oldestDate': null},
      'settlementRequest': s(),
      'wageChangeRequest': s(),
      'unpaidWage': {
        ...s(), 'overdueCount': 0, 'missingDueDateCount': 0,
        'byBusiness': [{'businessId': _dBiz1, 'count': 0, 'missingDueDateCount': 0}],
      },
    },
    'upcoming': {
      'expiringContract': {...s(), 'upcomingCount': 0, 'expiredCount': 0},
    },
  });
}

ApplicationModel _dApp(String id, String status,
        {String bizId = _dBiz1, String bizName = _dBizName, String toId = 'to1', String title = '물류 단기 모집',
        String wd = 'wd1', String work = '상하차', String start = '09:00', String end = '18:00', bool starred = false,
        DateTime? invitedAt, DateTime? releasedAt}) =>
    ApplicationModel(
      id: id, uid: 'u_$id', toId: toId, slotId: 's_$toId', businessId: bizId, businessName: bizName, toTitle: title,
      selectedWorkType: work, wdId: wd, startTime: start, endTime: end, wage: 12000, wageType: 'hourly', status: status,
      workDate: _dToday, appliedAt: _dApplied, isStarred: starred, invitedAt: invitedAt,
      invitedBy: invitedAt == null ? null : 'admin1', staffingReleasedAt: releasedAt, // [UXW-1a M2] 좌석 반납 시각
    );

DayStaffingRow _dRow(
        {String toId = 'to1', String title = '물류 단기 모집', String wd = 'wd1', String work = '상하차',
        String start = '09:00', String end = '18:00', required int req, required int conf, int pend = 0}) =>
    DayStaffingRow(
      toId: toId, toTitle: title, slotId: 's_$toId', wdId: wd, workType: work, startTime: start, endTime: end,
      requiredCount: req, confirmedCount: conf, pendingCount: pend,
    );

UserModel _dPerson(String appId) {
  final uid = 'u_$appId';
  UserModel u(String name, {int? personNo, String? phone, int noShow = 0, double rating = 0}) => UserModel(
      uid: uid, username: uid, name: name, email: '$uid@alfit.local', role: UserRole.USER,
      personNo: personNo, phone: phone, recentNoShowCount: noShow, averageRating: rating);
  switch (appId) {
    case 'p1':
      return u('김별표', phone: '01012345678', rating: 4.5);
    case 'p2':
      return u('이선택');
    case 'p3':
      return u('박노쇼', noShow: 1);
    case 'c1':
      return u('최확정');
    case 'c2':
      return u('정미작성');
    case 'c3':
      return u('한서명');
    case 'c4':
      return u('오관리');
    case 'i9':
      return u('문마감');
    case 'l1':
      return u(_dLongName, personNo: 123);
    case 'l2':
      return u(_dLatinName);
    case 'l3':
      return u('남궁하늘빛나리');
    case 'm1':
      return u('서다사업');
    case 'm2':
      return u('윤확정');
    case 'm3':
      return u('장미작성');
    case 'i1':
      return u('강초대');
    case 'n1': // [UXW-1a M3] 오늘 노쇼로 기록된 확정(빈자리 다시 모집 버튼)
      return u('최노쇼');
    case 'n2': // [UXW-1a M3] 좌석을 반납한 확정(자리 비움 배지)
      return u('한반납');
    default:
      return u('근로자 $appId');
  }
}

typedef _DFx = ({
  List<String> bizIds,
  List<BusinessModel> businesses,
  StaffingReadinessModel staffing,
  String dialogBiz,
  List<ApplicationModel> pending,
  List<ApplicationModel> confirmed,
  List<ApplicationModel> invites,
  List<DayStaffingRow> rows,
  Map<String, int> caps,
  Map<String, String> contracts,
  Map<String, UserModel> users,
  bool failFirst,
  bool rowsFail,
  bool invitesFail,
  bool capsFail,
  Set<String> noShow, // [UXW-1a M4] 그 날짜 근태가 NO_SHOW 인 지원서 id(읽기 값)
});

_DFx _dFx(List<BusinessModel> businesses, StaffingReadinessModel staffing,
    {List<String> bizIds = const [_dBiz1], String dialogBiz = _dBiz1, List<ApplicationModel> pending = const [],
    List<ApplicationModel> confirmed = const [], List<ApplicationModel> invites = const [],
    List<DayStaffingRow> rows = const [], Map<String, int> caps = const {}, Map<String, String> contracts = const {},
    bool failFirst = false, bool rowsFail = false, bool invitesFail = false, bool capsFail = false, Set<String> noShow = const {}}) {
  final users = {for (final a in [...pending, ...confirmed, ...invites]) a.uid: _dPerson(a.id)};
  return (
    bizIds: bizIds, businesses: businesses, staffing: staffing, dialogBiz: dialogBiz, pending: pending,
    confirmed: confirmed, invites: invites, rows: rows, caps: caps, contracts: contracts, users: users,
    failFirst: failFirst, rowsFail: rowsFail, invitesFail: invitesFail, capsFail: capsFail, noShow: noShow,
  );
}

/// 상태별 대역 — 각 사례가 새로 만든다(공유 상태 0). 홈 오늘 부족 > 0 이어야 '인원 현황 보기' 행이 선다(:2882).
_DFx _dFixture(String id) {
  final single = [_dBusiness(_dBiz1, _dBizName)];
  final multi = [_dBusiness(_dBiz1, _dBizName), _dBusiness(_dBiz2, _dLongBiz)];
  ApplicationModel night(String appId, String st, {DateTime? invitedAt, bool starred = false}) => _dApp(appId, st,
      bizId: _dBiz2, bizName: _dLongBiz, toId: 'to2', title: _dNightTitle, wd: 'wdA', start: '18:00', end: '23:00',
      invitedAt: invitedAt, starred: starred);
  switch (id) {
    case 'SHORT':
    case 'FAIL':
      return _dFx(single, _dStaffing(_dDay(5, 2, 3, byBusiness: [_dBiz(_dBiz1, _dBizName, 5, 2, 3)])),
          confirmed: [_dApp('c1', AppStatus.confirmed), _dApp('c2', AppStatus.confirmed)],
          rows: [_dRow(req: 5, conf: 2)], caps: const {'wd1': 5}, contracts: const {'c1': 'completed'},
          failFirst: id == 'FAIL');
    case 'FULL':
      return _dFx(single, _dStaffing(_dDay(5, 4, 1, byBusiness: [_dBiz(_dBiz1, _dBizName, 5, 4, 1)])),
          confirmed: [
            _dApp('c1', AppStatus.confirmed), _dApp('c2', AppStatus.confirmed), _dApp('c3', AppStatus.confirmed),
            _dApp('c4', AppStatus.confirmed, wd: 'wd2', work: '포장', start: '13:00', end: '22:00'),
          ],
          invites: [_dApp('i9', AppStatus.invited, invitedAt: _dInvAt)],
          rows: [_dRow(req: 3, conf: 3), _dRow(wd: 'wd2', work: '포장', start: '13:00', end: '22:00', req: 2, conf: 1)],
          caps: const {'wd1': 3, 'wd2': 2},
          contracts: const {'c1': 'completed', 'c2': 'pending_worker', 'c3': 'pending_employer'});
    case 'PEND':
      return _dFx(single, _dStaffing(_dDay(4, 1, 3, pending: 3, byBusiness: [_dBiz(_dBiz1, _dBizName, 4, 1, 3)])),
          pending: [_dApp('p1', AppStatus.pending, starred: true), _dApp('p2', AppStatus.pending), _dApp('p3', AppStatus.pending)],
          confirmed: [_dApp('c1', AppStatus.confirmed)], rows: [_dRow(req: 4, conf: 1, pend: 3)],
          caps: const {'wd1': 4}, contracts: const {'c1': 'completed'});
    case 'UNK':
      return _dFx(single, _dStaffing(_dDay(5, 2, 3, byBusiness: [_dBiz(_dBiz1, _dBizName, 5, 2, 3)])),
          pending: [_dApp('p2', AppStatus.pending)],
          confirmed: [_dApp('c1', AppStatus.confirmed), _dApp('c2', AppStatus.confirmed)],
          contracts: const {'c1': 'completed'}, rowsFail: true, invitesFail: true, capsFail: true);
    case 'LONG':
      return _dFx(single, _dStaffing(_dDay(3, 1, 2, pending: 2, byBusiness: [_dBiz(_dBiz1, _dBizName, 3, 1, 2)])),
          pending: [
            _dApp('l1', AppStatus.pending, title: _dLongTitle, work: _dLongWork),
            _dApp('l2', AppStatus.pending, title: _dLongTitle, work: _dLongWork),
          ],
          confirmed: [_dApp('l3', AppStatus.confirmed, title: _dLongTitle, work: _dLongWork)],
          rows: [_dRow(title: _dLongTitle, work: _dLongWork, req: 3, conf: 1, pend: 2)], caps: const {'wd1': 3});
    case 'NOSHOW': // [UXW-1a M5] 오늘 노쇼로 기록된 확정 n1(버튼) · 좌석 반납 확정 n2(배지) · 둘 다 계약 완료(계약서 작성 버튼 없음) · 홈 부족 2
      return _dFx(single, _dStaffing(_dDay(3, 1, 2, byBusiness: [_dBiz(_dBiz1, _dBizName, 3, 1, 2)])),
          confirmed: [_dApp('n1', AppStatus.confirmed), _dApp('n2', AppStatus.confirmed, releasedAt: _dApplied)],
          rows: [_dRow(req: 3, conf: 1)], caps: const {'wd1': 3}, contracts: const {'n1': 'completed', 'n2': 'completed'},
          noShow: const {'n1'});
    case 'DBANDS': // [DU534] MULTI 와 같은 두 사업장 대역 + 대기 2(m1 별표 · m4) · 확정 2명 모두 계약 없음(계약서 미작성 띠가 선다)
      return _dFx(multi,
          _dStaffing(_dDay(8, 4, 4, byBusiness: [_dBiz(_dBiz1, _dBizName, 3, 2, 1), _dBiz(_dBiz2, _dLongBiz, 5, 2, 3)])),
          bizIds: const [_dBiz1, _dBiz2], dialogBiz: _dBiz2,
          pending: [night('m1', AppStatus.pending, starred: true), night('m4', AppStatus.pending)],
          confirmed: [night('m2', AppStatus.confirmed), night('m3', AppStatus.confirmed)],
          invites: [night('i1', AppStatus.invited, invitedAt: _dInvAt)],
          rows: [_dRow(toId: 'to2', title: _dNightTitle, wd: 'wdA', start: '18:00', end: '23:00', req: 5, conf: 2, pend: 2)],
          caps: const {'wdA': 5});
    default: // MULTI — 부족 큰 순 biz2(3) · biz1(1) → 창 첫 사업장 biz2(:3548–3553 · :479–480)
      return _dFx(multi,
          _dStaffing(_dDay(8, 4, 4, byBusiness: [_dBiz(_dBiz1, _dBizName, 3, 2, 1), _dBiz(_dBiz2, _dLongBiz, 5, 2, 3)])),
          bizIds: const [_dBiz1, _dBiz2], dialogBiz: _dBiz2,
          pending: [night('m1', AppStatus.pending)],
          confirmed: [night('m2', AppStatus.confirmed), night('m3', AppStatus.confirmed)],
          invites: [night('i1', AppStatus.invited, invitedAt: _dInvAt)],
          rows: [_dRow(toId: 'to2', title: _dNightTitle, wd: 'wdA', start: '18:00', end: '23:00', req: 5, conf: 2, pend: 1)],
          caps: const {'wdA': 5}, contracts: const {'m2': 'completed'});
  }
}

AdminHomeReads _dHomeReads(_DFx fx, Map<String, int> calls) {
  void hit(String k) => calls[k] = (calls[k] ?? 0) + 1;
  return AdminHomeReads(
    summary: ({String? selectedBusinessId}) {
      hit('summary');
      return Future.value(_dSummary());
    },
    businessesByIds: (ids) async {
      hit('businesses');
      return fx.businesses;
    },
    staffingReadiness: ({String? selectedBusinessId}) {
      hit('staffing');
      return Future.value(fx.staffing);
    },
    attendanceByDate: ({required String businessId, required DateTime date}) async {
      hit('attendance');
      return <AttendanceModel>[];
    },
    confirmedWorkers: ({required DateTime date, required String businessId}) async {
      hit('roster');
      return <ApplicationModel>[];
    },
    workDetailTimes: (_) async => <String, dynamic>{},
    postingReadiness: (bizs) async => _dReady(bizs),
    contractTemplates: (_) async => <ContractTemplateModel>[_DTemplate()],
    tourCompleted: () => Future<bool>.value(true),
    clock: () => _dClock,
    legalReadiness: () async => const LegalReadiness(status: LegalReadinessStatus.current),
  );
}

/// 창의 읽기 경계 — 호출 수 · 사업장 · 날짜 · KST 자정 · 목적을 기록한다. 실패 대역은 fixture 플래그로만.
class _DDayReads {
  _DDayReads(this.fx);
  final _DFx fx;
  final calls = <String, int>{};
  final biz = <String>{};
  final dates = <String>{};
  final dayStarts = <int>{};
  final purposes = <String>{};

  /// [r1 · 판정 §3-3] 호출별 날짜 · 주간 경계 원값(읽기 이름 → 호출 순서대로). 끝에서 고정 KST 기대와 단언한다.
  final at = <String, List<String>>{};
  var _dPendingTries = 0;

  void _dHit(String k, [String? businessId]) {
    calls[k] = (calls[k] ?? 0) + 1;
    if (businessId != null) biz.add(businessId);
  }

  void _dOn(String k, DateTime d) {
    final v = _dDk(d);
    dates.add(v);
    at.putIfAbsent(k, () => <String>[]).add(v);
  }

  DayApplicantsReads reads() => DayApplicantsReads(
        pendingApplications: ({required date, required businessId, purpose}) async {
          _dHit('pending', businessId);
          _dOn('pending', date);
          purposes.add('p:${purpose ?? '-'}');
          _dPendingTries++;
          if (fx.failFirst && _dPendingTries == 1) throw StateError('NCB-12O 관측 fixture — 첫 조회 실패');
          return fx.pending;
        },
        confirmedWorkers: ({required date, required businessId}) async {
          _dHit('confirmed', businessId);
          _dOn('confirmed', date);
          return fx.confirmed;
        },
        dayStaffing: ({required businessId, required dayStartMs}) async {
          _dHit('dayStaffing', businessId);
          dayStarts.add(dayStartMs);
          if (fx.rowsFail) throw StateError('NCB-12O 관측 fixture — 인력 현황 조회 실패');
          return fx.rows;
        },
        dayInvitations: ({required date, required businessId}) async {
          _dHit('invites', businessId);
          _dOn('invites', date);
          if (fx.invitesFail) throw StateError('NCB-12O 관측 fixture — 초대 현황 조회 실패');
          return fx.invites;
        },
        hasWorkedMap: ({required businessId, required date}) async {
          _dHit('hasWorked', businessId);
          _dOn('hasWorked', date);
          return const <String, bool>{};
        },
        noShowApplicationIds: ({required businessId, required date}) async {
          _dHit('noShow', businessId);
          _dOn('noShow', date);
          return fx.noShow; // [UXW-1a M6] 대역 값(같은 읽기 · 같은 모양)
        },
        usersBatch: (uids, {required businessId, purpose}) async {
          _dHit('users', businessId);
          purposes.add('u:${purpose ?? '-'}');
          return {for (final u in uids) if (fx.users.containsKey(u)) u: fx.users[u]!};
        },
        weeklyAttendance: ({required businessId, required weekStart, required weekEnd}) async {
          _dHit('weekly', businessId);
          at.putIfAbsent('weekly', () => <String>[]).add('${_dDk(weekStart)}..${_dDk(weekEnd)}');
          return <String, List<AttendanceModel>>{};
        },
        slotWorkDetailCapacities: (toId, slotId) async {
          _dHit('caps');
          if (fx.capsFail) throw StateError('NCB-12O 관측 fixture — 정원 조회 실패');
          return fx.caps;
        },
        slotWorkDetails: (toId, slotId) async {
          _dHit('slotWds');
          return <WorkDetailData>[];
        },
        to: (toId) async {
          _dHit('to');
          return null;
        },
        contractStatusBatch: (ids, {required businessId}) async {
          _dHit('contracts', businessId);
          return ContractStatusBatch(statuses: {for (final x in ids) if (fx.contracts.containsKey(x)) x: fx.contracts[x]});
        },
        contractAttendances: ({required businessId, required date}) async {
          _dHit('contractAtt', businessId);
          _dOn('contractAtt', date);
          return <AttendanceModel>[];
        },
      );
}

/// 날짜 원값 — 연-월-일T시:분 + 시간대 표시(Z=UTC · L=기기 지역). 창이 넘기는 값을 그대로 적는다.
String _dDk(DateTime d) => '${d.year}-${d.month}-${d.day}T${d.hour}:${d.minute}${d.isUtc ? 'Z' : 'L'}';


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


/// 1단계 읽기 넷 — '다시 시도' 실제 탭으로 각 1 → 2(DU515 r3 에서 실측된 경로).
const _dPhase1 = ['pending', 'confirmed', 'dayStaffing', 'invites'];

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


/// 상태 대역 — UNK = 인력 현황 · 초대 · 정원 조회 실패(지원 1 · 확정 2 는 유효).
_DFx _dStateFx(String id) => _dFixture(id);

/// [UXW-1a] 머리 제목 — 이 셀은 글을 바꾸지 않는다. 칸 폭(그린 문단의 최대 폭) · 지금 글 · 판정156 Q1 제목안의 한 줄 폭(같은 글꼴 · 같은 배율 · TextPainter)을 기록한다 — 단일행 폭 비교일 뿐 후보 렌더가 아니다(판정160 §3).
String _titleLine(WidgetTester t, Finder dlg, String tok) {
  final hdr = find.descendant(of: dlg, matching: find.byType(AppModalHeader), skipOffstage: false);
  final nHdr = hdr.evaluate().length;
  var cur = '';
  var w = 0.0;
  var curW = 0.0;
  var altW = 0.0;
  var lines = 0;
  var full = false;
  var ell = false;
  if (nHdr == 1) {
    final tf = find.descendant(of: hdr, matching: find.byType(Text), skipOffstage: false).first;
    final tw = t.widget<Text>(tf);
    final rp = t.renderObject<RenderParagraph>(find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: false).first);
    final ctx = t.element(tf);
    final style = DefaultTextStyle.of(ctx).style.merge(tw.style);
    final scaler = MediaQuery.textScalerOf(ctx);
    final loc = Localizations.maybeLocaleOf(ctx);
    cur = tw.data ?? '';
    w = rp.constraints.maxWidth;
    curW = _tpWidth(cur, style, scaler, loc);
    altW = _tpWidth(_altTitle, style, scaler, loc);
    lines = _lineCount(rp);
    full = _fullShown(rp, rp.size);
    ell = rp.overflow == TextOverflow.ellipsis;
  }
  _out('D560 $tok att title n=$nHdr cur=${_enc(cur)} w=${w.toStringAsFixed(1)} curw=${curW.toStringAsFixed(1)} altw=${altW.toStringAsFixed(1)} '
      'altfit=${altW <= w + 0.5} lines=$lines full=$full ell=$ell');
  return 'title n=$nHdr cur=$cur w=$w curw=$curW altw=$altW lines=$lines full=$full ell=$ell';
}

typedef _BtnObs = ({int n, bool shown, bool full, bool ell0, int brk, int lines, bool m48, bool vis, bool hit});

/// [UXW-1a] 노쇼 확정 카드의 행 버튼(긴급 · 누르지 않는다) — ensureVisible(DU535 와 같은 동작)로 화면 안에 넣은 뒤 글 · 받는 자리 · 중심 hit 를 잰다.
Future<_BtnObs> _btnLine(WidgetTester t, Finder dlg, String tok, String label, Rect screen) async {
  final tf = find.descendant(of: dlg, matching: find.byWidgetPredicate((w) => w is Text && w.data == label), skipOffstage: false);
  final n = tf.evaluate().length;
  _TextObs o = (shown: false, name: false, full: false, ell0: false, brk: 0, size: Size.zero);
  var lines = 0;
  var m48 = false;
  var vis = false;
  var hit = false;
  if (n == 1) {
    await t.ensureVisible(find.ancestor(of: tf, matching: find.byType(InkWell)).first);
    for (var m = 0; m < 4; m++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    o = _textObs(t, tf, label);
    lines = _lineCount(t.renderObject<RenderParagraph>(find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: false).first));
    final ink = find.ancestor(of: tf, matching: find.byType(InkWell)).first;
    final r = t.getRect(ink);
    m48 = r.width >= 48 - 0.01 && r.height >= 48 - 0.01;
    vis = _inside(r, _area(ink, screen));
    hit = _hitWithin(t, ink, r.center);
  }
  _out('D560 $tok att btn n=$n shown=${o.shown} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=$lines m48=$m48 vis=$vis hit=$hit');
  return (n: n, shown: o.shown, full: o.full, ell0: o.ell0, brk: o.brk, lines: lines, m48: m48, vis: vis, hit: hit);
}

typedef _BadgeObs = ({int n, bool shown, bool full, bool ell0, int brk, int lines, bool vis});

/// [UXW-1a] 좌석 반납 확정 카드의 배지 — ensureVisible 로 화면 안에 넣은 뒤 글 · 화면 안을 잰다.
Future<_BadgeObs> _badgeLine(WidgetTester t, Finder dlg, String tok, String label, Rect screen) async {
  final tf = find.descendant(of: dlg, matching: find.byWidgetPredicate((w) => w is Text && w.data == label), skipOffstage: false);
  final n = tf.evaluate().length;
  _TextObs o = (shown: false, name: false, full: false, ell0: false, brk: 0, size: Size.zero);
  var lines = 0;
  var vis = false;
  if (n == 1) {
    await t.ensureVisible(tf);
    for (var m = 0; m < 4; m++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    o = _textObs(t, tf, label);
    lines = _lineCount(t.renderObject<RenderParagraph>(find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: false).first));
    vis = _inside(t.getRect(tf), _area(tf, screen));
  }
  _out('D560 $tok att badge n=$n shown=${o.shown} full=${o.full} ell0=${o.ell0} brk=${o.brk} lines=$lines vis=$vis');
  return (n: n, shown: o.shown, full: o.full, ell0: o.ell0, brk: o.brk, lines: lines, vis: vis);
}

typedef _DlgObs = ({int n, bool full, int brk, int lines, bool vis});

/// [UXW-1a] 확인창 안 글 하나 — 그린 글(표시 제어 문자 제외)이 [want] 인 RichText 가 정확히 하나일 때 전문 · 낱말 안 끊김 · 줄 수 · 화면 안(잰 즉시 값).
_DlgObs _dlgText(WidgetTester t, Finder host, String want, Rect screen) {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == want)
      .toList();
  if (es.length != 1) return (n: es.length, full: false, brk: 0, lines: 0, vis: false);
  final rp = es.first.renderObject as RenderParagraph;
  final r = t.getRect(find.byElementPredicate((x) => identical(x, es.first), skipOffstage: false));
  return (n: 1, full: _fullShown(rp, rp.size), brk: _midBreaks(rp), lines: _lineCount(rp), vis: _inside(r, screen));
}


/// 날짜별 창(DU-O002) 사례 — DU535 하네스(홈 → '인원 현황 보기' → 창) 그대로 + [UXW-1a] 측정 구간(머리 제목 기록 · 노쇼 확정 카드 버튼 · 좌석 반납 배지).
///   쓰기 동작(빈자리 다시 모집 · 확정취소 · 계약 · 확정)은 누르지 않는다 — 홈 행과 하단 '닫기'만 누른다. 넘침 수는 기록만.
Future<void> _dayCase(WidgetTester t, _V v, ({String id, int shots}) c, String tok) async {
  // guard 를 이 사례의 어떤 초기화보다 먼저 건다(대역 · provider · 홈 생성 전). 이전 값은 모두 잡아 둔다.
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final wire = _DWire();
  final net = _DNoHttp(wire);
  final prevAll = messenger.allMessagesHandler;
  final prevHttp = HttpOverrides.current;
  final prevOnError = FlutterError.onError;
  final prevOverride = DayApplicantsReads.debugOverride;
  messenger.allMessagesHandler = (channel, handler, message) => wire.route(messenger, channel, handler, message);
  HttpOverrides.global = net;
  addTearDown(() {
    messenger.allMessagesHandler = prevAll;
    HttpOverrides.global = prevHttp;
    FlutterError.onError = prevOnError;
    DayApplicantsReads.debugOverride = prevOverride;
  });
  t.view.physicalSize = Size(v.w, v.h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final mode = _before ? 'before' : 'strict';
  _out('D560 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
  final seen = _DSeen();
  void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
  void safe(String step) => need('안전 대역($step) — 예상 밖 채널 · CF · HTTP 0', !wire.tripped && net.tries.isEmpty,
      'cf ${wire.cf.length} 예상 밖 [${wire.unexpected.join(' | ')}] http ${net.tries.length}');
  final checks = <(String, bool, String)>[];
  void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

  final fx = _dStateFx(c.id);
  final owner = _DOwner(bizIds: fx.bizIds);
  final homeCalls = <String, int>{};
  final dayReads = _DDayReads(fx);
  Object? failure;
  StackTrace? failureSt;
  var shots = 0;
  var closed = false;
  var raw = '';
  try {
    FlutterError.onError = seen.add;
    DayApplicantsReads.debugOverride = dayReads.reads();
    final key = GlobalKey();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: owner),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
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
          home: BusinessAdminHomeScreen(reads: _dHomeReads(fx, homeCalls)),
        ),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    safe('홈 열림');
    final entryF = find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? '') == '인원 현황 보기');
    final nEntry = entryF.evaluate().length;
    need('홈 인원 현황 보기 행 ≥1', nEntry >= 1, '개수 $nEntry');
    await t.ensureVisible(entryF.first);
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(find.ancestor(of: entryF.first, matching: find.byType(InkWell)).first);
    for (var i = 0; i < 24; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final dlg = find.byType(DayApplicantsDialog);
    final nDlg = dlg.evaluate().length;
    need('창 1', nDlg == 1, '개수 $nDlg');
    safe('창 열림');
    Future<void> shot(String id, String state) async {
      _out('D560 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    // ① 첫 화면 — [UXW-1a] 머리 제목(이 셀은 바꾸지 않는다 · 판정156 Q1 제목안의 같은 칸 한 줄 폭만 기록 — 후보 렌더 아님 · 제목은 UXW-2 명칭 셀 · 판정160 §3-1).
    await shot('1top', 'list-open');
    safe('첫 캡처');
    final screen = Offset.zero & Size(v.w, v.h);
    final ho = _titleLine(t, dlg, tok);
    // ② 노쇼 확정 카드 — 빈자리 다시 모집 버튼 · 좌석 반납 배지(누르지 않는다 · ensureVisible 로 화면 안에 넣기만).
    final bo = await _btnLine(t, dlg, tok, _w.btn, screen);
    safe('버튼 재기');
    final go = await _badgeLine(t, dlg, tok, _w.badge, screen);
    safe('배지 재기');
    await shot('2noshow', 'noshow-card');
    safe('카드 캡처');
    raw = '$ho btn $bo badge $go';

    // ④ 닫기
    final closeF = find.descendant(of: find.byType(AppModalFooter), matching: find.widgetWithText(TextButton, '닫기'), skipOffstage: true);
    final nClose = closeF.evaluate().length;
    need('하단 닫기 1', nClose == 1, '개수 $nClose');
    await t.tap(closeF);
    for (var i = 0; i < 16; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final nAfter = find.byType(DayApplicantsDialog).evaluate().length;
    closed = nAfter == 0;
    safe('닫기');
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // ⑤ 성공 · 실패 공통 정리 — 홈 · 창을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다. guard 는 아직 걸려 있다.
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

  // ⑥ 최종 안전 집계 — 해제 · 대기 뒤 guard 아래에서 센다(값 측정과 분리).
  final p1ok = _dPhase1.every((k) => (dayReads.calls[k] ?? 0) == 1);
  final p1Text = [for (final k in _dPhase1) '$k*${dayReads.calls[k] ?? 0}'].join(',');
  final nUnexp = wire.unexpected.length;
  final nCf = wire.cf.length;
  final nHttp = net.tries.length;
  final tripped = wire.tripped;
  final unText = wire.unexpected.join(' | ');
  _out('D560 $tok att reader p1=$p1ok closed=$closed cf=$nCf unexpected=$nUnexp http=$nHttp');

  messenger.allMessagesHandler = prevAll;
  HttpOverrides.global = prevHttp;
  DayApplicantsReads.debugOverride = prevOverride;
  final exc = t.takeException();
  if (exc != null && failure == null) {
    failure = exc;
    failureSt = StackTrace.current;
  }
  final nOvf = seen.overflows.length;
  final nFw = seen.other.length;
  final ovfRaw = seen.overflows.join('\n----\n');
  final fwRaw = seen.other.join('\n----\n');
  _out('R560 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
      'fail64=${_enc(failure?.toString() ?? '')}');
  _out('D560 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  if (!_before) chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
  chk('캡처 수 = 선언', shots == c.shots, 'shots $shots want ${c.shots}');
  chk('읽기 1단계 호출 수(해제 · 대기 뒤) · 닫힘', p1ok && closed, 'p1 $p1Text want 각 1 closed $closed');
  chk('시험 전체 CF 0 · 예상 밖 채널 0 · HTTP 0(해제 · 대기 뒤)', nCf == 0 && nUnexp == 0 && nHttp == 0 && !tripped,
      'cf $nCf 예상 밖 [$unText] http $nHttp tripped $tripped');
  final bad = checks.where((x) => !x.$2).toList();
  if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
  for (final x in checks) {
    expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
  }
}

/// [UXW-1a] 확인창 사례 — DU285 와 같은 방식: 실제 `DialogHelper.showConfirm` 으로 열고 재고 `Navigator.pop` 으로 닫는다(누르는 것 0 · 쓰기 0).
///   글은 O002 호출부(day_applicants_dialog `_releaseNoshowSeatInner`)와 같은 식으로 만든다 — 이름(NOSHOW 대역 n1 '최노쇼') + 리터럴 두 조각 + 확인 글 ·
///   confirmColor warning. 그 리터럴이 **지금 A 소스**(주석 줄 제외)에 있는지 `att src` 가 contains 판정 10개로 센다(now = 이 모드 충족 수 · other = 다른 모드 충족 수 ·
///   리터럴 발생 횟수 전수검사가 아니다 · 판정160 §5).
Future<void> _confirmCase(WidgetTester t, _V v, ({String id, int shots}) c, String tok) async {
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
  _out('D560 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
  final seen = _DSeen();
  void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
  final screen = Offset.zero & Size(v.w, v.h);

  // 소스 대조(주석 줄 제외) — 버튼 · 배지 · 확인창 · 성공 토스트(O002) · 처리 중 · 실패 두 곳(서비스).
  final day = _code(File('lib/screens/business_admin/dialogs/day_applicants_dialog.dart').readAsStringSync());
  final svc = _code(File('lib/services/firestore/application_firestore.dart').readAsStringSync());
  //   작은따옴표는 상수 _q 로 잇는다(따옴표 안 단일 보간 형태를 만들지 않는다 · preflight 단일 보간 규칙).
  List<bool> marks(_W x) => [
        day.contains('label: $_q${x.btn}$_q'),
        day.contains('$_q${x.badge}$_q,'),
        day.contains('title: $_q${x.title}$_q'),
        day.contains('?? $_q해당 근무자$_q}${x.msg1}'),
        day.contains('$_q${x.msg2}$_q,'),
        day.contains('confirmText: $_q${x.ok}$_q'),
        day.contains('showSuccess($_q${x.toast}$_q)'),
        svc.contains('show($_q${x.load}$_q)'),
        svc.contains('e.message ?? $_q${x.fail}$_q'),
        svc.contains('showError($_q${x.fail}$_q)'),
      ];
  final nNow = marks(_w).where((x) => x).length;
  final nOther = marks(_wOther).where((x) => x).length;
  _out('D560 $tok att src now=$nNow other=$nOther');

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
        theme: RoleTheme.businessAdminTheme,
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
    final msg = '$_dName${_w.msg1}\n${_w.msg2}';
    unawaited(DialogHelper.showConfirm(t.element(scaffoldF),
        title: _w.title, message: msg, confirmText: _w.ok, cancelText: '취소', confirmColor: AppColors.warning));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final host = find.byType(Dialog);
    final nDlg = host.evaluate().length;
    _out('D560 $tok att dlg n=$nDlg');
    need('확인창 1', nDlg == 1, '개수 $nDlg');
    final tiO = _dlgText(t, host, _w.title, screen);
    final boO = _dlgText(t, host, msg, screen);
    final okO = _dlgText(t, host, _w.ok, screen);
    final noO = _dlgText(t, host, '취소', screen);
    _out('D560 $tok att dtitle n=${tiO.n} full=${tiO.full} brk=${tiO.brk} lines=${tiO.lines} vis=${tiO.vis}');
    _out('D560 $tok att dbody n=${boO.n} full=${boO.full} brk=${boO.brk} lines=${boO.lines} vis=${boO.vis}');
    _out('D560 $tok att dok n=${okO.n} full=${okO.full} brk=${okO.brk} lines=${okO.lines} vis=${okO.vis}');
    _out('D560 $tok att dno n=${noO.n} full=${noO.full} brk=${noO.brk} lines=${noO.lines} vis=${noO.vis}');
    _out('D560 $tok shot 1confirm ovf=${seen.overflows.length}');
    await vqCapture(t, key, '${tok}_1confirm', conditions: {
      'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
      'fixture': c.id, 'state': 'confirm-open',
    });
    shots++;
    raw = 'title $tiO body $boO ok $okO no $noO';
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
  _out('D560 $tok att wire cf=$nCf unexpected=$nUnexp http=$nHttp');
  messenger.allMessagesHandler = prevAll;
  HttpOverrides.global = prevHttp;
  final exc = t.takeException();
  if (exc != null && failure == null) {
    failure = exc;
    failureSt = StackTrace.current;
  }
  final nOvf = seen.overflows.length;
  final nFw = seen.other.length;
  _out('R560 $tok raw m64=${_enc(raw)} ovf64=${_enc(seen.overflows.join('\n----\n'))} fw64=${_enc(seen.other.join('\n----\n'))} '
      'un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D560 $tok att fw n=$nFw');
  _out('D560 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');
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
    _out('R560 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  tearDown(() {
    DayApplicantsReads.debugOverride = null;
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S560UX-${v.id}-${c.id} 빈자리 다시 모집 · 노쇼 확인창 문구(UXW-1a)', (t) async {
        final tok = 'S560UX-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        if (c.id == 'CONFIRM') {
          await _confirmCase(t, v, c, tok);
        } else {
          await _dayCase(t, v, c, tok);
        }
      }, skip: !_optIn);
    }
  }
}
