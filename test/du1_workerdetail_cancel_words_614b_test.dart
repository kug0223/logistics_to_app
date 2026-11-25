// ignore_for_file: depend_on_referenced_packages
// [DU614b · 표시 셀 · 후속 등록 F199-WD-CANCEL-WORDS · F199-WD-CANCEL-ENTRY] 근무자 상세(WorkerDetailDialog · DU-O025) 확정취소 흐름 후속(판정199 §4 :68–:69).
//   ① 상세 하단 '확정취소' 진입(사유창을 여는 단계) 글/아이콘 errorDark → 중립 textSecondary(같은 줄 '고정근무 관리' 진입 꼴).
//   ② 사유창 마지막 '확정 취소' 단추 글 — B(320·2.0)에서 '확정 취 / 소' 음절 분리 → 낱말 경계에서만 줄바꿈(TextLayout.keepWords) · 화면 읽기 이름 = 원문.
//   글 크기 · 말줄임 · 한 줄 강제 · 단추 폭/배치 · 채움(errorDark) · 비활성 조건 · 반환값 · 취소 호출 · 사유 목록은 그대로.
//   그리는 것: 확정자(계약서 서명 대기 · 출근 기록 없음) 상세 → 하단 진입을 눌러 사유창을 연다.
//     OPEN(고르기 전 — 진입 · 머리 · 안 고른 줄 · 비활성 최종 단추) · SEL('일정 변경' 고른 뒤) · ETC('기타' 고른 뒤 — 입력칸 · 활성 최종 단추).
//   before = 지금 A(worker_detail_dialog b5b712eb = DU611b 후보) 기록 · strict = 후보(prep/mk_cand.py) 단언(lgate lines).
//   하네스 = DU611b 시험(du1_workerdetail_cancel_picker_611b_test · 정규 DONE 5/5)의 소유자 · 근로자 · 지원서 · 읽기 CF 7종 대역 · 채널 관찰 · HTTP 차단 ·
//     측정 도우미 그대로 + DU610b 시험(du1_s071_myapps_ledger_610b_test)의 낱말 안 줄바꿈 · 전문 · 줄 수 도우미(_midBreaks · _fullShown max 판 · _lineCount) 그대로.
//   찾기/측정 기준 하나: 요소는 skipOffstage false 로 찾고 → 그 요소 자체를 ensureVisible(스크롤 생략 0) → 같은 요소에서 잰다(DU610b 진단199 교훈 · 지연 목록 0).
//   누르는 것: 세 상태 '확정취소' 진입 1(사유창 열기 — 쓰기 0) · SEL '일정 변경' / ETC '기타' 사유 줄 1(고르기 — 화면 상태만).
//     마지막 '확정 취소' · '취소' · 닫기 · 입력칸은 누르지 않는다. 쓰기 0 · 허용 밖 CF 0 · HTTP 요청 0. 기본 skip — TB before/du614bwd-tb/DU_BEFORE_OBSERVE=614 · TA after/du614bwd-ta/없음.
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
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/dialogs/worker_detail_dialog.dart';

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

const _biz = 'biz1';
const _bizName = '테스트 사업장';
const _worker = 'w9';

/// 소유자(BUSINESS_ADMIN) — DU550 _Owner 그대로. 이 창은 checkForBusiness(확정 권한) · checkCurrentBusiness(급여 · 계약 권한)를 부른다.
class _Owner extends UserProvider {
  final watched = <String>[];
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const [_biz], sealBase64: 'seal');
  @override
  bool get isSubAdmin => false;
  @override
  String? get effectiveBusinessId => null;
  @override
  bool get subAdminPermissionsLoaded => true;
  @override
  PermissionWatchState get currentBusinessPermissionHealth => PermissionWatchState.verified;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForAnyBusiness(bool Function(MemberPermissions p) check, {required bool whenUnknown}) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  VoidCallback watchBusinessPermissions(String businessId) {
    watched.add(businessId);
    return () {};
  }
}

/// 확정 근로자 — DU550 _user('CONFW') 값 그대로(급여계좌 · 통장사본 등록 · 이력 0).
UserModel _user() => UserModel(
      uid: _worker, username: _worker, name: '큐에이일', email: 'w9@test.local', role: UserRole.USER,
      gender: '여성', birthDate: DateTime(1995, 3, 2), contactPhone: '010-0000-0000',
      bankName: 'QA테스트은행', accountNumber: '0000000000', accountHolder: '큐에이일', bankbookImagePath: 'users/w9/bankbook.jpg',
      totalWorkDays: 0, averageRating: 0.0, reviewCount: 0, rehireRate: 0.0, recentNoShowCount: 0, recentLateCount: 0, isBlacklisted: false,
    );

