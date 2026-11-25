// ignore_for_file: depend_on_referenced_packages
// [DU557 · PP-TYPOGRAPHY T2-b] 지원자 '내 지원' 화면(MyApplicationsScreen · DU-S071) 카드 **문맥 행 상태 문장** 글자 역할 —
//   판단 본문 16/1.5/400(의미색 그대로 · 중립 textPrimary) · KeepWordsText(낱말 사이에서만 줄바꿈) · 거절 사유 전문 · 겹친 내 다른 약속 16(판정149 ⑤).
//   초대 판단 블록(초대 머리 · 조건 · 기한 · 제안 급여 · 기존 지원 정리 · 수락 준비 줄)은 T2-c — 이 시험은 그 글의 서명이 TB = TA 임을 두 모드 정확으로 단언한다(ru).
//   before = 현재 A(my_applications_screen a567e26e · DU556 T2-a 채택판) 기록 전용 · strict = 후보(T2-b).
//   하네스 = DU556(du1_s071_typo_t2_556_test 1bdfa446 · 정규 DONE 5/5)의 읽기 경계(MyApplicationsReads) · 시계(clock) · 플랫폼 채널 전수 관찰 · HTTP 대역 ·
//     측정 도우미(DU555 r2) 그대로. 값 = 기존 fixture 만(README 값 출처 표 — DU544 · DU554 · DU556 · MA · IC · DU466 · auto_cancel · MAS).
//   측정(읽기만): 역할별 실제 TextStyle(조각 서명) · 전문 · 말줄임/줄 제한 · 낱말 안 끊김(공용 du_word_break — 피할 수 있는 것 wb · **강제 wf 를 따로 센다**) ·
//     카드 안 읽기 순서 · 순차 도달(ensureVisible) · 행동 받는 자리(화면 안 · 중심 hit · 48 — DU552 `_tapNow`) · 넘침 · framework.
//   누르는 것 0 — 서버 쓰기 버튼(취소 · 수락 · 거절 · 동의 · 서명 · 리뷰) · 카드 탭 · 뒤로가기 · 다시 시도/재조회를 누르지 않는다.
//   [DU364] find.byType(Text) 는 KeepWordsText 를 세지 않는다 — 이 시험은 `w is Text` 술어로 찾는다.
//   기본 skip — TB before/du557-tb/DU_BEFORE_OBSERVE=557 · TA after/du557-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';
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

/// 지원 요건을 갖춘 **시험용** 사용자 — 실제 신원 · 계좌 검증이 아니다(DU544 · DU547 · DU553 · DU554 와 같은 대역).
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

/// 시계 = KST 2026-11-20 12:00(화면 clock · DU544 · DU547 · DU553 · DU554 와 같다). 초대 기한 = 시계 + 23시간(DU544 — 수락 가능).
final DateTime _today = FormatHelper.toKstDate(DateTime.utc(2026, 11, 20));
DateTime _day(int d) => _today.add(Duration(days: d));
DateTime _at(DateTime day, String hhmm) => FormatHelper.kstWallClockInstant(day, hhmm)!;
final DateTime _noon = _at(_today, '12:00');
final DateTime _invited = _noon.subtract(const Duration(hours: 1));
final DateTime _deadline = _noon.add(const Duration(hours: 23));

final DateTime _oct = FormatHelper.toKstDate(DateTime.utc(2026, 10, 20)); // DU544 DONE 값(지난달 · 리뷰 기간 밖)

const _bizQa = 'QA 사업장';
const _bizLong = '서울특별시 강남구 테헤란로 물류센터 제2창고'; // my_applications_same_target_test MAS-R 값(DU556 LONGBIZ)
const _toQa = 'QA 공고';
const _rejectMsg = '이번에는 경력 조건이 맞지 않아 함께하지 못하게 되었어요'; // du1_s041_my_app_section_466_test _rejectMsg 값

/// 지원 한 건(DU556 `_mk` + 기존 fixture 의 종료 사유 칸만 더함 — 값은 기존 fixture 것).
ApplicationModel _mk(String status, DateTime workDate,
        {String id = 'a1',
        String biz = _bizQa,
        String start = '20:00',
        String end = '22:00',
        DateTime? invitedAt,
        InviteAcceptReadiness r = InviteAcceptReadiness.ready,
        String? offerKind,
        String? sourceWorkType,
        String? cancelReason,
        String? rejectMessage,
        String? conflictingBusiness,
        String? conflictingTime}) =>
    ApplicationModel(
      id: id, toId: 'to1', slotId: 'slot1', wdId: 'wd-1', uid: _kUid, businessId: 'biz1', businessName: biz,
      toTitle: _toQa, status: status, selectedWorkType: 'QA 분류', startTime: start, endTime: end, wage: 13000,
      workDate: workDate, appliedAt: _today.subtract(const Duration(days: 7)), invitedAt: invitedAt,
      inviteExpiresAt: invitedAt == null ? null : _deadline,
      inviteAcceptDeadline: invitedAt == null ? null : _deadline,
      workInstanceCapacityState: InviteCapacityState.available, inviteAcceptReadiness: r, publicIntakeClosed: false,
      offerKind: offerKind, sourceWorkType: sourceWorkType, cancelReason: cancelReason, rejectMessage: rejectMessage,
      conflictingBusiness: conflictingBusiness, conflictingTime: conflictingTime,
      documentAccessConsentGiven: true, documentAccessConsentVersion: DocumentAccessConsent.version,
    );

