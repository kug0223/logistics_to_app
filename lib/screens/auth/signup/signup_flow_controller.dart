// lib/screens/auth/signup/signup_flow_controller.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · impl_plan §1.3/§4.3] 가입 마법사 상태 — **서버 세션 상태로 재개**한다.
//
//   화면 단계는 서버가 말한 세션 상태에서 정해진다(앱이 단계를 기억해 건너뛰지 않는다).
//     started            → 이용 목적
//     purpose_selected   → 필수 동의
//     consented/cert_issued → 본인확인(KG)
//     pass_verified      → 본인확인 끝 · 가입 마무리
//     committed          → 가입 완료(로그인 준비 · 재시도 가능)
//     blocked_existing   → 이미 가입된 계정 안내
//
//   KG 는 '취소 / 실패 / 서버 확인 중 / 끝' 을 구분한다(impl_plan §4.3). 창이 닫혔다는 것만으로
//   본인확인이 끝났다고 말하지 않는다 — 서버(verifyPassAuth)가 확인해야 끝이다.

import 'package:flutter/foundation.dart';

import '../../../models/core/legal_terms_model.dart';
import '../../../services/auth/signup_api.dart';
import '../../../services/pass_verification_service.dart';
import '../../../utils/terms_submit_guard.dart';

enum SignupStep { purpose, consent, identity, existingAccount, blocked, complete }

enum KgPhase {
  /// 아직 시작 전.
  idle,

  /// 인증창이 열려 있다.
  inWindow,

  /// 사용자가 인증창을 닫았다.
  canceled,

  /// 인증창 또는 서버 확인이 실패했다.
  failed,

  /// 인증창이 돌아왔고 서버가 확인하는 중.
  verifying,

  /// 서버가 확인했다.
  verified,
}

/// 가입 완료 뒤 로그인(토큰 → 세션). 실패면 사용자에게 보일 문장, 성공이면 null.
typedef SignupTokenSink = Future<String?> Function(String customToken, {required bool switchAccount});

/// KG 인증창 열기(시험 대역 가능).
typedef KgLauncher = Future<PassLaunchOutcome> Function(String requestId);

class SignupFlowController extends ChangeNotifier {
  SignupFlowController({
    required SignupApi api,
    required SignupSession session,
    required SignupTokenSink onToken,
    KgLauncher? kgLauncher,
    Future<EffectiveLegalTerms> Function()? termsLoader,
  })  : _api = api,
        _session = session,
        _onToken = onToken,
        _kgLauncher = kgLauncher ??
            ((id) => PassVerificationService.launchCertification(requestId: id)),
        _termsLoader = termsLoader,
        _isAddRole = session.isAddRole {
    _step = stepFor(session);
    if (session.state == SignupSessionState.passVerified) {
      _kg = KgPhase.verified;
      _verification = session.pass; // 재개 — 서버 SessionView.pass
    }
  }

  // 역할 추가는 완료 때 계정을 바꾼다(로그아웃 → 새 토큰) — 그 사이 화면이 닫혀도 남은 단계가
  //   끝까지 돌 수 있게, 닫힌 뒤의 알림은 버린다.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  final SignupApi _api;
  final SignupTokenSink _onToken;
  final KgLauncher _kgLauncher;
  final Future<EffectiveLegalTerms> Function()? _termsLoader;

  SignupSession _session;
  SignupSession get session => _session;

  /// 역할 추가 세션인가 — 처음 받은 세션 기준(서버 응답이 purpose 를 빠뜨려도 잃지 않는다).
  final bool _isAddRole;
  bool get isAddRole => _isAddRole || _session.isAddRole;

  late SignupStep _step;
  SignupStep get step => _step;

  KgPhase _kg = KgPhase.idle;
  KgPhase get kgPhase => _kg;

  String? _message;

  /// 현재 단계에 붙는 안내(실패 사유 등).
  String? get message => _message;

  bool _busy = false;
  bool get busy => _busy;

  String? _pendingRole;

  /// 이용 목적 화면에서 고른 값(서버 반영 전 포함).
  String? get selectedRole => _pendingRole ?? _session.role;

