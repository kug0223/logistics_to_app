import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/core/application_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/loading_state_mixin.dart';
import '../../../widgets/common/loading_button.dart';

/// 퇴사 요청 관리 다이얼로그 (관리자용)
class ResignRequestManagementDialog extends StatefulWidget {
  final String businessId;
  final VoidCallback onChanged;

  const ResignRequestManagementDialog({
    super.key,
    required this.businessId,
    required this.onChanged,
  });

  @override
  State<ResignRequestManagementDialog> createState() =>
      _ResignRequestManagementDialogState();
}

class _ResignRequestManagementDialogState
    extends State<ResignRequestManagementDialog>
    with LoadingStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  List<_ResignRequestWithUser> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadResignRequests();
  }

  /// 퇴사 요청 목록 로드
  Future<void> _loadResignRequests() => runWithLoading(() async {
    final applications = await _firestoreService.getResignRequests(
      widget.businessId,
    );

    final uniqueUids = applications.map((app) => app.uid).toSet().toList();
    final userEntries = await Future.wait(uniqueUids.map((uid) async {
      final user = await _firestoreService.getUser(uid);
      return MapEntry(uid, user);
    }));
    final userMap = Map.fromEntries(userEntries);

    final results = applications.map((app) {
      final user = userMap[app.uid];
      return _ResignRequestWithUser(
        application: app,
        userName: user?.name ?? '이름 없음',
        userPhone: user?.phone ?? '전화번호 없음',
      );
    }).toList();

    results.sort((a, b) => b.application.resignRequestedAt!
        .compareTo(a.application.resignRequestedAt!));

    if (mounted) setState(() => _requests = results);
    debugPrint('✅ 퇴사 요청 ${results.length}건 로드 완료');
  }, errorTag: '퇴사 요청 로드');

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          children: [
            // 헤더
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.exit_to_app, color: Colors.white),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
                  Text(
                    '퇴사 요청 관리',
                    style: ResponsiveHelper.titleStyle(context).copyWith(  // ⭐ 변경
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // 본문
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _requests.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
                          itemCount: _requests.length,
                          itemBuilder: (context, index) {
                            return _buildRequestCard(_requests[index]);
                          },
                        ),
            ),
          ],
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
            Icons.inbox, 
            size: ResponsiveHelper.iconSize(context, 64),  // ⭐ 변경
            color: Theme.of(context).disabledColor,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
          Text(
            '퇴사 요청이 없습니다',
            style: ResponsiveHelper.subtitleStyle(  // ⭐ 변경
              context,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  /// 요청 카드
  Widget _buildRequestCard(_ResignRequestWithUser item) {
    final app = item.application;
    final daysLeft = 3 - DateTime.now().difference(app.resignRequestedAt!).inDays;
    final isUrgent = daysLeft <= 1;

    return Card(
      margin: EdgeInsets.only(  // ⭐ const 제거
        bottom: ResponsiveHelper.spacing(context, 12),  // ⭐ 변경
      ),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isUrgent ? AppColors.error.withValues(alpha: 0.5) : Theme.of(context).dividerColor,
          width: isUrgent ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 근무자 정보
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                  child: Text(
                    item.userName[0],
                    style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.userName,
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(  // ⭐ 변경
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        item.userPhone,
                        style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                          context,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
                // 긴급 배지
                if (isUrgent)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 8),  // ⭐ 변경
                      vertical: ResponsiveHelper.spacing(context, 4),  // ⭐ 변경
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.warning, 
                          size: ResponsiveHelper.iconSize(context, 14),  // ⭐ 변경
                          color: AppColors.error,
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                        Text(
                          '긴급',
                          style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                            context,
                            color: AppColors.error,
                          ).copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경

            // 근무 정보
            Container(
              padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(Icons.business, '사업장', app.businessName),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                  _buildInfoRow(
                    Icons.calendar_today,
                    '근무 기간',
                    app.workPeriodDisplay,
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                  if (app.workDaysDisplay != null)
                    _buildInfoRow(
                      Icons.event_repeat,
                      '근무 요일',
                      app.workDaysDisplay!,
                    ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경

            // 퇴사 요청 정보
            Container(
              padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.exit_to_app,
                        size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
                        color: AppColors.warning,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                      Text(
                        '퇴사 희망일: ${DateFormat('yyyy년 M월 d일').format(app.resignRequestDate!)}',
                        style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                          context,
                          color: AppColors.warning,
                        ).copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                  Row(
                    children: [
                      Icon(
                        Icons.schedule, 
                        size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
                        color: AppColors.warning,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                      Text(
                        '요청일: ${DateFormat('M월 d일 HH:mm').format(app.resignRequestedAt!)}',
                        style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                          context,
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                  Row(
                    children: [
                      Icon(
                        isUrgent ? Icons.warning : Icons.info_outline,
                        size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
                        color: isUrgent ? AppColors.error : AppColors.warning,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                      Text(
                        daysLeft > 0
                            ? '$daysLeft일 후 자동 승인'
                            : '오늘 자정 자동 승인',
                        style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                          context,
                          color: isUrgent ? AppColors.error : AppColors.warning,
                        ).copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경

            // 승인/거절 버튼
            Row(
              children: [
                Expanded(
                  child: LoadingButton.outlined(
                    text: '거절',
                    icon: Icons.cancel,
                    borderColor: AppColors.error,
                    foregroundColor: AppColors.error,
                    onPressed: () async => await _handleReject(item),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: LoadingButton.success(
                    text: '승인',
                    icon: Icons.check_circle,
                    onPressed: () async => await _handleApprove(item),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 정보 행
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(
          icon, 
          size: ResponsiveHelper.iconSize(context, 14),  // ⭐ 변경
          color: Theme.of(context).textTheme.bodySmall?.color,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
        Text(
          '$label: ',
          style: ResponsiveHelper.smallStyle(  // ⭐ 변경
            context,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: ResponsiveHelper.smallStyle(context).copyWith(  // ⭐ 변경
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// 승인 처리
  Future<void> _handleApprove(_ResignRequestWithUser item) async {
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '퇴사 승인',
      message:
          '${item.userName}님의 퇴사를 승인하시겠습니까?\n\n'
          '퇴사일: ${DateFormat('yyyy년 M월 d일').format(item.application.resignRequestDate!)}\n\n'
          '승인 후에는 취소할 수 없습니다.',
      confirmText: '승인',
      confirmColor: AppColors.success,
    );

    if (!confirmed || !mounted) return;

    try {
      final adminUID = context.read<UserProvider>().currentUser?.uid ?? '';

      final success = await _firestoreService.approveResignation(
        applicationId: item.application.id,
        adminUID: adminUID,
      );

      if (success && mounted) {
        ToastHelper.showSuccess('퇴사가 승인되었습니다.');
        widget.onChanged();
        await _loadResignRequests();
      } else if (mounted) {
        ToastHelper.showError('승인 처리 중 오류가 발생했습니다.');
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.showError('승인 처리 중 오류가 발생했습니다.');
      }
    }
  }

  /// 거절 처리
  Future<void> _handleReject(_ResignRequestWithUser item) async {
    final reason = await DialogHelper.showTextInput(
      context,
      title: '퇴사 거절 사유',
      message: '${item.userName}님의 퇴사 요청을 거절하는 이유를 입력해주세요.',
      hintText: '거절 사유를 입력하세요',
      maxLines: 3,
      maxLength: 200,
      confirmText: '거절',
      confirmColor: AppColors.error,
      icon: Icons.cancel,
      iconColor: AppColors.error,
      validator: (value) {
        if (value == null || value.isEmpty) {
          ToastHelper.showWarning('거절 사유를 입력해주세요.');
          return false;
        }
        return true;
      },
    );

    if (reason == null || reason.isEmpty || !mounted) return;

    try {
      final adminUID = context.read<UserProvider>().currentUser?.uid ?? '';

      final success = await _firestoreService.rejectResignation(
        applicationId: item.application.id,
        adminUID: adminUID,
        rejectReason: reason,
      );

      if (success && mounted) {
        ToastHelper.showSuccess('퇴사 요청이 거절되었습니다.');
        widget.onChanged();
        await _loadResignRequests();
      } else if (mounted) {
        ToastHelper.showError('거절 처리 중 오류가 발생했습니다.');
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.showError('거절 처리 중 오류가 발생했습니다.');
      }
    }
  }
}

/// 퇴사 요청 + 사용자 정보
class _ResignRequestWithUser {
  final ApplicationModel application;
  final String userName;
  final String userPhone;

  _ResignRequestWithUser({
    required this.application,
    required this.userName,
    required this.userPhone,
  });
}