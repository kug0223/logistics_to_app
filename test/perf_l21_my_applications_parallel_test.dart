// ignore_for_file: depend_on_referenced_packages
// [ATTENDANCE-SCREEN-REFRESH] 내 지원 — 새로고침·재시도가 근태를 다시 읽는가.
//   DEVICE 10/20 12:38: 출근 뒤 당겨서 새로고침해도 '오늘 근무 예정이에요', 근태 월 조회 0(월 키 영구 보관).
//   CODE: 실패 표시(_attendanceFailed)도 true 가 되면 되돌아오지 않았다.
//   하네스는 my_applications_attendance_status_test 와 같다. 서버 쓰기 없음.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_applications_reads.dart';
import 'package:ALfit/screens/user/my_applications_screen.dart';
import 'package:ALfit/services/tax_identity_service.dart';
import 'package:ALfit/utils/format_helper.dart';

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
  @override
  UserModel? get currentUser => UserModel(
        uid: _kUid,
        username: _kUid,
        name: 'QA 지원자',
        email: '$_kUid@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시'),
        accountStatus: 'active',
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

// ── 고정 시계 ───────────────────────────────────────────────────────────
//   확정 근무가 '지났는가' 는 이 한 값으로 갈린다. TZ 가정을 하지 않도록
//   근무일은 이 시계에서 `toKstDate` 로 역산한다.
final DateTime _clock = DateTime(2026, 10, 13, 21, 30);
DateTime _todayKst() => FormatHelper.toKstDate(_clock);
DateTime _dayOffset(int d) => _todayKst().add(Duration(days: d));

ApplicationModel _app({
  required String id,
  required String status,
  required DateTime workDate,
}) =>
    ApplicationModel(
      id: id,
      toId: 'to1',
      uid: _kUid,
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toTitle: 'QA 공고',
      status: status,
      selectedWorkType: 'QA 분류',
      // [DEVICE-MISMATCH-FIX] 시계 21:30 보다 뒤의 근무 — 아직 '오늘 근무 예정' 이다.
      //   (10:00~11:00 이면 이제 '근무 시간이 지났어요' 로 말한다.)
      startTime: '22:00',
      endTime: '23:00',
      wage: 53000,
      workDate: workDate,
      appliedAt: _dayOffset(-5),
    );


TOModel _to() => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: 'QA 사업장',
      type: 'flex',
      title: 'QA 공고',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 3,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: _dayOffset(-10),
      statusUpdatedAt: _dayOffset(-10),
    );

Future<void> _pump(WidgetTester t, MyApplicationsReads reads) async {
  t.view.physicalSize = const Size(390, 2400);
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
        home: MyApplicationsScreen(reads: reads, clock: () => _clock),
      ),
    ),
  );
  // 이 화면은 멈추지 않는 애니메이션이 있어 pumpAndSettle 이 끝나지 않는다
  //   (기존 my_applications 테스트들과 같은 방식으로 프레임을 전진시킨다).
  for (var i = 0; i < 25; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

List<String> _texts(WidgetTester t) => t
    .widgetList<Text>(find.byWidgetPredicate((w) => w is Text))
    .map((w) => w.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

// ── [L21 · impl_7] '내 지원' 첫 로드 — 공고(R2)와 계약·후기·근태(R3) 동시 출발 · 월별 근태 동시 · 탭 keepAlive ──
class _Gate {
  final toC = Completer<({TOModel? to, bool failed})>();
  final monthC = <String, Completer<List<AttendanceModel>>>{};
  bool contractsCalled = false;
  int pagedCalls = 0;
  final List<ApplicationModel> apps;
  _Gate(this.apps);
  MyApplicationsReads get reads => MyApplicationsReads(
        myApplicationsPaged: ({required String uid, required int pageSize, String? startAfterDocId}) async {
          pagedCalls++;
          return {'items': apps, 'lastDocId': null, 'hasMore': false};
        },
        toOrFailure: (id) => toC.future,
        contractsByWorker: (uid) async {
          contractsCalled = true;
          return const <EmploymentContractModel>[];
        },
        autoExpirePending: (uid) async {},
        monthlyAttendances: ({required String userId, required int year, required int month}) =>
            (monthC['$year-$month'] = Completer<List<AttendanceModel>>()).future,
        reviewById: (key) async => null,
        taxStatus: () async => const TaxIdentityStatus.unknown(),
      );
}

Future<void> _frames(WidgetTester t, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await initializeDateFormatting('ko_KR');
  });

  testWidgets('L21-1 공고 읽기가 끝나기 전에 계약·근태가 이미 출발하고, 두 달 근태가 동시에 나간다', (t) async {
    final g = _Gate([
      _app(id: 'a1', status: AppStatus.confirmed, workDate: _dayOffset(-2)),
      _app(id: 'a2', status: AppStatus.confirmed, workDate: _dayOffset(-40)),
    ]);
    await _pump(t, g.reads);
    expect(g.toC.isCompleted, isFalse, reason: '공고 읽기는 아직 진행 중');
    expect(g.contractsCalled, isTrue, reason: 'R3(계약)는 R2(공고)를 기다리지 않는다');
    expect(g.monthC.length, 2, reason: '두 달 근태가 직렬이 아니라 동시에 출발');
    g.toC.complete((to: _to(), failed: false));
    for (final c in g.monthC.values) {
      c.complete(const <AttendanceModel>[]);
    }
    await _frames(t);
    expect(find.byType(MyApplicationsScreen), findsOneWidget);
    expect(_texts(t).any((s) => s.contains('QA 공고') || s.contains('QA 사업장')), isTrue, reason: '목록이 그려진다');
  });

  testWidgets('L21-2 탭에 들어 있을 때(onBack) 다른 탭에 갔다 와도 다시 읽지 않는다(keepAlive)', (t) async {
    final g = _Gate([_app(id: 'a1', status: AppStatus.pending, workDate: _dayOffset(3))]);
    g.toC.complete((to: _to(), failed: false));
    t.view.physicalSize = const Size(390, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    late BuildContext tabCtx;
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        home: DefaultTabController(
          length: 2,
          initialIndex: 1,
          child: Builder(builder: (ctx) {
            tabCtx = ctx;
            return Scaffold(
              body: TabBarView(children: [
                const Center(child: Text('일자리')),
                MyApplicationsScreen(onBack: () {}, reads: g.reads, clock: () => _clock),
              ]),
            );
          }),
        ),
      ),
    ));
    await _frames(t, 25);
    expect(g.pagedCalls, 1);
    DefaultTabController.of(tabCtx).index = 0;
    await _frames(t, 10);
    DefaultTabController.of(tabCtx).index = 1;
    await _frames(t, 25);
    expect(g.pagedCalls, 1, reason: '탭 전환으로 상태가 버려지지 않는다 — 다시 읽기 0');
  });
}
