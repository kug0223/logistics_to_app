// [.60] 보험료 금액 정합성 마감 — 확정 전 금액 대조·저장 버전·KST 연도·요율 확인 상태.
//
// 서버 후보(CWX·UPD)의 동작은 c60/ap60.js(실제 writer in-process)가 잰다. 여기서는 앱이
//   ① 확인한 금액·공제를 보내고(확정)·수정의 기준 버전을 보내는지(소스 계약 — 문자열 검사),
//   ② 보험료율 연도를 근무일의 KST 연도로 고르는지(동작),
//   ③ 요율을 확인하기 전·실패했을 때 표시 금액을 확정 금액처럼 보이지 않는지(동작)를 본다.
import 'dart:io';

import 'support/visible_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/wage_confirm_dialog.dart';
import 'package:ALfit/services/tax_deduction_service.dart';

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

const kBiz = 'biz1';
final kDate = DateTime(2026, 9, 29);

class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'owner1', username: 'owner1', name: '박사장', email: 'owner1@alfit.local',
        role: UserRole.BUSINESS_ADMIN, businessId: kBiz, createdAt: DateTime(2026, 1, 1));
}

ApplicationModel _app() => ApplicationModel(
      id: 'wa1', uid: 'wu1', toId: 'to1', slotId: 'slot1', businessId: kBiz, businessName: '강남 물류센터',
      toTitle: '단기 모집', selectedWorkType: '상하차', wdId: 'wd1', startTime: '09:00', endTime: '18:00',
      wage: 12000, wageType: 'hourly', status: 'CONFIRMED', workDate: kDate, appliedAt: DateTime(2026, 9, 27));

AttendanceModel _att() => AttendanceModel(
      id: 'att_wa1', applicationId: 'wa1', userId: 'wu1', businessId: kBiz, businessName: '강남 물류센터',
      workDate: kDate, workType: '상하차', status: AttendanceModel.statusPresent,
      wageStatus: AttendanceModel.wagePending, adminConfirmed: true,
      checkInAt: DateTime(2026, 9, 29, 9), checkOutAt: DateTime(2026, 9, 29, 18), createdAt: kDate);

Future<void> _pump(WidgetTester tester, {required Size size, required double textScale}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final w = _app();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _Owner(),
    child: MaterialApp(
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      home: Scaffold(
        body: WageConfirmDialog(
          date: kDate, businessId: kBiz, businessName: '강남 물류센터', workers: [w],
          attendanceMap: {w.id: _att()},
          userMap: {'wu1': UserModel(uid: 'wu1', username: 'wu1', name: '김근로', email: 'wu1@test.local', role: UserRole.USER)},
          workDetailTimeMap: {'상하차_09:00_18:00': <String, dynamic>{'breakMinutes': 60, 'wage': 12000, 'wageType': 'hourly', 'requiredCount': 3, 'taxDeductionType': 'four_insurance_fixed'}},
        ),
      ),
    ),
  ));
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  test('[A60-a] 보험료율 연도 = 근무일의 KST 연도 — GMT 기기의 KST 1월 1일', () {
    // KST 2027-01-01 00:00 = UTC 2026-12-31 15:00. GMT 기기에서 Timestamp.toDate() 가 주는 값과 같은 성분.
    final jan1KstOnGmt = DateTime.utc(2026, 12, 31, 15);
    expect(jan1KstOnGmt.year, 2026, reason: '예전 식(workDate.year) — GMT 기기에서 전년도 요율');
    expect(TaxDeductionService.kstWorkYear(jan1KstOnGmt), 2027);
    expect(TaxDeductionService.kstWorkYear(DateTime.utc(2026, 12, 31, 14, 59)), 2026);
  });

  for (final c in const [(Size(392, 844), 1.0), (Size(320, 640), 1.3), (Size(392, 844), 2.0)]) {
    testWidgets('[A60-b] 요율 확인 전 — 표시 금액이 확정 금액이 아니라고 말한다 ${c.$1.width.toInt()}·${c.$2}', (tester) async {
      await _pump(tester, size: c.$1, textScale: c.$2);
      // 시험 환경의 Firestore 는 응답하지 않는다 → 확인 중 상태가 유지된다.
      expect(findVisibleTextContaining('보험료율 확인 중'), findsOneWidget);
      expect(findVisibleTextContaining('표시 금액은 아직 확정 금액이 아닙니다'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('[A60-c] 확정·수정이 비교값을 보낸다 — 소스 계약(문자열 검사)', () {
    final src = File('lib/screens/business_admin/dialogs/wage_confirm_dialog.dart').readAsStringSync();
    expect("'expectedBreakdown': _expectedOf(calculatedWage),".allMatches(src).length, 2, reason: '일괄·개별 확정');
    expect(src.contains("'expectedCurrent': {"), isTrue, reason: '수정의 기준 버전');
    expect(src.contains("_processWageUpdate(app, attendance, result.wage, base: wage)"), isTrue);
    expect(src.contains("d['code'] == 'AMOUNT_CHANGED'"), isTrue);
    // [.82] 거절 코드 처리를 한 곳으로 모았다 — WAGE_CHANGED 와 서버 금액 검증(TOTAL_MISMATCH·COMPONENT_CHANGED)을 같이 다룬다.
    expect(src.contains("code == 'WAGE_CHANGED' || code == 'TOTAL_MISMATCH' || code == 'COMPONENT_CHANGED'"), isTrue);
    expect('workYear: TaxDeductionService.kstWorkYear(attendance.workDate)'.allMatches(src).length, 2);
    expect(src.contains('workYear: attendance.workDate.year'), isFalse);
  });
}
