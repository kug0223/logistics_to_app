import 'package:flutter/material.dart';
import '../../models/core/notification_model.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';

/// 알림 목록 아이템 카드
///
/// 왼쪽으로 드래그 시 [취소 | 🗑 삭제] 패널이 드러나며,
/// 휴지통 버튼을 눌러야만 실제 삭제가 실행된다.
///
/// 레이아웃 — category에 따라 두 가지:
///   admin:    [사업장명] / [●제목] / 본문 / [단일 CTA?]
///   personal: [●제목]   / [사업장/맥락?] / 본문 / [단일 CTA?]
///
/// 중요도(resolvedImportance):
///   ACTION_REQUIRED → 제목 w600, 단일 CTA 버튼 표시
///   STATUS_UPDATE   → 제목 w600(미읽음) / w500(읽음)
///   REMINDER_INFO   → 제목 w500, 아이콘 neutral grey (opacity 전체 낮추지 않음)
///
/// [openCardIdNotifier] — 스크린이 공유하는 "현재 열린 카드 ID" 노티파이어.
/// 이 카드의 ID와 다른 값이 세팅되면 자동으로 닫힌다.
class NotificationCard extends StatefulWidget {
  final NotificationModel notification;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
  final ValueNotifier<String?>? openCardIdNotifier;

  const NotificationCard({
    super.key,
    required this.notification,
    this.onTap,
    this.onDismiss,
    this.openCardIdNotifier,
  });

  @override
  State<NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<NotificationCard>
    with SingleTickerProviderStateMixin {
  static const double _revealWidth = 128.0;

  late final AnimationController _ctrl;
  // (1 - value*4).clamp(0,1): value 0→0.25 구간에서 1→0으로 페이드
  late final Animation<double> _badgeFade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _badgeFade = Tween<double>(begin: 1.0, end: 0.0)
        .chain(CurveTween(curve: const Interval(0.0, 0.25)))
        .animate(_ctrl);
    widget.openCardIdNotifier?.addListener(_onOpenCardChanged);
  }

  @override
  void didUpdateWidget(NotificationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.openCardIdNotifier != widget.openCardIdNotifier) {
      oldWidget.openCardIdNotifier?.removeListener(_onOpenCardChanged);
      widget.openCardIdNotifier?.addListener(_onOpenCardChanged);
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    _ctrl.value = 0.0;
    if (widget.openCardIdNotifier?.value == widget.notification.id) {
      widget.openCardIdNotifier?.value = null;
    }
  }

