// ignore_for_file: depend_on_referenced_packages
// [DU575 · 주 행동 채움 색 · 행동 배치만] 내 지원 초대/제안 수락 확인창 '동의하고 … 수락' 채움 초록(success) → brand(대표 11-21) +
//   큰 글자(배율>1.0)에서 행동 두 개를 세로 전체 폭으로 쌓기(DU573 후보 ① — B 에서 '동의/하고/제안/수락' 4줄) · 같은 흐름 서류 열람 동의 창 '동의하기' 배치.
//   [r1 · 판정139 §4 결정 이행] 같은 두 파일 안: 544-7 수락 확인창 머리 아이콘 grey600 · 544-2 '중간정산 요청' brand 외곽/글 ·
//     544-4 장기 D-day >14일 중립(grey500 10% 면 · textSecondary) · 544-11 공고 상세 '지원 취소하기' 진입 중립(textSecondary).
//   그리는 것: 내 지원(MyApplicationsScreen) 확인창 셋 — OFFER(제안 수락) · INVITE(초대 수락) · CONSENT(서류 열람 동의) + LONG(장기 확정 카드 —
//     '중간정산 요청' 단추 · D-day 배지 · 누르기 0).
//   공고 상세(JobPostingScreen) 수락 확인창 · 지원 취소 진입은 열지 않는다(미관측) — INVITE 사례에서 소스 계약만 읽는다(att jpsrc).
//   before = 지금 A(my_applications_screen eab7ce81 · job_posting_screen 0b035c10) 기록 · strict = 후보(prep/mk_cand.py) 단언.
//   측정 블록 = DU571 r2 시험(fad52117 · 정규 1회 DONE 5/5)의 max 판 _fullShown · _midBreaks · _area · _seeText · _btnLine 그대로(판정169a §5) ·
//     하네스 = DU573 r1 시험(7c0d634d · 정규 1회 DONE 5/5)의 내 지원 하네스 그대로(지연 목록 대비 scrollUntilVisible 포함 · 점검표 A4) ·
//     색 = DU309 시험(du1_confirm_color_split_309_test)의 _lum · _contrast · _hex · bgOf 그대로(bgOf 만 최상위로 옮김).
//   확인창 열기 = 카드 단추 한 번(PC-08 · PC-09 · PC-17 · F-1d 와 같은 열기) — 창 안 단추는 누르지 않는다(닫기 = 루트 Navigator pop(false) · CF 0).
//   쓰기 0 · 허용 밖 CF 0 · HTTP 요청 0. 기본 skip — TB before/du575acc-tb/DU_BEFORE_OBSERVE=575 · TA after/du575acc-ta/없음.
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

/// [DU573] 원 지원 A(대기 · 같은 슬롯 · 같은 시각)와 다른 업무 제안 B(초대 · A 를 가리킴) — DU558 대역의 초대 칸 꼴 + 제안 관계 칸.
///   값 꼴 = 기존 fixture: 제안 · 원 지원 = du1_s041_alt_offer_475_test 의 제안/원 지원(ALTERNATIVE_WORK · 원 지원 PENDING) · 기한 = DU558 초대 기한.
///   A 가 같은 목록에 있어 확인창이 원 지원을 한 건 더 읽지 않는다(화면 :2640–2645 · 읽기 0).
ApplicationModel _srcApp() => ApplicationModel(
      id: 'a0', toId: 'to1', slotId: 'slot1', wdId: 'wd-0', uid: _kUid, businessId: 'biz1', businessName: _bizQa,
      toTitle: _toQa, status: AppStatus.pending, selectedWorkType: '상차', startTime: '20:00', endTime: '22:00', wage: 13000,
      workDate: _day(3), appliedAt: _today.subtract(const Duration(days: 7)),
    );

