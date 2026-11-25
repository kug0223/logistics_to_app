// ignore_for_file: depend_on_referenced_packages
// [DU610b · 표시 셀 · 파일 단위 장부] 내 지원(MyApplicationsScreen · DU-S071) 미반영 결정 5행 — 색 · 글자 역할 · 줄 높이 · 문장만.
//   장부 012 '계약 진행 중'·'근무 초대' 배지 infoBg/infoDark → brandSurface/brand(판정139 :40) · 013 명시 결근 결과 배지 + 문장 두 곳 → error 짝(판정139 :44) ·
//   063 읽기 실패 · 이전 자료 · 목록 끝 안내 16 · '다시 시도' 16(판정149 :47) · 064 필터 칩 조작 16 · 700/400 · 배율만큼 줄 높이(판정149 :46) ·
//   065 시작일이 지난 장기 근무 '출근 예정' → 시작일 정보(판정139 :65 544-10).
//   그리는 것: 내 지원 목록 9 상태 — CPEND(계약 진행 중 · 칩) · INVITE(근무 초대) · ABS(확정 지난 근무 결근) · CPABS(계약 진행 중 지난 근무 결근) ·
//     LONG(장기 · 시작일 지남) · LONGF(장기 · 시작일 앞날) · ERR(첫 목록 읽기 실패) · MORE(다음 페이지 실패 · 목록 끝) · STALE(다시 읽기 실패 · 이전 자료).
//   before = 지금 A(my_applications_screen 30ab68c4) 기록 · strict = 후보(prep/mk_cand.py) 단언(lgate lines).
//   측정 블록 = DU575 시험(5cd431b1 · 정규 1회 DONE 5/5)의 max 판 _fullShown · _midBreaks · _area · _seeText · _btnLine · 색 도우미 · _fills 그대로(판정169a §5) ·
//     하네스 = 같은 DU575 내 지원 하네스(시험용 사용자 · 고정 시계 · 목록 읽기 경계 · 채널 관찰) — 목록 읽기만 사례별 n 번째 실패(DU553 · DU554 와 같은 꼴).
//   누르는 것: MORE 두 모드 '진행중 0' 칩(다음 페이지 읽기 — DU553 MORE 와 같은 길) · STALE 두 모드 RefreshIndicator.show()(DU554 STALE 과 같은 길).
//     '다시 시도' · 카드 단추는 누르지 않는다. 쓰기 0 · 허용 밖 CF 0 · HTTP 요청 0. 기본 skip — TB before/du610bma-tb/DU_BEFORE_OBSERVE=610 · TA after/du610bma-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show BoxHeightStyle;

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
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';

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

const _bizQa = 'QA 사업장';
const _toQa = 'QA 공고';

/// [DU610b] 단기 지원 하나 — 근무 10:00–11:00(지난 날이면 끝난 근무) · 값 꼴 = DU575 _srcApp(상태 · 날짜 · 시각만 인자).
ApplicationModel _shortApp(String id, String status, DateTime day) => ApplicationModel(
      id: id, toId: 'to1', slotId: 'slot1', wdId: 'wd-1', uid: _kUid, businessId: 'biz1', businessName: _bizQa,
      toTitle: _toQa, status: status, selectedWorkType: 'QA 분류', startTime: '10:00', endTime: '11:00', wage: 13000,
      workDate: day, appliedAt: _today.subtract(const Duration(days: 7)),
    );

/// [DU575] 같은 칸의 일반 초대(제안 관계 칸 0) — 동의함 = 수락 가능(INVITE · '수락하기') · 동의 전 = 동의 필요(CONSENT · '서류 열람 동의').
///   값 꼴 = invite_preaccept_card_test 의 _invite(r, consented:) 와 같은 갈래(준비 상태 · 동의 여부 · 동의 버전).
ApplicationModel _inviteApp({required bool consented}) => ApplicationModel(
      id: 'a2', toId: 'to1', slotId: 'slot1', wdId: 'wd-1', uid: _kUid, businessId: 'biz1', businessName: _bizQa,
      toTitle: _toQa, status: AppStatus.invited, selectedWorkType: 'QA 분류', startTime: '20:00', endTime: '22:00', wage: 13000,
      workDate: _day(3), appliedAt: _today.subtract(const Duration(days: 7)), invitedAt: _invited,
      inviteExpiresAt: _deadline, inviteAcceptDeadline: _deadline,
      workInstanceCapacityState: InviteCapacityState.available,
      inviteAcceptReadiness: consented ? InviteAcceptReadiness.ready : InviteAcceptReadiness.consentRequired,
      documentAccessConsentGiven: consented, documentAccessConsentVersion: consented ? DocumentAccessConsent.version : null,
    );

