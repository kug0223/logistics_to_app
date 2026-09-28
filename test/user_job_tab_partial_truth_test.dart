import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/to_filter_state.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/job_posting_screen.dart';
import 'package:ALfit/screens/user/tabs/user_job_tab.dart';
import 'package:ALfit/screens/user/tabs/user_job_tab_reads.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/utils/format_helper.dart';

/// [R7-P2-2 P22-L/N] 일자리 탭이 **부분 결과를 "없음"으로 말하지 않는가**,
/// 그리고 목록에서 고른 하루가 상세까지 살아 있는가.
///
///   production 위젯을 읽기 경계 한 칸만 갈아끼워 돌린다. 페이지는 서버가
///   나눠 주고 날짜는 클라이언트가 거른다 — 그 사이가 이번 검증 대상이다.

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

/// 장기(contract) 공고 — 목록의 날짜 필터는 `date ~ endDate` 겹침으로 본다.
TOModel _to({
  required String id,
  required String title,
  required DateTime start,
  required DateTime end,
}) =>
    TOModel(
      id: id,
      businessId: 'biz1',
      businessName: '강남 물류센터',
      type: 'contract',
      title: title,
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
      rangeStart: start,
      rangeEnd: end,
      createdAt: _day(-5),
      statusUpdatedAt: _day(-5),
    );

