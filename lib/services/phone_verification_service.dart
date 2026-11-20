// lib/services/phone_verification_service.dart
//
// Firebase Phone Auth 기반 SMS 인증 서비스
//
// 🔧 사전 설정:
//   Firebase Console → Authentication → Sign-in method → 전화 (활성화)
//   Android: SHA-1 / SHA-256 지문 등록 필요 (google-services.json)
//   iOS: APNs 인증키 또는 APN 인증서 등록 필요
//
// 사용 예:
//   final svc = PhoneVerificationService();
//   await svc.sendCode('01012345678');
//   final result = await svc.verifyCode('01012345678', '123456');

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// [DU362] 더 새 발송이 시작되어 이 발송은 대체됐다(결과를 쓰지 않는다).
class PhoneSendSupersededException implements Exception {
  const PhoneSendSupersededException();
  @override
  String toString() => 'PhoneSendSupersededException';
}

class PhoneVerificationService {
  /// [DU362 seam] 시험이 SDK 콜백 순서를 정하도록 FirebaseAuth 를 주입할 수 있다(기본은 FirebaseAuth.instance — 운영 동작 같음).
  PhoneVerificationService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  String? _verificationId;
  int? _resendToken;

  /// [DU362] 발송 세대 · 지금 세대가 보낸 번호(E.164) · 지금 세대의 대기 중 발송.
  ///   이전 발송의 늦은 callback(codeSent · 시간 초과 · 실패)이 새 발송의 verificationId 를 덮거나 끝내지 못하게 한다
  ///   (A 발송 → B 발송 → 늦은 A 시간 초과가 확인 기준을 A 로 되돌리던 경로, 소급 11 · 12).
  int _sendGen = 0;
  String? _sentE164;
  Completer<void>? _pendingSend;

  /// 한국 번호 → E.164 (+821012345678)
  String _toE164(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.startsWith('0') ? '+82${digits.substring(1)}' : '+82$digits';
  }