/// 확정(CONFIRMED) 단기 지원서 — DU550 _application('CONFW') 값 그대로.
ApplicationModel _application() => ApplicationModel(
      id: 'app1', uid: _worker, toId: 'to1', slotId: 'slot1', wdId: 'wd1', businessId: _biz, businessName: _bizName, toTitle: '테스트 공고',
      selectedWorkType: 'QA 분류', startTime: '10:00', endTime: '11:00', wage: 12000, wageType: 'hourly',
      status: AppStatus.confirmed, workDate: DateTime.utc(2030, 1, 14, 15), appliedAt: DateTime.utc(2030, 1, 10, 1),
      confirmedAt: DateTime.utc(2030, 1, 11, 2), documentAccessConsentGiven: true, documentAccessConsentVersion: '2026-09-18-v3',
    );

/// callableGetContractsByBiz 의 계약서 한 건(서명 대기) — DU550 _contract('pending_worker') 그대로.
Map<String, Object?> _contract() => <String, Object?>{
      'id': 'ct1', 'applicationId': 'app1', 'businessId': _biz, 'workerId': _worker, 'isLongTerm': false, 'toId': 'to1', 'workDetailId': 'wd1',
      'status': 'pending_worker',
      'snapshot': <String, Object?>{'businessName': _bizName, 'workerName': '큐에이일', 'workType': 'QA 분류'},
      'createdAt': <String, Object?>{'_seconds': DateTime.utc(2030, 1, 11, 3).millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0},
    };

/// callableGetTaxIdentityReview 응답(확인 전) — DU550 _tax(false) 그대로.
Map<String, Object?> _tax() => <String, Object?>{
      'state': 'UNREVIEWED', 'valid': true, 'idDocumentVersion': 1, 'taxIdentityFingerprint': 'fp1', 'hasIdDocument': true,
      'reviewedAtMs': null, 'officialName': '큐에이일', 'hasTaxIdentity': false,
    };

/// 사례 — OPEN(사유 고르기 전 · 진입 캡처 + 사유창 캡처) · SEL('일정 변경' 고른 뒤) · ETC('기타' 고른 뒤 — 입력칸).
const _cases = <({String id, int shots})>[(id: 'OPEN', shots: 2), (id: 'SEL', shots: 1), (id: 'ETC', shots: 1)];

/// 글 원문(대상 소스 그대로 — mkcell 이 base · 후보에서 확인한다).
const _entryText = '확정취소';
const _askText = '취소 사유를 선택해주세요';
const _titleText = '확정 취소';
const _subText = '큐에이일님';
const _pickText = '일정 변경';
const _otherText = '인원 조정';
const _etcText = '기타';

const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';

/// 첫 화면이 부르는 읽기 CF(서비스 소스 그대로 · DU550 7종) — 이 밖의 CF 이름(취소 호출 포함)은 차단하고 센다.
const _readFns = <String>{
  'callableGetApplicationsByBiz', 'callableGetMonthlyReviewsForUser', 'callableGetReviewsForUser', 'callableCheckIdCardAccess',
  'callableAdminHasAttendanceRecord', 'callableGetContractsByBiz', 'callableGetTaxIdentityReview',
};

/// Firestore 쓰기 연산 — 하나라도 오면 fsw 로 센다.
const _fsWrites = <String>{'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult'};

/// [DU550 과 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du614bwd.fake.auth.';
const _authListeners = ['registerIdTokenListener', 'registerAuthStateListener'];

/// 원래 경로로 보내는 Flutter 기반 채널과 이유.
const _frameworkAllow = <String, String>{
  'flutter/assets': 'AssetBundle(아이콘 글꼴 · 이미지 매니페스트) 읽기',
  'flutter/platform': 'MaterialApp Title · SystemSound/Haptic',
  'flutter/processtext': 'EditableText 표시의 framework 경로(원 handler/delegate 전달)',
  'flutter/navigation': '루트 Navigator 경로 보고',
  'flutter/mousecursor': 'MouseRegion 커서 갱신(시험 포인터)',
  'flutter/restoration': 'RootRestorationScope 상태 복원 조회',
  'flutter/keyboard': 'HardwareKeyboard 상태 동기화',
  'flutter/accessibility': '의미 트리/알림 전달',
};

