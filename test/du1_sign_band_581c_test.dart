// ignore_for_file: depend_on_referenced_packages
// [DU581c · 색만 · 판정171 §4 DU581b 후속] 두 주의 면이 함께 보이는 출퇴근(근로자 서명 필요 안내 + 하단 서명 띠)에서
//   본문 출근 gate 안내를 대표 warning 으로 두고, 겹쳐 보이는 하단 띠(PendingContractBar)를 중립면 surface · 제목 textPrimary ·
//   작은 warning 표지(아이콘 warningDark 그대로) · 설명 textSecondary · brand 화살표로 그린다. 서명 필요 안내 테두리는 grey200(후속 중립선 정렬).
//   겹침 판단 = 출퇴근 화면의 signable 갈래가 **보이는 화면에**(TickerMode 켜짐) 붙어 있는 동안(_SignNoticeHold → PendingContractBar.bodyNoticeCount > 0) — 셸 띠 · 화면 띠 같은 값.
//   [g1 · 메인 보정] 셸은 숨은 탭을 TickerMode(enabled: false) 로 감싼다(후보 user_root_screen) — 숨은 탭에 붙은 안내는 띠를 낮추지 않는다(ATTHIDE).
//   사례: BARONE(띠 혼자 = DU581b 짝 그대로) · ATTOTHER(출퇴근 + 다른 근무 서명 대기 띠 · 이 근무는 사업주 서명 대기 = 겹침 아님 → 띠 짝 그대로) ·
//         ATTHIDE(셸의 숨은 탭 = IndexedStack 안 TickerMode(false) 에 서명 필요 출퇴근 · 보이는 탭은 빈 화면 = 겹침 아님 → 띠 짝 그대로) ·
//         ATTSIGN(셸 밖 출퇴근 + 자기 하단 띠) · ATTSHELL(셸 안 출퇴근 — 화면 띠는 그리지 않고 바깥 셸 띠가 보인다 · [SHU-2b] 와 같은 UserTabScope).
//   before = 지금 A(pending_contract_bar 2ce71746 · attendance_check_screen 7be1d518 = DU581b 후보 · user_root_screen 11a26e8c) 기록 · strict = 후보(g1/prep/mk_cand.py) —
//     띠 짝 · 안내 짝(+ 테두리) · 대비 · 띠/안내 제목 전문 · 보임 · 화면 안 주의 면 수 · 넘침 0 · framework 예외 0 은 cell lines(lgate)가 판정한다.
//   하네스 = DU581b 시험(du1_sign_notice_581b_test · 3742ff9e · 정규 1회 DONE 5/5)의 대역 · 측정 · 색 · 채움 · 주의 면 블록 그대로 +
//     띠 측정(_barOf) · 안내 측정(_noteOf 에 테두리) · 셸 그릇(_scope · shell_unification_render_test [SHU-2b] 와 같은 빈 콜백).
//   새 이름(bodyNoticeCount)을 시험이 직접 읽지 않는다 — before(지금 A)에도 같은 시험이 컴파일되어야 한다. 값은 그려진 색으로만 잰다.
//   누르는 것 0 · 쓰기 0 · HTTP 요청 0. 기본 skip — TB before/du581csb-tb/DU_BEFORE_OBSERVE=581 · TA after/du581csb-ta/없음.
//   [g3 · 판정167 시험 수리 1/3] host 아래를 재는 descendant/ancestor 의 matching 찾기에도 skipOffstage: false — flutter_test 는 matching 을 따로 evaluate 해
//     교집합을 내므로(finders.dart:1721–1724) 숨은 IndexedStack 자식(ATTHIDE)이 빠져 `_bringBuilt` 가 sc.first 에서 멈췄다(g1/g2 TB STOP). 기대 · lines 불변.
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
import 'package:ALfit/models/core/business_model.dart' show AttendanceRules;
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/attendance_check_reads.dart';
import 'package:ALfit/screens/user/attendance_check_screen.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/services/auth_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/user/pending_contract_bar.dart';

import 'support/checkin_contract_fixture.dart';
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

