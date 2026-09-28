// [R7-P3-2 P32-H] **같은 사건 키**를 관리자 화면과 지원자 화면에서 동시에 읽는다.
//
// 키: businessId `biz1` · toId `to1` · slotId `slot1` · wdId `wd1` ·
//     날짜 2026-09-29 · 업무 `홀서빙` 09:00~18:00.
// 비슷한 제목의 서로 다른 fixture 를 나란히 두는 것이 아니라, **한 벌의 상수**를
// 양쪽 경계에 그대로 먹인다.
//
// 실제 발송·수락·확정은 **하지 않는다** — 읽기 경계에만 값을 준다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_reads.dart';
import 'package:ALfit/screens/user/my_applications_reads.dart';
import 'package:ALfit/screens/user/my_applications_screen.dart';

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

// ── 한 벌의 사건 키 ─────────────────────────────────────────────────────────
const kBiz = 'biz1';
const kBizName = '강남 물류센터';
const kToId = 'to1';
const kSlotId = 'slot1';
const kWdId = 'wd1';
const kWorkType = '홀서빙';
const kStart = '09:00';
const kEnd = '18:00';
// [R7-P1-2 후속] 원래 `DateTime(2026, 9, 29)` 로 못박아 두었는데, 그날이 오늘이
//   되자 IHK-4 의 '출근 예정' 분기를 벗어나 깨졌다(제품 결함이 아니라 시한부
//   fixture 였다). 이 사건 키에 필요한 것은 **아직 오지 않은 근무일**이다.
final kDate = DateTime(
  DateTime.now().year,
  DateTime.now().month,
  DateTime.now().day,
).add(const Duration(days: 3));
final kInvitedAt = kDate.subtract(const Duration(days: 2));

class _Worker extends UserProvider {
  _Worker(this.uid, {this.ready = true});
  final String uid;
  final bool ready;
  @override
  UserModel? get currentUser => UserModel(
        uid: uid,
        username: uid,
        name: '김근로',
        email: '$uid@alfit.local',
        role: UserRole.USER,
        accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 2, 1),
        isIdVerified: ready,
        idCardImagePath: ready ? 'users/u1/id.png' : null,
        bankName: ready ? '국민은행' : null,
        accountNumber: ready ? '1234' : null,
        bankbookImagePath: ready ? 'users/u1/bb.png' : null,
        createdAt: DateTime(2026, 1, 1),
      );
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get permissionsLoaded => true;
}

class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'owner1',
        username: 'owner1',
        name: '박사장',
        email: 'owner1@alfit.local',
        role: UserRole.BUSINESS_ADMIN,
        businessId: kBiz,
        createdAt: DateTime(2026, 1, 1),
      );
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
  // `can`/`canForBusiness` 는 provider 의 private `_currentUser` 를 읽으므로
  // getter override 만으로는 켜지지 않는다. 오너는 전권이라는 계약 그대로 둔다.
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      true;
}

BusinessModel _business() => BusinessModel(
      id: kBiz,
      name: kBizName,
      businessNumber: '000-00-00000',
      category: '음식점',
      subCategory: '한식',
      address: '서울특별시 강남구 테헤란로 1',
      ownerId: 'owner1',
      createdAt: DateTime(2026, 9, 1),
    );

/// 같은 키를 쓰는 지원서 — 상태와 `invitedAt` 만 바꾼다.
ApplicationModel _app({
  required String id,
  required String uid,
  required String status,
  DateTime? invitedAt,
  InviteCapacityState capacity = InviteCapacityState.unknown,
}) =>
    ApplicationModel(
      id: id,
      uid: uid,
      toId: kToId,
      slotId: kSlotId,
      businessId: kBiz,
      businessName: kBizName,
      toTitle: '단기 모집',
      selectedWorkType: kWorkType,
      wdId: kWdId,
      startTime: kStart,
      endTime: kEnd,
      wage: 12000,
      wageType: 'hourly',
      status: status,
      workDate: kDate,
      appliedAt: kDate,
      invitedAt: invitedAt,
      workInstanceCapacityState: capacity,
    );

