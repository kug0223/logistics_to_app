// lib/services/auth/signup_api.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · impl_plan §2.1–§2.5] 새 가입 흐름 서버 callable 래퍼.
//
//   · 이름·입출력은 impl_plan §2(그리고 서버 담당의 server_api_1.md)를 따른다. 응답 필드는
//     관대하게 읽는다 — 빠진 값은 '모름' 으로 두고 성공으로 접지 않는다.
//   · 가입 세션 자격(secret)은 서버가 카카오 토큰 검증 뒤에만 발급한다(B277-02). 앱은 **메모리에만**
//     둔다(디스크·로그·화면 0). 재개는 카카오 재로그인 → 서버가 secret 을 회전해 다시 준다.
//   · 시험·시뮬레이터는 [SignupApi] 를 가짜로 바꿔 끼운다(실제 카카오/KG = PENDING VERIFICATION).

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../auth_service.dart';
import '../../utils/format_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 모델
// ─────────────────────────────────────────────────────────────────────────────

/// 서버 세션 상태(§1.3 상태도). 모르는 값은 [unknown].
enum SignupSessionState {
  started,
  purposeSelected,
  consented,
  certIssued,
  passVerified,
  committed,
  blockedExisting,
  canceled,
  expired,
  unknown,
}

SignupSessionState parseSignupSessionState(Object? raw) {
  switch (raw) {
    case 'started':
      return SignupSessionState.started;
    case 'purpose_selected':
      return SignupSessionState.purposeSelected;
    case 'consented':
      return SignupSessionState.consented;
    case 'cert_issued':
      return SignupSessionState.certIssued;
    case 'pass_verified':
      return SignupSessionState.passVerified;
    case 'committed':
      return SignupSessionState.committed;
    case 'blocked_existing':
      return SignupSessionState.blockedExisting;
    case 'canceled':
      return SignupSessionState.canceled;
    case 'expired':
      return SignupSessionState.expired;
    default:
      return SignupSessionState.unknown;
  }
}

/// 가입 세션의 앱 쪽 모습. [secret] 은 서버 호출에만 쓴다 — toString 에 넣지 않는다.
@immutable
class SignupSession {
  const SignupSession({
    required this.sessionId,
    required this.secret,
    required this.state,
    this.role,
    this.purpose = 'signup',
    this.consentDone = false,
    this.passDone = false,
    this.expiresAt,
    this.pass,
  });

  final String sessionId;
  final String secret;
  final SignupSessionState state;

  /// 'USER' | 'BUSINESS_ADMIN' | null(아직 안 고름)
  final String? role;

  /// 'signup' | 'add_role'
  final String purpose;
  final bool consentDone;
  final bool passDone;
  final DateTime? expiresAt;

  /// 서버 SessionView.pass — 본인확인을 마친 세션을 재개할 때 보일 이름·생년·가린 휴대폰.
  final PassSignupVerification? pass;

  bool get isAddRole => purpose == 'add_role';

  SignupSession copyWith({
    String? secret,
    SignupSessionState? state,
    String? role,
    bool? consentDone,
    bool? passDone,
    DateTime? expiresAt,
  }) =>
      SignupSession(
        sessionId: sessionId,
        secret: secret ?? this.secret,
        state: state ?? this.state,
        role: role ?? this.role,
        purpose: purpose,
        consentDone: consentDone ?? this.consentDone,
        passDone: passDone ?? this.passDone,
        expiresAt: expiresAt ?? this.expiresAt,
        pass: pass,
      );

  /// 서버 응답(`session:{…}`)에서 읽는다. 필수 값이 없으면 null — 가짜 세션을 만들지 않는다.
  static SignupSession? tryFrom(Object? raw, {String? fallbackSecret}) {
    if (raw is! Map) return null;
    final id = raw['sessionId'];
    final secret = raw['secret'] ?? fallbackSecret;
    if (id is! String || id.isEmpty || secret is! String || secret.isEmpty) {
      return null;
    }
    final role = raw['role'];
    final purpose = raw['purpose'];
    return SignupSession(
      sessionId: id,
      secret: secret,
      state: parseSignupSessionState(raw['state']),
      role: (role == 'USER' || role == 'BUSINESS_ADMIN') ? role as String : null,
      purpose: purpose == 'add_role' ? 'add_role' : 'signup',
      consentDone: raw['consentDone'] == true,
      passDone: raw['passDone'] == true,
      expiresAt: _parseTime(raw['expiresAtMs'] ?? raw['expiresAt']),
      pass: raw['pass'] is Map
          ? PassSignupVerification(
              name: (raw['pass'] as Map)['name'] as String?,
              birthDate: (raw['pass'] as Map)['birthDate'] as String?,
              phoneMasked: (raw['pass'] as Map)['phoneMasked'] as String?,
            )
          : null,
    );
  }

