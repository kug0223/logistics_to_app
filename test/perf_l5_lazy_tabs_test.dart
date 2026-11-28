// [판정289 C289-04 · L5] 근로자 루트 탭 지연 생성 · 날짜 목적지 소비 계약 시험 **초안**.
//
//   상태: 준비 초안(2026-11-26 prep_p1_l5.md §3) → impl_9(L5·L20 구현) 뒤 계약 시험. 기존 단언은 완화하지 않았다.
//   impl_9 에서 L20 묶음(동시 출발 · 같은 문서 1회 · 새로고침 달력 유지)과 문서 읽기 계수를 더했다.
//
//   계약(판정289 §5 · 인계289 §7):
//     · 방문 시 생성 — 첫 진입에 홈만 만든다(L5R-1). TickerMode 는 생성 방지가 아니다.
//     · 첫 postFrame 에 나머지 탭을 몰아 만들지 않는다(L5R-2). 유휴 미리 생성은 2단계·선택(L5R-8 skip).
//     · 한 번 방문한 탭은 State 를 유지한다(IndexedStack 상태 보존 · L5R-3) · 숨은 방문 탭 TickerMode off(DU581c).
//     · 첫 진입 callable 에서 방문하지 않은 탭의 조회가 빠진다(L5R-4).
//     · pendingJobDate · pendingScheduleDate · pendingScheduleMonth 를 **최초 방문/기방문** 모두 실제 목적지가 소비한다
//       (L5R-5/6/7 루트 · L5S-1~5 화면). 월/선택일/ALL · 기존 필터 보존 · 연속 최신 요청 · 1회 소비.
//
//   [발견 · INF→LOCAL 확인 대상] L5S-1: 일정 화면이 **첫 조회 중**에 다른 달 날짜를 받으면 `_loadApplications` 가 세대 검사에서
//     조용히 빠지고 `_isLoading` 이 true 로 남아 스피너에 갇힐 수 있다(my_schedule_screen.dart:288 반환 · :796 body).
//     지금은 일정 탭이 루트와 함께 미리 만들어져 드물지만, 지연 생성이면 '첫 방문 = 첫 조회 중 소비'가 기본 경로가 된다.
// ignore_for_file: depend_on_referenced_packages, avoid_print

import 'dart:async';
import 'dart:convert';

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
import 'package:ALfit/models/core/invite_region_preference.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_schedule_reads.dart';
import 'package:ALfit/screens/user/my_schedule_screen.dart';
import 'package:ALfit/screens/user/tabs/user_job_tab.dart';
import 'package:ALfit/screens/user/tabs/user_job_tab_reads.dart';
import 'package:ALfit/screens/user/tabs/user_my_tab.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/screens/user/user_root_screen.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/widgets/common/app_bottom_tab_bar.dart';
import 'package:ALfit/widgets/common/loading_widget.dart';

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

UserModel _worker() => UserModel(
      uid: 'w1', username: 'w1', name: '김근로', email: 'w1@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구'), accountStatus: 'active',
    );

class _User extends UserProvider {
  @override
  UserModel? get currentUser => _worker();
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
  @override
  bool get hasPendingContract => false;
}

// ── 루트 하네스(worker_home_startup_dedupe_test 와 같은 채널 대역) ─────────────────
const _callCh = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.';

class _Server {
  int delayMs = 200;
  final calls = <String, int>{};
  final args = <String, List<Map>>{};

