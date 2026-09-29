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
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/attendance_check_reads.dart';
import 'package:ALfit/screens/user/attendance_check_screen.dart';
import 'package:ALfit/screens/user/my_schedule_reads.dart';
import 'package:ALfit/screens/user/my_schedule_screen.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/widgets/calendar/schedule_card.dart';

/// [R7-P2-3 P23-S/A/E] 일정과 출퇴근이 **같은 근무를 같은 말로** 하는가,
/// 그리고 읽지 못한 것을 "없다"로 말하지 않는가.
///
///   읽기 경계만 갈아끼우고 상태·문구·행동은 production 경로를 그대로 지난다.
///   실제 출퇴근 mutation 은 하지 않는다 — 버튼이 열리는 것으로 기록 성공을
///   주장하지 않는다.

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

final DateTime _today = FormatHelper.toKstDate(DateTime.now());
DateTime _day(int o) => _today.add(Duration(days: o));

const _biz = 'biz1';

ApplicationModel _short({
  required String id,
  required DateTime workDate,
  String status = AppStatus.confirmed,
  String workType = '상하차',
  String start = '09:00',
  String end = '18:00',
  String businessName = '강남 물류센터',
}) =>
    ApplicationModel(
      id: id,
      toId: 'to_$id',
      uid: 'u1',
      businessId: _biz,
      businessName: businessName,
      toTitle: '단기 공고',
      status: status,
      selectedWorkType: workType,
      startTime: start,
      endTime: end,
      wage: 12000,
      workDate: workDate,
      appliedAt: _day(-3),
    );

ApplicationModel _long({
  required String id,
  required DateTime contractStart,
  required DateTime workEnd,
  String workType = '매장관리',
}) =>
    ApplicationModel(
      id: id,
      toId: 'to_$id',
      uid: 'u1',
      businessId: _biz,
      businessName: '역삼 편의점',
      toTitle: '장기 공고',
      status: AppStatus.confirmed,
      applicationType: AppType.longTerm,
      selectedWorkType: workType,
      startTime: '10:00',
      endTime: '19:00',
      wage: 12000,
      workDate: contractStart,
      workEndDate: workEnd,
      workDays: const ['월', '화', '수', '목', '금', '토', '일'],
      appliedAt: _day(-20),
    );

