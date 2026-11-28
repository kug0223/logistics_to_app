// [DEVICE-MISMATCH-FIX] 출근 기록 없이 예정 시간이 끝난 근무에는 누를 것이 없다.
//
// DEVICE 관찰(Pixel 5, 원본 APK, 10-20 14:58): Zdn7(10:00~11:00, 근태 없음,
//   reconfirm pending) 카드에 `아니요, 취소할게요`·`네, 출근합니다`·`출근하기`
//   세 버튼이 모두 활성이었다. 배포 callableCheckIn 에는 종료 상한이 없어
//   누르면 종료 4시간 뒤 출근이 기록될 수 있다(서버 결함은 별도 — 이 테스트는
//   **화면 차단만** 증명한다).
//
// 계약(기기 KST·UTC 각각)
//   SE-1 종료 뒤: 출근·리컨펌 두 버튼 모두 없음, 종료 안내 1개
//   SE-2 근무 중(종료 전): 기존대로 출근·리컨펌 버튼 있음
//   SE-3 화면을 연 채 종료 시각이 지나면 다시 그려 버튼이 닫힌다
//   SE-4 출근은 했고 퇴근 전: 종료 뒤에도 `퇴근하기`는 그대로(잠그지 않는다)
//   SE-5 어제 야간(23:00~07:00) 06:30 — 아직 끝나지 않았으므로 열려 있다
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

DateTime _kst(int y, int mo, int d, [int h = 0, int mi = 0, int s = 0]) =>
    DateTime.utc(y, mo, d, h, mi, s).subtract(const Duration(hours: 9));

enum _Device { kst, utc }

DateTime _dev(DateTime utcInstant, _Device d) =>
    d == _Device.kst ? utcInstant.toLocal() : utcInstant.toUtc();

const _kEnded = '근무 시간이 지났어요 · 출근 기록이 없어요';

ApplicationModel _app(
  _Device d, {
  required String id,
  required int day,
  String start = '10:00',
  String end = '11:00',
  String? reconfirm = 'pending',
}) =>
    ApplicationModel(
      id: id,
      toId: 'to_$id',
      uid: 'u1',
      businessId: 'biz1',
      businessName: '골든패스 사업장',
      toTitle: 'QA',
      status: AppStatus.confirmed,
      selectedWorkType: 'QA 분류',
      startTime: start,
      endTime: end,
      wage: 12000,
      workDate: _dev(_kst(2026, 10, day), d),
      appliedAt: _dev(_kst(2026, 10, 17), d),
      attendancePolicySnapshot: const AttendanceRules(),
      reconfirmStatus: reconfirm,
    );

AttendanceModel _checkedIn(_Device d, String appId, int day) => AttendanceModel(
      id: 'att-$appId',
      applicationId: appId,
      userId: 'u1',
      businessId: 'biz1',
      businessName: '골든패스 사업장',
      workDate: _dev(_kst(2026, 10, day), d),
      workType: 'QA 분류',
      checkInAt: _dev(_kst(2026, 10, day, 10, 0), d),
      status: AttendanceModel.statusPresent,
      wageStatus: 'pending',
      createdAt: _dev(_kst(2026, 10, day, 10, 0), d),
    );

AttendanceCheckReads _reads(List<ApplicationModel> apps,
        {Map<String, AttendanceModel> att = const {}}) =>
    AttendanceCheckReads(
      myApplications: (uid) async => apps,
      // [CONTRACT-BEFORE-CHECKIN] 출근 버튼은 계약 양측 서명 완료일 때만 열린다(2026-10-25) — 이 시험의 전제로 명시
      myContracts: (uid) async => completedContractsFor(apps),
      todayAttendance: (
              {required String userId, required String applicationId}) async =>
          att[applicationId],
    );

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 2600);
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

Iterable<LoadingButton> _checkInButtons(WidgetTester tester) => tester
    .widgetList<LoadingButton>(find.ancestor(
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
      testWidgets('SE-1 [DEV 재현 Zdn7] 10/20 14:58 — 출근·리컨펌 버튼 없음, 종료 안내',
          (t) async {
        await _pump(
            t,
            AttendanceCheckScreen(
                reads: _reads([_app(d, id: 'zdn7', day: 20)]),
                clock: () => _dev(_kst(2026, 10, 20, 14, 58), d),
                reconfirmResponder: (_, __) async => true));
        expect(findVisibleText('골든패스 사업장'), findsWidgets, // [DU253] 보이는 글자 기준
            reason: '근무 카드는 남는다(기록을 숨기지 않는다)');
        expect(findVisibleText('출근하기'), findsNothing);
        expect(find.text('네, 출근합니다'), findsNothing);
        expect(find.text('아니요, 취소할게요'), findsNothing);
        expect(find.text(_kEnded), findsOneWidget);
      });

      testWidgets('SE-2 10/20 10:30 근무 시간 중 — 기존대로 열려 있다', (t) async {
        await _pump(
            t,
            AttendanceCheckScreen(
                reads: _reads([_app(d, id: 'zdn7', day: 20)]),
                clock: () => _dev(_kst(2026, 10, 20, 10, 30), d),
                reconfirmResponder: (_, __) async => true));
        final btns = _checkInButtons(t).toList();
        expect(btns.length, 1);
        expect(btns.single.onPressed, isNotNull);
        expect(find.text('네, 출근합니다'), findsOneWidget);
        expect(find.text(_kEnded), findsNothing);
      });

      testWidgets('SE-3 화면을 연 채 11:00 이 지나면 버튼이 닫힌다', (t) async {
        var now = _dev(_kst(2026, 10, 20, 10, 59, 50), d);
        await _pump(
            t,
            AttendanceCheckScreen(
                reads: _reads([_app(d, id: 'zdn7', day: 20)]),
                clock: () => now,
                reconfirmResponder: (_, __) async => true));
        expect(_checkInButtons(t).length, 1);
        // 실제 시계가 흐른 것처럼 시계와 fake time 을 함께 20초 전진한다.
        now = now.add(const Duration(seconds: 20));
        await t.pump(const Duration(seconds: 20));
        await t.pump();
        expect(findVisibleText('출근하기'), findsNothing);
        expect(find.text('네, 출근합니다'), findsNothing);
        expect(find.text(_kEnded), findsOneWidget);
      });

      testWidgets('SE-4 출근 후 퇴근 전 — 종료 뒤에도 퇴근하기는 잠그지 않는다', (t) async {
        await _pump(
            t,
            AttendanceCheckScreen(
                reads: _reads([_app(d, id: 'zdn7', day: 20)],
                    att: {'zdn7': _checkedIn(d, 'zdn7', 20)}),
                clock: () => _dev(_kst(2026, 10, 20, 14, 58), d),
                reconfirmResponder: (_, __) async => true));
        expect(findVisibleText('퇴근하기'), findsOneWidget);
        expect(find.text(_kEnded), findsNothing);
      });

      testWidgets('SE-5 어제 야간 23:00~07:00 · 오늘 06:30 — 아직 열려 있다', (t) async {
        await _pump(
            t,
            AttendanceCheckScreen(
                reads: _reads([
                  _app(d,
                      id: 'night',
                      day: 19,
                      start: '23:00',
                      end: '07:00',
                      reconfirm: null)
                ]),
                clock: () => _dev(_kst(2026, 10, 20, 6, 30), d),
                reconfirmResponder: (_, __) async => true));
        expect(_checkInButtons(t).length, 1);
        expect(find.text(_kEnded), findsNothing);
      });
    });
  }
}
