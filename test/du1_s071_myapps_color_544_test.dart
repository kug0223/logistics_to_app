// ignore_for_file: depend_on_referenced_packages
// [DU544 · 표시만] 지원자 '내 지원' 화면(MyApplicationsScreen · DU-S071) 색 예산 1차 — 상태 문장 중립 · 초대 주 행동 brand 채움 · 지원 취소/퇴사 신청 진입 중립.
//   before = 현재 A(my_applications_screen 5a2de89e) 기록 전용 · strict = 후보(a9ce2c90).
//   [r1] 관리자 거절 배지(REJECT)도 중립 짝으로 바꾼 후보 — 상태 19. r0 시험(921c72ee · 상태 18)은 실행 0 으로 r0/ 에 보존.
//   하네스 = S071 기존 시험(du1_s071_context_muted_459 · du1_s071_dday_badge_477 · invite_closure_projection_render)의 읽기 경계(MyApplicationsReads) · 시계(clock) +
//     DU536–541 의 플랫폼 채널 전수 관찰(읽기 CF 1종 = 변경 제안 목록만 빈 응답 · 그 밖 CF 와 Firestore 는 차단 응답 + 기록 · 기반 채널은 원래 경로 · 나머지는 기록) +
//     DU541 r2 의 HTTP 대역(클라이언트 생성 허용 · 요청만 차단 — 이 화면도 ContractService() 를 만든다).
//   상태 19 · 누르는 것 0 — ensureVisible(끌기)만 쓴다. 서버 호출 버튼(취소 · 수락 · 동의 · 서류 등록 · 다시 확인 · 거절 · 퇴사 신청)은 누르지 않는다.
//   기본 skip — TB before/du544-tb/DU_BEFORE_OBSERVE=544 · TA after/du544-ta/없음.
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

/// 지원 요건을 갖춘 **시험용** 사용자 — 실제 신원 · 계좌 검증이 아니다(DU459 · DU477 과 같은 대역).
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

/// 시계 = KST 2026-11-20 12:00(화면 clock). 오늘 근무 · 다음 근무 · 지난달 근무를 이 한 값에서 센다.
final DateTime _today = FormatHelper.toKstDate(DateTime.utc(2026, 11, 20));
final DateTime _oct = FormatHelper.toKstDate(DateTime.utc(2026, 10, 20));
DateTime _day(int d) => _today.add(Duration(days: d));
DateTime _at(DateTime day, String hhmm) => FormatHelper.kstWallClockInstant(day, hhmm)!;
final DateTime _noon = _at(_today, '12:00');
final DateTime _invited = _noon.subtract(const Duration(hours: 1));
final DateTime _deadline = _noon.add(const Duration(hours: 23));

ApplicationModel _mk(String status, DateTime workDate,
        {String start = '20:00',
        String end = '22:00',
        DateTime? invitedAt,
        InviteAcceptReadiness r = InviteAcceptReadiness.ready,
        String? cancelReason,
        String? offerKind,
        String? sourceWorkType,
        String? applicationType,
        DateTime? workEndDate}) =>
    ApplicationModel(
      id: 'a1', toId: 'to1', slotId: 'slot1', wdId: 'wd-1', uid: _kUid, businessId: 'biz1', businessName: 'QA 사업장',
      toTitle: 'QA 공고', status: status, selectedWorkType: 'QA 분류', startTime: start, endTime: end, wage: 13000,
      workDate: workDate, appliedAt: _today.subtract(const Duration(days: 7)), invitedAt: invitedAt,
      inviteExpiresAt: invitedAt == null ? null : _deadline,
      inviteAcceptDeadline: invitedAt == null ? null : _deadline,
      workInstanceCapacityState: InviteCapacityState.available, inviteAcceptReadiness: r, publicIntakeClosed: false,
      cancelReason: cancelReason, offerKind: offerKind, sourceWorkType: sourceWorkType, applicationType: applicationType, workEndDate: workEndDate,
      documentAccessConsentGiven: true, documentAccessConsentVersion: DocumentAccessConsent.version,
    );

/// 사흘 뒤 20:00 근무 초대 — 기한 = 시계 + 23시간(수락 가능).
ApplicationModel _inv(InviteAcceptReadiness r, {String? offerKind, String? sourceWorkType}) =>
    _mk(AppStatus.invited, _day(3), invitedAt: _invited, r: r, offerKind: offerKind, sourceWorkType: sourceWorkType);

