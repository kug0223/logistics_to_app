// ignore_for_file: depend_on_referenced_packages
// [DU582c · 판정171 §4 'DU582b [결정]' 후속 · 문구만] ① 로그인 차단 안내 토스트의 앱에 없는 '고객센터: 문의하기 메뉴 이용' 줄 삭제(대체 채널 · 절차 0) ·
//   ② 판정166 결정② — 이미 확정된 근무도 출근 체크가 막히는 효과를 지원 준비 화면 이용 제한 배너(읽는 안내 · 끝 시각 = 같은 restrictedUntil 표기)에 둔다.
//     공고 상세 하단 비활성 버튼 글은 그대로다(설명을 몰아넣지 않는다 — POSTT 가 그 글 그대로 · 효과 문장 0 을 잰다).
//   바뀐 글: 지원 준비 화면(ApplyPrerequisitesScreen) 이용 제한 배너 두 갈래(PRET 끝 시각 · PREPERM 기한 없음) ·
//     로그인 차단 안내 두 갈래(LGAUTO 노쇼 · LGMAN 관리자 조치 — AuthService.restrictionLoginMessage 반환값 그대로를 로그인 화면이 띄우는 공용 오류 토스트로 그린다).
//   안 바뀐 글: POSTT(공고 상세 JobPostingScreen 하단 버튼 사유 · 두 모드 같은 글).
//   before = 지금 A(apply_prerequisites_screen 284c61d2 · auth_service 8c57fcf5 = DU582b 후보) 기록 · strict = 후보(prep/mk_cand.py) 정확.
//   측정 블록 = DU582b 시험(82ff9408 · 정규 1회 DONE 5/5 · 판정171 수용)의 하네스(Firebase 대역 · 채널 · 공고 상세 대역) · _midBreaks · _fullShown(max 판) ·
//     _area · _seeText · _btnLine · _fills · _inkOf 바이트 그대로 + DU571 r2 시험(fad52117)의 이용 제한 사용자 대역 _P 바이트 그대로(prep/mk_test.py 단언).
//   잰다(읽기만): 바뀐 글 RichText **하나를** ensureVisible 로 넣고 **같은 요소**로 화면 ∩ 스크롤 칸 안(vis) · 전문 · 낱말 안 끊김(강제 포함) · 줄 수 · 읽는 이름 ·
//     그 글이 든 버튼(ButtonStyleButton) 한 요소의 비활성(onPressed null — 행동 불변) · 화면 안 · 중심 hit · 화면에 그려진 단추 채움(A8 기록) · 효과 문장 조각 수(eff).
//   쓰기 0 · CF 0 · HTTP 0 · 누르는 것 0. 기본 skip — TB before/du582crst-tb/DU_BEFORE_OBSERVE=582 · TA after/du582crst-ta/없음.
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
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/job_posting_reads.dart';
import 'package:ALfit/screens/common/job_posting_screen.dart';
import 'package:ALfit/screens/user/apply_prerequisites_screen.dart';
import 'package:ALfit/services/auth_service.dart';
import 'package:ALfit/services/tax_identity_service.dart';
import 'package:ALfit/services/work_type_guide_resolver.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/utils/toast_helper.dart';

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

/// 서류는 다 갖췄고 이용 제한만 걸린 **시험용** 사용자(posting_cta_no_selectable_work_test · DU466 과 같은 꼴 · 실제 검증 아님).
class _P extends UserProvider {
  _P(this.until);
  final DateTime until;
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER, accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 2, 1), isIdVerified: true, idCardImagePath: 'users/u1/id.png', bankName: '국민은행',
        accountNumber: '1234', accountHolder: '김근로', bankbookImagePath: 'users/u1/bb.png', createdAt: DateTime(2026, 1, 1),
        restrictedUntil: until,
      );
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
}

/// 공고 상세 대역 — DU466 · posting_cta_no_selectable_work_test 와 같은 꼴(열린 단기 공고 · 남은 자리 있음 · 내 지원 0).
///   날짜는 오늘 기준 상대값(고정 날짜는 하루 지나면 마감 경로로 빠진다). taxStatus 대역 = 서비스 계약의 '모름'(CF 0).
const _kTo = 'to1';
const _kSlot = 'slot1';
final DateTime _kDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).add(const Duration(days: 3));
const _wd = WorkDetailData(wdId: 'wdA', workType: '상하차', workTypeIcon: 'box', workTypeColor: '#000000', workTypeBackgroundColor: '#FFFFFF',
    wage: 12000, wageType: 'hourly', requiredCount: 3, startTime: '09:00', endTime: '13:00');

