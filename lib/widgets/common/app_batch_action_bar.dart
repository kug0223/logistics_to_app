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
// 표준값:
//   - 배경: AppColors.infoBg
//   - padding: (horizontal:12, vertical:6)
//   - 액션 버튼 배경: AppColors.success

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';

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
    return Container(
      color: AppColors.infoBg,
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                TextButton(
                  onPressed: onSelectAll,
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(36, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: Text('전체선택',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.info, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 2),
                TextButton(
                  onPressed: onDeselectAll,
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(32, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: Text('해제',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.info, fontWeight: FontWeight.w600)),
                ),
                if (selectedCount > 0 && selectedAmount > 0) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      FormatHelper.formatWage(selectedAmount),
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.infoDark,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 30,
            child: ElevatedButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon, size: 13),
              label: Text('$selectedCount건 $actionLabel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 10),
                  vertical: 0,
                ),
                textStyle: ResponsiveHelper.tinyStyle(context,
                    fontWeight: FontWeight.w600),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
