// ignore_for_file: depend_on_referenced_packages
// [DU573 · UXW-3c · 문구 리터럴 · 낱말 단위 줄바꿈만] 다른 업무 제안 수락 — 기존 지원 정리 안내와 실제로 면제되는 기록(판정166 결정③ · 판정156 Q5 · 어투).
//   바뀐 글(이 시험이 그리는 것): 내 지원(MyApplicationsScreen) 제안 수락 확인창 본문 · 초대 약속 카드(InvitationPromiseCard) 제안 정리 안내.
//   before = 지금 A(my_applications_screen f6aa348d · invitation_promise_card 0bceab8c) 문장 정확 · strict = 후보 문장 정확(prep/mk_cand.py 와 같은 값).
//   측정 블록 = DU571 r2 시험(fad52117 · 정규 1회 DONE 5/5)의 max 판 _fullShown · _midBreaks · _area · _seeText · _btnLine 그대로(판정169a §5) —
//     바뀐 글 RichText **하나를** ensureVisible 로 넣고 **같은 요소**로 화면 ∩ 스크롤 칸 안(vis) · 전문 · 낱말 안 끊김(강제 포함) · 줄 수 · 읽는 이름.
//   하네스 = DU558 시험(d92408e3)의 내 지원 화면 하네스 그대로(읽기 경계 MyApplicationsReads · 시계 · 채널 전수 관찰 · 읽기 CF 1종만 빈 응답 · HTTP 차단).
//   확인창 열기 = 카드 '제안 조건으로 수락' 단추 한 번(invite_preaccept_card_test PC-17 · disclosure_four_screen_render_test F-1d 의 수락 단추 열기와 같은 경로) —
//     창 안 단추는 누르지 않는다(닫기 = 루트 Navigator pop(false) · 수락 CF 0). 카드 = 직접 생성(du1_s041_alt_offer_475_test 와 같은 꼴 · 누르기 0).
//   쓰기 0 · 허용 밖 CF 0 · HTTP 요청 0. 기본 skip — TB before/du573uxw3c-tb/DU_BEFORE_OBSERVE=573 · TA after/du573uxw3c-ta/없음.
import 'dart:convert';
import 'dart:io';
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
import 'package:ALfit/models/ui/invitation_projection.dart';
import 'package:ALfit/models/ui/invite_accept_readiness.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_applications_reads.dart';
import 'package:ALfit/screens/user/my_applications_screen.dart';
import 'package:ALfit/services/tax_identity_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';
import 'package:ALfit/widgets/user/invitation_promise_card.dart';

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

/// 사례 — OFFER = 내 지원 제안 수락 확인창 · CARD = 초대 약속 카드(공고 상세의 초대 화면이 그리는 카드 — 직접 생성).
typedef _Case = ({String id, int shots, bool card});
const _cases = <_Case>[(id: 'OFFER', shots: 1, card: false), (id: 'CARD', shots: 1, card: true)];

/// [DU573] 이 셀이 바꾸는 글 — after = 후보 문장(prep/mk_cand.py OFFER_MA · CARD_A) · before = 지금 A 문장(OFFER_MA_B · CARD_B). 정확 대조.
const _offerAfter = "수락하면 제안받은 업무로 확정되고, 기존 지원은 '다른 업무로 확정됨'으로 정리돼요.\n이 정리는 노쇼로 기록되지 않아요.";
const _offerBefore = "제안받은 업무로 확정되고, 기존 지원은 '다른 업무로 확정됨'으로\n정리됩니다. 취소·노쇼 불이익은 적용되지 않습니다.";
const _cardAfter = "수락하면 기존 지원은 '다른 업무로 확정됨'으로 정리돼요.\n이 정리는 노쇼로 기록되지 않아요.";
const _cardBefore = "수락하면 기존 지원은 '다른 업무로 확정됨'으로 정리되며,\n취소·노쇼 불이익은 적용되지 않습니다.";

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';

/// 첫 화면이 부르는 읽기 CF(화면 소스 그대로 — initState 의 변경 제안 목록) — 이 밖의 CF 이름은 차단하고 센다.
const _readFns = <String>{'callableGetMyConfirmedReassignmentProposals'};

