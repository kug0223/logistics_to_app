// ignore_for_file: depend_on_referenced_packages
// [DU623b · 판정206 §5 새 배치 셀 · 표시만] DU-O001 근태 현황(attendance_status_dialog) — F206-OATT-BADGE-OVERFLOW + 장부143 [+ 판정207 근태 기준 적용 창 brand].
//   OATT: 좌석 반납 배지 칩(_buildStaffingReleasedBadge) 안 글이 B 320@2.0 에서 칩 밖으로 넘쳤다(판정206 :47 · 20px) — strict 넘침 0 · 글 전문/끊김/보임.
//     067 진입 · 확인창 글과 092 brand 는 이미 A(eb172262)에 있다 — 두 모드 같은 글 · 옛 글 0(att alt) · 회귀로 보존(판정206 :65).
//   ROUND 갈래(판정207 §5 :96): ROUND 출근 같은 결과 2명 · RMIX changed 1 + unchanged 1(다른 결과 → 기준 적용) · RSIX 5명 초과(외 1명) · ROUT 퇴근 — 주 행동 brand(092) · 시트 시각 두 표시 · 두 행동 48 · 창 색(pcol) · 아래 줄(pextra) · 이름/회색 메타(pmeta 기록). 정확 색 값은 cell lines(ac = brand 계열 · 판정207).
//   OBIZ: 머리 사업장 선택칸(:1143) 국소 wrapLabel — 전문 · 실제 말줄임(ex) · 낱말 · 보임 · 칸 도달을 낸다. 단언 형태는 cell 판(s1 = 판정206 :65 문구 · s2 = 개별 잘림 관측 기록 · 판정208 대기).
//   before = 지금 A(eb172262) 기록 · strict = 후보(cand_a 또는 cand_ab · mkcell 이 SHA 대조).
//   하네스 = DU618b 최종 suite(records du618b-attendance-status/new 811d8f93) 정확 치환 재사용(prep/mk_suite.py) + 새 조각(prep/suite_parts/obiz_round_new.dart).
//   누르는 것: OATT '처리완료' 탭 · 결원 복구 진입(확인창 열기만) · 확인창 '취소' / ROUND 근무자 탭 · '전체' · 일괄 '출근' · 시트 '예정 09:00' 칩 · '-10분' ·
//     '08:50 로 출근 처리' · 확인 창 바깥(닫힘 = null 반환 → 처리 0) / OBIZ 누름 0. 주 행동 · 보조('다시 모집' · '09:00으로 기록' · '08:50 그대로')는 누르지 않는다(쓰기 0 · CF 0).
//   기본 skip — TB before/du623bbr-tb/DU_BEFORE_OBSERVE=623 · TA after/du623bbr-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/attendance_reads.dart';
import 'package:ALfit/screens/business_admin/dialogs/attendance_status_dialog.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/action_guard.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/app_select_field.dart';
import 'package:ALfit/widgets/common/app_checkbox.dart';
import 'package:ALfit/widgets/common/app_tab_label.dart';
import 'package:ALfit/widgets/pickers/attendance_quick_time_sheet.dart';

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

typedef _V = ({String id, double w, double h, double s});

const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0), (id: 'N', w: 320.0, h: 640.0, s: 1.0)];

/// [DU623b] 사례 — OATT = 노쇼 2명(n1 좌석 미반납 → 결원 복구 진입 · n2 좌석 반납 → 배지 칩) 2장(카드 · 확인창) /
///   ROUND = 미출근 2명 일괄 출근 → 시트에서 08:50 → 근태 기준 적용 확인 창 1장 / OBIZ = 사업장 2곳 · 머리 사업장 선택칸(143 wrapLabel) 1장.
const _cases = <({String id, int shots})>[
  (id: 'OATT', shots: 2), (id: 'ROUND', shots: 1), (id: 'RMIX', shots: 1), (id: 'RSIX', shots: 1), (id: 'ROUT', shots: 1), (id: 'OBIZ', shots: 1),
];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '623';

/// [DU623b] 글 — 067 은 이미 A(eb172262 :2741 · :2766 · :2780–:2784 · mkcell 이 base/후보 소스와 대조)에 있어 두 모드 같다(판정206 :65 TB = 지금 base 기록).
///   옛 글(DU618b 이전)은 두 모드 모두 화면에 0(att alt). 확인창 본문 이름 = n1 '최노쇼'(_dPerson · O002 확인창과 같은 식).
const _label = '빈자리 다시 모집';
const _ok = '다시 모집';
const _msg = '최노쇼님의 오늘 근무가 노쇼로 기록됐어요. 이 자리를 비우고 다시 모집해요.\n확정 기록은 그대로 남고, 이 근무가 차지하던 1자리를 모집 정원으로 돌려요.';
const _badge = '자리 비움 처리됨';
const _altLabel = '대체 인력 충원';
const _altBadge = '대체 충원 진행 중';

/// [DU623b r1] 근태 기준 적용 창 글 · 시각 = 갈래별 _rcfg(아래 ROUND 갈래 조각) — 두 모드 같다(변형 ac 는 색만 바꾼다).

final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du623bbr-tb' && _env['DU_BEFORE_OBSERVE'] == '623') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du623bbr-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _dBiz1 = 'biz1';
const _dBiz2 = 'biz2';
const _dBizName = '강남 물류센터';
const _dLongBiz = '강남구 테헤란로 제2물류센터 야간 상하차 전용 창고'; // CP04 · CP01 인계 긴 사업장
const _dLongName = '응우옌 티 프엉 타오 쩐'; // CP01-C1 · CP04 인계 긴 이름(띄어쓰기 있음)
const _dLatinName = 'KHAMPHOUVONGSOUKSAVANH'; // 띄어쓰기 없는 긴 로마자 이름

/// 소유자(BUSINESS_ADMIN) — 홈(CP04 _DOwner)과 창(ARO _DOwner · PCL _DAdminP)이 실제로 부르는 판정을 허용으로 준다.
///   창은 `canForBusiness`(private _dCurrentUser 를 읽는다) · `watchBusinessPermissions` 를 부르므로 둘 다 대역에서 답한다.
class _DOwner extends UserProvider {
  _DOwner();
  final List<String> bizIds = const [_dBiz1];
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

BusinessModel _dBusiness(String id, String name) => BusinessModel(
    id: id, name: name, ownerId: 'admin1', businessNumber: '000-00-00000', address: '서울시 어딘가',
    category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));

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

