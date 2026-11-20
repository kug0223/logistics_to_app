// ignore_for_file: depend_on_referenced_packages
// [DU1 SubAdmin §5] 급여 월 근무자 목록 — 빈 이유 분리(LOCAL RENDER).
//   ML-1 부모 없음 → 하위 목록을 읽지 않는다 + 원장 확정 전 N건 문장
//   ML-2 부모 없음 + 원장 0(끝까지 셈) → 기존 '확정된 급여가 없습니다'
//   ML-3 부모 없음 + 건수 모름 → '확인하지 못했어요'(0 이라고 말하지 않는다)
//   ML-4 하위 거부 + CF 거부 → 권한 없음(다시 시도 없음)
//   ML-5 하위 거부 + CF 에 그 달 있음 → 권한 확인 불가 + 다시 시도 / CF 에 없음 → 부모 없음 문장
//   ML-6 거부 아닌 실패(unavailable) → 기존 '불러오지 못했습니다' + 다시 시도(CF 재확인 없음)
//   ML-7 부모 없음 + 이전 확정분 + 현재 모름 → 모름 우선 / ML-8 실제 production reader(가짜 오프라인 DB) → 서버 조회만, 빈 캐시를 정상0으로 만들지 않음
//   DEV 호출 없음. 실제 W-only SubAdmin 기기 성공은 PENDING.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/payroll_summary_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_overview_reads.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_overview_screen.dart';

import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options =>
      const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

PayrollSummaryModel _summary({int confirmed = 0, int pending = 0}) => PayrollSummaryModel(
      id: 'b1_2026-09',
      businessId: 'b1',
      yearMonth: '2026-09',
      year: 2026,
      month: 9,
      totalPayout: 0,
      confirmedCount: confirmed,
      workerCount: 0,
      pendingCount: pending,
      notTransferredCount: 0,
      workers: const {},
      updatedAt: DateTime(2026, 9, 30),
    );

class _Calls {
  int workers = 0;
  int summaries = 0;
}

PayrollOverviewReads _reads(_Calls c,
        {Future<List<({String id, Map<String, dynamic> data})>> Function()? workers,
        Future<List<Map<String, dynamic>>> Function()? summaries}) =>
    PayrollOverviewReads(
      businesses: ({required isSubAdmin, required effectiveBusinessId, required managedIds}) async =>
          <BusinessModel>[],
      payrollSummaries: ({required businessId, required year}) {
        c.summaries++;
        return summaries != null ? summaries() : Future.value(const <Map<String, dynamic>>[]);
      },
      adminAttendances: ({required businessId, required yearMonthGte, required yearMonthLte}) async =>
          (items: const <Map<String, dynamic>>[], limitReached: false),
      workerSummaries: (_) {
        c.workers++;
        return workers != null ? workers() : Future.value(const <({String id, Map<String, dynamic> data})>[]);
      },
      repairSummary: ({required businessId, required yearMonth}) async {},
      todayPaymentCount: (_) async => 0,
    );

Future<void> _pump(WidgetTester t, PayrollMonthScreen screen) async {
  t.view.physicalSize = const Size(392, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<NotificationProvider>(
    create: (_) => NotificationProvider(),
    child: MaterialApp(home: screen),
  ));
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

FirebaseException _denied() => FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');


// ── [DU1 MONTH-READ-SOURCE] production reader 경계 ──────────────────────────────
//   설치 SDK get_options.dart: 기본 serverAndCache 는 서버 불가 시 캐시로 대체, 빈 캐시 쿼리는 빈 결과.
//   가짜 DB 는 그 의미를 그대로 흉내 낸다: source=server → unavailable throw / 그 외 → 빈 캐시 성공.
class _OfflineDb extends Fake implements FirebaseFirestore {
  final sources = <Source?>[];
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) => _OfflineCol(this);
}

class _OfflineCol extends Fake implements CollectionReference<Map<String, dynamic>> {
  _OfflineCol(this.db);
  final _OfflineDb db;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => _OfflineDoc(db);
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    db.sources.add(options?.source);
    if (options?.source == Source.server) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return _EmptyCacheSnap();
  }
}

class _OfflineDoc extends Fake implements DocumentReference<Map<String, dynamic>> {
  _OfflineDoc(this.db);
  final _OfflineDb db;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) => _OfflineCol(db);
}

