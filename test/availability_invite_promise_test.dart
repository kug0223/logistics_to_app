import 'dart:io';

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
import 'package:ALfit/models/core/invite_region_preference.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/worker_availability_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_schedule_reads.dart';
import 'package:ALfit/screens/user/my_schedule_screen.dart';

/// [R7-P2-3 READ] 근무 가능일 화면이 **실제 초대 계약**을 왜곡하지 않는가.
///
///   서버(`callableInviteWorker`)는 세 가지를 모두 본다:
///     ① 날짜가 `dates` 에 있고 ② `inviteEnabled == true` 이며
///     ③ 사업장 근무지역이 `inviteRegionKeys` 에 있다.
///   ②③ 가 없으면 `callableSetAvailability` 가 `inviteKeys` 를 빈 배열로 만들어
///   관리자 후보 조회에 잡히지 않는다. 화면의 약속이 여기에 맞아야 한다.

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
        homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
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

MyScheduleReads _reads({
  required List<String> dates,
  required InviteRegionPreference pref,
}) =>
    MyScheduleReads(
      myApplications: (uid) async => const <ApplicationModel>[],
      myMonthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) async =>
          const <AttendanceModel>[],
      myAvailability: (uid) async => dates.isEmpty
          ? null
          : WorkerAvailabilityModel(uid: uid, dates: dates, city: '강남구'),
      invitePreference: (uid) async => pref,
    );

/// 오늘 기준 유효 범위(today~+90) 안의 날짜 키 두 개.
List<String> _twoDates() {
  final now = DateTime.now();
  return [
    WorkerAvailabilityModel.dateKeyFrom(now.add(const Duration(days: 3))),
    WorkerAvailabilityModel.dateKeyFrom(now.add(const Duration(days: 5))),
  ];
}

