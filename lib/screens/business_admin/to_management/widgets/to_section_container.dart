import 'package:flutter/material.dart';
import '../../../../theme/app_colors.dart';
import '../../../../utils/responsive_helper.dart';

/// ✨ TO 섹션 공통 컨테이너
/// create_to_screen, edit_to_screen에서 공통으로 사용하는 카드 컨테이너
class TOSectionContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;

  const TOSectionContainer({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.grey500.withValues(alpha: 0.15),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}