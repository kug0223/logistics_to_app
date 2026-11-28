// lib/screens/auth/signup/signup_complete_step.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · §2.4/§2.5 · 대표 결정 2026-11-25] 가입 완료 → 바로 홈.
//
//   예전에는 여기서 '시작 준비' 목록을 보였다. 이제 회원 완료 + 로그인 준비가 끝나면 이 화면은 곧바로 닫히고
//   (SignupFlowScreen), 아래 AuthWrapper 가 첫 안내(3장 · 건너뛰기) → 홈으로 보낸다. 해야 할 준비는
//   홈 상단 「시작 준비」 카드(근무자)와 공고 준비 카드(사업주)가 단계별로 안내한다.
//
//   이 화면이 실제로 머무는 경우는 예외 상태뿐이다:
//     · 로그인 준비 중(토큰 받는 중) — 진행 표시
//     · 커밋은 됐는데 로그인 준비 실패(authPending) — '가입은 저장됐어요' + 다시 시도(같은 UID · B277-01)

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../utils/responsive_helper.dart';
import 'signup_flow_controller.dart';
import 'signup_flow_screen.dart';

class SignupCompleteStep extends StatelessWidget {
  const SignupCompleteStep({super.key, required this.controller});

  final SignupFlowController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final children = <Widget>[
      Center(
        child: Container(
          width: ResponsiveHelper.spacing(context, 72),
          height: ResponsiveHelper.spacing(context, 72),
          decoration: const BoxDecoration(color: AppColors.brandSurface, shape: BoxShape.circle),
          child: Icon(Icons.check_rounded,
              size: ResponsiveHelper.spacing(context, 40), color: AppColors.brand),
        ),
      ),
      SizedBox(height: ResponsiveHelper.spacing(context, 20)),
    ];
    if (c.authPending) {
      children.add(SignupNote(
        tone: SignupNoteTone.caution,
        title: '가입은 저장됐어요',
        text: c.message ?? '로그인 준비를 마무리하지 못했어요. 다시 시도해 주세요.',
      ));
    } else if (!c.signedIn) {
      children.add(const SignupNote(tone: SignupNoteTone.progress, text: '로그인을 준비하고 있어요.'));
    } else {
      children.add(const SignupNote(tone: SignupNoteTone.success, text: '홈으로 이동하고 있어요.'));
    }
    return SignupStepScaffold(
      title: '가입을 마쳤어요',
      description: '필요한 준비는 홈에서 하나씩 안내해 드려요.',
      children: children,
    );
  }
}
