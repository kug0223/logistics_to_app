// lib/services/auth/kakao_auth_service.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · impl_plan §4.1/§4.2] 로그인 수단 추상 1 칸 + 카카오 구현.
//
//   앱은 카카오 **액세스 토큰만** 서버(callableAuthKakao)에 넘긴다. 서버가 토큰 정보를 직접 조회해
//   app_id · 만료 · 회원번호(subject)를 뽑는다(B277-02). 앱이 회원번호·uid·역할을 권위값으로 보내지 않는다.
//   동의항목(scope)은 요청하지 않는다(회원번호만 · X3/X6).
//
//   네이티브 앱 키(공개 성격)는 `lib/config/kakao_config.dart` 에 있고, dart-define `KAKAO_NATIVE_APP_KEY` 가 있으면
//   그 값이 우선한다. Android 리다이렉트 scheme(kakao{키})은 `res/values/kakao_config.xml` — 두 곳은 같은 값이다.
//   키가 비면 [isConfigured] = false → 시작 화면이 '카카오 로그인 준비 중'. build.gradle.kts 는 건드리지 않는다.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import '../../config/kakao_config.dart';
import '../auth_service.dart';

/// 로그인 수단. 이메일은 후속(§7) — 같은 서버 연결 구조(authLinks)를 쓴다.
enum LoginProviderKind { kakao, email }

extension LoginProviderKindName on LoginProviderKind {
  String get wireName => this == LoginProviderKind.kakao ? 'kakao' : 'email';
}

enum ProviderLoginStatus {
  /// 토큰을 받았다(아직 서버 확인 전).
  success,

  /// 사용자가 닫았다.
  canceled,

  /// 앱 키가 없다 — 준비 중.
  notConfigured,

  /// 그 밖의 실패.
  failed,
}

class ProviderLoginResult {
  const ProviderLoginResult._(this.status, {this.accessToken, this.message});
  const ProviderLoginResult.success(String token)
      : this._(ProviderLoginStatus.success, accessToken: token);
  const ProviderLoginResult.canceled() : this._(ProviderLoginStatus.canceled);
  const ProviderLoginResult.notConfigured()
      : this._(ProviderLoginStatus.notConfigured);
  const ProviderLoginResult.failed([String? message])
      : this._(ProviderLoginStatus.failed, message: message);

  final ProviderLoginStatus status;

  /// 서버로만 보낸다. 로그·화면에 찍지 않는다.
  final String? accessToken;
  final String? message;

  @override
  String toString() => 'ProviderLoginResult($status)'; // 토큰은 출력하지 않는다
}

/// 로그인 수단 한 칸 — 시험·이메일 후속이 같은 자리에 끼워진다.
abstract class LoginProviderGateway {
  LoginProviderKind get kind;
  bool get isConfigured;
  Future<ProviderLoginResult> login();
  Future<void> logout();
  Future<void> unlink();
}

class KakaoAuthService implements LoginProviderGateway {
  KakaoAuthService._();
  static final KakaoAuthService instance = KakaoAuthService._();

  /// 빌드 때 넣는 네이티브 앱 키. 값은 화면·로그에 출력하지 않는다.
  ///   dart-define 이 없으면 lib/config/kakao_config.dart 의 값(res/values/kakao_config.xml scheme 과 같은 키).
  static const String _nativeAppKey =
      String.fromEnvironment('KAKAO_NATIVE_APP_KEY', defaultValue: kKakaoNativeAppKey);

  static bool _initialized = false;

  /// [§3 DEV 모의] 디버그 빌드 + dart-define `KAKAO_MOCK_SUBJECT` 가 있으면 SDK 없이 `mock-kakao:{subject}` 를
  ///   서버로 보낸다. 서버는 `AUTH_MOCK_MODE`(비 prod)에서만 받는다 — 릴리스 빌드에서는 꺼진다.
  static const String _mockSubject = String.fromEnvironment('KAKAO_MOCK_SUBJECT');
  static bool get _mock => kDebugMode && _mockSubject.isNotEmpty;

  @override
  LoginProviderKind get kind => LoginProviderKind.kakao;

