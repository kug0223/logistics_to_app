// [WORKTYPE-MUTATION → WORKTYPE-IDENTITY 2026-10-17] 근로자 공고 상세의 업무 안내 연결
//
// 공고 카드의 업무명·임금·시간은 공고 슬롯 저장본(WorkDetailData)이다. 업무 설명·썸네일은 저장본이
// 없고 업무유형 문서의 **최신본**을 붙인다.
//
// 무엇이 잘못됐었나(같은 파일의 이전 관찰 셀): 화면이 현재 활성 목록을 **이름으로** 찾았다 —
//   같은 이름을 새 문서가 재사용하면 옛 공고에 새 업무의 설명이 붙었고(D5), 비활성화한 업무의
//   공고는 안내를 잃었다.
// 지금 규칙(WorkTypeGuideResolver): workTypeId 가 있으면 그 문서만(비활성 포함) · 레거시는 이름이
//   사업장 전체에서 유일하고 그 문서가 공고보다 먼저 만들어졌을 때만 연결 · 못 고르면 안내 없음.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/business_work_type_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/core/work_detail_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/job_posting_reads.dart';
import 'package:ALfit/screens/common/job_posting_screen.dart';
import 'package:ALfit/services/work_type_guide_resolver.dart';

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

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
        accountStatus: 'active',
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

DateTime _kstInstant(int y, int mo, int d) =>
    DateTime.utc(y, mo, d).subtract(const Duration(hours: 9));

/// 공고 슬롯에 저장된 업무 — 등록 당시 이름 '상하차', 시급 11000.
WorkDetailData _wd({String? workTypeId}) => WorkDetailData(
      wdId: 'wd1',
      workTypeId: workTypeId,
      workType: '상하차',
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 11000,
      wageType: 'hourly',
      requiredCount: 2,
      startTime: '09:00',
      endTime: '18:00',
      order: 0,
    );

TOModel _to({bool storedCreatedAt = true}) => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '강남 물류센터',
      type: 'flex',
      title: '단기 모집',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 4,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime(2026, 9, 1),
      storedCreatedAt: storedCreatedAt ? DateTime(2026, 9, 1) : null,
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

BusinessModel _business() => BusinessModel(
      id: 'biz1',
      name: '강남 물류센터',
      ownerId: 'admin1',
      businessNumber: '000-00-00000',
      address: '경기도 평택시 진위면 마산8로 10',
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: DateTime(2025),
    );

/// 공고는 2026-09-01 에 만들었다(_to().createdAt). 기본 업무유형은 그보다 먼저.
BusinessWorkTypeModel _wt(String id, String name, String description,
        {DateTime? createdAt, bool isActive = true, String businessId = 'biz1'}) =>
    BusinessWorkTypeModel(
      id: id,
      businessId: businessId,
      name: name,
      icon: 'box',
      displayOrder: 0,
      isActive: isActive,
      createdAt: createdAt ?? DateTime(2025),
      description: description,
    );

WorkTypeCatalog _catalog(List<BusinessWorkTypeModel> docs,
    {Map<String, int> extraNames = const {}, bool complete = true, String businessId = 'biz1'}) {
  final counts = <String, int>{...extraNames};
  for (final d in docs) {
    counts[d.name] = (counts[d.name] ?? 0) + 1;
  }
  return WorkTypeCatalog(
      businessId: businessId, byId: {for (final d in docs) d.id: d}, nameCounts: counts, complete: complete);
}

JobPostingReads _reads(WorkTypeCatalog catalog, String? workTypeId, bool storedCreatedAt) =>
    JobPostingReads(
      toOrFailure: (id) async => (to: _to(storedCreatedAt: storedCreatedAt), failed: false),
      workDetails: (id) async => const <WorkDetailModel>[],
      businessById: (id) async => _business(),
      slots: (id, {bool visibleOnly = true}) async => [
            SlotModel(
              id: 's1',
              toId: 'to1',
              // 지난 날짜 슬롯은 카드가 그려지지 않는다 — 실행일 기준 30일 뒤(시한부 fixture 금지).
              date: () {
                final k = DateTime.now().toUtc().add(const Duration(hours: 9 + 24 * 30));
                return _kstInstant(k.year, k.month, k.day);
              }(),
              workDetails: [_wd(workTypeId: workTypeId)],
              status: SlotStatus.open,
              confirmedCount: 0,
              createdAt: DateTime(2025),
            ),
          ],
      myApplications: (uid) async => const <ApplicationModel>[],
      workTypeCatalog: (id) async => catalog,
      applicationOnce: (id) async => null,
    );