/// 근태 한 건(이 지원서 a1) — 출근 시각 · 퇴근 시각(없으면 근무 중) · 급여 상태.
AttendanceModel _att(DateTime day, {required String inAt, String? outAt, String wage = 'pending'}) => AttendanceModel(
      id: 'att-a1', applicationId: 'a1', userId: _kUid, businessId: 'biz1', businessName: 'QA 사업장', workDate: day, workType: 'QA 분류',
      checkInAt: _at(day, inAt), checkOutAt: outAt == null ? null : _at(day, outAt), status: AttendanceModel.statusPresent,
      wageStatus: wage, createdAt: day,
    );

TOModel _to() => TOModel(
      id: 'to1', businessId: 'biz1', businessName: 'QA 사업장', type: 'flex', title: 'QA 공고', creatorUID: 'admin1',
      status: TOStatus.closed, deadlineType: 'NONE', hoursBeforeStart: 0, workDetails: const [], totalRequired: 3,
      totalConfirmed: 0, totalPending: 1, isPublished: true, publishMode: 'immediate',
      createdAt: _today.subtract(const Duration(days: 10)), statusUpdatedAt: _today.subtract(const Duration(days: 10)),
    );

typedef _Case = ({String id, List<ApplicationModel> apps, List<AttendanceModel> atts, bool listFail, bool ctFail});

/// 사례 한 줄 — 상태 이름은 이름 인자 `id:`(preflight v25 가 목록에서 fixture 값 집합을 읽는다).
_Case _c({required String id, required List<ApplicationModel> apps, List<AttendanceModel> atts = const [], bool listFail = false, bool ctFail = false}) =>
    (id: id, apps: apps, atts: atts, listFail: listFail, ctFail: ctFail);

/// 목록 읽기 경계 — 실패 사례는 목록(LFAIL) · 계약(CFAIL) 읽기만 예외로 끝난다. 쓰기 경로는 대역이 없다(autoExpirePending 은 아무 일도 하지 않는다).
MyApplicationsReads _reads(_Case c) => MyApplicationsReads(
      myApplicationsPaged: ({required String uid, required int pageSize, String? startAfterDocId}) async {
        if (c.listFail) throw Exception('du544 local list failure');
        return {'items': c.apps, 'lastDocId': null, 'hasMore': false};
      },
      toOrFailure: (id) async => (to: _to(), failed: false),
      contractsByWorker: (uid) async {
        if (c.ctFail) throw Exception('du544 local contract failure');
        return const <EmploymentContractModel>[];
      },
      autoExpirePending: (uid) async {},
      monthlyAttendances: ({required String userId, required int year, required int month}) async => c.atts,
      reviewById: (key) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
    );

final _cases = <_Case>[
  _c(id: 'EMPTY', apps: const []),
  _c(id: 'LFAIL', apps: const [], listFail: true),
  _c(id: 'PEND', apps: [_mk(AppStatus.pending, _day(3))]),
  _c(id: 'CPREP', apps: [_mk(AppStatus.contractPending, _day(3))]),
  _c(id: 'CFAIL', apps: [_mk(AppStatus.contractPending, _day(3))], ctFail: true),
  _c(id: 'CWORK', apps: [_mk(AppStatus.contractPending, _today, start: '10:00', end: '18:00')], atts: [_att(_today, inAt: '10:00')]),
  _c(id: 'CONF', apps: [_mk(AppStatus.confirmed, _day(3))]),
  _c(id: 'TODAY', apps: [_mk(AppStatus.confirmed, _today)]),
  _c(id: 'WORK', apps: [_mk(AppStatus.confirmed, _today, start: '10:00', end: '18:00')], atts: [_att(_today, inAt: '10:00')]),
  _c(id: 'SETTLE', apps: [_mk(AppStatus.confirmed, _today, start: '08:00', end: '11:00')], atts: [_att(_today, inAt: '08:00', outAt: '11:00')]),
  _c(id: 'DONE', apps: [_mk(AppStatus.confirmed, _oct, start: '10:00', end: '18:00')], atts: [_att(_oct, inAt: '10:00', outAt: '18:00', wage: 'confirmed')]),
  _c(id: 'CANCEL', apps: [_mk(AppStatus.canceled, _day(3), cancelReason: 'USER_CANCELED')]),
  _c(id: 'REJECT', apps: [_mk(AppStatus.rejected, _day(3))]),
  _c(id: 'INVITE', apps: [_inv(InviteAcceptReadiness.ready)]),
  _c(id: 'OFFER', apps: [_inv(InviteAcceptReadiness.ready, offerKind: 'ALTERNATIVE_WORK', sourceWorkType: '상차')]),
  _c(id: 'CONSENT', apps: [_inv(InviteAcceptReadiness.consentRequired)]),
  _c(id: 'DOCREQ', apps: [_inv(InviteAcceptReadiness.documentRequired)]),
  _c(id: 'RECHECK', apps: [_inv(InviteAcceptReadiness.unavailable)]),
  _c(id: 'LONG', apps: [_mk(AppStatus.confirmed, _day(-10), applicationType: AppType.longTerm, workEndDate: _day(30))]),
];

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';