/// 모든 플랫폼 메시지 관찰 — 읽기 CF 7종은 대역 응답(확정자 CONFW 갈래), 그 밖 CF 와 Firestore 는 차단 응답 + 기록,
///   기반 채널은 원래 경로, 나머지는 이름을 기록하고 응답 null. 예외를 삼키지 않는다 — 수는 줄로 남긴다(DU550 그대로).
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
        return codec.encodeMessage(<Object?>['not-found', 'du614bwd-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      _hit(fn);
      final Object data = switch (fn) {
        'callableGetApplicationsByBiz' => <String, Object?>{'applications': const <Object?>[]},
        'callableGetMonthlyReviewsForUser' => <String, Object?>{'items': const <Object?>[]},
        'callableGetReviewsForUser' => <String, Object?>{'reviews': const <Object?>[]},
        'callableCheckIdCardAccess' => <String, Object?>{'request': null},
        'callableAdminHasAttendanceRecord' => <String, Object?>{'hasRecord': false},
        'callableGetContractsByBiz' => <String, Object?>{'contracts': <Object?>[_contract()]},
        _ => _tax(),
      };
      return codec.encodeMessage(<Object?>[data]);
    } catch (e) {
      harness.add('cf $e');
      return codec.encodeMessage(<Object?>['internal', 'du614bwd-harness', null]);
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
      return codec.encodeMessage(<Object?>['du614bwd-blocked', '$op 차단', null]);
    } catch (e) {
      harness.add('fs $op $e');
      return null;
    }
  }
}

/// 외부 HTTP 차단 — 클라이언트 객체 생성은 허용하고 센다(ContractService 생성자 · 요청 0), 실제 요청은 기록하고 실패(DU550 그대로).
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
    throw const SocketException('DU614b 관측 — 외부 HTTP 차단');
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

/// [a] 가 [b] **안**에 있는가(겹침이 아니라 포함 · 0.5px 허용 — DU610b 와 같다).
bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

/// 시각 오류 수집 — 넘침은 원문 + 위치, 그 밖 framework 오류는 원문(DU610b 그대로).
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

typedef _V = ({String id, double w, double h, double s});