/// 사흘 뒤 20:00 근무 초대(DU544 `_inv`).
ApplicationModel _inv(InviteAcceptReadiness r, {String? offerKind, String? sourceWorkType}) =>
    _mk(AppStatus.invited, _day(3), invitedAt: _invited, r: r, offerKind: offerKind, sourceWorkType: sourceWorkType);

/// 근태 한 건(DU544 `_att` + 지원서 id · 근태 상태 — MA `_att` 의 status 값).
AttendanceModel _att(String appId, DateTime day, {String? inAt, String? outAt, String status = AttendanceModel.statusPresent, String wage = 'pending'}) =>
    AttendanceModel(
      id: 'att-$appId', applicationId: appId, userId: _kUid, businessId: 'biz1', businessName: _bizQa, workDate: day, workType: 'QA 분류',
      checkInAt: inAt == null ? null : _at(day, inAt), checkOutAt: outAt == null ? null : _at(day, outAt), status: status,
      wageStatus: wage, createdAt: day,
    );

TOModel _to() => TOModel(
      id: 'to1', businessId: 'biz1', businessName: _bizQa, type: 'flex', title: _toQa, creatorUID: 'admin1',
      status: TOStatus.closed, deadlineType: 'NONE', hoursBeforeStart: 0, workDetails: const [], totalRequired: 3,
      totalConfirmed: 0, totalPending: 1, isPublished: true, publishMode: 'immediate',
      createdAt: _today.subtract(const Duration(days: 10)), statusUpdatedAt: _today.subtract(const Duration(days: 10)),
    );

typedef _Case = ({String id, List<ApplicationModel> apps, List<AttendanceModel> atts, bool ctFail});

/// 사례 한 줄 — 상태 이름은 이름 인자 `id:`(preflight v25 가 목록에서 fixture 값 집합을 읽는다). ctFail = 계약 읽기 실패(DU544 CFAIL 과 같은 꼴).
_Case _c({required String id, required List<ApplicationModel> apps, List<AttendanceModel> atts = const [], bool ctFail = false}) =>
    (id: id, apps: apps, atts: atts, ctFail: ctFail);

/// 사례마다 새로 — 목록 읽기 · 근태 월 읽기 호출 수.
class _Count {
  var list = 0;
  var att = 0;
}

/// 목록 읽기 경계 — 실패 주입은 계약 읽기(ctFail · DU544 · DU556 CFAIL)뿐. 목록 · 근태는 성공 응답만(DU544 꼴 · 월과 무관하게 같은 목록). 쓰기 경로 대역 없음.
MyApplicationsReads _reads(_Case c, _Count n) => MyApplicationsReads(
      myApplicationsPaged: ({required String uid, required int pageSize, String? startAfterDocId}) async {
        n.list++;
        if (startAfterDocId != null) return {'items': const <ApplicationModel>[], 'lastDocId': null, 'hasMore': false};
        return {'items': c.apps, 'lastDocId': null, 'hasMore': false};
      },
      toOrFailure: (id) async => (to: _to(), failed: false),
      contractsByWorker: (uid) async {
        if (c.ctFail) throw Exception('du557 local contract failure');
        return const <EmploymentContractModel>[];
      },
      autoExpirePending: (uid) async {},
      monthlyAttendances: ({required String userId, required int year, required int month}) async {
        n.att++;
        return c.atts;
      },
      reviewById: (key) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
    );

