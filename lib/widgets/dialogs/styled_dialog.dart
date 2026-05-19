// lib/widgets/dialogs/styled_dialog.dart

import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';

/// ✨ 세련된 다이얼로그 위젯
/// 
/// 역할별 테마에 맞는 그라데이션 헤더와 통일된 디자인 제공
/// 
/// 사용 예:
/// ```dart
/// await showDialog(
///   context: context,
///   builder: (context) => StyledDialog(
///     title: '비밀번호 변경',
///     subtitle: '보안을 위해 안전한 비밀번호를 사용하세요',
///     icon: Icons.lock_outline,
///     content: YourContentWidget(),
///     actions: [
///       StyledDialogButton.cancel(
///         onPressed: () => Navigator.pop(context),
///       ),
///       StyledDialogButton.primary(
///         text: '변경하기',
///         onPressed: () => Navigator.pop(context, true),
///       ),
///     ],
///   ),
/// );
/// ```
class StyledDialog extends StatelessWidget {
  /// 제목
  final String title;

  /// 부제목 (선택)
  final String? subtitle;

  /// 아이콘
  final IconData icon;

  /// 헤더 색상 (기본값: Theme.of(context).primaryColor)
  final Color? headerColor;

  /// 컨텐츠
  final Widget content;

  /// 하단 버튼들
  final List<Widget>? actions;

  /// 닫기 버튼 표시 여부
  final bool showCloseButton;

  /// 최대 너비
  final double? maxWidth;

  /// 최대 높이 비율 (0.0 ~ 1.0)
  final double maxHeightRatio;

  /// true 이면 minHeight = maxHeight = 화면의 maxHeightRatio
  /// → 데이터 없을 때도 다이얼로그가 항상 같은 크기 유지
  /// 콘텐츠는 직접 SingleChildScrollView 를 감싸야 함
  final bool fillHeight;

  const StyledDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.headerColor,
    required this.content,
    this.actions,
    this.showCloseButton = false,
    this.maxWidth = 500,
    this.maxHeightRatio = 0.8,
    this.fillHeight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = headerColor ?? theme.primaryColor;

    final screenH = MediaQuery.of(context).size.height;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? 500,
          minHeight: fillHeight ? screenH * maxHeightRatio : 0,
          maxHeight: screenH * maxHeightRatio,
        ),
        child: Column(
          mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
          children: [
            _buildHeader(context, color),
            Flexible(
              child: fillHeight
                  ? content
                  : SingleChildScrollView(
                      padding: ResponsiveHelper.cardPadding(context),
                      child: content,
                    ),
            ),
            if (actions != null && actions!.isNotEmpty)
              _buildActions(context),
          ],
        ),
      ),
    );
  }

  /// 헤더
  Widget _buildHeader(BuildContext context, Color color) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color,
            color.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          // 아이콘
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: AppColors.surface,
              size: ResponsiveHelper.iconSize(context, 28),
            ),
          ),

          SizedBox(width: ResponsiveHelper.spacing(context, 12)),

          // 제목 & 부제목
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    color: AppColors.surface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    subtitle!,
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      color: AppColors.surface.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 닫기 버튼
          if (showCloseButton)
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.close, color: AppColors.surface),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  /// 버튼 영역
  Widget _buildActions(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: actions!
            .map((action) => Expanded(child: action))
            .toList()
            .fold<List<Widget>>(
          [],
          (list, widget) {
            if (list.isNotEmpty) {
              list.add(SizedBox(width: ResponsiveHelper.spacing(context, 12)));
            }
            list.add(widget);
            return list;
          },
        ),
      ),
    );
  }
}