const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0), (id: 'N', w: 320.0, h: 640.0, s: 1.0)];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '614';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du614bwd-tb' && _env['DU_BEFORE_OBSERVE'] == '614') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du614bwd-ta' && _env['DU_BEFORE_OBSERVE'] == null);

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
    final nCf = wire.calls.length + wire.blocked.length;
    final nUnexp = wire.unexpected.length;
    final nHttp = net.tries.length;
    _out('R614 setup init cf=$nCf unexpected=$nUnexp http=$nHttp hcl=${net.clients} auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S614WD-${v.id}-${c.id} 근무자 상세 확정취소 진입 중립 · 최종 단추 낱말 조판', (t) async {
        final tok = 'S614WD-${v.id}-${c.id}';
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
        _out('D614 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final owner = _Owner();
        Object? failure;
        StackTrace? failureSt;
        var nShot = 0;
        var raw = '';
        try {
          FlutterError.onError = seen.add;
          final key = GlobalKey();
          Future<void> shot(String id, String state) async {
            _out('D614 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            nShot++;
          }

          Future<void> frames(int n) async {
            for (var i = 0; i < n; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
          }

          // 근무자 상세 — DU550/DU611b 와 같은 앱(소유자 · 업무 관리자 테마 · ko 지역화 · 배율) · 확정자 CONFW 갈래(서명 대기 · 출근 기록 없음).
          await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
            value: owner,
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                navigatorKey: navigatorKey,
                theme: RoleTheme.businessAdminTheme,
                locale: const Locale('ko', 'KR'),
                supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (ctx, child) =>
                    MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: Scaffold(
                  body: WorkerDetailDialog(
                    key: UniqueKey(),
                    user: _user(),
                    application: _application(),
                    businessId: _biz,
                    isConfirmed: true,
                    showApprovalButtons: false,
                  ),
                ),
              ),
            ),
          ));
          await frames(40);
          final dlg = find.byType(WorkerDetailDialog);
          final nScr = dlg.evaluate().length;
          _out('D614 $tok att scr n=$nScr');
          need('창 1', nScr == 1, '개수 $nScr');

          // ① 하단 '확정취소' 진입(출근 기록 없는 확정자) — F199-WD-CANCEL-ENTRY 중립 글/아이콘. 잰 요소 = 누르는 요소(같은 RichText · ensureVisible 뒤).
          final en = await _entryOf(t, dlg, screen);
          _out('D614 $tok att ent n=${en.n} fg=${en.fg} ic=${en.ic} cr=${en.cr} ok45=${en.ok45} vis=${en.vis}');
          need('확정취소 진입 1', en.n == 1, '개수 ${en.n}');
          if (c.id == 'OPEN') await shot('0entry', 'detail-footer-entry');

          // ② 진입 누름 → 사유창 열기(누름 1 · 쓰기 0).
          final entryF = find.descendant(of: dlg, matching: find.text(_entryText), skipOffstage: false);
          final nEntry = entryF.evaluate().length;
          if (nEntry == 1) {
            await t.ensureVisible(entryF);
            await t.pump();
            await t.tap(entryF);
            await frames(20);
          }
          final host = find.ancestor(of: find.text(_askText, skipOffstage: false), matching: find.byType(Dialog));
          final nPk = host.evaluate().length;
          _out('D614 $tok att act n=$nEntry pk=$nPk');
          need('확정취소 진입 1 · 사유창 1', nEntry == 1 && nPk == 1, 'entry $nEntry picker $nPk');
          final pick = host.first;
          final fills0 = _fills(t);

          if (c.id == 'OPEN') {
            // ③ 머리 · 안 고른 줄('일정 변경') — DU611b 이행값(변경 0) 회귀 확인.
            final hd = _headOf(pick);
            _out('D614 $tok att head n=${hd.n} face=${hd.face} dlg=${hd.dlg} same=${hd.same} tfg=${hd.tfg} sfg=${hd.sfg} ic=${hd.ic} cl=${hd.cl} '
                'line=${hd.line} tcr=${hd.tcr} bcr=${hd.bcr} ok45=${hd.ok45}');
            need('머리 제목 1', hd.n == 1, '개수 ${hd.n}');
            final ro = await _rowOf(t, pick, _pickText);
            _out('D614 $tok att rowoff n=${ro.n} bg=${ro.bg} bd=${ro.bd} ic=${ro.ic} on=${ro.on} fg=${ro.fg} cr=${ro.cr}');
            need('사유 줄 1', ro.n == 1, '개수 ${ro.n}');
            await shot('1open', 'reason-picker-open');
            // ④ 마지막 '확정 취소'(고르기 전 = 비활성 · 누르지 않는다) — 낱말 조판 · 전문 · 화면 읽기 이름.
            final g = await _goOf(t, pick, screen);
            _out('D614 $tok att go n=${g.n} dis=${g.dis} fill=${g.fill} fg=${g.fg} cr=${g.cr} ok45=${g.ok45} m48=${g.m48} vis=${g.vis} hit=${g.hit} '
                'ln=${g.ln} mb=${g.mb} full=${g.full} sl=${g.sl}');
            need('최종 단추 1', g.n == 1, '개수 ${g.n}');
            raw = 'ent $en head $hd rowoff $ro go $g';
          } else {
            // ③ 사유 고르기(누름 1 · 화면 상태만) — SEL '일정 변경' · ETC '기타'(입력칸이 열린다 · 입력/포커스 0).
            final label = c.id == 'SEL' ? _pickText : _etcText;
            final pf = find.descendant(of: pick, matching: find.text(label), skipOffstage: false);
            final nPf = pf.evaluate().length;
            need('고를 사유 1', nPf == 1, '개수 $nPf');
            await t.ensureVisible(pf);
            await t.pump();
            await t.tap(pf);
            await frames(10);
            final rs = await _rowOf(t, pick, label);
            _out('D614 $tok att rowsel n=${rs.n} bg=${rs.bg} bd=${rs.bd} ic=${rs.ic} on=${rs.on} fg=${rs.fg} cr=${rs.cr}');
            need('고른 줄 1', rs.n == 1, '개수 ${rs.n}');
            var etcRaw = '';
            if (c.id == 'ETC') {
              final et = await _etcOf(t, pick, screen);
              _out('D614 $tok att etc n=${et.n} vis=${et.vis}');
              need('기타 입력칸 1', et.n == 1, '개수 ${et.n}');
              etcRaw = ' etc $et';
            }
            final ro = await _rowOf(t, pick, c.id == 'SEL' ? _otherText : _pickText);
            _out('D614 $tok att rowoff n=${ro.n} bg=${ro.bg} bd=${ro.bd} ic=${ro.ic} on=${ro.on} fg=${ro.fg} cr=${ro.cr}');
            need('안 고른 줄 1', ro.n == 1, '개수 ${ro.n}');
            final hd = _headOf(pick);
            _out('D614 $tok att head n=${hd.n} face=${hd.face} dlg=${hd.dlg} same=${hd.same} tfg=${hd.tfg} sfg=${hd.sfg} ic=${hd.ic} cl=${hd.cl} '
                'line=${hd.line} tcr=${hd.tcr} bcr=${hd.bcr} ok45=${hd.ok45}');
            need('머리 제목 1', hd.n == 1, '개수 ${hd.n}');
            final g = await _goOf(t, pick, screen);
            _out('D614 $tok att go n=${g.n} dis=${g.dis} fill=${g.fill} fg=${g.fg} cr=${g.cr} ok45=${g.ok45} m48=${g.m48} vis=${g.vis} hit=${g.hit} '
                'ln=${g.ln} mb=${g.mb} full=${g.full} sl=${g.sl}');
            need('최종 단추 1', g.n == 1, '개수 ${g.n}');
            raw = 'ent $en rowsel $rs$etcRaw rowoff $ro head $hd go $g';
          }
          final fills = _fills(t);
          _out('D614 $tok att fills n=${fills.n} brand=${fills.brand} err=${fills.err} none=${fills.none} other=${fills.other} list=${fills.list}');
          raw = '$raw fills0 $fills0 fills $fills';
          if (c.id == 'SEL') {
            await shot('2sel', 'reason-selected-final-enabled');
          } else if (c.id == 'ETC') {
            await shot('3etc', 'reason-other-input-final-enabled');
          }
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ⑤ 성공 · 실패 공통 정리 — 화면을 내리고(열린 사유창 포함) 남은 지연이 끝날 시간을 준다.
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

        // ⑥ 집계 — 읽기 CF 수 · 허용 밖 CF(취소 호출 포함) · Firestore 쓰기/그 밖 연산 · 예상 밖 채널 · HTTP 요청/클라이언트 생성.
        final nRd = wire.calls.values.fold<int>(0, (a, b) => a + b);
        final nCfx = wire.blocked.length;
        final nFsw = wire.fsWrites.length;
        final nFso = wire.fsOther.length;
        final nUnexp = wire.unexpected.length;
        final nHttp = net.tries.length;
        final nHcl = net.clients;
        final nHarness = wire.harness.length;
        final unText = [...wire.unexpected, ...wire.blocked, ...wire.fsWrites.map((x) => 'fsw $x'), ...wire.fsOther.map((x) => 'fs $x'), ...wire.harness, ...net.tries].join(' | ');
        _out('D614 $tok att wire rd=$nRd cfx=$nCfx fsw=$nFsw fso=$nFso unexpected=$nUnexp http=$nHttp hcl=$nHcl harness=$nHarness');

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
        _out('R614 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D614 $tok att fw n=$nFw');
        _out('D614 $tok done state=${c.id} mode=$mode captures=$nShot overflows=$nOvf exc=${exc != null}');

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

// 측정 도우미 — DU610b 색 도우미 · _fills 그대로(main 뒤에 둔다 — preflight 'renderObject 재사용' 줄 훑기 거짓 양성 회피 · DU573 r1 · DU610b 와 같다).

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

/// [DU610b · 점검표 A8] 화면에 그려진(onstage) ButtonStyleButton 전부의 채움 — 단추 자신의 Material 색(투명 · 없음 = none) · 글 = 첫 RichText(Icon 글리프 제외).
///   기록만(브랜드 밖 채움은 보고서 색 조화 표 '후보'). 상세 창 하단 진입(_buildDialogButton = InkWell)은 여기 들지 않는다 — README A8 표.
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

// [DU610b] 낱말 안 줄바꿈 · 전문 · 줄 수 — DU610b 시험 그대로(그려진 RenderParagraph 기준).

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

/// 그려진 문단의 줄 수 — 글자 자리(box)의 서로 다른 top 개수.
int _lineCount(RenderParagraph rp) {
  final n = rp.text.toPlainText(includeSemanticsLabels: false).length;
  final tops = <int>{};
  for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: n))) {
    tops.add(b.top.round());
  }
  return tops.length;
}

