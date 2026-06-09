// lib/services/phone_verification_service.dart
//
// NCP SENS SMS 인증 서비스
//
// 🔧 연결 방법:
//   Cloud Functions에 환경변수 설정 후 자동 활성화됩니다.
//   SENS 미설정 시 Cloud Function 콘솔에 코드가 출력됩니다 (테스트용).
//
// 사용 예시:
//   final svc = PhoneVerificationService();
//   await svc.sendCode('01012345678');
//   final ok = await svc.verifyCode('01012345678', '123456');

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class PhoneVerificationService {
  final _region = FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// SMS 인증번호 발송
  ///
  /// throws [FirebaseFunctionsException] — 1분 내 재발송, 잘못된 번호 등
  Future<void> sendCode(String phone) async {
    final fn = _region.httpsCallable('sendSmsVerificationCode');
    await fn.call({'phone': phone.replaceAll('-', '')});
    debugPrint('📱 SMS 발송 요청: $phone');
  }

  /// 인증번호 확인
  ///
  /// 반환값:
  ///   `true`  — 인증 성공
  ///   `false` — 실패 (reason: wrong_code / expired / too_many_attempts / no_code)
  Future<({bool valid, String? reason})> verifyCode(
    String phone,
    String code,
  ) async {
    try {
      final fn = _region.httpsCallable('verifySmsCode');
      final result = await fn.call({
        'phone': phone.replaceAll('-', ''),
        'code': code.trim(),
      });
      final data = result.data as Map<String, dynamic>;
      final valid = data['valid'] == true;
      final reason = data['reason'] as String?;
      debugPrint('📱 SMS 검증: valid=$valid reason=$reason');
      return (valid: valid, reason: reason);
    } catch (e) {
      debugPrint('❌ SMS 검증 실패: $e');
      return (valid: false, reason: 'error');
    }
  }
}
