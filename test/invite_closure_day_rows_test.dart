// [INVITE-CLOSURE-PROJECTION] 관리자 날짜별 명단 — 공개 모집 종료와 초대 효력을 나눈다.
//
//   실제 DayApplicantsDialog 를 서버 row(DayStaffingRow) 와 초대로 띄운다.
//     DR-01 공개 접수만 자동 마감(inviteEnded=false) → `초대 중 · 공개 모집 마감`, 초대 CTA 없음
//     DR-02 수동 마감 등(inviteEnded=true) → `모집 종료`
//     DR-03 구버전 서버(inviteEnded 없음) → isClosed 를 따른다(`모집 종료`)
//     DR-04 자동 마감 + 단위 정원 소진 → `모집 완료 · 정원 마감`
//     DR-05 열린 단위 → `초대 중`
//     DR-06 320dp × 글자 2.0 — DR-01 넘침 0
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';

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

ApplicationModel _invite({String status = AppStatus.invited, bool consented = true}) =>
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
      workDate: _date,
      appliedAt: _date.subtract(const Duration(days: 1)),
      invitedAt: _date.subtract(const Duration(days: 1)),
      documentAccessConsentGiven: consented,
      documentAccessConsentVersion:
          consented ? DocumentAccessConsent.inviteVersion : null,
    );

