// ignore_for_file: depend_on_referenced_packages
// [CONSENT-R4b] 서류 열람 동의 6 노출면(+ 재배치 시트) 화면 harness — 정적 작성 · 실행 0 · 컴파일 미확인.
// [CONSENT-R5 · 판정 consent1121(DU_consent_fast_path_decision_2026-11-21) §3–§4] 빠른 경로 판 — r4d 판(00508c60) 위 국소 수정만:
//   · 조건 W/B/N = DU 측정 블록과 같은 세 칸(W 390×844@1.0 · B 320×640@2.0 · N 320×640@1.0) — 옛 W360/B320 두 칸 대체.
//   · F-R4D-7 대체: 끝 글자 판정 = DU571 r2 max 세로+tight 가로 공차 0.5 `_fullShown`(바이트 그대로) + 화면 ∩ 조상 스크롤 칸(`_area`) 안.
//     r4d 의 조상 clip 종류 판정은 뺐다 — 잉크/모든 clip 무결은 W/B/N 원 PNG · 3칸 합성 직접 열람으로 따로 판정한다(이 시험의 통과로 대신하지 않는다).
//   · 캡처: 면마다 1body(카드 끝 문단 끝) · 2detail(자세히 열고 끝) · 3cta(자세히 닫고 동의 행동 단추 도달) — DU1_VQ_PHASE 있을 때만(du1_vq_capture).
//   · A4: 목록/시트 지연 생성 대비 `_bringBuilt`(DU581 r2 형태) — 카드 문단 · 자세히 · CTA · 내 지원 목록 단추 전부.
//   · A8: 동의 행동 단추 채움 색을 줄로 남긴다(ctaFill · brand/success 비교값).
//   · 채널/HTTP: DU573 하네스와 같은 관찰 — 읽기 CF 1종(callableGetMyConfirmedReassignmentProposals)만 빈 응답 · 그 밖 CF/Firestore 차단 · 'flutter/' 기반 채널 통과 ·
//     HTTP 차단. 허용 밖 CF · Firestore 쓰기 · 허용 밖 채널 · HTTP 요청이 하나라도 있으면 그 시험 실패(tearDown).
//   · 글꼴: DU573 과 같은 NotoSansKR(FlutterTest 글꼴 포함) — 실제 한글 폭으로 잰다.
//   · S6 거울: 공고 상세 원문(DU573 판 제안 문장 · KeepWordsText · DU575 판 머리 아이콘 grey600 · 주 행동 brand · 큰 글자 세로 쌓기 배치)과
//     같게 맞추고 MIRROR-BIND 에 그 결속을 더했다(g1 · 2026-11-21 DU575 DONE 뒤).
//
//   r4 판(045bd187 · history/ 보존)에서 바뀐 것(r4 감사 C-R4-5):
//     · 문단 끝 글자 상자가 화면과 가장 가까운 스크롤 영역(clip) 안에 있어야 한다(끝 정렬 스크롤 뒤)
//     · CTA 버튼의 터치 영역(버튼 render 상자) ≥ 48×48 · '자세히' ≥ 48×48
//     · 취소 = 미전송 + 취소 버튼 hitTestable(크기는 관측값 출력)
//     · S5o(내 지원 · 다른 업무 제안 수락)를 거울이 아니라 실제 MyApplicationsScreen 셀로 분리
//     · 문단 1 공통 행동 문장 · 동의 전용 창은 given:true 를 보낸다(원문 결속 MIRROR-BIND 에 추가)
//
//   LOCAL 위치: A_copy/test/consent_r4b_six_surface_harness_test.dart (후보 lib 적용본에서만 실행)
//   조건: 360×800 @1.0 · 320×640 @2.0 (devicePixelRatio 1.0, textScaler linear).
//   네트워크·실계정 0: Firebase core 는 가짜 플랫폼, 제출 버튼은 누르지 않는다(재배치 시트만 호출 대체 seam).
//
//   면(호스트)                                   방식
//   S1 지원 확인 시트(apply_confirm_dialog:123)     실제 ApplyConfirmDialog.show
//   S2 장기 지원 시트(longterm_apply_sheet:456)     실제 LongTermApplySheet(DialogHelper.showSheet)
//   S3 여러 업무 지원(multi_apply_confirm_sheet:750 · 현재 A c2b691ea · DU-O031) 실제 MultiApplyConfirmSheet(route)
//   S4 동의 전용 창(my_applications_screen:2528)    실제 MyApplicationsScreen(초대 · 'invite_preaccept_card_test' 하네스 모양)
//   S5 초대 수락 창(my_applications_screen:2691)    실제 MyApplicationsScreen(초대)
//   S5o 제안 수락 창(my_applications_screen:2605)   실제 MyApplicationsScreen(offerKind ALTERNATIVE_WORK · '제안 조건으로 수락' :1931)
//   S6 공고 화면 수락(job_posting_screen:3883)      거울(DialogHelper.showCustom) + 원문 결속 검사 — 초대/제안 두 버튼
//   S7 재배치 동의(후보 confirmed_reassignment_sheet) 실제 시트 + ConfirmedReassignmentService.debugCall
//
//   면마다 보는 것: 넘침 0 · 카드 두 문단이 보임 · 마지막 문단 끝까지 스크롤 후 hitTestable ·
//   '자세히' hitTestable(동의 전) → 열면 상세 전부 · 닫힘 · 여닫기 동안 제출·라우트 변화 0 ·
//   CTA hitTestable · 취소 = 미전송으로 닫힘. 문단 줄 수와 마지막 줄은 관측값으로 출력한다(기준값 미동결).
//
//   '거울'은 실제 화면이 아니다. 그 면의 위 안내·카드 호출·버튼 이름이 원문과 같은지 결속 검사로
//   묶고, 화면 실측 성공을 실제 면의 성공으로 올려 쓰지 않는다(보고에 따로 적는다).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui show BoxHeightStyle;

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/confirmed_reassignment_proposal.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/work_detail_model.dart';
import 'package:ALfit/models/ui/invite_accept_readiness.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_applications_reads.dart';
import 'package:ALfit/screens/user/my_applications_screen.dart';
import 'package:ALfit/services/confirmed_reassignment_service.dart';
import 'package:ALfit/services/tax_identity_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/responsive_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_confirm_dialog.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';
import 'package:ALfit/widgets/dialogs/apply/longterm_apply_sheet.dart';
import 'package:ALfit/widgets/common/keep_words_text.dart';
import 'package:ALfit/widgets/dialogs/apply/multi_apply_confirm_sheet.dart';
import 'package:ALfit/widgets/dialogs/confirmed_reassignment_sheet.dart';

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
const _biz = '강남 물류센터 제2물류동 야간 분류팀';

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: _kUid,
        username: _kUid,
        name: 'QA 지원자',
        email: '$_kUid@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시'),
        accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 9, 1),
        idCardImagePath: 'id_cards/$_kUid/front.jpg',
        isIdVerified: true,
        bankName: '국민은행',
        accountNumber: '000000000000',
        accountHolder: 'QA 지원자',
        bankbookImagePath: 'bankbooks/$_kUid/b.jpg',
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

typedef _Cond = ({String id, Size size, double scale});
// [r5] W/B/N — DU 측정 블록 `_views` 와 같은 세 칸(du1_s071_uxw3c_573_test.dart:401 · du1_s052_uxw5_admin_ops_test.dart:218).
const List<_Cond> _conds = [
  (id: 'W', size: Size(390, 844), scale: 1.0),
  (id: 'B', size: Size(320, 640), scale: 2.0),
  (id: 'N', size: Size(320, 640), scale: 1.0),
];

final _nav = GlobalKey<NavigatorState>();

// ── 공용 측정 ───────────────────────────────────────────────────────────
List<String> _overflowSink() {
  final sink = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      sink.add(m.split('\n').first);
    } else {
      prev?.call(d);
    }
  };
  addTearDown(() => FlutterError.onError = prev);
  return sink;
}

