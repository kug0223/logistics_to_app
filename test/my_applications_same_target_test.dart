import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_applications_reads.dart';
import 'package:ALfit/screens/user/my_applications_screen.dart';
import 'package:ALfit/utils/format_helper.dart';

/// [R7-P2-2 후속 P22-M] 지원한 그 건이 **같은 ID·날짜·업무·상태·사유**로
/// 내 지원 목록에 나타나는가. 취소 기록을 활성 지원처럼 세지 않는가.

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

final DateTime _today = FormatHelper.toKstDate(DateTime.now());
DateTime _day(int o) => _today.add(Duration(days: o));

ApplicationModel _app({
  required String id,
  required String status,
  required DateTime workDate,
  String workType = '상하차',
  String? cancelReason,
  String businessName = '강남 물류센터',
}) =>
    ApplicationModel(
      id: id,
      toId: 'to1',
      uid: 'u1',
      businessId: 'biz1',
      businessName: businessName,
      toTitle: '단기 모집',
      status: status,
      selectedWorkType: workType,
      startTime: '09:00',
      endTime: '18:00',
      wage: 12000,
      workDate: workDate,
      appliedAt: _day(-2),
      cancelReason: cancelReason,
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
      totalRequired: 3,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: _day(-10),
      statusUpdatedAt: _day(-10),
    );

MyApplicationsReads _reads(
  List<ApplicationModel> apps, {
  Object? pageError,
  Object? contractsError,
}) =>
    MyApplicationsReads(
      myApplicationsPaged: (
          {required String uid,
          required int pageSize,
          String? startAfterDocId}) async {
        if (pageError != null) throw pageError;
        return {'items': apps, 'lastDocId': null, 'hasMore': false};
      },
      toOrFailure: (id) async => (to: _to(), failed: false),
      contractsByWorker: (uid) async {
        if (contractsError != null) throw contractsError;
        return const <EmploymentContractModel>[];
      },
      autoExpirePending: (uid) async {},
    );

Future<void> _pump(
  WidgetTester tester, {
  required MyApplicationsReads reads,
  Size size = const Size(390, 1600),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
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
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: MyApplicationsScreen(reads: reads),
      ),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('MAS-1 지원한 건이 같은 날짜·업무로 목록에 나타난다', (tester) async {
    await _pump(
      tester,
      reads: _reads([
        _app(id: 'a1', status: AppStatus.pending, workDate: _day(3)),
      ]),
    );

    expect(tester.takeException(), isNull);
    final d = _day(3);
    expect(find.textContaining('${d.month}월 ${d.day}일'), findsWidgets,
        reason: '지원한 그 날짜가 보여야 한다');
    // 카드는 사업장·공고 제목·날짜·임금·상태로 그 건을 말한다.
    expect(find.text('단기 모집'), findsWidgets);
    expect(find.text('12,000원'), findsWidgets);
    expect(find.text('지원 검토 중'), findsWidgets);
  });

  testWidgets('MAS-2 자동취소는 **사유별 문구**로 말한다 — generic 으로 뭉개지 않는다',
      (tester) async {
    await _pump(
      tester,
      reads: _reads([
        _app(
          id: 'a2',
          status: AppStatus.autoCanceled,
          workDate: _day(3),
          cancelReason: 'SCHEDULE_CONFLICT',
        ),
      ]),
    );

    expect(find.text('다른 업무가 확정되어 자동 취소되었어요'), findsWidgets);
    expect(find.text('취소된 지원이에요'), findsNothing,
        reason: '사유를 아는데 generic 문구로 말하지 않는다');
  });

  testWidgets('MAS-3 사유를 모르는 자동취소는 지어내지 않는다(양성 대조)',
      (tester) async {
    await _pump(
      tester,
      reads: _reads([
        _app(id: 'a3', status: AppStatus.autoCanceled, workDate: _day(3)),
      ]),
    );

    expect(find.text('취소된 지원이에요'), findsWidgets);
    expect(find.text('다른 업무가 확정되어 자동 취소되었어요'), findsNothing);
  });

  testWidgets('MAS-4 취소 기록이 진행 중 지원처럼 보이지 않는다', (tester) async {
    await _pump(
      tester,
      reads: _reads([
        _app(id: 'live', status: AppStatus.pending, workDate: _day(3)),
        _app(
            id: 'dead',
            status: AppStatus.autoCanceled,
            workDate: _day(4),
            businessName: '취소된 사업장',
            cancelReason: 'TO_DELETED'),
      ]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('공고가 삭제되어 자동 취소되었어요'), findsWidgets,
        reason: '취소 건은 취소로 말해야 한다');
    // 탭 머리의 모집단 — 취소 건이 **진행중**에 섞이지 않는다.
    expect(find.text('전체 2'), findsOneWidget);
    expect(find.text('진행중 1'), findsOneWidget);
    expect(find.text('종료 1'), findsOneWidget);
  });

  testWidgets('MAS-5 목록 조회 실패를 "지원 없음"으로 말하지 않는다', (tester) async {
    await _pump(tester, reads: _reads(const [], pageError: Exception('network')));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('아직'), findsNothing,
        reason: '못 읽은 것을 "아직 지원이 없다"로 바꾸지 않는다');
  });

  testWidgets('MAS-6 계약 조회 실패가 목록 전체를 지우지 않는다(부분 실패)',
      (tester) async {
    await _pump(
      tester,
      reads: _reads([
        _app(id: 'c1', status: AppStatus.confirmed, workDate: _day(3)),
      ], contractsError: Exception('contract read failed')),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('단기 모집'), findsWidgets,
        reason: '계약을 못 읽어도 지원 목록 자체는 유효하다');
  });

  for (final size in const [Size(320, 1600), Size(412, 1600)]) {
    for (final scale in const [1.3, 2.0]) {
      testWidgets(
          'MAS-R ${size.width.toInt()}dp × $scale — 날짜·업무·상태가 예외 없이 그려진다',
          (tester) async {
        await _pump(
          tester,
          reads: _reads([
            _app(
                id: 'r1',
                status: AppStatus.confirmed,
                workDate: _day(3),
                businessName: '서울특별시 강남구 테헤란로 물류센터 제2창고'),
          ]),
          size: size,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('서울특별시 강남구 테헤란로 물류센터 제2창고'), findsWidgets);
        expect(find.text('12,000원'), findsWidgets);
      });
    }
  }
}
