// ignore_for_file: depend_on_referenced_packages
// [DU547 · 표시만] 지원자 '내 지원' 화면(MyApplicationsScreen · DU-S071) — 목록 조회 실패를 빈 화면으로 보이지 않게(감사139 §5 PP-MYAPPLICATIONS-READERROR-20261120 · 최초 조회 실패).
//   before = 현재 A(my_applications_screen a9ce2c90) 기록 전용 · strict = 후보(0c0f52a8).
//   [r2] 필터 칩 숫자는 base 그대로(실패 때도 '전체 0' — 대표 11-19 결정) — 칩 값(c0 · cbare · c1)은 두 모드 같은 기대(_wantChips · _wantChipsAfter)로 단언한다.
//     r1(후보 264aa4e2 · 시험 59762cbe)은 실행 0 으로 상위 폴더에 보존.
//   [r3 · 시험 수리 1회차] B-MORE 에서 '진행중 0' 칩 ensureVisible 뒤 첫 칩 '전체 1' 이 가로 칩 줄 칸 밖(트리에는 있음)으로 밀려 onstage 세기 0(r2 진단 STOP) —
//     '전체' 칩 세 키(c0 · cbare · c1)만 skipOffstage: false 로 센다. 기대값 · 개수 · strict 단언 · 동작 · 캡처 변경 0(r2 시험 0c8c1036 에서 이 4곳만).
//   하네스 = DU544(du1_s071_myapps_color_544_test d12a107d)의 읽기 경계(MyApplicationsReads) · 시계(clock) · 플랫폼 채널 전수 관찰 · HTTP 대역 그대로 —
//     목록 읽기(myApplicationsPaged)만 사례별로 n 번째 호출을 실패시킨다(나머지 읽기는 DU544 와 같은 성공 응답).
//   상태 9: EMPTY(성공 0건) · LFAIL(첫 조회 실패) · LNET(첫 조회 실패 · 네트워크 원인) · RETRYOK(실패 → 다시 시도 → 성공) · RETRYFAIL(실패 → 다시 시도 → 또 실패) ·
//     REFETCH(성공 → 당겨 새로고침과 같은 콜백 → 재조회 실패 · 관측) · MORE(성공 · 더 있음 → 필터 칩 → 추가 페이지 실패 · 관측) · PEND · CONF(정상 목록 회귀).
//   누르는 것: strict 의 '다시 시도'(RETRYOK · RETRYFAIL — 같은 읽기 재호출) · 두 모드의 RefreshIndicator.show()(REFETCH — my_applications_attendance_refresh_test 의
//     _refresh 와 같은 길) · 두 모드의 필터 칩 '진행중 0'(MORE — 다음 페이지 읽기). 서버 쓰기 버튼(취소 · 수락 · 거절 · 퇴사 등)과 뒤로가기는 누르지 않는다.
//   기본 skip — TB before/du547-tb/DU_BEFORE_OBSERVE=547 · TA after/du547-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/ui/invite_accept_readiness.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_applications_reads.dart';
import 'package:ALfit/screens/user/my_applications_screen.dart';
import 'package:ALfit/services/tax_identity_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/common/app_empty_state.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

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

const _kUid = 'u1';

/// 지원 요건을 갖춘 **시험용** 사용자 — 실제 신원 · 계좌 검증이 아니다(DU459 · DU477 · DU544 와 같은 대역).
class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: _kUid, username: _kUid, name: 'QA 지원자', email: '$_kUid@alfit.local', role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시'), accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 9, 1), idCardImagePath: 'id_cards/$_kUid/front.jpg', isIdVerified: true,
        bankName: '국민은행', accountNumber: '000000000000', accountHolder: 'QA 지원자', bankbookImagePath: 'bankbooks/$_kUid/b.jpg',
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

/// 시계 = KST 2026-11-20 12:00(화면 clock · DU544 와 같다). 카드는 사흘 뒤 20:00–22:00 근무 하나.
final DateTime _today = FormatHelper.toKstDate(DateTime.utc(2026, 11, 20));
DateTime _day(int d) => _today.add(Duration(days: d));
DateTime _at(DateTime day, String hhmm) => FormatHelper.kstWallClockInstant(day, hhmm)!;
final DateTime _noon = _at(_today, '12:00');

