// [WORKER-HOME-STARTUP.23] 근로자 첫 진입의 같은 요청 중복 제거.
//
// ── 대조 (CODE + LOCAL 브리지 기록) ──────────────────────────────────────
//   getMyMonthlyAttendances ×2 — 홈(KST 이번 달)과 IndexedStack 이 함께 만드는 일정 탭(이번 달)이
//     같은 uid·연·월을 **동시에** 보냈다. 2분 TTL 캐시는 완료 뒤에만 채워진다 → 둘 다 미스.
//   getMyContracts(미서명 필터·50건) ×3 — authStateChanges·signIn 이 각자 _loadUserData 를 돌고
//     홈 로드가 또 부른다(같은 uid·같은 인자). 홈의 전체 계약 조회(200건)는 **다른 요청**이라 그대로 둔다.
//
// ── 바꾼 것 ──────────────────────────────────────────────────────────
//   진행 중 요청만 공유하고 완료(성공·실패)되면 놓는다. 결과 보관은 기존 규칙 그대로.
//   근태: 무효화(출퇴근 성공)하면 진행 중 요청을 끊고 옛 응답은 캐시에 남기지 않는다.
//   미서명 계약: 같은 진입(로그인·홈 로드)만 합류. 서명 뒤 갱신은 항상 새로 읽는다.
//     더 새 조회가 출발했거나 계정이 바뀌었으면 늦은 응답은 쓰지 않는다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_schedule_screen.dart';
import 'package:ALfit/screens/user/user_root_screen.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/widgets/common/app_bottom_tab_bar.dart';

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

UserModel _worker(String uid) => UserModel(
      uid: uid, username: uid, name: '김근로', email: '$uid@alfit.local',
      role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
      accountStatus: 'active',
    );

class _User extends UserProvider {
  @override
  UserModel? get currentUser => _worker('w1');
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

const _callCh =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase =
    'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.';

/// 서버 대역 — 이름별로 세고, 인자를 남긴다. 근태·계약 응답은 순서대로 소비(마지막 값 반복).
class _Server {
  int delayMs = 300;
  final calls = <String, int>{};
  final args = <String, List<Map>>{};
  final List<Object> atts = [<Object?>[]];
  int _attIdx = 0;
  final List<Object> contracts = [<Object?>[]];
  int _cIdx = 0;
  Completer<void>? contractGate;

  Future<ByteData?> handle(ByteData? data) async {
    final a = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
    final name = a['functionName'] as String;
    calls[name] = (calls[name] ?? 0) + 1;
    (args[name] ??= []).add((a['parameters'] as Map?) ?? const {});
    // [impl_15 의도적 갱신] 이 대역은 개별 endpoint 경로(진행 중 공유·횟수)를 잰다 — 묶음 함수는 '구서버(없음)'로 답해
    //   앱이 같은 호출 안에서 개별 호출로 폴백하게 한다(묶음 경로 자체는 perf_l9_bundle_test WHB-* 가 맡는다).
    if (name == 'callableGetWorkerHomeBundle') return const StandardMessageCodec().encodeMessage(<Object?>['NOT_FOUND', 'no bundle', {'code': 'not-found', 'message': 'no bundle'}]);
    if (name == 'getMyMonthlyAttendances') {
      final r = atts[_attIdx < atts.length ? _attIdx : atts.length - 1];
      _attIdx++;
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      if (r is String) return _err(r);
      return _ok({'items': r});
    }
    if (name == 'getMyContracts') {
      final r = contracts[_cIdx < contracts.length ? _cIdx : contracts.length - 1];
      _cIdx++;
      final gate = contractGate;
      if (gate != null && _cIdx == 1) await gate.future;
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      if (r is String) return _err(r);
      return _ok({'items': r, 'hasMore': false});
    }
    await Future<void>.delayed(Duration(milliseconds: delayMs));
    return _ok({
      'applications': <Object?>[], 'items': <Object?>[], 'tos': <Object?>[],
      'requests': <Object?>[], 'proposals': <Object?>[], 'contracts': <Object?>[],
      'hasMore': false,
    });
  }

