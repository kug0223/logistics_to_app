// ignore_for_file: depend_on_referenced_packages
// [DU1 · 82_residual_corrections_1 §2] 급여 목록 휴게 칩 — 상태별 실제 위젯(LOCAL).
//   pending: 칩 편집 표시 + 탭 → 휴게 시트 / calculated: 편집 표시 없음 + 탭 → 명세(저장 base) / transferred: 편집 표시 없음.
//   DEV 쓰기 없음(Firestore 미응답 가짜 플랫폼).
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
import 'package:ALfit/utils/wage_calculator.dart';

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

AttendanceModel _att(String wageStatus) {
  final calc = wageStatus == AttendanceModel.wagePending
      ? null
      : WageCalculator.calculate(
              wageType: 'hourly', baseWage: 12000, workDate: kDate, scheduledStart: '09:00', scheduledEnd: '18:00',
              actualStart: '09:00', actualEnd: '18:00', breakMinutes: 60)
          .copyWith(calculatedAt: DateTime(2026, 9, 29, 19), calculatedBy: 'owner1', taxDeductionType: 'none');
  return AttendanceModel(
      id: 'att_wa1', applicationId: 'wa1', userId: 'wu1', businessId: kBiz, businessName: '강남 물류센터',
      workDate: kDate, workType: '상하차', status: AttendanceModel.statusPresent, wageStatus: wageStatus,
      adminConfirmed: true, checkInAt: DateTime(2026, 9, 29, 9), checkOutAt: DateTime(2026, 9, 29, 18),
      createdAt: kDate, wageDetail: calc);
}

Future<void> _pump(WidgetTester tester, String wageStatus) async {
  tester.view.physicalSize = const Size(392, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final w = _app();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _Owner(),
    child: MaterialApp(
      home: Scaffold(
        body: WageConfirmDialog(
          date: kDate, businessId: kBiz, businessName: '강남 물류센터', workers: [w],
          attendanceMap: {w.id: _att(wageStatus)},
          userMap: {'wu1': UserModel(uid: 'wu1', username: 'wu1', name: '김근로', email: 'wu1@test.local', role: UserRole.USER)},
          workDetailTimeMap: {'상하차_09:00_18:00': <String, dynamic>{'breakMinutes': 60, 'wage': 12000, 'wageType': 'hourly', 'requiredCount': 3, 'taxDeductionType': 'none'}},
        ),
      ),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _breakChipText() => find.byWidgetPredicate((w) =>
    // 행 칩 글자는 '무급휴게 …'로 시작한다(그룹 머리말 '추가 무급휴게 (석식·야식 등)'과 구분)
    w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').replaceAll('⁠', '').startsWith('무급휴게'));

Finder _chipEditIcon() => find.descendant(
    of: find.ancestor(of: _breakChipText().first, matching: find.byType(GestureDetector)).first,
    matching: find.byIcon(Icons.edit_outlined));

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.textContaining(label).first);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('pending — 칩 편집 표시가 있고 탭하면 휴게 시트가 열린다', (tester) async {
    await _pump(tester, AttendanceModel.wagePending);
    expect(_breakChipText(), findsWidgets);
    expect(_chipEditIcon(), findsOneWidget);
    await tester.tap(_breakChipText().first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('추가 무급휴게'), findsWidgets, reason: '휴게 조정 시트');
  });

  testWidgets('calculated — 편집 표시 없음, 칩을 눌러도 휴게 시트가 아니라 명세(저장 base)가 열린다', (tester) async {
    await _pump(tester, AttendanceModel.wageCalculated);
    await _openTab(tester, '확정내역');
    expect(_breakChipText(), findsWidgets);
    expect(_chipEditIcon(), findsNothing);
    await tester.tap(_breakChipText().first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('추가 무급휴게'), findsNothing, reason: '목록에서 휴게 미리보기를 다시 계산하지 않는다');
    expect(find.textContaining('급여 명세'), findsWidgets, reason: '정정은 명세 경로');
  });

  testWidgets('confirmed — 마감내역에 행은 있고 휴게 칩·편집 진입이 없다', (tester) async {
    await _pump(tester, AttendanceModel.wageConfirmed);
    await _openTab(tester, '마감내역');
    expect(findVisibleTextContaining('김근로'), findsWidgets, reason: '확정 행이 마감내역에 실제로 그려진다');
    // 실제 렌더: 마감 행은 휴게 칩 자체를 그리지 않는다(읽기 전용) — 존재 검사가 아니라 부재로 확인한다
    expect(_breakChipText(), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.textContaining('추가 무급휴게'), findsNothing, reason: '확정분은 목록에서 휴게를 다시 계산하지 않는다');
  });

  testWidgets('transferred — 마감내역에서 휴게 편집 진입이 없다', (tester) async {
    await _pump(tester, AttendanceModel.wageTransferred);
    await _openTab(tester, '마감내역');
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.textContaining('추가 무급휴게'), findsNothing);
  });
}