/// 지원 한 건(DU544 `_mk` 의 인자 그대로 · 초대/취소/장기 인자는 그 시험에서도 null 이었다 — 모델 기본값 null).
ApplicationModel _mk(String status, DateTime workDate) => ApplicationModel(
      id: 'a1', toId: 'to1', slotId: 'slot1', wdId: 'wd-1', uid: _kUid, businessId: 'biz1', businessName: 'QA 사업장',
      toTitle: 'QA 공고', status: status, selectedWorkType: 'QA 분류', startTime: '20:00', endTime: '22:00', wage: 13000,
      workDate: workDate, appliedAt: _today.subtract(const Duration(days: 7)),
      workInstanceCapacityState: InviteCapacityState.available, inviteAcceptReadiness: InviteAcceptReadiness.ready, publicIntakeClosed: false,
      documentAccessConsentGiven: true, documentAccessConsentVersion: DocumentAccessConsent.version,
    );

TOModel _to() => TOModel(
      id: 'to1', businessId: 'biz1', businessName: 'QA 사업장', type: 'flex', title: 'QA 공고', creatorUID: 'admin1',
      status: TOStatus.closed, deadlineType: 'NONE', hoursBeforeStart: 0, workDetails: const [], totalRequired: 3,
      totalConfirmed: 0, totalPending: 1, isPublished: true, publishMode: 'immediate',
      createdAt: _today.subtract(const Duration(days: 10)), statusUpdatedAt: _today.subtract(const Duration(days: 10)),
    );

typedef _Case = ({String id, List<ApplicationModel> apps, Set<int> failAt, bool net, bool more});

/// 사례 한 줄 — 상태 이름은 이름 인자 `id:`(preflight v25 가 목록에서 fixture 값 집합을 읽는다).
///   failAt = 목록 읽기의 몇 번째 호출을 실패시키는가 · net = 네트워크 원인(FirebaseException unavailable) · more = 첫 페이지가 '더 있음'.
_Case _c({required String id, List<ApplicationModel> apps = const [], Set<int> failAt = const <int>{}, bool net = false, bool more = false}) =>
    (id: id, apps: apps, failAt: failAt, net: net, more: more);

/// 사례마다 새로 — 목록 읽기 호출 수.
class _Count {
  var list = 0;
}

/// 목록 읽기 경계 — 목록 읽기만 사례의 failAt 번째 호출에서 예외로 끝난다. 쓰기 경로는 대역이 없다(autoExpirePending 은 아무 일도 하지 않는다).
MyApplicationsReads _reads(_Case c, _Count n) => MyApplicationsReads(
      myApplicationsPaged: ({required String uid, required int pageSize, String? startAfterDocId}) async {
        n.list++;
        if (c.failAt.contains(n.list)) {
          if (c.net) throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable', message: 'du547 local list failure');
          throw Exception('du547 local list failure');
        }
        return {'items': c.apps, 'lastDocId': c.more ? 'du547-p1' : null, 'hasMore': c.more};
      },
      toOrFailure: (id) async => (to: _to(), failed: false),
      contractsByWorker: (uid) async => const <EmploymentContractModel>[],
      autoExpirePending: (uid) async {},
      monthlyAttendances: ({required String userId, required int year, required int month}) async => const <AttendanceModel>[],
      reviewById: (key) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
    );

final _cases = <_Case>[
  _c(id: 'EMPTY'),
  _c(id: 'LFAIL', failAt: const {1}),
  _c(id: 'LNET', failAt: const {1}, net: true),
  _c(id: 'RETRYOK', apps: [_mk(AppStatus.pending, _day(3))], failAt: const {1}),
  _c(id: 'RETRYFAIL', failAt: const {1, 2}),
  _c(id: 'REFETCH', apps: [_mk(AppStatus.pending, _day(3))], failAt: const {2}),
  _c(id: 'MORE', apps: [_mk(AppStatus.confirmed, _day(3))], failAt: const {2}, more: true),
  _c(id: 'PEND', apps: [_mk(AppStatus.pending, _day(3))]),
  _c(id: 'CONF', apps: [_mk(AppStatus.confirmed, _day(3))]),
];

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';

/// 첫 화면이 부르는 읽기 CF(화면 소스 그대로 — initState 의 변경 제안 목록) — 이 밖의 CF 이름은 차단하고 센다.
const _readFns = <String>{'callableGetMyConfirmedReassignmentProposals'};

