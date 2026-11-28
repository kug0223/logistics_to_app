// ignore_for_file: depend_on_referenced_packages
// [PERF-FIRST-LOAD-1 · 저위험 4건] 로그인 직후 첫 진입 — 기다릴 이유가 없는 대기를 뺐다.
//
//   분석 정본: codex-audit/records/work/perf-first-load-1/analysis_1.md §2 · §4 · §6
//   L3   근로자 홈 읽기가 투어 확인(로컬 저장소)을 기다리지 않는다 · 오류 안내는 투어가 닫힌 뒤
//   L7   관리자 요약·인력 조회가 사업장 읽기 완료를 기다리지 않는다(출근·공고 준비만 기다린다)
//   L6   관리자 홈이 열릴 때 출근부 PDF 한글 폰트(2 × 6.2MB)를 읽지 않는다 — PDF 를 만들 때 읽는다
//   P6   추천 카드 사진은 표시 크기로 디코드한다(memCacheWidth)
//   P3   AuthWrapper 의 흰 스피너 프레임 0 — 온보딩 여부는 미리 연 저장소로 같은 프레임에 판정
//
//   각 셀은 이 변경이 없던 코드에서 실패하는 쪽으로 짰다(변경 전 사본 대조는 보고서).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/main.dart' show AuthWrapper;
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_home_summary_model.dart';
import 'package:ALfit/models/ui/staffing_readiness_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/theme_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_home_reads.dart';
import 'package:ALfit/screens/business_admin/business_admin_home_screen.dart';
import 'package:ALfit/screens/common/onboarding_screen.dart';
import 'package:ALfit/screens/common/splash_screen.dart';
import 'package:ALfit/screens/common/tour_screen.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/utils/attendance_list_pdf.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/prefs_preload.dart';
import 'package:ALfit/utils/text_layout.dart';

// ── Firebase 가짜 코어 ──────────────────────────────────────────────────
class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

String _code(String p) => File(p)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// `sig` 로 시작하는 메서드 본문(중괄호 균형).
String _bodyOf(String src, String sig) {
  final at = src.indexOf(sig);
  expect(at, isNot(-1), reason: '$sig 가 없다');
  final open = src.indexOf('{', at);
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(at, i + 1);
    }
  }
  return src.substring(at);
}

Finder _richContaining(String s) => find.byWidgetPredicate(
    (w) =>
        w is RichText &&
        TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false))
            .contains(s),
    skipOffstage: false);

// ══ 근로자 홈 ═════════════════════════════════════════════════════════════

final DateTime _today = FormatHelper.toKstDate(DateTime.now());
DateTime _day(int o) => _today.add(Duration(days: o));
const _region = UserRegion(province: '서울특별시', city: '강남구', district: '역삼동');

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: _region,
        accountStatus: 'active',
        createdAt: DateTime(2026, 1, 1),
      );
}

TOModel _recTo(String id) {
  final d = _day(4);
  final key = '${d.year}-${d.month.toString().padLeft(2, "0")}'
      '-${d.day.toString().padLeft(2, "0")}';
  return TOModel(
    id: id,
    businessId: 'biz_$id',
    businessName: '강남 물류센터',
    businessCity: _region.city,
    businessDistrict: _region.district,
    type: 'flex',
    title: '물류센터 상하차',
    creatorUID: 'admin1',
    status: TOStatus.active,
    deadlineType: 'NONE',
    hoursBeforeStart: 0,
    workDetails: [
      WorkDetailData(
        wdId: 'wd1',
        workType: '상하차',
        wage: 12000,
        wageType: 'hourly',
        requiredCount: 2,
        startTime: '09:00',
        endTime: '18:00',
      ),
    ],
    slotDateKeys: [key],
    totalRequired: 2,
    totalConfirmed: 0,
    totalPending: 0,
    isPublished: true,
    publishMode: 'immediate',
    createdAt: _day(-2),
    statusUpdatedAt: _day(-2),
  );
}

BusinessModel _bizWithPhoto(String id) => BusinessModel(
      id: id,
      name: '강남 물류센터',
      ownerId: 'admin1',
      businessNumber: '000-00-00000',
      address: '서울특별시 강남구 테헤란로 1',
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: _day(-200),
      mainImageUrl: 'https://example.invalid/$id.jpg',
    );

