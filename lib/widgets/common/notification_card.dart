import 'package:flutter/material.dart';
import '../../models/core/notification_model.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';

/// 알림 목록 아이템 카드
///
/// 왼쪽으로 드래그 시 [취소 | 🗑 삭제] 패널이 드러나며,
/// 휴지통 버튼을 눌러야만 실제 삭제가 실행된다.
class NotificationCard extends StatefulWidget {
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
  State<NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<NotificationCard>
    with SingleTickerProviderStateMixin {
  static const double _revealWidth = 128.0;

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _open() => _ctrl.animateTo(1.0, curve: Curves.easeOut);
  void _close() => _ctrl.animateTo(0.0, curve: Curves.easeOut);

  void _onDragUpdate(DragUpdateDetails d) {
    _ctrl.value = (_ctrl.value - d.delta.dx / _revealWidth).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_ctrl.value > 0.45 || d.velocity.pixelsPerSecond.dx < -400) {
      _open();
    } else {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = !widget.notification.isRead;

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // ── 액션 패널 (슬라이드로 드러남) ──────────────────────────
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: _revealWidth,
              child: Row(
                children: [
                  // 취소
                  Expanded(
                    child: GestureDetector(
                      onTap: _close,
                      child: Container(
                        color: AppColors.grey500,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.close, color: Colors.white, size: 22),
                            const SizedBox(height: 2),
                            Text(
                              '취소',
                              style: ResponsiveHelper.tinyStyle(
                                context,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 삭제
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onDismiss,
                      child: Container(
                        color: AppColors.error,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.delete_outline,
                                color: Colors.white, size: 22),
                            const SizedBox(height: 2),
                            Text(
                              '삭제',
                              style: ResponsiveHelper.tinyStyle(
                                context,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── 카드 본체 (좌로 슬라이드) ──────────────────────────────
        AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) => Transform.translate(
            offset: Offset(-_ctrl.value * _revealWidth, 0),
            child: child,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            child: InkWell(
              onTap: () {
                if (_ctrl.value > 0) {
                  _close();
                } else {
                  widget.onTap?.call();
                }
              },
              child: Container(
                padding: ResponsiveHelper.cardPadding(context),
                decoration: BoxDecoration(
                  color: isUnread
                      ? theme.primaryColor.withValues(alpha: 0.05)
                      : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(color: AppColors.grey200, width: 1),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 알림 타입 아이콘
                    Container(
                      padding:
                          EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                      decoration: BoxDecoration(
                        color: _getIconColor(widget.notification.type)
                            .withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getIcon(widget.notification.type),
                        color: _getIconColor(widget.notification.type),
                        size: ResponsiveHelper.iconSize(context, 20),
                      ),
                    ),

                    SizedBox(width: ResponsiveHelper.spacing(context, 12)),

                    // 제목 + 본문
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.notification.title,
                                  style: ResponsiveHelper.bodyStyle(
                                    context,
                                    fontWeight: isUnread
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                widget.notification.timeAgo,
                                style: ResponsiveHelper.tinyStyle(
                                  context,
                                  color: AppColors.grey500,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(
                              height: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            widget.notification.body,
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

                    // 미읽음 뱃지
                    if (isUnread)
                      Container(
                        width: 8,
                        height: 8,
                        margin: EdgeInsets.only(
                            left: ResponsiveHelper.spacing(context, 8)),
                        decoration: BoxDecoration(
                          color: theme.primaryColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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
      case NotificationType.reviewRequest:
        return Icons.star;
      case NotificationType.scheduleChangeRequested:
        return Icons.edit_calendar;
      case NotificationType.scheduleChangeApproved:
        return Icons.event_available;
      case NotificationType.scheduleChangeRejected:
        return Icons.event_busy;
      case NotificationType.contractSignRequested:
        return Icons.draw;
      case NotificationType.contractSigned:
        return Icons.task_alt;
      case NotificationType.contractVoided:
        return Icons.block;
      case NotificationType.contractExpiringReminder:
        return Icons.event_note;
      case NotificationType.contractRenewed:
        return Icons.autorenew;
      case NotificationType.contractTerminating:
        return Icons.event_busy;
      case NotificationType.terminationRequested:
      case NotificationType.resignRequested:
      case NotificationType.contractRequested:
        return Icons.exit_to_app;
      case NotificationType.terminationApproved:
      case NotificationType.resignApproved:
        return Icons.logout;
      case NotificationType.terminationRejected:
        return Icons.block;
      case NotificationType.resignRejected:
        return Icons.do_not_disturb_on;
      case NotificationType.wageConfirmed:
        return Icons.payments;
      case NotificationType.wageTransferred:
        return Icons.account_balance_wallet;
      case NotificationType.wageCancelConfirmed:
        return Icons.edit_note;
      case NotificationType.retroactiveDeductionAlert:
        return Icons.warning_amber;
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
      case NotificationType.workTypeChanged:
        return Icons.swap_horiz;
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
      case NotificationType.terminationRejected:
      case NotificationType.resignRejected:
      case NotificationType.idCardAccessRejected:
        return AppColors.error;
      case NotificationType.terminationApproved:
      case NotificationType.resignApproved:
        return AppColors.success;
      case NotificationType.contractVoided:
        return AppColors.error;
      case NotificationType.resignRequested:
      case NotificationType.contractRequested:
      case NotificationType.contractSignRequested:
      case NotificationType.contractSigned:
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
      case NotificationType.wageTransferred:
        return AppColors.success;
      case NotificationType.wageCancelConfirmed:
        return AppColors.warning;
      case NotificationType.retroactiveDeductionAlert:
        return AppColors.warning;
      case NotificationType.reviewReceived:
      case NotificationType.reviewRequest:
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
      case NotificationType.workTypeChanged:
        return AppColors.info;
      case NotificationType.applicationCanceled:
      case NotificationType.other:
        return AppColors.grey500;
    }
  }
}