final _cases = <_Case>[
  _c(id: 'CPREP', apps: [_mk(AppStatus.contractPending, _day(3))]),
  _c(id: 'CFAIL', apps: [_mk(AppStatus.contractPending, _day(3))], ctFail: true),
  _c(id: 'TODAY', apps: [_mk(AppStatus.confirmed, _today), _mk(AppStatus.confirmed, _today, id: 'a2', start: '10:00', end: '11:00')]),
  _c(id: 'WORK', apps: [_mk(AppStatus.confirmed, _today, start: '10:00', end: '18:00'), _mk(AppStatus.contractPending, _today, id: 'a2', start: '10:00', end: '18:00')],
      atts: [_att('a1', _today, inAt: '10:00'), _att('a2', _today, inAt: '10:00')]),
  _c(id: 'SETTLE', apps: [_mk(AppStatus.confirmed, _today, start: '08:00', end: '11:00')], atts: [_att('a1', _today, inAt: '08:00', outAt: '11:00')]),
  _c(id: 'DONE', apps: [_mk(AppStatus.confirmed, _oct, start: '10:00', end: '18:00'), _mk(AppStatus.contractPending, _oct, id: 'a2', start: '10:00', end: '18:00')],
      atts: [_att('a1', _oct, inAt: '10:00', outAt: '18:00', wage: 'confirmed'), _att('a2', _oct, inAt: '10:00', outAt: '18:00', wage: 'confirmed')]),
  _c(id: 'REVIEW', apps: [_mk(AppStatus.confirmed, _day(-1))], atts: [_att('a1', _day(-1), inAt: '20:00', outAt: '22:00', wage: 'confirmed')]),
  _c(id: 'NOSHOW', apps: [_mk(AppStatus.confirmed, _day(-1)), _mk(AppStatus.contractPending, _day(-1), id: 'a2')],
      atts: [_att('a1', _day(-1), status: AttendanceModel.statusNoShow, wage: 'confirmed'), _att('a2', _day(-1), status: AttendanceModel.statusNoShow, wage: 'confirmed')]),
  _c(id: 'ABSENT', apps: [_mk(AppStatus.confirmed, _day(-1)), _mk(AppStatus.contractPending, _day(-1), id: 'a2')],
      atts: [_att('a1', _day(-1), status: AttendanceModel.statusAbsent, wage: 'confirmed'), _att('a2', _day(-1), status: AttendanceModel.statusAbsent, wage: 'confirmed')]),
  _c(id: 'NOREC', apps: [_mk(AppStatus.confirmed, _day(-1)), _mk(AppStatus.confirmed, _day(-1), id: 'a2')], atts: [_att('a1', _day(-1))]),
  _c(id: 'LONGBIZ', apps: [_mk(AppStatus.confirmed, _day(3), biz: _bizLong, start: '09:00', end: '18:00')]),
  _c(id: 'REJECT', apps: [_mk(AppStatus.rejected, _day(3), invitedAt: _invited), _mk(AppStatus.rejected, _day(3), id: 'a2', rejectMessage: _rejectMsg)]),
  _c(id: 'CONFLICT', apps: [
    _mk(AppStatus.autoCanceled, _day(3), cancelReason: 'SCHEDULE_CONFLICT', conflictingBusiness: '다른 사업장', conflictingTime: '09:00~18:00')
  ]),
  _c(id: 'EXPIRED', apps: [_mk(AppStatus.expired, _day(3), invitedAt: _invited)]),
  _c(id: 'INVITE', apps: [_inv(InviteAcceptReadiness.ready)]),
  _c(id: 'RECHECK', apps: [_inv(InviteAcceptReadiness.unavailable)]),
  _c(id: 'OFFER', apps: [_inv(InviteAcceptReadiness.ready, offerKind: 'ALTERNATIVE_WORK', sourceWorkType: '상차')]),
];

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';

/// 첫 화면이 부르는 읽기 CF(화면 소스 그대로 — initState 의 변경 제안 목록) — 이 밖의 CF 이름은 차단하고 센다.
const _readFns = <String>{'callableGetMyConfirmedReassignmentProposals'};

/// Firestore 쓰기 연산 — 하나라도 오면 fsw 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// [DU526 · DU534 · DU536–554 와 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널(UserProvider → AuthService).
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du557.fake.auth.';
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
///   기반 채널은 원래 경로, 나머지는 이름을 기록하고 응답 null. 예외를 삼키지 않는다 — 수는 줄로 남긴다(DU554 그대로).
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
        return codec.encodeMessage(<Object?>['not-found', 'du557-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      _hit(fn);
      return codec.encodeMessage(<Object?>[<String, Object?>{'proposals': const <Object?>[]}]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['internal', 'du557-harness', null]);
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
      return codec.encodeMessage(<Object?>['du557-blocked', '$op 차단', null]);
    } catch (e) {
      harness.add('fs $op $e');
      return null;
    }
  }
}

/// 외부 HTTP 차단 — 클라이언트 객체 생성은 허용하고 센다(ContractService 생성자 · 요청 0), 실제 요청은 기록하고 실패(DU554 그대로).
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
    throw const SocketException('DU557 관측 — 외부 HTTP 차단');
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

/// [a] 가 [b] **안**에 있는가(겹침이 아니라 포함 · 0.5px 허용 — DU508 r3 · DU555 와 같다).
bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

/// 시각 오류 수집 — 넘침은 원문 + 위치, 그 밖 framework 오류는 원문(DU554 그대로).
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

/// 요소 하나가 끌기 없이 보이고 눌리는가 — 창 상자 ∩ 화면(∩ 가까운 Scrollable 이 있으면 그 칸) 안 + 중심 hit(DU537 · DU538 r2 · DU540 · DU543 r3 · DU548 · DU551 · DU552 · DU555 `_tapNow` 와 같은 식).
({bool vis, bool hit, bool min48, Rect r}) _tapNow(WidgetTester t, Finder f, Finder dlg, Rect screen) {
  final boxF = find.descendant(of: dlg, matching: find.byType(Dialog), skipOffstage: true);
  var area = boxF.evaluate().isEmpty ? screen : t.getRect(boxF.first).intersect(screen);
  final scF = find.ancestor(of: f, matching: find.byType(Scrollable));
  final nSc = scF.evaluate().length;
  if (nSc > 0) area = area.intersect(t.getRect(scF.first));
  final r = t.getRect(f);
  final vis = _inside(r, area);
  final hit = t.hitTestOnBinding(r.center).path.any((x) => identical(x.target, t.renderObject(f)));
  final min48 = r.width >= 48 - 0.01 && r.height >= 48 - 0.01;
  return (vis: vis, hit: hit, min48: min48, r: r);
}