/// 첫 화면이 부르는 읽기 CF(화면 소스 그대로 — initState 의 변경 제안 목록) — 이 밖의 CF 이름은 차단하고 센다.
const _readFns = <String>{'callableGetMyConfirmedReassignmentProposals'};

/// Firestore 쓰기 연산 — 하나라도 오면 fsw 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// [DU526 · DU534 · DU536–541 과 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널(UserProvider → AuthService).
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du544.fake.auth.';
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
        return codec.encodeMessage(<Object?>['not-found', 'du544-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      _hit(fn);
      return codec.encodeMessage(<Object?>[<String, Object?>{'proposals': const <Object?>[]}]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['internal', 'du544-harness', null]);
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
      return codec.encodeMessage(<Object?>['du544-blocked', '$op 차단', null]);
    } catch (e) {
      harness.add('fs $op $e');
      return null;
    }
  }
}

/// 외부 HTTP 차단 — 클라이언트 객체 생성은 허용하고 센다(ContractService 생성자가 서명 이미지용 http.Client() 를 만든다 · 요청 0),
///   실제 요청(모든 HttpClient 멤버 호출)은 [tries] 에 이름을 기록하고 실패시킨다(DU541 r2 와 같다).
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
    throw const SocketException('DU544 관측 — 외부 HTTP 차단');
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

/// [f](글)에서 가장 가까운 Container 의 면 색(BoxDecoration.color · 없으면 Container.color · 그것도 없으면 투명).
Color _faceOf(WidgetTester t, Finder f) {
  final box = t.widget<Container>(find.ancestor(of: f, matching: find.byType(Container)).first);
  final d = box.decoration;
  if (d is BoxDecoration) return d.color ?? Colors.transparent;
  return box.color ?? Colors.transparent;
}

/// Text 하나의 글자색(style 에 색이 없으면 검정으로 적는다).
Color _fgOf(WidgetTester t, Finder f) => t.widget<Text>(f).style?.color ?? Colors.black;

/// Text 하나가 실제로 그린 글자색(안쪽 RichText — 버튼 · 테마가 준 기본 글색까지 합친 값). 하나가 아니면 투명.
Color _paintOf(WidgetTester t, Finder f) {
  final rt = find.descendant(of: f, matching: find.byType(RichText), skipOffstage: true);
  if (rt.evaluate().length != 1) return Colors.transparent;
  return t.widget<RichText>(rt).text.style?.color ?? Colors.black;
}

typedef _Ink = ({int n, String face, String fg, bool cr});

/// 글 하나([f]) — 개수 · 가장 가까운 Container 면 · 글 색 · 대비(면을 흰 바탕 위에 합성). 하나가 아니면 '-'.
_Ink _inkOf(WidgetTester t, Finder f) {
  final n = f.evaluate().length;
  if (n != 1) return (n: n, face: '-', fg: '-', cr: false);
  final faceC = _faceOf(t, f);
  final fgC = _fgOf(t, f);
  return (n: n, face: _hex(faceC), fg: _hex(fgC), cr: _contrast(fgC, Color.alphaBlend(faceC, Colors.white)) >= 4.5);
}

bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

/// 버튼 글 하나가 보이고 눌리는가(기록 전용) — 화면 ∩ 가까운 Scrollable 칸 안 + 중심 hit(DU537 `_retryNow` · DU538 r2 `_tapNow` 와 같은 식).
///   개수 1 을 확인한 뒤 · ensureVisible 뒤에만 부른다(화면 밖 rect 금지).
({bool vis, bool hit}) _tapNow(WidgetTester t, Finder f, Rect screen) {
  var area = screen;
  final scF = find.ancestor(of: f, matching: find.byType(Scrollable));
  if (scF.evaluate().isNotEmpty) area = area.intersect(t.getRect(scF.first));
  final r = t.getRect(f);
  final ro = t.renderObject(f);
  final vis = _inside(r, area);
  final hit = t.hitTestOnBinding(r.center).path.any((x) => identical(x.target, ro));
  return (vis: vis, hit: hit);
}

