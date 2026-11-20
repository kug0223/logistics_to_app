import 'support/visible_text.dart';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_month_detail_screen.dart';
import 'package:ALfit/screens/business_admin/admin_stats_screen.dart';
import 'package:ALfit/services/admin_stats_service.dart';

/// [R7-P1-7 후속 P17-S] 통계 **실제 콘텐츠**를 production widget 으로 그린다.
///
///   이전 보고에서 렌더가 막혔던 이유는 화면의 lifecycle 이 아니라
///   `AdminStatsService.getBusinessOptions` 안의 `Future.timeout(15s)` 였다 —
///   가짜 Firebase 에서 Firestore future 가 끝나지 않으면 그 타이머가 남는다.
///   production 에서는 조회가 끝나거나 15초에 타임아웃되며 타이머가 풀리고,
///   화면은 `mounted` 와 `_statsRequestId` 로 늦은 응답을 이미 버린다.
///   그래서 **timeout 을 줄이거나 로딩을 강제 완료하지 않고** reader 만 주입한다.
///   파싱·파생·문구·필터는 전부 화면의 기존 경로를 그대로 지난다.

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

class _AdminProvider extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'admin1',
        username: 'admin1',
        name: '김관리',
        email: 'a@alfit.local',
        role: UserRole.BUSINESS_ADMIN,
        managedBusinessIds: const ['biz1', 'biz2'],
      );
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
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

/// [ADMIN-STATS-CLOSEOUT] 같은 SubAdmin 이 사업장마다 다른 급여 권한(바꿀 수 있음).
class _SubProvider extends UserProvider {
  _SubProvider(this.perms);
  final Map<String, PermissionCheck> perms;
  @override
  UserModel? get currentUser => UserModel(uid: 'sub1', username: 'sub1', name: '박부관리', email: 's@alfit.local', role: UserRole.USER,
      subAdminBusinessIds: perms.keys.toList());
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSubAdmin => true;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      perms[businessId] ?? PermissionCheck.denied;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
}

const _longName = '서울특별시 강남구 제1물류센터 야간운영팀 상시근무지';

/// 현행 schema 그대로 — 단위는 원(금액) · 건(근무) · 명(고유 인원).
AnnualStatsData _annual({
  int totalWage = 128400000,
  int totalWorkCount = 1472,
  int totalWorkerCount = 63,
  double attendanceRate = 97.4,
  double noShowRate = 1.2,
  AttendanceStatsState attendance = AttendanceStatsState.available,
  List<MonthlyTrend>? trends,
}) =>
    AnnualStatsData(
      year: 2026,
      totalWage: totalWage,
      totalWorkCount: totalWorkCount,
      totalWorkerCount: totalWorkerCount,
      prevYearTotalWage: 98000000,
      prevYearTotalWorkCount: 1200,
      attendanceRecordCount: totalWorkCount == 0 ? 0 : 1500,
      attendanceRate: attendanceRate,
      prevYearAttendanceRate: 95.0,
      rehireRate: 72.5,
      avgRating: 4.6,
      noShowCount: 18,
      noShowRate: noShowRate,
      prevYearNoShowRate: 2.0,
      wageByWorkType: const {'홀서빙': 64200000, '주방 보조': 64200000},
      monthlyTrends: trends ??
          const [
            MonthlyTrend(
                year: 2026, month: 9, workCount: 140, totalWage: 12840000,
                workerCount: 21),
          ],
      exceptions: const [],
      exceptionMonth: 9,
      attendanceStatsState: attendance,
      prevAttendanceStatsState: attendance,
    );

MonthDetailData _detail({
  int totalWage = 12840000,
  List<WorkerMonthSummary>? workers,
}) =>
    MonthDetailData(
      year: 2026,
      month: 9,
      presentCount: 130,
      lateCount: 7,
      absentCount: 3,
      totalWage: totalWage,
      workers: workers ?? const [],
      avgRating: 4.6,
      rehireCount: 12,
      noRehireCount: 3,
      posTagFreq: const {},
      impTagFreq: const {},
      rawAttendance: const [],
      userInfoMap: const {},
    );