  Future<ByteData?> handle(ByteData? data) async {
    final a = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
    final name = a['functionName'] as String;
    calls[name] = (calls[name] ?? 0) + 1;
    (args[name] ??= []).add((a['parameters'] as Map?) ?? const {});
    // [impl_15 의도적 갱신] 이 대역은 개별 endpoint 경로(진행 중 공유·횟수)를 잰다 — 묶음 함수는 '구서버(없음)'로 답해
    //   앱이 같은 호출 안에서 개별 호출로 폴백하게 한다(묶음 경로 자체는 perf_l9_bundle_test WHB-* 가 맡는다).
    if (name == 'callableGetWorkerHomeBundle') return const StandardMessageCodec().encodeMessage(<Object?>['NOT_FOUND', 'no bundle', {'code': 'not-found', 'message': 'no bundle'}]);
    await Future<void>.delayed(Duration(milliseconds: delayMs));
    return const StandardMessageCodec().encodeMessage(<Object?>[
      <String, Object?>{
        'applications': <Object?>[], 'items': <Object?>[], 'tos': <Object?>[], 'requests': <Object?>[],
        'proposals': <Object?>[], 'contracts': <Object?>[], 'hasMore': false,
      }
    ]);
  }

  int n(String name) => calls[name] ?? 0;

  /// [L20] Firestore 문서 읽기 요청 중 경로에 [part] 가 들어 있는 것의 수(메시지 바이트의 UTF-8 경로 문자열로 센다).
  final docReads = <String>[];
  int docReadsContaining(String part) => docReads.where((p) => p.contains(part)).length;
}

void _install(WidgetTester t, _Server s) {
  final m = t.binding.defaultBinaryMessenger;
  m.setMockMessageHandler(_callCh, s.handle);
  for (final api in ['documentReferenceGet', 'queryGet', 'aggregateQuery']) {
    m.setMockMessageHandler('$_fsBase$api', (data) async {
      if (api == 'documentReferenceGet' && data != null) {
        s.docReads.add(utf8.decode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), allowMalformed: true));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'mock', null]);
    });
  }
  addTearDown(() {
    m.setMockMessageHandler(_callCh, null);
    for (final api in ['documentReferenceGet', 'queryGet', 'aggregateQuery']) {
      m.setMockMessageHandler('$_fsBase$api', null);
    }
  });
}

Future<void> _pumpFor(WidgetTester t, int ms, {void Function(int ms)? each}) async {
  for (var e = 0; e < ms; e += 50) {
    await t.pump(const Duration(milliseconds: 50));
    each?.call(e + 50);
  }
}

Future<_Server> _mountRoot(WidgetTester t) async {
  final s = _Server();
  _install(t, s);
  t.view.physicalSize = const Size(390, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _User()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: const MaterialApp(home: UserRootScreen()),
  ));
  return s;
}

/// 루트에서 지금 만들어져 있는 탭 루트(홈 제외) 수.
int _builtNonHomeTabs() =>
    find.byType(UserJobTab, skipOffstage: false).evaluate().length +
    find.byType(MyScheduleScreen, skipOffstage: false).evaluate().length +
    find.byType(UserMyTab, skipOffstage: false).evaluate().length;

Future<void> _tapTab(WidgetTester t, String label) async {
  await t.tap(find.descendant(
      of: find.byType(AppBottomTabBar),
      matching: find.byWidgetPredicate((w) => w is Text && visibleText(w.data ?? w.textSpan?.toPlainText() ?? '') == label)));
}

UserTabScope _scope(WidgetTester t) => t.widget<UserTabScope>(find.byType(UserTabScope).first);

String _monthTitle(DateTime d) => '${d.year}년 ${d.month}월';

/// 다른 달이 확실한 날짜(오늘 + 45일).
DateTime _otherMonthDay() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(const Duration(days: 45));
}