ApplicationModel _offerApp() => ApplicationModel(
      id: 'a1', toId: 'to1', slotId: 'slot1', wdId: 'wd-1', uid: _kUid, businessId: 'biz1', businessName: _bizQa,
      toTitle: _toQa, status: AppStatus.invited, selectedWorkType: 'QA 분류', startTime: '20:00', endTime: '22:00', wage: 13000,
      workDate: _day(3), appliedAt: _today.subtract(const Duration(days: 7)), invitedAt: _invited,
      inviteExpiresAt: _deadline, inviteAcceptDeadline: _deadline,
      workInstanceCapacityState: InviteCapacityState.available, inviteAcceptReadiness: InviteAcceptReadiness.ready,
      offerKind: 'ALTERNATIVE_WORK', sourceApplicationId: 'a0', sourceWorkType: '상차',
      documentAccessConsentGiven: true, documentAccessConsentVersion: DocumentAccessConsent.version,
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

/// [DU575 r1] 장기 확정(LONG) — 열흘 전 시작 · 끝 = 시계 + 30일(D-30 · '정상 남은 기간 >14일' 갈래) · 퇴사 신청 없음.
///   값 꼴 = du1_s071_myapps_color_544_test 의 LONG(_mk(AppStatus.confirmed, _day(-10), applicationType: AppType.longTerm, workEndDate: _day(30))).
ApplicationModel _longApp() => ApplicationModel(
      id: 'a3', toId: 'to1', slotId: 'slot1', wdId: 'wd-1', uid: _kUid, businessId: 'biz1', businessName: _bizQa,
      toTitle: _toQa, status: AppStatus.confirmed, selectedWorkType: 'QA 분류', startTime: '20:00', endTime: '22:00', wage: 13000,
      workDate: _day(-10), appliedAt: _today.subtract(const Duration(days: 14)),
      applicationType: AppType.longTerm, workEndDate: _day(30),
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

/// [DU573] 목록 읽기 경계 — DU558 의 같은 이름 대역과 같은 몸통(실패 주입 0 · 목록 · 근태는 성공 응답만 · 쓰기 경로 대역 없음). 인자만 목록으로 받는다.
MyApplicationsReads _reads(List<ApplicationModel> apps, _Count n) => MyApplicationsReads(
      myApplicationsPaged: ({required String uid, required int pageSize, String? startAfterDocId}) async {
        n.list++;
        if (startAfterDocId != null) return {'items': const <ApplicationModel>[], 'lastDocId': null, 'hasMore': false};
        return {'items': apps, 'lastDocId': null, 'hasMore': false};
      },
      toOrFailure: (id) async => (to: _to(), failed: false),
      contractsByWorker: (uid) async => const <EmploymentContractModel>[],
      autoExpirePending: (uid) async {},
      monthlyAttendances: ({required String userId, required int year, required int month}) async {
        n.att++;
        return const <AttendanceModel>[];
      },
      reviewById: (key) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
    );

/// 사례 — open = 카드에서 누르는 단추 글 · go = 확인창 주 행동 글(이 셀이 채움 색 · 배치를 재는 단추) · LONG 은 확인창 없음(둘 다 빈 글).
typedef _Case = ({String id, int shots, String open, String go});
const _cases = <_Case>[
  (id: 'OFFER', shots: 1, open: '제안 조건으로 수락', go: '동의하고 제안 수락'),
  (id: 'INVITE', shots: 1, open: '수락하기', go: '동의하고 초대 수락'),
  (id: 'CONSENT', shots: 1, open: '서류 열람 동의', go: '동의하기'),
  (id: 'LONG', shots: 1, open: '', go: ''),
];

/// 사례의 목록 — OFFER = 원 지원 A + 제안 B(DU573 과 같다) · INVITE = 동의한 초대 · CONSENT = 동의 전 초대 · LONG = 장기 확정 하나.
List<ApplicationModel> _apps(_Case c) => c.id == 'OFFER'
    ? [_srcApp(), _offerApp()]
    : c.id == 'LONG'
        ? [_longApp()]
        : [_inviteApp(consented: c.id == 'INVITE')];

/// [DU575 r1] LONG 에서 재는 글 — 중간정산 요청 단추 글 · D-day 배지 글(시계 고정 · 끝 = +30일).
const _interimLabel = '중간정산 요청';
const _ddayLabel = 'D-30';

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';

/// 첫 화면이 부르는 읽기 CF(화면 소스 그대로 — initState 의 변경 제안 목록) — 이 밖의 CF 이름은 차단하고 센다.
const _readFns = <String>{'callableGetMyConfirmedReassignmentProposals'};

/// Firestore 쓰기 연산 — 하나라도 오면 fsw 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// [DU526 · DU534 · DU536–554 와 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널(UserProvider → AuthService).
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du575acc.fake.auth.';
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
        return codec.encodeMessage(<Object?>['not-found', 'du575acc-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      _hit(fn);
      return codec.encodeMessage(<Object?>[<String, Object?>{'proposals': const <Object?>[]}]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['internal', 'du575acc-harness', null]);
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
      return codec.encodeMessage(<Object?>['du575acc-blocked', '$op 차단', null]);
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
    throw const SocketException('DU575 관측 — 외부 HTTP 차단');
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '575';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du575acc-tb' && _env['DU_BEFORE_OBSERVE'] == '575') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du575acc-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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
    _out('R575 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S575AB-${v.id}-${c.id} 수락 확인창 주 행동 채움 · 배치', (t) async {
        final tok = 'S575AB-${v.id}-${c.id}';
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
        _out('D575 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
            _out('D575 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            nShot++;
          }

          // 내 지원 — DU573 과 같은 앱(시험용 사용자 · 시계 · 목록 읽기 경계) · 목록 = 사례별(_apps).
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
                home: MyApplicationsScreen(reads: _reads(_apps(c), count), clock: () => _noon),
              ),
            ),
          ));
          for (var i = 0; i < 30; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          final home = find.byType(MyApplicationsScreen);
          final nScr = home.evaluate().length;
          _out('D575 $tok att scr n=$nScr');
          need('화면 1', nScr == 1, '개수 $nScr');
          // [DU573 r1 · 점검표 A4] 지연 생성 목록 — 찾는 글이 안 만들어졌으면 세로 목록을 그 글이 보일 때까지 끈다(누르기 아님 · 같은 host 찾기 전부).
          final vList = find.descendant(
              of: home, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down));
          if (c.id == 'LONG') {
            // [DU575 r1] 장기 확정 카드 — D-day(판정139 544-4) · '중간정산 요청'(544-2). 누르지 않는다.
            final ddF = find.text(_ddayLabel);
            if (ddF.evaluate().isEmpty) {
              await t.scrollUntilVisible(ddF, 120, scrollable: vList.first);
            }
            final nDd = ddF.evaluate().length;
            need('D-day 1', nDd == 1, '개수 $nDd');
            await t.ensureVisible(ddF);
            await t.pump();
            final dd = _ddayOf(ddF);
            _out('D575 $tok att dday n=$nDd fg=${dd.fg} base=${dd.base} face=${dd.face} cr=${dd.cr} ok45=${dd.ok45} neutral=${dd.neutral}');
            final imF = find.text(_interimLabel);
            if (imF.evaluate().isEmpty) {
              await t.scrollUntilVisible(imF, 120, scrollable: vList.first);
            }
            final nIm = imF.evaluate().length;
            need('중간정산 요청 1', nIm == 1, '개수 $nIm');
            await t.ensureVisible(imF);
            await t.pump();
            final im = _interimOf(t, imF);
            _out('D575 $tok att interim n=$nIm fg=${im.fg} side=${im.side} lab=${im.lab} face=${im.face} cr=${im.cr} ok45=${im.ok45} brand=${im.brand} teal=${im.teal}');
            final lfills = _fills(t);
            _out('D575 $tok att fills n=${lfills.n} brand=${lfills.brand} err=${lfills.err} none=${lfills.none} other=${lfills.other} list=${lfills.list}');
            await shot('1card', 'long-term-card');
            raw = 'dday $dd interim $im fills $lfills';
          } else {
            // 확인창 열기 — 카드 단추 한 번(수락 CF 는 창의 확인 단추에서만 나간다 — 누르지 않는다).
            final cta = find.text(c.open);
            if (cta.evaluate().isEmpty) {
              await t.scrollUntilVisible(cta, 120, scrollable: vList.first);
            }
            final nCta = cta.evaluate().length;
            need('여는 단추 1', nCta == 1, '개수 $nCta');
            await t.ensureVisible(cta);
            await t.pump();
            await t.tap(cta);
            for (var i = 0; i < 30; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
            final dlg = find.byType(Dialog);
            final nDlg = dlg.evaluate().length;
            _out('D575 $tok att open n=$nDlg');
            need('확인창 1', nDlg == 1, '개수 $nDlg');
            // 주 행동 글 — 전문 · 낱말 안 끊김 · 줄 수 · 읽는 이름 · 보임(DU571 _seeText 그대로 · 대상 = 확인창 안 그 글 하나).
            final label = await _seeText(t, dlg, (s) => s == c.go, screen);
            _out('D575 $tok att label n=${label.n} name=${label.name} full=${label.full} brk=${label.brk} lines=${label.lines} vis=${label.vis}');
            final go = _btnLine(t, dlg, (s) => s == c.go, screen);
            _out('D575 $tok att go n=${go.n} dis=${go.dis} m48=${go.m48} vis=${go.vis} hit=${go.hit}');
            final no = _btnLine(t, dlg, (s) => s == '취소', screen);
            _out('D575 $tok att no n=${no.n} dis=${no.dis} m48=${no.m48} vis=${no.vis} hit=${no.hit}');
            final lay = _layOf(t, dlg, c.go, v.s);
            _out('D575 $tok att lay mode=${lay.mode} ok=${lay.ok} ctext=${lay.ctext} acc=${lay.acc} can=${lay.can}');
            final paint = _paintOf(t, dlg, c.go);
            _out('D575 $tok att paint n=${paint.n} fill=${paint.fill} fg=${paint.fg} cr=${paint.cr} brand=${paint.brand} white=${paint.white} icon=${paint.icon}');
            final fills = _fills(t);
            _out('D575 $tok att fills n=${fills.n} brand=${fills.brand} err=${fills.err} none=${fills.none} other=${fills.other} list=${fills.list}');
            if (c.id == 'INVITE') {
              // [DU575] 공고 상세 수락 확인창 — 이 시험은 열지 않는다(미관측) · 같은 함수 본문의 소스 계약만 읽는다(채움 · 배치 · 낱말 줄바꿈 · 초록 0).
              final jp = File('lib/screens/common/job_posting_screen.dart').readAsStringSync();
              final i0 = jp.indexOf('Future<void> _acceptInviteFromDetail() async {');
              final i1 = i0 < 0 ? -1 : jp.indexOf('Future<void> _declineInviteFromDetail() async {', i0);
              final fn = (i0 < 0 || i1 < 0) ? '' : jp.substring(i0, i1);
              final jBrand = fn.contains('style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),');
              final jGreen = fn.contains('backgroundColor: AppColors.success');
              // (이어 쓴 리터럴 — preflight '정의 없는 private 호출' 훑기가 문자열 안 '_이름(' 을 호출로 읽지 않게 · 값은 같은 글)
              final jStack = fn.contains('actions: _acceptDialog' 'Actions(') && jp.contains('List<Widget> _acceptDialog' 'Actions(');
              final jWords = fn.contains("TextLayout.keepWords(isOffer ? '동의하고 제안 수락' : '동의하고 초대 수락')");
              // [r1] 판정139 544-7 머리 아이콘 grey600 · 544-11 '지원 취소하기' 일반 진입 중립(그 블록 안 errorDark 0 · textSecondary).
              final jIcon = fn.contains('iconColor: AppColors.grey600,') && !fn.contains('iconColor: AppColors.success,');
              final k0 = jp.indexOf('// 지원 취소 링크 (PENDING)');
              final k1 = k0 < 0 ? -1 : jp.indexOf('// ── 내 지원 진입 시 하단 바', k0);
              final cancelSrc = (k0 < 0 || k1 < 0) ? '' : jp.substring(k0, k1);
              final jCancel = cancelSrc.contains('AppColors.textSecondary') && !cancelSrc.contains('AppColors.errorDark');
              _out('D575 $tok att jpsrc found=${fn.isNotEmpty && cancelSrc.isNotEmpty} brand=$jBrand green=$jGreen stack=$jStack words=$jWords icon=$jIcon cancel=$jCancel');
            }
            await shot('1dlg', 'accept-dialog-actions');
            // 닫기 — 루트 Navigator pop(false)(창의 '취소' 단추를 누르지 않는다 · 반환 false → 수락/동의 호출 0).
            navigatorKey.currentState?.pop(false);
            for (var i = 0; i < 10; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
            final nAfter = find.byType(Dialog).evaluate().length;
            _out('D575 $tok att close n=$nAfter');
            raw = 'label $label go $go no $no lay $lay paint $paint fills $fills close $nAfter';
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
        _out('D575 $tok att wire rp=$nRp lr=$nLr la=$nLa cfx=$nCfx fsw=$nFsw fso=$nFso unexpected=$nUnexp http=$nHttp hcl=$nHcl harness=$nHarness');

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
        _out('R575 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D575 $tok att fw n=$nFw');
        _out('D575 $tok done state=${c.id} mode=$mode captures=$nShot overflows=$nOvf exc=${exc != null}');

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

// 측정 도우미(DU571 r2 바이트 그대로 · DU573 r1 과 같이 main 뒤에 둔다 — preflight 'renderObject 재사용' 줄 훑기 거짓 양성 회피).

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

/// [DU575] 확인창 안 [go] 글이 든 버튼 하나와 '취소' 글이 든 버튼 하나의 놓임 — col = 주 행동이 취소 위(가로 겹침) · row = 주 행동이 취소 오른쪽(세로 겹침).
///   ok = 배율 >1 이면 col · 아니면 row(후보 기대 — before 는 기록) · ctext = 취소가 TextButton(글자 단추 위계 그대로).
typedef _LayObs = ({String mode, bool ok, bool ctext, String acc, String can});

String _rect(Rect r) =>
    '${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)},${r.right.toStringAsFixed(1)},${r.bottom.toStringAsFixed(1)}';

Finder? _btnOf(Finder host, String text) {
  final btn = find.byWidgetPredicate((w) => w is ButtonStyleButton, skipOffstage: false);
  final es = find
      .descendant(of: host, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == text)
      .where((e) => find.ancestor(of: find.byElementPredicate((x) => identical(x, e), skipOffstage: false), matching: btn).evaluate().isNotEmpty)
      .toList();
  if (es.length != 1) return null;
  final el = es.first;
  return find.ancestor(of: find.byElementPredicate((x) => identical(x, el), skipOffstage: false), matching: btn).first;
}

_LayObs _layOf(WidgetTester t, Finder host, String go, double scale) {
  final af = _btnOf(host, go);
  final cf = _btnOf(host, '취소');
  if (af == null || cf == null) return (mode: 'none', ok: false, ctext: false, acc: '-', can: '-');
  final a = t.getRect(af);
  final c = t.getRect(cf);
  final hOverlap = a.left < c.right && c.left < a.right;
  final vOverlap = a.top < c.bottom && c.top < a.bottom;
  final mode = (a.bottom <= c.top + 0.5 && hOverlap) ? 'col' : (a.left >= c.right - 0.5 && vOverlap) ? 'row' : 'other';
  return (
    mode: mode,
    ok: scale > 1.0 ? mode == 'col' : mode == 'row',
    ctext: t.widget(cf) is TextButton,
    acc: _rect(a),
    can: _rect(c),
  );
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

/// [DU575 r1 · 판정139 544-2] '중간정산 요청' 외곽선 단추 — 단추 스타일의 글/선 색(DU544 시험 :747–749 와 같은 읽기) · 그려진 글자색 · 글 뒤 실제 바탕 · 대비.
///   brand = 글 · 선 · 그려진 글 모두 brand · teal = 셋 중 teal/tealDark 하나라도(옛 식별색).
typedef _ImObs = ({String fg, String side, String lab, String face, String cr, bool ok45, bool brand, bool teal});

_ImObs _interimOf(WidgetTester t, Finder f) {
  final b = t.widget<OutlinedButton>(find.ancestor(of: f, matching: find.byWidgetPredicate((w) => w is OutlinedButton)).first);
  final fg = b.style?.foregroundColor?.resolve(<WidgetState>{}) ?? Colors.transparent;
  final side = b.style?.side?.resolve(<WidgetState>{})?.color ?? Colors.transparent;
  final el = find.descendant(of: f, matching: find.byType(RichText), skipOffstage: false).evaluate().first;
  final lab =(el.widget as RichText).text.style?.color ?? Colors.transparent;
  final face = _bgOf(el);
  final cr = _contrast(lab, face);
  final brand = AppColors.brand.toARGB32();
  final teals = {AppColors.teal.toARGB32(), AppColors.tealDark.toARGB32()};
  return (
    fg: _hex(fg),
    side: _hex(side),
    lab: _hex(lab),
    face: _hex(face),
    cr: cr.toStringAsFixed(2),
    ok45: cr >= 4.5,
    brand: fg.toARGB32() == brand && side.toARGB32() == brand && lab.toARGB32() == brand,
    teal: teals.contains(fg.toARGB32()) || teals.contains(side.toARGB32()) || teals.contains(lab.toARGB32()),
  );
}

/// [DU575 r1 · 판정139 544-4] D-day 배지(>14일) — 그려진 글자색 · 배지 면의 원래 색(가장 가까운 BoxDecoration 색 · 알파 뺀 RGB) · 글 뒤 실제 바탕(_bgOf) · 대비.
///   neutral = 글 textSecondary · 면 원색 grey500(10% → grey100 꼴 · 만료 갈래와 같은 짝).
typedef _DdObs = ({String fg, String base, String face, String cr, bool ok45, bool neutral});

_DdObs _ddayOf(Finder f) {
  final el = find.descendant(of: f, matching: find.byType(RichText), skipOffstage: false).evaluate().first;
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
  return (
    fg: _hex(fg),
    base: base == null ? '-' : _hex(base),
    face: _hex(face),
    cr: cr.toStringAsFixed(2),
    ok45: cr >= 4.5,
    neutral: fg.toARGB32() == AppColors.textSecondary.toARGB32() && base != null && (base.toARGB32() & 0xFFFFFF) == (AppColors.grey500.toARGB32() & 0xFFFFFF),
  );
}