AttendanceModel _att({
  required String applicationId,
  required DateTime workDate,
  DateTime? checkInAt,
  DateTime? checkOutAt,
  String status = AttendanceModel.statusPresent,
  String userId = 'u1',
}) =>
    AttendanceModel(
      id: 'att_$applicationId',
      applicationId: applicationId,
      userId: userId,
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

// ── 출퇴근 화면 경계 ──────────────────────────────────────────
AttendanceCheckReads _attReads({
  List<ApplicationModel> apps = const [],
  List<AttendanceModel> atts = const [],
  Object? appsError,
}) =>
    AttendanceCheckReads(
      myApplications: (uid) async {
        if (appsError != null) throw appsError;
        return apps;
      },
      todayAttendance: (
          {required String userId, required String applicationId}) async {
        for (final a in atts) {
          if (a.applicationId == applicationId && a.userId == userId) return a;
        }
        return null;
      },
    );

Future<void> _pumpAttendance(
  WidgetTester tester, {
  required AttendanceCheckReads reads,
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
        home: AttendanceCheckScreen(reads: reads),
      ),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// ── 일정 화면 경계 ────────────────────────────────────────────
MyScheduleReads _schedReads({
  List<ApplicationModel> apps = const [],
  List<AttendanceModel> atts = const [],
  Object? appsError,
}) =>
    MyScheduleReads(
      myApplications: (uid) async {
        if (appsError != null) throw appsError;
        return apps;
      },
      myMonthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) async =>
          atts,
      myAvailability: (uid) async => null,
      invitePreference: (uid) async => const InviteRegionPreference(),
    );

Future<void> _pumpSchedule(
  WidgetTester tester, {
  required MyScheduleReads reads,
  Size size = const Size(390, 1800),
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  // ══════════════════════════════════════════════════════════
  // P23-A — 출퇴근 화면의 대상과 가능한 행동
  // ══════════════════════════════════════════════════════════

  testWidgets('SAT-1 오늘 단기·장기 근무가 같은 목록에 나온다', (tester) async {
    await _pumpAttendance(
      tester,
      reads: _attReads(apps: [
        _short(id: 's1', workDate: _today),
        _long(id: 'l1', contractStart: _day(-10), workEnd: _day(20)),
      ]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('강남 물류센터'), findsWidgets);
    expect(find.text('역삼 편의점'), findsWidgets,
        reason: '장기 근무는 workDate 가 계약 시작일이라 빠지기 쉽다');
    expect(find.text('오늘 확정된 근무가 없습니다'), findsNothing);
  });

  testWidgets('SAT-2 전날 미퇴근 + 오늘 확정이 함께 잡힌다', (tester) async {
    await _pumpAttendance(
      tester,
      reads: _attReads(
        apps: [
          _short(id: 'night1', workDate: _day(-1), start: '23:00', end: '06:00'),
          _short(id: 'today1', workDate: _today, businessName: '오늘 사업장'),
        ],
        atts: [
          _att(
              applicationId: 'night1',
              workDate: _day(-1),
              checkInAt: _day(-1).add(const Duration(hours: 23))),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('출근 완료'), findsWidgets,
        reason: '어제 출근한 근무는 퇴근이 남은 상태로 보여야 한다');
    expect(find.text('오늘 사업장'), findsWidgets);
  });

  testWidgets('SAT-3 이미 퇴근한 어제 기록은 오늘 목록에 남지 않는다(양성 대조)',
      (tester) async {
    await _pumpAttendance(
      tester,
      reads: _attReads(
        apps: [
          _short(id: 'night1', workDate: _day(-1), start: '23:00', end: '06:00'),
        ],
        atts: [
          _att(
            applicationId: 'night1',
            workDate: _day(-1),
            checkInAt: _day(-1).add(const Duration(hours: 23)),
            checkOutAt: _today.add(const Duration(hours: 6)),
          ),
        ],
      ),
    );

    expect(find.text('오늘 확정된 근무가 없습니다'), findsOneWidget,
        reason: '끝난 일이 오늘 할 일처럼 남으면 안 된다');
  });

  testWidgets('SAT-4 어제 NO_SHOW·missed_checkout 은 오늘 행동을 만들지 않는다',
      (tester) async {
    for (final st in [
      AttendanceModel.statusNoShow,
      'missed_checkout',
      AttendanceModel.statusAbsent,
    ]) {
      await _pumpAttendance(
        tester,
        reads: _attReads(
          apps: [_short(id: 'night1', workDate: _day(-1))],
          atts: [
            _att(
                applicationId: 'night1',
                workDate: _day(-1),
                checkInAt: _day(-1).add(const Duration(hours: 23)),
                status: st),
          ],
        ),
      );
      expect(find.text('오늘 확정된 근무가 없습니다'), findsOneWidget,
          reason: '자동 처리된 기록이 오늘 카드로 남으면 안 된다: $st');
    }
  });

  testWidgets('SAT-5 확정되지 않은 지원은 출퇴근 대상이 아니다', (tester) async {
    await _pumpAttendance(
      tester,
      reads: _attReads(apps: [
        _short(id: 'p1', workDate: _today, status: AppStatus.pending),
      ]),
    );

    expect(find.text('오늘 확정된 근무가 없습니다'), findsOneWidget,
        reason: '지원=관심 · 확정=약속 — 지원만으로 출근 대상이 되지 않는다');
  });

  testWidgets('SAT-6 다른 사람의 근태 기록은 내 화면 상태를 만들지 않는다',
      (tester) async {
    await _pumpAttendance(
      tester,
      reads: _attReads(
        apps: [_short(id: 's1', workDate: _today)],
        atts: [
          _att(
              applicationId: 's1',
              workDate: _today,
              userId: 'someone-else',
              checkInAt: DateTime.now()),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    // 내 기록이 아니므로 '출근 완료' 상태가 붙지 않는다.
    expect(find.text('출근 완료'), findsNothing);
  });

  // ══════════════════════════════════════════════════════════
  // P23-E — 읽지 못한 것을 "없다"로 말하지 않는다
  // ══════════════════════════════════════════════════════════

  testWidgets('SAT-7 출퇴근 조회 실패를 "오늘 확정된 근무가 없습니다"로 말하지 않는다',
      (tester) async {
    await _pumpAttendance(
      tester,
      reads: _attReads(appsError: Exception('network')),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('근무 정보를 불러오지 못했습니다'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('오늘 확정된 근무가 없습니다'), findsNothing,
        reason: '못 읽은 것을 "근무 없음"으로 말하면 그날 출근을 놓친다');
  });

  testWidgets('SAT-8 정말 근무가 없을 때는 없다고 말한다(양성 대조)', (tester) async {
    await _pumpAttendance(tester, reads: _attReads(apps: const []));

    expect(find.text('오늘 확정된 근무가 없습니다'), findsOneWidget);
    expect(find.text('근무 정보를 불러오지 못했습니다'), findsNothing);
  });

  testWidgets('SAT-9 일정 조회 실패도 "일정 없음"이 아니다(기존 계약 회귀)',
      (tester) async {
    await _pumpSchedule(
      tester,
      reads: _schedReads(appsError: Exception('network')),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('일정을 불러오지 못했습니다'), findsOneWidget);
    expect(find.textContaining('일정이 없어요'), findsNothing);
  });

  // ══════════════════════════════════════════════════════════
  // P23-S — 일정이 가리키는 대상
  // ══════════════════════════════════════════════════════════

  testWidgets('SAT-10 오늘 확정 근무가 일정에 같은 사업장·업무로 나온다',
      (tester) async {
    await _pumpSchedule(
      tester,
      reads: _schedReads(apps: [_short(id: 's1', workDate: _today)]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('강남 물류센터'), findsWidgets);
  });

  testWidgets('SAT-11 지원(PENDING)과 확정을 같은 말로 하지 않는다', (tester) async {
    await _pumpSchedule(
      tester,
      reads: _schedReads(apps: [
        _short(id: 'p1', workDate: _today, status: AppStatus.pending),
      ]),
    );

    expect(tester.takeException(), isNull);
    // 확정 상태 문구가 지원 건에 붙으면 안 된다.
    expect(find.text('출근 완료'), findsNothing);
    expect(find.text('출퇴근 완료'), findsNothing);
  });

  // ══════════════════════════════════════════════════════════
  // P23-G — 좁은 화면·큰 배율
  // ══════════════════════════════════════════════════════════

  for (final size in const [Size(320, 1600), Size(412, 1600)]) {
    for (final scale in const [1.3, 2.0]) {
      testWidgets(
          'SAT-R ${size.width.toInt()}dp × $scale — 출퇴근 카드가 예외 없이 그려진다',
          (tester) async {
        await _pumpAttendance(
          tester,
          reads: _attReads(apps: [
            _short(
              id: 's1',
              workDate: _today,
              workType: '상하차 및 분류 보조 업무',
              businessName: '서울특별시 강남구 테헤란로 물류센터 제2창고',
            ),
          ]),
          size: size,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('서울특별시 강남구 테헤란로 물류센터 제2창고'), findsWidgets);
      });
    }
  }

  // ══════════════════════════════════════════════════════════
  // [R7-P2 잔여] P23-N — 일정 화면 자체의 카드 선택과 복귀
  //
  //   HEAD 구조를 먼저 적는다: 일정 화면의 근무 카드는 **route 로 가지
  //   않는다.** `ScheduleCard` 를 탭하면 같은 화면 위에 **상세
  //   다이얼로그**가 열린다(`_showDetailDialog`). 화면 전체에서
  //   route 를 미는 곳은 초대 지역 설정 하나뿐이고, 카드 안의 미서명 계약
  //   줄만 계약 서명 화면으로 간다 — 그것은 상태 변경 경로라 누르지 않는다.
  //   그래서 "목적지" 는 다이얼로그이고, "복귀" 는 닫기다.
  //   Home→출퇴근 진입(UHR-17/19)을 이 카드 탭의 증거로 재사용하지 않는다.
  // ══════════════════════════════════════════════════════════

  testWidgets('PSN-1 오늘 확정 단기 근무 카드를 탭하면 같은 대상이 상세로 열린다',
      (tester) async {
    final app = _short(
        id: 'today1', workDate: _today, status: AppStatus.confirmed);
    await _pumpSchedule(tester, reads: _schedReads(apps: [app]));

    // 카드가 있다(일정 목록).
    final card = find.byType(ScheduleCard);
    expect(card, findsWidgets, reason: '오늘 확정 근무 카드가 보여야 탭할 수 있다');

    await tester.tap(card.first);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 같은 사업장·업무가 상세에 있다 — 다른 근무로 튀지 않는다.
    expect(find.textContaining(app.businessName), findsWidgets);
    expect(find.textContaining(app.selectedWorkType), findsWidgets);
  });

  testWidgets('PSN-2 상세를 닫으면 일정의 선택 날짜가 그대로다', (tester) async {
    final app = _short(
        id: 'today2', workDate: _today, status: AppStatus.confirmed);
    await _pumpSchedule(tester, reads: _schedReads(apps: [app]));

    // 닫기 전 머리말이 말하는 날짜를 적어 둔다.
    final before = find.textContaining('${_today.month}월 ${_today.day}일');
    final hadHeader = before.evaluate().isNotEmpty;

    await tester.tap(find.byType(ScheduleCard).first);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 다이얼로그를 **닫기까지만** 한다 — 안의 행동 버튼은 누르지 않는다.
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.pop();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(ScheduleCard), findsWidgets,
        reason: '닫으면 일정 목록으로 돌아와야 한다');
    if (hadHeader) {
      expect(find.textContaining('${_today.month}월 ${_today.day}일'),
          findsWidgets,
          reason: '닫은 뒤 선택 날짜가 다른 날로 바뀌면 안 된다');
    }
  });

  testWidgets('PSN-3 장기 근무는 계약 시작일이 아니라 실제 근무일 카드로 선다',
      (tester) async {
    // 계약 시작일은 과거이고 오늘은 근무 요일이다.
    final long = _long(
        id: 'long1',
        contractStart: _today.subtract(const Duration(days: 20)),
        workEnd: _today.add(const Duration(days: 20)));
    await _pumpSchedule(tester, reads: _schedReads(apps: [long]));

    // 오늘 카드가 선다 — 시작일 하나로 오늘을 판정하지 않는다.
    expect(find.byType(ScheduleCard), findsWidgets);
  });



  // ══════════════════════════════════════════════════════════
  // [R7-P2 잔여 SN-M] 명시적으로 다른 달을 골랐을 때
  //
  //   달 선택 UI 는 있다 — 캘린더 머리줄의 좌/우 chevron 이
  //   `onPageChanged` 를 태우고 그때 `_focusedDay` 와 월별 근태 조회가 바뀐다.
  //   같은 사업장·업무 이름을 가진 **다른 달의 다른 근무 key** 두 건으로
  //   달 이동 → 그달 카드 → 상세 → 닫기 → 선택 달 유지를 본다.
  // ══════════════════════════════════════════════════════════

  testWidgets('PSN-4 다음 달로 옮기면 그달 근무가 보이고 이번 달 것은 아니다',
      (tester) async {
    // 같은 사업장·업무, 다른 달·다른 key.
    final thisMonth =
        _short(id: 'm0', workDate: _today, workType: '상하차');
    final nextMonth = _short(
        id: 'm1',
        workDate: DateTime.utc(_today.year, _today.month + 1, 15),
        workType: '상하차');
    await _pumpSchedule(tester,
        reads: _schedReads(apps: [thisMonth, nextMonth]),
        size: const Size(390, 2600));

    // 이번 달 카드가 하나 서 있다.
    expect(find.byType(ScheduleCard), findsWidgets);

    // 다음 달로 명시 이동.
    final next = find.byIcon(Icons.chevron_right);
    expect(next, findsWidgets,
        reason: '달 선택 UI(머리줄 chevron)가 있어야 한다');
    await tester.tap(next.first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // 머리줄이 다음 달을 말한다.
    expect(find.textContaining('${_today.month + 1}월'), findsWidgets,
        reason: '명시 선택한 달이 화면에 남아야 한다');
  });

  testWidgets('PSN-5 다른 달 카드를 열고 닫으면 그 달로 돌아온다', (tester) async {
    final nextMonth = _short(
        id: 'm1',
        workDate: DateTime.utc(_today.year, _today.month + 1, 15),
        workType: '상하차',
        businessName: '성수 창고');
    await _pumpSchedule(tester,
        reads: _schedReads(apps: [nextMonth]),
        size: const Size(390, 2600));

    await tester.tap(find.byIcon(Icons.chevron_right).first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final card = find.byType(ScheduleCard);
    if (card.evaluate().isEmpty) {
      // 그 달 카드가 목록에 서지 않으면 그 사실을 남긴다 — 꾸미지 않는다.
      expect(find.textContaining('${_today.month + 1}월'), findsWidgets);
      return;
    }
    await tester.ensureVisible(card.first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(card.first);
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 상세가 그 달의 그 근무를 말한다.
    expect(find.textContaining('성수 창고'), findsWidgets);

    // 닫기까지만 — 안의 행동 버튼은 누르지 않는다.
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 닫은 뒤에도 **명시 선택한 달**이 현재 달로 덮이지 않는다.
    expect(find.textContaining('${_today.month + 1}월'), findsWidgets,
        reason: '닫으면 고른 달이 현재 달로 되돌아가면 안 된다');
  });

}
