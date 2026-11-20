// [ALFIT-E2-INVITED-READER-INTEGRATION-AND-DEVICE-RECHECK.1]
//
//   **실제 위젯 트리**로 한 초대를 끝까지 따라간다.
//
//     TOGroupCard(접힘)  `대기 1`              ← 슬롯 카운터
//       → 펼침           헤더·업무 행 `대기 1` ← WorkforceController.loadWorkDetails
//                                               (production tallyWorkDetailSeats)
//       → 업무 행 탭     WorkApplicantsDialog  `지원: 0명` · `초대: 1명`
//                                               (WorkApplicantsReads seam, 창 코드는 그대로)
//       → 초대 행 탭     WorkerDetailDialog    `초대 발송`·`수락 기한`(KST)·다음 행동
//
//   행 위젯만 따로 그린 E2_INVITED_SEAT 의 W 그룹과 다르다 — 여기서는 카드가
//   showDialog 로 실제 창을 열고, 그 창이 실제 초대 행을 만들고, 그 행이 실제
//   상세를 연다. 대조군: 직접 지원만 / 둘 다 / 끝난 초대 / 지원서 조회 실패 /
//   정원 조회 실패(초대 사실은 남는다).
import 'support/visible_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart' show MemberPermissions;
import 'package:ALfit/models/core/slot_model.dart' show SlotModel, SlotStatus;
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/to_list_dialogs.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_reads.dart';
import 'package:ALfit/services/applicant_document_review_service.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/widgets/admin/cards/admin_to_group_card.dart';
import 'package:ALfit/widgets/admin/cards/admin_work_detail.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';
import 'package:ALfit/widgets/dialogs/worker_detail_dialog.dart';

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

class _AdminP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'owner1', username: 'owner1', name: '관리자',
      email: 'owner1@test.local', role: UserRole.BUSINESS_ADMIN);
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      true;
  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

// ── 픽스처 ─────────────────────────────────────────────────────────────────
const _biz = 'biz1';
const _wd = 'wd-s1';

/// 근무일 = 3일 뒤 KST 자정(저장 규칙), 14:00~15:00 — DEV QA 공고 모양.
final DateTime _workDate = () {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day + 3)
      .subtract(const Duration(hours: 9));
}();

/// 초대는 1시간 전에 보냈다 → 만료(24h)는 근무 시작보다 이르다.
final DateTime _sentAt =
    DateTime.now().toUtc().subtract(const Duration(hours: 1));

TOModel _to() => TOModel(
      id: 'to1',
      businessId: _biz,
      businessName: '테스트 사업장',
      type: 'flex',
      title: 'QA-N E2 consent',
      creatorUID: 'owner1',
      status: 'ACTIVE',
      workDetails: const [],
      totalRequired: 1,
      totalConfirmed: 0,
      totalPending: 1,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      statusUpdatedAt: DateTime.now().subtract(const Duration(days: 3)),
    );

WorkDetailData _wdData() => WorkDetailData(
      wdId: _wd,
      workType: 'QA 분류',
      startTime: '14:00',
      endTime: '15:00',
      requiredCount: 1,
      wage: 12000,
      wageType: 'hourly',
      applicationDeadline: DateTime.now().add(const Duration(days: 2)),
    );