class _EmptyCacheSnap extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => const [];
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('ML-1 부모 없음 + 원장 확정 전 2건 → 하위 목록을 읽지 않고 확정 전 문장', (t) async {
    final c = _Calls();
    await _pump(t, PayrollMonthScreen(summary: _summary(pending: 2), reads: _reads(c), summaryDocExists: false));
    expect(c.workers, 0, reason: '부모 없는 달의 하위 목록은 rule 상 권한이 있어도 거부된다');
    expect(findVisibleText('확정 전 급여 2건이 있어요'), findsOneWidget);
    expect(findVisibleText('근무자 목록을 불러오지 못했습니다'), findsNothing);
    expect(findVisibleText('집계 데이터 복원'), findsNothing);
  });

  testWidgets('ML-2 부모 없음 + 원장 0(끝까지 셈) → 확정된 급여가 없습니다', (t) async {
    final c = _Calls();
    await _pump(t, PayrollMonthScreen(summary: _summary(), reads: _reads(c), summaryDocExists: false));
    expect(c.workers, 0);
    expect(findVisibleText('확정된 급여가 없습니다'), findsOneWidget);
  });

  testWidgets('ML-3 부모 없음 + 건수 모름 → 0 이라고 말하지 않는다', (t) async {
    final c = _Calls();
    await _pump(t, PayrollMonthScreen(
        summary: _summary(), reads: _reads(c), summaryDocExists: false, countsUnknown: true));
    expect(findVisibleText('이 달 급여 건수를 확인하지 못했어요'), findsOneWidget);
    expect(findVisibleText('확정된 급여가 없습니다'), findsNothing);
  });

  testWidgets('ML-3b 부모 없음 + 원장 확정분 있음 → 기존 집계 누락·복원 분기', (t) async {
    final c = _Calls();
    await _pump(t, PayrollMonthScreen(summary: _summary(confirmed: 3), reads: _reads(c), summaryDocExists: false));
    expect(c.workers, 0);
    expect(findVisibleText('집계 데이터가 없습니다'), findsOneWidget);
    expect(findVisibleText('집계 데이터 복원'), findsOneWidget);
  });

  testWidgets('ML-4 하위 거부 + CF 거부 → 권한 없음, 다시 시도 없음', (t) async {
    final c = _Calls();
    await _pump(t, PayrollMonthScreen(
        summary: _summary(confirmed: 2),
        reads: _reads(c,
            workers: () => Future.error(_denied()),
            summaries: () => Future.error(FirebaseException(plugin: 'cloud_functions', code: 'permission-denied')))));
    expect(c.summaries, 1);
    expect(findVisibleText('급여 정보를 볼 권한이 없습니다'), findsOneWidget);
    expect(findVisibleText('다시 시도'), findsNothing);
    expect(findVisibleText('집계 데이터 복원'), findsNothing, reason: '권한 없음에 재집계를 권하지 않는다');
  });

  testWidgets('ML-5 하위 거부 + CF 에 그 달 있음 → 권한 확인 불가 + 다시 시도', (t) async {
    final c = _Calls();
    await _pump(t, PayrollMonthScreen(
        summary: _summary(confirmed: 2),
        reads: _reads(c,
            workers: () => Future.error(_denied()),
            summaries: () async => [<String, dynamic>{'id': 'b1_2026-09'}])));
    expect(findVisibleText('권한을 확인하지 못했어요'), findsOneWidget);
    expect(findVisibleText('다시 시도'), findsOneWidget);
  });

  testWidgets('ML-5b 하위 거부 + CF 에 그 달 없음 → 부모 없음(원장 확정 전 문장)', (t) async {
    final c = _Calls();
    await _pump(t, PayrollMonthScreen(
        summary: _summary(pending: 1),
        reads: _reads(c, workers: () => Future.error(_denied()), summaries: () async => const [])));
    expect(findVisibleText('확정 전 급여 1건이 있어요'), findsOneWidget);
    expect(findVisibleText('권한을 확인하지 못했어요'), findsNothing);
  });

  testWidgets('ML-6 거부 아닌 실패 → 읽기 실패 + 다시 시도, CF 재확인 없음', (t) async {
    final c = _Calls();
    await _pump(t, PayrollMonthScreen(
        summary: _summary(confirmed: 2),
        reads: _reads(c,
            workers: () => Future.error(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable')))));
    expect(c.summaries, 0);
    expect(findVisibleText('근무자 목록을 불러오지 못했습니다'), findsOneWidget);
    expect(findVisibleText('다시 시도'), findsOneWidget);
  });

  testWidgets('ML-7 부모 없음 + 이전 확정분 3 + 현재 모름 → 모름 우선, 복원 권하지 않음', (t) async {
    final c = _Calls();
    await _pump(t, PayrollMonthScreen(
        summary: _summary(confirmed: 3), reads: _reads(c), summaryDocExists: false, countsUnknown: true));
    expect(findVisibleText('이 달 급여 건수를 확인하지 못했어요'), findsOneWidget);
    expect(findVisibleText('집계 데이터 복원'), findsNothing);
    expect(findVisibleText('집계 데이터가 없습니다'), findsNothing);
  });

  test('ML-8a production reader 는 서버 조회만 한다 — 오프라인이면 빈 캐시 대신 오류', () async {
    final db = _OfflineDb();
    final r = PayrollOverviewReads.of(firestore: db);
    await expectLater(r.workerSummaries('b1_2026-09'), throwsA(isA<FirebaseException>().having((e) => e.code, 'code', 'unavailable')));
    expect(db.sources, [Source.server]);
  });

  testWidgets('ML-8b production reader + 확정분 2 오프라인 → 불러오지 못함(집계 누락·복원 아님)', (t) async {
    final db = _OfflineDb();
    await _pump(t, PayrollMonthScreen(summary: _summary(confirmed: 2), reads: PayrollOverviewReads.of(firestore: db)));
    expect(findVisibleText('근무자 목록을 불러오지 못했습니다'), findsOneWidget);
    expect(findVisibleText('집계 데이터 복원'), findsNothing);
    expect(findVisibleText('확정된 급여가 없습니다'), findsNothing);
  });
}