// ── 글자 역할 측정(읽기만 · DU555 r2 도우미 그대로) ──

/// 화면 안 글(Text 위젯 — KeepWordsText 같은 하위 형 포함) — 의미 이름이 [s] 이거나, 의미 이름이 없으면 보이는 글(표시 제어 문자 제거)이 [s] 인 것. 화면 밖 포함.
///   find.text 는 EditableText 도 센다 — Text 위젯만 본다.
Finder _textOf(Finder home, String s) => find.descendant(of: home, skipOffstage: false,
    matching: find.byWidgetPredicate(
        (w) => w is Text && (w.semanticsLabel == s || (w.semanticsLabel == null && visibleText(w.data ?? '') == s)),
        skipOffstage: false));

/// [f] 의 Text 위젯마다 그 안 RichText 문단 — Text 하나에 문단이 정확히 1 이 아니면 그 Text 는 뺀다(개수는 raw 에 남는다).
List<RenderParagraph> _parasOf(Finder f) {
  final out = <RenderParagraph>[];
  for (final e in f.evaluate()) {
    final rps = <RenderParagraph>[];
    void visit(Element x) {
      final ro = x.renderObject;
      if (x.widget is RichText && ro is RenderParagraph) rps.add(ro);
      x.visitChildren(visit);
    }
    e.visitChildren(visit);
    if (rps.length == 1) out.add(rps.first);
  }
  return out;
}

/// 글 조각별 실제 스타일 — 조상 스타일부터 차례로 merge. 빈 조각은 뺀다.
List<(String, TextStyle)> _spansOf(RenderParagraph rp) {
  final out = <(String, TextStyle)>[];
  void walk(InlineSpan s, TextStyle eff) {
    final e = s.style == null ? eff : eff.merge(s.style);
    if (s is TextSpan) {
      final tx = s.text;
      if (tx != null && tx.isNotEmpty) out.add((tx, e));
      for (final ch in s.children ?? const <InlineSpan>[]) {
        walk(ch, e);
      }
    }
  }
  walk(rp.text, const TextStyle());
  return out;
}

/// 스타일 서명 '크기/줄 높이/굵기/자간/색' — 크기 · 자간 소수 1 · 줄 높이 소수 2 · 굵기 값 · ARGB 8자리(없으면 n).
String _sig(TextStyle s) {
  String n(double? x, int d) => x == null ? 'n' : x.toStringAsFixed(d);
  final c = s.color;
  return [
    n(s.fontSize, 1),
    n(s.height, 2),
    s.fontWeight == null ? 'n' : s.fontWeight!.value.toString(),
    n(s.letterSpacing, 1),
    c == null ? 'n' : c.toARGB32().toRadixString(16).padLeft(8, '0'),
  ].join('/');
}

/// 칸 하나의 서명 집합 — 글 조각 서명을 모아 정렬 · '|'. 없으면 '-'.
String _sigsOf(List<(RenderParagraph, String)> ps) {
  final out = <String>{};
  for (final (p, _) in ps) {
    for (final (_, st) in _spansOf(p)) {
      out.add(_sig(st));
    }
  }
  final l = out.toList()..sort();
  return l.isEmpty ? '-' : l.join('|');
}

/// 문단의 줄 수 — 전체 선택 상자의 윗변이 1px 넘게 달라지는 횟수.
int _linesOf(RenderParagraph rp) {
  final n = rp.text.toPlainText().length;
  if (n == 0) return 0;
  final tops = <double>[];
  for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: n))) {
    if (tops.every((x) => (x - b.top).abs() > 1)) tops.add(b.top);
  }
  return tops.length;
}

typedef _Fit = ({int ex, int cut, int wb, int full, int lines});

/// 문단 하나 — 줄 제한 넘음 · 줄 제한/말줄임 설정 · 피할 수 있는 낱말 안 끊김(공용 판정기) · 전문 불일치 · 줄 수.
_Fit _fitOf(RenderParagraph rp, String show) => (
      ex: rp.didExceedMaxLines ? 1 : 0,
      cut: rp.maxLines != null || rp.overflow == TextOverflow.ellipsis ? 1 : 0,
      wb: wordBreaks(rp).where((x) => !x.forced).length,
      full: visibleText(rp.text.toPlainText()) == show ? 0 : 1,
      lines: _linesOf(rp),
    );

Rect _rectOf(RenderParagraph rp) => MatrixUtils.transformRect(rp.getTransformTo(null), Offset.zero & rp.size);

/// [b] 가 [a] 다음 읽기 자리인가 — 같은 줄 오른쪽(세로로 겹치고 왼쪽 ≥ a 오른쪽) 또는 아래(위 ≥ a 아래).
bool _after(Rect a, Rect b) => (b.left >= a.right - 0.5 && b.top < a.bottom && b.bottom > a.top) || b.top >= a.bottom - 0.5;

