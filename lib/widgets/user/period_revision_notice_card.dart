// lib/widgets/user/period_revision_notice_card.dart
//
// [R7-CONTRACT-PERIOD-DISCLOSURE] 근무 종료일이 바뀐 사실을 **당사자에게**
// 말하는 자리.
//
//   오류가 아니다. 약속이 바뀌었다는 고지다. 그래서 빨간 경고로 만들지
//   않고 정보 톤으로 둔다. 다만 **언제에서 언제로** 바뀌었는지는 분명히
//   보여야 한다 — 그게 이 카드의 존재 이유다.
//
//   계약 전이면 "계약이 변경되었습니다" 라고 쓰지 않는다. 아직 계약이
//   아니다. 바뀐 것은 **근무기간**이다.
//
//   판정은 하지 않는다 — `PeriodRevisionDisclosure` 가 한다.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/period_revision_disclosure.dart';
import '../../utils/responsive_helper.dart';

class PeriodRevisionNoticeCard extends StatelessWidget {
  const PeriodRevisionNoticeCard({
    super.key,
    required this.disclosure,
    this.scale = 1.0,
  });

  final PeriodRevisionDisclosure disclosure;
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (!disclosure.shouldShow) return const SizedBox.shrink();
    final s = scale;
    final from = FormatHelper.formatDateCompact(disclosure.presentedEndDate!);
    final to = FormatHelper.formatDateCompact(disclosure.appliedEndDate!);

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: 8 * s),
      padding: EdgeInsets.all(10 * s),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.event_repeat_outlined,
              size: 16 * s, color: AppColors.infoDark),
          SizedBox(width: 8 * s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '근무 종료일이 변경되었습니다',
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: AppColors.infoDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2 * s),
                // 날짜가 길어지거나 배율이 커지면 줄을 바꾼다 — 자르지 않는다.
                Wrap(
                  spacing: 6 * s,
                  runSpacing: 2 * s,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('지원 당시 $from',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.textSecondary)),
                    Icon(Icons.arrow_forward_rounded,
                        size: 13 * s, color: AppColors.textTertiary),
                    Text('현재 적용 $to',
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        )),
                  ],
                ),
                SizedBox(height: 2 * s),
                Text(
                  '계약 전에 변경된 근무기간을 확인해 주세요.',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