// ── 화면 하네스(읽기 주입) ─────────────────────────────────────────────
class _Host extends StatefulWidget {
  const _Host({super.key, required this.child, this.initialJobDate, this.initialScheduleDate, this.initialScheduleMonth});
  final Widget child;
  final DateTime? initialJobDate;
  final DateTime? initialScheduleDate;
  final DateTime? initialScheduleMonth;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late DateTime? jobDate = widget.initialJobDate;
  late DateTime? scheduleDate = widget.initialScheduleDate;
  late DateTime? scheduleMonth = widget.initialScheduleMonth;
  int jobClears = 0;
  int scheduleClears = 0;
  int monthClears = 0;
  int rebuilds = 0;
  void sendSchedule(DateTime d) => setState(() => scheduleDate = d);
  void sendJob(DateTime d) => setState(() => jobDate = d);
  void plainRebuild() => setState(() => rebuilds++);
  @override
  Widget build(BuildContext context) => UserTabScope(
        switchToTab: (_) {},
        switchToTabWithDate: (_, __) {},
        pendingJobDate: jobDate,
        clearPendingJobDate: () {
          jobClears++;
          setState(() => jobDate = null);
        },
        pendingScheduleMonth: scheduleMonth,
        clearPendingScheduleMonth: () {
          monthClears++;
          setState(() => scheduleMonth = null);
        },
        switchToScheduleNow: () {},
        switchToScheduleDate: (_) {},
        pendingScheduleDate: scheduleDate,
        clearPendingScheduleDate: () {
          scheduleClears++;
          setState(() => scheduleDate = null);
        },
        child: widget.child,
      );
}

Future<GlobalKey<_HostState>> _mountScreen(WidgetTester t, Widget screen,
    {DateTime? jobDate, DateTime? scheduleDate, DateTime? scheduleMonth}) async {
  t.view.physicalSize = const Size(390, 2000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final key = GlobalKey<_HostState>();
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _User()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      home: _Host(
        key: key,
        initialJobDate: jobDate,
        initialScheduleDate: scheduleDate,
        initialScheduleMonth: scheduleMonth,
        child: screen,
      ),
    ),
  ));
  return key;
}

MyScheduleReads _scheduleReads(List<String> months, {int appsMs = 300, List<String>? appCalls}) => MyScheduleReads(
      myApplications: (_) async {
        appCalls?.add('apps');
        await Future<void>.delayed(Duration(milliseconds: appsMs));
        return const <ApplicationModel>[];
      },
      myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
        months.add('$year-$month');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return const <AttendanceModel>[];
      },
      myAvailability: (_) async => null,
      invitePreference: (_) async => const InviteRegionPreference(),
    );

UserJobTabReads _jobReads(List<String> paged) => UserJobTabReads(
      publishedTOsPaged: ({String? lastToId, filter}) async {
        paged.add('${lastToId ?? '-'}|${filter?.dateRange?.start.toIso8601String() ?? '-'}');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return {'items': const <TOModel>[], 'lastToId': null, 'hasMore': false};
      },
      myApplications: (_) async => const <ApplicationModel>[],
      tosByIds: (_) async => const <TOModel>[],
    );

/// 화면 전체 로딩 표지 — 일정은 `LoadingWidget`(my_schedule_screen.dart:796), 그 밖은 원형 진행 표시.
Finder _spinnerIn(Type screen) => find.descendant(
    of: find.byType(screen),
    matching: find.byWidgetPredicate((w) => w is LoadingWidget || w is CircularProgressIndicator));

