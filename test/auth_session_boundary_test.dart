// [.25 AUTH-BOUNDARY] 로그인·로그아웃·계정 전환 사이에 늦게 도착한 사용자 로드가
//   현재 사용자를 덮지 않는다.
//
// ── 재현 (LOCAL, 지연 제어 대역) ─────────────────────────────────────
//   `_loadUserData` 는 `_currentUser = await getUserData(uid)` 로 **먼저 대입하고** 나서야
//   세대(_loadGeneration)를 비교해 "낡은 로드"를 버렸다. 그래서
//     · 로그아웃 뒤 이전 계정 응답이 오면 `_currentUser` 에 이전 계정이 다시 들어갔고(AB-1),
//     · A 로드가 걸린 사이 B 가 로그인을 마치면, 늦게 온 A 응답이 B 를 A 로 바꿨다(AB-2).
//   세대가 다르면 대입하지 않도록 고쳤다(읽은 값은 지역 변수에 두고 세대 확인 뒤 대입).
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/services/auth_service.dart';

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

class _AuthUser extends Fake implements User {
  _AuthUser(this.uid);
  @override
  final String uid;
}

UserModel _model(String uid, {String status = 'active'}) => UserModel(
      uid: uid, username: uid, name: '합성 $uid', email: '$uid@alfit.local',
      role: UserRole.BUSINESS_ADMIN, accountStatus: status,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
    );

/// 사용자 문서 읽기를 uid 별로 붙잡을 수 있는 인증 대역.
class _GatedAuth extends Fake implements AuthService {
  final _ctl = StreamController<User?>.broadcast();
  final Map<String, Completer<void>> gates = {};
  final Map<String, String> statusOf = {};
  final Set<String> missing = {};
  final Set<String> failing = {};
  User? _current;

  @override
  Stream<User?> get authStateChanges => _ctl.stream;
  @override
  User? get currentUser => _current;

  void restore(String uid) {
    _current = _AuthUser(uid);
    _ctl.add(_AuthUser(uid));
  }

  @override
  Future<UserModel?> signIn(String username, String password) async {
    _current = _AuthUser(username);
    _ctl.add(_AuthUser(username));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return _model(username);
  }

  @override
  Future<UserModel?> getUserData(String uid) async {
    final g = gates[uid];
    if (g != null) await g.future;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (failing.contains(uid)) throw Exception('unavailable');
    if (missing.contains(uid)) return null;
    return _model(uid, status: statusOf[uid] ?? 'active');
  }

  @override
  Future<DeletionRecoveryState> getDeletionRecoveryState() async =>
      DeletionRecoveryState.none;

  @override
  Future<void> signOut({bool showToast = true}) async {
    _current = null;
    _ctl.add(null);
  }
}

Future<void> _settle([int ms = 200]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final ch in ['plugins.flutter.io/firebase_messaging', 'dexterous.com/flutter/local_notifications']) {
      m.setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
  });

  UserProvider make(_GatedAuth a) {
    final p = UserProvider(authService: a)..initialize();
    addTearDown(p.dispose);
    return p;
  }

  test('AB-1 복원 로드가 걸린 사이 로그아웃 → 늦은 응답이 이전 사용자를 다시 세우지 않는다', () async {
    final a = _GatedAuth()..gates['wA'] = Completer<void>();
    final p = make(a);
    a.restore('wA'); // 앱 재시작 복원 — 사용자 문서 읽기가 걸려 있다
    await _settle(50);
    await p.signOut();
    a.gates['wA']!.complete(); // 이전 계정 응답이 이제 도착
    await _settle();
    expect(p.currentUser, isNull, reason: '로그아웃 뒤에는 아무도 아니다');
    expect(p.isLoggedIn, isFalse);
  });

  test('AB-2 A 로드가 걸린 사이 B 로그인 완료 → 늦은 A 응답이 B 를 덮지 않는다', () async {
    final a = _GatedAuth()..gates['wA'] = Completer<void>();
    final p = make(a);
    a.restore('wA');
    await _settle(50);
    await p.signOut();
    expect(await p.signIn('wB', 'ok'), isTrue);
    await _settle();
    expect(p.currentUser?.uid, 'wB');
    a.gates['wA']!.complete();
    await _settle();
    expect(p.currentUser?.uid, 'wB', reason: '늦게 온 A 응답은 버린다');
  });

  test('AB-3 같은 uid 새 세션 — 이전 세션 로드가 늦게 와도 새 세션 상태만 남는다', () async {
    final a = _GatedAuth()..gates['wS'] = Completer<void>();
    final p = make(a);
    a.restore('wS');
    await _settle(50);
    await p.signOut();
    a.gates.remove('wS')!.complete(); // 이전 세션 응답(같은 uid)
    expect(await p.signIn('wS', 'ok'), isTrue);
    await _settle();
    expect(p.currentUser?.uid, 'wS');
    expect(p.isLoading, isFalse);
  });

  test('AB-2b 늦게 실패한 A 로드(토큰 오류)가 B 세션을 로그아웃시키지 않는다', () async {
    final a = _GatedAuth()
      ..gates['wA'] = Completer<void>()
      ..failing.add('wA');
    final p = make(a);
    a.restore('wA');
    await _settle(50);
    await p.signOut();
    expect(await p.signIn('wB', 'ok'), isTrue);
    await _settle();
    a.gates['wA']!.complete(); // A 실패 응답이 이제 도착
    await _settle();
    expect(p.currentUser?.uid, 'wB');
    expect(p.isLoggedIn, isTrue);
    expect(p.error, isNull, reason: '낡은 실패를 새 세션의 오류로 보이지 않는다');
  });

  test('AB-4 사용자 문서 읽기 실패 → 로그인 상태로 들어가지 않고 다시 시도하면 들어간다', () async {
    final a = _GatedAuth()..failing.add('wF');
    final p = make(a);
    a.restore('wF');
    await _settle();
    expect(p.currentUser, isNull);
    expect(p.isLoggedIn, isFalse);
    a.failing.remove('wF');
    await p.refreshUserData();
    await _settle();
    expect(p.currentUser?.uid, 'wF');
  });

  test('AB-5 가입 미완료(registration_pending)·사용자 문서 없음 → 홈 진입 상태가 아니다', () async {
    final a = _GatedAuth()
      ..statusOf['wP'] = 'registration_pending'
      ..missing.add('wN');
    final p = make(a);
    a.restore('wP');
    await _settle();
    expect(p.currentUser, isNull, reason: '가입 미완료는 메인으로 가지 않는다');
    a.restore('wN');
    await _settle();
    expect(p.currentUser, isNull, reason: '문서 없는 세션은 정리된다');
    expect(p.isLoggedIn, isFalse);
  });
}
