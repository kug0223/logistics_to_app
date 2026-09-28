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
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/attendance_check_reads.dart';
import 'package:ALfit/screens/user/attendance_check_screen.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';

/// [R7-P2-1 잔여 · VERIFY-ATTENDANCE-LOCAL-MIDNIGHT]
/// **같은 하나의 근무**를 홈과 출퇴근 화면에 동시에 물려 날짜 판정을 맞댄다.
///
///   두 화면 모두 production 위젯이고, 읽기 경계와 **시계**만 주입한다.
///   비-KST 기기는 기기 조작 없이 흉내 낸다 — 그 기기의 `DateTime.now()` 가
///   내놓을 **로컬 필드**를 가진 시각을 시계에 넣고, Firestore 가 내려준
///   근무일도 그 기기의 `Timestamp.toDate().toLocal()` 이 만들 값으로 준다.
///   instant 는 같고 필드만 그 기기의 것이므로, `toKstDate`(instant 기반)와
///   `DateTime(y,m,d)`(필드 기반)가 production 과 똑같이 갈린다.

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

// ── 기기 흉내 ──────────────────────────────────────────────────
//
//   KST 자정 instant 를 그 기기의 로컬 필드로 바꿔 준다.
//   `offsetHours` 는 기기의 UTC offset (KST = +9).
const _biz = 'biz1';

/// KST civil (y,m,d[,h,m]) → UTC instant.
DateTime _kst(int y, int mo, int d, [int h = 0, int mi = 0]) =>
    DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 9));

/// 기기 흉내는 **두 가지**만 가능하고, 그것으로 충분하다.
///
///   Dart 의 DateTime 은 instant 와 wall-clock 필드가 묶여 있다. 그래서
///   "필드는 그 기기 것, instant 는 그대로"를 만들 수 있는 것은
///     · 호스트 시간대(여기서는 KST) → `toLocal()`
///     · UTC                          → `toUtc()`
///   두 가지다. 이 테스트는 **UTC 기기**로 비-KST 기기를 대표한다.
///   다른 offset 은 같은 식(필드 기준 vs instant 기준)의 부호만 다른
///   대칭 사례이고, 이번 수정은 필드 의존 자체를 없앤다.
enum _Device { kst, utc }

DateTime _asDevice(DateTime utcInstant, _Device d) =>
    d == _Device.kst ? utcInstant.toLocal() : utcInstant.toUtc();

ApplicationModel _shortTerm({
  required DateTime workDate,
  String id = 'night1',
  String start = '23:00',
  String end = '06:00',
}) =>
    ApplicationModel(
      id: id,
      toId: 'to1',
      uid: 'u1',
      businessId: _biz,
      businessName: '강남 물류센터',
      toTitle: '야간 단기',
      status: AppStatus.confirmed,
      selectedWorkType: '상하차',
      startTime: start,
      endTime: end,
      wage: 12000,
      workDate: workDate,
      appliedAt: workDate,
    );

AttendanceModel _att({
  required DateTime workDate,
  DateTime? checkInAt,
  DateTime? checkOutAt,
  String status = AttendanceModel.statusPresent,
  String applicationId = 'night1',
}) =>
    AttendanceModel(
      id: 'att_$applicationId',
      applicationId: applicationId,
      userId: 'u1',
      businessId: _biz,
      businessName: '강남 물류센터',
      workDate: workDate,
      workType: '상하차',
      status: status,
      wageStatus: AttendanceModel.wagePending,
      adminConfirmed: false,
      checkInAt: checkInAt,
      checkOutAt: checkOutAt,
      createdAt: checkInAt ?? workDate,
    );

BusinessModel _business() => BusinessModel(
      id: _biz,
      name: '강남 물류센터',
      ownerId: 'a1',
      businessNumber: '000-00-00000',
      address: '서울시',
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: DateTime.utc(2026, 1, 1),
    );

