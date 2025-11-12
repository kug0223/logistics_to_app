import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/core/application_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';

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
    // 확정된 장기 근무만 필터링
    final longTermWorks = widget.applications
        .where((app) =>
            app.isLongTermApplication && app.status == 'CONFIRMED')
        .toList();

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[700],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.work, color: Colors.white),
                  const SizedBox(width: 12),
                  const Text(
                    '고정근무 관리',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
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
                      padding: const EdgeInsets.all(16),
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
          Icon(Icons.work_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '확정된 고정근무가 없습니다',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// 근무 카드
  Widget _buildWorkCard(ApplicationModel app) {
    final hasResignRequest = app.resignStatus != null;
    final isPending = app.resignStatus == 'PENDING';
    final isRejected = app.resignStatus == 'REJECTED';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 사업장명
            Row(
              children: [
                Icon(Icons.business, size: 18, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    app.businessName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 근무 기간
            _buildInfoRow(
              Icons.calendar_today,
              '근무 기간',
              app.workPeriodDisplay,
            ),
            const SizedBox(height: 8),

            // 근무 요일
            if (app.workDaysDisplay != null)
              _buildInfoRow(
                Icons.event_repeat,
                '근무 요일',
                app.workDaysDisplay!,
              ),
            const SizedBox(height: 8),

            // 근무 시간
            _buildInfoRow(
              Icons.access_time,
              '근무 시간',
              '${app.startTime} ~ ${app.endTime}',
            ),
            const SizedBox(height: 8),

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
              const SizedBox(height: 16),
              _buildResignStatusBanner(app),
            ],

            const SizedBox(height: 16),

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
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
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
                    backgroundColor: Colors.red,
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
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
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
      case 'PENDING':
        bgColor = Colors.orange[50]!;
        textColor = Colors.orange[900]!;
        icon = Icons.schedule;
        statusText = '퇴사 승인 대기중';
        final requestDate = DateFormat('M월 d일').format(app.resignRequestDate!);
        final daysLeft = 3 - DateTime.now().difference(app.resignRequestedAt!).inDays;
        detailText = '$requestDate 퇴사 요청 (${daysLeft}일 후 자동 승인)';
        break;
      case 'REJECTED':
        bgColor = Colors.red[50]!;
        textColor = Colors.red[900]!;
        icon = Icons.cancel;
        statusText = '퇴사 요청 거절됨';
        detailText = app.resignRejectReason ?? '사유 없음';
        break;
      case 'APPROVED':
      case 'AUTO_APPROVED':
        bgColor = Colors.green[50]!;
        textColor = Colors.green[900]!;
        icon = Icons.check_circle;
        statusText = app.resignStatus == 'AUTO_APPROVED' ? '퇴사 자동 승인됨' : '퇴사 승인됨';
        final resignDate = DateFormat('M월 d일').format(app.actualResignDate!);
        detailText = '$resignDate자로 퇴사 처리';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                if (detailText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    detailText,
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor.withOpacity(0.8),
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
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
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
    final resignDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: app.workEndDate ?? DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ko', 'KR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue[700]!,
            ),
          ),
          child: child!,
        );
      },
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
      confirmColor: Colors.red,
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
        setState(() {});
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
      confirmColor: Colors.orange,
    );

    if (!confirmed || !mounted) return;

    try {
      final success = await _firestoreService.cancelResignRequest(app.id);

      if (success && mounted) {
        ToastHelper.showSuccess('퇴사 요청이 취소되었습니다.');
        widget.onChanged();
        setState(() {});
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