// ignore_for_file: depend_on_referenced_packages
// [DU592b · 파일 단위 장부 셀 · 표시만] DU-O002 날짜별 지원·근무 현황(lib/screens/business_admin/dialogs/day_applicants_dialog.dart) 결정 미이행 이행 —
//   장부 038 확정 카드 계약 '무효' 칩 글 error → errorDark(면 errorBg · 테두리 식 그대로 · 판정138 R3 :46 · O003 DU589b 와 같은 짝) ·
//   장부 144(J144) 좌석 반납 배지 이름 → 처리 결과 이름(판정169 §3 :47 · 조건 staffingReleasedAt · 색 · 크기 · 자리 그대로).
//   before = 지금 A(day_applicants_dialog 8fdf86fd = DU584b r2 후보) 기록 · strict = 후보(cand/ · mkcell 이 SHA 대조).
//   하네스 = 블록 재사용(전체 바이트 동일 아님 · prep/mk_test.py 가 원본 fullSHA · 블록 sha12 단언):
//     DU584b r2 suite(be4972bb · r2/g1 DONE 5/5) — 가짜 Firebase · 채널/HTTP 관찰 · 글꼴 · max 판 _fullShown · _textObs · _area · _lineCount · 보기 W/B/N ·
//       날짜별 창 대역 · 읽기 경계 · guard(DU560 NOSHOW 대역 n2 = 좌석 반납 확정) · _txt · _bringBuilt · _semOf · _textLine · 색 도우미 · _fills · setUpAll.
//   새로 쓴 것: 이 머리 · 사례 2(VOID · RLSD) · 글 상수 · VOID 대역(확정 c1 계약 voided) · 칩/배지 칠 _inkOf · 사례 본문 _caseOf · main 반복.
//   누르는 것: O002 홈 '인원 현황 보기' · 하단 '닫기' 뿐(그 밖은 ensureVisible · _bringBuilt 의 scrollUntilVisible). 쓰기 · CF 0.
//   기본 skip — TB before/du592bda-tb/DU_BEFORE_OBSERVE=592 · TA after/du592bda-ta/없음.
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
import 'package:ALfit/utils/action_guard.dart';
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
const _authFake = 'du592b.fake.auth.';
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
    throw const SocketException('DU592b 관측 — 외부 HTTP 차단');
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

/// [DU592b] 사례 — VOID = 확정 카드 계약 '무효' 칩(장부 038) · RLSD = 좌석 반납 확정 카드 배지(장부 144 · DU560 NOSHOW 대역 n2). 각 2장(첫 화면 · 대상).
const _cases = <({String id, int shots})>[(id: 'VOID', shots: 2), (id: 'RLSD', shots: 2)];

/// [DU592b] 이 셀이 보는 글 — mkcell 이 base/후보 소스와 대조한다(옛 이름 = 지금 A · 새 이름 = 후보 · 무효 글은 두 모드 같다).
const _kVoid = '무효';
const _kBadgeOld = '자리 비움';
const _kBadgeNew = '자리 비움 처리됨';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '592';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du592bda-tb' && _env['DU_BEFORE_OBSERVE'] == '592') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du592bda-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

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

// [DU592b] 아래 측정 도우미는 바이트 그대로 옮겼다 — DU584b r2(be4972bb) :786–827(_txt · _bringBuilt · _semOf · _TO · _textLine — ensureVisible 대상 = 잰 대상) ·
//   :868–904(색 · 칠) · :935–967(화면 채움 단추 · A8). _btnReach · _dlgText · _paintOf · _dlgWith · _outlineOf · O001 대역은 이 셀이 쓰지 않아 옮기지 않았다.

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

// ───────────── [DU592b] 새로 쓴 부분 — 칩/배지 칠 · 사례 대역 · 사례 본문 ─────────────

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