UserHomeReads _userReads({
  required Future<List<ApplicationModel>> Function() apps,
  Map<String, int>? calls,
  List<TOModel> tos = const [],
  Future<BusinessModel?> Function(String id)? businessById,
}) {
  void hit(String k) {
    if (calls != null) calls[k] = (calls[k] ?? 0) + 1;
  }

  return UserHomeReads(
    myContracts: (uid) async => const [],
    myApplications: (uid) {
      hit('apps');
      return apps();
    },
    myMonthlyAttendances: (
            {required String userId,
            required int year,
            required int month}) async =>
        const <AttendanceModel>[],
    publishedTOs: () async {
      hit('tos');
      return tos;
    },
    pendingIdCardRequests: (uid) async => const <IdCardAccessRequestModel>[],
    myRenewalProposals: () async => const <RenewalProposalModel>[],
    businessById: businessById ?? (id) async => null,
    slotsForTO: (toId) async => const <SlotModel>[],
    invalidatePublishedTOsCache: () {},
    documentCorrections: () async => DocumentCorrectionSurface.empty,
  );
}

Future<void> _pumpUserHome(
  WidgetTester t, {
  required UserHomeReads reads,
  Future<bool> Function()? tourCompleted,
  double dpr = 1.0,
}) async {
  t.view.physicalSize = Size(390 * dpr, 2400 * dpr);
  t.view.devicePixelRatio = dpr;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Worker()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: UserTabScope(
          switchToTab: (_) {},
          switchToTabWithDate: (_, __) {},
          pendingJobDate: null,
          clearPendingJobDate: () {},
          pendingScheduleMonth: null,
          clearPendingScheduleMonth: () {},
          switchToScheduleNow: () {},
          child: UserHomeScreen(reads: reads, tourCompleted: tourCompleted),
        ),
      ),
    ),
  );
}

// ══ 관리자 홈 ═════════════════════════════════════════════════════════════

class _Admin extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'admin1',
        username: 'admin1',
        name: '김관리',
        email: 'admin1@alfit.local',
        role: UserRole.BUSINESS_ADMIN,
        managedBusinessIds: const ['biz1'],
        sealBase64: 'seal',
      );
  @override
  bool get isSubAdmin => false;
  @override
  String? get effectiveBusinessId => null;
  @override
  bool get subAdminPermissionsLoaded => true;
  @override
  PermissionWatchState get currentBusinessPermissionHealth =>
      PermissionWatchState.verified;
  @override
  PermissionCheck checkCurrentBusiness(
          bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForAnyBusiness(bool Function(MemberPermissions p) check,
          {required bool whenUnknown}) =>
      true;
}

BusinessModel _adminBiz() => BusinessModel(
      id: 'biz1',
      name: '강남 물류센터',
      ownerId: 'admin1',
      businessNumber: '000-00-00000',
      address: '서울시 어딘가',
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: DateTime(2026, 1, 1),
    );

class _Template extends Fake implements ContractTemplateModel {}

AdminHomeReads _adminReads({
  required Future<List<BusinessModel>> businesses,
  required List<String> order,
}) =>
    AdminHomeReads(
      summary: ({String? selectedBusinessId}) {
        order.add('summary');
        return Future<AdminHomeSummaryModel>.error(StateError('test'));
      },
      businessesByIds: (ids) {
        order.add('businesses');
        return businesses;
      },
      staffingReadiness: ({String? selectedBusinessId}) {
        order.add('staffing');
        return Future<StaffingReadinessModel>.error(StateError('test'));
      },
      attendanceByDate: ({required String businessId, required DateTime date}) async {
        order.add('attendance');
        return const <AttendanceModel>[];
      },
      confirmedWorkers: ({required DateTime date, required String businessId}) async {
        order.add('roster');
        return const <ApplicationModel>[];
      },
      workDetailTimes: (_) async => <String, dynamic>{},
      postingReadiness: (bizs) async {
        order.add('posting');
        return <String, BusinessPostingReadiness>{};
      },
      contractTemplates: (_) async => <ContractTemplateModel>[_Template()],
      tourCompleted: () => Future<bool>.value(true),
    );