final String _wantGrey100 = _hex(AppColors.grey100);
final String _wantGrey300 = _hex(AppColors.grey300);
final String _wantGrey400 = _hex(AppColors.grey400);
final String _wantGrey600 = _hex(AppColors.grey600);
final String _wantGrey700 = _hex(AppColors.grey700);
final String _wantText2 = _hex(AppColors.textSecondary);
final String _wantText3 = _hex(AppColors.textTertiary);
final String _wantBrand = _hex(AppColors.brand);
final String _wantWhite = _hex(Colors.white);
final String _wantLine = _hex(AppColors.border);
final String _wantTeal = _hex(AppColors.teal);
final String _wantTealDark = _hex(AppColors.tealDark);

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];

/// 글 원문(대상 소스 · 모델 소스 그대로 — mkcell 이 base · 후보 · 모델에서 확인한다).
const _badgeLabel = <String, String>{
  'PEND': '지원 검토 중', 'CPREP': '계약 진행 중', 'CFAIL': '계약 진행 중', 'CWORK': '계약 진행 중',
  'CONF': '확정', 'TODAY': '확정', 'WORK': '확정', 'SETTLE': '확정', 'DONE': '확정', 'LONG': '확정', 'CANCEL': '취소', 'REJECT': '거절',
  'INVITE': '근무 초대', 'OFFER': '근무 초대', 'CONSENT': '근무 초대', 'DOCREQ': '근무 초대', 'RECHECK': '근무 초대',
};
const _ctxLine = <String, String>{
  'PEND': '지원 결과를 기다리고 있어요', 'CPREP': '관리자가 계약서를 준비 중이에요', 'CFAIL': '계약 정보를 불러오지 못했어요. 다시 시도해주세요',
  'CWORK': '근무 중이에요', 'TODAY': '오늘 근무 예정이에요', 'WORK': '근무 중이에요', 'SETTLE': '근무가 끝났어요 · 정산 중', 'DONE': '근무 완료',
  'CANCEL': '지원이 취소되었어요', 'REJECT': '이번 지원은 확정되지 않았어요', 'INVITE': '근무 초대가 도착했어요', 'OFFER': '다른 업무 제안이 도착했어요', 'CONSENT': '근무 초대가 도착했어요',
  'DOCREQ': '근무 초대가 도착했어요', 'RECHECK': '근무 초대가 도착했어요',
};
/// CONF · LONG 의 상태 문장 끝 — 앞의 날짜는 FormatHelper.formatDateKorean 이 만든다.
const _ctxSuffix = ' 출근 예정이에요';
const _actLabel = <String, String>{'INVITE': '수락하기', 'OFFER': '제안 조건으로 수락', 'CONSENT': '서류 열람 동의', 'DOCREQ': '서류 등록하기', 'RECHECK': '다시 확인'};
const _disLabel = '수락하기';
const _declineLabel = '거절';
const _cancelLabel = '취소';
const _resignLabel = '퇴사 신청';
const _interimLabel = '중간정산 요청';
const _emptyTitle = '아직 지원한 일자리가 없어요';
const _emptySubPart = '일자리를 찾아보세요';
const _emptyBtn = '날짜 선택하기';
const _toastPart = '지원 내역을 불러오는데 실패했습니다';
const _allChip0 = '전체 0';

/// 상태별 캡처 이름 · 상태 설명(캡처 조건 'state').
const _shotOf = <String, (String, String)>{
  'EMPTY': ('1empty', 'no-application-empty'), 'LFAIL': ('1lfail', 'list-load-failed'), 'PEND': ('1pend', 'pending-cancel-entry'),
  'CPREP': ('1cprep', 'contract-preparing'), 'CFAIL': ('1cfail', 'contract-read-failed-retry'), 'CWORK': ('1cwork', 'contract-pending-working'),
  'CONF': ('1conf', 'confirmed-upcoming'), 'TODAY': ('1today', 'confirmed-today'), 'WORK': ('1work', 'confirmed-working'),
  'SETTLE': ('1settle', 'confirmed-settling'), 'DONE': ('1done', 'confirmed-done'), 'CANCEL': ('1cancel', 'user-canceled'),
  'REJECT': ('1reject', 'admin-rejected'),
  'INVITE': ('1invite', 'invite-accept'), 'OFFER': ('1offer', 'alternative-offer-accept'), 'CONSENT': ('1consent', 'invite-consent-required'),
  'DOCREQ': ('1docreq', 'invite-document-required'), 'RECHECK': ('1recheck', 'invite-recheck'), 'LONG': ('1long', 'long-term-resign-entry'),
};