Future<void> _pump(
  WidgetTester tester, {
  required MyScheduleReads reads,
  Size size = const Size(390, 1600),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: MyScheduleScreen(reads: reads),
      ),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 저장된 날짜의 **첫 번째 효과** — 초대 설정과 무관하게 동작한다.
const _matchAlert = '등록한 날 내 지역에 새 공고가 열리면 알림을 받아요.';
const _promiseOn = '$_matchAlert 조건이 맞는 사업장이 먼저 제안할 수도 있어요.';
const _promiseIntro =
    "가능일을 등록하면 그 날 새 공고 알림을 받고, '초대 받을 지역'까지 설정하면 "
    '사업장의 근무 제안도 받을 수 있어요.';
const _needRegion =
    "$_matchAlert 사업장이 먼저 제안하게 하려면 아래 '초대 받을 지역'을 설정하세요.";
const _offCopy =
    '$_matchAlert 지금은 초대를 받지 않도록 설정돼 있어 사업장의 제안은 오지 않아요.';
const _unknownCopy = '$_matchAlert 초대 설정은 확인하지 못했어요.';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('AIP-1 가능일 등록 + 초대 지역 UNSET — 제안이 온다고 말하지 않는다',
      (tester) async {
    await _pump(
      tester,
      reads: _reads(
          dates: _twoDates(), pref: const InviteRegionPreference()), // UNSET
    );

    expect(tester.takeException(), isNull);
    expect(find.text('근무 가능일 2일 등록됨'), findsOneWidget);
    expect(find.text(_promiseOn), findsNothing,
        reason: '초대 지역을 설정하지 않으면 후보 조회에 잡히지 않는다 — '
            '하지 않은 설정을 한 것처럼 확인해 주면 안 된다');
    expect(find.text(_needRegion), findsOneWidget);
    // 할 일을 말했으면 그 자리도 있어야 한다.
    expect(find.text('초대 받을 지역'), findsOneWidget);
    expect(find.text('설정하기'), findsOneWidget);
    // 저장한 날짜가 **아무 일도 안 한다**고 읽히면 안 된다 —
    //   초대와 무관한 공고 알림은 계속 온다(CF active consumer).
    expect(find.textContaining('새 공고가 열리면 알림을 받아요'), findsWidgets);
  });

  testWidgets('AIP-2 가능일 등록 + 초대 ON — 그때만 제안을 약속한다', (tester) async {
    await _pump(
      tester,
      reads: _reads(
        dates: _twoDates(),
        pref: const InviteRegionPreference(
          enabled: true,
          regions: [UserRegion(province: '서울특별시', city: '강남구')],
        ),
      ),
    );

    expect(find.text(_promiseOn), findsOneWidget);
    expect(find.text(_needRegion), findsNothing);
    expect(find.text('강남구'), findsWidgets);
  });

  testWidgets('AIP-3 초대 OFF — 제안이 오지 않는다고 말한다', (tester) async {
    await _pump(
      tester,
      reads: _reads(
        dates: _twoDates(),
        pref: const InviteRegionPreference(
          enabled: false,
          regions: [UserRegion(province: '서울특별시', city: '강남구')],
        ),
      ),
    );

    expect(find.text(_offCopy), findsOneWidget);
    expect(find.text(_promiseOn), findsNothing);
    expect(find.text('받지 않음'), findsOneWidget);
    expect(find.textContaining('새 공고가 열리면 알림을 받아요'), findsWidgets,
        reason: 'OFF 라도 저장한 날짜는 공고 알림에 쓰인다 — 쓸모없다고 말하지 않는다');
  });

  testWidgets('AIP-4 초대 설정을 못 읽으면 모른다고 말한다 — OFF 로 단정하지 않는다',
      (tester) async {
    await _pump(
      tester,
      reads: _reads(
        dates: _twoDates(),
        pref: const InviteRegionPreference.unknown(),
      ),
    );

    expect(find.text(_unknownCopy), findsOneWidget);
    expect(find.text(_offCopy), findsNothing);
    expect(find.text('확인하지 못함'), findsOneWidget);
  });

  testWidgets('AIP-5 가능일 0일 — 기능 안내는 그대로 둔다(양성 대조)',
      (tester) async {
    await _pump(
      tester,
      reads: _reads(dates: const [], pref: const InviteRegionPreference()),
    );

    expect(find.text(_promiseIntro), findsOneWidget);
    expect(find.text('등록'), findsOneWidget);
  });

  testWidgets('AIP-6 가능일은 지원·확정과 다른 자리다 — 화면이 둘을 섞지 않는다',
      (tester) async {
    await _pump(
      tester,
      reads: _reads(
          dates: _twoDates(),
          pref: const InviteRegionPreference(
            enabled: true,
            regions: [UserRegion(province: '서울특별시', city: '강남구')],
          )),
    );

    // 가능일 배너는 '등록됨'을 말할 뿐 지원/확정을 말하지 않는다.
    expect(find.textContaining('지원'), findsNothing,
        reason: '날짜를 표시하는 행위가 지원이 아니다');
    expect(find.textContaining('확정됐'), findsNothing);
  });

  testWidgets('AIP-7 첫 날짜를 고르기 **전** 에 이득·조건·수락 필요성을 말한다',
      (tester) async {
    await _pump(
      tester,
      reads: _reads(dates: const [], pref: const InviteRegionPreference()),
    );

    // 에디트 모드 진입 — 캘린더만 주고 나중에 정정하지 않는다.
    await tester.tap(find.text('가능일'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('근무 가능일 선택'), findsOneWidget);
    expect(find.textContaining('새 공고가 열리면 알림을 받아요'), findsWidgets,
        reason: '왜 날짜를 고르는지 먼저 말한다');
    expect(find.textContaining("'초대 받을 지역'도 설정하세요"), findsWidgets,
        reason: '초대를 받으려면 무엇이 더 필요한지 먼저 말한다');
    expect(find.textContaining('제안을 수락해야 근무가 확정돼요'), findsWidgets,
        reason: '제안이 곧 근무 확정이 아니라는 것을 먼저 말한다');
  });

  testWidgets('AIP-8 초대 설정으로 갔다 돌아오면 상태를 다시 읽는다', (tester) async {
    var loads = 0;
    final reads = MyScheduleReads(
      myApplications: (uid) async => const <ApplicationModel>[],
      myMonthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) async =>
          const <AttendanceModel>[],
      myAvailability: (uid) async =>
          WorkerAvailabilityModel(uid: uid, dates: _twoDates(), city: '강남구'),
      invitePreference: (uid) async {
        loads++;
        return const InviteRegionPreference();
      },
    );
    await _pump(tester, reads: reads);
    expect(loads, greaterThanOrEqualTo(1));
    final before = loads;

    // '초대 받을 지역' 행 → 설정 화면 → 뒤로
    await tester.tap(find.text('초대 받을 지역'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.pop();
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(loads, greaterThan(before),
        reason: '설정하고 돌아왔으면 배너가 낡은 상태를 말하면 안 된다');
  });

  testWidgets('AIP-9 날짜를 골라도 초대가 자동으로 켜지지 않는다', (tester) async {
    // 초대 수신은 **명시 행동**으로 남는다(자동 ON 금지).
    final src = File('lib/screens/user/my_schedule_screen.dart').readAsStringSync();
    final save = src.substring(src.indexOf('Future<void> _saveAvailability('));
    final body = save.substring(0, save.indexOf('Future<', 10));
    expect(body.contains('setInviteRegions'), isFalse);
    expect(body.contains('inviteEnabled'), isFalse);
  });

  for (final size in const [Size(320, 1600), Size(360, 1600), Size(412, 1600)]) {
    for (final scale in const [1.3, 2.0]) {
      testWidgets(
          'AIP-R ${size.width.toInt()}dp × $scale — 가능일·초대 지역 줄이 예외 없이 그려진다',
          (tester) async {
        await _pump(
          tester,
          reads: _reads(
              dates: _twoDates(), pref: const InviteRegionPreference()),
          size: size,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('초대 받을 지역'), findsOneWidget);
      });
    }
  }
}
