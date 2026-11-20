// [INVITE-PREACCEPT] 관리자: 날짜별 지원자 화면 → 초대 행 → 근로자 상세의 `서류 확인`.
//
//   실제 DayApplicantsDialog 를 띄우고, 실제 초대 행을 눌러 실제 WorkerDetailDialog
//   를 연다. 서버 응답(callableGetApplicantDocumentReview)만 테스트가 대신 준다 —
//   판정·권한·버전은 서버 테스트(functions/test/invite_preaccept_consent.test.js)가
//   실행으로 본다. 이 파일은 **입구와 렌더**를 본다.
//
//     PAN-01 동의한 초대: 행 라벨 → 탭 → 상세 → `신분증 보기`·`확인 완료` 가 보인다
//     PAN-02 동의 전 초대: 상세가 서버의 거절 사유를 그대로 말한다(검토 버튼 없음)
//     PAN-03 초대 상세에는 확정/거절 버튼이 없다 — 초대는 근로자가 수락한다
//     PAN-04 상세의 다른 조회가 실패해도 서류 검토 영역은 로드된다
//     PAN-05 320dp × 글자 2.0 — 상세의 서류 확인 영역·버튼에 닿을 수 있다(넘침 0)
//     PAN-06 끝난 초대(만료) 행은 눌러도 열리지 않는다
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart'; // [DU255] keepWords 문구는 보이는 글자로 찾는다
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart' show MemberPermissions;
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_reads.dart';
import 'package:ALfit/services/applicant_document_review_service.dart';
import 'package:ALfit/services/contract_service.dart';
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

const _biz = 'biz1';
const _worker = 'w9';

/// 사업장 관리자 — 권한 판정은 이 사업장에 대해 허용.
class _AdminP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'owner1', username: 'owner1', name: '관리자',
        email: 'owner1@test.local', role: UserRole.BUSINESS_ADMIN);
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
}

BusinessModel _business() => BusinessModel(
      id: _biz,
      name: '테스트 사업장',
      businessNumber: '000-00-00000',
      category: '음식점',
      subCategory: '한식',
      address: '서울특별시 강남구 테헤란로 1',
      ownerId: 'owner1',
      createdAt: DateTime(2026, 9, 1),
    );

final _date = DateTime(2026, 10, 20);

ApplicationModel _invite({String status = AppStatus.invited, bool consented = true, DateTime? workDate, DateTime? expiresAt}) =>
    ApplicationModel(
      id: 'inv1',
      uid: _worker,
      toId: 'to1',
      slotId: 'slot1',
      wdId: 'wd1',
      businessId: _biz,
      businessName: '테스트 사업장',
      toTitle: '테스트 공고',
      selectedWorkType: '홀서빙',
      startTime: '20:00',
      endTime: '22:00',
      wage: 13000,
      wageType: 'hourly',
      status: status,
      workDate: workDate ?? _date,
      appliedAt: _date.subtract(const Duration(days: 1)),
      invitedAt: _date.subtract(const Duration(days: 1)),
      inviteExpiresAt: expiresAt,
      documentAccessConsentGiven: consented,
      documentAccessConsentVersion:
          consented ? DocumentAccessConsent.inviteVersion : null,
    );

DayApplicantsReads _reads(List<ApplicationModel> invites) => DayApplicantsReads(
      pendingApplications: ({required date, required businessId, purpose}) async =>
          const [],
      confirmedWorkers: ({required date, required businessId}) async => const [],
      dayStaffing: ({required businessId, required dayStartMs}) async => [
        DayStaffingRow(
          toId: 'to1', toTitle: '테스트 공고', slotId: 'slot1', wdId: 'wd1',
          workType: '홀서빙', startTime: '20:00', endTime: '22:00',
          requiredCount: 2, confirmedCount: 0, pendingCount: 1,
        ),
      ],
      dayInvitations: ({required date, required businessId}) async => invites,
      hasWorkedMap: ({required businessId, required date}) async => const {},
      noShowApplicationIds: ({required businessId, required date}) async =>
          <String>{},
      usersBatch: (uids, {required businessId, purpose}) async => {
        for (final u in uids)
          u: UserModel(uid: u, username: u, name: '초대근로자',
              email: '$u@test.local', role: UserRole.USER),
      },
      weeklyAttendance: ({required businessId, required weekStart,
              required weekEnd}) async =>
          <String, List<AttendanceModel>>{},
      slotWorkDetailCapacities: (toId, slotId) async => const {'wd1': 2},
      slotWorkDetails: (toId, slotId) async => <WorkDetailData>[],
      to: (toId) async => null,
      contractStatusBatch: (ids, {required businessId}) async =>
          const ContractStatusBatch(),
    );

