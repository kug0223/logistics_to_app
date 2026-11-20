// [DU362] P1 휴대폰 서비스 callback 세대 guard(소급 12 §2-1) — 합성 FirebaseAuth 로 SDK 콜백 순서를 정한다(생성기 work/du362-phone-service-gen/mk.py).
//   사례: 정상 · 늦은 이전 시간 초과 · 늦은 이전 codeSent · 번호 불일치 확인 · 확인 중 새 발송 · 대체된 발송 Future.
//   흐름(항상): 정상 확인 성공 · 새 번호 정상 확인 성공. 제품 기대(기본 단언, DU_BEFORE_OBSERVE=362 면 기록만): 이전 발송의 인증번호로 새 번호가 인증되지 않는다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/services/phone_verification_service.dart';

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '362';

typedef _Call = ({String phone, PhoneCodeSent codeSent, PhoneCodeAutoRetrievalTimeout timeout, PhoneVerificationFailed failed});

class _Cred extends Fake implements UserCredential {
  @override
  User? get user => null;
}

class _FakeAuth extends Fake implements FirebaseAuth {
  final calls = <_Call>[];
  final codes = <String, String>{}; // verificationId → 인증번호
  Completer<void>? holdSignIn;
  @override
  User? get currentUser => null;
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
const _b = '01033334444';

void main() {
  final prod = <String, bool>{};
  tearDownAll(() {
    // ignore: avoid_print
    print('DU362 prod=$prod beforeObs=$_beforeObs');
    // ignore: avoid_print
    print('KNOWN ${prod.values.every((v) => v) ? 'ok' : 'NG'} DU362 서비스 세대 guard');
  });

  void check(String k, bool v) {
    prod[k] = v;
    if (!_beforeObs) expect(v, isTrue, reason: k);
  }

  test('G-1 정상: A 발송 → codeSent → A 인증번호로 확인 성공(흐름)', () async {
    final auth = _FakeAuth();
    final svc = PhoneVerificationService(auth: auth);
    final f = svc.sendCode(_a);
    await Future<void>.delayed(Duration.zero);
    auth.calls[0].codeSent('vA', 1);
    await f;
    auth.codes['vA'] = '111111';
    expect((await svc.verifyCode(_a, '111111')).valid, isTrue);
    expect((await svc.verifyCode(_a, '999999')).valid, isFalse);
  });

  test('G-2 늦은 이전 시간 초과: A → B 발송 뒤 A timeout 이 늦게 와도 A 인증번호로 B 인증 안 됨', () async {
    final auth = _FakeAuth();
    final svc = PhoneVerificationService(auth: auth);
    final fa = svc.sendCode(_a);
    await Future<void>.delayed(Duration.zero);
    auth.calls[0].codeSent('vA', 1);
    await fa;
    final fb = svc.sendCode(_b);
    await Future<void>.delayed(Duration.zero);
    auth.calls[1].codeSent('vB', 2);
    await fb;
    auth.calls[0].timeout('vA'); // 늦은 A 시간 초과
    auth.codes['vA'] = '111111';
    auth.codes['vB'] = '222222';
    final stale = await svc.verifyCode(_b, '111111');
    // ignore: avoid_print
    print('G-2 stale=${stale.valid}/${stale.reason}');
    check('G-2 늦은 A 시간 초과 뒤 A 인증번호로 B 인증 안 됨', !stale.valid);
    final fresh = await svc.verifyCode(_b, '222222');
    // ignore: avoid_print
    print('G-2 fresh=${fresh.valid}/${fresh.reason}');
    check('G-2 B 인증번호로 B 인증 성공', fresh.valid);
  });

  test('G-3 늦은 이전 codeSent: A 응답 전 B 발송 → B codeSent → A codeSent 늦게 와도 기준은 B · A Future 는 대체', () async {
    final auth = _FakeAuth();
    final svc = PhoneVerificationService(auth: auth);
    Object? aOutcome;
    final fa = svc.sendCode(_a).then<void>((_) { aOutcome = 'done'; }, onError: (Object e) { aOutcome = e; }); // [수리 1/3] 오류 처리기 반환형
    await Future<void>.delayed(Duration.zero);
    final fb = svc.sendCode(_b);
    await Future<void>.delayed(Duration.zero);
    auth.calls[1].codeSent('vB', 2);
    await fb;
    auth.calls[0].codeSent('vA', 1); // 늦은 A
    await Future<void>.delayed(Duration.zero);
    auth.codes['vA'] = '111111';
    auth.codes['vB'] = '222222';
    final stale = await svc.verifyCode(_b, '111111');
    final fresh = await svc.verifyCode(_b, '222222');
    await Future<void>.delayed(Duration.zero);
    // ignore: avoid_print
    print('G-3 stale=${stale.valid} fresh=${fresh.valid} aOutcome=$aOutcome');
    check('G-3 늦은 A codeSent 뒤 A 인증번호로 B 인증 안 됨', !stale.valid);
    check('G-3 B 인증 성공', fresh.valid);
    check('G-3 대체된 A 발송 Future 는 대체 예외로 끝남', '$aOutcome' == 'PhoneSendSupersededException'); // before(seam)에는 이 형이 없어 문자열로 본다
    unawaited(fa);
  });

  test('G-4 번호 불일치 확인: A 로 보낸 인증번호를 B 번호로 확인하면 실패', () async {
    final auth = _FakeAuth();
    final svc = PhoneVerificationService(auth: auth);
    final f = svc.sendCode(_a);
    await Future<void>.delayed(Duration.zero);
    auth.calls[0].codeSent('vA', 1);
    await f;
    auth.codes['vA'] = '111111';
    final r = await svc.verifyCode(_b, '111111');
    // ignore: avoid_print
    print('G-4 r=${r.valid}/${r.reason}');
    check('G-4 B 번호로 A 인증번호 확인 실패(no_code)', !r.valid && r.reason == 'no_code');
  });

  test('G-5 확인 중 새 발송: 이전 기준 확인 결과는 쓰지 않는다', () async {
    final auth = _FakeAuth();
    final svc = PhoneVerificationService(auth: auth);
    final f = svc.sendCode(_a);
    await Future<void>.delayed(Duration.zero);
    auth.calls[0].codeSent('vA', 1);
    await f;
    auth.codes['vA'] = '111111';
    auth.holdSignIn = Completer<void>();
    final rv = svc.verifyCode(_a, '111111');
    await Future<void>.delayed(Duration.zero);
    unawaited(svc.sendCode(_a).catchError((_) {})); // 같은 번호 재발송(새 세대)
    await Future<void>.delayed(Duration.zero);
    auth.holdSignIn!.complete();
    final r = await rv;
    // ignore: avoid_print
    print('G-5 r=${r.valid}/${r.reason}');
    check('G-5 확인 중 새 발송 → 이전 결과 무효', !r.valid);
  });
}
