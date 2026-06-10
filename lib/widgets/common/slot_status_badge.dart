import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/slot_status_util.dart';

/// 슬롯/공고 상태 배지 공통 위젯
///
/// [compact] true = 개별 슬롯 카드·다이얼로그용 (작은 크기)
/// [compact] false = 그룹 카드용 (기본 크기)
class SlotStatusBadge extends StatelessWidget {
  final SlotDisplayStatus status;
  final DateTime? scheduledAt;
  final bool compact;

  const SlotStatusBadge({
    super.key,
    required this.status,
    this.scheduledAt,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case SlotDisplayStatus.draft:
        return _badge(
          context,
          icon: Icons.visibility_off_outlined,
          label: '미공개',
          color: AppColors.grey500,
          bgColor: AppColors.grey100,
        );
      case SlotDisplayStatus.closed:
        return _badge(
          context,
          icon: Icons.lock,
          label: '마감',
          color: AppColors.grey600,
          bgColor: AppColors.grey100,
        );
      case SlotDisplayStatus.scheduled:
        final label = scheduledAt != null
            ? '${FormatHelper.formatDateTime(scheduledAt!)} 오픈'
            : '예약';
        return _badge(
          context,
          icon: Icons.schedule,
          label: label,
          color: AppColors.scheduledDark,
          bgColor: AppColors.scheduledBg,
        );
      case SlotDisplayStatus.full:
        return _badge(
          context,
          icon: Icons.check_circle_outline,
          label: '충족',
          color: AppColors.successDark,
          bgColor: AppColors.successBg,
        );
      case SlotDisplayStatus.recruiting:
        return _badge(
          context,
          icon: Icons.campaign,
          label: '모집중',
          color: AppColors.successDark,
          bgColor: AppColors.successBg,
        );
    }
  }

  Widget _badge(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
  }) {
    final hPad = compact
        ? ResponsiveHelper.spacing(context, 6)
        : ResponsiveHelper.spacing(context, 8);
    final vPad = compact
        ? ResponsiveHelper.spacing(context, 3)
        : ResponsiveHelper.spacing(context, 4);
    final iconSize = compact
        ? ResponsiveHelper.iconSize(context, 10)
        : ResponsiveHelper.iconSize(context, 12);
    final textStyle = compact
        ? ResponsiveHelper.tinyStyle(context, color: color)
            .copyWith(fontWeight: FontWeight.w600)
        : ResponsiveHelper.smallStyle(context, color: color);
    final radius = compact ? 6.0 : 12.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, compact ? 3 : 4)),
          Text(label, style: textStyle),
        ],
      ),
    );
  }
}
