import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/income_detail_screen.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';

/// [R7-P2-1 최종 · VERIFY-INCOME-MONTH-LOCAL]
/// 홈이 말하는 **'이번 달'** 의 라벨·조회 연월·금액이 같은 달을 가리키는가.
///
///   KST 9/30 → 10/1 경계에서 KST 기기와 UTC 기기를 같은 instant 로 세워
///   비교한다. 기기 흉내는 `attendance_kst_parity` 와 같다 — Dart 의
///   DateTime 은 instant 와 필드가 묶여 있어 호스트(KST)와 UTC 두 가지만
///   충실히 재현되고, 이 테스트는 **UTC 기기**로 비-KST 를 대표한다.

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

enum _Device { kst, utc }

DateTime _kst(int y, int mo, int d, [int h = 0, int mi = 0]) =>
    DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 9));

DateTime _dev(DateTime instant, _Device d) =>
    d == _Device.kst ? instant.toLocal() : instant.toUtc();

const _biz = 'biz1';

ApplicationModel _app({required String id, required DateTime workDate}) =>
    ApplicationModel(
      id: id,
      toId: 'to1',
      uid: 'u1',
      businessId: _biz,
      businessName: '강남 물류센터',
      toTitle: '단기',
      status: AppStatus.confirmed,
      selectedWorkType: '상하차',
      startTime: '09:00',
      endTime: '18:00',
      wage: 100000,
      workDate: workDate,
      appliedAt: workDate,
    );

/// 확정 임금이 찍힌 근태 — 월별로 **다른 액수**를 준다.
AttendanceModel _att({
  required String id,
  required DateTime workDate,
  required int finalWage,
}) =>
    AttendanceModel(
      id: id,
      applicationId: id,
      userId: 'u1',
      businessId: _biz,
      businessName: '강남 물류센터',
      workDate: workDate,
      workType: '상하차',
      status: AttendanceModel.statusPresent,
      wageStatus: AttendanceModel.wageConfirmed,
      adminConfirmed: true,
      finalWage: finalWage,
      checkInAt: workDate,
      checkOutAt: workDate.add(const Duration(hours: 9)),
      createdAt: workDate,
    );