// [DU584b] 아래 측정 도우미는 바이트 그대로 옮겼다 — DU562 r2(b4029f2a) :930–945 · :947–971 · :991–1013(ensureVisible 대상 = 잰 대상) · DU560 r3(0c33ce67) :885–898(확인창 글) · DU575(5cd431b1) :766–802 · :842–869 · :871–903(색 · 칠 · 화면 채움 단추).

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

/// [DU575] 주 행동 칠 — 그 글(RichText)의 글자색 · 그 글 뒤 실제 바탕(_bgOf = 버튼 Material) · 대비 · brand 여부 · 흰 글 여부 · 머리 아이콘 색(맨 위 Icon).
typedef _PaintObs = ({int n, String fill, String fg, String cr, bool brand, bool white, String icon});

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
  final icon = ic == null ? '-' : _hex(ic);
  if (es.length != 1) return (n: es.length, fill: '-', fg: '-', cr: '0.00', brand: false, white: false, icon: icon);
  final el = es.first;
  final Color? fg = (el.widget as RichText).text.style?.color;
  final bg = _bgOf(el);
  return (
    n: 1,
    fill: _hex(bg),
    fg: fg == null ? '-' : _hex(fg),
    cr: fg == null ? '0.00' : _contrast(fg, bg).toStringAsFixed(2),
    brand: bg.toARGB32() == AppColors.brand.toARGB32(),
    white: fg != null && fg.toARGB32() == Colors.white.toARGB32(),
    icon: icon,
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
      rows.add('$lab:${_hex(fc)}');
    }
  }
  return (n: rows.length, brand: b, err: er, none: no, other: ot, list: _enc(rows.join('|')));
}

