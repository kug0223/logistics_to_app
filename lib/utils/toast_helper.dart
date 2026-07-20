import 'package:flutter/material.dart';
import '../utils/navigation_key.dart';
import '../theme/app_colors.dart';

class ToastHelper {
  static OverlayEntry? _currentEntry;

  static void showSuccess(String message) => _show(
        message: message,
        backgroundColor: AppColors.success,
        icon: Icons.check_circle_outline,
      );

  static void showError(String message) => _show(
        message: message,
        backgroundColor: AppColors.error,
        icon: Icons.error_outline,
        duration: const Duration(seconds: 4),
      );

  static void showInfo(String message) => _show(
        message: message,
        backgroundColor: AppColors.info,
        icon: Icons.info_outline,
      );

  static void showWarning(String message) => _show(
        message: message,
        backgroundColor: AppColors.warning,
        icon: Icons.warning_amber_outlined,
      );

  static void _show({
    required String message,
    required Color backgroundColor,
    required IconData icon,
    Duration duration = const Duration(seconds: 2),
  }) {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _currentEntry?.remove();
    _currentEntry = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        message: message,
        backgroundColor: backgroundColor,
        icon: icon,
      ),
    );
    _currentEntry = entry;
    overlay.insert(entry);

    Future.delayed(duration, () {
      if (entry.mounted) entry.remove();
      if (_currentEntry == entry) _currentEntry = null;
    });
  }
}

class _ToastWidget extends StatelessWidget {
  final String message;
  final Color backgroundColor;
  final IconData icon;

  const _ToastWidget({
    required this.message,
    required this.backgroundColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Positioned(
      bottom: 24 + bottomPadding,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.textOnDark, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