TOItem _slot({required int counterPending}) => TOItem(
      to: _to(),
      slot: SlotModel(
        id: 's1',
        toId: 'to1',
        date: _workDate,
        status: SlotStatus.open,
        workDetails: [_wdData()],
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
      confirmedCount: 0,
      pendingCount: counterPending, // 원장 slot.pendingCount
      totalRequired: 1,
    );

ApplicationModel _app(String id, String uid, String status,
        {bool consented = true}) =>
    ApplicationModel(
      id: id,
      uid: uid,
      toId: 'to1',
      slotId: 's1',
      wdId: _wd,
      businessId: _biz,
      businessName: '테스트 사업장',
      toTitle: 'QA-N E2 consent',
      selectedWorkType: 'QA 분류',
      startTime: '14:00',
      endTime: '15:00',
      wage: 12000,
      wageType: 'hourly',
      status: status,
      workDate: _workDate,
      appliedAt: _sentAt,
      invitedAt: status == AppStatus.pending ? null : _sentAt,
      inviteExpiresAt: status == AppStatus.pending
          ? null
          : _sentAt.add(const Duration(hours: 24)),
      documentAccessConsentGiven: consented,
      documentAccessConsentVersion:
          consented ? DocumentAccessConsent.inviteVersion : null,
    );

/// 카드 통계와 창 정원 — **production** 집계를 같은 지원서로 돌린다.
Future<Map<String, dynamic>> _capacityOf(List<ApplicationModel> apps,
    {List<WorkDetailData>? slotWorkDetails}) async {
  final details = slotWorkDetails ?? [_wdData()];
  final stats = {
    for (final w in details) w.canonicalId: {'confirmed': 0, 'pending': 0}
  };
  FirestoreService.tallyWorkDetailSeats(stats, apps,
      slotId: 's1', seatDay: DateTime.now());
  return {'workDetails': details, 'workStats': stats, 'statsFailed': false};
}

WorkApplicantsReads _reads(
  List<ApplicationModel> apps, {
  bool appsFail = false,
  bool capacityFail = false,
}) =>
    WorkApplicantsReads(
      applications: (to, {slotId, required purpose}) async {
        if (appsFail) throw Exception('unavailable');
        return apps;
      },
      usersBatch: (uids, {required businessId, purpose}) async => {
        for (final u in uids)
          u: UserModel(uid: u, username: u, name: '근로자$u',
              email: '$u@test.local', role: UserRole.USER),
      },
      weeklyAttendance: ({required businessId, required weekStart,
              required weekEnd}) async =>
          <String, List<AttendanceModel>>{},
      contractStatusBatch: (ids, {required businessId}) async =>
          const ContractStatusBatch(),
      hasWorkedMap: ({required businessId, required date}) async => const {},
      idCardStatusBatch: ({required requesterId, required targetUserIds}) async =>
          const {},
      capacity: (to, {slotId, slotWorkDetails}) async {
        if (capacityFail) throw Exception('unavailable');
        return _capacityOf(apps, slotWorkDetails: slotWorkDetails);
      },
      reassignProposals: (bizId) async => const [],
    );

class _FakeReview extends Fake implements ApplicantDocumentReviewService {
  @override
  Future<ApplicantDocumentReview> load({
    required String applicationId,
    required String businessId,
  }) async =>
      ApplicantDocumentReview.fromMap({
        'workerUid': 'w2',
        'canReviewDocuments': true,
        'consentBlock': null,
        'versions': {'id': 2, 'bankbook': 1, 'account': 1},
        'readiness': {
          'ready': false,
          'idDecision': 'NOT_REVIEWED',
          'bankDecision': 'NOT_REVIEWED',
        },
        'documents': {'hasIdCard': true, 'hasBankbook': true},
        'matchingReadiness': {
          'ready': false,
          'state': 'ID_UNASSESSED',
          'reason': '신분증 확인이 필요합니다. 지원자 상세에서 확인해주세요.',
        },
      });
}

String _texts(WidgetTester t) => [
      ...t.widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? w.textSpan?.toPlainText() ?? ''),
      ...t.widgetList<RichText>(find.byType(RichText))
          .map((w) => w.text.toPlainText()),
    ].map(visibleText).where((s) => s.isNotEmpty).join(' | ');

Future<void> _settle(WidgetTester t, [int n = 40]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

List<String> _overflows(WidgetTester t) {
  final out = <String>[];
  Object? e;
  while ((e = t.takeException()) != null) {
    if (e.toString().contains('overflowed')) out.add(e.toString().split('\n').first);
  }
  return out;
}

/// 실제 카드를 그린다 — [expanded] 면 컨트롤러가 먼저 통계를 읽는다(카드와 같은 경로).
Future<TOItem> _pumpCard(
  WidgetTester t, {
  required List<ApplicationModel> apps,
  required bool expanded,
  int counterPending = 1,
  double width = 411,
  double scale = 1.0,
}) async {
  t.view.physicalSize = Size(width, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final slot = _slot(counterPending: counterPending);
  final group = TOGroupItem(singleTO: _to())
    ..setGroupTOs([slot])
    ..setSlotDates([_workDate]);
  final controller = WorkforceController(
      loadWorkDetailStats: (to, {slotId, slotWorkDetails}) =>
          _capacityOf(apps, slotWorkDetails: slotWorkDetails));
  addTearDown(controller.dispose);
  if (expanded) await controller.loadWorkDetails(slot);
  final svc = FirestoreService();
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _AdminP(),
    child: MaterialApp(
      builder: (ctx, c) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: c!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Builder(
            builder: (ctx) => TOGroupCard(
              groupItem: group,
              firestoreService: svc,
              onRetryWorkDetailStats: controller.loadWorkDetails,
              onRetryGroupWorkDetailStats: controller.loadGroupWorkDetailStats,
              dialogs: TOListDialogs(
                  context: ctx, firestoreService: svc, onChanged: () {}),
              onChanged: () {},
              isExpanded: expanded,
              expandedTOs: const <String>{},
              onToggleExpand: () {},
              onToggleTOExpand: (_) {},
            ),
          ),
        ),
      ),
    ),
  ));
  await _settle(t, 10);
  return slot;
}