/// [DU610b] 장기 확정 — 끝 날짜 없음(진행 중 계약 · _reviewDate null → 화면 '출근 예정' 블록) · 시작 = 인자(지난 날 / 앞날).
///   값 꼴 = DU575 _longApp(applicationType · 상태 · 시각 같음) — workEndDate 만 뺐다.
ApplicationModel _longApp(String id, DateTime start) => ApplicationModel(
      id: id, toId: 'to1', slotId: 'slot1', wdId: 'wd-1', uid: _kUid, businessId: 'biz1', businessName: _bizQa,
      toTitle: _toQa, status: AppStatus.confirmed, selectedWorkType: 'QA 분류', startTime: '20:00', endTime: '22:00', wage: 13000,
      workDate: start, appliedAt: _today.subtract(const Duration(days: 14)),
      applicationType: AppType.longTerm,
    );

/// [DU610b] 명시 결근 근태 — 값 꼴 = my_applications_attendance_status_test 의 _att(status: AttendanceModel.statusAbsent).
AttendanceModel _absent(String appId, DateTime day) => AttendanceModel(
      id: 'att-$appId', applicationId: appId, userId: _kUid, businessId: 'biz1', businessName: _bizQa,
      workDate: day, workType: 'QA 분류', status: AttendanceModel.statusAbsent, wageStatus: 'pending', createdAt: day,
    );

TOModel _to() => TOModel(
      id: 'to1', businessId: 'biz1', businessName: _bizQa, type: 'flex', title: _toQa, creatorUID: 'admin1',
      status: TOStatus.closed, deadlineType: 'NONE', hoursBeforeStart: 0, workDetails: const [], totalRequired: 3,
      totalConfirmed: 0, totalPending: 1, isPublished: true, publishMode: 'immediate',
      createdAt: _today.subtract(const Duration(days: 10)), statusUpdatedAt: _today.subtract(const Duration(days: 10)),
    );

/// 사례마다 새로 — 목록 읽기 · 근태 월 읽기 호출 수.
class _Count {
  var list = 0;
  var att = 0;
}

/// 사례 — failAt = 목록 읽기의 몇 번째 호출을 실패시키는가(DU553 · DU554 꼴) · more = 첫 페이지가 '더 있음'.
typedef _Case = ({String id, int shots, Set<int> failAt, bool more});
const _cases = <_Case>[
  (id: 'CPEND', shots: 1, failAt: <int>{}, more: false),
  (id: 'INVITE', shots: 1, failAt: <int>{}, more: false),
  (id: 'ABS', shots: 1, failAt: <int>{}, more: false),
  (id: 'CPABS', shots: 1, failAt: <int>{}, more: false),
  (id: 'LONG', shots: 1, failAt: <int>{}, more: false),
  (id: 'LONGF', shots: 1, failAt: <int>{}, more: false),
  (id: 'ERR', shots: 1, failAt: <int>{1}, more: false),
  (id: 'MORE', shots: 1, failAt: <int>{2}, more: true),
  (id: 'STALE', shots: 1, failAt: <int>{2}, more: false),
];

/// 사례의 목록 — 카드 하나(ERR 는 첫 읽기가 실패해 목록 0).
List<ApplicationModel> _apps(_Case c) => switch (c.id) {
      'CPEND' => [_shortApp('a1', AppStatus.contractPending, _day(3))],
      'INVITE' => [_inviteApp(consented: true)],
      'ABS' => [_shortApp('a3', AppStatus.confirmed, _day(-1))],
      'CPABS' => [_shortApp('a4', AppStatus.contractPending, _day(-2))],
      'LONG' => [_longApp('a5', _day(-10))],
      'LONGF' => [_longApp('a6', _day(5))],
      'MORE' => [_shortApp('a7', AppStatus.confirmed, _day(3))],
      'STALE' => [_shortApp('a8', AppStatus.confirmed, _day(3))],
      _ => const <ApplicationModel>[],
    };

