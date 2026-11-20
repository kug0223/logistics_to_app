// lib/widgets/common/app_batch_action_bar.dart
//
// 앱 전체 공통 일괄 선택 액션 바
// ─────────────────────────────────────────
// 사용법:
//   AppBatchActionBar(
//     selectedCount: _selectedIds.length,
//     selectedAmount: _selectedAmount,   // 선택 (0이면 미표시)
//     onSelectAll: _selectAll,
//     onDeselectAll: _deselectAll,
//     onAction: _markBatch,              // null이면 버튼 비활성
//     actionLabel: '송금 처리',          // 기본: '처리'
//     actionIcon: Icons.send,            // 기본: Icons.check
//   )
//
// 표준값([DU257] 시안 기준으로 갱신):
//   - 면: 흰(surface) + 위 선 grey200 — 화면 아래 행동 영역
//   - 선택 행동(전체선택·해제): 대표색 글자 13 w600, 터치 48×48
//   - 선택 금액: 본문색 15 w700
//   - 실행 버튼: 앱 테마 ElevatedButton(대표색 채움·흰 글자·최소 높이 48·반경 12)
//   - 글자 1.3배 이상: 선택 줄 위, 실행 버튼 아래(전체 폭)
//   이전: infoBg 면·info 글자(2.74)·터치 28·초록 버튼 흰 12(2.78)·높이 30

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import 'amount_text.dart';

class AppBatchActionBar extends StatelessWidget {
  final int selectedCount;
  final int selectedAmount;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;
  final VoidCallback? onAction;
  final String actionLabel;
  final IconData actionIcon;

  const AppBatchActionBar({
    super.key,
    required this.selectedCount,
    this.selectedAmount = 0,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onAction,
    this.actionLabel = '처리',
    this.actionIcon = Icons.check,
  });

  @override
  Widget build(BuildContext context) {
    // [DU257] 시안 기준 — 흰 면·위 선, 선택 행동은 대표색 글자(터치 48), 주 행동은 대표색 채움(테마, 48).
    //   글자 1.3배 이상이면 선택 줄 위·실행 버튼 아래(전체 폭)로 세운다(DU256 정보 줄과 같은 기준).
    final stacked = MediaQuery.textScalerOf(context).scale(10) >= 13;
    TextButton choice(String label, VoidCallback onPressed) => TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
              foregroundColor: AppColors.brand,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: Text(label,
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.brand, fontWeight: FontWeight.w600)),
        );
    // [R7-P2-4 P24-G] `전체선택`·`해제` 는 **행동 이름**이라 줄이지 않고 줄바꿈시킨다.
    final controls = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        choice('전체선택', onSelectAll),
        choice('해제', onDeselectAll),
        if (selectedCount > 0 && selectedAmount > 0) ...[
          const SizedBox(width: 6),
          // [UI-INTEGRATION.33] 선택 금액을 말줄임하지 않는다(1억 이상 선택 시 끝자리가
          //   '…' 로 사라졌다) — 쉼표 뒤에서만 줄을 바꾼다.
          AmountText(
            FormatHelper.formatWage(selectedAmount),
            style: ResponsiveHelper.bodyStyle(context,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700),
          ),
        ],
      ],
    );
    // [DU257 r1] 실행 글자는 낱말 단위로 줄을 바꾼다(B320 전체 폭 버튼에서 '12건 이체 완료 처/리' 로 끊겼다).
    final actionText = '${FormatHelper.formatNumber(selectedCount)}건 $actionLabel';
    final action = ElevatedButton.icon(
      onPressed: onAction,
      icon: Icon(actionIcon, size: 18),
      label: Text(TextLayout.keepWords(actionText), semanticsLabel: actionText),
      // 색·높이·반경은 앱 테마(대표색 채움·흰 글자·최소 48·반경 12)
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: 10,
        ),
        textStyle: ResponsiveHelper.bodyStyle(context, fontWeight: FontWeight.w700),
      ),
    );
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.grey200)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      child: stacked
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [controls, const SizedBox(height: 8), action],
            )
          : Row(
              children: [
                Expanded(child: controls),
                const SizedBox(width: 8),
                action,
              ],
            ),
    );
  }
}
