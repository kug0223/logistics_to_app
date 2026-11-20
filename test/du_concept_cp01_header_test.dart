// ignore_for_file: depend_on_referenced_packages
// [CP01] 공용 글자 로고·머리 receiver — 지원자 홈·관리자 홈 첫 화면(offset 0) 머리 관측/단언.
//   정본: records/reports/DU_concept_precise_spec_audit_2026-11-11.md §3, 지시 requests/DU_concept_precise_implementation_2026-11-11.md CP01.
//   phase 는 DU1_VQ_PHASE=before|after(없으면 실패). before = 원본 관측 기록(사전 결손은 실패로 만들지 않는다), after = 사양 단언.
//   무쓰기·무네트워크: reads 메모리 fixture, Firebase 가짜 플랫폼. 새 위젯 타입은 import 하지 않는다(이름 문자열로 찾는다 — before 컴파일).
//   SubAdmin 전환은 provider 대역이 호출만 기록한다(switchToAdminMode/toggleAdminMode — 실서비스·shell 라우팅 0, 라우팅은 미관측).
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
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/ui/admin_home_summary_model.dart';
import 'package:ALfit/models/ui/staffing_readiness_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_home_reads.dart';
import 'package:ALfit/screens/business_admin/business_admin_home_screen.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/widgets/common/business_selector_sheet.dart';

import 'support/checkin_contract_fixture.dart';
import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

// ── 가짜 Firebase (du1_vq_capture_test.dart:50–64 와 같은 모양) ──
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
const _longBiz = '강남구 테헤란로 제2물류센터 야간 상하차 전용 창고';

// ── 역할 provider(게터 덮개 — debugSetCurrentUser 로 ContractService 를 부르지 않는다) ──
/// ① 지원자 정상 (du1_vq_capture_test.dart:66–82)
class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구', district: '역삼동'),
      accountStatus: 'active', passVerifiedAt: DateTime.utc(2026, 10, 1), totalWorkDays: 3);
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

/// ③ SubAdmin — 같은 사람이 지원자 홈(지원자 모드)과 관리자 홈(관리자 모드)을 오간다. 사업장 2곳(긴 이름).
class _Sub extends UserProvider {
  _Sub({required this.adminMode, required this.calls});
  final bool adminMode;
  /// 전환 호출 기록(실제 provider 동작 대신) — `switchToAdminMode:biz` · `toggleAdminMode`.
  final List<String> calls;
  @override
  Future<void> switchToAdminMode(String businessId) async => calls.add('switchToAdminMode:$businessId');
  @override
  void toggleAdminMode() => calls.add('toggleAdminMode');
  @override
  UserModel? get currentUser => UserModel(
      uid: 'sub1', username: 'sub1', name: '박하위', email: 'sub1@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구', district: '역삼동'),
      accountStatus: 'active', passVerifiedAt: DateTime.utc(2026, 10, 1), totalWorkDays: 3,
      subAdminBusinessIds: const [_biz1, _biz2], sealBase64: 'seal');
  @override
  bool get isSubAdmin => true;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => adminMode;
  @override
  bool get permissionsLoaded => true;
  @override
  Map<String, String> get subAdminBusinessNames => const {_biz1: _longBiz, _biz2: '강남 물류센터 2공장'};
  @override
  String? get effectiveBusinessId => _biz1;
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

/// [CP01-C1] ③ 의 긴 사용자 이름 변형 — 이름만 다르고 나머지 상태는 `_Sub(adminMode: true)` 그대로(UserModel.copyWith(name)).
class _SubLong extends _Sub {
  _SubLong({required super.calls}) : super(adminMode: true);
  static const longName = '응우옌 티 프엉 타오 쩐';
  @override
  UserModel? get currentUser => super.currentUser?.copyWith(name: longName);
}

/// ② 소유자 단일 사업장 (admin_home_content_render_test.dart:128–169)
class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local', role: UserRole.BUSINESS_ADMIN,
      managedBusinessIds: const [_biz1], sealBase64: 'seal');
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

// ── 고정 시각(KST) — vqNow() 기준 날의 10:00 ──
final DateTime _clock = () {
  final k = vqNow().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day, 10).subtract(const Duration(hours: 9));
}();
final DateTime _today = FormatHelper.toKstDate(_clock);
DateTime _day(int o) => _today.add(Duration(days: o));
final String _todayStr =
    '${_today.year}-${_today.month.toString().padLeft(2, '0')}-${_today.day.toString().padLeft(2, '0')}';

// ── 지원자 홈 reads (du1_vq_capture_test.dart:117–140) ──
ApplicationModel _shift(String uid) => ApplicationModel(
    id: 'n1', toId: 'to_n1', uid: uid, businessId: _biz1, businessName: '강남 물류센터', toTitle: '단기 공고',
    status: AppStatus.confirmed, selectedWorkType: '피킹', startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly',
    workDate: _day(2), appliedAt: _day(-3));

UserHomeReads _userReads(String uid) {
  Future<List<ApplicationModel>>? last;
  final apps = [_shift(uid)];
  return UserHomeReads(
    slotsForTO: (_) async => const <SlotModel>[],
    myContracts: (_) async => completedContractsFor(await (last ?? Future.value(const <ApplicationModel>[]))),
    myApplications: (_) => last = Future.value(apps),
    myMonthlyAttendances: ({required String userId, required int year, required int month}) async => const [],
    publishedTOs: () async => const [],
    pendingIdCardRequests: (_) async => const [],
    myRenewalProposals: () async => const <RenewalProposalModel>[],
    businessById: (_) async => BusinessModel(
        id: _biz1, name: '강남 물류센터', ownerId: 'a1', businessNumber: '000-00-00000', address: '서울특별시 강남구 테헤란로 1',
        category: '물류', subCategory: '창고', isApproved: true, createdAt: _day(-200)),
    invalidatePublishedTOsCache: () {},
    documentCorrections: () async => DocumentCorrectionSurface.empty,
    legalReadiness: () async => const LegalReadiness(status: LegalReadinessStatus.current),
  );
}

