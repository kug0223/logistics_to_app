import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

/// 앱 공통 필터 칩
///
/// - [solid] = false (기본, subtle): 미선택=grey, 선택=색상 12% 배경
/// - [solid] = true: 미선택=grey, 선택=색상 완전 채움 + 흰 텍스트
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.color,
    this.leadingIcon,
    this.count,
    this.solid = false,
    this.onClear,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  /// 선택 시 색상 — null이면 theme.primaryColor 사용
  final Color? color;

  /// 좌측 아이콘 (subtle 스타일에서 주로 사용)
  final IconData? leadingIcon;

  /// 우측 카운트 뱃지
  final int? count;

  /// true이면 solid 스타일 (선택 시 색상 완전 채움, 흰 텍스트)
  final bool solid;

  /// X 버튼 콜백 — solid에서 선택 상태일 때 X 아이콘 표시
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? Theme.of(context).primaryColor;
    return solid
        ? _buildSolid(context, activeColor)
        : _buildSubtle(context, activeColor);
  }

  Widget _buildSubtle(BuildContext context, Color activeColor) {
    final textColor = isSelected ? activeColor : AppColors.grey500;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 10),
          vertical: ResponsiveHelper.spacing(context, 4),
        ),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.12) : AppColors.grey100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : AppColors.grey200,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon != null) ...[
              Icon(
                leadingIcon,
                size: ResponsiveHelper.iconSize(context, 14),
                color: textColor,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            ],
            Text(
              label,
              style: ResponsiveHelper.smallStyle(context).copyWith(
                color: textColor,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
            if (count != null && count! > 0) ...[
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 5),
                  vertical: ResponsiveHelper.spacing(context, 1),
                ),
                decoration: BoxDecoration(
                  color: isSelected ? activeColor : AppColors.grey300,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${count!}',
                  style: ResponsiveHelper.tinyStyle(
                    context,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSolid(BuildContext context, Color activeColor) {
    final bgColor = isSelected ? activeColor : Theme.of(context).cardColor;
    final contentColor = isSelected ? Colors.white : AppColors.grey500;
    final hasTrailing = isSelected && onClear != null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, hasTrailing ? 10 : 12),
          vertical: ResponsiveHelper.spacing(context, 6),
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : AppColors.grey300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: ResponsiveHelper.smallStyle(context).copyWith(
                color: contentColor,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            if (hasTrailing)
              Semantics(
                button: true,
                label: '필터 삭제',
                child: GestureDetector(
                  onTap: onClear,
                  child: Icon(
                    Icons.close,
                    size: ResponsiveHelper.iconSize(context, 14),
                    color: contentColor,
                  ),
                ),
              )
            else
              Icon(
                Icons.keyboard_arrow_down,
                size: ResponsiveHelper.iconSize(context, 16),
                color: contentColor,
              ),
          ],
        ),
      ),
    );
  }
}
