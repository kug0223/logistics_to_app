import 'dart:async';
import 'dart:io';

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
import 'package:ALfit/screens/business_admin/payroll/payroll_worker_detail_screen.dart';

import 'support/visible_text.dart';

/// [PAYROLL-DETAIL.32] 급여 월 목록 → 근무자 상세 연결 (RENDER)
///
///   PD-1 근무일은 KST 날짜(기기 시간대와 무관)
///   PD-2 확정 근무 건수는 개요(서버)와 같은 식 — 노쇼·결근 0원 제외, 그 기록은 '지급 없음'으로 남긴다
///        확정 0원은 '0원'('-' 모름과 구분)
///   PD-3 같은 날 두 근무는 출근 순 + 시간 범위로 구분된다
///   PD-4 머리말이 인력번호·이름·기간을 말한다(동명이인 구분)
///   PD-5 실패 → 다시 시도 회복, 불러오는 중 임시 금액 없음
///   PD-6 중간정산 후보는 이체 대상만(노쇼 0원 제외), 취소하면 쓰기 0
///   PD-7 320·1.3 / 392·2.0 예외 0, 날짜·시간·금액 표시
///   PM-1 같은 이름이 있을 때만 그 사람들의 인력번호를 읽어 이름 옆에 붙인다 / PM-2 없으면 부르지 않는다
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

/// KST d일 0시 instant — 서버가 workDate 로 쓰는 값.
Timestamp _kstMid(int y, int m, int d) =>
    Timestamp.fromMillisecondsSinceEpoch(DateTime.utc(y, m, d).millisecondsSinceEpoch - 9 * 3600 * 1000);
Timestamp _kstAt(int y, int m, int d, int hh, int mm) =>
    Timestamp.fromMillisecondsSinceEpoch(DateTime.utc(y, m, d, hh, mm).millisecondsSinceEpoch - 9 * 3600 * 1000);

Map<String, dynamic> _att(String id, int d, String ws, int net,
        {String status = 'present', int sh = 9, int eh = 18, bool times = true}) =>
    {
      'id': id,
      'userId': 'w1',
      'applicationId': 'app_$id',
      'businessId': 'b1',
      'businessName': '[합성] E7 사업장',
      'workDate': _kstMid(2026, 9, d),
      'workType': '분류',
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
      'status': status,
      'wageStatus': ws,
      'finalWage': net,
      if (times) 'checkIn': _kstAt(2026, 9, d, sh, 0),
      if (times) 'checkOut': _kstAt(2026, 9, d, eh, 0),
      'wageDetail': {
        'wageType': 'hourly',
        'workMinutes': times ? (eh - sh) * 60 : 0,
        'totalAmount': net,
        'netWage': net,
        'calculatedAt': Timestamp.fromDate(DateTime(2026, 9, 30)),
        'confirmedAt': Timestamp.fromDate(DateTime(2026, 9, 30)),
      },
    };

