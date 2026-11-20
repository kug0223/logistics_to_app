// ignore_for_file: depend_on_referenced_packages
// [DU1 후속72 §2] S073 정상 일정 기본 시각 — 실패/재시도 사건이 아닌 **정상 출발**.
//   출발: production MyScheduleScreen(reads: LOCAL MyScheduleReads) 단독 화면 · USER · workerTheme · W360×780@1.0 · DPR1 · inset0 · prefs {}.
//     UserRoot 자연 진입이 아니다. 시계 미주입(DateTime.now) — 실제 KST 날짜를 기록한다.
//   fixture: 감사69 수용 fixture 재사용 — Q=KST 오늘+1 확정 단기 1건(긴 사업장·상하차 09:00~13:00·시급 12,000), U=+2 근무 0,
//     가능일 {Q,U}·초대 지역 ON(서울특별시 송파구)·월 근태 empty. read 4종 모두 즉시 정상. 쓰기 채널 차단·계수 0.
//   장면: ① 첫 화면(초기 선택일=오늘) ② Q 실제 탭 뒤 첫 화면 ③ 실제 drag 로 Q 카드까지.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// [DU212 S073-D212] 이번 진단 전용 import — 기존 S073-N 시험은 쓰지 않는다.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_localizations/flutter_localizations.dart';
// [DU213 S073-D213] 이번 교정 검증 전용 import — 기존 S073-N·D212 블록은 쓰지 않는다.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:ALfit/utils/text_layout.dart';

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
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/calendar/schedule_calendar.dart';
import 'package:ALfit/widgets/calendar/schedule_card.dart';

import 'support/du1_vq_capture.dart';

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

const kUid = 'worker-local-c67';
const kBizName = 'QA 송파 물류센터 제2캠퍼스 상하차동';

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: kUid, username: 'worker', name: 'QA 근로자', email: 'w@test.local', role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '송파구'), accountStatus: 'active',
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

void main() {
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  const fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  final kNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  DateTime kstMidnight(int plus) => DateTime.utc(kNow.year, kNow.month, kNow.day + plus).subtract(const Duration(hours: 9));
  final qDate = kstMidnight(1);
  final uDate = kstMidnight(2);
  final qKey = WorkerAvailabilityModel.dateKeyFrom(qDate);
  final uKey = WorkerAvailabilityModel.dateKeyFrom(uDate);
  final kQ = qDate.toUtc().add(const Duration(hours: 9));
  final kU = uDate.toUtc().add(const Duration(hours: 9));
  final appQ = ApplicationModel(
    id: 'app-c67-q', toId: 'to-c67-q', slotId: 'slot-c67-q', workDetailId: 'wd-c67-q', uid: kUid, applicantName: 'QA 근로자',
    businessId: 'biz-c67', businessName: kBizName, toTitle: 'QA 상하차 단기', status: AppStatus.confirmed,
    selectedWorkType: '상하차', startTime: '09:00', endTime: '13:00', wage: 12000, wageType: 'hourly',
    workDate: qDate, appliedAt: qDate.subtract(const Duration(days: 3)),
  );
  final calls = <String, int>{};
  void inc(String k) => calls[k] = (calls[k] ?? 0) + 1;
  MyScheduleReads reads() => MyScheduleReads(
        myApplications: (uid) async {
          inc('myApplications');
          return [appQ];
        },
        myMonthlyAttendances: ({required String userId, required int year, required int month}) async {
          inc('myMonthlyAttendances');
          return const <AttendanceModel>[];
        },
        myAvailability: (uid) async {
          inc('myAvailability');
          return WorkerAvailabilityModel(uid: uid, dates: [qKey, uKey], city: '송파구');
        },
        invitePreference: (uid) async {
          inc('invitePreference');
          return const InviteRegionPreference(enabled: true, regions: [UserRegion(province: '서울특별시', city: '송파구')]);
        },
      );

  testWidgets('S073-N 정상 일정 360×780@1.0 — 첫 화면 · Q 탭 · Q 카드(실제 drag)', (t) async {
    await t.runAsync(vqLoadFonts);
    calls.clear();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMessageHandler(fnChannel, (msg) async {
      inc('BLOCKED functions');
      return const StandardMessageCodec().encodeMessage(<Object?>['not-found', 'blocked', <String, Object?>{'code': 'not-found'}]);
    });
    for (final op in const ['documentReferenceGet', 'queryGet', 'documentReferenceSet', 'documentReferenceUpdate',
      'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$fsBase.$op', (msg) async {
        inc('BLOCKED firestore $op');
        return null;
      });
    }
    final overflows = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = d.exceptionAsString();
      if (s.contains('overflowed')) {
        overflows.add(s.split('\n').first);
      } else {
        prev?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prev);
    t.view.physicalSize = const Size(360, 780);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    expect(kQ.month == kNow.month && kU.month == kNow.month, isTrue, reason: 'Q/U 같은 표시 월');
    final key = GlobalKey();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: RoleTheme.workerTheme,
          builder: (ctx, child) =>
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
          home: MyScheduleScreen(reads: reads()),
        ),
      ),
    ));
    Future<void> frames([int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await frames(12);
    final screen = find.byType(MyScheduleScreen);
    final cal = find.byType(ScheduleCalendar);
    final card = find.byType(ScheduleCard);
    Finder scroll() => find
        .descendant(of: find.descendant(of: screen, matching: find.byType(CustomScrollView)), matching: find.byType(Scrollable))
        .first;
    double offset() => t.state<ScrollableState>(scroll()).position.pixels;
    Map<String, Object?> cond(String scene) => {
          'entry': 'LOCAL MaterialApp(home: MyScheduleScreen(reads: LOCAL MyScheduleReads)) 단독 · USER · UserRoot 미사용',
          'theme': 'RoleTheme.workerTheme', 'viewport': '360x780', 'dpr': 1.0, 'textScaler': 1.0, 'inset': 0,
          'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) — 기기 글꼴 아님', 'prefs': '{}',
          'clock': '미주입 — 실행 KST ${kNow.toIso8601String().substring(0, 16)}',
          'fixture': 'Q=$qKey 확정 단기 상하차 09:00~13:00 "$kBizName" 시급 12,000 · U=$uKey 근무 0 · 가능일 {$qKey,$uKey} · 초대 ON 송파구 · 월근태 []',
          'scene': scene, 'offset': offset().toStringAsFixed(1), 'calls': calls.toString(), 'overflows': overflows.length};

    // ① 첫 화면
    expect(calls, {'myApplications': 1, 'myMonthlyAttendances': 1, 'myAvailability': 1, 'invitePreference': 1});
    await vqCapture(t, key, 'S073-N_1_first', conditions: cond('첫 화면 · 초기 선택일 KST 오늘'));
    // ② Q 실제 탭
    final qCell = find.descendant(of: cal, matching: find.text('${kQ.day}')).first;
    await t.tapAt(t.getRect(qCell).center);
    await frames(6);
    await vqCapture(t, key, 'S073-N_2_q_tapped', conditions: cond('Q 탭 뒤 · Q 셀 ${t.getRect(qCell)}'));
    // ③ 실제 drag(달력 밖 왼쪽 여백)로 Q 카드까지
    final vp = t.getRect(scroll());
    for (var k = 0; k < 40; k++) {
      if (card.evaluate().isNotEmpty) {
        final r = t.getRect(card.first);
        if (r.bottom <= vp.bottom - 8) break;
      }
      final pos = t.state<ScrollableState>(scroll()).position;
      if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
      await t.dragFrom(Offset(vp.left + 8, vp.bottom - 30), const Offset(0, -60));
      await frames(2);
    }
    await frames(4);
    expect(card, findsWidgets, reason: 'Q 카드');
    await vqCapture(t, key, 'S073-N_3_q_card', conditions: cond('drag 뒤 Q 카드 ${t.getRect(card.first)} vp=$vp'));
    expect(overflows, isEmpty);
    expect(calls.keys.where((k) => k.startsWith('BLOCKED')), isEmpty, reason: '쓰기·원격 채널 0');
    expect(t.takeException(), isNull);
  });

  // [DU212 S073-D212] 조회 진실성 비시각 진단 — 감사211·후속212. 제품 무수정.
  //   결함을 확인하려는 expect 는 두지 않는다. 라벨·값·호출을 D212OBS 줄로 기록하고,
  //   expect 는 준비 guard·fake 계약·기준값·예산·채널에만 쓴다.
  testWidgets('S073-D212 조회 진실성 진단', (t) async {
    await _d212Run(t);
  });

  // [DU213 S073-D213] 월 조회 미완결 표시 교정·C19 보충 — 감사212·후속213.
  //   env D213_MODE=before|after. 같은 하네스·fixture·조작이며 after 단언만 모드로 나눈다.
  testWidgets('S073-D213 월 조회 미완결 교정·C19 보충', (t) async {
    await _d213Run(t);
  });
}

