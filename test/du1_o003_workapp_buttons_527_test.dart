// ignore_for_file: depend_on_referenced_packages
// [DU527a · 표시만] DU-O003 '업무별 지원자' 창 — 행 버튼 · 일괄 띠 버튼을 UI-1(O002 역할 짝)으로.
//   before = 현재 A(work_applicants_dialog 26f1ff39) 기록 전용 · strict = 후보 r2(e249b1b2). 상태 ROWS(행 버튼) · BULK(일괄 띠) × W/B.
//   하네스 = offer_workdetail_roster_test · noshow_contract_dialog_gate_test 의 WorkApplicantsReads.debugOverride(창을 Scaffold body 로 직접 세운다)
//   + 대기(PENDING) 3 · 확정 2 대역. 쓰기 동작(확정 · 거절 · 계약)은 누르지 않는다 — 일괄선택 켜기 · 전체 선택(화면 상태)만.
//   기본 skip — TB before/du527a-tb/DU_BEFORE_OBSERVE=527 · TA after/du527a-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/slot_model.dart' show SlotModel, SlotStatus;
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_reads.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/widgets/admin/applicant_row_surface.dart';
import 'package:ALfit/widgets/common/app_checkbox.dart';
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';

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

const _biz1 = 'biz1';
const _bizName = '강남 물류센터';

/// 소유자(BUSINESS_ADMIN) — DU526 _Owner 와 같은 override(창은 `checkForBusiness` · `watchBusinessPermissions` 를 부른다).
class _Owner extends UserProvider {
  final watched = <String>[];
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const [_biz1], sealBase64: 'seal');
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

/// 근무일 = 3일 뒤 KST 자정(noshow_contract_dialog_gate_test 의 kDay 와 같은 식 — 증명된 대역).
final DateTime _day = () {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day + 3).subtract(const Duration(hours: 9));
}();
final DateTime _applied = DateTime.now().subtract(const Duration(hours: 3));
final DateTime _made = DateTime.now().subtract(const Duration(days: 3));

WorkDetailData _wd1() => WorkDetailData(
    wdId: 'wd1', workType: '홀서빙', startTime: '09:00', endTime: '18:00', requiredCount: 5, wage: 12000, wageType: 'hourly',
    applicationDeadline: DateTime.now().add(const Duration(days: 2)));

/// 둘째 업무 — '다른 업무 제안' · '근무 변경 제안' 이 서려면 제안할 다른 업무가 있어야 한다(:3256 offerableFrom).
WorkDetailData _wd2() => WorkDetailData(
    wdId: 'wd2', workType: '주방 보조', startTime: '13:00', endTime: '22:00', requiredCount: 3, wage: 12000, wageType: 'hourly',
    applicationDeadline: DateTime.now().add(const Duration(days: 2)));

TOModel _to() => TOModel(
    id: 'to1', businessId: _biz1, businessName: _bizName, type: 'flex', title: '단기 모집', creatorUID: 'admin1', status: 'ACTIVE',
    workDetails: [_wd1(), _wd2()], totalRequired: 8, totalConfirmed: 2, totalPending: 3, isPublished: true, publishMode: 'immediate',
    createdAt: _made, statusUpdatedAt: _made);

TOItem _item() => TOItem(
    to: _to(),
    slot: SlotModel(id: 'slot1', toId: 'to1', date: _day, status: SlotStatus.open, workDetails: [_wd1(), _wd2()], createdAt: _made),
    workDetails: [_wd1(), _wd2()], confirmedCount: 2, pendingCount: 3, totalRequired: 8);

ApplicationModel _app(String id, String status, {bool starred = false}) => ApplicationModel(
    id: id, uid: 'u_$id', toId: 'to1', slotId: 'slot1', businessId: _biz1, businessName: _bizName, toTitle: '단기 모집',
    selectedWorkType: '홀서빙', wdId: 'wd1', startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly', status: status,
    workDate: _day, appliedAt: _applied, isStarred: starred);

const _names = <String, String>{'p1': '김별표', 'p2': '이선택', 'p3': '박대기', 'c1': '최확정', 'c2': '정미작성'};

/// 대역 — 대기 3(p1 별표) · 확정 2(c1 계약 완료 · c2 계약 미작성). 사례마다 새로 만든다(공유 상태 0).
List<ApplicationModel> _apps() => [
      _app('p1', AppStatus.pending, starred: true), _app('p2', AppStatus.pending), _app('p3', AppStatus.pending),
      _app('c1', AppStatus.confirmed), _app('c2', AppStatus.confirmed),
    ];

