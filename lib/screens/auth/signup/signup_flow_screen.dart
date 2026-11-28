// lib/screens/auth/signup/signup_flow_screen.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · impl_plan §4.3] 가입 마법사 호스트 — 서버 세션 상태로 재개한다.
//
//   단계: 이용 목적 → 필수 동의 → 본인확인(KG 통합 간편인증) → 가입 완료.
//   흰 표면 · 머리(뒤로 48 · 제목 · 단계 이름 · 남은 단계 · 진행 막대) · 하단 고정 주 버튼(SafeArea(top:false)).
//   머리·진행 막대 모양은 기존 가입 화면(RegisterScreen 머리)과 같은 규칙이다.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/core/legal_terms_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/auth/signup_api.dart';
import '../../../services/legal_terms_service.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/text_layout.dart';
import 'signup_complete_step.dart';
import 'signup_consent_step.dart';
import 'signup_existing_account_step.dart';
import 'signup_flow_controller.dart';
import 'signup_identity_step.dart';
import 'signup_purpose_step.dart';

class SignupFlowScreen extends StatefulWidget {
  const SignupFlowScreen({
    super.key,
    required this.session,
    required this.api,
    this.kgLauncher,
    this.termsLoader,
    this.tokenSink,
  });

  final SignupSession session;
  final SignupApi api;

  /// 시험·시뮬레이터 대역(실제 KG 창 대신).
  final KgLauncher? kgLauncher;

  /// 시험 대역(생략 = 서버 시행본).
  final Future<EffectiveLegalTerms> Function()? termsLoader;

  /// 시험 대역(생략 = UserProvider 로그인).
  final SignupTokenSink? tokenSink;

  @override
  State<SignupFlowScreen> createState() => _SignupFlowScreenState();
}

class _SignupFlowScreenState extends State<SignupFlowScreen> {
  late final SignupFlowController _c;