TOModel _to() => TOModel(
      id: _kTo, businessId: 'biz1', businessName: '강남 물류센터', type: 'flex', title: '단기 모집', creatorUID: 'admin1',
      status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0, workDetails: const [], totalRequired: 3, totalConfirmed: 0,
      totalPending: 0, isPublished: true, publishMode: 'immediate', createdAt: DateTime(2026, 9, 1), statusUpdatedAt: DateTime(2026, 9, 1),
    );

BusinessModel _business() => BusinessModel(
      id: 'biz1', name: '강남 물류센터', businessNumber: '000-00-00000', category: '음식점', subCategory: '한식',
      address: '서울특별시 강남구 테헤란로 1', ownerId: 'owner1', createdAt: DateTime(2026, 9, 1),
    );

SlotModel _slot() => SlotModel(id: _kSlot, toId: _kTo, date: _kDate, workDetails: const [_wd], status: SlotStatus.open, confirmedCount: 0,
    createdAt: DateTime(2025));

JobPostingReads _reads() => JobPostingReads(
      toOrFailure: (id) async => (to: _to(), failed: false),
      workDetails: (id) async => const <WorkDetailData>[],
      businessById: (id) async => _business(),
      slots: (id, {bool visibleOnly = true}) async => [_slot()],
      myApplications: (uid) async => const <ApplicationModel>[],
      workTypeCatalog: (id) async => WorkTypeCatalog.empty,
      applicationOnce: (id) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
    );

/// 대역 끝 시각 — 2030-12-31 23:59 KST(가장 긴 한국어 표기 꼴 · 늘 미래) · 기한 없음 = 서버 경계 KST 9999-01-01 00:00(auth_service · all_users_screen 과 같은 값).
final DateTime _untilTime = DateTime.utc(2030, 12, 31, 14, 59);
final DateTime _untilPerm = DateTime.utc(9998, 12, 31, 15);

/// 사례 — PRET · PREPERM = 지원 준비 화면 이용 제한 배너(끝 시각 · 기한 없음) / POSTT = 공고 상세 하단 버튼 사유(끝 시각 · 안 바뀐 글) /
///   LGAUTO · LGMAN = 로그인 차단 안내 토스트(노쇼 · 관리자 조치 — 문의하기 메뉴 줄 삭제).
typedef _Case = ({String id, int shots, String kind, bool perm});
const _cases = <_Case>[(id: 'PRET', shots: 1, kind: 'pre', perm: false), (id: 'PREPERM', shots: 1, kind: 'pre', perm: true), (id: 'POSTT', shots: 1, kind: 'post', perm: false), (id: 'LGAUTO', shots: 1, kind: 'lg', perm: false), (id: 'LGMAN', shots: 1, kind: 'lg', perm: false)];

/// 이 셀이 바꾸는 글 — after = 후보 문장(prep/mk_cand.py 와 같은 값 · 끝 시각 자리 = 위 대역의 KST 표기를 손으로 적은 값) · before = 지금 A 문장.
const _preTimeBefore = '2030년 12월 31일 오후 11시 59분까지 이용이 제한돼 지원할 수 없어요.';
const _preTimeAfter = '2030년 12월 31일 오후 11시 59분까지 이용이 제한돼 지원할 수 없어요.\n이미 확정된 근무도 제한이 끝날 때까지 출근 체크를 할 수 없어요.';
const _prePermBefore = '이용 제한(기한 없음) 상태라 지원할 수 없어요.';
const _prePermAfter = '이용 제한(기한 없음) 상태라 지원할 수 없어요.\n이미 확정된 근무도 해제 전까지 출근 체크를 할 수 없어요.';

/// 공고 상세 하단 버튼 사유 — 이 셀이 바꾸지 않는다(두 모드 같은 글 · 판정171 '옅은 비활성 버튼에 설명을 몰아넣지 않는다').
const _postTime = '2030년 12월 31일 오후 11시 59분까지 이용이 제한돼요';
const _lgAutoBefore = '노쇼로 인해 2030년 12월 31일 오후 11시 59분(한국시간)까지 이용이 제한돼요.\n(최근 90일 3회 이상 노쇼 시 24시간 제한)\n고객센터: 문의하기 메뉴 이용';
const _lgAutoAfter = '노쇼로 인해 2030년 12월 31일 오후 11시 59분(한국시간)까지 이용이 제한돼요.\n(최근 90일 3회 이상 노쇼 시 24시간 제한)';
const _lgManBefore = '관리자 조치로 2030년 12월 31일 오후 11시 59분(한국시간)까지 이용이 제한돼요.\n고객센터: 문의하기 메뉴 이용';
const _lgManAfter = '관리자 조치로 2030년 12월 31일 오후 11시 59분(한국시간)까지 이용이 제한돼요.';

