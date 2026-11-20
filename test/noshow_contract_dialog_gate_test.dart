// [NOSHOW-CONTRACT-GUARD] 지원자 명단 다이얼로그 두 곳이 노쇼·결근 근무일에
//   `계약서 작성` 을 권하지 않는다 — 서버(srvContractBlockedByAttendance)와 같은 규칙.
//
//   DEV 10-20: 서버는 노쇼 근무 발행을 거절하도록 바뀌었으나(00067), 두 다이얼로그는
//   근태를 보지 않는 `isContractIssuable` 로 버튼을 띄웠다 → 누르면 서버가 거절.
//   근태를 읽지 못했을 때 단기 근무를 "발행 가능"이라고 단정하지 않는다.
//   실제 writer(계약서 작성·발송)는 실행하지 않는다 — 버튼 존재만 본다.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/slot_model.dart' show SlotModel, SlotStatus;
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_reads.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_reads.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/utils/contract_attendance_gate.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/widgets/admin/contract_attendance_unknown_notice.dart';

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

class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'owner1', username: 'owner1', name: '박사장',
        email: 'owner1@alfit.local', role: UserRole.BUSINESS_ADMIN,
        businessId: kBiz, createdAt: DateTime(2026, 1, 1));
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
  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

/// 근무일 = 3일 뒤 KST 자정(저장 규칙). 판정은 날짜와 무관하다 — 단기 근무는 지난
///   날짜여도 `끝난 관계`가 아니므로(occupiesSeatOn), 같은 규칙이 과거 노쇼 행에도 적용된다.
final DateTime kDay = () {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day + 3).subtract(const Duration(hours: 9));
}();

ApplicationModel _app(String id, String uid,
        {DateTime? day, String? type, List<String>? workDays, DateTime? workEnd,
        DateTime? released, DateTime? invitedAt, String? invitedBy}) =>
    ApplicationModel(
      invitedAt: invitedAt, invitedBy: invitedBy,
      id: id, uid: uid, toId: 'to1', slotId: 'slot1', businessId: kBiz,
      businessName: '강남 물류센터', toTitle: '단기 모집', selectedWorkType: '홀서빙',
      wdId: 'wd1', startTime: '09:00', endTime: '18:00', wage: 12000,
      wageType: 'hourly', status: AppStatus.confirmed, workDate: day ?? kDay,
      appliedAt: kDay.subtract(const Duration(days: 2)),
      applicationType: type, workDays: workDays, workEndDate: workEnd,
      staffingReleasedAt: released,
    );

AttendanceModel _att(ApplicationModel app, String status,
        {String? id, String? applicationId}) =>
    AttendanceModel(
      id: id ?? '${app.id}_${FormatHelper.formatDateStamp(app.workDate)}',
      applicationId: applicationId ?? app.id,
      userId: app.uid, businessId: kBiz, businessName: '강남 물류센터',
      workDate: app.workDate, workType: '홀서빙', status: status,
      createdAt: app.workDate,
    );

// ── 당일 다이얼로그 ─────────────────────────────────────────────────────────
DayApplicantsReads _dayReads(List<ApplicationModel> confirmed,
        {Future<List<AttendanceModel>> Function()? atts, bool omit = false}) =>
    DayApplicantsReads(
      pendingApplications: ({required date, required businessId, purpose}) async => const [],
      confirmedWorkers: ({required date, required businessId}) async => confirmed,
      dayStaffing: ({required businessId, required dayStartMs}) async => [
        DayStaffingRow(toId: 'to1', toTitle: '단기 모집', slotId: 'slot1', wdId: 'wd1',
            workType: '홀서빙', startTime: '09:00', endTime: '18:00',
            requiredCount: 5, confirmedCount: confirmed.length, pendingCount: 0),
      ],
      dayInvitations: ({required date, required businessId}) async => const [],
      hasWorkedMap: ({required businessId, required date}) async => const {},
      noShowApplicationIds: ({required businessId, required date}) async => <String>{},
      usersBatch: (uids, {required businessId, purpose}) async => {
        for (final u in uids)
          u: UserModel(uid: u, username: u, name: '근로자 $u',
              email: '$u@test.local', role: UserRole.USER),
      },
      weeklyAttendance: ({required businessId, required weekStart, required weekEnd}) async =>
          <String, List<AttendanceModel>>{},
      slotWorkDetailCapacities: (toId, slotId) async => const {'wd1': 5},
      slotWorkDetails: (toId, slotId) async => <WorkDetailData>[],
      to: (toId) async => null,
      contractStatusBatch: (ids, {required businessId}) async => const ContractStatusBatch(),
      contractAttendances: omit
          ? null
          : ({required businessId, required date}) =>
              atts != null ? atts() : Future.value(const <AttendanceModel>[]),
    );