/// [DU584b] 확인창 호스트 — 그린 글(표시 제어 문자 제외)이 [want] 인 RichText 를 품은 Dialog 만 고른다(뒤에 깔린 날짜별 창 · 근태 창과 섞지 않는다).
///   부를 때 한 번 고정한다 — 연 뒤 · 닫은 뒤 각각 새로 부른다.
Finder _dlgWith(String want) {
  final ds = find.byType(Dialog, skipOffstage: false).evaluate().where((d) => find
      .descendant(of: find.byElementPredicate((x) => identical(x, d), skipOffstage: false), matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .any((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == want)).toList();
  return find.byElementPredicate((x) => ds.contains(x), skipOffstage: false);
}

/// [DU584b] O001 결원 복구 진입(외곽선 단추) 칠 — 단추 스타일의 글/선 색(DU575 _interimOf 와 같은 읽기) · 선 알파 · 아이콘 색 · 그려진 글자색 · 글 뒤 실제 바탕(_bgOf) · 대비.
///   brand = 글 · 선 · 아이콘 · 그려진 글 모두 brand(RGB) · warn = 넷 중 warning/warningDark 하나라도(옛 색). [ink] = 그 단추의 InkWell(_btnReach 가 잰 같은 요소).
typedef _OlObs = ({int n, String fg, String side, int sa, String icon, String lab, String face, String cr, bool ok45, bool brand, bool warn});

_OlObs _outlineOf(Finder ink, String label) {
  final bs = find.ancestor(of: ink, matching: find.byWidgetPredicate((w) => w is OutlinedButton, skipOffstage: false)).evaluate().toList();
  final es = find
      .descendant(of: ink, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == label)
      .toList();
  final ics = find.descendant(of: ink, matching: find.byType(Icon), skipOffstage: false).evaluate().toList();
  if (bs.length != 1 || es.length != 1 || ics.length != 1) {
    return (n: 0, fg: '-', side: '-', sa: 0, icon: '-', lab: '-', face: '-', cr: '0.00', ok45: false, brand: false, warn: false);
  }
  final b = bs.first.widget as OutlinedButton;
  final fg = b.style?.foregroundColor?.resolve(<WidgetState>{}) ?? Colors.transparent;
  final side = b.style?.side?.resolve(<WidgetState>{})?.color ?? Colors.transparent;
  final ic = (ics.first.widget as Icon).color ?? Colors.transparent;
  final lab = (es.first.widget as RichText).text.style?.color ?? Colors.transparent;
  final face = _bgOf(es.first);
  final cr = _contrast(lab, face);
  int rgb(Color c) => c.toARGB32() & 0xFFFFFF;
  final brand = rgb(AppColors.brand);
  final warns = {rgb(AppColors.warning), rgb(AppColors.warningDark)};
  return (
    n: 1,
    fg: _hex(fg),
    side: _hex(side),
    sa: (side.a * 255).round(),
    icon: _hex(ic),
    lab: _hex(lab),
    face: _hex(face),
    cr: cr.toStringAsFixed(2),
    ok45: cr >= 4.5,
    brand: rgb(fg) == brand && rgb(side) == brand && rgb(ic) == brand && rgb(lab) == brand,
    warn: [fg, side, ic, lab].any((c) => warns.contains(rgb(c))),
  );
}

// ───────────── [DU618b] 새로 쓴 부분 — O001 읽기 경계(사례별) · 사례 공통 틀 · 사례 본문 3 · main ─────────────

Map<String, dynamic> _ts(DateTime d) => {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

/// 그린 글(표시 제어 문자 제외)이 조건에 맞는 RichText — DU505 시험(f5658c1c :177) rt 와 같은 식(최상위로 옮김 · 판정203 skipOffstage 일관: 찾기는 지어진 전부 → 쓰기 전 ensureVisible).
Finder _rt(bool Function(String p) p) => find.byWidgetPredicate(
    (w) => w is RichText && p(TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false))),
    skipOffstage: false);

Finder _fe(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);

/// [e] 의 가장 가까운 조상 중 [test] 에 맞는 것 — DU505 시험(:178–:188) nearest 와 같은 식.
Element? _nearest(Element e, bool Function(Widget w) test) {
  Element? hit;
  e.visitAncestorElements((a) {
    if (test(a.widget)) {
      hit = a;
      return false;
    }
    return true;
  });
  return hit;
}

/// [DU618b] O001 읽기 경계 — DU584b _aReads(be4972bb :1023–:1050 · DU505 대역 모양) 그대로 · 값만 사례별:
///   OATT = 오늘(KST · _dToday) 단기 확정 n1 · n2(근태 NO_SHOW 둘) · n2 만 좌석 반납(staffingReleasedAt) · 모집 단위 행 0(= 종료 아님) · 계약 서명 완료.
///   ROUND = 단기 확정 r1 · r2 09:00–18:00(근태 없음 = 미출근) · 사업장 근태 기준 기본값(AttendanceRules()).
///   [DU623b r1] RMIX = r1 + r2(지원서 근태 기준 스냅숏 {earlyWindow 0 · earlyArrivalUnit 5} → 08:50 그대로) · RSIX = l1(긴 이름) + r2–r6 ·
///     ROUT = r1 · r2 출근 09:00 기록(status present · 퇴근 없음). 네 갈래 모두 같은 근무 시간(한 파트 → 시트 경로) · 사업장 기준 기본값.
///   OBIZ = 확정 0 · 사업장 2곳(_dBiz1 = 긴 이름 _dLongBiz · _dBiz2) · 읽기만.
AttendanceReads _oReads(String cid) {
  final dayKey = FormatHelper.kstDayKeyOfCivil(_dToday);
  Map<String, dynamic> app(String appId, {bool released = false, bool snap = false}) => {
        'id': appId, 'uid': 'u_$appId', 'toId': 'to1', 'slotId': 's_to1', 'businessId': _dBiz1, 'wdId': 'wd1', 'workDetailId': 'wd1',
        'status': 'CONFIRMED', 'type': 'short_term', 'selectedWorkType': '상하차', 'startTime': '09:00', 'endTime': '18:00',
        'workDate': _ts(dayKey), 'createdAt': _ts(dayKey), 'appliedAt': _ts(dayKey),
        if (released) 'staffingReleasedAt': _ts(dayKey),
        if (snap) 'attendancePolicySnapshot': {'earlyWindow': 0, 'earlyArrivalUnit': 5},
      };
  Map<String, dynamic> noShow(String appId) => {
        'id': 'att-$appId', 'applicationId': appId, 'uid': 'u_$appId', 'businessId': _dBiz1, 'status': AttendanceModel.statusNoShow,
        'workDate': _ts(dayKey), 'createdAt': _ts(dayKey),
      };
  Map<String, dynamic> checkedIn(String appId) => {
        'id': 'att-$appId', 'applicationId': appId, 'uid': 'u_$appId', 'businessId': _dBiz1, 'status': AttendanceModel.statusPresent,
        'checkIn': '09:00', 'workDate': _ts(dayKey), 'createdAt': _ts(dayKey),
      };
  final apps = switch (cid) {
    'OATT' => [app('n1'), app('n2', released: true)],
    'ROUND' || 'ROUT' => [app('r1'), app('r2')],
    'RMIX' => [app('r1'), app('r2', snap: true)],
    'RSIX' => [app('l1'), app('r2'), app('r3'), app('r4'), app('r5'), app('r6')],
    _ => <Map<String, dynamic>>[],
  };
  final atts = switch (cid) {
    'OATT' => [noShow('n1'), noShow('n2')],
    'ROUT' => [checkedIn('r1'), checkedIn('r2')],
    _ => <Map<String, dynamic>>[],
  };
  final names = cid == 'OBIZ' ? {_dBiz1: _dLongBiz, _dBiz2: _dBizName} : {_dBiz1: _dBizName};
  final base = _dBusiness(_dBiz1, names[_dBiz1]!);
  final business = const {'ROUND', 'RMIX', 'RSIX', 'ROUT'}.contains(cid) ? base.copyWith(attendanceRules: const AttendanceRules()) : base;
  return AttendanceReads(
    applicationsPaged: (payload) async {
      if (payload['type'] != null) return const [];
      return [for (final a in apps) Map<String, dynamic>.of(a)];
    },
    workTypeDocs: (wid) async => const {},
    adminAttendances: ({required businessId, required startMs, required endMs}) async => [for (final a in atts) Map<String, dynamic>.of(a)],
    workDetailTimes: (workers) async => const {},
    usersBatch: ({required uids, required businessId}) async => {for (final u in uids) u: _dPerson(u.substring(2))},
    contractStatus: ({required appIds, required businessId}) async => ContractStatusBatch(statuses: {for (final x in appIds) x: 'signed'}),
    dayStaffing: ({required businessId, required dayStartMs}) async => const <DayStaffingRow>[],
    businessById: (bid) async => business,
    businessNames: (ids) async => {for (final i in ids) i: names[i] ?? i},
  );
}

/// [DU618b] 사례 하나의 실행 문맥 — 캡처 · 단언 모음 · 안전 대역 확인 · 프레임 넘기기.
class _Run {
  _Run(this.t, this.v, this.c, this.tok, this.key, this.mode, this.seen, this.wire, this.net);
  final WidgetTester t;
  final _V v;
  final ({String id, int shots}) c;
  final String tok;
  final GlobalKey key;
  final String mode;
  final _DSeen seen;
  final _DWire wire;
  final _DNoHttp net;
  final checks = <(String, bool, String)>[];
  var shots = 0;

  Rect get screen => Offset.zero & Size(v.w, v.h);
  Finder get host => find.byType(AttendanceStatusDialog);

  void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
  void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));
  void safe(String step) => need('안전 대역($step) — 예상 밖 채널 · CF · HTTP 0', !wire.tripped && net.tries.isEmpty,
      'cf ${wire.cf.length} 예상 밖 [${wire.unexpected.join(' | ')}] http ${net.tries.length}');

  Future<void> frames(int n) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> shot(String id, String state) async {
    _out('D623 $tok shot $id ovf=${seen.overflows.length}');
    await vqCapture(t, key, '${tok}_$id', conditions: {
      'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
      'fixture': c.id, 'state': state,
    });
    shots++;
  }
}