  @override
  String toString() => 'SignupSession($sessionId, $state, role=$role, purpose=$purpose)';
}

/// callableAuthKakao 결과(§2.1).
sealed class AuthKakaoResult {
  const AuthKakaoResult();
}

/// 연결된 계정이 있다 — 바로 로그인.
class AuthKakaoToken extends AuthKakaoResult {
  const AuthKakaoToken({required this.uid, required this.role, required this.customToken});
  final String uid;
  final String? role;
  final String customToken;
}

/// 같은 카카오에 두 역할이 있다 — 어느 쪽으로 들어갈지 고른다.
class AuthKakaoRoleSelection extends AuthKakaoResult {
  const AuthKakaoRoleSelection(this.roles);
  final List<String> roles;
}

/// 고른 역할에는 연결이 없다 — [roles] 가 실제로 연결된 역할(server_api_1 §1).
class AuthKakaoRoleNotLinked extends AuthKakaoResult {
  const AuthKakaoRoleNotLinked(this.roles);
  final List<String> roles;
}

/// 연결된 계정이 없다 — 가입 세션(새로 열었거나 이어서).
class AuthKakaoSignupRequired extends AuthKakaoResult {
  const AuthKakaoSignupRequired(this.session);
  final SignupSession session;
}

/// 탈퇴가 끝나지 않았다 — 토큰으로 들어가 삭제 재개 화면으로.
class AuthKakaoDeletionRecovery extends AuthKakaoResult {
  const AuthKakaoDeletionRecovery(this.customToken);
  final String customToken;
}

/// verifyPassAuth(purpose:'signup') 결과(§2.3). 화면엔 이름·생년만, 전화는 가린 값만.
@immutable
class PassSignupVerification {
  const PassSignupVerification({
    this.name,
    this.birthDate,
    this.phoneMasked,
    this.roleLikelyTaken = false,
  });
  final String? name;
  final String? birthDate;
  final String? phoneMasked;

  /// 서버가 준 비원자 힌트 — 확정은 completeSignup 이 한다.
  final bool roleLikelyTaken;
}

/// callableCompleteSignup / callableSignupFinalizeAuth 결과(§2.4/§2.5).
@immutable
class CompleteSignupResult {
  const CompleteSignupResult({required this.uid, this.role, this.customToken});
  final String uid;
  final String? role;

  /// 없으면 Auth 준비가 아직 — FinalizeAuth 로 이어서 받는다(커밋은 유효).
  final String? customToken;
}

/// 서버 거절. [reason] = HttpsError details.reason(§2 reason 목록).
class SignupApiException implements Exception {
  const SignupApiException({required this.code, this.reason, this.details});
  final String code;
  final String? reason;
  final Map<String, dynamic>? details;

  /// 사용자에게 보일 문장.
  String get userMessage => SignupCopy.reasonMessage(reason, code: code, details: details);

  @override
  String toString() => 'SignupApiException($code, $reason)';
}

// ─────────────────────────────────────────────────────────────────────────────
// 서버 경계
// ─────────────────────────────────────────────────────────────────────────────

abstract class SignupApi {
  Future<AuthKakaoResult> authKakao({required String accessToken, String? role});
  Future<SignupSession> getSession(SignupSession s);
  Future<SignupSession> startAddRole({required String role});
  Future<SignupSession> setPurpose(SignupSession s, {required String role});
  Future<SignupSession> recordConsent(SignupSession s, Map<String, dynamic> consentRecord);

  /// 서버 requestId(= PortOne merchant_uid) 를 받는다.
  Future<String> prepareCertification(SignupSession s);
  Future<PassSignupVerification> verifyPass(SignupSession s, {required String impUid});
  Future<CompleteSignupResult> completeSignup(SignupSession s);
  Future<CompleteSignupResult> finalizeAuth(SignupSession s);
  Future<void> cancel(SignupSession s);
}

