import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../../models/core/notification_model.dart';
import '../../widgets/common/notification_card.dart';
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
import '../../services/contract_service.dart';
import '../../services/member_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/loading_widget.dart';

/// 알림 목록 화면
class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '알림',
      actions: [
        Consumer<NotificationProvider>(
          builder: (context, provider, _) {
            if (provider.notifications.isEmpty) return const SizedBox.shrink();
            return TextButton(
              onPressed: () async {
                await provider.markAllAsRead();
                ToastHelper.showSuccess('모든 알림을 읽음 처리했습니다');
              },
              child: Text('모두 읽음',
                  style: ResponsiveHelper.smallStyle(context, color: Colors.white)),
            );
          },
        ),
      ],
      body: Consumer<NotificationProvider>(
        builder: (context, provider, _) {
          if (provider.notifications.isEmpty) {
            return _buildEmptyState(context);
          }
          
          return RefreshIndicator(
            onRefresh: () async {
              // 스트림 기반이라 별도 새로고침 불필요
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: ListView.builder(
              itemCount: provider.notifications.length,
              padding: ResponsiveHelper.listPadding(context),
              itemBuilder: (context, index) {
                final notification = provider.notifications[index];
                
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
        },
      ),
    );
  }
  
  Widget _buildEmptyState(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.notifications_none,
      title: '알림이 없습니다',
    );
  }
  
 void _handleNotificationTap(
    BuildContext context,
    NotificationModel notification,
    NotificationProvider provider,
  ) async {
    // 1. 읽음 처리 (실패해도 네비게이션은 계속)
    try {
      await provider.markAsRead(notification.id);
    } catch (_) {}

    if (!context.mounted) return;

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
        // 지원자 → 내 지원 내역
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
        );
        break;
        
      case NotificationType.newApplication:
      case NotificationType.applicationCanceled:
        // 관리자 → 해당 업무의 지원자 관리 다이얼로그
        await _openWorkApplicantsFromNotification(context, notification);
        break;
        
      // ═══════════════════════════════════════════════════════════
      // 스케줄 변경 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.scheduleChangeRequested:
        if (isUser) {
          // 지원자가 받은 경우 → 내 스케줄 화면
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
          );
        } else {
          // 관리자가 받은 경우 → 인력 관리 화면
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
          );
        }
        break;
        
      case NotificationType.scheduleChangeApproved:
      case NotificationType.scheduleChangeRejected:
        // 지원자 → 내 스케줄 화면
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
        // 관리자 → 고정근무 관리 화면 (연장/종료 선택)
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
        );
        break;

      case NotificationType.contractRenewed:
      case NotificationType.contractTerminating:
        // 근무자 → 내 스케줄 화면
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
        break;

      // ═══════════════════════════════════════════════════════════
      // 계약해지 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.terminationRequested:
        // 지원자 → 내 스케줄 화면
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
        break;
        
      case NotificationType.terminationApproved:
      case NotificationType.resignApproved:
      case NotificationType.resignRejected:
        if (isUser) {
          // 근무자 → 내 스케줄 화면
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
          );
        } else {
          // 관리자 → 인력 관리 화면
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
          );
        }
        break;

      case NotificationType.resignRequested:
        // 관리자 → 퇴사 요청 관리 화면
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
        );
        break;

      // ═══════════════════════════════════════════════════════════
      // 신분증 열람 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.idCardAccessRequested:
        // 신분증 소유자(지원자)에게 오는 알림 → 내 요청 다이얼로그에서 확인
        _showMyRequestsDialog(context, userProvider.currentUser?.uid);
        break;
      case NotificationType.idCardAccessApproved:
      case NotificationType.idCardAccessRejected:
      case NotificationType.idCardAccessExpiringSoon:
        // 요청자(관리자)에게 오는 알림 → 인력 관리 화면, 사용자면 내 요청 다이얼로그
        if (isUser) {
          _showMyRequestsDialog(context, userProvider.currentUser?.uid);
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()));
        }
        break;
        
      // ═══════════════════════════════════════════════════════════
      // 기타 알림 (향후 구현)
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
        // 수락/거절 알림 확인 — 별도 네비게이션 없음
        break;

      case NotificationType.wageConfirmed:
      case NotificationType.wageCancelConfirmed:
        if (isUser) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
          );
        }
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
      final contract = await ContractService().getByApplication(
        notification.data?['applicationId'] as String? ?? '',
      );

      if (!context.mounted) return;
      Navigator.pop(context); // 로딩 닫기

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
        ToastHelper.showSuccess('초대를 수락했습니다. 관리자 모드를 사용할 수 있어요!');
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

    // 데이터 없으면 기존처럼 인력관리 화면으로
    if (toId == null || toId.isEmpty || workDetailId == null || workDetailId.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
      );
      return;
    }

    // 로딩 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingWidget(),
    );

    try {
      // 1. TO 조회
      final toDoc = await FirebaseFirestore.instance
          .collection('tos')
          .doc(toId)
          .get();
      
      if (!toDoc.exists) {
        if (!context.mounted) return;
        Navigator.pop(context); // 로딩 닫기
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

      // 2. WorkDetail 조회
      final workDetailDoc = await FirebaseFirestore.instance
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc(workDetailId)
          .get();

      if (!workDetailDoc.exists) {
        if (!context.mounted) return;
        Navigator.pop(context); // 로딩 닫기
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

      // 3. TOItem 생성
      final toItem = TOItem(
        to: to,
        workDetails: [workDetail],
        confirmedCount: workDetail.currentCount,
        pendingCount: workDetail.pendingCount,
        totalRequired: workDetail.requiredCount,
        isWorkDetailLoaded: true,
      );

      if (!context.mounted) return;
      Navigator.pop(context); // 로딩 닫기

      // 4. 다이얼로그 열기
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
      Navigator.pop(context); // 로딩 닫기
      debugPrint('❌ 알림 네비게이션 실패: $e');
      ToastHelper.showError('데이터를 불러오는데 실패했습니다');
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
      );
    }
  }
}
