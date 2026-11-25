// ignore_for_file: depend_on_referenced_packages
// [DU553 · 표시만] 지원자 '내 지원' 화면(MyApplicationsScreen · DU-S071) — 다음 페이지 조회 실패를 빈 칸 + 토스트로 두지 않는다(감사139 §5-3 · §5-4 PP-MYAPPLICATIONS-READERROR-20261120).
//   before = 현재 A(my_applications_screen 0c0f52a8 · DU547 r3 채택판) 기록 전용 · strict = 후보(12db2a55).
//   [r2 · 실행 전 판정 §4] r1 후보 4b1ae1f1 에서 다음 페이지 리뷰 catch 한 덩어리만 뺀 판(base 호출 유지) — 시험 상태 · 기대 · 단언 변경 0(리뷰 실패 주입 상태 0).
//   하네스 = DU547 r3(du1_s071_myapps_readerror_547_test eb2963a2 · 정규 DONE 5/5)의 읽기 경계(MyApplicationsReads) · 시계(clock) · 플랫폼 채널 전수 관찰 · HTTP 대역 그대로 —
//     목록 읽기(myApplicationsPaged)만 사례별로 n 번째 호출을 실패시킨다. [DU553] 커서가 있는 읽기(다음 페이지)가 성공하면 사례의 page2 를 돌려준다(MOREROK 만 이 갈래에 온다).
//   상태 6: MORE(성공 · 더 있음 → 필터 칩 → 다음 페이지 실패) · MORENET(같음 · 네트워크 원인) · MOREALL(MORE 뒤 '전체' 칩 — 받은 목록 + 목록 끝 안내) ·
//     MOREROK(MORE 뒤 목록 끝 다시 시도 → 성공) · MORERFAIL(MORE 뒤 다시 시도 → 또 실패) · PEND(정상 목록 · 더 없음 · 회귀).
//   누르는 것: 두 모드의 필터 칩 '진행중 0'(다음 페이지 읽기 — DU547 MORE 와 같은 길) · MOREALL 두 모드의 '전체 1'(읽기 0) · strict 만 목록 끝 '다시 시도'(MOREROK · MORERFAIL — 같은 커서 다시 읽기).
//     서버 쓰기 버튼(취소 · 수락 · 거절 · 퇴사 등)과 뒤로가기는 누르지 않는다.
//   [DU547 r3 교훈] 칩 글 세기는 skipOffstage: false(가로 칩 줄 ensureVisible 이 앞 칩을 칸 밖으로 민다).
//   기본 skip — TB before/du553-tb/DU_BEFORE_OBSERVE=553 · TA after/du553-ta/없음.
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
import 'package:ALfit/widgets/common/loading_widget.dart';
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

/// 지원 요건을 갖춘 **시험용** 사용자 — 실제 신원 · 계좌 검증이 아니다(DU459 · DU477 · DU544 · DU547 와 같은 대역).
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

/// 시계 = KST 2026-11-20 12:00(화면 clock · DU544 · DU547 과 같다). 카드는 사흘 뒤(page2 는 나흘 뒤) 20:00–22:00 근무.
final DateTime _today = FormatHelper.toKstDate(DateTime.utc(2026, 11, 20));
DateTime _day(int d) => _today.add(Duration(days: d));
DateTime _at(DateTime day, String hhmm) => FormatHelper.kstWallClockInstant(day, hhmm)!;
final DateTime _noon = _at(_today, '12:00');

