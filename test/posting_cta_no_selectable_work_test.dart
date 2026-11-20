// [ISG2-CTA] 하단 CTA 가 **할 수 없는 일**을 시키지 않는다.
//
// ── 에뮬레이터에서 본 것 (2026-10-15, QA 공고 10/16) ──────────────────
//   업무가 하나뿐이고 그 업무의 상태 칩이 `지원완료` 인데, 하단 고정
//   버튼은 그대로 `지원할 업무를 선택해주세요` 였다. 고를 것이 없는
//   화면에서 고르라고 한 것이다.
//
// ── 원인 ──────────────────────────────────────────────────────────────
//   CTA 는 `_totalSelectedCount == 0` 하나만 봤다. 선택이 0인 이유가
//   "아직 안 골랐다"인지 "고를 수 있는 게 없다"인지 구분하지 않았다.
//
// ── 고친 것 ───────────────────────────────────────────────────────────
//   `_hasSelectableWork` — 선택을 거부하는 바로 그 두 조건(기존 관계·
//   확정 일정 겹침)으로 "하나라도 고를 수 있는가"를 센다. 판정식을 새로
//   만들지 않았다.
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
}) =>
    JobPostingReads(
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('CTA-01 고를 업무가 있으면 고르라고 한다', (t) async {
    await _pump(t, _reads(details: [_wd()]));
    expect(_texts(t), contains('지원할 업무를 선택해주세요'));
  });

  testWidgets('CTA-02 유일한 업무가 지원완료면 고르라고 하지 않는다', (t) async {
    // 에뮬레이터에서 본 바로 그 상태.
    await _pump(t, _reads(
      details: [_wd()],
      myApps: [_myApp(status: AppStatus.pending)],
    ));
    final texts = _texts(t);
    expect(texts, contains('지원완료'), reason: '카드 상태 칩은 그대로다');
    expect(texts, contains('지금 지원할 수 있는 업무가 없어요'));
    expect(texts.contains('지원할 업무를 선택해주세요'), isFalse);
  });

  testWidgets('CTA-03 확정된 업무도 마찬가지다', (t) async {
    await _pump(t, _reads(
      details: [_wd()],
      myApps: [_myApp(status: AppStatus.confirmed)],
    ));
    expect(_texts(t), contains('지금 지원할 수 있는 업무가 없어요'));
  });

  testWidgets('CTA-04 하나라도 남아 있으면 여전히 고르라고 한다', (t) async {
    await _pump(t, _reads(
      details: [_wd(), _wd(id: 'wd-2', type: 'QA 분류2')],
      myApps: [_myApp(status: AppStatus.pending)],
    ));
    final texts = _texts(t);
    expect(texts, contains('지원완료'));
    expect(texts, contains('지원할 업무를 선택해주세요'),
        reason: '남은 업무가 있으면 문구를 바꾸지 않는다');
  });

  testWidgets('CTA-05 CTA 는 두 경우 모두 비활성이다', (t) async {
    await _pump(t, _reads(
      details: [_wd()],
      myApps: [_myApp(status: AppStatus.pending)],
    ));
    final btn = find.ancestor(of: find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll('\u2060', '') == '지금 지원할 수 있는 업무가 없어요'), matching: find.byType(ElevatedButton));
    expect(btn, findsOneWidget);
    expect(t.widget<ElevatedButton>(btn).onPressed, isNull);
  });
}
