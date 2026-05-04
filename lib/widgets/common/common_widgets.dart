// lib/widgets/common/common_widgets.dart

import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';

/// 🎨 앱 전체에서 사용하는 공통 위젯 모음
/// 디자인 일관성을 위해 이 위젯들을 사용하세요!
class CommonWidgets {
  
  /// 📦 기본 카드 스타일
  static BoxDecoration cardDecoration({Color? color}) {
    return BoxDecoration(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: AppColors.grey500.withOpacity(0.1),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
  
  /// 🎨 그라데이션 카드 데코레이션
  static BoxDecoration gradientCardDecoration({
    required Color color,
    double opacity = 0.8,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color,
          color.withOpacity(opacity),
        ],
      ),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.3),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
  
  /// 🔘 기본 버튼
  static Widget primaryButton({
    required BuildContext context,
    required String text,
    required VoidCallback onPressed,
    bool isLoading = false,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.primaryColor,
            theme.primaryColor.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.primaryColor.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: ResponsiveHelper.iconSize(context, 20),
                    height: ResponsiveHelper.iconSize(context, 20),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else ...[
                  if (icon != null) ...[
                    Icon(
                      icon,
                      color: Colors.white,
                      size: ResponsiveHelper.iconSize(context, 20),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  ],
                  Text(
                    text,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  /// 🔘 아웃라인 버튼
  static Widget outlineButton({
    required BuildContext context,
    required String text,
    required VoidCallback onPressed,
    Color? color,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    final buttonColor = color ?? theme.primaryColor;
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: buttonColor, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: buttonColor,
                    size: ResponsiveHelper.iconSize(context, 20),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                ],
                Text(
                  text,
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: buttonColor,
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
  
  /// 📝 통일된 텍스트 입력 필드
  static Widget textField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    bool obscureText = false,
    bool readOnly = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Widget? suffixIcon,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      readOnly: readOnly,
      keyboardType: keyboardType,
      onTap: onTap,
      style: ResponsiveHelper.bodyStyle(context),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: ResponsiveHelper.smallStyle(
          context,
          color: AppColors.grey400,
        ),
        prefixIcon: icon != null
            ? Icon(
                icon,
                color: theme.primaryColor,
                size: ResponsiveHelper.iconSize(context, 24),
              )
            : null,
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
        filled: true,
        fillColor: readOnly ? AppColors.disabledBackground : AppColors.inputBackground,
        contentPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 18),
        ),
      ),
      validator: validator,
    );
  }
  
  /// 📌 섹션 헤더
  static Widget sectionHeader({
    required BuildContext context,
    required String title,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          decoration: BoxDecoration(
            color: theme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 20),
            color: theme.primaryColor,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Text(
          title,
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  /// 💡 안내 카드
  static Widget infoCard({
    required BuildContext context,
    required String message,
    IconData icon = Icons.info_outline,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final cardColor = color ?? theme.primaryColor;
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: cardColor,
            size: ResponsiveHelper.iconSize(context, 20),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Text(
              message,
              style: ResponsiveHelper.bodyStyle(
                context,
                color: cardColor.withOpacity(0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  static Color getRoleColor(String? role) {
    switch (role) {
      case 'SUPER_ADMIN':
        return AppColors.purple;  // 슈퍼 관리자는 보라색
      case 'BUSINESS_ADMIN':
        return AppColors.info;    // 사업장 관리자는 파란색
      case 'USER':
      default:
        return AppColors.success; // 지원자는 초록색
    }
  }
  
  /// 📛 역할 이름 반환
  static String getRoleName(String? role) {
    switch (role) {
      case 'SUPER_ADMIN':
        return '슈퍼 관리자';
      case 'BUSINESS_ADMIN':
        return '사업장 관리자';
      case 'USER':
      default:
        return '지원자';
    }
  }
}