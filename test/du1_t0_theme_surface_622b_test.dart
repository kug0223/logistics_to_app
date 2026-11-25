// ignore_for_file: depend_on_referenced_packages
// [DU622b · 판정207 ② T0-a · 표시만] 테마 창/시트 기본 면 — lib/theme/role_theme.dart light 에 dialogTheme · bottomSheetTheme(white · modal white · tint transparent)만.
//   관측 표면(판정207 §3 :50–:56): ROUND = 관리자 실제 화면(AttendanceStatusDialog → 일괄 출근 → 실제 시트 AttendanceQuickTimeSheet(showSheet 명시 white) →
//     바탕 미지정 직접 AlertDialog '근태 기준 적용') / OCRE = 근로자 실제 창 함수 OcrVerificationDialog.showError(바탕 미지정 AlertDialog · 호출 화면은 시험 호스트) /
//     PART = 부품 전용 호스트(RoleTheme.workerTheme): 공용 white 확인창 DialogHelper.showConfirm · 바탕 미지정 modal 시트 · 명시색 Dialog · 투명 modal 시트(우선순위 보존).
//   재는 것: 셸 Material 의 실제 color · surfaceTintColor(해석값) · 덮개(ModalBarrier) 색 · 글 대비(글 뒤 실제 바탕) · 전문/끊김/보임 · 단추 도달/48 · 반환값 · 넘침.
//   before = 지금 A(role_theme 3cb5985a) 기록 · strict = 후보(cand/ 9cc10962 · mkcell 이 SHA 대조).
//   하네스 = DU618b suite(811d8f93 · g3 TB 9/9 성공 · TA W-ROUND 성공) 블록 재사용(prep/mk_suite.py 가 줄 범위 바이트 단언) + 새 부분(prep/suite_parts/p2 · p3).
//   누르는 것: ROUND 근무자 탭 · '전체' · 일괄 '출근' · 시트 '예정 09:00' 칩 · '-10분' · '08:50 로 출근 처리' · 창 바깥(닫힘 = null → 처리 0) /
//     OCRE '취소'(Navigator.pop(false) · 도달 실패 시 pop) / PART 확인창 '취소' · 시트/창 바깥. 주 행동('09:00으로 기록' · '다시 시도' · '그대로 등록' · '확인하기')은 누르지 않는다.
//   기본 skip — TB before/du622bts-tb/DU_BEFORE_OBSERVE=622 · TA after/du622bts-ta/없음.
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
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/common/app_checkbox.dart';
import 'package:ALfit/widgets/common/app_tab_label.dart';
import 'package:ALfit/widgets/dialogs/ocr_verification_dialog.dart';
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

/// [DU622b] 사례 — ROUND = 관리자 실제 근태 화면 2장(실제 시트 · 근태 기준 적용 창) / OCRE = 근로자 OCR 실패 창 1장 / PART = 부품 전용 호스트 2장(공용 확인창 · 바탕 미지정 시트).
const _cases = <({String id, int shots})>[(id: 'ROUND', shots: 2), (id: 'OCRE', shots: 1), (id: 'PART', shots: 2)];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '622';

/// [DU618b 와 같은 글] 근태 기준 적용 창 — 예정 09:00 · 입력 08:50(10분 일찍 · 사업장 기준 기본값 조기 도착 30분 안 → 정시) → 기록 09:00.
///   이 셀은 글 · 색 토큰을 바꾸지 않는다(테마 면만) — 두 모드 같은 글.
const _rTitle = '근태 기준 적용';
const _rBody = '이 근무의 근태 기준을 적용하면 출근 시각이 이렇게 기록돼요.';
const _rApply = '09:00으로 기록';
const _rKeep = '08:50 그대로';
const _rChip = '예정  09:00';
const _rTime = '08:50';
const _rGo = '08:50 로 출근 처리';

/// [DU622b] OCR 실패 창(ocr_verification_dialog.dart :304 showError · 실제 호출 document_upload_helper.dart:244 과 같은 인자 꼴 — documentType '신분증' · allowContinue true).
///   errorMessage 는 fixture 글(실제는 OCR 결과 error 문자열). 글은 제품 원문(소스 대조 = mkcell).
const _oTitle = '인식 실패';
const _oBody = '신분증를 인식할 수 없습니다';
const _oErr = '이미지를 읽지 못했어요';
const _oLast = '오류: 이미지를 읽지 못했어요';
const _oCancel = '취소';
const _oKeep = '그대로 등록';
const _oRetry = '다시 시도';