  @override
  void dispose() {
    widget.openCardIdNotifier?.removeListener(_onOpenCardChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onOpenCardChanged() {
    if (widget.openCardIdNotifier?.value != widget.notification.id) {
      _ctrl.animateTo(0.0, curve: Curves.easeOut);
    }
  }

  void _open() => _ctrl.animateTo(1.0, curve: Curves.easeOut);
  void _close() => _ctrl.animateTo(0.0, curve: Curves.easeOut);

  void _onDragUpdate(DragUpdateDetails d) {
    if (d.delta.dx < 0 &&
        widget.openCardIdNotifier?.value != widget.notification.id) {
      widget.openCardIdNotifier?.value = widget.notification.id;
    }
    _ctrl.value = (_ctrl.value - d.delta.dx / _revealWidth).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_ctrl.value > 0.45 || d.velocity.pixelsPerSecond.dx < -400) {
      _open();
    } else {
      _close();
      if (widget.openCardIdNotifier?.value == widget.notification.id) {
        widget.openCardIdNotifier?.value = null;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 아이콘 (모든 52개 타입 포함)
  // ─────────────────────────────────────────────────────────────────────────
  IconData _getIcon(NotificationType type) {
    switch (type) {
      case NotificationType.applicationConfirmed:      return Icons.check_circle;
      case NotificationType.applicationRejected:       return Icons.cancel;
      case NotificationType.newApplication:            return Icons.person_add;
      case NotificationType.applicationCanceled:       return Icons.person_remove;
      case NotificationType.confirmationCanceled:      return Icons.event_busy;
      case NotificationType.workTypeChanged:           return Icons.swap_horiz;
      case NotificationType.workReminder:              return Icons.alarm;
      case NotificationType.workCanceled:              return Icons.event_busy;
      case NotificationType.scheduleChangeRequested:   return Icons.edit_calendar;
      case NotificationType.scheduleChangeApproved:    return Icons.event_available;
      case NotificationType.scheduleChangeRejected:    return Icons.event_busy;
      case NotificationType.contractSignRequested:     return Icons.draw;
      case NotificationType.contractSigned:            return Icons.task_alt;
      case NotificationType.contractVoided:            return Icons.block;
      case NotificationType.contractExpiringReminder:  return Icons.event_note;
      case NotificationType.contractRenewed:           return Icons.autorenew;
      case NotificationType.contractTerminating:       return Icons.event_busy;
      case NotificationType.terminationRequested:
      case NotificationType.resignRequested:
      case NotificationType.contractRequested:         return Icons.exit_to_app;
      case NotificationType.terminationApproved:
      case NotificationType.resignApproved:            return Icons.logout;
      case NotificationType.terminationRejected:       return Icons.block;
      case NotificationType.resignRejected:            return Icons.do_not_disturb_on;
      case NotificationType.wageConfirmed:             return Icons.payments;
      case NotificationType.wageTransferred:           return Icons.account_balance_wallet;
      case NotificationType.wageCancelConfirmed:       return Icons.edit_note;
      case NotificationType.retroactiveDeductionAlert: return Icons.info_outline;
      case NotificationType.interimSettlementRequested:    return Icons.account_balance_wallet_outlined;
      case NotificationType.interimSettlementApproved:     return Icons.account_balance_wallet;
      case NotificationType.interimSettlementRejected:     return Icons.money_off;
      case NotificationType.interimSettlementCompleted:    return Icons.account_balance_wallet;
      case NotificationType.reviewReceived:
      case NotificationType.reviewRequest:             return Icons.star;
      case NotificationType.idCardAccessRequested:     return Icons.badge;
      case NotificationType.idCardAccessApproved:      return Icons.verified;
      case NotificationType.idCardAccessRejected:      return Icons.block;
      case NotificationType.idCardAccessExpiringSoon:  return Icons.schedule;
      case NotificationType.idCardConsentGranted:      return Icons.lock_open; // [ID-CONSENT]
      case NotificationType.memberInvitationReceived:  return Icons.group_add;
      case NotificationType.memberInvitationAccepted:  return Icons.how_to_reg;
      case NotificationType.memberInvitationRejected:  return Icons.person_remove;
      case NotificationType.resignReminder:            return Icons.alarm;
      case NotificationType.toPostingExpiringTomorrow:
      case NotificationType.toPostingExpired:          return Icons.event_note;
      case NotificationType.toInvite:
      case NotificationType.toInviteCanceled:          return Icons.mail_outline;
      case NotificationType.toInviteAccepted:          return Icons.how_to_reg;
      case NotificationType.toInviteDeclined:          return Icons.person_remove;
      case NotificationType.reconfirmRequest:          return Icons.check_circle_outline;
      case NotificationType.reconfirmAdminWarning:
      case NotificationType.reconfirmDeclined:         return Icons.warning_amber;
      case NotificationType.toMatch:                   return Icons.work_outline; // [Phase 8.1C] 일자리 발견
      case NotificationType.systemNotice:              return Icons.campaign;
      case NotificationType.other:                     return Icons.notifications;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 아이콘 의미론적 색상 (importance 무관, 이벤트 의미 기준)
  // Orange/Red는 실제 warning/error/cancel/reject/urgent 의미일 때만 사용.
  // Primary blue는 일반 액션·요청·정보.
  // ─────────────────────────────────────────────────────────────────────────
  Color _getSemanticIconColor(NotificationType type) {
    switch (type) {
      // ── 확정·승인·완료 → green ─────────────────────────────────────────
      case NotificationType.applicationConfirmed:
      case NotificationType.scheduleChangeApproved:
      case NotificationType.idCardAccessApproved:
      case NotificationType.idCardConsentGranted: // [ID-CONSENT] 열람 권한 활성화 → green
      case NotificationType.terminationApproved:
      case NotificationType.resignApproved:
      case NotificationType.contractRenewed:
      case NotificationType.wageConfirmed:
      case NotificationType.wageTransferred:
      case NotificationType.interimSettlementApproved:
      case NotificationType.interimSettlementCompleted:
      case NotificationType.memberInvitationAccepted:
      case NotificationType.contractSigned:
      case NotificationType.toInviteAccepted:
        return AppColors.success;

      // ── 거절·무효·차단 → red ───────────────────────────────────────────
      case NotificationType.applicationRejected:
      case NotificationType.terminationRejected:
      case NotificationType.resignRejected:
      case NotificationType.contractVoided:
      case NotificationType.idCardAccessRejected:
      case NotificationType.interimSettlementRejected:
        return AppColors.error;

      // ── 실제 주의 상황 (취소·종료·공제·경고) → orange ──────────────────
      case NotificationType.confirmationCanceled:
      case NotificationType.workCanceled:
      case NotificationType.scheduleChangeRejected:
      case NotificationType.contractTerminating:
      case NotificationType.wageCancelConfirmed:
      case NotificationType.retroactiveDeductionAlert:
      case NotificationType.workReminder:
      case NotificationType.idCardAccessExpiringSoon:
      case NotificationType.resignReminder:
      case NotificationType.toPostingExpiringTomorrow:
      case NotificationType.toPostingExpired:
      case NotificationType.reconfirmAdminWarning:
      case NotificationType.reconfirmDeclined:
        return AppColors.warning;

      // ── 리뷰 → amber ───────────────────────────────────────────────────
      case NotificationType.reviewReceived:
      case NotificationType.reviewRequest:
        return AppColors.amber;

      // ── 중간정산 요청 → teal ───────────────────────────────────────────
      case NotificationType.interimSettlementRequested:
        return AppColors.teal;

      // ── 중립 (선택 취소, 거절 결과 통보) → grey ────────────────────────
      case NotificationType.applicationCanceled:
      case NotificationType.memberInvitationRejected:
      case NotificationType.toInviteDeclined:
      case NotificationType.toInviteCanceled:
        return AppColors.grey500;

      // ── 액션·요청·변경·정보 → primary blue ────────────────────────────
      case NotificationType.newApplication:
      case NotificationType.workTypeChanged:
      case NotificationType.scheduleChangeRequested:
      case NotificationType.contractSignRequested:
      case NotificationType.contractExpiringReminder:
      case NotificationType.terminationRequested:
      case NotificationType.resignRequested:
      case NotificationType.contractRequested:
      case NotificationType.idCardAccessRequested:
      case NotificationType.memberInvitationReceived:
      case NotificationType.toInvite:
      case NotificationType.reconfirmRequest:
      case NotificationType.toMatch:  // [Phase 8.1C] 일자리 발견 — 긍정적 정보 알림 → primary blue
      case NotificationType.systemNotice:
      case NotificationType.other:
        return AppColors.info;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CTA 레이블 (ACTION_REQUIRED 타입별 단일 버튼 텍스트)
  // 실제 승인/거절은 상세 화면/Dialog에서 처리 — 인라인 즉시 실행 버튼 없음.
  // ─────────────────────────────────────────────────────────────────────────
  String get _ctaLabel {
    switch (widget.notification.type) {
      case NotificationType.contractSignRequested:
        return '서명하기';
      case NotificationType.reviewRequest:
        return '리뷰 작성';
      case NotificationType.memberInvitationReceived:
        return '초대 확인';
      case NotificationType.reconfirmRequest:
        return '근무 확인';
      default:
        return '확인하기';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.notification;
    final isUnread = !n.isRead;
    final importance = n.resolvedImportance;
    final isAdmin = n.resolvedCategory == NotificationCategory.admin;
    final isActionRequired = importance == NotificationImportance.actionRequired;
    final isReminder = importance == NotificationImportance.reminderInfo;

    // 아이콘 색상: REMINDER_INFO는 neutral grey, 나머지는 의미론적 색상
    // grey400(disabled 톤)보다 한 단계 진한 grey500 사용 — 비활성처럼 보이지 않도록
    final iconColor = isReminder
        ? AppColors.grey500
        : _getSemanticIconColor(n.type);

    // 제목 fontWeight: REMINDER_INFO → w500, 미읽음·ACTION_REQUIRED → w600, 읽음 → w500
    final titleWeight = (!isReminder && isUnread) ? FontWeight.w600 : FontWeight.w500;

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // ── 액션 패널 (스와이프로 드러남) ─────────────────────────────────
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: _revealWidth,
              child: Row(
                children: [
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
                              style: ResponsiveHelper.tinyStyle(context, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onDismiss,
                      child: Container(
                        color: AppColors.error,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.delete_outline, color: Colors.white, size: 22),
                            const SizedBox(height: 2),
                            Text(
                              '삭제',
                              style: ResponsiveHelper.tinyStyle(context, color: Colors.white),
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

        // ── 카드 본체 (좌로 슬라이드) ─────────────────────────────────────
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
                      ? Color.alphaBlend(
                          theme.primaryColor.withValues(alpha: 0.05),
                          theme.scaffoldBackgroundColor,
                        )
                      : theme.scaffoldBackgroundColor,
                  border: Border(
                    bottom: BorderSide(color: AppColors.grey200, width: 1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Admin 카드: 사업장명 헤더 ──────────────────────────
                    if (isAdmin && n.businessName != null)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: ResponsiveHelper.spacing(context, 4),
                          left: ResponsiveHelper.spacing(context, 40), // 아이콘 너비 맞춤
                        ),
                        child: Text(
                          n.businessName!,
                          style: ResponsiveHelper.tinyStyle(
                            context,
                            color: AppColors.workTypeBlue,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                    // ── 메인 행: 아이콘 + 콘텐츠 ──────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 아이콘 컨테이너
                        Container(
                          width: ResponsiveHelper.spacing(context, 36),
                          height: ResponsiveHelper.spacing(context, 36),
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _getIcon(n.type),
                            color: iconColor,
                            size: ResponsiveHelper.iconSize(context, 18),
                          ),
                        ),

                        SizedBox(width: ResponsiveHelper.spacing(context, 10)),

                        // 콘텐츠 영역
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 제목 행: [미읽음 dot] 제목 ... 시간
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // 미읽음 dot — 6px, workTypeBlue, 제목 바로 앞
                                  // 아이콘 위보다 제목 근처가 시각적으로 더 명확히 인지됨
                                  if (isUnread)
                                    FadeTransition(
                                      opacity: _badgeFade,
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        margin: EdgeInsets.only(
                                          right: ResponsiveHelper.spacing(context, 5),
                                        ),
                                        decoration: const BoxDecoration(
                                          color: AppColors.workTypeBlue,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  // 제목
                                  Expanded(
                                    child: Text(
                                      n.title,
                                      style: ResponsiveHelper.bodyStyle(
                                        context,
                                        fontWeight: titleWeight,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                  // 시간
                                  Text(
                                    n.timeAgo,
                                    style: ResponsiveHelper.tinyStyle(
                                      context,
                                      color: AppColors.grey400,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ],
                              ),

                              // Personal 카드: 사업장/업무 맥락 (제목 아래)
                              if (!isAdmin && n.businessName != null)
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: ResponsiveHelper.spacing(context, 1),
                                  ),
                                  child: Text(
                                    n.businessName!,
                                    style: ResponsiveHelper.tinyStyle(
                                      context,
                                      color: AppColors.textTertiary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),

                              SizedBox(height: ResponsiveHelper.spacing(context, 3)),

                              // 본문
                              Text(
                                n.body,
                                style: ResponsiveHelper.smallStyle(
                                  context,
                                  color: AppColors.grey600,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),

                              // CTA — ACTION_REQUIRED만 표시, 단일 버튼, Primary Blue
                              // "레이블 >" 형태로 우측 정렬. 실제 승인/거절은 상세 화면에서 처리.
                              if (isActionRequired)
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: ResponsiveHelper.spacing(context, 4),
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: widget.onTap,
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppColors.workTypeBlue,
                                        textStyle: ResponsiveHelper.smallStyle(
                                          context,
                                          color: AppColors.workTypeBlue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        padding: const EdgeInsets.only(
                                          left: 8,
                                          top: 3,
                                          bottom: 3,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(_ctaLabel),
                                          const SizedBox(width: 2),
                                          const Icon(Icons.chevron_right, size: 14),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
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
}
