// [DU367] DU362 P2(소급 13 §2) — 합성 FirebaseAuth/User 로 오류 반환 세대 판정 · 발송 Future 수명 · 로그인 상태 link 경로(생성기 work/du367-phone-p2/mk.py).
//   미처리 비동기 오류는 runZonedGuarded 로 모아 센다. DU_BEFORE_OBSERVE=367 이면 제품 기대는 기록만.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/services/phone_verification_service.dart';

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '367';

typedef _Call = ({String phone, PhoneCodeSent codeSent, PhoneCodeAutoRetrievalTimeout timeout, PhoneVerificationFailed failed});

class _Cred extends Fake implements UserCredential {
  @override
  User? get user => null;
}

class _User extends Fake implements User {
  _User(this.auth);
  final _FakeAuth auth;
  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    final h = auth.holdSignIn;
    if (h != null) await h.future;
    final c = credential as PhoneAuthCredential;
    if (auth.codes[c.verificationId] != null && auth.codes[c.verificationId] == c.smsCode) return _Cred();
    throw FirebaseAuthException(code: 'invalid-verification-code');
  }

  @override
  Future<User> unlink(String providerId) async => this;
}

class _FakeAuth extends Fake implements FirebaseAuth {
  final calls = <_Call>[];
  final codes = <String, String>{};
  Completer<void>? holdSignIn;
  Completer<void>? holdRegister;
  Object? registerError;
  bool loggedIn = false;
  @override
  User? get currentUser => loggedIn ? _User(this) : null;
  @override
  Future<void> verifyPhoneNumber({
    String? phoneNumber,
    PhoneMultiFactorInfo? multiFactorInfo,
    required PhoneVerificationCompleted verificationCompleted,
    required PhoneVerificationFailed verificationFailed,
    required PhoneCodeSent codeSent,
    required PhoneCodeAutoRetrievalTimeout codeAutoRetrievalTimeout,
    String? autoRetrievedSmsCodeForTesting,
    Duration timeout = const Duration(seconds: 30),
    int? forceResendingToken,
    MultiFactorSession? multiFactorSession,
  }) async {
    final hr = holdRegister;
    if (hr != null) await hr.future;
    final err = registerError;
    if (err != null) {
      registerError = null;
      throw err;
    }
    calls.add((phone: phoneNumber!, codeSent: codeSent, timeout: codeAutoRetrievalTimeout, failed: verificationFailed));
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    final h = holdSignIn;
    if (h != null) await h.future;
    final c = credential as PhoneAuthCredential;
    if (codes[c.verificationId] != null && codes[c.verificationId] == c.smsCode) return _Cred();
    throw FirebaseAuthException(code: 'invalid-verification-code');
  }
}

const _a = '01011112222';

Future<List<Object>> _guarded(Future<void> Function() body) async {
  final unhandled = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(() async {
    try {
      await body();
    } finally {
      if (!done.isCompleted) done.complete();
    }
  }, (e, st) {
    unhandled.add(e);
    if (!done.isCompleted) done.complete();
  });
  await done.future;
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return unhandled;
}

