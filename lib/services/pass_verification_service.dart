import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../utils/toast_helper.dart';

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
    // 릴리즈 빌드에서 throw가 아닌 graceful fallback — UnimplementedError 던지면 앱 크래시
    ToastHelper.showInfo('PASS 인증은 현재 준비 중입니다. 잠시 후 이용해주세요.');
    return null;
  }

  /// 비밀번호 찾기용 PASS 인증 후 Custom Token 발급
  ///
  /// [주의] 현재 LoginScreen은 이 메서드를 사용하지 않고 CF를 직접 호출함.
  /// 이 메서드는 향후 다른 진입점(예: 딥링크)에서 재사용을 위해 남겨둠.
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
      // debug 모드: CF 호출 없이 mock 토큰 반환
      // 실제 Firebase signInWithCustomToken에는 사용 불가 — UX 흐름 테스트용
      return 'mock-custom-token-for-debug';
    }

    // [TODO-DANAL] 실제 CF 호출
    try {
      final result = await _fn
          .httpsCallable('resetPasswordWithPass',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
          .call({'passToken': passToken, 'username': username});
      // result.data가 null이거나 키 없으면 예외 → 아래 catch에서 null 반환 처리
      return result.data['customToken'] as String?;
    } catch (e) {
      debugPrint('❌ [PassVerificationService] resetPasswordWithPass 실패: $e');
      return null;
    }
  }

  /// 가입 완료 후 passToken 소비 — [AUTH-H3] 15분 재사용 차단
  ///
  /// 가입 성공 직후 호출한다. 실패해도 가입 자체는 완료된 상태이므로 예외를 삼킨다.
  /// mock 토큰은 kDebugMode에서만 CF 호출 생략 — 릴리즈 빌드에서 'mock-' 접두어 우회 차단.
  static Future<void> finalizeRegistration(String passToken) async {
    if (kDebugMode) return;
    try {
      await _fn.httpsCallable('finalizeRegistration',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 10)))
          .call({'passToken': passToken});
    } catch (e) {
      debugPrint('⚠️ [PassVerificationService] finalizeRegistration 실패: $e');
      // best-effort — 가입 완료를 막지 않음. passToken은 15분 후 TTL로 자동 만료됨.
    }
  }

  // ── Mock (개발/테스트용) ─────────────────────────────────────────────────

  static final _rng = Random();

  static const _mockNames = [
    '김민준', '이서연', '박지호', '최수아', '정우진',
    '강하은', '조민서', '윤도현', '임채원', '한소율',
  ];

  /// 다날 계약 전 개발 테스트용 mock 데이터 — 매 호출마다 랜덤 값 반환
  static Future<PassAuthResult?> _mockAuthenticate({
    required String purpose,
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));

    final name = _mockNames[_rng.nextInt(_mockNames.length)];
    final gender = _rng.nextBool() ? '남성' : '여성';
    final year = 1975 + _rng.nextInt(25); // 1975~1999
    final month = 1 + _rng.nextInt(12);
    final day = 1 + _rng.nextInt(28);
    final mid = (1000 + _rng.nextInt(9000)).toString();
    final end = (1000 + _rng.nextInt(9000)).toString();
    final phone = '010$mid$end';

    return PassAuthResult(
      name: name,
      gender: gender,
      birthDate: DateTime(year, month, day),
      phone: phone,
      passToken: 'mock-pass-token-${DateTime.now().millisecondsSinceEpoch}',
    );
  }
}
