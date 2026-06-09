// lib/widgets/dialogs/apply/apply_confirm_dialog.dart

import 'package:flutter/material.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../theme/app_colors.dart';
import '../styled_dialog.dart';

/// 지원 확인 다이얼로그
class ApplyConfirmDialog extends StatelessWidget {
  final String businessName;
  final WorkDetailModel work;
  final bool isLongTerm;
  final DateTime? workDate;
  final DateTime? desiredStartDate;
  final DateTime? endDate;
  final List<String>? workDays;

  const ApplyConfirmDialog({
    super.key,
    required this.businessName,
    required this.work,
    required this.isLongTerm,
    this.workDate,
    this.desiredStartDate,
    this.endDate,
    this.workDays,
  });

  static Future<bool> show({
    required BuildContext context,
    required String businessName,
    required WorkDetailModel work,
    required bool isLongTerm,
    DateTime? workDate,
    DateTime? desiredStartDate,
    DateTime? endDate,
    List<String>? workDays,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ApplyConfirmDialog(
        businessName: businessName,
        work: work,
        isLongTerm: isLongTerm,
        workDate: workDate,
        desiredStartDate: desiredStartDate,
        endDate: endDate,
        workDays: workDays,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return StyledDialog(
      title: '지원 확인',
      subtitle: '아래 내용으로 지원하시겠습니까?',
      icon: Icons.assignment_outlined,
      headerColor: isLongTerm ? AppColors.longTerm : theme.primaryColor,
      maxHeightRatio: 0.6,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildInfoCard(context),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          if (isLongTerm)
            StyledDialogInfoCard.info(
              '희망 시작일부터 계약 종료일까지 일괄 지원됩니다.\n첫 근무 전까지는 확정취소 가능, 근무 시작 후에는 퇴사 요청을 통해 퇴사 가능합니다.',
            )
          else
            StyledDialogInfoCard.info(
              '지원 후 관리자 승인을 기다려주세요.\n확정 전까지는 자유롭게 취소 가능합니다.',
            ),
        ],
      ),
      actions: [
        StyledDialogButton.cancel(
          onPressed: () => Navigator.pop(context, false),
        ),
        StyledDialogButton.primary(
          text: '지원하기',
          backgroundColor: isLongTerm ? AppColors.longTerm : null,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        children: [
          _buildInfoRow(context, Icons.business, '사업장', businessName),
          _buildDivider(),
          _buildInfoRow(
            context,
            Icons.calendar_today,
            isLongTerm ? '근무 기간' : '근무일',
            _getDateDisplay(),
            valueColor: isLongTerm ? AppColors.longTerm : null,
          ),
          if (isLongTerm && workDays != null && workDays!.isNotEmpty) ...[
            _buildDivider(),
            _buildInfoRow(context, Icons.repeat, '근무 요일', '매주 ${workDays!.join(", ")}'),
          ],
          _buildDivider(),
          _buildInfoRow(context, Icons.access_time, '근무 시간', '${work.startTime} ~ ${work.endTime}'),
          _buildDivider(),
          _buildInfoRow(context, Icons.work_outline, '업무', work.workType),
          _buildDivider(),
          _buildInfoRow(
            context,
            Icons.payments_outlined,
            '급여',
            _getWageDisplay(),
            valueColor: AppColors.success,
            valueBold: true,
          ),
          if (work.payScheduleLabel.isNotEmpty) ...[
            _buildDivider(),
            _buildInfoRow(
              context,
              Icons.account_balance_wallet_outlined,
              '지급 일정',
              work.payScheduleLabel,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
    bool valueBold = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,  // ✅ 여러 줄일 때 상단 정렬
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.grey500),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Text(label, style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600)),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ✅ Spacer 대신 고정 간격
          Expanded(  // ✅ Flexible → Expanded
            child: Text(
              value,
              style: ResponsiveHelper.bodyStyle(context, color: valueColor ?? AppColors.grey800).copyWith(
                fontWeight: valueBold ? FontWeight.bold : FontWeight.w500,
              ),
              textAlign: TextAlign.end,
              // ✅ overflow 제거 → 줄바꿈 허용
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() => Divider(height: 1, color: AppColors.grey200);

  String _getDateDisplay() {
    if (isLongTerm) {
      if (desiredStartDate == null || endDate == null) return '날짜 미선택';
      return '${FormatHelper.formatDate(desiredStartDate!)} ~ ${FormatHelper.formatDate(endDate!)}';
    }
    if (workDate == null) return '날짜 정보 없음';
    return FormatHelper.formatDate(workDate!);
  }

  String _getWageDisplay() {
    final wageStr = FormatHelper.formatWage(work.wage);
    final typeStr = work.wageType == 'hourly' ? '시급' : work.wageType == 'daily' ? '일급' : '월급';
    return '$wageStr/$typeStr';
  }
}