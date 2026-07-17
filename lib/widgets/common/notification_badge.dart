import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../../utils/responsive_helper.dart';

/// 알림 아이콘에 읽지 않은 개수 뱃지 표시
class NotificationBadge extends StatelessWidget {
  final Widget child;
  final bool showZero;
  
  const NotificationBadge({
    super.key,
    required this.child,
    this.showZero = false,
  });
  
  @override
  Widget build(BuildContext context) {
    // [PERF-2026-07-16] int 1개만 필요 → Selector로 rebuild 범위 축소
    return Selector<NotificationProvider, int>(
      selector: (_, p) => p.unreadCount,
      builder: (context, count, _) {
        
        if (count == 0 && !showZero) {
          return child;
        }
        
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
                constraints: BoxConstraints(
                  minWidth: ResponsiveHelper.spacing(context, 18),
                  minHeight: ResponsiveHelper.spacing(context, 18),
                ),
                child: Center(
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: ResponsiveHelper.tinyStyle(context).fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}