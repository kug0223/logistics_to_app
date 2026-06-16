// lib/screens/user/dialogs/my_requests_dialog.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/core/schedule_change_request_model.dart';
import '../../../models/core/id_card_access_request_model.dart';
import '../../../models/core/application_model.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../theme/app_colors.dart';

/// 통합 알림 아이템 타입
enum NotificationItemType {
  scheduleChange,   // 스케줄 변경 요청
  idCardRequest,    // 신분증 열람 요청
  termination,      // 계약해지 요청
}

/// 통합 알림 아이템
class _NotificationItem {
  final NotificationItemType type;
  final dynamic data;
  final DateTime requestedAt;

  _NotificationItem({
    required this.type,
    required this.data,
    required this.requestedAt,
  });
}

/// 내 알림 다이얼로그 (스케줄 변경 + 신분증 요청 + 계약해지 통합)
class MyRequestsDialog extends StatefulWidget {
  final String applicantUid;
  final VoidCallback onChanged;

  const MyRequestsDialog({
    super.key,
    required this.applicantUid,
    required this.onChanged,
  });

  @override
  State<MyRequestsDialog> createState() => _MyRequestsDialogState();
}

class _MyRequestsDialogState extends State<MyRequestsDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  
  List<_NotificationItem> _allNotifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllNotifications();
  }

  /// 모든 알림 로드 (3가지 타입 통합)
  Future<void> _loadAllNotifications() async {
    setState(() => _isLoading = true);

    try {
      // 병렬 조회
      final results = await Future.wait([
        _firestoreService.getMyScheduleChangeRequests(widget.applicantUid),
        _firestoreService.getPendingIdCardRequestsForUser(widget.applicantUid),
        _firestoreService.getMyTerminationRequests(widget.applicantUid),
      ]);

      final scheduleRequests = results[0] as List<ScheduleChangeRequestModel>;
      final idCardRequests = results[1] as List<IdCardAccessRequestModel>;
      final terminations = results[2] as List<ApplicationModel>;

      // 통합 리스트 생성
      final notifications = <_NotificationItem>[];

      // 1. 스케줄 변경 요청 (관리자가 보낸 PENDING만)
      for (final req in scheduleRequests) {
        if (req.isPending && req.isAdminRequest) {
          notifications.add(_NotificationItem(
            type: NotificationItemType.scheduleChange,
            data: req,
            requestedAt: req.requestedAt,
          ));
        }
      }

      // 2. 신분증 열람 요청
      for (final req in idCardRequests) {
        notifications.add(_NotificationItem(
          type: NotificationItemType.idCardRequest,
          data: req,
          requestedAt: req.requestedAt,
        ));
      }

      // 3. 계약해지 요청
      for (final app in terminations) {
        if (app.terminationRequestedAt != null) {
          notifications.add(_NotificationItem(
            type: NotificationItemType.termination,
            data: app,
            requestedAt: app.terminationRequestedAt!,
          ));
        }
      }

      // 최신순 정렬
      notifications.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

      if (!mounted) return;
      setState(() {
        _allNotifications = notifications;
        _isLoading = false;
      });

      debugPrint('✅ 알림 로드 완료: ${notifications.length}건');
    } catch (e) {
      debugPrint('❌ 알림 로드 실패: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: AppDialogSize.insetV,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
        ),
        child: Padding(
          padding: ResponsiveHelper.listPadding(context),
          child: Column(
          children: [
            // 헤더
            Row(
              children: [
                Icon(
                  Icons.notifications,
                  size: ResponsiveHelper.iconSize(context, 28),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Text(
                  '내 알림',
                  style: ResponsiveHelper.titleStyle(context),
                ),
                if (_allNotifications.isNotEmpty)
                  Container(
                    margin: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 8)),
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 8),
                      vertical: ResponsiveHelper.spacing(context, 2),
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_allNotifications.length}',
                      style: ResponsiveHelper.tinyStyle(context, color: Colors.white),
                    ),
                  ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            Divider(height: ResponsiveHelper.spacing(context, 24)),

            // 알림 목록
            Expanded(
              child: _isLoading
                  ? const LoadingWidget(message: '알림 로딩 중...')
                  : _allNotifications.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          itemCount: _allNotifications.length,
                          itemBuilder: (context, index) {
                            return _buildNotificationCard(_allNotifications[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: ResponsiveHelper.iconSize(context, 64),
            color: Theme.of(context).disabledColor,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Text(
            '알림이 없습니다',
            style: ResponsiveHelper.subtitleStyle(
              context,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  /// 통합 알림 카드
  Widget _buildNotificationCard(_NotificationItem item) {
    switch (item.type) {
      case NotificationItemType.scheduleChange:
        return _buildScheduleChangeCard(item.data as ScheduleChangeRequestModel);
      case NotificationItemType.idCardRequest:
        return _buildIdCardRequestCard(item.data as IdCardAccessRequestModel);
      case NotificationItemType.termination:
        return _buildTerminationCard(item.data as ApplicationModel);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 스케줄 변경 요청 카드
  // ═══════════════════════════════════════════════════════════

  Widget _buildScheduleChangeCard(ScheduleChangeRequestModel request) {
    IconData icon;
    Color iconColor;

    if (request.isLeaveRequest) {
      icon = Icons.beach_access;
      iconColor = AppColors.warning;
    } else if (request.isNoWorkRequest) {
      icon = Icons.block;
      iconColor = AppColors.error;
    } else {
      icon = Icons.add_circle;
      iconColor = AppColors.success;
    }

    return Card(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: iconColor.withValues(alpha: 0.2),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(
          request.requestTypeLabel,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(FormatHelper.formatDateKorean(request.targetDate)),
            if (request.reason != null)
              Text(
                request.reason!,
                style: ResponsiveHelper.tinyStyle(
                  context,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            _buildStatusChip('대기중', AppColors.warning),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.error),
              onPressed: () => _handleScheduleReject(request),
              tooltip: '거절',
            ),
            IconButton(
              icon: const Icon(Icons.check, color: AppColors.success),
              onPressed: () => _handleScheduleApprove(request),
              tooltip: '수락',
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 신분증 열람 요청 카드
  // ═══════════════════════════════════════════════════════════

  Widget _buildIdCardRequestCard(IdCardAccessRequestModel request) {
    return Card(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      color: AppColors.infoBg,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.info.withValues(alpha: 0.2),
          child: Icon(Icons.badge, color: AppColors.info),
        ),
        title: Text(
          '신분증 열람 요청',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(request.requesterBusinessName),
            Text(
              '요청자: ${request.requesterName}',
              style: ResponsiveHelper.tinyStyle(
                context,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            Text(
              '사유: ${request.reasonText}',
              style: ResponsiveHelper.tinyStyle(
                context,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            _buildStatusChip('승인 대기', AppColors.info),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.error),
              onPressed: () => _handleIdCardReject(request),
              tooltip: '거절',
            ),
            IconButton(
              icon: const Icon(Icons.check, color: AppColors.success),
              onPressed: () => _handleIdCardApprove(request),
              tooltip: '승인',
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 계약해지 요청 카드
  // ═══════════════════════════════════════════════════════════

  Widget _buildTerminationCard(ApplicationModel app) {
    final requestedAt = app.terminationRequestedAt;
    final daysLeft = requestedAt != null
        ? 3 - DateTime.now().difference(requestedAt).inDays
        : 0;

    return Card(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      color: AppColors.warningBg,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.warning.withValues(alpha: 0.2),
          child: Icon(Icons.warning_amber, color: AppColors.warning),
        ),
        title: Text(
          '계약해지 요청',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.warningDark,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(app.businessName),
            if (app.terminationReason != null)
              Text(
                '사유: ${app.terminationReason}',
                style: ResponsiveHelper.tinyStyle(
                  context,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Row(
              children: [
                _buildStatusChip(
                  daysLeft > 0 ? '$daysLeft일 후 자동승인' : '오늘 자동승인',
                  AppColors.warning,
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: AppColors.error),
              onPressed: () => _handleTerminationReject(app),
              tooltip: '거절',
            ),
            IconButton(
              icon: const Icon(Icons.check, color: AppColors.success),
              onPressed: () => _handleTerminationApprove(app),
              tooltip: '승인',
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 공통 위젯
  // ═══════════════════════════════════════════════════════════

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: ResponsiveHelper.tinyStyle(
          context,
          color: color,
        ).copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 스케줄 변경 액션
  // ═══════════════════════════════════════════════════════════

  Future<void> _handleScheduleApprove(ScheduleChangeRequestModel request) async {
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;
    if (uid == null) return;

    final success = await _firestoreService.approveScheduleChangeRequest(
      requestId: request.id,
      approverUid: uid,
    );

    if (!mounted) return;
    if (success) {
      ToastHelper.showSuccess('수락되었습니다');
      await _loadAllNotifications();
      widget.onChanged();
    } else {
      ToastHelper.showError('수락 실패');
    }
  }

  Future<void> _handleScheduleReject(ScheduleChangeRequestModel request) async {
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;
    if (uid == null) return;

    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: const Text('거절 사유'),
        content: SingleChildScrollView(
          child: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            hintText: '거절 사유를 입력하세요 (선택)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('거절'),
          ),
        ],
      ),
    );

    final scheduleRejectReason = reasonController.text.trim().isEmpty ? null : reasonController.text.trim();
    reasonController.dispose();

    if (confirmed != true) return;
    if (!mounted) return;

    final success = await _firestoreService.rejectScheduleChangeRequest(
      requestId: request.id,
      rejectorUid: uid,
      rejectReason: scheduleRejectReason,
    );

    if (!mounted) return;
    if (success) {
      ToastHelper.showSuccess('거절되었습니다');
      await _loadAllNotifications();
      widget.onChanged();
    } else {
      ToastHelper.showError('거절 실패');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 신분증 요청 액션
  // ═══════════════════════════════════════════════════════════

  Future<void> _handleIdCardApprove(IdCardAccessRequestModel request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('신분증 열람 승인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${request.requesterBusinessName}에서 신분증 열람을 요청했습니다.'),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text('요청 사유: ${request.reasonText}'),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text(
              '승인 시 7일간 열람 가능합니다.',
              style: ResponsiveHelper.smallStyle(
                context,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('승인'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final success = await _firestoreService.approveIdCardAccessRequest(request.id);

    if (!mounted) return;
    if (success) {
      ToastHelper.showSuccess('승인되었습니다');
      await _loadAllNotifications();
      widget.onChanged();
    } else {
      ToastHelper.showError('승인 실패');
    }
  }

  Future<void> _handleIdCardReject(IdCardAccessRequestModel request) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: const Text('신분증 열람 거절'),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${request.requesterBusinessName}의 요청을 거절합니다.'),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: '거절 사유 (선택)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('거절'),
          ),
        ],
      ),
    );

    final idCardRejectReason = reasonController.text.trim().isEmpty ? null : reasonController.text.trim();
    reasonController.dispose();

    if (confirmed != true) return;
    if (!mounted) return;

    final success = await _firestoreService.rejectIdCardAccessRequest(
      request.id,
      reason: idCardRejectReason,
    );

    if (!mounted) return;
    if (success) {
      ToastHelper.showSuccess('거절되었습니다');
      await _loadAllNotifications();
      widget.onChanged();
    } else {
      ToastHelper.showError('거절 실패');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 계약해지 액션
  // ═══════════════════════════════════════════════════════════

  Future<void> _handleTerminationApprove(ApplicationModel app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('계약해지 승인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${app.businessName}과의 계약을 해지합니다.'),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            if (app.terminationReason != null)
              Text('해지 사유: ${app.terminationReason}'),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text(
              '승인 시 즉시 계약이 해지됩니다.',
              style: ResponsiveHelper.smallStyle(
                context,
                color: AppColors.error,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('승인 (해지)'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final success = await _firestoreService.approveTermination(app.id);

    if (!mounted) return;
    if (success) {
      ToastHelper.showSuccess('계약이 해지되었습니다');
      await _loadAllNotifications();
      widget.onChanged();
    } else {
      ToastHelper.showError('처리 실패');
    }
  }

  Future<void> _handleTerminationReject(ApplicationModel app) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: const Text('계약해지 거절'),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${app.businessName}의 계약해지 요청을 거절합니다.'),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: '거절 사유 (선택)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.info),
            child: const Text('거절'),
          ),
        ],
      ),
    );

    final terminationRejectReason = reasonController.text.trim().isEmpty ? null : reasonController.text.trim();
    reasonController.dispose();

    if (confirmed != true) return;
    if (!mounted) return;

    final success = await _firestoreService.rejectTermination(
      applicationId: app.id,
      rejectReason: terminationRejectReason,
    );

    if (!mounted) return;
    if (success) {
      ToastHelper.showSuccess('거절되었습니다');
      await _loadAllNotifications();
      widget.onChanged();
    } else {
      ToastHelper.showError('거절 실패');
    }
  }
}