/// 문단 하나의 **강제** 낱말 안 끊김 수(공용 판정기 forced — 낱말 하나가 문단 폭보다 길어 불가피한 분절). `_fitOf` 의 wb 는 forced 를 세지 않는다(판정149 :49).
int _wfOf(RenderParagraph rp) => wordBreaks(rp).where((x) => x.forced).length;

/// 이 셀이 바꾼 문맥 행 문장 원문(후보 · base 소스 그대로 — mkcell 이 확인한다).
const _kPrep = '관리자가 계약서를 준비 중이에요';
const _kCtFail = '계약 정보를 불러오지 못했어요. 다시 시도해주세요';
const _kToday = '오늘 근무 예정이에요';
const _kMissed = '근무 시간이 지났어요 · 출근 기록이 없어요';
const _kWorking = '근무 중이에요';
const _kSettle = '근무가 끝났어요 · 정산 중';
const _kDone = '근무 완료';
const _kReview = '리뷰를 작성해 주세요';
const _kNoShow = '노쇼 처리됐어요';
const _kAbsent = '결근 처리됐어요';
const _kNoCheckIn = '출근 기록이 없어요';
const _kNoRecord = '근무 기록이 없어요';
const _kDeclined = '초대를 거절했어요';
const _kExpired = '초대 유효기간이 종료되었어요';

/// 카드 글 칸 — 상태의 지원서 목록에서 화면과 같은 식으로 만든다.
///   nm 사업장 · bg 상태 배지 · tt 공고 제목 · dt 일시 · wg 급여 · ct 단추 글(T2-a) · cx 이번에 바뀐 문맥 행 문장(T2-b) · cu 초대 블록 글(T2-c · 불변 단언).
Map<String, List<String>> _slotsOf(_Case c) {
  final apps = c.apps;
  String date(ApplicationModel a) => '${FormatHelper.formatDateKorean(a.workDate)} · ${a.startTime}~${a.endTime}';
  String wage(ApplicationModel a) => a.wageTypeLabel.isNotEmpty ? '${a.wageTypeLabel} ${a.formattedWage}' : a.formattedWage;
  String dl(ApplicationModel a) => '~${FormatHelper.formatKstMonthDayTime(a.effectiveInviteDeadline!)} 만료';
  final head = <String, List<String>>{
    'nm': [for (final a in apps) a.businessName],
    'tt': List<String>.filled(apps.length, _toQa),
    'dt': [for (final a in apps) date(a)],
    'wg': [for (final a in apps) wage(a)],
  };
  final a0 = apps.first;
  switch (c.id) {
    case 'CPREP':
      return {...head, 'bg': ['계약 진행 중'], 'cx': [_kPrep], 'ct': [], 'cu': []};
    case 'CFAIL':
      return {...head, 'bg': ['계약 진행 중'], 'cx': [_kCtFail], 'ct': [], 'cu': []};
    case 'TODAY':
      return {...head, 'bg': ['확정'], 'cx': [_kToday, _kMissed], 'ct': [], 'cu': []};
    case 'WORK':
      return {...head, 'bg': ['확정', '계약 진행 중'], 'cx': [_kWorking], 'ct': [], 'cu': []};
    case 'SETTLE':
      return {...head, 'bg': ['확정'], 'cx': [_kSettle], 'ct': [], 'cu': []};
    case 'DONE':
      return {...head, 'bg': ['확정', '계약 진행 중'], 'cx': [_kDone], 'ct': [], 'cu': []};
    case 'REVIEW':
      return {...head, 'bg': ['확정'], 'cx': [_kReview], 'ct': [], 'cu': []};
    case 'NOSHOW':
      return {...head, 'bg': ['노쇼'], 'cx': [_kNoShow], 'ct': [], 'cu': []};
    case 'ABSENT':
      return {...head, 'bg': ['결근'], 'cx': [_kAbsent], 'ct': [], 'cu': []};
    case 'NOREC':
      return {...head, 'bg': ['확정'], 'cx': [_kNoCheckIn, _kNoRecord], 'ct': [], 'cu': []};
    case 'LONGBIZ':
      return {...head, 'bg': ['확정'], 'cx': ['${FormatHelper.formatDateKorean(a0.workDate)} 출근 예정이에요'], 'ct': [], 'cu': []};
    case 'REJECT':
      return {...head, 'bg': ['초대 거절', '거절'], 'cx': [_kDeclined, apps[1].rejectMessage!], 'ct': [], 'cu': []};
    case 'CONFLICT':
      return {...head, 'bg': ['자동 취소'], 'cx': [a0.workerEndReasonSentence, a0.scheduleConflictContext!], 'ct': [], 'cu': []};
    case 'EXPIRED':
      return {...head, 'bg': ['초대 종료'], 'cx': [_kExpired], 'ct': [], 'cu': []};
    case 'INVITE':
      return {...head, 'bg': ['근무 초대'], 'cx': [], 'ct': ['수락하기', '거절'], 'cu': ['근무 초대가 도착했어요', dl(a0)]};
    case 'RECHECK':
      return {...head, 'bg': ['근무 초대'], 'cx': [], 'ct': ['다시 확인', '수락하기', '거절'],
        'cu': ['근무 초대가 도착했어요', dl(a0), '수락할 수 있는지 확인하지 못했어요. 다시 확인해 주세요.']};
    case 'OFFER':
      return {...head, 'bg': ['근무 초대'], 'cx': [], 'ct': ['제안 조건으로 수락', '거절'],
        'cu': ['다른 업무 제안이 도착했어요', '수락하면 기존 지원(상차)은 자동으로 정리돼요', dl(a0)]};
    default:
      return const {};
  }
}