/// 원래 경로로 보내는 Flutter 기반 채널과 이유(DU536 · DU540 · DU542 와 같은 표).
const _frameworkAllow = <String, String>{
  'flutter/assets': 'AssetBundle(아이콘 글꼴 · 이미지 매니페스트) 읽기',
  'flutter/platform': 'MaterialApp Title · SystemSound/Haptic(InkWell 탭 피드백)',
  'flutter/navigation': '루트 Navigator 경로 보고',
  'flutter/mousecursor': 'MouseRegion 커서 갱신(시험 포인터)',
  'flutter/restoration': 'RootRestorationScope 상태 복원 조회',
  'flutter/keyboard': 'HardwareKeyboard 상태 동기화',
  'flutter/accessibility': '의미 트리/알림 전달',
};

/// 모든 플랫폼 메시지 관찰 — 기반 채널은 원래 경로, 나머지(CF · Firestore · Auth · 그 밖)는 이름을 기록하고 응답 null.
class _Wire {
  final unexpected = <String>[];

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
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
    throw const SocketException('DU581c 관측 — 외부 HTTP 차단');
  }
}

/// 인증 대역 — 카드는 인증을 읽지 않는다(UserProvider 생성자가 기본 AuthService 로 FirebaseAuth 를 만들지 않게 할 뿐).
class _NoAuth extends Fake implements AuthService {}

/// [DU581b] 근로자 대역 — 서명 대기 계약 [sign] 하나와 그 개수 [count] 만 바꾼다(셸 띠 · 일정 카드 · 출퇴근 하단 띠가 읽는 getter · 서버 읽기 0).
///   currentUser · 권한 getter = attendance_contract_gate_render_test 의 _P 와 같은 값(출퇴근 gate 의 uid) · isUser = shell_unification_render_test 의 _Worker 와 같다.
class _P extends UserProvider {
  _P({this.sign, this.count = 0}) : super(authService: _NoAuth());
  final EmploymentContractModel? sign;
  final int count;
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시'),
        accountStatus: 'active',
      );
  @override
  bool get isUser => true;
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
  @override
  bool get hasPendingContract => count > 0;
  @override
  int get pendingContractCount => count;
  @override
  EmploymentContractModel? get nearestPendingContract => sign;
  @override
  EmploymentContractModel? pendingContractForTo(String toId) => sign?.toId == toId ? sign : null;
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

/// 시각 오류 수집 — 넘침은 원문 + 위치, 그 밖 framework 오류는 원문.
class _Seen {
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
      overflows.add('${m.split('\n').first} @ $loc');
    } else {
      other.add(m);
    }
  }
}

// ── 고정값 — DU581b 시험(= DU576 · DU545 :154–220)의 _kst · _future · _biz · _wt · _app 그대로.

DateTime _kst(int y, int mo, int d, [int h = 0, int mi = 0]) => DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 9));

final DateTime _future = _kst(2099, 1, 5);

const _biz = '골든패스 사업장';
const _wt = 'QA 분류';

ApplicationModel _app(
  String id, {
  required DateTime workDate,
  String status = AppStatus.confirmed,
}) =>
    ApplicationModel(
      id: id,
      toId: 'to_$id',
      uid: 'u1',
      businessId: 'biz1',
      businessName: _biz,
      toTitle: 'QA',
      status: status,
      selectedWorkType: _wt,
      startTime: '10:00',
      endTime: '11:00',
      wage: 12000,
      wageType: 'hourly',
      workDate: workDate,
      appliedAt: workDate.subtract(const Duration(days: 3)),
    );

// ── 출퇴근 근무 — DU581b 시험의 _work(attendance_contract_gate_render_test.dart :91–108 · 선택 인자 status 뺌) 그대로.

/// 직접 지원 확정(CONTRACT_PENDING) 또는 초대 수락(CONFIRMED) — 근무 20:00~21:00, 지금 20:00
ApplicationModel _work() =>
    ApplicationModel(
      id: 'app1',
      toId: 'to1',
      uid: 'u1',
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toTitle: '당일 QA',
      status: AppStatus.contractPending,
      selectedWorkType: 'QA 분류',
      startTime: '20:00',
      endTime: '21:00',
      wage: 12000,
      workDate: _kst(2026, 10, 17),
      appliedAt: _kst(2026, 10, 17, 17, 57),
      attendancePolicySnapshot: const AttendanceRules(),
    );