UserHomeReads _homeReads(
  List<ApplicationModel> apps,
  List<AttendanceModel> atts, {
  List<String>? monthCalls,
}) =>
    UserHomeReads(
      myApplications: (uid) async => apps,
      myMonthlyAttendances: (
          {required String userId, required int year, required int month}) async {
        monthCalls?.add('$year-$month');
        return atts;
      },
      publishedTOs: () async => const <TOModel>[],
      pendingIdCardRequests: (uid) async => const <IdCardAccessRequestModel>[],
      myRenewalProposals: () async => const <RenewalProposalModel>[],
      businessById: (id) async => _business(),
      invalidatePublishedTOsCache: () {},
    );

AttendanceCheckReads _destReads(
        List<ApplicationModel> apps, List<AttendanceModel> atts) =>
    AttendanceCheckReads(
      myApplications: (uid) async => apps,
      todayAttendance: (
          {required String userId, required String applicationId}) async {
        for (final a in atts) {
          if (a.applicationId == applicationId && a.userId == userId) return a;
        }
        return null;
      },
    );

Future<void> _reset(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await _reset(tester);
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

/// 한 시나리오를 **두 화면에 같은 fixture 로** 물린 결과.
typedef _Parity = ({bool homeCard, bool destListed});

Future<_Parity> _run(
  WidgetTester tester, {
  required DateTime nowInstant,
  required _Device device,
  required DateTime workDateKstMidnight,
  DateTime? checkInInstant,
  DateTime? checkOutInstant,
  String status = AttendanceModel.statusPresent,
  List<ApplicationModel> extraApps = const [],
  List<AttendanceModel> extraAtts = const [],
}) async {
  DateTime dev(DateTime t) => _asDevice(t, device);

  final apps = <ApplicationModel>[
    _shortTerm(workDate: dev(workDateKstMidnight)),
    ...extraApps,
  ];
  final atts = <AttendanceModel>[
    _att(
      workDate: dev(workDateKstMidnight),
      checkInAt: checkInInstant == null ? null : dev(checkInInstant),
      checkOutAt: checkOutInstant == null ? null : dev(checkOutInstant),
      status: status,
    ),
    ...extraAtts,
  ];
  DateTime clock() => dev(nowInstant);

  await _pump(
    tester,
    UserHomeScreen(reads: _homeReads(apps, atts), clock: clock),
  );
  final homeCard = find.text('퇴근 기록이 남았어요').evaluate().isNotEmpty;

  await _pump(
    tester,
    AttendanceCheckScreen(reads: _destReads(apps, atts), clock: clock),
  );
  // 목적지가 **그 근무를 찾았는지**를 본다 — 화면이 열렸는지가 아니다.
  final destListed = find.text('강남 물류센터').evaluate().isNotEmpty;

  return (homeCard: homeCard, destListed: destListed);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'tour_completed_user_home': true});
  });

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  // 시나리오 고정값:
  //   근무일 = 2026-09-28(KST), 23:00 KST 출근, 미퇴근.
  //   자정 배치(`processMissedCheckouts`)는 createdAt 24시간 경과분만
  //   `missed_checkout` 으로 바꾸므로 **2026-09-29 하루 내내 퇴근 가능 상태**다.
  final workDate = _kst(2026, 9, 28);
  final checkIn = _kst(2026, 9, 28, 23, 0);

  group('KST-DEV 같은 근무를 두 화면이 같은 날로 부르는가', () {
    testWidgets('KDP-1 KST 기기 · 09-29 01:00 — 둘 다 그 근무를 본다', (tester) async {
      final r = await _run(
        tester,
        nowInstant: _kst(2026, 9, 29, 1, 0),
        device: _Device.kst,
        workDateKstMidnight: workDate,
        checkInInstant: checkIn,
      );
      expect(r.homeCard, isTrue);
      expect(r.destListed, isTrue, reason: '홈이 보낸 근무가 목적지 목록에 있어야 한다');
    });

    testWidgets('KDP-2 KST 기기 · 09-29 10:00 — 둘 다 그 근무를 본다', (tester) async {
      final r = await _run(
        tester,
        nowInstant: _kst(2026, 9, 29, 10, 0),
        device: _Device.kst,
        workDateKstMidnight: workDate,
        checkInInstant: checkIn,
      );
      expect(r.homeCard, isTrue);
      expect(r.destListed, isTrue);
    });

    // ── 방향 A: 기기 날짜가 KST 보다 하루 뒤처진 구간 ──────────────
    //   근무일 필드는 09-27(UTC), 기기 오늘은 09-29 → 기기 기준
    //   {오늘, 어제} = {09-29, 09-28} 에 09-27 이 없다.
    testWidgets('KDP-3 UTC 기기 · 09-29 10:00 KST — 홈이 보낸 근무가 목적지에 있어야 한다',
        (tester) async {
      final r = await _run(
        tester,
        nowInstant: _kst(2026, 9, 29, 10, 0),
        device: _Device.utc,
        workDateKstMidnight: workDate,
        checkInInstant: checkIn,
      );
      expect(r.homeCard, isTrue);
      expect(r.destListed, isTrue,
          reason: '기기 로컬 자정으로 날짜를 만들면 이 근무가 목록에서 사라진다 '
              '— 홈은 퇴근하라는데 목적지에 그 근무가 없다');
    });

    testWidgets('KDP-4 UTC 기기 · 09-29 01:00 KST — 기기 날짜가 아직 09-28(정렬 구간)',
        (tester) async {
      final r = await _run(
        tester,
        nowInstant: _kst(2026, 9, 29, 1, 0),
        device: _Device.utc,
        workDateKstMidnight: workDate,
        checkInInstant: checkIn,
      );
      expect(r.homeCard, isTrue);
      expect(r.destListed, isTrue);
    });

    // ── 방향 B: 반대 부호 — KST 로는 **오늘**인 근무를 기기가 어제로 읽는다 ──
    //   그러면 "어제 기록" 제외 규칙이 오늘 기록에 걸려, 이미 퇴근한
    //   **오늘** 근무가 목록에서 사라진다.
    testWidgets('KDP-5 UTC 기기 · 오늘(KST) 퇴근 완료한 근무가 목록에서 사라지지 않는다',
        (tester) async {
      final r = await _run(
        tester,
        nowInstant: _kst(2026, 9, 29, 20, 0),
        device: _Device.utc,
        workDateKstMidnight: _kst(2026, 9, 29),
        checkInInstant: _kst(2026, 9, 29, 9, 0),
        checkOutInstant: _kst(2026, 9, 29, 18, 0),
      );
      expect(r.homeCard, isFalse, reason: '오늘 근무는 Hero 의 몫이다');
      expect(r.destListed, isTrue,
          reason: '오늘 끝낸 근무가 "어제 기록" 규칙에 걸려 사라지면 안 된다');
    });
  });

  group('KST-DEV 제외 조건은 두 화면에서 같이 움직인다', () {
    testWidgets('이미 퇴근 — 둘 다 안 보인다(UTC 기기)', (tester) async {
      final r = await _run(
        tester,
        nowInstant: _kst(2026, 9, 29, 10, 0),
        device: _Device.utc,
        workDateKstMidnight: workDate,
        checkInInstant: checkIn,
        checkOutInstant: _kst(2026, 9, 29, 6, 0),
      );
      expect(r.homeCard, isFalse);
      expect(r.destListed, isFalse);
    });

    testWidgets('미출근 — 홈은 CTA 없음, 목적지는 출근하러 남는다(UTC 기기)',
        (tester) async {
      final r = await _run(
        tester,
        nowInstant: _kst(2026, 9, 29, 10, 0),
        device: _Device.utc,
        workDateKstMidnight: workDate,
      );
      expect(r.homeCard, isFalse, reason: '출근 기록이 없으면 퇴근 CTA 를 만들지 않는다');
      // 목적지는 어제 근무를 출근 후보로 남긴다 — 의도된 차이(퇴근 CTA 가 아니다).
      expect(r.destListed, isTrue);
    });

    testWidgets('NO_SHOW — 둘 다 그 근무를 내보내지 않는다(UTC 기기)', (tester) async {
      final r = await _run(
        tester,
        nowInstant: _kst(2026, 9, 29, 10, 0),
        device: _Device.utc,
        workDateKstMidnight: workDate,
        checkInInstant: checkIn,
        status: AttendanceModel.statusNoShow,
      );
      expect(r.homeCard, isFalse);
      expect(r.destListed, isFalse);
    });
  });

  group('KST-DEV 지난달 꼬리 읽기 — 실제 호출 수', () {
    Future<List<String>> monthCallsAt(WidgetTester tester, DateTime kstNow) async {
      final calls = <String>[];
      DateTime clock() => _asDevice(kstNow, _Device.kst);
      await _pump(
        tester,
        UserHomeScreen(
          reads: _homeReads(const [], const [], monthCalls: calls),
          clock: clock,
        ),
      );
      return calls;
    }

    testWidgets('KDP-C1 1일이 아닌 날에는 근태 조회가 1회다', (tester) async {
      final calls = await monthCallsAt(tester, _kst(2026, 9, 29, 10, 0));
      expect(calls, ['2026-9'],
          reason: '꼬리 조회는 달 경계에서만 — 평소에는 추가 원격 요청이 없다');
    });

    testWidgets('KDP-C2 1일에는 2회다 — 이번 달 + 지난달, 같은 Future.wait 안에서',
        (tester) async {
      final calls = await monthCallsAt(tester, _kst(2026, 10, 1, 10, 0));
      expect(calls.length, 2,
          reason: '순차 대기 단계는 늘지 않지만 **원격 요청 1회는 늘어난다**');
      expect(calls.contains('2026-10'), isTrue);
      expect(calls.contains('2026-9'), isTrue);
    });

    testWidgets('KDP-C3 꼬리 판정은 **KST** 1일 기준이다', (tester) async {
      // 기기(UTC) 로는 아직 9/30 21:00 이지만 KST 는 10/1 06:00 이다.
      final calls = <String>[];
      DateTime clock() => _asDevice(_kst(2026, 10, 1, 6, 0), _Device.utc);
      await _pump(
        tester,
        UserHomeScreen(
          reads: _homeReads(const [], const [], monthCalls: calls),
          clock: clock,
        ),
      );
      expect(calls.length, 2, reason: 'KST 로 1일이면 꼬리를 읽어야 한다');
    });
  });

  group('KST-DEV 월 경계와 같은 날 다른 근무', () {
    testWidgets('월말 → 1일: 09-30 근무를 10-01 에 퇴근한다(UTC 기기)',
        (tester) async {
      final r = await _run(
        tester,
        nowInstant: _kst(2026, 10, 1, 10, 0),
        device: _Device.utc,
        workDateKstMidnight: _kst(2026, 9, 30),
        checkInInstant: _kst(2026, 9, 30, 23, 0),
      );
      expect(r.homeCard, isTrue);
      expect(r.destListed, isTrue);
    });

    testWidgets('같은 날 또 다른 근무 — 어제 퇴근과 오늘 근무가 함께 잡힌다(UTC 기기)',
        (tester) async {
      DateTime dev(DateTime t) => _asDevice(t, _Device.utc);
      final apps = [
        _shortTerm(workDate: dev(workDate)),
        _shortTerm(
            id: 'today1', workDate: dev(_kst(2026, 9, 29)), start: '09:00', end: '18:00'),
      ];
      final atts = [
        _att(
            workDate: dev(workDate),
            checkInAt: dev(checkIn)),
      ];
      DateTime clock() => dev(_kst(2026, 9, 29, 10, 0));

      await _pump(tester,
          UserHomeScreen(reads: _homeReads(apps, atts), clock: clock));
      expect(find.text('퇴근 기록이 남았어요'), findsOneWidget);
      expect(find.text('오늘의 근무'), findsOneWidget);

      await _pump(tester,
          AttendanceCheckScreen(reads: _destReads(apps, atts), clock: clock));
      // 두 근무가 모두 목록에 있다 — 어제(퇴근 대기)와 오늘(출근 대기).
      expect(find.text('강남 물류센터'), findsNWidgets(2));
    });
  });
}