// ═══════════════════════════════════════════════════════════════════
// [DU212 S073-D212] 이번 진단 전용 fake·진단 함수 — 기존 S073-N 블록과 분리한다.
//   fake 는 uid·year·month 를 호출 번호별 기대와 먼저 대조하고(실패 지정 호출 포함),
//   어긋나면 violations 에 남긴다. 성공·실패·보류(Completer)는 호출 번호로 정한다.
// ═══════════════════════════════════════════════════════════════════

class _D212Srv {
  _D212Srv({
    required this.apps,
    required this.expectAttMonths,
    this.appsFailOn = const {},
    this.attFailOn = const {},
    this.attHold = const {},
  });

  final List<ApplicationModel> apps;
  final Map<int, List<int>> expectAttMonths;
  final Set<int> appsFailOn;
  final Set<int> attFailOn;
  final Map<int, Completer<List<AttendanceModel>>> attHold;
  final List<Map<String, Object?>> log = [];
  final List<String> violations = [];
  final Map<String, int> calls = {};

  int _n(String k) => calls[k] = (calls[k] ?? 0) + 1;

  void _check(bool ok, String why, Map<String, Object?> e) {
    if (!ok) {
      violations.add(why);
      e['violation'] = why;
    }
  }

  void _p(Map<String, Object?> e) => print('D212SRV ${jsonEncode(e)}');

  MyScheduleReads reads() => MyScheduleReads(
        myApplications: (uid) async {
          final n = _n('myApplications');
          final e = <String, Object?>{'read': 'myApplications', 'n': n, 'uid': uid};
          log.add(e);
          _check(uid == kUid, 'apps-uid', e);
          if (appsFailOn.contains(n)) {
            e['result'] = 'throw';
            _p(e);
            throw Exception('d212-apps-network');
          }
          e['result'] = 'ok';
          e['ids'] = apps.map((a) => a.id).toList();
          _p(e);
          return apps;
        },
        myMonthlyAttendances: (
            {required String userId, required int year, required int month}) async {
          final n = _n('myMonthlyAttendances');
          final e = <String, Object?>{
            'read': 'myMonthlyAttendances',
            'n': n,
            'uid': userId,
            'year': year,
            'month': month,
          };
          log.add(e);
          _check(userId == kUid, 'att-uid', e);
          final want = expectAttMonths[n];
          _check(want != null && want[0] == year && want[1] == month,
              'att-month-n$n', e);
          final h = attHold[n];
          if (h != null) {
            e['held'] = true;
            _p(e);
            try {
              final r = await h.future;
              e['result'] = 'ok-after-hold';
              e['count'] = r.length;
              _p(e);
              return r;
            } catch (_) {
              e['result'] = 'throw-after-hold';
              _p(e);
              rethrow;
            }
          }
          if (attFailOn.contains(n)) {
            e['result'] = 'throw';
            _p(e);
            throw Exception('d212-att-network');
          }
          e['result'] = 'ok';
          e['count'] = 0;
          _p(e);
          return const <AttendanceModel>[];
        },
        myAvailability: (uid) async {
          _n('myAvailability');
          return WorkerAvailabilityModel(uid: uid, dates: const [], city: '송파구');
        },
        invitePreference: (uid) async {
          _n('invitePreference');
          return const InviteRegionPreference(
              enabled: true,
              regions: [UserRegion(province: '서울특별시', city: '송파구')]);
        },
      );
}