  ByteData? _ok(Map<String, Object?> body) =>
      const StandardMessageCodec().encodeMessage(<Object?>[body]);
  ByteData? _err(String code) =>
      const StandardMessageCodec().encodeMessage(<Object?>[code, 'mock $code', null]);

  int get att => calls['getMyMonthlyAttendances'] ?? 0;
  int get con => calls['getMyContracts'] ?? 0;
}

Map<String, Object?> _ts(DateTime d) =>
    {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

Map<String, Object?> _att(String id, String status) => {
      'id': id, 'userId': 'w1', 'applicationId': 'app_$id', 'businessId': 'biz1',
      'businessName': '합성 사업장', 'workType': '상하차', 'status': status,
      'workDate': _ts(DateTime.now()), 'createdAt': _ts(DateTime.now()),
    };

/// 서버 응답 모양의 합성 미서명 계약(파서 필수 snapshot 포함).
Map<String, Object?> _contract(String id) => {
      'id': id, 'status': 'pending_worker', 'workerId': 'w1', 'businessId': 'biz1',
      'applicationId': 'app_$id', 'applicationIds': ['app_$id'], 'toId': 'to1',
      'isLongTerm': false, 'createdAt': _ts(DateTime.now()),
      'snapshot': {
        'businessName': '합성 사업장', 'businessNumber': '000-00-00000',
        'businessAddress': '서울특별시 강남구', 'ownerName': '합성 대표',
        'workerName': '김근로', 'workType': '상하차', 'workPlace': '서울특별시 강남구',
        'isLongTerm': false, 'contractStart': '2026-10-28', 'contractEnd': '2026-10-28',
        'workDays': <Object?>[], 'startTime': '09:00', 'endTime': '18:00', 'breakMinutes': 60,
        'wage': 12000, 'wageType': 'hourly', 'paymentMethod': '계좌이체',
        'payScheduleType': 'same_day', 'taxDeductionType': 'none',
      },
      'articles': <Object?>[],
    };

void _install(WidgetTester t, _Server s) {
  final m = t.binding.defaultBinaryMessenger;
  m.setMockMessageHandler(_callCh, s.handle);
  for (final api in ['documentReferenceGet', 'queryGet', 'aggregateQuery']) {
    m.setMockMessageHandler('$_fsBase$api', (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return const StandardMessageCodec()
          .encodeMessage(<Object?>['unavailable', 'mock', null]);
    });
  }
  addTearDown(() {
    m.setMockMessageHandler(_callCh, null);
    for (final api in ['documentReferenceGet', 'queryGet', 'aggregateQuery']) {
      m.setMockMessageHandler('$_fsBase$api', null);
    }
  });
}

Future<void> _pumpFor(WidgetTester t, int ms) async {
  for (var e = 0; e < ms; e += 50) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({'tour_completed_user_home': true});
    for (final u in ['w1', 'w2', 'w3', 'w4', 'w5', 'w6']) {
      FirestoreService().invalidateMyAttendanceCache(u);
      FirestoreService().invalidateMyApplicationsCache(u);
    }
  });

