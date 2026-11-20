// [SIM-RECONFIRM-ACCESS] 전날 밤 리컨펌 요청에 **응답할 수 있어야** 한다.
//
// 근거(CODE·LOCAL, 2026-10-18):
//   · 서버 sendReconfirmNotifications 는 workDate(KST 자정) 기준이라 10/20 근무의 요청을
//     **10/19 21:00** 에 보낸다(알림 data.screen = attendanceCheck).
//   · 응답 버튼은 출퇴근 체크 화면의 리컨펌 카드에만 있다. 그런데 이 화면은 workDate 가
//     **오늘·어제**인 단기 근무만 실었다 → 10/19 밤에는 10/20 근무가 없어 응답할 수 없었다.
//     22:00 관리자 '미응답' 경고는 그래서 사실상 항상 나갔다.
//
// 계약(기기 KST·UTC 각각)
//   RA-1 10/19 21:05 — 내일(10/20) 근무의 리컨펌 카드·두 버튼이 보인다. 그 근무의 출근 요청 버튼은 없다
//   RA-2 오늘·어제 기존 근무는 그대로 — 오늘 근무에는 출근 요청 버튼이 있다
//   RA-3 '네, 출근합니다' → 응답 1회 → 다시 읽으면 카드가 사라진다
//   RA-4 대조군 — 취소된 내일 근무·모레 근무·요청 없는(내일, reconfirmStatus 없음) 근무는 카드 없음
//   RA-5 10/20 00:05 — 같은 근무는 '오늘 근무'로 한 번만 보이고, 출근 요청 버튼은 열리기 전(09:30)이다
import 'support/visible_text.dart';
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

DateTime _kst(int y, int mo, int d, [int h = 0, int mi = 0]) =>
    DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 9));

enum _Device { kst, utc }

DateTime _dev(DateTime utcInstant, _Device d) =>
    d == _Device.kst ? utcInstant.toLocal() : utcInstant.toUtc();

ApplicationModel _app(
  _Device d, {
  required String id,
  required String biz,
  required int day,
  String start = '10:00',
  String end = '11:00',
  String status = AppStatus.confirmed,
  String? reconfirm,
}) =>
    ApplicationModel(
      id: id,
      toId: 'to_$id',
      uid: 'u1',
      businessId: 'biz1',
      businessName: biz,
      toTitle: 'QA',
      status: status,
      selectedWorkType: 'QA 분류',
      startTime: start,
      endTime: end,
      wage: 12000,
      workDate: _dev(_kst(2026, 10, day), d),
      appliedAt: _dev(_kst(2026, 10, 17), d),
      attendancePolicySnapshot: const AttendanceRules(),
      reconfirmStatus: reconfirm,
    );