Future<void> _settle(WidgetTester t, [int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// 문단 하나의 줄 수와 마지막 줄(보이는 글자) — 관측값.
({int lines, String last}) _lineInfo(WidgetTester t, Finder text) {
  // [g6 · 판정173 §5 :57] Text(semanticsLabel 있으면 바깥 렌더 = RenderSemanticsAnnotations) 아래 정확한 RichText 1 개의 RenderParagraph.
  final rich = find.descendant(of: text, matching: find.byType(RichText));
  expect(rich, findsOneWidget, reason: '문단 Text 아래 RichText 정확히 1');
  final rp = t.renderObject<RenderParagraph>(rich);
  final raw = rp.text.toPlainText();
  final tops = <double>[];
  final buf = <double, StringBuffer>{};
  for (var i = 0; i < raw.length; i++) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = (bx.first.top * 10).roundToDouble() / 10;
    if (!tops.contains(top)) tops.add(top);
    (buf[top] ??= StringBuffer()).write(raw[i]);
  }
  tops.sort();
  return (lines: tops.length, last: tops.isEmpty ? '' : visibleText(buf[tops.last].toString()).trim());
}

// ── [r5] 채널 · HTTP 관찰(DU573 하네스 du1_s071_uxw3c_573_test.dart:158–281 과 같은 꼴 · 기반 채널은 DU581 처럼 'flutter/' 접두 통과) ──
const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';

/// 내 지원 첫 화면이 부르는 읽기 CF(DU573 과 같음) — 빈 목록 응답. 이 밖의 CF 이름은 차단하고 센다.
const _readFns = <String>{'callableGetMyConfirmedReassignmentProposals'};

/// [g8 · 판정175 §6-2 D2 · 명시 예외] S3 여러 업무 지원 시트(W/B/N 각 시험만)의 시간 충돌 확인 읽기 1 종 — 정확 이름 · 지역 · 원 payload 결속 · 빈 응답.
///   multi_apply_confirm_sheet.dart _loadConflicts → schedule_conflict_service.dart :247–:262 _fetchCommitments
///   (statuses = AppStatus.confirmedStatuses = CONFIRMED · CONTRACT_PENDING · limit 200 · uid 를 보내지 않는다 — 서버가 request.auth.uid 로 정한다).
///   화면 계측용 빈 데이터다 — 서버 인증 · 권한 · 실제 충돌 정책 성공을 뜻하지 않는다(조회 실패 경고 대신 무충돌 fixture 가 된다).
typedef _ExtraRead = ({Map<String, Object?> want, Map<String, Object?> reply});
const Map<String, _ExtraRead> _s3ConflictRead = {
  'callableGetMyApplications': (
    want: {'statuses': ['CONFIRMED', 'CONTRACT_PENDING'], 'limit': 200},
    reply: {'applications': <Object?>[]},
  ),
};

/// [g8 D2] 채널 payload 가 원 payload 와 정확히 같은가 — 키 집합 · 값(목록은 순서까지).
bool _samePayload(Object? got, Map<String, Object?> want) {
  if (got is! Map || got.length != want.length) return false;
  for (final e in want.entries) {
    if (!got.containsKey(e.key)) return false;
    final g = got[e.key];
    final w = e.value;
    if (w is List) {
      if (g is! List || g.length != w.length) return false;
      for (var i = 0; i < w.length; i++) {
        if (g[i] != w[i]) return false;
      }
    } else if (g != w) {
      return false;
    }
  }
  return true;
}

/// Firestore 쓰기 연산 — 하나라도 오면 fsw 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널(UserProvider → AuthService · DU573 과 같음).
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'consentr5.fake.auth.';
const _authListeners = ['registerIdTokenListener', 'registerAuthStateListener'];

class _Wire {
  _Wire([this.extra = const {}]);

  /// [g8 D2] 이 시험에만 허용하는 읽기(기본 빈 값 = 지금과 같음) · 그 호출 수.
  final Map<String, _ExtraRead> extra;
  final extraHits = <String, int>{};
  final unexpected = <String>[];
  final blocked = <String>[];
  final fsWrites = <String>[];
  final fsOther = <String>[];
  final auth = <String>[];
  final harness = <String>[];
  final framework = <String, int>{};
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
    if (channel.startsWith('flutter/')) {
      framework.update(channel, (x) => x + 1, ifAbsent: () => 1);
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
      final x = extra[fn];
      if (x != null && region == 'asia-northeast3') {
        // [g8 D2] 허용 읽기 — 원 payload 와 정확히 같을 때만 빈 응답 · 다르면 지금처럼 차단(blocked).
        final p = args['parameters'];
        if (!_samePayload(p, x.want)) {
          blocked.add('fn $fn@$region payload=$p');
          return codec.encodeMessage(<Object?>['not-found', 'consentr5-blocked', <String, Object?>{'code': 'not-found'}]);
        }
        extraHits[fn] = (extraHits[fn] ?? 0) + 1;
        return codec.encodeMessage(<Object?>[x.reply]);
      }
      if (region != 'asia-northeast3' || !_readFns.contains(fn)) {
        blocked.add('fn $fn@$region');
        return codec.encodeMessage(<Object?>['not-found', 'consentr5-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      _hit(fn);
      return codec.encodeMessage(<Object?>[<String, Object?>{'proposals': const <Object?>[]}]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['internal', 'consentr5-harness', null]);
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
      return codec.encodeMessage(<Object?>['consentr5-blocked', '$op 차단', null]);
    } catch (e) {
      harness.add('fs $op $e');
      return null;
    }
  }
}

/// 외부 HTTP 차단 — 클라이언트 객체 생성은 허용하고 센다 · 실제 요청은 기록하고 실패(DU573 과 같음).
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
    throw const SocketException('CONSENT-R5 관측 — 외부 HTTP 차단');
  }
}

/// [r5] 시험마다 관찰을 켜고, 끝에 허용 밖 CF · Firestore 쓰기 · 허용 밖 채널 · HTTP 요청 · 하네스 오류가 0 인지 본다(실패면 그 시험 실패).
void _guard(WidgetTester t, {Map<String, _ExtraRead> extraReads = const {}}) {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final wire = _Wire(extraReads);
  final net = _NoHttp();
  final prevAll = m.allMessagesHandler;
  final prevHttp = HttpOverrides.current;
  m.allMessagesHandler = (channel, handler, message) => wire.route(m, channel, handler, message);
  HttpOverrides.global = net;
  addTearDown(() {
    m.allMessagesHandler = prevAll;
    HttpOverrides.global = prevHttp;
  });
  final tok = t.testDescription;
  // 나중에 등록한 tearDown 이 먼저 돈다 — 복원 전에 센다.
  addTearDown(() {
    // ignore: avoid_print
    print('CONSENT-R5 wire [$tok] cf=${wire.calls} cfx=${wire.blocked.length} fsw=${wire.fsWrites.length} fso=${wire.fsOther.length} '
        'unexpected=${wire.unexpected.length} http=${net.tries.length} hcl=${net.clients} auth=${wire.auth.length} '
        'fw=${wire.framework.length} harness=${wire.harness.length} extra=${wire.extraHits}');
    expect([...wire.blocked, ...wire.fsWrites.map((x) => 'fsw $x'), ...wire.unexpected, ...wire.harness, ...net.tries], isEmpty,
        reason: '[$tok] 예상 밖 접촉(허용 밖 CF · Firestore 쓰기 · 허용 밖 채널 · 하네스 오류 · HTTP 요청)');
    if (extraReads.isNotEmpty) {
      // [g8 · 판정175 D2] 이 시험에만 허용한 읽기는 정확히 1 회씩 · 다른 허용 읽기(_readFns) 호출 0 — 그 밖 CF 는 위 차단 단언 그대로.
      expect(wire.extraHits, {for (final k in extraReads.keys) k: 1}, reason: '[$tok] 허용 읽기 정확 1 회 ${wire.extraHits}');
      expect(wire.calls, isEmpty, reason: '[$tok] 다른 허용 읽기 0 ${wire.calls}');
    }
  });
}

/// DU573 과 같은 글꼴(FlutterTest 포함 NotoSansKR · MaterialIcons) — 실제 한글 폭으로 잰다.
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

// ── [r5 · A4 · DU581 r2 `_bringBuilt` 형태] 지연 생성(ListView 등) 대비 — 안 만들어졌을 때만 세로 목록을 끌어 넣는다(누르기 아님 · 단언 없음) ──
bool _visMatch(Widget w, bool Function(String s) m) {
  if (w is! Text) return false;
  final s = w.data ?? w.textSpan?.toPlainText();
  return s != null && m(visibleText(s));
}

Finder _vt(String text) => find.byWidgetPredicate((w) => _visMatch(w, (s) => s == text), skipOffstage: false);
Finder _vtc(String part) => find.byWidgetPredicate((w) => _visMatch(w, (s) => s.contains(part)), skipOffstage: false);

Future<void> _bringBuilt(WidgetTester t, Finder want) async {
  if (want.evaluate().isNotEmpty) return;
  final sc = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down, skipOffstage: false);
  if (sc.evaluate().isEmpty) return;
  await t.scrollUntilVisible(want.first, 120, scrollable: sc.last, maxScrolls: 40);
  await t.pump(const Duration(milliseconds: 50));
}

