// ignore_for_file: depend_on_referenced_packages
// [PERF-FIRST-LOAD-1 · 판정289 §2·§3·§8] PerfLog 최소 계측 · L2 사용자 준비 분리 · L1 안전판.
//
//   PerfLog  기본 빌드(ALFIT_PERF 없음)는 출력 0 · extra 계산 0
//   L2       계정 판정이 끝나면 홈 준비 해제 — FCM(권한 창)·미서명 계약은 기다리지 않는다
//            미서명 계약 출처 상태(LOADING/ERROR …)를 '없음'으로 접지 않는다
//            알림 탭 cold-start payload 는 준비 완료 뒤 세션·uid 재검사 후 1회 소비(세 root)
//            FCM 초기화의 늦은 continuation 은 로그아웃 뒤 아무것도 쓰지 않는다(세션 가드)
//   L1       버전 판정 전 사용자 문서 읽기만 미리 · 판정 뒤 같은 uid·시효 안에서 1회 소비
import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/providers/user_snapshot_prefetch.dart';
import 'package:ALfit/services/auth_service.dart';
import 'package:ALfit/services/cold_start_readiness.dart';
import 'package:ALfit/utils/perf_log.dart';

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

class _FbUser extends Fake implements User {
  _FbUser(this.uid);
  @override
  final String uid;
}

class _FakeAuth extends Fake implements AuthService {
  final events = StreamController<User?>.broadcast();
  int reads = 0;
  UserModel? user;
  @override
  Stream<User?> get authStateChanges => events.stream;
  @override
  Future<UserModel?> getUserData(String uid) async {
    reads++;
    return user;
  }
}

UserModel _worker() => UserModel(
      uid: 'u1',
      username: 'u1',
      name: '김근로',
      email: 'u1@alfit.local',
      role: UserRole.USER,
      accountStatus: 'active',
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
      createdAt: DateTime(2026, 1, 1),
    );