Future<void> _pumpDay(WidgetTester t, DayApplicantsReads reads) async {
  t.view.physicalSize = const Size(411, 3200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _Owner(),
    child: MaterialApp(
      home: Scaffold(
        body: DayApplicantsDialog(
          key: UniqueKey(),
          date: kDay,
          businessIds: const [kBiz],
          businesses: [
            BusinessModel(id: kBiz, name: '강남 물류센터', businessNumber: '000-00-00000',
                category: '음식점', subCategory: '한식', address: '서울특별시 강남구 테헤란로 1',
                ownerId: 'owner1', createdAt: DateTime(2026, 9, 1)),
          ],
          reads: reads,
        ),
      ),
    ),
  ));
  for (var i = 0; i < 30; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

// ── 업무별(주간) 다이얼로그 ─────────────────────────────────────────────────
TOModel _to() => TOModel(
      id: 'to1', businessId: kBiz, businessName: '강남 물류센터', type: 'flex',
      title: '단기 모집', creatorUID: 'owner1', status: 'ACTIVE', workDetails: const [],
      totalRequired: 5, totalConfirmed: 1, totalPending: 0, isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      statusUpdatedAt: DateTime.now().subtract(const Duration(days: 3)),
    );

WorkDetailData _wd() => WorkDetailData(
      wdId: 'wd1', workType: '홀서빙', startTime: '09:00', endTime: '18:00',
      requiredCount: 5, wage: 12000, wageType: 'hourly',
      applicationDeadline: DateTime.now().add(const Duration(days: 2)));

TOItem _slotItem() => TOItem(
      to: _to(),
      slot: SlotModel(id: 'slot1', toId: 'to1', date: kDay, status: SlotStatus.open,
          workDetails: [_wd()], createdAt: DateTime.now().subtract(const Duration(days: 3))),
      confirmedCount: 1, pendingCount: 0, totalRequired: 5);

List<({DateTime first, DateTime last})> workRanges = [];

WorkApplicantsReads _workReads(List<ApplicationModel> apps,
        {Future<List<AttendanceModel>> Function()? atts, bool omit = false,
        Map<String, UserModel>? users}) =>
    WorkApplicantsReads(
      applications: (to, {slotId, required purpose}) async => apps,
      usersBatch: (uids, {required businessId, purpose}) async => {
        for (final u in uids)
          u: users?[u] ??
              UserModel(uid: u, username: u, name: '근로자$u',
                  email: '$u@test.local', role: UserRole.USER),
      },
      weeklyAttendance: ({required businessId, required weekStart, required weekEnd}) async =>
          <String, List<AttendanceModel>>{},
      contractStatusBatch: (ids, {required businessId}) async => const ContractStatusBatch(),
      hasWorkedMap: ({required businessId, required date}) async => const {},
      idCardStatusBatch: ({required requesterId, required targetUserIds}) async => const {},
      capacity: (to, {slotId, slotWorkDetails}) async => {
        'workDetails': [_wd()],
        'workStats': {'wd1': {'confirmed': 1, 'pending': 0}},
        'statsFailed': false,
      },
      reassignProposals: (bizId) async => const [],
      contractAttendances: omit
          ? null
          : ({required businessId, required first, required last}) {
              workRanges.add((first: first, last: last));
              return atts != null ? atts() : Future.value(const <AttendanceModel>[]);
            },
    );

Future<void> _pumpWork(WidgetTester t, WorkApplicantsReads reads,
    {double width = 411, String? font}) async {
  WorkApplicantsReads.debugOverride = reads;
  t.view.physicalSize = Size(width, 3200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _Owner(),
    child: MaterialApp(
      theme: font == null ? null : ThemeData(fontFamily: font),
      home: Scaffold(
        body: WorkApplicantsDialog(
          key: UniqueKey(), toItem: _slotItem(), work: _wd(), onChanged: () {}),
      ),
    ),
  ));
  for (var i = 0; i < 40; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

final _write = find.text('계약서 작성');
final _notice = find.text(ContractAttendanceUnknownNotice.message);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  setUp(() {
    workRanges = [];
    // 실제 callable 은 부르지 않는다 — 혹시 부르면 unavailable 로 떨어진다.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
        (data) async => const StandardMessageCodec()
            .encodeMessage(<Object?>['unavailable', 'test harness', null]));
  });
  tearDown(() => WorkApplicantsReads.debugOverride = null);

  final a = _app('A1', 'u1');

  group('NCG-U 판정(서버와 같은 규칙)', () {
    test('NCG-U1 결정적 id + applicationId + NO_SHOW/absent 만 막는다', () {
      expect(ContractAttendanceGate.blockedBy(a, [_att(a, 'NO_SHOW')]), isTrue);
      expect(ContractAttendanceGate.blockedBy(a, [_att(a, 'absent')]), isTrue);
      expect(ContractAttendanceGate.blockedBy(a, [_att(a, 'present')]), isFalse);
      expect(ContractAttendanceGate.blockedBy(a, const []), isFalse);
      // 다른 날짜의 문서 id · 다른 지원서의 applicationId — 정확히 대응하지 않는다
      expect(ContractAttendanceGate.blockedBy(a,
          [_att(a, 'NO_SHOW', id: 'A1_19990101')]), isFalse);
      expect(ContractAttendanceGate.blockedBy(a,
          [_att(a, 'NO_SHOW', applicationId: 'OTHER')]), isFalse);
    });
    test('NCG-U2 장기 근무는 막지 않는다(서버 판정식: type·workDays·workEnd≠workDate)', () {
      for (final l in [
        _app('L1', 'u1', type: AppType.longTerm),
        _app('L2', 'u1', type: AppType.shortTerm, workDays: const ['월']),
        _app('L3', 'u1', workEnd: kDay.add(const Duration(days: 30))),
      ]) {
        expect(ContractAttendanceGate.attendanceDocId(l), isNull, reason: l.id);
        expect(ContractAttendanceGate.blockedBy(l, [_att(l, 'NO_SHOW')]), isFalse);
        expect(ContractAttendanceGate.clearForIssue(l, null), isTrue);
      }
    });
    test('NCG-U3 근태를 모르면(null) 단기 근무는 발행 가능이 아니다', () {
      expect(ContractAttendanceGate.blockedIds([a], null), isNull);
      expect(ContractAttendanceGate.clearForIssue(a, null), isFalse);
      expect(ContractAttendanceGate.clearForIssue(a, const {}), isTrue);
      expect(ContractAttendanceGate.clearForIssue(a, const {'A1'}), isFalse);
    });
    test('NCG-U4 문서 id 는 KST 근무일(서버 srvKstDateKey 와 같은 날짜)', () {
      // 근무일은 KST 자정으로 저장된다 — 기기 시간대와 무관하게 같은 키여야 한다.
      final utcMidnightKst = DateTime.utc(2026, 10, 10, 15); // = 10-11 00:00 KST
      expect(ContractAttendanceGate.attendanceDocId(_app('Z', 'u', day: utcMidnightKst)),
          'Z_20261011');
    });
  });

  group('NCG-S 근태 읽기(서비스)', () {
    void reply(Map<String, Object?> data) => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMessageHandler(
            'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
            (msg) async => const StandardMessageCodec().encodeMessage(<Object?>[data]));
    test('NCG-S1 조회 상한 도달(limitReached) — 던진다(모름 ≠ 근태 없음)', () async {
      reply({'items': <Object?>[], 'limitReached': true});
      await expectLater(
          FirestoreService().getAttendanceForKstDays(
              businessId: kBiz, first: kDay, last: kDay),
          throwsA(isA<StateError>()));
    });
    test('NCG-S2 정상 응답 0건 — 빈 목록(근태 문서 없음 = 발행 가능 재료)', () async {
      reply({'items': <Object?>[], 'limitReached': false});
      expect(
          await FirestoreService().getAttendanceForKstDays(
              businessId: kBiz, first: kDay, last: kDay),
          isEmpty);
    });
    test('NCG-S3 호출 실패 — 던진다', () async {
      await expectLater(
          FirestoreService().getAttendanceForKstDays(
              businessId: kBiz, first: kDay, last: kDay),
          throwsA(anything));
    });
  });

  group('NCG-D 당일 다이얼로그', () {
    testWidgets('NCG-D1 근태 없음 — 계약서 작성 있음(사후 계약 가능)', (t) async {
      await _pumpDay(t, _dayReads([a]));
      expect(_write, findsOneWidget);
    });
    testWidgets('NCG-D2 노쇼 — 계약서 작성 없음', (t) async {
      await _pumpDay(t, _dayReads([a], atts: () async => [_att(a, 'NO_SHOW')]));
      expect(_write, findsNothing);
      expect(find.text('근로자 u1'), findsWidgets, reason: '행 자체는 남는다');
    });
    testWidgets('NCG-D3 결근(absent) — 계약서 작성 없음', (t) async {
      await _pumpDay(t, _dayReads([a], atts: () async => [_att(a, 'absent')]));
      expect(_write, findsNothing);
    });
    testWidgets('NCG-D4 출근(present) — 계약서 작성 있음', (t) async {
      await _pumpDay(t, _dayReads([a], atts: () async => [_att(a, 'present')]));
      expect(_write, findsOneWidget);
    });
    testWidgets('NCG-D5 근태 조회 실패 — 버튼 없음 + 이유·재시도 안내, 화면은 열린다', (t) async {
      await _pumpDay(t, _dayReads([a], atts: () async => throw Exception('unavailable')));
      expect(_write, findsNothing);
      expect(find.text('근로자 u1'), findsWidgets);
      expect(_notice, findsOneWidget, reason: '버튼만 조용히 사라지지 않는다');
      expect(find.text('다시 시도'), findsOneWidget);
    });
    testWidgets('NCG-D9 재시도 성공(근태 없음) — 안내가 사라지고 버튼이 돌아온다', (t) async {
      var fail = true;
      await _pumpDay(t, _dayReads([a], atts: () async {
        if (fail) throw StateError('limit reached');
        return const <AttendanceModel>[];
      }));
      expect(_notice, findsOneWidget);
      fail = false;
      await t.tap(find.text('다시 시도'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(_notice, findsNothing);
      expect(_write, findsOneWidget);
    });
    testWidgets('NCG-D10 재시도 결과 노쇼 — 안내는 사라지고 버튼은 없다(모름≠막힘)', (t) async {
      var fail = true;
      await _pumpDay(t, _dayReads([a], atts: () async {
        if (fail) throw Exception('unavailable');
        return [_att(a, 'NO_SHOW')];
      }));
      fail = false;
      await t.tap(find.text('다시 시도'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(_notice, findsNothing);
      expect(_write, findsNothing);
    });
    testWidgets('NCG-D11 조회 성공(노쇼·근태 없음)에는 안내가 없다', (t) async {
      await _pumpDay(t, _dayReads([a, _app('B1', 'u2')],
          atts: () async => [_att(a, 'NO_SHOW')]));
      expect(_notice, findsNothing);
    });
    testWidgets('NCG-D6 근태 읽기를 주지 않으면 모름 — 버튼 없음', (t) async {
      await _pumpDay(t, _dayReads([a], omit: true));
      expect(_write, findsNothing);
    });
    testWidgets('NCG-D7 다른 지원서의 노쇼 — 이 행은 그대로', (t) async {
      final b = _app('B1', 'u2');
      await _pumpDay(t, _dayReads([a, b], atts: () async => [_att(b, 'NO_SHOW')]));
      expect(_write, findsOneWidget, reason: 'A1 만 남는다');
    });
    testWidgets('NCG-D8 일괄 개수도 같은 판정 — 3명 중 노쇼 1 → 미작성 2명', (t) async {
      final b = _app('B1', 'u2');
      final c = _app('C1', 'u3');
      await _pumpDay(t, _dayReads([a, b, c], atts: () async => [_att(c, 'NO_SHOW')]));
      expect(findVisibleText('계약서 미작성 2명'), findsOneWidget);
      expect(_write, findsNWidgets(2));
    });
  });

  group('NCG-W 업무별 다이얼로그', () {
    testWidgets('NCG-W1 근태 없음 — 계약서 작성 있음, 근무일 범위를 한 번 읽는다', (t) async {
      await _pumpWork(t, _workReads([a]));
      expect(_write, findsOneWidget);
      expect(workRanges.length, 1);
      expect(workRanges.single.first, kDay);
      expect(workRanges.single.last, kDay);
    });
    testWidgets('NCG-W2 노쇼 — 계약서 작성 없음', (t) async {
      await _pumpWork(t, _workReads([a], atts: () async => [_att(a, 'NO_SHOW')]));
      expect(_write, findsNothing);
      expect(find.text('근로자u1'), findsWidgets);
    });
    testWidgets('NCG-W3 결근 — 계약서 작성 없음', (t) async {
      await _pumpWork(t, _workReads([a], atts: () async => [_att(a, 'absent')]));
      expect(_write, findsNothing);
    });
    testWidgets('NCG-W4 근태 조회 실패 — 버튼 없음 + 이유·재시도 안내, 화면은 열린다', (t) async {
      await _pumpWork(t, _workReads([a], atts: () async => throw Exception('unavailable')));
      expect(_write, findsNothing);
      expect(find.text('근로자u1'), findsWidgets);
      expect(_notice, findsOneWidget);
    });
    testWidgets('NCG-W7 상한 도달 → 재시도 성공 — 버튼이 돌아오고 같은 범위를 다시 읽는다', (t) async {
      var fail = true;
      await _pumpWork(t, _workReads([a], atts: () async {
        if (fail) throw StateError('limit reached');
        return const <AttendanceModel>[];
      }));
      expect(_notice, findsOneWidget);
      fail = false;
      await t.tap(find.text('다시 시도'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(_notice, findsNothing);
      expect(_write, findsOneWidget);
      expect(workRanges.length, 2);
      expect(workRanges.last.first, kDay);
    });
    testWidgets('NCG-W8 조회 성공(노쇼)에는 안내가 없다', (t) async {
      await _pumpWork(t, _workReads([a], atts: () async => [_att(a, 'NO_SHOW')]));
      expect(_notice, findsNothing);
    });
    testWidgets('NCG-W5 근태 읽기를 주지 않으면 모름 — 버튼 없음', (t) async {
      await _pumpWork(t, _workReads([a], omit: true));
      expect(_write, findsNothing);
    });
    testWidgets('NCG-W6 다른 날짜 문서의 노쇼는 보지 않는다 — 버튼 있음', (t) async {
      await _pumpWork(t, _workReads([a],
          atts: () async => [_att(a, 'NO_SHOW', id: 'A1_19990101')]));
      expect(_write, findsOneWidget);
    });
  });

  // [DIALOG-VISUAL-CLOSE] 배지는 버튼과 같은 판정으로 말한다(Pixel 5 10-23: 노쇼·좌석 반납
  //   행에 버튼은 없는데 `계약서 작성 필요` 가 남았다).
  final need = find.text('계약서 작성 필요');
  final notTarget = find.text('계약 대상 아님');
  final attUnknown = find.text('근태 확인 필요');
  final released = _app('R1', 'u1', released: kDay.subtract(const Duration(hours: 1)));
  group('NCG-B 배지 = 버튼 판정', () {
    testWidgets('NCG-BD1 당일 · 근태 없음 → 작성 필요 + 버튼', (t) async {
      await _pumpDay(t, _dayReads([a]));
      expect(need, findsOneWidget);
      expect(_write, findsOneWidget);
      expect(notTarget, findsNothing);
    });
    testWidgets('NCG-BD2 당일 · 노쇼 → 계약 대상 아님, 작성 필요 없음', (t) async {
      await _pumpDay(t, _dayReads([a], atts: () async => [_att(a, 'NO_SHOW')]));
      expect(need, findsNothing);
      expect(notTarget, findsOneWidget);
      expect(_write, findsNothing);
    });
    testWidgets('NCG-BD3 당일 · 근태 조회 실패 → 근태 확인 필요(위 안내가 할 일)', (t) async {
      await _pumpDay(t, _dayReads([a], atts: () async => throw Exception('unavailable')));
      expect(need, findsNothing);
      expect(attUnknown, findsOneWidget);
      expect(_notice, findsOneWidget);
    });
    testWidgets('NCG-BD4 당일 · 좌석 반납 → 계약 대상 아님', (t) async {
      await _pumpDay(t, _dayReads([released]));
      expect(need, findsNothing);
      expect(notTarget, findsOneWidget);
      expect(_write, findsNothing);
    });
    testWidgets('NCG-BW1 업무별 · 근태 없음 → 작성 필요 + 버튼', (t) async {
      await _pumpWork(t, _workReads([a]));
      expect(need, findsOneWidget);
      expect(_write, findsOneWidget);
    });
    testWidgets('NCG-BW2 업무별 · 노쇼 → 계약 대상 아님', (t) async {
      await _pumpWork(t, _workReads([a], atts: () async => [_att(a, 'NO_SHOW')]));
      expect(need, findsNothing);
      expect(notTarget, findsOneWidget);
    });
    testWidgets('NCG-BW3 업무별 · 근태 조회 실패 → 근태 확인 필요', (t) async {
      await _pumpWork(t, _workReads([a], atts: () async => throw Exception('unavailable')));
      expect(need, findsNothing);
      expect(attUnknown, findsOneWidget);
    });
    testWidgets('NCG-BW4 업무별 · 좌석 반납 → 작성 필요 없음', (t) async {
      await _pumpWork(t, _workReads([released]));
      expect(need, findsNothing);
      expect(_write, findsNothing);
      expect(notTarget.evaluate().length + find.text('계약서 미작성').evaluate().length, 1,
          reason: '반납 행은 기록(계약 대상 아님 또는 미작성) 하나만');
    });
  });

  // [DIALOG-VISUAL-CLOSE] 업무별 다이얼로그 이름 — 두 근로자를 이름으로 구별할 수 있어야 한다.
  //   측정 자: 번들 NotoSansKR(기기 한글 폰트에 가장 가까운 자, 기본 테스트 폰트는 더 넓다).
  // [INVITE-TIME-COPY] 초대로 들어온 확정자는 초대한 시각을 쓴다(지원 시각이 아니다).
  group('NCG-T 확정 행 시각 라벨', () {
    final inv = DateTime.now().subtract(const Duration(minutes: 52));
    testWidgets('NCG-T1 당일 · 초대 시각이 있으면 "초대 N분 전"', (t) async {
      await _pumpDay(t, _dayReads([_app('i1', 'w1', invitedAt: inv, invitedBy: 'owner1')]));
      expect(find.textContaining('초대 52분 전'), findsOneWidget);
      expect(findVisibleTextContaining('지원 '), findsNothing);
    });
    testWidgets('NCG-T2 당일 · 초대 표시만 있고 시각이 없으면 "초대" 만(시간을 지어내지 않는다)', (t) async {
      await _pumpDay(t, _dayReads([_app('i2', 'w1', invitedBy: 'owner1')]));
      expect(find.text('초대'), findsOneWidget);
      expect(find.textContaining('분 전'), findsNothing);
    });
    testWidgets('NCG-T3 당일 대조 · 직접 지원은 "지원 N일 전" 그대로', (t) async {
      await _pumpDay(t, _dayReads([a]));
      expect(find.textContaining(RegExp(r'^지원 ')), findsOneWidget);
    });
    testWidgets('NCG-T4 업무별 · 초대 시각이면 "초대 N분 전", 직접 지원은 "지원"', (t) async {
      await _pumpWork(t, _workReads([_app('i3', 'w1', invitedAt: inv, invitedBy: 'owner1'), a]));
      expect(find.textContaining('초대 52분 전'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^지원 ')), findsOneWidget);
    });
  });

  group('NCG-N 이름 폭(320·360·411dp, NotoSansKR)', () {
    setUpAll(() async {
      final loader = FontLoader('NotoSansKR');
      for (final f in const ['Regular', 'Bold']) {
        loader.addFont(rootBundle
            .load('assets/fonts/NotoSansKR-$f.ttf')
            .then((b) => ByteData.sublistView(b.buffer.asUint8List())));
      }
      await loader.load();
    });
    final u1 = UserModel(uid: 'u1', username: 'u1', name: 'QA 지원자1', personNo: 1,
        email: 'u1@test.local', role: UserRole.USER);
    final u2 = UserModel(uid: 'u2', username: 'u2', name: 'QA 지원자2', personNo: 2,
        email: 'u2@test.local', role: UserRole.USER);
    final b2 = _app('B2', 'u2');
    for (final w in const [320.0, 360.0, 411.0]) {
      testWidgets('NCG-N ${w.toInt()}dp — 이름 전체가 보이고 번호·버튼도 읽힌다, 넘침 없음', (t) async {
        await _pumpWork(t, _workReads([a, b2], users: {'u1': u1, 'u2': u2}),
            width: w, font: 'NotoSansKR');
        expect(t.takeException(), isNull, reason: 'RenderFlex 넘침 없음');
        for (final n in const ['QA 지원자1', 'QA 지원자2']) {
          // maxLines 없는 말줄임은 didExceedMaxLines 로 안 잡힌다 — 그린 폭 ≥ 글자 전체 폭으로 본다.
          final p = t.renderObject<RenderParagraph>(find.text(n));
          final full = p.getMaxIntrinsicWidth(double.infinity);
          expect(p.size.width, greaterThanOrEqualTo(full - 0.5),
              reason: '$n 이 잘리지 않는다(${w}dp: 그린 ${p.size.width.toStringAsFixed(1)} / 전체 ${full.toStringAsFixed(1)})');
        }
        expect(find.text('(P-001)'), findsOneWidget);
        expect(find.text('(P-002)'), findsOneWidget);
        expect(_write, findsNWidgets(2));
      });
    }
  });
}