/// 스타일 다이얼로그 버튼
class StyledDialogButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool isOutlined;
  final bool isLoading;

  const StyledDialogButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.isOutlined = false,
    this.isLoading = false,
  });

  /// Primary 버튼 (채워진 버튼)
  factory StyledDialogButton.primary({
    required String text,
    required VoidCallback onPressed,
    Color? backgroundColor,
    bool isLoading = false,
  }) {
    return StyledDialogButton(
      text: text,
      onPressed: onPressed,
      backgroundColor: backgroundColor,
      foregroundColor: AppColors.surface,
      isLoading: isLoading,
    );
  }

  /// Cancel 버튼 (아웃라인 버튼)
  factory StyledDialogButton.cancel({
    String text = '취소',
    required VoidCallback onPressed,
  }) {
    return StyledDialogButton(
      text: text,
      onPressed: onPressed,
      isOutlined: true,
    );
  }

  /// Danger 버튼 (빨간색)
  factory StyledDialogButton.danger({
    required String text,
    required VoidCallback onPressed,
    bool isLoading = false,
  }) {
    return StyledDialogButton(
      text: text,
      onPressed: onPressed,
      backgroundColor: AppColors.error,
      foregroundColor: AppColors.surface,
      isLoading: isLoading,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isOutlined
        ? AppColors.grey100
        : (backgroundColor ?? theme.primaryColor);
    final fg = isOutlined
        ? AppColors.grey700
        : (foregroundColor ?? AppColors.surface);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 14),
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    height: ResponsiveHelper.iconSize(context, 18),
                    width: ResponsiveHelper.iconSize(context, 18),
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                : Text(
                    text,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 다이얼로그용 TextField (통일된 스타일)
class StyledDialogTextField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final IconData prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final void Function(String)? onChanged;
  final int? maxLength;
  final FocusNode? focusNode;
  final void Function(String)? onFieldSubmitted;
  final bool enabled;
  final bool autofocus;

  const StyledDialogTextField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText,
    required this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
    this.maxLength,
    this.focusNode,
    this.onFieldSubmitted,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          autofocus: autofocus,
          onSubmitted: onFieldSubmitted,
          obscureText: obscureText,
          keyboardType: keyboardType,
          onChanged: onChanged,
          maxLength: maxLength,
          style: ResponsiveHelper.bodyStyle(context),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.grey400,
            ),
            prefixIcon: Icon(
              prefixIcon,
              color: theme.primaryColor,
              size: ResponsiveHelper.iconSize(context, 22),
            ),
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.primaryColor, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.grey200),
            ),
            filled: true,
            fillColor: enabled ? AppColors.grey50 : AppColors.grey100,
            contentPadding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 16),
            ),
            counterText: '', // maxLength 카운터 숨기기
          ),
        ),
      ],
    );
  }
}

/// 다이얼로그용 안내 카드
class StyledDialogInfoCard extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color color;

  const StyledDialogInfoCard({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.color = AppColors.info,
  });

  /// Info 카드 (파란색)
  factory StyledDialogInfoCard.info(String message) {
    return StyledDialogInfoCard(
      message: message,
      icon: Icons.info_outline,
      color: AppColors.info,
    );
  }

  /// Warning 카드 (주황색)
  factory StyledDialogInfoCard.warning(String message) {
    return StyledDialogInfoCard(
      message: message,
      icon: Icons.warning_amber,
      color: AppColors.warning,
    );
  }

  /// Success 카드 (초록색)
  factory StyledDialogInfoCard.success(String message) {
    return StyledDialogInfoCard(
      message: message,
      icon: Icons.check_circle_outline,
      color: AppColors.success,
    );
  }

  /// Error 카드 (빨간색)
  factory StyledDialogInfoCard.error(String message) {
    return StyledDialogInfoCard(
      message: message,
      icon: Icons.error_outline,
      color: AppColors.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: _getShade(color, 700),
            size: ResponsiveHelper.iconSize(context, 20),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Text(
              message,
              style: ResponsiveHelper.smallStyle(
                context,
                color: _getShade(color, 900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 색상 shade 가져오기 (MaterialColor가 아닌 경우 대체)
  Color _getShade(Color color, int shade) {
    if (color is MaterialColor) {
      return color[shade]!;
    }
    
    // MaterialColor가 아닌 경우 어둡게/밝게 처리
    if (shade >= 700) {
      // 어둡게 (700, 800, 900)
      final factor = (shade - 500) / 500; // 0.4 ~ 0.8
      return Color.lerp(color, Colors.black, factor * 0.3)!;
    } else {
      // 밝게 (100, 200, 300)
      final factor = (500 - shade) / 500; // 0.4 ~ 0.8
      return Color.lerp(color, Colors.white, factor * 0.5)!;
    }
  }
}

/// 비밀번호 강도 표시기
class PasswordStrengthIndicator extends StatelessWidget {
  final int strength; // 0: 약함, 1~2: 보통, 3: 강함

  const PasswordStrengthIndicator({
    super.key,
    required this.strength,
  });

  @override
  Widget build(BuildContext context) {
    Color getColor(int index) {
      if (strength == 0) return AppColors.grey300;
      if (index >= strength) return AppColors.grey300;
      if (strength <= 2) return AppColors.warning;
      return AppColors.success;
    }

    String getLabel() {
      if (strength == 0) return '약함';
      if (strength <= 2) return '보통';
      return '강함';
    }

    Color getLabelColor() {
      if (strength == 0) return AppColors.errorDark;
      if (strength <= 2) return AppColors.warningDark;
      return AppColors.successDark;
    }

    return Row(
      children: [
        Expanded(
          child: Container(
            height: ResponsiveHelper.spacing(context, 4),
            decoration: BoxDecoration(
              color: getColor(1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Expanded(
          child: Container(
            height: ResponsiveHelper.spacing(context, 4),
            decoration: BoxDecoration(
              color: getColor(2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Expanded(
          child: Container(
            height: ResponsiveHelper.spacing(context, 4),
            decoration: BoxDecoration(
              color: getColor(3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Text(
          getLabel(),
          style: ResponsiveHelper.smallStyle(context).copyWith(
            color: getLabelColor(),
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}