DayApplicantsReads _reads(List<ApplicationModel> invites, DayStaffingRow row) => DayApplicantsReads(
      pendingApplications: ({required date, required businessId, purpose}) async =>
          const [],
      confirmedWorkers: ({required date, required businessId}) async => const [],
      dayStaffing: ({required businessId, required dayStartMs}) async => [row],
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


DayStaffingRow _row({required bool closed, bool? inviteEnded, int confirmed = 0, bool inviteOpen = false}) =>
    DayStaffingRow(
      toId: 'to1', toTitle: '테스트 공고', slotId: 'slot1', wdId: 'wd1',
      workType: '홀서빙', startTime: '20:00', endTime: '22:00',
      requiredCount: 2, confirmedCount: confirmed, pendingCount: 1,
      isClosed: closed, inviteEnded: inviteEnded, inviteOpen: inviteOpen,
    );

Future<void> _open(WidgetTester t, DayStaffingRow row,
    {Size size = const Size(1080, 2400), double dpr = 3.0, double textScale = 1.0,
    List<ApplicationModel>? invites}) async {
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
          reads: _reads(invites ?? [_invite()], row),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 30; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

String _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .where((s) => s.isNotEmpty)
    .join(' | ');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('DR-01 공개 접수만 자동 마감 → 초대는 살아 있다, 공개 모집 CTA 는 다시 열리지 않는다', (t) async {
    await _open(t, _row(closed: true, inviteEnded: false));
    final s = _texts(t);
    expect(s, contains('초대 중 · 공개 모집 마감 (1명)'));
    expect(s, contains('초대 중 · 서류 확인 가능'));
    expect(s.contains('모집 종료 (1명)'), isFalse);
    expect(s.contains('인력 초대 ('), isFalse, reason: '새 초대·공개 모집 CTA 를 열지 않는다');
  });

  testWidgets('DR-02 초대 효력 종료(수동 마감 등) → 모집 종료', (t) async {
    await _open(t, _row(closed: true, inviteEnded: true));
    final s = _texts(t);
    expect(s, contains('모집 종료 (1명)'));
    expect(s.contains('초대 중 ·'), isFalse);
  });

  testWidgets('DR-03 구버전 서버(inviteEnded 없음) → isClosed 를 따른다', (t) async {
    expect(DayStaffingRow.tryFromMap({'toId': 'to1', 'slotId': 's', 'wdId': 'w', 'isClosed': true})!.inviteEnded, isTrue);
    expect(DayStaffingRow.tryFromMap({'toId': 'to1', 'slotId': 's', 'wdId': 'w', 'isClosed': true,
      'inviteEnded': false})!.inviteEnded, isFalse);
    await _open(t, _row(closed: true));
    expect(_texts(t), contains('모집 종료 (1명)'));
  });

  testWidgets('DR-04 자동 마감 + 단위 정원 소진 → 모집 완료 · 정원 마감', (t) async {
    await _open(t, _row(closed: true, inviteEnded: false, confirmed: 2));
    expect(_texts(t), contains('모집 완료 · 정원 마감 (1명)'));
  });

  testWidgets('DR-05 열린 단위 → 초대 중', (t) async {
    await _open(t, _row(closed: false));
    final s = _texts(t);
    expect(s, contains('초대 중 (1명)'));
    expect(s.contains('공개 모집 마감'), isFalse);
  });

  // ── [INVITE-TERMINAL] 공개 지원 마감 후 비공개 인력 초대 ──────────────────
  testWidgets('DR-07 지원자 0명인 자동 마감 단위 — 서버가 inviteOpen 이면 그룹이 서고 `인력 초대` 가 뜬다', (t) async {
    await _open(t, _row(closed: true, inviteEnded: false, inviteOpen: true), invites: const []);
    final s = _texts(t);
    expect(s, contains('공개 지원은 마감됐어요 · 근무 시작 전까지 인력 초대는 가능해요'));
    expect(s, contains('인력 초대 (2명 부족)'));
  });

  testWidgets('DR-08 수동 마감(inviteEnded) → 초대 행동 없음', (t) async {
    await _open(t, _row(closed: true, inviteEnded: true, inviteOpen: false));
    final s = _texts(t);
    expect(s.contains('인력 초대 ('), isFalse);
    expect(s.contains('공개 지원은 마감됐어요'), isFalse);
  });

  testWidgets('DR-09 근무 시작 경과·구버전 서버(inviteOpen false) → 마감 단위로 새 그룹·CTA 없음', (t) async {
    await _open(t, _row(closed: true, inviteEnded: false), invites: const []);
    final s = _texts(t);
    expect(s.contains('인력 초대 ('), isFalse);
    expect(s.contains('홀서빙'), isFalse, reason: '채울 수 없는 마감 단위로 그룹을 세우지 않는다');
  });

  testWidgets('DR-10 사업장 쪽 종료로 철회된 초대는 사유를 말한다', (t) async {
    final canceled = ApplicationModel.fromMap({
      'uid': _worker, 'toId': 'to1', 'slotId': 'slot1', 'wdId': 'wd1', 'businessId': _biz,
      'businessName': '테스트 사업장', 'toTitle': '테스트 공고', 'selectedWorkType': '홀서빙',
      'startTime': '20:00', 'endTime': '22:00', 'wage': 13000, 'status': 'CANCELED',
      'cancelReason': 'RECRUIT_CLOSED',
      'workDate': Timestamp.fromDate(_date), 'appliedAt': Timestamp.fromDate(_date),
      'invitedAt': Timestamp.fromDate(_date.subtract(const Duration(hours: 3))),
    }, 'inv9');
    await _open(t, _row(closed: true, inviteEnded: true), invites: [canceled]);
    expect(_texts(t), contains('모집 마감으로 초대 종료'));
    expect(canceled.workerEndReasonSentence, '사업장이 모집을 마감해 초대가 취소됐어요');
  });

  testWidgets('DR-06 320dp × 2.0 — 자동 마감 초대 섹션 넘침 0', (t) async {
    final errors = <FlutterErrorDetails>[];
    final prev = FlutterError.onError;
    FlutterError.onError = errors.add;
    await _open(t, _row(closed: true, inviteEnded: false),
        size: const Size(320, 2400), dpr: 1.0, textScale: 2.0);
    FlutterError.onError = prev;
    expect(errors.where((e) => e.toString().contains('overflowed')), isEmpty);
    expect(_texts(t), contains('초대 중 · 공개 모집 마감 (1명)'));
  });
}
