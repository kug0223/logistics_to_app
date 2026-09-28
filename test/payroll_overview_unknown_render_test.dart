import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_overview_reads.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_overview_screen.dart';

/// [R7-P1-5 PAY-1·PAY-4] 급여 개요·월 상세를 **실제 위젯으로** 그린다.
///
///   이 화면의 월별 `미확정`·`미이체` 건수는 출근 집계 CF 하나에서만 온다.
///   그 호출이 실패하면 예전에는 12개월 전부 0 이 되어 미이체 줄이 사라지고,
///   월 상세는 `이체 완료 = 확정 - 미이체` 를 계산해 **전부 이체된 달**이라고
///   말했다. 여기서는 `PayrollOverviewReads` 만 갈아끼워 그 경로를 그대로 돈다.
///   합계 구성·판정·문구는 화면에 남아 있고, 테스트용 카드를 따로 만들지 않는다.

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
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

const _biz = 'biz1';

/// 급여 권한이 실제로 있는 관리자 — 권한 없는 provider 로 숨겨진 화면을
/// "확인했다"고 세지 않기 위해 production 판정 경로를 통과시킨다.
class _WageAdmin extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'admin1',
        username: 'admin1',
        name: '김관리',
        email: 'admin1@alfit.local',
        role: UserRole.BUSINESS_ADMIN,
        managedBusinessIds: const [_biz],
      );

  @override
  bool get isSubAdmin => false;

  @override
  String? get effectiveBusinessId => null;

  @override
  PermissionCheck checkCurrentBusiness(
          bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;

  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;

  @override
  bool can(bool Function(MemberPermissions p) check) => true;
}

BusinessModel _business(String id, String name) => BusinessModel(
      id: id,
      name: name,
      ownerId: 'admin1',
      businessNumber: '000-00-00000',
      address: '서울시 어딘가',
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: DateTime(2026, 1, 1),
    );

final int _thisYear = DateTime.now().year;
final int _thisMonth = DateTime.now().month;
String get _ym => '$_thisYear-${_thisMonth.toString().padLeft(2, '0')}';

/// CF `callableGetPayrollSummaries` 의 item 모양.
Map<String, dynamic> _summaryItem({
  required int totalPayout,
  required int confirmedCount,
  required int workerCount,
}) =>
    {
      'id': '${_biz}_$_ym',
      'businessId': _biz,
      'yearMonth': _ym,
      'year': _thisYear,
      'month': _thisMonth,
      'totalPayout': totalPayout,
      'confirmedCount': confirmedCount,
      'workerCount': workerCount,
      'notTransferredCount': 0,
      'updatedAt': DateTime.now().toIso8601String(),
    };

/// CF `callableGetAdminAttendances` 의 item 모양(이 화면이 쓰는 필드만).
Map<String, dynamic> _attItem({
  required String wageStatus,
  required int finalWage,
  String status = 'present',
  String userId = 'u1',
}) =>
    {
      'yearMonth': _ym,
      'wageStatus': wageStatus,
      'status': status,
      'finalWage': finalWage,
      'userId': userId,
    };

PayrollOverviewReads _reads({
  List<Map<String, dynamic>>? summaries,
  List<Map<String, dynamic>>? attendances,
  Object? attendanceError,
  List<({String id, Map<String, dynamic> data})>? workers,
  Object? workersError,
}) =>
    PayrollOverviewReads(
      businesses: ({
        required bool isSubAdmin,
        required String? effectiveBusinessId,
        required List<String> managedIds,
      }) async =>
          [_business(_biz, '강남 물류센터')],
      payrollSummaries: ({required String businessId, required int year}) async =>
          summaries ??
          [
            _summaryItem(totalPayout: 4800000, confirmedCount: 5, workerCount: 3),
          ],
      adminAttendances: ({
        required String businessId,
        required String yearMonthGte,
        required String yearMonthLte,
      }) async {
        if (attendanceError != null) throw attendanceError;
        return attendances ??
            [
              _attItem(wageStatus: 'confirmed', finalWage: 1600000),
              _attItem(wageStatus: 'confirmed', finalWage: 1600000, userId: 'u2'),
              _attItem(wageStatus: 'confirmed', finalWage: 1600000, userId: 'u3'),
              _attItem(wageStatus: 'pending', finalWage: 0, userId: 'u4'),
            ];
      },
      workerSummaries: (summaryId) async {
        if (workersError != null) throw workersError;
        return workers ??
            [
              (
                id: 'u1',
                data: {'name': '김근로', 'totalPayout': 1600000, 'workDays': 2},
              ),
            ];
      },
      repairSummary: ({
        required String businessId,
        required String yearMonth,
      }) async {},
      todayPaymentCount: (_) async => 0,
    );

