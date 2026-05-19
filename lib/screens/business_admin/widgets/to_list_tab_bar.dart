import 'package:flutter/material.dart';
import '../../../models/core/to_model.dart';
import '../../../utils/responsive_helper.dart';

/// ✨ 세련된 TO 목록 탭 위젯 (진행중/마감됨)
class TOListTabs extends StatelessWidget {
  final String selectedTab;
  final ValueChanged<String> onTabChanged;

  const TOListTabs({
    super.key,
    required this.selectedTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.primaryColor.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // 진행중 탭
          Expanded(
            child: _buildTab(
              context: context,
              label: '진행중',
              value: TOStatus.active,
              isSelected: selectedTab == TOStatus.active,
              theme: theme,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          // 마감됨 탭
          Expanded(
            child: _buildTab(
              context: context,
              label: '마감됨',
              value: TOStatus.closed,
              isSelected: selectedTab == TOStatus.closed,
              theme: theme,
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 개별 탭 위젯
  Widget _buildTab({
    required BuildContext context,
    required String label,
    required String value,
    required bool isSelected,
    required ThemeData theme,
  }) {
    return GestureDetector(
      onTap: () {
        if (selectedTab != value) {
          onTabChanged(value);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 12),
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    theme.primaryColor,
                    theme.primaryColor.withValues(alpha: 0.85),
                  ],
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSelected) ...[
              Icon(
                value == TOStatus.active ? Icons.play_circle_outline : Icons.check_circle_outline,
                size: ResponsiveHelper.iconSize(context, 18),
                color: Colors.white,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            ],
            Text(
              label,
              textAlign: TextAlign.center,
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : theme.primaryColor.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}