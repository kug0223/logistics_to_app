// lib/widgets/common/loading_button.dart
// 로딩 상태를 자동 관리하는 공통 버튼 위젯

import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';

/// 버튼 스타일 타입
enum LoadingButtonStyle {
  /// 채워진 버튼 (기본)
  elevated,
  
  /// 테두리 버튼
  outlined,
  
  /// 텍스트 버튼
  text,
}

/// 로딩 상태를 자동 관리하는 버튼 위젯
/// 
/// async 함수를 onPressed에 전달하면 자동으로 로딩 상태 표시
/// 
/// 사용 예시:
/// ```dart
/// LoadingButton(
///   text: '저장',
///   onPressed: () async {
///     await saveData();
///   },
/// )
/// ```
class LoadingButton extends StatefulWidget {
  /// 버튼 텍스트
  final String text;
  
  /// 로딩 중 표시할 텍스트 (null이면 text 유지)
  final String? loadingText;
  
  /// 클릭 핸들러 (async 함수 가능)
  final Future<void> Function()? onPressed;
  
  /// 버튼 스타일
  final LoadingButtonStyle style;
  
  /// 아이콘 (선택)
  final IconData? icon;
  
  /// 배경색 (elevated 스타일)
  final Color? backgroundColor;
  
  /// 전경색 (텍스트/아이콘 색상)
  final Color? foregroundColor;
  
  /// 테두리 색상 (outlined 스타일)
  final Color? borderColor;
  
  /// 버튼 너비 확장 여부
  final bool expand;
  
  /// 외부에서 로딩 상태 제어 (선택)
  final bool? isLoading;
  
  /// 비활성화 여부
  final bool disabled;
  
  /// 수평 패딩
  final double? horizontalPadding;
  
  /// 수직 패딩
  final double? verticalPadding;

  const LoadingButton({
    super.key,
    required this.text,
    this.loadingText,
    this.onPressed,
    this.style = LoadingButtonStyle.elevated,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.expand = false,
    this.isLoading,
    this.disabled = false,
    this.horizontalPadding,
    this.verticalPadding,
  });

  /// Primary 버튼 (테마 색상)
  factory LoadingButton.primary({
    required String text,
    String? loadingText,
    Future<void> Function()? onPressed,
    IconData? icon,
    bool expand = false,
    bool? isLoading,
    bool disabled = false,
  }) {
    return LoadingButton(
      text: text,
      loadingText: loadingText,
      onPressed: onPressed,
      style: LoadingButtonStyle.elevated,
      icon: icon,
      expand: expand,
      isLoading: isLoading,
      disabled: disabled,
    );
  }

  /// Success 버튼 (녹색)
  factory LoadingButton.success({
    required String text,
    String? loadingText,
    Future<void> Function()? onPressed,
    IconData? icon,
    bool expand = false,
    bool? isLoading,
    bool disabled = false,
  }) {
    return LoadingButton(
      text: text,
      loadingText: loadingText,
      onPressed: onPressed,
      style: LoadingButtonStyle.elevated,
      icon: icon,
      backgroundColor: AppColors.success,
      foregroundColor: Colors.white,
      expand: expand,
      isLoading: isLoading,
      disabled: disabled,
    );
  }

  /// Danger 버튼 (빨간색)
  factory LoadingButton.danger({
    required String text,
    String? loadingText,
    Future<void> Function()? onPressed,
    IconData? icon,
    bool expand = false,
    bool? isLoading,
    bool disabled = false,
  }) {
    return LoadingButton(
      text: text,
      loadingText: loadingText,
      onPressed: onPressed,
      style: LoadingButtonStyle.elevated,
      icon: icon,
      backgroundColor: AppColors.error,
      foregroundColor: Colors.white,
      expand: expand,
      isLoading: isLoading,
      disabled: disabled,
    );
  }

  /// Outlined 버튼 (테두리)
  factory LoadingButton.outlined({
    required String text,
    String? loadingText,
    Future<void> Function()? onPressed,
    IconData? icon,
    Color? borderColor,
    Color? foregroundColor,
    bool expand = false,
    bool? isLoading,
    bool disabled = false,
  }) {
    return LoadingButton(
      text: text,
      loadingText: loadingText,
      onPressed: onPressed,
      style: LoadingButtonStyle.outlined,
      icon: icon,
      borderColor: borderColor,
      foregroundColor: foregroundColor,
      expand: expand,
      isLoading: isLoading,
      disabled: disabled,
    );
  }

