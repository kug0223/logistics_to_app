import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
// Firebase 대역(_FakeApp · _FakeCore)용 — firebase_core 가 전이로 가져오는 interface 패키지다(pubspec 직접 의존 아님).
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_month_detail_screen.dart';
import 'package:ALfit/screens/business_admin/admin_stats_screen.dart';
import 'package:ALfit/screens/business_admin/stats_attendance_list_screen.dart';
import 'package:ALfit/services/admin_stats_service.dart';
import 'support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

/// [STATS-TO-ATTENDANCE.27] 통계 숫자 → 그 숫자를 만든 **바로 그 근태 문서** → 기존 근태 화면.
///
///   판정식을 복제하지 않는다 — 집계(`getMonthDetail` 의 합계·직원별)와 목록(`matches`)이
///   같은 `AdminStatsService.bucketOf` 를 쓰는지, 그리고 화면이 실제로 그 원본을 넘기는지 본다.

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

class _Provider extends UserProvider {
  _Provider({this.workers = PermissionCheck.allowed});
  final PermissionCheck workers;
  @override
  UserModel? get currentUser => UserModel(uid: 'admin1', username: 'admin1', name: '김관리', email: 'a@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const ['biz1']);
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) {
    // 통계는 canManageWage, 근태 화면은 canManageWorkers — 서로 다른 판정이다.
    final asksWage = check(const MemberPermissions(canManageWage: true));
    final asksWorkers = check(const MemberPermissions(canManageWorkers: true));
    if (asksWorkers && !asksWage) return workers;
    return PermissionCheck.allowed;
  }
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
}

DateTime _kst(int d) => DateTime.utc(2026, 10, d).subtract(const Duration(hours: 9));

AttendanceModel _att(String id, String uid, int day, String status,
    {String app = '', String wage = 'pending', DateTime? inAt}) =>
    AttendanceModel(
      id: id,
      applicationId: app.isEmpty ? 'app_$id' : app,
      userId: uid,
      businessId: 'biz1',
      businessName: '평택 센터',
      workDate: _kst(day),
      workType: '분류',
      status: status,
      wageStatus: wage,
      checkInAt: inAt,
      createdAt: DateTime.utc(2026, 10, 1),
    );

final _rows = <AttendanceModel>[
  _att('m1', 'twinA', 6, AttendanceModel.statusMissedCheckout, inAt: _kst(6).add(const Duration(hours: 9))),
  _att('m2', 'twinB', 6, AttendanceModel.statusMissedCheckout, inAt: _kst(6).add(const Duration(hours: 9))),
  // 같은 사람·같은 날 두 근무 — 오전만 퇴근 미확인
  _att('am', 'two', 7, AttendanceModel.statusMissedCheckout, app: 'app_two_am', inAt: _kst(7).add(const Duration(hours: 9))),
  _att('pm', 'two', 7, AttendanceModel.statusPresent, app: 'app_two_pm', inAt: _kst(7).add(const Duration(hours: 13))),
  _att('u1', 'unk', 8, AttendanceModel.statusUnconfirmed),
  _att('a1', 'abs', 5, AttendanceModel.statusAbsent),
  _att('n1', 'ns', 5, AttendanceModel.statusNoShow),
  _att('p1', 'paid', 9, AttendanceModel.statusLate, wage: AttendanceModel.wageConfirmed),
];

const _info = {
  'twinA': UserInfo(name: '합성 동명이', personNo: 'P-201'),
  'twinB': UserInfo(name: '합성 동명이', personNo: 'P-202'),
  'two': UserInfo(name: '합성 두근무', personNo: 'P-203'),
  'unk': UserInfo(name: '합성 상태없음', personNo: 'P-204'),
  'abs': UserInfo(name: '합성 결근', personNo: 'P-205'),
  'ns': UserInfo(name: '합성 노쇼', personNo: 'P-206'),
  'paid': UserInfo(name: '합성 확정지각', personNo: 'P-207'),
};

