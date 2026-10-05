// [R7-P4.4E.7A] 근로자와 한 근무 사이의 **지원 관계**를 네 단계가 같은 뜻으로
// 읽는지 고정한다.
//
//   render eligibility · toggle eligibility · confirm-sheet reconciliation ·
//   server guard — 네 곳이 같은 판정을 써야 한다. 서버는 바꾸지 않으므로
//   여기서는 앞의 세 단계가 서버 계약과 같은 축인지 본다.
//
// 고친 세 결함
//   A. 공고 상세가 `_myApplications` 를 들고 있으면서도 선택 가능 여부를
//      그것과 무관하게 정했다 — 이미 지원한 업무에 `선택` 이 보이고 CTA 의
//      N 이 부풀었다.
//   B. 확인 시트가 `selectedWorkType` 하나로 비교해, 같은 업무명이 시간대만
//      다른 **별개 근무**를 하나로 뭉쳤다 → 정당한 지원이 제출에서 조용히
//      빠졌다. 서버 `srvFindRelationApplications` 주석이 이미 경고한 실수다.
//   C. INVITED 가 신규 지원 가능처럼 보였다 — 서버는 막고 다른 문구를 준다.
//
// 서버 계약(`callableApplyToTO`, 변경하지 않았다)
//   PENDING · CONTRACT_PENDING · CONFIRMED → already-exists
//   INVITED                                → already-exists (다른 문구)
//   REJECTED · CANCELED · AUTO_CANCELED    → isReactivation = true (재지원 가능)
//   EXPIRED                                → 두 집합에 없음 → 신규 지원으로 통과
//   퇴사·해지 승인 완료                      → guard 자체를 건너뜀
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/business_work_type_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/job_posting_reads.dart';
import 'package:ALfit/screens/common/job_posting_screen.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/services/schedule_conflict_service.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/dialogs/apply/application_relation.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_work_dialog.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_work_reads.dart';
import 'package:ALfit/widgets/dialogs/apply/multi_apply_confirm_sheet.dart';

// ── Firebase core 가짜 ────────────────────────────────────────────
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

class _Applicant extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        // 서류 게이트를 우회하지 않는다 — 요건을 **실제로 충족한** 사용자를
        // 쓴다. 그러지 않으면 CTA 가 '지원 준비하기' 로 덮여 선택 수치를
        // 볼 수 없다.
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
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
}

const kTo = 'to1';
const kSlot = 'slot1';
final kDate = DateTime(2026, 10, 10);

/// 미래 근무일 — 과거면 마감 경로로 빠져 카드가 덮인다.
final kFutureDate = DateTime(
  DateTime.now().year,
  DateTime.now().month,
  DateTime.now().day,
).add(const Duration(days: 5));

/// 같은 업무명 + 서로 다른 wdId. 결함 B 의 핵심 표본이다.
WorkDetailData _wd({
  required String? wdId,
  String type = '상하차',
  String start = '09:00',
  String end = '13:00',
}) =>
    WorkDetailData(
      wdId: wdId,
      workType: type,
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 12000,
      wageType: 'hourly',
      requiredCount: 3,
      startTime: start,
      endTime: end,
    );

ApplicationModel _app({
  required String status,
  String? wdId = 'wdA',
  String type = '상하차',
  String start = '09:00',
  String end = '13:00',
  String? slotId = kSlot,
  String? resignStatus,
  String? terminationStatus,
  // [R7-APPLICATION-LIFECYCLE.1C] 다른 공고·다른 사업장의 **약속**을 세울 수
  //   있어야 한다 — 관계 축은 none 인데 시간은 겹치는 경우가 이 phase 의 표본이다.
  String toId = kTo,
  String businessName = '강남 물류센터',
}) =>
    ApplicationModel(
      id: 'a_$status${wdId}_$toId',
      uid: 'u1',
      toId: toId,
      slotId: slotId,
      businessId: 'biz1',
      businessName: businessName,
      toTitle: '단기 모집',
      selectedWorkType: type,
      wdId: wdId,
      startTime: start,
      endTime: end,
      wage: 12000,
      wageType: 'hourly',
      status: status,
      workDate: kDate,
      appliedAt: DateTime(2026, 10, 1),
      resignStatus: resignStatus,
      terminationStatus: terminationStatus,
    );