  @override
  void initState() {
    super.initState();
    final up = widget.tokenSink == null ? context.read<UserProvider>() : null;
    _c = SignupFlowController(
      api: widget.api,
      session: widget.session,
      kgLauncher: widget.kgLauncher,
      termsLoader: widget.termsLoader ?? LegalTermsService().fetchEffectiveTerms,
      onToken: widget.tokenSink ??
          (token, {required bool switchAccount}) async {
            final p = up!;
            final ok = switchAccount
                ? await p.switchAccountWithCustomToken(token)
                : await p.signInWithCustomToken(token);
            if (ok) return null;
            return p.error ?? '로그인을 마무리하지 못했어요. 다시 시도해 주세요.';
          },
    );
    _c.addListener(_onChange);
    if (_c.step == SignupStep.consent) _c.loadTerms();
    // 커밋된 세션으로 재개했다(응답 유실 등) — 같은 UID 로 로그인 준비만 다시 받는다(B277-01).
    if (_c.step == SignupStep.complete && !_c.signedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _c.retryAuth();
      });
    }
  }

  SignupStep? _lastStep;
  bool _leftForHome = false;

  void _onChange() {
    if (_lastStep != _c.step && _c.step == SignupStep.consent && _c.terms == null) {
      _c.loadTerms();
    }
    _lastStep = _c.step;
    // [대표 결정 2026-11-25] 회원 완료 + 로그인 준비가 끝나면 완료 화면에 멈추지 않고 바로 닫는다 —
    //   아래 AuthWrapper 가 이미 로그인 상태라 (첫 안내 3장 · 건너뛰기 가능) → 홈으로 간다.
    //   로그인 준비 실패(authPending)는 이 화면에서 '다시 시도' 를 그대로 보인다.
    if (_c.signedIn && !_leftForHome && mounted) {
      _leftForHome = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _leaveToStart();
      });
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _c.dispose();
    super.dispose();
  }

  String get _title => _c.isAddRole ? '역할 추가' : '회원가입';

  String _stepName(SignupStep s) {
    switch (s) {
      case SignupStep.purpose:
        return '이용 목적';
      case SignupStep.consent:
        return '필수 동의';
      case SignupStep.identity:
        return '본인확인'; // [app_impl_9 · 인증 문구 2026-11-26]
      case SignupStep.existingAccount:
        return '이미 가입된 계정';
      case SignupStep.blocked:
        return '가입을 이어갈 수 없어요';
      case SignupStep.complete:
        return '가입 완료';
    }
  }

  void _leaveToStart() {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _onBack() {
    if (_c.busy) return;
    switch (_c.step) {
      case SignupStep.consent:
      case SignupStep.identity:
        if (!_c.isAddRole && _c.kgPhase != KgPhase.verified) {
          _c.backToPurpose();
          return;
        }
        Navigator.of(context).maybePop();
        return;
      case SignupStep.complete:
        _leaveToStart();
        return;
      case SignupStep.purpose:
      case SignupStep.existingAccount:
      case SignupStep.blocked:
        Navigator.of(context).maybePop();
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final step = _c.step;
        return PopScope(
          canPop: step == SignupStep.purpose ||
              step == SignupStep.existingAccount ||
              step == SignupStep.blocked,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _onBack();
          },
          child: Scaffold(
            backgroundColor: AppColors.surface,
            body: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    title: _title,
                    stepName: _stepName(step),
                    showProgress: step != SignupStep.existingAccount && step != SignupStep.blocked,
                    stepIndex: _c.stepIndex,
                    total: SignupFlowController.totalSteps,
                    remaining: _c.remainingSteps,
                    onBack: _onBack,
                  ),
                  Expanded(child: _body(step)),
                ],
              ),
            ),
            bottomNavigationBar: _bottom(step),
          ),
        );
      },
    );
  }

  Widget _body(SignupStep step) {
    switch (step) {
      case SignupStep.purpose:
        return SignupPurposeStep(controller: _c);
      case SignupStep.consent:
        return SignupConsentStep(controller: _c);
      case SignupStep.identity:
        return SignupIdentityStep(controller: _c);
      case SignupStep.existingAccount:
        return SignupExistingAccountStep(
          role: (_c.existingDetails?['role'] as String?) ?? _c.session.role ?? _c.selectedRole,
          joinedMonth: _c.existingDetails?['joinedMonth'] as String?,
        );
      case SignupStep.blocked:
        return SignupBlockedStep(message: _c.message);
      case SignupStep.complete:
        return SignupCompleteStep(controller: _c);
    }
  }

  Widget _bottom(SignupStep step) {
    String label;
    VoidCallback? action;
    bool loading = _c.busy;
    switch (step) {
      case SignupStep.purpose:
        label = '다음';
        action = _c.selectedRole == null ? null : _c.submitPurpose;
        break;
      case SignupStep.consent:
        label = '동의하고 계속';
        action = _c.consentBlockReason == null ? _c.submitConsent : null;
        break;
      case SignupStep.identity:
        switch (_c.kgPhase) {
          case KgPhase.idle:
            label = '간편인증으로 본인확인 하기'; // [app_impl_9 · 인증 문구 2026-11-26]
            action = _c.startIdentity;
            break;
          case KgPhase.canceled:
          case KgPhase.failed:
            label = '본인확인 다시 하기';
            action = _c.startIdentity;
            break;
          case KgPhase.inWindow:
          case KgPhase.verifying:
            label = '확인하고 있어요';
            action = null;
            loading = true;
            break;
          case KgPhase.verified:
            label = '가입 마치기';
            action = _c.complete;
            break;
        }
        break;
      case SignupStep.existingAccount:
      case SignupStep.blocked:
        label = '처음 화면으로';
        action = _leaveToStart;
        loading = false;
        break;
      case SignupStep.complete:
        if (_c.authPending) {
          label = '다시 시도';
          action = _c.retryAuth;
        } else if (_c.signedIn) {
          label = '시작하기';
          action = _leaveToStart;
        } else {
          label = '로그인 준비 중';
          action = null;
          loading = true;
        }
        break;
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
        child: ElevatedButton(
          onPressed: (loading || action == null) ? null : action,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: AppColors.textOnDark,
            disabledBackgroundColor: AppColors.grey200,
            disabledForegroundColor: AppColors.textSecondary,
            minimumSize: const Size.fromHeight(52),
            padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 14)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: loading && step != SignupStep.complete && step != SignupStep.identity
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  TextLayout.keepWords(label),
                  semanticsLabel: label,
                  textAlign: TextAlign.center,
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.w600,
                    color: (loading || action == null)
                        ? AppColors.textSecondary
                        : AppColors.textOnDark,
                  ),
                ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.stepName,
    required this.showProgress,
    required this.stepIndex,
    required this.total,
    required this.remaining,
    required this.onBack,
  });

  final String title;
  final String stepName;
  final bool showProgress;
  final int stepIndex;
  final int total;
  final int remaining;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final sub = (showProgress && remaining > 0) ? '$stepName · 남은 단계 $remaining' : stepName;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 4),
        ResponsiveHelper.spacing(context, 6),
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: '뒤로',
            child: GestureDetector(
              onTap: onBack,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Icon(Icons.arrow_back,
                      color: AppColors.textPrimary,
                      size: ResponsiveHelper.iconSize(context, 22)),
                ),
              ),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 2)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: ResponsiveHelper.titleStyle(context).copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  TextLayout.keepWords(sub),
                  semanticsLabel: sub,
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                ),
                if (showProgress) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  Row(
                    children: [
                      for (var i = 0; i < total; i++) ...[
                        if (i > 0) SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                        Expanded(
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: i <= stepIndex ? AppColors.brand : AppColors.grey200,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 단계 본문 공통 틀 — 좌우 여백 20 · 제목 · 설명 · 내용.
class SignupStepScaffold extends StatelessWidget {
  const SignupStepScaffold({
    super.key,
    required this.title,
    this.description,
    required this.children,
  });

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final h = ResponsiveHelper.spacing(context, 20);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(h, ResponsiveHelper.spacing(context, 8), h, h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            TextLayout.keepWords(title),
            semanticsLabel: title,
            style: ResponsiveHelper.subtitleStyle(context,
                color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          ),
          if (description != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text(
              TextLayout.keepWords(description!),
              semanticsLabel: description,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
            ),
          ],
          SizedBox(height: ResponsiveHelper.spacing(context, 20)),
          ...children,
        ],
      ),
    );
  }
}

/// 단계 안 안내 상자(중립 · 성공 · 주의). 위험색(빨강)은 쓰지 않는다.
enum SignupNoteTone { neutral, success, caution, progress }

class SignupNote extends StatelessWidget {
  const SignupNote({super.key, required this.tone, required this.text, this.title});

  final SignupNoteTone tone;
  final String? title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, IconData icon) = switch (tone) {
      SignupNoteTone.neutral => (AppColors.grey100, AppColors.textSecondary, Icons.info_outline),
      SignupNoteTone.success => (AppColors.successBg, AppColors.successDark, Icons.check_circle_outline),
      SignupNoteTone.caution => (AppColors.warningBg, AppColors.warningInk, Icons.error_outline),
      SignupNoteTone.progress => (AppColors.brandSurface, AppColors.brandDark, Icons.hourglass_top),
    };
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tone == SignupNoteTone.progress
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Icon(icon, size: 20, color: fg),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    TextLayout.keepWords(title!),
                    semanticsLabel: title,
                    style: ResponsiveHelper.bodyStyle(context, color: fg, fontWeight: FontWeight.w700),
                  ),
                if (title != null) SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  TextLayout.keepWords(text),
                  semanticsLabel: text,
                  style: ResponsiveHelper.smallStyle(context,
                      color: tone == SignupNoteTone.neutral ? AppColors.textPrimary : fg),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