// ── [DU581c] 사례 — 판정171 §4 DU581b '두 주의 면이 함께 보이는 ATTSIGN' + 겹치지 않는 대조 둘.
//   host = 그리는 그릇(bar 띠 혼자 · att 셸 밖 출퇴근 · shell 셸 안 출퇴근) · note/noteSub = 출퇴근 안내 제목/설명(null = 안내 없음) ·
//   quiet = 후보에서 띠가 중립면으로 서야 하는가 · face/icon/ink/subInk/border = 안내 결정 짝(후보 · DU581b 짝 + 테두리).

const _signBody = '계약서를 확인하고 동의(서명)하면 출근 버튼이 열려요. '
    '출근 기록이 없으면 기존 기준대로 결근 처리될 수 있어요.';
const _empBody = '사업주가 서명한 계약서를 받으면 동의 후 출근할 수 있어요. '
    '근무가 가까우면 사업장 관리자에게 문의해 주세요.';

/// 하단 띠 글 — 서명 대기 1 건(pending_contract_bar.dart 한 건 문구) · 설명 = 계약서 snapshot 사업장(슬롯 0 → 날짜 없음).
const _barTitle = '계약서 서명이 필요해요';
const _barSub = '합성 사업장';

typedef _Case = ({String id, String host, String? note, String? noteSub, bool quiet, Color? face, Color? icon, Color? ink, Color? subInk, Color? border});
const _cases = <_Case>[
  (id: 'BARONE', host: 'bar', note: null, noteSub: null, quiet: false,
      face: null, icon: null, ink: null, subInk: null, border: null),
  (id: 'ATTOTHER', host: 'att', note: '사업주 서명을 기다리고 있어요', noteSub: _empBody, quiet: false,
      face: AppColors.yellowWarnBg, icon: AppColors.yellowWarnDark, ink: AppColors.yellowWarnText, subInk: AppColors.yellowWarnText, border: AppColors.yellowWarnBorder),
  (id: 'ATTHIDE', host: 'hide', note: '근로계약서에 동의해야 출근할 수 있어요', noteSub: _signBody, quiet: false,
      face: AppColors.warningBg, icon: AppColors.warningDark, ink: AppColors.warningDark, subInk: AppColors.textSecondary, border: AppColors.grey200),
  (id: 'ATTSIGN', host: 'att', note: '근로계약서에 동의해야 출근할 수 있어요', noteSub: _signBody, quiet: true,
      face: AppColors.warningBg, icon: AppColors.warningDark, ink: AppColors.warningDark, subInk: AppColors.textSecondary, border: AppColors.grey200),
  (id: 'ATTSHELL', host: 'shell', note: '근로계약서에 동의해야 출근할 수 있어요', noteSub: _signBody, quiet: true,
      face: AppColors.warningBg, icon: AppColors.warningDark, ink: AppColors.warningDark, subInk: AppColors.textSecondary, border: AppColors.grey200),
];

typedef _Pair = ({Color face, Color icon, Color ink, Color sub, Color arrow});

/// [DU581c] 띠 결정 짝(후보) — quiet(본문 대표 안내가 함께 보임) = 중립면 surface · 아이콘 warningDark(작은 warning 표지) · 제목 textPrimary · 설명 textSecondary · 화살표 brand /
///   그 밖 = DU581b 짝 그대로(warningBg · warningDark · warningDark · textSecondary · brand).
_Pair _barWant(bool quiet) => quiet
    ? (face: AppColors.surface, icon: AppColors.warningDark, ink: AppColors.textPrimary, sub: AppColors.textSecondary, arrow: AppColors.brand)
    : (face: AppColors.warningBg, icon: AppColors.warningDark, ink: AppColors.warningDark, sub: AppColors.textSecondary, arrow: AppColors.brand);

/// 일정 카드 사례의 근무 — DU576 CONTRACT 와 같은 입력(계약 진행 중 · 먼 미래) · 그 공고(toId = to_sign)의 서명 대기 계약이 서명 줄을 낸다.
final ApplicationModel _signApp = _app('sign', workDate: _future, status: AppStatus.contractPending);
final ApplicationModel _attApp = _work();
final DateTime _attNow = _kst(2026, 10, 17, 20, 0);

/// 근로자 서명 대기 계약(pending_worker · 사업주 서명 끝) — UserProvider 서명 대기 목록(pending_worker 만)과 출퇴근 gate 근거에 같은 꼴로 쓴다.
EmploymentContractModel _signFor(ApplicationModel a) => checkInContractFor(a, status: ContractStatus.pendingWorker);

