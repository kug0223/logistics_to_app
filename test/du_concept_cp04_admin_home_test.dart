// ignore_for_file: depend_on_referenced_packages
// [CP04] 관리자 홈·할 일 — 8상태 × W/B = 16사례.
//   지시: records/requests/DU_concept_CP04_start_2026-11-12.md(정밀 §4–6·8–9, 문구 계약·관리자 전수표).
//   phase = DU1_VQ_PHASE=before|after. before = 원본 관측 기록(단언 없음), after = 확정 구성·문구·R 단언.
//   기존 LOCAL 진입 재사용: BusinessAdminHomeScreen(reads:) + AdminHomeReads 메모리 대역(admin_home_content_render_test.dart:362–479 모양),
//   provider 는 시험 대역(소유자·SubAdmin 권한 조합). 새 production seam 0, 무쓰기·무네트워크.
//   새 위젯 타입은 import 하지 않는다(글자·Semantics 로 찾는다 — before 컴파일).
//   상태: ownerSingle · ownerMulti · subContract · subWorkers · empty(정상0, 새로고침 전환) · allStaffed · partial · switchAB(A→B 지연, 권한 error 전환).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/ui/admin_home_summary_model.dart';
import 'package:ALfit/models/ui/staffing_readiness_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_home_reads.dart';
import 'package:ALfit/screens/business_admin/business_admin_home_screen.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';

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
const _biz2 = 'biz2';
const _bizName = '강남 물류센터';
const _longBiz = '강남구 테헤란로 제2물류센터 야간 상하차 전용 창고'; // CP01 인계(du_concept_cp01_header_test.dart:69)
const _longName = '응우옌 티 프엉 타오 쩐'; // CP01-C1 인계(:136)

/// 소유자(BUSINESS_ADMIN) — production 판정 경로(can·checkCurrentBusiness)를 그대로 쓰고 결과만 허용으로 준다.
class _Owner extends UserProvider {
  _Owner({this.bizIds = const [_biz1], this.displayName = '김관리'});
  final List<String> bizIds;
  final String displayName;
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: displayName, email: 'admin1@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: bizIds, sealBase64: 'seal');
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
}

/// SubAdmin — 사업장별 MemberPermissions 로 판정한다. 전환(switchTo)·권한 상태 error 전이는 production 과 같은 notifyListeners.
class _Sub extends UserProvider {
  _Sub({required this.perms, required this.names, required String current}) : _current = current;
  final Map<String, MemberPermissions> perms;
  final Map<String, String> names;
  String _current;
  PermissionWatchState _health = PermissionWatchState.verified;
  void switchTo(String id) {
    _current = id;
    notifyListeners();
  }

  void setHealthError() {
    _health = PermissionWatchState.error;
    notifyListeners();
  }

  @override
  UserModel? get currentUser => UserModel(
      uid: 'sub1', username: 'sub1', name: '박하위', email: 'sub1@alfit.local', role: UserRole.USER,
      subAdminBusinessIds: perms.keys.toList());
  @override
  bool get isSubAdmin => true;
  @override
  String? get effectiveBusinessId => _current;
  @override
  Map<String, String> get subAdminBusinessNames => names;
  @override
  bool get subAdminPermissionsLoaded => true;
  @override
  PermissionWatchState get currentBusinessPermissionHealth => _health;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) {
    if (_health == PermissionWatchState.error) return PermissionCheck.error;
    return check(perms[_current] ?? const MemberPermissions()) ? PermissionCheck.allowed : PermissionCheck.denied;
  }

  @override
  bool can(bool Function(MemberPermissions p) check) => check(perms[_current] ?? const MemberPermissions());
  @override
  bool canForAnyBusiness(bool Function(MemberPermissions p) check, {required bool whenUnknown}) => perms.values.any(check);
}

// ── 고정 시각(KST) — DU1_VQ_DATE 날의 10:00 (CP01·CP03 과 같은 산식) ──
final DateTime _clock = () {
  final k = vqNow().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day, 10).subtract(const Duration(hours: 9));
}();
final DateTime _today = FormatHelper.toKstDate(_clock);
String _ymd(int o) {
  final d = _today.add(Duration(days: o));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

const _wd = ['월', '화', '수', '목', '금', '토', '일'];
String _kDate(DateTime d) => '${d.month}월 ${d.day}일 ${_wd[d.weekday - 1]}요일';

BusinessModel _business(String id, String name) => BusinessModel(
    id: id, name: name, ownerId: 'admin1', businessNumber: '000-00-00000', address: '서울시 어딘가',
    category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));

Map<String, dynamic> _biz(String id, String name, int req, int conf, int short) =>
    {'businessId': id, 'businessName': name, 'requiredCount': req, 'confirmedCount': conf, 'shortageCount': short};

Map<String, dynamic> _day(int o, int req, int conf, int short, {int? pending, List<Map<String, dynamic>> byBusiness = const []}) => {
      'date': _ymd(o), 'requiredCount': req, 'confirmedCount': conf, 'shortageCount': short,
      if (pending != null) 'pendingCount': pending, 'pendingAvailable': pending != null, 'byBusiness': byBusiness,
    };

StaffingReadinessModel _staffing(List<Map<String, dynamic>> days, {bool partial = false, int failed = 0}) =>
    StaffingReadinessModel(
        available: true, partial: partial, failedBusinessCount: failed, publishedPostingCount: 1,
        days: days.map(StaffingDayData.fromMap).toList());

class _Template extends Fake implements ContractTemplateModel {
  @override
  bool get isSupportedForNewUse => true;
}

Map<String, BusinessPostingReadiness> _ready(List<BusinessModel> bizs) => {
      for (final b in bizs)
        b.id: BusinessPostingReadiness(
            bizId: b.id, isApproved: true, hasCanonicalLicense: true, hasOwnerLegacyLicense: false,
            hasActiveWorkTypes: true, hasEmployerSeal: true),
    };

