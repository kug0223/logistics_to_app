// [.82-4] 급여 정정 '가 수정안' 앱 측 — daily_auto_8 금액 잠금(렌더), F2 재조회 경로, F3 문구, 새 거절 코드 처리(소스 계약).
//   서버 계약(D8_AMOUNT_LOCKED·D8_MONTH_DEPENDENCY·PREVIEW_MISMATCH 등)은 c82/ap82-4.js 에뮬레이터 시험이 잰다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/services/tax_deduction_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/wage_calculator.dart';
import 'package:ALfit/widgets/dialogs/wage/wage_detail_dialog.dart';

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

final kDate = DateTime(2026, 11, 3);

ApplicationModel _app() => ApplicationModel(
      id: 'wa1', uid: 'wu1', toId: 'to1', slotId: 'slot1', businessId: 'biz1', businessName: '강남 물류센터',
      toTitle: '단기 모집', selectedWorkType: '상하차', wdId: 'wd1', startTime: '09:00', endTime: '18:00',
      wage: 25000, wageType: 'hourly', status: 'CONFIRMED', workDate: kDate, appliedAt: DateTime(2026, 11, 1));

AttendanceModel _att() => AttendanceModel(
      id: 'att_wa1', applicationId: 'wa1', userId: 'wu1', businessId: 'biz1', businessName: '강남 물류센터',
      workDate: kDate, workType: '상하차', status: AttendanceModel.statusPresent,
      wageStatus: AttendanceModel.wageCalculated, adminConfirmed: true,
      checkInAt: DateTime(2026, 11, 3, 9), checkOutAt: DateTime(2026, 11, 3, 18), createdAt: kDate);