/// 창의 읽기 경계(주입) — 호출 수만 센다. 쓰기는 여기 없다.
class _Reads {
  final calls = <String, int>{};
  void _hit(String k) => calls[k] = (calls[k] ?? 0) + 1;

  WorkApplicantsReads reads() => WorkApplicantsReads(
        applications: (to, {slotId, required purpose}) async {
          _hit('applications');
          return _apps();
        },
        usersBatch: (uids, {required businessId, purpose}) async {
          _hit('users');
          return {
            for (final u in uids)
              u: UserModel(uid: u, username: u, name: _names[u.replaceFirst('u_', '')] ?? '근로자 $u', email: '$u@alfit.local', role: UserRole.USER),
          };
        },
        weeklyAttendance: ({required businessId, required weekStart, required weekEnd}) async {
          _hit('weekly');
          return <String, List<AttendanceModel>>{};
        },
        contractStatusBatch: (ids, {required businessId}) async {
          _hit('contracts');
          return ContractStatusBatch(statuses: <String, String?>{for (final x in ids) if (x == 'c1') x: 'completed'});
        },
        hasWorkedMap: ({required businessId, required date}) async {
          _hit('hasWorked');
          return const <String, bool>{};
        },
        idCardStatusBatch: ({required requesterId, required targetUserIds}) async {
          _hit('idCard');
          return const <String, String>{};
        },
        capacity: (to, {slotId, slotWorkDetails}) async {
          _hit('capacity');
          return <String, dynamic>{
            'workDetails': [_wd1(), _wd2()],
            'workStats': {
              'wd1': {'confirmed': 2, 'pending': 3},
              'wd2': {'confirmed': 0, 'pending': 0},
            },
            'statsFailed': false,
          };
        },
        reassignProposals: (bizId) async {
          _hit('reassign');
          return const [];
        },
        contractAttendances: ({required businessId, required first, required last}) async {
          _hit('contractAtt');
          return const <AttendanceModel>[];
        },
      );
}

/// CF Pigeon 채널 — RG 시험(offer_workdetail_roster · noshow_contract_dialog_gate)과 같은 'unavailable' 응답을 주고 센다.
const _cfChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// [DU526 과 같다] FirebaseAuth 를 처음 읽을 때 등록하는 두 리스너 채널과 그 이벤트 채널.
const _authBase = 'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.';
const _authFake = 'du527a.fake.auth.';
const _authListeners = ['registerIdTokenListener', 'registerAuthStateListener'];

/// 원래 경로로 보내는 Flutter 기반 채널과 이유.
const _frameworkAllow = <String, String>{
  'flutter/assets': 'AssetBundle(아이콘 글꼴 · 이미지 매니페스트) 읽기',
  'flutter/platform': 'MaterialApp Title · SystemSound/Haptic(InkWell 탭 피드백)',
  'flutter/navigation': '루트 Navigator 경로 보고',
  'flutter/mousecursor': 'MouseRegion 커서 갱신(시험 포인터)',
  'flutter/restoration': 'RootRestorationScope 상태 복원 조회',
  'flutter/keyboard': 'HardwareKeyboard 상태 동기화',
  'flutter/accessibility': '의미 트리/알림 전달',
};

/// 모든 플랫폼 메시지 관찰 — 기반 채널은 원래 경로 · Auth 두 리스너는 setUpAll 모의 · CF 는 'unavailable' 응답 ·
///   그 밖은 이름을 기록하고 응답 null(플러그인 없음과 같은 결과). 예외를 삼키지 않는다 — 수는 줄로 남긴다.
class _Wire {
  final unexpected = <String>[];
  final cf = <String>[];
  final auth = <String>[];

  Future<ByteData?>? route(TestDefaultBinaryMessenger m, String channel, MessageHandler? handler, ByteData? message) {
    if (channel == _cfChannel) {
      cf.add(channel);
      return Future<ByteData?>.value(const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'test harness', null]));
    }
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
}

