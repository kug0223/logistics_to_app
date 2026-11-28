// lib/screens/auth/signup/signup_existing_account_step.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · §2.6] 같은 본인 · 같은 역할의 계정이 이미 있을 때(IDENTITY_ROLE_TAKEN).
//   1차는 연결하지 않고 거부 + 안내다(clean cutover · C278-5). 새 흐름 계정은 늘 카카오 연결과 함께 태어나므로
//   '이미 가입' = 다른 카카오 계정으로 가입했다는 뜻이다. 상대 계정 정보는 보여 주지 않는다.
//   중립색 — 사용자의 잘못이 아니므로 위험색(빨강)을 쓰지 않는다.
//
//   그리고 가입을 이어갈 수 없는 경우(재가입 제한 · 세션 만료 등)의 안내 화면도 여기 둔다.

import 'package:flutter/material.dart';

import '../../../services/auth/signup_api.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/responsive_helper.dart';
import 'signup_flow_screen.dart';

class SignupExistingAccountStep extends StatelessWidget {
  const SignupExistingAccountStep({super.key, this.role, this.joinedMonth});

  final String? role;

  /// 서버가 주면(예: '2026-11') '가입한 달' 만 보인다 — 상대 계정의 다른 정보는 없다.
  final String? joinedMonth;

  @override
  Widget build(BuildContext context) {
    final label = SignupCopy.roleLabel(role);
    final head = label.isEmpty
        ? '같은 본인확인 정보로 가입한 계정이 이미 있어요.'
        : '같은 본인확인 정보로 가입한 $label 계정이 이미 있어요.';
    return SignupStepScaffold(
      title: '이미 가입된 계정이 있어요',
      description: head,
      children: [
        _bigIcon(context, Icons.person_search_outlined),
        SizedBox(height: ResponsiveHelper.spacing(context, 20)),
        if (_month(joinedMonth) != null) ...[
          SignupNote(tone: SignupNoteTone.neutral, text: '가입한 달 · ${_month(joinedMonth)}'),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        ],
        const SignupNote(
          tone: SignupNoteTone.neutral,
          title: '처음 가입한 카카오 계정으로 로그인해 주세요',
          text: '한 사람은 역할마다 계정을 하나만 만들 수 있어요. 지금 카카오 계정으로는 새 계정을 만들지 않았어요.',
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        const SignupNote(
          tone: SignupNoteTone.neutral,
          text: '어떤 카카오 계정으로 가입했는지 기억나지 않으면 고객센터에 문의해 주세요.',
        ),
      ],
    );
  }
}

String? _month(String? ym) {
  if (ym == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{1,2})').firstMatch(ym);
  if (m == null) return null;
  return '${m.group(1)}년 ${int.parse(m.group(2)!)}월';
}

class SignupBlockedStep extends StatelessWidget {
  const SignupBlockedStep({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message ?? '가입 진행 시간이 지났어요. 카카오로 다시 시작해 주세요.';
    return SignupStepScaffold(
      title: '지금은 가입을 이어갈 수 없어요',
      children: [
        _bigIcon(context, Icons.pause_circle_outline),
        SizedBox(height: ResponsiveHelper.spacing(context, 20)),
        SignupNote(tone: SignupNoteTone.neutral, text: text),
      ],
    );
  }
}

Widget _bigIcon(BuildContext context, IconData icon) => Center(
      child: Container(
        width: ResponsiveHelper.spacing(context, 72),
        height: ResponsiveHelper.spacing(context, 72),
        decoration: const BoxDecoration(color: AppColors.grey100, shape: BoxShape.circle),
        child: Icon(icon,
            size: ResponsiveHelper.spacing(context, 36), color: AppColors.textSecondary),
      ),
    );
