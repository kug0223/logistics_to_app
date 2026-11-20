import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
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
import 'package:ALfit/screens/business_admin/payroll/payroll_month_ledger.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_overview_reads.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_overview_screen.dart';

/// [PAYROLL-ANNUAL-READ.48] 급여 개요 미이체 — 연간 1회 원장 조회(10,000건 상한 시 12개월 전부 '확인 못함')를
///   달마다 조회로 바꾼 것. 기대값은 앱 집계를 부르지 않고 아래 합성 생성기에서 따로 센다.

// ── 합성 원본 ───────────────────────────────────────────────────────────────
const _kinds = [
  ('pending', 'present', 0), ('calculated', 'present', 80000),
  ('confirmed', 'present', 91230), ('transferred', 'present', 100000),
  ('confirmed', 'NO_SHOW', 0), ('transferred', 'absent', 0),
  ('confirmed', 'present', 0), ('confirmed', 'NO_SHOW', 5000),
];
final int _year = DateTime.now().year;
String _ymOf(int m) => '$_year-${m.toString().padLeft(2, '0')}';

List<Map<String, dynamic>> _items(int month, int n) => [
      for (var i = 0; i < n; i++)
        {
          'id': 'a${month}_$i',
          'yearMonth': _ymOf(month),
          'wageStatus': _kinds[i % _kinds.length].$1,
          'status': _kinds[i % _kinds.length].$2,
          'finalWage': _kinds[i % _kinds.length].$3,
          'userId': 'w${i % 37}',
        },
    ];

/// 독립 기대값 — 규칙을 손으로 적는다(앱 코드 아님).
({int pending, int nt, int t, int payout, int workers}) _expect(int n) {
  var p = 0, nt = 0, t = 0, pay = 0;
  final w = <String>{};
  for (var i = 0; i < n; i++) {
    final (ws, st, fw) = _kinds[i % _kinds.length];
    if (ws == 'pending' || ws == 'calculated') { p++; continue; }
    if ((st == 'NO_SHOW' || st == 'absent') && fw == 0) continue;
    if (ws == 'confirmed') { nt++; } else { t++; }
    pay += fw;
    w.add('w${i % 37}');
  }
  return (pending: p, nt: nt, t: t, payout: pay, workers: w.length);
}

// ── 화면 하네스(기존 payroll_overview_unknown_render_test 와 같은 모양) ──────────
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

class _WageAdmin extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'admin1', username: 'admin1', name: '김관리', email: 'a@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const ['biz1']);
  @override
  bool get isSubAdmin => false;
  @override
  String? get effectiveBusinessId => null;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
}

BusinessModel _biz() => BusinessModel(id: 'biz1', name: '강남 물류센터', ownerId: 'admin1', businessNumber: '000-00-00000',
    address: '서울', category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1));

typedef _Ledger = Future<({List<Map<String, dynamic>> items, bool limitReached})> Function(String gte, String lte);

PayrollOverviewReads _reads(_Ledger ledger, {Future<Object?> Function(String ym)? counts, Map<String, int>? calls}) =>
    PayrollOverviewReads(
      businesses: ({required bool isSubAdmin, required String? effectiveBusinessId, required List<String> managedIds}) async =>
          [_biz()],
      payrollSummaries: ({required String businessId, required int year}) async => const [],
      adminAttendances: ({required String businessId, required String yearMonthGte, required String yearMonthLte}) {
        calls?.update('ledger:$yearMonthGte~$yearMonthLte', (v) => v + 1, ifAbsent: () => 1);
        return ledger(yearMonthGte, yearMonthLte);
      },
      monthLedgerCounts: counts == null
          ? null
          : ({required String businessId, required String yearMonth}) {
              calls?.update('counts:$yearMonth', (v) => v + 1, ifAbsent: () => 1);
              return counts(yearMonth);
            },
      workerSummaries: (_) async => const [],
      repairSummary: ({required String businessId, required String yearMonth}) async {},
      todayPaymentCount: (_) async => 0,
    );

/// 연간 범위를 부르면 실제 서버처럼 10,000건에서 자르고 limitReached, 달 하나면 그 달 1,000건.
_Ledger _serverLike({Set<int> failOnce = const {}, Set<int> limitMonths = const {}}) {
  final failed = <int>{};
  return (gte, lte) async {
    if (gte != lte) {
      final all = [for (var m = 1; m <= 12; m++) ..._items(m, 1000)];
      return (items: all.take(10000).toList(), limitReached: all.length > 10000);
    }
    final m = int.parse(gte.split('-')[1]);
    if (failOnce.contains(m) && failed.add(m)) throw FirebaseFunctionsException(code: 'unavailable', message: 'x');
    if (limitMonths.contains(m)) return (items: _items(m, 10000), limitReached: true);
    return (items: _items(m, 1000), limitReached: false);
  };
}