/// [DU592b] 사례 대역 — RLSD = DU560 NOSHOW 대역 그대로(_dStateFx · 확정 n1 노쇼 미반납 · n2 좌석 반납 = 배지 · 둘 다 계약 완료) ·
///   VOID = 단일 사업장 · 모집 3 · 확정 2(c1 계약 voided = '무효' 칩 · c2 계약 완료) · 홈 오늘 부족 1('인원 현황 보기' 행) · 대기 · 초대 · 노쇼 0.
_DFx _fx592(String id) => id == 'VOID'
    ? _dFx([_dBusiness(_dBiz1, _dBizName)], _dStaffing(_dDay(3, 2, 1, byBusiness: [_dBiz(_dBiz1, _dBizName, 3, 2, 1)])),
        confirmed: [_dApp('c1', AppStatus.confirmed), _dApp('c2', AppStatus.confirmed)],
        rows: [_dRow(req: 3, conf: 2)], caps: const {'wd1': 3}, contracts: const {'c1': 'voided', 'c2': 'completed'})
    : _dStateFx('NOSHOW');

/// [DU592b] O002 날짜별 창 사례 — DU584b r2 _odCase(홈 → '인원 현황 보기' → 창 · 하단 '닫기')의 guard · 진입 · 정리 · 집계를 그대로 따르고 측정 구간만 바꿨다.
///   ① 첫 화면 채움 단추(A8 · 기록만) · 1top ② 대상 글(VOID '무효' 칩 · RLSD 좌석 반납 배지) — _bringBuilt(지연 목록 대비 · A4) → _textLine(ensureVisible 대상 = 잰 대상 · A1) ·
///   같은 Finder 의 칠(_inkOf) · 옛/새 이름 개수 · 화면 채움 단추(A8) · 2chip / 2badge ③ 하단 '닫기'. 그 밖 누르기 0.
Future<void> _caseOf(WidgetTester t, _V v, ({String id, int shots}) c, String tok) async {
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
  _out('D592 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
  final seen = _DSeen();
  void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
  void safe(String step) => need('안전 대역($step) — 예상 밖 채널 · CF · HTTP 0', !wire.tripped && net.tries.isEmpty,
      'cf ${wire.cf.length} 예상 밖 [${wire.unexpected.join(' | ')}] http ${net.tries.length}');
  final checks = <(String, bool, String)>[];
  void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

  final fx = _fx592(c.id);
  final owner = _DOwner(bizIds: fx.bizIds);
  final homeCalls = <String, int>{};
  final dayReads = _DDayReads(fx);
  Object? failure;
  StackTrace? failureSt;
  var shots = 0;
  var closed = false;
  var raw = '';
  // 모은 단언 재료 — 측정 즉시 값(뒤에 UI 를 다시 읽지 않는다 · preflight v34).
  var okBefore = false;
  var okStrict = false;
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
      _out('D592 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    final screen = Offset.zero & Size(v.w, v.h);
    // ① 첫 화면 — 화면에 그려진 채움 단추(A8 · 기록만) · 1top.
    final ftp = _fills(t);
    _out('D592 $tok att ftop n=${ftp.n} brand=${ftp.brand} err=${ftp.err} none=${ftp.none} other=${ftp.other} list=${ftp.list}');
    await shot('1top', 'list-open');
    safe('첫 캡처');
    // ② 대상 글 — 지연 목록이면 먼저 짓고(_bringBuilt) · 같은 Finder 를 ensureVisible 해 잰다(_textLine) · 그 Finder 의 칠(_inkOf).
    if (c.id == 'VOID') {
      await _bringBuilt(t, dlg, _kVoid);
      final tf = _txt(dlg, _kVoid, onstage: false);
      final lo = await _textLine(t, tf, _kVoid, screen);
      _out('D592 $tok att vl n=${lo.n} shown=${lo.shown} sem=${lo.sem} full=${lo.full} ell0=${lo.ell0} brk=${lo.brk} lines=${lo.lines} vis=${lo.vis}');
      final io = _inkOf(tf);
      final dark = io.fg == _hex(AppColors.errorDark);
      final err = io.fg == _hex(AppColors.error);
      final face = io.bg == _hex(AppColors.errorBg);
      _out('D592 $tok att vc n=${io.n} fg=${io.fg} bg=${io.bg} cr=${io.cr} ok45=${io.ok45} dark=$dark err=$err');
      okBefore = io.n == 1 && err && face;
      okStrict = io.n == 1 && dark && face && io.ok45 && lo.n == 1 && lo.shown && lo.full && lo.vis;
      final fo = _fills(t);
      _out('D592 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
      await shot('2chip', 'void-chip');
      safe('대상 캡처');
      raw = 'top $ftp vl $lo vc $io fills $fo';
    } else {
      final want = _before ? _kBadgeOld : _kBadgeNew;
      await _bringBuilt(t, dlg, want);
      final tf = _txt(dlg, want, onstage: false);
      final lo = await _textLine(t, tf, want, screen);
      _out('D592 $tok att bl n=${lo.n} shown=${lo.shown} sem=${lo.sem} full=${lo.full} ell0=${lo.ell0} brk=${lo.brk} lines=${lo.lines} vis=${lo.vis}');
      final nOld = _txt(dlg, _kBadgeOld, onstage: false).evaluate().length;
      final nNew = _txt(dlg, _kBadgeNew, onstage: false).evaluate().length;
      _out('D592 $tok att bt old=$nOld new=$nNew');
      final io = _inkOf(tf);
      final warn = io.fg == _hex(AppColors.warning);
      _out('D592 $tok att bc n=${io.n} fg=${io.fg} bg=${io.bg} cr=${io.cr} ok45=${io.ok45} warn=$warn');
      okBefore = nOld == 1 && nNew == 0 && io.n == 1 && warn;
      okStrict = nOld == 0 && nNew == 1 && io.n == 1 && warn && lo.n == 1 && lo.shown && lo.full && lo.vis && lo.brk == 0;
      final fo = _fills(t);
      _out('D592 $tok att fills n=${fo.n} brand=${fo.brand} err=${fo.err} none=${fo.none} other=${fo.other} list=${fo.list}');
      await shot('2badge', 'released-badge');
      safe('대상 캡처');
      raw = 'top $ftp bl $lo bt $nOld/$nNew bc $io fills $fo';
    }

    // ③ 하단 '닫기'(DU584b r2 _odCase ④ 와 같다)
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

  // ④ 성공 · 실패 공통 정리 — 홈 · 창을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다. guard 는 아직 걸려 있다.
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

  // ⑤ 최종 안전 집계 — 해제 · 대기 뒤 guard 아래에서 센다(값 측정과 분리).
  final p1ok = _dPhase1.every((k) => (dayReads.calls[k] ?? 0) == 1);
  final p1Text = [for (final k in _dPhase1) '$k*${dayReads.calls[k] ?? 0}'].join(',');
  final nUnexp = wire.unexpected.length;
  final nCf = wire.cf.length;
  final nHttp = net.tries.length;
  final tripped = wire.tripped;
  final unText = wire.unexpected.join(' | ');
  _out('D592 $tok att reader p1=$p1ok closed=$closed cf=$nCf unexpected=$nUnexp http=$nHttp');

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
  _out('R592 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
      'fail64=${_enc(failure?.toString() ?? '')}');
  _out('D592 $tok att fw n=$nFw');
  _out('D592 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

  final f0 = failure;
  if (f0 != null) {
    _halt ??= '$tok ${f0.toString().split('\n').first}';
    Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
  }
  if (_before) chk('before 대상 = 지금 A(VOID 글 error · 면 errorBg / RLSD 옛 이름 1 · 새 이름 0 · warning 글)', okBefore, raw);
  if (!_before) chk('strict 대상 = 후보(VOID 글 errorDark · 면 errorBg · 대비 ≥ 4.5 · 전문 · 보임 / RLSD 새 이름 1 · 옛 이름 0 · warning 그대로 · 전문 · 낱말 안 끊김 0 · 보임)', okStrict, raw);
  if (!_before) chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
  if (!_before && c.id == 'RLSD') chk('strict 넘침 0(RLSD 사례 전체 — 같은 대역 base 관측 0)', nOvf == 0, ovfRaw);
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
    _out('R592 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  tearDown(() {
    DayApplicantsReads.debugOverride = null;
    ActionGuard.resetForTest();
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S592DA-${v.id}-${c.id} O002 결정 이행 — 무효 칩 errorDark · 반납 배지 처리 결과 이름', (t) async {
        final tok = 'S592DA-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _caseOf(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
