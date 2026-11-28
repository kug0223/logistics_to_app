// [ALFIT-E2-INVITED-SEAT-READER-AND-DETAIL-UI-CORRECTION.1]
//
//   설치 앱(에뮬레이터, DEV)에서 재현된 장면:
//     원장  업무·슬롯·공고 pendingCount = 1 (INVITED 1건, QA-W2)
//     접힌 공고 카드  `대기 1`         (카운터)
//     펼친 공고 카드  `대기 0`         (지원서 재집계 — INVITED 누락)
//     업무별 지원자 창 `지원자가 없습니다` (INVITED 버림)
//     날짜별 명단     `초대 중 · 서류 확인 가능` (정상)
//     상세            `지원일 2026.10.15 14:00` (KST 23:00 을 UTC 기기 시각으로)
//                     `[확인 완료]를 누르면 확정할 수 있어요` (초대에 확정 버튼 없음)
//
//   여기서는 production 코드를 **실행**한다(식을 복제하지 않는다).
//     R  좌석 집계 `FirestoreService.tallyWorkDetailSeats` — 수정 전 집합으로
//        같은 반례(원장 1 → 화면 0)를 재현하고, 기본값으로 1 이 됨을 본다.
//     C  카드 projection — 접힘(카운터)과 펼침(집계)이 같은 수를 말한다.
//     W  업무별 창 — 같은 응답에서 초대를 고르고(splitWorkApplications),
//        그 행(InviteRosterRow)을 실제로 그린다.
//     D  상세(WorkerDetailDialog) — KST 시각·초대 다음 행동·버튼 없음·좁은 폭.
//     L  날짜별 명단(DayApplicantsDialog) — 같은 초대가 같은 문구로 그려진다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart' show MemberPermissions;
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/models/ui/group_header_totals.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/models/ui/work_applicant_split.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_reads.dart';
import 'package:ALfit/services/applicant_document_review_service.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/widgets/admin/invite_roster_row.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';
import 'package:ALfit/widgets/dialogs/worker_detail_dialog.dart';
import 'support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

// ── Firebase 가짜 코어 (기존 하네스와 같은 방식) ─────────────────────────────
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

// ── 픽스처 — DEV 장면을 그대로 옮긴다(시각은 UTC instant) ─────────────────────
const _biz = 'biz1';
const _wd = 'wd1';

/// KST 자정 = 전날 15:00Z. 근무일 저장 규칙과 같다.
DateTime _kstMidnight(int y, int m, int d) =>
    DateTime.utc(y, m, d).subtract(const Duration(hours: 9));

ApplicationModel _app({
  String id = 'inv1',
  String uid = 'w9',
  String status = AppStatus.invited,
  String slotId = 'slot1',
  String? wdId = _wd,
  DateTime? workDate,
  DateTime? invitedAt,
  DateTime? inviteExpiresAt,
  bool consented = true,
  DateTime? staffingReleasedAt,
}) {
  final wDate = workDate ?? _kstMidnight(2030, 10, 19);
  final sent = status == AppStatus.pending
      ? null
      : (invitedAt ?? DateTime.utc(2030, 10, 15, 14, 0, 17)); // KST 23:00:17
  return ApplicationModel(
    id: id,
    uid: uid,
    toId: 'to1',
    slotId: slotId,
    wdId: wdId,
    businessId: _biz,
    businessName: '테스트 사업장',
    toTitle: 'QA-N E2 consent',
    selectedWorkType: 'QA 분류',
    startTime: '14:00',
    endTime: '15:00',
    wage: 12000,
    wageType: 'hourly',
    status: status,
    workDate: wDate,
    appliedAt: sent ?? DateTime.utc(2030, 10, 14, 1),
    invitedAt: sent,
    inviteExpiresAt: sent == null
        ? null
        : (inviteExpiresAt ?? sent.add(const Duration(hours: 24))),
    documentAccessConsentGiven: consented,
    documentAccessConsentVersion:
        consented ? DocumentAccessConsent.inviteVersion : null,
    staffingReleasedAt: staffingReleasedAt,
  );
}

/// 수정 전 집합 — 같은 반례를 **같은 코드 경로**로 재현하기 위해서만 쓴다.
const _legacySeatStatuses = {'PENDING', 'CONFIRMED', 'CONTRACT_PENDING'};