/// [DU622b] 부품 전용 호스트 글(시험이 정한 글 · 제품 글 아님).
const _pTitle = '근무 확인';
const _pMsg = '이 근무를 확인할까요?';
const _pOk = '확인하기';
const _pSheet = '시트 면 확인';
const _pExplicit = '명시 면 확인';
const _pClear = '투명 셸 확인';

final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du622bts-tb' && _env['DU_BEFORE_OBSERVE'] == '622') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du622bts-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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
///   OBIZ = 확정 0 · 사업장 2곳(_dBiz1 = 긴 이름 _dLongBiz · _dBiz2) · 읽기만.
AttendanceReads _oReads(String cid) {
  final dayKey = FormatHelper.kstDayKeyOfCivil(_dToday);
  Map<String, dynamic> app(String appId, {bool released = false}) => {
        'id': appId, 'uid': 'u_$appId', 'toId': 'to1', 'slotId': 's_to1', 'businessId': _dBiz1, 'wdId': 'wd1', 'workDetailId': 'wd1',
        'status': 'CONFIRMED', 'type': 'short_term', 'selectedWorkType': '상하차', 'startTime': '09:00', 'endTime': '18:00',
        'workDate': _ts(dayKey), 'createdAt': _ts(dayKey), 'appliedAt': _ts(dayKey),
        if (released) 'staffingReleasedAt': _ts(dayKey),
      };
  Map<String, dynamic> noShow(String appId) => {
        'id': 'att-$appId', 'applicationId': appId, 'uid': 'u_$appId', 'businessId': _dBiz1, 'status': AttendanceModel.statusNoShow,
        'workDate': _ts(dayKey), 'createdAt': _ts(dayKey),
      };
  final apps = switch (cid) {
    'OATT' => [app('n1'), app('n2', released: true)],
    'ROUND' => [app('r1'), app('r2')],
    _ => <Map<String, dynamic>>[],
  };
  final atts = cid == 'OATT' ? [noShow('n1'), noShow('n2')] : <Map<String, dynamic>>[];
  final names = cid == 'OBIZ' ? {_dBiz1: _dLongBiz, _dBiz2: _dBizName} : {_dBiz1: _dBizName};
  final base = _dBusiness(_dBiz1, names[_dBiz1]!);
  final business = cid == 'ROUND' ? base.copyWith(attendanceRules: const AttendanceRules()) : base;
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

// ───────────── [DU622b] 새로 쓴 부분 — 셸 면 · 덮개 · 글 대비 도우미 · 사례 문맥 · 공통 틀 · 사례 본문 3 · main ─────────────

String _argb(Color c) => c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();

typedef _SurfObs = ({int n, String col, String tint, bool white, bool tint0, bool m3});

/// [DU622b] 셸 면 — [host](Dialog 또는 BottomSheet 하나)의 첫 Material(셸이 그리는 면)이 실제로 받은 color · surfaceTintColor(SDK 해석 뒤 값).
///   white = 흰색 · tint0 = tint 가 투명(null 은 false) · m3 = [m3want](그 자리 테마의 M3 기본 container 톤 — before 기대)와 같다(없으면 false).
_SurfObs _surfOf(Finder host, Color? m3want) {
  final hs = host.evaluate().toList();
  if (hs.length != 1) return (n: hs.length, col: '-', tint: '-', white: false, tint0: false, m3: false);
  final ms = find.descendant(of: _fe(hs.first), matching: find.byType(Material), skipOffstage: false).evaluate().toList();
  if (ms.isEmpty) return (n: 0, col: '-', tint: '-', white: false, tint0: false, m3: false);
  final m = ms.first.widget as Material;
  final c = m.color;
  final tc = m.surfaceTintColor;
  return (
    n: 1,
    col: c == null ? 'null' : _argb(c),
    tint: tc == null ? 'null' : _argb(tc),
    white: c != null && c.toARGB32() == Colors.white.toARGB32(),
    tint0: tc != null && tc.a == 0,
    m3: c != null && m3want != null && c.toARGB32() == m3want.toARGB32(),
  );
}

typedef _BarObs = ({int n, String top, String list});

/// [DU622b] 덮개 — 지어진 ModalBarrier 중 색이 있는 것(경로 순서) · 맨 위(마지막) 색 · 목록(기록만 · 이 셀은 덮개를 바꾸지 않는다 — 판정207 §4 D-BARRIER).
_BarObs _barOf() {
  final cs = <String>[];
  for (final e in find.byType(ModalBarrier, skipOffstage: false).evaluate()) {
    final c = (e.widget as ModalBarrier).color;
    if (c != null && c.a > 0) cs.add(_argb(c));
  }
  return (n: cs.length, top: cs.isEmpty ? '-' : cs.last, list: _enc(cs.join('|')));
}

typedef _CrObs = ({int n, String fg, String bg, String cr, bool ok45});

/// [DU622b] 글 대비 — [host] 안 그린 글(표시 제어 문자 제외)이 [want] 인 RichText 하나의 글자색 · 그 글 뒤 실제 바탕(_bgOf — 셸 Material 포함) · 대비.
_CrObs _crOf(Finder host, String want) {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == want)
      .toList();
  if (es.length != 1) return (n: es.length, fg: '-', bg: '-', cr: '0.00', ok45: false);
  final fg = (es.first.widget as RichText).text.style?.color;
  final bg = _bgOf(es.first);
  final cr = fg == null ? 0.0 : _contrast(Color.alphaBlend(fg, bg), bg);
  return (n: 1, fg: fg == null ? '-' : _hex(fg), bg: _hex(bg), cr: cr.toStringAsFixed(2), ok45: cr >= 4.5);
}