Future<void> _d212Run(WidgetTester t) async {
  const fnChannel =
      'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  const fsBase =
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const fsOps = [
    'documentReferenceGet', 'queryGet', 'documentReferenceSet', 'documentReferenceUpdate',
    'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'aggregateQuery',
    'querySnapshot', 'documentReferenceSnapshot',
  ];
  final blocked = <String>[];
  final msgr = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  msgr.setMockMessageHandler(fnChannel, (msg) async {
    blocked.add('functions');
    return const StandardMessageCodec().encodeMessage(
        <Object?>['not-found', 'blocked', <String, Object?>{'code': 'not-found'}]);
  });
  for (final op in fsOps) {
    msgr.setMockMessageHandler('$fsBase.$op', (msg) async {
      blocked.add('firestore $op');
      return null;
    });
  }
  addTearDown(() {
    msgr.setMockMessageHandler(fnChannel, null);
    for (final op in fsOps) {
      msgr.setMockMessageHandler('$fsBase.$op', null);
    }
  });
  t.view.physicalSize = const Size(360, 780);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  // ── 예산(실측) ──
  var pumps = 0;
  var taps = 0;
  var drags = 0;
  void budget() {
    pumps++;
    expect(pumps, lessThanOrEqualTo(300), reason: 'D212 pump 예산 300 초과');
  }

  Future<void> frames(int n) async {
    for (var i = 0; i < n; i++) {
      budget();
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  // ── 날짜: 실행일 KST D0, M0=그 달, M1=다음 달 ──
  final kNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  final d0 = DateTime.utc(kNow.year, kNow.month, kNow.day);
  final m0 = DateTime.utc(d0.year, d0.month, 1);
  final m1 = DateTime.utc(d0.year, d0.month + 1, 1);
  final dP1 = DateTime.utc(d0.year, d0.month, d0.day + 1);
  final dP2 = DateTime.utc(d0.year, d0.month, d0.day + 2);
  final c15 = DateTime.utc(m1.year, m1.month, 15);
  DateTime kstMid(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).subtract(const Duration(hours: 9));
  String ymd(DateTime d) => '${d.year}-${d.month}-${d.day}';
  final local = DateTime.now();
  print('D212ENV ${jsonEncode({
        'utc': DateTime.now().toUtc().toIso8601String(),
        'tz': local.timeZoneName,
        'offsetMin': local.timeZoneOffset.inMinutes,
        'local': local.toIso8601String(),
        'd0': ymd(d0),
        'm0': '${m0.year}-${m0.month}',
        'm1': '${m1.year}-${m1.month}',
        'a': ymd(dP1),
        'b': ymd(dP2),
        'c': ymd(c15),
        'viewport': '360x780@1.0',
        'theme': 'RoleTheme.workerTheme',
        'locale': 'ko_KR(명시)',
      })}');
  expect(dP2.month == d0.month, isTrue, reason: 'D212 D0+2 가 M0 안이어야 한다');
  expect(local.year == d0.year && local.month == d0.month && local.day == d0.day,
      isTrue,
      reason: 'D212 기기 로컬 날짜가 KST D0 와 같아야 한다(달력 초기 월)');

  ApplicationModel app(String id, DateTime day, String s, String e, int wage) =>
      ApplicationModel(
        id: id, toId: 'to-$id', slotId: 'slot-$id', workDetailId: 'wd-$id', uid: kUid,
        applicantName: 'QA 근로자', businessId: 'biz-d212', businessName: 'D212 사업장 $id',
        toTitle: 'D212 $id', status: AppStatus.confirmed, selectedWorkType: '상하차',
        startTime: s, endTime: e, wage: wage, wageType: 'hourly',
        workDate: kstMid(day), appliedAt: kstMid(day).subtract(const Duration(days: 3)),
      );
  final aA = app('d212-a', dP1, '09:00', '13:00', 12000);
  final aB = app('d212-b', dP2, '09:00', '13:00', 15000);
  final aC = app('d212-c', c15, '09:00', '13:00', 10000);
  final aE = app('d212-e', d0, '20:00', '23:00', 12000);

  late _D212Srv srv;
  void guard(String step) {
    expect(t.takeException(), isNull, reason: 'D212 $step 예외·overflow');
    expect(srv.violations, isEmpty, reason: 'D212 $step fake 계약 위반');
    expect(blocked, isEmpty, reason: 'D212 $step 쓰기·원격 채널 0');
  }

  Future<void> mount(_D212Srv s) async {
    srv = s;
    budget();
    await t.pumpWidget(const SizedBox.shrink());
    await frames(1);
    budget();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        locale: const Locale('ko', 'KR'),
        supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: RoleTheme.workerTheme,
        builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)),
            child: child!),
        home: MyScheduleScreen(reads: s.reads()),
      ),
    ));
    await frames(12);
    expect(Localizations.localeOf(t.element(find.byType(MyScheduleScreen))),
        const Locale('ko', 'KR'),
        reason: 'D212 resolved locale');
    guard('mount');
  }

  bool vis(String s) => find.text(s).evaluate().isNotEmpty;
  List<String> texts(bool Function(String) f) => find
      .byWidgetPredicate((w) => w is Text && w.data != null && f(w.data!))
      .evaluate()
      .map((e) => (e.widget as Text).data!)
      .toList();

  Map<String, Object?> kpi(String label) {
    final lf = find.text(label);
    final n = lf.evaluate().length;
    if (n != 1) return {'label': label, 'found': n};
    final col = find.ancestor(of: lf, matching: find.byType(Column)).first;
    final ts = find
        .descendant(of: col, matching: find.byType(Text))
        .evaluate()
        .map((e) => e.widget as Text)
        .toList();
    final v = ts.length >= 2 ? ts[1] : null;
    return {
      'label': label,
      'value': v?.data,
      'color': v?.style?.color?.toARGB32().toRadixString(16),
    };
  }

  String? kpiValue(String label) => kpi(label)['value'] as String?;

  List<Map<String, Object?>> cards() => find
      .byType(ScheduleCard)
      .evaluate()
      .map((e) {
        final r = t.getRect(find.byElementPredicate((x) => identical(x, e)));
        return <String, Object?>{
          'id': (e.widget as ScheduleCard).application.id,
          'rect': [r.left, r.top, r.right, r.bottom],
          'inViewport': r.top >= 0 && r.bottom <= 780,
        };
      })
      .toList();

  void obs(String kase, String step) {
    print('D212OBS ${jsonEncode({
          'case': kase,
          'step': step,
          'utc': DateTime.now().toUtc().toIso8601String(),
          'pumps': pumps,
          'taps': taps,
          'drags': drags,
          'calls': Map<String, int>.from(srv.calls),
          'calendarTitle': texts((s) => s.contains('년 ') && s.endsWith('월')),
          'summaryHeader': texts((s) => s.endsWith('월 요약')),
          'kpi': [kpi('확정 근무'), kpi('실근무'), kpi('예상수입'), kpi('확정수입')],
          'errorBody': vis('일정을 불러오지 못했어요'),
          'retry': vis('다시 시도'),
          'toastAtt': vis('출근 기록을 불러오지 못했어요'),
          'toastApps': vis('일정을 불러오지 못했어요'),
          'progress': find.byType(CircularProgressIndicator).evaluate().length,
          'cards': cards(),
        })}');
  }

  // ── D212-1 월 이동 보류 / D212-2 같은 보류를 실패로 완료 ──
  final hold = Completer<List<AttendanceModel>>();
  await mount(_D212Srv(
    apps: [aA, aB, aC],
    expectAttMonths: {
      1: [m0.year, m0.month],
      2: [m1.year, m1.month],
    },
    attHold: {2: hold},
  ));
  expect(srv.calls,
      {'myApplications': 1, 'myMonthlyAttendances': 1, 'myAvailability': 1, 'invitePreference': 1},
      reason: 'D212-1 첫 조회 4종 각 1');
  expect(vis('${m0.year}년 ${m0.month}월'), isTrue, reason: 'D212-1 달력 M0');
  expect(vis('${m0.month}월 요약'), isTrue, reason: 'D212-1 요약 머리 M0');
  expect([kpiValue('확정 근무'), kpiValue('실근무'), kpiValue('예상수입'), kpiValue('확정수입')],
      ['2건', '0일', '108,000원', '0원'],
      reason: 'D212-1 M0 기준값(손 계산 독립 기대)');
  obs('D212-1', 'M0');
  final next = find.descendant(
      of: find.byType(ScheduleCalendar), matching: find.byIcon(Icons.chevron_right));
  expect(next, findsOneWidget, reason: 'D212-1 달력 다음 달 아이콘 1개');
  final nr = t.getRect(next);
  expect(nr.top >= 0 && nr.bottom <= 780 && nr.left >= 0 && nr.right <= 360, isTrue,
      reason: 'D212-1 다음 달 아이콘 화면 안');
  taps++;
  expect(taps, lessThanOrEqualTo(20));
  await t.tap(next);
  await frames(10);
  guard('D212-1 다음 달');
  expect(srv.calls['myApplications'], 2, reason: 'D212-1 월 이동 apps 재조회 1');
  expect(srv.calls['myMonthlyAttendances'], 2, reason: 'D212-1 월 이동 근태 조회 1');
  expect(srv.log.last['held'] == true || srv.log.any((e) => e['read'] == 'myMonthlyAttendances' && e['n'] == 2 && e['held'] == true),
      isTrue,
      reason: 'D212-1 M1 근태 응답 보류');
  expect(vis('${m1.year}년 ${m1.month}월'), isTrue, reason: 'D212-1 달력 M1');
  obs('D212-1', 'M1-held');

  hold.completeError(Exception('d212-att-network'));
  await frames(3);
  guard('D212-2 실패 완료');
  obs('D212-2', 'failed-toast');
  await frames(42);
  guard('D212-2 toast 뒤');
  obs('D212-2', 'after-toast');

  // ── D212-3 초기 월근태 실패 대 정상 [] ──
  await mount(_D212Srv(
    apps: [aA],
    expectAttMonths: {
      1: [m0.year, m0.month],
    },
    attFailOn: {1},
  ));
  expect(srv.calls['myMonthlyAttendances'], 1, reason: 'D212-3a 근태 1회');
  obs('D212-3', 'a-att-failed');
  await mount(_D212Srv(
    apps: [aA],
    expectAttMonths: {
      1: [m0.year, m0.month],
    },
  ));
  expect(srv.calls['myMonthlyAttendances'], 1, reason: 'D212-3b 근태 1회');
  obs('D212-3', 'b-att-empty');

  // ── D212-4 일정 첫 조회 실패 ──
  await mount(_D212Srv(
    apps: [aA],
    expectAttMonths: const {},
    appsFailOn: {1},
  ));
  expect(srv.calls['myApplications'], 1, reason: 'D212-4 apps 1회');
  expect(srv.calls['myMonthlyAttendances'] ?? 0, 0, reason: 'D212-4 근태 0회');
  obs('D212-4', 'apps-failed');
  await frames(42);
  guard('D212-4 toast 뒤');
  obs('D212-4', 'after-toast');

  // ── D212-5 선택일 일정 있음 → 실제 당김 → 같은 조건 apps 실패 ──
  await mount(_D212Srv(
    apps: [aE],
    expectAttMonths: {
      1: [m0.year, m0.month],
    },
    appsFailOn: {2},
  ));
  expect(srv.calls['myApplications'], 1, reason: 'D212-5 첫 apps 1회');
  expect(cards().map((c) => c['id']).toList(), ['d212-e'], reason: 'D212-5 D0 카드');
  obs('D212-5', 'before-pull');
  final sv = find.descendant(
      of: find.byType(MyScheduleScreen), matching: find.byType(CustomScrollView));
  expect(sv, findsOneWidget, reason: 'D212-5 목록 1개');
  final sc = t.state<ScrollableState>(
      find.descendant(of: sv, matching: find.byType(Scrollable)).first);
  expect(sc.position.pixels, 0.0, reason: 'D212-5 목록 맨 위');
  print('D212PULL ${jsonEncode({
        'listRect': () {
          final r = t.getRect(sv);
          return [r.left, r.top, r.right, r.bottom];
        }(),
        'pixels': sc.position.pixels,
        'gesture': 'fling(0,300) v1000 from CustomScrollView center',
      })}');
  drags++;
  expect(drags, lessThanOrEqualTo(8));
  await t.fling(sv, const Offset(0, 300), 1000);
  await frames(20);
  guard('D212-5 당김');
  expect(srv.calls['myApplications'], 2, reason: 'D212-5 새로고침 apps 1회 증가');
  expect(srv.log.where((e) => e['read'] == 'myApplications').last['result'], 'throw',
      reason: 'D212-5 새로고침 apps 실패 지정');
  obs('D212-5', 'refresh-failed');
  await frames(42);
  guard('D212-5 toast 뒤');
  obs('D212-5', 'after-toast');

  final endNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  expect(DateTime.utc(endNow.year, endNow.month, endNow.day), d0,
      reason: 'D212 자정 경계를 넘었다');
  print('D212END ${jsonEncode({
        'pumps': pumps,
        'taps': taps,
        'drags': drags,
        'blocked': blocked.length,
        'utc': DateTime.now().toUtc().toIso8601String(),
      })}');
}

// ═══════════════════════════════════════════════════════════════════
// [DU213 S073-D213] 월 조회 미완결 표시 교정·C19 보충 전용 fake·진단 — 기존 S073-N·D212 와 분리.
//   fake 4종 모두 uid(근태는 year·month)를 호출 번호별 기대와 먼저 대조한다(실패·보류 포함).
//   호출 번호별 계획: List(성공) · 'fail' · Completer(보류).
// ═══════════════════════════════════════════════════════════════════

class _D213Srv {
  _D213Srv({required this.apps, required this.att, required this.attMonths});

  final Map<int, Object> apps;
  final Map<int, Object> att;
  final Map<int, List<int>> attMonths;
  final List<Map<String, Object?>> log = [];
  final List<String> violations = [];
  final Map<String, int> calls = {};

  int _n(String k) => calls[k] = (calls[k] ?? 0) + 1;
  void _v(String why, Map<String, Object?> e) {
    violations.add(why);
    e['violation'] = why;
  }

  void _p(Map<String, Object?> e) => print('D213SRV ${jsonEncode(e)}');

