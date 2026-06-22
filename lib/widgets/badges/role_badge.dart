// lib/widgets/role_badge.dart

import 'package:flutter/material.dart';
import '../../theme/role_theme.dart';
import '../../utils/responsive_helper.dart';

/// 사용자 역할을 표시하는 배지
class RoleBadge extends StatelessWidget {
  final String? role;
  final bool showIcon;
  final double? fontSize;

  const RoleBadge({
    super.key,
    required this.role,
    this.showIcon = true,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = RoleTheme.getPrimaryColor(role);
    final backgroundColor = RoleTheme.getBackgroundColor(role);
    final icon = RoleTheme.getRoleIcon(role);
    final label = RoleTheme.getRoleLabel(role);
    final resolvedFontSize = fontSize ?? ResponsiveHelper.smallStyle(context).fontSize ?? 12.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: primaryColor, width: 1.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(icon, size: resolvedFontSize + 3, color: primaryColor),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          ],
          Text(
            label,
            style: TextStyle(
              color: primaryColor,
              fontSize: resolvedFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// 작은 사이즈 역할 점
class RoleDot extends StatelessWidget {
  final String? role;
  final double size;
  
  const RoleDot({
    super.key,
    required this.role,
    this.size = 10,
  });

  @override
  Widget build(BuildContext context) {
    final color = RoleTheme.getPrimaryColor(role);
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// 역할별 그라데이션 배경 컨테이너
class RoleGradientContainer extends StatelessWidget {
  final String? role;
  final Widget child;
  final double? height;
  
  const RoleGradientContainer({
    super.key,
    required this.role,
    required this.child,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = RoleTheme.getPrimaryColor(role);
    final secondaryColor = RoleTheme.getSecondaryColor(role);
    
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor,
            secondaryColor,
          ],
        ),
      ),
      child: child,
    );
  }
}

/// 역할별 AppBar (그라데이션)
class RoleAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? role;
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  
  const RoleAppBar({
    super.key,
    required this.role,
    required this.title,
    this.actions,
    this.leading,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      leading: leading,
      actions: actions,
      bottom: bottom,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              RoleTheme.getPrimaryColor(role),
              RoleTheme.getSecondaryColor(role),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(
    kToolbarHeight + (bottom?.preferredSize.height ?? 0.0),
  );
}