  /// SMS 인증번호 발송
  ///
  /// throws [FirebaseAuthException] — too-many-requests, invalid-phone-number 등
  Future<void> sendCode(String phone) async {
    // [DU362] 새 세대 — 이전 발송은 대체된다(대기 중이면 대체 예외로 끝낸다), 이전 확인 기준 · 보낸 번호는 지운다.
    final gen = ++_sendGen;
    final e164 = _toE164(phone);
    final previous = _pendingSend;
    if (previous != null && !previous.isCompleted) {
      previous.completeError(const PhoneSendSupersededException());
    }
    _verificationId = null;
    _sentE164 = null;
    final completer = Completer<void>();
    // [DU367] 만들자마자 관찰한다 — 대체 · 실패로 끝나도 미처리 오류가 되지 않는다(오류는 아래 반환으로 호출자에게 그대로 간다).
    completer.future.ignore();
    _pendingSend = completer;
    bool current() => gen == _sendGen;

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: e164,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) {
          // Android 자동 SMS 인식 — 코드 입력 단계에서 별도 처리
          debugPrint('📱 [PhoneAuth] 자동 인증 감지');
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!current()) return; // [DU362] 대체된 발송의 늦은 실패는 쓰지 않는다
          debugPrint('❌ [PhoneAuth] 발송 실패: ${e.code}');
          if (!completer.isCompleted) completer.completeError(e);
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!current()) return; // [DU362] 대체된 발송의 늦은 codeSent 는 확인 기준을 덮지 않는다
          _verificationId = verificationId;
          _sentE164 = e164;
          _resendToken = resendToken;
          debugPrint('📱 [PhoneAuth] SMS 발송 완료');
          if (!completer.isCompleted) completer.complete();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!current()) return; // [DU362] 대체된 발송의 늦은 시간 초과는 확인 기준을 덮지 않는다
          _verificationId = verificationId;
          _sentE164 = e164;
          if (!completer.isCompleted) completer.complete();
        },
      );
    } catch (e, st) {
      // [DU367] SDK 등록 자체가 실패했다 — 자기 요청만 정리하고 그 오류로 끝낸다(다음 발송이 이 completer 를 다시 끝내지 않게).
      if (identical(_pendingSend, completer)) _pendingSend = null;
      if (!completer.isCompleted) completer.completeError(e, st);
    }

    return completer.future;
  }

  /// 인증번호 확인
  ///
  /// 반환값:
  ///   `true`  — 인증 성공
  ///   `false` — 실패 (reason: wrong_code / expired / too_many_attempts / no_code / error)
  Future<({bool valid, String? reason})> verifyCode(
    String phone,
    String code,
  ) async {
    // [DU362] 시작 때의 확인 기준 · 보낸 번호 · 세대를 잡는다 — 번호가 다르면 이 인증번호는 이 번호의 것이 아니다.
    final vid = _verificationId;
    final sent = _sentE164;
    final gen = _sendGen;
    if (vid == null || sent == null || _toE164(phone) != sent) {
      return (valid: false, reason: 'no_code');
    }
    // 확인 도중 새 발송이 시작되면 이 결과는 쓰지 않는다(이전 기준의 결과다).
    ({bool valid, String? reason}) settle(({bool valid, String? reason}) r) =>
        gen == _sendGen ? r : (valid: false, reason: 'no_code');

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: vid,
        smsCode: code.trim(),
      );

      if (_auth.currentUser != null) {
        // 스냅샷: linkWithCredential/unlink의 await 사이에 로그아웃 경쟁조건 방지
        final currentUser = _auth.currentUser!;
        // 이미 로그인된 상태 — linkWithCredential로 유효성만 검증 후 즉시 unlink
        // (signInWithCredential 사용 시 기존 세션이 파괴되므로 금지)
        try {
          await currentUser.linkWithCredential(credential);
          // unlink 실패 시 재시도 — 실패해도 인증 결과는 유지하되 계정 오염 방지를 최우선
          try {
            await currentUser.unlink(PhoneAuthProvider.PROVIDER_ID);
          } catch (unlinkErr) {
            debugPrint('⚠️ [PhoneAuth] unlink 1차 실패, 재시도: $unlinkErr');
            try {
              await currentUser.unlink(PhoneAuthProvider.PROVIDER_ID);
            } catch (retryErr) {
              // unlink 2회 실패 → 계정에 전화번호 잔존. Firebase Console에서 수동 해제 필요.
              debugPrint('❌ [PhoneAuth] unlink 재시도 실패 — 계정 오염 가능성: $retryErr');
            }
          }
          debugPrint('✅ [PhoneAuth] 인증 성공 (link/unlink)');
          return settle((valid: true, reason: null));
        } on FirebaseAuthException catch (e) {
          debugPrint('❌ [PhoneAuth] 코드 오류 (link): ${e.code}');
          // [DU367] 오류 반환도 세대 판정 — 대체된 확인이면 no_code
          if (e.code == 'credential-already-in-use') {
            return settle((valid: false, reason: '이미 다른 계정에 등록된 번호입니다'));
          }
          return settle(switch (e.code) {
            'invalid-verification-code' => (valid: false, reason: 'wrong_code'),
            'session-expired'           => (valid: false, reason: 'expired'),
            'too-many-requests'         => (valid: false, reason: 'too_many_attempts'),
            'invalid-verification-id'   => (valid: false, reason: 'no_code'),
            _                           => (valid: false, reason: 'error'),
          });
        }
      } else {
        // 로그인 전 — 임시 로그인으로 코드 유효성 검증 후 삭제
        final result = await _auth.signInWithCredential(credential);
        debugPrint('✅ [PhoneAuth] 인증 성공');

        // 검증용 임시 계정 삭제 (Firebase Auth 세션 정리)
        // [AUTH-M3] 삭제 실패 시 최대 2회 재시도 — 고아 계정 잔존 최소화
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            await result.user?.delete();
            break;
          } catch (deleteErr) {
            if (attempt == 2) {
              debugPrint('⚠️ [PhoneAuth] 임시 계정 삭제 최종 실패 (3회) — 고아 계정 잔존 가능: $deleteErr');
            } else {
              debugPrint('⚠️ [PhoneAuth] 임시 계정 삭제 실패 (${attempt + 1}회), 재시도: $deleteErr');
              await Future.delayed(const Duration(milliseconds: 500));
            }
          }
        }

        return settle((valid: true, reason: null));
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ [PhoneAuth] 코드 오류: ${e.code}');
      return settle(switch (e.code) {
        'invalid-verification-code' => (valid: false, reason: 'wrong_code'),
        'session-expired'           => (valid: false, reason: 'expired'),
        'too-many-requests'         => (valid: false, reason: 'too_many_attempts'),
        'invalid-verification-id'   => (valid: false, reason: 'no_code'),
        _                           => (valid: false, reason: 'error'),
      });
    } catch (e) {
      debugPrint('❌ [PhoneAuth] 검증 오류: $e');
      return settle((valid: false, reason: 'error'));
    }
  }
}