Future<void> _pump(
  WidgetTester tester, {
  required PayrollOverviewReads reads,
  Size size = const Size(390, 900),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _WageAdmin()),
        // 알림 배지만 쓰는 provider — 구독을 시작하지 않으므로 기본 인스턴스로 충분하다.
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: PayrollOverviewScreen(reads: reads),
      ),
    ),
  );
  // 멈추지 않는 애니메이션이 있을 수 있어 유한 프레임으로 흘려보낸다.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('POV-1 정상 — 미이체 건수를 그린다', (tester) async {
    await _pump(tester, reads: _reads());

    expect(tester.takeException(), isNull);
    expect(find.textContaining('미이체 3'), findsOneWidget);
    expect(find.text('미이체 확인 못함'), findsNothing);
  });

  testWidgets('POV-2 출근 집계 실패 — 0 이 아니라 확인 못함', (tester) async {
    await _pump(tester,
        reads: _reads(attendanceError: StateError('attendance cf down')));

    expect(tester.takeException(), isNull);
    // 금액은 집계 projection 에서 왔으므로 그대로 있다.
    expect(find.textContaining('4,800,000'), findsWidgets);
    // 미이체 줄이 사라지지도, 0 이 되지도 않는다.
    expect(find.text('미이체 확인 못함'), findsOneWidget);
    expect(find.textContaining('미이체 0'), findsNothing);
  });

  testWidgets('POV-3 월 상세 — 모를 때 이체 완료 건수를 계산해 말하지 않는다',
      (tester) async {
    await _pump(tester,
        reads: _reads(attendanceError: StateError('attendance cf down')));

    // 월 카드를 눌러 상세로 들어간다(production 경로).
    await tester.tap(find.text('미이체 확인 못함'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('이체 완료'), findsOneWidget);
    expect(find.text('미이체'), findsOneWidget);
    // 두 수치 모두 모름으로 말한다 — `5건`(=확정 5 - 미이체 0)을 주장하지 않는다.
    expect(find.text('확인 못함'), findsNWidgets(2));
    // 파생값(확정 5 - 미이체 0 = 5)을 이체 완료 자리에 앉히지 않는다.
    //   우측 요약 칩의 '확정 5건' 은 집계 projection 값이라 그대로 있다.
    final transferRow = find.ancestor(
      of: find.text('이체 완료'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: transferRow.first, matching: find.text('확인 못함')),
      findsOneWidget,
    );
  });

  testWidgets('POV-4 근무자 목록 조회 실패 — 집계 없음이라고 말하지 않는다',
      (tester) async {
    await _pump(tester, reads: _reads(workersError: StateError('perm denied')));

    await tester.tap(find.textContaining('미이체 3'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('근무자 목록을 불러오지 못했습니다'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    // 실패에 서버 재집계를 권하지 않는다.
    expect(find.text('집계 데이터가 없습니다'), findsNothing);
    expect(find.text('집계 데이터 복원'), findsNothing);
    expect(find.text('확정된 급여가 없습니다'), findsNothing);
  });

  testWidgets('POV-5 근무자 행은 확정 근무 건수로 말한다', (tester) async {
    await _pump(tester, reads: _reads());

    await tester.tap(find.textContaining('미이체 3'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('김근로'), findsOneWidget);
    // projection 의 workDays 는 확정·이체된 attendance 1건당 +1 이다.
    expect(find.text('확정 근무 2건'), findsOneWidget);
    expect(find.text('2일 근무'), findsNothing);
  });

  testWidgets('POV-6 320dp·배율 1.3 — 큰 금액과 새 문구가 함께 있어도 예외 0',
      (tester) async {
    await _pump(tester,
        size: const Size(320, 900),
        textScale: 1.3,
        reads: _reads(
          summaries: [
            _summaryItem(
                totalPayout: 128400000, confirmedCount: 147, workerCount: 62),
          ],
          attendanceError: StateError('attendance cf down'),
        ));

    expect(tester.takeException(), isNull);
    expect(find.text('미이체 확인 못함'), findsOneWidget);
    expect(find.textContaining('128,400,000'), findsWidgets);
  });
}
