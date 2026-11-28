// [impl_40 · AUD-4 H7/H11/H13/H14/M23] 급여 지급 대시보드의 근무자 상세(_WorkerPayDetailScreen) — 주차·날짜·좁은 폭.
//
//   P1  주차 = 대시보드 칩과 같은 helper(weeksOfMonth) — 7/8(수) → '7월 1주차'(예전 2주차) · 7/1(수) → '6월 5주차'
//   P2  KST 자정 instant 를 기기 시간대가 아닌 KST 달력으로 — 경계 instant(UTC 15:00)도 같은 날
//   P3  화면 — 제목 주차 · 기록 날짜/요일 · 이체일(KST 00–09시 이체) · 통계 줄 범위
//   P4  320@1.0 / 320@1.3 / 320@2.0 / 392@2.0 — 넘침 0 · 금액·잔여 금액 보임
//   P5  소스 — 화면 안의 subtract 주차 계산 0 · 날짜는 FormatHelper.toKstDate
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart' show MemberPermissions;
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
import 'package:ALfit/screens/payroll/payslip_period_helper.dart';

import 'support/visible_text.dart';

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

class _AdminP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'owner1', username: 'owner1', name: '관리자', email: 'owner1@test.local', role: UserRole.BUSINESS_ADMIN);
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
  @override
  VoidCallback watchBusinessPermissions(String businessId) => () {};
}

/// KST y-m-d 00:00 instant (서버 workDate 와 같은 값).
DateTime _kstMid(int y, int m, int d) => DateTime.utc(y, m, d).subtract(const Duration(hours: 9));
Timestamp _ts(DateTime dt) => Timestamp.fromDate(dt);

AttendanceModel _att(String id, DateTime workDate, {String ws = 'confirmed', DateTime? transferDate, int net = 80000}) =>
    AttendanceModel.fromMap({
      'applicationId': 'app_$id',
      'userId': 'w1',
      'businessId': 'b1',
      'businessName': '[합성] 평택 사업장',
      'workDate': _ts(workDate),
      'workType': '분류',
      'createdAt': _ts(DateTime.utc(2026, 7, 1)),
      'status': 'present',
      'wageStatus': ws,
      'finalWage': net,
      'checkIn': _ts(workDate.add(const Duration(hours: 9))),
      'checkOut': _ts(workDate.add(const Duration(hours: 18))),
      if (transferDate != null) 'transferDate': _ts(transferDate),
      'wageDetail': {
        'wageType': 'hourly',
        'workMinutes': 480,
        'totalAmount': net,
        'netWage': net,
        'payScheduleType': 'weekly',
        'calculatedAt': _ts(DateTime.utc(2026, 7, 20)),
        'confirmedAt': _ts(DateTime.utc(2026, 7, 20)),
      },
    }, id);

