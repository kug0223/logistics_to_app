import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

/// 텍스트 + 카운트 배지로 구성된 탭 라벨 공통 위젯
///
/// TabBar의 Tab(child: AppTabLabel(...)) 형태로 사용
/// count가 null이면 배지 없이 텍스트만 표시
class AppTabLabel extends StatelessWidget {
  final String label;

  /// null이면 배지 미표시
  final int? count;

  /// null이면 theme.primaryColor 사용
  final Color? badgeColor;

  /// true면 배지가 solid red로 강조 (예: 미완료 항목이 있을 때)
  final bool urgent;

  const AppTabLabel({
    super.key,
    required this.label,
    this.count,
    this.badgeColor,
    this.urgent = false,
  });

  @override
  Widget build(BuildContext context) {
    if (count == null && !urgent) {
      return Text(label);
    }

    final effectiveColor = badgeColor ?? Theme.of(context).primaryColor;
    final displayCount = count ?? 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        SizedBox(width: ResponsiveHelper.spacing(context, 5)),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 6),
            vertical: ResponsiveHelper.spacing(context, 2),
          ),
          decoration: BoxDecoration(
            color: urgent
                ? AppColors.error
                : effectiveColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$displayCount',
            style: ResponsiveHelper.tinyStyle(
              context,
              color: urgent ? Colors.white : effectiveColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