/// 서버의 callableGetApplicantDocumentReview 응답을 대신한다.
class _FakeReview extends Fake implements ApplicantDocumentReviewService {
  _FakeReview(this.map);
  final Map<String, dynamic> map;
  int loads = 0;
  @override
  Future<ApplicantDocumentReview> load({
    required String applicationId,
    required String businessId,
  }) async {
    loads++;
    return ApplicantDocumentReview.fromMap(map);
  }
}

/// 서버 조회 실패(권한·망 오류) — 상세는 오류로 말해야 한다.
class _FailReview extends Fake implements ApplicantDocumentReviewService {
  @override
  Future<ApplicantDocumentReview> load({
    required String applicationId,
    required String businessId,
  }) async =>
      throw Exception('permission-denied');
}

Map<String, dynamic> _reviewMap({String? consentBlock}) => {
      'workerUid': _worker,
      'canReviewDocuments': true,
      'consentBlock': consentBlock,
      'versions': {'id': 2, 'bankbook': 1, 'account': 1},
      'readiness': {'ready': false, 'idDecision': 'NOT_REVIEWED',
        'bankDecision': 'NOT_REVIEWED'},
      'documents': {'hasIdCard': true, 'hasBankbook': true},
      'matchingReadiness': {'ready': false, 'state': 'ID_UNASSESSED',
        'reason': '신분증 확인이 필요합니다. 지원자 상세에서 확인해주세요.'},
    };

