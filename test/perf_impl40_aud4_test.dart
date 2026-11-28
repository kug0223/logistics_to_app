// [AUD-4 · impl_40 · 판정296] H1 내 지원 페이지 조회 실패를 빈 목록·목록 끝으로 접지 않는다 ·
//   H3 지원서 200 건 상한에 닿으면 출근 화면이 '오늘 확정된 근무가 없습니다' 로 단정하지 않는다.
// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/attendance_check_reads.dart';
import 'package:ALfit/screens/user/attendance_check_screen.dart';
import 'package:ALfit/screens/user/interim_settlement_reads.dart';
import 'package:ALfit/screens/user/interim_settlement_request_screen.dart';
import 'package:ALfit/screens/user/my_schedule_screen.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/services/firestore_service.dart';

import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _P extends UserProvider {
  @override
  UserModel? get currentUser =>
      UserModel(uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER, accountStatus: 'active');
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

const _cf = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

DateTime _kst(int y, int mo, int d, [int h = 0, int mi = 0]) =>
    DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 9));

/// 지난 확정 근무 n 건(오늘 근무 없음).
List<ApplicationModel> _pastConfirmed(int n) => [
      for (var i = 0; i < n; i++)
        ApplicationModel(
          id: 'p$i', toId: 'to$i', uid: 'u1', businessId: 'biz1', businessName: 'QA 사업장', toTitle: '지난 근무',
          status: AppStatus.confirmed, selectedWorkType: '분류', startTime: '09:00', endTime: '10:00', wage: 10000,
          workDate: _kst(2026, 9, 1).add(Duration(days: i % 30)), appliedAt: _kst(2026, 8, 1),
        ),
    ];

Future<void> _pumpCheck(WidgetTester t, List<ApplicationModel> apps) async {
  t.view.physicalSize = const Size(390, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final now = _kst(2026, 11, 27, 12);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      home: AttendanceCheckScreen(
        reads: AttendanceCheckReads(
          myApplications: (uid) async => apps,
          todayAttendance: ({required String userId, required String applicationId}) async => null as AttendanceModel?,
          myContracts: (uid) async => const <EmploymentContractModel>[],
        ),
        clock: () => now,
      ),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  test('H1 내 지원 페이지 조회 실패는 던진다(빈 목록 · hasMore=false 로 접지 않는다)', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_cf, (msg) async {
      final args = (const StandardMessageCodec().decodeMessage(msg) as List).first as Map;
      calls.add(args['functionName'] as String);
      return const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'impl_40 주입 실패', null]);
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_cf, null));
    await expectLater(FirestoreService().getMyApplicationsPaged(uid: 'u1'), throwsA(anything));
    expect(calls, contains('callableGetMyApplications'), reason: '실제 callable 경로를 탔다');
  });

  testWidgets('H3-a 지원서 200 건(상한)이고 오늘 근무가 안 보이면 — 없음 단정 대신 일부만 확인', (t) async {
    await _pumpCheck(t, _pastConfirmed(200));
    expect(findVisibleText('오늘 근무를 모두 확인하지 못했어요'), findsOneWidget);
    expect(findVisibleText('오늘 확정된 근무가 없습니다'), findsNothing);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('H3-b 상한 미만(199 건)은 기존 빈 상태 그대로', (t) async {
    await _pumpCheck(t, _pastConfirmed(199));
    expect(findVisibleText('오늘 확정된 근무가 없습니다'), findsOneWidget);
    expect(findVisibleText('오늘 근무를 모두 확인하지 못했어요'), findsNothing);
  });

  // UTC 성분 DateTime(isUtc) 은 KST 가 아닌(UTC) 기기에서 Timestamp.toDate().toLocal() 이 주는 성분과 같다.
  test('H9 일정 근태 맵 키 = KST 근무일(UTC 기기에서도 그날 카드에 근태가 붙는다)', () {
    final att = AttendanceModel(
        id: 'a1', applicationId: 'app1', userId: 'u1', businessId: 'biz1', businessName: 'QA',
        workDate: DateTime.utc(2026, 11, 3, 15), workType: '분류', status: AttendanceModel.statusPresent,
        createdAt: DateTime.utc(2026, 11, 3));
    final m = MyScheduleScreen.buildAttendanceMap([att]);
    expect(m.keys, ['app1_2026-11-4'], reason: 'KST 11/4 근무 — 달력이 고른 날(11/4)의 조회 키와 같아야 한다');
  });

  testWidgets('H12 중간정산 근무일·출퇴근 시각 = KST(UTC 기기 성분으로 D-1 · 9시간 어긋나지 않는다)', (t) async {
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final att = AttendanceModel(
        id: 'a1', applicationId: 'app1', userId: 'u1', businessId: 'biz1', businessName: 'QA',
        workDate: DateTime.utc(2026, 11, 3, 15), workType: '분류', status: AttendanceModel.statusPresent,
        checkInAt: DateTime.utc(2026, 11, 4, 0), checkOutAt: DateTime.utc(2026, 11, 4, 8),
        wageStatus: AttendanceModel.wageConfirmed, finalWage: 80000, createdAt: DateTime.utc(2026, 11, 3));
    final app = _pastConfirmed(1).first;
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        home: InterimSettlementRequestScreen(
          app: app,
          reads: InterimSettlementReads(
            myMonthlyAttendances: ({required String userId, required int year, required int month}) async =>
                [att],
          ),
        ),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final texts = t
        .widgetList<Text>(find.byType(Text, skipOffstage: false))
        .map((x) => TextLayout.plain(x.data ?? x.textSpan?.toPlainText() ?? ''))
        .toList();
    expect(texts.any((x) => x.contains('11.04 (수)')), isTrue, reason: 'KST 근무일 · $texts');
    expect(texts.any((x) => x.contains('11.03 (화)')), isFalse, reason: 'D-1');
    expect(texts.any((x) => x.contains('09:00 ~ 17:00')), isTrue, reason: 'KST 출퇴근 · $texts');
  });
}
