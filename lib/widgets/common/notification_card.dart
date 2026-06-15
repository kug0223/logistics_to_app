import 'package:flutter/material.dart';
import '../../models/core/notification_model.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';

/// 알림 목록 아이템 카드
class NotificationCard extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
  
  const NotificationCard({
    super.key,
    required this.notification,
    this.onTap,
    this.onDismiss,
  });
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = !notification.isRead;
    
    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss?.call(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 20)),
        color: AppColors.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: isUnread 
                ? theme.primaryColor.withValues(alpha: 0.05) 
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: AppColors.grey200,
                width: 1,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 아이콘
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                decoration: BoxDecoration(
                  color: _getIconColor(notification.type).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getIcon(notification.type),
                  color: _getIconColor(notification.type),
                  size: ResponsiveHelper.iconSize(context, 20),
                ),
              ),
              
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              
              // 내용
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: ResponsiveHelper.bodyStyle(
                              context,
                              fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          notification.timeAgo,
                          style: ResponsiveHelper.tinyStyle(
                            context,
                            color: AppColors.grey500,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      notification.body,
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: AppColors.grey600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // 읽지 않음 표시
              if (isUnread)
                Container(
                  width: 8,
                  height: 8,
                  margin: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 8)),
                  decoration: BoxDecoration(
                    color: theme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  IconData _getIcon(NotificationType type) {
    switch (type) {
      case NotificationType.applicationConfirmed:
        return Icons.check_circle;
      case NotificationType.applicationRejected:
        return Icons.cancel;
      case NotificationType.newApplication:
        return Icons.person_add;
      case NotificationType.applicationCanceled:
        return Icons.person_remove;
      case NotificationType.confirmationCanceled:
        return Icons.event_busy;
      case NotificationType.workReminder:
        return Icons.alarm;
      case NotificationType.workCanceled:
        return Icons.event_busy;
      case NotificationType.reviewReceived:
        return Icons.star;
      case NotificationType.scheduleChangeRequested:
        return Icons.edit_calendar;
      case NotificationType.scheduleChangeApproved:
        return Icons.event_available;
      case NotificationType.scheduleChangeRejected:
        return Icons.event_busy;
      case NotificationType.contractSignRequested:
        return Icons.draw;
      case NotificationType.contractExpiringReminder:
        return Icons.event_note;
      case NotificationType.contractRenewed:
        return Icons.autorenew;
      case NotificationType.contractTerminating:
        return Icons.event_busy;
      case NotificationType.terminationRequested:
      case NotificationType.resignRequested:
        return Icons.exit_to_app;
      case NotificationType.terminationApproved:
      case NotificationType.resignApproved:
        return Icons.logout;
      case NotificationType.resignRejected:
        return Icons.do_not_disturb_on;
      case NotificationType.wageConfirmed:
        return Icons.payments;
      case NotificationType.wageCancelConfirmed:
        return Icons.edit_note;
      case NotificationType.idCardAccessRequested:
        return Icons.badge;
      case NotificationType.idCardAccessApproved:
        return Icons.verified;
      case NotificationType.idCardAccessRejected:
        return Icons.block;
      case NotificationType.idCardAccessExpiringSoon:
        return Icons.schedule;
      case NotificationType.memberInvitationReceived:
        return Icons.group_add;
      case NotificationType.memberInvitationAccepted:
        return Icons.how_to_reg;
      case NotificationType.memberInvitationRejected:
        return Icons.person_remove;
      case NotificationType.systemNotice:
        return Icons.campaign;
      case NotificationType.other:
        return Icons.notifications;
    }
  }
  
  Color _getIconColor(NotificationType type) {
    switch (type) {
      case NotificationType.applicationConfirmed:
      case NotificationType.scheduleChangeApproved:
      case NotificationType.idCardAccessApproved:
        return AppColors.success;
      case NotificationType.applicationRejected:
      case NotificationType.confirmationCanceled:
      case NotificationType.workCanceled:
      case NotificationType.scheduleChangeRejected:
      case NotificationType.terminationRequested:
      case NotificationType.resignRejected:
      case NotificationType.idCardAccessRejected:
        return AppColors.error;
      case NotificationType.terminationApproved:
      case NotificationType.resignApproved:
        return AppColors.success;
      case NotificationType.resignRequested:
      case NotificationType.contractSignRequested:
      case NotificationType.contractExpiringReminder:
      case NotificationType.newApplication:
      case NotificationType.scheduleChangeRequested:
      case NotificationType.idCardAccessRequested:
        return AppColors.info;
      case NotificationType.contractRenewed:
        return AppColors.success;
      case NotificationType.contractTerminating:
        return AppColors.warning;
      case NotificationType.wageConfirmed:
        return AppColors.success;
      case NotificationType.wageCancelConfirmed:
        return AppColors.warning;
      case NotificationType.reviewReceived:
        return AppColors.amber;
      case NotificationType.workReminder:
      case NotificationType.idCardAccessExpiringSoon:
        return AppColors.warning;
      case NotificationType.memberInvitationReceived:
        return AppColors.info;
      case NotificationType.memberInvitationAccepted:
        return AppColors.success;
      case NotificationType.memberInvitationRejected:
        return AppColors.grey500;
      case NotificationType.systemNotice:
        return AppColors.info;
      case NotificationType.applicationCanceled:
      case NotificationType.other:
        return AppColors.grey500;
    }
  }
}