Future<void> _openWorkDialog(WidgetTester t) async {
  final row = find.byType(WorkDetailRow);
  expect(row, findsOneWidget, reason: '펼친 카드에 업무 행이 있어야 한다');
  await t.ensureVisible(row);
  await t.tap(row);
  await _settle(t);
  expect(find.byType(WorkApplicantsDialog), findsOneWidget,
      reason: '업무 행이 실제 업무별 창을 연다');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
            'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
            (data) async => const StandardMessageCodec()
                .encodeMessage(<Object?>['unavailable', 'test harness', null]));
  });
  tearDown(() {
    WorkApplicantsReads.debugOverride = null;
    ApplicantDocumentReviewService.debugOverride = null;
  });

  final invite = _app('inv1', 'w2', AppStatus.invited);
  final direct = _app('app1', 'w1', AppStatus.pending);

  testWidgets('IR-1 초대만 — 접힘 1 → 펼침 1 → 창 `지원 0 · 초대 1` → 행 → 상세', (t) async {
    // ① 접힘 — 카운터
    await _pumpCard(t, apps: [invite], expanded: false);
    expect(_texts(t), contains('대기 1'));

    // ② 펼침 — 같은 수
    WorkApplicantsReads.debugOverride = _reads([invite]);
    ApplicantDocumentReviewService.debugOverride = _FakeReview();
    await _pumpCard(t, apps: [invite], expanded: true);
    final expandedText = _texts(t);
    expect(expandedText, isNot(contains('대기 0')),
        reason: '펼치는 순간 원장 1 을 0 으로 말했다(수정 전 반례)');
    expect('대기 1'.allMatches(expandedText).length, greaterThanOrEqualTo(2),
        reason: '헤더와 업무 행이 둘 다 `대기 1`');

    // ③ 업무별 창
    await _openWorkDialog(t);
    final dlg = _texts(t);
    expect(dlg, contains('지원: '));
    expect(dlg, contains('초대: '));
    expect(dlg, isNot(contains('지원자가 없습니다')));
    expect(dlg, contains('초대 중 · 서류 확인 가능'));
    final sent = '${FormatHelper.formatDateTime(invite.invitedAt!)} 발송';
    final until =
        '${FormatHelper.formatDateTime(invite.effectiveInviteDeadline!)}까지 수락';
    expect(dlg, contains(sent));
    expect(dlg, contains(until));
    // 지원 0명 · 초대 1명 — 통계 줄의 숫자
    final stat = t.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList();
    final iSup = stat.indexOf('지원: ');
    final iInv = stat.indexOf('초대: ');
    expect(stat[iSup + 1], '0명');
    expect(stat[iInv + 1], '1명');
    // 초대 행에 승인 버튼 없음
    expect(findVisibleText('승인'), findsNothing);
    expect(_overflows(t), isEmpty);

    // ④ 초대 행 → 상세
    await t.tap(findVisibleText('근로자w2'));
    await _settle(t);
    expect(find.byType(WorkerDetailDialog), findsOneWidget);
    final d = t.widget<WorkerDetailDialog>(find.byType(WorkerDetailDialog));
    expect(d.showApprovalButtons, isFalse);
    expect(d.application!.id, 'inv1', reason: '같은 초대가 이어진다');
    final det = _texts(t);
    expect(det, contains('초대 발송'));
    expect(det, contains(FormatHelper.formatDateTimeFull(invite.invitedAt!)));
    expect(det, contains('수락 기한'));
    expect(det,
        contains(FormatHelper.formatDateTimeFull(invite.effectiveInviteDeadline!)));
    expect(det, isNot(contains('확정할 수 있어요')));
    expect(det, contains('근로자가 수락하려면 신분증 확인이 필요해요.'));
    _overflows(t);
  });

  testWidgets('IR-2 직접 지원만 — `지원 1`, 초대 섹션 없음(기존 계산 그대로)', (t) async {
    WorkApplicantsReads.debugOverride = _reads([direct]);
    await _pumpCard(t, apps: [direct], expanded: true);
    expect(_texts(t), contains('대기 1'));
    await _openWorkDialog(t);
    final stat = t.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList();
    expect(stat[stat.indexOf('지원: ') + 1], '1명');
    expect(stat.contains('초대: '), isFalse);
    expect(_texts(t), isNot(contains('초대 중')));
    expect(findVisibleText('근로자w1'), findsWidgets);
    _overflows(t);
  });

  testWidgets('IR-3 둘 다 — 펼침 `대기 2`, 창 `지원 1 · 초대 1`', (t) async {
    WorkApplicantsReads.debugOverride = _reads([direct, invite]);
    await _pumpCard(t, apps: [direct, invite], expanded: true, counterPending: 2);
    expect(_texts(t), contains('대기 2'));
    await _openWorkDialog(t);
    final stat = t.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList();
    expect(stat[stat.indexOf('지원: ') + 1], '1명');
    expect(stat[stat.indexOf('초대: ') + 1], '1명');
    expect(findVisibleText('근로자w1'), findsWidgets);
    expect(findVisibleText('근로자w2'), findsOneWidget);
    _overflows(t);
  });

  testWidgets('IR-4 끝난 초대(만료)만 — 대기 0 · 초대 행 없음(현재 인력 화면)', (t) async {
    final expired = _app('inv9', 'w9', AppStatus.expired);
    WorkApplicantsReads.debugOverride = _reads([expired]);
    await _pumpCard(t, apps: [expired], expanded: true, counterPending: 0);
    expect(_texts(t), contains('대기 0'));
    await _openWorkDialog(t);
    expect(_texts(t), isNot(contains('초대 중')));
    expect(findVisibleText('근로자w9'), findsNothing);
    _overflows(t);
  });

  testWidgets('IR-5 지원서 조회 실패 — `지원자 없음`이 아니라 불러오지 못했다', (t) async {
    WorkApplicantsReads.debugOverride = _reads([invite], appsFail: true);
    await _pumpCard(t, apps: [invite], expanded: true);
    await _openWorkDialog(t);
    final s = _texts(t);
    expect(s, contains('인력 현황을 불러오지 못했어요'));
    expect(s, isNot(contains('지원자가 없습니다')));
    expect(s, isNot(contains('초대: ')), reason: '모르는 초대 수를 0 으로도 1 로도 말하지 않는다');
    _overflows(t);
  });

  testWidgets('IR-6 정원 조회 실패 — 배지는 `상태 확인 불가`, 아는 초대 사실은 남는다', (t) async {
    WorkApplicantsReads.debugOverride = _reads([invite], capacityFail: true);
    await _pumpCard(t, apps: [invite], expanded: true);
    await _openWorkDialog(t);
    final s = _texts(t);
    expect(s, contains('상태 확인 불가'));
    expect(s, contains('근로자 응답 대기 · 서류 열람 동의함'),
        reason: 'INVITED·동의는 모집 상태와 무관하게 아는 사실');
    expect(s, isNot(contains('초대 중 · 서류 확인 가능')),
        reason: '자리를 모르면 수락을 기다리라고 약속하지 않는다');
    expect(s, contains('초대: '));
    _overflows(t);
  });

  testWidgets('IR-8 창을 열었다 닫아도 카드가 공유하는 통계가 `대기 1` 그대로다', (t) async {
    // 설치 앱 실측: 창을 닫은 뒤 화면이 다시 그려지자 업무 행이 `대기 0` 이 됐다.
    //   창의 _updateLocalStats 가 처음 열릴 때도 돌아 PENDING 만 센 값으로
    //   카드와 **같은 TOItem** 의 workDetailStats·pendingCount 를 덮어썼다.
    WorkApplicantsReads.debugOverride = _reads([invite]);
    final slot = await _pumpCard(t, apps: [invite], expanded: true);
    expect(slot.resolveStats().pending, 1);
    await _openWorkDialog(t);
    await t.tap(findVisibleText('닫기').last);
    await _settle(t);
    expect(find.byType(WorkApplicantsDialog), findsNothing);
    expect(slot.pendingCount, 1, reason: '창이 카드의 대기 카운터를 0 으로 덮었다');
    expect(slot.resolveStats().pending, 1, reason: '창이 카드의 업무별 통계를 0 으로 덮었다');
    _overflows(t);
  });

  for (final (w, scale) in const [
    (320.0, 1.0), (320.0, 1.3), (320.0, 2.0),
    (360.0, 1.0), (360.0, 1.3), (360.0, 2.0),
    (411.0, 1.0), (411.0, 1.3), (411.0, 2.0),
  ]) {
    testWidgets('IR-7 ${w.toInt()}dp × $scale — 카드 시급·창 초대 행 넘침 없음·시각 온전',
        (t) async {
      WorkApplicantsReads.debugOverride = _reads([invite]);
      await _pumpCard(t, apps: [invite], expanded: true, width: w, scale: scale);
      expect(_overflows(t), isEmpty, reason: '카드');
      // 업무 행 시급 — 자르지 않는다(카드 실제 렌더).
      final wage = t
          .widgetList<RichText>(find.byType(RichText))
          .map((r) => r.text.toPlainText())
          .firstWhere((s) => s.contains('12,000'), orElse: () => '');
      expect(wage, contains('시급 12,000원'));
      final wageRt = t
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((r) => r.text.toPlainText().contains('12,000'));
      expect(wageRt.overflow, isNot(TextOverflow.ellipsis));
      await _openWorkDialog(t);
      expect(_overflows(t), isEmpty, reason: '업무별 창');
      final row = findVisibleText('근로자w2');
      await t.ensureVisible(row);
      await t.pump();
      expect(row.hitTestable(), findsOneWidget, reason: '초대 행(상세 진입)에 닿는다');
    });
  }
}