// [DU611b] 사유창 도우미 — DU611b 시험 그대로(사유창 안([pick] 아래)만 본다).

/// 사유창 안에서 그린 글이 [label] 과 같은 RichText 요소들 — [inButton] 이면 ButtonStyleButton 조상이 있는 것만, 아니면 없는 것만.
List<Element> _textEls(Finder pick, String label, {required bool inButton}) {
  final btn = find.byWidgetPredicate((w) => w is ButtonStyleButton, skipOffstage: false);
  return find
      .descendant(of: pick, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == label)
      .where((e) {
        final ef = find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
        return find.ancestor(of: ef, matching: btn).evaluate().isNotEmpty == inButton;
      })
      .toList();
}

/// 사유창 안 아이콘 [icon] 의 색(정확히 하나일 때) — 없거나 여럿이면 개수 표시.
String _iconColor(Finder pick, IconData icon) {
  final es = find.descendant(of: pick, matching: find.byWidgetPredicate((w) => w is Icon && w.icon == icon), skipOffstage: false).evaluate().toList();
  if (es.length != 1) return 'n${es.length}';
  final c = (es.first.widget as Icon).color;
  return c == null ? '-' : _hex(c);
}

/// 가장 가까운 DecoratedBox(BoxDecoration · 색 또는 선이 있는 것) 조상.
BoxDecoration? _decoOf(Element el) {
  BoxDecoration? found;
  el.visitAncestorElements((a) {
    final w = a.widget;
    if (w is DecoratedBox && w.decoration is BoxDecoration) {
      final d = w.decoration as BoxDecoration;
      if (d.color != null || d.border != null) {
        found = d;
        return false;
      }
    }
    return true;
  });
  return found;
}