/// 사례의 근태 — 결근 두 사례만(그 지원서 id 로 매칭).
List<AttendanceModel> _atts(_Case c) => switch (c.id) {
      'ABS' => [_absent('a3', _day(-1))],
      'CPABS' => [_absent('a4', _day(-2))],
      _ => const <AttendanceModel>[],
    };

/// [DU610b] 목록 읽기 경계 — 목록 읽기만 사례의 failAt 번째 호출에서 예외로 끝난다(DU553 · DU554 꼴). 커서 있는 읽기가 성공하면 빈 다음 페이지.
///   쓰기 경로는 대역이 없다(autoExpirePending 은 아무 일도 하지 않는다).
MyApplicationsReads _reads(_Case c, _Count n) => MyApplicationsReads(
      myApplicationsPaged: ({required String uid, required int pageSize, String? startAfterDocId}) async {
        n.list++;
        if (c.failAt.contains(n.list)) throw Exception('du610b local list failure');
        if (startAfterDocId != null) return {'items': const <ApplicationModel>[], 'lastDocId': null, 'hasMore': false};
        return {'items': _apps(c), 'lastDocId': c.more ? 'du610b-p1' : null, 'hasMore': c.more};
      },
      toOrFailure: (id) async => (to: _to(), failed: false),
      contractsByWorker: (uid) async => const <EmploymentContractModel>[],
      autoExpirePending: (uid) async {},
      monthlyAttendances: ({required String userId, required int year, required int month}) async {
        n.att++;
        return _atts(c);
      },
      reviewById: (key) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
    );

/// [DU610b] 재는 글 — 배지 이름 · 결근 문장 · 실패/끝/이전 자료 안내 · 재시도 · 칩.
const _badgeLabel = <String, String>{'CPEND': '계약 진행 중', 'INVITE': '근무 초대', 'ABS': '결근', 'CPABS': '결근'};
const _absentText = '결근 처리됐어요';
const _errTitle = '지원 내역을 불러오지 못했어요';
const _moreText = '지원 내역을 더 불러오지 못했어요';
const _staleText = '최신 정보를 불러오지 못했어요. 아래는 이전에 받은 내용입니다.';
const _retryText = '다시 시도';
const _startPrefix = '시작일 ';
const _plannedSuffix = '출근 예정이에요';
const _chipAll = '전체 1';
const _chipProg = '진행중 1';
const _chipLast = '초대 0';
const _chipProgZero = '진행중 0';

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';

/// 첫 화면이 부르는 읽기 CF(화면 소스 그대로 — initState 의 변경 제안 목록) — 이 밖의 CF 이름은 차단하고 센다.
const _readFns = <String>{'callableGetMyConfirmedReassignmentProposals'};