/// 외부 HTTP 차단 — 만들려는 시도를 기록하고 실패시킨다.
class _NoHttp extends HttpOverrides {
  final tries = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    tries.add('createHttpClient');
    throw const SocketException('DU527a 관측 — 외부 HTTP 차단');
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

/// [a] 가 [b] **안**에 있는가(0.5px 허용).
bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

String _hex(Color c) {
  String h(double x) => (x * 255).round().toRadixString(16).padLeft(2, '0');
  return '${h(c.a)}${h(c.r)}${h(c.g)}${h(c.b)}';
}

/// WCAG 대비 — [fg] 글자 · [bg] 불투명 바탕.
double _contrast(Color fg, Color bg) {
  final a = Color.alphaBlend(fg, bg).computeLuminance();
  final b = bg.computeLuminance();
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

typedef _Probe = ({String label, Rect r, Color fill, Color fg, double cr, bool big, bool hit});

/// 버튼 하나의 관측값 — 잰 즉시 값으로 굳힌다(트리 변경 뒤 다시 읽지 않는다).
///   면 = 가장 가까운 Material(버튼 자신) 색 · 글자색 = 버튼 안 Text 의 style 색 · 대비 = 글자 ↔ (채움이면 그 면, 아니면 [under]).
_Probe _probe(WidgetTester t, Finder one, Color under) {
  final textF = find.descendant(of: one, matching: find.byType(Text), skipOffstage: true);
  final tw = t.widget<Text>(textF.first);
  final label = tw.data ?? '';
  final fg = tw.style?.color ?? Colors.black;
  final fill = t.widget<Material>(find.ancestor(of: one, matching: find.byType(Material)).first).color ?? Colors.transparent;
  final bg = fill.a == 0 ? under : Color.alphaBlend(fill, under);
  final r = t.getRect(one);
  final big = r.width >= 48 - 0.01 && r.height >= 48 - 0.01;
  final hit = t.hitTestOnBinding(r.center).path.any((x) => identical(x.target, t.renderObject(one)));
  return (label: label, r: r, fill: fill, fg: fg, cr: _contrast(fg, bg), big: big, hit: hit);
}

/// 버튼 면이 '분류색 면'인가 — 면 없음(투명) · brand 채움 · 비활성 회색(grey100)이 아니면 분류색 면이다.
bool _classFace(Color fill) => fill.a != 0 && fill != AppColors.brand && fill != AppColors.grey100;

/// 후보 r2(e249b1b2)에서 행 버튼이 그려지는 줄 범위 — 카드 버튼 호출부(:2781) ~ _buildActionButton 끝(:3020).
///   넘침 오류의 '오류를 낸 위젯' 위치(work_applicants_dialog.dart:줄)가 이 안이면 행 버튼 발 넘침으로 센다. before 는 기록만(줄이 9 어긋난다).
const _ownLo = 2781;
const _ownHi = 3020;
final RegExp _locRe = RegExp(r'work_applicants_dialog\.dart:(\d+)');

/// 시각 오류 수집 — 넘침은 원문 + 위치, 그 밖 framework 오류는 원문.
class _Seen {
  final overflows = <String>[];
  final other = <String>[];
  var own = 0;
  var unk = 0;

  void add(FlutterErrorDetails d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      final full = d.toString();
      final k = full.indexOf('The relevant error-causing widget was');
      final loc = k < 0
          ? ''
          : full.substring(k).split('\n').skip(1).where((l) => l.trim().isNotEmpty).take(2).map((l) => l.trim()).join(' ');
      // 위치 줄이 아예 없으면 '모름'(어느 위젯인지 가릴 수 없다) · 이 창의 행 버튼 줄 범위면 '행 버튼 발'.
      final lines = [for (final x in _locRe.allMatches(loc)) int.parse(x.group(1)!)];
      if (loc.isEmpty) {
        unk++;
      } else if (lines.any((n) => n >= _ownLo && n <= _ownHi)) {
        own++;
      }
      overflows.add('${m.split('\n').first} @ $loc');
    } else {
      other.add(m);
    }
  }
}

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[(id: 'ROWS', shots: 2), (id: 'BULK', shots: 1)];

/// 행 버튼 문구 — 문구 불변 기준(선언 lines 의 exact 와 같은 값). 순서 = 정렬.
const _rowLabels = ['거절', '계약서 작성', '근무 변경 제안', '다른 업무 제안', '확정', '확정취소'];
const _bulkLabels = ['거절', '확정'];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '527';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du527a-tb' && _env['DU_BEFORE_OBSERVE'] == '527') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du527a-ta' && _env['DU_BEFORE_OBSERVE'] == null);