typedef _HeadObs = ({int n, String face, String dlg, bool same, String tfg, String sfg, String ic, String cl, String line, String tcr, String bcr, bool ok45});

/// 사유창 머리 — 제목 '확정 취소'(단추 밖 RichText 하나) 뒤 실제 바탕(face) · 창 본문 바탕(dlg = '취소 사유를 선택해주세요' 뒤) · 같은가 ·
///   제목/부제 글자색 · 머리 아이콘(cancel_outlined) · 닫기(close) 색 · 머리 상자 아래 선 색(없으면 '-') · 제목/부제 대비 · 둘 다 ≥4.5.
///   읽기만(누름 0 · 끌기 0 — 머리는 창 맨 위 고정 순서 첫 칸).
_HeadObs _headOf(Finder pick) {
  final ts = _textEls(pick, _titleText, inButton: false);
  final ss = _textEls(pick, _subText, inButton: false);
  final ks = _textEls(pick, _askText, inButton: false);
  if (ts.length != 1 || ss.length != 1 || ks.length != 1) {
    return (n: ts.length, face: '-', dlg: '-', same: false, tfg: '-', sfg: '-', ic: '-', cl: '-', line: '-', tcr: '0.00', bcr: '0.00', ok45: false);
  }
  final face = _bgOf(ts.first);
  final dlg = _bgOf(ks.first);
  final tfg = (ts.first.widget as RichText).text.style?.color ?? Colors.transparent;
  final sfg = (ss.first.widget as RichText).text.style?.color ?? Colors.transparent;
  final tcr = _contrast(Color.alphaBlend(tfg, face), face);
  final bcr = _contrast(Color.alphaBlend(sfg, face), face);
  final deco = _decoOf(ts.first);
  final bd = deco?.border;
  final line = bd is Border && bd.bottom.style != BorderStyle.none ? _hex(bd.bottom.color) : '-';
  return (
    n: 1,
    face: _hex(face),
    dlg: _hex(dlg),
    same: face.toARGB32() == dlg.toARGB32(),
    tfg: _hex(tfg),
    sfg: _hex(sfg),
    ic: _iconColor(pick, Icons.cancel_outlined),
    cl: _iconColor(pick, Icons.close),
    line: line,
    tcr: tcr.toStringAsFixed(2),
    bcr: bcr.toStringAsFixed(2),
    ok45: tcr >= 4.5 && bcr >= 4.5,
  );
}

