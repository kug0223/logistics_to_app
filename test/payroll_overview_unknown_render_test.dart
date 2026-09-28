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
import 'package:ALfit/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';

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
  int notTransferredCount = 0,
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
      'notTransferredCount': notTransferredCount,
      'updatedAt': DateTime.now().toIso8601String(),
    };

/// CF `callableGetAdminAttendances` 의 item 모양(이 화면이 쓰는 필드만).
Map<String, dynamic> _attItem({
  required String wageStatus,
  required int finalWage,
  String status = 'present',
  String userId = 'u1',
  String id = 'r1',
}) =>
    {
      'id': id,
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
  bool attendanceLimitReached = false,
  List<({String id, Map<String, dynamic> data})>? workers,
  Object? workersError,
  Map<String, int>? calls,
}) =>
    PayrollOverviewReads(
      businesses: ({
        required bool isSubAdmin,
        required String? effectiveBusinessId,
        required List<String> managedIds,
      }) async =>
          [_business(_biz, '강남 물류센터')],
      payrollSummaries: ({required String businessId, required int year}) async {
        if (calls != null) calls['summaries'] = (calls['summaries'] ?? 0) + 1;
        return summaries ??
            [
              _summaryItem(totalPayout: 4800000, confirmedCount: 5, workerCount: 3),
            ];
      },
      adminAttendances: ({
        required String businessId,
        required String yearMonthGte,
        required String yearMonthLte,
      }) async {
        if (calls != null) calls['ledger'] = (calls['ledger'] ?? 0) + 1;
        if (attendanceError != null) throw attendanceError;
        return (
          items: attendances ??
              [
                _attItem(wageStatus: 'confirmed', finalWage: 1600000),
                _attItem(wageStatus: 'confirmed', finalWage: 1600000, userId: 'u2'),
                _attItem(wageStatus: 'confirmed', finalWage: 1600000, userId: 'u3'),
                _attItem(wageStatus: 'pending', finalWage: 0, userId: 'u4'),
              ],
          limitReached: attendanceLimitReached,
        );
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
// ══════════════════════════════════════════════════════════
  // [R7-P1-5 후속] 미이체 건수의 owner — 원장 하나
  //   집계 문서(projection)는 트리거가 유지하므로 지연·누락될 수 있다.
  //   같은 계약을 두 owner 가 계산하면 화면이 낡은 값을 확정 사실로 말한다.
  // ══════════════════════════════════════════════════════════

  testWidgets('PNT-1 복귀 갱신이 낡은 집계 문서로 미이체를 덮지 않는다',
      (tester) async {
    final calls = <String, int>{};
    // 원장: 확정 2건(= 이체 취소 직후) / 집계 문서: 아직 1건만 반영(트리거 지연)
    await _pump(tester,
        reads: _reads(
          calls: calls,
          summaries: [
            _summaryItem(
                totalPayout: 48000,
                confirmedCount: 2,
                workerCount: 1,
                notTransferredCount: 1),
          ],
          attendances: [
            _attItem(wageStatus: 'confirmed', finalWage: 24000),
            _attItem(wageStatus: 'confirmed', finalWage: 24000, id: 'r2'),
          ],
        ));

    // 개요는 원장 기준이다.
    expect(find.textContaining('미이체 2'), findsOneWidget);

    // 월 상세 진입
    await tester.tap(find.textContaining('미이체 2'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('2건'), findsWidgets, reason: '미이체 2건');

    // 지급 현황으로 갔다가 돌아온다 → 복귀 시 _refreshSummary 가 돈다.
    //   (권한 gate 가 스스로 닫는 경로라 pop 을 따로 누르지 않는다 —
    //    중요한 것은 **복귀 갱신이 실제로 돌았다는 것**이고 호출 수로 증명한다.)
    final ledgerBefore = calls['ledger'] ?? 0;
    final summariesBefore = calls['summaries'] ?? 0;
    await tester.tap(find.byIcon(Icons.receipt_long_outlined), warnIfMissed: false);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    tester.takeException(); // 목적지의 자체 조회 실패는 이 테스트의 대상이 아니다

    expect(calls['summaries']! > summariesBefore, isTrue,
        reason: '복귀 갱신이 집계 문서를 다시 읽었다');
    expect(calls['ledger']! > ledgerBefore, isTrue,
        reason: '복귀 갱신이 **원장도** 다시 읽는다 — 건수의 owner 이기 때문이다');

    // 복귀 후에도 원장 값이다 — 집계 문서의 1 로 되돌아가지 않는다.
    expect(find.text('1건'), findsNothing,
        reason: '낡은 집계 문서 값(미이체 1)이 확정 사실로 앉으면 안 된다');
    expect(find.text('2건'), findsWidgets);
    expect(find.text('확인 못함'), findsNothing, reason: '원장을 받았으므로 모름이 아니다');
  });

  testWidgets('PNT-2 네 상태·동일인 복수 근무 — 파생이 한 owner 안에서 정확하다',
      (tester) async {
    // 같은 사람, 같은 달: 확정 1 · 이체완료 1 · 미확정 1 · 노쇼 0원 1(제외)
    // 집계 문서의 확정 건수는 낡아 있다(5) — 파생에 섞이면 이체 완료가 4가 된다.
    await _pump(tester,
        reads: _reads(
          summaries: [
            _summaryItem(
                totalPayout: 48000,
                confirmedCount: 5,
                workerCount: 1,
                notTransferredCount: 3),
          ],
          attendances: [
            _attItem(wageStatus: 'confirmed', finalWage: 24000),
            _attItem(wageStatus: 'transferred', finalWage: 24000, id: 'r2'),
            _attItem(wageStatus: 'calculated', finalWage: 0, id: 'r3'),
            _attItem(
                wageStatus: 'confirmed',
                finalWage: 0,
                status: 'NO_SHOW',
                id: 'r4'),
          ],
        ));

    expect(find.textContaining('미이체 1'), findsOneWidget);

    await tester.tap(find.textContaining('미이체 1'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 이체 완료 = 확정(원장 2) - 미이체(원장 1) = 1. 낡은 5 를 섞으면 4 가 된다.
    final transferRow = find.ancestor(
      of: find.text('이체 완료'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: transferRow.first, matching: find.text('1건')),
      findsOneWidget,
    );
    expect(find.text('4건'), findsNothing, reason: '낡은 확정 건수가 파생에 섞였다');
  });

  testWidgets('PNT-3 상한에 걸린 응답은 작은 수를 사실처럼 보여주지 않는다',
      (tester) async {
    await _pump(tester,
        reads: _reads(
          attendances: [
            _attItem(wageStatus: 'confirmed', finalWage: 1600000),
          ],
          attendanceLimitReached: true,
        ));

    expect(tester.takeException(), isNull);
    expect(find.text('미이체 확인 못함'), findsOneWidget);
    expect(find.textContaining('미이체 1'), findsNothing);
  });

  testWidgets('PNT-4 집계 문서도 없고 원장도 못 읽은 달은 데이터 없음이 아니다',
      (tester) async {
    await _pump(tester,
        reads: _reads(
          summaries: const [],
          attendanceError: StateError('attendance cf down'),
        ));

    expect(tester.takeException(), isNull);
    // 근무가 없었다고 말하지 않는다.
    expect(find.text('데이터 없음'), findsNothing);
    expect(find.text('확인 못함'), findsWidgets);
  });
}
