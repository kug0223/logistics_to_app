import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../../models/core/notification_model.dart';
import '../../widgets/common/notification_card.dart';
import '../../widgets/common/common_widgets.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';

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
                  onDismiss: () {
                    // TODO: 알림 삭제 기능 (Phase F에서 구현)
                    ToastHelper.showInfo('알림이 삭제되었습니다');
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
    
    // 2. Phase F에서 네비게이션 구현
    // TODO: 알림 타입에 따른 화면 이동
  }
}