/// 내 지원 목록 단추 — 만들어 넣고 · 보이게 하고 · 누른다(옛 find.text 직접 탭 대체 · 같은 단추).
Future<void> _bringTap(WidgetTester t, String label) async {
  final want = _vt(label);
  await _bringBuilt(t, want);
  expect(want, findsWidgets, reason: '목록 단추 $label');
  await t.ensureVisible(want.first);
  await t.pump();
  await t.tap(want.first);
}

/// [r5 g1] 공고 상세 `_acceptDialogActions`(job_posting_screen · DU575)와 같은 식 — 기본 배율이면 [취소, 주 행동] ·
///   큰 글자(배율 > 1.0)면 세로 전체 폭으로 쌓고 주 행동을 위에(MIRROR-BIND 가 원문의 같은 두 줄을 확인한다).
List<Widget> _mirrorAcceptActions(BuildContext context, {required Widget cancel, required Widget accept}) {
  if (MediaQuery.textScalerOf(context).scale(1) <= 1.0) return [cancel, accept];
  return [
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [accept, SizedBox(height: ResponsiveHelper.spacing(context, 8)), cancel],
    ),
  ];
}

// ── [r5] 캡처 · 채움 색 기록 ──
final _shotKey = GlobalKey();

String _hex(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0');

Future<void> _shot(WidgetTester t, String surface, _Cond c, String id, String state) async {
  // ignore: avoid_print
  print('CONSENT-R5 shot ${surface}_${c.id}_$id state=$state');
  await vqCapture(t, _shotKey, '${surface}_${c.id}_$id', conditions: {
    'viewport': '${c.size.width.toInt()}x${c.size.height.toInt()}', 'textScaler': c.scale, 'run': vqRun,
    'surface': surface, 'state': state,
  });
}

// ── [r5] DU571 r2 측정 블록(work/du571-uxw3b-limit-notice/r2/new/du1_s065_uxw3b_limit_notice_test.dart :138–:144 · :178–:202 바이트 그대로) ──
/// [a] 가 [b] **안**에 있는가(0.5px 허용).
bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

final String _wj = String.fromCharCode(0x2060);
final String _zw = String.fromCharCode(0x200B);

bool _gap(String ch) => ch == ' ' || ch == '\n' || ch == '\t' || ch == _zw;

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

const _zeroWidth = {0x2060, 0x200B, 0x200C, 0x200D, 0xFEFF};

/// [C-R4-5] 문단의 **끝 글자 상자**가 화면 안 · 가장 가까운 스크롤 영역 안에 있는가.
///   먼저 문단 끝이 보이도록(alignment 1.0) 스크롤한 뒤 잰다. 보이는 글자가 아닌 낱말 묶음 문자는 건너뛴다.
Future<void> _expectEndGlyphVisible(WidgetTester t, Finder text, String why) async {
  await Scrollable.ensureVisible(t.element(text), alignment: 1.0);
  await _settle(t, 6);
  // [g6 · 판정173 §5 :57] 같은 정합 — 끝 글자 측정도 그 Text 아래 정확한 RichText 1 개의 RenderParagraph 로(좌표 원점 = 그 문단).
  final rich = find.descendant(of: text, matching: find.byType(RichText));
  expect(rich, findsOneWidget, reason: '$why Text 아래 RichText 정확히 1');
  final rp = t.renderObject<RenderParagraph>(rich);
  final raw = rp.text.toPlainText();
  var i = raw.length - 1;
  while (i >= 0 && (raw[i].trim().isEmpty || _zeroWidth.contains(raw.codeUnitAt(i)))) {
    i--;
  }
  expect(i, greaterThanOrEqualTo(0), reason: '$why 끝 글자 없음');
  final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
  expect(boxes, isNotEmpty, reason: '$why 끝 글자 상자 없음(잘림)');
  final b = boxes.last.toRect();
  final g = Rect.fromPoints(rp.localToGlobal(b.topLeft), rp.localToGlobal(b.bottomRight));
  final view = Offset.zero & (t.view.physicalSize / t.view.devicePixelRatio);
  // [r5 · 판정 consent1121 §4 F-R4D-7] r4d 의 조상 clip 종류 판정을 버리고 DU571 r2 측정 블록으로 본다 —
  //   전문 = max 세로 + tight 가로 · 공차 0.5(_fullShown) · 끝 글자 상자가 화면 ∩ 조상 스크롤 칸(_area) 안(_inside).
  //   max 선택상자만으로 잉크/모든 조상 clip 무결을 주장하지 않는다 — W/B/N 원 PNG · 3칸 합성 직접 열람으로 함께 판정한다.
  expect(_fullShown(rp, rp.size), isTrue, reason: '$why 전문(말줄임 · 문단 상자 밖 0)');
  final area = _area(text, view);
  expect(area.isEmpty, isFalse, reason: '$why 보이는 칸이 비었다');
  expect(_inside(g, area), isTrue, reason: '$why 끝 글자 $g 가 보이는 칸 $area 밖');
  // ignore: avoid_print
  print('CONSENT-R5 $why endGlyph="${raw[i]}" rect=$g area=$area');
}

// ── [g7 · 판정174 §6 ②] 문단 읽기 도달 — du1(g5/g6 판 du1_consent_sheet_render_test.dart :94–:113 _lineRects · :218–:288 도달 증명)의 같은 증명을 이 하네스 공통 계약에 재사용 ──
/// [g7] 문단의 줄 상자(문단 좌표) — 보이는 글자마다 max 상자(줄 배치 세로 · tight 가로)를 같은 줄끼리 합친다(공백 · 낱말 묶음 문자 제외). du1 :94–:113 과 같은 식.
List<Rect> _lineRects(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final out = <Rect>[];
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == _wj || _gap(ch)) continue;
    for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1), boxHeightStyle: ui.BoxHeightStyle.max)) {
      final r = b.toRect();
      final k = out.indexWhere((x) => (x.top - r.top).abs() <= 0.5);
      if (k < 0) {
        out.add(r);
      } else {
        out[k] = out[k].expandToInclude(r);
      }
    }
  }
  out.sort((a, b) => a.top.compareTo(b.top));
  return out;
}

