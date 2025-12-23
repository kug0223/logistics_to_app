import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../../models/core/notification_model.dart';
import '../../widgets/common/notification_card.dart';
import '../../widgets/common/common_widgets.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../providers/user_provider.dart';
// 네비게이션 대상 화면들
import '../user/my_applications_screen.dart';
import '../user/my_schedule_screen.dart';
import '../user/dialogs/my_requests_dialog.dart';
import '../business_admin/workforce_management/integrated_workforce_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/core/to_model.dart';
import '../../models/core/work_detail_model.dart';
import '../../models/ui/admin_to_list_ui_models.dart';
import '../../services/firestore_service.dart';
import '../business_admin/dialogs/work_applicants_dialog.dart';

/// 알림 목록 화면
class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          Consumer<NotificationProvider>(
            builder: (context, provider, _) {
              if (provider.notifications.isEmpty) {
                return const SizedBox.shrink();
              }
              
              return TextButton(
                onPressed: () async {
                  await provider.markAllAsRead();
                  ToastHelper.showSuccess('모든 알림을 읽음 처리했습니다');
                },
                child: Text(
                  '모두 읽음',
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: theme.primaryColor,
                  ),
                ),
              );
            },
          ),
        ],
      ),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: ResponsiveHelper.iconSize(context, 80),
            color: Colors.grey[300],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Text(
            '알림이 없습니다',
            style: ResponsiveHelper.subtitleStyle(
              context,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
  
 void _handleNotificationTap(
    BuildContext context,
    NotificationModel notification,
    NotificationProvider provider,
  ) async {
    // 1. 읽음 처리
    await provider.markAsRead(notification.id);
    
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
          // 지원자가 받은 경우 (관리자가 요청) → 내 요청 다이얼로그
          _showMyRequestsDialog(context, userProvider.currentUser?.uid);
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
      // 계약해지 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.terminationRequested:
        // 지원자 → 내 요청 다이얼로그
        _showMyRequestsDialog(context, userProvider.currentUser?.uid);
        break;
        
      case NotificationType.terminationApproved:
        if (isUser) {
          // 지원자 → 내 스케줄 화면
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
        
      // ═══════════════════════════════════════════════════════════
      // 신분증 열람 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.idCardAccessRequested:
      case NotificationType.idCardAccessApproved:
      case NotificationType.idCardAccessRejected:
      case NotificationType.idCardAccessExpiringSoon:
        // 지원자 → 내 요청 다이얼로그
        _showMyRequestsDialog(context, userProvider.currentUser?.uid);
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
        
      case NotificationType.wageConfirmed:
      case NotificationType.reviewReceived:
      case NotificationType.systemNotice:
      case NotificationType.other:
        // 일단 스케줄 화면으로
        if (isUser) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
          );
        }
        break;
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
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 1. TO 조회
      final toDoc = await FirebaseFirestore.instance
          .collection('tos')
          .doc(toId)
          .get();
      
      if (!toDoc.exists) {
        Navigator.pop(context); // 로딩 닫기
        ToastHelper.showError('공고를 찾을 수 없습니다');
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
        );
        return;
      }

      final to = TOModel.fromMap(toDoc.data()!, toId);

      // 2. WorkDetail 조회
      final workDetailDoc = await FirebaseFirestore.instance
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc(workDetailId)
          .get();
      
      if (!workDetailDoc.exists) {
        Navigator.pop(context); // 로딩 닫기
        ToastHelper.showError('업무 정보를 찾을 수 없습니다');
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
        );
        return;
      }

      final workDetail = WorkDetailModel.fromMap(workDetailDoc.data()!, workDetailId);

      // 3. TOItem 생성
      final toItem = TOItem(
        to: to,
        workDetails: [workDetail],
        confirmedCount: workDetail.currentCount,
        pendingCount: workDetail.pendingCount,
        totalRequired: workDetail.requiredCount,
        isWorkDetailLoaded: true,
      );

      Navigator.pop(context); // 로딩 닫기

      // 4. 다이얼로그 열기
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (_) => WorkApplicantsDialog(
            work: workDetail,
            toItem: toItem,
            onChanged: () {},
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // 로딩 닫기
      print('❌ 알림 네비게이션 실패: $e');
      ToastHelper.showError('데이터를 불러오는데 실패했습니다');
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const IntegratedWorkforceScreen()),
      );
    }
  }
}