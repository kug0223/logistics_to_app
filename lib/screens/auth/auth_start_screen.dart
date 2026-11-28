// lib/screens/auth/auth_start_screen.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · impl_plan §4.3] 시작 화면 — 로그인 안 된 사람이 처음 보는 화면.
//
//   주 행동 = '카카오로 시작하기'(가입·로그인 공통 입구). 보조 = '아이디로 로그인'(기존 아이디 계정 · QA).
//   새 아이디 가입 입구는 없다(B277-03 — 서버가 옛 가입을 막는다). 키가 없으면 카카오 버튼은 '준비 중'.
//
//   카카오 한 번의 결과(KakaoEntry):
//     로그인됨 → AuthWrapper 가 역할 화면으로 바꾼다(이 화면은 AuthWrapper 의 자식이라 저절로 사라진다)
//     두 역할  → 시트에서 고르기
//     가입 필요 → 가입 마법사(서버 세션 상태로 재개)
//     실패     → 화면 안 안내(토스트 대신 · 다시 시도 가능)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../services/auth/kakao_auth_service.dart';
import '../../services/auth/kakao_entry.dart';
import '../../services/auth/signup_api.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../widgets/auth/kakao_login_button.dart';
import '../../widgets/auth/role_login_choice_sheet.dart';
import '../../widgets/common/alfit_wordmark.dart';
import 'login_screen.dart';
import 'signup/signup_flow_screen.dart';

class AuthStartScreen extends StatefulWidget {
  const AuthStartScreen({super.key, this.gateway, this.api, this.signupScreenBuilder});

  /// 시험·시뮬레이터 대역. 생략하면 카카오 SDK.
  final LoginProviderGateway? gateway;

  /// 시험·시뮬레이터 대역. 생략하면 Firebase callable.
  final SignupApi? api;

  /// 시험용 — 가입 마법사 대신 다른 화면을 띄운다.
  final Widget Function(SignupSession session, SignupApi api)? signupScreenBuilder;

  @override
  State<AuthStartScreen> createState() => _AuthStartScreenState();
}

class _AuthStartScreenState extends State<AuthStartScreen> {
  late final LoginProviderGateway _gateway = widget.gateway ?? KakaoAuthService.instance;
  late final SignupApi _api = widget.api ?? FirebaseSignupApi();
  bool _busy = false;
  String? _notice;

  Future<String?> _signIn(String token) async {
    final up = context.read<UserProvider>();
    final ok = await up.signInWithCustomToken(token);
    if (ok || up.needsDeletionRecovery) return null;
    return up.error ?? '로그인하지 못했어요. 다시 시도해 주세요.';
  }

  Future<void> _startKakao() async {
    if (_busy) return;
    final up = context.read<UserProvider>();
    if (up.error != null) up.clearError();
    setState(() {
      _busy = true;
      _notice = null;
    });
    final entry = KakaoEntry(gateway: _gateway, api: _api, onToken: _signIn);
    try {
      var outcome = await entry.start();
      while (outcome is EntryRoleSelection) {
        if (!mounted) return;
        final role = await showRoleLoginChoiceSheet(context, outcome.roles);
        if (role == null) return;
        outcome = await entry.chooseRole(role);
      }
      if (!mounted) return;
      switch (outcome) {
        case EntrySignup(:final session):
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                widget.signupScreenBuilder?.call(session, _api) ??
                SignupFlowScreen(session: session, api: _api),
          ));
        case EntryFailed(:final message):
          setState(() => _notice = message);
        case EntryNotConfigured():
          setState(() => _notice = '카카오 로그인을 준비하고 있어요. 지금은 아이디 로그인만 쓸 수 있어요.');
        case EntryCanceled():
        case EntrySignedIn():
        case EntryDeletionRecovery():
        case EntryRoleSelection():
          break;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openIdLogin() async {
    final up = context.read<UserProvider>();
    if (up.error != null) up.clearError();
    // [app_impl_9 · 인증 문구 2026-11-26] 지난 카카오 시도의 안내는 새 시도(아이디 로그인)를 열 때 지운다.
    setState(() => _notice = null);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const LoginScreen(openedFromStart: true),
    ));
    if (!mounted) return;
    // 아이디 로그인 화면에서 돌아오면(그 화면의 '회원가입' 포함) 그 화면의 오류를 시작 화면에 남기지 않는다.
    final up2 = context.read<UserProvider>();
    if (up2.error != null) up2.clearError();
    setState(() => _notice = null);
  }

  @override
  Widget build(BuildContext context) {
    // 자동 복원에서 계정 상태로 세션이 정리됐으면 그 사유를 여기서 말한다(K7).
    final providerError = context.select<UserProvider, String?>((p) => p.error);
    final notice = _notice ?? providerError;
    final configured = _gateway.isConfigured;
    final gutter = ResponsiveHelper.spacing(context, 24);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: ResponsiveHelper.spacing(context, 56)),
                    // 워드마크는 고정 크기 위젯이다 — 글자 줄임 우회 없이 그림만 1.6배로 그린다(장식 · 낭독 'ALfit').
                    SizedBox(
                      height: AlfitWordmark.slotHeight * 1.6,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Transform.scale(
                          scale: 1.6,
                          alignment: Alignment.centerLeft,
                          child: const AlfitWordmark(),
                        ),
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                    Text(
                      TextLayout.keepWords('내 시간에 맞는 일,\n믿을 수 있는 약속'),
                      semanticsLabel: '내 시간에 맞는 일, 믿을 수 있는 약속',
                      style: ResponsiveHelper.titleStyle(context,
                          color: AppColors.textPrimary, fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                    // [app_impl_9 · 인증 문구 2026-11-26] 본인확인 수단은 KG 통합 간편인증(인증서 앱)이다 — '휴대폰 본인확인'이라고 하지 않는다(BL285-01).
                    Text(
                      TextLayout.keepWords('카카오 계정으로 간편하게 시작해요. 처음 한 번만 간편인증으로 본인확인을 해요.'),
                      semanticsLabel: '카카오 계정으로 간편하게 시작해요. 처음 한 번만 간편인증으로 본인확인을 해요.',
                      style: ResponsiveHelper.bodyStyle(context, color: AppColors.textSecondary),
                    ),
                    const Spacer(),
                    SizedBox(height: ResponsiveHelper.spacing(context, 32)),
                    if (notice != null) ...[
                      _NoticeBox(message: notice),
                      SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    ],
                    KakaoLoginButton(
                      configured: configured,
                      loading: _busy,
                      onPressed: _startKakao,
                    ),
                    if (!configured) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      Text(
                        TextLayout.keepWords('지금은 기존 아이디 계정으로만 로그인할 수 있어요.'),
                        semanticsLabel: '지금은 기존 아이디 계정으로만 로그인할 수 있어요.',
                        textAlign: TextAlign.center,
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                      ),
                    ],
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    TextButton(
                      onPressed: _busy ? null : _openIdLogin,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: Text(
                        TextLayout.keepWords('아이디로 로그인'),
                        semanticsLabel: '아이디로 로그인',
                        style: ResponsiveHelper.bodyStyle(context,
                            color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20, color: AppColors.textSecondary),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Text(
              TextLayout.keepWords(message),
              semanticsLabel: message,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