/// [g7] 문단 하나를 처음부터 끝까지 읽을 수 있는가 — `ensureVisible` 뒤 중앙 한 점 hit 대신(판정174 §6 ② · 윗끝 hit + 끝 글자만의 대체는 미채택).
///   같은 Text 아래 정확한 RichText 1 개 · 실제 본문 scroll owner = 가장 가까운 세로 Scrollable · 화면 ∩ 조상 스크롤 칸(_area) · 공차 0.5.
///   매 줄이 적어도 한 프레임에 온전히 · 가로 잘림 0 · 첫/끝/중간 줄 누락 0 · 문단 좌표 가시 구간 0..h 빈틈 0 · 문단 ≤ 칸이면 문단 전체 한 프레임.
///   한 프레임에 다 못 보면 그 owner 를 실제 drag(위 끝이 안 보였으면 먼저 손가락 아래 · 그다음 손가락 위)하며 이동마다 다시 재고, 실제로 움직였음을 단언.
Future<void> _expectReadReach(WidgetTester t, Finder text, String why) async {
  final rich = find.descendant(of: text, matching: find.byType(RichText));
  expect(rich, findsOneWidget, reason: '$why Text 아래 RichText 정확히 1');
  final rp = t.renderObject<RenderParagraph>(rich);
  final view = Offset.zero & (t.view.physicalSize / t.view.devicePixelRatio);
  final lines = _lineRects(rp);
  expect(lines, isNotEmpty, reason: '$why 줄 상자');
  final h = rp.size.height;
  final ownerF = find.ancestor(of: text, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down));
  final pos = ownerF.evaluate().isEmpty ? null : t.state<ScrollableState>(ownerF.first).position;
  final seen = List<bool>.filled(lines.length, false);
  final spans = <(double, double)>[];
  var wholeSeen = false;
  var areaH = -1.0;
  void read(String tag) {
    final a = _area(text, view);
    expect(a.isEmpty, isFalse, reason: '$why $tag 보이는 칸이 비었다');
    if (areaH < 0) areaH = a.height;
    final o = rp.localToGlobal(Offset.zero);
    final vTop = (a.top - o.dy).clamp(0.0, h).toDouble();
    final vBot = (a.bottom - o.dy).clamp(0.0, h).toDouble();
    if (vBot > vTop) spans.add((vTop, vBot));
    for (var i = 0; i < lines.length; i++) {
      final g = lines[i].shift(o);
      expect(g.left >= a.left - 0.5 && g.right <= a.right + 0.5, isTrue,
          reason: '$why $tag 줄 ${i + 1} 가로 잘림 $g / $a — 제품 접근성 실패');
      if (g.top >= a.top - 0.5 && g.bottom <= a.bottom + 0.5) seen[i] = true;
    }
    if (_inside(o & rp.size, a)) wholeSeen = true;
  }

  double coveredTo() {
    final ss = [...spans]..sort((x, y) => x.$1.compareTo(y.$1));
    var cov = 0.0;
    for (final s in ss) {
      if (s.$1 > cov + 0.5) break;
      if (s.$2 > cov) cov = s.$2;
    }
    return cov;
  }

  bool topSeen() => spans.any((s) => s.$1 <= 0.5);
  read('start');
  final needWhole = h <= areaH + 0.5;
  bool done() => seen.every((x) => x) && coveredTo() >= h - 0.5 && (!needWhole || wholeSeen);
  final step = needWhole ? ((areaH - h) / 2).clamp(1.0, 8.0).toDouble() : 8.0;
  var moves = 0;
  if (!done()) {
    expect(pos, isNotNull, reason: '$why 한 프레임에 다 안 보이는데 끌 세로 scroll owner 가 없다 — 제품 접근성 실패');
    final p = pos!;
    final p0 = p.pixels;
    for (final dir in const [1.0, -1.0]) {
      if (done() || (dir > 0 && topSeen())) continue;
      final g = await t.startGesture(_area(text, view).center);
      await g.moveBy(Offset(0, 24 * dir)); // 끌기 인식(터치 슬롭 넘김)
      await t.pump(const Duration(milliseconds: 16));
      read(dir > 0 ? 'up0' : 'down0');
      while (moves < 600 && (dir > 0 ? (p.pixels > 0 && !topSeen()) : (p.pixels < p.maxScrollExtent && !done()))) {
        await g.moveBy(Offset(0, step * dir));
        await t.pump(const Duration(milliseconds: 16));
        moves++;
        read(dir > 0 ? 'up$moves' : 'down$moves');
      }
      await t.pump(const Duration(milliseconds: 150)); // 놓기 전 멈춤 — 튕김 없이 놓는다
      await g.up();
      await _settle(t, 6);
    }
    expect((p.pixels - p0).abs() > 0.5, isTrue, reason: '$why 같은 scroll owner 가 실제로 끌려 움직였다');
  }
  // ignore: avoid_print
  print('CONSENT-R7 $why read h=${h.toStringAsFixed(1)} area=${areaH.toStringAsFixed(1)} lines=${lines.length} '
      'seen=${seen.where((x) => x).length} whole=$wholeSeen cov=${coveredTo().toStringAsFixed(1)} frames=${spans.length} '
      'moves=$moves step=${step.toStringAsFixed(1)} offset=${pos?.pixels.toStringAsFixed(1)} max=${pos?.maxScrollExtent.toStringAsFixed(1)}');
  final miss = [for (var i = 0; i < lines.length; i++) if (!seen[i]) i + 1];
  expect(miss, isEmpty, reason: '$why 첫 줄 · 마지막 줄 · 중간 모든 줄이 적어도 한 번 온전히 보인다(안 보인 줄 $miss / ${lines.length}) — 제품 접근성 실패');
  if (needWhole) {
    expect(wholeSeen, isTrue, reason: '$why 문단(${h.toStringAsFixed(1)})이 칸(${areaH.toStringAsFixed(1)})에 들어가면 한 프레임에 문단 전체가 온전히 보인다');
  }
  expect(coveredTo() >= h - 0.5, isTrue,
      reason: '$why 문단 좌표 가시 구간이 0-${h.toStringAsFixed(1)} 를 빈틈 없이 잇는다(끝 ${coveredTo().toStringAsFixed(1)} · 프레임 ${spans.length})');
}