/// 상태별 행동 받는 자리(보이는 글 · 같은 글의 몇 번째) — 그 글의 가장 가까운 GestureDetector. 비활성 '수락하기'는 받는 자리가 아니라 뺀다.
List<(String, int)> _ctasOf(String id) => switch (id) {
      'CFAIL' => [(_kCtFail, 0)],
      'REVIEW' => [(_kReview, 0)],
      'INVITE' => [('수락하기', 0), ('거절', 0)],
      'RECHECK' => [('다시 확인', 0), ('거절', 0)],
      'OFFER' => [('제안 조건으로 수락', 0), ('거절', 0)],
      _ => const <(String, int)>[],
    };

/// 상태별 캡처(이름 · 상태 설명) — 모든 상태 같은 두 장.
const _shotsOf = <String, List<(String, String)>>{
  'CPREP': [('1top', 'card-origin'), ('2end', 'card-end')], 'CFAIL': [('1top', 'card-origin'), ('2end', 'card-end')],
  'TODAY': [('1top', 'card-origin'), ('2end', 'card-end')], 'WORK': [('1top', 'card-origin'), ('2end', 'card-end')],
  'SETTLE': [('1top', 'card-origin'), ('2end', 'card-end')], 'DONE': [('1top', 'card-origin'), ('2end', 'card-end')],
  'REVIEW': [('1top', 'card-origin'), ('2end', 'card-end')], 'NOSHOW': [('1top', 'card-origin'), ('2end', 'card-end')],
  'ABSENT': [('1top', 'card-origin'), ('2end', 'card-end')], 'NOREC': [('1top', 'card-origin'), ('2end', 'card-end')],
  'LONGBIZ': [('1top', 'card-origin'), ('2end', 'card-end')], 'REJECT': [('1top', 'card-origin'), ('2end', 'card-end')],
  'CONFLICT': [('1top', 'card-origin'), ('2end', 'card-end')], 'EXPIRED': [('1top', 'card-origin'), ('2end', 'card-end')],
  'INVITE': [('1top', 'card-origin'), ('2end', 'card-end')], 'RECHECK': [('1top', 'card-origin'), ('2end', 'card-end')],
  'OFFER': [('1top', 'card-origin'), ('2end', 'card-end')],
};

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '557';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du557-tb' && _env['DU_BEFORE_OBSERVE'] == '557') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du557-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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
    _out('R557 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S957TB-${v.id}-${c.id} 내 지원 카드 문맥 행 글자 역할 T2-b — 역할 값 · 전문 · 말줄임 · 강제 포함 음절 끊김 · 읽기 순서 · 순차 도달 · 행동 48 · 초대 블록 불변', (t) async {
        final tok = 'S957TB-${v.id}-${c.id}';
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
        _out('D557 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final user = _P();
        final count = _Count();
        final sid = c.id;
        final shots = _shotsOf[sid]!;
        Object? failure;
        StackTrace? failureSt;
        var nShot = 0;
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
          // 이 화면은 멈추지 않는 애니메이션이 있어 pumpAndSettle 대신 시간 전진(DU544 · DU547 · DU553 · DU554 · DU556 과 같다).
          for (var i = 0; i < 30; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          final home = find.byType(MyApplicationsScreen);
          final nScr = home.evaluate().length;
          need('화면 1', nScr == 1, '개수 $nScr');

          Future<void> shot(int i) async {
            final (id, state) = shots[i];
            _out('D557 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            nShot++;
          }

          // ① 역할 글 — 칸마다 글을 찾아 문단을 모은다. 선언한 글은 모두 있어야 한다(없으면 멈춘다).
          final slots = _slotsOf(c);
          final found = <String, List<(RenderParagraph, String)>>{};
          for (final e in slots.entries) {
            final ps = <(RenderParagraph, String)>[];
            for (final q in e.value.toSet()) {
              final got = _parasOf(_textOf(home, q));
              need('역할 글 있음 ${e.key}', got.isNotEmpty, q);
              for (final p in got) {
                ps.add((p, q));
              }
            }
            found[e.key] = ps;
          }
          List<(RenderParagraph, String)> at(String k) => found[k] ?? const [];
          final fam = at('nm').isEmpty ? '-' : (at('nm').first.$1.text.style?.fontFamily ?? 'n');
          _out('D557 $tok att role nm=${_sigsOf(at('nm'))} bg=${_sigsOf(at('bg'))} tt=${_sigsOf(at('tt'))} dt=${_sigsOf(at('dt'))} wg=${_sigsOf(at('wg'))} cx=${_sigsOf(at('cx'))} ct=${_sigsOf(at('ct'))} fam=$fam');
          _out('D557 $tok att ru cu=${_sigsOf(at('cu'))}');

          // ② 전문 · 말줄임 · 줄 제한 · 낱말 안 끊김(피할 수 있는 것 wb · 강제 wf) — 바뀐 문맥 행(fit) / 카드 머리 · 단추(fith · T2-a 유지) / 초대 블록(fitu · T2-c 잔여 기록).
          String fitLine(List<String> keys, List<String> badL, List<String> slotRaw, List<int> acc) {
            for (final k in keys) {
              final ls = <int>[];
              for (final (p, show) in at(k)) {
                final f = _fitOf(p, show);
                final wf = _wfOf(p);
                acc[0]++;
                acc[1] += f.ex;
                acc[2] += f.cut;
                acc[3] += f.wb;
                acc[4] += wf;
                acc[5] += f.full;
                ls.add(f.lines);
                if (f.ex + f.cut + f.wb + wf + f.full > 0) {
                  badL.add('$k ex${f.ex} cut${f.cut} wb${f.wb} wf$wf full${f.full} "${visibleText(p.text.toPlainText())}" ${wordBreaks(p).map((x) => x.toString()).join(';')}');
                }
              }
              slotRaw.add('$k:${at(k).length}:${ls.join('.')}');
            }
            return 'slots ${slotRaw.join(' ')} bad ${badL.join(' | ')}';
          }
          final fa = [0, 0, 0, 0, 0, 0];
          final fitRaw = fitLine(const ['cx'], <String>[], <String>[], fa);
          _out('D557 $tok att fit n=${fa[0]} ex=${fa[1]} cut=${fa[2]} wb=${fa[3]} wf=${fa[4]} full=${fa[5]}');
          final fh = [0, 0, 0, 0, 0, 0];
          final fithRaw = fitLine(const ['nm', 'bg', 'tt', 'dt', 'wg', 'ct'], <String>[], <String>[], fh);
          _out('D557 $tok att fith n=${fh[0]} ex=${fh[1]} cut=${fh[2]} wb=${fh[3]} wf=${fh[4]} full=${fh[5]}');
          final fu = [0, 0, 0, 0, 0, 0];
          final fituRaw = fitLine(const ['cu'], <String>[], <String>[], fu);
          _out('D557 $tok att fitu n=${fu[0]} ex=${fu[1]} cut=${fu[2]} wb=${fu[3]} wf=${fu[4]} full=${fu[5]}');
          raw = '$raw fit $fitRaw fith $fithRaw fitu $fituRaw';
          if (!_before) {
            chk('strict 바뀐 문맥 행 문장 전문 · 줄 제한/말줄임 0 · 낱말 안 끊김 0(피할 수 있는 것 · 강제 모두)',
                fa[1] == 0 && fa[2] == 0 && fa[3] == 0 && fa[4] == 0 && fa[5] == 0, fitRaw);
          }
          if (!_before) chk('strict 카드 머리 · 단추 전문 · 줄 제한/말줄임 0 · 피할 수 있는 낱말 안 끊김 0(T2-a 유지)', fh[1] == 0 && fh[2] == 0 && fh[3] == 0 && fh[5] == 0, fithRaw);

          // ③ 카드 안 읽기 순서 — 칸마다 가장 위 글: 사업장 → 배지(같은 줄 오른쪽 또는 아래) → 제목 → 일시 → 급여 → 문맥 행 첫 문장 → 첫 단추.
          Rect? top(String k) {
            final rs = [for (final (p, _) in at(k)) _rectOf(p)]..sort((a, b) => a.top.compareTo(b.top));
            return rs.isEmpty ? null : rs.first;
          }
          final ctxTop = [top('cx'), top('cu')].whereType<Rect>().toList()..sort((a, b) => a.top.compareTo(b.top));
          final seqR = <(String, Rect)>[
            for (final k in const ['nm', 'bg', 'tt', 'dt', 'wg']) if (top(k) != null) (k, top(k)!),
            if (ctxTop.isNotEmpty) ('ctx', ctxTop.first),
            if (top('ct') != null) ('ct', top('ct')!),
          ];
          var ord = true;
          for (var i = 1; i < seqR.length; i++) {
            if (!_after(seqR[i - 1].$2, seqR[i].$2)) ord = false;
          }
          final ordRaw = [for (final (k, r) in seqR) '$k ${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)}-${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}'].join(' ');
          _out('D557 $tok att order ord=$ord');
          raw = '$raw order $ordRaw';
          if (!_before) chk('strict 카드 안 읽기 순서', ord, ordRaw);
          await shot(0);

          // ④ 순차 도달 — 같은 순서의 칸 글을 하나씩 ensureVisible(대상마다 한 번 · 4 × 50ms) 해서 화면 ∩ 목록 칸 안에 들어오는가(KeepWordsText 는 Text 하위라 그대로 찾는다).
          final seqQ = <String>[
            for (final k in const ['nm', 'bg', 'tt', 'dt', 'wg']) if ((slots[k] ?? const <String>[]).isNotEmpty) slots[k]!.first,
            ...[...(slots['cx'] ?? const <String>[]), ...(slots['cu'] ?? const <String>[])].take(1),
            ...(slots['ct'] ?? const <String>[]).take(1),
          ];
          var sVis = 0;
          final seqRaw = <String>[];
          for (final q in seqQ) {
            final f = _textOf(home, q).first;
            await t.ensureVisible(f);
            for (var k = 0; k < 4; k++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final p = _tapNow(t, f, home, screen);
            if (p.vis) sVis++;
            seqRaw.add(p.vis.toString());
          }
          final sAll = sVis == seqQ.length;
          _out('D557 $tok att seq n=${seqQ.length} all=$sAll');
          raw = '$raw seq ${seqRaw.join(',')}';
          if (!_before) chk('strict 카드 글 순차 도달(전부 화면 · 목록 칸 안)', sAll, seqRaw.join(','));

          // ⑤ 행동 받는 자리 — ensureVisible 로 화면에 넣고 화면 안 · 중심 hit · 48 이상. 누르지 않는다.
          final ctas = _ctasOf(sid);
          var cVis = 0, cHit = 0, c48 = 0;
          final ctaRaw = <String>[];
          for (final (lab, i) in ctas) {
            final labs = _textOf(home, lab);
            final nLab = labs.evaluate().length;
            need('행동 글 $lab #$i', nLab > i, '개수 $nLab');
            final rf = find.ancestor(of: labs.at(i), matching: find.byType(GestureDetector)).first;
            await t.ensureVisible(rf);
            for (var k = 0; k < 4; k++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final p = _tapNow(t, rf, home, screen);
            if (p.vis) cVis++;
            if (p.hit) cHit++;
            if (p.min48) c48++;
            ctaRaw.add('$lab#$i ${p.r.width.toStringAsFixed(1)}x${p.r.height.toStringAsFixed(1)} ${p.vis}/${p.hit}/${p.min48}');
          }
          _out('D557 $tok att cta n=${ctas.length} vis=$cVis hit=$cHit m48=$c48');
          raw = '$raw cta ${ctaRaw.join(' | ')}';
          if (!_before) chk('strict 행동 받는 자리 화면 안 · 중심 hit · 48 이상(전부)', cVis == ctas.length && cHit == ctas.length && c48 == ctas.length, ctaRaw.join(' | '));
          await shot(1);
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ⑥ 성공 · 실패 공통 정리 — 화면을 내리고 남은 지연(토스트 4초 등)이 끝날 시간을 준다.
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

        // ⑦ 집계 — 읽기 CF 수 · 목록 읽기 수 · 근태 월 읽기 수 · 허용 밖 CF · Firestore 쓰기/그 밖 연산 · 예상 밖 채널 · HTTP 요청/클라이언트 생성.
        final nRp = wire.calls['callableGetMyConfirmedReassignmentProposals'] ?? 0;
        final nLr = count.list;
        final nLa = count.att;
        final nCfx = wire.blocked.length;
        final nFsw = wire.fsWrites.length;
        final nFso = wire.fsOther.length;
        final nUnexp = wire.unexpected.length;
        final nHttp = net.tries.length;
        final nHcl = net.clients;
        final nHarness = wire.harness.length;
        final unText = [...wire.unexpected, ...wire.blocked, ...wire.fsWrites.map((x) => 'fsw $x'), ...wire.fsOther.map((x) => 'fs $x'), ...wire.harness, ...net.tries].join(' | ');
        _out('D557 $tok att wire rp=$nRp lr=$nLr la=$nLa cfx=$nCfx fsw=$nFsw fso=$nFso unexpected=$nUnexp http=$nHttp hcl=$nHcl harness=$nHarness');

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
        _out('R557 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D557 $tok att fw n=$nFw');
        _out('D557 $tok done state=${c.id} mode=$mode captures=$nShot overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        chk('쓰기 · 허용 밖 CF 0 · HTTP 요청 0 · 대역 오류 0', nCfx == 0 && nFsw == 0 && nHttp == 0 && nHarness == 0, unText);
        chk('읽기 CF = 변경 제안 목록 1', nRp == 1, 'rp $nRp');
        // 목록 읽기 수 — 첫 조회 1(누르는 것 0 · 스크롤 자동 다음 페이지 0 — hasMore 거짓).
        chk('목록 읽기 수 = 1(두 모드)', nLr == 1, 'lr $nLr');
        if (!_before) chk('strict 화면 전체 넘침 0(W · B · N)', nOvf == 0, ovfRaw);
        if (!_before) chk('strict 미처리 framework 예외 0', nFw == 0, fwRaw);
        chk('캡처 수 = 선언', nShot == shots.length, 'shots $nShot want ${shots.length}');
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
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0), (id: 'N', w: 320.0, h: 640.0, s: 1.0)];
