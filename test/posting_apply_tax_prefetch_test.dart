// [R8-PERCEIVED.1] 공고 상세 `지원하기` 탭 → 첫 반응 대기.
//
// ── 측정에서 본 것 (2026-10-19, DEV Cloud Run 지표 14일·1분 단위) ──────
//   `callableGetTaxIdentityStatus` 는 지원 버튼을 눌렀을 때만 불린다. 그래서
//   거의 언제나 콜드다 — 요청 11건 중 9건이 컨테이너 시작이 낀 분에 있었고
//   (시작 8회, 시작 p50 1,174ms), 그 분들의 요청 p50 은 970ms 였다.
//   공고 상세는 이 응답을 **화면 변화 없이** 기다린 뒤에야 확인 시트를 연다.
//
// ── 고친 것 ───────────────────────────────────────────────────────────
//   상세를 여는 순간(이미 스피너가 떠 있는 동안) 같은 조회를 먼저 출발시키고,
//   탭에서 그 결과를 1회 소비한다. 60초가 지났거나 조회가 실패했으면 탭에서
//   다시 읽는다(기존과 같다). 판정(`meetsApplyPrerequisites`)·서버 최종 판단은
//   바꾸지 않는다. 첫 렌더는 이 조회를 기다리지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/business_work_type_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/core/work_detail_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/job_posting_reads.dart';
import 'package:ALfit/services/work_type_guide_resolver.dart';
import 'package:ALfit/screens/common/job_posting_screen.dart';
import 'package:ALfit/services/tax_identity_service.dart';
import 'package:ALfit/utils/identity_identifier.dart';
import 'package:ALfit/widgets/dialogs/apply/multi_apply_confirm_sheet.dart';

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

const _kUid = 'u1';

class _P extends UserProvider {
  // 지원 자격은 이 테스트의 주제가 아니다 — 차단 사유가 하나라도 있으면
  //   CTA 가 그 사유를 말하는 다른 분기로 가므로, 준비 완료 상태로 둔다.
  @override
  UserModel? get currentUser => UserModel(
        uid: _kUid,
        username: _kUid,
        name: 'QA 지원자',
        email: '$_kUid@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시'),
        accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 9, 1),
        idCardImagePath: 'id_cards/$_kUid/front.jpg',
        isIdVerified: true,
        bankName: '국민은행',
        accountNumber: '000000000000',
        accountHolder: 'QA 지원자',
        bankbookImagePath: 'bankbooks/$_kUid/b.jpg',
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

DateTime _kstInstant(int y, int mo, int d) =>
    DateTime.utc(y, mo, d).subtract(const Duration(hours: 9));

/// 늘 미래인 날 — 날짜가 지나면 `마감된 공고` 로 바뀌어 다른 분기가 된다.
DateTime _futureKstDay(int plusDays) {
  final k = DateTime.now().toUtc().add(Duration(hours: 9, days: plusDays));
  return _kstInstant(k.year, k.month, k.day);
}

final _day = _futureKstDay(2);

WorkDetailData _wd({String id = 'wd-1', String type = 'QA 분류'}) =>
    WorkDetailData(
      wdId: id,
      workType: type,
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 12000,
      wageType: 'hourly',
      requiredCount: 2,
      startTime: '10:00',
      endTime: '11:00',
      order: 0,
    );

SlotModel _slot(List<WorkDetailData> details) => SlotModel(
      id: 'slot1',
      toId: 'to1',
      date: _day,
      workDetails: details,
      status: SlotStatus.open,
      confirmedCount: 0,
      createdAt: DateTime(2025),
    );

TOModel _to() => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '골든패스 테스트 사업장',
      type: 'flex',
      title: 'QA 공고',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 2,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

BusinessModel _business() => BusinessModel(
      id: 'biz1',
      name: '골든패스 테스트 사업장',
      ownerId: 'admin1',
      businessNumber: '000-00-00000',
      address: '경기도 평택시',
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: DateTime(2025),
    );

ApplicationModel _myApp({
  required String status,
  String wdId = 'wd-1',
}) =>
    ApplicationModel(
      id: 'app1',
      toId: 'to1',
      slotId: 'slot1',
      wdId: wdId,
      uid: _kUid,
      businessId: 'biz1',
      businessName: '골든패스 테스트 사업장',
      toTitle: 'QA 공고',
      status: status,
      selectedWorkType: 'QA 분류',
      startTime: '10:00',
      endTime: '11:00',
      wage: 12000,
      workDate: _day,
      appliedAt: DateTime(2026, 10, 14),
    );

JobPostingReads _reads({
  required List<WorkDetailData> details,
  List<ApplicationModel> myApps = const [],
  required Future<TaxIdentityStatus> Function() taxStatus,
  DateTime Function()? now,
}) =>
    JobPostingReads(
      taxStatus: taxStatus,
      now: now ?? DateTime.now,
      toOrFailure: (id) async => (to: _to(), failed: false),
      workDetails: (id) async => const <WorkDetailModel>[],
      businessById: (id) async => _business(),
      slots: (id, {bool visibleOnly = true}) async => [_slot(details)],
      myApplications: (uid) async => myApps,
      workTypeCatalog: (id) async => WorkTypeCatalog.empty,
      applicationOnce: (id) async => null,
    );

Future<void> _pump(WidgetTester t, JobPostingReads reads) async {
  t.view.physicalSize = const Size(390, 1800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(milliseconds: 50));
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        home: JobPostingScreen(
          to: _to(),
          workDetails: const [],
          slotDate: _day,
          reads: reads,
        ),
      ),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