typedef _RowObs = ({int n, String bg, String bd, String ic, bool on, String fg, String cr});

/// 사유 줄 하나 — 글이 [label] 인 RichText 하나를 ensureVisible 로 넣고(잰 대상 = 넣은 대상), 그 줄 면(가장 가까운 BoxDecoration 색) ·
///   선(Border 윗변 색 = Border.all) · 같은 InkWell 안 라디오 아이콘 색 · 켜짐(radio_button_checked) · 글자색 · 글/면 대비를 잰다.
Future<_RowObs> _rowOf(WidgetTester t, Finder pick, String label) async {
  final es0 = _textEls(pick, label, inButton: false);
  if (es0.length != 1) return (n: es0.length, bg: '-', bd: '-', ic: '-', on: false, fg: '-', cr: '0.00');
  final tf = find.byElementPredicate((q) => identical(q, es0.first), skipOffstage: false);
  await t.ensureVisible(tf);
  await t.pump();
  final el = _textEls(pick, label, inButton: false).first;
  final deco = _decoOf(el);
  final bgc = deco?.color;
  final bd = deco?.border;
  final bdc = bd is Border ? bd.top.color : null;
  final ef = find.byElementPredicate((q) => identical(q, el), skipOffstage: false);
  final ink = find.ancestor(of: ef, matching: find.byType(InkWell));
  final icons = ink.evaluate().isEmpty
      ? <Element>[]
      : find.descendant(of: ink.first, matching: find.byType(Icon), skipOffstage: false).evaluate().toList();
  final icon = icons.length == 1 ? icons.first.widget as Icon : null;
  final fg = (el.widget as RichText).text.style?.color ?? Colors.transparent;
  final face = bgc ?? _bgOf(el);
  return (
    n: 1,
    bg: bgc == null ? '-' : _hex(bgc),
    bd: bdc == null ? '-' : _hex(bdc),
    ic: icon?.color == null ? 'n${icons.length}' : _hex(icon!.color!),
    on: icon?.icon == Icons.radio_button_checked,
    fg: _hex(fg),
    cr: _contrast(Color.alphaBlend(fg, face), face).toStringAsFixed(2),
  );
}

// [DU614b] 새 도우미 — 진입 · 최종 단추 글 조판 · 기타 입력칸.

/// 단추 안 글 [el] 의 화면 읽기 이름 — ButtonStyleButton 까지 올라가며 label 이 있는 첫 Semantics(Text.semanticsLabel 이 만든 것), 없으면 그린 글 원본(표시 제어 문자 포함).
String _semLabel(Element el) {
  String? found;
  el.visitAncestorElements((a) {
    final w = a.widget;
    if (w is ButtonStyleButton) return false;
    if (w is Semantics && w.properties.label != null) {
      found = w.properties.label;
      return false;
    }
    return true;
  });
  return found ?? (el.widget as RichText).text.toPlainText(includeSemanticsLabels: false);
}

typedef _EntObs = ({int n, String fg, String ic, String cr, bool ok45, bool vis});

/// 상세 창 하단 '확정취소' 진입 — 창(사유창 열기 전) 안 단추 밖 RichText 중 글이 진입 글인 것 하나를 ensureVisible 로 넣고(잰 대상 = 넣은 대상),
///   그 글자색 · 같은 InkWell 안 아이콘(cancel_outlined) 색 · 글/바탕 대비 · 화면 ∩ 스크롤 칸 안을 잰다(누름은 본문에서 같은 글 finder 로).
Future<_EntObs> _entryOf(WidgetTester t, Finder dlg, Rect screen) async {
  List<Element> els() => find
      .descendant(of: dlg, matching: find.byType(RichText), skipOffstage: false)
      .evaluate()
      .where((e) => TextLayout.plain((e.widget as RichText).text.toPlainText(includeSemanticsLabels: false)) == _entryText)
      .toList();
  final es0 = els();
  if (es0.length != 1) return (n: es0.length, fg: '-', ic: '-', cr: '0.00', ok45: false, vis: false);
  final tf = find.byElementPredicate((q) => identical(q, es0.first), skipOffstage: false);
  await t.ensureVisible(tf);
  await t.pump();
  final el = els().first;
  final ef = find.byElementPredicate((q) => identical(q, el), skipOffstage: false);
  final ink = find.ancestor(of: ef, matching: find.byType(InkWell));
  final icons = ink.evaluate().isEmpty
      ? <Element>[]
      : find.descendant(of: ink.first, matching: find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.cancel_outlined), skipOffstage: false).evaluate().toList();
  final ic = icons.length == 1 ? (icons.first.widget as Icon).color : null;
  final fg = (el.widget as RichText).text.style?.color ?? Colors.transparent;
  final face = _bgOf(el);
  final cr = _contrast(Color.alphaBlend(fg, face), face);
  return (
    n: 1,
    fg: _hex(fg),
    ic: ic == null ? 'n${icons.length}' : _hex(ic),
    cr: cr.toStringAsFixed(2),
    ok45: cr >= 4.5,
    vis: _inside(t.getRect(ef), _area(ef, screen)),
  );
}

