import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// PASS 본인인증 결과 데이터
class PassAuthResult {
  final String name;
  final String gender;       // '남성' | '여성'
  final DateTime birthDate;
  final String phone;
  final String passToken;    // 15분 유효, 가입/비밀번호 찾기 시 CF로 전달

  const PassAuthResult({
    required this.name,
    required this.gender,
    required this.birthDate,
    required this.phone,
    required this.passToken,
  });
}

/// PASS 본인인증 서비스
///
/// [TODO-DANAL] kDebugMode에서는 mock 데이터를 반환합니다.
/// 다날 계약 완료 후 아래 단계로 실제 연결:
///   1. initiatePassAuth CF에서 다날 txSeq + authUrl 수신
///   2. WebView로 authUrl 오픈
///   3. 인증 완료 후 encData 수신
///   4. verifyPassAuth CF로 복호화 + CI 검증
class PassVerificationService {
  static final _fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// PASS 인증 실행
  ///
  /// [purpose]: 'register' (가입) | 'resetPassword' (비밀번호 찾기)
  /// [role]: 'USER' | 'BUSINESS_ADMIN' (가입 시 중복 체크에 사용)
  ///
  /// 반환값이 null이면 사용자가 인증을 취소한 것입니다.
  static Future<PassAuthResult?> authenticate({
    required String purpose,
    String role = 'USER',
  }) async {
    if (kDebugMode) {
      return _mockAuthenticate(purpose: purpose);
    }

    // [TODO-DANAL] 실제 다날 WebView 인증 흐름
    // 1. CF initiatePassAuth 호출 → txSeq + authUrl 수신
    // 2. PassAuthWebViewPage 열기 (WebView)
    // 3. 인증 완료 콜백에서 encData 수신
    // 4. CF verifyPassAuth 호출 → PassAuthResult 반환
    throw UnimplementedError('다날 계약 완료 후 구현 예정 [TODO-DANAL]');
  }

  /// 비밀번호 찾기용 PASS 인증 후 Custom Token 발급
  ///
  /// [passToken]: authenticate()에서 받은 토큰
  /// [username]: 비밀번호를 찾을 계정 아이디
  ///
  /// 반환값: Firebase Custom Token (앱에서 signInWithCustomToken 사용)
  static Future<String?> getPasswordResetToken({
    required String passToken,
    required String username,
  }) async {
    if (kDebugMode) {
      return 'mock-custom-token-for-debug';
    }

    // [TODO-DANAL] 실제 CF 호출
    try {
      final result = await _fn
          .httpsCallable('resetPasswordWithPass')
          .call({'passToken': passToken, 'username': username});
      return result.data['customToken'] as String?;
    } catch (e) {
      debugPrint('❌ [PassVerificationService] resetPasswordWithPass 실패: $e');
      return null;
    }
  }

  // ── Mock (개발/테스트용) ─────────────────────────────────────────────────

  /// 다날 계약 전 개발 테스트용 mock 데이터
  /// kDebugMode에서만 사용됩니다.
  static Future<PassAuthResult?> _mockAuthenticate({
    required String purpose,
  }) async {
    // 실제 네트워크 딜레이 시뮬레이션
    await Future.delayed(const Duration(milliseconds: 800));

    return PassAuthResult(
      name: '홍길동',
      gender: '남성',
      birthDate: DateTime(1990, 1, 15),
      phone: '01012345678',
      passToken: 'mock-pass-token-${DateTime.now().millisecondsSinceEpoch}',
    );
  }
}