Future<void> _pump(WidgetTester t, List<AttendanceModel> recs, {double width = 411, double scale = 1.0}) async {
  t.view.physicalSize = Size(width, 4000); // 큰 글자에서도 기록 카드가 모두 화면 안에 그려지게(목록은 지연 생성)
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _AdminP(),
    child: MaterialApp(
      builder: (ctx, c) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: c!,
      ),
      home: debugWorkerPayDetailScreen(workerName: '김지현', records: recs, businessId: 'b1', bankInfo: 'B은행 ***1234'),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

List<String> _overflows(WidgetTester t) {
  final out = <String>[];
  Object? e;
  while ((e = t.takeException()) != null) {
    out.add(e.toString().split('\n').first);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  test('P1 주차 = 대시보드 칩과 같은 helper', () {
    final chip1 = PayslipPeriodHelper.weeksOfMonth(2026, 7).first;
    expect((chip1.weekNo, chip1.start.day), (1, 6), reason: '2026-07-01 은 수요일 → 첫 주 = 7/6');
    final w = workerPayWeekInfo([_kstMid(2026, 7, 8)]);
    expect(w.weekLabel, '7월 1주차', reason: '예전 subtract 방식은 2주차');
    expect(w.rangeLabel, '1주차 · 7/6 ~ 7/12');
    final june = workerPayWeekInfo([_kstMid(2026, 7, 1)]);
    expect(june.weekLabel, '6월 5주차', reason: '월요일(6/29)이 속한 달');
    // 가장 이른 근무일 기준
    expect(workerPayWeekInfo([_kstMid(2026, 7, 15), _kstMid(2026, 7, 13)]).weekLabel, '7월 2주차');
  });

  test('P2 KST 자정 instant(UTC 전날 15:00)도 KST 달력의 그 날 주차', () {
    final inst = _kstMid(2026, 7, 6); // 2026-07-05T15:00Z
    expect(inst.isUtc, isTrue);
    expect(inst.day, 5, reason: 'UTC 로는 전날이다 — 이 값을 기기 시간대로 읽으면 D-1');
    expect(PayslipPeriodHelper.weekOfWorkDate(inst).weekNo, 1);
    expect(PayslipPeriodHelper.weekOfWorkDate(inst).month, 7);
    expect(PayslipPeriodHelper.weekOfWorkDate(_kstMid(2026, 7, 5)).month, 6, reason: '7/5(일)은 6/29 주');
  });

  testWidgets('P3 화면 — 제목 주차 · 기록 날짜/요일 · KST 00–09시 이체일 · 통계 범위', (t) async {
    final recs = [
      _att('a', _kstMid(2026, 7, 8), ws: 'transferred', transferDate: DateTime.utc(2026, 7, 9, 18, 30)), // KST 7/10 03:30
      _att('b', _kstMid(2026, 7, 9)),
    ];
    await _pump(t, recs);
    expect(_overflows(t), isEmpty);
    expect(findVisibleTextContaining('7월 1주차'), findsWidgets);
    expect(findVisibleTextContaining('7월 2주차'), findsNothing, reason: '대시보드 칩과 다른 주차');
    expect(findVisibleTextContaining('7/8 (수)'), findsOneWidget);
    expect(findVisibleTextContaining('7/9 (목)'), findsOneWidget);
    expect(findVisibleTextContaining('7/10 이체'), findsOneWidget, reason: 'KST 03:30 이체는 KST 날짜');
    expect(findVisibleTextContaining('1주차 · 7/6 ~ 7/12'), findsOneWidget);
    expect(findVisibleTextContaining('잔여 80,000원'), findsOneWidget);
  });

  for (final (w, s) in [(320.0, 1.0), (320.0, 1.3), (320.0, 2.0), (392.0, 2.0)]) {
    testWidgets('P4 ${w.toInt()}·$s — 넘침 0 · 금액·잔여 보임', (t) async {
      final recs = [
        _att('a', _kstMid(2026, 12, 30), ws: 'transferred', transferDate: DateTime.utc(2026, 12, 31, 1), net: 1234560),
        _att('b', _kstMid(2026, 12, 31), net: 987650),
      ];
      await _pump(t, recs, width: w, scale: s);
      expect(_overflows(t), isEmpty);
      expect(findVisibleTextContaining('1,234,560원'), findsWidgets);
      expect(findVisibleTextContaining('잔여 987,650원'), findsOneWidget);
      expect(findVisibleTextContaining('12/31 (목)'), findsOneWidget);
    });
  }

  test('P5 소스 — 화면 안 subtract 주차 0 · KST 날짜 helper', () {
    final src = File('lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart').readAsStringSync();
    final scr = src.substring(src.indexOf('class _WorkerPayDetailScreenState'));
    expect(scr.contains('firstMonday'), isFalse);
    expect(scr.contains('anchor.subtract('), isFalse);
    expect(scr.contains('final d      = FormatHelper.toKstDate(r.workDate);'), isTrue);
    expect(scr.contains('FormatHelper.toKstDate(xferDate)'), isTrue);
    expect(scr.contains('FormatHelper.toKstDate(dueDate).month'), isTrue);
    expect(src.contains('PayslipPeriodHelper.weekOfWorkDate(first)'), isTrue);
  });
}