/// Firestore 쓰기 연산 — 하나라도 오면 fsw 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// [DU526 · DU534 · DU536–554 와 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널(UserProvider → AuthService).
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du610bma.fake.auth.';
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
        return codec.encodeMessage(<Object?>['not-found', 'du610bma-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      _hit(fn);
      return codec.encodeMessage(<Object?>[<String, Object?>{'proposals': const <Object?>[]}]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['internal', 'du610bma-harness', null]);
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
      return codec.encodeMessage(<Object?>['du610bma-blocked', '$op 차단', null]);
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
    throw const SocketException('DU610b 관측 — 외부 HTTP 차단');
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '610';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du610bma-tb' && _env['DU_BEFORE_OBSERVE'] == '610') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du610bma-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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
    _out('R610 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S610MA-${v.id}-${c.id} 내 지원 장부 배지 · 결근 · 칩 · 실패 안내 · 장기 시작일', (t) async {
        final tok = 'S610MA-${v.id}-${c.id}';
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
        _out('D610 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final user = _P();
        final count = _Count();
        Object? failure;
        StackTrace? failureSt;
        var nShot = 0;
        var raw = '';
        try {
          FlutterError.onError = seen.add;
          final key = GlobalKey();
          Future<void> shot(String id, String state) async {
            _out('D610 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            nShot++;
          }

          Future<void> frames(int n) async {
            for (var i = 0; i < n; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
          }

          // 내 지원 — DU575 와 같은 앱(시험용 사용자 · 시계 · 목록 읽기 경계) · 목록 = 사례별(_apps · 목록 읽기 실패 주입 = failAt).
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
          await frames(30);
          final home = find.byType(MyApplicationsScreen);
          final nScr = home.evaluate().length;
          _out('D610 $tok att scr n=$nScr');
          need('화면 1', nScr == 1, '개수 $nScr');
          // [점검표 A4] 지연 생성 목록 — 찾는 글이 안 만들어졌으면 그 방향 목록을 그 글이 보일 때까지 끈다(누르기 아님 · 같은 host 찾기 전부 _bring 뒤).
          final vList = find.descendant(
              of: home, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down));
          final hList = find.descendant(
              of: home, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right));
          final fills0 = _fills(t);
          if (_badgeLabel.containsKey(c.id)) {
            // ① 상태 배지 — 장부 012(brand 짝) · 013(error 짝). 글 · 분기 그대로 · 색만.
            final label = _badgeLabel[c.id]!;
            await _bring(t, vList, (s) => s == label);
            final bd = await _badgeOf(t, home, label);
            _out('D610 $tok att badge n=${bd.n} fg=${bd.fg} base=${bd.base} face=${bd.face} cr=${bd.cr} ok45=${bd.ok45} brand=${bd.brand} err=${bd.err}');
            need('배지 1', bd.n == 1, '개수 ${bd.n}');
            raw = 'badge $bd';
          }
          if (c.id == 'ABS' || c.id == 'CPABS') {
            // ② 결근 결과 문장 — ABS = 확정 지난 근무 갈래 · CPABS = 계약 진행 중 지난 근무 갈래(_pastShiftOutcome).
            await _bring(t, vList, (s) => s == _absentText);
            final ab = await _txtOf(t, home, (s) => s == _absentText, screen);
            _out('D610 $tok att asent n=${ab.n} fs=${ab.fs} fw=${ab.fw} fg=${ab.fg} full=${ab.full} brk=${ab.brk} vis=${ab.vis}');
            need('결근 문장 1', ab.n == 1, '개수 ${ab.n}');
            raw = '$raw asent $ab';
          }
          if (c.id == 'CPEND') {
            // ③ 필터 칩 — 장부 064(조작 16 · 선택 700 / 미선택 400 · 배율만큼 줄 높이). 선택 '전체 1' · 미선택 '진행중 1' · 끝 '초대 0'(가로 도달).
            final ka = await _chipOf(t, home, hList, _chipAll, screen);
            _out('D610 $tok att chipa n=${ka.n} fs=${ka.fs} fw=${ka.fw} fg=${ka.fg} full=${ka.full} brk=${ka.brk} vis=${ka.vis} fit=${ka.fit}');
            need('칩 전체 1', ka.n == 1, '개수 ${ka.n}');
            final kb = await _chipOf(t, home, hList, _chipProg, screen);
            _out('D610 $tok att chipb n=${kb.n} fs=${kb.fs} fw=${kb.fw} fg=${kb.fg} full=${kb.full} brk=${kb.brk} vis=${kb.vis} fit=${kb.fit}');
            need('칩 진행중 1', kb.n == 1, '개수 ${kb.n}');
            final nRow = hList.evaluate().length;
            final rowH = nRow == 1 ? t.getRect(hList).height : 0.0;
            _out('D610 $tok att chiprow n=$nRow h=${rowH.toStringAsFixed(1)} m48=${rowH >= 48 - 0.01}');
            need('칩 줄 1', nRow == 1, '개수 $nRow');
            await shot('1chips', 'filter-chips-badge');
            final kz = await _chipOf(t, home, hList, _chipLast, screen);
            _out('D610 $tok att chipz n=${kz.n} fs=${kz.fs} fw=${kz.fw} fg=${kz.fg} full=${kz.full} brk=${kz.brk} vis=${kz.vis} fit=${kz.fit}');
            need('칩 초대 0', kz.n == 1, '개수 ${kz.n}');
            raw = '$raw chipa $ka chipb $kb row $rowH chipz $kz';
          }
          if (c.id == 'LONG' || c.id == 'LONGF') {
            // ④ 장기 확정 문장 — 장부 065. LONG(시작일 지남) strict = '시작일 …' · LONGF(앞날) = 두 모드 '… 출근 예정이에요' 그대로.
            bool isStart(String s) => s.startsWith(_startPrefix);
            bool isPlanned(String s) => s.endsWith(_plannedSuffix);
            final want = (c.id == 'LONG' && !_before) ? isStart : isPlanned;
            await _bring(t, vList, want);
            final nSt = _countText(home, isStart);
            final nOld = _countText(home, isPlanned);
            final lg = await _txtOf(t, home, want, screen);
            _out('D610 $tok att long st=$nSt old=$nOld n=${lg.n} fs=${lg.fs} fw=${lg.fw} fg=${lg.fg} full=${lg.full} brk=${lg.brk} vis=${lg.vis}');
            need('장기 문장 1', lg.n == 1, '개수 ${lg.n}');
            raw = '$raw long $nSt/$nOld $lg';
          }
          if (c.id == 'MORE') {
            // ⑤ '진행중 0' 칩(두 모드 · 그 필터가 비고 더 있음 → 다음 페이지 읽기 = 목록 읽기 2번째 실패 → 목록 끝 안내).
            final chF = find.text(_chipProgZero);
            if (chF.evaluate().isEmpty && hList.evaluate().isNotEmpty) {
              await t.scrollUntilVisible(chF, 80, scrollable: hList.first);
            }
            final nCh = chF.evaluate().length;
            _out('D610 $tok att act n=$nCh');
            need('진행중 0 칩 1', nCh == 1, '개수 $nCh');
            await t.ensureVisible(chF);
            await t.pump();
            await t.tap(chF);
            await frames(30);
            await _bring(t, vList, (s) => s == _moreText);
            final mt = await _txtOf(t, home, (s) => s == _moreText, screen);
            _out('D610 $tok att mtext n=${mt.n} fs=${mt.fs} fw=${mt.fw} fg=${mt.fg} full=${mt.full} brk=${mt.brk} vis=${mt.vis}');
            need('목록 끝 안내 1', mt.n == 1, '개수 ${mt.n}');
            raw = '$raw mtext $mt';
          }
          if (c.id == 'STALE') {
            // ⑤ 당겨 새로고침과 같은 콜백(RefreshIndicator.show() → onRefresh = _loadApplications · 두 모드) → 목록 읽기 2번째 실패 → 이전 자료 안내.
            final riF = find.byType(RefreshIndicator);
            final nRi = riF.evaluate().length;
            _out('D610 $tok att act n=$nRi');
            need('당겨 새로고침 1', nRi == 1, '개수 $nRi');
            t.state<RefreshIndicatorState>(riF).show();
            await frames(40);
            final st = await _txtOf(t, home, (s) => s == _staleText, screen);
            _out('D610 $tok att stext n=${st.n} fs=${st.fs} fw=${st.fw} fg=${st.fg} full=${st.full} brk=${st.brk} vis=${st.vis}');
            need('이전 자료 안내 1', st.n == 1, '개수 ${st.n}');
            raw = '$raw stext $st';
          }
          if (c.id == 'ERR') {
            final nEt = _countText(home, (s) => s == _errTitle);
            _out('D610 $tok att etitle n=$nEt');
            need('실패 본문 제목 1', nEt == 1, '개수 $nEt');
          }
          if (c.id == 'ERR' || c.id == 'MORE' || c.id == 'STALE') {
            // ⑥ '다시 시도' — 장부 063(조작 16/700). 글(전문 · 보임 · 역할) + 그 글이 든 단추(받는 자리 48 · 보임 · 중심 hit). 누르지 않는다.
            await _bring(t, vList, (s) => s == _retryText);
            final rt = await _txtOf(t, home, (s) => s == _retryText, screen);
            _out('D610 $tok att retry n=${rt.n} fs=${rt.fs} fw=${rt.fw} fg=${rt.fg} full=${rt.full} brk=${rt.brk} vis=${rt.vis}');
            need('다시 시도 1', rt.n == 1, '개수 ${rt.n}');
            final rb = _btnLine(t, home, (s) => s == _retryText, screen);
            _out('D610 $tok att rbtn n=${rb.n} dis=${rb.dis} m48=${rb.m48} vis=${rb.vis} hit=${rb.hit}');
            raw = '$raw retry $rt rbtn $rb';
          }
          final fills = _fills(t);
          _out('D610 $tok att fills n=${fills.n} brand=${fills.brand} err=${fills.err} none=${fills.none} other=${fills.other} list=${fills.list}');
          raw = '$raw fills0 $fills0 fills $fills';
          if (c.id != 'CPEND') {
            await shot(_shotId[c.id]!, _shotState[c.id]!);
          }
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
        _out('D610 $tok att wire rp=$nRp lr=$nLr la=$nLa cfx=$nCfx fsw=$nFsw fso=$nFso unexpected=$nUnexp http=$nHttp hcl=$nHcl harness=$nHarness');

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
        _out('R610 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D610 $tok att fw n=$nFw');
        _out('D610 $tok done state=${c.id} mode=$mode captures=$nShot overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        expect(nShot == c.shots, isTrue, reason: '$tok 캡처 수 = 선언 shots $nShot want ${c.shots}');
      }, skip: !_optIn);
    }
  }
}

/// [DU610b] 사례별 캡처 이름 · 상태(CPEND 는 칩 측정 중 '1chips').
const _shotId = <String, String>{
  'INVITE': '1badge', 'ABS': '1abs', 'CPABS': '1abs', 'LONG': '1long', 'LONGF': '1long', 'ERR': '1err', 'MORE': '1more', 'STALE': '1stale',
};
const _shotState = <String, String>{
  'INVITE': 'invite-badge', 'ABS': 'absent-confirmed', 'CPABS': 'absent-contract-pending', 'LONG': 'long-started', 'LONGF': 'long-upcoming',
  'ERR': 'list-read-failed', 'MORE': 'next-page-failed', 'STALE': 'reload-failed-stale',
};

// 측정 도우미(DU575 바이트 그대로 · DU573 r1 과 같이 main 뒤에 둔다 — preflight 'renderObject 재사용' 줄 훑기 거짓 양성 회피).

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

// [DU610b] 새 도우미 — 위 측정 블록을 그대로 부르고 글 역할(크기 · 굵기 · 색)만 더 읽는다.

/// 그린 글이 [match] 에 맞는 RichText 가 host 아래 몇 개인가(skipOffstage false · 지연 목록은 _bring 뒤).
int _countText(Finder host, bool Function(String s) match) => find
    .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
    .evaluate()
    .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
    .length;

/// [점검표 A4] 지연 생성 목록 대비 — 그 글이 아직 안 만들어졌으면 [list](세로 · 가로 Scrollable)를 그 글이 보일 때까지 끈다(누르기 아님).
Future<void> _bring(WidgetTester t, Finder list, bool Function(String s) match) async {
  final f = find.byWidgetPredicate(
      (w) => w is RichText && match(TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false))), skipOffstage: false);
  if (f.evaluate().isNotEmpty || list.evaluate().isEmpty) return;
  await t.scrollUntilVisible(
      find.byWidgetPredicate((w) => w is RichText && match(TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)))), 120,
      scrollable: list.first);
}

