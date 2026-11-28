// lib/screens/auth/signup/signup_purpose_step.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · §4.3] 이용 목적 — 일할게요 / 사람을 구할게요.
//   고른 역할은 본인확인(KG) 준비 때 서버가 cert 에 고정한다. 본인확인 뒤 역할을 바꾸면 본인확인을 다시 한다.

import 'package:flutter/material.dart';

import '../../../services/auth/signup_api.dart';
import '../../../utils/responsive_helper.dart';
import '../../../widgets/auth/role_choice_card.dart';
import 'signup_flow_controller.dart';
import 'signup_flow_screen.dart';

class SignupPurposeStep extends StatelessWidget {
  const SignupPurposeStep({super.key, required this.controller});

  final SignupFlowController controller;

  @override
  Widget build(BuildContext context) {
    final role = controller.selectedRole;
    return SignupStepScaffold(
      title: '알핏을 어떻게 쓰실 건가요?',
      description: '고른 목적에 맞춰 계정을 만들어요. 다른 목적도 나중에 추가할 수 있어요.',
      children: [
        RoleChoiceCard(
          icon: Icons.work_outline,
          title: SignupCopy.roleUser,
          description: SignupCopy.roleUserDesc,
          selected: role == 'USER',
          onTap: controller.busy ? null : () => controller.choosePurpose('USER'),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        RoleChoiceCard(
          icon: Icons.storefront_outlined,
          title: SignupCopy.roleAdmin,
          description: SignupCopy.roleAdminDesc,
          selected: role == 'BUSINESS_ADMIN',
          onTap: controller.busy ? null : () => controller.choosePurpose('BUSINESS_ADMIN'),
        ),
        if (controller.message != null) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          SignupNote(tone: SignupNoteTone.caution, text: controller.message!),
        ],
      ],
    );
  }
}