  Future<T> _serve<T>(Object? plan, Map<String, Object?> e, String failMsg) async {
    if (plan == null) {
      _v('no-plan', e);
      _p(e);
      throw StateError('d213 no plan');
    }
    if (plan == 'fail') {
      e['result'] = 'throw';
      _p(e);
      throw Exception(failMsg);
    }
    if (plan is Completer<T>) {
      e['held'] = true;
      _p(e);
      try {
        final r = await plan.future;
        e['result'] = 'ok-after-hold';
        _p(e);
        return r;
      } catch (_) {
        e['result'] = 'throw-after-hold';
        _p(e);
        rethrow;
      }
    }
    if (plan is T) {
      e['result'] = 'ok';
      _p(e);
      return plan as T;
    }
    _v('bad-plan', e);
    _p(e);
    throw StateError('d213 bad plan');
  }

  MyScheduleReads reads() => MyScheduleReads(
        myApplications: (uid) async {
          final n = _n('myApplications');
          final e = <String, Object?>{'read': 'myApplications', 'n': n, 'uid': uid};
          log.add(e);
          if (uid != kUid) _v('apps-uid', e);
          return _serve<List<ApplicationModel>>(apps[n], e, 'd213-apps-network');
        },
        myMonthlyAttendances: (
            {required String userId, required int year, required int month}) async {
          final n = _n('myMonthlyAttendances');
          final e = <String, Object?>{
            'read': 'myMonthlyAttendances', 'n': n, 'uid': userId, 'year': year, 'month': month,
          };
          log.add(e);
          if (userId != kUid) _v('att-uid', e);
          final want = attMonths[n];
          if (want == null || want[0] != year || want[1] != month) _v('att-month-n$n', e);
          return _serve<List<AttendanceModel>>(att[n], e, 'd213-att-network');
        },
        myAvailability: (uid) async {
          final n = _n('myAvailability');
          final e = <String, Object?>{'read': 'myAvailability', 'n': n, 'uid': uid};
          log.add(e);
          if (uid != kUid) _v('avail-uid', e);
          if (n != 1) _v('avail-n$n', e);
          e['result'] = 'ok';
          _p(e);
          return WorkerAvailabilityModel(uid: uid, dates: const [], city: '송파구');
        },
        invitePreference: (uid) async {
          final n = _n('invitePreference');
          final e = <String, Object?>{'read': 'invitePreference', 'n': n, 'uid': uid};
          log.add(e);
          if (uid != kUid) _v('invite-uid', e);
          if (n != 1) _v('invite-n$n', e);
          e['result'] = 'ok';
          _p(e);
          return const InviteRegionPreference(
              enabled: true, regions: [UserRegion(province: '서울특별시', city: '송파구')]);
        },
      );
}

