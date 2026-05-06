import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/app_colors.dart';

class ToastHelper {
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
    scaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
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
          backgroundColor: backgroundColor,
          duration: duration,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        ),
      );
  }
}
