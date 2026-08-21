// lib/widgets/dialogs/apply/apply_confirm_dialog.dart

import 'package:flutter/material.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../theme/app_colors.dart';
import '../styled_dialog.dart';

/// 지원 확인 바텀시트
///
/// 단기/장기 공통 확인 시트. 장기는 희망 시작일을 상단에 강조 표시.
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
    final result = await DialogHelper.showSheet<bool>(
      context,
      isScrollControlled: true,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 헤더
        _buildHeader(context),
        // 내용 (스크롤 가능)
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 16),
              0,
              ResponsiveHelper.spacing(context, 16),
              ResponsiveHelper.spacing(context, 8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 장기: 희망 시작일 강조 카드
                if (isLongTerm && desiredStartDate != null)
                  _buildStartDateHighlight(context),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                // 상세 정보 카드
                _buildInfoCard(context),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                // 안내 메시지
                if (isLongTerm)
                  StyledDialogInfoCard.info(
                    '희망 시작일부터 계약 종료일까지 일괄 지원됩니다.\n첫 근무 전까지는 확정취소 가능, 근무 시작 후에는 퇴사 요청을 통해 퇴사 가능합니다.',
                  )
                else
                  StyledDialogInfoCard.info(
                    '지원 후 관리자 승인을 기다려주세요.\n확정 전까지는 자유롭게 취소 가능합니다.',
                  ),
                // [DOCUMENT-CONSENT] 서류 접근 사전동의 안내 (V3: 신분증+급여계좌+통장사본)
                // [LEGAL-REVIEW-ID-CONSENT] 동의 문구 및 방식의 법적 적절성은 별도 법무 검토 필요
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                StyledDialogInfoCard.warning(
                  '지원하기를 누르면 [$businessName]의 권한 있는 관리자가 '
                  '근무 확정 시 소득신고·급여처리 목적으로 등록된 서류에 접근할 수 있음에 동의합니다.\n'
                  '· 신분증: 확정일로부터 7일간\n'
                  '· 급여계좌·통장사본: 급여처리 관계가 유효한 동안',
                ),
              ],
            ),
          ),
        ),
        // 하단 버튼
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 16),
              ResponsiveHelper.spacing(context, 8),
              ResponsiveHelper.spacing(context, 16),
              ResponsiveHelper.spacing(context, 16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        vertical: ResponsiveHelper.spacing(context, 14),
                      ),
                      side: BorderSide(color: AppColors.grey300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      '취소',
                      style: ResponsiveHelper.bodyStyle(context,
                          color: AppColors.grey600, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.infoDark,
                      padding: EdgeInsets.symmetric(
                        vertical: ResponsiveHelper.spacing(context, 14),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      '지원하기',
                      style: ResponsiveHelper.bodyStyle(context,
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── 헤더 ─────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 16),
      ),
      decoration: BoxDecoration(
        color: AppColors.infoDark,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.assignment_outlined,
            size: ResponsiveHelper.iconSize(context, 22),
            color: Colors.white,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '지원 확인',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '아래 내용으로 지원하시겠습니까?',
                  style: ResponsiveHelper.smallStyle(context,
                      color: Colors.white.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.close, color: Colors.white),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ─── 장기 희망 시작일 강조 ─────────────────────────────

  Widget _buildStartDateHighlight(BuildContext context) {
    if (desiredStartDate == null) return const SizedBox.shrink();
    final startStr = FormatHelper.formatDate(desiredStartDate!);
    final endStr = endDate != null ? FormatHelper.formatDate(endDate!) : '';
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_month_outlined,
            size: ResponsiveHelper.iconSize(context, 28),
            color: AppColors.infoDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '희망 시작일',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.infoDark, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  startStr,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    color: AppColors.infoDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (endStr.isNotEmpty)
                  Text(
                    '~ $endStr',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.infoDark),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 상세 정보 카드 ────────────────────────────────────

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
          if (!isLongTerm)
            _buildInfoRow(
              context,
              Icons.calendar_today,
              '근무일',
              _getDateDisplay(),
            ),
          if (isLongTerm && workDays != null && workDays!.isNotEmpty) ...[
            _buildInfoRow(
              context,
              Icons.repeat,
              '근무 요일',
              '매주 ${workDays!.join(", ")}',
            ),
            _buildDivider(),
          ],
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.grey500),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Text(label, style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600)),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Text(
              value,
              style: ResponsiveHelper.bodyStyle(context, color: valueColor ?? AppColors.grey800).copyWith(
                fontWeight: valueBold ? FontWeight.bold : FontWeight.w500,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() => Divider(height: 1, color: AppColors.grey200);

  String _getDateDisplay() {
    if (workDate == null) return '날짜 정보 없음';
    return FormatHelper.formatDate(workDate!);
  }

  String _getWageDisplay() {
    final wageStr = FormatHelper.formatWage(work.wage);
    final typeStr = work.wageType == 'hourly' ? '시급' : work.wageType == 'daily' ? '일급' : '월급';
    return '$wageStr/$typeStr';
  }
}