BusinessModel _business() => BusinessModel(
      id: _biz,
      name: '강남 물류센터',
      ownerId: 'a1',
      businessNumber: '000-00-00000',
      address: '서울시',
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// 서버(`getMyMonthlyAttendances`)와 **같은 자**로 자르는 원장 —
/// 요청한 연월의 KST 달력월에 드는 기록만 돌려준다.
/// 이 동형 표본이 없으면 "어느 달 원장을 읽었는가"를 볼 수 없다.
UserHomeReads _reads({
  required List<ApplicationModel> apps,
  required List<AttendanceModel> ledgerKst, // workDate 는 KST instant
  required _Device device,
  List<String>? monthCalls,
  Object? ledgerError,
}) =>
    UserHomeReads(
      myApplications: (uid) async => apps,
      myMonthlyAttendances: (
          {required String userId, required int year, required int month}) async {
        monthCalls?.add('$year-$month');
        if (ledgerError != null) throw ledgerError;
        return ledgerKst.where((a) {
          final k = a.workDate.toUtc().add(const Duration(hours: 9));
          return k.year == year && k.month == month;
        }).map((a) {
          // 기기가 읽어들이는 표현으로 바꿔 준다(Timestamp.toDate().toLocal()).
          return _att(
            id: a.id,
            workDate: _dev(a.workDate, device),
            finalWage: a.finalWage!,
          );
        }).toList();
      },
      publishedTOs: () async => const <TOModel>[],
      pendingIdCardRequests: (uid) async => const <IdCardAccessRequestModel>[],
      myRenewalProposals: () async => const <RenewalProposalModel>[],
      businessById: (id) async => _business(),
      invalidatePublishedTOsCache: () {},
    );

Future<void> _pumpHome(
  WidgetTester tester, {
  required UserHomeReads reads,
  required DateTime nowInstant,
  required _Device device,
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        home: UserHomeScreen(
          reads: reads,
          clock: () => _dev(nowInstant, device),
        ),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'tour_completed_user_home': true});
  });

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  // 월별로 **다른 액수**. 9/30 과 10/1 이 붙어 있는 경계 표본이다.
  final ledger = [
    _att(id: 'sep30', workDate: _kst(2026, 9, 30), finalWage: 90000),
    _att(id: 'oct01', workDate: _kst(2026, 10, 1), finalWage: 10000),
  ];
  final apps = [
    _app(id: 'sep30', workDate: _kst(2026, 9, 30)),
    _app(id: 'oct01', workDate: _kst(2026, 10, 1)),
  ];

  // KST 10/1 05:00 — UTC 기기의 달력은 아직 9/30 20:00 이다.
  final boundary = _kst(2026, 10, 1, 5, 0);

  for (final device in _Device.values) {
    final label = device == _Device.kst ? 'KST 기기' : 'UTC 기기';

    testWidgets('IMK-1 $label · KST 10/1 05:00 — 라벨이 KST 달을 말한다',
        (tester) async {
      await _pumpHome(
        tester,
        reads: _reads(apps: apps, ledgerKst: ledger, device: device),
        nowInstant: boundary,
        device: device,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('2026년 10월 ›'), findsOneWidget,
          reason: '$label 에서 홈이 9월이라고 말하면 사용자는 다른 달 돈을 본다');
      expect(find.text('2026년 9월 ›'), findsNothing);
    });

    testWidgets('IMK-2 $label · 읽는 원장도 같은 KST 달이다', (tester) async {
      final calls = <String>[];
      await _pumpHome(
        tester,
        reads: _reads(
            apps: apps, ledgerKst: ledger, device: device, monthCalls: calls),
        nowInstant: boundary,
        device: device,
      );

      expect(calls.contains('2026-10'), isTrue,
          reason: '라벨이 10월이면 원장도 10월이어야 한다 — 호출: $calls');
    });

    testWidgets('IMK-3 $label · KST 1일에 번 돈이 이번 달에 들어온다',
        (tester) async {
      await _pumpHome(
        tester,
        reads: _reads(apps: apps, ledgerKst: ledger, device: device),
        nowInstant: boundary,
        device: device,
      );

      // 10월 원장에는 10/1 의 10,000원만 있다. 9/30 의 90,000원이 섞이면
      // 다른 달 돈을 이번 달로 부르는 것이다.
      expect(find.text('10,000원'), findsWidgets,
          reason: 'KST 1일 근무가 기기 로컬 달 필터에 걸려 사라졌다');
      expect(find.text('90,000원'), findsNothing,
          reason: '지난달 금액이 이번 달에 섞였다');
      expect(find.text('아직 이번 달 수입이 없어요'), findsNothing);
    });

    testWidgets('IMK-4 $label · 상세로 넘기는 월도 같은 달이다', (tester) async {
      await _pumpHome(
        tester,
        reads: _reads(apps: apps, ledgerKst: ledger, device: device),
        nowInstant: boundary,
        device: device,
      );

      await tester.tap(find.text('2026년 10월 ›'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final pushed = tester.widget<IncomeDetailScreen>(
          find.byType(IncomeDetailScreen, skipOffstage: false));
      expect(pushed.initialYear, 2026);
      expect(pushed.initialMonth, 10,
          reason: '홈이 10월이라고 말했으면 상세도 10월로 열려야 한다');
    });
  }

  testWidgets('IMK-5 월 중간에는 두 기기가 같은 달을 말한다(회귀)', (tester) async {
    for (final device in _Device.values) {
      await _pumpHome(
        tester,
        reads: _reads(apps: apps, ledgerKst: ledger, device: device),
        nowInstant: _kst(2026, 10, 15, 12, 0),
        device: device,
      );
      expect(find.text('2026년 10월 ›'), findsOneWidget);
    }
  });

  testWidgets('IMK-6 원장 조회 실패를 0원으로 바꾸지 않는다(UTC 기기)',
      (tester) async {
    await _pumpHome(
      tester,
      reads: _reads(
        apps: apps,
        ledgerKst: ledger,
        device: _Device.utc,
        ledgerError: Exception('ledger read failed'),
      ),
      nowInstant: boundary,
      device: _Device.utc,
    );

    expect(find.text('확인 못함'), findsWidgets);
    expect(find.text('아직 이번 달 수입이 없어요'), findsNothing);
    expect(find.text('2026년 10월 ›'), findsOneWidget,
        reason: '조회가 실패해도 말하는 달은 흔들리지 않는다');
  });

  testWidgets('IMK-7 명시 선택한 과거 월은 그대로 열린다', (tester) async {
    // 홈에서 넘어온 월이 아니라 **사용자가 고른 월**로 여는 경우.
    //   상세는 initState 에서 한 번만 읽고 이후 "지금"으로 덮지 않는다.
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
          ChangeNotifierProvider<NotificationProvider>(
              create: (_) => NotificationProvider()),
        ],
        child: const MaterialApp(
          home: IncomeDetailScreen(initialYear: 2026, initialMonth: 7),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('2026년 7월'), findsOneWidget,
        reason: '자정이나 재조회가 선택 월을 현재 월로 바꾸면 안 된다');
  });
}