/// 효과 문장의 조각 — 그 화면에 만들어진 글 가운데 몇 개에 들었는가(PRE before 0 · strict 1 · POSTT 두 모드 0).
const _effPart = '출근 체크';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '582';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du582crst-tb' && _env['DU_BEFORE_OBSERVE'] == '582') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du582crst-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

/// [DU582c] 사례의 글 — before = 지금 A 문장 · strict = 후보 문장(둘 다 정확) · POSTT = 두 모드 같은 글.
String _wantText(_Case c) {
  if (c.id == 'PRET') return _before ? _preTimeBefore : _preTimeAfter;
  if (c.id == 'PREPERM') return _before ? _prePermBefore : _prePermAfter;
  if (c.id == 'POSTT') return _postTime;
  if (c.id == 'LGAUTO') return _before ? _lgAutoBefore : _lgAutoAfter;
  return _before ? _lgManBefore : _lgManAfter;
}

/// [DU582c] 토스트에 띄울 문장 — 제품 함수 반환값 그대로(끝 시각 = 대역 · 출처 auto = 노쇼 · manual = 관리자 조치).
String _lgMessage(_Case c) => AuthService.restrictionLoginMessage(_untilTime, c.id == 'LGAUTO' ? 'auto' : 'manual');

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

/// [DU582b · 점검표 A8 · 색 조화] 바뀐 글 하나의 글자색 · 그 글 뒤 실제 바탕(_bgOf) · 대비 — 기록만(이 셀은 색을 바꾸지 않는다 · DU575 _paintOf 와 같은 읽기 · 같은 식).
typedef _InkObs = ({int n, String fg, String bg, String cr});

_InkObs _inkOf(Finder host, bool Function(String s) match) {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .toList();
  if (es.length != 1) return (n: es.length, fg: '-', bg: '-', cr: '0.00');
  final el = es.first;
  final Color? fg = (el.widget as RichText).text.style?.color;
  final bg = _bgOf(el);
  return (n: 1, fg: fg == null ? '-' : _hex(fg), bg: _hex(bg), cr: fg == null ? '0.00' : _contrast(fg, bg).toStringAsFixed(2));
}

/// [DU582c] 효과 문장 조각(_effPart)이 든 그린 글 수 — host 안 만들어진 RichText 전부(skipOffstage: false · 표시 제어 문자 뺀 글 · 기록 겸 단언).
int _effCount(Finder host) => find
    .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
    .evaluate()
    .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)).contains(_effPart))
    .length;