/// [DU618b] 사례 공통 틀 — DU584b _oaCase(be4972bb :1287–:1485)의 guard(모든 초기화보다 먼저) · 창 직접 그리기 · 성공/실패 공통 정리 · 집계 그대로.
///   본문만 [body] 로 받는다. 본문의 r.chk 는 정리 뒤에 단언한다(정리 전에 던지지 않는다).
Future<void> _oCase(WidgetTester t, _V v, ({String id, int shots}) c, String tok, Future<String> Function(_Run r) body) async {
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
  _out('D623 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
  final seen = _DSeen();
  final owner = _DOwner();
  final key = GlobalKey();
  final r = _Run(t, v, c, tok, key, mode, seen, wire, net);
  final bizIds = c.id == 'OBIZ' ? const [_dBiz1, _dBiz2] : const [_dBiz1];
  Object? failure;
  StackTrace? failureSt;
  var raw = '';
  try {
    FlutterError.onError = seen.add;
    await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
      value: owner,
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
          home: Scaffold(body: AttendanceStatusDialog(date: _dToday, businessIds: bizIds, initialBusinessId: _dBiz1, reads: _oReads(c.id))),
        ),
      ),
    ));
    raw = await body(r);
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // 성공 · 실패 공통 정리 — DU584b _oaCase 와 같다.
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
  final tripped = wire.tripped;
  final unText = wire.unexpected.join(' | ');
  _out('D623 $tok att wire cf=$nCf unexpected=$nUnexp http=$nHttp');

  messenger.allMessagesHandler = prevAll;
  HttpOverrides.global = prevHttp;
  final exc = t.takeException();
  if (exc != null && failure == null) {
    failure = exc;
    failureSt = StackTrace.current;
  }
  final nOvf = seen.overflows.length;
  final nFw = seen.other.length;
  final ovfRaw = seen.overflows.join('\n----\n');
  final fwRaw = seen.other.join('\n----\n');
  _out('R623 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
      'fail64=${_enc(failure?.toString() ?? '')}');
  _out('D623 $tok att fw n=$nFw');
  _out('D623 $tok done state=${c.id} mode=$mode captures=${r.shots} overflows=$nOvf exc=${exc != null}');

  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  final checks = r.checks;
  void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));
  if (!_before) chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
  if (!_before) chk('strict 사례 전체 넘침 0(판정206 :65 · 세 사례 모두 바뀐 자리 또는 회귀)', nOvf == 0, ovfRaw);
  chk('캡처 수 = 선언', r.shots == c.shots, 'shots ${r.shots} want ${c.shots}');
  chk('시험 전체 CF 0 · 예상 밖 채널 0 · HTTP 0(해제 · 대기 뒤)', nCf == 0 && nUnexp == 0 && nHttp == 0 && !tripped,
      'cf $nCf 예상 밖 [$unText] http $nHttp tripped $tripped');
  final bad = checks.where((x) => !x.$2).toList();
  if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
  for (final x in checks) {
    expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
  }
}