/// 지원 한 건(DU547 `_mk` 그대로 + [DU553] 문서 id 인자 — page2 의 두 번째 지원서).
ApplicationModel _mk(String status, DateTime workDate, {String id = 'a1'}) => ApplicationModel(
      id: id, toId: 'to1', slotId: 'slot1', wdId: 'wd-1', uid: _kUid, businessId: 'biz1', businessName: 'QA 사업장',
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

typedef _Case = ({String id, List<ApplicationModel> apps, List<ApplicationModel> page2, Set<int> failAt, bool net, bool more});

/// 사례 한 줄 — 상태 이름은 이름 인자 `id:`(preflight v25 가 목록에서 fixture 값 집합을 읽는다).
///   failAt = 목록 읽기의 몇 번째 호출을 실패시키는가 · net = 네트워크 원인(FirebaseException unavailable) · more = 첫 페이지가 '더 있음' ·
///   page2 = 커서 있는 읽기가 성공할 때의 다음 페이지(더 없음).
_Case _c({required String id, List<ApplicationModel> apps = const [], List<ApplicationModel> page2 = const [], Set<int> failAt = const <int>{}, bool net = false, bool more = false}) =>
    (id: id, apps: apps, page2: page2, failAt: failAt, net: net, more: more);

/// 사례마다 새로 — 목록 읽기 호출 수.
class _Count {
  var list = 0;
}

/// 목록 읽기 경계 — 목록 읽기만 사례의 failAt 번째 호출에서 예외로 끝난다. 쓰기 경로는 대역이 없다(autoExpirePending 은 아무 일도 하지 않는다).
MyApplicationsReads _reads(_Case c, _Count n) => MyApplicationsReads(
      myApplicationsPaged: ({required String uid, required int pageSize, String? startAfterDocId}) async {
        n.list++;
        if (c.failAt.contains(n.list)) {
          if (c.net) throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable', message: 'du553 local list failure');
          throw Exception('du553 local list failure');
        }
        if (startAfterDocId != null) return {'items': c.page2, 'lastDocId': null, 'hasMore': false};
        return {'items': c.apps, 'lastDocId': c.more ? 'du553-p1' : null, 'hasMore': c.more};
      },
      toOrFailure: (id) async => (to: _to(), failed: false),
      contractsByWorker: (uid) async => const <EmploymentContractModel>[],
      autoExpirePending: (uid) async {},
      monthlyAttendances: ({required String userId, required int year, required int month}) async => const <AttendanceModel>[],
      reviewById: (key) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
    );

final _cases = <_Case>[
  _c(id: 'MORE', apps: [_mk(AppStatus.confirmed, _day(3))], failAt: const {2}, more: true),
  _c(id: 'MORENET', apps: [_mk(AppStatus.confirmed, _day(3))], failAt: const {2}, net: true, more: true),
  _c(id: 'MOREALL', apps: [_mk(AppStatus.confirmed, _day(3))], failAt: const {2}, more: true),
  _c(id: 'MOREROK', apps: [_mk(AppStatus.confirmed, _day(3))], page2: [_mk(AppStatus.pending, _day(4), id: 'a2')], failAt: const {2}, more: true),
  _c(id: 'MORERFAIL', apps: [_mk(AppStatus.confirmed, _day(3))], failAt: const {2, 3}, more: true),
  _c(id: 'PEND', apps: [_mk(AppStatus.pending, _day(3))]),
];

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';

/// 첫 화면이 부르는 읽기 CF(화면 소스 그대로 — initState 의 변경 제안 목록) — 이 밖의 CF 이름은 차단하고 센다.
const _readFns = <String>{'callableGetMyConfirmedReassignmentProposals'};

/// Firestore 쓰기 연산 — 하나라도 오면 fsw 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// [DU526 · DU534 · DU536–547 와 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널(UserProvider → AuthService).
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du553.fake.auth.';
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
        return codec.encodeMessage(<Object?>['not-found', 'du553-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      _hit(fn);
      return codec.encodeMessage(<Object?>[<String, Object?>{'proposals': const <Object?>[]}]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['internal', 'du553-harness', null]);
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
      return codec.encodeMessage(<Object?>['du553-blocked', '$op 차단', null]);
    } catch (e) {
      harness.add('fs $op $e');
      return null;
    }
  }
}