Map<String, Map<String, int>> _tally(
  List<ApplicationModel> apps, {
  String? slotId = 'slot1',
  Set<String>? statuses,
  List<String> seeds = const [_wd],
}) {
  final stats = {for (final k in seeds) k: {'confirmed': 0, 'pending': 0}};
  FirestoreService.tallyWorkDetailSeats(stats, apps,
      slotId: slotId,
      seatDay: DateTime.utc(2030, 10, 16),
      countedStatuses: statuses);
  return stats;
}

WorkDetailData _detail({String wdId = _wd, int required = 1}) => WorkDetailData(
      wdId: wdId,
      workType: 'QA 분류',
      startTime: '14:00',
      endTime: '15:00',
      wage: 12000,
      wageType: 'hourly',
      requiredCount: required,
    );

TOModel _to() => TOModel(
      id: 'to1',
      businessId: _biz,
      businessName: '테스트 사업장',
      type: 'flex',
      title: 'QA-N E2 consent',
      creatorUID: 'owner1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 1,
      totalConfirmed: 0,
      totalPending: 1,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime(2030),
      statusUpdatedAt: DateTime(2030),
    );

Future<void> _settle(WidgetTester t, [int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

List<String> _overflows(WidgetTester t) {
  final out = <String>[];
  Object? e;
  while ((e = t.takeException()) != null) {
    final s = e.toString();
    if (s.contains('overflowed')) out.add(s.split('\n').first);
  }
  return out;
}

String _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .where((s) => s.isNotEmpty)
    .join(' | ');

Widget _host(Widget child, {double scale = 1.0}) =>
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _AdminP(),
      child: MaterialApp(
        builder: (ctx, c) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: c!,
        ),
        home: Scaffold(body: child),
      ),
    );