  /// Text 버튼
  factory LoadingButton.text({
    required String text,
    String? loadingText,
    Future<void> Function()? onPressed,
    IconData? icon,
    Color? foregroundColor,
    bool? isLoading,
    bool disabled = false,
  }) {
    return LoadingButton(
      text: text,
      loadingText: loadingText,
      onPressed: onPressed,
      style: LoadingButtonStyle.text,
      icon: icon,
      foregroundColor: foregroundColor,
      isLoading: isLoading,
      disabled: disabled,
    );
  }

  @override
  State<LoadingButton> createState() => _LoadingButtonState();
}

class _LoadingButtonState extends State<LoadingButton> {
  bool _internalLoading = false;

  bool get _isLoading => widget.isLoading ?? _internalLoading;
  bool get _isDisabled => widget.disabled || widget.onPressed == null;

  Future<void> _handlePressed() async {
    if (_isLoading || _isDisabled) return;

    setState(() => _internalLoading = true);

    try {
      await widget.onPressed?.call();
    } finally {
      if (mounted) {
        setState(() => _internalLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    Widget button;
    
    switch (widget.style) {
      case LoadingButtonStyle.elevated:
        button = _buildElevatedButton(context, theme);
        break;
      case LoadingButtonStyle.outlined:
        button = _buildOutlinedButton(context, theme);
        break;
      case LoadingButtonStyle.text:
        button = _buildTextButton(context, theme);
        break;
    }

    if (widget.expand) {
      return SizedBox(
        width: double.infinity,
        child: button,
      );
    }

    return button;
  }

  Widget _buildElevatedButton(BuildContext context, ThemeData theme) {
    final bgColor = widget.backgroundColor ?? theme.primaryColor;
    final fgColor = widget.foregroundColor ?? Colors.white;

    if (widget.icon != null) {
      return ElevatedButton.icon(
        onPressed: (_isLoading || _isDisabled) ? null : _handlePressed,
        icon: _buildIconOrLoader(context, fgColor),
        label: _buildLabel(context, fgColor),
        style: _elevatedStyle(context, bgColor, fgColor),
      );
    }

    return ElevatedButton(
      onPressed: (_isLoading || _isDisabled) ? null : _handlePressed,
      style: _elevatedStyle(context, bgColor, fgColor),
      child: _buildContent(context, fgColor),
    );
  }

  Widget _buildOutlinedButton(BuildContext context, ThemeData theme) {
    final borderCol = widget.borderColor ?? theme.primaryColor;
    final fgColor = widget.foregroundColor ?? theme.primaryColor;

    if (widget.icon != null) {
      return OutlinedButton.icon(
        onPressed: (_isLoading || _isDisabled) ? null : _handlePressed,
        icon: _buildIconOrLoader(context, fgColor),
        label: _buildLabel(context, fgColor),
        style: _outlinedStyle(context, borderCol, fgColor),
      );
    }

    return OutlinedButton(
      onPressed: (_isLoading || _isDisabled) ? null : _handlePressed,
      style: _outlinedStyle(context, borderCol, fgColor),
      child: _buildContent(context, fgColor),
    );
  }

  Widget _buildTextButton(BuildContext context, ThemeData theme) {
    final fgColor = widget.foregroundColor ?? theme.primaryColor;

    if (widget.icon != null) {
      return TextButton.icon(
        onPressed: (_isLoading || _isDisabled) ? null : _handlePressed,
        icon: _buildIconOrLoader(context, fgColor),
        label: _buildLabel(context, fgColor),
        style: _textStyle(context, fgColor),
      );
    }

    return TextButton(
      onPressed: (_isLoading || _isDisabled) ? null : _handlePressed,
      style: _textStyle(context, fgColor),
      child: _buildContent(context, fgColor),
    );
  }

  Widget _buildContent(BuildContext context, Color color) {
    if (_isLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: ResponsiveHelper.iconSize(context, 16),
            height: ResponsiveHelper.iconSize(context, 16),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: color,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            widget.loadingText ?? widget.text,
            style: ResponsiveHelper.bodyStyle(context, color: color).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return Text(
      widget.text,
      style: ResponsiveHelper.bodyStyle(context, color: color).copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildIconOrLoader(BuildContext context, Color color) {
    if (_isLoading) {
      return SizedBox(
        width: ResponsiveHelper.iconSize(context, 16),
        height: ResponsiveHelper.iconSize(context, 16),
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: color,
        ),
      );
    }

    return Icon(
      widget.icon,
      size: ResponsiveHelper.iconSize(context, 18),
    );
  }

  Widget _buildLabel(BuildContext context, Color color) {
    return Text(
      _isLoading ? (widget.loadingText ?? widget.text) : widget.text,
      style: ResponsiveHelper.bodyStyle(context, color: color).copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }

  ButtonStyle _elevatedStyle(BuildContext context, Color bgColor, Color fgColor) {
    return ElevatedButton.styleFrom(
      backgroundColor: bgColor,
      foregroundColor: fgColor,
      disabledBackgroundColor: bgColor.withOpacity(0.5),
      disabledForegroundColor: fgColor.withOpacity(0.7),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, widget.horizontalPadding ?? 16),
        vertical: ResponsiveHelper.spacing(context, widget.verticalPadding ?? 12),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      elevation: 0,
    );
  }

  ButtonStyle _outlinedStyle(BuildContext context, Color borderColor, Color fgColor) {
    return OutlinedButton.styleFrom(
      foregroundColor: fgColor,
      disabledForegroundColor: fgColor.withOpacity(0.5),
      side: BorderSide(
        color: (_isLoading || _isDisabled) ? borderColor.withOpacity(0.5) : borderColor,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, widget.horizontalPadding ?? 16),
        vertical: ResponsiveHelper.spacing(context, widget.verticalPadding ?? 12),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  ButtonStyle _textStyle(BuildContext context, Color fgColor) {
    return TextButton.styleFrom(
      foregroundColor: fgColor,
      disabledForegroundColor: fgColor.withOpacity(0.5),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, widget.horizontalPadding ?? 12),
        vertical: ResponsiveHelper.spacing(context, widget.verticalPadding ?? 8),
      ),
    );
  }
}

/// 아이콘만 있는 로딩 버튼
/// 
/// 사용 예시:
/// ```dart
/// LoadingIconButton(
///   icon: Icons.save,
///   onPressed: () async {
///     await saveData();
///   },
/// )
/// ```
class LoadingIconButton extends StatefulWidget {
  final IconData icon;
  final Future<void> Function()? onPressed;
  final Color? color;
  final Color? backgroundColor;
  final double? size;
  final bool? isLoading;
  final bool disabled;
  final String? tooltip;

  const LoadingIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.color,
    this.backgroundColor,
    this.size,
    this.isLoading,
    this.disabled = false,
    this.tooltip,
  });

  @override
  State<LoadingIconButton> createState() => _LoadingIconButtonState();
}

class _LoadingIconButtonState extends State<LoadingIconButton> {
  bool _internalLoading = false;

  bool get _isLoading => widget.isLoading ?? _internalLoading;
  bool get _isDisabled => widget.disabled || widget.onPressed == null;

  Future<void> _handlePressed() async {
    if (_isLoading || _isDisabled) return;

    setState(() => _internalLoading = true);

    try {
      await widget.onPressed?.call();
    } finally {
      if (mounted) {
        setState(() => _internalLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconSize = widget.size ?? ResponsiveHelper.iconSize(context, 24);
    final color = widget.color ?? theme.primaryColor;

    Widget child;
    
    if (_isLoading) {
      child = SizedBox(
        width: iconSize,
        height: iconSize,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: color,
        ),
      );
    } else {
      child = Icon(
        widget.icon,
        size: iconSize,
        color: _isDisabled ? color.withOpacity(0.5) : color,
      );
    }

    Widget button;
    
    if (widget.backgroundColor != null) {
      button = Material(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: (_isLoading || _isDisabled) ? null : _handlePressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
            child: child,
          ),
        ),
      );
    } else {
      button = IconButton(
        onPressed: (_isLoading || _isDisabled) ? null : _handlePressed,
        icon: child,
        iconSize: iconSize,
      );
    }

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }

    return button;
  }
}