/// [DU582c] 근무자 이용 제한 안내 사례 — DU582b `_blockCase` 의 틀(guard · 캡처 · 정리 · 집계)을 그대로 쓰고,
///   사용자 대역(DU571 _P · 끝 시각/기한 없음) · 사례 갈래(LG 소스 대조 0 · eff 조각 수 추가)만 바꿨다(누르는 것 0).
Future<void> _limitCase(WidgetTester t, _V v, _Case c, String tok) async {
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
  _out('D582 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
  final seen = _DSeen();
  void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
  final screen = Offset.zero & Size(v.w, v.h);
  final want = _wantText(c);

  Object? failure;
  StackTrace? failureSt;
  var shots = 0;
  var raw = '';
  try {
    FlutterError.onError = seen.add;
    final key = GlobalKey();
    final lg = c.kind == 'lg';
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P(c.perm ? _untilPerm : _untilTime)),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: lg ? navigatorKey : null,
          theme: RoleTheme.workerTheme,
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
          home: c.kind == 'post'
              ? JobPostingScreen(to: _to(), workDetails: const [], slotDate: _kDate, reads: _reads())
              : (lg ? const Scaffold(body: SizedBox.expand()) : const ApplyPrerequisitesScreen(isFlexType: true)),
        ),
      ),
    ));
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final host = c.kind == 'post'
        ? find.byType(JobPostingScreen)
        : (lg ? find.byType(MaterialApp) : find.byType(ApplyPrerequisitesScreen));
    final nScr = host.evaluate().length;
    _out('D582 $tok att scr n=$nScr');
    need('화면 1', nScr == 1, '개수 $nScr');
    Future<void> shot(String id, String state) async {
      _out('D582 $tok shot $id ovf=${seen.overflows.length}');
      await vqCapture(t, key, '${tok}_$id', conditions: {
        'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
        'fixture': c.id, 'state': state,
      });
      shots++;
    }

    if (c.kind == 'post') {
      await shot('1bar', 'posting-bottom-bar');
      // 하단 버튼 사유 글(스크롤 밖 고정 바 · 이 셀이 안 바꾸는 글) — 그 글 · 그 버튼(누르지 않는다) · 효과 문장 조각 0.
      final cta = await _seeText(t, host, (s) => s == want, screen);
      _out('D582 $tok att cta n=${cta.n} name=${cta.name} full=${cta.full} brk=${cta.brk} lines=${cta.lines} vis=${cta.vis}');
      final btn = _btnLine(t, host, (s) => s == want, screen);
      _out('D582 $tok att btn n=${btn.n} dis=${btn.dis} m48=${btn.m48} vis=${btn.vis} hit=${btn.hit}');
      final ink = _inkOf(host, (s) => s == want);
      _out('D582 $tok att ink n=${ink.n} fg=${ink.fg} bg=${ink.bg} cr=${ink.cr}');
      final fl = _fills(t);
      _out('D582 $tok att fills n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
      final eff = _effCount(host);
      _out('D582 $tok att eff n=$eff');
      raw = 'cta $cta btn $btn ink $ink fills $fl eff $eff';
    } else if (c.kind == 'pre') {
      await shot('1top', 'prereq-banner');
      // 화면 맨 위 이용 제한 배너 글 · 지원하기 버튼(비활성 유지 · 누르지 않는다) · 효과 문장 조각 수.
      final ban = await _seeText(t, host, (s) => s == want, screen);
      _out('D582 $tok att ban n=${ban.n} name=${ban.name} full=${ban.full} brk=${ban.brk} lines=${ban.lines} vis=${ban.vis}');
      final go = _btnLine(t, host, (s) => s == '지원하기', screen);
      _out('D582 $tok att go n=${go.n} dis=${go.dis} m48=${go.m48} vis=${go.vis} hit=${go.hit}');
      final ink = _inkOf(host, (s) => s == want);
      _out('D582 $tok att ink n=${ink.n} fg=${ink.fg} bg=${ink.bg} cr=${ink.cr}');
      final fl = _fills(t);
      _out('D582 $tok att fills n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
      final eff = _effCount(host);
      _out('D582 $tok att eff n=$eff');
      raw = 'ban $ban go $go ink $ink fills $fl eff $eff';
    } else {
      // 로그인 화면이 실패 때 부르는 공용 오류 토스트 — 같은 문장으로 한 번(4초 표시 · 정리에서 사라짐).
      ToastHelper.showError(_lgMessage(c));
      for (var i = 0; i < 2; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await shot('1toast', 'login-block-toast');
      final msg = await _seeText(t, host, (s) => s == want, screen);
      _out('D582 $tok att msg n=${msg.n} name=${msg.name} full=${msg.full} brk=${msg.brk} lines=${msg.lines} vis=${msg.vis}');
      final ink = _inkOf(host, (s) => s == want);
      _out('D582 $tok att ink n=${ink.n} fg=${ink.fg} bg=${ink.bg} cr=${ink.cr}');
      final fl = _fills(t);
      _out('D582 $tok att fills n=${fl.n} brand=${fl.brand} err=${fl.err} none=${fl.none} other=${fl.other} list=${fl.list}');
      raw = 'msg $msg ink $ink fills $fl';
    }
  } catch (e, st) {
    failure = e;
    failureSt = st;
  } finally {
    FlutterError.onError = prevOnError;
  }

  // 성공 · 실패 공통 정리 — DU582b _blockCase 와 같다(토스트 4초 타이머도 여기서 지난다).
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
  _out('D582 $tok att wire cf=$nCf unexpected=$nUnexp http=$nHttp');
  messenger.allMessagesHandler = prevAll;
  HttpOverrides.global = prevHttp;
  final exc = t.takeException();
  if (exc != null && failure == null) {
    failure = exc;
    failureSt = StackTrace.current;
  }
  final nOvf = seen.overflows.length;
  final nFw = seen.other.length;
  _out('R582 $tok raw m64=${_enc(raw)} ovf64=${_enc(seen.overflows.join('\n----\n'))} fw64=${_enc(seen.other.join('\n----\n'))} '
      'un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
  _out('D582 $tok att fw n=$nFw');
  _out('D582 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');
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
    _out('R582 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S582RC-${v.id}-${c.id} 근무자 이용 제한 안내 후속(DU582c)', (t) async {
        final tok = 'S582RC-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await _limitCase(t, v, c, tok);
      }, skip: !_optIn);
    }
  }
}
