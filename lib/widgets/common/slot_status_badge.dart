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
///   예: '종료'(수동 종료), '지원 마감'(TIME_EXPIRED), '공고 만료'(POSTING_EXPIRED)
/// [recruitmentComplete] closed의 원인이 **인원 충족**인가.
///   [POSTING-V2-03S.1] 모집 종료와 근무 종료는 다른 축이다. 인원이 다 찬 것은
///   모집 흐름의 성공이지 공고가 끝난 것이 아니다 — 내일 근무일 수도 있다.
///   이전에는 만료 공고와 같은 회색·자물쇠라 목록 스캔에서 구별되지 않았다.
class SlotStatusBadge extends StatelessWidget {
  static const String recruitmentCompleteLabel = '모집 완료';

  final SlotDisplayStatus status;
  final DateTime? scheduledAt;
  final bool compact;
  final String? closedLabel;
  final bool recruitmentComplete;

  const SlotStatusBadge({
    super.key,
    required this.status,
    this.scheduledAt,
    this.compact = false,
    this.closedLabel,
    this.recruitmentComplete = false,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case SlotDisplayStatus.draft:
        // [POSTING-V2-03S.1] 아직 작성·준비 중이지 취소된 것이 아니다.
        //   이전 grey500/grey100은 AppColors.canceled/canceledBg와 값이 같아,
        //   준비 상태가 취소 상태와 똑같이 보였다. outline으로 분리한다 —
        //   같은 grey family를 써도 surface treatment가 다르면 구별된다.
        return _badge(
          context,
          icon: Icons.edit_note,
          label: '미공개',
          color: AppColors.grey700,
          bgColor: Colors.transparent,
          borderColor: AppColors.grey300,
        );
      case SlotDisplayStatus.closed:
        // [POSTING-V2-03S.1] 인원 충족은 모집 흐름의 **성공**이다.
        //   자물쇠와 회색은 "더 이상 못 한다"를 말하므로 여기 쓰지 않는다.
        if (recruitmentComplete) {
          return _badge(
            context,
            icon: Icons.check_circle,
            label: closedLabel ?? recruitmentCompleteLabel,
            color: AppColors.successDark,
            bgColor: AppColors.successBg,
          );
        }
        // 실제로 끝난 상태들: 수동 종료 / 지원 마감 / 공고 만료.
        //   grey600 → grey700: 13px 라벨이 grey100 위에서 너무 옅었다.
        return _badge(
          context,
          icon: Icons.lock,
          // [4I.1] 종료 원인별 contextual 레이블
          //   '종료'(수동 종료) / '지원 마감'(TIME_EXPIRED) / '공고 만료'(POSTING_EXPIRED)
          //   closedLabel 없으면 레거시 '마감' fallback
          label: closedLabel ?? '마감',
          color: AppColors.grey700,
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
    Color? borderColor,
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
        // [POSTING-V2-03S.1] outline 전용 — 미공개가 filled closed와 다른
        //   surface treatment를 갖게 한다. 나머지 상태는 border가 없다.
        border: borderColor == null
            ? null
            : Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, compact ? 3 : 4)),
          // [POSTING-V2-03R.1] Flexible이 없으면 Text가 부모의 maxWidth 전체를
          //   받아 ellipsis가 동작하지 않고, 배지가 같은 Row의 날짜를 0폭으로
          //   밀어냈다. `9/20 14:00 공개 예정` 같은 긴 라벨에서 실제로 그렇다.
          Flexible(
            child: Text(label,
                style: textStyle,
                overflow: TextOverflow.ellipsis,
                maxLines: 1),
          ),
        ],
      ),
    );
  }
}
