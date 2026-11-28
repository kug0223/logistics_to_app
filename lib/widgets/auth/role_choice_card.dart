// lib/widgets/auth/role_choice_card.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · §4.3] 이용 목적 선택 카드.
//   가입 화면(RegisterScreen._buildRoleCard)의 시각 규칙을 새 위젯으로 옮겼다 — 원본은 핀 시험이 있어 그대로 둔다.
//   아이콘 + 제목 + 설명 1줄 · 선택 = 브랜드 테두리 2 + 옅은 브랜드 바탕 + 체크. 낱말 단위 줄바꿈.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';

class RoleChoiceCard extends StatelessWidget {
  const RoleChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.brand;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 72),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 14),
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.brandSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? primary : AppColors.border,
              width: selected ? 2.0 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected ? AppColors.surface : AppColors.grey100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: selected ? primary : AppColors.grey600, size: 22),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TextLayout.keepWords(title),
                      semanticsLabel: title,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: selected ? AppColors.brandDark : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                    Text(
                      TextLayout.keepWords(description),
                      semanticsLabel: description,
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                Icon(Icons.check_rounded, color: primary, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