// ── 관리자 홈 reads (admin_home_content_render_test.dart:210–434 축약) ──
BusinessModel _business(String id, String name) => BusinessModel(
    id: id, name: name, ownerId: 'admin1', businessNumber: '000-00-00000', address: '서울시 어딘가',
    category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));

class _Template extends Fake implements ContractTemplateModel {
  @override
  bool get isSupportedForNewUse => true;
}

Map<String, dynamic> _simple(int count) => {
      'available': true,
      'count': count,
      'byBusiness': [
        {'businessId': _biz1, 'count': count},
      ],
    };

AdminHomeSummaryModel _summary() => AdminHomeSummaryModel.fromMap({
      'actions': {
        'resignRequest': {..._simple(0), 'soonCount': 0},
        'approval': {..._simple(3), 'overdueCount': 0},
        'scheduleChangeRequest': _simple(0),
        'unsentContract': _simple(2),
        'unclosed': {..._simple(0), 'oldestDate': null},
        'settlementRequest': _simple(0),
        'wageChangeRequest': _simple(0),
        'unpaidWage': {..._simple(0), 'overdueCount': 0, 'missingDueDateCount': 0},
      },
      'upcoming': {
        'expiringContract': {..._simple(0), 'upcomingCount': 0, 'expiredCount': 0},
      },
    });

AdminHomeReads _adminReads(List<BusinessModel> bizs) => AdminHomeReads(
      summary: ({String? selectedBusinessId}) => Future.value(_summary()),
      businessesByIds: (ids) async => bizs,
      staffingReadiness: ({String? selectedBusinessId}) => Future.value(StaffingReadinessModel(
            available: true,
            partial: false,
            failedBusinessCount: 0,
            publishedPostingCount: 1,
            days: [
              StaffingDayData.fromMap({
                'date': _todayStr, 'requiredCount': 6, 'confirmedCount': 4, 'shortageCount': 2,
                'pendingAvailable': false, 'byBusiness': const <Map<String, dynamic>>[],
              }),
            ],
          )),
      attendanceByDate: ({required String businessId, required DateTime date}) async => const [],
      confirmedWorkers: ({required DateTime date, required String businessId}) async => const [],
      workDetailTimes: (_) async => <String, dynamic>{},
      postingReadiness: (bs) async => {
            for (final b in bs)
              b.id: BusinessPostingReadiness(
                  bizId: b.id, isApproved: true, hasCanonicalLicense: true, hasOwnerLegacyLicense: false,
                  hasActiveWorkTypes: true, hasEmployerSeal: true),
          },
      contractTemplates: (_) async => <ContractTemplateModel>[_Template()],
      tourCompleted: () => Future<bool>.value(true),
      clock: () => _clock,
      legalReadiness: () async => const LegalReadiness(status: LegalReadinessStatus.current),
    );

// ── 글꼴 (du1_vq_capture_test.dart:269–289 와 같은 등록) ──
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

// ── 실행량 계수(CP01 phase 상한: fixture 6 · tap 12 · drag 4 · pump+mount 400 · PNG 6쌍) ──
int _mounts = 0, _pumps = 0, _pngs = 0, _taps = 0;
const _drags = 0;
final _cases = <String>{};
/// [r2] 오류별 진단문(발생 순간 렌더).
final _diag = Expando<String>('cp01-diag');

const _w = (id: 'W', size: Size(390, 844), scale: 1.0);
const _b = (id: 'B', size: Size(320, 640), scale: 2.0);

String _r(Rect r) => '[${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)} ${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)}]';