typedef _StyObs = ({int n, String fs, String fw, String fg});

/// 그 글 하나의 그려진 역할 — RichText 바깥 TextSpan 의 글자 크기 · 굵기 값 · 글자색(Text · KeepWordsText 모두 바깥 span 에 합친 style 이 있다).
_StyObs _styOf(Finder host, bool Function(String s) match) {
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => match(TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false))))
      .toList();
  if (es.length != 1) return (n: es.length, fs: '-', fw: '-', fg: '-');
  final st = (es.first.widget as RichText).text.style;
  final Color? fc = st?.color;
  return (n: 1, fs: (st?.fontSize ?? 0).toStringAsFixed(1), fw: (st?.fontWeight?.value ?? 0).toString(), fg: fc == null ? '-' : _hex(fc));
}

typedef _TxtObs = ({int n, String fs, String fw, String fg, bool full, int brk, bool vis});

/// 글 하나 — _seeText(전문 · 끊김 · 보임 · ensureVisible 대상 = 잰 대상) + _styOf(역할).
Future<_TxtObs> _txtOf(WidgetTester t, Finder host, bool Function(String s) match, Rect screen) async {
  final s = await _seeText(t, host, match, screen);
  final y = _styOf(host, match);
  return (n: s.n, fs: y.fs, fw: y.fw, fg: y.fg, full: s.full, brk: s.brk, vis: s.vis);
}

