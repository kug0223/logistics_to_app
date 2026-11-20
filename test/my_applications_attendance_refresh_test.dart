// [ATTENDANCE-SCREEN-REFRESH] 내 지원 — 새로고침·재시도가 근태를 다시 읽는가.
//   DEVICE 10/20 12:38: 출근 뒤 당겨서 새로고침해도 '오늘 근무 예정이에요', 근태 월 조회 0(월 키 영구 보관).
//   CODE: 실패 표시(_attendanceFailed)도 true 가 되면 되돌아오지 않았다.
//   하네스는 my_applications_attendance_status_test 와 같다. 서버 쓰기 없음.

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

AttendanceModel _att({
  required String applicationId,
  required DateTime workDate,
  String status = AttendanceModel.statusPresent,
  DateTime? checkIn,
  DateTime? checkOut,
  String wageStatus = 'pending',
  String userId = _kUid,
}) =>
    AttendanceModel(
      id: 'att-$applicationId',
      applicationId: applicationId,
      userId: userId,
      businessId: 'biz1',
      businessName: 'QA 사업장',
      workDate: workDate,
      workType: 'QA 분류',
      checkInAt: checkIn,
      checkOutAt: checkOut,
      status: status,
      wageStatus: wageStatus,
      createdAt: workDate,
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

/// 읽은 (year, month) 를 기록해 **몇 번 나갔는지** 셀 수 있게 한다.
class _ReadLog {
  final List<String> months = [];
}

MyApplicationsReads _reads(
  List<ApplicationModel> apps, {
  List<AttendanceModel> attendances = const [],
  Object? attendanceError,
  _ReadLog? log,
}) =>
    MyApplicationsReads(
      myApplicationsPaged: (
              {required String uid,
              required int pageSize,
              String? startAfterDocId}) async =>
          {'items': apps, 'lastDocId': null, 'hasMore': false},
      toOrFailure: (id) async => (to: _to(), failed: false),
      contractsByWorker: (uid) async => const <EmploymentContractModel>[],
      autoExpirePending: (uid) async {},
      monthlyAttendances: (
          {required String userId, required int year, required int month}) async {
        log?.months.add('$year-$month');
        if (attendanceError != null) throw attendanceError;
        return attendances
            .where((a) =>
                a.workDate.toUtc().year == year &&
                a.workDate.toUtc().month == month)
            .toList();
      },
      reviewById: (key) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
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
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

bool _has(WidgetTester t, String s) => _texts(t).contains(s);

const _kReview = '리뷰를 작성해 주세요';
const _kDone = '근무 완료';
const _kNoShow = '노쇼 처리됐어요';
const _kAbsent = '결근 처리됐어요';
const _kNoRecord = '근무 기록이 없어요';
const _kNoCheckIn = '출근 기록이 없어요';
const _kWorking = '근무 중이에요';
const _kEnded = '근무가 끝났어요 · 근태 확인 중';
const _kUnknown = '근무 상태를 확인하지 못했어요';
const _kTodayPlanned = '오늘 근무 예정이에요';

class _Ledger {
  _Ledger(this.apps);
  final List<ApplicationModel> apps;
  List<AttendanceModel> attendances = const [];
  Object? error;
  final months = <String>[];
  MyApplicationsReads get reads => MyApplicationsReads(
        myApplicationsPaged: ({required String uid, required int pageSize, String? startAfterDocId}) async =>
            {'items': apps, 'lastDocId': null, 'hasMore': false},
        toOrFailure: (id) async => (to: _to(), failed: false),
        contractsByWorker: (uid) async => const <EmploymentContractModel>[],
        autoExpirePending: (uid) async {},
        monthlyAttendances: ({required String userId, required int year, required int month}) async {
          months.add('$year-$month');
          if (error != null) throw error!;
          return attendances
              .where((a) => a.workDate.toUtc().year == year && a.workDate.toUtc().month == month)
              .toList();
        },
        reviewById: (key) async => null,
        taxStatus: () async => const TaxIdentityStatus.unknown(),
      );
}

Future<void> _frames(WidgetTester t, [int n = 25]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// 사용자의 당겨서 새로고침과 같은 콜백(RefreshIndicator.onRefresh = _loadApplications).
Future<void> _refresh(WidgetTester t) async {
  t.state<RefreshIndicatorState>(find.byType(RefreshIndicator).first).show();
  await _frames(t);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  ApplicationModel today() => _app(id: 'a1', status: AppStatus.confirmed, workDate: _todayKst());

  testWidgets('RM-1 출근 뒤 새로고침 → 근무 중이에요, 같은 달을 다시 읽는다', (t) async {
    final l = _Ledger([today()]);
    await _pump(t, l.reads);
    expect(_has(t, _kTodayPlanned), isTrue);
    expect(l.months.length, 1);
    l.attendances = [_att(applicationId: 'a1', workDate: _todayKst(), checkIn: _todayKst().add(const Duration(hours: 10)))];
    await _refresh(t);
    expect(l.months.length, 2, reason: '새로고침이 근태를 다시 읽지 않았다');
    expect(_has(t, _kWorking), isTrue);
    expect(_has(t, _kTodayPlanned), isFalse);
  });

  testWidgets('RM-2 퇴근까지 반영(새로고침 두 번)', (t) async {
    final l = _Ledger([today()]);
    await _pump(t, l.reads);
    l.attendances = [_att(applicationId: 'a1', workDate: _todayKst(), checkIn: _todayKst().add(const Duration(hours: 10)))];
    await _refresh(t);
    expect(_has(t, _kWorking), isTrue);
    l.attendances = [_att(applicationId: 'a1', workDate: _todayKst(),
        checkIn: _todayKst().add(const Duration(hours: 10)), checkOut: _todayKst().add(const Duration(hours: 11)))];
    await _refresh(t);
    expect(_has(t, _kWorking), isFalse, reason: '퇴근이 반영되지 않았다');
    expect(_has(t, _kTodayPlanned), isFalse);
    expect(l.months.length, 3);
  });

  testWidgets('RM-3 조회 실패 → 다시 시도 → 회복(실패 표시가 남지 않는다)', (t) async {
    final l = _Ledger([today()])..error = StateError('근태 조회 실패(테스트)');
    await _pump(t, l.reads);
    expect(_has(t, _kUnknown), isTrue);
    l.error = null;
    await t.tap(find.text(_kUnknown));
    await _frames(t);
    expect(_has(t, _kUnknown), isFalse, reason: '재시도 뒤에도 실패 표시가 남았다');
    expect(_has(t, _kTodayPlanned), isTrue);
    expect(l.months.length, 2);
  });

  testWidgets('RM-4 새로고침 없이 프레임만 → 다시 읽지 않는다', (t) async {
    final l = _Ledger([today()]);
    await _pump(t, l.reads);
    await _frames(t, 40);
    expect(l.months.length, 1);
  });
}
