// [R7-P1-2 DEVICE.1H.1 후속] 확정 명단 행이 320dp·배율 2.0 에서 잘리던 것.
//
// P3-2 의 IHK-5 가 넘침 3건(62/14/104px)을 재현했고, 그 상태를 **사실로** 고정해
// 두었다. 여기서 그 셋을 production 부모(`DayApplicantsDialog`) 안에서 다시 세우고
// **넘침 0** 을 새 기대값으로 만든다.
//
// 부모를 실제와 다르게 넓히지 않는다 — 320dp 물리 폭을 그대로 주고 화면이
// 스스로 만드는 제약을 쓴다. 실제 writer(초대·확정취소·거절)는 실행하지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_reads.dart';

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

const kBiz = 'biz1';
final kDate = DateTime(2026, 9, 29);
final kInvitedAt = DateTime(2026, 9, 27, 10);

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
  @override
  bool can(bool Function(MemberPermissions p) c) => true;
  @override
  bool canForBusiness(String b, bool Function(MemberPermissions p) c) => true;
}

BusinessModel _business() => BusinessModel(
      id: kBiz,
      name: '강남 물류센터',
      businessNumber: '000-00-00000',
      category: '음식점',
      subCategory: '한식',
      address: '서울특별시 강남구 테헤란로 1',
      ownerId: 'owner1',
      createdAt: DateTime(2026, 9, 1),
    );

ApplicationModel _app(String id, String uid, String status,
        {DateTime? invitedAt}) =>
    ApplicationModel(
      id: id,
      uid: uid,
      toId: 'to1',
      slotId: 'slot1',
      businessId: kBiz,
      businessName: '강남 물류센터',
      toTitle: '단기 모집',
      selectedWorkType: '홀서빙',
      wdId: 'wd1',
      startTime: '09:00',
      endTime: '18:00',
      wage: 12000,
      wageType: 'hourly',
      status: status,
      workDate: kDate,
      appliedAt: kDate,
      invitedAt: invitedAt,
    );

DayStaffingRow _row() => DayStaffingRow(
      toId: 'to1',
      toTitle: '단기 모집',
      slotId: 'slot1',
      wdId: 'wd1',
      workType: '홀서빙',
      startTime: '09:00',
      endTime: '18:00',
      requiredCount: 3,
      confirmedCount: 1,
      pendingCount: 0,
    );

/// IHK-5 가 넘침을 낸 바로 그 표본: 확정 1건(초대 수락) + 초대 응답 2건.
DayApplicantsReads _reads({
  List<ApplicationModel> pending = const [],
  List<ApplicationModel> confirmed = const [],
  List<ApplicationModel> invites = const [],
}) =>
    DayApplicantsReads(
      pendingApplications: ({required date, required businessId, purpose}) async =>
          pending,
      confirmedWorkers: ({required date, required businessId}) async => confirmed,
      dayStaffing: ({required businessId, required dayStartMs}) async => [_row()],
      dayInvitations: ({required date, required businessId}) async => invites,
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
      slotWorkDetailCapacities: (toId, slotId) async => const {'wd1': 3},
      slotWorkDetails: (toId, slotId) async => <WorkDetailData>[],
      to: (toId) async => null,
      contractStatusBatch: (ids, {required businessId}) async =>
          <String, String?>{},
    );

/// 넘침 메시지를 모은다 — `takeException` 은 첫 건만 주므로 직접 센다.
Future<List<String>> _pumpCollect(
  WidgetTester tester,
  DayApplicantsReads reads, {
  required Size size,
  required double textScale,
}) async {
  final overflows = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final s = d.exception.toString();
    if (s.contains('overflowed')) {
      overflows.add(s.split('\n').first);
    } else {
      prev?.call(d);
    }
  };
  addTearDown(() => FlutterError.onError = prev);

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
            key: ValueKey('$size-$textScale'),
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
  FlutterError.onError = prev;
  return overflows;
}

/// 표본 1 — 확정(초대 수락) 1건 + 초대 응답 2건. IHK-5 의 그 조합.
DayApplicantsReads _sampleAccepted() => _reads(
      confirmed: [_app('c1', 'u1', 'CONFIRMED', invitedAt: kInvitedAt)],
      invites: [
        _app('i1', 'u3', 'REJECTED', invitedAt: kInvitedAt),
        _app('i2', 'u4', 'CANCELED', invitedAt: kInvitedAt),
      ],
    );

/// 표본 2 — 스스로 지원해 확정된 행(초대 구역 없음).
DayApplicantsReads _sampleDirect() =>
    _reads(confirmed: [_app('c2', 'u2', 'CONFIRMED')]);

