// [판정285 · 대표 지시 2026-11-26] 근로자 홈 이전/이후 QA 렌더 캡처 — 같은 하네스·같은 데이터로 두 코드를 그린다.
//   실기기 캡처 대신(대표 해제). 단언 없음(렌더 예외만) — 이전 코드에도 있는 API 만 쓴다(UserHomeScreen(reads, clock) · 옛 UserTabScope 인자).
//   DU1_VQ_PHASE(before|after) · DU1_VQ_RUN · DU1_VQ_OUT 이 있을 때만 PNG 를 쓴다. 각 PNG 옆 run.txt 에 Dart SHA·폭·배율·시나리오·선택일.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/theme/role_theme.dart';

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

class _W extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1', username: '', name: '김알핏', email: '', role: UserRole.USER,
        accountStatus: 'active', passVerifiedAt: DateTime(2026, 11, 25),
        nationalityStatus: 'unknown', authProviders: const ['kakao'], signupSource: 'kakao_v1',
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

final DateTime _clock = DateTime.utc(2026, 11, 26, 1); // KST 2026-11-26(목) 10:00
DateTime _k(int m, int d) => DateTime.utc(2026, m, d);

ApplicationModel _short(String id, DateTime day, String status, String start, String end, String biz, String type) =>
    ApplicationModel(
      id: id, toId: 'to_$id', uid: 'u1', businessId: 'b_$id', businessName: biz, toTitle: '단기 공고',
      status: status, selectedWorkType: type, startTime: start, endTime: end, wage: 12000, wageType: 'hourly',
      workDate: day, appliedAt: _k(11, 20), applicationType: AppType.shortTerm,
      confirmedAt: status == AppStatus.pending ? null : _k(11, 1),
    );

List<ApplicationModel> _mixed() => [
      _short('c1', _k(11, 28), AppStatus.confirmed, '09:00', '18:00', '서울특별시 강남구 제1물류센터 야간운영팀 상시근무지', '분류'),
      _short('c2', _k(11, 28), AppStatus.contractPending, '07:00', '12:00', '나래 센터', '피킹'),
      _short('p1', _k(11, 28), AppStatus.pending, '13:00', '22:00', '다온 창고', '피킹'),
      _short('p2', _k(11, 29), AppStatus.pending, '13:00', '22:00', '라온 마트', '피킹'),
      _short('c3', _k(12, 1), AppStatus.confirmed, '10:00', '15:00', '가람 물류센터', '포장'),
    ];

// [판정286] 공고 있는 fixture — 서로 다른 날짜(11/28 ×3 · 11/30 · 12/1) flex 공고.
const _wd = WorkDetailData(wdId: 'wd1', workType: '상하차', wage: 12000, requiredCount: 1, startTime: '10:00', endTime: '15:00');
TOModel _flex(String id, String title, String dateKey) => TOModel(
      id: id, businessId: 'b$id', businessName: '사업장 $id', businessCity: '강남구', type: 'flex',
      title: title, creatorUID: 'admin1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0,
      workDetails: const [_wd], slotDateKeys: [dateKey], totalSlots: 1, totalRequired: 1,
      totalConfirmed: 0, totalPending: 0, isPublished: true, publishMode: 'immediate',
      createdAt: _k(11, 20), statusUpdatedAt: _k(11, 20),
    );
const _wdNight = WorkDetailData(wdId: 'wd2', workType: '야간 분류', wage: 13000, requiredCount: 1, startTime: '19:00', endTime: '23:00');
TOModel _flexNight(String id, String title, String dateKey) => TOModel(
      id: id, businessId: 'b$id', businessName: '사업장 $id', businessCity: '강남구', type: 'flex',
      title: title, creatorUID: 'admin1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0,
      workDetails: const [_wdNight], slotDateKeys: [dateKey], totalSlots: 1, totalRequired: 1,
      totalConfirmed: 0, totalPending: 0, isPublished: true, publishMode: 'immediate',
      createdAt: _k(11, 20), statusUpdatedAt: _k(11, 20),
    );
final _tos = [
  _flex('A1', '물류센터 상하차 오전', '2026-11-28'),
  _flex('A2', '물류센터 분류 단기', '2026-11-28'),
  _flex('A3', '창고 포장 보조', '2026-11-28'),
  _flex('B1', '마트 진열 하루', '2026-11-30'),
  _flex('C1', '택배 분류 야간 전', '2026-12-01'),
];