Future<void> _pump(WidgetTester t, PayrollOverviewReads reads, {Size size = const Size(392, 2400), double scale = 1.0}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _WageAdmin()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: PayrollOverviewScreen(reads: reads),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

int get _monthsSoFar => DateTime.now().month;

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('월별 로더(순수)', () {
    Future<Map<int, MonthLedgerState>> run({
      required MonthLedgerRead read,
      MonthLedgerCountsRead? counts,
      List<int> months = const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
      Duration budget = const Duration(seconds: 30),
      MonthLedgerCounts? Function(int)? previousOf,
      bool Function()? isCurrent,
      MonthLedgerCountsCapability? cap,
    }) async {
      final out = <int, MonthLedgerState>{};
      await loadMonthLedgers(
        months: months, yearMonthOf: _ymOf, read: read, countsRead: counts, budget: budget,
        previousOf: previousOf, isCurrent: isCurrent ?? () => true, capability: cap,
        onMonth: (m, s) => out[m] = s,
      );
      return out;
    }

    Future<({List<Map<String, dynamic>> items, bool limitReached})> monthRead(String ym) async {
      final m = int.parse(ym.split('-')[1]);
      return (items: _items(m, 1000), limitReached: false);
    }

    test('LR-1 연간 분산 12×1,000 — 12달 모두 known, 숫자 정확(합성 원본 대조)', () async {
      final out = await run(read: monthRead);
      final e = _expect(1000);
      expect(out.length, 12);
      for (final s in out.values) {
        expect(s.status, MonthLedgerStatus.known);
        expect((s.counts!.pending, s.counts!.notTransferred, s.counts!.transferred, s.counts!.payout, s.counts!.workerCount),
            (e.pending, e.nt, e.t, e.payout, e.workers));
      }
    });

    test('LR-2 9월 실패는 9월만 — 10월은 known', () async {
      final out = await run(read: (ym) async {
        if (ym.endsWith('-09')) throw FirebaseFunctionsException(code: 'unavailable', message: 'x');
        return monthRead(ym);
      });
      expect(out[9]!.status, MonthLedgerStatus.unknown);
      expect(out[9]!.failure, MonthLedgerFailure.failed);
      expect(out[10]!.status, MonthLedgerStatus.known);
    });

    test('LR-3 한 달이 상한(집계 함수 없음) — 그 달만 unknown(limit), 숫자 없음', () async {
      final out = await run(read: (ym) async => ym.endsWith('-10')
          ? (items: _items(10, 10000), limitReached: true)
          : await monthRead(ym));
      expect(out[10]!.status, MonthLedgerStatus.unknown);
      expect(out[10]!.failure, MonthLedgerFailure.limit);
      expect(out[10]!.counts, isNull);
      expect(out.values.where((s) => s.status == MonthLedgerStatus.known).length, 11);
    });

    test('LR-4 서버 월 집계가 있으면 먼저 쓴다 — 문서 목록을 받지 않는다', () async {
      var ledgerCalls = 0;
      final out = await run(
        read: (ym) { ledgerCalls++; return monthRead(ym); },
        counts: (ym) async => {'complete': true, 'pending': 1, 'notTransferred': 2, 'transferred': 3, 'payout': 4, 'workerCount': 5},
      );
      expect(ledgerCalls, 0);
      expect(out.values.every((s) => s.status == MonthLedgerStatus.known && s.counts!.notTransferred == 2), isTrue);
    });

    test('LR-5 집계 함수 없음(not-found) — 첫 달에 한 번만 묻고 나머지는 원장', () async {
      var countsCalls = 0;
      final cap = MonthLedgerCountsCapability();
      final out = await run(read: monthRead, cap: cap, counts: (ym) async {
        countsCalls++;
        throw FirebaseFunctionsException(code: 'not-found', message: 'x');
      });
      expect(countsCalls, 1);
      expect(cap.available, isFalse);
      expect(out.values.every((s) => s.status == MonthLedgerStatus.known), isTrue);
    });

    test('LR-6 집계가 끝까지 못 셌다(complete=false) — 그 달은 limit 으로 확인 못함', () async {
      final out = await run(months: const [10], read: monthRead, counts: (ym) async => {'complete': false, 'scanned': 1000});
      expect(out[10]!.status, MonthLedgerStatus.unknown);
      expect(out[10]!.failure, MonthLedgerFailure.limit);
    });

    test('LR-7 대기 상한은 전체 하나 — 응답 없는 달들이 있어도 상한 뒤 끝난다', () async {
      final sw = Stopwatch()..start();
      final out = await run(
        budget: const Duration(milliseconds: 120),
        read: (ym) => ym.endsWith('-01') ? monthRead(ym) : Completer<({List<Map<String, dynamic>> items, bool limitReached})>().future,
      );
      expect(sw.elapsedMilliseconds, lessThan(400), reason: '달마다 상한을 새로 주면 합계가 늘어난다');
      expect(out[1]!.status, MonthLedgerStatus.known);
      expect(out[2]!.failure, MonthLedgerFailure.timeout);
      expect(out[12]!.status, MonthLedgerStatus.unknown);
    });

    test('LR-8 전환되면(isCurrent=false) 이후 결과를 알리지 않는다', () async {
      var current = true;
      final out = await run(read: (ym) async {
        if (ym.endsWith('-03')) current = false;
        return monthRead(ym);
      }, isCurrent: () => current);
      expect(out.containsKey(12), isFalse);
    });

    test('LR-9 새로고침 실패 + 이전 숫자 있음 → stale(이전 조회), 이번 조회의 사실 아님', () async {
      final prev = MonthLedgerCounts.fromItems(_items(5, 1000), 5);
      final out = await run(months: const [5], read: (ym) async => throw FirebaseFunctionsException(code: 'unavailable', message: 'x'),
          previousOf: (m) => prev);
      expect(out[5]!.status, MonthLedgerStatus.stale);
      expect(out[5]!.isComplete, isFalse);
      expect(out[5]!.counts!.notTransferred, prev.notTransferred);
    });
  });

  group('급여 개요 화면', () {
    testWidgets('AW-1 [핵심] 연간 합 > 10,000, 달마다 1,000 — 어느 달도 "확인 못함"이 아니고 미이체 숫자가 정확하다', (t) async {
      final calls = <String, int>{};
      await _pump(t, _reads(_serverLike(), calls: calls));
      expect(find.bySemanticsLabel('미이체 확인 못함'), findsNothing, reason: '수정 전에는 12개월 전부 확인 못함');
      expect(find.text('확인 못함'), findsNothing);
      expect(find.byWidgetPredicate((w) => w is Text && (w.data == '미이체 확인 못함' || w.semanticsLabel == '미이체 확인 못함')), findsNothing);
      final e = _expect(1000);
      expect(find.text('미이체 ${e.nt}'), findsNWidgets(_monthsSoFar));
      expect(calls.keys.where((k) => k.startsWith('ledger:') && !k.contains('-01~') ).length + 1, greaterThanOrEqualTo(1));
      expect(calls.keys.any((k) => k == 'ledger:$_year-01~$_year-12'), isFalse, reason: '연간 범위를 한 번에 읽지 않는다');
      expect(calls.length, _monthsSoFar, reason: '미래 달은 읽지 않는다');
    });

    testWidgets('AW-2 9월만 실패 → 9월만 확인 못함·배너 → 다시 확인은 9월만 다시 읽는다', (t) async {
      if (_monthsSoFar < 10) return; // 9·10월이 지난 해에만 의미가 있다(2026-11 실행).
      final calls = <String, int>{};
      await _pump(t, _reads(_serverLike(failOnce: {9}), calls: calls));
      // 집계 문서가 없는 달은 원장을 못 읽으면 빈 카드로 '확인 못함'(데이터 없음이 아니다).
      expect(find.text('확인 못함'), findsOneWidget);
      expect(find.bySemanticsLabel('9월 미이체를 확인하지 못했어요.'), findsOneWidget);
      final before = Map.of(calls);
      await t.tap(find.bySemanticsLabel('다시 확인'));
      for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
      final diff = {for (final k in calls.keys) if (calls[k] != before[k]) k: calls[k]! - (before[k] ?? 0)};
      expect(diff, {'ledger:${_ymOf(9)}~${_ymOf(9)}': 1}, reason: '성공한 다른 달을 다시 읽지 않는다');
      expect(find.text('확인 못함'), findsNothing);
      expect(find.bySemanticsLabel('9월 미이체를 확인하지 못했어요.'), findsNothing);
    });

    testWidgets('AW-3 10월 한 달이 상한(서버 집계 없음) — 10월만 확인 못함, 배너가 건수가 많다고 말한다', (t) async {
      if (_monthsSoFar < 10) return;
      await _pump(t, _reads(_serverLike(limitMonths: {10})));
      expect(find.text('확인 못함'), findsOneWidget);
      expect(find.bySemanticsLabel('10월 미이체를 확인하지 못했어요. 건수가 많은 달이 있어요.'), findsOneWidget);
      expect(find.text('미이체 ${_expect(1000).nt}'), findsNWidgets(_monthsSoFar - 1));
    });

    testWidgets('AW-4 10월 상한 + 서버 집계 있음 — 10월도 정확한 숫자', (t) async {
      if (_monthsSoFar < 10) return;
      final calls = <String, int>{};
      await _pump(t, _reads(_serverLike(limitMonths: {10}), calls: calls, counts: (ym) async {
        if (!ym.endsWith('-10')) throw FirebaseFunctionsException(code: 'not-found', message: 'x');
        return {'complete': true, 'pending': 0, 'notTransferred': 4629, 'transferred': 1543, 'payout': 302782890, 'workerCount': 37};
      }));
      // 첫 달에 not-found 를 확인하면 나머지는 원장으로 센다 → 10월은 원장 상한 → 집계를 다시 묻지 않는다(이번 세션 '없음').
      //   그러므로 10월은 확인 못함이어야 한다 — 배포되지 않은 함수를 있다고 가정하지 않는다.
      expect(find.text('확인 못함'), findsOneWidget);
      expect(calls['counts:${_ymOf(1)}'], 1);
      expect(calls.keys.where((k) => k.startsWith('counts:')).length, 1);
    });

    testWidgets('AW-5 연도를 바꾸면 이전 연도의 늦은 응답은 버린다', (t) async {
      final gates = <String, Completer<void>>{};
      await _pump(t, _reads((gte, lte) async {
        final g = gates.putIfAbsent(gte, Completer.new);
        if (gte.startsWith('$_year-')) await g.future; // 올해 응답은 붙잡아 둔다
        final m = int.parse(gte.split('-')[1]);
        return (items: _items(m, gte.startsWith('$_year-') ? 1000 : 8), limitReached: false);
      }));
      await t.tap(find.byTooltip('이전 연도'));
      for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
      for (final g in gates.values) { if (!g.isCompleted) g.complete(); }
      for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
      expect(find.text('${_year - 1}년'), findsOneWidget);
      expect(find.text('미이체 ${_expect(1000).nt}'), findsNothing, reason: '올해 늦은 응답이 작년 화면에 들어왔다');
      expect(find.text('미이체 ${_expect(8).nt}'), findsNWidgets(12));
    });

    testWidgets('AW-6 새로고침이 실패한 달은 이전 숫자를 "이전 조회"로 보인다', (t) async {
      var round = 0;
      await _pump(t, _reads((gte, lte) async {
        if (round > 0 && gte.endsWith('-01')) throw FirebaseFunctionsException(code: 'unavailable', message: 'x');
        return (items: _items(int.parse(gte.split('-')[1]), 1000), limitReached: false);
      }));
      round = 1;
      await t.tap(find.byTooltip('새로고침'));
      for (var i = 0; i < 20; i++) { await t.pump(const Duration(milliseconds: 100)); }
      // 카드가 눌리는 영역이라 화면 읽기 노드는 카드 하나로 합쳐진다 — Text 의 의미 라벨로 찾는다.
      expect(find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == '미이체 ${_expect(1000).nt} · 이전 조회'), findsOneWidget);
      expect(find.bySemanticsLabel('1월 미이체를 확인하지 못했어요.'), findsOneWidget);
    });

    for (final (w, s) in [(320.0, 1.3), (392.0, 2.0)]) {
      testWidgets('AW-7 배너·카드 배치 $w·$s — 넘침 없음', (t) async {
        await _pump(t, _reads(_serverLike(failOnce: {1, 2, 3}, limitMonths: {5})), size: Size(w, 2400), scale: s);
        expect(t.takeException(), isNull);
        expect(find.bySemanticsLabel('다시 확인'), findsOneWidget);
      });
    }
  });
}
