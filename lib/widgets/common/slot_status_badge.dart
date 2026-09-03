import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/slot_status_util.dart';

/// 슬롯/공고 상태 배지 공통 위젯
///
/// [compact] true = 개별 슬롯 카드·다이얼로그용 (작은 크기)
/// [compact] false = 그룹 카드용 (기본 크기)
/// [closedLabel] closed 상태일 때 '마감' 대신 표시할 레이블
///   예: '종료'(수동 종료), '지원 마감'(TIME_EXPIRED), '모집 완료'(FULL), '공고 만료'(POSTING_EXPIRED)
class SlotStatusBadge extends StatelessWidget {
  final SlotDisplayStatus status;
  final DateTime? scheduledAt;
  final bool compact;
  final String? closedLabel;

  const SlotStatusBadge({
    super.key,
    required this.status,
    this.scheduledAt,
    this.compact = false,
    this.closedLabel,
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
          // [4I.1] 종료 원인별 contextual 레이블
          //   '종료'(수동 종료) / '지원 마감'(TIME_EXPIRED) / '모집 완료'(FULL) / '공고 만료'(POSTING_EXPIRED)
          //   closedLabel 없으면 레거시 '마감' fallback
          label: closedLabel ?? '마감',
          color: AppColors.grey600,
          bgColor: AppColors.grey100,
        );
      case SlotDisplayStatus.scheduled:
        // [4I.1] publishAt이 현재보다 이전인데 SCHEDULED 상태 = scheduler 지연 또는 한도 초과 → '공개 대기'
        final now = DateTime.now();
        final isOverdue = scheduledAt != null && scheduledAt!.isBefore(now);
        final label = isOverdue
            ? '공개 대기'
            : (scheduledAt != null
                ? '${FormatHelper.formatDateTime(scheduledAt!)} 공개 예정'
                : '예약 공개');
        return _badge(
          context,
          icon: isOverdue ? Icons.hourglass_empty : Icons.schedule,
          label: label,
          color: AppColors.scheduledDark,
          bgColor: AppColors.scheduledBg,
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
          Text(label, style: textStyle, overflow: TextOverflow.ellipsis, maxLines: 1),
        ],
      ),
    );
  }
}