void main() {
  final phase = vqPhase ?? '';
  final env = Platform.environment;
  final meta = env['CP01_META'] ?? '';
  if (phase != 'c1') {
  test('CP01 실행 조건 — 날짜·실행 ID·출력 경로 고정', () {
    expect(phase == 'before' || phase == 'after', isTrue, reason: 'DU1_VQ_PHASE=before|after');
    expect(env['DU1_VQ_DATE'], '2026-11-11', reason: 'DU1_VQ_DATE 고정');
    expect((env['DU1_VQ_RUN'] ?? '').isNotEmpty, isTrue, reason: 'DU1_VQ_RUN');
    expect((env['DU1_VQ_OUT'] ?? '').contains('cp01-concept-logo-surface'), isTrue, reason: 'DU1_VQ_OUT=E');
    expect(meta.isNotEmpty, isTrue, reason: 'CP01_META(소스·시험·로고 recipe·폰트 근거)');
  });
  }
  setUp(() => SharedPreferences.setMockInitialValues({
        'onboarding_completed_u1': true,
        'onboarding_completed_sub1': true,
        'onboarding_completed_admin1': true,
        'tour_completed_user_home': true,
        'tour_completed_admin_home': true,
      }));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    await _loadFonts();
  });

  /// 시험 본문 동안만 렌더 오류(overflow 는 FlutterError)를 모은다 — 본문 안에서 원래 처리기로 되돌린다.
  Future<void> collecting(Future<void> Function(List<FlutterErrorDetails> errors) body) async {
    final errors = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    // [r2] 진단문은 오류가 들어오는 순간(트리 활성) 렌더해 둔다 — 화면 해제 뒤 렌더하면 생성 위치를 못 얻는다.
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

  /// 한 화면을 그린다. 렌더 오류는 [errors] 에 모은다(overflow 는 FlutterError 로 온다).
  Future<({GlobalKey key, List<FlutterErrorDetails> errors})> open(WidgetTester t,
      {required Widget home, required UserProvider up, required ThemeData theme,
      required ({String id, Size size, double scale}) v, required List<FlutterErrorDetails> errors}) async {
    final key = GlobalKey();
    t.view.physicalSize = v.size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: up),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (ctx, child) =>
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.scale)), child: child!),
          home: home,
        ),
      ),
    ));
    _mounts++;
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 100));
      _pumps++;
    }
    return (key: key, errors: errors);
  }

  double offset0(WidgetTester t) {
    final all = find.byType(Scrollable);
    final vs = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
        .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
        .toList()
      ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
    return vs.isEmpty ? -1 : t.state<ScrollableState>(vs.first).position.pixels;
  }

  /// 실제 receiver rect 의 중심을 눌렀을 때 그 receiver 가 hit 경로에 있는가.
  bool centerHits(WidgetTester t, Finder receiver) {
    final ro = t.renderObject(receiver);
    final res = t.hitTestOnBinding(t.getRect(receiver).center);
    return res.path.any((e) => identical(e.target, ro));
  }

  Map<String, Object?> receiver(WidgetTester t, String name, Finder f, Size screen) {
    if (f.evaluate().isEmpty) return {'name': name, 'found': false};
    final r = t.getRect(f.first);
    final inScreen = r.left >= 0 && r.top >= 0 && r.right <= screen.width && r.bottom <= screen.height;
    return {'name': name, 'found': true, 'rect': _r(r), 'w': r.width, 'h': r.height, 'inScreen': inScreen, 'hit': centerHits(t, f.first)};
  }

  /// 글자 전문이 보이는가 — RenderParagraph 의 줄 수·초과 여부·마지막 글자 상자·조상 상자 안·화면 안.
  Map<String, Object?> paragraph(WidgetTester t, String name, Finder f, Size screen) {
    if (f.evaluate().isEmpty) return {'name': name, 'found': false};
    final rp = t.renderObject<RenderParagraph>(f.first);
    final r = t.getRect(f.first);
    final text = rp.text.toPlainText();
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length));
    final lines = boxes.map((b) => b.top.round()).toSet().length;
    final last = rp.getBoxesForSelection(TextSelection(baseOffset: text.length - 1, extentOffset: text.length));
    final lastBox = last.isEmpty ? null : last.last.toRect().shift(r.topLeft);
    final inScreen = r.left >= -0.5 && r.top >= -0.5 && r.right <= screen.width + 0.5 && r.bottom <= screen.height + 0.5;
    // [r2] 가로는 문단 안, 세로는 상자 중심이 문단 안(글꼴 상하 폭이 줄 높이보다 커서 상자 전체 포함은 쓰지 않는다).
    final lastVisible = lastBox != null &&
        lastBox.left >= r.left - 0.5 && lastBox.right <= r.right + 0.5 &&
        lastBox.center.dy >= r.top && lastBox.center.dy <= r.bottom &&
        lastBox.right <= screen.width + 0.5;
    return {'name': name, 'found': true, 'text': text, 'rect': _r(r), 'lines': lines, 'exceeded': rp.didExceedMaxLines,
      'maxLines': rp.maxLines, 'overflow': rp.overflow.name, 'inScreen': inScreen, 'lastVisible': lastVisible};
  }

  /// before 에서 허용하는 오류 — 사전 결손 위치의 overflow 뿐.
  ///   ③ 관리자 홈: 머리 이름 줄 Row(business_admin_home_screen.dart:1381)·SubAdmin 배지 Row(:2000)
  ///   ③ 지원자 홈: 머리 Row(user_home_screen.dart:902 — 로고+역할 전환+알림 한 줄)
  bool knownBeforeOverflow(FlutterErrorDetails e, {required bool admin, required bool sub}) {
    if (!sub) return false;
    final s = _diag[e] ?? '';
    if (!s.contains('overflowed')) return false;
    return admin
        ? (s.contains('business_admin_home_screen.dart:1381:') || s.contains('business_admin_home_screen.dart:2000:'))
        : s.contains('user_home_screen.dart:902:');
  }

  /// before 에서만: 행동 대상 중심이 화면 밖이면 원본 결손으로 도달 불가 — 기록하고 그 행동을 건너뛴다.
  bool reachableOrLog(WidgetTester t, String caseId, String what, Finder f, Size screen) {
    if (f.evaluate().isEmpty) {
      expect(phase, 'before', reason: '$caseId $what 대상 없음');
      // ignore: avoid_print
      print('CP01-ACTION $caseId $what skipped: target missing (before 결손)');
      return false;
    }
    final c = t.getRect(f.first).center;
    final ok = c.dx >= 0 && c.dy >= 0 && c.dx <= screen.width && c.dy <= screen.height && centerHits(t, f.first);
    if (!ok) {
      expect(phase, 'before', reason: '$caseId $what 중심 도달 불가(after 는 도달 필수)');
      // ignore: avoid_print
      print('CP01-ACTION $caseId $what skipped: center ${c.dx.toStringAsFixed(1)},${c.dy.toStringAsFixed(1)} unreachable (before 결손)');
    }
    return ok;
  }

  /// 사례 끝 — 행동·캡처·화면 교체 중 생긴 오류까지 판정한다.
  void finalErrors(String caseId, List<FlutterErrorDetails> errs, {required bool admin, required bool sub}) {
    if (phase == 'after') {
      expect(errs, isEmpty, reason: '$caseId 행동·캡처·교체 포함 오류 0');
    } else {
      for (final e in errs) {
        expect(knownBeforeOverflow(e, admin: admin, sub: sub), isTrue, reason: '$caseId before 예상 밖 오류(행동 포함): ${e.exceptionAsString().split('\n').first}');
      }
    }
  }

  Future<void> tapAt(WidgetTester t, Finder f) async {
    await t.tapAt(t.getRect(f.first).center);
    _taps++;
  }

  Future<void> settle(WidgetTester t, int n) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
      _pumps++;
    }
  }

  Finder inkOf(IconData icon) => find.ancestor(of: find.byIcon(icon), matching: find.byType(InkWell));
  Finder gdOfText(String text) => find.ancestor(of: find.text(text), matching: find.byType(GestureDetector));
  Finder gdOfTextContaining(String text) =>
      find.ancestor(of: find.textContaining(text), matching: find.byType(GestureDetector));
  final wordmark = find.byWidgetPredicate((w) => w.runtimeType.toString() == 'AlfitWordmark');
  final oldAsset = find.byWidgetPredicate(
      (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/icons/app_icon_foreground.png');

  /// 머리 관측 + (after) 단언. 반환: 로그 한 줄.
  Future<String> header(WidgetTester t, String caseId, ({String id, Size size, double scale}) v,
      List<FlutterErrorDetails> errors, {required bool admin, required bool sub}) async {
    final screen = v.size;
    final sem = t.ensureSemantics();
    final log = <String, Object?>{'case': caseId, 'phase': phase, 'viewport': '${screen.width.toInt()}x${screen.height.toInt()}', 'scale': v.scale};
    log['offset'] = offset0(t);
    log['oldAsset'] = oldAsset.evaluate().length;
    log['oldTextALfit'] = find.text('ALfit').evaluate().length;
    log['wordmark'] = wordmark.evaluate().length;
    Rect? wm;
    if (wordmark.evaluate().isNotEmpty) {
      wm = t.getRect(wordmark.first);
      final paint = find.descendant(of: wordmark.first, matching: find.byType(CustomPaint));
      final ink = t.getRect(paint.first);
      log['wordmarkRect'] = _r(wm);
      log['inkRect'] = _r(ink);
      final node = t.getSemantics(wordmark.first);
      log['semLabel'] = node.label;
      log['semImage'] = containsSemantics(isImage: true).matches(node, <dynamic, dynamic>{});
    }
    final rs = <Map<String, Object?>>[
      receiver(t, 'bell', inkOf(Icons.notifications_outlined), screen),
      if (admin) receiver(t, 'manage', inkOf(Icons.settings_outlined), screen),
      if (sub) receiver(t, 'toggle지원자', gdOfText('지원자'), screen),
      if (sub) receiver(t, 'toggle관리자', gdOfText('관리자'), screen),
      if (sub && admin) receiver(t, 'bizSelector', gdOfTextContaining('▼'), screen),
    ];
    log['receivers'] = rs;
    final ps = <Map<String, Object?>>[
      if (admin) paragraph(t, 'adminName', find.text(sub ? '박하위님' : '김관리님'), screen),
      if (admin && sub) paragraph(t, 'bizBadge', find.text('$_longBiz ▼'), screen),
    ];
    log['paragraphs'] = ps;
    if (sub && !admin && wm != null && gdOfText('지원자').evaluate().isNotEmpty) {
      final tg = t.getRect(gdOfText('지원자').first);
      log['togglePlacement'] = tg.top >= wm.bottom - 0.5 ? 'nextLine' : 'sameLine';
    }
    final msgs = errors.map((e) {
      final s = _diag[e] ?? '';
      final at = RegExp(r'[A-Za-z_]+\.dart:\d+:\d+').allMatches(s).map((m) => m.group(0)).toSet().join(',');
      return '${e.exceptionAsString().split('\n').first} @ $at';
    }).toList();
    log['errors'] = msgs;
    // ignore: avoid_print
    print('CP01-MEASURE ${log.toString()}');

    if (phase == 'after') {
      expect(log['offset'], 0.0, reason: '$caseId 첫 화면 offset 0');
      expect(errors, isEmpty, reason: '$caseId 렌더 오류 0: $msgs');
      expect(log['oldAsset'], 0, reason: '$caseId 원형 앱아이콘 장식 없음');
      expect(log['oldTextALfit'], 0, reason: '$caseId 구 글자 로고 없음');
      expect(log['wordmark'], 1, reason: '$caseId 글자 로고 1개');
      final ink = t.getRect(find.descendant(of: wordmark.first, matching: find.byType(CustomPaint)).first);
      expect(ink.height, closeTo(24, 0.01), reason: '$caseId 잉크 24(배율 ${v.scale}에서도)');
      expect(wm!.height, closeTo(28, 0.01), reason: '$caseId 자리 높이 28');
      expect(wm.width, greaterThanOrEqualTo(84), reason: '$caseId 자리 폭 ≥84');
      expect(ink.left, closeTo(wm.left, 0.01), reason: '$caseId 왼쪽 정렬');
      expect(log['semLabel'], 'ALfit');
      expect(log['semImage'], isTrue);
      expect(find.bySemanticsLabel('ALfit').evaluate().length, 1, reason: '$caseId ALfit 의미 1개');
      for (final r in rs) {
        expect(r['found'], isTrue, reason: '$caseId ${r['name']} 있음');
        expect(r['w'] as double, greaterThanOrEqualTo(48), reason: '$caseId ${r['name']} 폭 ≥48');
        expect(r['h'] as double, greaterThanOrEqualTo(48), reason: '$caseId ${r['name']} 높이 ≥48');
        expect(r['inScreen'], isTrue, reason: '$caseId ${r['name']} 화면 안');
        expect(r['hit'], isTrue, reason: '$caseId ${r['name']} 중심 hit');
      }
      if (sub && !admin) {
        expect(log['togglePlacement'], v.id == 'W' ? 'sameLine' : 'nextLine', reason: '$caseId 역할 전환 줄 배치');
      }
      for (final p in ps) {
        expect(p['found'], isTrue, reason: '$caseId ${p['name']} 있음');
        expect(p['exceeded'], isFalse, reason: '$caseId ${p['name']} 줄 초과 없음');
        expect(p['maxLines'], isNull, reason: '$caseId ${p['name']} 줄 제한 없음(전문)');
        expect(p['inScreen'], isTrue, reason: '$caseId ${p['name']} 화면 안');
        expect(p['lastVisible'], isTrue, reason: '$caseId ${p['name']} 마지막 글자(▼ 포함) 보임');
      }
    } else {
      // before: 사전 결손 목록 밖의 오류는 중단선 — 허용은 관리자 머리 이름/배지 줄 overflow 뿐(③, 정적 근거 :1381–1395·2003–2007).
      for (final e in errors) {
        final known = knownBeforeOverflow(e, admin: admin, sub: sub);
        expect(known, isTrue, reason: '$caseId before 예상 밖 오류: ${e.exceptionAsString().split('\n').first}');
      }
    }
    sem.dispose();
    return log.toString();
  }

  Future<void> shot(WidgetTester t, GlobalKey key, String id, ({String id, Size size, double scale}) v, String fixture) async {
    final before = _pngs;
    await vqCapture(t, key, id, conditions: {
      'id': id, 'phase': phase, 'fixture': fixture, 'viewport': '${v.size.width.toInt()}x${v.size.height.toInt()}', 'dpr': 1.0,
      'textScaler': v.scale, 'locale': 'ko_KR', 'inset': 0, 'clockUtc': _clock.toIso8601String(), 'offset': offset0(t),
      'fonts': 'NotoSansKR Regular+Bold(Roboto 별칭) · FlutterTest=Regular · MaterialIcons(SDK)',
      'run': env['DU1_VQ_RUN'], 'meta': meta,
    });
    if (vqEnabled) _pngs = before + 1;
  }

  // ═══ [CP01-C1] 긴 사용자 이름 보완 관측 — Codex requests/DU_concept_CP01_c1_supplement_2026-11-11.md ═══
  //   DU1_VQ_PHASE=c1 에서만 등록하고 여기서 끝낸다(기존 before/after 사례·기대·guard·행동은 등록하지 않는다).
  //   §2 관측: 정확 문자열·maxLines/줄 초과·문단 rect·줄 수 / 모든 run TextBox / 실제 line metrics(복제 TextPainter 동등성)
  //   / 유효 clip(self+조상+화면, 전역 좌표) / selector receiver. 원 guard·r2 중심 결과는 진단 기록만이다.
  if (phase == 'c1') {
    test('CP01-C1 실행 조건 — 날짜·실행 ID·출력 경로 고정', () {
      expect(env['DU1_VQ_DATE'], '2026-11-11', reason: 'DU1_VQ_DATE 고정');
      expect((env['DU1_VQ_RUN'] ?? '').startsWith('c1'), isTrue, reason: 'DU1_VQ_RUN=c1');
      expect((env['DU1_VQ_OUT'] ?? '').contains('cp01-concept-logo-surface'), isTrue, reason: 'DU1_VQ_OUT=E');
      expect(meta.isNotEmpty, isTrue, reason: 'CP01_META');
    });

    List<double> rr(Rect r) => [r.left, r.top, r.right, r.bottom].map((x) => double.parse(x.toStringAsFixed(2))).toList();
    bool axisAligned(Matrix4 m) => m.entry(0, 1) == 0 && m.entry(1, 0) == 0;
    bool translationOnly(Matrix4 m) => axisAligned(m) && m.entry(0, 0) == 1 && m.entry(1, 1) == 1;
    bool inside(Rect a, Rect b) => a.left >= b.left && a.top >= b.top && a.right <= b.right && a.bottom <= b.bottom;
    const exactRectClips = {
      'RenderClipRect', '_RenderSingleChildViewport', 'RenderViewport', 'RenderShrinkWrappingViewport', 'RenderFlex',
      'RenderStack', 'RenderIndexedStack', 'RenderWrap', 'RenderFittedBox', 'RenderConstrainedOverflowBox',
      'RenderSizedOverflowBox', 'RenderConstraintsTransformBox', 'RenderUnconstrainedBox',
    };

    Map<String, Object?> c1Para(WidgetTester t, String name, String exact, Size screen) {
      final f = find.text(exact);
      if (f.evaluate().isEmpty) return {'name': name, 'found': false};
      final rp = t.renderObject<RenderParagraph>(f.first);
      final text = rp.text.toPlainText();
      final m = rp.getTransformTo(null);
      Rect g(Rect r) => MatrixUtils.transformRect(m, r);
      final pr = g(Offset.zero & rp.size);
      var placeholders = 0;
      rp.text.visitChildren((s) {
        if (s is PlaceholderSpan) placeholders++;
        return true;
      });
      final sel = TextSelection(baseOffset: 0, extentOffset: text.length);
      final boxes = rp.getBoxesForSelection(sel);
      final gBoxes = boxes.map((b) => g(b.toRect())).toList();
      // 복제 TextPainter — RenderParagraph 와 같은 배치 조건(flutter rendering/paragraph.dart:349–357·845–852·912–936)
      final c = rp.constraints;
      final tp = TextPainter(
        text: rp.text,
        textAlign: rp.textAlign,
        textDirection: rp.textDirection,
        textScaler: rp.textScaler,
        maxLines: rp.maxLines,
        ellipsis: rp.overflow == TextOverflow.ellipsis ? String.fromCharCode(0x2026) : null,
        locale: rp.locale,
        strutStyle: rp.strutStyle,
        textWidthBasis: rp.textWidthBasis,
        textHeightBehavior: rp.textHeightBehavior,
      )..layout(minWidth: c.minWidth, maxWidth: (rp.softWrap || rp.overflow == TextOverflow.ellipsis) ? c.maxWidth : double.infinity);
      final tpSize = c.constrain(tp.size);
      final tpBoxes = tp.getBoxesForSelection(sel);
      var geomMatch = tpBoxes.length == boxes.length &&
          (tpSize.width - rp.size.width).abs() < 0.01 &&
          (tpSize.height - rp.size.height).abs() < 0.01;
      for (var i = 0; geomMatch && i < boxes.length; i++) {
        final a = boxes[i].toRect();
        final b = tpBoxes[i].toRect();
        geomMatch = (a.left - b.left).abs() < 0.01 && (a.top - b.top).abs() < 0.01 &&
            (a.right - b.right).abs() < 0.01 && (a.bottom - b.bottom).abs() < 0.01;
      }
      final lm = tp.computeLineMetrics();
      final lines = lm.map((l) => g(Rect.fromLTRB(l.left, l.baseline - l.ascent, l.left + l.width, l.baseline + l.descent))).toList();
      final hasVisualOverflow = rp.size.height < tp.height || tp.didExceedMaxLines || rp.size.width < tp.width;
      tp.dispose();
      final selfClip = hasVisualOverflow && rp.overflow != TextOverflow.visible ? pr : null;
      // 유효 clip — self + 조상(describeApproximatePaintClip) + 화면, 같은 전역 좌표
      final clips = <Map<String, Object?>>[];
      var eff = Offset.zero & screen;
      if (selfClip != null) eff = eff.intersect(selfClip);
      var approx = !axisAligned(m);
      final rrects = <RRect>[];
      RenderObject child = rp;
      RenderObject? anc = rp.parent;
      while (anc != null) {
        final r = anc.describeApproximatePaintClip(child);
        if (r != null) {
          final am = anc.getTransformTo(null);
          final gr = MatrixUtils.transformRect(am, r);
          final kind = anc.runtimeType.toString();
          var how = 'rect';
          if (!axisAligned(am)) {
            approx = true;
            how = 'transform';
          } else if (anc is RenderClipRRect) {
            if (anc.clipper != null || !translationOnly(am)) {
              approx = true;
              how = 'rrect-unsupported';
            } else {
              final tr = am.getTranslation();
              rrects.add(anc.borderRadius.resolve(anc.textDirection).toRRect(r).shift(Offset(tr.x, tr.y)));
              how = 'rrect';
            }
          } else if (!exactRectClips.contains(kind)) {
            approx = true;
            how = 'unsupported';
          }
          eff = eff.intersect(gr);
          clips.add({'kind': kind, 'how': how, 'rect': rr(gr)});
        }
        child = anc;
        anc = anc.parent;
      }
      bool inClip(Rect b) =>
          inside(b, eff) &&
          rrects.every((q) => q.contains(b.topLeft) && q.contains(b.topRight) && q.contains(b.bottomLeft) && q.contains(b.bottomRight));
      // 진단만: 원 guard(전체 포함)·r2 중심 기준 — 판정에 쓰지 않는다
      final lastSel = rp.getBoxesForSelection(TextSelection(baseOffset: text.length - 1, extentOffset: text.length));
      final lastBox = lastSel.isEmpty ? null : g(lastSel.last.toRect());
      final origGuard = lastBox != null && pr.inflate(0.5).contains(lastBox.topLeft) && pr.inflate(0.5).contains(lastBox.bottomRight);
      final r2Center = lastBox != null && lastBox.left >= pr.left - 0.5 && lastBox.right <= pr.right + 0.5 &&
          lastBox.center.dy >= pr.top && lastBox.center.dy <= pr.bottom;
      final rectInScreen = inside(pr, Offset.zero & screen);
      final boxesIn = gBoxes.every(inClip);
      final linesIn = lines.isNotEmpty && lines.every(inClip);
      return {
        'name': name, 'found': true, 'text': text, 'exact': text == exact, 'maxLines': rp.maxLines,
        'exceeded': rp.didExceedMaxLines, 'overflow': rp.overflow.name, 'softWrap': rp.softWrap,
        'paragraph': rr(pr), 'rectInScreen': rectInScreen, 'lineCount': lm.length,
        'distinctBoxTops': boxes.map((b) => b.top.round()).toSet().length, 'placeholders': placeholders,
        'axisAligned': axisAligned(m), 'replicaGeometryMatch': geomMatch,
        'replicaSize': [tpSize.width, tpSize.height], 'paragraphSize': [rp.size.width, rp.size.height],
        'constraints': [c.minWidth, c.maxWidth.isFinite ? c.maxWidth : -1, c.minHeight, c.maxHeight.isFinite ? c.maxHeight : -1],
        'textBoxes': gBoxes.map(rr).toList(), 'lastBox': lastBox == null ? null : rr(lastBox),
        'lineBoxes': lines.map(rr).toList(),
        'lineMetrics': lm.map((l) => {'n': l.lineNumber, 'baseline': l.baseline, 'ascent': l.ascent, 'descent': l.descent,
          'height': l.height, 'left': l.left, 'width': l.width}).toList(),
        'hasVisualOverflow': hasVisualOverflow, 'selfClip': selfClip == null ? null : rr(selfClip), 'clips': clips,
        'rrects': rrects.length, 'approx': approx, 'effectiveClip': rr(eff),
        'boxesInClip': boxesIn, 'linesInClip': linesIn, 'diagOrigGuard': origGuard, 'diagR2Center': r2Center,
      };
    }

    for (final v in const [_w, _b]) {
      testWidgets('CP01-C1 ③ SubAdmin 긴 사용자 이름·긴 사업장 관리자 홈 ${v.id}', (t) async {
        _cases.add('c1-${v.id}');
        final calls = <String>[];
        var errsOut = <FlutterErrorDetails>[];
        var off = -1.0;
        var nm = <String, Object?>{};
        var bz = <String, Object?>{};
        var sl = <String, Object?>{};
        await collecting((errs) async {
          errsOut = errs;
          final a = await open(t,
              home: BusinessAdminHomeScreen(reads: _adminReads([_business(_biz1, _longBiz), _business(_biz2, '강남 물류센터 2공장')])),
              up: _SubLong(calls: calls), theme: RoleTheme.businessAdminTheme, v: v, errors: errs);
          off = offset0(t);
          nm = c1Para(t, 'adminName', '${_SubLong.longName}님', v.size);
          bz = c1Para(t, 'bizBadge', '$_longBiz ▼', v.size);
          sl = receiver(t, 'bizSelector', gdOfTextContaining('▼'), v.size);
          final errLines = errs.map((e) => (_diag[e] ?? e.exceptionAsString()).split(String.fromCharCode(10)).first).toList();
          // ignore: avoid_print
          print('CP01-C1-MEASURE ${jsonEncode({'case': 'c1-${v.id}', 'viewport': '${v.size.width.toInt()}x${v.size.height.toInt()}',
            'scale': v.scale, 'offset': off, 'name': nm, 'biz': bz, 'selector': sl, 'calls': calls, 'errors': errLines})}');
          await shot(t, a.key, 'CP01-C1-subadmin-${v.id}', v, 'C1 SubAdmin long user name + long business, admin home, tap 0');
          await t.pumpWidget(const SizedBox.shrink());
          _pumps++;
        });
        // 판정 — 측정·캡처·해제 뒤. 첫 실패는 --fail-fast 로 다음 사례를 막는다.
        expect(errsOut, isEmpty, reason: 'c1-${v.id} 렌더 오류 0(mount·측정·캡처·해제)');
        expect(off, 0.0, reason: 'c1-${v.id} offset 0');
        for (final p in [nm, bz]) {
          final id = 'c1-${v.id} ${p['name']}';
          expect(p['found'], isTrue, reason: '$id 있음');
          expect(p['exact'], isTrue, reason: '$id 정확 문자열');
          expect(p['maxLines'], isNull, reason: '$id maxLines null');
          expect(p['exceeded'], isFalse, reason: '$id didExceedMaxLines false');
          expect(p['rectInScreen'], isTrue, reason: '$id 문단 rect 화면 안');
          expect(p['placeholders'], 0, reason: '$id placeholder 0');
          expect(p['axisAligned'], isTrue, reason: '$id 축 정렬 변환');
          expect(p['replicaGeometryMatch'], isTrue, reason: '$id 복제 TextPainter 크기·상자 동등');
          expect(p['approx'], isFalse, reason: '$id 비직사각·미지원 clip/transform 없음');
          expect(p['boxesInClip'], isTrue, reason: '$id 모든 run TextBox ⊂ 유효 clip');
          expect(p['linesInClip'], isTrue, reason: '$id 모든 줄 상자 ⊂ 유효 clip');
        }
        expect(sl['found'], isTrue, reason: 'c1-${v.id} selector 있음');
        expect(sl['w'] as double, greaterThanOrEqualTo(48), reason: 'c1-${v.id} selector 폭 ≥48');
        expect(sl['h'] as double, greaterThanOrEqualTo(48), reason: 'c1-${v.id} selector 높이 ≥48');
        expect(sl['inScreen'], isTrue, reason: 'c1-${v.id} selector 화면 안');
        expect(sl['hit'], isTrue, reason: 'c1-${v.id} selector 중심 hit');
        expect(calls, isEmpty, reason: 'c1-${v.id} tap 0 — 전환 호출 없음');
      });
    }

    tearDownAll(() {
      // ignore: avoid_print
      print('CP01-C1-FINAL phase=$phase cases=${_cases.length} mounts=$_mounts pumps=$_pumps pumpPlusMount=${_pumps + _mounts} '
          'taps=$_taps drags=$_drags pngPairs=$_pngs');
      expect(_cases.length, lessThanOrEqualTo(2));
      expect(_mounts, lessThanOrEqualTo(2));
      expect(_pumps + _mounts, lessThanOrEqualTo(60));
      expect(_taps, 0);
      expect(_pngs, lessThanOrEqualTo(2));
    });
    return;
  }

  for (final v in const [_w, _b]) {
    testWidgets('CP01 ① 지원자 정상 ${v.id}', (t) async {
      expect(phase == 'before' || phase == 'after', isTrue, reason: 'DU1_VQ_PHASE=before|after');
      _cases.add('worker-${v.id}');
      await collecting((errs) async {
        final o = await open(t, home: UserHomeScreen(reads: _userReads('u1'), clock: () => _clock), up: _Worker(),
            theme: RoleTheme.workerTheme, v: v, errors: errs);
        await header(t, 'worker-${v.id}', v, o.errors, admin: false, sub: false);
        await shot(t, o.key, 'CP01-worker-${v.id}', v, 'worker normal, confirmed shift D+2');
        await t.pumpWidget(const SizedBox.shrink());
        _pumps++;
        finalErrors('worker-${v.id}', errs, admin: false, sub: false);
      });
      expect(t.takeException(), isNull);
    });

    testWidgets('CP01 ② 소유자 단일 사업장 ${v.id}', (t) async {
      expect(phase == 'before' || phase == 'after', isTrue);
      _cases.add('owner-${v.id}');
      await collecting((errs) async {
        final o = await open(t, home: BusinessAdminHomeScreen(reads: _adminReads([_business(_biz1, '강남 물류센터')])),
            up: _Owner(), theme: RoleTheme.businessAdminTheme, v: v, errors: errs);
        await header(t, 'owner-${v.id}', v, o.errors, admin: true, sub: false);
        await shot(t, o.key, 'CP01-owner-${v.id}', v, 'owner single business, shortage 2');
        await t.pumpWidget(const SizedBox.shrink());
        _pumps++;
        finalErrors('owner-${v.id}', errs, admin: true, sub: false);
      });
      expect(t.takeException(), isNull);
    });

    testWidgets('CP01 ③ SubAdmin 긴 사업장·모드 전환 ${v.id}', (t) async {
      expect(phase == 'before' || phase == 'after', isTrue);
      _cases.add('sub-${v.id}');
      final calls = <String>[];
      await collecting((errs) async {
        final u = await open(t, home: UserHomeScreen(reads: _userReads('sub1'), clock: () => _clock),
            up: _Sub(adminMode: false, calls: calls), theme: RoleTheme.workerTheme, v: v, errors: errs);
        await header(t, 'sub-user-${v.id}', v, u.errors, admin: false, sub: true);
        // 행동 U: 지원자 홈 '관리자' → 기존 BusinessSelectorSheet → 2번째 사업장 → switchToAdminMode(biz2)
        if (reachableOrLog(t, 'sub-user-${v.id}', '관리자 전환', gdOfText('관리자'), v.size)) {
          await tapAt(t, gdOfText('관리자'));
          await settle(t, 8);
          final sheetU = find.byType(BusinessSelectorSheet);
          expect(sheetU, findsOneWidget, reason: 'sub-user-${v.id} 관리자 → 사업장 선택 시트');
          await tapAt(t, find.descendant(of: sheetU, matching: findVisibleText('강남 물류센터 2공장')));
          await settle(t, 8);
          expect(calls, ['switchToAdminMode:$_biz2'], reason: 'sub-user-${v.id} 선택 사업장 전달');
        }
        if (phase == 'after') expect(calls, ['switchToAdminMode:$_biz2'], reason: 'sub-user-${v.id} after 행동 관측 필수');
        // ignore: avoid_print
        print('CP01-ACTION sub-user-${v.id} calls=$calls errors=${errs.length}');
        await t.pumpWidget(const SizedBox.shrink());
        _pumps++;
        finalErrors('sub-user-${v.id}', errs, admin: false, sub: true);
      });
      await collecting((errs) async {
        final a = await open(t,
            home: BusinessAdminHomeScreen(reads: _adminReads([_business(_biz1, _longBiz), _business(_biz2, '강남 물류센터 2공장')])),
            up: _Sub(adminMode: true, calls: calls), theme: RoleTheme.businessAdminTheme, v: v, errors: errs);
        await header(t, 'sub-admin-${v.id}', v, a.errors, admin: true, sub: true);
        await shot(t, a.key, 'CP01-subadmin-${v.id}', v, 'SubAdmin 2 businesses (long name), admin home');
        final before = calls.length;
        final expected = [...calls];
        // 행동 A1: 사업장 배지(▼) → 기존 BusinessSelectorSheet → 다른 사업장 → switchToAdminMode(biz2)
        if (reachableOrLog(t, 'sub-admin-${v.id}', '사업장 선택', gdOfTextContaining('▼'), v.size)) {
          await tapAt(t, gdOfTextContaining('▼'));
          await settle(t, 8);
          final sheetA = find.byType(BusinessSelectorSheet);
          expect(sheetA, findsOneWidget, reason: 'sub-admin-${v.id} 배지 → 사업장 선택 시트');
          await tapAt(t, find.descendant(of: sheetA, matching: findVisibleText('강남 물류센터 2공장')));
          await settle(t, 8);
          expected.add('switchToAdminMode:$_biz2');
        }
        // 행동 A2: '지원자' → toggleAdminMode
        if (reachableOrLog(t, 'sub-admin-${v.id}', '지원자 전환', gdOfText('지원자'), v.size)) {
          await tapAt(t, gdOfText('지원자'));
          await settle(t, 2);
          expected.add('toggleAdminMode');
        }
        expect(calls, expected, reason: 'sub-admin-${v.id} 다른 사업장 전달 + 지원자 전환 호출');
        if (phase == 'after') {
          expect(calls.length - before, 2, reason: 'sub-admin-${v.id} after 행동 2개 모두 관측');
        }
        // ignore: avoid_print
        print('CP01-ACTION sub-admin-${v.id} calls=$calls errors=${errs.length}');
        await t.pumpWidget(const SizedBox.shrink());
        _pumps++;
        finalErrors('sub-admin-${v.id}', errs, admin: true, sub: true);
      });
      expect(t.takeException(), isNull);
    });
  }

  tearDownAll(() {
    // ignore: avoid_print
    print('CP01-FINAL phase=$phase cases=${_cases.length} mounts=$_mounts pumps=$_pumps pumpPlusMount=${_pumps + _mounts} '
        'taps=$_taps drags=$_drags pngPairs=$_pngs');
    expect(_cases.length, lessThanOrEqualTo(6));
    expect(_pumps + _mounts, lessThanOrEqualTo(400));
    expect(_pngs, lessThanOrEqualTo(6));
    expect(_taps, lessThanOrEqualTo(12));
  });
}