/// Firestore 쓰기 연산 — 하나라도 오면 fsw 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// [DU526 · DU534 · DU536–544 와 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널(UserProvider → AuthService).
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du547.fake.auth.';
const _authListeners = ['registerIdTokenListener', 'registerAuthStateListener'];

/// 원래 경로로 보내는 Flutter 기반 채널과 이유.
const _frameworkAllow = <String, String>{
  'flutter/assets': 'AssetBundle(아이콘 글꼴 · 이미지 매니페스트) 읽기',
  'flutter/platform': 'MaterialApp Title · SystemSound/Haptic',
  'flutter/navigation': '루트 Navigator 경로 보고',
  'flutter/mousecursor': 'MouseRegion 커서 갱신(시험 포인터)',
  'flutter/restoration': 'RootRestorationScope 상태 복원 조회',
  'flutter/keyboard': 'HardwareKeyboard 상태 동기화',
  'flutter/accessibility': '의미 트리/알림 전달',
};

/// 모든 플랫폼 메시지 관찰 — 읽기 CF 1종은 빈 목록 응답, 그 밖 CF 와 Firestore 는 차단 응답 + 기록,
///   기반 채널은 원래 경로, 나머지는 이름을 기록하고 응답 null. 예외를 삼키지 않는다 — 수는 줄로 남긴다.
class _Wire {
  final unexpected = <String>[];
  final blocked = <String>[];
  final fsWrites = <String>[];
  final fsOther = <String>[];
  final auth = <String>[];
  final harness = <String>[];
  final calls = <String, int>{};
  void _hit(String k) => calls[k] = (calls[k] ?? 0) + 1;

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (channel == _cfChannel) return Future<ByteData?>.value(_cf(message));
    if (channel.startsWith('$_fsBase.')) return Future<ByteData?>.value(_fs(channel.substring(_fsBase.length + 1)));
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