void main() {
  final prod = <String, bool>{};
  tearDownAll(() {
    // ignore: avoid_print
    print('DU367 prod=$prod beforeObs=$_beforeObs');
    // ignore: avoid_print
    print('KNOWN ${prod.values.every((v) => v) ? 'ok' : 'NG'} DU367 서비스 P2');
  });
  void check(String k, bool v) {
    prod[k] = v;
    if (!_beforeObs) expect(v, isTrue, reason: k);
  }

  test('P-1 대체된 확인의 늦은 오류 → no_code(로그아웃 경로)', () async {
    final auth = _FakeAuth();
    final svc = PhoneVerificationService(auth: auth);
    final f = svc.sendCode(_a);
    await Future<void>.delayed(Duration.zero);
    auth.calls[0].codeSent('vA', 1);
    await f;
    auth.codes['vA'] = '111111';
    auth.holdSignIn = Completer<void>();
    final rv = svc.verifyCode(_a, '999999'); // 틀린 번호 — 늦게 오류
    await Future<void>.delayed(Duration.zero);
    unawaited(svc.sendCode(_a).catchError((_) {}));
    await Future<void>.delayed(Duration.zero);
    auth.holdSignIn!.complete();
    final r = await rv;
    // ignore: avoid_print
    print('P-1 r=${r.valid}/${r.reason}');
    check('P-1 대체된 확인 늦은 오류 = no_code', !r.valid && r.reason == 'no_code');
  });

  test('P-2 SDK 등록 직접 실패 → 오류 전달 · 재시도에 미처리 오류 없음', () async {
    final auth = _FakeAuth()..registerError = FirebaseAuthException(code: 'too-many-requests');
    final svc = PhoneVerificationService(auth: auth);
    Object? first;
    final unhandled = await _guarded(() async {
      try {
        await svc.sendCode(_a);
      } catch (e) {
        first = e;
      }
      final f2 = svc.sendCode(_a); // 재시도
      await Future<void>.delayed(Duration.zero);
      auth.calls.last.codeSent('vA2', 2);
      await f2;
    });
    // ignore: avoid_print
    print('P-2 first=$first unhandled=$unhandled');
    check('P-2 첫 발송 SDK 오류가 호출자에게 전달', first is FirebaseAuthException);
    check('P-2 재시도에 미처리 오류 0', unhandled.isEmpty);
  });

  test('P-3 등록 대기 중 대체 → 이전 발송은 대체 예외로 관찰 · 미처리 오류 없음', () async {
    final auth = _FakeAuth()..holdRegister = Completer<void>();
    final svc = PhoneVerificationService(auth: auth);
    Object? firstOutcome;
    final unhandled = await _guarded(() async {
      final f1 = svc.sendCode(_a).then<void>((_) {
        firstOutcome = 'done';
      }, onError: (Object e) {
        firstOutcome = e;
      });
      await Future<void>.delayed(Duration.zero);
      final h = auth.holdRegister!;
      auth.holdRegister = null;
      final f2 = svc.sendCode(_a);
      await Future<void>.delayed(Duration.zero);
      h.complete();
      await Future<void>.delayed(Duration.zero);
      // [수리 1/3] 대기 없는 두 번째 발송이 먼저 등록된다(calls.first) — 그 발송의 codeSent 를 부른다
      auth.calls.first.codeSent('vB', 2);
      await f2;
      await f1;
    });
    // ignore: avoid_print
    print('P-3 first=$firstOutcome unhandled=$unhandled');
    check('P-3 이전 발송 = 대체 예외', '$firstOutcome' == 'PhoneSendSupersededException');
    check('P-3 미처리 오류 0', unhandled.isEmpty);
  });

  test('P-4 로그인 상태 link: 정상 성공 · 대체된 확인 늦은 오류 → no_code', () async {
    final auth = _FakeAuth()..loggedIn = true;
    final svc = PhoneVerificationService(auth: auth);
    final f = svc.sendCode(_a);
    await Future<void>.delayed(Duration.zero);
    auth.calls[0].codeSent('vA', 1);
    await f;
    auth.codes['vA'] = '111111';
    final ok = await svc.verifyCode(_a, '111111');
    auth.holdSignIn = Completer<void>();
    final rv = svc.verifyCode(_a, '999999');
    await Future<void>.delayed(Duration.zero);
    unawaited(svc.sendCode(_a).catchError((_) {}));
    await Future<void>.delayed(Duration.zero);
    auth.holdSignIn!.complete();
    final r = await rv;
    // ignore: avoid_print
    print('P-4 ok=${ok.valid} late=${r.valid}/${r.reason}');
    expect(ok.valid, isTrue, reason: 'P-4 로그인 상태 정상 link 성공(흐름)');
    check('P-4 로그인 상태 대체된 확인 늦은 오류 = no_code', !r.valid && r.reason == 'no_code');
  });
}
