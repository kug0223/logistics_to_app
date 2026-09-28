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
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';

/// [R7-P2-1 P21-H/E] **실제 지원자 홈 위젯**을 콘텐츠와 함께 그린다.
///
///   `UserHomeReads` 경계 한 칸만 갈아끼우고 Priority Hero 판정·주간 7일·
///   지원현황 집계·수입·실패 문구는 production 경로를 그대로 지난다.
///   테스트용 카드·계산식·라벨을 복제하지 않는다.
///
///   시계 의존을 만들지 않으려고 모든 fixture 날짜를 **오늘에서 파생**한다.

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
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

/// 지원자 provider — 역할은 USER 고정. 관리자 capability 를 덧씌우지 않는다.
class _UserProviderDouble extends UserProvider {
  _UserProviderDouble({this.uid = 'u1'});

  String uid;
  static const homeRegion =
      UserRegion(province: '서울특별시', city: '강남구', district: '역삼동');

  @override
  UserModel? get currentUser => UserModel(
        uid: uid,
        username: uid,
        name: '김근로',
        email: '$uid@alfit.local',
        role: UserRole.USER,
        homeRegion: homeRegion,
        accountStatus: 'active',
        passVerifiedAt: DateTime.now().subtract(const Duration(days: 30)),
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

  /// 계정 전환을 흉내 낸다 — 늦은 응답 가드가 uid 를 보는지 확인용.
  void switchAccount(String next) {
    uid = next;
    notifyListeners();
  }
}

// ── 오늘에서 파생한 날짜 ────────────────────────────────────────
final DateTime _today = FormatHelper.toKstDate(DateTime.now());
DateTime _day(int offset) => _today.add(Duration(days: offset));

const _biz = 'biz1';

/// 단기(슬롯) 지원 — `workDate` 가 실제 근무일이다.
ApplicationModel _shortTerm({
  String id = 'short1',
  required DateTime workDate,
  String status = AppStatus.confirmed,
  String businessName = '강남 물류센터',
  String workType = '피킹',
  String start = '09:00',
  String end = '18:00',
  int wage = 12000,
  DateTime? confirmedAt,
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
      wage: wage,
      workDate: workDate,
      confirmedAt: confirmedAt,
      appliedAt: _day(-3),
    );

/// 장기 지원 — `workDate` 는 **계약 시작일(고정값)** 이고 실제 근무는
/// `workDays` 요일이 정한다. Hero 가 이 구분을 지키는지가 P21-H 의 핵심이다.
ApplicationModel _longTerm({
  String id = 'long1',
  required DateTime contractStart,
  required DateTime workEnd,
  String businessName = '역삼 편의점',
  String workType = '매장관리',
  String start = '10:00',
  String end = '19:00',
  List<String>? workDays,
  List<DateTime> leaveDates = const [],
}) =>
    ApplicationModel(
      id: id,
      toId: 'to_$id',
      uid: 'u1',
      businessId: _biz,
      businessName: businessName,
      toTitle: '장기 공고',
      status: AppStatus.confirmed,
      applicationType: AppType.longTerm,
      selectedWorkType: workType,
      startTime: start,
      endTime: end,
      wage: 12000,
      workDate: contractStart,
      workEndDate: workEnd,
      workDays: workDays ?? const ['월', '화', '수', '목', '금', '토', '일'],
      leaveDates: leaveDates,
      appliedAt: _day(-20),
    );

BusinessModel _business() => BusinessModel(
      id: _biz,
      name: '강남 물류센터',
      ownerId: 'admin1',
      businessNumber: '000-00-00000',
      address: '서울특별시 강남구 테헤란로 1',
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: _day(-200),
    );

/// 홈이 읽는 원시 호출만 채운 경계.
UserHomeReads _reads({
  List<ApplicationModel>? applications,
  List<AttendanceModel> attendances = const [],
  List<TOModel> tos = const [],
  Object? applicationsError,
  Object? tosError,
  /// n 번째 호출의 지원 목록을 직접 준다(순서 역전 재현용).
  List<Future<List<ApplicationModel>>>? applicationsByCall,
  Map<String, int>? calls,
}) {
  var appCall = 0;
  return UserHomeReads(
    myApplications: (uid) {
      if (calls != null) calls['apps'] = (calls['apps'] ?? 0) + 1;
      final i = appCall++;
      if (applicationsByCall != null && i < applicationsByCall.length) {
        return applicationsByCall[i];
      }
      if (applicationsError != null) {
        return Future<List<ApplicationModel>>.error(applicationsError);
      }
      return Future<List<ApplicationModel>>.value(
          applications ?? const <ApplicationModel>[]);
    },
    myMonthlyAttendances: (
            {required String userId,
            required int year,
            required int month}) async =>
        attendances,
    publishedTOs: () async {
      if (tosError != null) throw tosError;
      return tos;
    },
    pendingIdCardRequests: (uid) async => const <IdCardAccessRequestModel>[],
    myRenewalProposals: () async => const <RenewalProposalModel>[],
    businessById: (id) async => _business(),
    invalidatePublishedTOsCache: () {},
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required UserHomeReads reads,
  Size size = const Size(390, 2200),
  double textScale = 1.0,
  _UserProviderDouble? provider,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(
            value: provider ?? _UserProviderDouble()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          // 같은 타입 화면을 연달아 pump 하면 State 가 재사용돼 시나리오가
          // 섞인다 — 매 pump 를 새 State 로 격리한다.
          child: KeyedSubtree(key: UniqueKey(), child: child!),
        ),
        home: UserHomeScreen(reads: reads),
      ),
    ),
  );
  // pumpAndSettle 은 쓰지 않는다 — 홈에 멈추지 않는 애니메이션이 있다.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    // 투어를 완료로 둔다 — 아니면 첫 프레임에 투어 화면이 덮는다.
    SharedPreferences.setMockInitialValues({'tour_completed_user_home': true});
  });

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  // ══════════════════════════════════════════════════════════
  // P21-H — Priority Hero 가 오늘 일하는 사람을 빠뜨리지 않는다
  // ══════════════════════════════════════════════════════════

  testWidgets('UHR-1 오늘 근무하는 **장기** 근무자에게 출퇴근 Hero 가 뜬다',
      (tester) async {
    // 계약 시작일은 10일 전 — 오늘이 아니다. 오늘은 근무 요일에 들어 있다.
    await _pump(
      tester,
      reads: _reads(applications: [
        _longTerm(contractStart: _day(-10), workEnd: _day(20)),
      ]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('오늘의 근무'), findsOneWidget,
        reason: '장기 근무의 workDate 는 계약 시작일이라 '
            'toKstDate(workDate)==today 로는 오늘 일하는 사람이 누락됐다');
    expect(find.text('오늘 10:00 출근이에요'), findsOneWidget);
    expect(find.text('출근하기'), findsOneWidget);
    // 날짜 탐색은 Priority Hero 와 **독립된 상시 섹션**이다(설계 주석 명시).
    // 둘이 동시에 보이는 것이 정상이므로 배타 조건으로 쓰지 않는다.
    expect(find.text('언제 일하고 싶으세요?'), findsOneWidget);
  });

  testWidgets('UHR-2 수정 전 술어(workDate==today)는 같은 fixture 에서 Hero 를 잃는다',
      (tester) async {
    // 수정 전 코드가 무엇을 했는지 **같은 production 모델**로 보여 준다.
    final app = _longTerm(contractStart: _day(-10), workEnd: _day(20));

    // 수정 전: 계약 시작일만 봤다 → 오늘이 아니다 → Hero 없음
    expect(FormatHelper.toKstDate(app.workDate) == _today, isFalse);
    // 수정 후: canonical 술어는 오늘 근무라고 답한다
    expect(app.isWorkingOnDate(_today), isTrue);

    // 그리고 화면은 수정 후 술어를 따른다.
    await _pump(tester, reads: _reads(applications: [app]));
    expect(find.text('오늘의 근무'), findsOneWidget);
  });

  testWidgets('UHR-3 휴무일은 오늘 근무가 아니다 — 술어를 통째로 느슨하게 만들지 않았다',
      (tester) async {
    await _pump(
      tester,
      reads: _reads(applications: [
        _longTerm(
          contractStart: _day(-10),
          workEnd: _day(20),
          leaveDates: [_today],
        ),
      ]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('오늘의 근무'), findsNothing,
        reason: '휴무일에 출근 CTA 를 띄우면 없는 근무를 만들어낸다');
  });

  testWidgets('UHR-4 단기 오늘 근무는 그대로 Hero 를 유지한다(회귀)', (tester) async {
    await _pump(
      tester,
      reads: _reads(applications: [_shortTerm(workDate: _today)]),
    );

    expect(find.text('오늘의 근무'), findsOneWidget);
    expect(find.text('오늘 09:00 출근이에요'), findsOneWidget);
  });

  testWidgets('UHR-5 오늘 근무가 없고 새 확정이 있으면 새 확정 Hero', (tester) async {
    await _pump(
      tester,
      reads: _reads(applications: [
        _shortTerm(
          id: 'new1',
          workDate: _day(3),
          confirmedAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ]),
    );

    expect(find.text('새로운 소식'), findsOneWidget);
    expect(find.text('오늘의 근무'), findsNothing);
  });

  testWidgets('UHR-6 아무것도 없으면 날짜 탐색 Hero', (tester) async {
    await _pump(tester, reads: _reads(applications: const []));

    expect(find.text('언제 일하고 싶으세요?'), findsOneWidget);
    expect(find.text('오늘의 근무'), findsNothing);
    expect(find.text('새로운 소식'), findsNothing);
  });

  // ══════════════════════════════════════════════════════════
  // P21-E — 실패·0건·부분, 그리고 늦은 응답
  // ══════════════════════════════════════════════════════════

  testWidgets('UHR-7 지원 조회 실패는 `0건`이 아니라 모른다고 말한다', (tester) async {
    await _pump(
      tester,
      reads: _reads(applicationsError: Exception('network')),
    );

    expect(find.text('지원 현황을 불러오지 못했어요'), findsOneWidget);
    // 실패한 섹션마다 재시도를 준다 — 한 곳만 있으면 나머지는 막힌 채로 남는다.
    expect(find.text('다시 시도'), findsWidgets);
    expect(find.text('아직 지원한 일자리가 없어요'), findsNothing,
        reason: '못 읽은 것을 "없다"로 바꾸면 사용자가 지원 기록을 잃었다고 믿는다');
  });

  testWidgets('UHR-8 정상 0건은 실패와 다른 화면이다', (tester) async {
    await _pump(tester, reads: _reads(applications: const []));

    expect(find.text('아직 지원한 일자리가 없어요'), findsOneWidget);
    expect(find.text('지원 현황을 불러오지 못했어요'), findsNothing);
  });

  testWidgets('UHR-9 공고만 실패하면 지원 현황은 살아 있다(부분 실패)', (tester) async {
    await _pump(
      tester,
      reads: _reads(
        applications: [_shortTerm(workDate: _today)],
        tosError: Exception('to read failed'),
      ),
    );

    expect(tester.takeException(), isNull);
    // 한 칸이 실패해도 나머지 칸은 그대로 그린다
    expect(find.text('오늘의 근무'), findsOneWidget);
    expect(find.text('지원 현황을 불러오지 못했어요'), findsNothing);
  });

  testWidgets('UHR-10 같은 계정의 재진입은 이미 직렬화돼 있다 — 순서 역전이 생기지 않는다',
      (tester) async {
    // 측정해서 남긴다: `_isLoadingHomeData` 가 진행 중 재진입을 막으므로
    //   **같은 uid** 의 두 로드는 애초에 겹치지 않는다. 그래서 seq 카운터는
    //   관측된 사건을 고치는 것이 아니라 uid 가드와 함께 두는 이중 방어다.
    //   이 사실을 적어 두지 않으면 다음 사람이 "seq 가 이 버그를 고쳤다"고
    //   읽는다.
    final slow = Completer<List<ApplicationModel>>();
    final calls = <String, int>{};

    await _pump(
      tester,
      reads: _reads(calls: calls, applicationsByCall: [slow.future]),
    );

    // 1번째가 미완인 채로 당겨서 새로고침을 시도한다.
    await tester.fling(
        find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(calls['apps'], 1,
        reason: '진행 중 로드가 있으면 두 번째 로드가 아예 시작되지 않는다');

    slow.complete([_shortTerm(id: 'fresh', workDate: _today)]);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('오늘의 근무'), findsOneWidget);
  });

  testWidgets('UHR-11 계정이 바뀌면 이전 사용자의 응답을 앉히지 않는다', (tester) async {
    final slow = Completer<List<ApplicationModel>>();
    final provider = _UserProviderDouble();

    await _pump(
      tester,
      provider: provider,
      reads: _reads(applicationsByCall: [slow.future]),
    );

    // 로드가 떠 있는 사이 계정이 바뀐다.
    provider.switchAccount('u2');
    await tester.pump();

    // 이전 사용자의 지원 내역이 뒤늦게 도착한다.
    slow.complete([_shortTerm(id: 'other', workDate: _today)]);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('오늘의 근무'), findsNothing,
        reason: '다른 사람의 확정 근무가 새 계정 홈에 앉으면 안 된다');
  });

  // ══════════════════════════════════════════════════════════
  // P21-N/H — 좁은 화면·큰 배율에서 내용이 살아 있는지
  // ══════════════════════════════════════════════════════════

  for (final size in const [Size(320, 2400), Size(360, 2400), Size(412, 2400)]) {
    for (final scale in const [1.3, 2.0]) {
      testWidgets(
          'UHR-R ${size.width.toInt()}dp × $scale 배율 — 예외 없이 Hero·지원현황을 그린다',
          (tester) async {
        await _pump(
          tester,
          size: size,
          textScale: scale,
          reads: _reads(applications: [
            _shortTerm(
              workDate: _today,
              businessName: '서울특별시 강남구 테헤란로 물류센터 제2창고',
              workType: '상하차 및 분류 보조 업무',
              wage: 1250000,
            ),
          ]),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('오늘의 근무'), findsOneWidget);
        expect(find.text('출근하기'), findsOneWidget);
        expect(find.text('지원 현황'), findsOneWidget);
      });
    }
  }
}