/// [g8 · 판정175 §6-2 D1 · A8] 받는 자리와 실제 채움을 **같은 버튼**에서 잰다.
///   ButtonStyleButton 조상이 있으면 지금과 같음(상자 = 그 버튼 render 상자 · 머티리얼 탭 패딩 포함 · 채움 = 그 안 첫 Material.color).
///   없을 때만 라벨을 감싼 가장 가까운 활성 InkWell(onTap ≠ null)과, 그것을 소유한 공용 CommonWidgets.primaryButton 꼴
///   (common_widgets.dart :73–:84 · Container(BoxDecoration) → Material(transparent) → InkWell)에 결속한다 — 상자 = 그 InkWell · 채움 = Container 장식 색.
///   임의의 큰 조상 · 다른 버튼을 잡지 않도록 직계 소유 · 유일을 단언한다.
({Rect rect, Color? fill, String kind}) _tapTarget(WidgetTester t, Finder label) {
  final btn = find.ancestor(of: label, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
  if (btn.evaluate().isNotEmpty) {
    final mat = find.descendant(of: btn.first, matching: find.byType(Material)).evaluate();
    return (rect: t.getRect(btn.first), fill: mat.isEmpty ? null : (mat.first.widget as Material).color, kind: 'ButtonStyleButton');
  }
  final ink = find.ancestor(of: label, matching: find.byWidgetPredicate((w) => w is InkResponse && w.onTap != null));
  expect(ink, findsWidgets, reason: '버튼 상자 없음(ButtonStyleButton · onTap 있는 InkWell 둘 다 0)');
  final inkF = ink.first;
  final matF = find.ancestor(of: inkF, matching: find.byType(Material)).first;
  final boxF = find.ancestor(of: matF, matching: find.byType(Container)).first;
  final mat = t.widget<Material>(matF);
  final box = t.widget<Container>(boxF);
  expect(mat.child, same(t.widget(inkF)), reason: 'CTA Material 의 자식 = 그 InkWell');
  expect(box.child, same(mat), reason: 'CTA Container 의 자식 = 그 Material');
  expect(mat.color, Colors.transparent, reason: 'CTA Material 은 투명 — 채움은 Container 장식');
  expect(box.decoration, isA<BoxDecoration>(), reason: 'CTA 채움 소유 = Container 장식');
  expect(find.descendant(of: boxF, matching: find.byWidgetPredicate((w) => w is InkResponse && w.onTap != null)), findsOneWidget,
      reason: 'CTA 상자 안 활성 InkWell 정확히 1');
  return (rect: t.getRect(inkF), fill: (box.decoration as BoxDecoration).color, kind: 'InkWell(primaryButton)');
}

/// [C-R4-5] 버튼의 터치 영역 — 글자가 아니라 버튼 render 상자(머티리얼 탭 패딩 포함)를 잰다. [g8] 결속 규칙은 _tapTarget.
Rect _buttonRect(WidgetTester t, Finder label) => _tapTarget(t, label).rect;

/// 카드·자세히·CTA 계약 — 모든 면 공통.
Future<void> _consentContract(
  WidgetTester t, {
  required String surface,
  required _Cond c,
  required List<String> parts,
  required List<String> details,
  required String cta,
  required List<String> sink,
  int Function()? submitCount,
}) async {
  for (var i = 0; i < parts.length; i++) {
    await _bringBuilt(t, _vtc(parts[i])); // [r5 · A4] 지연 생성 대비
    final f = findVisibleTextContaining(parts[i]);
    expect(f, findsWidgets, reason: '$surface ${c.id} 문단 ${i + 1}');
    await t.ensureVisible(f.first);
    await t.pump();
    // [g7 · 판정174 §6 ②] ensureVisible 뒤 중앙 한 점 hit → 모든 줄 도달 + 문단 좌표 가시 구간 연속(_expectReadReach · du1 증명 재사용).
    await _expectReadReach(t, f.first, '$surface ${c.id} 문단 ${i + 1}');
    await _expectEndGlyphVisible(t, f.first, '$surface ${c.id} 문단 ${i + 1}');
    final li = _lineInfo(t, f.first);
    // ignore: avoid_print
    print('CONSENT-R4b $surface ${c.id} part${i + 1} lines=${li.lines} last="${li.last}"');
  }
  await _shot(t, surface, c, '1body', 'card-last-paragraph-end');
  await _bringBuilt(t, find.byKey(const ValueKey('documentAccessConsentDetailsToggle'), skipOffstage: false));
  final toggle = find.byKey(const ValueKey('documentAccessConsentDetailsToggle'));
  expect(toggle, findsOneWidget, reason: '$surface 자세히');
  await t.ensureVisible(toggle);
  await t.pump();
  expect(toggle.hitTestable(), findsOneWidget, reason: '$surface ${c.id} 자세히는 동의 전에 누를 수 있다');
  final ts = t.getSize(toggle);
  expect(ts.height >= 48 - 0.01 && ts.width >= 48 - 0.01, isTrue, reason: '$surface ${c.id} 자세히 터치 $ts');
  final before = submitCount?.call() ?? 0;
  final canPop = _nav.currentState?.canPop();
  await t.tap(toggle);
  await t.pump();
  for (final d in details) {
    await _bringBuilt(t, _vtc(d)); // [r5 · A4]
    final f = findVisibleTextContaining(d);
    expect(f, findsOneWidget, reason: '$surface 상세: $d');
    await t.ensureVisible(f);
    await t.pump();
  }
  // 상세 마지막 문단의 끝 글자도 화면·스크롤 영역 안에 닿아야 한다.
  await _expectEndGlyphVisible(t, findVisibleTextContaining(details.last), '$surface ${c.id} 상세 끝');
  await _shot(t, surface, c, '2detail', 'details-open-end');
  await t.ensureVisible(toggle);
  await t.pump();
  await t.tap(toggle);
  await t.pump();
  expect(findVisibleTextContaining(details.first), findsNothing, reason: '$surface 닫힘');
  expect(submitCount?.call() ?? 0, before, reason: '$surface 여닫기 = 제출 0');
  expect(_nav.currentState?.canPop(), canPop, reason: '$surface 여닫기 = 라우트 변화 0');
  await _bringBuilt(t, _vt(cta)); // [r5 · A4]
  final ctaF = findVisibleText(cta);
  expect(ctaF, findsWidgets, reason: '$surface CTA $cta');
  await t.ensureVisible(ctaF.last);
  await t.pump();
  expect(ctaF.last.hitTestable(), findsOneWidget, reason: '$surface ${c.id} CTA 도달');
  final cr = _buttonRect(t, ctaF.last);
  expect(cr.height >= 48 - 0.01 && cr.width >= 48 - 0.01, isTrue, reason: '$surface ${c.id} CTA 터치 영역 $cr');
  final view = Offset.zero & (t.view.physicalSize / t.view.devicePixelRatio);
  expect(view.inflate(0.01).contains(cr.topLeft) && view.inflate(0.01).contains(cr.bottomRight), isTrue,
      reason: '$surface ${c.id} CTA 상자 $cr 화면 밖');
  // [r5 · A8 → g8 · 판정175 A8] 동의 행동 단추의 실제 채움 — 같은 CTA 결속(_tapTarget)의 채움 소유 요소
  //   (ButtonStyleButton = 그 안 Material.color · primaryButton = Container 장식 색). brand/success 비교값은 따로 적는다(기대값 대입 0).
  final ctaT = _tapTarget(t, ctaF.last);
  // ignore: avoid_print
  print('CONSENT-R5 $surface ${c.id} A8 ctaFill=${_hex(ctaT.fill)} kind=${ctaT.kind} '
      'brand=${_hex(AppColors.brand)} success=${_hex(AppColors.success)}');
  await _shot(t, surface, c, '3cta', 'details-closed-cta-reached');
  final cancel = findVisibleText('취소');
  if (cancel.evaluate().isNotEmpty) {
    await t.ensureVisible(cancel.last);
    await t.pump();
    expect(cancel.last.hitTestable(), findsOneWidget, reason: '$surface ${c.id} 취소 도달');
    // ignore: avoid_print
    print('CONSENT-R4b $surface ${c.id} cancelRect=${_buttonRect(t, cancel.last)} ctaRect=$cr');
  }
  expect(sink, isEmpty, reason: '$surface ${c.id} 넘침: ${sink.join(' | ')}');
}

Widget _app(Widget home, _Cond c) => RepaintBoundary(
    key: _shotKey, // [r5] 캡처 경계(대화창 · 시트 포함)
    child: MaterialApp(
      navigatorKey: _nav,
      debugShowCheckedModeBanner: false,
      theme: RoleTheme.workerTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ko', 'KR')],
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.scale)), child: child!),
      home: home,
    ));

