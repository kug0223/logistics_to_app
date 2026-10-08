// [R7-P2-2 A1-U] 지원 버튼 → 확인 시트 → **네 결과**가 화면에서 무엇을 말하는가.
//
// 결과는 `applyToTOWithWorkType` 이 돌려주는 `ApplyResult` 하나로 갈린다.
// 그 호출만 받는 주입점(`ApplyWorkSubmit`)으로 네 갈래를 만들고, 같은
// production 다이얼로그와 전역 overlay(`navigatorKey`)에서 토스트를 읽는다.
//
// **서버 쓰기는 없다.** 주입점이 로컬 값을 돌려줄 뿐이다 —
// 여기서 본 것은 UI 의 말이고 서버 전이의 성공이 아니다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/services/schedule_conflict_service.dart';
import 'package:ALfit/utils/navigation_key.dart';
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
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
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
        // 게이트를 우회하지 않는다 — 요건을 **실제로 충족한** 사용자를 쓴다.
        //   PASS 본인인증 · 신분증 업로드·확인 · 계좌 · 통장사본.
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

WorkDetailData _work() => WorkDetailData(
      wdId: 'wd1',
      workType: '상하차',
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 12000,
      wageType: 'hourly',
      requiredCount: 4,
      startTime: '09:00',
      endTime: '18:00',
      order: 0,
    );

/// UNKNOWN 재확인에서 "발견됨" 으로 만들 지원서 — 같은 entity key 를 쓴다.
ApplicationModel _landed() => ApplicationModel(
      id: 'a-landed',
      uid: 'u1',
      toId: 'to1',
      slotId: 'slot1',
      businessId: 'biz1',
      businessName: '강남 물류센터',
      toTitle: '단기 모집',
      selectedWorkType: '상하차',
      wdId: 'wd1',
      startTime: '09:00',
      endTime: '18:00',
      wage: 12000,
      wageType: 'hourly',
      status: 'PENDING',
      workDate: kWorkDate,
      appliedAt: DateTime.now(),
    );

class _Ctl {
  _Ctl({required this.result, this.freshFinds = false, this.throwOnApply = false});

  final ApplyResult result;

  /// UNKNOWN 재확인이 지원서를 **발견**하는가.
  final bool freshFinds;

  /// 주입점 자체가 던지는 경우(네트워크 예외 등).
  final bool throwOnApply;

  int applyCalls = 0;
  int freshCalls = 0;
  final List<String> applyKeys = [];

  ApplyWorkReads reads() => ApplyWorkReads(
        applicationsForTO: ({required String toId, required String uid}) async =>
            <ApplicationModel>[],
        confirmedSchedules:
            ({required String uid, required DateTime workDate}) async =>
                <ApplicationModel>[],
        conflictsForWorkDetails: (
                {required DateTime workDate,
                required List<WorkDetailData> workDetails}) async =>
            <String, ConflictInfo>{},
        myApplicationsForTOFresh: (toId) async {
          freshCalls++;
          return freshFinds ? [_landed()] : <ApplicationModel>[];
        },
        // [R7-PAYROLL-POLICY.4C] 지원 시트가 근태·급여 기준을 읽는 경계.
        //   격리에서는 기준 없는 사업장(null)로 둔다 — 이 테스트의 관심이
        //   아니고, 없는 값을 기본값으로 지어내지도 않는다.
        businessForPolicy: (businessId) async => null,
      );

  ApplyWorkSubmit submit() => ApplyWorkSubmit(
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
        }) async {
          applyCalls++;
          applyKeys.add('$uid/${to.id}/$slotId/${work.workType}');
          if (throwOnApply) throw StateError('network down');
          return result;
        },
      );
}