  group('MAT 월별 근태 — 진행 중 공유', () {
    testWidgets('MAT-1 같은 uid·연·월 동시 2회 → 서버 1회, 둘 다 같은 응답', (t) async {
      final s = _Server()..atts[0] = [_att('a1', 'present')];
      _install(t, s);
      final svc = FirestoreService();
      final f = [
        svc.getMyMonthlyAttendances(userId: 'w1', year: 2026, month: 10),
        svc.getMyMonthlyAttendances(userId: 'w1', year: 2026, month: 10),
      ];
      await _pumpFor(t, 400);
      final r = await Future.wait(f);
      expect(s.att, 1);
      expect(r.map((l) => l.map((a) => a.id).join(',')).toSet(), {'a1'});
    });

    testWidgets('MAT-2 실패는 공유되지만 보관되지 않는다 — 다음 호출은 새 요청으로 회복', (t) async {
      final s = _Server()..atts.clear()..atts.addAll(['unavailable', [_att('a2', 'present')]]);
      _install(t, s);
      final svc = FirestoreService();
      final errs = <Object>[];
      final f = [
        for (var i = 0; i < 2; i++)
          svc.getMyMonthlyAttendances(userId: 'w2', year: 2026, month: 10)
              .then<Object?>((v) => v, onError: (Object e) { errs.add(e); return null; }),
      ];
      await _pumpFor(t, 400);
      await Future.wait(f);
      expect(s.att, 1);
      expect(errs, hasLength(2), reason: '실패를 빈 목록(0)으로 바꾸지 않는다');
      final next = svc.getMyMonthlyAttendances(userId: 'w2', year: 2026, month: 10);
      await _pumpFor(t, 400);
      expect((await next).single.id, 'a2');
      expect(s.att, 2);
    });

    testWidgets('MAT-3 다른 달·다른 사용자는 공유하지 않는다(월 경계·계정 전환)', (t) async {
      final s = _Server();
      _install(t, s);
      final svc = FirestoreService();
      final f = [
        svc.getMyMonthlyAttendances(userId: 'w3', year: 2026, month: 10),
        svc.getMyMonthlyAttendances(userId: 'w3', year: 2026, month: 11),
        svc.getMyMonthlyAttendances(userId: 'w4', year: 2026, month: 10),
      ];
      await _pumpFor(t, 400);
      await Future.wait(f);
      expect(s.att, 3);
      final ps = s.args['getMyMonthlyAttendances']!.map((p) => '${p['year']}-${p['month']}').toList();
      expect(ps, containsAll(['2026-10', '2026-11']));
    });

    testWidgets('MAT-4 진행 중 출퇴근(무효화) — 새 호출은 합류하지 않고 옛 응답은 캐시에 남지 않는다', (t) async {
      final s = _Server()..atts.clear()..atts.addAll([[_att('a5', 'scheduled')], [_att('a5', 'present')]]);
      _install(t, s);
      final svc = FirestoreService();
      final old = svc.getMyMonthlyAttendances(userId: 'w5', year: 2026, month: 10);
      await _pumpFor(t, 100);
      svc.invalidateMyAttendanceCache('w5'); // 출근 성공 뒤 서비스가 하는 무효화
      final fresh = svc.getMyMonthlyAttendances(userId: 'w5', year: 2026, month: 10);
      await _pumpFor(t, 500);
      expect((await old).single.status, 'scheduled');
      expect((await fresh).single.status, 'present');
      expect(s.att, 2);
      final again = await svc.getMyMonthlyAttendances(userId: 'w5', year: 2026, month: 10);
      expect(again.single.status, 'present', reason: '옛 응답이 늦게 와서 캐시를 덮지 않는다');
      expect(s.att, 2);
    });
  });