void _view(WidgetTester t, _Cond c) {
  t.view.physicalSize = c.size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

// ── fixture ─────────────────────────────────────────────────────────────
/// 고정 시계 — 실제 현재 시각을 읽지 않는다(화면 문구의 날짜만 쓴다).
final DateTime _today = FormatHelper.toKstDate(DateTime.utc(2026, 12, 1, 3));

WorkDetailModel _work() => WorkDetailModel(
      wdId: 'wd1', workType: '냉장 분류 및 출고 검수', workTypeIcon: 'box',
      workTypeColor: '#000000', workTypeBackgroundColor: '#FFFFFF',
      wage: 53000, wageType: 'daily', requiredCount: 2, startTime: '18:00', endTime: '22:30');

DateTime _kstMid(int y, int m, int d) => DateTime.utc(y, m, d).subtract(const Duration(hours: 9));

TOModel _longTo() => TOModel(
      id: 'toLong', businessId: 'bizA', businessName: _biz, type: 'contract', title: '장기 모집',
      creatorUID: 'admin1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0,
      workDetails: const [], workDays: const ['토'], contractPeriodType: 'custom',
      rangeStart: _kstMid(2027, 1, 9), rangeEnd: _kstMid(2027, 3, 27),
      totalRequired: 5, totalConfirmed: 0, totalPending: 0, isPublished: true, publishMode: 'immediate',
      createdAt: DateTime(2026, 9, 1), statusUpdatedAt: DateTime(2026, 9, 1));

TOModel _flexTo() => TOModel(
      id: 'to1', businessId: 'biz1', businessName: _biz, type: 'flex', title: '단기 모집',
      creatorUID: 'admin1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0,
      workDetails: const [], totalRequired: 2, totalConfirmed: 0, totalPending: 0, isPublished: true,
      publishMode: 'immediate', createdAt: DateTime(2026, 11, 1), statusUpdatedAt: DateTime(2026, 11, 1));

WorkDetailData _wdData() => WorkDetailData(
    wdId: 'wd1', workType: 'QA 분류', workTypeIcon: 'box', workTypeColor: '#000000',
    workTypeBackgroundColor: '#FFFFFF', wage: 13000, wageType: 'hourly', requiredCount: 2,
    startTime: '15:30', endTime: '18:30', order: 0);

SlotModel _slot() => SlotModel(id: 's1', toId: 'to1', date: DateTime(2026, 12, 8), workDetails: [_wdData()],
    status: SlotStatus.open, createdAt: DateTime(2026, 11, 1));

final DateTime _invDay = FormatHelper.toKstDate(DateTime.utc(2026, 12, 20));
final DateTime _invStart = FormatHelper.kstWallClockInstant(_invDay, '20:00')!;

ApplicationModel _invite(InviteAcceptReadiness r, {bool consented = false, bool offer = false}) =>
    ApplicationModel(
      id: 'inv1', toId: 'to1', slotId: 'slot1', wdId: 'wd-1', uid: _kUid, businessId: 'biz1',
      businessName: _biz, toTitle: 'QA 공고', status: AppStatus.invited, selectedWorkType: 'QA 분류',
      startTime: '20:00', endTime: '22:00', wage: 13000, workDate: _invDay,
      appliedAt: _invDay.subtract(const Duration(days: 1)), inviteExpiresAt: _invStart,
      workInstanceCapacityState: InviteCapacityState.available, inviteAcceptReadiness: r,
      documentAccessConsentGiven: consented,
      documentAccessConsentVersion: consented ? DocumentAccessConsent.inviteVersion : null,
      // [CONSENT-R4b] S5o — 다른 업무 제안(원 지원은 목록에 없다 → 비교 줄은 '모름' 분기).
      offerKind: offer ? 'ALTERNATIVE_WORK' : null,
      offerId: offer ? 'offer1' : null,
      sourceApplicationId: offer ? 'src1' : null);

MyApplicationsReads _reads(List<ApplicationModel> apps) => MyApplicationsReads(
      myApplicationsPaged: ({required String uid, required int pageSize, String? startAfterDocId}) async =>
          {'items': apps, 'lastDocId': null, 'hasMore': false},
      toOrFailure: (id) async => (to: _flexTo(), failed: false),
      contractsByWorker: (uid) async => const <EmploymentContractModel>[],
      autoExpirePending: (uid) async {},
      monthlyAttendances: ({required String userId, required int year, required int month}) async =>
          const <AttendanceModel>[],
      reviewById: (key) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
    );

Future<void> _pumpMyApps(WidgetTester t, ApplicationModel app, _Cond c) async {
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: _app(
        MyApplicationsScreen(
            reads: _reads([app]), clock: () => _invStart.subtract(const Duration(hours: 3)), initialTabIndex: 6),
        c),
  ));
  await _settle(t, 25);
}

String _src(String p) => File(p).readAsStringSync();