/// 주입 reader — 실제 클래스를 상속해 **읽기 세 메서드만** 대체한다.
class _FakeStats extends AdminStatsService {
  _FakeStats({
    this.annual,
    this.detail,
    this.annualError,
    this.detailError,
    this.options = const [
      BusinessOption(id: 'biz1', name: _longName),
      BusinessOption(id: 'biz2', name: '평택 센터'),
    ],
    this.annualByCall,
  });

  final AnnualStatsData? annual;
  final MonthDetailData? detail;
  final Object? annualError;
  final Object? detailError;
  final List<BusinessOption> options;

  /// 호출 n번째 연간 응답 — 늦은 응답 역전 재현용.
  final List<Future<AnnualStatsData>>? annualByCall;

  int annualCalls = 0;
  int detailCalls = 0;
  final List<String?> filtersSeen = [];
  final List<int> yearsSeen = [];

  @override
  Future<List<BusinessOption>> getBusinessOptions(List<String> ids) async =>
      options;

  @override
  Future<AnnualStatsData> getAnnualStats({
    required List<String> businessIds,
    String? filterBusinessId,
    required int year,
  }) {
    final i = annualCalls++;
    filtersSeen.add(filterBusinessId);
    yearsSeen.add(year);
    if (annualByCall != null && i < annualByCall!.length) {
      return annualByCall![i];
    }
    if (annualError != null) {
      return Future<AnnualStatsData>.error(annualError!);
    }
    return Future<AnnualStatsData>.value(annual ?? _annual());
  }

