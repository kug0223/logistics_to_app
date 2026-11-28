// ignore_for_file: depend_on_referenced_packages
// [PERF impl_13 · 2026-11-26] 근로자 탭 — L18(빈 결과 자동 이어읽기 예산) · P11(요약 줄 자리) · P9(재방문 신선도).
//
//   J1–J5  L18 — 페이지·시간 두 상한 · 상한 뒤 사용자 다음 묶음 · 빈 페이지/같은 커서를 '끝(0)'으로 인증하지 않는다
//   J6     P11 — 결과 요약 줄이 응답 뒤 끼어들어 목록을 밀지 않는다
//   J7–J11 P9 일자리 — 신선하면 호출 0 · 시간 지나면 화면을 비우지 않고 재검증 · 무효화 세대 · 숨은 탭 복귀 0 ·
//          더 불러온 뒤 목록 유지 · 재검증 실패는 기존 실패 정책(DU210)
//   S1–S3  P9 내 일정 — 신선하면 0 · 지나면 달력을 둔 채 재검증 · 무효화 세대
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/invite_region_preference.dart';
import 'package:ALfit/models/core/to_filter_state.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_schedule_reads.dart';
import 'package:ALfit/screens/user/my_schedule_screen.dart';
import 'package:ALfit/screens/user/tabs/user_job_tab.dart';
import 'package:ALfit/screens/user/tabs/user_job_tab_reads.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/widgets/common/skeleton_widget.dart';

import 'support/visible_text.dart';

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

TOModel _to(String id, {required int startOffset, required int endOffset}) => TOModel(
      id: id,
      businessId: 'biz1',
      businessName: '강남 물류센터',
      type: 'contract',
      title: '공고 $id',
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
      rangeStart: _day(startOffset),
      rangeEnd: _day(endOffset),
      createdAt: _day(-5),
      statusUpdatedAt: _day(-5),
    );

/// 날짜 필터(+2일)에 걸리지 않는 공고 / 걸리는 공고.
TOModel _miss(String id) => _to(id, startOffset: 20, endOffset: 30);
TOModel _hit(String id) => _to(id, startOffset: 1, endOffset: 3);

class _Calls {
  int paged = 0;
  int apps = 0;
}

/// 서버 흉내. [pages] 를 차례로 준다. [onPaged] 로 시각을 흘리거나 응답을 붙잡는다.
UserJobTabReads _jobReads(
  List<List<TOModel>> pages,
  _Calls calls, {
  Future<void> Function(int idx)? onPaged,
  Map<String, dynamic>? Function(int idx)? override,
  int Function()? revision,
  Object? Function()? failFirstPage,
}) =>
    UserJobTabReads(
      publishedTOsPaged: ({String? lastToId, TOFilterState? filter}) async {
        calls.paged++;
        final idx = lastToId == null ? 0 : int.parse(lastToId);
        await onPaged?.call(idx);
        if (idx == 0) {
          final err = failFirstPage?.call();
          if (err != null) throw err;
        }
        final ov = override?.call(idx);
        if (ov != null) return ov;
        final items = idx < pages.length ? pages[idx] : <TOModel>[];
        final hasMore = idx + 1 < pages.length;
        return {
          'items': items,
          'lastToId': hasMore ? '${idx + 1}' : null,
          'hasMore': hasMore,
        };
      },
      myApplications: (uid) async {
        calls.apps++;
        return const <ApplicationModel>[];
      },
      tosByIds: (ids) async => const <TOModel>[],
      applicationsRevision: revision == null ? null : (_) => revision(),
    );

/// TickerMode 로 감싸 셸의 "숨은 탭"을 흉내 낸다.
final ValueNotifier<bool> _visible = ValueNotifier<bool>(true);

