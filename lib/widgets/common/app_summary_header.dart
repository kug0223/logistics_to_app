// lib/widgets/common/app_summary_header.dart
//
// 앱 전체 공통 통계 요약 헤더
// ─────────────────────────────────────────
// 사용법:
//   AppSummaryHeader(
//     stats: [
//       AppStat(label: '미이체', value: '472,849원', color: AppColors.warning),
//       AppStat(label: '송금 건수', value: '5건', color: AppColors.info),
//       AppStat(label: '이체완료', value: '79,835원', color: AppColors.success),
//     ],
//   )
//
// 표준값:
//   - 배경: primaryColor.withValues(alpha: 0.06)
//   - padding: (horizontal: 16, vertical: 12)
//   - 구분선: height 28, width 1, AppColors.grey200

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

class AppStat {
  final String label;
  final String value;
  final Color color;

  const AppStat({
    required this.label,
    required this.value,
    required this.color,
  });
}

class AppSummaryHeader extends StatelessWidget {
  final List<AppStat> stats;
  final EdgeInsets? padding;
  final Color? backgroundColor;

  const AppSummaryHeader({
    super.key,
    required this.stats,
    this.padding,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = backgroundColor ?? theme.primaryColor.withValues(alpha: 0.06);
    final items = <Widget>[];

    for (int i = 0; i < stats.length; i++) {
      if (i > 0) {
        items.add(Container(
          height: 28, width: 1,
          color: AppColors.grey200,
          margin: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12)),
        ));
      }
      items.add(Expanded(child: _StatItem(stat: stats[i])));
    }

    return Container(
      color: bg,
      padding: padding ??
          EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
      child: Row(children: items),
    );
  }
}

class _StatItem extends StatelessWidget {
  final AppStat stat;
  const _StatItem({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          stat.value,
          overflow: TextOverflow.ellipsis,
          style: ResponsiveHelper.smallStyle(context).copyWith(
              color: stat.color, fontWeight: FontWeight.w700),
        ),
        Text(
          stat.label,
          overflow: TextOverflow.ellipsis,
          style: ResponsiveHelper.tinyStyle(context,
              color: AppColors.grey500),
        ),
      ],
    );
  }
}
