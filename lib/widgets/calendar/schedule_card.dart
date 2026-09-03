import 'package:flutter/material.dart';
import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../utils/dialog_helper.dart';
import '../../services/firestore_service.dart';
import '../../utils/toast_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../dialogs/schedule_detail_dialog.dart';
import '../dialogs/wage/wage_detail_dialog.dart';
import '../../theme/app_colors.dart';
import '../../models/core/insurance_rate_model.dart';
import '../common/tax_deduction_badge.dart';
import '../work_type_icon.dart';

/// ✨ 개별 일정 카드 (세련된 디자인)
///
/// 탭 동작:
///   카드 전체 탭 → ScheduleDetailDialog (공고/일정 상세정보)
///   급여명세서 아이콘 탭 → WageDetailDialog (급여 확정 시만 표시)
class ScheduleCard extends StatelessWidget {
  final ApplicationModel application;
  final AttendanceModel? attendance;
  final VoidCallback? onChanged;
  final DateTime? selectedDay;

  const ScheduleCard({
    super.key,
    required this.application,
    this.attendance,
    this.onChanged,
    this.selectedDay,
  });

  @override
  Widget build(BuildContext context) {
    final statusInfo = _getDisplayStatus();
    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: const Color(0xFFE8E9ED)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDetailDialog(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ═══════════════════════════════════════════════════
                // 첫 번째 줄: 사업장명 + 상태배지 + 급여명세서 아이콘
                // ═══════════════════════════════════════════════════
                Row(
                  children: [
                    // 사업장 아이콘
                    Icon(
                      Icons.business,
                      size: ResponsiveHelper.iconSize(context, 16),
                      color: AppColors.grey600,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    // 사업장명
                    Expanded(
                      child: Text(
                        application.businessName,
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    // 상태 배지
                    _buildStatusBadgeCompact(context, statusInfo),
                    // 급여명세서 아이콘 버튼 (급여 확정 시만 표시)
                    _buildPayslipIconButton(context),
                  ],
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                // ═══════════════════════════════════════════════════
                // 두 번째 줄: 업무명
                // ═══════════════════════════════════════════════════
                Row(
                  children: [
                    // 업무유형 아이콘 (WorkTypeIcon 사용)
                    if (application.workTypeIcon != null)
                      WorkTypeIcon.buildWithBackground(
                        iconString: application.workTypeIcon!,
                        iconColor: application.workTypeColor,
                        backgroundColor: application.workTypeBackgroundColor,
                        size: 10,
                        containerSize: 18,
                      )
                    else
                      Container(
                        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 3)),
                        decoration: BoxDecoration(
                          color: AppColors.purple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          Icons.work,
                          size: ResponsiveHelper.iconSize(context, 12),
                          color: AppColors.purple,
                        ),
                      ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    Expanded(
                      child: Text(
                        application.selectedWorkType,
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 6)),

                // ═══════════════════════════════════════════════════
                // 세 번째 줄: 근무시간 · 급여
                // ═══════════════════════════════════════════════════
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: ResponsiveHelper.iconSize(context, 14),
                      color: AppColors.grey500,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    Expanded(
                      child: Text(
                        '${application.startTime}~${application.endTime}',
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    // 급여 (금액 + 타입)
                    Text(
                      _getWageDisplay(),
                      style: ResponsiveHelper.bodyStyle(context, color: AppColors.success).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),

                // ═══════════════════════════════════════════════════
                // 세금 공제 배지 (급여 계산 후에만 표시)
                // ═══════════════════════════════════════════════════
                if (attendance?.wageDetail?.taxDeductionType case final taxType?
                    when taxType != InsuranceRateModel.typeNone) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                  TaxDeductionBadge.row(taxDeductionType: taxType),
                ],

                // ═══════════════════════════════════════════════════
                // 장기 근무 정보 (있을 때만)
                // ═══════════════════════════════════════════════════
                if (application.isLongTermApplication) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 10),
                      vertical: ResponsiveHelper.spacing(context, 6),
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.star,
                          size: ResponsiveHelper.iconSize(context, 12),
                          color: AppColors.purple,
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                        Text(
                          '고정근무',
                          style: ResponsiveHelper.tinyStyle(context, color: AppColors.purple).copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Flexible(
                          child: Text(
                            '${application.workDaysDisplay ?? ""} · ${application.workPeriodDisplay}',
                            style: ResponsiveHelper.tinyStyle(context, color: AppColors.purple),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ✅ 상태 배지 (컴팩트)
  Widget _buildStatusBadgeCompact(BuildContext context, _StatusInfo info) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            info.icon,
            size: ResponsiveHelper.iconSize(context, 14),
            color: info.color,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            info.text,
            style: ResponsiveHelper.tinyStyle(context, color: info.color).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ 급여명세서 아이콘 버튼
  ///
  /// 노출 조건:
  ///   attendance.isWageConfirmed == true OR attendance.isWageTransferred == true
  ///   AND attendance.wageDetail != null
  ///
  /// 조건 미충족 시 SizedBox.shrink() 반환 — disabled 아이콘 표시하지 않음.
  ///
  /// 이벤트 격리:
  ///   IconButton은 내부적으로 InkWell을 사용하므로 제스처 아레나에서
  ///   부모 InkWell(카드 탭)보다 우선하여 onPressed만 실행된다.
  Widget _buildPayslipIconButton(BuildContext context) {
    final isWageConfirmed =
        attendance?.isWageConfirmed == true || attendance?.isWageTransferred == true;
    if (!isWageConfirmed || attendance?.wageDetail == null) {
      return const SizedBox.shrink();
    }
    return IconButton(
      icon: const Icon(Icons.receipt_long_outlined),
      iconSize: 20,
      color: AppColors.info,
      tooltip: '급여 명세서',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      onPressed: () => _showWageDetailDialog(context),
    );
  }

  /// ✅ 급여 명세서 다이얼로그 (중간 BottomSheet 없이 직접 진입)
  Future<void> _showWageDetailDialog(BuildContext context) async {
    if (attendance == null || attendance!.wageDetail == null) {
      ToastHelper.showWarning('급여 정보가 없습니다');
      return;
    }

    final firestoreService = FirestoreService();
    final user = await firestoreService.getUser(application.uid);
    final business = await firestoreService.getBusinessById(application.businessId);

    if (!context.mounted) return;

    await WageDetailDialog.show(
      context: context,
      app: application,
      user: user,
      attendance: attendance!,
      wage: attendance!.wageDetail!,
      mode: WageDialogMode.confirmed,
      businessName: business?.name,
      scheduledBreakMinutes: attendance!.wageDetail!.scheduledBreakMinutes,
    );
  }

  /// 상세 정보 다이얼로그 (카드 탭 진입점)
  void _showDetailDialog(BuildContext context) {
    DialogHelper.showSheet(
      context,
      isScrollControlled: true,
      useRootNavigator: true,  // BottomNav까지 dim — modal 계층 명확화
      builder: (context) => ScheduleDetailDialog(application: application),
    );
  }

  /// 상태 정보 가져오기
  _StatusInfo _getStatusInfo(String status) {
    switch (status) {
      case AppStatus.confirmed:
        return _StatusInfo(
          color: AppColors.success,
          text: '확정',
          icon: Icons.check_circle,
        );
      case AppStatus.pending:
        return _StatusInfo(
          color: AppColors.warning,
          text: '대기',
          icon: Icons.schedule,
        );
      case AppStatus.contractPending:
        return _StatusInfo(
          color: AppColors.info,
          text: '계약 진행 중',
          icon: Icons.assignment_outlined,
        );
      case AppStatus.rejected:
        return _StatusInfo(
          color: AppColors.error,
          text: '거절',
          icon: Icons.cancel,
        );
      case AppStatus.canceled:
        return _StatusInfo(
          color: AppColors.grey500,
          text: '취소',
          icon: Icons.remove_circle_outline,
        );
      case AppStatus.autoCanceled:
        return _StatusInfo(
          color: AppColors.warning,
          text: '자동 취소',
          icon: Icons.block,
        );
      default:
        return _StatusInfo(
          color: AppColors.grey500,
          text: '알 수 없음',
          icon: Icons.help_outline,
        );
    }
  }

  /// ✅ 출근 기록 기반 표시 상태 결정
  _StatusInfo _getDisplayStatus() {
    // 1. CONFIRMED가 아니면 기존 로직
    if (application.status != AppStatus.confirmed) {
      return _getStatusInfo(application.status);
    }

    // 2. attendance 없으면 "확정"
    if (attendance == null) {
      return _StatusInfo(
        text: '확정',
        color: AppColors.success,
        icon: Icons.check_circle,
      );
    }

    // 3. 노쇼 처리됨
    if (attendance!.status == 'NO_SHOW') {
      return _StatusInfo(
        text: '노쇼',
        color: AppColors.error,
        icon: Icons.cancel,
      );
    }

    // 4. 급여 최종 확정 (confirmed = 정산완료, transferred = 송금완료)
    if (attendance!.isWageConfirmed || attendance!.isWageTransferred) {
      return _StatusInfo(
        text: attendance!.isWageTransferred ? '송금 완료' : '정산 완료',
        color: AppColors.info,
        icon: Icons.verified,
      );
    }

    // 5. 급여 계산 완료 — 관리자 마감 대기
    if (attendance!.wageStatus == 'calculated') {
      return _StatusInfo(
        text: '정산 대기',
        color: AppColors.warning,
        icon: Icons.hourglass_bottom,
      );
    }

    // 6. 퇴근 완료
    if (attendance!.checkOut != null) {
      return _StatusInfo(
        text: '근무 완료',
        color: AppColors.purple,
        icon: Icons.task_alt,
      );
    }

    // 7. 출근만 완료
    if (attendance!.checkIn != null) {
      return _StatusInfo(
        text: '근무 중',
        color: AppColors.teal,
        icon: Icons.work,
      );
    }

    // 8. 기본 - 확정
    return _StatusInfo(
      text: '확정',
      color: AppColors.success,
      icon: Icons.check_circle,
    );
  }

  /// ✅ 급여 표시 (wageType 포함) - 모든 상태 통일
  String _getWageDisplay() {
    // 1. 정산완료/송금완료면 확정 급여 + wageType 표시
    if ((attendance?.isWageConfirmed == true || attendance?.isWageTransferred == true) &&
        attendance?.finalWage != null) {
      final wageTypeLabel = attendance!.wageDetail?.wageTypeLabel ?? '';
      return '${FormatHelper.formatWage(attendance!.finalWage!)}${wageTypeLabel.isNotEmpty ? ' ($wageTypeLabel)' : ''}';
    }

    // 2. 기본 - application의 wageType 우선 사용
    final wageTypeLabel = application.wageTypeLabel.isNotEmpty
        ? application.wageTypeLabel
        : (attendance?.wageDetail?.wageTypeLabel ?? '');
    final formattedWage = FormatHelper.formatWage(application.wage);

    return wageTypeLabel.isNotEmpty ? '$formattedWage ($wageTypeLabel)' : formattedWage;
  }
}

/// 상태 정보 클래스
class _StatusInfo {
  final Color color;
  final String text;
  final IconData icon;

  _StatusInfo({
    required this.color,
    required this.text,
    required this.icon,
  });
}