typedef _EtcObs = ({int n, bool vis});

/// '기타' 고른 뒤 사유창 안 입력칸(TextField) — 하나를 ensureVisible 로 넣고 화면 ∩ 스크롤 칸 안을 잰다(누름 · 입력 · 포커스 0).
Future<_EtcObs> _etcOf(WidgetTester t, Finder pick, Rect screen) async {
  final es0 = find.descendant(of: pick, matching: find.byType(TextField), skipOffstage: false).evaluate().toList();
  if (es0.length != 1) return (n: es0.length, vis: false);
  final tf = find.byElementPredicate((q) => identical(q, es0.first), skipOffstage: false);
  await t.ensureVisible(tf);
  await t.pump();
  return (n: 1, vis: _inside(t.getRect(tf), _area(tf, screen)));
}

typedef _GoObs = ({int n, bool dis, String fill, String fg, String cr, bool ok45, bool m48, bool vis, bool hit, int ln, int mb, bool full, String sl});

/// 마지막 '확정 취소' 단추 — 글이 든 ButtonStyleButton 하나의 그 RichText 를 ensureVisible 로 넣고, 그 단추 한 요소로
///   비활성(onPressed null) · 채움(단추 Material 색) · 글자색 · 채움(창 바탕 위 합성) 대비 · 받는 자리 48 · 화면 ∩ 스크롤 칸 안 · 중심 hit 를 재고(누르지 않는다),
///   [DU614b] 같은 RichText(RenderParagraph)로 줄 수 · 낱말 안 줄바꿈 · 전문 · 화면 읽기 이름(_enc)을 잰다.
Future<_GoObs> _goOf(WidgetTester t, Finder pick, Rect screen) async {
  final es0 = _textEls(pick, _titleText, inButton: true);
  if (es0.length != 1) {
    return (n: es0.length, dis: false, fill: '-', fg: '-', cr: '0.00', ok45: false, m48: false, vis: false, hit: false, ln: 0, mb: 0, full: false, sl: '-');
  }
  final tf = find.byElementPredicate((q) => identical(q, es0.first), skipOffstage: false);
  await t.ensureVisible(tf);
  await t.pump();
  final el = _textEls(pick, _titleText, inButton: true).first;
  final ef = find.byElementPredicate((q) => identical(q, el), skipOffstage: false);
  final bf = find.ancestor(of: ef, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
  final mats = find.descendant(of: bf, matching: find.byType(Material), skipOffstage: false).evaluate().toList();
  final fill = mats.isEmpty ? Colors.transparent : ((mats.first.widget as Material).color ?? Colors.transparent);
  final under = _bgOf(bf.evaluate().first);
  final base = Color.alphaBlend(fill, under);
  final fg = (el.widget as RichText).text.style?.color ?? Colors.transparent;
  final cr = _contrast(Color.alphaBlend(fg, base), base);
  final r = t.getRect(bf);
  final rp = el.renderObject! as RenderParagraph;
  return (
    n: 1,
    dis: (t.widget(bf) as ButtonStyleButton).onPressed == null,
    fill: _hex(fill),
    fg: _hex(fg),
    cr: cr.toStringAsFixed(2),
    ok45: cr >= 4.5,
    m48: r.width >= 48 - 0.01 && r.height >= 48 - 0.01,
    vis: _inside(r, _area(bf, screen)),
    hit: _hitWithin(t, bf, r.center),
    ln: _lineCount(rp),
    mb: _midBreaks(rp),
    full: _fullShown(rp, rp.size),
    sl: _enc(_semLabel(el)),
  );
}
