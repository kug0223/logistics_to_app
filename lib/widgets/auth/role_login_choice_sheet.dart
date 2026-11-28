// lib/widgets/auth/role_login_choice_sheet.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · §2.1 ROLE_SELECTION_REQUIRED] 같은 카카오 계정에 근무자·사업주 두 계정이
//   있을 때 어느 쪽으로 들어갈지 고르는 시트. DialogHelper.showSheet 전용(useSafeArea · 둥근 모서리).
//   두 계정은 서로 다른 UID 다 — 고른 쪽으로만 로그인한다(전환은 로그아웃 후 다시).

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import 'role_choice_card.dart';

/// 고른 역할('USER' | 'BUSINESS_ADMIN') 또는 null(닫음).
Future<String?> showRoleLoginChoiceSheet(BuildContext context, List<String> roles) {
  return DialogHelper.showSheet<String>(
    context,
    isScrollControlled: true,
    builder: (ctx) => RoleLoginChoiceSheet(roles: roles),
  );
}

class RoleLoginChoiceSheet extends StatelessWidget {
  const RoleLoginChoiceSheet({super.key, required this.roles});

  final List<String> roles;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            TextLayout.keepWords('어떤 계정으로 들어갈까요?'),
            semanticsLabel: '어떤 계정으로 들어갈까요?',
            style: ResponsiveHelper.subtitleStyle(context,
                color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          Text(
            TextLayout.keepWords('이 카카오 계정에 근무자 계정과 사업주 계정이 함께 있어요.'),
            semanticsLabel: '이 카카오 계정에 근무자 계정과 사업주 계정이 함께 있어요.',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          if (roles.contains('USER'))
            RoleChoiceCard(
              icon: Icons.work_outline,
              title: '근무자로 들어가기',
              description: '일자리 찾기 · 내 일정 · 급여',
              selected: false,
              onTap: () => Navigator.of(context).pop('USER'),
            ),
          if (roles.contains('USER') && roles.contains('BUSINESS_ADMIN'))
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          if (roles.contains('BUSINESS_ADMIN'))
            RoleChoiceCard(
              icon: Icons.storefront_outlined,
              title: '사업주로 들어가기',
              description: '공고 · 지원자 · 근무 관리',
              selected: false,
              onTap: () => Navigator.of(context).pop('BUSINESS_ADMIN'),
            ),
        ],
      ),
    );
  }
}