Future<void> _settle(WidgetTester t, [int n = 25]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpJob(WidgetTester tester, UserJobTabReads reads,
    {DateTime? pendingJobDate, DateTime Function()? clock}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  _visible.value = true;
  DateTime? pending = pendingJobDate;
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      home: UserTabScope(
        switchToTab: (_) {},
        switchToTabWithDate: (_, __) {},
        pendingJobDate: pending,
        clearPendingJobDate: () => pending = null,
        pendingScheduleMonth: null,
        clearPendingScheduleMonth: () {},
        switchToScheduleNow: () {},
        child: ValueListenableBuilder<bool>(
          valueListenable: _visible,
          builder: (_, v, child) => TickerMode(enabled: v, child: child!),
          child: UserJobTab(reads: reads, clock: clock),
        ),
      ),
    ),
  ));
  await _settle(tester);
}

/// 실제 순서대로 배경 → 복귀(앱 생명주기 검사기가 건너뛴 전이를 막는다).
void _backgroundAndResume(WidgetTester t) {
  for (final s in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    t.binding.handleAppLifecycleStateChanged(s);
  }
}

Future<void> _revisit(WidgetTester tester) async {
  _visible.value = false;
  await tester.pump();
  _visible.value = true;
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  group('L18 빈 결과 자동 이어읽기 예산', () {
    testWidgets('J1 페이지 상한 — 첫 페이지 + 자동 3쪽에서 멈추고 "여기까지 확인" · "없다"고 하지 않는다', (t) async {
      final calls = _Calls();
      final pages = [for (var i = 0; i < 8; i++) [_miss('m$i')]];
      await _pumpJob(t, _jobReads(pages, calls), pendingJobDate: _day(2));
      expect(calls.paged, 4);
      expect(findVisibleText('여기까지 확인했어요 · 더 찾아볼 수 있어요'), findsOneWidget);
      expect(findVisibleText('더 찾아보기'), findsOneWidget);
      expect(findVisibleText('필터 조건에 맞는 공고가 없습니다'), findsNothing);
      await _settle(t, 30);
      expect(calls.paged, 4, reason: '재build·빈 프레임이 예산을 초기화하지 않는다');
    });

    testWidgets('J2 상한 뒤 "더 찾아보기" = 같은 조건의 다음 묶음 — 첫 페이지 밖의 일치를 찾는다', (t) async {
      final calls = _Calls();
      final pages = [for (var i = 0; i < 5; i++) [_miss('m$i')], [_hit('h5')], [_miss('m6')]];
      await _pumpJob(t, _jobReads(pages, calls), pendingJobDate: _day(2));
      expect(calls.paged, 4);
      await t.tap(findVisibleText('더 찾아보기'));
      await _settle(t);
      expect(findVisibleText('공고 h5'), findsOneWidget);
      expect(calls.paged, 6, reason: '수동 1쪽 + 새 예산의 자동 1쪽에서 일치를 찾고 멈춘다');
    });

    testWidgets('J3 시간 상한 — 페이지 수가 남아도 경과 시간이 넘으면 새 자동 요청을 시작하지 않는다', (t) async {
      final calls = _Calls();
      var now = DateTime(2026, 11, 26, 10);
      final pages = [for (var i = 0; i < 8; i++) [_miss('m$i')]];
      await _pumpJob(
          t,
          _jobReads(pages, calls, onPaged: (_) async => now = now.add(const Duration(seconds: 5))),
          pendingJobDate: _day(2),
          clock: () => now);
      expect(calls.paged, 3, reason: '첫 + 자동 2쪽(10초 경과) — 페이지 상한(4) 전에 시간 상한');
      expect(findVisibleText('여기까지 확인했어요 · 더 찾아볼 수 있어요'), findsOneWidget);
    });

    testWidgets('J4 빈 추가 페이지 + 서버 hasMore=true 는 끝이 아니다 — 정상 0 인증 0', (t) async {
      final calls = _Calls();
      final pages = [[_miss('m0')], <TOModel>[], [_hit('h2')]];
      await _pumpJob(
          t,
          _jobReads(pages, calls,
              override: (idx) => idx == 1
                  ? {'items': <TOModel>[], 'lastToId': '2', 'hasMore': true}
                  : null),
          pendingJobDate: _day(2));
      expect(findVisibleText('필터 조건에 맞는 공고가 없습니다'), findsNothing);
      expect(findVisibleText('더 찾아보기'), findsOneWidget);
      await t.tap(findVisibleText('더 찾아보기'));
      await _settle(t);
      expect(findVisibleText('공고 h2'), findsOneWidget, reason: '커서는 서버가 준 다음 위치로 이어진다');
    });

    testWidgets('J5 같은 커서 반복 — 자동 연쇄를 멈추고 "없다"고 하지 않는다', (t) async {
      final calls = _Calls();
      await _pumpJob(
          t,
          _jobReads([[_miss('m0')]], calls,
              override: (idx) => {
                    'items': [_miss('loop$idx')],
                    'lastToId': '1',
                    'hasMore': true,
                  }),
          pendingJobDate: _day(2));
      expect(calls.paged, lessThanOrEqualTo(3));
      expect(findVisibleText('필터 조건에 맞는 공고가 없습니다'), findsNothing);
      expect(findVisibleText('더 찾아보기'), findsOneWidget);
    });
  });

  group('P11 요약 줄 자리', () {
    testWidgets('J6 응답 뒤 목록이 밀리지 않는다(뼈대 자리 = 목록 자리)', (t) async {
      final calls = _Calls();
      final gate = Completer<void>();
      await _pumpJob(
          t,
          _jobReads([[_hit('h0')]], calls, onPaged: (_) => gate.future));
      final skeletonTop = t.getTopLeft(find.byType(TOListSkeleton)).dy;
      gate.complete();
      await _settle(t);
      final listTop = t.getTopLeft(find.byType(ListView).first).dy;
      expect(listTop, skeletonTop, reason: '요약 줄이 늦게 끼어들면 목록이 그만큼 내려간다');
      expect(findVisibleText('조건에 맞는 일자리 1개'), findsOneWidget);
    });
  });

  group('P9 일자리 재방문 신선도', () {
    testWidgets('J7 신선하면 0 · 3분 뒤 재방문은 화면을 비우지 않고 다시 읽는다', (t) async {
      final calls = _Calls();
      var now = DateTime(2026, 11, 26, 10);
      Completer<void>? hold;
      await _pumpJob(t, _jobReads([[_hit('h0')]], calls, onPaged: (_) => hold?.future ?? Future.value()),
          clock: () => now);
      expect((calls.paged, calls.apps), (1, 1));
      await _revisit(t);
      await _settle(t, 5);
      expect((calls.paged, calls.apps), (1, 1), reason: '신선하면 호출 0');

      now = now.add(const Duration(minutes: 4));
      hold = Completer<void>();
      await _revisit(t);
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(TOListSkeleton), findsNothing, reason: '조용한 재검증 — 뼈대로 바꾸지 않는다');
      expect(findVisibleText('공고 h0'), findsOneWidget, reason: '읽는 동안 보던 목록을 둔다');
      hold.complete();
      await _settle(t, 5);
      expect((calls.paged, calls.apps), (2, 2));
    });

    testWidgets('J8 무효화 세대가 바뀌면(지원·취소 뒤) 지원 내역만 다시 읽는다', (t) async {
      final calls = _Calls();
      var rev = 0;
      await _pumpJob(t, _jobReads([[_hit('h0')]], calls, revision: () => rev));
      rev = 1;
      await _revisit(t);
      await _settle(t, 5);
      expect((calls.paged, calls.apps), (1, 2));
    });

    testWidgets('J9 숨은 탭에서 앱이 복귀해도 network 0', (t) async {
      final calls = _Calls();
      var now = DateTime(2026, 11, 26, 10);
      await _pumpJob(t, _jobReads([[_hit('h0')]], calls), clock: () => now);
      _visible.value = false;
      await t.pump();
      now = now.add(const Duration(minutes: 10));
      _backgroundAndResume(t);
      await _settle(t, 5);
      expect((calls.paged, calls.apps), (1, 1));
      _visible.value = true; // 다음에 보일 때 한 번
      await t.pump();
      await _settle(t, 5);
      expect((calls.paged, calls.apps), (2, 2));
    });

    testWidgets('J10 더 불러온 뒤(커서 진행)에는 목록을 다시 읽지 않는다 — 본 위치 보존', (t) async {
      final calls = _Calls();
      var now = DateTime(2026, 11, 26, 10);
      await _pumpJob(t, _jobReads([[_hit('h0')], [_hit('h1')]], calls), clock: () => now);
      await t.tap(findVisibleText('더 많은 공고 보기'));
      await _settle(t);
      expect(calls.paged, 2);
      now = now.add(const Duration(minutes: 10));
      await _revisit(t);
      await _settle(t, 5);
      expect(calls.paged, 2, reason: '커서·목록 유지');
      expect(calls.apps, 2, reason: '지원 내역은 다시 읽는다');
    });

    testWidgets('J11 조용한 재검증 실패는 기존 실패 정책(DU210) — "없음"으로 말하지 않는다', (t) async {
      final calls = _Calls();
      var now = DateTime(2026, 11, 26, 10);
      var fail = false;
      await _pumpJob(
          t,
          _jobReads([[_hit('h0')]], calls,
              failFirstPage: () => fail ? Exception('net') : null),
          clock: () => now);
      fail = true;
      now = now.add(const Duration(minutes: 4));
      await _revisit(t);
      await _settle(t, 10);
      expect(findVisibleText('공고를 불러오지 못했습니다'), findsOneWidget);
      expect(findVisibleText('등록된 공고가 없습니다'), findsNothing);
    });
  });

  group('P9 내 일정 재방문 신선도', () {
    late int apps;
    late int atts;
    MyScheduleReads reads({Object Function()? rev, Future<void> Function()? hold}) {
      apps = 0;
      atts = 0;
      return MyScheduleReads(
        myApplications: (uid) async {
          apps++;
          await hold?.call();
          return const <ApplicationModel>[];
        },
        myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
          atts++;
          return const <AttendanceModel>[];
        },
        myAvailability: (uid) async => null,
        invitePreference: (uid) async => const InviteRegionPreference(),
        dataRevision: rev == null ? null : (_) => rev(),
      );
    }

    Future<void> pumpSchedule(WidgetTester t, MyScheduleReads r, {DateTime Function()? clock}) async {
      t.view.physicalSize = const Size(390, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      _visible.value = true;
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: _visible,
            builder: (_, v, child) => TickerMode(enabled: v, child: child!),
            child: MyScheduleScreen(reads: r, clock: clock),
          ),
        ),
      ));
      await _settle(t);
    }

    testWidgets('S1 신선하면 0 · 1분 뒤 재방문은 달력을 둔 채 표시월을 다시 읽는다', (t) async {
      var now = DateTime(2026, 11, 26, 10);
      Completer<void>? gate;
      final r = reads(hold: () => gate?.future ?? Future.value());
      await pumpSchedule(t, r, clock: () => now);
      expect((apps, atts), (1, 1));
      await _revisit(t);
      await _settle(t, 5);
      expect((apps, atts), (1, 1));
      now = now.add(const Duration(minutes: 2));
      gate = Completer<void>();
      await _revisit(t);
      await t.pump(const Duration(milliseconds: 100));
      expect(findVisibleText('일정을 불러오고 있어요'), findsNothing, reason: '화면 전체 로딩으로 바꾸지 않는다');
      gate.complete();
      await _settle(t, 5);
      expect((apps, atts), (2, 2));
    });

    testWidgets('S2 무효화 세대가 바뀌면(출퇴근·지원 뒤) 시간이 안 지나도 다시 읽는다', (t) async {
      var rev = 'a';
      final r = reads(rev: () => rev);
      await pumpSchedule(t, r);
      rev = 'b';
      await _revisit(t);
      await _settle(t, 5);
      expect((apps, atts), (2, 2));
    });

    testWidgets('S3 숨은 채 복귀는 0', (t) async {
      var now = DateTime(2026, 11, 26, 10);
      final r = reads();
      await pumpSchedule(t, r, clock: () => now);
      _visible.value = false;
      await t.pump();
      now = now.add(const Duration(minutes: 5));
      _backgroundAndResume(t);
      await _settle(t, 5);
      expect((apps, atts), (1, 1));
    });
  });
}