  ByteData? _cf(ByteData? message) {
    const codec = StandardMessageCodec();
    try {
      final args = (codec.decodeMessage(message) as List).first as Map;
      final fn = args['functionName'].toString();
      final region = args['region'].toString();
      if (region != 'asia-northeast3' || !_readFns.contains(fn)) {
        blocked.add('fn $fn@$region');
        return codec.encodeMessage(<Object?>['not-found', 'du547-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      _hit(fn);
      return codec.encodeMessage(<Object?>[<String, Object?>{'proposals': const <Object?>[]}]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['internal', 'du547-harness', null]);
    }
  }

  ByteData? _fs(String op) {
    const codec = FirebaseFirestoreHostApi.codec;
    try {
      if (_fsWrites.contains(op)) {
        fsWrites.add(op);
      } else {
        fsOther.add(op);
      }
      return codec.encodeMessage(<Object?>['du547-blocked', '$op 차단', null]);
    } catch (e) {
      harness.add('fs $op $e');
      return null;
    }
  }
}

/// 외부 HTTP 차단 — 클라이언트 객체 생성은 허용하고 센다(ContractService 생성자가 서명 이미지용 http.Client() 를 만든다 · 요청 0),
///   실제 요청(모든 HttpClient 멤버 호출)은 [tries] 에 이름을 기록하고 실패시킨다(DU541 r2 · DU544 와 같다).
class _NoHttp extends HttpOverrides {
  final tries = <String>[];
  var clients = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    return _BlockedHttpClient(tries);
  }
}

/// 요청을 하나도 보내지 않는 HttpClient — 어떤 멤버든 부르면 기록하고 SocketException.
class _BlockedHttpClient implements HttpClient {
  _BlockedHttpClient(this.tries);
  final List<String> tries;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    tries.add('HttpClient ${invocation.memberName}');
    throw const SocketException('DU547 관측 — 외부 HTTP 차단');
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

String _hex(Color col) {
  String h(double x) => (x * 255).round().toRadixString(16).padLeft(2, '0');
  return '${h(col.a)}${h(col.r)}${h(col.g)}${h(col.b)}';
}

/// WCAG 대비 — [fg] 글자 · [bg] 불투명 바탕.
double _contrast(Color fg, Color bg) {
  final a = Color.alphaBlend(fg, bg).computeLuminance();
  final b = bg.computeLuminance();
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

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

/// Text 하나의 글자색(style 에 색이 없으면 검정으로 적는다).
Color _fgOf(WidgetTester t, Finder f) => t.widget<Text>(f).style?.color ?? Colors.black;

/// Text 하나가 실제로 그린 글자색(안쪽 RichText — 버튼 · 테마가 준 기본 글색까지 합친 값). 하나가 아니면 투명.
Color _paintOf(WidgetTester t, Finder f) {
  final rt = find.descendant(of: f, matching: find.byType(RichText), skipOffstage: true);
  if (rt.evaluate().length != 1) return Colors.transparent;
  return t.widget<RichText>(rt).text.style?.color ?? Colors.black;
}

bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

/// 요소 하나가 보이고 눌리는가 — 화면 ∩ 가까운 Scrollable 칸 안 + 중심 hit(DU537 `_retryNow` · DU544 `_tapNow` 와 같은 식).
///   개수 1 을 확인한 뒤 · ensureVisible 뒤에만 부른다(화면 밖 rect 금지). 값은 즉시 돌려준다(renderObject 보관 0).
({bool vis, bool hit, Rect r}) _reachOf(WidgetTester t, Finder f, Rect screen) {
  var area = screen;
  final scF = find.ancestor(of: f, matching: find.byType(Scrollable));
  if (scF.evaluate().isNotEmpty) area = area.intersect(t.getRect(scF.first));
  final r = t.getRect(f);
  final ro = t.renderObject(f);
  final vis = _inside(r, area);
  final hit = t.hitTestOnBinding(r.center).path.any((x) => identical(x.target, ro));
  return (vis: vis, hit: hit, r: r);
}

/// 끌어 넣은 뒤 프레임(DU544 와 같은 6 × 50ms).
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// 글 원문(후보 · base 소스 그대로 — mkcell 이 확인한다).
const _failTitle = '지원 내역을 불러오지 못했어요';
const _retryText = '다시 시도';
const _emptyTitle = '아직 지원한 일자리가 없어요';
const _filterEmpty = ['진행 중인 지원이 없어요', '확정된 일자리가 없어요', '종료된 지원 내역이 없어요', '받은 초대가 없어요', '일치하는 지원 내역이 없어요'];
const _bizName = 'QA 사업장';
const _chipAll = '전체';
const _chipAll0 = '전체 0';
const _chipAll1 = '전체 1';
const _chipInProg0 = '진행중 0';
const _toastSame = '지원 내역을 불러오는데 실패했습니다';
const _toastNet = '네트워크 연결을 확인해 주세요';
const _toastMore = '추가 데이터를 불러오지 못했습니다';

typedef _Body = ({int fail, int retry, int empty, int fempty, int cards, int c0, int cbare, int c1, int toast, int tsame, int tnet, int tmore, String icon});

/// 본문 한 번 세기 — 실패 안내 · 다시 시도 · 빈 상태(성공 0건) · 필터 빈 상태 · 카드 · '전체' 칩(숫자 0 / 숫자 없음 / 1) · 토스트(전체 · 같은 뜻 · 네트워크 · 추가 페이지) ·
///   실패 안내 아이콘 색(공용 빈 상태 위젯 안 · 하나가 아니면 '-'). 토스트는 화면 밖 private 위젯이라 이름으로 센다.
_Body _bodyNow(WidgetTester t) {
  final icF = find.descendant(of: find.byType(AppEmptyState), matching: find.byType(Icon), skipOffstage: true);
  final nIc = icF.evaluate().length;
  final icon = nIc == 1 ? _hex(t.widget<Icon>(icF).color ?? Colors.transparent) : '-';
  var fe = 0;
  for (final x in _filterEmpty) {
    fe += findVisibleText(x).evaluate().length;
  }
  return (
    fail: findVisibleText(_failTitle).evaluate().length,
    retry: find.widgetWithText(TextButton, _retryText).evaluate().length,
    empty: findVisibleText(_emptyTitle).evaluate().length,
    fempty: fe,
    cards: find.text(_bizName).evaluate().length,
    c0: find.text(_chipAll0, skipOffstage: false).evaluate().length,
    cbare: find.text(_chipAll, skipOffstage: false).evaluate().length,
    c1: find.text(_chipAll1, skipOffstage: false).evaluate().length,
    toast: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ToastWidget').evaluate().length,
    tsame: findVisibleTextContaining(_toastSame).evaluate().length,
    tnet: findVisibleTextContaining(_toastNet).evaluate().length,
    tmore: findVisibleTextContaining(_toastMore).evaluate().length,
    icon: icon,
  );
}

/// 본문 한 줄 비교 키(출력 키 순서 그대로).
String _bodyKey(_Body b) =>
    '${b.fail}/${b.retry}/${b.empty}/${b.fempty}/${b.cards}/${b.c0}/${b.cbare}/${b.c1}/${b.toast}/${b.tsame}/${b.tnet}/${b.tmore}/${b.icon}';

final String _wantBrand = _hex(AppColors.brand);
final String _wantText2 = _hex(AppColors.textSecondary);
final String _wantErr = _hex(AppColors.error);

/// strict 기대(후보) — 첫 화면 본문. 키 = fail/retry/empty/fempty/cards/c0/cbare/c1/toast/tsame/tnet/tmore/icon.
final Map<String, String> _wantBody = {
  'EMPTY': '0/0/1/0/0/0/0/0/0/0/0/0/-',
  'LFAIL': '1/1/0/0/0/1/0/0/0/0/0/0/$_wantErr',
  'LNET': '1/1/0/0/0/1/0/0/1/0/1/0/$_wantErr',
  'RETRYOK': '1/1/0/0/0/1/0/0/0/0/0/0/$_wantErr',
  'RETRYFAIL': '1/1/0/0/0/1/0/0/0/0/0/0/$_wantErr',
  'REFETCH': '0/0/0/0/1/0/0/1/0/0/0/0/-',
  'MORE': '0/0/0/0/1/0/0/1/0/0/0/0/-',
  'PEND': '0/0/0/0/1/0/0/1/0/0/0/0/-',
  'CONF': '0/0/0/0/1/0/0/1/0/0/0/0/-',
};

/// strict 기대(후보) — 동작 뒤. 키 = tapped/lr/ + 본문 키.
///   REFETCH 은 재조회 실패도 실패 안내(이전 자료는 읽기 전에 비워져 카드 0 — 판정 §5-2 잔여) · MORE 는 바꾸지 않은 추가 페이지 실패(토스트 + 빈 칸 — §5-3 잔여).
final Map<String, String> _wantAfter = {
  'RETRYOK': 'true/2/0/0/0/0/1/0/0/1/0/0/0/0/-',
  'RETRYFAIL': 'true/2/1/1/0/0/0/1/0/0/0/0/0/0/$_wantErr',
  'REFETCH': 'true/2/1/1/0/0/0/1/0/0/0/0/0/0/$_wantErr',
  'MORE': 'true/2/0/0/0/0/0/0/0/1/1/0/0/1/-',
};

/// [r2] 필터 칩 '전체' 의 숫자(c0 = '전체 0' · cbare = 숫자 없는 '전체' · c1 = '전체 1') — base 와 같은 기대, 두 모드 같다(대표 11-19 결정).
///   실패 화면도 base 처럼 '전체 0'. 성공 0건(EMPTY)은 칩을 숨긴다(그대로). 근거: DU544 TA.jsonl:25 · :249(LFAIL chips=1).
const _wantChips = <String, String>{
  'EMPTY': '0/0/0', 'LFAIL': '1/0/0', 'LNET': '1/0/0', 'RETRYOK': '1/0/0', 'RETRYFAIL': '1/0/0',
  'REFETCH': '0/0/1', 'MORE': '0/0/1', 'PEND': '0/0/1', 'CONF': '0/0/1',
};

/// [r2] 동작 뒤 칩 — 두 모드 같다. RETRYOK 만 before 는 누르지 않아 실패 화면('1/0/0')이 남는다(strict = 성공 목록 '0/0/1').
const _wantChipsAfter = <String, String>{'RETRYOK': '0/0/1', 'RETRYFAIL': '1/0/0', 'REFETCH': '1/0/0', 'MORE': '0/0/1'};
const _wantChipsAfterBeforeRetryOk = '1/0/0';

/// strict 기대(후보) — 실패 안내 전문 · 다시 시도 · 닫기(뒤로) · 당겨 새로고침. 키 = n/vis/hit/m48/fg/cr45/tn/tin/tfg/bn/bvis/bhit/pulln/always.
final String _wantReach = '1/true/true/true/$_wantBrand/true/1/true/$_wantText2/1/true/true/1/true';

/// 첫 화면이 조회 실패인 상태 · 동작이 있는 상태.
const _failFirst = <String>{'LFAIL', 'LNET', 'RETRYOK', 'RETRYFAIL'};
const _acts = <String>{'RETRYOK', 'RETRYFAIL', 'REFETCH', 'MORE'};

/// 상태별 캡처 이름 · 상태 설명(캡처 조건 'state').
const _shotOf = <String, (String, String)>{
  'EMPTY': ('1empty', 'no-application-empty'), 'LFAIL': ('1lfail', 'list-load-failed'), 'LNET': ('1lnet', 'list-load-failed-network'),
  'RETRYOK': ('1rok', 'retry-success'), 'RETRYFAIL': ('1rfail', 'retry-failed-again'), 'REFETCH': ('1refetch', 'refetch-failed'),
  'MORE': ('1more', 'next-page-failed'), 'PEND': ('1pend', 'list-pending'), 'CONF': ('1conf', 'list-confirmed'),
};

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '547';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du547-tb' && _env['DU_BEFORE_OBSERVE'] == '547') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du547-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

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
      FirebasePlatform.instance = _FakeCore();
      await Firebase.initializeApp();
      await initializeDateFormatting('ko_KR');
      await _loadFonts();
      // FirebaseAuth 생성 때의 두 listener 등록 채널 모의(이벤트 0 · 로그인 상태 불변) — UserProvider(AuthService)가 처음 읽을 때 쓰인다.
      const codec = StandardMessageCodec();
      for (final name in _authListeners) {
        m.setMockMessageHandler('$_authBase$name', (_) async => codec.encodeMessage(<Object?>['$_authFake$name']));
        m.setMockMethodCallHandler(MethodChannel('$_authFake$name'), (_) async => null);
      }
    } finally {
      m.allMessagesHandler = prevAll;
      HttpOverrides.global = prevHttp;
    }
    final nCf = wire.calls.length + wire.blocked.length;
    final nUnexp = wire.unexpected.length;
    final nHttp = net.tries.length;
    _out('R547 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S947MR-${v.id}-${c.id} 내 지원 화면 조회 실패 — 빈 목록과 구분 · 다시 시도', (t) async {
        final tok = 'S947MR-${v.id}-${c.id}';
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
        _out('D547 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final user = _P();
        final count = _Count();
        final sid = c.id;
        Object? failure;
        StackTrace? failureSt;
        var shots = 0;
        var raw = '';
        try {
          FlutterError.onError = seen.add;
          final key = GlobalKey();
          await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
            value: user,
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                navigatorKey: navigatorKey,
                theme: RoleTheme.workerTheme,
                builder: (ctx, child) =>
                    MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: MyApplicationsScreen(reads: _reads(c, count), clock: () => _noon),
              ),
            ),
          ));
          // 이 화면은 멈추지 않는 애니메이션이 있어 pumpAndSettle 대신 시간 전진(my_applications_* · DU544 시험과 같다).
          for (var i = 0; i < 30; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          final nScr = find.byType(MyApplicationsScreen).evaluate().length;
          need('화면 1', nScr == 1, '개수 $nScr');

          Future<void> shot(String id, String state) async {
            _out('D547 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // 그려진 글 집합(첫 화면 · 보이는 글 기준 · 숫자는 # 으로). 기록용: TB · TA 의 set 을 손으로 대조한다(달라지는 것은 실패 사례뿐이어야 한다).
          final words = <String>{};
          for (final e in find.byType(Text, skipOffstage: true).evaluate()) {
            final d = (e.widget as Text).data;
            if (d != null && d.isNotEmpty) words.add(visibleText(d).replaceAll(RegExp(r'\d+'), '#'));
          }
          final wordList = words.toList()..sort();
          _out('D547 $tok att txt n=${wordList.length} set=${_enc(wordList.join('|'))}');

          // ① 첫 화면 본문 — 모든 상태.
          final b0 = _bodyNow(t);
          _out('D547 $tok att body fail=${b0.fail} retry=${b0.retry} empty=${b0.empty} fempty=${b0.fempty} cards=${b0.cards} c0=${b0.c0} cbare=${b0.cbare} c1=${b0.c1} toast=${b0.toast} tsame=${b0.tsame} tnet=${b0.tnet} tmore=${b0.tmore} icon=${b0.icon}');
          final k0 = _bodyKey(b0);
          raw = 'body $k0';
          if (!_before) chk('strict 첫 화면 본문 = 기대(실패 안내 · 빈 상태 · 칩 숫자 · 토스트)', k0 == _wantBody[sid], '$k0 want ${_wantBody[sid]}');
          final ch0 = '${b0.c0}/${b0.cbare}/${b0.c1}';
          chk('칩 숫자 = base 값(두 모드 · 대표 11-19 결정 — 실패 때도 숫자 표시)', ch0 == _wantChips[sid], '$ch0 want ${_wantChips[sid]}');

          // ② 조회 실패 첫 화면 — 안내 전문(끌어 넣은 뒤 보이는 칸 안) · 다시 시도(보임 · 중심 hit · 받는 자리 ≥48 · brand 글) · 뒤로(닫기) · 당겨 새로고침(항상 끌 수 있는 스크롤).
          //   before 는 지금 모습(빈 본문 · 버튼 없음) 기록. 누르지 않는다.
          if (_failFirst.contains(sid)) {
            final tF = findVisibleText(_failTitle);
            final rF = find.widgetWithText(TextButton, _retryText);
            final bkF = find.byType(BackButton);
            final riF = find.byType(RefreshIndicator);
            final nT = tF.evaluate().length;
            final nR = rF.evaluate().length;
            final nB = bkF.evaluate().length;
            final nRi = riF.evaluate().length;
            var tin = false;
            var tfg = '-';
            var tcr = false;
            if (nT == 1) {
              await t.ensureVisible(tF);
              await _settle(t);
              tin = _reachOf(t, tF, screen).vis;
              final tc = _fgOf(t, tF);
              tfg = _hex(tc);
              tcr = _contrast(tc, Colors.white) >= 4.5;
            }
            var rv = false;
            var rh = false;
            var r48 = false;
            var rfg = '-';
            var rcr = false;
            if (nR == 1) {
              await t.ensureVisible(rF);
              await _settle(t);
              final rp = _reachOf(t, rF, screen);
              rv = rp.vis;
              rh = rp.hit;
              r48 = rp.r.width >= 48 - 0.01 && rp.r.height >= 48 - 0.01;
              final rc = _paintOf(t, find.descendant(of: rF, matching: find.text(_retryText), skipOffstage: true));
              rfg = _hex(rc);
              rcr = _contrast(rc, Colors.white) >= 4.5;
            }
            var bv = false;
            var bh = false;
            if (nB == 1) {
              final bp = _reachOf(t, bkF, screen);
              bv = bp.vis;
              bh = bp.hit;
            }
            var always = false;
            if (nRi == 1) {
              final scF = find.descendant(of: riF, matching: find.byType(Scrollable), skipOffstage: true);
              if (scF.evaluate().length == 1) always = t.widget<Scrollable>(scF).physics is AlwaysScrollableScrollPhysics;
            }
            final cr = tcr && rcr;
            _out('D547 $tok att reach n=$nR vis=$rv hit=$rh m48=$r48 fg=$rfg cr45=$cr tn=$nT tin=$tin tfg=$tfg bn=$nB bvis=$bv bhit=$bh pulln=$nRi always=$always');
            final rk = '$nR/$rv/$rh/$r48/$rfg/$cr/$nT/$tin/$tfg/$nB/$bv/$bh/$nRi/$always';
            raw = '$raw reach $rk';
            if (!_before) chk('strict 실패 안내 전문 · 다시 시도(보임 · hit · ≥48 · brand · 대비) · 뒤로 · 당겨 새로고침', rk == _wantReach, '$rk want $_wantReach');
          }

          // ③ 동작 — RETRY*: strict 만 '다시 시도'(같은 읽기) · REFETCH: 두 모드 RefreshIndicator.show() · MORE: 두 모드 필터 칩 '진행중 0'(다음 페이지 읽기).
          var tapped = false;
          if ((sid == 'RETRYOK' || sid == 'RETRYFAIL') && !_before) {
            final rF = find.widgetWithText(TextButton, _retryText);
            final nTap = rF.evaluate().length;
            need('다시 시도 1(탭 직전)', nTap == 1, '개수 $nTap');
            await t.tap(rF);
            tapped = true;
          }
          if (sid == 'REFETCH') {
            final riF = find.byType(RefreshIndicator);
            final nRi = riF.evaluate().length;
            need('당겨 새로고침 1(목록)', nRi == 1, '개수 $nRi');
            t.state<RefreshIndicatorState>(riF).show();
            tapped = true;
          }
          if (sid == 'MORE') {
            final chF = find.text(_chipInProg0);
            final nCh = chF.evaluate().length;
            need('진행중 칩 1', nCh == 1, '개수 $nCh');
            await t.ensureVisible(chF);
            await _settle(t);
            final cp = _reachOf(t, chF, screen);
            _out('D547 $tok att chip n=$nCh vis=${cp.vis} hit=${cp.hit}');
            final ck = '$nCh/${cp.vis}/${cp.hit}';
            raw = '$raw chip $ck';
            if (!_before) chk('strict 진행중 칩 보임 · hit(그대로)', ck == '1/true/true', ck);
            await t.tap(chF);
            tapped = true;
          }
          if (_acts.contains(sid)) {
            for (var i = 0; i < 40; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final b1 = _bodyNow(t);
            final nLr1 = count.list;
            _out('D547 $tok att after tapped=$tapped lr=$nLr1 fail=${b1.fail} retry=${b1.retry} empty=${b1.empty} fempty=${b1.fempty} cards=${b1.cards} c0=${b1.c0} cbare=${b1.cbare} c1=${b1.c1} toast=${b1.toast} tsame=${b1.tsame} tnet=${b1.tnet} tmore=${b1.tmore} icon=${b1.icon}');
            final ak = '$tapped/$nLr1/${_bodyKey(b1)}';
            raw = '$raw after $ak';
            if (!_before) chk('strict 동작 뒤 본문 = 기대', ak == _wantAfter[sid], '$ak want ${_wantAfter[sid]}');
            final ch1 = '${b1.c0}/${b1.cbare}/${b1.c1}';
            final wantCh1 = (_before && sid == 'RETRYOK') ? _wantChipsAfterBeforeRetryOk : _wantChipsAfter[sid];
            chk('동작 뒤 칩 숫자 = base 값(두 모드)', ch1 == wantCh1, '$ch1 want $wantCh1');
          }

          // ④ 캡처.
          final so = _shotOf[sid]!;
          await shot(so.$1, so.$2);
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ⑤ 성공 · 실패 공통 정리 — 화면을 내리고 남은 지연(토스트 4초 등)이 끝날 시간을 준다.
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

        // ⑥ 집계 — 읽기 CF 수 · 목록 읽기 수 · 허용 밖 CF · Firestore 쓰기/그 밖 연산 · 예상 밖 채널 · HTTP 요청/클라이언트 생성.
        final nRp = wire.calls['callableGetMyConfirmedReassignmentProposals'] ?? 0;
        final nLr = count.list;
        final nCfx = wire.blocked.length;
        final nFsw = wire.fsWrites.length;
        final nFso = wire.fsOther.length;
        final nUnexp = wire.unexpected.length;
        final nHttp = net.tries.length;
        final nHcl = net.clients;
        final nHarness = wire.harness.length;
        final unText = [...wire.unexpected, ...wire.blocked, ...wire.fsWrites.map((x) => 'fsw $x'), ...wire.fsOther.map((x) => 'fs $x'), ...wire.harness, ...net.tries].join(' | ');
        _out('D547 $tok att wire rp=$nRp lr=$nLr cfx=$nCfx fsw=$nFsw fso=$nFso unexpected=$nUnexp http=$nHttp hcl=$nHcl harness=$nHarness');

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
        _out('R547 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D547 $tok att fw n=$nFw');
        _out('D547 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        chk('쓰기 · 허용 밖 CF 0 · HTTP 요청 0 · 대역 오류 0', nCfx == 0 && nFsw == 0 && nHttp == 0 && nHarness == 0, unText);
        chk('읽기 CF = 변경 제안 목록 1', nRp == 1, 'rp $nRp');
        // 목록 읽기 수 — 첫 조회 1 + (REFETCH · MORE 는 두 모드 1 · RETRY* 는 strict 만 다시 시도 1).
        final wantLr = (sid == 'REFETCH' || sid == 'MORE' || (!_before && (sid == 'RETRYOK' || sid == 'RETRYFAIL'))) ? 2 : 1;
        chk('목록 읽기 수 = 기대', nLr == wantLr, 'lr $nLr want $wantLr');
        if (!_before) chk('strict 화면 전체 넘침 0(W · B — base 관측 0: DU544 TA 38 사례)', nOvf == 0, ovfRaw);
        if (!_before) chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
        chk('캡처 수 = 1', shots == 1, 'shots $shots');
        final bad = checks.where((x) => !x.$2).toList();
        if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
        for (final x in checks) {
          expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
        }
      }, skip: !_optIn);
    }
  }
}

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
