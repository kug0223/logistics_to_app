import 'dart:async';

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
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/core/work_detail_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/job_posting_reads.dart';
import 'package:ALfit/services/work_type_guide_resolver.dart';
import 'package:ALfit/screens/common/job_posting_screen.dart';

/// [R7-P2-2 후속 P22-D] 공고 상세가 **목록에서 고른 하루**를 재조회 결과에서
/// 되찾아 그 날의 업무·임금·정원을 말하는가.
///
///   seed(`to`/`workDetails`)와 재조회 결과를 **일부러 다르게** 주어,
///   무엇이 화면과 지원 판단을 지배하는지 실행으로 본다.

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


/// 오늘로부터 `days` 일 뒤의 **KST 자정** instant.
DateTime _kstDayPlus(int days) {
  final k = DateTime.now().toUtc()
      .add(const Duration(hours: 9))
      .add(Duration(days: days));
  return _kstInstant(k.year, k.month, k.day);
}

// [시한부 fixture 정정] 예전에는 `2026-10-10`·`2026-10-11` 고정이었다.
//   그 날이 지나는 순간 모집중 슬롯이 **마감된 공고**로 바뀌어 JPD-5 가
//   깨졌다(2026-10-12 에 실제로 깨졌다). 이 파일이 묻는 것은 **연속한 두 날**의
//   선택·전달·표시이므로 날짜 값 자체는 중요하지 않다. 항상 미래가 되게 센다.
final _d1 = _kstDayPlus(2);


WorkDetailData _wd({
  required String id,
  required String type,
  required int wage,
  required int required_,
}) =>
    WorkDetailData(
      wdId: id,
      workType: type,
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: wage,
      wageType: 'hourly',
      requiredCount: required_,
      startTime: '09:00',
      endTime: '18:00',
      order: 0,
    );

SlotModel _slot({
  required String id,
  required DateTime date,
  required List<WorkDetailData> details,
  String status = SlotStatus.open,
  int confirmed = 0,
}) =>
    SlotModel(
      id: id,
      toId: 'to1',
      date: date,
      workDetails: details,
      status: status,
      confirmedCount: confirmed,
      createdAt: DateTime(2025),
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

BusinessModel _business() => BusinessModel(
      id: 'biz1',
      name: '강남 물류센터',
      ownerId: 'admin1',
      businessNumber: '000-00-00000',
      address: '서울시 강남구',
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: DateTime(2025),
    );


// ── [L33 · impl_7] seed(목록이 넘긴 공고)가 있으면 상세를 **바로** 그리고, 슬롯·내 지원·업무 안내는 점진으로 채운다 ──
//   예전: 슬롯·내 지원·업무 안내가 모두 끝날 때까지 화면 전체가 '공고 정보를 불러오는 중...' 이었다.
//   지금: 머리말·사업장 정보는 즉시 · 날짜/업무 영역은 자리표시 · 지원 버튼은 확정 전 비활성.
class _Gate {
  final slotsC = Completer<List<SlotModel>>();
  JobPostingReads get reads => JobPostingReads(
        toOrFailure: (id) async => (to: _to(), failed: false),
        workDetails: (id) async => const [],
        businessById: (id) async => _business(),
        slots: (id, {bool visibleOnly = true}) => slotsC.future,
        myApplications: (uid) async => const <ApplicationModel>[],
        workTypeCatalog: (id) async => WorkTypeCatalog.empty,
        applicationOnce: (id) async => null,
      );
}

Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(home: screen),
  ));
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

ElevatedButton? _cta(WidgetTester t) {
  final w = t.widgetList<ElevatedButton>(find.byType(ElevatedButton));
  return w.isEmpty ? null : w.last;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('L33-1 seed 진입 — 슬롯을 기다리는 동안에도 머리말이 보이고 지원 버튼은 비활성 · 슬롯이 오면 업무가 채워진다', (tester) async {
    final g = _Gate();
    await _pumpScreen(tester, JobPostingScreen(to: _to(), workDetails: const [], reads: g.reads));
    expect(find.text('공고 정보를 불러오는 중...'), findsNothing, reason: '화면 전체 스피너로 막지 않는다');
    expect(find.textContaining('단기 모집'), findsWidgets, reason: 'seed 머리말 즉시');
    expect(find.text('상하차'), findsNothing, reason: '업무는 슬롯 확정 전 그리지 않는다(자리표시)');
    expect(find.textContaining('선택 가능한 근무 날짜가 없'), findsNothing, reason: '읽는 중을 날짜 없음으로 말하지 않는다');
    final pendingCta = _cta(tester);
    expect(pendingCta, isNotNull);
    expect(pendingCta!.onPressed, isNull, reason: '확정 전 지원 버튼 비활성');
    g.slotsC.complete([
      _slot(id: 's1', date: _d1.toLocal(), details: [_wd(id: 'wd1', type: '상하차', wage: 11000, required_: 2)]),
    ]);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('상하차'), findsWidgets);
  });

  testWidgets('L33-2 seed 없이 id 로만 들어오면 예전처럼 전체 로딩(회귀 경계)', (tester) async {
    final g = _Gate();
    await _pumpScreen(tester, JobPostingScreen(toId: 'to1', reads: g.reads));
    expect(find.text('공고 정보를 불러오는 중...'), findsOneWidget);
    g.slotsC.complete(const []);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}