/// [DU622b] 사례 하나의 실행 문맥 — DU618b _Run 과 같은 꼴(출력 접두 D622 · 부품 호스트 BuildContext 칸 추가).
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
  BuildContext? ctx;
  var shots = 0;

  Rect get screen => Offset.zero & Size(v.w, v.h);

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
    _out('D622 $tok shot $id ovf=${seen.overflows.length}');
    await vqCapture(t, key, '${tok}_$id', conditions: {
      'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
      'fixture': c.id, 'state': state,
    });
    shots++;
  }
}

/// [DU622b] 사례 공통 틀 — DU618b _oCase(811d8f93 :813–:924)의 guard(모든 초기화보다 먼저) · 성공/실패 공통 정리 · 집계 그대로.
///   바뀐 것: 출력 접두 D622/R622 · 화면 = ROUND 관리자 실제 근태 창(businessAdminTheme) / OCRE · PART 빈 Scaffold 호스트(workerTheme · BuildContext 를 r.ctx 로).
///   strict 넘침 0 단언 = ROUND(DU618b g3 TB W/B/N 넘침 0 기지) · OCRE/PART 는 기록(이 셀은 배치를 바꾸지 않는다 — TB/TA 같은 값이어야 함은 보고서 대조).
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
  _out('D622 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
  final seen = _DSeen();
  final owner = _DOwner();
  final key = GlobalKey();
  final r = _Run(t, v, c, tok, key, mode, seen, wire, net);
  final admin = c.id == 'ROUND';
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
          theme: admin ? RoleTheme.businessAdminTheme : RoleTheme.workerTheme,
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
          home: admin
              ? Scaffold(body: AttendanceStatusDialog(date: _dToday, businessIds: const [_dBiz1], initialBusinessId: _dBiz1, reads: _oReads(c.id)))
              : Scaffold(body: Builder(builder: (bc) {
                  r.ctx = bc;
                  return const SizedBox.expand();
                })),
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

  // 성공 · 실패 공통 정리 — DU618b _oCase 와 같다.
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
  _out('D622 $tok att wire cf=$nCf unexpected=$nUnexp http=$nHttp');

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
  _out('R622 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
      'fail64=${_enc(failure?.toString() ?? '')}');
  _out('D622 $tok att fw n=$nFw');
  _out('D622 $tok done state=${c.id} mode=$mode captures=${r.shots} overflows=$nOvf exc=${exc != null}');

  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  final checks = r.checks;
  void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));
  if (!_before) chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
  if (!_before && admin) chk('strict ROUND 사례 전체 넘침 0(DU618b g3 TB 기지 0)', nOvf == 0, ovfRaw);
  chk('캡처 수 = 선언', r.shots == c.shots, 'shots ${r.shots} want ${c.shots}');
  chk('시험 전체 CF 0 · 예상 밖 채널 0 · HTTP 0(해제 · 대기 뒤)', nCf == 0 && nUnexp == 0 && nHttp == 0 && !tripped,
      'cf $nCf 예상 밖 [$unText] http $nHttp tripped $tripped');
  final bad = checks.where((x) => !x.$2).toList();
  if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
  for (final x in checks) {
    expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
  }
}

/// [DU622b] 셸 면 기대 — before = 테마 기본 container 톤(흰 아님) · strict = 흰 + tint 투명. 명시 white 셸(showSheet · showConfirm)은 두 모드 흰 + tint 투명.
void _surfChk(_Run r, String k, _SurfObs s, {required bool themed}) {
  if (!themed) {
    r.chk('$k 명시 white 셸 — 두 모드 흰 · tint 투명', s.n == 1 && s.white && s.tint0 && !s.m3, '${s.col} ${s.tint}');
  } else if (_before) {
    r.chk('$k before 바탕 미지정 = 테마 기본 container 톤(흰 아님)', s.n == 1 && s.m3 && !s.white && s.tint0, '${s.col} ${s.tint}');
  } else {
    r.chk('$k strict 바탕 미지정 = 흰 · tint 투명(T0-a)', s.n == 1 && s.white && s.tint0 && !s.m3, '${s.col} ${s.tint}');
  }
}