/// 외부 HTTP 차단 — 클라이언트 객체 생성은 허용하고 센다(ContractService 생성자가 서명 이미지용 http.Client() 를 만든다 · 요청 0),
///   실제 요청(모든 HttpClient 멤버 호출)은 [tries] 에 이름을 기록하고 실패시킨다(DU541 r2 · DU544 · DU547 과 같다).
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
    throw const SocketException('DU553 관측 — 외부 HTTP 차단');
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

/// 요소 하나가 보이고 눌리는가 — 화면 ∩ 가까운 Scrollable 칸 안 + 중심 hit(DU537 `_retryNow` · DU544 `_tapNow` · DU547 `_reachOf` 와 같은 식).
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

/// 끌어 넣은 뒤 프레임(DU544 · DU547 과 같은 6 × 50ms).
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// 읽기를 부르는 동작 뒤 프레임(DU547 과 같은 40 × 50ms).
Future<void> _afterRead(WidgetTester t) async {
  for (var i = 0; i < 40; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// 글 원문(후보 · base 소스 그대로 — mkcell 이 확인한다).
const _moreTitle = '지원 내역을 더 불러오지 못했어요';
const _failTitle = '지원 내역을 불러오지 못했어요';
const _retryText = '다시 시도';
const _filterEmpty = ['진행 중인 지원이 없어요', '확정된 일자리가 없어요', '종료된 지원 내역이 없어요', '받은 초대가 없어요', '일치하는 지원 내역이 없어요'];
const _bizName = 'QA 사업장';
const _chipAll1 = '전체 1';
const _chipAll2 = '전체 2';
const _chipProg0 = '진행중 0';
const _chipProg1 = '진행중 1';
const _toastSame = '추가 데이터를 불러오지 못했습니다';
const _toastNet = '네트워크 연결을 확인해 주세요';

typedef _Body = ({int fail, int mrow, int retry, int load, int fempty, int cards, int c1, int c2, int p0, int p1, int toast, int tsame, int tnet});

/// 본문 한 번 세기 — DU547 실패 본문 · 목록 끝 안내 · 다시 시도 · 로딩 표시 · 필터 빈 상태 · 카드 · 칩('전체 1/2' · '진행중 0/1') · 토스트(전체 · 같은 뜻 · 네트워크).
///   토스트는 화면 밖 private 위젯이라 이름으로 센다. 칩 글은 칩 줄 밖에 없어 skipOffstage: false(DU547 r3).
_Body _bodyNow(WidgetTester t) {
  var fe = 0;
  for (final x in _filterEmpty) {
    fe += findVisibleText(x).evaluate().length;
  }
  return (
    fail: findVisibleText(_failTitle).evaluate().length,
    mrow: findVisibleText(_moreTitle).evaluate().length,
    retry: find.widgetWithText(TextButton, _retryText).evaluate().length,
    load: find.byType(LoadingWidget).evaluate().length,
    fempty: fe,
    cards: find.text(_bizName).evaluate().length,
    c1: find.text(_chipAll1, skipOffstage: false).evaluate().length,
    c2: find.text(_chipAll2, skipOffstage: false).evaluate().length,
    p0: find.text(_chipProg0, skipOffstage: false).evaluate().length,
    p1: find.text(_chipProg1, skipOffstage: false).evaluate().length,
    toast: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ToastWidget').evaluate().length,
    tsame: findVisibleTextContaining(_toastSame).evaluate().length,
    tnet: findVisibleTextContaining(_toastNet).evaluate().length,
  );
}

/// 본문 한 줄 비교 키(출력 키 순서 그대로).
String _bodyKey(_Body b) =>
    '${b.fail}/${b.mrow}/${b.retry}/${b.load}/${b.fempty}/${b.cards}/${b.c1}/${b.c2}/${b.p0}/${b.p1}/${b.toast}/${b.tsame}/${b.tnet}';

/// 칩 네 키(c1/c2/p0/p1) — 두 모드 같은 기대로 단언한다(칩 줄은 후보가 바꾸지 않는다).
String _chipKey(_Body b) => '${b.c1}/${b.c2}/${b.p0}/${b.p1}';

final String _wantBrand = _hex(AppColors.brand);
final String _wantText2 = _hex(AppColors.textSecondary);

/// strict 기대(후보) — 첫 화면 본문. 키 = fail/mrow/retry/load/fempty/cards/c1/c2/p0/p1/toast/tsame/tnet.
const Map<String, String> _wantBody = {
  'MORE': '0/0/0/0/0/1/1/0/1/0/0/0/0',
  'MORENET': '0/0/0/0/0/1/1/0/1/0/0/0/0',
  'MOREALL': '0/0/0/0/0/1/1/0/1/0/0/0/0',
  'MOREROK': '0/0/0/0/0/1/1/0/1/0/0/0/0',
  'MORERFAIL': '0/0/0/0/0/1/1/0/1/0/0/0/0',
  'PEND': '0/0/0/0/0/1/1/0/0/1/0/0/0',
};

/// strict 기대(후보) — '진행중 0' 칩 → 다음 페이지 실패 뒤. 키 = tapped/lr/ + 본문 키.
///   받은 목록('전체 1')은 그대로 · 이 필터는 0건이지만 더 있음이라 필터 빈 상태 0 · 목록 끝 안내 + 다시 시도 · 같은 뜻 토스트 0(원인 토스트는 MORENET 만).
const Map<String, String> _wantAfter = {
  'MORE': 'true/2/0/1/1/0/0/0/1/0/1/0/0/0/0',
  'MORENET': 'true/2/0/1/1/0/0/0/1/0/1/0/1/0/1',
  'MOREALL': 'true/2/0/1/1/0/0/0/1/0/1/0/0/0/0',
  'MOREROK': 'true/2/0/1/1/0/0/0/1/0/1/0/0/0/0',
  'MORERFAIL': 'true/2/0/1/1/0/0/0/1/0/1/0/0/0/0',
};

/// strict 기대(후보) — MOREALL '전체 1' 칩 뒤(읽기 0): 받은 카드 1 + 목록 끝 안내.
const Map<String, String> _wantAfter2 = {
  'MOREALL': 'true/2/0/1/1/0/0/1/1/0/1/0/0/0/0',
};

/// strict 기대(후보) — 목록 끝 '다시 시도' 뒤. MOREROK = 같은 커서로 다음 페이지 성공(진행중 카드 1 · '전체 2' · 안내 0) · MORERFAIL = 또 실패(안내 그대로).
const Map<String, String> _wantAgain = {
  'MOREROK': 'true/3/0/0/0/0/0/1/0/1/0/1/0/0/0',
  'MORERFAIL': 'true/3/0/1/1/0/0/0/1/0/1/0/0/0/0',
};

/// 칩 기대(두 모드) — 첫 화면 · '진행중 0' 뒤 · '전체 1' 뒤 · 다시 시도 뒤(before 는 누르지 않아 앞 값 그대로).
const _wantChips = <String, String>{
  'MORE': '1/0/1/0', 'MORENET': '1/0/1/0', 'MOREALL': '1/0/1/0', 'MOREROK': '1/0/1/0', 'MORERFAIL': '1/0/1/0', 'PEND': '1/0/0/1',
};
const _wantChipsAfter = '1/0/1/0';
const _wantChipsAgain = <String, String>{'MOREROK': '0/1/0/1', 'MORERFAIL': '1/0/1/0'};

/// strict 기대(후보) — 목록 끝 안내 전문 · 다시 시도(보임 · hit · ≥48 · brand · 대비) · 닫기(뒤로) · 당겨 새로고침 수.
///   키 = n/vis/hit/m48/fg/cr45/tn/tin/tfg/bn/bvis/bhit/pulln.
final String _wantReach = '1/true/true/true/$_wantBrand/true/1/true/$_wantText2/1/true/true/1';

/// 다음 페이지 실패 흐름 상태 · '전체' 칩 상태 · 목록 끝 다시 시도 상태.
const _moreStates = <String>{'MORE', 'MORENET', 'MOREALL', 'MOREROK', 'MORERFAIL'};
const _allStates = <String>{'MOREALL'};
const _againStates = <String>{'MOREROK', 'MORERFAIL'};

/// 상태별 캡처 이름 · 상태 설명(캡처 조건 'state').
const _shotOf = <String, (String, String)>{
  'MORE': ('1more', 'next-page-failed'), 'MORENET': ('1morenet', 'next-page-failed-network'), 'MOREALL': ('1moreall', 'next-page-failed-all-filter'),
  'MOREROK': ('1morerok', 'next-page-retry-success'), 'MORERFAIL': ('1morerfail', 'next-page-retry-failed-again'), 'PEND': ('1pend', 'list-pending'),
};

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '553';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du553-tb' && _env['DU_BEFORE_OBSERVE'] == '553') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du553-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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
    _out('R553 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S953MR-${v.id}-${c.id} 내 지원 화면 다음 페이지 조회 실패 — 받은 목록 보존 · 그 페이지 다시 시도', (t) async {
        final tok = 'S953MR-${v.id}-${c.id}';
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
        _out('D553 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
          // 이 화면은 멈추지 않는 애니메이션이 있어 pumpAndSettle 대신 시간 전진(my_applications_* · DU544 · DU547 시험과 같다).
          for (var i = 0; i < 30; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          final nScr = find.byType(MyApplicationsScreen).evaluate().length;
          need('화면 1', nScr == 1, '개수 $nScr');

          Future<void> shot(String id, String state) async {
            _out('D553 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // 그려진 글 집합(첫 화면 · 보이는 글 기준 · 숫자는 # 으로). 기록용: TB · TA 의 set 을 손으로 대조한다(첫 화면은 두 모드 같아야 한다).
          final words = <String>{};
          for (final e in find.byType(Text, skipOffstage: true).evaluate()) {
            final d = (e.widget as Text).data;
            if (d != null && d.isNotEmpty) words.add(visibleText(d).replaceAll(RegExp(r'\d+'), '#'));
          }
          final wordList = words.toList()..sort();
          _out('D553 $tok att txt n=${wordList.length} set=${_enc(wordList.join('|'))}');

          // ① 첫 화면 본문 — 모든 상태(후보가 바꾸지 않는다 — 더 있음이어도 목록 끝은 빈 칸).
          final b0 = _bodyNow(t);
          _out('D553 $tok att body fail=${b0.fail} mrow=${b0.mrow} retry=${b0.retry} load=${b0.load} fempty=${b0.fempty} cards=${b0.cards} c1=${b0.c1} c2=${b0.c2} p0=${b0.p0} p1=${b0.p1} toast=${b0.toast} tsame=${b0.tsame} tnet=${b0.tnet}');
          final k0 = _bodyKey(b0);
          raw = 'body $k0';
          if (!_before) chk('strict 첫 화면 본문 = 기대', k0 == _wantBody[sid], '$k0 want ${_wantBody[sid]}');
          chk('첫 화면 칩 = 기대(두 모드)', _chipKey(b0) == _wantChips[sid], '${_chipKey(b0)} want ${_wantChips[sid]}');

          if (_moreStates.contains(sid)) {
            // ② 필터 칩 '진행중 0' → 그 필터가 비어 다음 페이지를 읽는다(두 모드 · DU547 MORE 와 같은 길) → 목록 읽기 2번째 실패.
            final chF = find.text(_chipProg0);
            final nCh = chF.evaluate().length;
            need('진행중 칩 1', nCh == 1, '개수 $nCh');
            await t.ensureVisible(chF);
            await _settle(t);
            final cp = _reachOf(t, chF, screen);
            _out('D553 $tok att chip n=$nCh vis=${cp.vis} hit=${cp.hit}');
            final ck = '$nCh/${cp.vis}/${cp.hit}';
            raw = '$raw chip $ck';
            chk('진행중 칩 보임 · hit(두 모드 · 그대로)', ck == '1/true/true', ck);
            await t.tap(chF);
            await _afterRead(t);
            final b1 = _bodyNow(t);
            _out('D553 $tok att after tapped=true lr=${count.list} fail=${b1.fail} mrow=${b1.mrow} retry=${b1.retry} load=${b1.load} fempty=${b1.fempty} cards=${b1.cards} c1=${b1.c1} c2=${b1.c2} p0=${b1.p0} p1=${b1.p1} toast=${b1.toast} tsame=${b1.tsame} tnet=${b1.tnet}');
            final ak = 'true/${count.list}/${_bodyKey(b1)}';
            raw = '$raw after $ak';
            if (!_before) chk('strict 다음 페이지 실패 뒤 본문 = 기대(받은 목록 · 더 있음 보존 · 목록 끝 안내 · 같은 뜻 토스트 0)', ak == _wantAfter[sid], '$ak want ${_wantAfter[sid]}');
            chk('다음 페이지 실패 뒤 칩 = 기대(두 모드 · 받은 목록 그대로)', _chipKey(b1) == _wantChipsAfter, '${_chipKey(b1)} want $_wantChipsAfter');
          }

          if (_allStates.contains(sid)) {
            // ③ '전체 1' 칩(읽기 0 — 필터가 비지 않아 다음 페이지를 부르지 않는다) → 받은 카드 + 목록 끝 안내.
            final c2F = find.text(_chipAll1, skipOffstage: false);
            final nC2 = c2F.evaluate().length;
            need('전체 칩 1', nC2 == 1, '개수 $nC2');
            await t.ensureVisible(c2F);
            await _settle(t);
            final cp2 = _reachOf(t, c2F, screen);
            _out('D553 $tok att chip2 n=$nC2 vis=${cp2.vis} hit=${cp2.hit}');
            final ck2 = '$nC2/${cp2.vis}/${cp2.hit}';
            raw = '$raw chip2 $ck2';
            if (!_before) chk('strict 전체 칩 보임 · hit', ck2 == '1/true/true', ck2);
            await t.tap(c2F);
            await _settle(t);
            final b2 = _bodyNow(t);
            _out('D553 $tok att after2 tapped=true lr=${count.list} fail=${b2.fail} mrow=${b2.mrow} retry=${b2.retry} load=${b2.load} fempty=${b2.fempty} cards=${b2.cards} c1=${b2.c1} c2=${b2.c2} p0=${b2.p0} p1=${b2.p1} toast=${b2.toast} tsame=${b2.tsame} tnet=${b2.tnet}');
            final ak2 = 'true/${count.list}/${_bodyKey(b2)}';
            raw = '$raw after2 $ak2';
            if (!_before) chk('strict 전체 칩 뒤 본문 = 기대(받은 카드 1 + 목록 끝 안내)', ak2 == _wantAfter2[sid], '$ak2 want ${_wantAfter2[sid]}');
            chk('전체 칩 뒤 칩 = 기대(두 모드)', _chipKey(b2) == _wantChipsAfter, '${_chipKey(b2)} want $_wantChipsAfter');
          }

          if (_moreStates.contains(sid)) {
            // ④ 목록 끝 안내 전문(끌어 넣은 뒤 보이는 칸 안) · 다시 시도(보임 · 중심 hit · 받는 자리 ≥48 · brand 글 · 대비) · 뒤로(닫기) · 당겨 새로고침 수.
            //   before 는 지금 모습(목록 끝 빈 칸 · 버튼 없음) 기록. 누르지 않는다.
            final tF = findVisibleText(_moreTitle);
            final rF = find.widgetWithText(TextButton, _retryText);
            final bkF = find.byType(BackButton);
            final nT = tF.evaluate().length;
            final nR = rF.evaluate().length;
            final nB = bkF.evaluate().length;
            final nRi = find.byType(RefreshIndicator).evaluate().length;
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
            final cr = tcr && rcr;
            _out('D553 $tok att reach n=$nR vis=$rv hit=$rh m48=$r48 fg=$rfg cr45=$cr tn=$nT tin=$tin tfg=$tfg bn=$nB bvis=$bv bhit=$bh pulln=$nRi');
            final rk = '$nR/$rv/$rh/$r48/$rfg/$cr/$nT/$tin/$tfg/$nB/$bv/$bh/$nRi';
            raw = '$raw reach $rk';
            if (!_before) chk('strict 목록 끝 안내 전문 · 다시 시도(보임 · hit · ≥48 · brand · 대비) · 뒤로 · 당겨 새로고침', rk == _wantReach, '$rk want $_wantReach');
          }

          if (_againStates.contains(sid)) {
            // ⑤ strict 만 목록 끝 '다시 시도'(같은 커서로 다음 페이지 다시 읽기). before 는 버튼이 없어 누르지 않는다(기록).
            var tapped = false;
            if (!_before) {
              final rF = find.widgetWithText(TextButton, _retryText);
              final nTap = rF.evaluate().length;
              need('다시 시도 1(탭 직전)', nTap == 1, '개수 $nTap');
              await t.tap(rF);
              tapped = true;
              await _afterRead(t);
            }
            final b3 = _bodyNow(t);
            _out('D553 $tok att again tapped=$tapped lr=${count.list} fail=${b3.fail} mrow=${b3.mrow} retry=${b3.retry} load=${b3.load} fempty=${b3.fempty} cards=${b3.cards} c1=${b3.c1} c2=${b3.c2} p0=${b3.p0} p1=${b3.p1} toast=${b3.toast} tsame=${b3.tsame} tnet=${b3.tnet}');
            final gk = '$tapped/${count.list}/${_bodyKey(b3)}';
            raw = '$raw again $gk';
            if (!_before) chk('strict 다시 시도 뒤 본문 = 기대', gk == _wantAgain[sid], '$gk want ${_wantAgain[sid]}');
            final wantG = _before ? _wantChipsAfter : _wantChipsAgain[sid];
            chk('다시 시도 뒤 칩 = 기대(before 는 누르지 않아 앞 값)', _chipKey(b3) == wantG, '${_chipKey(b3)} want $wantG');
          }

          // ⑥ 캡처.
          final so = _shotOf[sid]!;
          await shot(so.$1, so.$2);
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ⑦ 성공 · 실패 공통 정리 — 화면을 내리고 남은 지연(토스트 4초 등)이 끝날 시간을 준다.
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

        // ⑧ 집계 — 읽기 CF 수 · 목록 읽기 수 · 허용 밖 CF · Firestore 쓰기/그 밖 연산 · 예상 밖 채널 · HTTP 요청/클라이언트 생성.
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
        _out('D553 $tok att wire rp=$nRp lr=$nLr cfx=$nCfx fsw=$nFsw fso=$nFso unexpected=$nUnexp http=$nHttp hcl=$nHcl harness=$nHarness');

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
        _out('R553 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D553 $tok att fw n=$nFw');
        _out('D553 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        chk('쓰기 · 허용 밖 CF 0 · HTTP 요청 0 · 대역 오류 0', nCfx == 0 && nFsw == 0 && nHttp == 0 && nHarness == 0, unText);
        chk('읽기 CF = 변경 제안 목록 1', nRp == 1, 'rp $nRp');
        // 목록 읽기 수 — 첫 조회 1 + 다음 페이지 1(MORE* 두 모드) + 목록 끝 다시 시도 1(MOREROK · MORERFAIL strict 만). 스크롤 자동 재호출은 0 이어야 한다.
        final wantLr = sid == 'PEND' ? 1 : ((_againStates.contains(sid) && !_before) ? 3 : 2);
        chk('목록 읽기 수 = 기대', nLr == wantLr, 'lr $nLr want $wantLr');
        if (!_before) chk('strict 화면 전체 넘침 0(W · B — base 관측 0: DU547 r3 TA MORE · PEND)', nOvf == 0, ovfRaw);
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