/// [DU581c] 사례의 대역 — sign/count = UserProvider 서명 대기 목록(띠가 읽는다) · contracts = 출퇴근 화면이 새로 읽는 계약 목록(gate 근거).
///   BARONE = 다른 근무(to_sign) 서명 대기 1 · ATTOTHER = 같은 띠(다른 근무 서명 대기 1) + 오늘 근무 계약 = 사업주 서명 대기(signable 0 → 겹침 아님) ·
///   ATTSIGN · ATTSHELL = 오늘 근무 서명 대기 1(띠 대표 = 그 계약) + 화면이 읽은 계약 = 같은 서명 대기(signable → 겹침) ·
///   ATTHIDE = ATTSIGN 과 같은 대역(signable 안내가 붙지만 숨은 탭 → 겹침 아님).
typedef _Fx = ({EmploymentContractModel? sign, int count, List<EmploymentContractModel> contracts});

_Fx _fixOf(_Case c) {
  switch (c.id) {
    case 'BARONE':
      return (sign: _signFor(_signApp), count: 1, contracts: const <EmploymentContractModel>[]);
    case 'ATTOTHER':
      return (sign: _signFor(_signApp), count: 1, contracts: [checkInContractFor(_attApp, status: ContractStatus.pendingEmployer)]);
    default: // ATTHIDE · ATTSIGN · ATTSHELL
      return (sign: _signFor(_attApp), count: 1, contracts: [_signFor(_attApp)]);
  }
}

/// 출퇴근 읽기 경계 — attendance_contract_gate_render_test 의 _Reads.build() 와 같은 몸통(근무 하나 · 오늘 근태 없음 · 계약 = 사례 응답 그대로 · 쓰기 0).
AttendanceCheckReads _attReads(List<EmploymentContractModel> contracts) => AttendanceCheckReads(
      myApplications: (uid) async => [_attApp],
      todayAttendance: ({required String userId, required String applicationId}) async => null as AttendanceModel?,
      myContracts: (uid) async => contracts,
    );

/// [DU581c] 근로자 셸의 탭 범위 — shell_unification_render_test [SHU-2b] 와 같은 빈 콜백 · 날짜 null(이 안에서 출퇴근 화면은 자기 하단 띠를 그리지 않는다).
Widget _scope(Widget child) => UserTabScope(
      switchToTab: (i) {},
      switchToTabWithDate: (i, d) {},
      pendingJobDate: null,
      clearPendingJobDate: () {},
      pendingScheduleMonth: null,
      clearPendingScheduleMonth: () {},
      switchToScheduleNow: () {},
      child: child,
    );

/// [DU581c g1] 셸의 숨은 탭 — 후보 user_root_screen 과 같이 IndexedStack 의 탭마다 TickerMode(enabled: 지금 탭) · 출퇴근(탭 범위 안)이 붙은 홈 탭(0)을 숨기고
///   빈 탭(1)을 보인다('내 일정' 으로 옮긴 꼴 · 탭 Navigator · 탭바 생략). 숨은 탭은 그려지지 않고 찾기 기본(skipOffstage)에서도 빠진다.
Widget _hidden(Widget child) => IndexedStack(
      index: 1,
      children: [
        TickerMode(enabled: false, child: _scope(child)),
        const TickerMode(enabled: true, child: SizedBox.expand()),
      ],
    );

