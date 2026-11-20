// [LOGIN-INIT-SINGLE] 로그인 버튼 한 번에 _loadUserData 가 두 번 돌았다.
//
// ── 대조 (CODE + LOCAL 로그) ─────────────────────────────────────────
//   FirebaseAuth 로그인이 끝나면 authStateChanges 가 발화해 리스너가 _loadUserData 를 시작한다(세대 1).
//   auth_service.signIn 은 사용자 문서를 따로 읽어 차단·가입 상태·제재를 확인하고 돌아온다.
//   그 뒤 UserProvider.signIn 이 _loadUserData 를 **또** 시작했다(세대 2) — 사용자 문서·미서명 계약·
//   FCM 초기화 시도가 한 벌 더 나가고, 세대 1의 결과는 버려졌다.
//
// ── 바꾼 것 ──────────────────────────────────────────────────────────
//   로그인 중(_isSigningIn) 리스너가 시작한 같은 사용자의 로드에 signIn 이 합류한다.
//   그 사이 다른 로드·로그아웃이 있었거나 uid 가 다르면 합류하지 않는다(예전처럼 새로 읽는다).
//   합류한 로드가 사용자를 세우지 못했으면(읽기 실패) 한 번 더 읽는다 — 예전의 재시도 기회 유지.
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

UserModel _model(String uid, {UserRole role = UserRole.USER}) => UserModel(
      uid: uid, username: uid, name: '합성 $uid', email: '$uid@alfit.local',
      role: role, accountStatus: 'active',
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
    );

/// 인증 대역 — 로그인하면 실제 SDK 처럼 authStateChanges 를 먼저 발화하고, 사용자 문서를 읽어 확인한 뒤 돌아온다.
class _FakeAuth extends Fake implements AuthService {
  final _ctl = StreamController<User?>.broadcast();
  int getUserDataCalls = 0;
  int failUserDataTimes = 0;
  Completer<void>? checksGate; // signIn 의 확인 단계를 붙잡는 문
  bool emitAfterChecks = false; // 리스너 이벤트가 늦게 오는 경우
  String? listenerUid; // 리스너에 다른 uid 를 보내는 경우
  User? _current;

  @override
  Stream<User?> get authStateChanges => _ctl.stream;
  @override
  User? get currentUser => _current;

  @override
  Future<UserModel?> signIn(String username, String password) async {
    if (password != 'ok') throw Exception('아이디 또는 비밀번호가 올바르지 않습니다.');
    _current = _AuthUser(username);
    if (!emitAfterChecks) _ctl.add(_AuthUser(listenerUid ?? username));
    await Future<void>.delayed(const Duration(milliseconds: 30)); // 문서 읽기·확인
    if (checksGate != null) await checksGate!.future;
    if (emitAfterChecks) {
      _ctl.add(_AuthUser(username));
      await Future<void>.delayed(Duration.zero);
    }
    return _model(username);
  }

  @override
  Future<UserModel?> getUserData(String uid) async {
    getUserDataCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (failUserDataTimes > 0) {
      failUserDataTimes--;
      throw Exception('unavailable');
    }
    return _model(uid, role: UserRole.BUSINESS_ADMIN); // 관리자 경로 — FCM 만 타고 끝난다
  }

  @override
  Future<void> signOut({bool showToast = true}) async {
    _current = null;
    _ctl.add(null);
  }
}

Future<void> _settle([int ms = 400]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // FCM·알림 플러그인은 응답하지 않는다(초기화 실패는 로드 안에서 잡힌다).
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final ch in ['plugins.flutter.io/firebase_messaging', 'dexterous.com/flutter/local_notifications']) {
      m.setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
  });

  UserProvider make(_FakeAuth a) {
    final p = UserProvider(authService: a)..initialize();
    addTearDown(p.dispose);
    return p;
  }

  test('LI-1 로그인 한 번 = 사용자 로드 한 번(리스너 로드에 합류) — 사용자·로그인 결과 동일', () async {
    final a = _FakeAuth();
    final p = make(a);
    final ok = await p.signIn('w1', 'ok');
    await _settle();
    expect(ok, isTrue);
    expect(a.getUserDataCalls, 1, reason: '예전에는 2(리스너 + signIn)');
    expect(p.currentUser?.uid, 'w1');
    expect(p.isLoading, isFalse);
  });

  test('LI-2 합류한 로드가 읽기 실패 → 한 번 더 읽어 회복(실패 고정 없음)', () async {
    final a = _FakeAuth()..failUserDataTimes = 1;
    final p = make(a);
    final ok = await p.signIn('w2', 'ok');
    await _settle();
    expect(ok, isTrue);
    expect(a.getUserDataCalls, 2);
    expect(p.currentUser?.uid, 'w2');
  });

  test('LI-3 비밀번호 오류 → 다시 시도 → 정상 진입(남은 합류 상태 없음)', () async {
    final a = _FakeAuth();
    final p = make(a);
    expect(await p.signIn('w3', 'bad'), isFalse);
    expect(p.currentUser, isNull);
    expect(await p.signIn('w3', 'ok'), isTrue);
    await _settle();
    expect(a.getUserDataCalls, 1);
    expect(p.currentUser?.uid, 'w3');
  });

  test('LI-4 리스너 이벤트가 확인 뒤에 오면 합류하지 않는다(예전과 같은 독립 로드)', () async {
    final a = _FakeAuth()..emitAfterChecks = true;
    final p = make(a);
    expect(await p.signIn('w4', 'ok'), isTrue);
    await _settle();
    expect(p.currentUser?.uid, 'w4');
    expect(a.getUserDataCalls, greaterThanOrEqualTo(1));
  });

  test('LI-5 리스너 uid 와 로그인 uid 가 다르면 합류하지 않는다', () async {
    final a = _FakeAuth()..listenerUid = 'other';
    final p = make(a);
    expect(await p.signIn('w5', 'ok'), isTrue);
    await _settle();
    expect(a.getUserDataCalls, 2);
    expect(p.currentUser?.uid, 'w5', reason: '마지막(로그인한) 사용자가 남는다');
  });

  test('LI-6 확인 중 로그아웃 — 로그아웃 전 로드에 합류하지 않는다', () async {
    final a = _FakeAuth()..checksGate = Completer<void>();
    final p = make(a);
    final f = p.signIn('w6', 'ok');
    await _settle(100);
    await p.signOut();
    a.checksGate!.complete();
    await f;
    await _settle();
    expect(a.getUserDataCalls, 2, reason: '합류하지 않고 새로 읽는다(예전 동작)');
  });

  test('LI-7 로그인 뒤 명시적 새로고침은 합류하지 않고 새로 읽는다', () async {
    final a = _FakeAuth();
    final p = make(a);
    await p.signIn('w7', 'ok');
    await _settle();
    final before = a.getUserDataCalls;
    await p.refreshUserData();
    expect(a.getUserDataCalls, before + 1);
  });

  test('LI-8 자동 세션 복원(로그인 버튼 없음)은 리스너 로드 하나 — 합류 상태를 남기지 않는다', () async {
    final a = _FakeAuth();
    final p = make(a);
    a._current = _AuthUser('w8');
    a._ctl.add(_AuthUser('w8'));
    await _settle();
    expect(a.getUserDataCalls, 1);
    expect(p.currentUser?.uid, 'w8');
    // 이후 다른 계정 로그인은 복원 로드에 합류하지 않는다(uid·세대가 다르다)
    expect(await p.signIn('w9', 'ok'), isTrue);
    await _settle();
    expect(p.currentUser?.uid, 'w9');
  });
}