/// 할 일 canonical(CF 직렬화 모양 그대로 — 모델 파싱은 production).
AdminHomeSummaryModel _summary({
  int resign = 0, int? manual, int soon = 0, int approval = 0, int approvalOverdue = 0, int schedule = 0,
  int unsent = 0, int unclosed = 0, String? oldest, int settlement = 0, int wageChange = 0,
  int unpaid = 0, int unpaidOverdue = 0, int missing = 0, int expiring = 0, int expired = 0,
  Set<String> unavailable = const {},
}) {
  Map<String, dynamic> s(String key, int count) => {
        'available': !unavailable.contains(key), 'count': count,
        'byBusiness': [{'businessId': _biz1, 'count': count}],
      };
  return AdminHomeSummaryModel.fromMap({
    'actions': {
      'resignRequest': {...s('resign', resign), 'soonCount': soon, 'manualReviewCount': manual},
      'approval': {...s('approval', approval), 'overdueCount': approvalOverdue},
      'scheduleChangeRequest': s('schedule', schedule),
      'unsentContract': s('unsent', unsent),
      'unclosed': {...s('unclosed', unclosed), 'oldestDate': oldest},
      'settlementRequest': s('settlement', settlement),
      'wageChangeRequest': s('wageChange', wageChange),
      'unpaidWage': {
        ...s('unpaid', unpaid), 'overdueCount': unpaidOverdue, 'missingDueDateCount': missing,
        'byBusiness': [{'businessId': _biz1, 'count': unpaid, 'missingDueDateCount': missing}],
      },
    },
    'upcoming': {
      'expiringContract': {...s('expiring', expiring), 'upcomingCount': expiring - expired, 'expiredCount': expired},
    },
  });
}

ApplicationModel _app(String id, String bizId, String bizName, String work, String start, String end) => ApplicationModel(
    id: id, toId: 'to_$id', uid: 'w_$id', businessId: bizId, businessName: bizName, toTitle: '단기 공고',
    status: AppStatus.confirmed, selectedWorkType: work, startTime: start, endTime: end, wage: 12000, wageType: 'hourly',
    workDate: _today, appliedAt: _today.subtract(const Duration(days: 3)));

/// 출근 기록 — 오늘 해당 근무 시작에 출근(검토 대상이 되지 않게).
AttendanceModel _checkedIn(ApplicationModel a) {
  final h = int.parse(a.startTime.split(':').first);
  return AttendanceModel(
    id: 'att_${a.id}', applicationId: a.id, userId: a.uid, businessId: a.businessId, businessName: a.businessName,
    workDate: _today, workType: a.selectedWorkType, status: AttendanceModel.statusPresent,
    wageStatus: AttendanceModel.wagePending, adminConfirmed: false,
    checkInAt: DateTime.utc(_today.year, _today.month, _today.day, h).subtract(const Duration(hours: 9)),
    checkOutAt: null, createdAt: _today,
  );
}

typedef _Fx = ({
  UserProvider Function() provider,
  List<BusinessModel> businesses,
  List<Future<StaffingReadinessModel> Function()> staffingByCall,
  AdminHomeSummaryModel summary,
  List<ApplicationModel> roster,
  bool rosterFailsAfterFirst,
});

/// 사례별 대역 — 각 사례가 새로 만든다(공유 상태 0).
_Fx _fixture(String state) {
  final single = [_business(_biz1, _bizName)];
  final multi = [_business(_biz1, _bizName), _business(_biz2, _longBiz)];
  Future<StaffingReadinessModel> Function() v(StaffingReadinessModel m) => () => Future.value(m);
  final rosterSingle = [
    _app('r1', _biz1, _bizName, '피킹', '09:00', '18:00'),
    _app('r2', _biz1, _bizName, '피킹', '09:00', '18:00'),
    _app('r3', _biz1, _bizName, '피킹', '09:00', '18:00'),
  ];
  switch (state) {
    case 'ownerSingle':
      return (
        provider: () => _Owner(),
        businesses: single,
        staffingByCall: [v(_staffing([_day(0, 5, 3, 2), _day(1, 3, 2, 1, pending: 2), _day(3, 2, 2, 0)]))],
        summary: _summary(resign: 1, manual: 1, soon: 1, approval: 3, approvalOverdue: 1, schedule: 2, unsent: 1,
            unclosed: 4, oldest: '2026-11-03'),
        roster: rosterSingle,
        rosterFailsAfterFirst: false,
      );
    case 'ownerMulti':
      return (
        provider: () => _Owner(bizIds: const [_biz1, _biz2], displayName: _longName),
        businesses: multi,
        staffingByCall: [
          v(_staffing([
            _day(0, 8, 5, 2, byBusiness: [_biz(_biz1, _bizName, 3, 3, 0), _biz(_biz2, _longBiz, 5, 2, 2)]),
            _day(2, 4, 1, 3, pending: 1, byBusiness: [_biz(_biz1, _bizName, 2, 1, 1), _biz(_biz2, _longBiz, 2, 0, 2)]),
          ]))
        ],
        summary: _summary(settlement: 1, wageChange: 1, unpaid: 2, unpaidOverdue: 1, missing: 1, expiring: 3, expired: 1),
        roster: [
          _app('m1', _biz1, _bizName, '피킹', '09:00', '18:00'),
          _app('m2', _biz2, _longBiz, '포장', '09:30', '13:30'),
        ],
        rosterFailsAfterFirst: false,
      );
    case 'subContract':
      return (
        provider: () => _Sub(
            perms: const {_biz1: MemberPermissions(canManageContract: true), _biz2: MemberPermissions(canManageContract: true)},
            names: const {_biz1: _longBiz, _biz2: '강남 물류센터 2공장'},
            current: _biz1),
        businesses: [_business(_biz1, _longBiz)],
        staffingByCall: [v(_staffing([_day(0, 2, 2, 0)]))],
        summary: _summary(unsent: 1, expiring: 2),
        roster: const [],
        rosterFailsAfterFirst: false,
      );
    case 'subWorkers':
      return (
        provider: () => _Sub(
            perms: const {_biz1: MemberPermissions(canManageWorkers: true)}, names: const {_biz1: _bizName}, current: _biz1),
        businesses: single,
        staffingByCall: [v(_staffing([_day(0, 5, 3, 2), _day(1, 3, 2, 1, pending: 2)]))],
        summary: _summary(resign: 2, schedule: 1),
        roster: rosterSingle,
        rosterFailsAfterFirst: false,
      );
    case 'empty':
      return (
        provider: () => _Owner(),
        businesses: single,
        staffingByCall: [
          v(_staffing([_day(0, 0, 0, 0), _day(2, 2, 2, 0)])),
          v(_staffing([_day(0, 0, 0, 0), _day(2, 2, 2, 0)])),
        ],
        summary: _summary(),
        roster: const [],
        rosterFailsAfterFirst: true,
      );
    case 'allStaffed':
      return (
        provider: () => _Owner(),
        businesses: single,
        staffingByCall: [v(_staffing([_day(0, 3, 3, 0)]))],
        summary: _summary(unclosed: 1),
        roster: rosterSingle,
        rosterFailsAfterFirst: false,
      );
    case 'partial':
      return (
        provider: () => _Owner(bizIds: const [_biz1, _biz2]),
        businesses: multi,
        staffingByCall: [
          v(_staffing([_day(0, 3, 3, 0), _day(1, 2, 1, 1)], partial: true, failed: 1)),
          v(_staffing([_day(0, 3, 3, 0), _day(1, 2, 1, 1)], partial: true, failed: 1)),
        ],
        summary: _summary(approval: 2, unavailable: const {'unsent'}),
        roster: rosterSingle,
        rosterFailsAfterFirst: false,
      );
    default: // switchAB
      return (
        provider: () => _Sub(
            perms: const {
              _biz1: MemberPermissions(canManageTo: true, canManageWorkers: true),
              _biz2: MemberPermissions(canManageTo: true),
            },
            names: const {_biz1: _bizName, _biz2: '강남 물류센터 2공장'},
            current: _biz1),
        businesses: single,
        staffingByCall: const [],
        summary: _summary(approval: 1),
        roster: const [],
        rosterFailsAfterFirst: false,
      );
  }
}