// ── 측정 블록(DU571 r2 바이트 그대로 · DU576 과 같다 · 출처 표시는 verify_test) ──

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
  for (final e in find.ancestor(of: f, matching: find.byType(Scrollable, skipOffstage: false)).evaluate()) {
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '581';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du581csb-tb' && _env['DU_BEFORE_OBSERVE'] == '581') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du581csb-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  // 출퇴근 화면 대역(attendance_contract_gate_render_test 와 같다) — 저장소 읽기는 메모리 값(채널 0).
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
    } finally {
      m.allMessagesHandler = prevAll;
      HttpOverrides.global = prevHttp;
    }
    final nUnexp = wire.unexpected.length;
    final nHttp = net.tries.length;
    _out('R581 setup init unexpected=$nUnexp http=$nHttp un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S581SB-${v.id}-${c.id} 출퇴근 서명 안내 대표 warning · 겹친 하단 띠 중립면(판정171 §4 DU581b)', (t) async {
        final tok = 'S581SB-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');

        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final wire = _Wire();
        final net = _NoHttp();
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
        final screen = Offset.zero & Size(v.w, v.h);
        final mode = _before ? 'before' : 'strict';
        _out('D581 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final fx = _fixOf(c);
        Object? failure;
        StackTrace? failureSt;
        var nShot = 0;
        var raw = '';
        try {
          FlutterError.onError = seen.add;
          final key = GlobalKey();
          Future<void> shot(String id, String state) async {
            _out('D581 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            nShot++;
          }

          // 띠 = 셸과 같은 const PendingContractBar()(useSafeArea false · 그릇만) · 출퇴근 = 셸 밖 AttendanceCheckScreen(자기 하단 띠 useSafeArea true) ·
          //   셸 = UserTabScope 안 출퇴근(화면 띠는 그리지 않는다 · [SHU-2b]) + 바깥 Scaffold 하단 const PendingContractBar()(UserRootScreen 과 같은 자리 · 탭 Navigator · 탭바 생략).
          final att = AttendanceCheckScreen(reads: _attReads(fx.contracts), clock: () => _attNow);
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider<UserProvider>(create: (_) => _P(sign: fx.sign, count: fx.count)),
                ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
              ],
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
                home: c.host == 'bar'
                    ? const Scaffold(body: SizedBox.expand(), bottomNavigationBar: PendingContractBar())
                    : c.host == 'shell'
                        ? Scaffold(body: _scope(att), bottomNavigationBar: const PendingContractBar())
                        : c.host == 'hide'
                            ? Scaffold(body: _hidden(att), bottomNavigationBar: const PendingContractBar())
                            : att,
              ),
            ),
          ));
          for (var i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          final barF = find.byType(PendingContractBar);
          // [g1] 출퇴근 host 는 숨은 탭(ATTHIDE)에서도 잡는다(skipOffstage 0) — 안내가 트리에 붙어 있음을 재야 '숨어서 겹치지 않음'이 입증된다.
          final attF = find.byType(AttendanceCheckScreen, skipOffstage: false);
          final nHost = (c.host == 'bar' ? barF : attF).evaluate().length;
          _out('D581 $tok att host n=$nHost');
          need('그릇 1(띠 · 출퇴근 화면)', nHost == 1, '개수 $nHost');
          // [점검표 A4] 띠는 스크롤 목록 밖(Scaffold 하단 고정 · 지연 생성 0)이라 띠 글은 바로 잰다. 출퇴근 안내 글은 같은 host(출퇴근 화면)의
          //   지연 ListView 안 — 그 host 의 찾기/측정 앞마다 _bringBuilt(String? want). 여는 순서 = 띠 제목 → 안내 설명 → 안내 제목
          //   (마지막 ensureVisible 이 안내 제목이라 캡처에 안내 머리와 하단 띠가 함께 보인다 · README §4).
          final barSee = await _seeText(t, barF, (s) => s == _barTitle, screen);
          _out('D581 $tok att bartitle n=${barSee.n} name=${barSee.name} full=${barSee.full} brk=${barSee.brk} lines=${barSee.lines} vis=${barSee.vis}');
          need('띠 제목 글 1', barSee.n == 1, '개수 ${barSee.n}');
          final bar = _barOf(barF, c);
          _out('D581 $tok att bar n=${bar.n} face=${bar.face} icon=${bar.icon} ink=${bar.ink} sub=${bar.sub} arrow=${bar.arrow} cr=${bar.cr} scr=${bar.scr} icr=${bar.icr} acr=${bar.acr} ok=${bar.ok} pair=${bar.pair}');
          final note = c.note;
          final noteSub = c.noteSub;
          if (noteSub != null) await _bringBuilt(t, attF, noteSub);
          final subSee = noteSub == null ? _none : await _seeText(t, attF, (s) => s == noteSub, screen);
          _out('D581 $tok att sub n=${subSee.n} name=${subSee.name} full=${subSee.full} brk=${subSee.brk} lines=${subSee.lines} vis=${subSee.vis}');
          if (note != null) await _bringBuilt(t, attF, note);
          final title = note == null ? _none : await _seeText(t, attF, (s) => s == note, screen);
          _out('D581 $tok att title n=${title.n} name=${title.name} full=${title.full} brk=${title.brk} lines=${title.lines} vis=${title.vis}');
          final gate = _noteOf(attF, c);
          _out('D581 $tok att note n=${gate.n} face=${gate.face} icon=${gate.icon} ink=${gate.ink} sub=${gate.sub} border=${gate.border} cr=${gate.cr} scr=${gate.scr} ok45=${gate.ok45} pair=${gate.pair}');
          final notes = _notes(t, screen);
          _out('D581 $tok att notes n=$notes');
          final fills = _fills(t);
          _out('D581 $tok att fills n=${fills.n} brand=${fills.brand} err=${fills.err} none=${fills.none} other=${fills.other} list=${fills.list}');
          await shot('1${c.host}', 'sign-band');
          raw = 'bartitle $barSee bar $bar sub $subSee title $title note $gate notes $notes fills $fills';
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // 성공 · 실패 공통 정리 — 화면을 내리고(UserProvider dispose) 남은 timer 가 끝날 시간을 준다.
        var cleanupErr = '';
        try {
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump(const Duration(milliseconds: 500));
        } catch (e, st) {
          cleanupErr = e.toString();
          if (failure == null) {
            failure = e;
            failureSt = st;
          }
        }

        // 집계 — 예상 밖 플랫폼 채널(서버 · 저장소 · 인증 포함) · HTTP.
        final nUnexp = wire.unexpected.length;
        final nHttp = net.tries.length;
        _out('D581 $tok att wire unexpected=$nUnexp http=$nHttp');

        messenger.allMessagesHandler = prevAll;
        HttpOverrides.global = prevHttp;
        final exc = t.takeException();
        if (exc != null && failure == null) {
          failure = exc;
          failureSt = StackTrace.current;
        }
        final nOvf = seen.overflows.length;
        final nFw = seen.other.length;
        final ovfRaw = seen.overflows.take(8).join('\n----\n');
        final fwRaw = seen.other.take(4).map((m) => m.length > 400 ? m.substring(0, 400) : m).join('\n----\n');
        _out('R581 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(wire.unexpected.join(' | '))} '
            'cleanup64=${_enc(cleanupErr)} fail64=${_enc(failure?.toString() ?? '')}');
        _out('D581 $tok att fw n=$nFw');
        _out('D581 $tok done state=${c.id} mode=$mode captures=$nShot overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        expect(nShot == 1, isTrue, reason: '$tok 캡처 수 = 1 $nShot');
      }, skip: !_optIn);
    }
  }
}