Future<void> _pumpAdminHome(WidgetTester t, AdminHomeReads reads) async {
  t.view.physicalSize = const Size(390, 1800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Admin()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(home: BusinessAdminHomeScreen(reads: reads)),
    ),
  );
}

// ══ AuthWrapper ══════════════════════════════════════════════════════════

class _Signed extends UserProvider {
  bool loading = false;
  @override
  bool get isLoading => loading;
  void finishLoading() {
    loading = false;
    notifyListeners();
  }
}

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  static int inits = 0;
  @override
  void initState() {
    super.initState();
    inits++;
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Color(0xFFFFFFFF));
}

UserModel _signedUser() => UserModel(
      uid: 'u9',
      username: 'u9',
      name: '박근로',
      email: 'u9@alfit.local',
      role: UserRole.USER,
      accountStatus: 'active',
      homeRegion: _region,
    );

Future<_Signed> _pumpAuth(WidgetTester t, {bool loading = false}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final prov = _Signed()
    ..loading = loading
    ..debugSetCurrentUser(_signedUser());
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(value: prov),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: const MaterialApp(home: AuthWrapper()),
  ));
  return prov;
}

/// 온보딩 분기 전에 그려지는 "흰 스피너" — 흰 Scaffold 가운데 기본 스피너 하나.
bool _whiteSpinnerShown(WidgetTester t) {
  if (find.byType(SplashLoadingScreen).evaluate().isNotEmpty) return false;
  return find.byType(CircularProgressIndicator).evaluate().isNotEmpty &&
      find.byType(OnboardingScreen).evaluate().isEmpty;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting('ko');
    await initializeDateFormatting('ko_KR', null);
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PrefsPreload.debugReset();
  });

  // ── L3 ──────────────────────────────────────────────────────────────
  group('[L3] 근로자 홈 읽기는 투어 확인을 기다리지 않는다', () {
    testWidgets('LR-L3-1 투어 확인이 끝나기 전에 홈 읽기가 출발한다', (t) async {
      final tourGate = Completer<bool>();
      final apps = Completer<List<ApplicationModel>>();
      final calls = <String, int>{};
      await _pumpUserHome(t,
          reads: _userReads(apps: () => apps.future, calls: calls),
          tourCompleted: () => tourGate.future);
      await t.pump();
      expect(calls['apps'], 1, reason: '투어 확인(로컬 저장소)을 기다리느라 홈 읽기가 늦어졌다');
      expect(calls['tos'], 1);
      expect(find.byType(TourScreen), findsNothing, reason: '투어 판정 전에는 투어를 띄우지 않는다');

      // 투어는 따로 확인된다 — 미완료면 그대로 뜬다(기존 동작).
      tourGate.complete(false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(TourScreen), findsOneWidget);
      expect(calls['apps'], 1, reason: '투어가 홈 읽기를 다시 부르지 않는다');

      apps.complete(const <ApplicationModel>[]);
      navigatorKey.currentState!.pop();
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    });

    testWidgets('LR-L3-2 투어 확인이 실패해도 홈 읽기는 돌고 투어는 뜨지 않는다', (t) async {
      final calls = <String, int>{};
      await _pumpUserHome(t,
          reads: _userReads(
              apps: () async => const <ApplicationModel>[], calls: calls),
          tourCompleted: () => Future<bool>.error(StateError('prefs')));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
      expect(calls['apps'], 1);
      expect(find.byType(TourScreen), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tour_completed_user_home'), isNull,
          reason: '실패를 완료로 저장하지 않는다');
    });

    testWidgets('LR-L3-3 투어가 떠 있는 동안의 오류 안내는 투어가 닫힌 뒤에 보인다', (t) async {
      const msg = '지원 현황을 불러오지 못했어요.';
      final apps = Completer<List<ApplicationModel>>();
      await _pumpUserHome(t,
          reads: _userReads(apps: () => apps.future),
          tourCompleted: () async => false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(TourScreen), findsOneWidget);

      apps.completeError(StateError('network'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(_richContaining(msg), findsNothing,
          reason: '투어 위에 오류 안내가 겹쳤다');

      navigatorKey.currentState!.pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(TourScreen), findsNothing);
      expect(_richContaining(msg), findsOneWidget,
          reason: '투어가 닫힌 뒤에는 오류를 알린다');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tour_completed_user_home'), isTrue,
          reason: '투어를 실제로 닫은 뒤에만 완료로 저장한다(기존 동작)');
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('LR-L3-4 투어가 없으면 오류 안내는 바로 보인다', (t) async {
      const msg = '지원 현황을 불러오지 못했어요.';
      await _pumpUserHome(t,
          reads: _userReads(
              apps: () => Future<List<ApplicationModel>>.error(StateError('x'))),
          tourCompleted: () async => true);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(_richContaining(msg), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
    });
  });

  // ── L7 · L6 ─────────────────────────────────────────────────────────
  group('[L7·L6] 관리자 홈 첫 진입', () {
    testWidgets('LR-L7-1 요약·인력 조회가 사업장 읽기 완료 전에 출발한다', (t) async {
      final biz = Completer<List<BusinessModel>>();
      final order = <String>[];
      await _pumpAdminHome(t, _adminReads(businesses: biz.future, order: order));
      await t.pump();
      expect(order, containsAll(<String>['businesses', 'summary', 'staffing']),
          reason: '요약·인력이 사업장 읽기를 기다렸다');
      expect(order.contains('posting'), isFalse,
          reason: '공고 준비는 사업장 목록을 읽으므로 사업장 확정 뒤다');
      expect(order.where((k) => k == 'businesses').length, 1,
          reason: '사업장 읽기는 한 번이다(출근 loader 가 따로 읽지 않는다)');

      biz.complete([_adminBiz()]);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(order.contains('posting'), isTrue);
      expect(order.contains('roster'), isTrue, reason: '출근 loader 는 사업장 확정 뒤 돈다');
      expect(order.where((k) => k == 'businesses').length, 1);
      expect(order.indexOf('posting'), greaterThan(order.indexOf('summary')));
      expect(t.takeException(), isNull);
    });

    testWidgets('LR-L6-1 관리자 홈 진입에 PDF 폰트를 읽지 않는다', (t) async {
      AttendanceListPdf.debugResetFonts();
      final order = <String>[];
      await _pumpAdminHome(
          t, _adminReads(businesses: Future.value([_adminBiz()]), order: order));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(AttendanceListPdf.debugFontLoadStarts, 0,
          reason: '홈 initState 가 12MB 폰트를 메인 isolate 에서 해석했다');
    });

    test('LR-L6-2 PDF 를 만들 때 폰트를 스스로 읽는다', () async {
      // 시험 환경의 기본 자산 응답은 SynchronousFuture 라 `Future.wait` 가 빈 목록을 돌려준다
      //   (기기의 PlatformAssetBundle 은 보통 Future — 이 시험 환경 특성만 바꾼다). 자산 채널을
      //   실제 비동기 파일 읽기로 응답하게 두고 production `_loadFonts` 를 그대로 돌린다.
      final messenger =
          TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler('flutter/assets', (msg) async {
        final key = utf8.decode(
            msg!.buffer.asUint8List(msg.offsetInBytes, msg.lengthInBytes));
        final bytes = await File(Uri.decodeFull(key)).readAsBytes();
        return ByteData.view(bytes.buffer);
      });
      addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
      AttendanceListPdf.debugResetFonts();
      final bytes = await AttendanceListPdf.generatePdf(AttendanceListData(
        businessName: 'QA 사업장',
        date: DateTime(2026, 11, 26),
        workTypeGroups: const {},
        workTypeTimeMap: const {},
        totalCount: 0,
      ));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(AttendanceListPdf.debugFontLoadStarts, 1);
      expect(AttendanceListPdf.debugFontsLoaded, isTrue,
          reason: '한글 폰트 없이 PDF 를 만들면 글자가 깨진다');
    });

    test('LR-L6-3 소스 — 홈 initState 에 폰트 미리 읽기가 없다', () {
      final home =
          _code('lib/screens/business_admin/business_admin_home_screen.dart');
      expect(home.contains('preloadFonts'), isFalse);
      final pdf = _code('lib/utils/attendance_list_pdf.dart');
      // [impl_19] generatePdf 에 이름 인자({offMain, debugUncompressed})가 생겨 중괄호 본문 찾기 대신
      //   시그니처 ~ 문서 함수(_buildPdfDoc) 정의 사이를 본다 — 뜻(스스로 폰트를 읽는다)은 같다.
      final at = pdf.indexOf('static Future<Uint8List> generatePdf(');
      final gen = pdf.substring(at, pdf.indexOf('static Future<Uint8List> _buildPdfDoc(', at));
      expect(gen.contains('await _loadFonts();'), isTrue);
    });
  });

  // ── P6 ──────────────────────────────────────────────────────────────
  group('[P6] 추천 카드 사진은 표시 크기로 디코드한다', () {
    testWidgets('LR-P6-1 memCacheWidth 를 지정하고 위 두 장을 미리 불러온다', (t) async {
      // 이미지 캐시가 부르는 path_provider 를 응답하지 않게 둔다 — 네트워크·디스크 없음(자리표시 고정).
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          pathProvider, (call) => Future.any(<Future<Object?>>[]));
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null));
      SharedPreferences.setMockInitialValues({'tour_completed_user_home': true});

      const dpr = 2.0;
      final tos = [_recTo('a'), _recTo('b'), _recTo('c')];
      await _pumpUserHome(t,
          dpr: dpr,
          reads: _userReads(
            apps: () async => const <ApplicationModel>[],
            tos: tos,
            // 카드가 한 번 그려진(사진 칸 폭을 잰) 뒤 사업장 문서가 오게 — 미리 불러오기 경로를 지난다.
            businessById: (id) =>
                Future.delayed(const Duration(milliseconds: 300), () => _bizWithPhoto(id)),
          ));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final images =
          t.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage)).toList();
      expect(images, isNotEmpty, reason: '추천 카드 사진이 그려지지 않았다');
      // 390dp → 화면 계수 s = 0.92 · 사진 칸 96s · cover 여유 2.
      final expected = (96 * 0.92 * dpr * 2).round();
      for (final img in images) {
        expect(img.memCacheWidth, expected,
            reason: '원본 해상도(최대 1920px)로 디코드한다');
        expect(img.memCacheHeight, isNull, reason: '두 축을 다 주면 비율이 깨진다');
      }
      // 미리 불러오기는 화면 위젯과 **같은 키**를 쓴다 — 두 번 받지 않는다.
      final shown = images.map((i) => i.imageUrl).toSet();
      for (final url in shown) {
        final provider = ResizeImage(CachedNetworkImageProvider(url), width: expected);
        final key = await provider.obtainKey(ImageConfiguration.empty);
        expect(PaintingBinding.instance.imageCache.statusForKey(key).tracked,
            isTrue, reason: '화면 위젯과 같은 키(표시 크기)로 캐시에 있다');
      }
      expect(t.takeException(), isNull);
    });

    test('LR-P6-2 소스 — 미리 불러오기 실패는 삼킨다', () {
      final home = _code('lib/screens/user/user_home_screen.dart');
      final pre = _bodyOf(home, 'void _precacheRecommendImages(');
      expect(pre.contains('precacheImage('), isTrue);
      expect(pre.contains('onError:'), isTrue, reason: '실패를 화면 오류로 올리지 않는다');
      expect(pre.contains('_homeRecommendPick('), isTrue, reason: '화면과 같은 두 후보');
      expect(pre.contains('w <= 0'), isTrue, reason: '사진 칸이 숨은 분기는 건너뛴다');
      expect(pre.contains('await '), isFalse, reason: '기다리지 않는다');
      final load = _bodyOf(home, 'Future<void> _loadHomeData(');
      expect(load.indexOf('_precacheRecommendImages(user, cache)'),
          lessThan(load.indexOf('setState(() => _businessCache = cache);')));
    });
  });

  // ── P3 + L4 ─────────────────────────────────────────────────────────
  group('[P3·L4] 흰 스피너 프레임 0', () {
    testWidgets('LR-P3-1 저장소를 미리 열었으면 첫 프레임에 온보딩 판정이 끝난다', (t) async {
      SharedPreferences.setMockInitialValues({});
      await PrefsPreload.start();
      await _pumpAuth(t);
      // pumpWidget 이 그린 첫 프레임 — postFrame 콜백 전.
      expect(_whiteSpinnerShown(t), isFalse, reason: '흰 스피너가 한 프레임 그려졌다');
      expect(find.byType(SplashLoadingScreen), findsNothing,
          reason: '미리 연 저장소가 있으면 기다릴 것이 없다');
      expect(find.byType(OnboardingScreen), findsOneWidget,
          reason: '온보딩 미완료 → 같은 프레임에 온보딩');
    });

    testWidgets('LR-P3-2 저장소가 아직이면 흰 화면 대신 스플래시와 같은 배경', (t) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpAuth(t);
      expect(_whiteSpinnerShown(t), isFalse, reason: '흰 스피너가 그려졌다');
      expect(find.byType(SplashLoadingScreen), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
        expect(_whiteSpinnerShown(t), isFalse);
      }
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(SplashLoadingScreen), findsNothing);
    });

    test('LR-P3-3 소스 — 흰 스피너 Scaffold 가 없고 main 이 저장소를 먼저 연다', () {
      final m = _code('lib/main.dart');
      expect(
          m.contains('return const Scaffold(\n            body: Center(child: CircularProgressIndicator()),'),
          isFalse);
      final mainFn = _bodyOf(m, 'void main() async');
      final pre = mainFn.indexOf('PrefsPreload.start()');
      final fb = mainFn.indexOf('Firebase.initializeApp(');
      expect(pre, greaterThan(-1));
      expect(pre, lessThan(fb), reason: 'Firebase 초기화와 겹쳐 열어야 한다');
      expect(mainFn.contains('await PrefsPreload.start()'), isFalse,
          reason: '앱 시작을 막지 않는다');
    });

    testWidgets('LR-L4-1 첫 인증 확인 스플래시 → 실제 화면은 한 번의 페이드(배경을 걷어도 화면 State 유지)',
        (t) async {
      SharedPreferences.setMockInitialValues({});
      await PrefsPreload.start();
      final prov = await _pumpAuth(t, loading: true);
      expect(find.byType(SplashLoadingScreen), findsOneWidget, reason: '첫 인증 확인 중');
      prov.finishLoading();
      await t.pump();
      // 실제 화면은 즉시 트리에 있다(새 최소 대기 0) — 밑에 같은 배경을 깔고 페이드한다.
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(SplashHandoff), findsOneWidget);
      expect(find.byKey(const ValueKey('splash-handoff-backdrop')), findsOneWidget);
      expect(_whiteSpinnerShown(t), isFalse);
      final fade = t.widget<FadeTransition>(
          find.byKey(const ValueKey('splash-handoff-child')));
      expect(fade.opacity.value, lessThan(1.0));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('splash-handoff-backdrop')), findsNothing);
      expect(t.widget<FadeTransition>(find.byKey(const ValueKey('splash-handoff-child')))
          .opacity.value, 1.0);
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('LR-L4-2 첫 스플래시가 없던 진입은 페이드 0 · 배경 걷기 전후 State 유지', (t) async {
      await _pumpAuth(t);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('splash-handoff-backdrop')), findsNothing,
          reason: '첫 인증 스플래시를 보지 않은 화면 전환은 예전처럼 즉시다');

      _ProbeState.inits = 0;
      await t.pumpWidget(const MaterialApp(home: SplashHandoff(fadeIn: true, child: _Probe())));
      expect(_ProbeState.inits, 1);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('splash-handoff-backdrop')), findsNothing);
      expect(_ProbeState.inits, 1, reason: '배경을 걷을 때 실제 화면을 다시 만들면 State 가 사라진다');
    });

    test('LR-P3-4 소스 — 스플래시 최소 시간은 그대로다', () {
      final s = _code('lib/screens/common/splash_screen.dart');
      expect(s.contains('duration: const Duration(milliseconds: 500),'), isTrue);
      expect(s.contains('transitionDuration: const Duration(milliseconds: 250),'),
          isTrue);
    });
  });
}
