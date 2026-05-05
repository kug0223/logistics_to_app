import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';  // ⭐ 추가
import '../../theme/app_colors.dart';
/// 공통 스타일 컨테이너 위젯 모음
/// 
/// 반복되는 Container + BoxDecoration 패턴을 공통화합니다.

/// 배지 스타일 컨테이너
/// 
/// 사용 예:
/// ```dart
/// StyledBadge(
///   label: '단기',
///   backgroundColor: AppColors.infoExtraLight!,
///   textColor: AppColors.infoDark!,
/// )
/// ```
class StyledBadge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final IconData? icon;
  final double? fontSize;  // ⭐ nullable로 변경
  final EdgeInsets? padding;
  final double borderRadius;
  
  const StyledBadge({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.icon,
    this.fontSize,  // ⭐ 기본값 제거
    this.padding,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveFontSize = fontSize ?? ResponsiveHelper.getFontSize(context, 12);
    
    return Container(
      padding: padding ?? EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon, 
              size: ResponsiveHelper.iconSize(context, effectiveFontSize + 2), 
              color: textColor
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: effectiveFontSize,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// 아웃라인 배지 (테두리 있는 배지)
/// 
/// 사용 예:
/// ```dart
/// StyledOutlineBadge(
///   label: '진행중',
///   color: AppColors.infoMedium!,
/// )
/// ```
class StyledOutlineBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color? backgroundColor;
  final IconData? icon;
  final double? fontSize;  // ⭐ nullable로 변경
  final EdgeInsets? padding;
  final double borderRadius;
  final double borderWidth;
  
  const StyledOutlineBadge({
    super.key,
    required this.label,
    required this.color,
    this.backgroundColor,
    this.icon,
    this.fontSize,  // ⭐ 기본값 제거
    this.padding,
    this.borderRadius = 12,
    this.borderWidth = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveFontSize = fontSize ?? ResponsiveHelper.getFontSize(context, 11);
    
    return Container(
      padding: padding ?? EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: color, width: borderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon, 
              size: ResponsiveHelper.iconSize(context, effectiveFontSize + 1), 
              color: color
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: effectiveFontSize,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 칩 스타일 컨테이너 (삭제 버튼 포함 가능)
/// 
/// 사용 예:
/// ```dart
/// StyledChip(
///   label: '11/01',
///   backgroundColor: AppColors.infoDark!,
///   textColor: Colors.white,
///   onDelete: () => debugPrint('삭제'),
/// )
/// ```
class StyledChip extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback? onDelete;
  final IconData? icon;
  final double? fontSize;  // ⭐ nullable로 변경
  final EdgeInsets? padding;
  final double borderRadius;
  
  const StyledChip({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.onDelete,
    this.icon,
    this.fontSize,  // ⭐ 기본값 제거
    this.padding,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveFontSize = fontSize ?? ResponsiveHelper.getFontSize(context, 13);
    
    return Container(
      padding: padding ?? EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon, 
              size: ResponsiveHelper.iconSize(context, effectiveFontSize - 1), 
              color: textColor
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          ],
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: effectiveFontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onDelete != null) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 3)),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close, 
                  size: ResponsiveHelper.iconSize(context, 12), 
                  color: textColor
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 정보 카드 (배경색 + 테두리)
/// 
/// 사용 예:
/// ```dart
/// StyledInfoCard(
///   backgroundColor: AppColors.successBg!,
///   borderColor: AppColors.successLight!,
///   child: Text('연속된 날짜입니다'),
/// )
/// ```
class StyledInfoCard extends StatelessWidget {
  final Widget child;
  final Color backgroundColor;
  final Color borderColor;
  final EdgeInsets? padding;
  final double borderRadius;
  final double borderWidth;
  
  const StyledInfoCard({
    super.key,
    required this.child,
    required this.backgroundColor,
    required this.borderColor,
    this.padding,
    this.borderRadius = 8,
    this.borderWidth = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: child,
    );
  }
}

/// 아이콘 컨테이너 (원형 배경)
/// 
/// 사용 예:
/// ```dart
/// StyledIconContainer(
///   icon: Icons.work,
///   backgroundColor: AppColors.infoExtraLight!,
///   iconColor: AppColors.infoDark!,
/// )
/// ```
class StyledIconContainer extends StatelessWidget {
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final double? size;  // ⭐ nullable로 변경
  final double? iconSize;  // ⭐ nullable로 변경
  final BoxShape shape;
  final double borderRadius;
  
  const StyledIconContainer({
    super.key,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    this.size,  // ⭐ 기본값 제거
    this.iconSize,  // ⭐ 기본값 제거
    this.shape = BoxShape.circle,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveSize = size ?? ResponsiveHelper.iconSize(context, 40);
    final effectiveIconSize = iconSize ?? ResponsiveHelper.iconSize(context, 24);
    
    return Container(
      width: effectiveSize,
      height: effectiveSize,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: shape == BoxShape.circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: shape == BoxShape.circle ? null : BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: Icon(
          icon,
          size: effectiveIconSize,
          color: iconColor,
        ),
      ),
    );
  }
}

/// 상태별 배지 (미리 정의된 색상)
/// 
/// 사용 예:
/// ```dart
/// StatusBadge.success(label: '승인됨')
/// StatusBadge.error(label: '거절됨')
/// StatusBadge.warning(label: '대기중')
/// StatusBadge.info(label: '진행중')
/// ```
class StatusBadge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final IconData? icon;
  
  const StatusBadge({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.icon,
  });

  /// 성공 (녹색)
  factory StatusBadge.success({
    required String label,
    IconData? icon,
  }) {
    return StatusBadge(
      label: label,
      backgroundColor: AppColors.successBg,
      textColor: AppColors.successDark,
      icon: icon ?? Icons.check_circle,
    );
  }

  /// 에러 (빨간색)
  factory StatusBadge.error({
    required String label,
    IconData? icon,
  }) {
    return StatusBadge(
      label: label,
      backgroundColor: AppColors.errorBg,
      textColor: AppColors.errorDark,
      icon: icon ?? Icons.error,
    );
  }

  /// 경고 (오렌지)
  factory StatusBadge.warning({
    required String label,
    IconData? icon,
  }) {
    return StatusBadge(
      label: label,
      backgroundColor: AppColors.warningBg,
      textColor: AppColors.warningDark,
      icon: icon ?? Icons.warning,
    );
  }
  /// 정보 (파란색)
  factory StatusBadge.info({
    required String label,
    IconData? icon,
  }) {
    return StatusBadge(
      label: label,
      backgroundColor: AppColors.infoBg,
      textColor: AppColors.infoDark,
      icon: icon ?? Icons.info,
    );
  }

  /// 중립 (회색)
  factory StatusBadge.neutral({
    required String label,
    IconData? icon,
  }) {
    return StatusBadge(
      label: label,
      backgroundColor: AppColors.grey200,
      textColor: AppColors.grey700,
      icon: icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StyledBadge(
      label: label,
      backgroundColor: backgroundColor,
      textColor: textColor,
      icon: icon,
    );
  }
}