// 측정 도우미(DU571 r2 바이트 그대로 · DU576 과 같이 main 뒤에 둔다 — preflight 'renderObject 재사용' 줄 훑기 거짓 양성 회피).

typedef _SeeObs = ({int n, bool name, bool full, int brk, int lines, bool vis});

/// [DU581b] 재지 않는 글(설명 · 조작 글이 없는 사례)의 자리값 — 출력 줄 모양을 사례마다 같게 둔다(n=0).
const _SeeObs _none = (n: 0, name: false, full: false, brk: 0, lines: 0, vis: false);

/// [DU571] 바뀐 글 하나 — 그린 글(표시 제어 문자 제외)이 [match] 에 맞는 RichText 가 정확히 하나일 때 **그 RichText 를** ensureVisible 로 넣고,
///   같은 요소로 읽는 이름(가장 가까운 Semantics 조상 label = 그 글 원문) · 전문 · 낱말 안 끊김(강제 포함) · 줄 수 · 화면 ∩ 스크롤 칸 안을 잰다
///   (DU570 의 같은 이름 도우미와 같은 잣대 · 찾는 조건만 함수 · await 뒤에는 Element 를 직접 읽지 않고 같은 finder 로 다시 잡는다).
Future<_SeeObs> _seeText(WidgetTester t, Finder host, bool Function(String s) match, Rect screen) async {
  final es = find
      .descendant(of: host, matching: find.byType(RichText, skipOffstage: false), skipOffstage: false)
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

/// [DU514 과 같다] 그린 글(표시 제어 문자 제외).
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

/// [DU581 r2 · 판정167 시험 STOP 수리] 지연 생성 목록(사용자 목록 · 상세 시트 ListView) 안의 글이 아직 안 만들어졌을 때만
///   그 host 의 세로 목록을 끌어 만든다(누르기 아님 · 찾는 식 = _seeText 와 같은 _plainOf · 단언 없음 — 개수 판정은 _seeText 뒤 need).
Future<void> _bringBuilt(WidgetTester t, Finder host, String? want) async {
  final tf = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == want, skipOffstage: false), skipOffstage: false);
  if (tf.evaluate().isNotEmpty) return;
  final sc = find.descendant(
      of: host, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down, skipOffstage: false), skipOffstage: false);
  await t.scrollUntilVisible(tf, 120, scrollable: sc.first, maxScrolls: 40);
  await t.pump(const Duration(milliseconds: 50));
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

