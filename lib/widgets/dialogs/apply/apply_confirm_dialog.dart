// lib/widgets/dialogs/apply/apply_confirm_dialog.dart

import 'package:flutter/material.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/business_model.dart' show AttendanceRules;
import '../../../utils/attendance_policy_disclosure.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../theme/app_colors.dart';
import '../styled_dialog.dart';
import 'document_access_consent.dart';

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

  /// [R7-PAYROLL-POLICY.4C] 지원 시 고정될 근태·급여 기준. 읽지 못했으면 null.
  final AttendanceRules? policyRules;

  /// 기준을 **읽어 봤는가**. 읽기 실패와 "기준 없는 사업장"을 구별한다.
  final bool policyLoaded;

  const ApplyConfirmDialog({
    super.key,
    required this.businessName,
    required this.work,
    required this.isLongTerm,
    this.workDate,
    this.desiredStartDate,
    this.endDate,
    this.workDays,
    this.policyRules,
    this.policyLoaded = false,
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
    AttendanceRules? policyRules,
    bool policyLoaded = false,
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
        policyRules: policyRules,
        policyLoaded: policyLoaded,
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
                // [R7-PAYROLL-POLICY.4C] `.4` 는 "공고 상세에서 보라"고만 했다.
                //   그런데 이 시트는 공고 상세를 거치지 않는 경로(카드 →
                //   지원)에서도 열리고, 지원하는 순간 그 기준이 지원서에
                //   고정된다 — 보지 못한 조건으로 약속의 씨앗이 생긴다.
                //   그래서 **여기서 7항목을 보여준다.** 값은 전달받은 것만
                //   쓴다(이 위젯이 사업장 문서를 읽지 않는다).
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _policyCard(context),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                DocumentAccessConsent.card(businessName),
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

  /// [R7-PAYROLL-POLICY.4C] 지원하면 이 지원서에 고정되는 근태·급여 기준.
  ///
  ///   항목·문구는 `.4B` 의 공용 formatter 에서 온다 — 초대 수락·계약서와
  ///   같은 목록이다. 읽지 못했으면(`policyRules == null` + 미로딩) 그 사실을
  ///   말한다. 사업장 현재 설정으로 메우지 않는다.
  Widget _policyCard(BuildContext context) {
    final r = policyRules;
    if (r == null) {
      // [R7-PAYROLL-POLICY.4D] 세 상태를 섞지 않는다.
      //   · 읽지 못했다(ERROR)  → 다시 시도
      //   · 기준이 없다(ABSENT) → 사업장이 준비해야 한다(지원 불가)
      //   ERROR 를 "기준 없음" 으로 위조하지 않는다.
      return StyledDialogInfoCard.info(policyLoaded
          ? kAttendancePolicyUnavailableNote
          : kAttendancePolicyLoadFailedNote);
    }
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kAttendancePolicyTitle,
              style: ResponsiveHelper.smallStyle(context)
                  .copyWith(fontWeight: FontWeight.bold)),
          for (final g in attendancePolicyGroups(r)) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(g.title,
                style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.grey600)
                    .copyWith(fontWeight: FontWeight.w600)),
            for (final line in g.lines)
              Padding(
                padding: EdgeInsets.only(
                    top: ResponsiveHelper.spacing(context, 2)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: ResponsiveHelper.spacing(context, 80),
                      child: Text(line.label,
                          style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.grey700)),
                    ),
                    Expanded(
                      child: Text(line.value,
                          style: ResponsiveHelper.smallStyle(context)
                              .copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
          ],
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            '지원하면 이 기준이 이 지원서에 고정됩니다. '
            '사업장이 이후에 기준을 바꿔도 적용되지 않습니다.',
            style:
                ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
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