WageDetailModel _stored(String type) => TaxDeductionService.applyDeduction(
    base: WageCalculator.calculate(
        wageType: 'hourly', baseWage: 25000, workDate: kDate, scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00', breakMinutes: 60),
    taxDeductionType: type,
    workYear: 2026);

/// 넘침은 따로 모아 기록한다(이 시험의 판정 대상 아님 — 기존 공제 행 등, 보고서 OPEN 항목). 다른 오류는 그대로 실패시킨다.
final overflowLog = <String>[];

Future<void> _pump(WidgetTester tester, String type,
    {double textScale = 1.0, Size size = const Size(392, 844), WageDialogMode mode = WageDialogMode.calculated}) async {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final msg = d.exceptionAsString();
    if (msg.contains('overflowed')) {
      final loc = RegExp(r'[a-z_]+.dart:d+').firstMatch((d.informationCollector?.call() ?? const <DiagnosticsNode>[]).map((e) => e.toString()).join(' '))?.group(0);
      overflowLog.add('$type ${size.width.toInt()}@$textScale $msg $loc');
    } else {
      prev?.call(d);
    }
  };
  addTearDown(() => FlutterError.onError = prev);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    // 앱 UI 는 fontFamily 미지정(기기 기본 한글 폰트) — 측정은 번들 NotoSansKR 로 근사한다.
    theme: RoleTheme.businessAdminTheme.copyWith(
        textTheme: RoleTheme.businessAdminTheme.textTheme.apply(fontFamily: 'NotoSansKR')),
    builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
    home: Scaffold(
      body: WageDetailDialog(
          app: _app(), user: null, attendance: _att(), wage: _stored(type), mode: mode),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

// 독립 기대 실수령액(2026 기본 요율: 고용 0.9 · 일용 비과세 150,000 · 2.7% · 지방 10% · 사업 3%)
int _net33(int g) { final i = (g * 3 / 100).round(); return g - i - (i * 10 / 100).round(); }
int _netD8lt8(int g) { final t = g - 150000 > 0 ? g - 150000 : 0; final i = t > 0 ? (t * 2.7 / 100).round() : 0;
  return g - (g * 0.9 / 100).round() - i - (i > 0 ? (i * 10 / 100).round() : 0); }

List<TextField> _amountFields(WidgetTester tester) =>
    tester.widgetList<TextField>(find.byType(TextField)).where((f) => f.keyboardType == TextInputType.number).toList();

void main() {
  tearDownAll(() {
    for (final l in overflowLog) {
      // ignore: avoid_print
      print('OVERFLOW $l');
    }
  });
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    // 시험 기본 폰트는 한글이 실제보다 넓다 — 번들 NotoSansKR 로 잰다(e2_render_regression_test 와 같은 방식).
    final f = File('assets/fonts/NotoSansKR-Regular.ttf');
    if (f.existsSync()) {
      final loader = FontLoader('NotoSansKR')..addFont(f.readAsBytes().then((b) => ByteData.view(b.buffer)));
      await loader.load();
    }
  });

  for (final c in const [(Size(392, 844), 1.0), (Size(320, 640), 1.3), (Size(392, 844), 2.0)]) {
    testWidgets('[82-4-a] daily_auto_8 계산분 — 금액 입력 잠금 + 메모만 안내 ${c.$1.width.toInt()}·${c.$2}', (tester) async {
      await _pump(tester, InsuranceRateModel.typeDailyAuto8, size: c.$1, textScale: c.$2);
      final fields = _amountFields(tester);
      expect(fields.length, 2);
      expect(fields.every((f) => f.enabled == false), isTrue, reason: '추가수당·추가공제 입력 비활성');
      expect(findVisibleTextContaining('메모만 수정할 수 있어요'), findsOneWidget);
      expect(findVisibleTextContaining('취소 후'), findsNothing, reason: '취소 후 재계산을 대안으로 안내하지 않는다');
      expect(find.byIcon(Icons.edit_outlined), findsNothing, reason: '휴게 수정 진입 숨김');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('[82-4-b] 3.3% 계산분 — 금액 입력 그대로 열림, 안내 없음', (tester) async {
    await _pump(tester, InsuranceRateModel.typeFreelancer33);
    final fields = _amountFields(tester);
    expect(fields.length, 2);
    expect(fields.every((f) => f.enabled != false), isTrue);
    expect(findVisibleTextContaining('메모만 수정할 수 있어요'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // [.82-5] 미확정(pending) D8 — 계산 확정 전 입력은 살아 있어야 한다(82_audit_05 회귀). 정정 잠금과 범위를 나눈다.
  testWidgets('[82-5-a] pending daily_auto_8 — 입력 활성·휴게 수정 진입·추가수당이 미리보기 총액에 반영', (tester) async {
    await _pump(tester, InsuranceRateModel.typeDailyAuto8, mode: WageDialogMode.pending);
    final fields = _amountFields(tester);
    expect(fields.every((f) => f.enabled != false), isTrue);
    expect(findVisibleTextContaining('메모만 수정할 수 있어요'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsWidgets, reason: '휴게 수정 진입');
    final before = _stored(InsuranceRateModel.typeDailyAuto8).totalAmount;
    await tester.enterText(find.byWidget(fields.first), '1000');
    await tester.pump();
    // 화면은 세전 총액을 한 줄로 보이지 않는다(기본·추가 줄 + 실수령) — 추가 줄과 재계산된 실수령으로 본다.
    expect(findVisibleTextContaining(FormatHelper.formatWage(1000)), findsWidgets, reason: '추가수당 줄');
    expect(findVisibleTextContaining(FormatHelper.formatWage(_netD8lt8(before + 1000))), findsWidgets, reason: '입력이 버려지지 않는다');
  });

  testWidgets('[82-5-b] calculated 3.3% — 추가수당이 미리보기 총액에 반영(비D8 정상 편집)', (tester) async {
    await _pump(tester, InsuranceRateModel.typeFreelancer33);
    final before = _stored(InsuranceRateModel.typeFreelancer33).totalAmount;
    await tester.enterText(find.byWidget(_amountFields(tester).first), '1000');
    await tester.pump();
    expect(findVisibleTextContaining(FormatHelper.formatWage(_net33(before + 1000))), findsWidgets);
  });

  testWidgets('[82-5-c] calculated daily_auto_8 — 잠긴 입력은 총액을 바꾸지 않는다', (tester) async {
    await _pump(tester, InsuranceRateModel.typeDailyAuto8);
    final before = _stored(InsuranceRateModel.typeDailyAuto8).totalAmount;
    await tester.enterText(find.byWidget(_amountFields(tester).first), '1000');
    await tester.pump();
    expect(findVisibleTextContaining(FormatHelper.formatWage(_stored(InsuranceRateModel.typeDailyAuto8).netWage)), findsWidgets);
    expect(findVisibleTextContaining(FormatHelper.formatWage(_netD8lt8(before + 1000))), findsNothing);
  });

  test('[82-4-c] F2 — 저장본 재조회는 관리자 callable(사업장·근로자·KST 하루, 정확 id), 직접 GET 없음', () {
    final src = File('lib/screens/business_admin/dialogs/wage_confirm_dialog.dart').readAsStringSync();
    final start = src.indexOf('Future<bool> _reloadSavedWage(');
    final end = src.indexOf('Future<void> _showWageDetailDialog(', start);
    expect(start, greaterThan(0));
    final body = src.substring(start, end);
    expect(body.contains("httpsCallable('callableGetAdminAttendances'"), isTrue);
    expect(body.contains("'userId': cur.userId"), isTrue);
    expect(body.contains("'startMs': startMs"), isTrue);
    expect(body.contains('if (id != attId) continue;'), isTrue);
    expect(body.contains("collection('attendance')"), isFalse, reason: '규칙상 관리자 직접 GET 은 거절된다');
    expect(body.contains('!saved.isCalculated) return false'), isTrue, reason: '금액 없는 명세면 보호 유지');
  });

  test('[82-4-d] 미리보기 불일치·취소된 급여는 이 창 값을 믿지 않는다(소스 계약)', () {
    final src = File('lib/screens/business_admin/dialogs/wage_confirm_dialog.dart').readAsStringSync();
    expect(src.contains("code == 'PREVIEW_MISMATCH' || code == 'NOT_CALCULATED'"), isTrue);
  });

  test('[82-4-e] F3 — 실제 상태(확인 필요)로 말한다', () {
    final src = File('lib/utils/transfer_export_plan.dart').readAsStringSync();
    expect('사업장의 통장사본 확인이 필요해요. 사업장이 요청하면 다시 등록해주세요.'.allMatches(src).length, 2);
    expect(src.contains('확인하고 있어요'), isFalse);
  });
}