  @override
  Future<MonthDetailData> getMonthDetail({
    required List<String> businessIds,
    String? filterBusinessId,
    required int year,
    required int month,
  }) {
    detailCalls++;
    if (detailError != null) {
      return Future<MonthDetailData>.error(detailError!);
    }
    return Future<MonthDetailData>.value(detail ?? _detail());
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(390, 900),
  double textScale = 1.0,
  UserProvider? provider,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => provider ?? _AdminProvider()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        // 같은 타입의 화면을 연달아 pump 하면 State 가 재사용돼 시나리오가 섞인다.
        home: KeyedSubtree(key: UniqueKey(), child: home),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [STATS-TO-ATTENDANCE.27] 여러 낱말 라벨은 낱말 안에서 줄이 바뀌지 않게 WORD JOINER 가 들어간다 —
///   보이는 글자로 찾는다.
Finder _label(String s) => find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').replaceAll('\u2060', '') == s);

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ══════════════════════════════════════════════════════════
  // 1) 큰 수 · 긴 라벨 · 좁은 폭
  // ══════════════════════════════════════════════════════════

  testWidgets('ASC-1 큰 수와 단위가 320dp·배율 1.3 에서 잘리지 않는다',
      (tester) async {
    await _pump(
        tester,
        AdminStatsScreen(
            businessIds: const ['biz1', 'biz2'], service: _FakeStats()),
        size: const Size(320, 800),
        textScale: 1.3);

    expect(tester.takeException(), isNull);
    // 금액은 압축 표기(1.3억), 근무는 건 — 단위가 서로 바뀌지 않는다.
    expect(findVisibleText('총 인건비'), findsWidgets);
    expect(findVisibleText('1.3억'), findsOneWidget);
    expect(_label('급여 확정 근무'), findsOneWidget);
    expect(findVisibleText('1472건'), findsOneWidget);
    expect(_label('출근율'), findsOneWidget);
    expect(findVisibleText('97.4%'), findsOneWidget);
    // 집계 범위(연·사업장)가 화면에 있다.
    expect(findVisibleText('2026년 전체'), findsOneWidget);
    expect(findVisibleText('전체 사업장'), findsWidgets);
  });

  testWidgets('ASC-2 배율 2.0 에서도 예외 없이 스크롤로 닿는다', (tester) async {
    await _pump(
        tester,
        AdminStatsScreen(
            businessIds: const ['biz1', 'biz2'], service: _FakeStats()),
        size: const Size(360, 800),
        textScale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  // ══════════════════════════════════════════════════════════
  // 2) 정상 0 ≠ 조회 오류
  // ══════════════════════════════════════════════════════════

  testWidgets('ASC-3 정상 0 · 부분 · 전체 실패가 서로 다른 말을 한다',
      (tester) async {
    // 정상 0 — 실제로 0원·0건인 해
    await _pump(
        tester,
        AdminStatsScreen(
          businessIds: const ['biz1'],
          service: _FakeStats(
              annual: _annual(
                  totalWage: 0, totalWorkCount: 0, totalWorkerCount: 0)),
        ));
    expect(tester.takeException(), isNull);
    expect(findVisibleText('0건'), findsWidgets);
    expect(findVisibleText('확인 불가'), findsNothing);

    // 전체 조회 실패 — 수치를 아예 주장하지 않는다(0건·0원도 아니다).
    await _pump(
        tester,
        AdminStatsScreen(
          businessIds: const ['biz1'],
          service: _FakeStats(annualError: StateError('stats cf down')),
        ));
    expect(tester.takeException(), isNull);
    expect(findVisibleText('통계를 불러오지 못했습니다'), findsOneWidget);
    expect(findVisibleTextContaining('데이터가 없습니다'), findsNothing,
        reason: '실패를 "없음"으로 바꾸지 않는다');
    expect(findVisibleText('0건'), findsNothing);
    expect(_label('급여 확정 근무'), findsNothing);
  });

  // ══════════════════════════════════════════════════════════
  // 3) 부분 결과 · 상한
  // ══════════════════════════════════════════════════════════

  testWidgets('ASC-4 출근 데이터가 부분·상한이면 그 수치를 주장하지 않는다',
      (tester) async {
    await _pump(
        tester,
        AdminStatsScreen(
          businessIds: const ['biz1', 'biz2'],
          // AttendanceStatsState.unavailable = 부분 결과 또는 limitReached
          service: _FakeStats(
              annual: _annual(attendance: AttendanceStatsState.unavailable)),
        ));

    expect(tester.takeException(), isNull);
    // 금액·건수·출근율을 완전한 결과처럼 보여주지 않는다.
    expect(findVisibleText('확인 불가'), findsWidgets);
    expect(findVisibleText('1472건'), findsNothing);
    expect(findVisibleText('1.3억'), findsNothing);
  });

  // ══════════════════════════════════════════════════════════
  // 4) 월·사업장 전환 중 늦은 응답
  // ══════════════════════════════════════════════════════════

  testWidgets('ASC-5 사업장 전환 중 늦게 온 이전 응답이 현재 선택을 덮지 않는다',
      (tester) async {
    final slowFirst = Completer<AnnualStatsData>();
    final fake = _FakeStats(annualByCall: [
      slowFirst.future, // 첫 조회(전체 사업장) — 늦게 온다
      Future<AnnualStatsData>.value(_annual(totalWorkCount: 7)), // 평택 센터 — 먼저
    ]);
    await _pump(
        tester,
        AdminStatsScreen(businessIds: const ['biz1', 'biz2'], service: fake),
        size: const Size(390, 1000));

    // 조회가 떠 있는 동안 사업장을 바꾼다(연도 버튼은 _isFetching 중 비활성이다).
    await tester.tap(findVisibleText('전체 사업장').first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(findVisibleText('평택 센터').last);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(fake.filtersSeen.last, 'biz2');
    expect(findVisibleText('7건'), findsOneWidget, reason: '현재 선택(평택 센터)의 응답');

    // 이제 첫 조회(전체 사업장)가 옛 값으로 도착한다.
    slowFirst.complete(_annual(totalWorkCount: 9999));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(findVisibleText('7건'), findsOneWidget);
    expect(findVisibleText('9999건'), findsNothing,
        reason: '낡은 응답이 현재 맥락을 덮었다');
  });

  testWidgets('ASC-6 사업장 선택이 조회 범위와 화면 맥락에 반영된다', (tester) async {
    final fake = _FakeStats();
    await _pump(
        tester,
        AdminStatsScreen(businessIds: const ['biz1', 'biz2'], service: fake),
        size: const Size(390, 1000));

    expect(fake.filtersSeen.last, isNull, reason: '처음은 전체 사업장');

    await tester.tap(findVisibleText('전체 사업장').first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(findVisibleText('평택 센터').last);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(fake.filtersSeen.last, 'biz2', reason: '선택이 조회 범위로 간다');
    // 머리말이 현재 맥락을 말한다.
    expect(findVisibleText('평택 센터'), findsWidgets);
    expect(findVisibleText('2026년 전체'), findsOneWidget);
  });

  testWidgets('ASC-7 월 상세가 실제 콘텐츠를 단위대로 그린다', (tester) async {
    await _pump(
        tester,
        AdminMonthDetailScreen(
          businessIds: const ['biz1', 'biz2'],
          filterBusinessId: 'biz2',
          year: 2026,
          month: 9,
          businesses: const [
            BusinessOption(id: 'biz1', name: _longName),
            BusinessOption(id: 'biz2', name: '평택 센터'),
          ],
          service: _FakeStats(
            detail: _detail(workers: const [
              WorkerMonthSummary(
                userId: 'u1',
                userName: '김근로',
                totalDays: 12,
                presentDays: 12,
                lateDays: 2,
                absentDays: 0,
                totalWage: 1284000,
                records: [],
              ),
            ]),
          ),
        ),
        size: const Size(320, 800),
        textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(_label('김근로'), findsOneWidget);
    // 근무일은 고유 날짜 수 — 건 단위 지표에는 '일' 을 붙이지 않는다.
    // [STATS-TO-ATTENDANCE.27-T1] 320dp·1.3 은 표 대신 쌓은 행 — 근무일이 제 이름과 함께 나온다.
    expect(findVisibleText('근무일 12일'), findsOneWidget);
    expect(findVisibleTextContaining('지각 2'), findsOneWidget);
    expect(findVisibleText('지각 2일'), findsNothing);
  });

  // [ADMIN-MONTHLY-1] 퇴근 미확인은 결근 칩이 아니라 따로 · 동명이인은 인력번호로 갈린다
  testWidgets('ASC-8 퇴근 미확인 칩·배지와 동명이인 인력번호', (tester) async {
    await _pump(
        tester,
        AdminMonthDetailScreen(
          businessIds: const ['biz1'],
          filterBusinessId: 'biz1',
          year: 2026,
          month: 10,
          businesses: const [BusinessOption(id: 'biz1', name: '평택 센터')],
          service: _FakeStats(
            detail: MonthDetailData(
              year: 2026, month: 10, presentCount: 4, lateCount: 1, absentCount: 1, missedCheckoutCount: 1,
              totalWage: 126420, avgRating: 0, rehireCount: 0, noRehireCount: 0, posTagFreq: const {}, impTagFreq: const {},
              rawAttendance: const [], userInfoMap: const {},
              workers: const [
                WorkerMonthSummary(userId: 'a', userName: '합성 김동명', personNo: 'P-002', totalDays: 1, presentDays: 2, lateDays: 0, absentDays: 0, totalWage: 41280, records: []),
                WorkerMonthSummary(userId: 'b', userName: '합성 김동명', personNo: 'P-003', totalDays: 1, presentDays: 1, lateDays: 0, absentDays: 0, totalWage: 0, records: []),
                WorkerMonthSummary(userId: 'c', userName: '합성 정미퇴근', personNo: 'P-005', totalDays: 1, presentDays: 0, lateDays: 0, absentDays: 0, missedCheckoutDays: 1, totalWage: 0, records: []),
              ],
            ),
          ),
        ),
        size: const Size(320, 900),
        textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(findVisibleText('퇴근 미확인 14%'), findsOneWidget);
    expect(findVisibleText('결근 14%'), findsOneWidget, reason: '노쇼 1건만 결근');
    // [STATS-TO-ATTENDANCE.27] 배지는 누를 수 있다 — '›' 가 붙는다.
    expect(findVisibleText('퇴근미확인 1 ›'), findsOneWidget);
    expect(findVisibleText('결근 1 ›'), findsNothing, reason: '미퇴근 근로자 행에 결근 배지가 없다');
    expect(findVisibleText('P-002'), findsOneWidget);
    expect(findVisibleText('P-003'), findsOneWidget);
    expect(_label('합성 김동명'), findsNWidgets(2));
  });

  test('ASC-9 설정 → 통계 입구는 고른 사업장의 급여 권한을 다시 본다', () {
    final src = File('lib/screens/common/settings_screen.dart').readAsStringSync();
    final i = src.indexOf("title: '통계',");
    final seg = src.substring(i, src.indexOf('AdminStatsScreen(businessIds: [biz.id])', i));
    expect(seg, contains('userProvider.checkForBusiness('));
    expect(seg, contains('biz.id, (p) => p.canManageWage)'));
  });

  // ── [ADMIN-STATS-CLOSEOUT] 조회 대상 사업장별 급여 권한 — 실제 화면 행동 ──
  testWidgets('ASC-10 급여 권한 없는 사업장은 숫자를 부르지도 그리지도 않는다 · 있는 사업장은 정상', (tester) async {
    final p = _SubProvider({'bizA': PermissionCheck.allowed, 'bizB': PermissionCheck.denied});
    final fa = _FakeStats(annual: _annual(totalWorkCount: 7));
    await _pump(tester, AdminStatsScreen(businessIds: const ['bizA'], service: fa), provider: p);
    expect(findVisibleText('7건'), findsOneWidget);
    expect(fa.annualCalls, 1);
    final fb = _FakeStats(annual: _annual(totalWorkCount: 7));
    await _pump(tester, AdminStatsScreen(businessIds: const ['bizB'], service: fb), provider: p);
    expect(fb.annualCalls, 0, reason: '권한 없는 대상은 조회하지 않는다');
    expect(findVisibleText('이 사업장의 급여 관리 권한이 없어요'), findsOneWidget);
    expect(findVisibleText('0원'), findsNothing);
    expect(findVisibleText('7건'), findsNothing);
  });

  testWidgets('ASC-11 권한 확인 실패·모름은 허용이 아니다', (tester) async {
    for (final c in [PermissionCheck.unknown, PermissionCheck.error]) {
      final f = _FakeStats();
      await _pump(tester, AdminStatsScreen(businessIds: const ['bizA'], service: f), provider: _SubProvider({'bizA': c}));
      expect(f.annualCalls, 0, reason: '$c');
      expect(findVisibleText('권한을 확인하지 못했어요'), findsOneWidget);
    }
  });

  testWidgets('ASC-12 A 조회 중 B(무권한)로 전환 → 늦게 온 A 응답이 B 화면을 덮지 않는다 → A 복귀 시 회복', (tester) async {
    final slowA = Completer<AnnualStatsData>();
    final f = _FakeStats(options: const [BusinessOption(id: 'biz1', name: '강남 센터'), BusinessOption(id: 'biz2', name: '평택 센터')],
        annualByCall: [slowA.future, Future<AnnualStatsData>.value(_annual(totalWorkCount: 11))]);
    final p = _SubProvider({'biz1': PermissionCheck.allowed, 'biz2': PermissionCheck.denied});
    await _pump(tester, AdminStatsScreen(businessIds: const ['biz1', 'biz2'], service: f), provider: p, size: const Size(390, 1000));
    // 전체 범위에 무권한 사업장이 섞여 있으면 막힌다 — 강남(허용)으로 좁힌다
    expect(findVisibleText('이 사업장의 급여 관리 권한이 없어요'), findsOneWidget);
    await tester.tap(findVisibleText('전체 사업장').first);
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    await tester.tap(findVisibleText('강남 센터').last);
    for (var i = 0; i < 5; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    expect(f.filtersSeen.last, 'biz1');
    // A 응답이 오기 전에 B 로 바꾼다
    await tester.tap(findVisibleText('강남 센터').first);
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    await tester.tap(findVisibleText('평택 센터').last);
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    expect(findVisibleText('이 사업장의 급여 관리 권한이 없어요'), findsOneWidget);
    slowA.complete(_annual(totalWorkCount: 9999));
    for (var i = 0; i < 12; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    expect(findVisibleText('9999건'), findsNothing, reason: '늦게 온 A 응답이 무권한 B 화면에 나타났다');
    expect(findVisibleText('이 사업장의 급여 관리 권한이 없어요'), findsOneWidget);
    // A 로 복귀 → 정상 조회
    await tester.tap(findVisibleText('평택 센터').first);
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    await tester.tap(findVisibleText('강남 센터').last);
    for (var i = 0; i < 15; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    expect(findVisibleText('11건'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ASC-13 월 상세가 열린 사이 권한 취소 → 새로고침은 숫자를 지우고 Excel 을 막는다 → 권한 복구 시 회복', (tester) async {
    final perms = {'biz1': PermissionCheck.allowed};
    final f = _FakeStats(detail: _detail(totalWage: 126420));
    await _pump(tester, AdminMonthDetailScreen(businessIds: const ['biz1'], filterBusinessId: 'biz1', year: 2026, month: 10,
        businesses: const [BusinessOption(id: 'biz1', name: '강남 센터')], service: f), provider: _SubProvider(perms));
    expect(findVisibleText('126,420원'), findsOneWidget);
    IconButton exportBtn() => tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.download_outlined).first);
    expect(exportBtn().onPressed, isNotNull);
    perms['biz1'] = PermissionCheck.denied;
    await tester.tap(find.byIcon(Icons.refresh_rounded).first);
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    expect(findVisibleText('126,420원'), findsNothing);
    expect(findVisibleText('이 사업장의 급여 관리 권한이 없어요'), findsOneWidget);
    expect(exportBtn().onPressed, isNull, reason: '권한 없는 대상의 Excel');
    final calls = f.detailCalls;
    perms['biz1'] = PermissionCheck.allowed;
    await tester.tap(find.byIcon(Icons.refresh_rounded).first);
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 100)); }
    expect(f.detailCalls, calls + 1);
    expect(findVisibleText('126,420원'), findsOneWidget);
    expect(exportBtn().onPressed, isNotNull);
  });

  testWidgets('ASC-14 0원·0%: 확정 0원은 확정, 분모 있는 0%는 0%, 근태 0건만 "-"', (tester) async {
    await _pump(tester, AdminStatsScreen(businessIds: const ['biz1'], service: _FakeStats(annual: AnnualStatsData(
        year: 2026, totalWage: 0, totalWorkCount: 1, totalWorkerCount: 1, prevYearTotalWage: 0, prevYearTotalWorkCount: 0,
        attendanceRecordCount: 3, attendanceRate: 0, prevYearAttendanceRate: 0, rehireRate: 0, avgRating: 0, noShowCount: 0, noShowRate: 0,
        prevYearNoShowRate: 0, wageByWorkType: const {}, monthlyTrends: List.generate(12, (i) => MonthlyTrend(year: 2026, month: i + 1, workCount: i == 9 ? 3 : 0, totalWage: 0, workerCount: i == 9 ? 1 : 0)),
        exceptions: const [], exceptionMonth: 10))));
    expect(findVisibleText('0원'), findsOneWidget, reason: '확정 근무 1건의 합 0원');
    expect(findVisibleText('0.0%'), findsNWidgets(2), reason: '출근율·노쇼율 분모 3');
    expect(_label('급여 확정 근무'), findsOneWidget);
    expect(findVisibleText('전체 근태 (건)'), findsOneWidget);
    await _pump(tester, AdminMonthDetailScreen(businessIds: const ['biz1'], filterBusinessId: 'biz1', year: 2026, month: 10,
        businesses: const [BusinessOption(id: 'biz1', name: '강남 센터')], service: _FakeStats(detail: MonthDetailData(
          year: 2026, month: 10, presentCount: 0, lateCount: 0, absentCount: 1, totalWage: 0, settledCount: 1, avgRating: 0, rehireCount: 0, noRehireCount: 0,
          posTagFreq: const {}, impTagFreq: const {}, rawAttendance: const [], userInfoMap: const {},
          workers: const [
            WorkerMonthSummary(userId: 'a', userName: '합성 최노쇼', personNo: 'P-004', totalDays: 1, presentDays: 0, lateDays: 0, absentDays: 1, totalWage: 0, records: [], hasSettledWage: true),
            WorkerMonthSummary(userId: 'b', userName: '합성 대기', personNo: 'P-008', totalDays: 1, presentDays: 1, lateDays: 0, absentDays: 0, totalWage: 0, records: []),
          ]))));
    expect(findVisibleText('0원'), findsOneWidget, reason: '월 총 인건비 — 확정 1건 0원');
    expect(findVisibleText('확정 · 0원'), findsOneWidget);
    expect(findVisibleText('미확정'), findsOneWidget, reason: '확정 근무가 없는 사람만');
  });
}