/// 첫 실패 뒤 사례는 본문에 들어가지 않는다(진입 0 · 캡처 0).
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
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
    final nCf = wire.cf.length;
    final nUnexp = wire.unexpected.length;
    final nHttp = net.tries.length;
    _out('R527 setup init cf=$nCf unexpected=$nUnexp http=$nHttp auth=${wire.auth.length} un64=${_enc(wire.unexpected.join('|'))}');
    final initOk = nCf == 0 && nUnexp == 0 && nHttp == 0;
    if (!initOk) _halt = 'setUpAll 초기화 안전 대역';
    expect(initOk, isTrue, reason: 'setUpAll 초기화 중 CF 0 · 예상 밖 채널 0 · HTTP 0 — [${wire.unexpected.join(' | ')}]');
  });
  tearDown(() => WorkApplicantsReads.debugOverride = null);

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S903AB-${v.id}-${c.id} 업무별 지원자 행 버튼 · 일괄 띠 버튼 — 주요 하나만 채움 · 보조 · 위험은 글자', (t) async {
        final tok = 'S903AB-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');

        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final wire = _Wire();
        final net = _NoHttp();
        final prevAll = messenger.allMessagesHandler;
        final prevHttp = HttpOverrides.current;
        final prevOnError = FlutterError.onError;
        final prevOverride = WorkApplicantsReads.debugOverride;
        messenger.allMessagesHandler = (channel, handler, message) => wire.route(messenger, channel, handler, message);
        HttpOverrides.global = net;
        addTearDown(() {
          messenger.allMessagesHandler = prevAll;
          HttpOverrides.global = prevHttp;
          FlutterError.onError = prevOnError;
          WorkApplicantsReads.debugOverride = prevOverride;
        });
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final mode = _before ? 'before' : 'strict';
        _out('D527 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));

        final owner = _Owner();
        final reads = _Reads();
        Object? failure;
        StackTrace? failureSt;
        var shots = 0;
        var raw = '';
        try {
          FlutterError.onError = seen.add;
          WorkApplicantsReads.debugOverride = reads.reads();
          final key = GlobalKey();
          await t.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
            value: owner,
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
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
                home: Scaffold(body: WorkApplicantsDialog(key: UniqueKey(), toItem: _item(), work: _wd1(), onChanged: () {})),
              ),
            ),
          ));
          for (var i = 0; i < 40; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          final dlg = find.byType(WorkApplicantsDialog);
          final nDlg = dlg.evaluate().length;
          need('창 1', nDlg == 1, '개수 $nDlg');
          Future<void> shot(String id, String state) async {
            _out('D527 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          if (c.id == 'ROWS') {
            // ① 행 버튼 — 카드(ApplicantRowSurface) 안의 InkWell › Container(카드 전체 InkWell 은 child 가 Padding 이라 빠진다).
            await shot('1top', 'rows-top');
            bool isRowBtn(Widget w) => w is InkWell && w.child is Container;
            final btnF = find.descendant(of: find.byType(ApplicantRowSurface), matching: find.byWidgetPredicate(isRowBtn), skipOffstage: true);
            final n = btnF.evaluate().length;
            need('행 버튼 ≥2', n >= 2, '개수 $n');
            var faces = 0;
            var lowCr = 0;
            var small = 0;
            var miss = 0;
            var offs = 0;
            var maxBrand = 0;
            final perRow = <int, int>{};
            final labels = <String>{};
            final rowsRaw = <String>[];
            final geo = <String>[];
            for (var i = 0; i < n; i++) {
              final one = btnF.at(i);
              // 문구는 위젯 값으로 먼저 모은다(자리와 무관 — 문구 집합은 두 모드에서 같아야 한다).
              labels.add(t.widget<Text>(find.descendant(of: one, matching: find.byType(Text), skipOffstage: true).first).data ?? '');
              await t.ensureVisible(one);
              for (var m = 0; m < 4; m++) {
                await t.pump(const Duration(milliseconds: 50));
              }
              // 보이는 것만 잰다 — 가장 가까운 스크롤 칸 안에 들어온 버튼만(아니면 세고 건너뛴다).
              final scF = find.ancestor(of: one, matching: find.byType(Scrollable));
              final nSc = scF.evaluate().length;
              final area = nSc == 0 ? (Offset.zero & Size(v.w, v.h)) : t.getRect(scF.first);
              final r0 = t.getRect(one);
              if (!_inside(r0, area)) {
                offs++;
                rowsRaw.add('$i 칸 밖 r=$r0 area=$area');
                continue;
              }
              final surfF = find.ancestor(of: one, matching: find.byType(ApplicantRowSurface));
              final surf = t.widget<ApplicantRowSurface>(surfF.first);
              final rowId = identityHashCode(surfF.evaluate().first);
              final p = _probe(t, one, Color.alphaBlend(surf.background, Colors.white));
              if (_classFace(p.fill)) faces++;
              if (p.cr < 4.5) lowCr++;
              if (!p.big) small++;
              if (!p.hit) miss++;
              if (p.fill == AppColors.brand) {
                final nb = (perRow[rowId] ?? 0) + 1;
                perRow[rowId] = nb;
                if (nb > maxBrand) maxBrand = nb;
              }
              geo.add('${p.label}:${p.r.width.toStringAsFixed(1)},${p.r.height.toStringAsFixed(1)},${_hex(p.fill)},${_hex(p.fg)},${p.cr.toStringAsFixed(2)}');
              rowsRaw.add('$i ${p.label} r=${p.r} fill=${_hex(p.fill)} fg=${_hex(p.fg)} cr=${p.cr.toStringAsFixed(2)} hit=${p.hit}');
            }
            final sorted = labels.toList()..sort();
            final setText = sorted.join('|');
            final nOwn = seen.own;
            final nUnk = seen.unk;
            raw = rowsRaw.join(' | ');
            _out('D527 $tok att btns n=$n set=${_enc(setText)} offs=$offs face0=${faces == 0} brand1=${maxBrand <= 1} cr45=${lowCr == 0} '
                'min48=${small == 0} hit=${miss == 0} own0=${nOwn == 0 && nUnk == 0}');
            _out('R527 $tok geo ${v.id} ${c.id} ${_enc(geo.join(';'))}');
            await shot('2end', 'rows-end');
            if (!_before) {
              chk('strict 행 버튼 문구 집합 불변', setText == _rowLabels.join('|'), 'set $setText');
              // [r2] B(320 · 2.0)는 기준에서 창 머리 · 통계가 높이를 다 써 목록 칸 높이가 0 이다(r1 TB: area 높이 0 · offs 14 · 창 Column 아래 넘침 69 —
              //   후보 밖 기존 결함). 보이는 버튼이 없어 B 의 면 · 대비 · 크기 · hit 는 잰 것 0 으로 통과한다 — B 에서 단언하는 것은 문구 집합과 행 버튼 줄 발 넘침 0 뿐이다.
              if (v.id == 'W') chk('strict W 행 버튼 14개를 모두 화면에 넣어 잼', offs == 0 && n == 14, 'offs $offs n $n');
              chk('strict 행 버튼 분류색 면 0', faces == 0, raw);
              chk('strict brand 채움 버튼 행당 ≤1', maxBrand <= 1, 'max $maxBrand');
              chk('strict 행 버튼 글자/면 대비 ≥4.5', lowCr == 0, raw);
              chk('strict 행 버튼 받는 자리 ≥48 · 중심 hit', small == 0 && miss == 0, raw);
              chk('strict 행 버튼 줄(:$_ownLo–$_ownHi) 발 넘침 0 · 위치 모르는 넘침 0', nOwn == 0 && nUnk == 0, 'own $nOwn unk $nUnk');
            }
          } else {
            // ② 일괄 띠 — '일괄선택' 켜기 → 전체 선택(화면 상태만 · 쓰기 0) → 하단 띠의 거절 · 확정.
            final togF = find.text('일괄선택');
            final nTog = togF.evaluate().length;
            need('일괄선택 1', nTog == 1, '개수 $nTog');
            await t.tap(find.ancestor(of: togF, matching: find.byType(InkWell)).first);
            for (var m = 0; m < 8; m++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final cbF = find.descendant(of: dlg, matching: find.byType(AppCheckbox), skipOffstage: true);
            final nCb = cbF.evaluate().length;
            need('일괄 모드 체크 ≥1', nCb >= 1, '개수 $nCb');
            await t.tap(cbF.first);
            for (var m = 0; m < 8; m++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            final barF = find.descendant(of: find.byType(AppModalFooter), matching: find.byType(InkWell), skipOffstage: true);
            final nBar = barF.evaluate().length;
            need('일괄 띠 버튼 2', nBar == 2, '개수 $nBar');
            var faces = 0;
            var lowCr = 0;
            var small = 0;
            var miss = 0;
            var brands = 0;
            var rejectFace = false;
            final labels = <String>[];
            final rowsRaw = <String>[];
            final geo = <String>[];
            for (var i = 0; i < nBar; i++) {
              final p = _probe(t, barF.at(i), Colors.white);
              labels.add(p.label);
              if (_classFace(p.fill)) faces++;
              if (p.cr < 4.5) lowCr++;
              if (!p.big) small++;
              if (!p.hit) miss++;
              if (p.fill == AppColors.brand) brands++;
              if (p.label == '거절' && p.fill.a != 0) rejectFace = true;
              geo.add('${p.label}:${p.r.width.toStringAsFixed(1)},${p.r.height.toStringAsFixed(1)},${_hex(p.fill)},${_hex(p.fg)},${p.cr.toStringAsFixed(2)}');
              rowsRaw.add('$i ${p.label} r=${p.r} fill=${_hex(p.fill)} fg=${_hex(p.fg)} cr=${p.cr.toStringAsFixed(2)} hit=${p.hit}');
            }
            labels.sort();
            final setText = labels.join('|');
            raw = rowsRaw.join(' | ');
            _out('D527 $tok att bulk n=$nBar set=${_enc(setText)} face0=${faces == 0} brand1=${brands == 1} textrej=${!rejectFace} cr45=${lowCr == 0} '
                'min48=${small == 0} hit=${miss == 0}');
            _out('R527 $tok geo ${v.id} ${c.id} ${_enc(geo.join(';'))}');
            await shot('1bulk', 'bulk-selected');
            if (!_before) {
              chk('strict 일괄 띠 문구 집합 불변', setText == _bulkLabels.join('|'), 'set $setText');
              chk('strict 일괄 띠 분류색 면 0 · 거절은 면 없는 글자', faces == 0 && !rejectFace, raw);
              chk('strict 일괄 띠 brand 채움 정확히 1(확정)', brands == 1, raw);
              chk('strict 일괄 띠 글자/면 대비 ≥4.5', lowCr == 0, raw);
              chk('strict 일괄 띠 받는 자리 ≥48', small == 0, raw);
              // B(320 · 2.0)의 일괄 띠 가로 넘침은 기준에 이미 있는 것으로 산술 예상(README · 후보 밖) — 중심 hit 는 W 에서만 단언한다.
              if (v.id == 'W') chk('strict W 일괄 띠 중심 hit', miss == 0, raw);
            }
          }
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // ③ 성공 · 실패 공통 정리 — 창을 내리고 남은 timer · 지연 응답이 끝날 시간을 준다.
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

        // ④ 집계 — 읽기 · 채널 · HTTP 는 기록(수). 쓰기 동작은 누르지 않았다.
        final nApps = reads.calls['applications'] ?? 0;
        final nUnexp = wire.unexpected.length;
        final nCf = wire.cf.length;
        final nHttp = net.tries.length;
        final unText = wire.unexpected.join(' | ');
        _out('D527 $tok att wire apps=$nApps cf=$nCf unexpected=$nUnexp http=$nHttp');

        messenger.allMessagesHandler = prevAll;
        HttpOverrides.global = prevHttp;
        WorkApplicantsReads.debugOverride = prevOverride;
        final exc = t.takeException();
        if (exc != null && failure == null) {
          failure = exc;
          failureSt = StackTrace.current;
        }
        final nOvf = seen.overflows.length;
        final nFw = seen.other.length;
        final ovfRaw = seen.overflows.join('\n----\n');
        final fwRaw = seen.other.join('\n----\n');
        _out('R527 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} un64=${_enc(unText)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')}');
        _out('D527 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        // 넘침 0 — W(기본 글자 크기)는 화면 전체. B 는 이 창이 아직 큰 글자 교정 전이라 화면 전체 수는 기록만 하고(TB · TA 대조),
        //   후보가 바꾼 행 버튼 줄 발 넘침 0 은 위 ROWS 에서 단언한다.
        if (!_before && v.id == 'W') chk('strict W 넘침 0', nOvf == 0, ovfRaw);
        chk('미처리 framework 예외 0', nFw == 0, fwRaw);
        chk('캡처 수 = 선언', shots == c.shots, 'shots $shots want ${c.shots}');
        final bad = checks.where((x) => !x.$2).toList();
        if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
        for (final x in checks) {
          expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
        }
      }, skip: !_optIn);
    }
  }
}