/// [DU622b · ROUND] 관리자 실제 근태 화면 — DU618b _roundBody(811d8f93 :1008–:1135) 흐름 그대로 + 실제 시트 면(ssurf · 1sheet) · 근태 기준 적용 창 면(dsurf) ·
///   덮개(bar) · 제목/본문 대비(ptcr · pbcr) · 2preview. 창 바깥(장벽) 누름 → null → 처리 0. 두 단추는 누르지 않는다.
///   [A7] 미출근 2명의 탭은 실행 시각에 따라 '정상'(09:00 전) 또는 '확인필요'(09:00 뒤) — 값으로 고른다.
Future<String> _roundBody(_Run r) async {
  final t = r.t;
  final tok = r.tok;
  final screen = r.screen;
  final reviewTab = find.byWidgetPredicate((w) => w is AppTabLabel && w.label == '확인필요');
  final normalTab = find.byWidgetPredicate((w) => w is AppTabLabel && w.label == '정상');
  int countOf(Finder f) => f.evaluate().length == 1 ? ((f.evaluate().first.widget as AppTabLabel).count ?? -1) : -2;
  for (var i = 0; i < 40 && countOf(reviewTab) + countOf(normalTab) != 2; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  r.safe('근태 창 열림');
  final nReview = countOf(reviewTab);
  final nNormal = countOf(normalTab);
  _out('D622 $tok att tabs review=$nReview normal=$nNormal');
  r.need('미출근 2명이 한 탭', (nReview == 2 && nNormal == 0) || (nReview == 0 && nNormal == 2), '확인필요 $nReview 정상 $nNormal');
  final tab = nReview == 2 ? reviewTab : normalTab;
  await t.ensureVisible(tab);
  await t.pump();
  await t.tap(tab);
  await r.frames(12);
  r.safe('근무자 탭');
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
  List<Element> ciEls() => find.byType(InkWell, skipOffstage: false).evaluate().where((e) =>
      find.descendant(of: _fe(e), matching: find.byIcon(Icons.login, skipOffstage: false), skipOffstage: false).evaluate().length == 1 &&
      find.descendant(of: _fe(e), matching: _rt((p) => p == '출근'), skipOffstage: false).evaluate().length == 1).toList();
  final ci0 = ciEls();
  r.need('출근 단추 1', ci0.length == 1, '개수 ${ci0.length}');
  await t.ensureVisible(_fe(ci0.first));
  await r.frames(4);
  final ci = ciEls();
  r.need('출근 단추 1(스크롤 뒤)', ci.length == 1, '개수 ${ci.length}');
  final ciInk = ci.first.widget as InkWell;
  final ciCnt = find.descendant(of: _fe(ci.first), matching: _rt((p) => p == '2건'), skipOffstage: false).evaluate().length;
  final ciBox = ci.first.renderObject! as RenderBox;
  final ciCenter = ciBox.localToGlobal(ciBox.size.center(Offset.zero));
  final ciHit = t.hitTestOnBinding(ciCenter).path.any((h) => identical(h.target, ciBox));
  _out('D622 $tok att ci n=${ci.length} cnt=$ciCnt enabled=${ciInk.onTap != null} hit=$ciHit');
  r.need('출근 단추 활성 · 2건 · 중심 hit', ciInk.onTap != null && ciCnt == 1 && ciHit, '활성 ${ciInk.onTap != null} 2건 $ciCnt hit $ciHit');
  await t.tapAt(ciCenter);
  await r.frames(12);
  r.safe('출근 시트 열림');
  // ① 실제 시트(DialogHelper.showSheet · 명시 white) — 셸 면.
  final sheet = find.byType(AttendanceQuickTimeSheet);
  final nSheet = sheet.evaluate().length;
  r.need('출근 시트 1', nSheet == 1, '개수 $nSheet');
  final ss = _surfOf(find.ancestor(of: sheet, matching: find.byType(BottomSheet)), null);
  _out('D622 $tok att ssurf n=${ss.n} col=${ss.col} tint=${ss.tint} white=${ss.white} tint0=${ss.tint0} m3=${ss.m3}');
  _surfChk(r, '실제 시트(showSheet)', ss, themed: false);
  final chip = _txt(sheet, _rChip, onstage: false);
  final nChip = chip.evaluate().length;
  r.need('예정 09:00 칩 1', nChip == 1, '개수 $nChip');
  await t.ensureVisible(chip);
  await t.pump();
  await t.tap(chip);
  await r.frames(4);
  final minus = find.descendant(of: sheet, matching: find.byType(InkWell), skipOffstage: false).evaluate().where((e) =>
      find.descendant(of: _fe(e), matching: find.byIcon(Icons.remove, skipOffstage: false), skipOffstage: false).evaluate().length == 1).toList();
  r.need('-10분 단추 1', minus.length == 1, '개수 ${minus.length}');
  await t.ensureVisible(_fe(minus.first));
  await t.pump();
  await t.tap(_fe(minus.first));
  await r.frames(4);
  final nTime = _txt(sheet, _rTime, onstage: false).evaluate().length;
  final goT = _txt(sheet, _rGo, onstage: false);
  final nGo = goT.evaluate().length;
  _out('D622 $tok att sheet n=$nSheet chip=$nChip minus=${minus.length} time=$nTime go=$nGo');
  r.need('시트 08:50 두 표시(큰 칸 · 단계 가운데 — attendance_quick_time_sheet.dart:227 · :326 같은 _timeString) · 처리 단추 1', nTime == 2 && nGo == 1, '시각 $nTime 단추 $nGo');
  await r.shot('1sheet', 'quick-time-sheet');
  r.safe('시트 캡처');
  final goInk = find.ancestor(of: goT, matching: find.byType(InkWell)).first;
  await t.ensureVisible(goInk);
  await t.pump();
  await t.tap(goInk);
  await r.frames(14);
  r.safe('근태 기준 적용 창 열림');
  // ② 바탕 미지정 직접 AlertDialog — 셸 면 · 덮개 · 주 행동/보조 도달 · 글 · 대비 · 칠.
  final pd = _dlgWith(_rApply);
  final nOpen = pd.evaluate().length;
  _out('D622 $tok att open n=$nOpen');
  r.need('근태 기준 적용 창 1', nOpen == 1, '개수 $nOpen');
  final ds = _surfOf(pd, Theme.of(t.element(pd)).colorScheme.surfaceContainerHigh);
  _out('D622 $tok att dsurf n=${ds.n} col=${ds.col} tint=${ds.tint} white=${ds.white} tint0=${ds.tint0} m3=${ds.m3}');
  _surfChk(r, '근태 기준 적용 창(AlertDialog 바탕 미지정)', ds, themed: true);
  final bar = _barOf();
  _out('D622 $tok att bar n=${bar.n} top=${bar.top} list=${bar.list}');
  final go = await _btnReach(t, pd, _rApply, screen);
  _out('D622 $tok att go n=${go.n} vis=${go.vis} hit=${go.hit} m48=${go.m48}');
  final keep = await _btnReach(t, pd, _rKeep, screen);
  _out('D622 $tok att keep n=${keep.n} vis=${keep.vis} hit=${keep.hit} m48=${keep.m48}');
  final pt = _dlgText(t, pd, _rTitle, screen);
  _out('D622 $tok att ptitle n=${pt.n} full=${pt.full} brk=${pt.brk} lines=${pt.lines} vis=${pt.vis}');
  final pb = _dlgText(t, pd, _rBody, screen);
  _out('D622 $tok att pbody n=${pb.n} full=${pb.full} brk=${pb.brk} lines=${pb.lines} vis=${pb.vis}');
  final pg = _dlgText(t, pd, _rApply, screen);
  _out('D622 $tok att gotext n=${pg.n} full=${pg.full} brk=${pg.brk} lines=${pg.lines} vis=${pg.vis}');
  final tc = _crOf(pd, _rTitle);
  _out('D622 $tok att ptcr n=${tc.n} fg=${tc.fg} bg=${tc.bg} cr=${tc.cr} ok45=${tc.ok45}');
  final bc = _crOf(pd, _rBody);
  _out('D622 $tok att pbcr n=${bc.n} fg=${bc.fg} bg=${bc.bg} cr=${bc.cr} ok45=${bc.ok45}');
  final pp = _paintOf(t, pd, _rApply);
  _out('D622 $tok att ppaint n=${pp.n} fill=${pp.fill} fg=${pp.fg} cr=${pp.cr} brand=${pp.brand} white=${pp.white} icon=${pp.icon}');
  final fo = _fills(t);
  _out('D622 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
  await r.shot('2preview', 'rounding-preview');
  r.safe('근태 기준 적용 창 캡처');
  await t.tapAt(const Offset(4, 4));
  await r.frames(10);
  final nLeft = _dlgWith(_rApply).evaluate().length;
  final nSheetLeft = sheet.evaluate().length;
  _out('D622 $tok att close n=$nLeft sheet=$nSheetLeft');
  r.need('근태 기준 적용 창 · 시트 닫힘', nLeft == 0 && nSheetLeft == 0, '창 $nLeft 시트 $nSheetLeft');
  r.safe('근태 기준 적용 창 닫힘');
  // 주 행동 칠은 지금 A(eb172262 · 장부092 적용 상태) 그대로 brand — 두 모드 같다(이 셀은 바꾸지 않는다).
  r.chk('주 행동 brand · 대비 ≥ 4.5(두 모드)', pp.brand && (double.tryParse(pp.cr) ?? 0) >= 4.5, '${pp.fill} ${pp.cr}');
  if (!_before) r.chk('strict 제목 · 본문 대비 ≥ 4.5(흰 면 위)', tc.ok45 && bc.ok45, '${tc.cr} ${bc.cr}');
  return 'tabs $nReview/$nNormal ci $ciCnt/$ciHit ssurf $ss sheet $nSheet/$nChip/${minus.length}/$nTime/$nGo dsurf $ds bar $bar go $go keep $keep '
      'title $pt body $pb gotext $pg tcr $tc bcr $bc ppaint $pp fills $fo';
}

/// [DU622b · OCRE] 근로자 실제 창 함수 OcrVerificationDialog.showError(바탕 미지정 AlertDialog) — 실제 호출(document_upload_helper.dart:244)과 같은 인자 꼴.
///   호출 화면(서류 등록 · 카메라/OCR)은 이 하네스에서 열 수 없어 시험 호스트 BuildContext 로 부른다(실제 창 함수 · 부모 화면 미관측).
///   셸 면 · 덮개 · 제목/본문/마지막 줄 전문 · 대비 · 세 단추 도달 · 칠 · 1error → '취소'(도달하면 누름 · 못 하면 Navigator.pop) → 반환 false.
Future<String> _ocreBody(_Run r) async {
  final t = r.t;
  final tok = r.tok;
  final screen = r.screen;
  final ctx = r.ctx;
  r.need('호스트 BuildContext', ctx != null);
  if (ctx == null) return 'no-ctx';
  final fut = OcrVerificationDialog.showError(context: ctx, documentType: '신분증', errorMessage: _oErr, allowContinue: true);
  await r.frames(10);
  r.safe('OCR 실패 창 열림');
  final od = _dlgWith(_oTitle);
  final nOpen = od.evaluate().length;
  _out('D622 $tok att open n=$nOpen');
  r.need('OCR 실패 창 1', nOpen == 1, '개수 $nOpen');
  final ds = _surfOf(od, Theme.of(t.element(od)).colorScheme.surfaceContainerHigh);
  _out('D622 $tok att dsurf n=${ds.n} col=${ds.col} tint=${ds.tint} white=${ds.white} tint0=${ds.tint0} m3=${ds.m3}');
  _surfChk(r, 'OCR 실패 창(AlertDialog 바탕 미지정)', ds, themed: true);
  final bar = _barOf();
  _out('D622 $tok att bar n=${bar.n} top=${bar.top} list=${bar.list}');
  final ot = _dlgText(t, od, _oTitle, screen);
  _out('D622 $tok att otitle n=${ot.n} full=${ot.full} brk=${ot.brk} lines=${ot.lines} vis=${ot.vis}');
  final ob = _dlgText(t, od, _oBody, screen);
  _out('D622 $tok att obody n=${ob.n} full=${ob.full} brk=${ob.brk} lines=${ob.lines} vis=${ob.vis}');
  final ol = _dlgText(t, od, _oLast, screen);
  _out('D622 $tok att olast n=${ol.n} full=${ol.full} brk=${ol.brk} lines=${ol.lines} vis=${ol.vis}');
  final tc = _crOf(od, _oTitle);
  _out('D622 $tok att otcr n=${tc.n} fg=${tc.fg} bg=${tc.bg} cr=${tc.cr} ok45=${tc.ok45}');
  final bc = _crOf(od, _oBody);
  _out('D622 $tok att obcr n=${bc.n} fg=${bc.fg} bg=${bc.bg} cr=${bc.cr} ok45=${bc.ok45}');
  final lc = _crOf(od, _oLast);
  _out('D622 $tok att olcr n=${lc.n} fg=${lc.fg} bg=${lc.bg} cr=${lc.cr} ok45=${lc.ok45}');
  final no = await _btnReach(t, od, _oCancel, screen);
  _out('D622 $tok att no n=${no.n} vis=${no.vis} hit=${no.hit} m48=${no.m48}');
  final kp = await _btnReach(t, od, _oKeep, screen);
  _out('D622 $tok att keep n=${kp.n} vis=${kp.vis} hit=${kp.hit} m48=${kp.m48}');
  final rt = await _btnReach(t, od, _oRetry, screen);
  _out('D622 $tok att retry n=${rt.n} vis=${rt.vis} hit=${rt.hit} m48=${rt.m48}');
  final fo = _fills(t);
  _out('D622 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
  await r.shot('1error', 'ocr-error');
  r.safe('OCR 실패 창 캡처');
  var how = 'pop';
  if (no.n == 1 && no.vis && no.hit) {
    how = 'tap';
    await t.tap(find.ancestor(of: _txt(od, _oCancel, onstage: false), matching: find.byType(InkWell)).first);
  } else {
    Navigator.of(t.element(od)).pop(false);
  }
  await r.frames(10);
  final nLeft = _dlgWith(_oTitle).evaluate().length;
  final ret = await fut;
  _out('D622 $tok att close n=$nLeft how=$how ret=$ret');
  r.need('OCR 실패 창 닫힘', nLeft == 0, '남은 $nLeft');
  r.safe('OCR 실패 창 닫힘');
  r.chk('취소 반환 false', ret == false, '반환 $ret');
  if (!_before) r.chk('strict 제목 · 본문 · 마지막 줄 대비 ≥ 4.5(흰 면 위)', tc.ok45 && bc.ok45 && lc.ok45, '${tc.cr} ${bc.cr} ${lc.cr}');
  return 'dsurf $ds bar $bar title $ot body $ob last $ol tcr $tc bcr $bc lcr $lc no $no keep $kp retry $rt fills $fo close $nLeft/$how/$ret';
}

/// [DU622b · PART] 부품 전용 호스트(workerTheme · 제품 화면 아님) — ① 공용 white 확인창 DialogHelper.showConfirm(명시 white 보존) · 1confirm · '취소' → false
///   ② 바탕 미지정 modal 시트(showModalBottomSheet — 테마 실효 · before = surfaceContainerLow) · 2sheet · 바깥 → null
///   ③ 명시색 Dialog(brandSurface — 우선순위 보존) · 바깥 ④ 투명 modal 시트(특수 투명 셸 보존) · 바깥.
Future<String> _partBody(_Run r) async {
  final t = r.t;
  final tok = r.tok;
  final screen = r.screen;
  final ctx = r.ctx;
  r.need('호스트 BuildContext', ctx != null);
  if (ctx == null) return 'no-ctx';
  final scheme = Theme.of(ctx).colorScheme;
  // ① 공용 white 확인창.
  final f1 = DialogHelper.showConfirm(ctx, title: _pTitle, message: _pMsg, confirmText: _pOk, cancelText: '취소');
  await r.frames(10);
  r.safe('확인창 열림');
  final cd = _dlgWith(_pOk);
  final nOpen = cd.evaluate().length;
  _out('D622 $tok att open n=$nOpen');
  r.need('확인창 1', nOpen == 1, '개수 $nOpen');
  final cs = _surfOf(cd, scheme.surfaceContainerHigh);
  _out('D622 $tok att dsurf n=${cs.n} col=${cs.col} tint=${cs.tint} white=${cs.white} tint0=${cs.tint0} m3=${cs.m3}');
  _surfChk(r, '공용 확인창(showConfirm 명시 white)', cs, themed: false);
  final bar = _barOf();
  _out('D622 $tok att bar n=${bar.n} top=${bar.top} list=${bar.list}');
  final go = await _btnReach(t, cd, _pOk, screen);
  _out('D622 $tok att go n=${go.n} vis=${go.vis} hit=${go.hit} m48=${go.m48}');
  final no = await _btnReach(t, cd, '취소', screen);
  _out('D622 $tok att no n=${no.n} vis=${no.vis} hit=${no.hit} m48=${no.m48}');
  final mc = _crOf(cd, _pMsg);
  _out('D622 $tok att dtcr n=${mc.n} fg=${mc.fg} bg=${mc.bg} cr=${mc.cr} ok45=${mc.ok45}');
  await r.shot('1confirm', 'common-confirm');
  r.safe('확인창 캡처');
  await t.tap(find.ancestor(of: _txt(cd, '취소', onstage: false), matching: find.byType(InkWell)).first);
  await r.frames(10);
  final r1 = await f1;
  final c1 = _dlgWith(_pOk).evaluate().length;
  _out('D622 $tok att cret n=$c1 ret=$r1');
  r.need('확인창 닫힘', c1 == 0, '남은 $c1');
  r.chk('확인창 취소 반환 false', r1 == false, '반환 $r1');
  // ② 바탕 미지정 modal 시트(호스트 BuildContext 는 await 뒤 mounted 확인 — use_build_context_synchronously).
  if (!ctx.mounted) return 'host-unmounted-2';
  final f2 = showModalBottomSheet<String>(
      context: ctx, builder: (_) => const Padding(padding: EdgeInsets.fromLTRB(24, 32, 24, 48), child: Text(_pSheet)));
  await r.frames(12);
  r.safe('시트 열림');
  final sh = find.byType(BottomSheet);
  final ss = _surfOf(sh, scheme.surfaceContainerLow);
  _out('D622 $tok att ssurf n=${ss.n} col=${ss.col} tint=${ss.tint} white=${ss.white} tint0=${ss.tint0} m3=${ss.m3}');
  _surfChk(r, '바탕 미지정 modal 시트', ss, themed: true);
  final sb = _barOf();
  _out('D622 $tok att sbar n=${sb.n} top=${sb.top} list=${sb.list}');
  final sc = _crOf(sh, _pSheet);
  _out('D622 $tok att stcr n=${sc.n} fg=${sc.fg} bg=${sc.bg} cr=${sc.cr} ok45=${sc.ok45}');
  await r.shot('2sheet', 'bare-sheet');
  r.safe('시트 캡처');
  await t.tapAt(const Offset(4, 4));
  await r.frames(12);
  final r2 = await f2;
  final c2 = find.byType(BottomSheet).evaluate().length;
  _out('D622 $tok att sret n=$c2 ret=$r2');
  r.need('시트 닫힘', c2 == 0, '남은 $c2');
  // ③ 명시색 Dialog — 테마보다 개별 명시색이 이긴다.
  if (!ctx.mounted) return 'host-unmounted-3';
  final f3 = showDialog<void>(
      context: ctx,
      builder: (_) => const Dialog(backgroundColor: AppColors.brandSurface, child: Padding(padding: EdgeInsets.all(24), child: Text(_pExplicit))));
  await r.frames(10);
  final xd = _dlgWith(_pExplicit);
  final xs = _surfOf(xd, null);
  final keep = xs.col == _argb(AppColors.brandSurface);
  _out('D622 $tok att xsurf n=${xs.n} col=${xs.col} tint=${xs.tint} keep=$keep');
  r.chk('명시색 Dialog 면 = brandSurface(두 모드)', xs.n == 1 && keep, xs.col);
  await t.tapAt(const Offset(4, 4));
  await r.frames(10);
  await f3;
  final c3 = _dlgWith(_pExplicit).evaluate().length;
  _out('D622 $tok att xret n=$c3');
  r.need('명시색 창 닫힘', c3 == 0, '남은 $c3');
  // ④ 투명 modal 시트 — 특수 투명 셸(직접 호출 3곳 꼴)은 투명 그대로.
  if (!ctx.mounted) return 'host-unmounted-4';
  final f4 = showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(color: Colors.white, padding: const EdgeInsets.all(24), child: const Text(_pClear)));
  await r.frames(12);
  final ts = _surfOf(find.byType(BottomSheet), null);
  final clear = ts.col != '-' && ts.col != 'null' && ts.col.startsWith('00');
  _out('D622 $tok att tsurf n=${ts.n} col=${ts.col} clear=$clear');
  r.chk('투명 시트 셸 = 투명(두 모드)', ts.n == 1 && clear, ts.col);
  await t.tapAt(const Offset(4, 4));
  await r.frames(12);
  await f4;
  final c4 = find.byType(BottomSheet).evaluate().length;
  _out('D622 $tok att tret n=$c4');
  r.need('투명 시트 닫힘', c4 == 0, '남은 $c4');
  r.safe('부품 호스트 끝');
  if (!_before) r.chk('strict 시트 글 대비 ≥ 4.5(흰 면 위)', sc.ok45, sc.cr);
  r.chk('확인창 본문 대비 ≥ 4.5(두 모드 · 명시 white)', mc.ok45, mc.cr);
  return 'dsurf $cs bar $bar go $go no $no dtcr $mc cret $c1/$r1 ssurf $ss sbar $sb stcr $sc sret $c2/$r2 xsurf $xs/$keep tsurf $ts/$clear';
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
    _out('R622 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  tearDown(() {
    ActionGuard.resetForTest();
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S622TS-${v.id}-${c.id} 테마 창 시트 기본 면(판정207 T0-a)', (t) async {
        final tok = 'S622TS-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _oCase(t, v, c, tok, switch (c.id) { 'ROUND' => _roundBody, 'OCRE' => _ocreBody, _ => _partBody });
      }, skip: !_optIn);
    }
  }
}