TOModel _to() => TOModel(
      id: kToId,
      businessId: kBiz,
      businessName: kBizName,
      type: 'flex',
      title: '단기 모집',
      creatorUID: 'owner1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 3,
      totalConfirmed: 1,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

DayStaffingRow _row() => DayStaffingRow(
      toId: kToId,
      toTitle: '단기 모집',
      slotId: kSlotId,
      wdId: kWdId,
      workType: kWorkType,
      startTime: kStart,
      endTime: kEnd,
      requiredCount: 3,
      confirmedCount: 1,
      pendingCount: 0,
    );

// ── 관리자 쪽 ───────────────────────────────────────────────────────────────

DayApplicantsReads _adminReads({
  required List<ApplicationModel> confirmed,
  required List<ApplicationModel> invitations,
}) =>
    DayApplicantsReads(
      pendingApplications: ({required date, required businessId, purpose}) async =>
          const [],
      confirmedWorkers: ({required date, required businessId}) async => confirmed,
      dayStaffing: ({required businessId, required dayStartMs}) async => [_row()],
      dayInvitations: ({required date, required businessId}) async => invitations,
      hasWorkedMap: ({required businessId, required date}) async => const {},
      noShowApplicationIds: ({required businessId, required date}) async =>
          <String>{},
      usersBatch: (uids, {required businessId, purpose}) async => {
        for (final u in uids)
          u: UserModel(
              uid: u,
              username: u,
              name: '근로자 $u',
              email: '$u@test.local',
              role: UserRole.USER),
      },
      weeklyAttendance: (
              {required businessId,
              required weekStart,
              required weekEnd}) async =>
          <String, List<AttendanceModel>>{},
      slotWorkDetailCapacities: (toId, slotId) async => const {kWdId: 3},
      slotWorkDetails: (toId, slotId) async => <WorkDetailData>[],
      to: (toId) async => null,
      contractStatusBatch: (ids, {required businessId}) async =>
          <String, String?>{},
    );

Future<void> _pumpAdmin(
  WidgetTester tester, {
  required DayApplicantsReads reads,
  Size size = const Size(390, 1800),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _Owner(),
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: DayApplicantsDialog(
            key: ValueKey(kDate),
            date: kDate,
            businessIds: const [kBiz],
            businesses: [_business()],
            reads: reads,
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// ── 지원자 쪽 ───────────────────────────────────────────────────────────────

MyApplicationsReads _workerReads(List<ApplicationModel> apps) =>
    MyApplicationsReads(
      myApplicationsPaged: (
              {required String uid,
              required int pageSize,
              String? startAfterDocId}) async =>
          {'items': apps, 'lastDocId': null, 'hasMore': false},
      toOrFailure: (toId) async => (to: _to(), failed: false),
      contractsByWorker: (uid) async => const [],
      autoExpirePending: (uid) async {},
    );

Future<void> _pumpWorker(
  WidgetTester tester, {
  required List<ApplicationModel> apps,
  String uid = 'u1',
  Size size = const Size(390, 1800),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _Worker(uid),
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: MyApplicationsScreen(reads: _workerReads(apps)),
      ),
    ),
  );
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('[IHK-1] 관리자 목록은 같은 키의 초대가 어떻게 끝났는지 세 갈래로 말한다',
      (tester) async {
    await _pumpAdmin(
      tester,
      reads: _adminReads(
        // 수락해서 자리를 가져간 초대 — 확정 명단에 있지만 invitedAt 으로 구분된다.
        confirmed: [
          _app(
              id: 'inv-ok',
              uid: 'u1',
              status: 'CONFIRMED',
              invitedAt: kInvitedAt)
        ],
        invitations: [
          _app(
              id: 'inv-no',
              uid: 'u2',
              status: 'REJECTED',
              invitedAt: kInvitedAt),
          _app(
              id: 'inv-wd',
              uid: 'u3',
              status: 'CANCELED',
              invitedAt: kInvitedAt),
        ],
      ),
    );
    expect(tester.takeException(), isNull);

    // 발송 결과가 확정 명단에 섞여 사라지지 않는다.
    // 지원자가 거절한 것과 관리자가 철회한 것이 서로 다른 말이다.
    expect(find.text('초대 수락 · 확정'), findsOneWidget);
    expect(find.text('초대 거절'), findsOneWidget);
    expect(find.text('초대 철회'), findsOneWidget);
  });

  testWidgets('[IHK-2] 지원자 화면의 같은 초대는 조건을 말하고서야 수락시킨다',
      (tester) async {
    await _pumpWorker(tester, apps: [
      _app(
          id: 'inv-ok',
          uid: 'u1',
          status: 'INVITED',
          invitedAt: kInvitedAt,
          capacity: InviteCapacityState.available),
    ]);
    expect(tester.takeException(), isNull);

    // 관리자가 보낸 그 사건이 지원자 쪽에도 같은 이름으로 온다.
    expect(find.textContaining(kBizName), findsWidgets);
    expect(find.text('근무 초대'), findsOneWidget);
    expect(find.text('근무 초대가 도착했어요'), findsOneWidget);
    // 날짜는 fixture 가 미는 값이라 문자열을 못박지 않는다 — 시간대만 고정.
    expect(find.textContaining('09:00~18:00'), findsOneWidget);

    // 자리가 있다고 **서버가 확인해 준** 경우에만 수락 CTA 가 뜬다.
    expect(find.text('수락하기'), findsOneWidget);
    expect(find.text('거절'), findsOneWidget);

    // 탭해도 즉시 확정되지 않는다 — 화면에 확정이 선언되지 않는다.
    await tester.tap(find.text('수락하기'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('확정되었습니다'), findsNothing);
    expect(find.textContaining('출근 예정이에요'), findsNothing);

    // ── 여기서 멈춘다. `_acceptInvite` 는 확인창을 띄우기 전에
    //    `TaxIdentityService.loadStatus()` → `meetsApplyPrerequisites(...)`
    //    라는 **서류 문턱**을 지난다(수락도 직접 지원과 같은 문턱이다).
    //    격리 표본으로는 그 문턱을 넘지 못했고, 테스트용 자격 우회는 넣지 않는다.
    //    확인창 문구(`수락 후 일정 충돌이 없으면 확정됩니다.` / `동의하고 초대 수락`)는
    //    **CODE only** 로 남긴다.
  });

  testWidgets('[IHK-2b] 자리 상태를 모르면 수락 CTA 자체가 없다 (UNKNOWN != 가능)',
      (tester) async {
    await _pumpWorker(tester, apps: [
      // capacity 기본값 = unknown
      _app(id: 'inv-unk', uid: 'u1', status: 'INVITED', invitedAt: kInvitedAt),
    ]);

    expect(find.text('근무 가능 여부를 확인하지 못했어요'), findsOneWidget);
    expect(find.text('새로고침 후 다시 확인해 주세요'), findsOneWidget);
    // 모르는 것을 "가능"으로 바꾸지 않는다.
    expect(find.text('수락하기'), findsNothing);
    // 거절은 자리 상태와 무관한 자기 결정이라 남는다.
    expect(find.text('거절'), findsOneWidget);
  });

  testWidgets('[IHK-3] 내가 거절한 초대와 관리자가 거절한 지원이 섞이지 않는다',
      (tester) async {
    await _pumpWorker(tester, apps: [
      // 초대를 내가 거절 — invitedAt 있음
      _app(id: 'r1', uid: 'u1', status: 'REJECTED', invitedAt: kInvitedAt),
    ]);
    expect(find.text('초대를 거절했어요'), findsOneWidget);
    expect(find.text('이번 지원은 확정되지 않았어요'), findsNothing);

    // 내가 지원했는데 관리자가 거절 — invitedAt 없음 (양성 대조)
    await _pumpWorker(tester, apps: [
      _app(id: 'r2', uid: 'u1', status: 'REJECTED'),
    ]);
    expect(find.text('이번 지원은 확정되지 않았어요'), findsOneWidget);
    expect(find.text('초대를 거절했어요'), findsNothing);
  });

  testWidgets('[IHK-4] 수락으로 끝나지 않는다 — 확정 뒤 남은 단계는 출근이다',
      (tester) async {
    await _pumpWorker(tester, apps: [
      _app(id: 'c1', uid: 'u1', status: 'CONFIRMED', invitedAt: kInvitedAt),
    ]);
    // 확정은 "끝"이 아니라 9월 29일 출근이라는 다음 약속이다.
    expect(find.textContaining('출근 예정이에요'), findsOneWidget);
  });

  testWidgets('[IHK-5] 320dp × 2.0 — 초대 결과 세 갈래와 확정 명단 행이 넘치지 않는다',
      (tester) async {
    await _pumpAdmin(
      tester,
      size: const Size(320, 2600),
      textScale: 2.0,
      reads: _adminReads(
        confirmed: [
          _app(
              id: 'inv-ok',
              uid: 'u1',
              status: 'CONFIRMED',
              invitedAt: kInvitedAt)
        ],
        invitations: [
          _app(
              id: 'inv-no',
              uid: 'u2',
              status: 'REJECTED',
              invitedAt: kInvitedAt),
          _app(
              id: 'inv-wd',
              uid: 'u3',
              status: 'CANCELED',
              invitedAt: kInvitedAt),
        ],
      ),
    );
    // 이 셀의 중요한 정보는 **초대 결과 세 갈래**다. 배율 2.0·320dp 에서도
    // 세 문구가 그대로 읽힌다.
    expect(find.text('초대 수락 · 확정'), findsOneWidget);
    expect(find.text('초대 거절'), findsOneWidget);
    expect(find.text('초대 철회'), findsOneWidget);

    // ── [R7-P1-2 DEVICE.1H.1 후속] 여기에는 원래 "확정 명단 행에 overflow 가
    //    3건 난다(62/14/104px)" 는 **결함 지속 기대**가 있었다. 그 owner 에서
    //    고쳤으므로 기대를 **정상값으로 옮긴다** — 기대를 지우지 않는다.
    //    같은 표본의 상세 검증은 `applicant_row_overflow_test.dart`(ARO-1~7).
    expect(tester.takeException(), isNull,
        reason: '확정 명단 행이 320dp·배율 2.0 에서 다시 넘치면 여기서 잡힌다');
  });
}
