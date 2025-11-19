import 'package:flutter/material.dart';
import '../../../utils/responsive_helper.dart';  // ⭐ 추가

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? textColor;
  final bool isLoading;
  final bool isOutlined;
  final IconData? icon;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.color,
    this.textColor,
    this.isLoading = false,
    this.isOutlined = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final buttonColor = color ?? Theme.of(context).primaryColor;
    final buttonTextColor = textColor ?? Colors.white;

    return SizedBox(
      width: double.infinity,
      height: ResponsiveHelper.buttonHeight(context),  // ⭐ 변경 (50 → 반응형)
      child: isOutlined
          ? OutlinedButton(
              onPressed: isLoading ? null : onPressed,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: buttonColor, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _buildButtonChild(context, buttonColor),  // ⭐ context 추가
            )
          : ElevatedButton(
              onPressed: isLoading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                foregroundColor: buttonTextColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 2,
              ),
              child: _buildButtonChild(context, buttonTextColor),  // ⭐ context 추가
            ),
    );
  }

  Widget _buildButtonChild(BuildContext context, Color color) {  // ⭐ context 추가
    if (isLoading) {
      return SizedBox(
        height: ResponsiveHelper.iconSize(context, 20),  // ⭐ 변경
        width: ResponsiveHelper.iconSize(context, 20),  // ⭐ 변경
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    }

    if (icon != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 20)),  // ⭐ 변경
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
          Text(
            text,
            style: ResponsiveHelper.subtitleStyle(context).copyWith(  // ⭐ 변경
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      );
    }

    return Text(
      text,
      style: ResponsiveHelper.subtitleStyle(context).copyWith(  // ⭐ 변경
        fontWeight: FontWeight.bold,
        color: color,
      ),
    );
  }
}