  @override
  bool get isConfigured => _mock || (_nativeAppKey.isNotEmpty && _initialized);

  /// main() 에서 한 번 부른다. 키가 없으면 아무것도 하지 않는다(준비 중 상태).
  static void install() {
    if (_nativeAppKey.isEmpty || _initialized) return;
    try {
      KakaoSdk.init(nativeAppKey: _nativeAppKey);
      _initialized = true;
      AuthService.providerSignOutHook = instance.logout;
      AuthService.providerUnlinkHook = instance.unlink;
    } catch (e) {
      debugPrint('⚠️ 카카오 SDK 초기화 실패: ${e.runtimeType}');
    }
  }

  @override
  Future<ProviderLoginResult> login() async {
    if (_mock) return const ProviderLoginResult.success('mock-kakao:$_mockSubject');
    if (!isConfigured) return const ProviderLoginResult.notConfigured();
    try {
      final OAuthToken token;
      if (await isKakaoTalkInstalled()) {
        try {
          token = await UserApi.instance.loginWithKakaoTalk();
        } on PlatformException catch (e) {
          // 톡 로그인 창을 닫았거나 동의 화면에서 취소했다 — 계정 로그인으로 넘기지 않는다(공식 안내와 같다).
          // [X0 실기기 2026-11-25] 동의 화면 '취소'는 SDK 네이티브가 톡의 error type 을 그대로 code 로
          //   보낸다(TalkAuthCodeActivity.sendError) → 'CANCELED' 가 아니라 'access_denied' 로 와서
          //   웹 계정 로그인이 뜨던 결함.
          if (isUserCancelCode(e.code)) return const ProviderLoginResult.canceled();
          debugPrint('ℹ️ 카카오톡 로그인 불가(code=${e.code}) → 카카오계정 로그인');
          // 톡에 연결된 카카오계정이 없는 등 — 카카오계정 로그인으로 이어 간다.
          return await _loginWithAccount();
        }
      } else {
        return await _loginWithAccount();
      }
      return ProviderLoginResult.success(token.accessToken);
    } on KakaoAuthException catch (e) {
      if (e.error == AuthErrorCause.accessDenied) {
        return const ProviderLoginResult.canceled();
      }
      debugPrint('⚠️ 카카오 로그인 실패: ${e.error}');
      return const ProviderLoginResult.failed();
    } catch (e) {
      debugPrint('⚠️ 카카오 로그인 실패: ${e.runtimeType}');
      return const ProviderLoginResult.failed();
    }
  }

  Future<ProviderLoginResult> _loginWithAccount() async {
    try {
      final token = await UserApi.instance.loginWithKakaoAccount();
      return ProviderLoginResult.success(token.accessToken);
    } on PlatformException catch (e) {
      if (isUserCancelCode(e.code)) return const ProviderLoginResult.canceled();
      return const ProviderLoginResult.failed();
    } on KakaoAuthException catch (e) {
      if (e.error == AuthErrorCause.accessDenied) {
        return const ProviderLoginResult.canceled();
      }
      return const ProviderLoginResult.failed();
    }
  }

  /// 사용자가 스스로 그만둔 경우의 네이티브 오류 코드(톡 창 닫기 · 동의 화면 취소).
  @visibleForTesting
  static bool isUserCancelCode(String code) =>
      code == 'CANCELED' || code == 'access_denied';

  @override
  Future<void> logout() async {
    if (_mock || !isConfigured) return;
    try {
      if (await AuthApi.instance.hasToken()) await UserApi.instance.logout();
    } catch (e) {
      debugPrint('⚠️ 카카오 로그아웃 실패(무시): ${e.runtimeType}');
    }
  }

  /// 탈퇴 완료 뒤, 서버 Final 이 providerUnlink 'ALLOWED'(이 카카오에 남은 역할 없음)라고 할 때만 부른다.
  @override
  Future<void> unlink() async {
    if (_mock || !isConfigured) return;
    try {
      await UserApi.instance.unlink();
    } catch (e) {
      debugPrint('⚠️ 카카오 연결 해제 실패(무시): ${e.runtimeType}');
    }
  }
}