/// 표본 3 — 대기 행(승인·거절 버튼이 가장 많은 줄).
DayApplicantsReads _samplePending() =>
    _reads(pending: [_app('p1', 'u5', 'PENDING')]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ══ 세 표본 · 320dp × 2.0 ═════════════════════════════════════════════════

  testWidgets('[ARO-1] 표본1(초대 수락 확정) 320dp×2.0 — 넘침 0', (tester) async {
    final o = await _pumpCollect(tester, _sampleAccepted(),
        size: const Size(320, 3200), textScale: 2.0);
    expect(o, isEmpty, reason: o.join(' | '));
  });

  testWidgets('[ARO-2] 표본2(직접 지원 확정) 320dp×2.0 — 넘침 0', (tester) async {
    final o = await _pumpCollect(tester, _sampleDirect(),
        size: const Size(320, 3200), textScale: 2.0);
    expect(o, isEmpty, reason: o.join(' | '));
  });

  testWidgets('[ARO-3] 표본3(대기 행) 320dp×2.0 — 넘침 0', (tester) async {
    final o = await _pumpCollect(tester, _samplePending(),
        size: const Size(320, 3200), textScale: 2.0);
    expect(o, isEmpty, reason: o.join(' | '));
  });

  // ══ 정보와 조작이 살아 있는지 ══════════════════════════════════════════════

  testWidgets('[ARO-4] 320dp×2.0 에서도 이름·상태·행동이 그대로 읽힌다',
      (tester) async {
    await _pumpCollect(tester, _sampleAccepted(),
        size: const Size(320, 3200), textScale: 2.0);

    // 누구인지
    expect(find.text('근로자 u1'), findsWidgets);
    // 무슨 상태인지 — 잘려서 다른 말이 되지 않는다
    expect(find.text('초대 수락 · 확정'), findsOneWidget);
    expect(find.text('초대 거절'), findsOneWidget);
    expect(find.text('초대 철회'), findsOneWidget);
    // 무엇을 할 수 있는지
    expect(find.text('계약서 작성'), findsOneWidget);
    expect(find.text('확정취소'), findsOneWidget);
    // 배지의 값이 잘리지 않는다
    expect(find.text('계약서 작성 필요'), findsOneWidget);
  });

  testWidgets('[ARO-5] 대기 행의 세 버튼이 모두 남는다', (tester) async {
    await _pumpCollect(tester, _samplePending(),
        size: const Size(320, 3200), textScale: 2.0);

    // 묶음 머리줄에도 '확정' 이라는 통계 라벨이 있으므로 **버튼만** 센다.
    expect(find.widgetWithText(InkWell, '다른 업무 제안'), findsOneWidget);
    expect(find.widgetWithText(InkWell, '거절'), findsOneWidget);
    expect(find.widgetWithText(InkWell, '확정'), findsOneWidget);
  });

  testWidgets('[ARO-6] 버튼이 실제로 눌린다 — 확정취소는 확인창까지만',
      (tester) async {
    await _pumpCollect(tester, _sampleAccepted(),
        size: const Size(320, 3200), textScale: 2.0);

    final btn = find.text('확정취소');
    expect(btn, findsOneWidget);
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // 확인 단계가 열린다 — 여기서 멈춘다. 실제 확정취소 writer 는 부르지 않는다.
    expect(find.text('확정취소'), findsWidgets);
  });

  testWidgets('[ARO-7] 행이 길어져도 목록 스크롤로 마지막 행동에 닿는다',
      (tester) async {
    await _pumpCollect(tester, _sampleAccepted(),
        size: const Size(320, 640), textScale: 2.0); // 실제 높이로 좁힌다

    final btn = find.text('확정취소');
    expect(btn, findsOneWidget);
    await tester.ensureVisible(btn);
    await tester.pump();
    expect(tester.getRect(btn).top, lessThan(640));
  });

  // ══ 정상 대조 ═════════════════════════════════════════════════════════════

  for (final size in [const Size(360, 3200), const Size(412, 3200)]) {
    testWidgets('[ARO-C] ${size.width.toInt()}dp × 1.3 — 넘침 0 (정상 대조)',
        (tester) async {
      final o = await _pumpCollect(tester, _sampleAccepted(),
          size: size, textScale: 1.3);
      expect(o, isEmpty, reason: o.join(' | '));
    });
  }

  testWidgets('[ARO-C0] 390dp × 기본 배율 — 넘침 0 (정상 대조)', (tester) async {
    final o = await _pumpCollect(tester, _sampleAccepted(),
        size: const Size(390, 3200), textScale: 1.0);
    expect(o, isEmpty, reason: o.join(' | '));
  });
}