/// 실제 서비스의 월 집계 코드(`buildMonthDetail`)로 만든 데이터 — 화면 숫자와 목록이 같은 분류를 쓰는지 본다.
MonthDetailData _month(List<AttendanceModel> rows) =>
    AdminStatsService.buildMonthDetail(year: 2026, month: 10, attendance: rows, infoMap: _info);

class _FakeStats extends AdminStatsService {
  _FakeStats(this.rows);
  List<AttendanceModel> rows;
  bool failSnapshot = false;
  int monthCalls = 0;
  int snapshotCalls = 0;

  @override
  Future<List<BusinessOption>> getBusinessOptions(List<String> ids) async =>
      const [BusinessOption(id: 'biz1', name: '평택 센터')];

  int annualCalls = 0;
  bool annualUnavailable = false;
  final List<int?> snapshotMonths = [];

  @override
  Future<AnnualStatsData> getAnnualStats({required List<String> businessIds, String? filterBusinessId,
      required int year}) async {
    annualCalls++;
    final unconfirmed = rows.where((r) => AdminStatsService.bucketOf(r) == StatsAttendanceBucket.unconfirmed).length;
    return AnnualStatsData(
      year: year, totalWage: 80000, totalWorkCount: 1, totalWorkerCount: 7, prevYearTotalWage: 0,
      prevYearTotalWorkCount: 0, attendanceRecordCount: rows.length, unconfirmedAttendanceCount: unconfirmed,
      attendanceRate: 50, prevYearAttendanceRate: 0, rehireRate: 0, avgRating: 0, noShowCount: 1,
      noShowRate: 10, prevYearNoShowRate: 0, wageByWorkType: const {},
      monthlyTrends: const [MonthlyTrend(year: 2026, month: 10, workCount: 8, totalWage: 80000, workerCount: 7)],
      exceptions: const [
        WorkerException(userId: 'abs', userName: '합성 결근', businessName: '평택 센터', lateCount: 0, absentCount: 1),
      ],
      exceptionMonth: 10,
      attendanceStatsState: annualUnavailable ? AttendanceStatsState.unavailable : AttendanceStatsState.available,
    );
  }

  @override
  Future<MonthDetailData> getMonthDetail({required List<String> businessIds, String? filterBusinessId,
      required int year, required int month}) async {
    monthCalls++;
    return _month(rows);
  }

  @override
  Future<StatsAttendanceSnapshot?> getAttendanceSnapshot({required List<String> businessIds,
      String? filterBusinessId, required int year, int? month}) async {
    snapshotCalls++;
    snapshotMonths.add(month);
    if (failSnapshot) return null;
    return StatsAttendanceSnapshot(records: rows, userInfo: _info);
  }
}