WorkApplyRelation _resolve(
  List<ApplicationModel> apps,
  WorkDetailData work, {
  String? slotId = kSlot,
}) =>
    ApplicationRelationResolver.resolve(
      myApplications: apps,
      toId: kTo,
      slotId: slotId,
      work: work,
    );

// ── 화면 하네스 ───────────────────────────────────────────────────

TOModel _to() => TOModel(
      id: kTo,
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
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

/// ApplyWorkDialog 는 `mainTO.date` 를 쓴다 — 과거면 마감 안내가 카드를 덮는다.
TOModel _toDated() => TOModel(
      id: kTo,
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
      rangeStart: kFutureDate,
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

BusinessModel _business() => BusinessModel(
      id: 'biz1',
      name: '강남 물류센터',
      businessNumber: '000-00-00000',
      category: '음식점',
      subCategory: '한식',
      address: '서울특별시 강남구 테헤란로 1',
      ownerId: 'owner1',
      createdAt: DateTime(2026, 9, 1),
    );

SlotModel _slot(List<WorkDetailData> details) => SlotModel(
      id: kSlot,
      toId: kTo,
      date: kDate,
      workDetails: details,
      status: SlotStatus.open,
      confirmedCount: 0,
      createdAt: DateTime(2025),
    );

JobPostingReads _reads({
  required List<WorkDetailData> details,
  List<ApplicationModel> myApps = const [],
}) =>
    JobPostingReads(
      toOrFailure: (id) async => (to: _to(), failed: false),
      workDetails: (id) async => details,
      businessById: (id) async => _business(),
      slots: (id, {bool visibleOnly = true}) async => [_slot(details)],
      myApplications: (uid) async => myApps,
      businessWorkTypes: (id) async => const <BusinessWorkTypeModel>[],
      applicationOnce: (id) async => null,
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<WorkDetailData> details,
  List<ApplicationModel> myApps = const [],
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Applicant()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        home: JobPostingScreen(
          to: _to(),
          workDetails: const [],
          slotDate: kDate,
          reads: _reads(details: details, myApps: myApps),
        ),
      ),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
  });

  // ══════════════════════════════════════════════════════════════
  // 1) resolver — 서버 상태 계약과 같은 축인가
  // ══════════════════════════════════════════════════════════════
  group('ARP-1x 상태별 관계', () {
    test('ARP-10 PENDING → pending (신규 지원 불가)', () {
      final r = _resolve([_app(status: AppStatus.pending)], _wd(wdId: 'wdA'));
      expect(r, WorkApplyRelation.pending);
      expect(r.blocksNewApplication, isTrue);
    });

    test('ARP-11 CONTRACT_PENDING → contractPending (신규 지원 불가)', () {
      final r = _resolve(
          [_app(status: AppStatus.contractPending)], _wd(wdId: 'wdA'));
      expect(r, WorkApplyRelation.contractPending);
      expect(r.blocksNewApplication, isTrue);
    });

    test('ARP-12 CONFIRMED → confirmed (신규 지원 불가)', () {
      final r = _resolve([_app(status: AppStatus.confirmed)], _wd(wdId: 'wdA'));
      expect(r, WorkApplyRelation.confirmed);
      expect(r.blocksNewApplication, isTrue);
    });

    test('ARP-13 INVITED → invited (신규 지원 불가 · 초대로 구별)', () {
      final r = _resolve([_app(status: AppStatus.invited)], _wd(wdId: 'wdA'));
      expect(r, WorkApplyRelation.invited);
      expect(r.blocksNewApplication, isTrue);
      expect(r.isInvitation, isTrue,
          reason: '초대는 수락·거절로 답하는 것이지 다시 지원하는 게 아니다');
    });

    for (final s in [
      AppStatus.rejected,
      AppStatus.canceled,
      AppStatus.autoCanceled,
      AppStatus.expired,
    ]) {
      test('ARP-14 $s → none (서버가 재지원을 허용한다)', () {
        final r = _resolve([_app(status: s)], _wd(wdId: 'wdA'));
        expect(r, WorkApplyRelation.none);
        expect(r.blocksNewApplication, isFalse);
      });
    }

    test('ARP-15 퇴사/해지 승인 완료 → none (서버도 guard 를 건너뛴다)', () {
      // 퇴사: resignStatus APPROVED + status CANCELED
      expect(
        _resolve([
          _app(
              status: AppStatus.canceled,
              resignStatus: AppStatus.approved)
        ], _wd(wdId: 'wdA')),
        WorkApplyRelation.none,
      );
      // 해지: terminationStatus APPROVED — status 는 확정이어도 끝난 관계다
      expect(
        _resolve([
          _app(
              status: AppStatus.confirmed,
              terminationStatus: AppStatus.autoApproved)
        ], _wd(wdId: 'wdA')),
        WorkApplyRelation.none,
      );
    });

    test('ARP-16 지원서가 없으면 none', () {
      expect(_resolve(const [], _wd(wdId: 'wdA')), WorkApplyRelation.none);
    });

    test('ARP-17 여러 줄이 잡히면 더 강한 약속을 보여준다', () {
      final r = _resolve([
        _app(status: AppStatus.pending),
        _app(status: AppStatus.confirmed),
      ], _wd(wdId: 'wdA'));
      expect(r, WorkApplyRelation.confirmed);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 2) 근무 식별 — wdId 우선, workType 단독 금지 (결함 B)
  // ══════════════════════════════════════════════════════════════
  group('ARP-2x 근무 식별', () {
    test('ARP-20 같은 날짜·다른 wdId → 지원 가능', () {
      final apps = [_app(status: AppStatus.pending, wdId: 'wdA')];
      expect(_resolve(apps, _wd(wdId: 'wdB')), WorkApplyRelation.none);
    });

    test('ARP-21 같은 workType + 다른 시간 + 다른 wdId → 지원 가능', () {
      final apps = [
        _app(
            status: AppStatus.pending,
            wdId: 'wdA',
            start: '09:00',
            end: '13:00')
      ];
      final other = _wd(wdId: 'wdB', start: '14:00', end: '18:00');
      expect(_resolve(apps, other), WorkApplyRelation.none,
          reason: '업무명만 보고 뭉치면 시간대가 다른 별개 근무가 막힌다');
    });

    test('ARP-22 같은 workType + 같은 시간 + 다른 valid wdId → 별개 관계', () {
      // 서버는 (uid, toId, slotId, wdId) 로 본다. 시간까지 같아도 wdId 가
      // 다르면 다른 근무다 — 여기서 막으면 정당한 지원이 사라진다.
      final apps = [
        _app(
            status: AppStatus.confirmed,
            wdId: 'wdA',
            start: '09:00',
            end: '13:00')
      ];
      final other = _wd(wdId: 'wdB', start: '09:00', end: '13:00');
      expect(_resolve(apps, other), WorkApplyRelation.none);
      // 자기 자신은 그대로 잡힌다.
      expect(_resolve(apps, _wd(wdId: 'wdA')), WorkApplyRelation.confirmed);
    });

    test('ARP-23 레거시(wdId 없음) → workType + 시작 + 종료 폴백', () {
      final legacy = [
        _app(
            status: AppStatus.pending,
            wdId: null,
            start: '09:00',
            end: '13:00')
      ];
      // 같은 업무명·같은 시간 → 같은 근무
      expect(
        _resolve(legacy, _wd(wdId: null, start: '09:00', end: '13:00')),
        WorkApplyRelation.pending,
      );
      // 같은 업무명·다른 시간 → 다른 근무 (업무명 단독 매칭이 아니다)
      expect(
        _resolve(legacy, _wd(wdId: null, start: '14:00', end: '18:00')),
        WorkApplyRelation.none,
      );
    });

    test('ARP-24 다른 slot → 관계 아님', () {
      final apps = [
        _app(status: AppStatus.pending, wdId: 'wdA', slotId: 'slotOther')
      ];
      expect(_resolve(apps, _wd(wdId: 'wdA')), WorkApplyRelation.none);
    });

    test('ARP-25 contract TO(slot 없음) — slotId 없는 지원서와 맞춘다', () {
      final apps = [
        _app(status: AppStatus.pending, wdId: 'wdA', slotId: null)
      ];
      expect(_resolve(apps, _wd(wdId: 'wdA'), slotId: null),
          WorkApplyRelation.pending);
    });

    test('ARP-26 다른 TO → 관계 아님', () {
      final r = ApplicationRelationResolver.resolve(
        myApplications: [_app(status: AppStatus.pending, wdId: 'wdA')],
        toId: 'toOther',
        slotId: kSlot,
        work: _wd(wdId: 'wdA'),
      );
      expect(r, WorkApplyRelation.none);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 3) 공고 상세 render + CTA (결함 A·C)
  // ══════════════════════════════════════════════════════════════
  group('ARP-3x 공고 상세', () {
    testWidgets('ARP-30 PENDING 업무는 선택 affordance 대신 지원완료를 보여준다',
        (tester) async {
      await _pump(
        tester,
        details: [_wd(wdId: 'wdA')],
        myApps: [_app(status: AppStatus.pending, wdId: 'wdA')],
      );

      expect(find.text('지원완료'), findsOneWidget,
          reason: '지금 관계를 말해야 한다');
      expect(find.text('선택'), findsNothing,
          reason: '이미 지원한 업무를 신규 선택 후보로 표현하지 않는다');
      expect(find.text('선택됨'), findsNothing);

      // 업무 카드와 상세보기는 그대로 유지한다.
      expect(find.text('업무 자세히 보기'), findsOneWidget,
          reason: '업무를 숨기지 않는다 — 비교할 수 있어야 한다');

      // CTA 의 N 은 신규 지원 가능한 것만 센다.
      expect(find.textContaining('개 업무 선택됨'), findsNothing);
      expect(find.text('지원할 업무를 선택해주세요'), findsOneWidget);
    });

    testWidgets('ARP-31 CONFIRMED 업무는 확정으로 보여준다', (tester) async {
      await _pump(
        tester,
        details: [_wd(wdId: 'wdA')],
        myApps: [_app(status: AppStatus.confirmed, wdId: 'wdA')],
      );
      expect(find.text('확정'), findsWidgets);
      expect(find.text('선택'), findsNothing);
    });

    testWidgets('ARP-32 INVITED 업무는 초대 확인으로 보여준다', (tester) async {
      await _pump(
        tester,
        details: [_wd(wdId: 'wdA')],
        myApps: [_app(status: AppStatus.invited, wdId: 'wdA')],
      );
      expect(find.text('초대 확인'), findsOneWidget,
          reason: '초대는 지원완료와 다른 사건이다');
      expect(find.text('선택'), findsNothing,
          reason: '서버가 초대받은 근무의 재지원을 막는다');
    });

    testWidgets('ARP-33 CANCELED 업무는 다시 선택할 수 있다', (tester) async {
      await _pump(
        tester,
        details: [_wd(wdId: 'wdA')],
        myApps: [_app(status: AppStatus.canceled, wdId: 'wdA')],
      );
      expect(find.text('선택'), findsOneWidget,
          reason: '서버가 재지원을 허용하는 상태다');
      expect(find.text('지원완료'), findsNothing);
    });

    testWidgets('ARP-34 기존 지원 + 신규 업무 혼재 — 신규만 셀 수 있다',
        (tester) async {
      await _pump(
        tester,
        details: [
          _wd(wdId: 'wdA', start: '09:00', end: '13:00'),
          _wd(wdId: 'wdB', start: '14:00', end: '18:00'),
        ],
        myApps: [_app(status: AppStatus.pending, wdId: 'wdA')],
      );

      // 지원한 쪽은 상태, 안 한 쪽은 선택 가능.
      expect(find.text('지원완료'), findsOneWidget);
      expect(find.text('선택'), findsOneWidget);

      await tester.tap(find.text('선택'));
      await tester.pump(const Duration(milliseconds: 100));

      // flex 는 날짜당 1건이므로 1 이 맞다 — 중요한 것은 2 가 아니라는 점이다.
      expect(find.textContaining('1개 업무 선택됨'), findsOneWidget,
          reason: '기존 지원이 N 에 섞이면 안 된다');
    });

    testWidgets('ARP-35 같은 workType 다른 wdId 는 선택 가능하다', (tester) async {
      // 결함 B 의 화면 측 회귀 — 같은 이름의 다른 시간대 근무가 막히면 안 된다.
      await _pump(
        tester,
        details: [
          _wd(wdId: 'wdA', start: '09:00', end: '13:00'),
          _wd(wdId: 'wdB', start: '14:00', end: '18:00'),
        ],
        myApps: [
          _app(
              status: AppStatus.pending,
              wdId: 'wdA',
              start: '09:00',
              end: '13:00')
        ],
      );
      expect(find.text('선택'), findsOneWidget,
          reason: '업무명이 같아도 wdId 가 다르면 별개 근무다');
    });

    // ── [R7-APPLICATION-LIFECYCLE.1C] 확정 일정 겹침 ────────────────────
    //
    //   관계 축은 `none` 이다(다른 공고의 약속이다). 그런데 서버
    //   `callableApplyToTO` 는 같은 시간에 약속이 있으면 거부한다. 상세가
    //   그 사실을 보지 않아서 겹치는 업무에도 `선택` 을 그리고 CTA 의 N 에
    //   셌다 — `[CONFIRMED-CONFLICT-ADVERTISED-AS-APPLICABLE]`.
    ApplicationModel commitment({
      String status = AppStatus.confirmed,
      String start = '09:00',
      String end = '13:00',
    }) =>
        _app(
          status: status,
          wdId: 'wdOther',
          start: start,
          end: end,
          toId: 'toOther',
          slotId: 'slotOther',
          businessName: '다른 사업장',
        );

    for (final s in AppStatus.confirmedStatuses) {
      testWidgets('ARP-36 $s 과 겹치는 업무는 선택할 수 없고 이유가 보인다',
          (tester) async {
        await _pump(
          tester,
          details: [_wd(wdId: 'wdA', start: '09:00', end: '13:00')],
          myApps: [commitment(status: s)],
        );

        expect(find.text('일정 겹침'), findsOneWidget,
            reason: '색만으로 말하지 않는다 — 이유가 글자로 보인다');
        expect(find.text('선택'), findsNothing);
        expect(find.text('지원할 업무를 선택해주세요'), findsOneWidget);
        // `마감`(정원) 과 다른 상태다.
        expect(find.text('지원완료'), findsNothing);
        // 업무 자체는 숨기지 않는다 — 발견은 유지한다.
        expect(find.text('업무 자세히 보기'), findsOneWidget);
      });
    }

    testWidgets('ARP-37 겹치는 업무만 막힌다 — 형제 업무는 선택 가능', (tester) async {
      await _pump(
        tester,
        details: [
          _wd(wdId: 'wdA', start: '09:00', end: '13:00'),
          _wd(wdId: 'wdB', start: '14:00', end: '18:00'),
        ],
        myApps: [commitment()],
      );

      expect(find.text('일정 겹침'), findsOneWidget);
      expect(find.text('선택'), findsOneWidget, reason: '14:00~18:00 은 겹치지 않는다');

      await tester.tap(find.text('선택'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('1개 업무 선택됨'), findsOneWidget);
    });

    testWidgets('ARP-38 인접(13:00 종료 → 14:00 시작)은 막지 않는다', (tester) async {
      await _pump(
        tester,
        details: [_wd(wdId: 'wdA', start: '14:00', end: '18:00')],
        myApps: [commitment(start: '09:00', end: '14:00')],
      );
      expect(find.text('일정 겹침'), findsNothing,
          reason: '현재 canonical 상 인접은 겹침이 아니다 — buffer 규칙을 넣지 않는다');
      expect(find.text('선택'), findsOneWidget);
    });

    for (final s in [AppStatus.pending, AppStatus.invited]) {
      testWidgets('ARP-39 $s 은 약속이 아니다 — 겹쳐도 다른 공고 지원을 막지 않는다',
          (tester) async {
        await _pump(
          tester,
          details: [_wd(wdId: 'wdA', start: '09:00', end: '13:00')],
          myApps: [commitment(status: s)],
        );
        expect(find.text('일정 겹침'), findsNothing);
        expect(find.text('선택'), findsOneWidget);
      });
    }
  });

  // ══════════════════════════════════════════════════════════════
  // 4) 확인 시트 — 정상 신규 업무가 silent drop 되지 않는가 (결함 B)
  // ══════════════════════════════════════════════════════════════
  group('ARP-4x 확인 시트', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      required List<WorkDetailData> works,
      required List<ApplicationModel> myApps,
    }) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final slot = _slot(works);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => _Applicant()),
            ChangeNotifierProvider<NotificationProvider>(
                create: (_) => NotificationProvider()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MultiApplyConfirmSheet(
                items: [for (final w in works) (slot: slot, work: w)],
                to: _to(),
                myApplications: myApps,
              ),
            ),
          ),
        ),
      );
      // 충돌 체크는 실제 플랫폼 채널을 탄다 — testWidgets 의 가짜 시계로는
      // 그 future 가 끝나지 않아 `_isCheckingConflicts` 가 풀리지 않고
      // 배지가 눌린다. 진짜 async 를 한 틱 돌려준다.
      // ([[project-p22-apply-reach-blocked]] 의 레시피)
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('ARP-40 같은 workType 다른 wdId — 하나만 이미 지원중',
        (tester) async {
      await pumpSheet(
        tester,
        works: [
          _wd(wdId: 'wdA', start: '09:00', end: '13:00'),
          _wd(wdId: 'wdB', start: '14:00', end: '18:00'),
        ],
        myApps: [
          _app(
              status: AppStatus.pending,
              wdId: 'wdA',
              start: '09:00',
              end: '13:00')
        ],
      );
      // 지원한 쪽만 표시된다 — 둘 다 표시되면 정당한 지원이 제출에서 빠진다.
      expect(find.text('이미 지원중'), findsOneWidget,
          reason: 'workType 단독 매칭이면 두 건 모두 이미 지원중이 된다');
    });

    testWidgets('ARP-41 INVITED 는 초대 확인으로 구별한다', (tester) async {
      await pumpSheet(
        tester,
        works: [_wd(wdId: 'wdA')],
        myApps: [_app(status: AppStatus.invited, wdId: 'wdA')],
      );
      expect(find.text('초대 확인'), findsOneWidget);
      expect(find.text('이미 지원중'), findsNothing,
          reason: '초대와 지원을 같은 말로 덮지 않는다');
    });

    testWidgets('ARP-42 CANCELED 는 이미 지원중이 아니다', (tester) async {
      await pumpSheet(
        tester,
        works: [_wd(wdId: 'wdA')],
        myApps: [_app(status: AppStatus.canceled, wdId: 'wdA')],
      );
      expect(find.text('이미 지원중'), findsNothing,
          reason: '서버가 재지원을 허용하는 상태다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 5) ApplyWorkDialog — E7B 수렴
  // ══════════════════════════════════════════════════════════════
  group('ARP-5x ApplyWorkDialog', () {
    Future<void> pumpDialog(
      WidgetTester tester, {
      required List<WorkDetailData> works,
      required List<ApplicationModel> myApps,
    }) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        ChangeNotifierProvider<UserProvider>(
          create: (_) => _Applicant(),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: Scaffold(
              body: ApplyWorkDialog(
                mainTO: _toDated(),
                workDetails: works,
                slotId: kSlot,
                businessName: '강남 물류센터',
                reads: ApplyWorkReads(
                  applicationsForTO:
                      ({required String toId, required String uid}) async =>
                          myApps,
                  confirmedSchedules: (
                          {required String uid,
                          required DateTime workDate}) async =>
                      const <ApplicationModel>[],
                  conflictsForWorkDetails: (
                          {required DateTime workDate,
                          required List<WorkDetailData> workDetails}) async =>
                      <String, ConflictInfo>{},
                  myApplicationsForTOFresh: (toId) async =>
                      const <ApplicationModel>[],
                ),
              ),
            ),
          ),
        ),
      );
      // 선결조건·지원서 조회는 실제 플랫폼 채널을 탄다 — 진짜 async 한 틱.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('ARP-50 신규 업무는 지원 버튼이 있다', (tester) async {
      await pumpDialog(tester, works: [_wd(wdId: 'wdA')], myApps: const []);
      expect(find.widgetWithText(InkWell, '지원'), findsWidgets,
          reason: '관계가 없으면 지원할 수 있어야 한다');
    });

    testWidgets('ARP-51 PENDING → 지원 버튼 없음 + 지원완료', (tester) async {
      await pumpDialog(
        tester,
        works: [_wd(wdId: 'wdA')],
        myApps: [_app(status: AppStatus.pending, wdId: 'wdA')],
      );
      expect(find.text('지원완료'), findsWidgets);
      expect(find.widgetWithText(InkWell, '지원'), findsNothing,
          reason: '이미 지원한 업무에 지원 CTA 를 주지 않는다');
    });

    testWidgets('ARP-52 INVITED → 지원 버튼 없음 + 초대 확인', (tester) async {
      await pumpDialog(
        tester,
        works: [_wd(wdId: 'wdA')],
        myApps: [_app(status: AppStatus.invited, wdId: 'wdA')],
      );
      expect(find.text('초대 확인'), findsWidgets,
          reason: '초대는 수락·거절로 답하는 사건이다');
      expect(find.widgetWithText(InkWell, '지원'), findsNothing,
          reason: '서버가 초대받은 근무의 재지원을 막는다');
    });

    testWidgets('ARP-53 CONFIRMED → 확정', (tester) async {
      await pumpDialog(
        tester,
        works: [_wd(wdId: 'wdA')],
        myApps: [_app(status: AppStatus.confirmed, wdId: 'wdA')],
      );
      expect(find.text('확정'), findsWidgets);
      expect(find.widgetWithText(InkWell, '지원'), findsNothing);
    });

    testWidgets('ARP-54 CONTRACT_PENDING → 확정', (tester) async {
      await pumpDialog(
        tester,
        works: [_wd(wdId: 'wdA')],
        myApps: [_app(status: AppStatus.contractPending, wdId: 'wdA')],
      );
      expect(find.text('확정'), findsWidgets);
      expect(find.widgetWithText(InkWell, '지원'), findsNothing);
    });

    for (final s in [
      AppStatus.rejected,
      AppStatus.canceled,
      AppStatus.autoCanceled,
      AppStatus.expired,
    ]) {
      testWidgets('ARP-55 $s → 지원 가능', (tester) async {
        await pumpDialog(
          tester,
          works: [_wd(wdId: 'wdA')],
          myApps: [_app(status: s, wdId: 'wdA')],
        );
        expect(find.widgetWithText(InkWell, '지원'), findsWidgets,
            reason: '서버가 재지원을 허용하는 상태다');
      });
    }

    testWidgets('ARP-56 같은 workType 다른 wdId — 하나만 막힌다', (tester) async {
      await pumpDialog(
        tester,
        works: [
          _wd(wdId: 'wdA', start: '09:00', end: '13:00'),
          _wd(wdId: 'wdB', start: '14:00', end: '18:00'),
        ],
        myApps: [
          _app(
              status: AppStatus.pending,
              wdId: 'wdA',
              start: '09:00',
              end: '13:00')
        ],
      );
      expect(find.text('지원완료'), findsWidgets);
      expect(find.widgetWithText(InkWell, '지원'), findsWidgets,
          reason: '업무명이 같아도 wdId 가 다르면 별개 근무다');
    });

    testWidgets('ARP-57 레거시(wdId 없음) 호환 유지', (tester) async {
      await pumpDialog(
        tester,
        works: [_wd(wdId: null, start: '09:00', end: '13:00')],
        myApps: [
          _app(
              status: AppStatus.pending,
              wdId: null,
              start: '09:00',
              end: '13:00')
        ],
      );
      expect(find.text('지원완료'), findsWidgets,
          reason: 'wdId 가 없으면 workType + 시작 + 종료 로 맞춘다');
      expect(find.widgetWithText(InkWell, '지원'), findsNothing);
    });
  });
}