/// [DU618b · 장부067] OATT — ① '처리완료' 탭(노쇼 2명) ② 좌석 반납 배지(n2) 글 ③ 결원 복구 진입(n1 · InkWell = ensureVisible 대상 = 잰 대상 = 누를 대상)
///   글 · 칠 · 다른 모드 글 0 · 화면 채움 단추 · 1card ④ 진입을 눌러 실제 확인창 — 제목 · 본문 · 주 행동/취소 보임/도달 · 주 행동 칠 · 2confirm
///   ⑤ 확인창 '취소' → 닫힘 · 행동 가드 키 0. '다시 모집' · '충원하기'는 누르지 않는다.
///   [A7] 진입은 창 날짜 = 실제 KST 오늘일 때만 선다(_buildNoshowRecoveryButton 당일 게이트) — _dToday(실행 시각 KST 오늘).
Future<String> _oattBody(_Run r) async {
  final t = r.t;
  final tok = r.tok;
  final host = r.host;
  final screen = r.screen;
  final doneTab = find.byWidgetPredicate((w) => w is AppTabLabel && w.label == '처리완료');
  final reviewTab = find.byWidgetPredicate((w) => w is AppTabLabel && w.label == '확인필요');
  int countOf(Finder f) => f.evaluate().length == 1 ? ((f.evaluate().first.widget as AppTabLabel).count ?? -1) : -2;
  for (var i = 0; i < 40 && countOf(doneTab) != 2; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  r.safe('근태 창 열림');
  final nDone = countOf(doneTab);
  final nReview = countOf(reviewTab);
  _out('D623 $tok att tabs done=$nDone review=$nReview');
  r.need('처리완료 탭 2명', nDone == 2, '처리완료 $nDone 확인필요 $nReview');
  // B 에서 탭 바가 가로 스크롤 — 화면 밖 '처리완료' 탭을 먼저 보이게 한 뒤 누른다(DU584b r1 수리와 같다 · A4).
  await t.ensureVisible(doneTab);
  await t.pump();
  await t.tap(doneTab);
  await r.frames(12);
  r.safe('처리완료 탭');
  // ② 배지(n2) — 진입보다 먼저 잰다(진입 측정이 마지막 ensureVisible 이 되어 누를 대상이 화면 안에 남는다).
  await _bringBuilt(t, host, _badge);
  final bg = await _textLine(t, _txt(host, _badge, onstage: false), _badge, screen);
  _out('D623 $tok att badge n=${bg.n} shown=${bg.shown} sem=${bg.sem} full=${bg.full} ell0=${bg.ell0} brk=${bg.brk} lines=${bg.lines} vis=${bg.vis}');
  // ③ 결원 복구 진입(n1) — 보임/도달 · 글 · 칠(외곽선 단추) · 다른 모드 글 0 · 화면 채움 단추.
  final bo = await _btnReach(t, host, _label, screen);
  _out('D623 $tok att btn n=${bo.n} vis=${bo.vis} hit=${bo.hit} m48=${bo.m48}');
  await _bringBuilt(t, host, _label);
  final lo = await _textLine(t, _txt(host, _label, onstage: false), _label, screen);
  _out('D623 $tok att label n=${lo.n} shown=${lo.shown} sem=${lo.sem} full=${lo.full} ell0=${lo.ell0} brk=${lo.brk} lines=${lo.lines} vis=${lo.vis}');
  final altB = _txt(host, _altBadge, onstage: false).evaluate().length;
  final altL = _txt(host, _altLabel, onstage: false).evaluate().length;
  _out('D623 $tok att alt b=$altB l=$altL');
  final ink = find.ancestor(of: _txt(host, _label, onstage: false), matching: find.byType(InkWell)).first;
  final oo = _outlineOf(ink, _label);
  _out('D623 $tok att opaint n=${oo.n} fg=${oo.fg} side=${oo.side} sa=${oo.sa} icon=${oo.icon} lab=${oo.lab} face=${oo.face} cr=${oo.cr} ok45=${oo.ok45} brand=${oo.brand} warn=${oo.warn}');
  final fo = _fills(t);
  _out('D623 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
  await r.shot('1card', 'noshow-entry');
  r.safe('카드 캡처');
  // ④ 그 진입(같은 InkWell)을 눌러 실제 확인창을 연다 — 확인창까지만.
  await t.tap(ink);
  await r.frames(10);
  r.safe('확인창 열림');
  final cdlg = _dlgWith(_ok);
  final nOpen = cdlg.evaluate().length;
  _out('D623 $tok att open n=$nOpen');
  r.need('확인창 1', nOpen == 1, '개수 $nOpen');
  final dt = _dlgText(t, cdlg, _label, screen);
  _out('D623 $tok att dtitle n=${dt.n} full=${dt.full} brk=${dt.brk} lines=${dt.lines} vis=${dt.vis}');
  final db = _dlgText(t, cdlg, _msg, screen);
  _out('D623 $tok att dbody n=${db.n} full=${db.full} brk=${db.brk} lines=${db.lines} vis=${db.vis}');
  final go = await _btnReach(t, cdlg, _ok, screen);
  _out('D623 $tok att go n=${go.n} vis=${go.vis} hit=${go.hit} m48=${go.m48}');
  final no = await _btnReach(t, cdlg, '취소', screen);
  _out('D623 $tok att no n=${no.n} vis=${no.vis} hit=${no.hit} m48=${no.m48}');
  final dp = _paintOf(t, cdlg, _ok);
  _out('D623 $tok att dpaint n=${dp.n} fill=${dp.fill} fg=${dp.fg} cr=${dp.cr} brand=${dp.brand} white=${dp.white} icon=${dp.icon}');
  await r.shot('2confirm', 'confirm-open');
  r.safe('확인창 캡처');
  // ⑤ 확인창 '취소'(_btnReach 가 잰 같은 InkWell) → 닫힘.
  await t.tap(find.ancestor(of: _txt(cdlg, '취소', onstage: false), matching: find.byType(InkWell)).first);
  await r.frames(10);
  final nLeft = _dlgWith(_ok).evaluate().length;
  final nKeys = ActionGuard.inFlightCount;
  _out('D623 $tok att close n=$nLeft keys=$nKeys');
  r.need('확인창 닫힘', nLeft == 0, '남은 $nLeft');
  r.safe('확인창 닫힘');
  r.chk('대비 ≥ 4.5(진입 글 · 확인창 주 행동 — 두 모드 같은 색)', oo.ok45 && (double.tryParse(dp.cr) ?? 0) >= 4.5, 'entry ${oo.cr} dlg ${dp.cr}');
  return 'tabs $nDone/$nReview badge $bg btn $bo label $lo alt $altB/$altL opaint $oo fills $fo title $dt body $db go $go no $no dpaint $dp keys $nKeys';
}

/// [DU623b r1 · 판정207 §5 :96] 근태 기준 적용 창 갈래 — 출근/퇴근 · 같은/다른 결과 라벨 · changed 1명 + unchanged · 5명 초과. 고정값은 소스 계산과 같다:
///   출근 = 예정 09:00 → '-10분' → 08:50(offset −10 · 기본 earlyWindow 30 안 → 정시 09:00 · attendance_rounding_helper processCheckin).
///   RMIX 의 r2 는 지원서 근태 기준 스냅숏 {earlyWindow 0 · earlyArrivalUnit 5}(application_model effectiveAttendanceRules) → −10 ~/ 5 × 5 = −10 → 08:50 그대로(unchanged) →
///     결과 집합 {09:00, 08:50} → 주 행동 '기준 적용' · '나머지 1명은 입력한 시각 그대로예요'(:5384).
///   RSIX = 6명 모두 09:00 → 미리보기 5줄 + '외 1명도 바뀌어요'(:5379 · maxRows 5) · 첫 근무자 = 긴 이름(_dLongName · 이름 칸 maxLines 2 말줄임 기록).
///   퇴근(ROUT) = 출근 09:00 기록 2명 · 예정 18:00 → '+10분' → 18:10(offset +10 · lateWindow 30 안 → 정시 18:00 · processCheckout).
typedef _RCfg = ({bool isIn, int n, String chip, IconData step, String time, String go, String apply, String keep, String applied, String body, String? more, String? rest});

const _rTitle = '근태 기준 적용';
const _rBodyIn = '이 근무의 근태 기준을 적용하면 출근 시각이 이렇게 기록돼요.';
const _rBodyOut = '이 근무의 근태 기준을 적용하면 퇴근 시각이 이렇게 기록돼요.';

_RCfg _rcfg(String id) => switch (id) {
      'RMIX' => (isIn: true, n: 2, chip: '예정  09:00', step: Icons.remove, time: '08:50', go: '08:50 로 출근 처리', apply: '기준 적용', keep: '08:50 그대로',
          applied: '09:00', body: _rBodyIn, more: null, rest: '나머지 1명은 입력한 시각 그대로예요'),
      'RSIX' => (isIn: true, n: 6, chip: '예정  09:00', step: Icons.remove, time: '08:50', go: '08:50 로 출근 처리', apply: '09:00으로 기록', keep: '08:50 그대로',
          applied: '09:00', body: _rBodyIn, more: '외 1명도 바뀌어요', rest: null),
      'ROUT' => (isIn: false, n: 2, chip: '예정  18:00', step: Icons.add, time: '18:10', go: '18:10 로 퇴근 처리', apply: '18:00으로 기록', keep: '18:10 그대로',
          applied: '18:00', body: _rBodyOut, more: null, rest: null),
      _ => (isIn: true, n: 2, chip: '예정  09:00', step: Icons.remove, time: '08:50', go: '08:50 로 출근 처리', apply: '09:00으로 기록', keep: '08:50 그대로',
          applied: '09:00', body: _rBodyIn, more: null, rest: null),
    };

/// [DU623b · 판정207] 창 색 — 미리보기 안 바뀐 시각 글([applied] 전부)의 개수 · 전문 개수 · 글자색 · 그 글을 싼 미리보기 면(가장 가까운 색 있는 BoxDecoration)의 면/테/테 알파 ·
///   글 대비(_bgOf) · 창 바탕(제목 글 뒤 _bgOf) · 덮개(맨 위 ModalBarrier 색 · 알파). 머리 아이콘 색은 _paintOf 의 icon 이 낸다. 값만 낸다 — 정확 값은 cell lines.
typedef _RcObs = ({int n, int nfull, String box, String line, int la, String fg, String cr, bool ok45, String bg, String scrim, int sa});

_RcObs _roundColors(Finder pd, String applied) {
  final ts = find.descendant(of: pd, matching: _rt((p) => p == applied), skipOffstage: false).evaluate().toList();
  final tt = find.descendant(of: pd, matching: _rt((p) => p == _rTitle), skipOffstage: false).evaluate().toList();
  final bg = tt.length == 1 ? _hex(_bgOf(tt.first)) : '-';
  final bars = find.byType(ModalBarrier, skipOffstage: false).evaluate().toList();
  final Color? sc = bars.isEmpty ? null : (bars.last.widget as ModalBarrier).color;
  final scrim = sc == null ? '-' : _hex(sc);
  final sa = sc == null ? 0 : (sc.a * 255).round();
  if (ts.isEmpty) return (n: 0, nfull: 0, box: '-', line: '-', la: 0, fg: '-', cr: '0.00', ok45: false, bg: bg, scrim: scrim, sa: sa);
  final nfull = ts.where((e) {
    final rp = e.renderObject! as RenderParagraph;
    return _fullShown(rp, rp.size);
  }).length;
  final fgs = {for (final e in ts) (e.widget as RichText).text.style?.color};
  final Color? fc = fgs.length == 1 ? fgs.first : null;
  final dec = _nearest(ts.first, (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color != null);
  final bd = dec == null ? null : (dec.widget as DecoratedBox).decoration as BoxDecoration;
  final bdr = bd?.border;
  final Color? lc = bdr is Border ? bdr.top.color : null;
  final c = fc == null ? 0.0 : _contrast(fc, _bgOf(ts.first));
  return (
    n: ts.length,
    nfull: nfull,
    box: bd?.color == null ? '-' : _hex(bd!.color!),
    line: lc == null ? '-' : _hex(lc),
    la: lc == null ? 0 : (lc.a * 255).round(),
    fg: fc == null ? (fgs.length > 1 ? 'mixed' : '-') : _hex(fc),
    cr: c.toStringAsFixed(2),
    ok45: c >= 4.5,
    bg: bg,
    scrim: scrim,
    sa: sa,
  );
}

/// [DU623b] 미리보기 아래 한 줄 글([want] · 없으면 n=0) — 지어진 전부에서 찾고(skipOffstage false) 하나면 ensureVisible 한 **같은 요소**의 전문 · 보임 · 글자색 · 대비.
typedef _LnObs = ({int n, bool full, bool vis, String fg, String cr});

Future<_LnObs> _lineOf(WidgetTester t, Finder pd, String? want, Rect screen) async {
  if (want == null) return (n: 0, full: false, vis: false, fg: '-', cr: '0.00');
  final es = find.descendant(of: pd, matching: _rt((p) => p == want), skipOffstage: false).evaluate().toList();
  if (es.length != 1) return (n: es.length, full: false, vis: false, fg: '-', cr: '0.00');
  await t.ensureVisible(_fe(es.first));
  for (var m = 0; m < 4; m++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  // 굴린 뒤 다시 찾아 그 자리에서 잰다(값은 즉시 지역 변수로).
  final es2 = find.descendant(of: pd, matching: _rt((p) => p == want), skipOffstage: false).evaluate().toList();
  if (es2.length != 1) return (n: es2.length, full: false, vis: false, fg: '-', cr: '0.00');
  final e = es2.first;
  final f = _fe(e);
  final rp = e.renderObject! as RenderParagraph;
  final Color? fc = (e.widget as RichText).text.style?.color;
  final full = _fullShown(rp, rp.size);
  final vis = _inside(t.getRect(f), _area(f, screen));
  return (n: 1, full: full, vis: vis, fg: fc == null ? '-' : _hex(fc), cr: fc == null ? '0.00' : _contrast(fc, _bgOf(e)).toStringAsFixed(2));
}

/// [DU623b · 판정207 :96 '이름 ellipsis · 회색 메타 가독성 잔여 기록'] 이름 칸(maxLines 2 RichText) 수 · 실제 말줄임 수 · 근무 시간 줄(회색) 대비 · 입력 시각(회색) 대비 — 기록만.
typedef _MetaObs = ({int rows, int trunc, String scr, String rcr});

_MetaObs _roundMeta(Finder pd, String shift, String raw) {
  final names = find.descendant(of: pd, matching: find.byWidgetPredicate((w) => w is RichText && w.maxLines == 2), skipOffstage: false).evaluate().toList();
  final trunc = names.where((e) => (e.renderObject! as RenderParagraph).didExceedMaxLines).length;
  String crOf(String want) {
    final es = find.descendant(of: pd, matching: _rt((p) => p == want), skipOffstage: false).evaluate().toList();
    if (es.isEmpty) return '0.00';
    final Color? fc = (es.first.widget as RichText).text.style?.color;
    return fc == null ? '0.00' : _contrast(fc, _bgOf(es.first)).toStringAsFixed(2);
  }

  return (rows: names.length, trunc: trunc, scr: crOf(shift), rcr: crOf(raw));
}

/// [DU618b → DU623b r1] ROUND 갈래 본문(ROUND · RMIX · RSIX · ROUT 같은 흐름 · 값은 _rcfg) — ① 대상 n명이 있는 탭 · '전체' 선택 ② 일괄 '출근'/'퇴근'(InkWell 중심 hit → tapAt)
///   ③ 시트 예정 칩 → '−10분'/'+10분' → 입력 시각 → '… 처리' ④ 근태 기준 적용 확인 창 — 제목 · 본문 · 주 행동/보조 보임/도달/48 · 주 행동 칠 · 창 색(pcol) · 아래 줄(pextra) ·
///   이름/회색 메타(pmeta) · 1preview ⑤ 창 바깥(장벽) 누름 → null → 처리 0 · 시트 닫힘. 두 단추는 누르지 않는다.
///   [A7] 탭은 실행 시각에 따라 '정상' 또는 '확인필요'(출근 갈래 09:00 · 퇴근 갈래 18:00 경계) — 값으로 고른다(어느 쪽이든 n명이 한 탭).
Future<String> _roundBody(_Run r) async {
  final t = r.t;
  final tok = r.tok;
  final screen = r.screen;
  final cfg = _rcfg(r.c.id);
  final reviewTab = find.byWidgetPredicate((w) => w is AppTabLabel && w.label == '확인필요');
  final normalTab = find.byWidgetPredicate((w) => w is AppTabLabel && w.label == '정상');
  int countOf(Finder f) => f.evaluate().length == 1 ? ((f.evaluate().first.widget as AppTabLabel).count ?? -1) : -2;
  for (var i = 0; i < 40 && countOf(reviewTab) + countOf(normalTab) != cfg.n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  r.safe('근태 창 열림');
  final nReview = countOf(reviewTab);
  final nNormal = countOf(normalTab);
  _out('D623 $tok att tabs review=$nReview normal=$nNormal');
  r.need('대상 n명이 한 탭', (nReview == cfg.n && nNormal == 0) || (nReview == 0 && nNormal == cfg.n), '확인필요 $nReview 정상 $nNormal 기대 ${cfg.n}');
  final tab = nReview == cfg.n ? reviewTab : normalTab;
  await t.ensureVisible(tab);
  await t.pump();
  await t.tap(tab);
  await r.frames(12);
  r.safe('근무자 탭');
  // '전체' 선택 칸(AppCheckbox 를 감싼 GestureDetector) — DU505 시험 findAllBox 와 같은 식.
  Finder? allBox() {
    final els = _rt((p) => p == '전체').evaluate().where((e) {
      final g = _nearest(e, (w) => w is GestureDetector);
      return g != null && find.descendant(of: _fe(g), matching: find.byType(AppCheckbox), skipOffstage: false).evaluate().length == 1;
    }).toList();
    return els.length == 1 ? _fe(_nearest(els.first, (w) => w is GestureDetector)!) : null;
  }

  Finder? box;
  for (var i = 0; i < 12 && box == null; i++) {
    await t.pump(const Duration(milliseconds: 50));
    box = allBox();
  }
  r.need('전체 선택 칸 1', box != null, '탭 전환 뒤 전체 칸 없음');
  if (box == null) return 'no-box';
  await t.ensureVisible(box);
  await t.pump();
  await t.tap(box);
  await r.frames(6);
  // ② 일괄 '출근'/'퇴근'(InkWell 안 login/logout 아이콘 + 글) — 보이게 굴린 뒤 다시 찾아 중심 hit 를 확인하고 그 자리를 누른다.
  final actIcon = cfg.isIn ? Icons.login : Icons.logout;
  final actLabel = cfg.isIn ? '출근' : '퇴근';
  final cntLabel = '${cfg.n}건';
  List<Element> ciEls() => find.byType(InkWell, skipOffstage: false).evaluate().where((e) =>
      find.descendant(of: _fe(e), matching: find.byIcon(actIcon, skipOffstage: false), skipOffstage: false).evaluate().length == 1 &&
      find.descendant(of: _fe(e), matching: _rt((p) => p == actLabel), skipOffstage: false).evaluate().length == 1).toList();
  final ci0 = ciEls();
  r.need('일괄 단추 1', ci0.length == 1, '개수 ${ci0.length}');
  await t.ensureVisible(_fe(ci0.first));
  await r.frames(4);
  final ci = ciEls();
  r.need('일괄 단추 1(스크롤 뒤)', ci.length == 1, '개수 ${ci.length}');
  final ciInk = ci.first.widget as InkWell;
  final ciCnt = find.descendant(of: _fe(ci.first), matching: _rt((p) => p == cntLabel), skipOffstage: false).evaluate().length;
  final ciBox = ci.first.renderObject! as RenderBox;
  final ciCenter = ciBox.localToGlobal(ciBox.size.center(Offset.zero));
  final ciHit = t.hitTestOnBinding(ciCenter).path.any((h) => identical(h.target, ciBox));
  _out('D623 $tok att ci n=${ci.length} cnt=$ciCnt enabled=${ciInk.onTap != null} hit=$ciHit');
  r.need('일괄 단추 활성 · n건 · 중심 hit', ciInk.onTap != null && ciCnt == 1 && ciHit, '활성 ${ciInk.onTap != null} $cntLabel $ciCnt hit $ciHit');
  await t.tapAt(ciCenter);
  await r.frames(12);
  r.safe('시트 열림');
  // ③ 시트 — 예정 칩 → '−10분'/'+10분'(remove/add 아이콘 InkWell) → 가운데 입력 시각 → '… 처리'.
  final sheet = find.byType(AttendanceQuickTimeSheet);
  final nSheet = sheet.evaluate().length;
  r.need('시트 1', nSheet == 1, '개수 $nSheet');
  final chip = _txt(sheet, cfg.chip, onstage: false);
  final nChip = chip.evaluate().length;
  r.need('예정 칩 1', nChip == 1, '개수 $nChip');
  await t.ensureVisible(chip);
  await t.pump();
  await t.tap(chip);
  await r.frames(4);
  final step = find.descendant(of: sheet, matching: find.byType(InkWell), skipOffstage: false).evaluate().where((e) =>
      find.descendant(of: _fe(e), matching: find.byIcon(cfg.step, skipOffstage: false), skipOffstage: false).evaluate().length == 1).toList();
  r.need('±10분 단추 1', step.length == 1, '개수 ${step.length}');
  await t.ensureVisible(_fe(step.first));
  await t.pump();
  await t.tap(_fe(step.first));
  await r.frames(4);
  final nTime = _txt(sheet, cfg.time, onstage: false).evaluate().length;
  final goT = _txt(sheet, cfg.go, onstage: false);
  final nGo = goT.evaluate().length;
  _out('D623 $tok att sheet n=$nSheet chip=$nChip minus=${step.length} time=$nTime go=$nGo');
  r.need('시트 입력 시각 두 표시(큰 칸 · 단계 가운데 — attendance_quick_time_sheet.dart:227 · :326 같은 _timeString) · 처리 단추 1', nTime == 2 && nGo == 1, '시각 $nTime 단추 $nGo');
  final goInk = find.ancestor(of: goT, matching: find.byType(InkWell)).first;
  await t.ensureVisible(goInk);
  await t.pump();
  await t.tap(goInk);
  await r.frames(14);
  r.safe('근태 기준 적용 창 열림');
  // ④ 근태 기준 적용 확인 창.
  final pd = _dlgWith(cfg.apply);
  final nOpen = pd.evaluate().length;
  _out('D623 $tok att open n=$nOpen');
  r.need('근태 기준 적용 창 1', nOpen == 1, '개수 $nOpen');
  final go = await _btnReach(t, pd, cfg.apply, screen);
  _out('D623 $tok att go n=${go.n} vis=${go.vis} hit=${go.hit} m48=${go.m48}');
  final keep = await _btnReach(t, pd, cfg.keep, screen);
  _out('D623 $tok att keep n=${keep.n} vis=${keep.vis} hit=${keep.hit} m48=${keep.m48}');
  final pt = _dlgText(t, pd, _rTitle, screen);
  _out('D623 $tok att ptitle n=${pt.n} full=${pt.full} brk=${pt.brk} lines=${pt.lines} vis=${pt.vis}');
  final pb = _dlgText(t, pd, cfg.body, screen);
  _out('D623 $tok att pbody n=${pb.n} full=${pb.full} brk=${pb.brk} lines=${pb.lines} vis=${pb.vis}');
  final pg = _dlgText(t, pd, cfg.apply, screen);
  _out('D623 $tok att gotext n=${pg.n} full=${pg.full} brk=${pg.brk} lines=${pg.lines} vis=${pg.vis}');
  final pp = _paintOf(t, pd, cfg.apply);
  _out('D623 $tok att ppaint n=${pp.n} fill=${pp.fill} fg=${pp.fg} cr=${pp.cr} brand=${pp.brand} white=${pp.white} icon=${pp.icon}');
  final pc = _roundColors(pd, cfg.applied);
  _out('D623 $tok att pcol n=${pc.n} nfull=${pc.nfull} box=${pc.box} line=${pc.line} la=${pc.la} fg=${pc.fg} cr=${pc.cr} ok45=${pc.ok45} bg=${pc.bg} scrim=${pc.scrim} sa=${pc.sa}');
  final pm = _roundMeta(pd, '09:00~18:00', cfg.time);
  _out('D623 $tok att pmeta rows=${pm.rows} trunc=${pm.trunc} scr=${pm.scr} rcr=${pm.rcr}');
  final mo = await _lineOf(t, pd, cfg.more, screen);
  final re = await _lineOf(t, pd, cfg.rest, screen);
  _out('D623 $tok att pextra mn=${mo.n} mfull=${mo.full} mvis=${mo.vis} mfg=${mo.fg} mcr=${mo.cr} rn=${re.n} rfull=${re.full} rvis=${re.vis} rcr=${re.cr}');
  final fo = _fills(t);
  _out('D623 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
  await r.shot('1preview', 'rounding-preview');
  r.safe('근태 기준 적용 창 캡처');
  // ⑤ 창 바깥(장벽) 누름 → null → 처리 0. 두 단추는 누르지 않는다.
  await t.tapAt(const Offset(4, 4));
  await r.frames(10);
  final nLeft = _dlgWith(cfg.apply).evaluate().length;
  final nSheetLeft = sheet.evaluate().length;
  _out('D623 $tok att close n=$nLeft sheet=$nSheetLeft');
  r.need('근태 기준 적용 창 · 시트 닫힘', nLeft == 0 && nSheetLeft == 0, '창 $nLeft 시트 $nSheetLeft');
  r.safe('근태 기준 적용 창 닫힘');
  final cr = double.tryParse(pp.cr) ?? 0;
  // [DU623b] 092 회귀 — 두 모드 모두 주 행동 brand 채움 · 흰 글 대비 ≥ 4.5(이미 A · 판정206 :51 · :65).
  r.chk('주 행동 채움 brand · 대비 ≥ 4.5(092 회귀 · 두 모드)', pp.brand && cr >= 4.5, '${pp.fill} ${pp.cr}');
  return 'tabs $nReview/$nNormal ci $ciCnt/$ciHit sheet $nSheet/$nChip/${step.length}/$nTime/$nGo go $go keep $keep title $pt body $pb gotext $pg ppaint $pp pcol $pc pmeta $pm more $mo rest $re fills $fo';
}

/// [DU623b · 장부143] 실제 말줄임 — 그 글 문단이 줄 수 상한을 넘겨 잘렸는가(RenderParagraph.didExceedMaxLines). 말줄임 '설정'(ell0)과 따로 본다:
///   AppSelectField 는 wrapLabel 이어도 overflow: ellipsis 설정을 두고 maxLines 2 를 준다(app_select_field.dart:153–:154) — 전문이 들어가면 실제 말줄임 0.
///   [tf] 는 지어진 전부에서 찾고(skipOffstage false) 개수 1 일 때만 잰다(앞 _textLine 이 같은 [tf] 를 ensureVisible 한 뒤 부른다). 1 이 아니면 true(보수).
bool _exceeded(Finder tf) {
  if (tf.evaluate().length != 1) return true;
  final rps = find.descendant(of: tf, matching: find.byType(RichText), skipOffstage: false).evaluate().toList();
  if (rps.length != 1) return true;
  return (rps.first.renderObject! as RenderParagraph).didExceedMaxLines;
}

/// [DU623b · 장부143 · 판정206 :53 · :65 · 판정208 대기] OBIZ — 사업장 2곳(선택 = _dBiz1 · 긴 이름 _dLongBiz) · 머리 사업장 선택칸(AppSelectField) 글 · 실제 말줄임 · 칸 도달 · 1head. 누름 0.
///   before = 지금 A(wrapLabel 없음 · 한 줄 말줄임) 기록 · strict = 후보(:1143 wrapLabel: true) — 단언 형태는 cell 판(s1 = 206 :65 문구 · s2 = 개별 잘림 관측 기록)이 정한다.
Future<String> _obizBody(_Run r) async {
  final t = r.t;
  final tok = r.tok;
  final field = find.byWidgetPredicate((w) => w is AppSelectField, skipOffstage: false);
  Finder lab() => _txt(field, _dLongBiz, onstage: false);
  for (var i = 0; i < 40 && lab().evaluate().length != 1; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  r.safe('근태 창 열림');
  final nField = field.evaluate().length;
  _out('D623 $tok att field n=$nField');
  r.need('사업장 선택칸 1', nField == 1, '개수 $nField');
  final bz = await _textLine(t, lab(), _dLongBiz, r.screen);
  final ex = _exceeded(lab());
  _out('D623 $tok att bz n=${bz.n} shown=${bz.shown} sem=${bz.sem} full=${bz.full} ell0=${bz.ell0} brk=${bz.brk} lines=${bz.lines} vis=${bz.vis} ex=$ex');
  final fr = await _btnReach(t, field, _dLongBiz, r.screen);
  _out('D623 $tok att freach n=${fr.n} vis=${fr.vis} hit=${fr.hit} m48=${fr.m48}');
  final fo = _fills(t);
  _out('D623 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
  await r.shot('1head', 'business-select');
  r.safe('머리 캡처');
  // [DU623b s3 · 판정208 §1] 143 보기별 strict(after 만 · before 는 기록) — 측정 · 출력 · 캡처 뒤에 건다(관측 보존).
  //   모든 보기(B 포함): 두 줄 이하 · 낱말 안 끊김 0 · 보임 · 읽는 이름 원문. W/N: 전문 · 실제 말줄임 0. B 의 전문/말줄임은 관측만(기대값으로 박지 않는다).
  if (!_before) {
    r.need('143 모든 보기 — 두 줄 이하 · 낱말 안 끊김 0 · 보임 · 읽는 이름 원문', bz.lines <= 2 && bz.brk == 0 && bz.vis && bz.sem,
        'lines ${bz.lines} brk ${bz.brk} vis ${bz.vis} sem ${bz.sem}');
    if (r.v.id != 'B') r.need('143 W/N — 전문 · 실제 말줄임 0', bz.full && !ex, 'full ${bz.full} ex $ex');
  }
  return 'field $nField bz $bz ex $ex freach $fr fills $fo';
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
    _out('R623 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  tearDown(() {
    ActionGuard.resetForTest();
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S623BR-${v.id}-${c.id} 근태 결원 배지 · 사업장 칸 · 기준 창(F206 143)', (t) async {
        final tok = 'S623BR-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _oCase(t, v, c, tok, switch (c.id) { 'OATT' => _oattBody, 'OBIZ' => _obizBody, _ => _roundBody });
      }, skip: !_optIn);
    }
  }
}
