// [BOTTOM-BAR-DOUBLE-COUNT] 공고 상세 맨 아래의 빈 공간.
//
// 이 화면의 하단 CTA 는 `Scaffold.bottomNavigationBar` 로 달려 있다. 즉
// **Scaffold 가 이미 그 높이를 본문에서 빼 준다** — 본문은 바 아래로 가지
// 않는다. 그런데 스크롤 내용의 마지막 자식이 100dp 고정 spacer 였다.
// 바를 피하려고 비운 자리인데, 바는 이미 피해져 있었다. 그래서 끝까지
// 내리면 마지막 카드와 CTA 사이에 쓰이지 않는 띠가 남았다.
//
// 같은 짝이 초대 fallback 상세(`invitation_promise_card.dart`)에도 있었다.
// 둘 다 `bottomNavigationBar` + 꼬리 100dp 라 같은 이중 계산이다.
import 'dart:io';

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

WorkDetailData _wd() => WorkDetailData(
      wdId: 'wd1',
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

TOModel _to() => TOModel(
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
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

/// 주소가 있어야 '찾아오는 길' 섹션이 그려진다.
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

JobPostingReads _reads() => JobPostingReads(
      toOrFailure: (id) async => (to: _to(), failed: false),
      workDetails: (id) async => const <WorkDetailModel>[],
      businessById: (id) async => _business(),
      slots: (id, {bool visibleOnly = true}) async => [
            SlotModel(
              id: 's1',
              toId: 'to1',
              date: _kstInstant(2026, 10, 10),
              workDetails: [_wd()],
              status: SlotStatus.open,
              confirmedCount: 0,
              createdAt: DateTime(2025),
            ),
          ],
      myApplications: (uid) async => const <ApplicationModel>[],
      businessWorkTypes: (id) async => const <BusinessWorkTypeModel>[],
      applicationOnce: (id) async => null,
    );

Future<void> _pump(
  WidgetTester t, {
  Size size = const Size(360, 780),
  double bottomInset = 0,
}) async {
  t.view.physicalSize = size;
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
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            padding: EdgeInsets.only(bottom: bottomInset),
            viewPadding: EdgeInsets.only(bottom: bottomInset),
          ),
          child: child!,
        ),
        home: JobPostingScreen(
          to: _to(),
          workDetails: const [],
          reads: _reads(),
        ),
      ),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// 스크롤을 끝까지 내린다 — 빈 공간은 거기서만 보인다.
Future<void> _toBottom(WidgetTester t) async {
  final scrollable = find
      .descendant(
          of: find.byType(CustomScrollView), matching: find.byType(Scrollable))
      .first;
  final pos = t.state<ScrollableState>(scrollable).position;
  pos.jumpTo(pos.maxScrollExtent);
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

/// 마지막 흰 섹션('찾아오는 길' 카드)의 바닥.
double _lastPanelBottom(WidgetTester t) => t
    .getRect(find
        .ancestor(
            of: find.text('찾아오는 길'),
            matching: find.byWidgetPredicate(
                (w) => w is Container && w.color == Colors.white))
        .first)
    .bottom;

/// 본문이 쓸 수 있는 영역의 바닥 = 하단 CTA 바의 윗변.
/// Scaffold 가 bottomNavigationBar 높이를 이미 빼 줬다는 뜻이기도 하다.
/// 가로 날짜 스트립도 Viewport 를 만든다 — 세로 본문 쪽으로 좁힌다.
double _viewportBottom(WidgetTester t) => t
    .getRect(find
        .descendant(
            of: find.byType(CustomScrollView), matching: find.byType(Viewport))
        .first)
    .bottom;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('JPB-01 끝까지 내렸을 때 마지막 카드와 CTA 사이에 빈 띠가 없다', (t) async {
    await _pump(t);
    await _toBottom(t);

    final gap = _viewportBottom(t) - _lastPanelBottom(t);
    expect(gap, lessThanOrEqualTo(24.0),
        reason: '바는 Scaffold 가 이미 피해 줬는데 본문이 또 비워 두고 있다');
    // 반대쪽으로도 틀리지 않게 — 마지막 카드가 CTA 에 딱 붙으면 안 된다.
    // 섹션 사이 간격(8dp)만큼은 남긴다.
    expect(gap, greaterThanOrEqualTo(7.0), reason: '카드가 CTA 에 붙었다');
    expect(t.takeException(), isNull);
  });

  testWidgets('JPB-02 화면 높이가 달라져도 빈 띠가 늘지 않는다', (t) async {
    for (final h in [640.0, 780.0, 900.0]) {
      await _pump(t, size: Size(360, h));
      await _toBottom(t);
      final gap = _viewportBottom(t) - _lastPanelBottom(t);
      expect(gap, lessThanOrEqualTo(24.0),
          reason: '화면 높이 ${h.toStringAsFixed(0)}');
      expect(t.takeException(), isNull);
    }
  });

  testWidgets('JPB-03 하단 시스템 inset — 여백을 두 번 먹지 않는다', (t) async {
    await _pump(t, bottomInset: 48);
    await _toBottom(t);
    final gap = _viewportBottom(t) - _lastPanelBottom(t);
    expect(gap, lessThanOrEqualTo(24.0));
    expect(t.takeException(), isNull);
  });

  test('JPB-04 소스 계약 — 하단 바를 피하려는 꼬리 여백이 lib 전체에 없다', () {
    // `bottomNavigationBar` 를 쓰는 화면은 바 높이를 본문에서 또 빼면 안 된다.
    // Scaffold 가 이미 빼 줬기 때문이다.
    //
    // 이 프로젝트가 실제로 쓴 세 가지 표현만 본다. 그래야 120px 짜리 이미지
    // 같은 멀쩡한 고정 높이를 잘못 잡지 않는다.
    final clearance = RegExp(
      r'copyWith\(bottom:\s*(?:ResponsiveHelper\.spacing\(context,\s*)?(?:8\d|9\d|1\d\d)\b'
      r'|bottom:\s*ResponsiveHelper\.spacing\(context,\s*(?:8\d|9\d|1\d\d)\b'
      r'|SizedBox\(height:\s*ResponsiveHelper\.spacing\(context,\s*(?:8\d|9\d|1\d\d)\b',
    );

    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final code = f
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      if (!code.contains('bottomNavigationBar')) continue;
      if (clearance.hasMatch(code)) offenders.add(f.path);
    }
    expect(offenders, isEmpty,
        reason: '하단 바를 두 번 피하는 화면이 남아 있다');

    // 고친 네 곳이 그대로인지도 못박는다 — 전수 스캔은 "없음"만 말한다.
    for (final p in const [
      'lib/screens/common/job_posting_screen.dart',
      'lib/widgets/user/invitation_promise_card.dart',
      'lib/screens/business_admin/to_management/create_to_screen.dart',
      'lib/screens/business_admin/to_management/edit_to_screen.dart',
    ]) {
      expect(File(p).readAsStringSync().contains('bottomNavigationBar'), isTrue,
          reason: '$p — 전제가 바뀌었다면 이 셀을 다시 생각해야 한다');
    }
  });
}