Future<void> _open(WidgetTester t, List<ApplicationModel> invites,
    {Size size = const Size(1080, 2400), double dpr = 3.0, double textScale = 1.0}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = dpr;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _AdminP(),
    child: MaterialApp(
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: DayApplicantsDialog(
          date: _date,
          businessIds: const [_biz],
          businesses: [_business()],
          reads: _reads(invites),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 30; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 30; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

String _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .where((s) => s.isNotEmpty)
    .join(' | ');

/// 상세의 다른 조회가 실패하며 남기는 예외(토스트·플랫폼 없음)를 비운다.
void _drainExceptions(WidgetTester t) {
  while (t.takeException() != null) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  tearDown(() => ApplicantDocumentReviewService.debugOverride = null);

  Future<void> tapInviteRow(WidgetTester t) async {
    final row = find.text('초대근로자');
    expect(row, findsWidgets, reason: '초대 행이 그려져야 한다');
    await t.ensureVisible(row.first);
    await t.tap(row.first);
    await _settle(t);
    _drainExceptions(t);
  }

  testWidgets('PAN-01 동의한 초대 → 상세의 서류 확인 영역에서 검토할 수 있다', (t) async {
    final fake = _FakeReview(_reviewMap());
    ApplicantDocumentReviewService.debugOverride = fake;
    await _open(t, [_invite()]);
    expect(_texts(t), contains('초대 중 · 서류 확인 가능'));
    await tapInviteRow(t);
    expect(find.byType(WorkerDetailDialog), findsOneWidget);
    expect(fake.loads, greaterThanOrEqualTo(1), reason: '서버 판정을 읽으러 갔다');
    final s = _texts(t);
    expect(s, contains('서류 확인'));
    expect(s, contains('신분증 보기'));
    expect(s, contains('확인 완료'));
  });

  // [CONSENT-PENDING-COPY 10-23] 서버의 "동의하지 않았습니다"는 화면에서 "아직 동의하지 않아"로
  //   바꿔 말한다(거부가 아니라 아직 전). 다른 거절 사유는 그대로 — doc_gate_copy_test CL-2.
  testWidgets('PAN-02 동의 전 초대 → 아직 동의 전이라고 말한다', (t) async {
    ApplicantDocumentReviewService.debugOverride = _FakeReview(
        _reviewMap(consentBlock: ApplicantDocumentReview.serverConsentMissingText));
    await _open(t, [_invite(consented: false)]);
    expect(_texts(t), contains('초대 중 · 서류 동의 전'));
    await tapInviteRow(t);
    expect(_texts(t), contains('근로자가 아직 서류 열람에 동의하지 않아 지금은 서류를 볼 수 없어요.'));
    expect(_texts(t), isNot(contains(ApplicantDocumentReview.serverConsentMissingText)));
  });

  testWidgets('PAN-03 초대 상세에는 확정·거절 버튼이 없다', (t) async {
    ApplicantDocumentReviewService.debugOverride = _FakeReview(_reviewMap());
    await _open(t, [_invite()]);
    await tapInviteRow(t);
    final d = t.widget<WorkerDetailDialog>(find.byType(WorkerDetailDialog));
    expect(d.showApprovalButtons, isFalse);
    expect(d.isConfirmed, isFalse);
    expect(find.ancestor(of: findVisibleText('확정'), matching: find.byType(ElevatedButton)), findsNothing);
  });

  testWidgets('PAN-04 다른 부가 조회가 실패해도 서류 검토는 로드된다', (t) async {
    // 이 테스트 환경에는 Firestore 플랫폼이 없다 — 상세의 근무 이력 등
    //   부가 조회는 실패한다. 그래도 서류 검토 요청은 나가야 한다.
    final fake = _FakeReview(_reviewMap());
    ApplicantDocumentReviewService.debugOverride = fake;
    await _open(t, [_invite()]);
    await tapInviteRow(t);
    expect(fake.loads, 1);
    expect(_texts(t), contains('신분증 보기'));
  });

  testWidgets('PAN-05 320dp × 2.0 — 서류 확인 버튼에 닿을 수 있다', (t) async {
    ApplicantDocumentReviewService.debugOverride = _FakeReview(_reviewMap());
    await _open(t, [_invite()], size: const Size(320, 1200), dpr: 1.0, textScale: 2.0);
    _drainExceptions(t);
    await tapInviteRow(t);
    final btn = find.text('신분증 보기');
    expect(btn, findsOneWidget);
    await t.ensureVisible(btn);
    await t.pump();
    expect(btn.hitTestable(), findsOneWidget);
    final e = t.takeException();
    expect(e == null || !e.toString().contains('overflowed'), isTrue,
        reason: '서류 확인 영역이 넘치면 안 된다: $e');
  });

  // [DOC-APP-CLOSEOUT.10] 초대 상세의 신분증 상태 — 지원 상세와 같은 서버 사실(등록 기록 · 확정 판정 사유).
  //   독자는 관리자, 수락은 근로자. 응답에 근거가 없으면 미등록·정상으로 추정하지 않는다.
  Map<String, dynamic> missing({bool? has, String reason = '', bool consent = true}) {
    final m = _reviewMap(consentBlock: consent ? null : ApplicantDocumentReview.serverConsentMissingText);
    m['matchingReadiness'] = {'ready': false, 'state': 'ID_MISSING', 'reason': reason};
    m['documents'] = {if (has != null) 'hasIdCard': has, 'hasBankbook': true};
    return m;
  }
  Future<String> detail(WidgetTester t, Map<String, dynamic> m) async {
    ApplicantDocumentReviewService.debugOverride = _FakeReview(m);
    // 수락 기한이 아직 남은 초대 — 고정 날짜(10-20)는 오늘 기준 만료라 만료 문구가 먼저 나온다.
    final now = DateTime.now();
    await _open(t, [_invite(workDate: now.add(const Duration(days: 3)), expiresAt: now.add(const Duration(days: 1)))]);
    await tapInviteRow(t);
    return _texts(t);
  }

  testWidgets('PAN-07 미등록 → 근로자가 등록하면 수락 가능 · 요청 버튼·미등록 아닌 말 없음', (t) async {
    final s = await detail(t, missing(has: false, reason: '신분증이 등록되어 있지 않습니다.'));
    expect(s, contains('근로자가 아직 신분증을 등록하지 않았어요.'));
    expect(s, contains('미등록'));
    expect(s, isNot(contains('신분증 보기')));
    expect(s, isNot(contains('[다시 등록 요청]')));
  });
  testWidgets('PAN-08 확인 중 → 아직 확인 중 · 미등록/완료로 말하지 않음', (t) async {
    final s = await detail(t, missing(has: true, reason: '신분증 파일을 확인하고 있습니다. 잠시 후 다시 시도해주세요.'));
    expect(s, contains('신분증 사진 파일을 확인하는 중이라 아직 수락할 수 없어요.'));
    expect(s, isNot(contains('등록하지 않았어요')));
    expect(s, isNot(contains('신분증 확인이 끝났어요')));
  });
  testWidgets('PAN-09 파일 없음 → 등록 기록은 있으나 파일 없음 · 보이는 [다시 등록 요청]으로 연결', (t) async {
    final s = await detail(t, missing(has: true, reason: '신분증 파일을 찾을 수 없습니다. 신분증을 다시 등록해야 합니다.'));
    expect(s, contains('신분증 사진 파일을 찾을 수 없어 근로자가 수락할 수 없어요.'));
    expect(s, contains('[다시 등록 요청]으로'));
    expect(find.text('다시 등록 요청'), findsWidgets, reason: '말한 버튼이 화면에 있다');
  });
  testWidgets('PAN-10 파일 없음 · 동의 전 → 없는 버튼을 말하지 않는다', (t) async {
    final s = await detail(t, missing(has: true, reason: '신분증 파일을 찾을 수 없습니다. 신분증을 다시 등록해야 합니다.', consent: false));
    expect(s, contains('근로자가 신분증을 다시 등록하면 수락할 수 있어요.'));
    expect(s, isNot(contains('[다시 등록 요청]으로')));
  });
  testWidgets('PAN-11 구 응답(등록 기록 없음) → 확인 불가 · 미등록으로 추정하지 않음', (t) async {
    final s = await detail(t, missing(has: null, reason: '신분증이 등록되어 있지 않습니다.'));
    expect(s, contains('신분증 상태를 확인하지 못했어요.'));
    expect(s, contains('확인 불가'));
    expect(s, isNot(contains('미등록')));
    expect(s, isNot(contains('등록하지 않았어요')));
  });
  testWidgets('PAN-12 조회 실패 → 오류로 말하고 다시 불러오기 · 미등록·정상 추정 없음', (t) async {
    ApplicantDocumentReviewService.debugOverride = _FailReview();
    await _open(t, [_invite()]);
    await tapInviteRow(t);
    final s = _texts(t);
    expect(s, contains('서류 상태를 불러오지 못해'));
    expect(s, contains('다시 불러오기'));
    expect(s, isNot(contains('미등록')));
    expect(s, isNot(contains('신분증 확인이 끝났어요')));
  });
  testWidgets('PAN-13 정상(자동 일치) → 등록·확인 사실만 · 원본 열람을 필수로 요구하지 않음 · 닫기 동작 그대로', (t) async {
    final m = _reviewMap();
    m['matchingReadiness'] = {'ready': true, 'state': 'READY_AUTO', 'reason': null};
    final s = await detail(t, m);
    expect(s, contains('신분증 확인이 끝났어요.'));
    expect(s, contains('서류 정보 일치'), reason: '자동 대조 결과는 수동 검토 완료와 다른 말이다');
    expect(s, isNot(contains('[확인 완료]를 누르면')));
    expect(find.byType(WorkerDetailDialog), findsOneWidget);
    final d = t.widget<WorkerDetailDialog>(find.byType(WorkerDetailDialog));
    expect(d.showApprovalButtons, isFalse, reason: '초대는 근로자가 수락한다 — 확정·거절 버튼 없음');
  });

  testWidgets('PAN-06 끝난 초대(만료) 행은 상세를 열지 않는다', (t) async {
    final fake = _FakeReview(_reviewMap());
    ApplicantDocumentReviewService.debugOverride = fake;
    await _open(t, [_invite(status: AppStatus.expired)]);
    final row = find.text('초대근로자');
    if (row.evaluate().isNotEmpty) {
      await t.ensureVisible(row.first);
      await t.tap(row.first, warnIfMissed: false);
      await _settle(t);
    }
    expect(find.byType(WorkerDetailDialog), findsNothing);
    expect(fake.loads, 0);
  });
}
