import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../../models/core/notification_model.dart';
import '../../widgets/common/notification_card.dart';
import '../../widgets/common/app_tab_label.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../providers/user_provider.dart';
// 네비게이션 대상 화면들
import '../user/my_applications_screen.dart';
import '../user/my_schedule_screen.dart';
import '../user/dialogs/my_requests_dialog.dart';
import '../business_admin/workforce_management/integrated_workforce_screen.dart';
import '../contract/contract_sign_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/core/to_model.dart';
import '../../models/core/work_detail_model.dart';
import '../../models/ui/admin_to_list_ui_models.dart';
import '../business_admin/dialogs/work_applicants_dialog.dart';
import '../business_admin/dialogs/fixed_worker_management_dialog.dart';
import '../../services/contract_service.dart';
import '../../services/member_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/loading_widget.dart';

/// 알림 목록 화면 (전체 / 미읽음 탭)
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool _isHandlingTap = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, provider, _) {
        final unreadList = provider.notifications.where((n) => !n.isRead).toList();

        return DefaultTabController(
          length: 2,
          child: GradientScaffold(
            title: '알림',
            showNotificationBell: false,
            headerBottom: TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: Colors.white,
              indicatorWeight: 2.5,
              dividerColor: Colors.transparent,
              tabs: [
                Tab(
                  child: AppTabLabel(
                    label: '전체',
                    count: provider.notifications.length,
                    badgeColor: Colors.white,
                  ),
                ),
                Tab(
                  child: AppTabLabel(
                    label: '미읽음',
                    count: provider.unreadCount,
                    badgeColor: AppColors.error,
                    urgent: provider.hasUnread,
                  ),
                ),
              ],
            ),
            actions: [
              if (provider.hasUnread)
                TextButton(
                  onPressed: () async {
                    await provider.markAllAsRead();
                    ToastHelper.showSuccess('모든 알림을 읽음 처리했습니다');
                  },
                  child: Text(
                    '모두 읽음',
                    style: ResponsiveHelper.smallStyle(context, color: Colors.white),
                  ),
                ),
            ],
            body: _buildBody(context, provider, unreadList),
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    NotificationProvider provider,
    List<NotificationModel> unreadList,
  ) {
    if (provider.isLoading) {
      return const LoadingWidget(message: '알림 불러오는 중...');
    }
    if (provider.hasError) {
      return _buildErrorState(context, provider);
    }

    return TabBarView(
      children: [
        _buildList(
          context, provider, provider.notifications,
          hasMore: provider.hasMore,
          isLoadingMore: provider.isLoadingMore,
          onLoadMore: provider.loadMore,
        ),
        _buildList(context, provider, unreadList, emptyMessage: '미읽음 알림이 없습니다'),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    NotificationProvider provider,
    List<NotificationModel> notifications, {
    String emptyMessage = '알림이 없습니다',
    bool hasMore = false,
    bool isLoadingMore = false,
    VoidCallback? onLoadMore,
  }) {
    if (notifications.isEmpty) {
      return AppEmptyState(
        icon: Icons.notifications_none,
        title: emptyMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        // 에러 상태인 경우 스트림 재연결, 정상 상태에서는 Firestore 스트림이 자동 갱신
        provider.retry();
        await Future.delayed(const Duration(milliseconds: 300));
      },
      child: ListView.builder(
        itemCount: notifications.length + (hasMore ? 1 : 0),
        padding: ResponsiveHelper.listPadding(context),
        itemBuilder: (context, index) {
          if (hasMore && index == notifications.length) {
            return Padding(
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
              child: Center(
                child: isLoadingMore
                    ? const CircularProgressIndicator()
                    : TextButton.icon(
                        onPressed: onLoadMore,
                        icon: const Icon(Icons.expand_more),
                        label: const Text('이전 알림 더 보기'),
                      ),
              ),
            );
          }
          final notification = notifications[index];
          return NotificationCard(
            notification: notification,
            onTap: () => _handleNotificationTap(context, notification, provider),
            onDismiss: () async {
              final success = await provider.deleteNotification(notification.id);
              if (success) {
                ToastHelper.showSuccess('알림이 삭제되었습니다');
              } else {
                ToastHelper.showError('알림 삭제에 실패했습니다');
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, NotificationProvider provider) {
    return AppEmptyState(
      icon: Icons.cloud_off_outlined,
      iconColor: Colors.orange,
      title: '알림을 불러오지 못했습니다',
      subtitle: '네트워크 상태를 확인하고 다시 시도해주세요',
      action: TextButton.icon(
        onPressed: provider.retry,
        icon: const Icon(Icons.refresh),
        label: const Text('다시 시도'),
      ),
    );
  }

  Future<void> _handleNotificationTap(
    BuildContext context,
    NotificationModel notification,
    NotificationProvider provider,
  ) async {
    if (_isHandlingTap) return;
    _isHandlingTap = true;
    // 1. 읽음 처리 (실패해도 네비게이션은 계속)
    try {
      await provider.markAsRead(notification.id);
    } catch (_) {}

    if (!context.mounted) {
      _isHandlingTap = false;
      return;
    }

    // 2. 알림 타입에 따른 화면 이동
    final userProvider = context.read<UserProvider>();
    final isUser = userProvider.isUser;

    switch (notification.type) {
      // ═══════════════════════════════════════════════════════════
      // 지원 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.applicationConfirmed:
      case NotificationType.applicationRejected:
      case NotificationType.confirmationCanceled:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
        );
        break;

      case NotificationType.newApplication:
      case NotificationType.applicationCanceled:
        await _openWorkApplicantsFromNotification(context, notification);
        break;

      // ═══════════════════════════════════════════════════════════
      // 스케줄 변경 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.scheduleChangeRequested:
        if (isUser) {
          _showMyRequestsDialog(context, userProvider.currentUser?.uid);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
          );
        }
        break;

      case NotificationType.scheduleChangeApproved:
      case NotificationType.scheduleChangeRejected:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
        break;

      // ═══════════════════════════════════════════════════════════
      // 근로계약서 서명 요청
      // ═══════════════════════════════════════════════════════════
      case NotificationType.contractSignRequested:
        await _openContractSignFromNotification(context, notification);
        break;

      case NotificationType.contractExpiringReminder:
        {
          final businessId = userProvider.effectiveBusinessId;
          if (businessId != null) {
            showDialog(
              context: context,
              builder: (_) => FixedWorkerManagementDialog(
                initialBusinessId: businessId,
                onChanged: () {},
              ),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
            );
          }
        }
        break;

      case NotificationType.contractRenewed:
      case NotificationType.contractTerminating:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
        break;

      // ═══════════════════════════════════════════════════════════
      // 계약해지 / 퇴사 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.terminationRequested:
        if (isUser) {
          _showMyRequestsDialog(context, userProvider.currentUser?.uid);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
          );
        }
        break;

      case NotificationType.terminationApproved:
      case NotificationType.resignApproved:
      case NotificationType.resignRejected:
        if (isUser) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
          );
        }
        break;

      case NotificationType.resignRequested:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
        );
        break;

      // ═══════════════════════════════════════════════════════════
      // 신분증 열람 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.idCardAccessRequested:
        _showMyRequestsDialog(context, userProvider.currentUser?.uid);
        break;

      case NotificationType.idCardAccessApproved:
      case NotificationType.idCardAccessRejected:
      case NotificationType.idCardAccessExpiringSoon:
        if (isUser) {
          _showMyRequestsDialog(context, userProvider.currentUser?.uid);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
          );
        }
        break;

      // ═══════════════════════════════════════════════════════════
      // 근무 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.workReminder:
      case NotificationType.workCanceled:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
        break;

      // ═══════════════════════════════════════════════════════════
      // 멤버 초대 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.memberInvitationReceived:
        await _handleMemberInvitation(context, notification);
        break;

      case NotificationType.memberInvitationAccepted:
      case NotificationType.memberInvitationRejected:
        break;

      // ═══════════════════════════════════════════════════════════
      // 급여 관련 알림 — MyScheduleScreen으로 이동
      // (MyApplicationsScreen은 지원 내역 목록이며 급여 확인과 무관)
      // ═══════════════════════════════════════════════════════════
      case NotificationType.wageConfirmed:
      case NotificationType.wageCancelConfirmed:
      case NotificationType.retroactiveDeductionAlert:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
        break;

      case NotificationType.reviewReceived:
      case NotificationType.systemNotice:
      case NotificationType.other:
        if (isUser) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
          );
        }
        break;
    }
    if (mounted) _isHandlingTap = false;
  }

  /// 알림에서 계약서 서명 화면 열기 (근무자용)
  Future<void> _openContractSignFromNotification(
    BuildContext context,
    NotificationModel notification,
  ) async {
    final contractId = notification.data?['contractId'] as String?;
    if (contractId == null || contractId.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingWidget(),
    );

    try {
      final currentUser = context.read<UserProvider>().currentUser;
      // USER 컨텍스트 — 보안 규칙 workerId == auth.uid 필터 사용 (businessId 불필요)
      final contract = await ContractService().getByApplication(
        notification.data?['applicationId'] as String? ?? '',
        workerId: currentUser?.uid,
      );

      if (!context.mounted) return;
      Navigator.pop(context);

      if (contract == null) {
        ToastHelper.showError('계약서를 찾을 수 없습니다');
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ContractSignScreen(contract: contract, role: 'worker'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ToastHelper.showError('계약서를 불러오는데 실패했습니다');
    }
  }

  /// 내 요청 다이얼로그 표시
  void _showMyRequestsDialog(BuildContext context, String? uid) {
    if (uid == null) {
      ToastHelper.showError('사용자 정보를 찾을 수 없습니다');
      return;
    }

    showDialog(
      context: context,
      builder: (_) => MyRequestsDialog(
        applicantUid: uid,
        onChanged: () {},
      ),
    );
  }

  /// 하위 관리자 초대 수락/거절 처리
  Future<void> _handleMemberInvitation(
    BuildContext context,
    NotificationModel notification,
  ) async {
    final invitationId = notification.data?['invitationId'] as String?;
    if (invitationId == null || invitationId.isEmpty) {
      ToastHelper.showError('초대 정보를 찾을 수 없습니다');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingWidget(),
    );

    try {
      final invitation = await MemberService().getInvitation(invitationId);

      if (!context.mounted) return;
      Navigator.pop(context);

      if (invitation == null || !invitation.isPending) {
        ToastHelper.showError('이미 처리된 초대입니다');
        return;
      }

      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('${invitation.businessName} 초대'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${invitation.invitedByName}님이 하위 관리자로 초대했습니다.'),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.grey50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '부여 권한',
                      style: ResponsiveHelper.smallStyle(ctx, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(invitation.permissions.summaryText),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('거절'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('수락'),
            ),
          ],
        ),
      );

      if (result == null || !context.mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const LoadingWidget(),
      );

      if (result) {
        await MemberService().acceptInvitation(invitation);
        if (!context.mounted) return;
        Navigator.pop(context);
        await context.read<UserProvider>().refreshUserData();
        if (!context.mounted) return;
        ToastHelper.showSuccess('초대를 수락했습니다. 잠시 후 관리자 모드를 사용할 수 있어요!');
      } else {
        await MemberService().rejectInvitation(invitation);
        if (!context.mounted) return;
        Navigator.pop(context);
        ToastHelper.showSuccess('초대를 거절했습니다');
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ToastHelper.showError('초대 처리 중 오류가 발생했습니다');
    }
  }

  /// 알림에서 지원자 관리 다이얼로그 열기
  Future<void> _openWorkApplicantsFromNotification(
    BuildContext context,
    NotificationModel notification,
  ) async {
    final data = notification.data;
    if (data == null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
      );
      return;
    }

    final toId = data['toId'] as String?;
    final workDetailId = data['workDetailId'] as String?;

    if (toId == null || toId.isEmpty || workDetailId == null || workDetailId.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingWidget(),
    );

    try {
      final toDoc = await FirebaseFirestore.instance.collection('tos').doc(toId).get();

      if (!toDoc.exists) {
        if (!context.mounted) return;
        Navigator.pop(context);
        ToastHelper.showError('공고를 찾을 수 없습니다');
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
        );
        return;
      }

      final toData = toDoc.data();
      if (toData == null) {
        if (!context.mounted) return;
        Navigator.pop(context);
        ToastHelper.showError('공고 데이터를 불러올 수 없습니다');
        Navigator.push(context, MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()));
        return;
      }
      final to = TOModel.fromMap(toData, toId);

      final workDetailDoc = await FirebaseFirestore.instance
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc(workDetailId)
          .get();

      if (!workDetailDoc.exists) {
        if (!context.mounted) return;
        Navigator.pop(context);
        ToastHelper.showError('업무 정보를 찾을 수 없습니다');
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
        );
        return;
      }

      final workDetailData = workDetailDoc.data();
      if (workDetailData == null) {
        if (!context.mounted) return;
        Navigator.pop(context);
        ToastHelper.showError('업무 정보를 불러올 수 없습니다');
        Navigator.push(context, MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()));
        return;
      }
      final workDetail = WorkDetailModel.fromMap(workDetailData, workDetailId);

      final toItem = TOItem(
        to: to,
        workDetails: [workDetail],
        confirmedCount: workDetail.currentCount,
        pendingCount: workDetail.pendingCount,
        totalRequired: workDetail.requiredCount,
        isWorkDetailLoaded: true,
      );

      if (!context.mounted) return;
      Navigator.pop(context);

      showDialog(
        context: context,
        builder: (_) => WorkApplicantsDialog(
          work: workDetail,
          toItem: toItem,
          onChanged: () {},
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      debugPrint('❌ 알림 네비게이션 실패: $e');
      ToastHelper.showError('데이터를 불러오는데 실패했습니다');
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
      );
    }
  }
}