// ── [DU581b] 새 측정 — 안내(면 · 아이콘 · 제목 · 설명) · 조작(글 · 화살표 · 외곽선) · 화면 안 주의 면 수.

/// host 안(skipOffstage 0) 그린 글이 [s] 인 RichText 요소들(DU576 _chipOf 와 같은 찾기 · Icon 글리프는 글이 달라 들지 않는다).
List<Element> _richIn(Finder host, String s) => find
    .descendant(of: host, matching: find.byType(RichText, skipOffstage: false), skipOffstage: false)
    .evaluate()
    .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == s)
    .toList();

/// [e] 뒤 면을 만든 가장 가까운 조상 요소 — _bgOf 가 처음 만나는 면(ColoredBox · BoxDecoration · 불투명 Material)과 같은 규칙 · 없으면 null.
Element? _ownerOf(Element e) {
  Element? hit;
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
    hit = a;
    return false;
  });
  return hit;
}

/// [원문 '뷰포트 대표 주의1개 / E-NOTICE'] 화면과 겹치는(onstage) 주의 면(warningBg · yellowWarnBg) 상자 수 — 같은 사각형은 하나로 센다 · 기록만(README §0 판단 필요).
int _notes(WidgetTester t, Rect screen) {
  bool warn(Color? c) => c != null && (c.toARGB32() == AppColors.warningBg.toARGB32() || c.toARGB32() == AppColors.yellowWarnBg.toARGB32());
  final rects = <String>{};
  final faces = find.byWidgetPredicate((w) =>
      (w is ColoredBox && warn(w.color)) ||
      (w is DecoratedBox && w.decoration is BoxDecoration && warn((w.decoration as BoxDecoration).color)) ||
      (w is Material && warn(w.color)));
  for (final e in faces.evaluate()) {
    final r = t.getRect(find.byElementPredicate((x) => identical(x, e)));
    if (!r.overlaps(screen)) continue;
    rects.add('${r.left.round()},${r.top.round()},${r.right.round()},${r.bottom.round()}');
  }
  return rects.length;
}

// ── [DU581c] 새 측정 — 하단 띠(면 · 표지 아이콘 · 제목 · 설명 · 화살표) · 출퇴근 안내(+ 테두리).

/// 두 색이 둘 다 있고 같은가(ARGB).
bool _same(Color? a, Color? b) => a != null && b != null && a.toARGB32() == b.toARGB32();

/// 하단 띠 하나 — 띠 제목 [_barTitle] 이 그려진 RichText(모든 PendingContractBar 안 · 정확히 하나 — 셸 사례의 화면 띠는 그리지 않는다)의 글자색 · 그 글 뒤 면(_bgOf) ·
///   그 면을 만든 상자(_ownerOf) 안 draw_outlined 표지 · chevron_right 화살표 하나씩의 색 · 같은 상자 안 설명 [_barSub] 글자색 · 대비.
///   pair = 사례의 띠 결정 짝(_barWant(quiet)) · ok = 제목/설명 ≥4.5 · 표지/화살표 ≥3.0.
typedef _BarObs = ({int n, String face, String icon, String ink, String sub, String arrow, String cr, String scr, String icr, String acr, bool ok, bool pair});