typedef _ChipObs = ({int n, String fs, String fw, String fg, bool full, int brk, bool vis, bool fit});

/// 필터 칩 하나 — 가로 칩 줄에서 안 만들어졌으면 끌어 넣고(_bring) · 글(_txtOf) · 그 글 상자가 칩 면(AnimatedContainer) 안에 드는가(fit).
Future<_ChipObs> _chipOf(WidgetTester t, Finder host, Finder hList, String label, Rect screen) async {
  // r1 수리(DU610b g1 B-CPEND STOP): 가로 칩 줄 끝 칩이 화면 밖이면 drag 대신 그 Scrollable 을 끝으로 옮긴 뒤 센다(단언 불변).
  // r2 수리(진단199): 캐시에 지어졌지만 화면 밖인 칩(skipOffstage:false 1 · 기본 0)을 '있음'으로 보고 이동을 건너뛰던 불일치 →
  //   측정(_seeText 의 matching 기본 skipOffstage:true)과 같은 기준인 '화면 안' 존재로 판단한다.
  final onstage0 = find
      .byWidgetPredicate((w) => w is RichText && TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) == label)
      .evaluate()
      .isNotEmpty;
  if (!onstage0 && hList.evaluate().isNotEmpty) {
    final pos = t.state<ScrollableState>(hList.first).position;
    pos.jumpTo(pos.maxScrollExtent);
    await t.pump();
  }
  await _bring(t, hList, (s) => s == label);
  final x = await _txtOf(t, host, (s) => s == label, screen);
  var fit = false;
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == label)
      .toList();
  if (es.length == 1) {
    final tf = find.byElementPredicate((q) => identical(q, es.first), skipOffstage: false);
    final cf = find.ancestor(of: tf, matching: find.byType(AnimatedContainer));
    if (cf.evaluate().isNotEmpty) fit = _inside(t.getRect(tf), t.getRect(cf.first));
  }
  return (n: x.n, fs: x.fs, fw: x.fw, fg: x.fg, full: x.full, brk: x.brk, vis: x.vis, fit: fit);
}