  group('PCI 미서명 계약 — 같은 진입만 합류', () {
    UserProvider provider(String uid) {
      final p = UserProvider()..debugSetCurrentUser(_worker(uid));
      addTearDown(p.dispose);
      return p;
    }

    testWidgets('PCI-1 로그인·홈 로드(합류) 동시 2회 → 서버 1회, 결과 반영', (t) async {
      final s = _Server()..contracts[0] = [_contract('c1')];
      _install(t, s);
      final p = provider('w1');
      final f = [p.refreshPendingContracts(joinInFlight: true), p.refreshPendingContracts(joinInFlight: true)];
      await _pumpFor(t, 400);
      await Future.wait(f);
      expect(s.con, 1);
      expect(p.pendingContractCount, 1);
      expect(s.args['getMyContracts']!.single['statusFilter'], 'pending_worker');
    });

    testWidgets('PCI-2 서명 뒤 갱신(기본값)은 진행 중 요청에 합류하지 않고 새로 읽어 그 값이 남는다', (t) async {
      final s = _Server()..contracts.clear()..contracts.addAll([[_contract('c1')], <Object?>[]]);
      _install(t, s);
      final p = provider('w1');
      final before = p.refreshPendingContracts(joinInFlight: true); // 서명 전에 출발
      await _pumpFor(t, 100);
      final after = p.refreshPendingContracts(); // 서명 완료 뒤
      await _pumpFor(t, 500);
      await Future.wait([before, after]);
      expect(s.con, 2);
      expect(p.pendingContractCount, 0, reason: '먼저 출발한 옛 응답(미서명 1)이 새 값(0)을 덮지 않는다');
    });

    testWidgets('PCI-3 계정이 바뀌면 이전 사용자의 늦은 응답을 쓰지 않는다', (t) async {
      final s = _Server()
        ..contractGate = Completer<void>()
        ..contracts.clear()..contracts.addAll([[_contract('old')], <Object?>[]]);
      _install(t, s);
      final p = provider('w1');
      final f = p.refreshPendingContracts(joinInFlight: true);
      await _pumpFor(t, 100);
      p.debugSetCurrentUser(_worker('w6')); // 다른 계정
      s.contractGate!.complete();
      await _pumpFor(t, 500);
      await f;
      expect(p.pendingContractCount, 0);
    });

    testWidgets('PCI-4 실패는 보관하지 않는다 — 다음 갱신은 새 요청으로 회복', (t) async {
      final s = _Server()..contracts.clear()..contracts.addAll(['unavailable', [_contract('c2')]]);
      _install(t, s);
      final p = provider('w1');
      await Future.wait([p.refreshPendingContracts(joinInFlight: true), _pumpFor(t, 400)]);
      expect(p.pendingContractCount, 0);
      await Future.wait([p.refreshPendingContracts(joinInFlight: true), _pumpFor(t, 400)]);
      expect(s.con, 2);
      expect(p.pendingContractCount, 1);
    });
  });

  testWidgets('MAT-ROOT 첫 진입 네 탭 — 이번 달 근태 서버 호출 2→1, 홈·일정 모두 받는다', (t) async {
    final s = _Server()..atts[0] = [_att('r1', 'present')];
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
    // [impl_9 PERF-L5 의도적 갱신] 일정 탭은 방문 시 생긴다 — 홈의 이번 달 근태 조회(300ms)가 진행 중일 때 일정 탭을 열어
    //   '홈·일정이 같은 진행 중 조회를 한 번 공유한다'는 원래 계약을 그대로 입증한다(방문하지 않으면 공유 입증이 사라진다).
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.descendant(
        of: find.byType(AppBottomTabBar),
        matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? '').replaceAll('⁠', '').replaceAll('​', '') == '내 일정')));
    await _pumpFor(t, 3000);
    expect(find.byType(MyScheduleScreen), findsOneWidget, reason: '일정 탭이 실제로 열렸다');
    // ignore: avoid_print
    print('[MAT-ROOT] ${s.calls}');
    // [.47 월초] 이 시험의 계약은 "이번 달 근태를 홈·일정이 **한 번** 공유한다" 이다.
    //   루트는 실제 시계를 쓰고 루트·일정에는 시계 주입 지점이 없다(제품에 새 시각 정책을 넣지 않는다).
    //   그래서 날짜에 따라 달라지는 것 — KST 1일의 지난달 꼬리 1회 — 는 그 날에만 더한다.
    //   날짜별 동작 자체는 시계를 주입한 고정 날짜 시험이 맡는다:
    //   user_home_attendance_kst_parity_test KDP-C1(평일 1회) · KDP-C2(1일 2회) · KDP-C4·연말→1월 1일(전년도 12월 꼬리·연결).
    final kst = DateTime.now().toUtc().add(const Duration(hours: 9));
    final months = (s.args['getMyMonthlyAttendances'] ?? const [])
        .map((p) => '${p['year']}-${p['month']}')
        .toList();
    expect(months.where((m) => m == '${kst.year}-${kst.month}').length, 1,
        reason: '이번 달 근태는 홈·일정이 공유해 한 번만 읽는다');
    final prev = DateTime.utc(kst.year, kst.month, 0);
    expect(months.where((m) => m == '${prev.year}-${prev.month}').length, kst.day == 1 ? 1 : 0,
        reason: '지난달 꼬리는 KST 1일에만 읽는다');
    expect(s.att, kst.day == 1 ? 2 : 1);
    t.takeException();
  });
}
