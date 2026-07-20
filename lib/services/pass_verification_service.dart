import 'dart:async';
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../utils/toast_helper.dart';

// TODO: 다날 계약 완료 후 아래 주석 해제 + pubspec.yaml에 iamport_flutter 추가
// import 'package:iamport_flutter/iamport_flutter.dart';
// import 'package:iamport_flutter/model/certification_data.dart';
// import '../utils/navigation_key.dart';

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

/// PASS 본인인증 서비스 — PortOne(포트원) SDK 기반
///
/// [kDebugMode]에서는 mock 데이터를 반환합니다.
/// 운영 환경에서는 iamport_flutter → verifyPassAuth CF → passToken 흐름으로 처리됩니다.
class PassVerificationService {
  static final _fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// PortOne 가맹점 식별코드 (포트원 콘솔 > 내 식별코드·API Keys)
  /// 계약 후 실제 코드로 교체 필요
  // ignore: unused_field
  static const _portoneUserCode = 'imp00000000';

  /// PASS 인증 실행
  ///
  /// [purpose]: 'register' (가입) | 'resetPassword' (비밀번호 찾기)
  /// [role]: 'USER' | 'BUSINESS_ADMIN' (가입 시 중복 체크에 사용)
  ///
  /// 반환값이 null이면 사용자가 인증을 취소하거나 오류가 발생한 것입니다.
  static Future<PassAuthResult?> authenticate({
    required String purpose,
    String role = 'USER',
  }) async {
    if (kDebugMode) {
      return _mockAuthenticate(purpose: purpose);
    }

    // TODO: 다날 계약 완료 후 아래 PortOne SDK 연동 코드로 교체
    // 현재 iamport_flutter 패키지가 주석 처리되어 있으므로 운영 인증 불가
    ToastHelper.showError('본인인증은 서비스 준비 중입니다.');
    return null;

    // ── 계약 후 교체할 코드 (참고용) ──────────────────────────────────────
    // final completer = Completer<PassAuthResult?>();
    // final merchantUid = 'cert_${DateTime.now().millisecondsSinceEpoch}';
    // IamportCertification.certification(
    //   navigatorKey,
    //   userCode: _portoneUserCode,
    //   data: CertificationData(pg: 'danal', merchantUid: merchantUid, name: '', phone: '', minAge: 19),
    //   callback: (IamportResponse response) async { ... },
    // );
    // return completer.future;
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

    try {
      final result = await _fn
          .httpsCallable(
            'resetPasswordWithPass',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
          )
          .call({'passToken': passToken, 'username': username});
      return result.data['customToken'] as String?;
    } catch (e) {
      debugPrint('❌ [PassVerificationService] resetPasswordWithPass 실패: $e');
      return null;
    }
  }

  /// 가입 완료 후 passToken 소비 + ciHash 저장 — [AUTH-H3] 15분 재사용 차단
  ///
  /// 가입 성공 직후 호출한다. 실패해도 가입 자체는 완료된 상태이므로 예외를 삼킨다.
  static Future<void> finalizeRegistration(String passToken) async {
    try {
      await _fn
          .httpsCallable(
            'finalizeRegistration',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
          )
          .call({'passToken': passToken});
    } catch (e) {
      debugPrint('⚠️ [PassVerificationService] finalizeRegistration 실패: $e');
      // best-effort — 가입 완료를 막지 않음. passToken은 15분 후 TTL로 자동 만료됨.
    }
  }

  // ── 유틸 ───────────────────────────────────────────────────────────────────

  /// YYYYMMDD → DateTime 변환 (포트원 계약 후 authenticate()에서 사용)
  // ignore: unused_element
  static DateTime _parseBirthDate(String yyyymmdd) {
    final y = int.parse(yyyymmdd.substring(0, 4));
    final m = int.parse(yyyymmdd.substring(4, 6));
    final d = int.parse(yyyymmdd.substring(6, 8));
    return DateTime(y, m, d);
  }

  // ── Mock (개발/테스트용) ───────────────────────────────────────────────────

  static final _rng = Random();

  static const _mockNames = [
    '김민준', '이서연', '박지호', '최수아', '정우진',
    '강하은', '조민서', '윤도현', '임채원', '한소율',
  ];

  /// 포트원 계약 전 개발 테스트용 mock 데이터 — 매 호출마다 랜덤 값 반환
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