AdminHomeReads _reads(_Fx fx, Map<String, int> calls, List<String?> scopes,
    {List<Future<StaffingReadinessModel>>? staffingOverride}) {
  var staffingCall = 0;
  var rosterCall = 0;
  return AdminHomeReads(
    summary: ({String? selectedBusinessId}) {
      calls['summary'] = (calls['summary'] ?? 0) + 1;
      return Future.value(fx.summary);
    },
    businessesByIds: (ids) async => fx.businesses,
    staffingReadiness: ({String? selectedBusinessId}) {
      calls['staffing'] = (calls['staffing'] ?? 0) + 1;
      scopes.add(selectedBusinessId);
      final i = staffingCall++;
      if (staffingOverride != null && i < staffingOverride.length) return staffingOverride[i];
      final list = fx.staffingByCall;
      return list[i < list.length ? i : list.length - 1]();
    },
    attendanceByDate: ({required String businessId, required DateTime date}) async =>
        [for (final a in fx.roster) if (a.businessId == businessId) _checkedIn(a)],
    confirmedWorkers: ({required DateTime date, required String businessId}) async {
      calls['roster'] = (calls['roster'] ?? 0) + 1;
      rosterCall++;
      if (fx.rosterFailsAfterFirst && rosterCall > 1) throw StateError('CP04 LOCAL 로스터 조회 실패 fixture');
      return [for (final a in fx.roster) if (a.businessId == businessId) a];
    },
    workDetailTimes: (_) async => <String, dynamic>{},
    postingReadiness: (bizs) async => _ready(bizs),
    contractTemplates: (_) async => <ContractTemplateModel>[_Template()],
    tourCompleted: () => Future<bool>.value(true),
    clock: () => _clock,
    legalReadiness: () async => const LegalReadiness(status: LegalReadinessStatus.current),
  );
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

// ── 실행량(CP04 상한: 사례·mount 16 · 물리탭+의미 dispatch 48 · scroll/drag/ensureVisible 24 · pump+mount 1000 · PNG 12쌍) ──
int _mounts = 0, _pumps = 0, _pngs = 0, _taps = 0, _actions = 0, _scrolls = 0;
final _cases = <String>{};
final _diag = Expando<String>('cp04-diag');

typedef _V = ({String id, Size size, double scale});
const _V _w = (id: 'W', size: Size(390, 844), scale: 1.0);
const _V _b = (id: 'B', size: Size(320, 640), scale: 2.0);

void main() {
  final phase = vqPhase ?? '';
  final env = Platform.environment;
  final meta = env['CP04_META'] ?? '';
  final after = phase == 'after';
  test('CP04 실행 조건', () {
    expect(phase == 'before' || phase == 'after', isTrue, reason: 'DU1_VQ_PHASE=before|after');
    expect(env['DU1_VQ_DATE'], '2026-11-11', reason: '고정 KST 날짜(CP01 계보)');
    expect((env['DU1_VQ_RUN'] ?? '').isNotEmpty, isTrue);
    expect((env['DU1_VQ_OUT'] ?? '').contains('cp04-admin-home'), isTrue);
    expect(meta.contains('runner='), isTrue, reason: 'CP04_META(runner SHA 포함)');
  });
  setUp(() => SharedPreferences.setMockInitialValues({'tour_completed_business_admin_home': true}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    await _loadFonts();
  });

  Future<void> collecting(WidgetTester t, Future<void> Function(List<FlutterErrorDetails> errors) body) async {
    final errors = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      _diag[d] = TextTreeRenderer(wrapWidth: 400).render(d.toDiagnosticsNode(style: DiagnosticsTreeStyle.error));
      errors.add(d);
    };
    try {
      await body(errors);
    } finally {
      FlutterError.onError = prev;
    }
  }

  Future<void> settle(WidgetTester t, int n) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
      _pumps++;
    }
  }

  Future<GlobalKey> open(WidgetTester t, _V v, UserProvider provider, AdminHomeReads reads) async {
    final key = GlobalKey();
    t.view.physicalSize = v.size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: provider),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
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
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.scale)), child: child!),
          home: BusinessAdminHomeScreen(reads: reads),
        ),
      ),
    ));
    _mounts++;
    await settle(t, 20);
    return key;
  }

  // ── 찾기·측정 ──
  Finder plain(String s) => find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? '') == s);
  Finder plainRich(String s) =>
      find.byWidgetPredicate((w) => w is Text && w.textSpan != null && TextLayout.plain(w.textSpan!.toPlainText()) == s);
  Finder semLabel(String s) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == s);
  /// receiver 의미 node — container Semantics 만. 안쪽 Text 가 같은 semanticsLabel 로 만드는 Semantics(container 아님)는 제외한다.
  Finder semRecv(String s) => find.byWidgetPredicate((w) => w is Semantics && w.container && w.properties.label == s);
  RenderParagraph para(WidgetTester t, Finder text) =>
      t.renderObject<RenderParagraph>(find.descendant(of: text, matching: find.byType(RichText)).first);
  SemanticsNode node(WidgetTester t, Finder f) => t.semantics.find(f);
  final ctl = RegExp('[${String.fromCharCode(0x2060)}${String.fromCharCode(0x200B)}${String.fromCharCode(0x00A0)}]');

  Map<String, Object?> textRec(WidgetTester t, String s) {
    final f = plain(s);
    final n = f.evaluate().length;
    if (n == 0) return {'text': s, 'count': 0};
    final r = t.getRect(f.first);
    final rp = para(t, f.first);
    final st = rp.text.style;
    return {
      'text': s, 'count': n, 'rect': [r.left, r.top, r.width, r.height], 'exceeded': rp.didExceedMaxLines,
      'maxLines': rp.maxLines, 'scale': rp.textScaler.scale(10) / 10, 'size': st?.fontSize,
      'weight': st?.fontWeight?.value, 'color': st?.color?.toARGB32().toRadixString(16),
    };
  }

  bool hitAt(WidgetTester t, Offset p, Finder receiver) {
    final ro = t.renderObject(receiver);
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
    return hit.path.any((e) => identical(e.target, ro));
  }

  void log(String id, Map<String, Object?> m) {
    // ignore: avoid_print
    print('CP04-MEASURE $id ${jsonEncode(m)}');
  }

  void judgeErrors(String id, List<FlutterErrorDetails> errs) {
    final lines = [
      for (final e in errs)
        '${e.exceptionAsString().split(String.fromCharCode(10)).first} @ ${RegExp(r'[A-Za-z_]+[.]dart:[0-9]+:[0-9]+').allMatches(_diag[e] ?? '').map((x) => x.group(0)).toSet().join(',')}',
    ];
    // ignore: avoid_print
    print('CP04-ERRORS $id ${jsonEncode(lines)}');
    if (after) expect(lines, isEmpty, reason: '$id 렌더 오류 0');
  }

  Finder vScroll() => find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
  double vOffset(WidgetTester t) => t.state<ScrollableState>(vScroll().first).position.pixels;
  Rect viewRect(WidgetTester t) => t.getRect(vScroll().first);

  Future<void> shot(WidgetTester t, GlobalKey key, String id, _V v, String fixture, {required String frame}) async {
    await vqCapture(t, key, id, conditions: {
      'id': id, 'phase': phase, 'fixture': fixture, 'viewport': '${v.size.width.toInt()}x${v.size.height.toInt()}', 'dpr': 1.0,
      'textScaler': v.scale, 'locale': 'ko_KR', 'clock': _clock.toIso8601String(), 'date': env['DU1_VQ_DATE'],
      'run': env['DU1_VQ_RUN'], 'meta': meta, 'frame': frame, 'offset': vOffset(t), 'semantics': 'ensureSemantics 켬',
      'fonts': 'NotoSansKR Regular+Bold(Roboto 별칭) · FlutterTest=Regular · MaterialIcons(SDK)',
    });
    if (vqEnabled) _pngs++;
  }

  Future<void> reach(WidgetTester t, Finder f) async {
    await t.ensureVisible(f.first);
    _scrolls++;
    await settle(t, 3);
  }

  Future<void> dispatchTap(WidgetTester t, Finder f) async {
    final n = node(t, f);
    n.owner!.performAction(n.id, SemanticsAction.tap);
    _actions++;
    await settle(t, 6);
  }

  /// 최종 의미 node 의 label·button·tap(위젯 label 존재·좌표 탭으로 대신하지 않는다).
  void expectNode(WidgetTester t, Finder f, String id, {required String label, required bool tap}) {
    final d = node(t, f).getSemanticsData();
    expect(d.label, label, reason: '$id 의미 이름 원문');
    expect(ctl.hasMatch(d.label), isFalse, reason: '$id 의미 이름 제어문자 0');
    expect(d.flagsCollection.isButton, isTrue, reason: '$id button');
    expect(d.hasAction(SemanticsAction.tap), tap, reason: '$id tap action');
  }

  /// 의미 onTap 과 실제 receiver(GestureDetector·InkWell) onTap 이 같은 콜백인가 — 목적지는 실행하지 않는다.
  void expectSameCallback(WidgetTester t, Finder sem, String id) {
    final sw = t.widget<Semantics>(sem);
    final gd = find.descendant(of: sem, matching: find.byType(GestureDetector));
    final ink = find.descendant(of: sem, matching: find.byType(InkWell));
    final receiverTap = ink.evaluate().isNotEmpty
        ? t.widget<InkWell>(ink.first).onTap
        : t.widget<GestureDetector>(gd.first).onTap;
    expect(sw.properties.onTap, isNotNull, reason: '$id 의미 onTap');
    expect(sw.properties.onTap == receiverTap, isTrue, reason: '$id 의미 onTap = receiver onTap(같은 콜백)');
  }

  /// receiver ≥48×48·이 스크롤 위치에서 화면 안·중심 hit.
  void expectReceiver(WidgetTester t, Finder sem, _V v, String id, {bool onScreen = true}) {
    final r = t.getRect(sem);
    expect(r.width, greaterThanOrEqualTo(48), reason: '$id receiver 폭 ≥48');
    expect(r.height, greaterThanOrEqualTo(48), reason: '$id receiver 높이 ≥48');
    if (onScreen) {
      final vr = viewRect(t);
      expect(r.top >= vr.top - 0.5 && r.bottom <= vr.bottom + 0.5 && r.left >= -0.5 && r.right <= v.size.width + 0.5, isTrue,
          reason: '$id 화면 안');
      expect(hitAt(t, r.center, sem), isTrue, reason: '$id 중심 hit');
    }
  }

  /// 대상 낱말(공백 기준)의 글자가 같은 줄에 있는가(실제 줄상자).
  void expectWordsKept(RenderParagraph rp, String original, String id) {
    final disp = rp.text.toPlainText(includeSemanticsLabels: false);
    final idx = <int>[];
    for (var i = 0; i < disp.length; i++) {
      final c = disp.codeUnitAt(i);
      if (c != 0x2060 && c != 0x200B) idx.add(i);
    }
    final p = TextLayout.plain(disp);
    expect(p, original, reason: '$id 표시 원문 전문');
    var from = 0;
    for (final w in original.split(' ')) {
      if (w.isEmpty || w == '·') continue;
      final at = p.indexOf(w, from);
      expect(at >= 0, isTrue, reason: '$id 낱말 $w');
      final tops = <double>[];
      for (var k = at; k < at + w.length; k++) {
        for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: idx[k], extentOffset: idx[k] + 1))) {
          tops.add(b.top);
        }
      }
      final lo = tops.reduce((a, b) => a < b ? a : b), hi = tops.reduce((a, b) => a > b ? a : b);
      expect(hi - lo, lessThan(1.0), reason: '$id 낱말 `$w` 한 줄(lo=$lo hi=$hi)');
      from = at + w.length;
    }
  }

  /// 홈 안의 모든 문단: 말줄임/잘림 0·실제 배율(전체 R 그물).
  Map<String, Object?> sweepParagraphs(WidgetTester t, _V v, String id) {
    var n = 0;
    final bad = <String>[];
    for (final e in find.byType(RichText).evaluate()) {
      final ro = e.renderObject;
      if (ro is! RenderParagraph) continue;
      n++;
      if (ro.didExceedMaxLines) bad.add('exceeded:${TextLayout.plain(ro.text.toPlainText(includeSemanticsLabels: false))}');
    }
    if (after) expect(bad, isEmpty, reason: '$id 말줄임/잘림 문단 0');
    return {'paragraphs': n, 'bad': bad};
  }

  String taskLabel(String title, String desc, [List<String> subs = const []]) => [title, desc, ...subs, '열기'].join(', ');

  final cases = <({String state, bool pngW, bool pngB, String fixture})>[
    (state: 'ownerSingle', pngW: true, pngB: true, fixture: '소유자 1곳 · 오늘 5명 중 3명·2명 추가 필요 · 할 일 5종 · 다가오는 2일'),
    (state: 'ownerMulti', pngW: true, pngB: true, fixture: '소유자 2곳(긴 사업장)·긴 이름 · 부족 위치·집계 차이 · 업무 2개 · 할 일 4종'),
    (state: 'subContract', pngW: true, pngB: true, fixture: 'SubAdmin 계약 단독 · 긴 사업장 배지 ▼ · noPostingScope · 계약 할 일 2종'),
    (state: 'subWorkers', pngW: true, pngB: false, fixture: 'SubAdmin 인력 단독 · 부족 필(행동 없음) · 명단 보기 · 퇴사·일정'),
    (state: 'empty', pngW: true, pngB: false, fixture: '정상0 · noToday(허용·빈 로스터) · 처리할 업무 0 · 새로고침 뒤 로스터 실패'),
    (state: 'allStaffed', pngW: true, pngB: false, fixture: '오늘 3명 전원 확정 · 출근 known · normalToday'),
    (state: 'partial', pngW: true, pngB: false, fixture: '2곳 중 1곳 실패(partial) · 일부 할 일 미확인 · 다시 시도'),
    (state: 'switchAB', pngW: true, pngB: false, fixture: 'SubAdmin A→B 전환(A 응답 지연·폐기) · B 근태 권한 없음 → error 전환'),
  ];

  for (final v in const [_w, _b]) {
    for (final c in cases) {
      testWidgets('CP04 ${c.state} ${v.id}', (t) async {
        _cases.add('${c.state}-${v.id}');
        final semH = t.ensureSemantics();
        try {
          await collecting(t, (errs) async {
            final id = '${c.state}-${v.id}';
            final fx = _fixture(c.state);
            final calls = <String, int>{};
            final scopes = <String?>[];
            final provider = fx.provider();
            Completer<StaffingReadinessModel>? lateA;
            List<Future<StaffingReadinessModel>>? staffOverride;
            if (c.state == 'switchAB') {
              lateA = Completer<StaffingReadinessModel>();
              staffOverride = [
                lateA.future,
                Future.value(_staffing([_day(0, 0, 0, 0)])),
              ];
            }
            final key = await open(t, v, provider, _reads(fx, calls, scopes, staffingOverride: staffOverride));
            if (c.state == 'switchAB') {
              // A 응답이 오기 전에 B 로 전환 → B 응답 → 늦은 A 응답(오늘 5명 추가 필요)은 버려져야 한다.
              (provider as _Sub).switchTo(_biz2);
              await settle(t, 10);
              lateA!.complete(_staffing([_day(0, 5, 0, 5)]));
              await settle(t, 10);
            }
            final pngHere = (v.id == 'W' && c.pngW) || (v.id == 'B' && c.pngB && c.state != 'ownerMulti');
            if (pngHere) await shot(t, key, 'CP04-${c.state}-${v.id}', v, c.fixture, frame: 'offset0');

            final rec = <String, Object?>{
              'state': c.state, 'calls': Map.of(calls), 'scopes': scopes,
              for (final s in ['오늘 운영을 한눈에', _kDate(_today), '+ 공고 등록', '오늘의 근무', '오늘', '처리할 일', '다가오는 근무',
                '다가오는 7일', '앞으로 7일', '명단 보기', '당일 명단', '인원 현황 보기', '2명 추가 필요', '2명 부족', '처리할 업무가 없어요'])
                s: textRec(t, s),
              'sweep': sweepParagraphs(t, v, id),
            };
            log('$id-open', rec);

            if (after) {
              // ── 머리(정밀 §8·§9) ──
              final head = plain('오늘 운영을 한눈에');
              expect(head, findsOneWidget, reason: '$id 큰 운영 머리');
              expect(para(t, head).text.style?.fontSize, 24);
              expect(para(t, head).text.style?.fontWeight, FontWeight.w700);
              final date = plain(_kDate(_today));
              expect(date, findsOneWidget, reason: '$id KST 날짜(고정 clock)');
              expect(para(t, date).text.style?.fontSize, 14);
              expect(t.getRect(date).top - t.getRect(head).bottom, closeTo(4, 0.5), reason: '$id 머리→날짜 4');
              // [CP04 C1] 실측 기록 — Text 값은 RenderParagraph 상자(잉크 아님), receiver 값은 의미 Semantics 상자.
              final dateR = t.getRect(date);
              final c1 = <String, Object?>{
                'measured': 'Text=RenderParagraph 상자(잉크 아님) · receiver=의미 Semantics 상자',
                'headTextBottom': t.getRect(head).bottom,
                'dateText': [dateR.left, dateR.top, dateR.width, dateR.height],
              };
              final canCreate = c.state.startsWith('owner') || c.state == 'empty' || c.state == 'allStaffed' ||
                  c.state == 'partial' || c.state == 'switchAB';
              final reg = semRecv('공고 등록');
              if (canCreate) {
                expect(reg, findsOneWidget, reason: '$id `+ 공고 등록`(허용)');
                expect(plain('+ 공고 등록'), findsWidgets);
                expectNode(t, reg, '$id 공고 등록', label: '공고 등록', tap: true);
                expectSameCallback(t, reg, '$id 공고 등록');
                expectReceiver(t, reg, v, '$id 공고 등록');
                final regText = find.descendant(of: reg, matching: plain('+ 공고 등록'));
                expect(regText, findsOneWidget, reason: '$id 등록 Text');
                final regTextR = t.getRect(regText), regR = t.getRect(reg);
                c1['regText'] = [regTextR.left, regTextR.top, regTextR.width, regTextR.height];
                c1['regReceiver'] = [regR.left, regR.top, regR.width, regR.height];
                if (v.id == 'W') {
                  // [CP04 C1] W 등록 허용 = 같은 줄 분기 — 날짜 Text 상자 top 과 등록 Text 상자 top 이 같은 줄(±0.5).
                  expect(regTextR.top, closeTo(dateR.top, 0.5), reason: '$id 날짜·등록 Text 위쪽 같은 줄');
                }
              } else {
                expect(semLabel('공고 등록'), findsNothing, reason: '$id 권한 없으면 등록 없음');
              }
              expect(find.textContaining('›'), findsNothing, reason: '$id 문자열 꺾쇠 0');

              // 머리 이름·사업장(CP01 인계)
              final nameText = c.state == 'ownerMulti' ? '$_longName님' : (provider is _Sub ? '박하위님' : '김관리님');
              final nm = plain(nameText);
              expect(nm, findsOneWidget, reason: '$id 이름');
              expectWordsKept(para(t, nm), nameText, '$id 이름(마지막 낱말+님)');
              expect(semLabel(nameText), findsOneWidget, reason: '$id 이름 의미 원문');
              if (c.state == 'subContract') {
                final badge = plain('$_longBiz ▼');
                expect(badge, findsOneWidget, reason: '$id 사업장 배지 전문');
                expectWordsKept(para(t, badge), '$_longBiz ▼', '$id 사업장 배지 낱말');
                final sel = find.ancestor(of: badge, matching: find.byType(GestureDetector)).first;
                final r = t.getRect(sel);
                expect(r.width >= 48 && r.height >= 48, isTrue, reason: '$id 사업장 선택 receiver ≥48');
              }

              // ── 섹션 제목 20/700·순서 ──
              final ys = <String, double>{'head': t.getRect(head).top};
              for (final s in ['오늘의 근무', '처리할 일', '다가오는 근무']) {
                final f = plain(s);
                if (f.evaluate().isEmpty) continue;
                expect(para(t, f).text.style?.fontSize, 20, reason: '$id 섹션 $s 20');
                ys[s] = t.getRect(f).top;
              }
              final order = ['head', '오늘의 근무', '처리할 일', '다가오는 근무'].where(ys.containsKey).toList();
              for (var i = 1; i < order.length; i++) {
                expect(ys[order[i]]! > ys[order[i - 1]]!, isTrue, reason: '$id 순서 ${order[i - 1]} < ${order[i]}');
              }
              for (final old in ['오늘', '당일 명단', '다가오는 7일', '2명 부족', '오늘 근무는 문제없이 진행 중이에요']) {
                expect(plain(old), findsNothing, reason: '$id 옛 문구 `$old` 없음');
              }
              if (plain('다가오는 근무').evaluate().isNotEmpty) {
                expect(plain('앞으로 7일'), findsOneWidget, reason: '$id 범위 `앞으로 7일`');
              }
              // ── [CP04 C1] 섹션 제목 왼쪽 = gutter(W20/B16)±0.5 ──
              //   fixture·권한 조건상 보여야 할 제목을 먼저 정한다(원 B1 before 16사례 -open 기록과 같은 표시 조건 — 표시 gate 는 CP04 diff 밖).
              //   잰 값은 제목·부제 Text 상자(RenderParagraph)의 left(잉크 아님). 기대 제목을 못 찾으면 실패다(건너뛰지 않는다).
              final expectTitles = switch (c.state) {
                'subContract' || 'switchAB' => const ['처리할 일'],
                'empty' => const ['처리할 일', '다가오는 근무'],
                'allStaffed' => const ['오늘의 근무', '처리할 일'],
                _ => const ['오늘의 근무', '처리할 일', '다가오는 근무'],
              };
              final gutter = v.id == 'W' ? 20.0 : 16.0;
              for (final s in const ['오늘의 근무', '처리할 일', '다가오는 근무']) {
                expect(plain(s), expectTitles.contains(s) ? findsOneWidget : findsNothing, reason: '$id 섹션 $s 표시(fixture 조건)');
              }
              final lefts = <String, double>{};
              for (final s in [...expectTitles, if (expectTitles.contains('다가오는 근무')) '앞으로 7일']) {
                lefts[s] = t.getRect(plain(s)).left;
                expect(lefts[s], closeTo(gutter, 0.5), reason: '$id `$s` Text left = gutter $gutter');
              }
              c1['gutter'] = gutter;
              c1['titleTextLeft'] = lefts;
              c1['sectionTitleTop'] = Map.of(ys);
              log('$id-c1', c1);
              if (plain('명단 보기').evaluate().isNotEmpty) {
                final roster = semRecv('명단 보기');
                expectNode(t, roster, '$id 명단 보기', label: '명단 보기', tap: true);
                expectSameCallback(t, roster, '$id 명단 보기');
                expectReceiver(t, roster, v, '$id 명단 보기', onScreen: false);
              }

              // ── 사례별 ──
              if (c.state == 'ownerSingle' || c.state == 'subWorkers') {
                final pill = plain('2명 추가 필요');
                expect(pill, findsOneWidget, reason: '$id `N명 추가 필요` 필 한 번');
                expect(para(t, pill).text.style?.color, AppColors.conceptStaffingNeedText, reason: '$id 필 글자 #8A4B00');
                final box = t.widget<Container>(find.ancestor(of: pill, matching: find.byType(Container)).first);
                expect((box.decoration as BoxDecoration?)?.color, AppColors.conceptStaffingNeedBg, reason: '$id 필 바탕 #FDEAC4');
                final staff = plainRich('5명 중 3명 확정');
                expect(staff, findsOneWidget, reason: '$id 인원 요약 원문');
                final spans = (t.widget<Text>(staff).textSpan! as TextSpan).children!.cast<TextSpan>();
                expect(spans.every((x) => x.style?.fontSize == 18), isTrue, reason: '$id 인원 18');
                expect(spans.where((x) => x.style?.fontWeight == FontWeight.w700).map((x) => x.text).toList(), ['3명'],
                    reason: '$id 확정 수만 700');
              }
              if (c.state == 'ownerSingle') {
                expect(plain('피킹 · 09:00–18:00'), findsOneWidget, reason: '$id 단일 업무·시간 머리');
                expect(para(t, plain('피킹 · 09:00–18:00')).text.style?.fontSize, 20);
                final drill = semRecv('인원 현황 보기');
                expectNode(t, drill, '$id 인원 현황 보기', label: '인원 현황 보기', tap: true);
                expectSameCallback(t, drill, '$id 인원 현황 보기');
                // 할 일 5종 — 정확 설명·알약·보조줄·순서·의미 이름
                final rows = [
                  ('퇴사 요청', '퇴사 요청 1건을 검토해 주세요', ['수동 검토 1건', '빠른 검토 필요 1건'], '1'),
                  ('지원 검토', '대기 중인 지원 3건을 확인해 주세요', ['긴급 1건'], '3'),
                  ('일정 변경 요청', '근로자의 일정 변경 요청 2건이 있어요', <String>[], '2'),
                  ('계약 미발송', '발송이 필요한 계약 1건이 있어요', <String>[], '1'),
                  ('마감 필요', '사업장별 미마감 근무일 합계 4일이에요', ['가장 오래된 날 2026.11.03'], '4일'),
                ];
                var lastY = -1.0;
                for (final (title, desc, subs, pill) in rows) {
                  final sem = semLabel(taskLabel(title, desc, subs));
                  expect(sem, findsOneWidget, reason: '$id 행 $title 의미 이름');
                  expectNode(t, sem, '$id 행 $title', label: taskLabel(title, desc, subs), tap: true);
                  expectSameCallback(t, sem, '$id 행 $title');
                  expect(find.descendant(of: sem, matching: plain(pill)), findsOneWidget, reason: '$id $title 알약 $pill');
                  final r = t.getRect(sem);
                  expect(r.height, greaterThanOrEqualTo(68), reason: '$id $title 행 ≥68');
                  expect(r.top > lastY, isTrue, reason: '$id 행 순서 $title');
                  lastY = r.top;
                }
                expect(para(t, plain('긴급 1건')).text.style?.color, AppColors.errorDark, reason: '$id 긴급만 errorDark');
                expect(para(t, plain('빠른 검토 필요 1건')).text.style?.color, AppColors.warningDark);
                expect(para(t, plain('대기 중인 지원 3건을 확인해 주세요')).text.style?.fontSize, 14);
                expect(para(t, plain('지원 검토')).text.style?.fontSize, 17);
                // 다가오는 근무
                expect(plain('내일'), findsOneWidget, reason: '$id D+1 = 내일(고정 clock)');
                expect(plain('1명 추가 필요'), findsOneWidget, reason: '$id 다가오는 부족');
                expect(para(t, plain('1명 추가 필요')).text.style?.color, AppColors.textSecondary, reason: '$id 다가오는 부족 중립색');
              }
              if (c.state == 'ownerMulti') {
                expect(plain('전체 2개 사업장 합계'), findsOneWidget, reason: '$id 집계 범위');
                expect(plain(_longBiz), findsWidgets, reason: '$id 부족 위치(긴 사업장)');
                expect(plain('필요·확정 인원과 추가 필요 인원은 집계 기준이 달라요'), findsOneWidget, reason: '$id 집계 기준 설명');
                expect(plain('지금 모집 중인 업무만 센 숫자예요'), findsNothing);
                expect(plain('확정 근무 · 업무 2개 · 시간대 2개'), findsOneWidget, reason: '$id 업무 여럿 — 대표 시간 없음');
                final rows = [
                  ('이체 대기', '이체 확인이 필요한 급여 3건이 있어요', ['연체 1건', '지급일 확인 필요 1건'], '3'),
                  ('중간정산 요청', '대기 중인 중간정산 요청 1건이 있어요', <String>[], '1'),
                  ('급여 변경 요청', '지급방식 변경 요청 1건을 확인해 주세요', <String>[], '1'),
                  ('계약 확인 필요', '연장·종료를 정할 계약 3건을 확인해 주세요', ['만료 후 미결정 1건'], '3'),
                ];
                var lastY = -1.0;
                for (final (title, desc, subs, pill) in rows) {
                  final sem = semLabel(taskLabel(title, desc, subs));
                  expect(sem, findsOneWidget, reason: '$id 행 $title');
                  expectNode(t, sem, '$id 행 $title', label: taskLabel(title, desc, subs), tap: true);
                  expect(find.descendant(of: sem, matching: plain(pill)), findsOneWidget, reason: '$id $title 알약 $pill');
                  expect(t.getRect(sem).top > lastY, isTrue, reason: '$id 행 순서(연체 이체 상향) $title');
                  lastY = t.getRect(sem).top;
                }
                expect(para(t, plain('연체 1건')).text.style?.color, AppColors.errorDark);
                expect(para(t, plain('만료 후 미결정 1건')).text.style?.color, AppColors.errorDark);
                expect(para(t, plain('지급일 확인 필요 1건')).text.style?.color, AppColors.textSecondary);
                if (v.id == 'B') {
                  // 할 일 도달 프레임 — 첫 행 전문·receiver·중심 hit
                  final first = semLabel(taskLabel('이체 대기', '이체 확인이 필요한 급여 3건이 있어요', ['연체 1건', '지급일 확인 필요 1건']));
                  await reach(t, first);
                  await shot(t, key, 'CP04-ownerMulti-B-tasks', v, c.fixture, frame: 'task-reach');
                  expectReceiver(t, first, v, '$id 이체 대기 행');
                  expectWordsKept(para(t, plain('이체 확인이 필요한 급여 3건이 있어요')), '이체 확인이 필요한 급여 3건이 있어요', '$id 이체 설명');
                }
              }
              if (c.state == 'subContract' || c.state == 'subWorkers') {
                expect(plain('공고 정보를 볼 수 있는 권한이 없어요'), findsOneWidget, reason: '$id noPostingScope');
                expect(
                    plain('공고를 관리할 수 있는 사업장이 배정되어 있지 않아요.${String.fromCharCode(10)}'
                        '필요하면 사업장 관리자에게 권한을 요청해 주세요'),
                    findsOneWidget,
                    reason: '$id noPostingScope 보조 두 문장(해요체)');
              }
              if (c.state == 'subContract') {
                expect(plain('오늘의 근무'), findsNothing, reason: '$id 계약 단독 — 오늘 숨김');
                expect(plain('다가오는 근무'), findsNothing);
                expect(semLabel(taskLabel('계약 미발송', '발송이 필요한 계약 1건이 있어요')), findsOneWidget);
                expect(semLabel(taskLabel('계약 확인 필요', '연장·종료를 정할 계약 2건을 확인해 주세요')), findsOneWidget);
              }
              if (c.state == 'subWorkers') {
                expect(semLabel('인원 현황 보기'), findsNothing, reason: '$id 공고 권한 없음 — 행동 없음');
                expect(plain('인원 현황 보기'), findsNothing);
                expect(semLabel(taskLabel('일정 변경 요청', '근로자의 일정 변경 요청 1건이 있어요')), findsOneWidget);
                expect(plain('스케줄 변경 요청'), findsNothing);
              }
              if (c.state == 'empty') {
                expect(plain('오늘 예정된 근무는 없어요${String.fromCharCode(10)}앞으로 7일은 추가 필요 인원이 없어요'), findsOneWidget,
                    reason: '$id noToday 허용·빈 로스터 + 7일 추가 필요 0');
                expect(plain('처리할 업무가 없어요'), findsOneWidget, reason: '$id 정상0');
                // 자연 전환 — 새로고침(RefreshIndicatorState.show: 당김과 같은 onRefresh 경로, scroll 1로 셈)
                //   → 로스터 2번째 호출 실패 → 확인하지 못함(부재 단정 0)
                unawaited(t.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show());
                _scrolls++;
                await settle(t, 20);
                expect(plain('오늘 근무 정보를 확인하지 못했어요'), findsOneWidget, reason: '$id 허용+null 문구');
                expect(plain('오늘 예정된 근무는 없어요'), findsNothing);
                log('$id-refresh', {'calls': Map.of(calls)});
              }
              if (c.state == 'allStaffed') {
                expect(plainRich('3명 전원 확정'), findsOneWidget, reason: '$id 전원 확정');
                expect(plain('오늘 근무 현황이에요'), findsOneWidget, reason: '$id normalToday');
              }
              if (c.state == 'partial') {
                expect(plain('오늘 상황을 일부만 확인했어요'), findsOneWidget, reason: '$id partialInfo');
                expect(plain('사업장 1곳의 정보를 불러오지 못해 나머지 사업장 기준으로 표시했어요'), findsWidgets);
                expect(plain('일부 업무 상태를 확인하지 못했어요'), findsOneWidget, reason: '$id 할 일 일부 미확인');
                expect(plain('전체 2개 사업장 합계'), findsNothing, reason: '$id partial 에서 합계 라벨 숨김');
                final retry = semLabel('다시 시도');
                expect(retry, findsWidgets);
                expectNode(t, retry.first, '$id 다시 시도', label: '다시 시도', tap: true);
                expectReceiver(t, retry.first, v, '$id 다시 시도', onScreen: false);
                final before = calls['staffing'] ?? 0;
                await dispatchTap(t, retry.first);
                await settle(t, 10);
                expect((calls['staffing'] ?? 0) > before, isTrue, reason: '$id 의미 tap → 같은 로더 재조회');
              }
              if (c.state == 'switchAB') {
                expect(scopes.contains(_biz2), isTrue, reason: '$id B 로 다시 읽음');
                expect(plain('5명 추가 필요'), findsNothing, reason: '$id 늦은 A 응답 폐기(seq)');
                expect(plain('근태 조회 권한이 없어요'), findsOneWidget, reason: '$id noToday denied');
                (provider as _Sub).setHealthError();
                await settle(t, 20);
                expect(plain('근태 조회 권한을 확인하지 못했어요'), findsOneWidget, reason: '$id noToday error');
                log('$id-transition', {'calls': Map.of(calls), 'scopes': scopes});
              }
              if (v.id == 'B') {
                // B: 마지막 섹션까지 전체 스크롤 도달
                final lastTitle = ['다가오는 근무', '처리할 일', '오늘의 근무'].firstWhere((s) => plain(s).evaluate().isNotEmpty,
                    orElse: () => '오늘 운영을 한눈에');
                await reach(t, plain(lastTitle));
                final r = t.getRect(plain(lastTitle));
                final vr = viewRect(t);
                expect(r.top >= vr.top - 0.5 && r.bottom <= vr.bottom + 0.5, isTrue, reason: '$id 마지막 섹션 도달');
              }
            }
            log('$id-end', {'taps': _taps, 'actions': _actions, 'scrolls': _scrolls, 'calls': calls});
            await t.pumpWidget(const SizedBox.shrink());
            _pumps++;
            await t.pump(const Duration(seconds: 5));
            _pumps++;
            judgeErrors(id, errs);
          });
        } finally {
          semH.dispose();
        }
      });
    }
  }

  tearDown(() {
    // ignore: avoid_print
    print('CP04-COUNT cases=${_cases.length} mounts=$_mounts pumps=$_pumps pumpPlusMount=${_pumps + _mounts} '
        'taps=$_taps actions=$_actions tapsPlusActions=${_taps + _actions} scrolls=$_scrolls pngPairs=$_pngs');
  });

  tearDownAll(() {
    // ignore: avoid_print
    print('CP04-FINAL phase=$phase cases=${_cases.length} mounts=$_mounts pumps=$_pumps pumpPlusMount=${_pumps + _mounts} '
        'taps=$_taps actions=$_actions scrolls=$_scrolls pngPairs=$_pngs');
    expect(_cases.length, lessThanOrEqualTo(16));
    expect(_mounts, lessThanOrEqualTo(16));
    expect(_taps + _actions, lessThanOrEqualTo(48));
    expect(_scrolls, lessThanOrEqualTo(24));
    expect(_pumps + _mounts, lessThanOrEqualTo(1000));
    expect(_pngs, lessThanOrEqualTo(12));
  });
}