/// 상태 배지 기대 — StatusBadge 짝(그대로) · 관리자 거절(REJECT)만 후보에서 중립 짝으로 바뀐다. 정보 배지(infoBg/infoDark)는 판정 요청 1(대비 기록만).
(Color, Color) _wantBadge(String id) => switch (id) {
      'PEND' => (AppColors.warningBg, AppColors.warningDark),
      'CPREP' || 'CFAIL' || 'CWORK' || 'INVITE' || 'OFFER' || 'CONSENT' || 'DOCREQ' || 'RECHECK' => (AppColors.infoBg, AppColors.infoDark),
      'CANCEL' || 'REJECT' => (AppColors.grey100, AppColors.textSecondary),
      _ => (AppColors.successBg, AppColors.successDark),
    };
bool _infoBadge(String id) => _wantBadge(id).$1 == AppColors.infoBg;

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '544';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du544-tb' && _env['DU_BEFORE_OBSERVE'] == '544') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du544-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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
    _out('R544 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S944MA-${v.id}-${c.id} 내 지원 화면 색 1차 — 상태 문장 중립 · 행동 brand · 진입 중립', (t) async {
        final tok = 'S944MA-${v.id}-${c.id}';
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
        _out('D544 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final user = _P();
        final isB = v.id == 'B';
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
                home: MyApplicationsScreen(reads: _reads(c), clock: () => _noon),
              ),
            ),
          ));
          // 이 화면은 멈추지 않는 애니메이션이 있어 pumpAndSettle 대신 시간 전진(my_applications_* 시험과 같다).
          for (var i = 0; i < 30; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          final nScr = find.byType(MyApplicationsScreen).evaluate().length;
          need('화면 1', nScr == 1, '개수 $nScr');

          Future<void> shot(String id, String state) async {
            _out('D544 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          // 그려진 글 집합(보이는 글 기준 · 숫자는 # 으로). 기록용: TB · TA 의 set 이 같아야 한다(글 변경 0 — 손 대조).
          final words = <String>{};
          for (final e in find.byType(Text, skipOffstage: true).evaluate()) {
            final d = (e.widget as Text).data;
            if (d != null && d.isNotEmpty) words.add(visibleText(d).replaceAll(RegExp(r'\d+'), '#'));
          }
          final wordList = words.toList()..sort();
          _out('D544 $tok att txt n=${wordList.length} set=${_enc(wordList.join('|'))}');

          // 캡처 전에 화면 안으로 끌어 넣을 요소(상태마다 하나) — 개수 1 일 때만 끈다.
          Finder? focus;

          // ① 빈 목록(EMPTY) — 그대로: 아이콘 grey300 · 제목 grey700 · 부제 textTertiary · '날짜 선택하기' brand 채움.
          if (sid == 'EMPTY') {
            final etF = findVisibleText(_emptyTitle);
            final nEt = etF.evaluate().length;
            need('빈 상태 제목 1', nEt == 1, '개수 $nEt');
            final esF = findVisibleTextContaining(_emptySubPart);
            final nEs = esF.evaluate().length;
            need('빈 상태 부제 1', nEs == 1, '개수 $nEs');
            final eiF = find.byIcon(Icons.work_outline, skipOffstage: true);
            final nEi = eiF.evaluate().length;
            need('빈 상태 아이콘 1', nEi == 1, '개수 $nEi');
            final ebF = find.text(_emptyBtn, skipOffstage: true);
            final nEb = ebF.evaluate().length;
            need('날짜 선택하기 1', nEb == 1, '개수 $nEb');
            final eIcon = t.widget<Icon>(eiF).color ?? Colors.transparent;
            final eTitle = _fgOf(t, etF);
            final eSub = _fgOf(t, esF);
            final eBtn = t.widget<FilledButton>(find.ancestor(of: ebF, matching: find.byWidgetPredicate((w) => w is FilledButton)).first);
            final eFace = eBtn.style?.backgroundColor?.resolve(<WidgetState>{}) ?? Colors.transparent;
            final eFg = _paintOf(t, ebF);
            final eCr = _contrast(eTitle, Colors.white) >= 4.5 && _contrast(eSub, Colors.white) >= 4.5;
            _out('D544 $tok att empty n=$nEt icon=${_hex(eIcon)} title=${_hex(eTitle)} sub=${_hex(eSub)} bface=${_hex(eFace)} bfg=${_hex(eFg)} cr45=$eCr');
            final eRaw = 'empty ${_hex(eIcon)}/${_hex(eTitle)}/${_hex(eSub)}/${_hex(eFace)}/${_hex(eFg)} cr $eCr';
            raw = '$raw $eRaw';
            if (!_before) {
              chk('strict 빈 상태 그대로 — 아이콘 grey300 · 제목 grey700 · 부제 textTertiary · 버튼 brand 채움',
                  _hex(eIcon) == _wantGrey300 && _hex(eTitle) == _wantGrey700 && _hex(eSub) == _wantText3 && _hex(eFace) == _wantBrand, eRaw);
              chk('strict 빈 상태 글 대비 ≥4.5', eCr, eRaw);
            }
            focus = etF;
          }

          // ② 목록 조회 실패(LFAIL) — 기록 전용: 오류 토스트(E-TOAST) · 본문(필터 칩 · 빈 상태 문구 · 카드 수).
          if (sid == 'LFAIL') {
            final toF = findVisibleTextContaining(_toastPart);
            final nTo = toF.evaluate().length;
            final toFace = nTo == 1 ? _hex(_faceOf(t, toF)) : '-';
            final toFg = nTo == 1 ? _hex(_fgOf(t, toF)) : '-';
            _out('D544 $tok att toast n=$nTo face=$toFace fg=$toFg');
            final nChips = find.text(_allChip0, skipOffstage: true).evaluate().length;
            final nEmpty = findVisibleText(_emptyTitle).evaluate().length;
            final nCards = find.text('QA 사업장', skipOffstage: true).evaluate().length;
            _out('D544 $tok att body chips=$nChips empty=$nEmpty cards=$nCards');
            raw = '$raw toast $nTo $toFace/$toFg body $nChips/$nEmpty/$nCards';
          }

          // ③ 상태 배지(카드 상태) — 그대로(StatusBadge 짝).
          final bLabel = _badgeLabel[sid];
          if (bLabel != null) {
            final bgF = find.text(bLabel, skipOffstage: true);
            final bg = _inkOf(t, bgF);
            _out('D544 $tok att badge n=${bg.n} face=${bg.face} fg=${bg.fg} cr45=${bg.cr}');
            need('상태 배지 1', bg.n == 1, '$bLabel 개수 ${bg.n}');
            final bWant = _wantBadge(sid);
            final bRaw = 'badge ${bg.face}/${bg.fg} cr ${bg.cr}';
            raw = '$raw $bRaw';
            if (!_before) {
              chk('strict 상태 배지 그대로(StatusBadge 짝)', bg.face == _hex(bWant.$1) && bg.fg == _hex(bWant.$2), bRaw);
              if (!_infoBadge(sid)) chk('strict 상태 배지 대비 ≥4.5', bg.cr, bRaw);
            }
          }

          // ④ 상태 문장(카드 상태) — 행동 없는 문장 = grey600 · 다시 시도(CFAIL) = brand 글 + brand 꺾쇠.
          final cLine = _ctxLine[sid];
          final isDate = sid == 'CONF' || sid == 'LONG';
          if (cLine != null || isDate) {
            final cxF = find.byWidgetPredicate(
                (w) => w is Text && w.data != null && (isDate ? w.data!.endsWith(_ctxSuffix) : w.data == cLine),
                skipOffstage: true);
            final cx = _inkOf(t, cxF);
            final chF = find.byIcon(Icons.chevron_right, skipOffstage: true);
            final nCh = chF.evaluate().length;
            final chev = nCh == 0 ? '-' : (nCh == 1 ? _hex(t.widget<Icon>(chF).color ?? Colors.transparent) : 'many');
            _out('D544 $tok att ctx n=${cx.n} fg=${cx.fg} chev=$chev cr45=${cx.cr}');
            need('상태 문장 1', cx.n == 1, '${cLine ?? _ctxSuffix} 개수 ${cx.n}');
            final link = sid == 'CFAIL';
            final cRaw = 'ctx ${cx.fg} chev $chev cr ${cx.cr}';
            raw = '$raw $cRaw';
            if (!_before) {
              chk(link ? 'strict 다시 시도 문장 = brand 글 + brand 꺾쇠(그대로)' : 'strict 행동 없는 상태 문장 = grey600 · 꺾쇠 없음',
                  cx.fg == (link ? _wantBrand : _wantGrey600) && chev == (link ? _wantBrand : '-'), cRaw);
              chk('strict 상태 문장 대비 ≥4.5', cx.cr, cRaw);
            }
            focus = cxF;
          }

          // ⑤ 진입 · 행동 버튼 찾기(개수 1 확인 뒤 끌어 넣을 대상으로 둔다).
          final aLabel = _actLabel[sid];
          final cnF = find.text(_cancelLabel, skipOffstage: true);
          final acF = find.text(aLabel ?? _actLabel['INVITE']!, skipOffstage: true);
          final rsF = find.text(_resignLabel, skipOffstage: true);
          if (sid == 'PEND') {
            final nCn = cnF.evaluate().length;
            need('지원 취소 1', nCn == 1, '개수 $nCn');
            focus = cnF;
          }
          if (aLabel != null) {
            final nAc = acF.evaluate().length;
            need('주 행동 1', nAc == 1, '$aLabel 개수 $nAc');
            focus = acF;
          }
          if (sid == 'LONG') {
            final nRs = rsF.evaluate().length;
            need('퇴사 신청 1', nRs == 1, '개수 $nRs');
            focus = rsF;
          }

          // ⑥ 끌어 넣기(누르지 않는다) — 이 뒤의 보임 · hit 는 기록.
          final fx = focus;
          if (fx != null) {
            await t.ensureVisible(fx);
            for (var i = 0; i < 6; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
          }

          // ⑦ 대기 '취소'(PEND) — 확인창을 여는 진입: 중립 grey100 면 + textSecondary 글.
          if (sid == 'PEND') {
            final cn = _inkOf(t, cnF);
            final cnP = _tapNow(t, cnF, screen);
            _out('D544 $tok att cancel n=${cn.n} face=${cn.face} fg=${cn.fg} cr45=${cn.cr} vis=${cnP.vis} hit=${cnP.hit}');
            final cnRaw = 'cancel ${cn.face}/${cn.fg} cr ${cn.cr} vis ${cnP.vis} hit ${cnP.hit}';
            raw = '$raw $cnRaw';
            if (!_before) {
              chk('strict 지원 취소 진입 = grey100 · textSecondary(거절 버튼 짝)', cn.face == _wantGrey100 && cn.fg == _wantText2, cnRaw);
              chk('strict 지원 취소 대비 ≥4.5', cn.cr, cnRaw);
            }
          }

          // ⑧ 초대 카드 주 행동(INVITE · OFFER · CONSENT · DOCREQ · RECHECK) — brand 채움 + 흰 글. RECHECK 은 비활성 '수락하기'(그대로) 도 있다.
          if (aLabel != null) {
            final ac = _inkOf(t, acF);
            final acP = _tapNow(t, acF, screen);
            _out('D544 $tok att act n=${ac.n} face=${ac.face} fg=${ac.fg} cr45=${ac.cr} vis=${acP.vis} hit=${acP.hit}');
            final acRaw = 'act $aLabel ${ac.face}/${ac.fg} cr ${ac.cr} vis ${acP.vis} hit ${acP.hit}';
            raw = '$raw $acRaw';
            if (!_before) {
              chk('strict 주 행동 = brand 채움 + 흰 글', ac.face == _wantBrand && ac.fg == _wantWhite, acRaw);
              chk('strict 주 행동 대비 ≥4.5', ac.cr, acRaw);
            }
            if (sid == 'RECHECK') {
              final dsF = find.text(_disLabel, skipOffstage: true);
              final ds = _inkOf(t, dsF);
              _out('D544 $tok att dis n=${ds.n} face=${ds.face} fg=${ds.fg}');
              need('비활성 수락하기 1', ds.n == 1, '개수 ${ds.n}');
              final dsRaw = 'dis ${ds.face}/${ds.fg}';
              raw = '$raw $dsRaw';
              if (!_before) chk('strict 비활성 수락하기 그대로 = grey100 · grey400', ds.face == _wantGrey100 && ds.fg == _wantGrey400, dsRaw);
            }
            final dcF = find.text(_declineLabel, skipOffstage: true);
            final dc = _inkOf(t, dcF);
            _out('D544 $tok att decline n=${dc.n} face=${dc.face} fg=${dc.fg} cr45=${dc.cr}');
            need('거절 1', dc.n == 1, '개수 ${dc.n}');
            final dcRaw = 'decline ${dc.face}/${dc.fg} cr ${dc.cr}';
            raw = '$raw $dcRaw';
            if (!_before) chk('strict 거절 그대로(DU469) = grey100 · textSecondary · 대비 ≥4.5', dc.face == _wantGrey100 && dc.fg == _wantText2 && dc.cr, dcRaw);
          }

          // ⑨ 장기 확정(LONG) — '퇴사 신청' 진입 = textSecondary 글 · border 선 / '중간정산 요청' 은 그대로(teal · 판정 요청).
          if (sid == 'LONG') {
            final rsB = t.widget<OutlinedButton>(find.ancestor(of: rsF, matching: find.byWidgetPredicate((w) => w is OutlinedButton)).first);
            final rsFg = rsB.style?.foregroundColor?.resolve(<WidgetState>{}) ?? Colors.transparent;
            final rsSide = rsB.style?.side?.resolve(<WidgetState>{})?.color ?? Colors.transparent;
            final rsLab = _paintOf(t, rsF);
            final rsCr = _contrast(rsLab, Colors.white) >= 4.5;
            _out('D544 $tok att resign n=1 fg=${_hex(rsFg)} lab=${_hex(rsLab)} side=${_hex(rsSide)} cr45=$rsCr');
            final rsRaw = 'resign ${_hex(rsFg)}/${_hex(rsLab)}/${_hex(rsSide)} cr $rsCr';
            final imF = find.text(_interimLabel, skipOffstage: true);
            final nIm = imF.evaluate().length;
            need('중간정산 요청 1', nIm == 1, '개수 $nIm');
            final imB = t.widget<OutlinedButton>(find.ancestor(of: imF, matching: find.byWidgetPredicate((w) => w is OutlinedButton)).first);
            final imFg = imB.style?.foregroundColor?.resolve(<WidgetState>{}) ?? Colors.transparent;
            final imSide = imB.style?.side?.resolve(<WidgetState>{})?.color ?? Colors.transparent;
            _out('D544 $tok att interim n=$nIm fg=${_hex(imFg)} side=${_hex(imSide)}');
            final imRaw = 'interim ${_hex(imFg)}/${_hex(imSide)}';
            raw = '$raw $rsRaw $imRaw';
            if (!_before) {
              chk('strict 퇴사 신청 진입 = textSecondary 글 · border 선', _hex(rsFg) == _wantText2 && _hex(rsLab) == _wantText2 && _hex(rsSide) == _wantLine, rsRaw);
              chk('strict 퇴사 신청 대비 ≥4.5', rsCr, rsRaw);
              chk('strict 중간정산 요청 그대로 = tealDark 글 · teal 선', _hex(imFg) == _wantTealDark && _hex(imSide) == _wantTeal, imRaw);
            }
          }

          // ⑩ 캡처 — 누르지 않는다.
          final so = _shotOf[sid]!;
          await shot(so.$1, so.$2);
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ⑪ 성공 · 실패 공통 정리 — 화면을 내리고 남은 지연(토스트 4초 등)이 끝날 시간을 준다.
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

        // ⑫ 집계 — 읽기 CF 수 · 허용 밖 CF · Firestore 쓰기/그 밖 연산 · 예상 밖 채널 · HTTP 요청/클라이언트 생성.
        final nRp = wire.calls['callableGetMyConfirmedReassignmentProposals'] ?? 0;
        final nCfx = wire.blocked.length;
        final nFsw = wire.fsWrites.length;
        final nFso = wire.fsOther.length;
        final nUnexp = wire.unexpected.length;
        final nHttp = net.tries.length;
        final nHcl = net.clients;
        final nHarness = wire.harness.length;
        final unText = [...wire.unexpected, ...wire.blocked, ...wire.fsWrites.map((x) => 'fsw $x'), ...wire.fsOther.map((x) => 'fs $x'), ...wire.harness, ...net.tries].join(' | ');
        _out('D544 $tok att wire rp=$nRp cfx=$nCfx fsw=$nFsw fso=$nFso unexpected=$nUnexp http=$nHttp hcl=$nHcl harness=$nHarness');

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
        _out('R544 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D544 $tok att fw n=$nFw');
        _out('D544 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        chk('쓰기 · 허용 밖 CF 0 · HTTP 요청 0 · 대역 오류 0', nCfx == 0 && nFsw == 0 && nHttp == 0 && nHarness == 0, unText);
        chk('읽기 CF = 변경 제안 목록 1', nRp == 1, 'rp $nRp');
        if (!_before && !isB) chk('strict W 화면 전체 넘침 0', nOvf == 0, ovfRaw);
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
