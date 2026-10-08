// [R7-P4.4E.6A] 지원 확인 시트의 DEVICE 세로 넘침(9.7px) 재현.
//
// E6 에서 이 시트의 두 가설이 모두 소스 근거로 기각됐다 —
// `isScrollControlled` 는 이미 주고 있고, 삼중 하단 처리도 E5 에서 측정·기각됐다.
// 그래서 추측을 더 만들지 않고 **production parent 를 그대로 세워** 재현한다.
//
// 처음 만든 하네스는 평평한 `Scaffold` 에서 `ApplyConfirmDialog.show` 를
// 불렀고 16/16 셀 모두 넘침 0 이었다. 그건 production 이 아니다 —
// 실제로는 `ApplyWorkDialog` **자체가 이미 열린 바텀시트**이고
// (`apply_work_dialog.dart:108` `DialogHelper.showSheet`), 확인 시트는
// 그 시트의 context 에서 열리는 **시트 안의 시트**다.
// 여기서는 그 중첩을 그대로 만든다.
//
// 하네스 성질(재발명 금지, [[project-p22-apply-reach-blocked]]):
//   · 선결조건 게이트는 **실제 플랫폼 채널**을 타므로 `runAsync` 한 틱이 필요하다.
//   · 서류 게이트를 우회하지 않는다 — 요건을 실제로 충족한 fixture 를 쓴다.
//   · TO 근무일은 미래여야 한다(과거면 마감 안내가 카드를 덮는다).
//   · 확인 시트가 열리면 `지원하기` 가 2개 → `.last` 가 시트의 승인 버튼이다.
//
// 이 테스트가 고정하는 계약: 중첩 상태에서도 넘침 0 이고, 승인·취소 버튼이
// 둘 다 도달 가능하다. 동의 문구는 canonical 원문을 그대로 쓴다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/services/schedule_conflict_service.dart';
import 'package:ALfit/utils/dialog_helper.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_confirm_dialog.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_work_dialog.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_work_reads.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_work_submit.dart';

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k',
      appId: 'a',
      messagingSenderId: 's',
      projectId: 'p',
      storageBucket: 'b');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _LoggedIn extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        // 게이트를 우회하지 않는다 — 요건을 실제로 충족한 사용자를 쓴다.
        accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 2, 1),
        isIdVerified: true,
        idCardImagePath: 'users/u1/id.png',
        bankName: '국민은행',
        accountNumber: '1234',
        accountHolder: '김근로',
        bankbookImagePath: 'users/u1/bb.png',
        createdAt: DateTime(2026, 1, 1),
      );
}

final kWorkDate = DateTime(
  DateTime.now().year,
  DateTime.now().month,
  DateTime.now().day,
).add(const Duration(days: 5));

TOModel _to() => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '강남 물류센터',
      type: 'flex',
      title: '단기 모집',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 4,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      rangeStart: kWorkDate,
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

/// 긴 업무명·긴 사업장명을 쓴다 — 짧은 문자열로 통과시키면 의미가 없다.
WorkDetailData _work() => WorkDetailData(
      wdId: 'wd1',
      workType: '물류 상하차 보조',
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 12000,
      wageType: 'hourly',
      requiredCount: 4,
      startTime: '09:00',
      endTime: '18:00',
      breakMinutes: 60,
      order: 0,
    );

ApplyWorkReads _reads() => ApplyWorkReads(
      applicationsForTO: ({required String toId, required String uid}) async =>
          <ApplicationModel>[],
      confirmedSchedules:
          ({required String uid, required DateTime workDate}) async =>
              <ApplicationModel>[],
      conflictsForWorkDetails: (
              {required DateTime workDate,
              required List<WorkDetailData> workDetails}) async =>
          <String, ConflictInfo>{},
      myApplicationsForTOFresh: (toId) async => <ApplicationModel>[],
      // [R7-PAYROLL-POLICY.4D] 지원 시트가 근태·급여 기준을 읽는 경계.
      //   **정상 상태는 기준이 있는 사업장**이다 —  이후 기준 없는
      //   사업장에서는 신규 지원이 아예 막히므로, 지원 흐름을 보는 이
      //   테스트는 기준 있는 사업장을 써야 한다.
      businessForPolicy: (businessId) async => _policyBusiness(),
    );

ApplyWorkSubmit _submit() => ApplyWorkSubmit(
      apply: ({
        required String uid,
        required TOModel to,
        required WorkDetailData work,
        required DateTime workDate,
        // [R7-PAYROLL-POLICY.4C] 화면이 본 기준의 토큰.
        required String expectedAttendancePolicy,
        String? slotId,
        DateTime? workEndDate,
        DateTime? desiredStartDate,
      }) async =>
          ApplyResult.success(),
    );