List<String> _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    // [DU1] 렌더용 단어 결합 문자(\u2060)는 보이는 문구가 아니다 — 제거하고 비교한다
    .map((w) => (w.data ?? '').replaceAll('\u2060', ''))
    .where((s) => s.isNotEmpty)
    .toList();


class _Tax {
  _Tax(this.delay, {this.failFirst = false});
  final Duration delay;
  final bool failFirst;
  final List<Duration> calledAt = [];
  final Stopwatch clock = Stopwatch();
  Future<TaxIdentityStatus> call() {
    calledAt.add(clock.elapsed);
    final fail = failFirst && calledAt.length == 1;
    return Future.delayed(delay, () => fail
        ? const TaxIdentityStatus.unknown()
        : const TaxIdentityStatus(
            registered: true,
            identifierType: 'RRN',
            collectionEnabled: false,
            documentMatch: DocFieldOutcome.unassessed,
            documentMatchCurrent: false,
            loadFailed: false,
          ));
  }
}

/// 업무 하나를 고르고 CTA 를 누른 뒤, 확인 시트가 보일 때까지의 가짜 시간(ms).
Future<int> _tapApplyAndWaitSheet(WidgetTester t) async {
  final pick = find.text('선택'); // OutlinedButton.icon 은 하위 타입이라 widgetWithText 로 안 잡힌다
  if (pick.evaluate().isNotEmpty) {
    await t.tap(pick.first);
    await t.pump();
  }
  final cta = find.textContaining('지원하기');
  expect(cta, findsWidgets, reason: 'CTA 가 보여야 한다');
  await t.tap(cta.last);
  var ms = 0;
  while (find.byType(MultiApplyConfirmSheet).evaluate().isEmpty && ms < 5000) {
    await t.pump(const Duration(milliseconds: 50));
    ms += 50;
  }
  return ms;
}

Future<void> _closeSheet(WidgetTester t) async {
  Navigator.of(t.element(find.byType(MultiApplyConfirmSheet)), rootNavigator: true).pop();
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

const _delay = Duration(milliseconds: 2000);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('TP-1 상세가 이미 떠 있으면 탭은 세무 조회를 다시 기다리지 않는다', (t) async {
    final tax = _Tax(_delay)..clock.start();
    await _pump(t, _reads(details: [_wd()], taxStatus: tax.call)); // 2.5초 경과
    final openCalls = tax.calledAt.length;
    final waited = await _tapApplyAndWaitSheet(t);
    // ignore: avoid_print
    print('[TP-1] open calls=$openCalls · tap→sheet ${waited}ms · total calls=${tax.calledAt.length}');
    expect(find.byType(MultiApplyConfirmSheet), findsOneWidget);
    expect(openCalls, 1, reason: '상세를 여는 동안 한 번 출발한다');
    expect(tax.calledAt.length, 1, reason: '탭에서 같은 조회를 다시 보내지 않는다');
    expect(waited, lessThan(_delay.inMilliseconds), reason: '탭 → 시트가 조회 지연만큼 걸리면 안 된다');
  });

  testWidgets('TP-2 첫 렌더는 세무 조회를 기다리지 않는다(끝나지 않아도 CTA 가 보인다)', (t) async {
    final tax = _Tax(const Duration(days: 1))..clock.start();
    await _pump(t, _reads(details: [_wd()], taxStatus: tax.call));
    expect(_texts(t), contains('지원할 업무를 선택해주세요'));
    await t.pump(const Duration(days: 1)); // 매달린 타이머 정리
  });

  testWidgets('TP-3 먼저 받은 값이 실패면 탭에서 다시 읽는다(실패를 재사용하지 않는다)', (t) async {
    final tax = _Tax(_delay, failFirst: true)..clock.start();
    await _pump(t, _reads(details: [_wd()], taxStatus: tax.call));
    final waited = await _tapApplyAndWaitSheet(t);
    expect(find.byType(MultiApplyConfirmSheet), findsOneWidget);
    expect(tax.calledAt.length, 2);
    expect(waited, greaterThanOrEqualTo(_delay.inMilliseconds - 50));
  });

  testWidgets('TP-4 60초가 지난 값은 쓰지 않는다', (t) async {
    final tax = _Tax(_delay)..clock.start();
    var skew = Duration.zero; // 위젯 테스트의 가짜 시간은 DateTime.now 를 움직이지 않는다 — 경계의 시계로 만든다
    await _pump(t, _reads(details: [_wd()], taxStatus: tax.call, now: () => DateTime.now().add(skew)));
    skew = const Duration(seconds: 61);
    await _tapApplyAndWaitSheet(t);
    expect(find.byType(MultiApplyConfirmSheet), findsOneWidget);
    expect(tax.calledAt.length, 2);
  });

  testWidgets('TP-5 한 번 쓴 값은 다음 탭에서 다시 쓰지 않는다', (t) async {
    final tax = _Tax(_delay)..clock.start();
    await _pump(t, _reads(details: [_wd()], taxStatus: tax.call));
    await _tapApplyAndWaitSheet(t);
    await _closeSheet(t);
    final second = await _tapApplyAndWaitSheet(t);
    expect(find.byType(MultiApplyConfirmSheet), findsOneWidget);
    expect(tax.calledAt.length, 2, reason: '두 번째 탭은 새로 읽는다');
    expect(second, greaterThanOrEqualTo(_delay.inMilliseconds - 50));
  });
}