_BarObs _barOf(Finder bar, _Case c) {
  final es = _richIn(bar, _barTitle);
  if (es.length != 1) {
    return (n: es.length, face: '-', icon: '-', ink: '-', sub: '-', arrow: '-', cr: '0.00', scr: '0.00', icr: '0.00', acr: '0.00', ok: false, pair: false);
  }
  final el = es.first;
  final Color ink = (el.widget as RichText).text.style?.color ?? Colors.transparent;
  final face = _bgOf(el);
  final owner = _ownerOf(el);
  final box = owner == null ? bar : find.byElementPredicate((x) => identical(x, owner), skipOffstage: false);
  Color? iconIn(IconData d) {
    final ics = find
        .descendant(of: box, matching: find.byWidgetPredicate((w) => w is Icon && w.icon == d, skipOffstage: false), skipOffstage: false)
        .evaluate()
        .toList();
    return ics.length == 1 ? (ics.first.widget as Icon).color : null;
  }

  final ic = iconIn(Icons.draw_outlined);
  final ar = iconIn(Icons.chevron_right);
  final ss = _richIn(box, _barSub);
  final Color? sc = ss.length == 1 ? (ss.first.widget as RichText).text.style?.color : null;
  final want = _barWant(c.quiet);
  final cr = _contrast(ink, face);
  final scr = sc == null ? 0.0 : _contrast(sc, face);
  final icr = ic == null ? 0.0 : _contrast(ic, face);
  final acr = ar == null ? 0.0 : _contrast(ar, face);
  return (
    n: 1,
    face: _hex(face),
    icon: ic == null ? '-' : _hex(ic),
    ink: _hex(ink),
    sub: sc == null ? '-' : _hex(sc),
    arrow: ar == null ? '-' : _hex(ar),
    cr: cr.toStringAsFixed(2),
    scr: scr.toStringAsFixed(2),
    icr: icr.toStringAsFixed(2),
    acr: acr.toStringAsFixed(2),
    ok: cr >= 4.5 && scr >= 4.5 && icr >= 3.0 && acr >= 3.0,
    pair: owner != null && _same(face, want.face) && _same(ic, want.icon) && _same(ink, want.ink) && _same(sc, want.sub) && _same(ar, want.arrow),
  );
}

/// 출퇴근 안내 하나 — 제목 [c.note] 이 그려진 RichText(host 안 정확히 하나)의 글자색 · 그 글 뒤 면 · 그 면 상자 안 draw_outlined 아이콘 · 설명 [c.noteSub] 글자색 ·
///   안내 상자(ValueKey checkin-contract-gate) 테두리 위 선 색 · 대비. pair = 면 · 아이콘 · 제목 · 설명 · 테두리 = 사례의 결정 짝(후보). 안내 없는 사례(note null)는 n=0.
typedef _NoteObs = ({int n, String face, String icon, String ink, String sub, String border, String cr, String scr, bool ok45, bool pair});

_NoteObs _noteOf(Finder host, _Case c) {
  final head = c.note;
  final es = head == null ? <Element>[] : _richIn(host, head);
  if (es.length != 1) {
    return (n: es.length, face: '-', icon: '-', ink: '-', sub: '-', border: '-', cr: '0.00', scr: '0.00', ok45: false, pair: false);
  }
  final el = es.first;
  final Color ink = (el.widget as RichText).text.style?.color ?? Colors.transparent;
  final face = _bgOf(el);
  final owner = _ownerOf(el);
  final box = owner == null ? host : find.byElementPredicate((x) => identical(x, owner), skipOffstage: false);
  final ics = find
      .descendant(of: box, matching: find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.draw_outlined, skipOffstage: false), skipOffstage: false)
      .evaluate()
      .toList();
  final Color? ic = ics.length == 1 ? (ics.first.widget as Icon).color : null;
  final sub = c.noteSub;
  final ss = sub == null ? <Element>[] : _richIn(box, sub);
  final Color? sc = ss.length == 1 ? (ss.first.widget as RichText).text.style?.color : null;
  final gs = find
      .descendant(of: host, matching: find.byKey(const ValueKey('checkin-contract-gate'), skipOffstage: false), skipOffstage: false)
      .evaluate()
      .toList();
  final Decoration? gd = gs.length == 1 && gs.first.widget is Container ? (gs.first.widget as Container).decoration : null;
  final BoxBorder? gb = gd is BoxDecoration ? gd.border : null;
  final Color? bc = gb is Border ? gb.top.color : null;
  final cr = _contrast(ink, face);
  final scr = sc == null ? 0.0 : _contrast(sc, face);
  return (
    n: 1,
    face: _hex(face),
    icon: ic == null ? '-' : _hex(ic),
    ink: _hex(ink),
    sub: sc == null ? '-' : _hex(sc),
    border: bc == null ? '-' : _hex(bc),
    cr: cr.toStringAsFixed(2),
    scr: scr.toStringAsFixed(2),
    ok45: cr >= 4.5 && (sub == null || scr >= 4.5),
    pair: owner != null && _same(face, c.face) && _same(ic, c.icon) && _same(ink, c.ink) && (sub == null || _same(sc, c.subInk)) && _same(bc, c.border),
  );
}