  PassSignupVerification? _verification;
  PassSignupVerification? get verification => _verification;

  /// IDENTITY_ROLE_TAKEN details(역할 · 가입 달) — 상대 계정의 다른 정보는 받지도 보이지도 않는다.
  Map<String, dynamic>? _existingDetails;
  Map<String, dynamic>? get existingDetails => _existingDetails;

  CompleteSignupResult? _completed;
  CompleteSignupResult? get completed => _completed;

  /// 가입은 커밋됐지만 로그인 준비(토큰)가 아직이다 — 재시도 버튼을 보인다.
  bool _authPending = false;
  bool get authPending => _authPending;

  bool _signedIn = false;
  bool get signedIn => _signedIn;

  // ── 약관 ────────────────────────────────────────────────────
  EffectiveLegalTerms? _terms;
  EffectiveLegalTerms? get terms => _terms;
  bool _termsLoading = false;
  bool get termsLoading => _termsLoading;
  String? _termsError;
  String? get termsError => _termsError;
  final Map<String, bool> _choices = {};
  Map<String, bool> get choices => Map.unmodifiable(_choices);
  final Set<String> _viewed = {};
  Set<String> get viewed => Set.unmodifiable(_viewed);

  /// 전체 단계 수와 현재 위치(진행 표시용). 이미 가입 안내·차단은 진행 표시 없이 보인다.
  static const int totalSteps = 4;
  int get stepIndex {
    switch (_step) {
      case SignupStep.purpose:
        return 0;
      case SignupStep.consent:
        return 1;
      case SignupStep.identity:
        return 2;
      case SignupStep.complete:
        return 3;
      case SignupStep.existingAccount:
      case SignupStep.blocked:
        return 2;
    }
  }

  /// 남은 단계 수(현재 단계 포함, 완료 화면 제외).
  int get remainingSteps => (totalSteps - 1 - stepIndex).clamp(0, totalSteps);

  static SignupStep stepFor(SignupSession s) {
    switch (s.state) {
      case SignupSessionState.started:
        // 역할 추가 세션은 역할이 고정돼 있다 — 바로 동의로.
        return (s.isAddRole && s.role != null) ? SignupStep.consent : SignupStep.purpose;
      case SignupSessionState.purposeSelected:
        return SignupStep.consent;
      case SignupSessionState.consented:
      case SignupSessionState.certIssued:
      case SignupSessionState.passVerified:
        return SignupStep.identity;
      case SignupSessionState.committed:
        return SignupStep.complete;
      case SignupSessionState.blockedExisting:
        return SignupStep.existingAccount;
      case SignupSessionState.canceled:
      case SignupSessionState.expired:
      case SignupSessionState.unknown:
        return SignupStep.blocked;
    }
  }

  void _set({SignupStep? step, KgPhase? kg, String? message, bool clearMessage = false}) {
    if (step != null) _step = step;
    if (kg != null) _kg = kg;
    if (clearMessage) _message = null;
    if (message != null) _message = message;
    notifyListeners();
  }

