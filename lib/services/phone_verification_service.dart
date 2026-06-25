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

class PhoneVerificationService {
  final _auth = FirebaseAuth.instance;

  String? _verificationId;
  int? _resendToken;

  /// 한국 번호 → E.164 (+821012345678)
  String _toE164(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.startsWith('0') ? '+82${digits.substring(1)}' : '+82$digits';
  }

  /// SMS 인증번호 발송
  ///
  /// throws [FirebaseAuthException] — too-many-requests, invalid-phone-number 등
  Future<void> sendCode(String phone) async {
    final completer = Completer<void>();

    await _auth.verifyPhoneNumber(
      phoneNumber: _toE164(phone),
      timeout: const Duration(seconds: 60),
      forceResendingToken: _resendToken,
      verificationCompleted: (PhoneAuthCredential credential) {
        // Android 자동 SMS 인식 — 코드 입력 단계에서 별도 처리
        debugPrint('📱 [PhoneAuth] 자동 인증 감지');
      },
      verificationFailed: (FirebaseAuthException e) {
        debugPrint('❌ [PhoneAuth] 발송 실패: ${e.code}');
        if (!completer.isCompleted) completer.completeError(e);
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        debugPrint('📱 [PhoneAuth] SMS 발송 완료');
        if (!completer.isCompleted) completer.complete();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
        if (!completer.isCompleted) completer.complete();
      },
    );

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
    if (_verificationId == null) {
      return (valid: false, reason: 'no_code');
    }

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code.trim(),
      );

      if (_auth.currentUser != null) {
        // 이미 로그인된 상태 — linkWithCredential로 유효성만 검증 후 즉시 unlink
        // (signInWithCredential 사용 시 기존 세션이 파괴되므로 금지)
        try {
          await _auth.currentUser!.linkWithCredential(credential);
          // unlink 실패 시 재시도 — 실패해도 인증 결과는 유지하되 계정 오염 방지를 최우선
          try {
            await _auth.currentUser!.unlink(PhoneAuthProvider.PROVIDER_ID);
          } catch (unlinkErr) {
            debugPrint('⚠️ [PhoneAuth] unlink 1차 실패, 재시도: $unlinkErr');
            try {
              await _auth.currentUser!.unlink(PhoneAuthProvider.PROVIDER_ID);
            } catch (retryErr) {
              // [특이사항] unlink 2회 실패 → 계정에 전화번호 잔존. Firebase Console에서 수동 해제 필요.
              debugPrint('❌ [PhoneAuth] unlink 재시도 실패 — 계정 오염 가능성: $retryErr');
            }
          }
          debugPrint('✅ [PhoneAuth] 인증 성공 (link/unlink)');
          return (valid: true, reason: null);
        } on FirebaseAuthException catch (e) {
          debugPrint('❌ [PhoneAuth] 코드 오류 (link): ${e.code}');
          if (e.code == 'credential-already-in-use') {
            return (valid: false, reason: '이미 다른 계정에 등록된 번호입니다');
          }
          return switch (e.code) {
            'invalid-verification-code' => (valid: false, reason: 'wrong_code'),
            'session-expired'           => (valid: false, reason: 'expired'),
            'too-many-requests'         => (valid: false, reason: 'too_many_attempts'),
            'invalid-verification-id'   => (valid: false, reason: 'no_code'),
            _                           => (valid: false, reason: 'error'),
          };
        }
      } else {
        // 로그인 전 — 임시 로그인으로 코드 유효성 검증 후 삭제
        final result = await _auth.signInWithCredential(credential);
        debugPrint('✅ [PhoneAuth] 인증 성공');

        // 검증용 임시 계정 삭제 (Firebase Auth 세션 정리)
        // [특이사항] delete 실패 시 고아 계정이 잔존할 수 있음. 인증 결과는 유효하므로 로그만 남김.
        try {
          await result.user?.delete();
        } catch (deleteErr) {
          debugPrint('⚠️ [PhoneAuth] 임시 계정 삭제 실패 — 고아 계정 잔존 가능: $deleteErr');
        }

        return (valid: true, reason: null);
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ [PhoneAuth] 코드 오류: ${e.code}');
      return switch (e.code) {
        'invalid-verification-code' => (valid: false, reason: 'wrong_code'),
        'session-expired'           => (valid: false, reason: 'expired'),
        'too-many-requests'         => (valid: false, reason: 'too_many_attempts'),
        'invalid-verification-id'   => (valid: false, reason: 'no_code'),
        _                           => (valid: false, reason: 'error'),
      };
    } catch (e) {
      debugPrint('❌ [PhoneAuth] 검증 오류: $e');
      return (valid: false, reason: 'error');
    }
  }
}
