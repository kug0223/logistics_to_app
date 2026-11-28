// [SIM-CHECKIN-EARLY] 출근 요청 버튼은 서버가 받는 시각부터 눌린다.
//
// DEVICE 관찰(DEV 셀 6HB9, 설치 앱 1.0.21+25): 10/17 20:00 근무의 출퇴근 화면
//   `출근하기` 가 18:03 부터 눌리는 상태였다. 서버 callableCheckIn 은
//   `예정 시작 − earlyWindow`(이 근무 30분) 이전 요청을
//   `아직 출근할 수 있는 시간이 아닙니다` 로 거절한다. 그 사이에 누르면
//   위치 안내·권한·GPS 측정까지 다 치른 뒤에야 거절을 듣는다.
//
//   홈 hero 의 `출근하기` 는 이 화면으로 **이동**만 한다(의도된 진입).
//   실제 요청 버튼은 이 화면의 `_buildCheckInArea` 하나다.
//
// 계약
//   OT-1 19:29 KST — 요청 버튼 비활성 + `19:30부터 출근할 수 있어요`
//   OT-2 19:30 KST — 요청 버튼 활성
//   OT-3 화면을 열어 둔 채 19:30 이 되면 스스로 풀린다
//   OT-4 정책 스냅샷이 없으면(서버가 사업장 설정을 본다) 화면이 막지 않는다
//   각 셀을 KST 기기·UTC 기기로 — 근무일은 저장된 KST 날짜를 쓴다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart'; // [DU253] 출퇴근 카드 이름은 낱말 결합 문자를 품는다
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart' show AttendanceRules;
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/attendance_check_reads.dart';

import 'support/checkin_contract_fixture.dart';
import 'package:ALfit/screens/user/attendance_check_screen.dart';
import 'package:ALfit/widgets/common/loading_button.dart';

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

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
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

/// KST civil → UTC instant.
DateTime _kst(int y, int mo, int d, [int h = 0, int mi = 0, int s = 0]) =>
    DateTime.utc(y, mo, d, h, mi, s).subtract(const Duration(hours: 9));

/// 기기 흉내 — instant 는 같고 필드만 그 기기 것(KST 호스트 / UTC).
enum _Device { kst, utc }

DateTime _dev(DateTime utcInstant, _Device d) =>
    d == _Device.kst ? utcInstant.toLocal() : utcInstant.toUtc();

ApplicationModel _work(_Device d, {AttendanceRules? snapshot = const AttendanceRules()}) =>
    ApplicationModel(
      id: 'app1',
      toId: 'to1',
      uid: 'u1',
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toTitle: '당일 QA',
      status: AppStatus.confirmed,
      selectedWorkType: 'QA 분류',
      startTime: '20:00',
      endTime: '21:00',
      wage: 12000,
      workDate: _dev(_kst(2026, 10, 17), d),
      appliedAt: _dev(_kst(2026, 10, 17, 17, 57), d),
      attendancePolicySnapshot: snapshot,
    );

AttendanceCheckReads _reads(List<ApplicationModel> apps) => AttendanceCheckReads(
      myApplications: (uid) async => apps,
      // [CONTRACT-BEFORE-CHECKIN] 출근 버튼은 계약 양측 서명 완료일 때만 열린다(2026-10-25) — 이 시험의 전제로 명시
      myContracts: (uid) async => completedContractsFor(apps),
      todayAttendance: (
              {required String userId, required String applicationId}) async =>
          null as AttendanceModel?,
    );

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(home: screen),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 이 화면의 **실제 요청 버튼**.
LoadingButton _checkInButton(WidgetTester tester) => tester.widget<LoadingButton>(
    find.ancestor(
        of: findVisibleText('출근하기'), matching: find.byType(LoadingButton)));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  for (final d in _Device.values) {
    group('기기 ${d.name}', () {
      testWidgets('OT-1 19:29 KST — 요청 버튼 비활성, 열리는 시각을 말한다', (tester) async {
        final now = _kst(2026, 10, 17, 19, 29);
        await _pump(
            tester,
            AttendanceCheckScreen(
                reads: _reads([_work(d)]), clock: () => _dev(now, d)));
        expect(findVisibleText('QA 사업장'), findsWidgets, reason: '그 근무가 목록에 있어야 한다'); // [DU253]
        expect(_checkInButton(tester).onPressed, isNull,
            reason: '서버가 거절할 시각에 요청 버튼이 살아 있으면 안 된다');
        expect(find.textContaining('19:30부터 출근할 수 있어요'), findsOneWidget);
      });

      testWidgets('OT-2 19:30 KST — 요청 버튼 활성', (tester) async {
        final now = _kst(2026, 10, 17, 19, 30);
        await _pump(
            tester,
            AttendanceCheckScreen(
                reads: _reads([_work(d)]), clock: () => _dev(now, d)));
        expect(_checkInButton(tester).onPressed, isNotNull);
        expect(find.textContaining('부터 출근할 수 있어요'), findsNothing);
      });

      testWidgets('OT-3 열어 둔 채 19:30 이 되면 스스로 풀린다', (tester) async {
        var now = _kst(2026, 10, 17, 19, 29, 50);
        await _pump(
            tester,
            AttendanceCheckScreen(
                reads: _reads([_work(d)]), clock: () => _dev(now, d)));
        expect(_checkInButton(tester).onPressed, isNull);
        now = _kst(2026, 10, 17, 19, 30, 1);
        await tester.pump(const Duration(seconds: 11));
        await tester.pump();
        expect(_checkInButton(tester).onPressed, isNotNull,
            reason: '열리는 시각에 화면이 다시 그려져야 한다');
      });

      testWidgets('OT-4 정책 스냅샷이 없으면 화면이 막지 않는다(서버 판정)', (tester) async {
        final now = _kst(2026, 10, 17, 19, 0);
        await _pump(
            tester,
            AttendanceCheckScreen(
                reads: _reads([_work(d, snapshot: null)]),
                clock: () => _dev(now, d)));
        expect(_checkInButton(tester).onPressed, isNotNull,
            reason: '기준을 모르면 지어내지 않는다 — 서버가 사업장 설정으로 판정한다');
      });
    });
  }
}