String _code(String p) => File(p)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _bodyOf(String src, String sig) {
  final at = src.indexOf(sig);
  expect(at, isNot(-1), reason: '$sig 가 없다');
  // 매개변수의 `{…}`(이름 있는 인자)를 본문으로 잘못 잡지 않게 `) {` / `) async {` 를 찾는다.
  final m = RegExp(r'\)\s*(async\s*)?\{').firstMatch(src.substring(at));
  final open = at + m!.end - 1;
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(at, i + 1);
    }
  }
  return src.substring(at);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ── PerfLog ─────────────────────────────────────────────────────────
  group('[PerfLog] 기본 빌드는 출력 0 · extra 계산 0', () {
    test('PL-1 ALFIT_PERF 없이는 꺼져 있고 아무것도 출력·계산하지 않는다', () {
      expect(PerfLog.enabled, const bool.fromEnvironment('ALFIT_PERF'));
      if (PerfLog.enabled) return; // perf 빌드로 이 파일을 돌릴 때는 PL-2 가 본다
      final printed = <String>[];
      var extraCalls = 0;
      runZoned(() {
        PerfLog.start();
        PerfLog.mark('x.event', () {
          extraCalls++;
          return {'n': 1};
        });
        PerfLog.watchFrames();
      }, zoneSpecification: ZoneSpecification(print: (_, __, ___, line) => printed.add(line)));
      expect(printed, isEmpty);
      expect(extraCalls, 0);
    });

    test('PL-2 켜진 빌드의 줄 형식 · 개인정보 키 없음(소스)', () {
      final src = _code('lib/utils/perf_log.dart');
      expect(src.contains("static const bool enabled = bool.fromEnvironment('ALFIT_PERF');"), isTrue);
      expect(RegExp(r'(?<![a-zA-Z_$])print\s*\(').allMatches(src).length, 1,
          reason: 'LOG-01 예외는 sink 한 곳');
      if (PerfLog.enabled) {
        final printed = <String>[];
        runZoned(() => PerfLog.mark('x.event', () => {'n': 2}),
            zoneSpecification: ZoneSpecification(print: (_, __, ___, l) => printed.add(l)));
        expect(printed.single, matches(RegExp(r'^\[PERF\] \+\d+ms #\d+ run=\d+ x\.event n=2$')));
      }
      // 표식 지점에 uid·이름·토큰을 extra 로 넣지 않는다.
      for (final p in [
        'lib/main.dart', 'lib/providers/user_provider.dart', 'lib/services/fcm_service.dart',
        'lib/screens/user/user_home_screen.dart', 'lib/screens/business_admin/business_admin_home_screen.dart',
        'lib/screens/common/splash_screen.dart',
      ]) {
        final c = _code(p);
        for (final m in RegExp(r"PerfLog\.mark\([^;]*;").allMatches(c)) {
          final call = m.group(0)!;
          for (final banned in ['uid', 'name', 'token', 'phone', 'email', 'url']) {
            expect(RegExp("'$banned'").hasMatch(call), isFalse, reason: '$p: $call');
          }
        }
      }
    });
  });

  // ── L2 cold-start 준비 ─────────────────────────────────────────────
  group('[L2] cold-start 준비 → 재검사 → 1회 소비', () {
    test('CS-1 준비가 끝나기 전에는 소비 판정을 하지 않는다', () async {
      final r = ColdStartReadiness()..begin(1);
      var asked = 0;
      final f = r.waitFor(stillValid: (s) {
        asked++;
        return s == 1;
      });
      await Future<void>.delayed(Duration.zero);
      expect(asked, 0);
      expect(r.settle(1), isTrue);
      expect(await f, isTrue);
      expect(asked, 1);
      expect(r.settle(1), isFalse, reason: '두 번 끝내지 않는다');
    });

    test('CS-2 로그아웃(cancel) 은 대기자를 끝내고 소비는 거절된다', () async {
      final r = ColdStartReadiness()..begin(5);
      var fcmSession = 5;
      final f = r.waitFor(stillValid: (s) => s == fcmSession);
      fcmSession = 6; // clearToken 이 세션을 올린다
      r.cancel();
      expect(await f, isFalse);
    });

    test('CS-3 준비 중 새 세션(계정 전환 재초기화)이면 새 준비를 기다린다', () async {
      final r = ColdStartReadiness()..begin(1);
      final f = r.waitFor(stillValid: (s) => s == 2);
      r.settle(1);
      r.begin(2); // 같은 동기 구간에서 다음 세션이 열린다(finally → initialize)
      await Future<void>.delayed(Duration.zero);
      r.settle(2);
      expect(await f, isTrue);
    });

    test('CS-4 초기화가 시작된 적 없으면 받을 payload 가 없다(끝)', () async {
      expect(await ColdStartReadiness().waitFor(stillValid: (_) => true), isFalse);
    });

    test('CS-5 소스 — 세 root 모두 준비 뒤 소비 · 직접 소비 0', () {
      for (final p in [
        'lib/screens/user/user_root_screen.dart',
        'lib/screens/business_admin/business_admin_shell.dart',
        'lib/screens/super_admin/super_admin_home_screen.dart',
      ]) {
        final c = _code(p);
        expect(c.contains('consumeColdStartPayloadWhenReady('), isTrue, reason: p);
        expect(c.contains('consumePendingColdStartPayload()'), isFalse, reason: p);
        expect(c.contains('isActive: () => mounted'), isTrue, reason: p);
      }
    });

    test('CS-6 소스 — FCM 초기화의 각 await 뒤 세션 가드 · 낡은 세션은 플래그/구독을 건드리지 않음', () {
      final fcm = _code('lib/services/fcm_service.dart');
      final init = _bodyOf(fcm, 'Future<void> initialize(String userId');
      expect('if (stale()) return;'.allMatches(init).length, greaterThanOrEqualTo(6));
      expect(init.contains('if (!stale()) {\n        _currentUserId = null;'), isTrue);
      expect(init.contains('if (!stale()) {\n        _isInitializing = false;'), isTrue);
      expect(init.contains('_coldStart.settle(session)'), isTrue, reason: 'finally 에서 준비를 끝낸다');
      // .69 순서: 폐기 settle → (권한·폐기 완료일 때만) 등록
      expect(init.indexOf('_revoker.settle('), lessThan(init.indexOf('_saveToken(')));
      final clear = _bodyOf(fcm, 'Future<bool> clearToken(');
      expect(clear.contains('_session++;'), isTrue);
      expect(clear.contains('_coldStart.cancel();'), isTrue);
      final save = _bodyOf(fcm, 'Future<void> _saveToken(');
      expect(save.indexOf('session != _session'), lessThan(save.indexOf('_updateToken(token)')));
    });
  });

  // ── L2 사용자 준비 ──────────────────────────────────────────────────
  group('[L2] 계정 판정이 끝나면 홈 준비 해제', () {
    late MethodChannel messaging;
    setUp(() {
      UserSnapshotPrefetch.debugReset();
      // 알림 권한 창이 응답하지 않는 상태(첫 로그인 · 사용자가 아직 고르지 않음).
      messaging = const MethodChannel('plugins.flutter.io/firebase_messaging');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(messaging, (call) {
        if (call.method == 'Messaging#requestPermission') {
          return Future.any(<Future<Object?>>[]);
        }
        return Future<Object?>.value(null);
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(messaging, null));

    test('UP-1 권한 창 응답을 기다리지 않고 로딩을 푼다 · 미서명 계약은 아직 모름', () async {
      final auth = _FakeAuth()..user = _worker();
      final p = UserProvider(authService: auth)..initialize();
      expect(p.isLoading, isTrue);
      auth.events.add(_FbUser('u1'));
      for (var i = 0; i < 20 && p.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(p.isLoading, isFalse, reason: 'FCM 권한 창 응답을 기다리느라 홈이 열리지 않았다');
      expect(p.currentUser?.uid, 'u1');
      expect(p.pendingContractsStatus, isNot(PendingContractsStatus.loaded),
          reason: '아직 확인하지 않은 미서명 계약을 "없음(확인됨)"으로 접지 않는다');
      expect(auth.reads, 1);
      p.dispose();
      await auth.events.close();
    });

    test('UP-2 L1 — 미리 읽은 같은 uid 문서를 1회 쓰고 다시 읽지 않는다', () async {
      final auth = _FakeAuth()..user = _worker();
      var prefetchReads = 0;
      UserSnapshotPrefetch.start('u1', (uid) async {
        prefetchReads++;
        return _worker();
      });
      final p = UserProvider(authService: auth)..initialize();
      auth.events.add(_FbUser('u1'));
      for (var i = 0; i < 20 && p.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(p.currentUser?.uid, 'u1');
      expect(prefetchReads, 1);
      expect(auth.reads, 0, reason: '같은 문서를 두 번 읽었다');
      expect(UserSnapshotPrefetch.debugHasPending, isFalse, reason: '1회 소비');
      p.dispose();
      await auth.events.close();
    });

    test('UP-3 L1 — 다른 uid · 시효 초과 · 실패는 쓰지 않는다', () async {
      UserSnapshotPrefetch.start('u1', (uid) async => _worker());
      expect(UserSnapshotPrefetch.take('u2'), isNull, reason: '다른 계정');
      final t0 = DateTime(2026, 11, 26, 10);
      UserSnapshotPrefetch.start('u1', (uid) async => _worker(), clock: () => t0);
      expect(
          UserSnapshotPrefetch.take('u1',
              clock: () => t0.add(UserSnapshotPrefetch.maxAge + const Duration(seconds: 1))),
          isNull,
          reason: '오래된 미리 읽기');
      // 실패한 미리 읽기 → 소비자가 다시 읽는다.
      final auth = _FakeAuth()..user = _worker();
      UserSnapshotPrefetch.start('u1', (uid) => Future<UserModel?>.error(StateError('offline')));
      final p = UserProvider(authService: auth)..initialize();
      auth.events.add(_FbUser('u1'));
      for (var i = 0; i < 20 && p.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(p.currentUser?.uid, 'u1');
      expect(auth.reads, 1, reason: '미리 읽기 실패 → 평소처럼 읽기');
      p.dispose();
      await auth.events.close();
    });

    test('UP-4 소스 — 부가 초기화 비대기 · 필수 판정 뒤 해제 · main 은 판정 전 읽기만', () {
      final up = _code('lib/providers/user_provider.dart');
      final load = _bodyOf(up, 'Future<void> _loadUserData(String uid)');
      expect(load.contains('await FCMService().initialize'), isFalse);
      expect(load.contains('await fcmFuture'), isFalse);
      expect(load.contains('await Future.wait(['), isFalse);
      // 필수 판정(고아·삭제·pending·LoginGate·서브관리자 권한) 뒤에 해제
      final release = load.lastIndexOf('_isLoading = false;\n      notifyListeners();\n    } catch');
      for (final gate in [
        'getDeletionRecoveryState()',
        "accountStatus == 'deleting'",
        "acStatus == 'pending'",
        'LoginGate.fromUser(',
        'await permMapFuture;',
      ]) {
        expect(load.indexOf(gate), allOf(isNot(-1), lessThan(release)), reason: gate);
      }
      final aux = _bodyOf(up, 'void _runAuxInit(');
      expect(aux.contains('_loadGeneration != gen'), isTrue);
      expect(aux.contains('onError:'), isTrue);
      // L1 — main 은 Firestore settings 뒤 · 읽기만
      final m = _code('lib/main.dart');
      final mainFn = _bodyOf(m, 'void main() async');
      expect(mainFn.indexOf('UserSnapshotPrefetch.start('),
          greaterThan(mainFn.indexOf('FirebaseFirestore.instance.settings')));
      expect(mainFn.contains('AuthService().getUserData'), isTrue);
      expect(m.contains('lazy: false'), isFalse, reason: 'initialize 전체 eager 화는 미수용');
    });
  });
}