/// 선결조건 게이트는 실제 플랫폼 채널을 탄다 — 진짜 async 를 한 틱 준다.
Future<void> _settle(WidgetTester tester, {int frames = 40}) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)));
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// production 과 동일하게 **시트 안의 시트**를 만든다.
/// 바깥 시트는 `ApplyWorkDialog.show` 가 쓰는 옵션(`isScrollControlled: true`)
/// 을 그대로 쓴다.
Future<void> _openNestedConfirm(
  WidgetTester tester, {
  required double w,
  required double h,
  required double scale,
  double safeBottom = 48,
}) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _LoggedIn(),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (c) => MediaQuery(
            data: MediaQuery.of(c).copyWith(
              textScaler: TextScaler.linear(scale),
              viewPadding: EdgeInsets.only(bottom: safeBottom),
              padding: EdgeInsets.only(bottom: safeBottom),
            ),
            child: Scaffold(
              body: Center(
                child: Builder(
                  builder: (inner) => ElevatedButton(
                    onPressed: () =>
                        DialogHelper.showSheet<ApplyDialogResult>(
                      inner,
                      isScrollControlled: true,
                      builder: (_) => ApplyWorkDialog(
                        mainTO: _to(),
                        workDetails: [_work()],
                        slotId: 'slot1',
                        businessName: '강남 물류센터 주식회사',
                        reads: _reads(),
                        submit: _submit(),
                      ),
                    ),
                    child: const Text('열기'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  // 바깥 시트 열기
  await tester.tap(find.text('열기'));
  await _settle(tester, frames: 24);

  // 업무 카드의 지원 버튼 → 확인 시트(시트 안의 시트)
  final btn = find.widgetWithText(InkWell, '지원');
  expect(btn, findsWidgets,
      reason: '업무 카드의 지원 버튼에 도달해야 한다 — 바깥 시트가 열리지 않았다');
  await tester.tap(btn.first);
  await _settle(tester, frames: 24);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
  });

  const cells = <List<double>>[
    [320, 640, 1.0],
    [360, 640, 1.0],
    [360, 800, 1.0],
    [411, 823, 1.0],
    [412, 915, 1.0],
    [360, 800, 1.3],
    [320, 640, 1.3],
    [360, 800, 2.0],
    [320, 640, 2.0],
  ];

  for (final c in cells) {
    final w = c[0], h = c[1], s = c[2];
    testWidgets(
        '확인 시트(중첩) ${w.toInt()}x${h.toInt()} 배율 $s — 넘침 0 + 두 CTA 도달',
        (tester) async {
      await _openNestedConfirm(tester, w: w, h: h, scale: s);

      expect(find.byType(ApplyConfirmDialog), findsOneWidget,
          reason: '확인 시트가 열리지 않았다 — 측정 대상에 도달하지 못했다');

      expect(tester.takeException(), isNull,
          reason: '${w.toInt()}x${h.toInt()} 배율 $s 에서 넘쳤다');

      // 승인·취소 두 CTA 가 모두 도달 가능해야 한다.
      // 확인 시트가 열리면 '지원하기' 가 2개 — 시트의 승인 버튼은 마지막이다.
      final ok = find.text('지원하기');
      expect(ok, findsWidgets, reason: '승인 버튼이 없다');
      await tester.ensureVisible(ok.last);
      await tester.pump();

      final cancel = find.text('취소');
      expect(cancel, findsWidgets, reason: '취소 버튼이 없다');
      await tester.ensureVisible(cancel.last);
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: 'CTA 를 끌어오는 과정에서 넘쳤다');

      // 타이머를 흘려보낸다 — 남기면 pending 으로 깨진다.
      await tester.pump(const Duration(seconds: 5));
    });
  }

  // 재현 과정에서 드러난 것은 확인 시트가 아니라 **바깥 업무 선택 카드**였다.
  //   `work_selection_card.dart` 의 메타데이터는 `Wrap` 안에 경직된
  //   `Row(mainAxisSize: min)` 조각을 넣고 있었고, Wrap 은 자식에게
  //   maxWidth: Infinity 를 주므로 조각이 줄어들 수 없었다.
  //   320dp 가용 226.9px 에 시간 조각이 242.3px 를 요구해 12px 넘쳤다.
  // 그 카드를 직접 지킨다 — 근무시간·급여·인원이 전부 남아야 한다.
  for (final s in <double>[1.0, 1.3, 2.0]) {
    testWidgets('업무 선택 카드 320dp 배율 $s — 넘침 0 + 조건 전부 보임',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<UserProvider>(
          create: (_) => _LoggedIn(),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: Builder(
              builder: (c) => MediaQuery(
                data: MediaQuery.of(c).copyWith(
                  textScaler: TextScaler.linear(s),
                  viewPadding: const EdgeInsets.only(bottom: 48),
                  padding: const EdgeInsets.only(bottom: 48),
                ),
                child: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (inner) => ElevatedButton(
                        onPressed: () =>
                            DialogHelper.showSheet<ApplyDialogResult>(
                          inner,
                          isScrollControlled: true,
                          builder: (_) => ApplyWorkDialog(
                            mainTO: _to(),
                            workDetails: [_work()],
                            slotId: 'slot1',
                            businessName: '강남 물류센터 주식회사',
                            reads: _reads(),
                            submit: _submit(),
                          ),
                        ),
                        child: const Text('열기'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('열기'));
      await _settle(tester, frames: 24);

      expect(tester.takeException(), isNull,
          reason: '업무 선택 카드가 320dp 배율 $s 에서 넘쳤다');

      // 근무조건이 전부 남아야 한다 — 좁다고 숨기지 않는다.
      expect(find.textContaining('09:00'), findsWidgets,
          reason: '근무시간이 사라졌다');
      expect(find.textContaining('12,000'), findsWidgets,
          reason: '급여가 사라졌다');
      expect(find.textContaining('모집'), findsWidgets,
          reason: '모집 인원이 사라졌다');

      await tester.pump(const Duration(seconds: 5));
    });
  }
}

/// [R7-PAYROLL-POLICY.4D] 기준이 있는 사업장 — 지원이 가능한 정상 상태.
///   값은 ALfit 기본값이고, 이 테스트의 관심은 기준 숫자가 아니다.
BusinessModel _policyBusiness() => BusinessModel(
      id: 'b1',
      businessNumber: '1234567890',
      name: '사업장',
      category: 'c',
      subCategory: 's',
      address: '주소',
      ownerId: 'owner',
      createdAt: DateTime(2026, 1, 1),
      attendanceRules: AttendanceRules.defaults(),
    );