/// 페이지를 나눠 주는 서버 흉내 — 날짜는 **서버가 거르지 않는다**(현행 계약).
UserJobTabReads _reads({
  required List<List<TOModel>> pages,
  Map<String, int>? calls,
  Object? firstPageError,
}) {
  return UserJobTabReads(
    publishedTOsPaged: ({String? lastToId, TOFilterState? filter}) async {
      calls?['paged'] = (calls?['paged'] ?? 0) + 1;
      if (lastToId == null && firstPageError != null) throw firstPageError;
      final idx = lastToId == null ? 0 : int.parse(lastToId);
      final items = idx < pages.length ? pages[idx] : <TOModel>[];
      final hasMore = idx + 1 < pages.length;
      return {
        'items': items,
        'lastToId': hasMore ? '${idx + 1}' : null,
        'hasMore': hasMore,
      };
    },
    myApplications: (uid) async => const <ApplicationModel>[],
    tosByIds: (ids) async => const <TOModel>[],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required UserJobTabReads reads,
  DateTime? pendingJobDate,
  Size size = const Size(390, 1400),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));

  DateTime? pending = pendingJobDate;
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
        // 홈 날짜 CTA 와 같은 경로 — root 가 넘겨 주고 탭이 소비한다.
        home: UserTabScope(
          switchToTab: (_) {},
          switchToTabWithDate: (_, __) {},
          pendingJobDate: pending,
          clearPendingJobDate: () => pending = null,
          pendingScheduleMonth: null,
          clearPendingScheduleMonth: () {},
          switchToScheduleNow: () {},
          child: UserJobTab(reads: reads),
        ),
      ),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  // 1페이지에는 **그 날짜가 없는** 공고만, 2페이지에 있다.
  List<List<TOModel>> twoPages() => [
        [
          _to(id: 'p1a', title: '1페이지 공고 A', start: _day(20), end: _day(30)),
          _to(id: 'p1b', title: '1페이지 공고 B', start: _day(21), end: _day(31)),
        ],
        [
          _to(id: 'p2a', title: '2페이지 공고', start: _day(1), end: _day(3)),
        ],
      ];

  testWidgets('UJT-1 첫 페이지가 다 걸러져도 "없습니다"라고 말하지 않는다',
      (tester) async {
    await _pump(
      tester,
      reads: _reads(pages: twoPages()),
      pendingJobDate: _day(2), // 홈 날짜 CTA — 1페이지에는 없는 날
    );

    expect(tester.takeException(), isNull);
    expect(find.text('필터 조건에 맞는 공고가 없습니다'), findsNothing,
        reason: '읽지 않은 페이지가 남아 있는데 "없다"고 말하면 지원 기회를 잃는다');
  });

  testWidgets('UJT-2 남은 페이지를 이어 읽어 그 날짜의 공고를 찾아낸다',
      (tester) async {
    final calls = <String, int>{};
    await _pump(
      tester,
      reads: _reads(pages: twoPages(), calls: calls),
      pendingJobDate: _day(2),
    );

    expect(calls['paged'], greaterThanOrEqualTo(2),
        reason: '조건이 첫 페이지를 다 걸러 냈으면 다음 페이지를 읽어야 한다');
    expect(find.text('2페이지 공고'), findsOneWidget,
        reason: '홈에서 고른 날짜의 공고가 목록에 나타나야 한다');
  });

  testWidgets('UJT-3 정말 없을 때(더 읽을 페이지 없음)는 "없습니다"라고 말한다',
      (tester) async {
    await _pump(
      tester,
      reads: _reads(pages: [
        [
          _to(id: 'only', title: '유일 공고', start: _day(20), end: _day(30)),
        ],
      ]),
      pendingJobDate: _day(2),
    );

    expect(find.text('필터 조건에 맞는 공고가 없습니다'), findsOneWidget,
        reason: '읽을 것이 남지 않았으면 없다고 말해야 한다 — 양성 대조');
  });

  testWidgets('UJT-4 조회 실패는 "없음"이 아니라 "못 읽음"이다', (tester) async {
    await _pump(
      tester,
      reads: _reads(pages: twoPages(), firstPageError: Exception('network')),
    );

    expect(find.text('공고를 불러오지 못했습니다'), findsOneWidget);
    expect(find.text('등록된 공고가 없습니다'), findsNothing);
    expect(find.text('필터 조건에 맞는 공고가 없습니다'), findsNothing);
  });

  testWidgets('UJT-5 머리말이 말하는 조건·모집단이 목록과 같다', (tester) async {
    await _pump(
      tester,
      reads: _reads(pages: twoPages()),
      pendingJobDate: _day(2),
    );

    final d = _day(2);
    expect(find.textContaining('${d.month}월 ${d.day}일'), findsWidgets,
        reason: '보이는 날짜가 실제 적용된 조건이어야 한다');
  });

  testWidgets('UJT-6 목록에서 고른 하루가 공고 상세까지 살아 있다', (tester) async {
    await _pump(
      tester,
      reads: _reads(pages: twoPages()),
      pendingJobDate: _day(2),
    );

    await tester.tap(find.text('2페이지 공고'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final pushed = tester.widget<JobPostingScreen>(
        find.byType(JobPostingScreen, skipOffstage: false));
    expect(pushed.to?.id, 'p2a', reason: '탭한 공고가 그대로 열려야 한다');
    expect(pushed.slotDate, isNotNull,
        reason: '목록이 하루를 고르고 있었으면 상세도 그 하루를 받아야 한다');
    expect(FormatHelper.toKstDate(pushed.slotDate!),
        FormatHelper.toKstDate(_day(2)));
  });

  testWidgets('UJT-7 날짜를 고르지 않았으면 상세에 하루를 넘기지 않는다', (tester) async {
    await _pump(tester, reads: _reads(pages: twoPages()));

    await tester.tap(find.text('1페이지 공고 A'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final pushed = tester.widget<JobPostingScreen>(
        find.byType(JobPostingScreen, skipOffstage: false));
    expect(pushed.to?.id, 'p1a');
    expect(pushed.slotDate, isNull,
        reason: '고르지 않은 날짜를 상세가 고른 것처럼 만들지 않는다');
  });

  // ══════════════════════════════════════════════════════════
  // N1 — 상세에서 돌아오면 고른 날짜·조건이 그대로인가
  // ══════════════════════════════════════════════════════════

  testWidgets('UJT-8 상세 → 뒤로 → 목록의 선택 날짜·조건·결과가 그대로다',
      (tester) async {
    await _pump(
      tester,
      reads: _reads(pages: twoPages()),
      pendingJobDate: _day(2),
    );

    final d = _day(2);
    // 돌아왔을 때와 비교할 "떠나기 전" 상태.
    expect(find.textContaining('${d.month}월 ${d.day}일'), findsWidgets);
    expect(find.text('2페이지 공고'), findsOneWidget);

    await tester.tap(find.text('2페이지 공고'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(JobPostingScreen, skipOffstage: false), findsOneWidget);

    // 실제 navigator 로 뒤로.
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.pop();
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(JobPostingScreen, skipOffstage: false), findsNothing);
    expect(find.textContaining('${d.month}월 ${d.day}일'), findsWidgets,
        reason: '돌아왔는데 고른 날짜가 풀려 있으면 다시 찾아야 한다');
    expect(find.text('2페이지 공고'), findsOneWidget,
        reason: '조건에 맞던 결과가 그대로여야 한다');
    // 홈이 넘긴 날짜는 **한 번만** 소비된다 — 재진입으로 다시 걸리지 않는다.
    expect(find.text('1페이지 공고 A'), findsNothing);
  });

  for (final size in const [Size(320, 1400), Size(412, 1400)]) {
    for (final scale in const [1.3, 2.0]) {
      testWidgets(
          'UJT-R ${size.width.toInt()}dp × $scale — 조건·목록·CTA 가 예외 없이 그려진다',
          (tester) async {
        await _pump(
          tester,
          reads: _reads(pages: twoPages()),
          pendingJobDate: _day(2),
          size: size,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('2페이지 공고'), findsOneWidget);
      });
    }
  }
}