class FirebaseSignupApi implements SignupApi {
  FirebaseSignupApi({FirebaseFunctions? functions})
      : _fn = functions ?? FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  final FirebaseFunctions _fn;

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> body,
      {int timeoutSec = 20}) async {
    try {
      final res = await _fn
          .httpsCallable(name,
              options: HttpsCallableOptions(timeout: Duration(seconds: timeoutSec)))
          .call<Object?>(body);
      final data = res.data;
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final d = e.details;
      final details = d is Map ? Map<String, dynamic>.from(d) : null;
      final reason = details?['reason'];
      debugPrint('⚠️ [$name] ${e.code} reason=$reason');
      throw SignupApiException(
          code: e.code, reason: reason is String ? reason : null, details: details);
    }
  }

  Map<String, dynamic> _cred(SignupSession s) =>
      {'sessionId': s.sessionId, 'secret': s.secret};

  SignupSession _sessionOf(Map<String, dynamic> data, SignupSession? prev) {
    final raw = data['session'] ?? data;
    final next = SignupSession.tryFrom(raw, fallbackSecret: prev?.secret);
    if (next == null) {
      throw const SignupApiException(code: 'internal', reason: 'SESSION_RESPONSE_INVALID');
    }
    return next;
  }

  @override
  Future<AuthKakaoResult> authKakao({required String accessToken, String? role}) async {
    final data = await _call('callableAuthKakao', {
      'accessToken': accessToken,
      if (role != null) 'role': role,
    });
    return parseAuthKakaoResult(data);
  }

  @override
  Future<SignupSession> getSession(SignupSession s) async =>
      _sessionOf(await _call('callableSignupSessionGet', _cred(s)), s);

  @override
  Future<SignupSession> startAddRole({required String role}) async =>
      _sessionOf(await _call('callableSignupSessionStartAddRole', {'role': role}), null);

  @override
  Future<SignupSession> setPurpose(SignupSession s, {required String role}) async =>
      _sessionOf(await _call('callableSignupSessionSetPurpose', {..._cred(s), 'role': role}), s);

  @override
  Future<SignupSession> recordConsent(
          SignupSession s, Map<String, dynamic> consentRecord) async =>
      _sessionOf(
          await _call('callableSignupSessionConsent',
              {..._cred(s), 'consentRecord': consentRecord}),
          s);

  @override
  Future<String> prepareCertification(SignupSession s) async {
    final data = await _call('callableSignupSessionPrepareCertification', _cred(s));
    final cert = data['cert'];
    final id = data['requestId'] ?? (cert is Map ? cert['requestId'] : null);
    if (id is! String || id.isEmpty) {
      throw const SignupApiException(code: 'internal', reason: 'CERT_RESPONSE_INVALID');
    }
    return id;
  }

  @override
  Future<PassSignupVerification> verifyPass(SignupSession s, {required String impUid}) async {
    final data = await _call('verifyPassAuth', {
      'imp_uid': impUid,
      'purpose': 'signup',
      ..._cred(s),
    });
    final hint = data['hint'];
    return PassSignupVerification(
      name: data['name'] as String?,
      birthDate: data['birthDate'] as String?,
      phoneMasked: data['phoneMasked'] as String?,
      roleLikelyTaken: data['roleTaken'] == true ||
          (hint is Map && (hint['roleTaken'] == true || hint['roleOccupied'] == true)),
    );
  }

  @override
  Future<CompleteSignupResult> completeSignup(SignupSession s) async =>
      parseCompleteResult(await _call('callableCompleteSignup', _cred(s), timeoutSec: 30));

  @override
  Future<CompleteSignupResult> finalizeAuth(SignupSession s) async =>
      parseCompleteResult(await _call('callableSignupFinalizeAuth', _cred(s)));

  @override
  Future<void> cancel(SignupSession s) async {
    await _call('callableSignupSessionCancel', _cred(s));
  }
}

/// callableAuthKakao 응답 판독(시험 공용).
AuthKakaoResult parseAuthKakaoResult(Map<String, dynamic> data) {
  switch (data['status']) {
    case 'TOKEN':
      final token = data['customToken'];
      final uid = data['uid'];
      if (token is String && token.isNotEmpty && uid is String) {
        return AuthKakaoToken(uid: uid, role: data['role'] as String?, customToken: token);
      }
      break;
    case 'ROLE_SELECTION_REQUIRED':
      final roles = _roles(data['roles']);
      if (roles.length >= 2) return AuthKakaoRoleSelection(roles);
      break;
    case 'ROLE_NOT_LINKED':
      final roles = _roles(data['roles']);
      if (roles.isNotEmpty) return AuthKakaoRoleNotLinked(roles);
      break;
    case 'SIGNUP_REQUIRED':
      final s = SignupSession.tryFrom(data['session']);
      if (s != null) return AuthKakaoSignupRequired(s);
      break;
    case 'DELETION_RECOVERY':
      final token = data['customToken'];
      if (token is String && token.isNotEmpty) return AuthKakaoDeletionRecovery(token);
      break;
    case 'ACCOUNT_DELETED':
      throw const SignupApiException(code: 'failed-precondition', reason: 'ACCOUNT_DELETED');
  }
  throw const SignupApiException(code: 'internal', reason: 'AUTH_RESPONSE_INVALID');
}