AttendanceCheckReads _reads(List<ApplicationModel> Function() apps) =>
    AttendanceCheckReads(
      myApplications: (uid) async => apps(),
      // [CONTRACT-BEFORE-CHECKIN] 출근 버튼은 계약 양측 서명 완료일 때만 열린다(2026-10-25) — 이 시험의 전제로 명시
      myContracts: (uid) async => completedContractsFor(apps()),
      todayAttendance: (
              {required String userId, required String applicationId}) async =>
          null as AttendanceModel?,
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
      testWidgets('RA-1 10/19 21:05 — 내일 근무 리컨펌 카드·버튼, 출근 요청 버튼 없음', (t) async {
        final apps = [_app(d, id: 'zdn7', biz: '골든패스 사업장', day: 20, reconfirm: 'pending')];
        await _pump(t, AttendanceCheckScreen(
            reads: _reads(() => apps), clock: () => _dev(_kst(2026, 10, 19, 21, 5), d),
            reconfirmResponder: (_, __) async => true));
        expect(findVisibleText('골든패스 사업장'), findsWidgets, reason: '내일 근무가 이 화면에 있어야 한다');
        expect(findVisibleTextContaining('10월 20일'), findsWidgets, reason: '어느 날 근무인지 절대 날짜로');
        expect(findVisibleText('네, 출근합니다'), findsOneWidget);
        expect(findVisibleText('아니요, 취소할게요'), findsOneWidget);
        expect(findVisibleText('출근하기'), findsNothing, reason: '내일 근무의 출근 요청 경로는 열리지 않는다');
        expect(findVisibleText('오늘 확정된 근무가 없습니다'), findsNothing);
      });

      testWidgets('RA-2 오늘·어제 기존 근무는 그대로 — 오늘 근무에 출근 버튼', (t) async {
        final apps = [
          _app(d, id: 'today', biz: '오늘 사업장', day: 19, start: '22:00', end: '23:00'),
          _app(d, id: 'yday', biz: '어제 야간 사업장', day: 18, start: '23:00', end: '07:00'),
          _app(d, id: 'zdn7', biz: '골든패스 사업장', day: 20, reconfirm: 'pending'),
        ];
        await _pump(t, AttendanceCheckScreen(
            reads: _reads(() => apps), clock: () => _dev(_kst(2026, 10, 19, 21, 5), d),
            reconfirmResponder: (_, __) async => true));
        expect(findVisibleText('오늘 사업장'), findsWidgets);
        expect(findVisibleText('어제 야간 사업장'), findsWidgets);
        expect(findVisibleText('골든패스 사업장'), findsWidgets);
        // [DEVICE-MISMATCH-FIX] 어제 야간(18일 23:00~19일 07:00)은 출근 기록 없이
        //   이미 끝났다(시계 19일 21:05) — 목록에는 남되 출근 요청은 닫힌다.
        expect(_checkInButtons(t).length, 1, reason: '아직 끝나지 않은 오늘 근무만 출근 요청 영역을 가진다');
        expect(findVisibleText('근무 시간이 지났어요 · 출근 기록이 없어요'), findsOneWidget);
      });

      testWidgets('RA-3 응답 → 1회 호출 → 다시 읽으면 카드가 사라진다', (t) async {
        var apps = [_app(d, id: 'zdn7', biz: '골든패스 사업장', day: 20, reconfirm: 'pending')];
        final calls = <String>[];
        await _pump(t, AttendanceCheckScreen(
            reads: _reads(() => apps), clock: () => _dev(_kst(2026, 10, 19, 21, 5), d),
            reconfirmResponder: (id, r) async {
              calls.add('$id:$r');
              apps = [_app(d, id: 'zdn7', biz: '골든패스 사업장', day: 20, reconfirm: r)];
              return true;
            }));
        await t.tap(findVisibleText('네, 출근합니다'));
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(calls, ['zdn7:confirmed']);
        expect(findVisibleText('네, 출근합니다'), findsNothing, reason: '응답한 요청은 다시 묻지 않는다');
      });

      testWidgets('RA-4 대조군 — 취소·모레·요청 없음은 카드 없음', (t) async {
        final apps = [
          _app(d, id: 'canceled', biz: '취소 사업장', day: 20, status: AppStatus.canceled, reconfirm: 'pending'),
          _app(d, id: 'd21', biz: '모레 사업장', day: 21, reconfirm: 'pending'),
          _app(d, id: 'noreq', biz: '요청없음 사업장', day: 20),
        ];
        await _pump(t, AttendanceCheckScreen(
            reads: _reads(() => apps), clock: () => _dev(_kst(2026, 10, 19, 21, 5), d),
            reconfirmResponder: (_, __) async => true));
        expect(findVisibleText('네, 출근합니다'), findsNothing);
        expect(findVisibleText('취소 사업장'), findsNothing);
        expect(findVisibleText('모레 사업장'), findsNothing);
        expect(findVisibleText('요청없음 사업장'), findsNothing);
        expect(findVisibleText('오늘 확정된 근무가 없습니다'), findsOneWidget);
      });

      testWidgets('RA-5 10/20 00:05 — 오늘 근무로 한 번, 출근 버튼은 09:30 전 닫힘', (t) async {
        final apps = [_app(d, id: 'zdn7', biz: '골든패스 사업장', day: 20, reconfirm: 'pending')];
        await _pump(t, AttendanceCheckScreen(
            reads: _reads(() => apps), clock: () => _dev(_kst(2026, 10, 20, 0, 5), d),
            reconfirmResponder: (_, __) async => true));
        expect(findVisibleText('네, 출근합니다'), findsOneWidget, reason: '두 목록에 중복으로 들어가지 않는다');
        final btns = _checkInButtons(t).toList();
        expect(btns.length, 1);
        expect(btns.single.onPressed, isNull, reason: '기존 허용 시각(시작 − 30분) 전에는 열리지 않는다');
        expect(findVisibleTextContaining('09:30부터 출근할 수 있어요'), findsOneWidget);
      });

      // [SIM-RECONFIRM-DECLINE-ALIGN] '출근 불가'는 기존 확정취소와 같은 확인창·같은 시각 기준.
      testWidgets('RA-6 10/19 21:05 내일 카드 불가 → 기존 확정취소 안내(패널티 없음) → 진행 시 1회', (t) async {
        final apps = [_app(d, id: 'zdn7', biz: '골든패스 사업장', day: 20, reconfirm: 'pending')];
        final calls = <String>[];
        await _pump(t, AttendanceCheckScreen(
            reads: _reads(() => apps), clock: () => _dev(_kst(2026, 10, 19, 21, 5), d),
            reconfirmResponder: (id, r) async { calls.add('$id:$r'); return true; }));
        await t.tap(findVisibleText('아니요, 취소할게요'));
        await t.pumpAndSettle();
        expect(findVisibleText('확정 취소 안내'), findsOneWidget, reason: '기존 확정취소 확인창');
        expect(findVisibleTextContaining('근무 시작 5분 전부터 취소'), findsOneWidget);
        expect(findVisibleText('현재 시점: 패널티 없이 취소 가능'), findsOneWidget);
        expect(findVisibleText('출근하기'), findsNothing, reason: '내일 카드에는 출근 요청 경로가 없다');
        await t.tap(findVisibleText('취소 진행'));
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(calls, ['zdn7:declined']);
      });

      testWidgets('RA-7 10/20 09:57 불가 → 패널티 적용 구간을 누르기 전에 보여 준다, 돌아가기면 호출 없음', (t) async {
        final apps = [_app(d, id: 'zdn7', biz: '골든패스 사업장', day: 20, reconfirm: 'pending')];
        final calls = <String>[];
        await _pump(t, AttendanceCheckScreen(
            reads: _reads(() => apps), clock: () => _dev(_kst(2026, 10, 20, 9, 57), d),
            reconfirmResponder: (id, r) async { calls.add('$id:$r'); return true; }));
        await t.tap(findVisibleText('아니요, 취소할게요'));
        await t.pumpAndSettle();
        expect(findVisibleText('현재 시점: 패널티 적용 구간'), findsOneWidget);
        expect(findVisibleText('이 취소는 패널티가 적용됩니다.'), findsOneWidget);
        await t.tap(findVisibleText('돌아가기'));
        await t.pumpAndSettle();
        expect(calls, isEmpty);
      });
    });
  }
}
