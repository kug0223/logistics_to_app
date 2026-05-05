import 'package:flutter/material.dart';
import '../../../../utils/responsive_helper.dart';

/// ✨ TO 저장/생성 버튼
/// create_to_screen, edit_to_screen에서 공통으로 사용
class TOActionButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? backgroundColor;

  const TOActionButton({
    super.key,
    required this.text,
    this.icon = Icons.check_circle_outline,
    this.onPressed,
    this.isLoading = false,
    this.backgroundColor,
  });

  /// TO 생성 버튼
  factory TOActionButton.create({
    VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return TOActionButton(
      text: 'TO 생성',
      icon: Icons.check_circle_outline,
      onPressed: onPressed,
      isLoading: isLoading,
    );
  }

  /// TO 저장 버튼
  factory TOActionButton.save({
    VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return TOActionButton(
      text: '저장하기',
      icon: Icons.check_circle_outline,
      onPressed: onPressed,
      isLoading: isLoading,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? theme.primaryColor;

    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bgColor,
            bgColor.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: bgColor.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        color: Colors.white,
                        size: ResponsiveHelper.iconSize(context, 24),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Text(
                        text,
                        style: ResponsiveHelper.titleStyle(context).copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}