typedef _BadgeObs = ({int n, String fg, String base, String face, String cr, bool ok45, bool brand, bool err});

/// 상태 배지 하나 — 글 이름이 정확히 [label] 인 RichText 하나를 ensureVisible 로 넣고, 글자색 · 배지 면 원색(가장 가까운 BoxDecoration 색) ·
///   글 뒤 실제 바탕(_bgOf) · 대비 · brand 짝(brand / brandSurface) · error 짝(errorDark / errorBg) 을 잰다(DU575 _ddayOf 꼴).
Future<_BadgeObs> _badgeOf(WidgetTester t, Finder host, String label) async {
  bool hit(Element e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == label;
  final es0 = find.descendant(of: host, matching: find.byType(RichText), skipOffstage: false).evaluate().where(hit).toList();
  if (es0.length != 1) return (n: es0.length, fg: '-', base: '-', face: '-', cr: '0.00', ok45: false, brand: false, err: false);
  final tf = find.byElementPredicate((q) => identical(q, es0.first), skipOffstage: false);
  await t.ensureVisible(tf);
  await t.pump();
  final el = find.descendant(of: host, matching: find.byType(RichText), skipOffstage: false).evaluate().where(hit).first;
  final fg = (el.widget as RichText).text.style?.color ?? Colors.transparent;
  Color? found;
  el.visitAncestorElements((a) {
    final w = a.widget;
    if (w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color != null) {
      found = (w.decoration as BoxDecoration).color;
      return false;
    }
    return true;
  });
  final base = found;
  final face = _bgOf(el);
  final cr = _contrast(fg, face);
  final bv = base?.toARGB32();
  return (
    n: 1,
    fg: _hex(fg),
    base: base == null ? '-' : _hex(base),
    face: _hex(face),
    cr: cr.toStringAsFixed(2),
    ok45: cr >= 4.5,
    brand: fg.toARGB32() == AppColors.brand.toARGB32() && bv == AppColors.brandSurface.toARGB32(),
    err: fg.toARGB32() == AppColors.errorDark.toARGB32() && bv == AppColors.errorBg.toARGB32(),
  );
}
