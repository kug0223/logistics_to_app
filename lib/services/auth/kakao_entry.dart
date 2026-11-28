// lib/services/auth/kakao_entry.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · impl_plan §2.1] 시작 화면의 '카카오로 시작하기' 한 번을 끝까지 판정한다.
//
//   카카오 로그인(토큰) → 서버 callableAuthKakao → 결과 하나:
//     · TOKEN                  → custom token 로그인(아이디 로그인과 같은 계정 상태 판정)
//     · ROLE_SELECTION_REQUIRED → 두 역할 중 고르기(같은 카카오 토큰으로 다시 묻는다)
//     · SIGNUP_REQUIRED        → 가입 마법사(서버 세션 상태로 재개)
//     · DELETION_RECOVERY      → 토큰으로 들어가 삭제 재개 화면(AuthWrapper 가 보낸다)
//   토큰은 이 객체 메모리에만 있고, 역할 선택이 끝나면 버린다.

//   계정 상태 판정(차단·거절·기간 제한)은 여기서 하지 않는다 — 토큰을 받은 쪽(UserProvider →
//   AuthService.signInWithCustomToken / _loadUserData)이 LoginGate 로 한다.

import 'kakao_auth_service.dart';
import 'signup_api.dart';

sealed class KakaoEntryOutcome {
  const KakaoEntryOutcome();
}

class EntrySignedIn extends KakaoEntryOutcome {
  const EntrySignedIn();
}

class EntryRoleSelection extends KakaoEntryOutcome {
  const EntryRoleSelection(this.roles);
  final List<String> roles;
}

class EntrySignup extends KakaoEntryOutcome {
  const EntrySignup(this.session);
  final SignupSession session;
}

class EntryDeletionRecovery extends KakaoEntryOutcome {
  const EntryDeletionRecovery();
}

class EntryCanceled extends KakaoEntryOutcome {
  const EntryCanceled();
}

class EntryNotConfigured extends KakaoEntryOutcome {
  const EntryNotConfigured();
}

class EntryFailed extends KakaoEntryOutcome {
  const EntryFailed(this.message);
  final String message;
}

/// 토큰 → 로그인. 실패면 사용자 문장, 성공이면 null.
typedef EntryTokenSink = Future<String?> Function(String customToken);

class KakaoEntry {
  KakaoEntry({
    required LoginProviderGateway gateway,
    required SignupApi api,
    required EntryTokenSink onToken,
  })  : _gateway = gateway,
        _api = api,
        _onToken = onToken;

  final LoginProviderGateway _gateway;
  final SignupApi _api;
  final EntryTokenSink _onToken;

  String? _heldAccessToken;

  bool get isConfigured => _gateway.isConfigured;

  Future<KakaoEntryOutcome> start() async {
    _heldAccessToken = null;
    final login = await _gateway.login();
    switch (login.status) {
      case ProviderLoginStatus.canceled:
        return const EntryCanceled();
      case ProviderLoginStatus.notConfigured:
        return const EntryNotConfigured();
      case ProviderLoginStatus.failed:
        return const EntryFailed('카카오 로그인을 마치지 못했어요. 다시 시도해 주세요.');
      case ProviderLoginStatus.success:
        break;
    }
    _heldAccessToken = login.accessToken;
    return _ask(null);
  }

  /// 두 역할 중 하나를 골랐다.
  Future<KakaoEntryOutcome> chooseRole(String role) async {
    if (_heldAccessToken == null) return start();
    return _ask(role);
  }

  Future<KakaoEntryOutcome> _ask(String? role) async {
    final token = _heldAccessToken;
    if (token == null) return const EntryFailed('카카오로 다시 시작해 주세요.');
    final AuthKakaoResult res;
    try {
      res = await _api.authKakao(accessToken: token, role: role);
    } on SignupApiException catch (e) {
      _heldAccessToken = null;
      if (e.reason == 'KAKAO_NOT_CONFIGURED') return const EntryNotConfigured();
      return EntryFailed(e.userMessage);
    }
    switch (res) {
      case AuthKakaoRoleSelection(:final roles):
        return EntryRoleSelection(roles); // 토큰 유지 — 고른 역할로 다시 묻는다
      case AuthKakaoRoleNotLinked(:final roles):
        // 고른 역할에 연결이 없다 — 연결된 역할이 하나면 그 역할로, 둘 이상이면 다시 고르게 한다.
        if (roles.length == 1 && roles.first != role) return _ask(roles.first);
        if (roles.length >= 2) return EntryRoleSelection(roles);
        _heldAccessToken = null;
        return const EntryFailed('연결된 계정을 찾지 못했어요. 카카오로 다시 시작해 주세요.');
      case AuthKakaoToken(:final customToken):
        _heldAccessToken = null;
        final err = await _onToken(customToken);
        return err == null ? const EntrySignedIn() : EntryFailed(err);
      case AuthKakaoSignupRequired(:final session):
        _heldAccessToken = null;
        return EntrySignup(session);
      case AuthKakaoDeletionRecovery(:final customToken):
        _heldAccessToken = null;
        // [판정280 B280-02] 토큰 처리 실패를 삼키지 않는다 — 세션이 삭제 재개 상태로 서지 못했으면
        //   '재개 화면으로 갔다' 고 말하지 않고 그 사유를 그대로 보인다.
        final err = await _onToken(customToken);
        return err == null ? const EntryDeletionRecovery() : EntryFailed(err);
    }
  }
}