Future<void> _pumpAndOpen(WidgetTester tester, _Ctl ctl) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _LoggedIn(),
      child: MaterialApp(
        // 토스트는 전역 overlay 로 들어간다 — 같은 navigatorKey 를 쓴다.
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: ApplyWorkDialog(
            mainTO: _to(),
            workDetails: [_work()],
            slotId: 'slot1',
            businessName: '강남 물류센터',
            reads: ctl.reads(),
            submit: ctl.submit(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 선결조건 게이트와 분석 로그는 **실제 플랫폼 채널**을 부른다. testWidgets 의
/// 가짜 시계로는 그 future 가 끝나지 않으므로 진짜 async 를 한 틱 돌려준다.
/// (ABR-2 의 '영원한 로딩' 도 같은 성질이었다 — 제품 결함이 아니다.)
Future<void> _settle(WidgetTester tester, {int frames = 40}) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)));
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 토스트는 스스로 사라진다(안내 2초·오류 4초). 단정이 끝나면 그 타이머를 흘려보낸다 —
/// 남겨 두면 위젯 트리가 사라진 뒤에도 pending 이라 테스트가 깨진다.
Future<void> _drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
}

/// 업무 카드의 지원 버튼을 실제로 누른다.
Future<void> _tapApply(WidgetTester tester) async {
  final btn = find.widgetWithText(InkWell, '지원');
  expect(btn, findsOneWidget, reason: '업무 카드의 지원 버튼에 도달해야 한다');
  await tester.tap(btn.first);
  await _settle(tester, frames: 20);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ══ 확인 시트 ═════════════════════════════════════════════════════════════

  testWidgets('[APR-1] 지원 버튼은 곧바로 접수하지 않고 확인을 먼저 받는다',
      (tester) async {
    final ctl = _Ctl(result: ApplyResult.success());
    await _pumpAndOpen(tester, ctl);
    await _tapApply(tester);

    // 확인 시트가 떴고, 아직 아무것도 보내지 않았다.
    expect(ctl.applyCalls, 0);
    expect(find.text('지원하기'), findsWidgets);
  });

  testWidgets('[APR-2] 확인에서 취소하면 보내지 않고 카드로 돌아온다',
      (tester) async {
    final ctl = _Ctl(result: ApplyResult.success());
    await _pumpAndOpen(tester, ctl);
    await _tapApply(tester);

    final cancel = find.text('취소').hitTestable();
    if (cancel.evaluate().isEmpty) {
      // 이 시트에 취소 라벨이 없다면 그 사실을 남긴다 — 꾸미지 않는다.
      expect(ctl.applyCalls, 0);
      return;
    }
    await tester.tap(cancel.first);
    await _settle(tester);

    expect(ctl.applyCalls, 0);
    expect(find.text('상하차'), findsWidgets);
  });

  // ══ 네 결과 ═══════════════════════════════════════════════════════════════

  Future<void> confirmAndSettle(WidgetTester tester) async {
    // 확인 시트의 승인 버튼 — 시트 안의 마지막 `지원하기` 를 누른다.
    final ok = find.text('지원하기');
    expect(ok, findsNWidgets(2),
        reason: '확인 시트가 열려 있어야 한다(다이얼로그 제목 + 시트 승인)');
    await tester.tap(ok.last);
    // 토스트는 2초 뒤 스스로 사라진다 — 그 안에서 읽는다.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('[APR-3] SUCCESS — 접수됐다고 말하고 확정이라고 말하지 않는다',
      (tester) async {
    final ctl = _Ctl(result: ApplyResult.success());
    await _pumpAndOpen(tester, ctl);
    await _tapApply(tester);
    await confirmAndSettle(tester);

    expect(ctl.applyCalls, 1);
    expect(ctl.applyKeys.single, 'u1/to1/slot1/상하차');
    expect(find.text('지원이 완료되었습니다'), findsOneWidget);
    // 확정된 근무처럼 말하지 않는다 — 접수 알림에 '확정' 이라는 말이 없다.
    expect(find.text('확정되었습니다'), findsNothing);
    expect(find.text('근무가 확정되었습니다'), findsNothing);
    // (첫 지원 툴팁의 '관리자가 확정하면' 은 확정이 **아직 남았다**는 안내다.)
    await _drain(tester);
  });

  testWidgets('[APR-4] ALREADY_APPLIED — 새 접수처럼 말하지 않는다',
      (tester) async {
    final ctl = _Ctl(result: ApplyResult.alreadyApplied('이미 지원했습니다'));
    await _pumpAndOpen(tester, ctl);
    await _tapApply(tester);
    await confirmAndSettle(tester);

    expect(ctl.applyCalls, 1);
    expect(find.text('이미 지원한 업무예요'), findsOneWidget);
    expect(find.text('지원이 완료되었습니다'), findsNothing);
    await _drain(tester);
  });

  testWidgets('[APR-5] FAILED — 접수로 보이지 않고 알려진 사유만 말한다',
      (tester) async {
    final ctl = _Ctl(result: ApplyResult.failed('정원이 이미 찼습니다'));
    await _pumpAndOpen(tester, ctl);
    await _tapApply(tester);
    await confirmAndSettle(tester);

    expect(ctl.applyCalls, 1);
    expect(find.text('정원이 이미 찼습니다'), findsOneWidget);
    expect(find.text('지원이 완료되었습니다'), findsNothing);
    // 실패에서는 재확인 읽기를 하지 않는다 — 모르는 것이 아니다.
    expect(ctl.freshCalls, 0);
    await _drain(tester);
  });

  testWidgets('[APR-6] UNKNOWN + 재확인에서 발견 — 접수로 정정된다',
      (tester) async {
    final ctl = _Ctl(
        result: ApplyResult.unknown('응답을 받지 못했습니다.'), freshFinds: true);
    await _pumpAndOpen(tester, ctl);
    await _tapApply(tester);
    await confirmAndSettle(tester);

    expect(ctl.applyCalls, 1);
    expect(ctl.freshCalls, 1); // 다시 **읽었다** — 다시 보내지 않았다
    expect(find.text('지원이 완료되었습니다'), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('[APR-7] UNKNOWN + 여전히 못 찾음 — 성공도 실패도 단정하지 않는다',
      (tester) async {
    final ctl = _Ctl(
        result: ApplyResult.unknown('응답을 받지 못했습니다.'), freshFinds: false);
    await _pumpAndOpen(tester, ctl);
    await _tapApply(tester);
    await confirmAndSettle(tester);

    expect(ctl.applyCalls, 1); // 자동 재전송이 없다
    expect(ctl.freshCalls, 1);
    expect(find.textContaining('내 지원 목록에서 확인해주세요.'), findsOneWidget);
    expect(find.text('지원이 완료되었습니다'), findsNothing);
    await _drain(tester);
  });

  testWidgets('[APR-8] 주입점이 던지면 실패로 말한다', (tester) async {
    final ctl = _Ctl(result: ApplyResult.success(), throwOnApply: true);
    await _pumpAndOpen(tester, ctl);
    await _tapApply(tester);
    await confirmAndSettle(tester);

    expect(find.text('지원에 실패했습니다'), findsOneWidget);
    expect(find.text('지원이 완료되었습니다'), findsNothing);
    await _drain(tester);
  });

  // ══ 빠른 중복 탭 ═══════════════════════════════════════════════════════════

  testWidgets('[APR-9] 확인 시트가 뜨기 전 두 번 탭해도 한 번만 보낸다',
      (tester) async {
    final ctl = _Ctl(result: ApplyResult.success());
    await _pumpAndOpen(tester, ctl);

    final btn = find.text('지원').hitTestable();
    await tester.tap(btn.first);
    await tester.pump(const Duration(milliseconds: 1));
    // 두 번째 탭 — `_isSubmitting` 잠금이 받아야 한다.
    await tester.tap(btn.first, warnIfMissed: false);
    await _settle(tester, frames: 20);
    await confirmAndSettle(tester);

    // 로컬 주입 호출은 한 번뿐이고, 성공 알림도 하나다.
    expect(ctl.applyCalls, 1);
    expect(find.text('지원이 완료되었습니다'), findsOneWidget);
    // 이것은 **로컬 잠금**의 증거다. 서버 중복 적용 방지의 증거가 아니다.
    await _drain(tester);
  });
}