String _chip(DateTime d) => '${d.month}/${d.day}~${d.month}/${d.day}';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({'tour_completed_user_home': true});
    FirestoreService().invalidateMyAttendanceCache('w1');
    FirestoreService().invalidateMyApplicationsCache('w1');
  });

  group('L5R 루트', () {
    testWidgets('L5R-1 첫 진입 3초 — 홈만 만든다(일자리·내 일정·내 정보 0 · 탭 Navigator 1)', (t) async {
      await _mountRoot(t);
      await _pumpFor(t, 3000);
      expect(find.byType(UserHomeScreen), findsOneWidget);
      expect(_builtNonHomeTabs(), 0, reason: '방문하지 않은 탭은 만들지 않는다');
      expect(
          find.descendant(of: find.byType(IndexedStack).first, matching: find.byType(Navigator, skipOffstage: false)),
          findsOneWidget);
      t.takeException();
    });

    testWidgets('L5R-2 첫 postFrame 몰아 생성 0 — 1초 안 추가 탭 0 · 한 표본에 1개 넘게 늘지 않는다', (t) async {
      await _mountRoot(t);
      final counts = <(int, int)>[(0, _builtNonHomeTabs())];
      await _pumpFor(t, 3000, each: (ms) => counts.add((ms, _builtNonHomeTabs())));
      print('[L5R-2] ${counts.where((c) => c.$2 > 0).take(5).toList()}');
      expect(counts.where((c) => c.$1 < 1000 && c.$2 > 0), isEmpty, reason: '첫 1초 안 미리 생성 0');
      for (var i = 1; i < counts.length; i++) {
        expect(counts[i].$2 - counts[i - 1].$2, lessThanOrEqualTo(1), reason: '한 번에 하나씩 — ${counts[i]}');
      }
      t.takeException();
    });

    testWidgets('L5R-3 방문 생성 · 재방문 State 유지 · 숨은 방문 탭 TickerMode off', (t) async {
      await _mountRoot(t);
      await _pumpFor(t, 1500);
      await _tapTab(t, '일자리');
      await _pumpFor(t, 800);
      expect(find.byType(UserJobTab), findsOneWidget, reason: '눌렀을 때 만든다');
      final s1 = t.state(find.byType(UserJobTab));
      await _tapTab(t, '홈');
      await _pumpFor(t, 300);
      // 탭 자리 = IndexedStack 의 직접 자식 TickerMode(가까운 조상은 Navigator Overlay 의 TickerMode 라 쓰지 않는다)
      final stack = t.widget<IndexedStack>(find.byType(IndexedStack).first);
      final hiddenJobTicker = stack.children[1] as TickerMode;
      expect(hiddenJobTicker.enabled, isFalse, reason: 'DU581c — 숨은 탭 애니메이션·서명 안내 hold');
      await _tapTab(t, '일자리');
      await _pumpFor(t, 300);
      expect(identical(t.state(find.byType(UserJobTab)), s1), isTrue, reason: '한 번 만든 탭은 다시 만들지 않는다');
      expect(find.byType(MyScheduleScreen, skipOffstage: false), findsNothing, reason: '방문 안 한 일정 탭은 여전히 0');
      t.takeException();
    });

    testWidgets('L5R-4 첫 진입 callable — 방문 안 한 일자리 탭 페이지 조회 0 · 이번 달 근태 1회', (t) async {
      final s = await _mountRoot(t);
      await _pumpFor(t, 3000);
      print('[L5R-4] ${s.calls}');
      expect(s.n('callableGetPublishedTOsPaged'), 0, reason: '일자리 탭은 방문 때 읽는다');
      final kst = DateTime.now().toUtc().add(const Duration(hours: 9));
      final months = (s.args['getMyMonthlyAttendances'] ?? const []).map((p) => '${p['year']}-${p['month']}').toList();
      expect(months.where((m) => m == '${kst.year}-${kst.month}').length, 1);
      t.takeException();
    });

    testWidgets('L5R-5 홈 선택일 → 일정 탭 첫 방문(다른 달) — 그 달 · 스피너 갇힘 0 · 1회 소비', (t) async {
      final s = await _mountRoot(t);
      await _pumpFor(t, 1500);
      final d = _otherMonthDay();
      _scope(t).switchToScheduleDate!(d);
      await _pumpFor(t, 2500);
      expect(find.byType(MyScheduleScreen), findsOneWidget, reason: '탭 전환 + 첫 생성');
      expect(findVisibleText(_monthTitle(d)), findsWidgets, reason: '받은 날짜의 달');
      expect(_spinnerIn(MyScheduleScreen), findsNothing, reason: '첫 조회 중 소비가 화면을 로딩에 가두지 않는다');
      expect(_scope(t).pendingScheduleDate, isNull, reason: '소비 뒤 root 보관값 비움');
      final months = (s.args['getMyMonthlyAttendances'] ?? const []).map((p) => '${p['year']}-${p['month']}').toList();
      expect(months, contains('${d.year}-${d.month}'));
      t.takeException();
    });

    testWidgets('L5R-6 홈 날짜 → 일자리 탭 첫 방문 — 그날 하루 필터 · 1회 소비 · 페이지 조회 1', (t) async {
      final s = await _mountRoot(t);
      await _pumpFor(t, 1500);
      final n = DateTime.now();
      final d = DateTime(n.year, n.month, n.day).add(const Duration(days: 2));
      _scope(t).switchToTabWithDate(1, d);
      await _pumpFor(t, 2000);
      expect(find.byType(UserJobTab), findsOneWidget);
      expect(findVisibleText(_chip(d)), findsOneWidget, reason: '날짜 칩 = 받은 하루');
      expect(_scope(t).pendingJobDate, isNull);
      expect(s.n('callableGetPublishedTOsPaged'), 1, reason: '첫 방문 + 날짜 적용이 두 번 읽지 않는다');
      t.takeException();
    });

    testWidgets('L5R-7 근무 기록 보기(현재 달) → 일정 탭 첫 방문 — 이번 달 · 소비', (t) async {
      await _mountRoot(t);
      await _pumpFor(t, 1500);
      _scope(t).switchToScheduleNow();
      await _pumpFor(t, 2000);
      expect(find.byType(MyScheduleScreen), findsOneWidget);
      expect(findVisibleText(_monthTitle(DateTime.now())), findsWidgets);
      expect(_scope(t).pendingScheduleMonth, isNull);
      expect(_spinnerIn(MyScheduleScreen), findsNothing);
      t.takeException();
    });

    testWidgets('L5R-8 [2단계 · 선택] 홈 안정 뒤 유휴 미리 생성 — 하나씩 · 탭 입력 시 남은 예약 취소', (t) async {
      await _mountRoot(t);
      final counts = <(int, int)>[];
      await _pumpFor(t, 6000, each: (ms) => counts.add((ms, _builtNonHomeTabs())));
      for (var i = 1; i < counts.length; i++) {
        expect(counts[i].$2 - counts[i - 1].$2, lessThanOrEqualTo(1));
      }
      t.takeException();
    }, skip: true); // 미리 생성을 채택할 때만 기대(대상 탭·간격)를 고정하고 켠다 — 노트 §2.3
  });

  group('L5S 화면(읽기 주입) — 최초/기방문 소비', () {
    testWidgets('L5S-1 일정 화면 첫 생성에 다른 달 날짜(첫 조회 300ms 중) — 스피너 갇힘 0 · 그 달 · ALL · 1회 소비', (t) async {
      final months = <String>[];
      final appCalls = <String>[];
      final d = _otherMonthDay();
      final host = await _mountScreen(t, MyScheduleScreen(reads: _scheduleReads(months, appCalls: appCalls)), scheduleDate: d);
      await _pumpFor(t, 2500);
      print('[L5S-1] months=$months apps=${appCalls.length} clears=${host.currentState!.scheduleClears}');
      expect(_spinnerIn(MyScheduleScreen), findsNothing, reason: 'my_schedule_screen.dart:288 세대 반환 뒤 _isLoading 이 남지 않는다');
      expect(findVisibleText(_monthTitle(d)), findsWidgets);
      expect(months, contains('${d.year}-${d.month}'));
      expect(host.currentState!.scheduleClears, 1);
      expect(appCalls.length, lessThanOrEqualTo(2), reason: '첫 생성 소비가 조회를 불필요하게 늘리지 않는다(목표 1)');
      t.takeException();
    });

    testWidgets('L5S-2 일정 화면 첫 생성에 같은 달 날짜 — 스피너 갇힘 0 · 1회 소비', (t) async {
      final months = <String>[];
      final n = DateTime.now();
      final host = await _mountScreen(t, MyScheduleScreen(reads: _scheduleReads(months)),
          scheduleDate: DateTime(n.year, n.month, n.day));
      await _pumpFor(t, 2500);
      expect(_spinnerIn(MyScheduleScreen), findsNothing);
      expect(findVisibleText(_monthTitle(n)), findsWidgets);
      expect(host.currentState!.scheduleClears, 1);
      t.takeException();
    });

    testWidgets('L5S-3 일자리 탭 첫 생성에 날짜 — 첫 프레임부터 날짜 칩 · 조회 1 · 1회 소비', (t) async {
      final paged = <String>[];
      final n = DateTime.now();
      final d = DateTime(n.year, n.month, n.day).add(const Duration(days: 2));
      final host = await _mountScreen(t, UserJobTab(reads: _jobReads(paged)), jobDate: d);
      // 첫 프레임 사실은 적어 두고 끝에 판정한다(아래 소비 검사가 묻히지 않게).
      final firstFrameChip = findVisibleText(_chip(d)).evaluate().length == 1;
      await _pumpFor(t, 1500);
      expect(findVisibleText(_chip(d)), findsOneWidget);
      expect(paged.length, 1, reason: '$paged');
      expect(host.currentState!.jobClears, 1);
      t.takeException();
      expect(firstFrameChip, isTrue, reason: '첫 방문 첫 프레임에 다른 목록(날짜 미적용)이 보이지 않는다');
    });

    testWidgets('L5S-4 이미 열린 일정 화면 — 같은 프레임 연속 요청 A→B 는 B 로 수렴 · 이후 일반 재빌드는 B 유지', (t) async {
      final months = <String>[];
      final host = await _mountScreen(t, MyScheduleScreen(reads: _scheduleReads(months, appsMs: 100)));
      await _pumpFor(t, 1500);
      final a = _otherMonthDay();
      final b = DateTime(a.year, a.month + 1, 10);
      host.currentState!.sendSchedule(a);
      host.currentState!.sendSchedule(b); // 같은 프레임 — 최신 요청이 이긴다
      await _pumpFor(t, 2000);
      expect(findVisibleText(_monthTitle(b)), findsWidgets, reason: '연속 최신 요청');
      expect(findVisibleText(_monthTitle(a)), findsNothing);
      host.currentState!.plainRebuild(); // 일반 탭 전환과 같은 재빌드 — pending 없음
      await _pumpFor(t, 500);
      expect(findVisibleText(_monthTitle(b)), findsWidgets, reason: '1회 소비 뒤 일반 전환은 사용자 상태를 바꾸지 않는다');
      t.takeException();
    });

    testWidgets('L5S-5 이미 열린 일자리 탭 — 날짜 필터 뒤 일반 재빌드는 필터 유지(286) · 새 날짜 요청은 교체', (t) async {
      final paged = <String>[];
      final n = DateTime.now();
      final d1 = DateTime(n.year, n.month, n.day).add(const Duration(days: 2));
      final d2 = d1.add(const Duration(days: 3));
      final host = await _mountScreen(t, UserJobTab(reads: _jobReads(paged)));
      await _pumpFor(t, 1200);
      host.currentState!.sendJob(d1);
      await _pumpFor(t, 800);
      expect(findVisibleText(_chip(d1)), findsOneWidget);
      host.currentState!.plainRebuild();
      await _pumpFor(t, 500);
      expect(findVisibleText(_chip(d1)), findsOneWidget, reason: '일반 탭 이동이 기존 날짜 필터를 지우지 않는다');
      host.currentState!.sendJob(d2);
      await _pumpFor(t, 800);
      expect(findVisibleText(_chip(d2)), findsOneWidget);
      expect(host.currentState!.jobClears, 2);
      t.takeException();
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // [impl_9 발견·수정] 세대를 올리고 새 조회를 시작하지 않는 경로 — 진행 중 조회의 로딩을 끌 주인이 없다
  // ═════════════════════════════════════════════════════════════════════
  testWidgets('L5S-6 월 조회 중 가능일 편집 → 편집 중 달 넘김 → 취소 — 그 달을 다시 읽고 "월 일정을 확인하고 있어요"에 갇히지 않는다', (t) async {
    final months = <String>[];
    var slow = false;
    final reads = MyScheduleReads(
      myApplications: (_) async => const <ApplicationModel>[],
      myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
        months.add('$year-$month');
        await Future<void>.delayed(Duration(milliseconds: slow ? 800 : 50));
        return const <AttendanceModel>[];
      },
      myAvailability: (_) async => null,
      invitePreference: (_) async => const InviteRegionPreference(),
    );
    await _mountScreen(t, MyScheduleScreen(reads: reads));
    await _pumpFor(t, 600);
    slow = true;
    await t.tap(find.byIcon(Icons.chevron_right).first); // 다음 달 — 느린 조회(800ms) 출발(진행 중)
    await _pumpFor(t, 350); // 달력 넘김 애니메이션이 끝날 때까지(조회는 아직 진행 중)
    await t.tap(find.text('가능일 설정'));
    await t.pump(const Duration(milliseconds: 100));
    expect(findVisibleText('근무 가능일 선택'), findsWidgets, reason: '전제: 편집 모드');
    await t.tap(find.byIcon(Icons.chevron_right).first); // 편집 중 달 넘김 — 세대만 오르고 새 조회 없음
    await _pumpFor(t, 1200); // 앞 조회가 stale 로 끝난다(그 달 조회 출발 뒤 ~450ms 안에 넘겼다)
    final now0 = DateTime.now();
    final t2 = DateTime(now0.year, now0.month + 2);
    expect(findVisibleText(_monthTitle(t2)), findsWidgets, reason: '전제: 편집 중 두 달 뒤로 넘어갔다');
    slow = false;
    await t.tap(findVisibleText('취소'));
    await _pumpFor(t, 800);
    final now = DateTime.now();
    final target = DateTime(now.year, now.month + 2);
    print('[L5S-6] months=$months');
    expect(months, contains('${target.year}-${target.month}'), reason: '편집을 끝내면 보고 있는 달을 읽는다');
    expect(findVisibleText('월 일정을 확인하고 있어요'), findsNothing, reason: '로딩 표지에 갇히지 않는다');
    t.takeException();
  });

  // ═════════════════════════════════════════════════════════════════════
  // [L20 · 분석2 §6 #6] 일정 탭 — 지원·근태 동시 출발(반영은 지원 먼저) · 같은 문서 1회 · 새로고침 달력 유지 + TTL 무효화
  // ═════════════════════════════════════════════════════════════════════
  group('L20 일정 탭', () {
    MyScheduleReads reads({
      required List<String> log,
      Completer<void>? appsGate,
      bool appsFail = false,
      bool attsFail = false,
      List<String>? invalidated,
    }) =>
        MyScheduleReads(
          myApplications: (_) async {
            log.add('apps.start');
            if (appsGate != null) await appsGate.future;
            await Future<void>.delayed(const Duration(milliseconds: 100));
            log.add('apps.end');
            if (appsFail) throw Exception('L20 지원 실패 fixture');
            return const <ApplicationModel>[];
          },
          myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
            log.add('atts.start');
            await Future<void>.delayed(const Duration(milliseconds: 50));
            log.add('atts.end');
            if (attsFail) throw Exception('L20 근태 실패 fixture');
            return const <AttendanceModel>[];
          },
          myAvailability: (_) async => null,
          invitePreference: (_) async => const InviteRegionPreference(),
          invalidateCaches: invalidated == null ? null : (uid) => invalidated.add(uid),
        );

    testWidgets('L20-1 지원 응답을 기다리는 동안 근태도 이미 출발 · 근태가 먼저 끝나도 반영은 지원 먼저 · 완결', (t) async {
      final log = <String>[];
      final gate = Completer<void>();
      await _mountScreen(t, MyScheduleScreen(reads: reads(log: log, appsGate: gate)));
      await _pumpFor(t, 300);
      expect(log, containsAll(['apps.start', 'atts.start', 'atts.end']), reason: '지원이 붙잡힌 동안 근태는 출발·완료($log)');
      expect(log.contains('apps.end'), isFalse);
      expect(_spinnerIn(MyScheduleScreen), findsOneWidget, reason: '지원 전에는 첫 로딩 그대로');
      gate.complete();
      await _pumpFor(t, 800);
      print('[L20-1] $log');
      expect(_spinnerIn(MyScheduleScreen), findsNothing);
      expect(findVisibleText(_monthTitle(DateTime.now())), findsWidgets);
      expect(findVisibleText('출근 기록을 불러오지 못했어요'), findsNothing, reason: '먼저 끝난 근태 응답을 버리지 않는다');
      expect(log.where((e) => e == 'atts.start').length, 1, reason: '근태는 한 번');
      t.takeException();
    });

    testWidgets('L20-2 근태만 실패 → 근태 실패 안내(달력 유지) · 지원 실패 → 일정 실패 안내(근태 결과 버림)', (t) async {
      final log = <String>[];
      await _mountScreen(t, MyScheduleScreen(reads: reads(log: log, attsFail: true)));
      await _pumpFor(t, 800);
      expect(findVisibleText('출근 기록을 불러오지 못했어요'), findsOneWidget);
      expect(findVisibleText(_monthTitle(DateTime.now())), findsWidgets);
      final log2 = <String>[];
      await _mountScreen(t, MyScheduleScreen(reads: reads(log: log2, appsFail: true)));
      await _pumpFor(t, 800);
      expect(findVisibleText('일정을 불러오지 못했어요'), findsOneWidget);
      expect(findVisibleText('출근 기록을 불러오지 못했어요'), findsNothing);
      t.takeException();
    });

    testWidgets('L20-3 당겨서 새로고침 — 달력 유지(전체 로딩 표지 0) · 이 사용자 TTL 캐시 무효화 1 · 표시월 재조회', (t) async {
      final log = <String>[];
      final invalidated = <String>[];
      await _mountScreen(t, MyScheduleScreen(reads: reads(log: log, invalidated: invalidated)));
      await _pumpFor(t, 800);
      final apps0 = log.where((e) => e == 'apps.start').length;
      // 당겨서 새로고침과 같은 경로(RefreshIndicator.onRefresh) — 제스처 대신 공개 API show() 로 결정적으로 연다.
      unawaited(t.state<RefreshIndicatorState>(find.byType(RefreshIndicator).first).show());
      var calendarHeld = true;
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 50));
        // 화면 전체 로딩 표지(LoadingWidget)만 본다 — 당겨서 새로고침 자신의 원형 표시는 정상이다.
        if (find.descendant(of: find.byType(MyScheduleScreen), matching: find.byType(LoadingWidget)).evaluate().isNotEmpty ||
            findVisibleText(_monthTitle(DateTime.now())).evaluate().isEmpty) {
          calendarHeld = false;
        }
      }
      await _pumpFor(t, 600);
      print('[L20-3] invalidated=$invalidated log=$log');
      expect(invalidated, ['w1']);
      expect(log.where((e) => e == 'apps.start').length, apps0 + 1, reason: '새로고침이 실제로 다시 읽었다');
      expect(calendarHeld, isTrue, reason: '새로고침 동안 달력이 사라지지 않는다');
      t.takeException();
    });

    testWidgets('L20-4 루트 — 일정 탭 첫 방문에 worker_availability 문서 읽기 1회(가능일·초대 지역 공유)', (t) async {
      final s = await _mountRoot(t);
      await _pumpFor(t, 1200);
      final before = s.docReadsContaining('worker_availability');
      await _tapTab(t, '내 일정');
      await _pumpFor(t, 2000);
      print('[L20-4] worker_availability reads ${s.docReadsContaining('worker_availability') - before} (전체 문서 읽기 ${s.docReads.length})');
      expect(s.docReadsContaining('worker_availability') - before, 1);
      t.takeException();
    });
  });
}