void main() {
  setUpAll(() async {
    // [r5] 초기화도 관찰 안에서 — CF 0 · 예상 밖 채널 0 · HTTP 0(DU573 setUpAll 과 같은 꼴).
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final wire = _Wire();
    final net = _NoHttp();
    final prevAll = m.allMessagesHandler;
    final prevHttp = HttpOverrides.current;
    m.allMessagesHandler = (channel, handler, message) => wire.route(m, channel, handler, message);
    HttpOverrides.global = net;
    try {
      await initializeDateFormatting('ko_KR', null);
      FirebasePlatform.instance = _FakeCore();
      await Firebase.initializeApp();
      await _loadFonts();
      const codec = StandardMessageCodec();
      for (final name in _authListeners) {
        m.setMockMessageHandler('$_authBase$name', (_) async => codec.encodeMessage(<Object?>['$_authFake$name']));
        m.setMockMethodCallHandler(MethodChannel('$_authFake$name'), (_) async => null);
      }
    } finally {
      m.allMessagesHandler = prevAll;
      HttpOverrides.global = prevHttp;
    }
    // ignore: avoid_print
    print('CONSENT-R5 setup cf=${wire.calls.length + wire.blocked.length} unexpected=${wire.unexpected.length} http=${net.tries.length}');
    expect(wire.calls.length + wire.blocked.length == 0 && wire.unexpected.isEmpty && net.tries.isEmpty, isTrue,
        reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  final gParts = DocumentAccessConsent.partsFor(_biz);
  final gDetails = DocumentAccessConsent.detailsFor(_biz);
  final iParts = DocumentAccessConsent.invitePartsFor(_biz);
  final iDetails = DocumentAccessConsent.inviteDetailsFor(_biz);

  for (final c in _conds) {
    testWidgets('S1 지원 확인 시트 ${c.id}', (t) async {
      final sink = _overflowSink();
      _guard(t); // [r5] 채널 · HTTP 관찰
      _view(t, c);
      bool? result;
      await t.pumpWidget(_app(Scaffold(body: Builder(builder: (ctx) => Center(child: ElevatedButton(
          onPressed: () async => result = await ApplyConfirmDialog.show(
              context: ctx, businessName: _biz, work: _work(), isLongTerm: false,
              workDate: _today.add(const Duration(days: 2))),
          child: const Text('열기'))))), c));
      await t.tap(find.text('열기'));
      await _settle(t);
      await _consentContract(t, surface: 'S1', c: c, parts: gParts, details: gDetails, cta: '지원하기', sink: sink);
      await t.tap(find.widgetWithText(OutlinedButton, '취소'));
      await _settle(t);
      expect(result, isFalse, reason: 'S1 취소 = 미전송');
    });

    testWidgets('S2 장기 지원 시트 ${c.id}', (t) async {
      final sink = _overflowSink();
      _guard(t); // [r5] 채널 · HTTP 관찰
      _view(t, c);
      var closed = false;
      Object? sheetResult = 'unset';
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => _P(),
        child: _app(Scaffold(body: Builder(builder: (ctx) => Center(child: ElevatedButton(
            onPressed: () async {
              sheetResult = await DialogHelper.showSheet<Object?>(ctx, isScrollControlled: true,
                  builder: (_) => LongTermApplySheet(
                      to: _longTo(), selectedWorks: [_work()], businessName: _biz,
                      myApplications: const [], commitmentsSource: () async => <ApplicationModel>[]));
              closed = true;
            },
            child: const Text('열기'))))), c),
      ));
      await t.tap(find.text('열기'));
      await _settle(t, 30);
      await _consentContract(t, surface: 'S2', c: c, parts: gParts, details: gDetails,
          cta: '이 조건으로 지원하기', sink: sink);
      // [r4c · F-R4B-5] 취소 = 실제로 닫힘 · 결과 null(지원 요청 0 — 시트는 결과 없이 닫힌다).
      //   이 시트의 취소 수단은 머리의 닫기 버튼이다(A longterm_apply_sheet.dart:626–632 · tooltip '닫기' · 48).
      final cancel = find.byTooltip('닫기');
      expect(cancel, findsOneWidget, reason: 'S2 닫기 버튼');
      // [g7 · 판정174 §6 ①] M3 IconButton 의 Tooltip 은 보이는 상자(최소 40) 안쪽 — 받는 자리(48)는 그 버튼(ButtonStyleButton)의 _InputPadding 상자다.
      //   Tooltip → 그 버튼 조상 하나의 결속을 확인하고, CTA 와 같은 _buttonRect(버튼 render 상자 · 머티리얼 탭 패딩 포함)로 잰다 · 48 · 공차 0.01 그대로.
      expect(find.ancestor(of: cancel, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)), findsOneWidget,
          reason: 'S2 닫기 Tooltip 의 버튼 조상 하나');
      final cs = _buttonRect(t, cancel).size;
      expect(cs.height >= 48 - 0.01 && cs.width >= 48 - 0.01, isTrue, reason: 'S2 닫기 48 $cs');
      await t.ensureVisible(cancel);
      expect(cancel.hitTestable(), findsOneWidget, reason: 'S2 닫기 누를 수 있음');
      await t.tap(cancel);
      await _settle(t, 20);
      expect(closed, isTrue, reason: 'S2 취소 = 시트 닫힘');
      expect(sheetResult, isNull, reason: 'S2 취소 = 결과 없음(미전송)');
      expect(find.byType(LongTermApplySheet), findsNothing);
    });

    testWidgets('S3 여러 업무 지원 시트 ${c.id}', (t) async {
      final sink = _overflowSink();
      _guard(t, extraReads: _s3ConflictRead); // [r5] 채널 · HTTP 관찰 · [g8 · 판정175 D2] S3 만 충돌 확인 읽기 1 종
      _view(t, c);
      await t.pumpWidget(_app(const Scaffold(body: Text('공고 상세')), c));
      unawaited(_nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => Scaffold(
          body: MultiApplyConfirmSheet(items: [(slot: _slot(), work: _wdData())], to: _flexTo(),
              myApplications: const [])))));
      await _settle(t);
      await _consentContract(t, surface: 'S3', c: c, parts: gParts, details: gDetails, cta: '지원하기', sink: sink);
      await t.tap(find.widgetWithText(TextButton, '취소'));
      await _settle(t);
      expect(find.text('공고 상세'), findsOneWidget, reason: 'S3 취소 = 미전송으로 닫힘');
    });

    testWidgets('S4 동의 전용 창(초대) ${c.id}', (t) async {
      final sink = _overflowSink();
      _guard(t); // [r5] 채널 · HTTP 관찰
      _view(t, c);
      await _pumpMyApps(t, _invite(InviteAcceptReadiness.consentRequired), c);
      await _bringTap(t, '서류 열람 동의'); // [r5 · A4] 목록 지연 생성 대비
      await _settle(t);
      expect(findVisibleTextContaining('동의만으로 근무가 확정되지는 않아요'), findsOneWidget, reason: 'S4 위 안내');
      await _consentContract(t, surface: 'S4', c: c, parts: iParts, details: iDetails, cta: '동의하기', sink: sink);
      await t.tap(find.text('취소'));
      await _settle(t);
      expect(find.text('동의하기'), findsNothing, reason: 'S4 취소 = 미전송으로 닫힘');
    });

    testWidgets('S5 초대 수락 창 ${c.id}', (t) async {
      final sink = _overflowSink();
      _guard(t); // [r5] 채널 · HTTP 관찰
      _view(t, c);
      await _pumpMyApps(t, _invite(InviteAcceptReadiness.ready, consented: true), c);
      await _bringTap(t, '수락하기'); // [r5 · A4]
      await _settle(t);
      await _consentContract(t, surface: 'S5', c: c, parts: iParts, details: iDetails,
          cta: '동의하고 초대 수락', sink: sink);
      await t.tap(find.text('취소'));
      await _settle(t);
      expect(findVisibleText('동의하고 초대 수락'), findsNothing, reason: 'S5 취소 = 미전송');
    });

    testWidgets('S5o 제안 수락 창(실제 화면) ${c.id}', (t) async {
      final sink = _overflowSink();
      _guard(t); // [r5] 채널 · HTTP 관찰
      _view(t, c);
      await _pumpMyApps(t, _invite(InviteAcceptReadiness.ready, consented: true, offer: true), c);
      await _bringTap(t, '제안 조건으로 수락'); // [r5 · A4] S5o 목록 행 버튼 · 지연 생성 대비
      await _settle(t);
      expect(findVisibleTextContaining('다른 업무 제안 수락'), findsWidgets, reason: 'S5o 창 제목');
      await _consentContract(t, surface: 'S5o', c: c, parts: iParts, details: iDetails,
          cta: '동의하고 제안 수락', sink: sink);
      await t.tap(findVisibleText('취소').last);
      await _settle(t);
      expect(findVisibleText('동의하고 제안 수락'), findsNothing, reason: 'S5o 취소 = 미전송');
    });

    for (final offer in [false, true]) {
      // S6(공고 화면 · 초대/제안) — 거울. 원문 결속은 아래 'MIRROR-BIND' 시험. S5o 는 위 실제 셀.
      final label = offer ? '동의하고 제안 수락' : '동의하고 초대 수락';
      final top = offer
          // [r5] 공고 상세 원문(DU573 판 job_posting_screen _acceptInviteFromDetail · 원 업무 이름 없는 fixture)
          ? "수락하면 제안받은 업무로 확정되고, 기존 지원은 '다른 업무로 확정됨'으로 정리돼요.\n이 정리는 노쇼로 기록되지 않아요."
          : '이 근무 초대를 수락할까요?\n확정된 다른 근무와 시간이 겹치면 수락할 수 없어요. 수락이 완료되면 근무가 확정돼요.';
      testWidgets('S6${offer ? 'o' : 'i'} 공고 화면 수락(거울) ${c.id}', (t) async {
        final sink = _overflowSink();
      _guard(t); // [r5] 채널 · HTTP 관찰
        _view(t, c);
        bool? result;
        await t.pumpWidget(_app(Scaffold(body: Builder(builder: (ctx) => Center(child: ElevatedButton(
            onPressed: () async => result = await DialogHelper.showCustom<bool>(ctx,
                title: offer ? '다른 업무 제안 수락' : '초대 수락',
                icon: offer ? Icons.swap_horiz : Icons.check_circle_outline,
                // [r5 g1] 원문 결속(아래 MIRROR-BIND) — DU575 판 공고 상세: 머리 아이콘 grey600 · 주 행동 brand · 큰 글자면 세로 쌓기
                iconColor: AppColors.grey600,
                content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                    children: [KeepWordsText(top), const SizedBox(height: 12), DocumentAccessConsent.inviteCard(_biz)]),
                actions: _mirrorAcceptActions(ctx,
                    cancel: TextButton(onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false), child: const Text('취소')),
                    accept: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
                        onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
                        child: Text(TextLayout.keepWords(label), semanticsLabel: label, textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white))))),
            child: const Text('열기'))))), c));
        await t.tap(find.text('열기'));
        await _settle(t);
        await _consentContract(t, surface: offer ? 'S6o' : 'S6i', c: c, parts: iParts, details: iDetails,
            cta: label, sink: sink);
        await t.tap(find.text('취소'));
        await _settle(t);
        expect(result, isFalse);
      });
    }

    testWidgets('S7 재배치 — INHERIT 실패 → 같은 시트에 카드 · 취소=미전송 · 동의=EXPLICIT ${c.id}', (t) async {
      final sink = _overflowSink();
      _guard(t); // [r5] 채널 · HTTP 관찰
      _view(t, c);
      final calls = <Map<String, dynamic>>[];
      var answer = 'CONSENT_REQUIRED';
      ConfirmedReassignmentService.debugCall = (name, payload) async {
        calls.add(payload);
        if (answer == 'CONSENT_REQUIRED') {
          throw FirebaseFunctionsException(code: 'failed-precondition',
              message: '변경을 수락하려면 서류 열람 동의가 필요합니다.',
              details: {'code': 'CONSENT_REQUIRED', 'reason': 'VERSION_NOT_INHERITABLE'});
        }
        return {'success': true};
      };
      addTearDown(() => ConfirmedReassignmentService.debugCall = null);
      final p = ConfirmedReassignmentProposal.fromMap({
        'proposalId': 'p1', 'status': 'PROPOSED', 'uid': _kUid, 'businessId': 'biz1', 'businessName': _biz,
        'sourceApplicationId': 'a1',
        'sourcePromise': {'wdId': 'wd-1', 'workType': '분류', 'startTime': '09:00', 'endTime': '18:00', 'wage': 12000, 'wageType': 'hourly'},
        'targetPromise': {'wdId': 'wd-2', 'workType': '검수', 'startTime': '09:00', 'endTime': '18:00', 'wage': 12500, 'wageType': 'hourly'},
        'targetToId': 'to1', 'targetSlotId': 's1', 'targetWdId': 'wd-2',
      });
      ReassignmentDecision? decision;
      await t.pumpWidget(_app(Scaffold(body: Builder(builder: (ctx) => Center(child: ElevatedButton(
          onPressed: () async => decision = await ConfirmedReassignmentSheet.decide(ctx, p),
          child: const Text('열기'))))), c));
      await t.tap(find.text('열기'));
      await _settle(t);
      expect(find.byKey(const ValueKey('documentAccessConsentCard')), findsNothing, reason: '첫 화면엔 카드 0');
      await t.ensureVisible(find.text('변경 수락'));
      await t.tap(find.text('변경 수락'));
      await _settle(t);
      expect(calls.length, 1);
      expect(calls.single, {'proposalId': 'p1', 'consentMode': 'INHERIT'}, reason: '첫 호출에 동의 값 0');
      expect(decision, isNull, reason: 'CONSENT_REQUIRED 에서 시트를 닫지 않는다');
      await _consentContract(t, surface: 'S7', c: c, parts: gParts, details: gDetails,
          cta: '동의하고 변경 수락', sink: sink, submitCount: () => calls.length);
      // 취소 = 전송 0
      await t.tap(find.widgetWithText(OutlinedButton, '취소'));
      await _settle(t);
      expect(calls.length, 1, reason: '취소는 보내지 않는다');
      expect(decision, ReassignmentDecision.dismissed);
      // 다시 열어 명시 동의
      answer = 'OK';
      await t.tap(find.text('열기'));
      await _settle(t);
      // 새 시트는 처음 상태 — 첫 호출이 다시 INHERIT 로 간다(제안이 열린 채라 서버가 다시 판정).
      await t.ensureVisible(find.text('변경 수락'));
      await t.tap(find.text('변경 수락'));
      await _settle(t);
      expect(calls.length, 2);
      expect(calls.last['consentMode'], 'INHERIT');
      expect(decision, ReassignmentDecision.changed);
    });

    testWidgets('S7b 재배치 — 카드 본 뒤 동의하고 변경 수락 = EXPLICIT(v4 · consentShown) ${c.id}', (t) async {
      final sink = _overflowSink();
      _guard(t); // [r5] 채널 · HTTP 관찰
      _view(t, c);
      final calls = <Map<String, dynamic>>[];
      ConfirmedReassignmentService.debugCall = (name, payload) async {
        calls.add(payload);
        if (payload['consentMode'] == 'INHERIT') {
          throw FirebaseFunctionsException(code: 'failed-precondition', message: 'x',
              details: {'code': 'CONSENT_REQUIRED', 'reason': 'AT_MISSING'});
        }
        return {'success': true};
      };
      addTearDown(() => ConfirmedReassignmentService.debugCall = null);
      final p = ConfirmedReassignmentProposal.fromMap({
        'proposalId': 'p2', 'status': 'PROPOSED', 'uid': _kUid, 'businessId': 'biz1', 'businessName': _biz,
        'sourceApplicationId': 'a1',
        'sourcePromise': {'wdId': 'wd-1', 'workType': '분류', 'startTime': '09:00', 'endTime': '18:00'},
        'targetPromise': {'wdId': 'wd-2', 'workType': '검수', 'startTime': '09:00', 'endTime': '18:00'},
      });
      ReassignmentDecision? decision;
      await t.pumpWidget(_app(Scaffold(body: Builder(builder: (ctx) => Center(child: ElevatedButton(
          onPressed: () async => decision = await ConfirmedReassignmentSheet.decide(ctx, p),
          child: const Text('열기'))))), c));
      await t.tap(find.text('열기'));
      await _settle(t);
      await t.ensureVisible(find.text('변경 수락'));
      await t.tap(find.text('변경 수락'));
      await _settle(t);
      final accept = findVisibleText('동의하고 변경 수락');
      await t.ensureVisible(accept);
      await t.tap(accept);
      await _settle(t);
      expect(calls.length, 2);
      expect(calls.last, {
        'proposalId': 'p2', 'consentMode': 'EXPLICIT', 'documentAccessConsentGiven': true,
        'documentAccessConsentVersion': DocumentAccessConsent.version, 'consentShown': true,
      });
      expect(decision, ReassignmentDecision.changed);
      expect(sink, isEmpty);
    });
  }

  group('MIRROR-BIND 거울 면의 원문 결속(후보 lib 기준)', () {
    test('S6 공고 화면 수락 — 위 안내 두 갈래 · 초대 카드 · 두 버튼 이름이 원문과 같다', () {
      final s = _src('lib/screens/common/job_posting_screen.dart');
      final i = s.indexOf('Future<void> _acceptInviteFromDetail() async {');
      final body = s.substring(i, s.indexOf('Future<void> _declineInviteFromDetail()', i));
      expect(body.contains('DocumentAccessConsent.inviteCard(app.businessName),'), isTrue);
      expect(body.contains("isOffer ? '동의하고 제안 수락' : '동의하고 초대 수락'"), isTrue);
      expect(body.contains("'이 근무 초대를 수락할까요?\\n확정된 다른 근무와 시간이 겹치면 수락할 수 없어요. 수락이 완료되면 근무가 확정돼요.'"), isTrue);
      // [r5] 제안 갈래(DU573 판) · 낱말 단위 위젯 · 채움 색 — 거울과 같은 값(다르면 거울을 먼저 맞춘다 · DU575 뒤 재정렬에서 다시 본다).
      expect(body.contains("? '수락하면 제안받은 업무로 확정되고, 기존 지원'"), isTrue);
      expect(body.contains("\"은 '다른 업무로 확정됨'으로 정리돼요.\\n\""), isTrue);
      expect(body.contains("'이 정리는 노쇼로 기록되지 않아요.'"), isTrue);
      expect(body.contains('KeepWordsText('), isTrue);
      // [r5 g1] DU575 판 — 머리 아이콘 grey600 · 주 행동 brand · 행동 배치 helper(거울 _mirrorAcceptActions 와 같은 식)
      expect(body.contains('iconColor: AppColors.grey600,'), isTrue);
      expect(body.contains('style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),'), isTrue);
      expect(body.contains('actions: _acceptDialogActions('), isTrue);
      expect(body.contains("TextLayout.keepWords(isOffer ? '동의하고 제안 수락' : '동의하고 초대 수락')"), isTrue);
      expect(s.contains('if (MediaQuery.textScalerOf(context).scale(1) <= 1.0) return [cancel, accept];'), isTrue);
      expect(s.contains('children: [accept, SizedBox(height: ResponsiveHelper.spacing(context, 8)), cancel],'), isTrue);
      expect(body.contains("child: const Text('취소'),"), isTrue);
      expect(body.contains("'documentAccessConsentVersion': DocumentAccessConsent.inviteVersion,"), isTrue);
    });
    test('S5o 내 지원 제안 수락 — 같은 카드 · 버튼 이름 분기(실제 셀 S5o 와 함께)', () {
      final s = _src('lib/screens/user/my_applications_screen.dart');
      expect(s.contains('DocumentAccessConsent.inviteCard(item.application.businessName),'), isTrue);
      expect(s.contains("TextLayout.keepWords(isOfferAccept ? '동의하고 제안 수락' : '동의하고 초대 수락')"), isTrue);
    });
    test('[C-R4-1] S4 동의 전용 창 — 동의하기 뒤에만 given:true 를 보낸다 · 취소는 요청 0', () {
      final s = _src('lib/screens/user/my_applications_screen.dart');
      final i = s.indexOf('Future<void> _giveInviteConsent(ApplicationModel app) async {');
      final body = s.substring(i, s.indexOf('Future<void> _acceptInviteFlow(', i));
      final ret = body.indexOf('if (ok != true || !mounted) return;');
      final callAt = body.indexOf(".httpsCallable('callableGiveApplicationDocumentConsent')");
      expect(ret > 0 && callAt > ret, isTrue, reason: '취소(ok != true)는 호출 전에 돌아간다');
      expect(body.contains("'documentAccessConsentGiven': true,"), isTrue);
      expect(body.contains("'documentAccessConsentVersion': DocumentAccessConsent.inviteVersion,"), isTrue);
    });
  });
}