Future<void> _pump(WidgetTester t, WorkTypeCatalog catalog,
    {String? workTypeId, bool storedCreatedAt = true}) async {
  t.view.physicalSize = const Size(360, 780);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(milliseconds: 50));
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        home: JobPostingScreen(
          to: _to(storedCreatedAt: storedCreatedAt),
          workDetails: const [],
          reads: _reads(catalog, workTypeId, storedCreatedAt),
        ),
      ),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  bool shows(String text) => find.text(text, skipOffstage: false).evaluate().isNotEmpty;

  testWidgets('WMR-01 id 연결 — 그 업무의 최신 설명, 업무명은 저장본', (t) async {
    await _pump(t, _catalog([_wt('wtA', '상하차', 'A 최신 안내')]), workTypeId: 'wtA');
    expect(find.text('상하차', skipOffstage: false), findsWidgets);
    expect(shows('A 최신 안내'), isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('WMR-02 id 연결 · 업무유형 비활성 — 기존 공고는 계속 그 업무의 안내', (t) async {
    await _pump(t, _catalog([_wt('wtA', '상하차', 'A 안내', isActive: false)]), workTypeId: 'wtA');
    expect(shows('A 안내'), isTrue);
  });

  testWidgets('WMR-03 [D5] id 연결 · 같은 이름 새 문서 — 새 업무 안내를 붙이지 않는다', (t) async {
    // 이전 관찰(이름 연결): 이 상황에서 옛 공고에 '새 업무 안내'가 붙었다.
    await _pump(t, _catalog([
      _wt('wtA', '상하차', 'A 안내', isActive: false),
      _wt('wtNew', '상하차', '새 업무 안내', createdAt: DateTime(2026, 10, 1)),
    ]), workTypeId: 'wtA');
    expect(shows('새 업무 안내'), isFalse);
    expect(shows('A 안내'), isTrue);
  });

  testWidgets('WMR-04 id 연결 · 원래 문서가 지워짐 + 같은 이름 새 문서 — 안내 없음', (t) async {
    await _pump(t, _catalog([_wt('wtNew', '상하차', '새 업무 안내')]), workTypeId: 'wtA');
    expect(shows('새 업무 안내'), isFalse);
    expect(find.text('상하차', skipOffstage: false), findsWidgets);
  });

  testWidgets('WMR-05 레거시 · 그 이름 문서가 하나이고 공고보다 먼저 — 연결', (t) async {
    await _pump(t, _catalog([_wt('wtA', '상하차', 'A 안내')]));
    expect(shows('A 안내'), isTrue);
  });

  testWidgets('WMR-06 레거시 · 그 이름 문서가 공고 뒤에 생김(재사용) — 안내 없음', (t) async {
    await _pump(t, _catalog([_wt('wtNew', '상하차', '새 업무 안내', createdAt: DateTime(2026, 10, 1))]));
    expect(shows('새 업무 안내'), isFalse);
  });

  testWidgets('WMR-07 레거시 · 같은 이름 문서 2개(비활성 포함) — 안내 없음', (t) async {
    await _pump(t, _catalog([
      _wt('wtA', '상하차', 'A 안내', isActive: false),
      _wt('wtB', '상하차', '둘째 안내'),
    ]));
    expect(shows('A 안내'), isFalse);
    expect(shows('둘째 안내'), isFalse);
  });

  testWidgets('WMR-08 레거시 · 같은 이름의 읽을 수 없는 문서가 하나 더 — 안내 없음', (t) async {
    await _pump(t, _catalog([_wt('wtA', '상하차', 'A 안내')], extraNames: {'상하차': 1}));
    expect(shows('A 안내'), isFalse);
  });

  testWidgets('WMR-09 레거시 · 이름이 바뀌어 같은 이름 문서가 없음 — 안내 없음', (t) async {
    await _pump(t, _catalog([_wt('wtA', '하역', 'A 안내')]));
    expect(shows('A 안내'), isFalse);
    expect(find.text('상하차', skipOffstage: false), findsWidgets);
  });

  // ── [WORKTYPE-LOCAL-CLOSURE] 확인하지 못하면 숨긴다
  testWidgets('WMR-10 레거시 · 공고 문서에 createdAt 이 없음 — 현재 시각 기본값으로 연결하지 않는다', (t) async {
    await _pump(t, _catalog([_wt('wtA', '상하차', 'A 안내')]), storedCreatedAt: false);
    expect(shows('A 안내'), isFalse);
    expect(find.text('상하차', skipOffstage: false), findsWidgets);
  });

  testWidgets('WMR-11 레거시 · 목록을 끝까지 읽지 못함(상한) — 연결하지 않는다', (t) async {
    await _pump(t, _catalog([_wt('wtA', '상하차', 'A 안내')], complete: false));
    expect(shows('A 안내'), isFalse);
  });

  testWidgets('WMR-12 id 연결 · 목록이 불완전해도 그 문서는 확인된다 — 연결', (t) async {
    await _pump(t, _catalog([_wt('wtA', '상하차', 'A 안내')], complete: false), workTypeId: 'wtA');
    expect(shows('A 안내'), isTrue);
  });

  testWidgets('WMR-13 id 연결 · 문서의 businessId 가 다른 사업장 — 연결하지 않는다', (t) async {
    await _pump(t, _catalog([_wt('wtA', '상하차', '남의 안내', businessId: 'bizX')]), workTypeId: 'wtA');
    expect(shows('남의 안내'), isFalse);
  });

  testWidgets('WMR-14 목록이 다른 사업장의 것 — 연결하지 않는다', (t) async {
    await _pump(t, _catalog([_wt('wtA', '상하차', 'A 안내')], businessId: 'bizX'), workTypeId: 'wtA');
    expect(shows('A 안내'), isFalse);
  });
}