void _size(WidgetTester t, double w, {double h = 1400}) {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

class _FakeReview extends Fake implements ApplicantDocumentReviewService {
  _FakeReview(this.map);
  final Map<String, dynamic> map;
  @override
  Future<ApplicantDocumentReview> load({
    required String applicationId,
    required String businessId,
  }) async =>
      ApplicantDocumentReview.fromMap(map);
}

Map<String, dynamic> _review({
  String? consentBlock,
  bool matchingReady = false,
  String state = 'ID_UNASSESSED',
  bool canReview = true,
}) =>
    {
      'workerUid': 'w9',
      'canReviewDocuments': canReview,
      'consentBlock': consentBlock,
      'versions': {'id': 2, 'bankbook': 1, 'account': 1},
      'readiness': {
        'ready': false,
        'idDecision': matchingReady ? 'REVIEWED_OK' : 'NOT_REVIEWED',
        'bankDecision': 'NOT_REVIEWED',
      },
      'documents': {'hasIdCard': state != 'ID_MISSING', 'hasBankbook': true},
      'matchingReadiness': {
        'ready': matchingReady,
        'state': matchingReady ? 'READY_MANUAL' : state,
        'reason': matchingReady ? null : '신분증 확인이 필요합니다. 지원자 상세에서 확인해주세요.',
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  // 상세의 부가 조회(근무 이력·리뷰)는 callable 이다 — 끝나지 않으면 `기본 정보`
  //   가 로딩에 가려진다. 기존 하네스(admin_document_review_ux_test)처럼 즉시
  //   `unavailable` 로 실패시켜, 부가 조회가 실패한 뒤의 실제 배치를 그린다.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
            'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
            (data) async {
      return const StandardMessageCodec()
          .encodeMessage(<Object?>['unavailable', 'test harness', null]);
    });
  });
  tearDown(() => ApplicantDocumentReviewService.debugOverride = null);

  // ══════════════════════════════════════════════════════════════════════
  // R. 좌석 집계 reader — production `tallyWorkDetailSeats` 실행
  // ══════════════════════════════════════════════════════════════════════
  group('R 좌석 집계', () {
    test('R-0 반례 재현: 수정 전 집합은 원장 pendingCount 1 을 0 으로 읽는다', () {
      final before = _tally([_app()], statuses: _legacySeatStatuses);
      expect(before[_wd], {'confirmed': 0, 'pending': 0},
          reason: '수정 전 reader — 펼친 카드 `대기 0` 의 원인');
    });

    test('R-1 초대만 1건 → 대기 1 (서버 카운터와 같다)', () {
      expect(_tally([_app()])[_wd], {'confirmed': 0, 'pending': 1});
    });

    test('R-2 직접 지원만 1건 → 대기 1 (기존 계산 그대로)', () {
      final s = _tally([_app(id: 'p1', status: AppStatus.pending)]);
      expect(s[_wd], {'confirmed': 0, 'pending': 1});
      // 수정 전 집합으로도 같다 — 직접 지원 계산은 바뀌지 않았다.
      expect(_tally([_app(id: 'p1', status: AppStatus.pending)],
          statuses: _legacySeatStatuses)[_wd], s[_wd]);
    });

    test('R-3 지원 1 + 초대 1 → 대기 2 (각각 한 번씩)', () {
      final s = _tally([
        _app(id: 'p1', uid: 'w1', status: AppStatus.pending),
        _app(id: 'i1', uid: 'w2'),
      ]);
      expect(s[_wd], {'confirmed': 0, 'pending': 2});
    });

    test('R-4 확정 계열은 확정으로만 센다 — 대기에 중복 없음', () {
      final s = _tally([
        _app(id: 'c1', uid: 'w1', status: AppStatus.confirmed),
        _app(id: 'c2', uid: 'w2', status: AppStatus.contractPending),
        _app(id: 'i1', uid: 'w3'),
      ]);
      expect(s[_wd], {'confirmed': 2, 'pending': 1});
    });

    test('R-5 끝난 초대(만료·거절·철회·자동종료)는 세지 않는다', () {
      final s = _tally([
        for (final st in [
          AppStatus.expired,
          AppStatus.rejected,
          AppStatus.canceled,
          AppStatus.autoCanceled,
        ])
          _app(id: 'x_$st', uid: 'u_$st', status: st),
      ]);
      expect(s[_wd], {'confirmed': 0, 'pending': 0});
    });

    test('R-6 슬롯 여러 개·업무 여러 개 — 자기 슬롯·자기 업무에만 센다', () {
      final apps = [
        _app(id: 'a', uid: 'w1', slotId: 'slot1', wdId: 'wd1'),
        _app(id: 'b', uid: 'w2', slotId: 'slot1', wdId: 'wd2',
            status: AppStatus.pending),
        _app(id: 'c', uid: 'w3', slotId: 'slot2', wdId: 'wd1'),
      ];
      final s1 = _tally(apps, slotId: 'slot1', seeds: const ['wd1', 'wd2']);
      expect(s1['wd1'], {'confirmed': 0, 'pending': 1});
      expect(s1['wd2'], {'confirmed': 0, 'pending': 1});
      final s2 = _tally(apps, slotId: 'slot2', seeds: const ['wd1', 'wd2']);
      expect(s2['wd1'], {'confirmed': 0, 'pending': 1});
      expect(s2['wd2'], {'confirmed': 0, 'pending': 0});
    });

    test('R-7 좌석 반납 축은 그대로다(초대와 무관한 기존 규칙)', () {
      final s = _tally([
        _app(id: 'c1', status: AppStatus.confirmed,
            staffingReleasedAt: DateTime.utc(2030, 10, 1)),
      ]);
      expect(s[_wd], {'confirmed': 0, 'pending': 0});
    });

    test('R-8 상태 집합이 서버 PENDING_STATUSES 와 짝이다', () {
      expect(AppStatus.seatPendingStatuses, ['PENDING', 'INVITED']);
      // 충돌 판정용 activeStates 는 바꾸지 않았다.
      expect(AppStatus.activeStates, isNot(contains('INVITED')));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // C. 카드 — 접힘(카운터) ↔ 펼침(집계)
  // ══════════════════════════════════════════════════════════════════════
  group('C 공고 카드 접힘·펼침', () {
    TOItem collapsed() => TOItem(
          to: _to(),
          workDetails: [_detail()],
          confirmedCount: 0,
          pendingCount: 1, // 원장 slot.pendingCount
          totalRequired: 1,
        );

    GroupHeaderTotals header(TOItem item) => projectGroupHeaderTotals(
        targetTOs: [item], singleFallback: () => item);

    test('C-1 접힘은 카운터로 `대기 1`', () {
      expect(header(collapsed()).pending, 1);
    });

    test('C-2 펼침(수정 전 집계) → `대기 0` — 기기에서 본 반례', () {
      final item = collapsed()
        ..setWorkDetails([_detail()],
            _tally([_app()], statuses: _legacySeatStatuses));
      expect(header(item).pending, 0);
      expect(item.resolveStats().pending, 0, reason: '업무 행도 같은 값을 읽는다');
    });

    test('C-3 펼침(수정 후 집계) → 헤더·업무 행 모두 `대기 1`', () {
      final item = collapsed()..setWorkDetails([_detail()], _tally([_app()]));
      expect(header(item).pending, 1);
      expect(item.resolveStats().pending, 1);
      // 부족은 대기를 빼지 않는다 — 초대는 자리를 확보하지 않는다.
      expect(item.resolveStats().shortage, 1);
      expect(header(item).confirmed, 0);
    });

    test('C-4 조회 오류 → 0 으로 떨어지지 않고 카운터로 말한다', () {
      final item = collapsed()
        ..setWorkDetails([_detail()], {_wd: {'confirmed': 0, 'pending': 0}},
            statsFailed: true);
      expect(header(item).pending, 1, reason: 'ERROR != ZERO');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // W. 업무별 지원자 창 — 분리 + 초대 행 렌더
  // ══════════════════════════════════════════════════════════════════════
  group('W 업무별 지원자 창', () {
    bool mine(ApplicationModel a) => a.wdId == _wd;

    test('W-1 초대만 있는 업무 — active 0 · invites 1 (빈 화면 아님)', () {
      final s = splitWorkApplications([_app()], mine);
      expect(s.active, isEmpty);
      expect(s.invites.map((a) => a.id), ['inv1']);
    });

    test('W-2 지원 1 + 초대 1 — 따로 담긴다(`지원 1 · 초대 1`)', () {
      final s = splitWorkApplications([
        _app(id: 'p1', uid: 'w1', status: AppStatus.pending),
        _app(id: 'i1', uid: 'w2'),
      ], mine);
      expect(s.active.map((a) => a.id), ['p1']);
      expect(s.invites.map((a) => a.id), ['i1']);
    });

    test('W-3 끝난 초대·다른 업무 초대는 이 창의 초대 목록에 없다', () {
      final s = splitWorkApplications([
        _app(id: 'e', status: AppStatus.expired),
        _app(id: 'c', status: AppStatus.canceled),
        _app(id: 'o', wdId: 'other'),
      ], mine);
      expect(s.invites, isEmpty);
      expect(s.active, isEmpty);
    });

    testWidgets('W-4 초대 행 — 날짜별 명단과 같은 문구 · KST 발송/기한', (t) async {
      _size(t, 411);
      await t.pumpWidget(_host(InviteRosterRow(
        application: _app(),
        name: '큐에이이',
        capacity: InviteCapacityState.available,
        onTap: () {},
      )));
      final s = _texts(t);
      expect(s, contains('초대 중 · 서류 확인 가능'));
      expect(s, contains('10/15 23:00 발송'));
      expect(s, contains('10/16 23:00까지 수락'));
      // 직접 지원의 행동은 없다.
      for (final banned in ['승인', '거절', '확정']) {
        expect(find.text(banned), findsNothing, reason: banned);
      }
    });

    testWidgets('W-5 동의 전 초대 → `초대 중 · 서류 동의 전`', (t) async {
      _size(t, 411);
      await t.pumpWidget(_host(InviteRosterRow(
        application: _app(consented: false),
        name: '큐에이이',
        capacity: InviteCapacityState.available,
      )));
      expect(_texts(t), contains('초대 중 · 서류 동의 전'));
      expect(find.byIcon(Icons.chevron_right), findsNothing,
          reason: '사용자 정보가 없으면 진입을 약속하지 않는다');
    });

    for (final (w, scale) in const [
      (320.0, 1.0), (320.0, 1.3), (320.0, 2.0),
      (360.0, 1.0), (360.0, 1.3), (360.0, 2.0),
      (411.0, 1.0), (411.0, 1.3), (411.0, 2.0),
    ]) {
      testWidgets('W-6 초대 행 ${w.toInt()}dp × $scale — 넘침 없음 · 시각 온전',
          (t) async {
        _size(t, w);
        await t.pumpWidget(_host(
            Padding(
              padding: const EdgeInsets.all(16),
              child: InviteRosterRow(
                application: _app(),
                name: '큐에이이',
                capacity: InviteCapacityState.available,
                onTap: () {},
              ),
            ),
            scale: scale));
        expect(_overflows(t), isEmpty);
        final line = find.textContaining('까지 수락');
        expect(line, findsOneWidget);
        final text = t.widget<Text>(line);
        expect(text.overflow, isNull, reason: '시각을 자르지 않는다');
        expect(text.data, contains('10/16 23:00까지 수락'));
      });
    }
  });

  // ══════════════════════════════════════════════════════════════════════
  // D. 상세 — 사건 시각 KST · 초대 다음 행동 · 좁은 폭
  // ══════════════════════════════════════════════════════════════════════
  group('D 초대 상세', () {
    Future<void> open(WidgetTester t, ApplicationModel app,
        {double w = 411, double scale = 1.0, Map<String, dynamic>? review}) async {
      ApplicantDocumentReviewService.debugOverride =
          _FakeReview(review ?? _review());
      _size(t, w, h: 1600);
      await t.pumpWidget(_host(
          WorkerDetailDialog(
            user: UserModel(uid: 'w9', username: 'w9', name: '큐에이이',
                email: 'w9@test.local', role: UserRole.USER),
            application: app,
            businessId: _biz,
            showApprovalButtons: false,
          ),
          scale: scale));
      await _settle(t);
    }

    testWidgets('D-1 초대 발송 시각을 KST 로 — 기기 시간대 무관', (t) async {
      await open(t, _app());
      final s = _texts(t);
      expect(s, contains('초대 발송'));
      expect(s, contains('2030.10.15 23:00'),
          reason: '14:00Z = KST 23:00 (날짜별 명단 `10/15 23:00 발송` 과 같은 시각)');
      expect(s, contains('수락 기한'));
      expect(s, contains('2030.10.16 23:00'));
      expect(s, isNot(contains('지원일')), reason: '초대는 지원이 아니다');
      _overflows(t);
    });

    testWidgets('D-2 확인 대기 — 확정 약속 대신 근로자 수락을 말한다', (t) async {
      await open(t, _app());
      final s = _texts(t);
      expect(s, isNot(contains('확정할 수 있어요')));
      expect(s, contains('근로자가 수락하려면 신분증 확인이 필요해요.'));
      expect(s, contains('[확인 완료]를 누르면 근로자가 10/16 23:00까지 수락할 수 있어요.'));
      expect(findVisibleText('승인'), findsNothing);
      _overflows(t);
    });

    testWidgets('D-3 동의 전 — 동의가 먼저라고 말한다', (t) async {
      await open(t, _app(consented: false),
          review: _review(consentBlock: '근로자가 서류 접근에 동의하지 않았습니다.'));
      final s = _texts(t);
      expect(s, contains('근로자가 서류 열람에 동의하면 신분증을 확인할 수 있어요.'));
      expect(s, isNot(contains('확정할 수 있어요')));
      _overflows(t);
    });

    testWidgets('D-4 확인 완료 — 근로자가 기한 안에 수락하면 확정', (t) async {
      await open(t, _app(), review: _review(matchingReady: true));
      final s = _texts(t);
      expect(s, contains('신분증 확인이 끝났어요.'));
      expect(s, contains('근로자가 10/16 23:00까지 수락하면 확정돼요.'));
      expect(s, isNot(contains('확정할 수 있어요')));
      _overflows(t);
    });

    testWidgets('D-5 기한 종료 — 수락할 수 없다고 말한다', (t) async {
      await open(t,
          _app(
            workDate: _kstMidnight(2020, 10, 19),
            invitedAt: DateTime.utc(2020, 10, 15, 14),
            inviteExpiresAt: DateTime.utc(2020, 10, 16, 14),
          ),
          review: _review(matchingReady: true));
      final s = _texts(t);
      expect(s, contains('초대 수락 기한이 지났어요.'));
      expect(s, isNot(contains('수락하면 확정돼요')));
      _overflows(t);
    });

    testWidgets('D-6 직접 지원은 `지원일` 그대로 — 시각은 KST', (t) async {
      await open(t, _app(id: 'p1', status: AppStatus.pending));
      final s = _texts(t);
      expect(s, contains('지원일'));
      expect(s, contains('2030.10.14 10:00'), reason: '01:00Z = KST 10:00');
      expect(s, isNot(contains('초대 발송')));
      _overflows(t);
    });

    for (final (w, scale) in const [
      (320.0, 1.0), (320.0, 1.3), (360.0, 1.3), (411.0, 1.3),
    ]) {
      testWidgets('D-7 라벨 ${w.toInt()}dp × $scale — 글자 단위로 쪼개지지 않고 값과 붙지 않는다',
          (t) async {
        await open(t, _app(), w: w, scale: scale);
        expect(_overflows(t), isEmpty);
        final label = find.text('지원 업무');
        final value = find.text('QA 분류');
        expect(label, findsOneWidget);
        // 한 줄이면 라벨 높이 == 값 높이 (`지원 업/무` 이면 두 배).
        expect(t.getSize(label).height, t.getSize(value).height,
            reason: '라벨이 줄을 바꿨다');
        // 라벨과 값 사이에 간격이 있다.
        expect(t.getTopLeft(value).dx - t.getTopRight(label).dx,
            greaterThanOrEqualTo(4.0));
      });
    }

    testWidgets('D-8 320dp × 2.0 — 넘침 없음 · 라벨과 값이 겹치지 않는다', (t) async {
      await open(t, _app(), w: 320, scale: 2.0);
      expect(_overflows(t), isEmpty);
      final label = find.text('지원 업무');
      final value = find.text('QA 분류');
      expect(t.getTopLeft(value).dx, greaterThan(t.getTopRight(label).dx));
      // 서류 확인 영역 CTA 에 닿는다.
      final btn = find.text('신분증 보기');
      await t.ensureVisible(btn);
      await t.pump();
      expect(btn.hitTestable(), findsOneWidget);
      _overflows(t);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // L. 날짜별 명단 — 같은 초대가 같은 문구로
  // ══════════════════════════════════════════════════════════════════════
  group('L 날짜별 명단 연결', () {
    testWidgets('L-1 같은 초대 inv1 이 `초대 중 · 서류 확인 가능` 과 KST 발송 시각으로 그려진다',
        (t) async {
      final invite = _app();
      final reads = DayApplicantsReads(
        pendingApplications: ({required date, required businessId, purpose}) async =>
            const [],
        confirmedWorkers: ({required date, required businessId}) async => const [],
        dayStaffing: ({required businessId, required dayStartMs}) async => [
          DayStaffingRow(
            toId: 'to1', toTitle: 'QA-N E2 consent', slotId: 'slot1', wdId: _wd,
            workType: 'QA 분류', startTime: '14:00', endTime: '15:00',
            requiredCount: 1, confirmedCount: 0, pendingCount: 1,
          ),
        ],
        dayInvitations: ({required date, required businessId}) async => [invite],
        hasWorkedMap: ({required businessId, required date}) async => const {},
        noShowApplicationIds: ({required businessId, required date}) async =>
            <String>{},
        usersBatch: (uids, {required businessId, purpose}) async => {
          for (final u in uids)
            u: UserModel(uid: u, username: u, name: '큐에이이',
                email: '$u@test.local', role: UserRole.USER),
        },
        weeklyAttendance: ({required businessId, required weekStart,
                required weekEnd}) async =>
            <String, List<AttendanceModel>>{},
        slotWorkDetailCapacities: (toId, slotId) async => const {_wd: 1},
        slotWorkDetails: (toId, slotId) async => <WorkDetailData>[],
        to: (toId) async => null,
        contractStatusBatch: (ids, {required businessId}) async =>
            const ContractStatusBatch(),
      );
      _size(t, 411, h: 1400);
      await t.pumpWidget(_host(DayApplicantsDialog(
        date: _kstMidnight(2030, 10, 19),
        businessIds: const [_biz],
        businesses: [
          BusinessModel(
            id: _biz, name: '테스트 사업장', businessNumber: '000-00-00000',
            category: '음식점', subCategory: '한식',
            address: '서울특별시 강남구 테헤란로 1', ownerId: 'owner1',
            createdAt: DateTime(2030, 9, 1)),
        ],
        reads: reads,
      )));
      await _settle(t);
      while (t.takeException() != null) {}
      final s = _texts(t);
      // 업무별 창의 행(W-4)과 같은 문구·같은 시각.
      expect(s, contains('초대 중 · 서류 확인 가능'));
      expect(s, contains('10/15 23:00 발송'));
      expect(s, contains(InviteRosterRow.timesLine(invite).split(' · ').first));
    });
  });
}
