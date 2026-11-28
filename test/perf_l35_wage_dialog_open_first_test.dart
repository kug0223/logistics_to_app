import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/services/tax_deduction_service.dart';
import 'package:ALfit/utils/wage_calculator.dart';
import 'package:ALfit/widgets/dialogs/wage/wage_detail_dialog.dart';
import 'support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

// [L35 · impl_7] 일정 카드 급여 명세 — 이름 두 개를 기다리지 않고 바로 연다(이름은 안에서 채움).
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

final kDate = DateTime(2026, 11, 3);
WageDetailModel _wage() => TaxDeductionService.applyDeduction(
    base: WageCalculator.calculate(
        wageType: 'hourly', baseWage: 25000, workDate: kDate, scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00', breakMinutes: 60),
    taxDeductionType: InsuranceRateModel.typeNone,
    workYear: 2026);
ApplicationModel _app() => ApplicationModel(
      id: 'wa1', uid: 'wu1', toId: 'to1', slotId: 'slot1', businessId: 'biz1', businessName: '강남 물류센터',
      toTitle: '단기 모집', selectedWorkType: '상하차', wdId: 'wd1', startTime: '09:00', endTime: '18:00',
      wage: 25000, wageType: 'hourly', status: 'CONFIRMED', workDate: kDate, appliedAt: DateTime(2026, 11, 1));
AttendanceModel _att() => AttendanceModel(
      id: 'att_wa1', applicationId: 'wa1', userId: 'wu1', businessId: 'biz1', businessName: '강남 물류센터',
      workDate: kDate, workType: '상하차', status: AttendanceModel.statusPresent,
      wageStatus: AttendanceModel.wageConfirmed, adminConfirmed: true, wageDetail: _wage(),
      checkInAt: DateTime(2026, 11, 3, 9), checkOutAt: DateTime(2026, 11, 3, 18), createdAt: kDate);
UserModel _user() => UserModel(uid: 'wu1', username: 'wu1', name: '김근로', email: 'wu1@alfit.local',
    role: UserRole.USER, accountStatus: 'active');

Future<void> _pump(WidgetTester t, {Future<UserModel?>? user, Future<String?>? biz}) async {
  t.view.physicalSize = const Size(392, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: WageDetailDialog(app: _app(), user: null, attendance: _att(), wage: _wage(),
          mode: WageDialogMode.confirmed, userLoader: user, businessNameLoader: biz),
    ),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

OutlinedButton _payslip(WidgetTester t) => t.widget<OutlinedButton>(
    find.ancestor(of: findVisibleText('임금명세서 보기'), matching: find.byWidgetPredicate((w) => w is OutlinedButton)));

String _all(WidgetTester t) => t
    .widgetList<RichText>(find.byType(RichText))
    .map((r) => r.text.toPlainText().replaceAll('\u2060', ''))
    .join('\n');

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('L35-1 이름을 읽는 동안에도 다이얼로그·금액이 바로 보이고, 명세서 버튼은 이름을 읽은 뒤 열린다', (t) async {
    final u = Completer<UserModel?>();
    final b = Completer<String?>();
    await _pump(t, user: u.future, biz: b.future);
    expect(find.byType(WageDetailDialog), findsOneWidget);
    expect(_all(t), contains('…'), reason: '이름 자리 = 읽는 중');
    expect(_payslip(t).onPressed, isNull, reason: '명세서(근로자 정보 사용)는 이름을 읽은 뒤');
    u.complete(_user());
    b.complete('강남 물류센터');
    await t.pump(const Duration(milliseconds: 50));
    expect(_all(t), contains('김근로'));
    expect(_all(t), contains('강남 물류센터'));
    expect(_payslip(t).onPressed, isNotNull);
  });

  testWidgets('L35-2 이름 읽기 실패 — 다이얼로그는 그대로 · 예전 기본 표기(이름 없음) · 버튼 활성', (t) async {
    final u = Completer<UserModel?>();
    await _pump(t, user: u.future, biz: Future<String?>.value(null));
    u.completeError(StateError('offline'));
    await t.pump(const Duration(milliseconds: 50));
    expect(_all(t), contains('이름 없음'));
    expect(_payslip(t).onPressed, isNotNull);
  });

  test('L35-3 일정 카드는 이름 두 개를 기다린 뒤 여는 순서가 아니다(원문)', () {
    final src = File('lib/widgets/calendar/schedule_card.dart').readAsStringSync();
    final i = src.indexOf('Future<void> _showWageDetailDialog(');
    final body = src.substring(i, src.indexOf('\n  }\n', i));
    expect(body.contains('await firestoreService.getUser('), isFalse);
    expect(body.contains('await firestoreService.getBusinessById('), isFalse);
    expect(body.contains('userLoader: firestoreService.getUser(application.uid)'), isTrue);
  });
}