Future<void> _pump(WidgetTester tester, Widget home,
    {UserProvider? provider, Size size = const Size(390, 900), double textScale = 1.0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => provider ?? _Provider()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      home: KeyedSubtree(key: UniqueKey(), child: home),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

AdminMonthDetailScreen _detailScreen(_FakeStats svc, List<AttendanceModel> opened, {bool changed = false}) =>
    AdminMonthDetailScreen(
      businessIds: const ['biz1'],
      filterBusinessId: null,
      year: 2026,
      month: 10,
      businesses: const [BusinessOption(id: 'biz1', name: '평택 센터')],
      service: svc,
      debugOpenAttendance: (r) async {
        opened.add(r);
        return changed;
      },
    );

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  test('SA-1 집계와 목록이 같은 분류식을 쓴다 — 결근 칸에 노쇼 포함, 상태 없음은 확인 필요', () {
    final d = _month(_rows);
    int count(StatsAttendanceBucket b) => _rows.where((r) => AdminStatsService.bucketOf(r) == b).length;
    expect(d.missedCheckoutCount, count(StatsAttendanceBucket.missedCheckout));
    expect(d.missedCheckoutCount, 3);
    expect(d.unconfirmedCount, count(StatsAttendanceBucket.unconfirmed));
    expect(d.absentCount, count(StatsAttendanceBucket.absent));
    expect(d.absentCount, 2);
    expect(d.lateCount, count(StatsAttendanceBucket.late));
    expect(d.presentCount, count(StatsAttendanceBucket.present));
    final two = d.workers.firstWhere((w) => w.userId == 'two');
    expect(two.missedCheckoutDays, 1);
    expect(two.totalDays, 1, reason: '근무일은 날짜 수 — 같은 날 두 근무는 하루');
    expect(two.records.length, 2, reason: '근무 건은 둘');
  });

  testWidgets('SA-2 월 상세 "퇴근 미확인 3건" → 그 3건만, 동명이인은 인력번호로 갈린다', (tester) async {
    final svc = _FakeStats(List.of(_rows));
    final opened = <AttendanceModel>[];
    await _pump(tester, _detailScreen(svc, opened));
    await tester.tap(find.byKey(const ValueKey('att-stat-missedCheckout')));
    await _settle(tester);
    expect(find.byType(StatsAttendanceListScreen), findsOneWidget);
    expect(find.text('퇴근 미확인 내역'), findsOneWidget);
    expect(find.textContaining('합성 동명이 · P-201'), findsOneWidget);
    expect(find.textContaining('합성 동명이 · P-202'), findsOneWidget);
    expect(find.textContaining('합성 두근무'), findsOneWidget, reason: '오후(정상) 근무는 이 목록에 없다');
    expect(find.textContaining('합성 결근'), findsNothing);
    expect(svc.snapshotCalls, 0, reason: '이미 받은 월 원본을 쓴다 — 첫 목록에서 다시 읽지 않는다');
  });

  testWidgets('SA-3 같은 사람 같은 날 두 근무 — 누른 근무의 applicationId 로 연다(첫 근무로 고르지 않음)', (tester) async {
    final svc = _FakeStats(List.of(_rows));
    final opened = <AttendanceModel>[];
    await _pump(tester, _detailScreen(svc, opened));
    // 직원 행(합성 두근무) → 그 사람의 이번 달 전체 근태 내역
    await tester.ensureVisible(find.byKey(const ValueKey('worker-row-two')));
    await tester.pump();
    // 행 가운데는 상태 배지다 — 이름 칸을 누른다(행 진입).
    await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('worker-row-two'))) + const Offset(12, 14));
    await _settle(tester);
    expect(find.text('근태 내역'), findsOneWidget);
    expect(find.textContaining('퇴근 미확인'), findsWidgets);
    final rows = find.byKey(const ValueKey('att-row-pm'));
    expect(rows, findsOneWidget);
    await tester.tap(rows);
    await _settle(tester);
    expect(opened.single.applicationId, 'app_two_pm');
    expect(opened.single.id, 'pm');
  });

  testWidgets('SA-4 직원 행 상태 배지 → 그 근로자·그 상태만', (tester) async {
    final svc = _FakeStats(List.of(_rows));
    await _pump(tester, _detailScreen(svc, []));
    await tester.ensureVisible(find.byKey(const ValueKey('worker-badge-twinB-missedCheckout')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('worker-badge-twinB-missedCheckout')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('att-row-m2')), findsOneWidget);
    expect(find.byKey(const ValueKey('att-row-m1')), findsNothing, reason: '동명이인(P-201)은 빠진다');
    expect(find.textContaining('P-201'), findsNothing);
  });

  for (final p in [PermissionCheck.denied, PermissionCheck.unknown]) {
  testWidgets('SA-5 근태 권한 $p — 통계가 보여도 근태 화면을 열지 않는다', (tester) async {
      final svc = _FakeStats(List.of(_rows));
      final opened = <AttendanceModel>[];
      await _pump(tester, _detailScreen(svc, opened), provider: _Provider(workers: p));
      await tester.tap(find.byKey(const ValueKey('att-stat-unconfirmed')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('att-row-u1')));
      await _settle(tester);
      expect(opened, isEmpty, reason: '$p');
      expect(find.byType(StatsAttendanceListScreen), findsOneWidget, reason: '목록에 머문다');
      await tester.pump(const Duration(seconds: 4));
  });
  }

  testWidgets('SA-6 정정 성공 → 목록 다시 읽기 · 빠진 근무 안내 · 뒤로 가면 월 상세가 조용히 갱신', (tester) async {
    final svc = _FakeStats(List.of(_rows));
    final opened = <AttendanceModel>[];
    await _pump(tester, _detailScreen(svc, opened, changed: true));
    expect(find.text('3건'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('att-stat-missedCheckout')));
    await _settle(tester);
    // 다른 관리자가(또는 이 정정이) 오전 근무를 정상으로 바꿨다
    svc.rows = [for (final r in _rows) r.id == 'am' ? r.copyWith(status: AttendanceModel.statusPresent) : r];
    await tester.tap(find.byKey(const ValueKey('att-row-am')));
    await _settle(tester);
    expect(svc.snapshotCalls, 1);
    expect(find.textContaining('제외된 근무 1건'), findsOneWidget);
    expect(find.byKey(const ValueKey('att-row-am')), findsNothing);
    final before = svc.monthCalls;
    await tester.pageBack();
    await _settle(tester);
    expect(svc.monthCalls, before + 1, reason: '변경이 있었을 때만 월 상세를 다시 읽는다');
    expect(find.byType(AdminMonthDetailScreen), findsOneWidget);
  });

  testWidgets('SA-6b 시스템 뒤로(기기 뒤로 키)도 같은 결과를 돌려준다 — 월 상세가 갱신된다', (tester) async {
    final svc = _FakeStats(List.of(_rows));
    await _pump(tester, _detailScreen(svc, [], changed: true));
    await tester.tap(find.byKey(const ValueKey('att-stat-missedCheckout')));
    await _settle(tester);
    svc.rows = [for (final r in _rows) r.id == 'am' ? r.copyWith(status: AttendanceModel.statusPresent) : r];
    await tester.tap(find.byKey(const ValueKey('att-row-am')));
    await _settle(tester);
    final before = svc.monthCalls;
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(StatsAttendanceListScreen), findsNothing);
    expect(svc.monthCalls, before + 1);
    expect(find.text('2건'), findsWidgets, reason: '퇴근 미확인 3 → 2');
  });

  testWidgets('SA-7 취소(변경 없음) → 다시 읽지 않는다', (tester) async {
    final svc = _FakeStats(List.of(_rows));
    await _pump(tester, _detailScreen(svc, [], changed: false));
    await tester.tap(find.byKey(const ValueKey('att-stat-missedCheckout')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('att-row-m1')));
    await _settle(tester);
    expect(svc.snapshotCalls, 0);
    final before = svc.monthCalls;
    await tester.pageBack();
    await _settle(tester);
    expect(svc.monthCalls, before);
  });

  testWidgets('SA-8 정정 뒤 다시 읽기 실패 → 이전 목록을 지우지 않고 낡았다고 말한다', (tester) async {
    final svc = _FakeStats(List.of(_rows));
    await _pump(tester, _detailScreen(svc, [], changed: true));
    await tester.tap(find.byKey(const ValueKey('att-stat-missedCheckout')));
    await _settle(tester);
    svc.failSnapshot = true;
    await tester.tap(find.byKey(const ValueKey('att-row-m1')));
    await _settle(tester);
    expect(find.textContaining('정정 전 기준'), findsOneWidget);
    expect(find.byKey(const ValueKey('att-row-m1')), findsOneWidget);
    expect(find.textContaining('0건'), findsNothing);
  });

  testWidgets('SA-9 결근 내역은 결과 목록 — 정정 필수로 말하지 않는다', (tester) async {
    final svc = _FakeStats(List.of(_rows));
    await _pump(tester, _detailScreen(svc, []));
    await tester.tap(find.byKey(const ValueKey('att-stat-absent')));
    await _settle(tester);
    expect(find.text('결근 내역'), findsOneWidget);
    expect(find.textContaining('근태 보기'), findsNWidgets(2));
    expect(find.textContaining('근태 확인 ›'), findsNothing);
    expect(find.text('노쇼'), findsOneWidget);
    expect(find.text('결근'), findsOneWidget);
  });

  testWidgets('SA-10 급여 확정된 근무는 목록에서 확정 표시 — 정정 차단은 기존 근태 화면 몫', (tester) async {
    final svc = _FakeStats(List.of(_rows));
    await _pump(tester, _detailScreen(svc, []));
    await tester.tap(find.byKey(const ValueKey('att-stat-late')));
    await _settle(tester);
    expect(findVisibleTextContaining('급여 확정'), findsOneWidget);
  });

  testWidgets('SA-11 연간 "미확인 N건" → 그해(월 없음) 확인 필요 근태만 · 정정 뒤 연간 조용히 갱신', (tester) async {
    final svc = _FakeStats(List.of(_rows));
    await _pump(tester, AdminStatsScreen(businessIds: const ['biz1'], service: svc,
        debugOpenAttendance: (r) async => true));
    expect(find.textContaining('미확인 1건'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('annual-unconfirmed-att')));
    await _settle(tester);
    expect(find.text('근태 확인 필요 내역'), findsOneWidget);
    expect(svc.snapshotMonths.single, isNull, reason: '연간 숫자이므로 그해 전체를 읽는다');
    expect(find.byKey(const ValueKey('att-row-u1')), findsOneWidget);
    expect(find.byKey(const ValueKey('att-row-m1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('att-row-u1')));
    await _settle(tester);
    final before = svc.annualCalls;
    await tester.pageBack();
    await _settle(tester);
    expect(svc.annualCalls, before + 1);
  });

  testWidgets('SA-11b 연간 지각·결근 내역 행 → 그 달·그 근로자의 지각·결근(노쇼 포함)만', (tester) async {
    final svc = _FakeStats([
      ..._rows,
      _att('n2', 'abs', 12, AttendanceModel.statusNoShow),
      _att('p2', 'abs', 13, AttendanceModel.statusPresent),
    ]);
    await _pump(tester, AdminStatsScreen(businessIds: const ['biz1'], service: svc));
    expect(find.textContaining('지각·결근 내역'), findsOneWidget);
    expect(find.textContaining('주의 직원'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('exception-row-abs')));
    await _settle(tester);
    expect(svc.snapshotMonths.single, 10);
    expect(find.byKey(const ValueKey('att-row-a1')), findsOneWidget);
    expect(find.byKey(const ValueKey('att-row-n2')), findsOneWidget);
    expect(find.byKey(const ValueKey('att-row-p2')), findsNothing);
    expect(find.byKey(const ValueKey('att-row-n1')), findsNothing, reason: '다른 근로자의 노쇼');
  });

  testWidgets('SA-11c 정정 뒤 연간 갱신이 근태를 못 읽으면 이전 숫자를 지우지 않는다', (tester) async {
    final svc = _FakeStats(List.of(_rows));
    await _pump(tester, AdminStatsScreen(businessIds: const ['biz1'], service: svc,
        debugOpenAttendance: (r) async => true));
    await tester.tap(find.byKey(const ValueKey('annual-unconfirmed-att')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('att-row-u1')));
    await _settle(tester);
    svc.annualUnavailable = true;
    await tester.pageBack();
    await _settle(tester);
    expect(find.textContaining('정정 전 기준'), findsOneWidget);
    expect(find.textContaining('미확인 1건'), findsWidgets);
    expect(find.text('확인 불가'), findsNothing);
  });

  // [STATS-TO-ATTENDANCE.27-T1] 폭·글자 대응 — 글자를 줄이지 않고 배치를 바꾼다.
  //   폭만 줄인 경우와 글자만 키운 경우를 따로 본다. 큰 글자를 되돌려 줄이지 않는다.
  Future<void> layoutCase(WidgetTester tester, Size size, double scale) =>
      _pump(tester, _detailScreen(_FakeStats(List.of(_rows)), []), size: size, textScale: scale);

  bool isTable() => find.text('출결 현황').evaluate().isNotEmpty;

  testWidgets('TR-1 일반 폭·기본 글자 → 표 유지, 머리말·칩 한 줄', (tester) async {
    await layoutCase(tester, const Size(393, 851), 1.0);
    expect(tester.takeException(), isNull);
    expect(isTable(), isTrue);
    final head = tester.widget<Text>(findVisibleText('근무일').last);
    expect(head.softWrap, isFalse, reason: "'근무 / 일' 로 음절이 갈리지 않는다");
  });

  testWidgets('TR-2 320dp·기본 글자(폭만 축소) → 쌓은 행, 글자 크기 그대로', (tester) async {
    await layoutCase(tester, const Size(320, 800), 1.0);
    expect(tester.takeException(), isNull);
    expect(isTable(), isFalse);
    expect(find.text('근무일 1일'), findsWidgets);
    expect(find.byType(FittedBox), findsNothing, reason: '글자를 줄이는 방식을 쓰지 않는다');
  });

  testWidgets('TR-3 일반 폭·큰 글자(1.3) → 더 일찍 쌓는다 · 2.0 에서도 예외 없음', (tester) async {
    await layoutCase(tester, const Size(393, 851), 1.3);
    expect(tester.takeException(), isNull);
    expect(isTable(), isFalse);
    await layoutCase(tester, const Size(393, 851), 2.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TR-2b 320dp — 앱바 제목 "10월" 이 잘리지 않게 새로고침 아이콘을 내린다(당겨서 새로고침은 그대로)', (tester) async {
    await layoutCase(tester, const Size(320, 800), 1.0);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.text('10월'), findsOneWidget);
    expect(find.text('2026년 10월 · 평택 센터'), findsOneWidget, reason: '연도·사업장은 본문 첫 줄');
    await layoutCase(tester, const Size(393, 851), 1.0);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
  });

  testWidgets('TR-4 상태 칩은 글자·건수·화살표 한 단위(칩 안 줄바꿈 없음)', (tester) async {
    await layoutCase(tester, const Size(320, 800), 1.3);
    final chip = tester.widget<Text>(find.text('퇴근미확인 1 ›').first);
    expect(chip.softWrap, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TR-5 연간 KPI — 좁거나 글자가 크면 2×2, 값은 줄이거나 자르지 않는다', (tester) async {
    final svc = _FakeStats(List.of(_rows));
    await _pump(tester, AdminStatsScreen(businessIds: const ['biz1'], service: svc),
        size: const Size(320, 800), textScale: 1.3);
    expect(tester.takeException(), isNull);
    final v = tester.widget<Text>(findVisibleText('확인 필요').first);
    expect(v.maxLines, isNull);
    expect(v.overflow, isNot(TextOverflow.ellipsis));
    final att = tester.getTopLeft(find.byKey(const ValueKey('annual-unconfirmed-att')));
    final ns = tester.getTopLeft(find.byKey(const ValueKey('annual-unconfirmed-noshow')));
    expect(ns.dy, greaterThan(att.dy), reason: '2×2 — 출근율과 노쇼율이 다른 줄');
  });

  testWidgets('SA-12 320dp·글자 1.3 — 월 상세·목록이 넘치지 않는다', (tester) async {
    final svc = _FakeStats(List.of(_rows));
    await _pump(tester, _detailScreen(svc, []), size: const Size(320, 800), textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('직원별 요약'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('att-stat-missedCheckout')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });
}
