import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:intl/intl.dart';
import '../../models/core/application_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';  // ⭐ 추가
import '../pickers/date_picker_bottom_sheet.dart';

/// 고정근무 관리 다이얼로그
class LongTermWorkManagementDialog extends StatefulWidget {
  final List<ApplicationModel> applications;
  final VoidCallback onChanged;

  const LongTermWorkManagementDialog({
    super.key,
    required this.applications,
    required this.onChanged,
  });

  @override
  State<LongTermWorkManagementDialog> createState() =>
      _LongTermWorkManagementDialogState();
}

class _LongTermWorkManagementDialogState
    extends State<LongTermWorkManagementDialog> {
  final FirestoreService _firestoreService = FirestoreService();

  @override
  Widget build(BuildContext context) {
    // 확정된 장기 근무만 필터링 (퇴사/해지 완료 제외)
    final longTermWorks = widget.applications
        .where((app) =>
            app.isLongTermApplication &&
            AppStatus.confirmedStatuses.contains(app.status) &&
            !app.isTerminationApproved)
        .toList();

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 24),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Container(
              padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.work, color: Colors.white),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
                  Text(
                    '고정근무 관리',
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
              child: longTermWorks.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
                      itemCount: longTermWorks.length,
                      itemBuilder: (context, index) {
                        return _buildWorkCard(longTermWorks[index]);
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
            Icons.work_off, 
            size: ResponsiveHelper.iconSize(context, 64),  // ⭐ 변경
            color: Theme.of(context).disabledColor,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
          Text(
            '확정된 고정근무가 없습니다',
            style: ResponsiveHelper.subtitleStyle(  // ⭐ 변경
              context,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  /// 근무 카드
  Widget _buildWorkCard(ApplicationModel app) {
    final hasResignRequest = app.resignStatus != null;
    final isPending = app.resignStatus == AppStatus.pending;
    final isRejected = app.resignStatus == AppStatus.rejected;

    return Card(
      margin: EdgeInsets.only(  // ⭐ const 제거
        bottom: ResponsiveHelper.spacing(context, 12),  // ⭐ 변경
      ),
      elevation: 2,
      child: Padding(
        padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 사업장명
            Row(
              children: [
                Icon(
                  Icons.business, 
                  size: ResponsiveHelper.iconSize(context, 18),  // ⭐ 변경
                  color: Theme.of(context).primaryColor,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                Expanded(
                  child: Text(
                    app.businessName,
                    style: ResponsiveHelper.subtitleStyle(context),  // ⭐ 변경
                  ),
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경

            // 근무 기간
            _buildInfoRow(
              Icons.calendar_today,
              '근무 기간',
              app.workPeriodDisplay,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경

            // 근무 요일
            if (app.workDaysDisplay != null)
              _buildInfoRow(
                Icons.event_repeat,
                '근무 요일',
                app.workDaysDisplay!,
              ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경

            // 근무 시간
            _buildInfoRow(
              Icons.access_time,
              '근무 시간',
              '${app.startTime} ~ ${app.endTime}',
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경

            // 업무 유형 & 급여
            Row(
              children: [
                Expanded(
                  child: _buildInfoRow(
                    Icons.work,
                    '업무',
                    app.selectedWorkType,
                  ),
                ),
                Expanded(
                  child: _buildInfoRow(
                    Icons.attach_money,
                    '급여',
                    FormatHelper.formatWage(app.wage),
                  ),
                ),
              ],
            ),

            // 퇴사 요청 상태 표시
            if (hasResignRequest) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
              _buildResignStatusBanner(app),
            ],

            SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경

            // 버튼
            if (isPending)
              // 퇴사 요청 대기 중 - 취소 버튼만
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _handleCancelResignRequest(app),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('퇴사 요청 취소'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    side: const BorderSide(color: AppColors.warning),
                  ),
                ),
              )
            else if (isRejected)
              // 퇴사 거절됨 - 재요청 버튼
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _handleResignRequest(app),
                  icon: const Icon(Icons.refresh),
                  label: const Text('퇴사 재요청'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  ),
                ),
              )
            else
              // 정상 상태 - 퇴사 요청 버튼
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _handleResignRequest(app),
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text('퇴사 요청'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 퇴사 상태 배너
  Widget _buildResignStatusBanner(ApplicationModel app) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String statusText;
    String? detailText;

    switch (app.resignStatus) {
      case AppStatus.pending:
        bgColor = AppColors.warning.withValues(alpha: 0.1);
        textColor = AppColors.warning;
        icon = Icons.schedule;
        statusText = '퇴사 승인 대기중';
        final requestDate = DateFormat('M월 d일').format(app.resignRequestDate ?? DateTime.now());
        final daysLeft = 3 - DateTime.now().difference(app.resignRequestedAt ?? DateTime.now()).inDays;
        detailText = '$requestDate 퇴사 요청 ($daysLeft일 후 자동 승인)';
        break;
      case AppStatus.rejected:
        bgColor = AppColors.error.withValues(alpha: 0.1);
        textColor = AppColors.error;
        icon = Icons.cancel;
        statusText = '퇴사 요청 거절됨';
        detailText = app.resignRejectReason ?? '사유 없음';
        break;
      case AppStatus.approved:
      case AppStatus.autoApproved:
        bgColor = AppColors.success.withValues(alpha: 0.1);
        textColor = AppColors.success;
        icon = Icons.check_circle;
        statusText = app.resignStatus == AppStatus.autoApproved ? '퇴사 자동 승인됨' : '퇴사 승인됨';
        final resignDate = DateFormat('M월 d일').format(app.actualResignDate ?? DateTime.now());
        detailText = '$resignDate자로 퇴사 처리';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            icon, 
            color: textColor, 
            size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 변경
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                    context,
                    color: textColor,
                  ).copyWith(fontWeight: FontWeight.bold),
                ),
                ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                Text(
                  detailText,
                  style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                    context,
                    color: textColor.withValues(alpha: 0.8),
                  ),
                ),
              ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 정보 행
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(
          icon, 
          size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
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

  /// 퇴사 요청
  Future<void> _handleResignRequest(ApplicationModel app) async {
    // 퇴사 희망일 선택
    final resignDate = await DatePickerBottomSheet.show(
      context: context,
      title: '퇴사 희망일 선택',
      minDate: DateTime.now(),
      maxDate: app.workEndDate ?? DateTime.now().add(const Duration(days: 365)),
    );

    if (resignDate == null || !mounted) return;

    // 확인 다이얼로그
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '퇴사 요청',
      message:
          '${DateFormat('yyyy년 M월 d일').format(resignDate)}자로 퇴사 요청합니다.\n\n'
          '✓ 관리자가 3일 이내에 승인/거절합니다\n'
          '✓ 3일 후에도 처리가 없으면 자동 승인됩니다\n'
          '✓ 승인 전까지 요청을 취소할 수 있습니다\n\n'
          '요청하시겠습니까?',
      confirmText: '퇴사 요청',
      confirmColor: AppColors.error,
    );

    if (!confirmed || !mounted) return;

    try {
      final success = await _firestoreService.requestResignation(
        applicationId: app.id,
        resignDate: resignDate,
      );

      if (success && mounted) {
        ToastHelper.showSuccess('퇴사 요청이 완료되었습니다.');
        widget.onChanged();
      } else if (mounted) {
        ToastHelper.showError('퇴사 요청 중 오류가 발생했습니다.');
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.showError('퇴사 요청 중 오류가 발생했습니다.');
      }
    }
  }

  /// 퇴사 요청 취소
  Future<void> _handleCancelResignRequest(ApplicationModel app) async {
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '퇴사 요청 취소',
      message: '퇴사 요청을 취소하시겠습니까?',
      confirmText: '취소하기',
      confirmColor: AppColors.warning,
    );

    if (!confirmed || !mounted) return;

    try {
      final success = await _firestoreService.cancelResignRequest(app.id);

      if (success && mounted) {
        ToastHelper.showSuccess('퇴사 요청이 취소되었습니다.');
        widget.onChanged();
      } else if (mounted) {
        ToastHelper.showError('취소 중 오류가 발생했습니다.');
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.showError('취소 중 오류가 발생했습니다.');
      }
    }
  }
}