Future<void> _d213Run(WidgetTester t) async {
  final mode = Platform.environment['D213_MODE'] ?? '';
  expect(mode == 'before' || mode == 'after', isTrue, reason: 'D213_MODE 는 before|after');
  final after = mode == 'after';
  final outRoot = Platform.environment['D213_OUT'] ?? '';
  expect(outRoot.isNotEmpty, isTrue, reason: 'D213_OUT');
  final outDir = Directory('$outRoot/$mode');
  await t.runAsync(vqLoadFonts);
  expect(t.takeException(), isNull, reason: 'D213 글꼴 등록');

  const fnChannel =
      'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  const fsBase =
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const fsOps = [
    'documentReferenceGet', 'queryGet', 'documentReferenceSet', 'documentReferenceUpdate',
    'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'aggregateQuery',
    'querySnapshot', 'documentReferenceSnapshot',
  ];
  final blocked = <String>[];
  final msgr = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  msgr.setMockMessageHandler(fnChannel, (msg) async {
    blocked.add('functions');
    return const StandardMessageCodec().encodeMessage(
        <Object?>['not-found', 'blocked', <String, Object?>{'code': 'not-found'}]);
  });
  for (final op in fsOps) {
    msgr.setMockMessageHandler('$fsBase.$op', (msg) async {
      blocked.add('firestore $op');
      return null;
    });
  }
  addTearDown(() {
    msgr.setMockMessageHandler(fnChannel, null);
    for (final op in fsOps) {
      msgr.setMockMessageHandler('$fsBase.$op', null);
    }
  });

  var vw = 360.0;
  var vh = 780.0;
  var scale = 1.0;
  void setView(double w, double h, double s) {
    t.view.physicalSize = Size(w, h);
    t.view.devicePixelRatio = 1.0;
    vw = w;
    vh = h;
    scale = s;
  }

  setView(360, 780, 1.0);
  addTearDown(t.view.reset);

  // ── 예산(실측) ──
  var pumps = 0;
  var taps = 0;
  var drags = 0;
  var pngs = 0;
  final steps = <String>[];
  void budget() {
    pumps++;
    expect(pumps, lessThanOrEqualTo(600), reason: 'D213 pump 예산 600 초과');
  }

  Future<void> frames(int n) async {
    for (var i = 0; i < n; i++) {
      budget();
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  // ── 날짜 ──
  final kNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  final d0 = DateTime.utc(kNow.year, kNow.month, kNow.day);
  DateTime dd(int plus) => DateTime.utc(d0.year, d0.month, d0.day + plus);
  final m0 = DateTime.utc(d0.year, d0.month, 1);
  final m1 = DateTime.utc(d0.year, d0.month + 1, 1);
  final m2 = DateTime.utc(d0.year, d0.month + 2, 1);
  final c15 = DateTime.utc(m1.year, m1.month, 15);
  DateTime kstAt(DateTime d, int h) =>
      DateTime.utc(d.year, d.month, d.day, h).subtract(const Duration(hours: 9));
  String ymd(DateTime d) => '${d.year}-${d.month}-${d.day}';
  final local = DateTime.now();
  print('D213ENV ${jsonEncode({
        'mode': mode,
        'utc': DateTime.now().toUtc().toIso8601String(),
        'tz': local.timeZoneName,
        'offsetMin': local.timeZoneOffset.inMinutes,
        'local': local.toIso8601String(),
        'd0': ymd(d0),
        'm0': '${m0.year}-${m0.month}',
        'm1': '${m1.year}-${m1.month}',
        'm2': '${m2.year}-${m2.month}',
        'out': outDir.path,
        'fonts': 'vqLoadFonts NotoSansKR·Roboto·MaterialIcons(SDK) — 기기 글꼴 아님',
      })}');
  expect(dd(-3).month == d0.month && dd(2).month == d0.month, isTrue,
      reason: 'D213 D0−3·D0+2 가 M0 안');
  expect(local.year == d0.year && local.month == d0.month && local.day == d0.day, isTrue,
      reason: 'D213 기기 로컬 날짜 = KST D0');

  ApplicationModel app(String id, DateTime day, String s, String e, int wage) =>
      ApplicationModel(
        id: id, toId: 'to-$id', slotId: 'slot-$id', workDetailId: 'wd-$id', uid: kUid,
        applicantName: 'QA 근로자', businessId: 'biz-d213', businessName: 'D213 사업장 $id',
        toTitle: 'D213 $id', status: AppStatus.confirmed, selectedWorkType: '상하차',
        startTime: s, endTime: e, wage: wage, wageType: 'hourly',
        workDate: kstAt(day, 0), appliedAt: kstAt(day, 0).subtract(const Duration(days: 3)),
      );
  final aA = app('d213-a', dd(1), '09:00', '13:00', 12000);
  final aB = app('d213-b', dd(2), '09:00', '13:00', 15000);
  final aC = app('d213-c', c15, '09:00', '13:00', 10000);
  final aE = app('d213-e', d0, '19:00', '23:00', 12000);
  final aX = app('d213-x', dd(-3), '09:00', '13:00', 12000);
  final aY = app('d213-y', dd(1), '09:00', '13:00', 10000);
  final attX = AttendanceModel(
    id: 'att-d213-x', applicationId: aX.id, userId: kUid, businessId: 'biz-d213',
    businessName: 'D213 사업장 d213-x', workDate: kstAt(dd(-3), 0), workType: '상하차',
    checkInAt: kstAt(dd(-3), 9), checkOutAt: kstAt(dd(-3), 13),
    status: AttendanceModel.statusPresent, createdAt: kstAt(dd(-3), 0),
    wageStatus: AttendanceModel.wageConfirmed, finalWage: 50000,
  );
  final abc = [aA, aB, aC];
  const exM0 = ['2건', '0일', '108,000원', '0원'];
  const exM1 = ['1건', '0일', '40,000원', '0원'];
  const exM2 = ['0건', '0일', '0원', '0원'];
  const exA = ['1건', '0일', '48,000원', '0원'];
  const exE = ['1건', '0일', '48,000원', '0원'];
  const exNone = ['0건', '0일', '0원', '0원'];
  const exXY = ['2건', '1일', '40,000원', '50,000원'];
  const wait4 = ['확인 중', '확인 중', '확인 중', '확인 중'];
  const fail4 = ['확인하지 못함', '확인하지 못함', '확인하지 못함', '확인하지 못함'];
  const tLoading = '월 일정을 확인하고 있어요';
  const tAttFail = '출근 기록을 불러오지 못했어요';
  const tAttSub = '월 요약을 확인할 수 없어요. 잠시 후 다시 시도해 주세요.';
  const tAppsFail = '일정을 불러오지 못했어요';
  const tAppsSub = '일정이 없다는 뜻은 아니에요. 잠시 후 다시 시도해 주세요.';

  final key = GlobalKey();
  late _D213Srv srv;
  void guard(String step) {
    expect(t.takeException(), isNull, reason: 'D213 $step 예외·overflow');
    expect(srv.violations, isEmpty, reason: 'D213 $step fake 계약 위반');
    expect(blocked, isEmpty, reason: 'D213 $step 쓰기·원격 채널 0');
  }

  Future<void> mount(_D213Srv s) async {
    srv = s;
    steps.clear();
    budget();
    await t.pumpWidget(const SizedBox.shrink());
    await frames(1);
    budget();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: RoleTheme.workerTheme,
          builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: MyScheduleScreen(reads: s.reads()),
        ),
      ),
    ));
    await frames(12);
    expect(Localizations.localeOf(t.element(find.byType(MyScheduleScreen))),
        const Locale('ko', 'KR'),
        reason: 'D213 resolved locale');
    guard('mount');
  }

  // ── 표시문자 정규화 finder(TextLayout.plain) ──
  bool isToast(Element e) {
    var hit = false;
    e.visitAncestorElements((a) {
      if (a.widget.runtimeType.toString() == '_ToastWidget') {
        hit = true;
        return false;
      }
      return true;
    });
    return hit;
  }

  List<Element> els(bool Function(String) f) => find
      .byWidgetPredicate((w) {
        if (w is! Text) return false;
        final d = w.data ?? w.textSpan?.toPlainText();
        return d != null && f(TextLayout.plain(d));
      })
      .evaluate()
      .toList();
  List<Element> body(String s) => els((x) => x == s).where((e) => !isToast(e)).toList();
  bool hasBody(String s) => body(s).isNotEmpty;
  bool hasToast(String s) => els((x) => x == s).any(isToast);
  Rect rectOf(Element e) => t.getRect(find.byElementPredicate((x) => identical(x, e)));
  bool inVp(Rect r) => r.top >= 0 && r.bottom <= vh && r.left >= 0 && r.right <= vw;
  Map<String, Object?> seen(String s) {
    final b = body(s);
    if (b.isEmpty) return {'text': s, 'tree': 0};
    final r = rectOf(b.first);
    return {'text': s, 'tree': b.length, 'rect': [r.left, r.top, r.right, r.bottom], 'inViewport': inVp(r)};
  }

  Finder retryBtn() => find.byElementPredicate((x) {
        if (x.widget is! ButtonStyleButton) return false;
        if (isToast(x)) return false;
        return find
            .descendant(
                of: find.byElementPredicate((y) => identical(y, x)),
                matching: find.byWidgetPredicate(
                    (w) => w is Text && TextLayout.plain(w.data ?? '') == '다시 시도'))
            .evaluate()
            .isNotEmpty;
      });

  String? kpiValue(String label) {
    final lf = body(label);
    if (lf.length != 1) return null;
    final col = find
        .ancestor(of: find.byElementPredicate((x) => identical(x, lf.first)), matching: find.byType(Column))
        .first;
    final ts = find
        .descendant(of: col, matching: find.byType(Text))
        .evaluate()
        .map((e) => e.widget as Text)
        .toList();
    if (ts.length < 2) return null;
    return TextLayout.plain(ts[1].data ?? '');
  }

  String? kpiColor(String label) {
    final lf = body(label);
    if (lf.length != 1) return null;
    final col = find
        .ancestor(of: find.byElementPredicate((x) => identical(x, lf.first)), matching: find.byType(Column))
        .first;
    final ts = find.descendant(of: col, matching: find.byType(Text)).evaluate().map((e) => e.widget as Text).toList();
    return ts.length < 2 ? null : ts[1].style?.color?.toARGB32().toRadixString(16);
  }

  const kLabels = ['확정 근무', '실근무', '예상수입', '확정수입'];
  List<String?> kpis() => kLabels.map(kpiValue).toList();

  Finder sv() => find.descendant(of: find.byType(MyScheduleScreen), matching: find.byType(CustomScrollView));
  double offset() {
    final f = find.descendant(of: sv(), matching: find.byType(Scrollable));
    return f.evaluate().isEmpty ? -1 : t.state<ScrollableState>(f.first).position.pixels;
  }

  List<Map<String, Object?>> cards() => find.byType(ScheduleCard).evaluate().map((e) {
        final r = rectOf(e);
        return <String, Object?>{
          'id': (e.widget as ScheduleCard).application.id,
          'rect': [r.left, r.top, r.right, r.bottom],
          'inViewport': inVp(r),
        };
      }).toList();

  List<double>? rectText(bool Function(String) f) {
    final b = els(f).where((e) => !isToast(e)).toList();
    if (b.length != 1) return null;
    final r = rectOf(b.first);
    return [r.left, r.top, r.right, r.bottom];
  }

  List<double>? rectFinder(Finder f) {
    if (f.evaluate().length != 1) return null;
    final r = t.getRect(f);
    return [r.left, r.top, r.right, r.bottom];
  }

  Map<String, Object?> state() {
    final rb = retryBtn();
    final rbr = rectFinder(rb);
    return {
      'calendarTitle': els((s) => s.contains('년 ') && s.endsWith('월')).map((e) => TextLayout.plain((e.widget as Text).data ?? '')).toList(),
      'summaryHeader': els((s) => s.endsWith('월 요약')).map((e) => TextLayout.plain((e.widget as Text).data ?? '')).toList(),
      'kpi': kpis(),
      'kpiColor': kLabels.map(kpiColor).toList(),
      'loading': seen(tLoading),
      'attFail': seen(tAttFail),
      'attSub': seen(tAttSub),
      'appsFail': seen(tAppsFail),
      'appsSub': seen(tAppsSub),
      'retry': seen('다시 시도'),
      'retryButton': rbr,
      'retryButtonH': rbr == null ? null : rbr[3] - rbr[1],
      'toastAtt': hasToast('출근 기록을 불러오지 못했어요'),
      'toastApps': hasToast('일정을 불러오지 못했어요'),
      'emptyDay': seen('${d0.month}월 ${d0.day}일 일정이 없어요'),
      'cards': cards(),
      'offset': offset(),
      'calls': Map<String, int>.from(srv.calls),
    };
  }

  void obs(String kase, String step) {
    print('D213OBS ${jsonEncode({
          'mode': mode, 'case': kase, 'step': step,
          'utc': DateTime.now().toUtc().toIso8601String(),
          'pumps': pumps, 'taps': taps, 'drags': drags, 'pngs': pngs,
          'steps': List<String>.from(steps),
          ...state(),
        })}');
  }

  Map<String, Object?> geometry(String id) => {
        'id': id, 'mode': mode, 'utc': DateTime.now().toUtc().toIso8601String(),
        'viewport': [vw, vh], 'dpr': 1.0, 'textScaler': scale, 'inset': 0,
        'theme': 'RoleTheme.workerTheme', 'locale': 'ko_KR(resolved)', 'fonts': 'vqLoadFonts',
        'd0': ymd(d0),
        'rects': {
          'calendar': rectFinder(find.byType(ScheduleCalendar)),
          'appBarTitle': rectText((s) => s == '내 일정'),
          'calendarTitle': rectText((s) => s.contains('년 ') && s.endsWith('월')),
          'legend': rectText((s) => s == '근무 가능일'),
          'banner': rectText((s) => s.startsWith('가능일을 등록하면')),
          'invite': rectText((s) => s == '초대 받을 지역'),
          'summaryHeader': rectText((s) => s.endsWith('월 요약')),
          'filterRow': () {
            final es = find
                .ancestor(
                    of: find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? '') == '전체'),
                    matching: find.byType(Row))
                .evaluate()
                .toList();
            if (es.isEmpty) return null;
            final r = rectOf(es.first);
            return [r.left, r.top, r.right, r.bottom];
          }(),
          'chipAll': rectText((s) => s == '전체'),
        },
        'steps': List<String>.from(steps),
        ...state(),
      };

  Future<void> capture(String id) async {
    await frames(8);
    guard('$id 캡처 전');
    expect(pngs, lessThan(12), reason: 'D213 PNG 예산 12');
    final meta = geometry(id);
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      outDir.createSync(recursive: true);
      final img = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final png = File('${outDir.path}/$id.png');
      if (png.existsSync()) throw StateError('D213 캡처를 덮지 않는다: ${png.path}');
      png.writeAsBytesSync(bytes!.buffer.asUint8List());
      final js = File('${outDir.path}/$id.json');
      if (js.existsSync()) throw StateError('D213 sidecar 를 덮지 않는다: ${js.path}');
      js.writeAsStringSync(jsonEncode(meta));
    });
    pngs++;
    guard('$id 캡처');
    expect(File('${outDir.path}/$id.png').existsSync(), isTrue, reason: 'D213 $id PNG');
  }

  Future<void> tapOn(Finder f, String what, {int wait = 10}) async {
    expect(f, findsOneWidget, reason: 'D213 $what 후보 1');
    final r = t.getRect(f);
    expect(inVp(r), isTrue, reason: 'D213 $what 화면 안 $r');
    taps++;
    expect(taps, lessThanOrEqualTo(30), reason: 'D213 tap 예산');
    steps.add(what);
    await t.tap(f);
    await frames(wait);
    guard(what);
  }

  Finder vsf() => find.descendant(
      of: sv(),
      matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down));
  Finder calF() => find.byType(ScheduleCalendar);
  List<String> hitPath(Offset p) =>
      t.hitTestOnBinding(p).path.map((e) => e.target.runtimeType.toString()).toList();
  List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom];
  bool inView(Offset p) => p.dx >= 0 && p.dx <= vw && p.dy >= 0 && p.dy <= vh;

  Future<void> dragUp(String what) async {
    expect(calF(), findsOneWidget, reason: 'D213 $what 달력 하나');
    final cr = t.getRect(calF());
    final u0 = Offset(8, vh - 40);
    print('D213PTR ${jsonEncode({
          'mode': mode, 'kind': 'up', 'step': what, 'start': [u0.dx, u0.dy],
          'calendarRect': lt(cr), 'viewport': [vw, vh], 'offset': offset(),
          'hitPath': hitPath(u0),
        })}');
    expect(!cr.contains(u0) && inView(u0), isTrue,
        reason: 'D213 $what 시작점 $u0 달력 $cr 밖·viewport 안');
    drags++;
    expect(drags, lessThanOrEqualTo(16), reason: 'D213 drag 예산');
    steps.add(what);
    await t.dragFrom(u0, const Offset(0, -600));
    await frames(4);
    guard(what);
  }

  Future<void> dragBack(String what) async {
    final sf = vsf();
    expect(sf, findsOneWidget, reason: 'D213 $what 세로 scrollable 하나');
    expect(calF(), findsOneWidget, reason: 'D213 $what 달력 하나');
    final pos0 = t.state<ScrollableState>(sf).position;
    final px = pos0.pixels;
    final sr = t.getRect(sf);
    final cr = t.getRect(calF());
    final p0 = Offset(sr.left + 8, (cr.bottom > sr.top ? cr.bottom : sr.top) + 8);
    final p1 = p0 + const Offset(0, 20);
    final p2 = p1 + Offset(0, px);
    print('D213PTR ${jsonEncode({
          'mode': mode, 'kind': 'back', 'step': what, 'pixels': px,
          'extentBefore': pos0.extentBefore,
          'points': [[p0.dx, p0.dy], [p1.dx, p1.dy], [p2.dx, p2.dy]],
          'calendarRect': lt(cr), 'scrollRect': lt(sr), 'viewport': [vw, vh],
          'hitPath': hitPath(p0),
        })}');
    expect(px > 0, isTrue, reason: 'D213 $what pixels>0 $px');
    expect(!cr.contains(p0), isTrue, reason: 'D213 $what 시작점 $p0 달력 $cr 밖');
    for (final p in [p0, p1, p2]) {
      expect(sr.contains(p) && inView(p), isTrue,
          reason: 'D213 $what 점 $p scrollRect $sr viewport 안');
    }
    final callsBefore = Map<String, int>.from(srv.calls);
    drags++;
    expect(drags, lessThanOrEqualTo(16), reason: 'D213 drag 예산');
    steps.add('$what(${px.toStringAsFixed(1)})');
    final g = await t.startGesture(p0);
    var upSent = false;
    try {
      await g.moveBy(const Offset(0, 20));
      await g.moveBy(Offset(0, px));
      upSent = true;
      await g.up();
    } finally {
      if (!upSent) {
        upSent = true;
        await g.up();
      }
    }
    await frames(4);
    final pos = t.state<ScrollableState>(sf).position;
    print('D213BACK ${jsonEncode({
          'mode': mode, 'step': what, 'pxBefore': px, 'offset': pos.pixels,
          'extentBefore': pos.extentBefore,
          'scrollRect': lt(sr),
          'points': [[p0.dx, p0.dy], [p1.dx, p1.dy], [p2.dx, p2.dy]],
          'callsBefore': callsBefore, 'callsAfter': Map<String, int>.from(srv.calls),
          'pumps': pumps, 'taps': taps, 'drags': drags, 'pngs': pngs,
        })}');
    expect(pos.pixels, 0.0, reason: 'D213 $what offset 0');
    expect(pos.extentBefore, 0.0, reason: 'D213 $what extentBefore 0');
    expect(srv.calls, callsBefore, reason: 'D213 $what 호출 불변');
    guard(what);
  }

  Finder nextMonth() => find.descendant(
      of: find.byType(ScheduleCalendar), matching: find.byIcon(Icons.chevron_right));
  void callsAre(String what, Map<String, int> want) =>
      expect(srv.calls, want, reason: 'D213 $what 호출 수');
  void a(bool cond, String why) {
    if (after) expect(cond, isTrue, reason: 'D213 after $why');
  }

  void aEq(Object? got, Object? want, String why) {
    if (after) expect(got, want, reason: 'D213 after $why');
  }

  // ════ P1 월 이동: 보류 → 실패 → toast 소멸 → (after) 다시 시도 ════
  final h1 = Completer<List<AttendanceModel>>();
  await mount(_D213Srv(
    apps: {1: abc, 2: abc, 3: abc},
    att: {1: <AttendanceModel>[], 2: h1, 3: <AttendanceModel>[]},
    attMonths: {1: [m0.year, m0.month], 2: [m1.year, m1.month], 3: [m1.year, m1.month]},
  ));
  callsAre('P1 mount', {'myApplications': 1, 'myMonthlyAttendances': 1, 'myAvailability': 1, 'invitePreference': 1});
  expect(kpis(), exM0, reason: 'D213 P1 M0 기준값(손 계산)');
  obs('P1', 'M0');
  await capture('N1');
  await tapOn(nextMonth(), 'P1 다음 달');
  expect(srv.calls['myApplications'], 2);
  expect(srv.calls['myMonthlyAttendances'], 2);
  expect(hasBody('${m1.year}년 ${m1.month}월'), isTrue, reason: 'D213 P1 달력 M1');
  obs('P1', 'M1-held');
  aEq(kpis(), wait4, 'P1 보류 4값 확인 중');
  a(hasBody(tLoading), 'P1 보류 안내');
  a(cards().isEmpty, 'P1 보류 카드 0');
  a(hasBody('${m1.month}월 요약'), 'P1 보류 머리 M1');
  await capture('P1-hold-top');
  h1.completeError(Exception('d213-att-network'));
  await frames(3);
  guard('P1 실패');
  obs('P1', 'failed-toast');
  await frames(41);
  guard('P1 toast 뒤');
  obs('P1', 'after-toast');
  aEq(kpis(), fail4, 'P1 실패 4값 확인하지 못함');
  a(hasBody(tAttFail) && hasBody(tAttSub) && hasBody('다시 시도'), 'P1 근태 실패 안내 지속');
  a(!hasToast('출근 기록을 불러오지 못했어요'), 'P1 toast 소멸');
  await capture('P1-fail-top');
  await dragUp('P1 아래로');
  obs('P1', 'fail-bottom');
  if (after) {
    final s = seen(tAttFail);
    a(s['inViewport'] == true, 'P1 안내 제목 화면 안');
    final rb = rectFinder(retryBtn());
    a(rb != null && rb[3] - rb[1] >= 48 && inVp(Rect.fromLTRB(rb[0], rb[1], rb[2], rb[3])), 'P1 retry 48·화면 안');
  }
  await capture('P1-fail-bottom');
  if (after) {
    await tapOn(retryBtn(), 'P1 다시 시도');
    callsAre('P1 재시도', {'myApplications': 3, 'myMonthlyAttendances': 3, 'myAvailability': 1, 'invitePreference': 1});
    obs('P1', 'retried');
    aEq(kpis(), exM1, 'P1 재시도 M1 값');
    a(!hasBody(tAttFail), 'P1 재시도 뒤 실패 안내 해제');
  }

  // ════ P2 (a) 초기 근태 실패 / (b) 정상 [] ════
  await mount(_D213Srv(
    apps: {1: [aA], 2: [aA]},
    att: {1: 'fail', 2: <AttendanceModel>[]},
    attMonths: {1: [m0.year, m0.month], 2: [m0.year, m0.month]},
  ));
  callsAre('P2a mount', {'myApplications': 1, 'myMonthlyAttendances': 1, 'myAvailability': 1, 'invitePreference': 1});
  obs('P2a', 'att-failed');
  aEq(kpis(), fail4, 'P2a 4값 확인하지 못함');
  a(hasBody(tAttFail) && hasBody(tAttSub) && hasBody('다시 시도'), 'P2a 안내');
  await capture('P2a-top');
  await dragUp('P2a 아래로');
  obs('P2a', 'bottom');
  await capture('P2a-bottom');
  if (after) {
    await tapOn(retryBtn(), 'P2a 다시 시도');
    callsAre('P2a 재시도', {'myApplications': 2, 'myMonthlyAttendances': 2, 'myAvailability': 1, 'invitePreference': 1});
    aEq(kpis(), exA, 'P2a 재시도 값');
    obs('P2a', 'retried');
  }
  await mount(_D213Srv(
    apps: {1: [aA]},
    att: {1: <AttendanceModel>[]},
    attMonths: {1: [m0.year, m0.month]},
  ));
  obs('P2b', 'att-empty');
  expect(kpis(), exA, reason: 'D213 P2b 정상 [] 값');
  a(!hasBody(tAttFail) && !hasBody(tAppsFail), 'P2b 실패 안내 0');

  // ════ P3 최초 apps 실패 → 제목·본문·retry 도달 → 재시도 ════
  await mount(_D213Srv(
    apps: {1: 'fail', 2: [aA]},
    att: {1: <AttendanceModel>[]},
    attMonths: {1: [m0.year, m0.month]},
  ));
  callsAre('P3 mount', {'myApplications': 1, 'myAvailability': 1, 'invitePreference': 1});
  obs('P3', 'apps-failed');
  await frames(41);
  guard('P3 toast 뒤');
  aEq(kpis(), fail4, 'P3 4값 확인하지 못함');
  await capture('P3-top');
  await dragUp('P3 아래로');
  obs('P3', 'bottom');
  a(seen(tAppsFail)['inViewport'] == true && seen(tAppsSub)['inViewport'] == true, 'P3 제목·본문 화면 안');
  await capture('P3-bottom');
  await tapOn(retryBtn(), 'P3 다시 시도');
  callsAre('P3 재시도', {'myApplications': 2, 'myMonthlyAttendances': 1, 'myAvailability': 1, 'invitePreference': 1});
  obs('P3', 'retried');
  aEq(kpis(), exA, 'P3 재시도 값');

  // ════ P4 D0 카드 실제 도달 → 맨 위 복귀 → 실제 당김 apps 실패 → 재시도 ════
  await mount(_D213Srv(
    apps: {1: [aE], 2: 'fail', 3: [aE]},
    att: {1: <AttendanceModel>[], 2: <AttendanceModel>[]},
    attMonths: {1: [m0.year, m0.month], 2: [m0.year, m0.month]},
  ));
  callsAre('P4 mount', {'myApplications': 1, 'myMonthlyAttendances': 1, 'myAvailability': 1, 'invitePreference': 1});
  expect(kpis(), exE, reason: 'D213 P4 [E] 값');
  await dragUp('P4 카드까지');
  final c0 = cards();
  expect(c0.length == 1 && c0.first['id'] == 'd213-e' && c0.first['inViewport'] == true, isTrue,
      reason: 'D213 P4 D0 카드 화면 안 $c0');
  obs('P4', 'card-visible');
  await dragBack('P4 맨 위로');
  final sf4 = vsf();
  expect(sf4, findsOneWidget, reason: 'D213 P4 당김 세로 scrollable 하나');
  expect(calF(), findsOneWidget, reason: 'D213 P4 당김 달력 하나');
  final sr4 = t.getRect(sf4);
  final cr4 = t.getRect(calF());
  final vd4 = t.state<ScrollableState>(sf4).position.viewportDimension;
  final calls4 = Map<String, int>.from(srv.calls);
  final q0 = Offset(sr4.left + 8, (cr4.bottom > sr4.top ? cr4.bottom : sr4.top) + 8);
  final q1 = q0 + const Offset(0, 20);
  final pullLim = (sr4.bottom < vh ? sr4.bottom : vh) - 8;
  final pullRoom = pullLim - q1.dy;
  final pullD = pullRoom < vd4 * 0.5 ? pullRoom : vd4 * 0.5;
  final q2 = q1 + Offset(0, pullD);
  Finder rpi() => find.descendant(
      of: find.byType(RefreshIndicator), matching: find.byType(RefreshProgressIndicator));
  Map<String, Object?> pullRaw(String phase) {
    final p = t.state<ScrollableState>(sf4).position;
    final ri = rpi().evaluate().toList();
    final ir = ri.length == 1 ? t.getRect(rpi()) : null;
    return {
      'mode': mode, 'phase': phase, 'offset': p.pixels, 'extentBefore': p.extentBefore,
      'viewportDimension': p.viewportDimension, 'vh': vh, 'vw': vw,
      'scrollRect': lt(sr4), 'calendarRect': lt(cr4),
      'start': [q0.dx, q0.dy], 'mid': [q1.dx, q1.dy], 'end': [q2.dx, q2.dy],
      'pullLim': pullLim, 'pullRoom': pullRoom, 'pullD': pullD, 'quarter': vd4 * 0.25,
      'indicators': ri.length,
      'indicatorRect': ir == null ? null : lt(ir),
      'indicatorInViewport': ir == null ? null : inVp(ir),
      'indicatorValue': ri.length == 1 ? (ri.first.widget as RefreshProgressIndicator).value : null,
      'callsBefore': calls4, 'calls': Map<String, int>.from(srv.calls),
      'pumps': pumps, 'taps': taps, 'drags': drags, 'pngs': pngs,
    };
  }

  final ready = pullRaw('ready');
  ready['hitPath'] = hitPath(q0);
  print('D213PULL ${jsonEncode(ready)}');
  obs('P4', 'pull-ready');
  expect(ready['offset'], 0.0, reason: 'D213 P4 당김 전 offset 0');
  expect(ready['extentBefore'], 0.0, reason: 'D213 P4 당김 전 extentBefore 0');
  expect(srv.calls,
      {'myApplications': 1, 'myMonthlyAttendances': 1, 'myAvailability': 1, 'invitePreference': 1},
      reason: 'D213 P4 당김 전 호출 불변');
  expect(!cr4.contains(q0), isTrue, reason: 'D213 P4 당김 시작점 $q0 달력 $cr4 밖');
  for (final q in [q0, q1, q2]) {
    expect(sr4.contains(q) && inView(q), isTrue,
        reason: 'D213 P4 당김 점 $q scrollRect $sr4 viewport 안');
  }
  expect(pullD > vd4 * 0.25, isTrue, reason: 'D213 P4 당김 거리 $pullD 대 viewport $vd4');
  drags++;
  expect(drags, lessThanOrEqualTo(16), reason: 'D213 drag 예산');
  steps.add('P4 당김');
  final g4 = await t.startGesture(q0);
  var up4 = false;
  try {
    await g4.moveBy(const Offset(0, 20));
    await g4.moveBy(Offset(0, pullD));
    await frames(1);
    final held = pullRaw('held');
    print('D213PULL ${jsonEncode(held)}');
    expect(held['indicators'], 1, reason: 'D213 P4 held indicator 1');
    expect(held['indicatorInViewport'], isTrue, reason: 'D213 P4 held indicator 화면 안');
    expect(held['indicatorValue'], isNotNull, reason: 'D213 P4 held indicator value');
    expect(held['indicatorValue'], closeTo(0.75, 0.000001), reason: 'D213 P4 held 포화 0.75');
    expect(srv.calls, calls4, reason: 'D213 P4 held 호출 불변');
    guard('P4 당김 held');
    up4 = true;
    await g4.up();
  } finally {
    if (!up4) {
      up4 = true;
      await g4.up();
    }
  }
  await frames(10);
  print('D213PULL ${jsonEncode(pullRaw('released'))}');
  obs('P4', 'released');
  guard('P4 당김');
  expect(srv.calls['myApplications'], 2, reason: 'D213 P4 당김 apps +1');
  final l4 = srv.log.where((e) => e['read'] == 'myApplications' && e['n'] == 2).toList();
  expect(l4.length == 1 && l4.single['uid'] == kUid && l4.single['result'] == 'throw', isTrue,
      reason: 'D213 P4 당김 2회차 실패 fixture $l4');
  obs('P4', 'refresh-failed');
  await frames(41);
  guard('P4 toast 뒤');
  aEq(kpis(), fail4, 'P4 4값 확인하지 못함');
  a(cards().isEmpty, 'P4 이전 카드 비노출');
  await capture('P4-fail-top');
  await dragUp('P4 아래로');
  obs('P4', 'bottom');
  a(seen(tAppsFail)['inViewport'] == true, 'P4 오류 제목 화면 안');
  await capture('P4-fail-bottom');
  if (after) {
    await tapOn(retryBtn(), 'P4 다시 시도');
    callsAre('P4 재시도', {'myApplications': 3, 'myMonthlyAttendances': 2, 'myAvailability': 1, 'invitePreference': 1});
    aEq(kpis(), exE, 'P4 재시도 값');
    await dragUp('P4 재시도 뒤 카드');
    final c1 = cards();
    a(c1.length == 1 && c1.first['id'] == 'd213-e' && c1.first['inViewport'] == true, 'P4 재시도 뒤 카드 복구');
    obs('P4', 'retried');
  }

  // ════ P5 두 read 정상 빈 목록 ════
  await mount(_D213Srv(apps: {1: <ApplicationModel>[]}, att: {1: <AttendanceModel>[]}, attMonths: {1: [m0.year, m0.month]}));
  obs('P5', 'empty');
  expect(kpis(), exNone, reason: 'D213 P5 정상 0');
  expect(hasBody('${d0.month}월 ${d0.day}일 일정이 없어요'), isTrue, reason: 'D213 P5 정상 빈 상태');
  a(!hasBody(tAttFail) && !hasBody(tAppsFail) && !hasBody(tLoading), 'P5 실패·조회중 안내 0');

  // ════ P6 양수 근태·확정금액, 근태 의존 예상수입 ════
  await mount(_D213Srv(apps: {1: [aX, aY]}, att: {1: [attX]}, attMonths: {1: [m0.year, m0.month]}));
  obs('P6', 'positive');
  expect(kpis(), exXY, reason: 'D213 P6 손 계산 값');
  await capture('N6');

  // ════ P7 세대 보호: 옛 달 보류 응답이 새 달을 덮지 않음 ════
  final h7 = Completer<List<AttendanceModel>>();
  await mount(_D213Srv(
    apps: {1: abc, 2: abc, 3: abc},
    att: {1: <AttendanceModel>[], 2: h7, 3: <AttendanceModel>[]},
    attMonths: {1: [m0.year, m0.month], 2: [m1.year, m1.month], 3: [m2.year, m2.month]},
  ));
  await tapOn(nextMonth(), 'P7 다음 달(M1 보류)');
  await tapOn(nextMonth(), 'P7 다음 달(M2)');
  expect(hasBody('${m2.year}년 ${m2.month}월'), isTrue, reason: 'D213 P7 달력 M2');
  obs('P7', 'M2-loaded');
  h7.complete(const <AttendanceModel>[]);
  await frames(5);
  guard('P7 옛 응답 완료');
  obs('P7', 'late-M1-done');
  a(hasBody('${m2.month}월 요약'), 'P7 머리 M2 유지');
  aEq(kpis(), exM2, 'P7 M2 값 유지');
  a(!hasBody(tAttFail) && !hasToast('출근 기록을 불러오지 못했어요'), 'P7 오류·toast 0');

  // ════ P8 320x640@2.0 근태 실패 긴 문구·재시도 도달(DU216 유한 탐색: dragUp 최대 4회, 최초 전체 도달에서 멈춤) ════
  setView(320, 640, 2.0);
  await mount(_D213Srv(apps: {1: [aA]}, att: {1: 'fail'}, attMonths: {1: [m0.year, m0.month]}));
  callsAre('P8 mount',
      {'myApplications': 1, 'myMonthlyAttendances': 1, 'myAvailability': 1, 'invitePreference': 1});
  final calls8 = Map<String, int>.from(srv.calls);
  // 목표: after = 근태 실패 제목·부제·retry 버튼, before = D0 빈 안내 제목·부제(CTA 없음). 교정 성공 단언이 아니다.
  final p8Title = after ? tAttFail : '${d0.month}월 ${d0.day}일 일정이 없어요';
  final p8Sub = after ? tAttSub : '다른 날짜를 선택해 확인해보세요';
  bool p8Inside(Rect r, Rect c) =>
      r.left >= c.left && r.top >= c.top && r.right <= c.right && r.bottom <= c.bottom;
  Map<String, Object?> p8Item(List<Element> es, Rect clip) {
    if (es.length != 1) return {'tree': es.length};
    final r = rectOf(es.first);
    return {'tree': 1, 'rect': lt(r), 'overlap': r.overlaps(clip), 'inside': p8Inside(r, clip)};
  }

  double? prev8;
  int? firstTree8;
  int? firstOverlap8;
  int? firstFull8;
  var p8Drags = 0;
  var full8 = false;
  for (var i = 0;; i++) {
    final sf8 = vsf();
    expect(sf8, findsOneWidget, reason: 'D213 P8 탐색 $i 세로 scrollable 하나');
    expect(calF(), findsOneWidget, reason: 'D213 P8 탐색 $i 달력 하나');
    final pos8 = t.state<ScrollableState>(sf8).position;
    final sr8 = t.getRect(sf8);
    final clip8 = sr8.intersect(Rect.fromLTWH(0, 0, vw, vh));
    final dims = pos8.hasContentDimensions;
    final ti = p8Item(body(p8Title), clip8);
    final su = p8Item(body(p8Sub), clip8);
    final bt = after
        ? p8Item(retryBtn().evaluate().toList(), clip8)
        : <String, Object?>{'tree': 0, 'role': 'baseline CTA 없음'};
    final items = after ? [ti, su, bt] : [ti, su];
    final anyTree = items.any((m) => (m['tree'] as int) > 0);
    final anyOverlap = items.any((m) => m['overlap'] == true);
    full8 = items.every((m) => m['inside'] == true);
    if (anyTree && firstTree8 == null) firstTree8 = i;
    if (anyOverlap && firstOverlap8 == null) firstOverlap8 = i;
    if (full8 && firstFull8 == null) firstFull8 = i;
    final ea = dims ? pos8.extentAfter : null;
    final dp = prev8 == null ? null : pos8.pixels - prev8;
    print('D213P8 ${jsonEncode({
          'mode': mode, 'i': i, 'drags8': p8Drags, 'hasContentDimensions': dims,
          'pixels': pos8.pixels,
          'min': dims ? pos8.minScrollExtent : null, 'max': dims ? pos8.maxScrollExtent : null,
          'extentBefore': dims ? pos8.extentBefore : null, 'extentAfter': ea,
          'viewportDimension': pos8.viewportDimension, 'outOfRange': dims ? pos8.outOfRange : null,
          'isScrolling': pos8.isScrollingNotifier.value, 'deltaPixels': dp,
          'scrollRect': lt(sr8), 'clip': lt(clip8), 'calendarRect': lt(t.getRect(calF())),
          'title': ti, 'sub': su, 'btn': bt, 'full': full8,
          'firstTree': firstTree8, 'firstOverlap': firstOverlap8, 'firstFull': firstFull8,
          'calls': Map<String, int>.from(srv.calls), 'violations': srv.violations.length,
          'blocked': blocked.length, 'pumps': pumps, 'taps': taps, 'drags': drags, 'pngs': pngs,
        })}');
    expect(srv.calls, calls8, reason: 'D213 P8 탐색 $i 호출 불변');
    guard('P8 탐색 $i');
    expect(pos8.isScrollingNotifier.value, isFalse, reason: 'D213 P8 탐색 $i 고정 pump 뒤 스크롤 진행 중');
    if (full8) break;
    expect(dims, isTrue, reason: 'D213 P8 탐색 $i 스크롤 범위 미측정');
    final eaN = ea ?? 0.0;
    expect(eaN <= 0.01 && !pos8.outOfRange, isFalse, reason: 'D213 P8 끝도달/목표미관측 $i');
    if (dp != null) {
      expect(dp <= 0.01 && eaN > 0.01, isFalse, reason: 'D213 P8 무진행/조작·계측미확인 $i');
    }
    expect(p8Drags < 4, isTrue, reason: 'D213 P8 탐색상한미도달 $i');
    final st8 = Offset(8, vh - 40);
    expect(clip8.contains(st8), isTrue, reason: 'D213 P8 시작점 $st8 scroll clip $clip8 안');
    prev8 = pos8.pixels;
    p8Drags++;
    await dragUp('P8 아래로 $p8Drags');
  }
  obs('P8', 'bottom');
  print('D213P8DONE ${jsonEncode({
        'mode': mode, 'drags8': p8Drags, 'firstTree': firstTree8, 'firstOverlap': firstOverlap8,
        'firstFull': firstFull8, 'full': full8, 'target': [p8Title, p8Sub, if (after) '다시 시도'],
      })}');
  expect(full8, isTrue, reason: 'D213 P8 목표 전체 clip 안(${after ? '근태 실패 안내' : 'baseline 빈 안내'})');
  if (after) {
    final sub = body(tAttSub);
    a(sub.length == 1 && inVp(rectOf(sub.first)), 'P8 부제 화면 안');
    if (sub.isNotEmpty) {
      final rp = t.renderObject<RenderParagraph>(find.descendant(
          of: find.byElementPredicate((x) => identical(x, sub.first)), matching: find.byType(RichText)));
      a(!rp.didExceedMaxLines, 'P8 부제 넘침 없음');
    }
    final rb = rectFinder(retryBtn());
    a(rb != null && rb[3] - rb[1] >= 48 && inVp(Rect.fromLTRB(rb[0], rb[1], rb[2], rb[3])), 'P8 retry 48·화면 안');
  }
  await capture('P8-bottom');
  setView(360, 780, 1.0);

  final endNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  expect(DateTime.utc(endNow.year, endNow.month, endNow.day), d0, reason: 'D213 자정 경계');
  print('D213END ${jsonEncode({
        'mode': mode, 'pumps': pumps, 'taps': taps, 'drags': drags, 'pngs': pngs,
        'blocked': blocked.length, 'utc': DateTime.now().toUtc().toIso8601String(),
      })}');
}