Future<void> _pumpDetail(WidgetTester t, {Size size = const Size(392, 1600), double scale = 1.0}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<NotificationProvider>(
    create: (_) => NotificationProvider(),
    child: MaterialApp(
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: const PayrollWorkerDetailScreen(
          businessId: 'b1', workerId: 'w1', workerName: '합성 두근무', year: 2026, month: 9),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  tearDown(() {
    PayrollWorkerDetailScreenTestHooks.reset();
  });

  testWidgets('PD-1·3·4 KST 날짜, 같은 날 두 근무 출근 순·시간 범위, 머리말 인력번호', (t) async {
    final calls = <Map<String, dynamic>>[];
    PayrollWorkerDetailScreenTestHooks.attendance = (p) async {
      calls.add(p);
      // 일부러 오후 근무를 먼저 준다
      return [_att('pm', 12, 'transferred', 41280, sh: 14, eh: 18), _att('am', 12, 'confirmed', 41280, sh: 9, eh: 13)];
    };
    PayrollWorkerDetailScreenTestHooks.personNo = (b, w) async => 'P-303';
    await _pumpDetail(t);
    expect(calls.single['userId'], 'w1');
    expect(calls.single['businessId'], 'b1');
    expect(findVisibleText('P-303 · 합성 두근무 · 2026년 9월'), findsOneWidget);
    expect(findVisibleTextContaining('9/12 (토) · 분류'), findsNWidgets(2), reason: 'KST 9/12 — 기기 시간대와 무관');
    final am = t.getTopLeft(findVisibleText('09:00 ~ 13:00')).dy;
    final pm = t.getTopLeft(findVisibleText('14:00 ~ 18:00')).dy;
    expect(am, lessThan(pm), reason: '같은 날 두 근무는 출근 순');
    expect(findVisibleText('2건'), findsOneWidget);
  });

  testWidgets('PD-2 확정 0원은 0원, 노쇼 0원은 지급 없음 — 건수는 개요와 같은 식', (t) async {
    PayrollWorkerDetailScreenTestHooks.attendance = (_) async => [
          _att('z1', 16, 'confirmed', 0, sh: 9, eh: 10),
          _att('z2', 17, 'confirmed', 0, status: 'NO_SHOW', times: false),
        ];
    await _pumpDetail(t);
    expect(findVisibleText('1건'), findsWidgets, reason: '서버 srvPayrollContribution 과 같은 수');
    expect(findVisibleText('2건'), findsNothing, reason: '노쇼 0원을 확정 근무로 세지 않는다');
    expect(findVisibleTextContaining('노쇼·결근 1건 · 지급 없음'), findsOneWidget);
    expect(findVisibleText('0원'), findsNWidgets(2), reason: "'-'(모름)이 아니라 0원");
    expect(findVisibleText('노쇼 · 지급 없음'), findsOneWidget);
    expect(findVisibleText('미이체'), findsNWidgets(2), reason: '머리말 라벨 + 확정 0원(z1) 배지 — 노쇼는 미이체가 아니다');
    expect(findVisibleText('9/16 (수) · 분류'), findsOneWidget);
    expect(findVisibleText('9/17 (목) · 분류'), findsOneWidget);
  });

  testWidgets('PD-5 실패 → 다시 시도 회복, 불러오는 중 금액을 보이지 않는다', (t) async {
    var n = 0;
    final second = Completer<List<Map<String, dynamic>>>();
    PayrollWorkerDetailScreenTestHooks.attendance = (_) {
      n++;
      if (n == 1) return Future.error(StateError('network'));
      return second.future;
    };
    await _pumpDetail(t);
    expect(findVisibleText('데이터를 불러오지 못했습니다'), findsOneWidget);
    expect(findVisibleText('실수령 합계'), findsNothing, reason: '실패를 0원·- 합계로 보이지 않는다');
    await t.tap(findVisibleText('다시 시도'));
    await t.pump(const Duration(milliseconds: 50));
    expect(findVisibleText('실수령 합계'), findsNothing, reason: '불러오는 중 임시 합계 없음');
    expect(findVisibleTextContaining('원'), findsNothing);
    second.complete([_att('a', 10, 'confirmed', 80000)]);
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(findVisibleText('80,000원'), findsWidgets);
    expect(findVisibleText('데이터를 불러오지 못했습니다'), findsNothing);
  });

  testWidgets('PD-6 중간정산 후보는 이체 대상만 — 취소하면 쓰기 없음', (t) async {
    PayrollWorkerDetailScreenTestHooks.attendance = (_) async => [
          _att('a', 10, 'confirmed', 80000),
          _att('ns', 11, 'confirmed', 0, status: 'NO_SHOW', times: false),
          _att('done', 12, 'transferred', 70000),
        ];
    await _pumpDetail(t);
    await t.tap(find.byIcon(Icons.more_vert));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(find.text('중간정산 처리'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(findVisibleTextContaining('확정 급여 1건'), findsOneWidget, reason: '노쇼 0원·이체 완료 제외');
    expect(findVisibleTextContaining('대상 금액: 80,000원'), findsOneWidget);
    await t.tap(findVisibleText('취소'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(findVisibleTextContaining('확정 급여 1건'), findsNothing);
  });

  for (final c in const [(320.0, 1.3), (392.0, 2.0)]) {
    final (w, s) = c;
    testWidgets('PD-7 ${w.toInt()}·$s — 예외 0, 날짜·시간·금액·상태가 다 보인다', (t) async {
      PayrollWorkerDetailScreenTestHooks.attendance = (_) async => [
            _att('am', 12, 'confirmed', 41280, sh: 9, eh: 13),
            _att('pm', 12, 'transferred', 103200, sh: 14, eh: 18),
          ];
      PayrollWorkerDetailScreenTestHooks.personNo = (b, w) async => 'P-303';
      await _pumpDetail(t, size: Size(w, 3200), scale: s);
      expect(t.takeException(), isNull);
      for (final v in ['09:00 ~ 13:00', '14:00 ~ 18:00', '41,280원', '103,200원', '이체 완료', '미이체']) {
        expect(findVisibleText(v), findsWidgets, reason: v);
      }
    });
  }

  testWidgets('PD-9 빈 내역은 실패와 다르게 말한다 — 0원 합계를 만들지 않는다', (t) async {
    PayrollWorkerDetailScreenTestHooks.attendance = (_) async => [];
    await _pumpDetail(t);
    expect(findVisibleText('확정된 급여 내역이 없습니다'), findsOneWidget);
    expect(findVisibleText('데이터를 불러오지 못했습니다'), findsNothing);
    expect(findVisibleText('다시 시도'), findsNothing);
  });

  testWidgets('PD-10 다시 시도는 실패로 빠진 인력번호도 다시 읽는다', (t) async {
    var a = 0;
    var p = 0;
    PayrollWorkerDetailScreenTestHooks.attendance = (_) async {
      if (a++ == 0) throw StateError('network');
      return [_att('z1', 16, 'confirmed', 0, sh: 9, eh: 10)];
    };
    PayrollWorkerDetailScreenTestHooks.personNo = (b, w) async {
      if (p++ == 0) throw StateError('network');
      return 'P-305';
    };
    await _pumpDetail(t);
    expect(findVisibleText('데이터를 불러오지 못했습니다'), findsOneWidget);
    await t.tap(findVisibleText('다시 시도'));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(findVisibleTextContaining('P-305 · 합성 두근무'), findsOneWidget);
    expect(p, 2);
  });

  test('PD-8 날짜 계산은 KST 변환을 거친다(원천 계약) — GMT 기기에서 하루 앞 날짜가 됐다', () {
    final src = File('lib/screens/business_admin/payroll/payroll_worker_detail_screen.dart').readAsStringSync();
    expect(src.contains('final workDate = FormatHelper.toKstDate(record.workDate);'), isTrue);
    expect(src.contains("final dateStr = '\${workDate.month}/\${workDate.day}"), isTrue);
    // 기존 다음 행동(급여 명세 창)도 같은 날짜·사람을 말한다 — 기기(GMT)에서 9/10 근무가 2026.09.09 로,
    //   이름은 '이름 없음'으로 보였다.
    final dlg = File('lib/widgets/dialogs/wage/wage_detail_dialog.dart').readAsStringSync();
    expect(dlg.contains('final d = FormatHelper.toKstDate(widget.attendance.workDate);'), isTrue);
    expect(src.contains('fallbackName: widget.workerName,'), isTrue);
  });

  // ───────────────────────── 월 목록 ─────────────────────────
  PayrollSummaryModel summary() => PayrollSummaryModel(
        id: 'b1_2026-09',
        businessId: 'b1',
        yearMonth: '2026-09',
        year: 2026,
        month: 9,
        totalPayout: 152000,
        confirmedCount: 2,
        workerCount: 3,
        pendingCount: 0,
        notTransferredCount: 1,
        workers: const {},
        updatedAt: DateTime(2026, 9, 30),
      );

  PayrollOverviewReads reads(List<({String id, Map<String, dynamic> data})> workers,
          List<List<String>> labelCalls) =>
      PayrollOverviewReads(
        businesses: ({required isSubAdmin, required effectiveBusinessId, required managedIds}) async =>
            <BusinessModel>[],
        payrollSummaries: ({required businessId, required year}) async => const [],
        adminAttendances: ({required businessId, required yearMonthGte, required yearMonthLte}) async =>
            (items: const <Map<String, dynamic>>[], limitReached: false),
        workerSummaries: (_) async => workers,
        repairSummary: ({required businessId, required yearMonth}) async {},
        todayPaymentCount: (_) async => 0,
        personLabels: ({required businessId, required uids}) async {
          labelCalls.add(uids);
          return {'tA': 'P-301', 'tB': 'P-302'};
        },
      );

  Future<void> pumpMonth(WidgetTester t, PayrollOverviewReads r) async {
    t.view.physicalSize = const Size(392, 1200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<NotificationProvider>(
      create: (_) => NotificationProvider(),
      child: MaterialApp(home: PayrollMonthScreen(summary: summary(), reads: r)),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('PM-1 동명이인만 인력번호를 읽어 이름 옆에 붙인다', (t) async {
    final calls = <List<String>>[];
    await pumpMonth(t, reads([
      (id: 'tA', data: {'name': '합성 동명', 'totalPayout': 80000, 'workDays': 1}),
      (id: 'tB', data: {'name': '합성 동명', 'totalPayout': 72000, 'workDays': 1}),
      (id: 'x', data: {'name': '합성 단독', 'totalPayout': 0, 'workDays': 1}),
    ], calls));
    expect(calls, hasLength(1));
    expect(calls.single.toSet(), {'tA', 'tB'}, reason: '같은 이름인 사람만');
    expect(findVisibleText('합성 동명 · P-301'), findsOneWidget);
    expect(findVisibleText('합성 동명 · P-302'), findsOneWidget);
    expect(findVisibleText('합성 단독'), findsOneWidget, reason: '단독 이름은 그대로');
  });

  testWidgets('PM-2 같은 이름이 없으면 인력번호를 부르지 않는다', (t) async {
    final calls = <List<String>>[];
    await pumpMonth(t, reads([
      (id: 'a', data: {'name': '합성 가', 'totalPayout': 1000, 'workDays': 1}),
      (id: 'b', data: {'name': '합성 나', 'totalPayout': 2000, 'workDays': 1}),
    ], calls));
    expect(calls, isEmpty);
  });
}