UserHomeReads _reads(List<ApplicationModel> apps, {List<TOModel> tos = const []}) => UserHomeReads(
      slotsForTO: (_) async => const <SlotModel>[],
      myContracts: (_) async => const [],
      myApplications: (_) async => apps,
      myMonthlyAttendances: ({required String userId, required int year, required int month}) async =>
          const <AttendanceModel>[],
      publishedTOs: () async => tos,
      pendingIdCardRequests: (_) async => const [],
      myRenewalProposals: () async => const [],
      businessById: (id) async => BusinessModel(
          id: id, name: 'b', ownerId: 'o', businessNumber: '0', address: 'a', category: 'c',
          subCategory: 's', isApproved: true, createdAt: DateTime(2026)),
      invalidatePublishedTOsCache: () {},
      documentCorrections: () async => DocumentCorrectionSurface.empty,
    );

final _cap = GlobalKey();
final String _homeSha = sha256.convert(File('lib/screens/user/user_home_screen.dart').readAsBytesSync()).toString();

Future<void> _shot(WidgetTester t, String id, {required String scenario, required double w, required double h,
    required double scale, required List<ApplicationModel> apps, String? tapPrefix, List<TOModel> tos = const [],
    double preScroll = 0}) async {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(RepaintBoundary(
    key: _cap,
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _W()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        theme: RoleTheme.workerTheme,
        debugShowCheckedModeBanner: false,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: UserTabScope(
          switchToTab: (_) {},
          switchToTabWithDate: (_, __) {},
          pendingJobDate: null,
          clearPendingJobDate: () {},
          pendingScheduleMonth: null,
          clearPendingScheduleMonth: () {},
          switchToScheduleNow: () {},
          child: UserHomeScreen(reads: _reads(apps, tos: tos), clock: () => _clock),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  var tapped = 'none';
  // [판정286] 현실 높이 표본 — 손 스크롤(dragFrom) 후 선택. ensureVisible 를 쓰지 않는다.
  if (preScroll > 0) {
    await t.dragFrom(Offset(w / 2, h * 0.7), Offset(0, -preScroll));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }
  if (tapPrefix != null) {
    final cell = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.button == true && (w.properties.label ?? '').startsWith(tapPrefix));
    if (cell.evaluate().length == 1) {
      if (preScroll <= 0) await t.ensureVisible(cell);
      await t.tap(cell, warnIfMissed: false);
      tapped = tapPrefix;
    }
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }
  expect(t.takeException(), isNull);
  await vqCapture(t, _cap, id, conditions: {
    'kind': 'LOCAL widget render(QA · 실기기 아님 · 모의 데이터)',
    'home_dart_sha256': _homeSha,
    'source': Platform.environment['WH_SOURCE'] ?? '(unset)',
    'logical_width': w,
    'viewport_height': h,
    'text_scale': scale,
    'clock_kst': '2026-11-26 10:00 (목)',
    'scenario': scenario,
    'tap_date': tapped,
    'pre_scroll_drag_px': preScroll,
    'postings': tos.map((x) => '${x.id}@${x.slotDateKeys.join('|')}').join(','),
  });
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    await vqLoadFonts();
  });
  setUp(() => SharedPreferences.setMockInitialValues({'tour_completed_user_home': true}));

  const zero = '새 회원 정상0 — 지역·서류·계좌 없음 · 지원 0 · 공고 0';
  const mixed = '혼합 — 11/28 계약진행중07·확정09(긴 사업장명)·지원중13 · 11/29 지원중 · 12/1 확정 · 공고 0';
  testWidgets('CAP-1 정상0 360/1.0 미선택', (t) async =>
      _shot(t, 'WH285-1_zero_360x1.0', scenario: zero, w: 360, h: 2600, scale: 1.0, apps: const []));
  testWidgets('CAP-2 정상0 360/1.0 빈 날(11/28) 탭', (t) async => _shot(t, 'WH285-2_zero_tap1128_360x1.0',
      scenario: zero, w: 360, h: 2600, scale: 1.0, apps: const [], tapPrefix: '11월 28일 토요일'));
  testWidgets('CAP-3 혼합 360/1.0 11/28 탭', (t) async => _shot(t, 'WH285-3_mixed_tap1128_360x1.0',
      scenario: mixed, w: 360, h: 3000, scale: 1.0, apps: _mixed(), tapPrefix: '11월 28일 토요일'));
  testWidgets('CAP-4 혼합 320/1.0 11/28 탭', (t) async => _shot(t, 'WH285-4_mixed_tap1128_320x1.0',
      scenario: mixed, w: 320, h: 3200, scale: 1.0, apps: _mixed(), tapPrefix: '11월 28일 토요일'));
  testWidgets('CAP-5 혼합 320/2.0 11/28 탭', (t) async => _shot(t, 'WH285-5_mixed_tap1128_320x2.0',
      scenario: mixed, w: 320, h: 7000, scale: 2.0, apps: _mixed(), tapPrefix: '11월 28일 토요일'));
  // [판정286] 공고 있는 조건 — 미선택 추천 · 선택일 · 좁은 폭 · 큰 글자 · 현실 높이(손 스크롤) 표본.
  const posts = '공고 5(11/28×3 · 11/30 · 12/1 · 강남구 flex) · 지원 0';
  const postsMixed = '공고 5 + 혼합 일정(11/28 3건 · 11/29 · 12/1)';
  testWidgets('CAP-6 공고 360/1.0 미선택', (t) async => _shot(t, 'WH286-6_posts_360x1.0',
      scenario: posts, w: 360, h: 2800, scale: 1.0, apps: const [], tos: _tos));
  testWidgets('CAP-7 공고 360/1.0 11/28', (t) async => _shot(t, 'WH286-7_posts_tap1128_360x1.0',
      scenario: posts, w: 360, h: 2800, scale: 1.0, apps: const [], tos: _tos, tapPrefix: '11월 28일 토요일'));
  testWidgets('CAP-8 공고+혼합 320/1.0 11/28', (t) async => _shot(t, 'WH286-8_postsmixed_tap1128_320x1.0',
      scenario: postsMixed, w: 320, h: 3400, scale: 1.0, apps: _mixed(), tos: _tos, tapPrefix: '11월 28일 토요일'));
  testWidgets('CAP-9 공고+혼합 320/2.0 11/30', (t) async => _shot(t, 'WH286-9_postsmixed_tap1130_320x2.0',
      scenario: postsMixed, w: 320, h: 7600, scale: 2.0, apps: _mixed(), tos: _tos, tapPrefix: '11월 30일 월요일'));
  testWidgets('CAP-11 공고 320/1.0 미선택(카드 이미지 문턱)', (t) async => _shot(t, 'WH286-11_posts_320x1.0',
      scenario: posts, w: 320, h: 3000, scale: 1.0, apps: const [], tos: _tos));
  // [판정287 C287-01] 200 건 상한(일부만 읽음) — 미선택 오늘 · 선택일(11/27 · 읽은 목록에 그날 0).
  const partial = '지원 200 건(전부 12/25 지원 중 · 읽기 상한) · 공고 0';
  List<ApplicationModel> many() => [for (var i = 0; i < 200; i++) _short('x$i', _k(12, 25), AppStatus.pending, '09:00', '18:00', '가람 물류센터', '피킹')];
  testWidgets('CAP-12 partial 360/1.0 미선택', (t) async => _shot(t, 'WH287-12_partial_360x1.0',
      scenario: partial, w: 360, h: 2800, scale: 1.0, apps: many()));
  testWidgets('CAP-13 partial 360/1.0 11/27', (t) async => _shot(t, 'WH287-13_partial_tap1127_360x1.0',
      scenario: partial, w: 360, h: 2800, scale: 1.0, apps: many(), tapPrefix: '11월 27일 금요일'));
  // [BL287-01] 확정 근무(11/28 09–18)와 겹쳐 빠진 공고 2 + 야간(19–23) 1 — 320/2.0 · 11/28.
  const conflict = '확정 11/28 09–18 · 공고 11/28 겹침 2(10–15) + 야간 1(19–23)';
  testWidgets('CAP-14 conflict 320/2.0 11/28', (t) async => _shot(t, 'BL287-14_conflict_tap1128_320x2.0',
      scenario: conflict, w: 320, h: 7600, scale: 2.0,
      apps: [_short('cf', _k(11, 28), AppStatus.confirmed, '09:00', '18:00', '확정 사업장', '피킹')],
      tos: [_flex('O1', '겹치는 공고 하나', '2026-11-28'), _flex('O2', '겹치는 공고 둘', '2026-11-28'),
        _flexNight('N1', '야간 공고', '2026-11-28')],
      tapPrefix: '11월 28일 토요일'));
  testWidgets('CAP-10 현실 높이 360×780 손 스크롤 400 → 11/28', (t) async => _shot(t, 'WH286-10_viewport_360x780_scroll',
      scenario: postsMixed, w: 360, h: 780, scale: 1.0, apps: _mixed(), tos: _tos, tapPrefix: '11월 28일 토요일', preScroll: 400));
}