/// Firestore 쓰기 연산 — 하나라도 오면 fsw 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// [DU526 · DU534 · DU536–554 와 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널(UserProvider → AuthService).
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du573uxw3c.fake.auth.';
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
        return codec.encodeMessage(<Object?>['not-found', 'du573uxw3c-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      _hit(fn);
      return codec.encodeMessage(<Object?>[<String, Object?>{'proposals': const <Object?>[]}]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['internal', 'du573uxw3c-harness', null]);
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
      return codec.encodeMessage(<Object?>['du573uxw3c-blocked', '$op 차단', null]);
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
    throw const SocketException('DU573 관측 — 외부 HTTP 차단');
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '573';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du573uxw3c-tb' && _env['DU_BEFORE_OBSERVE'] == '573') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du573uxw3c-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

/// [DU573] 사례의 바뀐 글인가 — before = 지금 A 문장 · strict = 후보 문장(둘 다 정확).
bool _want(_Case c, String s) => s == (c.card ? (_before ? _cardBefore : _cardAfter) : (_before ? _offerBefore : _offerAfter));

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
    _out('R573 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S573MT-${v.id}-${c.id} 제안 수락 정리 안내 어투(UXW-3c)', (t) async {
        final tok = 'S573MT-${v.id}-${c.id}';
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
        _out('D573 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
            _out('D573 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            nShot++;
          }

          if (c.card) {
            // 카드 — 공고 상세 초대 화면이 그리는 약속 카드를 직접 생성(DU475 와 같은 꼴 · 누르기 0).
            await t.pumpWidget(RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.workerTheme,
                builder: (ctx, child) =>
                    MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: InvitationPromiseCard(
                      projection: InvitationProjection(
                        application: _offerApp(),
                        contextState: InvitationContextState.loaded,
                        acceptability: InvitationAcceptability.acceptable,
                        drift: const InvitationDrift(),
                      ),
                      sourceApplication: _srcApp(),
                    ),
                  ),
                ),
              ),
            ));
            for (var i = 0; i < 8; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final host = find.byType(InvitationPromiseCard);
            final nScr = host.evaluate().length;
            _out('D573 $tok att scr n=$nScr');
            need('카드 1', nScr == 1, '개수 $nScr');
            final note = await _seeText(t, host, (s) => _want(c, s), screen);
            _out('D573 $tok att note n=${note.n} name=${note.name} full=${note.full} brk=${note.brk} lines=${note.lines} vis=${note.vis}');
            await shot('1card', 'promise-card-offer-note');
            raw = 'note $note';
          } else {
            // 내 지원 — DU558 과 같은 앱(시험용 사용자 · 시계 · 목록 읽기 경계) · 목록 = 원 지원 A + 제안 B.
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
                  home: MyApplicationsScreen(reads: _reads([_srcApp(), _offerApp()], count), clock: () => _noon),
                ),
              ),
            ));
            for (var i = 0; i < 30; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
            final home = find.byType(MyApplicationsScreen);
            final nScr = home.evaluate().length;
            _out('D573 $tok att scr n=$nScr');
            need('화면 1', nScr == 1, '개수 $nScr');
            // 확인창 열기 — 카드 단추 한 번(PC-17 · F-1d 와 같은 열기 · 수락 CF 는 창의 확인 단추에서만 나간다 — 누르지 않는다).
            final cta = find.text('제안 조건으로 수락');
            // [DU573 r1 · 판정167 시험 STOP 수리] B(320x640@2.0)에서 제안 카드 단추가 목록 지연 생성 · 화면 밖이라 0 개였다 —
            //   안 보일 때만 세로 목록을 단추가 보일 때까지 끈다(누르기 아님 · 단언 · 기대 · fixture 그대로).
            final vList = find.descendant(
                of: home, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down));
            if (cta.evaluate().isEmpty) {
              await t.scrollUntilVisible(cta, 120, scrollable: vList.first);
            }
            final nCta = cta.evaluate().length;
            need('제안 수락 단추 1', nCta == 1, '개수 $nCta');
            await t.ensureVisible(cta);
            await t.pump();
            await t.tap(cta);
            for (var i = 0; i < 30; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
            final dlg = find.byType(Dialog);
            final nDlg = dlg.evaluate().length;
            _out('D573 $tok att open n=$nDlg');
            need('확인창 1', nDlg == 1, '개수 $nDlg');
            final body = await _seeText(t, dlg, (s) => _want(c, s), screen);
            _out('D573 $tok att body n=${body.n} name=${body.name} full=${body.full} brk=${body.brk} lines=${body.lines} vis=${body.vis}');
            await shot('1dlg', 'offer-accept-dialog');
            final go = _btnLine(t, dlg, (s) => s == '동의하고 제안 수락', screen);
            _out('D573 $tok att go n=${go.n} dis=${go.dis} m48=${go.m48} vis=${go.vis} hit=${go.hit}');
            // 닫기 — 루트 Navigator pop(false)(창의 '취소' 단추를 누르지 않는다 · 반환 false → 수락 호출 0).
            navigatorKey.currentState?.pop(false);
            for (var i = 0; i < 10; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
            final nAfter = find.byType(Dialog).evaluate().length;
            _out('D573 $tok att close n=$nAfter');
            raw = 'body $body go $go close $nAfter';
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
        _out('D573 $tok att wire rp=$nRp lr=$nLr la=$nLa cfx=$nCfx fsw=$nFsw fso=$nFso unexpected=$nUnexp http=$nHttp hcl=$nHcl harness=$nHarness');

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
        _out('R573 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D573 $tok att fw n=$nFw');
        _out('D573 $tok done state=${c.id} mode=$mode captures=$nShot overflows=$nOvf exc=${exc != null}');

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

// [r1] 측정 도우미 2(DU571 r2 바이트 그대로)는 main 뒤에 둔다 — 위치만 옮김(Dart 최상위 선언은 순서 무관).
//   preflight v43 'renderObject 재사용' 줄 훑기가 _seeText 의 지역 rp 를 main 의 wire 출력 글자 'rp=' 와 이어 본 거짓 양성(check_03 · rp@438 동작@560 재사용@678)을 피한다.

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