  Future<T?> _guard<T>(Future<T> Function() body) async {
    if (_busy) return null;
    _busy = true;
    notifyListeners();
    try {
      return await body();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _applySession(SignupSession next) {
    _session = next;
    _step = stepFor(next);
    if (next.state == SignupSessionState.passVerified) {
      _kg = KgPhase.verified;
    } else if (_step == SignupStep.identity && _kg == KgPhase.verified) {
      _kg = KgPhase.idle; // 역할을 바꾸면 서버가 KG 결과를 버린다(§1.3) — 화면도 따라간다.
    }
  }

  /// 서버 거절을 단계로 옮긴다. 알 수 없는 것은 메시지만.
  void _applyError(SignupApiException e) {
    switch (e.reason) {
      case 'IDENTITY_ROLE_TAKEN':
        _step = SignupStep.existingAccount;
        _existingDetails = e.details;
        _message = null;
        break;
      case 'IDENTITY_PROVIDER_MISMATCH':
      case 'IDENTITY_ROLE_DELETING':
      case 'ROLE_ADD_BLOCKED':
      case 'ROLE_ADD_REQUIRED':
      case 'MOCK_EVIDENCE_FORBIDDEN':
        _step = SignupStep.blocked;
        _message = e.userMessage;
        break;
      case 'CONSENT_REQUIRED':
        _step = SignupStep.consent;
        _message = e.userMessage;
        break;
      case 'PASS_REQUIRED':
      case 'PASS_ROLE_MISMATCH':
      case 'CERT_EXPIRED':
      case 'CERT_NOT_ISSUED':
      case 'KG_NOT_CERTIFIED':
      case 'KG_BINDING_MISMATCH':
      case 'KG_CI_MISSING':
      case 'KG_DATA_INCOMPLETE':
        _step = SignupStep.identity;
        _kg = KgPhase.failed;
        _verification = null;
        _message = e.userMessage;
        break;
      case 'REREGISTER_BLACKLISTED':
      case 'REREGISTER_COOLDOWN':
      case 'SESSION_INVALID':
      case 'SESSION_EXPIRED':
      case 'CERT_ATTEMPTS_EXCEEDED':
      case 'SUBJECT_IDENTITY_MISMATCH':
      case 'ADD_ROLE_IDENTITY_MISMATCH':
      case 'LINK_CONFLICT':
      case 'UNDER_AGE':
        _step = SignupStep.blocked;
        _message = e.userMessage;
        break;
      case 'TERMS_VERSION_STALE':
      case 'LEGAL_REQUIRED_REVISION_MISMATCH':
        _step = SignupStep.consent;
        _choices.clear();
        _viewed.clear();
        _terms = null;
        _message = e.userMessage;
        break;
      case 'PASS_RESULT_STALE':
      case 'IMP_UID_BOUND_ELSEWHERE':
        _step = SignupStep.identity;
        _kg = KgPhase.failed;
        _verification = null;
        _message = e.userMessage;
        break;
      default:
        _message = e.userMessage;
    }
  }

  // ── 1. 이용 목적 ─────────────────────────────────────────────
  void choosePurpose(String role) {
    if (isAddRole) return; // 역할 추가는 서버가 고정
    _pendingRole = role;
    _set(clearMessage: true);
  }

  Future<void> submitPurpose() => _guard(() async {
        final role = selectedRole;
        if (role == null) {
          _set(message: '이용 목적을 골라 주세요');
          return;
        }
        try {
          final next = await _api.setPurpose(_session, role: role);
          _pendingRole = null;
          _verification = null;
          _applySession(next);
          _message = null;
          if (_step == SignupStep.purpose) _step = SignupStep.consent; // 서버가 상태를 늦게 말해도 다음으로
        } on SignupApiException catch (e) {
          _applyError(e);
        }
      });

  /// 동의·본인확인 단계에서 목적으로 돌아간다(역할을 바꾸면 서버가 KG 결과를 버린다).
  void backToPurpose() {
    if (isAddRole) return;
    _set(step: SignupStep.purpose, clearMessage: true);
  }

  // ── 2. 필수 동의 ─────────────────────────────────────────────
  Future<void> loadTerms() async {
    final loader = _termsLoader;
    if (loader == null || _termsLoading) return;
    _termsLoading = true;
    _termsError = null;
    notifyListeners();
    try {
      final t = await loader();
      _terms = t;
      for (final item in t.activeItems) {
        _choices.putIfAbsent(item.id, () => false);
      }
    } catch (e) {
      _termsError = '약관을 불러오지 못했어요.';
    } finally {
      _termsLoading = false;
      notifyListeners();
    }
  }

  void setChoice(String id, bool agreed) {
    _choices[id] = agreed;
    _set(clearMessage: true);
  }

  void markViewed(String id) {
    _viewed.add(id);
    notifyListeners();
  }

  /// 아직 동의하지 않은 항목(전체 동의 때 본문을 차례로 보여 줄 순서).
  List<LegalTermsItem> get unagreedItems =>
      (_terms?.activeItems ?? const <LegalTermsItem>[]).where((i) => _choices[i.id] != true).toList();

  /// '전체 동의' 를 끈다 — 모든 항목 선택을 지운다(아직 서버에 보내기 전이라 되돌릴 수 있다).
  void clearAll() {
    for (final k in _choices.keys.toList()) {
      _choices[k] = false;
    }
    _set(clearMessage: true);
  }

  String? get consentBlockReason => termsSubmitBlockReason(
      loading: _termsLoading, error: _termsError, terms: _terms, consent: _choices);

  Future<void> submitConsent() => _guard(() async {
        final block = consentBlockReason;
        if (block != null) {
          _set(message: block);
          return;
        }
        final record = <String, dynamic>{
          for (final item in _terms!.activeItems)
            item.id: {'agreed': _choices[item.id] == true, 'version': item.version},
        };
        try {
          final next = await _api.recordConsent(_session, record);
          _applySession(next);
          _message = null;
          if (_step == SignupStep.consent) _step = SignupStep.identity;
        } on SignupApiException catch (e) {
          _applyError(e);
        }
      });

  // ── 3. 본인확인(KG) ──────────────────────────────────────────
  Future<void> startIdentity() => _guard(() async {
        _message = null;
        final String requestId;
        try {
          requestId = await _api.prepareCertification(_session);
        } on SignupApiException catch (e) {
          _kg = KgPhase.failed;
          _applyError(e);
          return;
        }
        _set(kg: KgPhase.inWindow);
        final outcome = await _kgLauncher(requestId);
        switch (outcome.status) {
          case PassLaunchStatus.canceled:
            _set(kg: KgPhase.canceled);
            return;
          case PassLaunchStatus.failed:
          case PassLaunchStatus.unavailable:
            _set(kg: KgPhase.failed, message: '본인확인 창에서 문제가 생겼어요. 다시 시도해 주세요.');
            return;
          case PassLaunchStatus.returned:
            break;
        }
        _set(kg: KgPhase.verifying);
        try {
          _verification = await _api.verifyPass(_session, impUid: outcome.impUid!);
          _session = _session.copyWith(state: SignupSessionState.passVerified, passDone: true);
          _kg = KgPhase.verified;
        } on SignupApiException catch (e) {
          _kg = KgPhase.failed;
          _applyError(e);
        }
      });

  // ── 4. 가입 마무리 ───────────────────────────────────────────
  Future<void> complete() => _guard(() async {
        _message = null;
        try {
          _completed = await _api.completeSignup(_session);
          _session = _session.copyWith(state: SignupSessionState.committed);
          _step = SignupStep.complete;
        } on SignupApiException catch (e) {
          _applyError(e);
          return;
        }
        await _deliverToken();
      });

  /// 커밋은 됐는데 로그인 준비가 안 됐을 때(응답 유실 · Auth 실패) — 같은 UID 로 다시 받는다.
  Future<void> retryAuth() => _guard(() async {
        _message = null;
        try {
          _completed = await _api.finalizeAuth(_session);
        } on SignupApiException catch (e) {
          _authPending = true;
          _message = e.userMessage;
          return;
        }
        await _deliverToken();
      });

  Future<void> _deliverToken() async {
    final token = _completed?.customToken;
    if (token == null) {
      // 커밋은 유효 — 토큰만 따로 받는다(B277-01).
      try {
        _completed = await _api.finalizeAuth(_session);
      } on SignupApiException catch (e) {
        _authPending = true;
        _message = e.userMessage;
        return;
      }
    }
    final t = _completed?.customToken;
    if (t == null) {
      _authPending = true;
      _message = SignupCopy.reasonMessage('AUTH_PROVISION_RETRY');
      return;
    }
    final err = await _onToken(t, switchAccount: isAddRole);
    if (err != null) {
      _authPending = true;
      _message = err;
      return;
    }
    _authPending = false;
    _signedIn = true;
  }

  /// 가입을 그만둔다(서버 세션 취소 · pass/cert 폐기). 실패해도 화면은 닫는다(세션은 만료로 정리).
  Future<void> cancel() async {
    try {
      await _api.cancel(_session);
    } catch (_) {}
  }
}