List<String> _roles(Object? raw) => (raw is List)
    ? raw
        .map((r) => r is Map ? r['role'] : r)
        .whereType<String>()
        .where((r) => r == 'USER' || r == 'BUSINESS_ADMIN')
        .toSet()
        .toList()
    : const <String>[];

CompleteSignupResult parseCompleteResult(Map<String, dynamic> data) {
  final uid = data['uid'];
  if (uid is! String || uid.isEmpty) {
    throw const SignupApiException(code: 'internal', reason: 'COMPLETE_RESPONSE_INVALID');
  }
  final token = data['customToken'];
  return CompleteSignupResult(
    uid: uid,
    role: data['role'] as String?,
    customToken: (token is String && token.isNotEmpty) ? token : null,
  );
}

DateTime? _parseTime(Object? v) {
  if (v is String) return DateTime.tryParse(v);
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is Map) {
    final s = v['_seconds'] ?? v['seconds'];
    if (s is int) return DateTime.fromMillisecondsSinceEpoch(s * 1000);
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// 문구 — 앱 말투(해요체) · '인증 완료/검증 완료/취업자격/진위' 표현 0
// ─────────────────────────────────────────────────────────────────────────────

class SignupCopy {
  SignupCopy._();

  static const String roleUser = '일할게요';
  static const String roleUserDesc = '근무할 곳을 찾고 일정을 관리해요';
  static const String roleAdmin = '사람을 구할게요';
  static const String roleAdminDesc = '사업장을 등록하고 함께 일할 사람을 찾아요';

  static String roleLabel(String? role) =>
      role == 'BUSINESS_ADMIN' ? '사업주' : (role == 'USER' ? '근무자' : '');

  static String reasonMessage(String? reason, {String? code, Map<String, dynamic>? details}) {
    final ms = details?['canReregisterAtMs'];
    final untilMs = details?['restrictedUntilMs'];
    switch (reason) {
      // ── callableAuthKakao 계정 상태(server_api_1 §1) — 아이디 로그인 안내와 같은 말 ──
      case 'ACCOUNT_BLACKLISTED':
        final r = details?['blacklistReason'];
        return '계정 이용 차단 상태라 해제 전까지 로그인할 수 없어요.\n사유: ${r is String ? r : '이용 정책 위반'}\n고객센터에 문의해주세요.';
      case 'ACCOUNT_REJECTED':
        return '가입이 거절되었습니다.\n고객센터에 문의해주세요.';
      case 'ACCOUNT_RESTRICTED':
        if (untilMs is int) {
          return AuthService.restrictionLoginMessage(
              DateTime.fromMillisecondsSinceEpoch(untilMs), details?['restrictionSource'] as String?);
        }
        return '지금은 이용이 제한된 계정이에요.';
      case 'ACCOUNT_INCOMPLETE':
        return '가입이 끝나지 않은 계정이에요. 고객센터에 문의해 주세요.';
      case 'REREGISTER_COOLDOWN':
        if (ms is int) {
          final d = FormatHelper.formatKstDateTimeKorean(DateTime.fromMillisecondsSinceEpoch(ms));
          return '탈퇴 후 재가입 제한 기간이라 아직 가입할 수 없어요.\n$d(한국시간)부터 다시 가입할 수 있어요.';
        }
        return '탈퇴 후 재가입 제한 기간이라 아직 가입할 수 없어요.\n제한 기간이 지나면 다시 가입할 수 있어요.';
      case 'IDENTITY_PROVIDER_MISMATCH':
        return '다른 카카오 계정으로 가입한 계정이 있어요. 그 카카오 계정으로 로그인한 뒤 역할을 추가해 주세요.';
      case 'IDENTITY_ROLE_DELETING':
        return '같은 역할의 계정이 탈퇴 처리 중이에요. 탈퇴가 끝난 뒤 다시 시도해 주세요.';
      case 'ROLE_ADD_BLOCKED':
        return '지금 계정 상태로는 역할을 추가할 수 없어요.';
      case 'ROLE_ADD_REQUIRED':
        return '이 카카오 계정은 이미 가입돼 있어요. 카카오로 로그인한 뒤 내 정보에서 역할을 추가해 주세요.';
      case 'ROLE_INVALID':
      case 'PURPOSE_FIXED':
        return '이용 목적을 다시 골라 주세요.';
      case 'CONSENT_REQUIRED':
        return '필수 약관에 먼저 동의해 주세요.';
      case 'PASS_REQUIRED':
      case 'PASS_ROLE_MISMATCH':
      case 'CERT_NOT_ISSUED':
        return '본인확인을 다시 해 주세요.';
      case 'CERT_EXPIRED':
        return '본인확인 시간이 지났어요. 본인확인을 다시 해 주세요.';
      case 'KG_NOT_CERTIFIED':
      case 'KG_BINDING_MISMATCH':
      case 'KG_DATA_INCOMPLETE':
        return '본인확인 결과를 확인하지 못했어요. 본인확인을 다시 해 주세요.';
      // [app_impl_9 · 인증 문구 2026-11-26] 간편인증은 인증서 앱마다 넘겨주는 정보가 다르다 — '휴대폰' 으로 단정하지 않는다.
      case 'KG_CI_MISSING':
        return '고른 인증 방법으로는 본인확인 정보를 받지 못했어요. 다른 인증 방법으로 다시 시도해 주세요.';
      // [app_impl_9 · 인증 문구 2026-11-26] 두 사유 모두 본인확인 창이 끝난 **뒤** 서버가 결과를 읽는 단계다(verifyPassAuth).
      //   창 자체의 문제(PassLaunchStatus.failed/unavailable)는 컨트롤러가 '본인확인 창에서 문제가 생겼어요' 로 따로 말한다.
      case 'PORTONE_UNAVAILABLE':
        return '본인확인 결과를 받아 오지 못했어요. 잠시 후 본인확인을 다시 해 주세요.';
      case 'PORTONE_NOT_CONFIGURED':
        return '지금은 본인확인을 진행할 수 없어요. 잠시 후 다시 시도해 주세요.';
      case 'MOCK_EVIDENCE_FORBIDDEN':
        return '시험용 본인확인 결과로는 가입할 수 없어요.';
      case 'DOCUMENT_KIND_REQUIRED':
        return '등록할 신분증 종류를 먼저 골라 주세요.';
      case 'DOCUMENT_KIND_MISMATCH':
        return '고른 신분증 종류가 등록된 정보와 달라요. 종류를 다시 확인해 주세요.';
      case 'FOREIGN_ID_FORMAT':
        return '외국인등록번호를 다시 확인해 주세요.';
      case 'FOREIGN_ID_GENDER_MISMATCH':
        return '외국인등록번호가 본인확인 정보와 맞지 않아요. 번호를 다시 확인해 주세요.';
      case 'NATIONALITY_ALREADY_SET':
        return '이미 신분증 종류가 정해진 계정이에요. 내 서류 관리에서 확인해 주세요.';
      case 'LEGACY_ACCOUNT':
        return '이 계정은 기존 방식으로 서류를 등록해요.';
      case 'IDENTITY_MISMATCH':
        return '이 계정을 만든 본인 명의로 다시 확인해 주세요.'; // [app_impl_9 · 인증 문구 2026-11-26]
      case 'DELETION_REAUTH_NOT_STARTED':
        return '본인확인을 처음부터 다시 해 주세요.';
      case 'NOT_PROVIDER_ACCOUNT':
        return '이 계정은 비밀번호로 본인확인을 해요.';
      case 'DELETION_REAUTH_REQUIRED':
        return '탈퇴하려면 본인확인을 다시 해 주세요.';
      case 'KAKAO_NOT_CONFIGURED':
        return '카카오 로그인을 준비하고 있어요. 잠시 후 다시 시도해 주세요.';
      case 'KAKAO_TOKEN_INVALID':
      case 'KAKAO_APP_MISMATCH':
        return '카카오 로그인 정보를 확인하지 못했어요. 다시 로그인해 주세요.';
      case 'KAKAO_UNAVAILABLE':
        return '카카오 연결이 원활하지 않아요. 잠시 후 다시 시도해 주세요.';
      case 'SESSION_INVALID':
      case 'SESSION_EXPIRED':
      case 'SESSION_RESPONSE_INVALID':
        return '가입 진행 시간이 지났어요. 카카오로 다시 시작해 주세요.';
      case 'SESSION_STATE':
        return '가입 단계가 바뀌었어요. 화면을 새로 불러올게요.';
      case 'ROLE_ALREADY_LINKED':
        return '이미 같은 역할의 계정이 있어요.';
      case 'NO_PROVIDER_LINK':
        return '카카오로 가입한 계정에서만 역할을 추가할 수 있어요.';
      case 'TERMS_UNAVAILABLE':
        return '약관을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.';
      case 'TERMS_VERSION_STALE':
      case 'LEGAL_REQUIRED_REVISION_MISMATCH':
        return '약관이 바뀌었어요. 바뀐 내용을 확인하고 다시 동의해 주세요.';
      case 'CERT_ATTEMPTS_EXCEEDED':
        return '본인확인 시도 횟수를 넘었어요. 카카오로 다시 시작해 주세요.';
      case 'IMP_UID_BOUND_ELSEWHERE':
        return '이 본인확인 결과는 다른 가입에 쓰였어요. 본인확인을 다시 해 주세요.';
      case 'PASS_RESULT_STALE':
        return '본인확인 후 시간이 지났어요. 본인확인을 다시 해 주세요.';
      case 'UNDER_AGE':
        return '만 19세 이상만 가입할 수 있어요.';
      case 'REREGISTER_BLACKLISTED':
        // 옛 가입의 영구 제한 안내와 같은 문장(한 곳 — AuthService.signupRestrictionMessage).
        return AuthService.signupRestrictionMessage('영구 제한');
      case 'IDENTITY_ROLE_TAKEN':
        return '이미 가입된 계정이 있어요. 처음 가입한 카카오 계정으로 로그인해 주세요.';
      case 'SUBJECT_IDENTITY_MISMATCH':
      case 'ADD_ROLE_IDENTITY_MISMATCH':
        return '지금 로그인한 카카오 계정의 본인 정보와 달라요. 본인 명의로 다시 확인해 주세요.';
      case 'LINK_CONFLICT':
        return '이 카카오 계정은 다른 계정에 연결돼 있어요. 고객센터에 문의해 주세요.';
      case 'AUTH_PROVISION_RETRY':
        return '가입은 저장됐어요. 로그인 준비를 마무리하지 못했어요 — 다시 시도해 주세요.';
      case 'ACCOUNT_DELETED':
        return '탈퇴가 끝난 계정이에요. 새로 가입하려면 카카오로 다시 시작해 주세요.';
      case 'LEGACY_SIGNUP_CLOSED':
      case 'LEGACY_PASS_FLOW_CLOSED':
        return '이 방법으로는 더 이상 가입할 수 없어요. 카카오로 시작해 주세요.';
      case 'CI_KEY_UNAVAILABLE':
        return '본인확인을 처리할 수 없는 상태예요. 잠시 후 다시 시도해 주세요.';
      case 'NATIONALITY_UNCONFIRMED':
        return '신분증 또는 외국인등록증을 먼저 등록해 주세요.';
      case 'FOREIGN_ID_DOCUMENT_REQUIRED':
        return '외국인등록증 정보를 먼저 등록해 주세요.';
      case 'FOREIGN_ID_BIRTHDATE_MISMATCH':
        return '외국인등록번호의 생년월일이 본인확인 정보와 달라요. 번호를 다시 확인해 주세요.';
    }
    // [app_impl_9 · 인증 문구 2026-11-26] 사유가 없는 오류 — 원인 계층만 구분한다(과장 0).
    switch (code) {
      case 'unavailable':
      case 'deadline-exceeded':
        // 연결 끊김·서버 일시 장애·응답 지연 — 어느 쪽인지 앱이 가리지 못한다.
        return '연결이 원활하지 않아요. 네트워크를 확인하고 잠시 후 다시 시도해 주세요.';
      case 'not-found':
      case 'unimplemented':
        // 서버에 그 기능이 아직 없다(점검·배포 중이거나 앱 버전이 맞지 않음).
        return '지금은 이 기능을 쓸 수 없어요. 잠시 후 다시 시도해 주세요. 계속되면 앱을 최신 버전으로 업데이트해 주세요.';
      case 'resource-exhausted':
        return '요청이 많아요. 잠시 후 다시 시도해 주세요.';
    }
    return '처리하지 못했어요. 잠시 후 다시 시도해 주세요.';
  }
}
