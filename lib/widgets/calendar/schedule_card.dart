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
import '../../screens/payroll/payslip_view_screen.dart';
import '../../models/core/schedule_change_request_model.dart';
import '../../theme/app_colors.dart';
import '../../models/core/insurance_rate_model.dart';
import '../common/tax_deduction_badge.dart';
import '../work_type_icon.dart';
import '../dialogs/business_review_dialog.dart';
import '../../models/core/review_request_model.dart';
import '../../services/monthly_review_service.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../common/app_menu_sheet.dart';

/// ✨ 개별 일정 카드 (세련된 디자인)
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
        border: (application.status == AppStatus.confirmed ||
                application.status == AppStatus.contractPending)
            ? Border.all(
                color: application.status == AppStatus.contractPending
                    ? Theme.of(context).primaryColor.withValues(alpha: 0.5)
                    : AppColors.success.withValues(alpha: 0.5),
                width: 1.5,
              )
            : null,
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
                // 첫 번째 줄: 사업장명 + 상태배지 + 더보기
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
                    // 더보기 버튼
                    _buildPopupMenu(context),
                  ],
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                
                // ═══════════════════════════════════════════════════
                // 두 번째 줄: 근무시간 · 업무유형 · 급여
                // ═══════════════════════════════════════════════════
                Row(
                  children: [
                    // 근무시간
                    Icon(
                      Icons.access_time,
                      size: ResponsiveHelper.iconSize(context, 14),
                      color: AppColors.grey500,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    Flexible(
                      child: Text(
                        '${application.startTime}~${application.endTime}',
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 12)),
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

  /// ✅ 더보기 팝업 메뉴
  Widget _buildPopupMenu(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.more_vert,
        size: ResponsiveHelper.iconSize(context, 22),
        color: AppColors.grey600,
      ),
      padding: EdgeInsets.zero,
      tooltip: '메뉴',
      onPressed: () => _showMenuSheet(context),
    );
  }

  Future<void> _showMenuSheet(BuildContext context) async {
    // 장기 확정 지원건만 대기 요청 체크 (취소 메뉴에 request 객체 필요하므로 직접 조회)
    ScheduleChangeRequestModel? pendingRequest;
    if (selectedDay != null &&
        application.isLongTermApplication &&
        (application.status == AppStatus.confirmed ||
         application.status == AppStatus.contractPending)) {
      pendingRequest = await _getPendingRequest(selectedDay!);
    }
    final hasPendingRequest = pendingRequest != null;

    if (!context.mounted) return;

    // [BUG-수정] M-5: 대기 요청이 있을 때 전체 메뉴를 차단하던 문제 수정.
    // hasPendingRequest=true면 cancelItem만 null로 두고 메뉴는 열리게 하되,
    // headerSubtitle로 '처리 대기중인 요청이 있습니다' 안내를 표시.
    final primaryColor = Theme.of(context).primaryColor;
    final isWageConfirmed = attendance?.isWageConfirmed == true || attendance?.isWageTransferred == true;
    final hasCheckedIn = attendance?.checkIn != null;
    final isNoShow = attendance?.status == 'NO_SHOW';
    final hasWorked = hasCheckedIn || isWageConfirmed;

    // 이미 이 달에 해당 사업장 리뷰를 작성했는지 확인
    bool hasReviewedThisMonth = false;
    if (hasWorked) {
      try {
        final workDate = application.workDate;
        hasReviewedThisMonth = await MonthlyReviewService().hasWorkerReviewThisMonth(
          businessId: application.businessId,
          reviewerId: application.uid,
          year: workDate.year,
          month: workDate.month,
        );
      } catch (e) {
        debugPrint('❌ 리뷰 여부 확인 오류: $e');
        // hasReviewedThisMonth = false 유지 → 리뷰 버튼 표시
      }
      if (!context.mounted) return;
    }

    // [BUG-수정] M-5: 취소 항목 결정 — hasPendingRequest=true이면 cancelItem을 null로 두어
    // 파괴적 액션(취소/휴무 요청)만 제거하고, 상세보기 등 비파괴 액션은 그대로 열린다.
    AppMenuSheetItem? cancelItem;
    if (!isWageConfirmed && !isNoShow && !hasCheckedIn && !hasPendingRequest) {
      final isLeaveDay = selectedDay != null &&
          application.isLongTermApplication &&
          application.isLeaveDateOn(selectedDay!);
      final isExtraWorkDay = selectedDay != null &&
          application.isLongTermApplication &&
          application.isExtraWorkDateOn(selectedDay!);

      IconData menuIcon;
      String menuText;
      Color menuColor;

      if (isLeaveDay) {
        menuIcon = Icons.refresh;
        menuText = '휴무 취소';
        menuColor = AppColors.success;
      } else if (isExtraWorkDay) {
        menuIcon = Icons.remove_circle_outline;
        menuText = '근무 취소';
        menuColor = AppColors.warning;
      } else if (application.isLongTermApplication &&
          (application.status == AppStatus.confirmed ||
           application.status == AppStatus.contractPending)) {
        menuIcon = Icons.beach_access;
        menuText = '휴무 요청';
        menuColor = AppColors.error;
      } else if (application.status == AppStatus.confirmed ||
          application.status == AppStatus.contractPending) {
        menuIcon = Icons.cancel_outlined;
        menuText = '확정 취소';
        menuColor = AppColors.error;
      } else {
        menuIcon = Icons.cancel_outlined;
        menuText = '지원 취소';
        menuColor = AppColors.error;
      }

      cancelItem = AppMenuSheetItem(
        icon: menuIcon,
        label: menuText,
        color: menuColor,
        isDanger: true,
        onTap: () => _handleMenuAction(context, 'cancel'),
      );
    }

    // [FAIL-SCR-01] 대기중인 요청 취소 항목 — hasPendingRequest일 때 표시
    AppMenuSheetItem? pendingCancelItem;
    if (pendingRequest != null) {
      final req = pendingRequest;
      pendingCancelItem = AppMenuSheetItem(
        icon: Icons.undo,
        label: '요청 취소',
        color: AppColors.error,
        isDanger: true,
        onTap: () => _cancelPendingRequest(context, req),
      );
    }

    AppMenuSheet.show(
      context: context,
      // [BUG-수정] M-5: 대기 요청이 있으면 headerSubtitle로 안내 표시 (메뉴 자체는 열림)
      headerSubtitle: hasPendingRequest ? '처리 대기중인 요청이 있습니다' : null,
      itemGroups: [
        [
          AppMenuSheetItem(
            icon: Icons.info_outline,
            label: '상세 정보',
            color: AppColors.info,
            onTap: () => _handleMenuAction(context, 'detail'),
          ),
          if (isWageConfirmed && attendance?.wageDetail != null) ...[
            AppMenuSheetItem(
              icon: Icons.receipt_long,
              label: '급여 명세서',
              color: AppColors.success,
              onTap: () => _handleMenuAction(context, 'wage_detail'),
            ),
            AppMenuSheetItem(
              icon: Icons.picture_as_pdf_outlined,
              label: '임금명세서 PDF',
              color: AppColors.infoDark,
              onTap: () => _handleMenuAction(context, 'payslip_pdf'),
            ),
          ],
          if (hasWorked && !hasReviewedThisMonth)
            AppMenuSheetItem(
              icon: Icons.rate_review,
              label: '사업장 리뷰',
              color: primaryColor,
              onTap: () => _handleMenuAction(context, 'write_review'),
            ),
        ],
        if (pendingCancelItem != null) [pendingCancelItem],
        if (cancelItem != null) [cancelItem],
      ],
    );
  }

  /// [FAIL-SCR-01] 대기중인 요청 취소
  Future<void> _cancelPendingRequest(
    BuildContext context,
    ScheduleChangeRequestModel request,
  ) async {
    final success = await FirestoreService().cancelScheduleChangeRequest(
      requestId: request.id,
    );
    if (!context.mounted) return;
    if (success) {
      ToastHelper.showSuccess('요청이 취소되었습니다');
      onChanged?.call();
    } else {
      ToastHelper.showError('요청 취소에 실패했습니다');
    }
  }

  /// ✅ 메뉴 액션 처리
  void _handleMenuAction(BuildContext context, String action) {
    switch (action) {
      case 'detail':
        _showDetailDialog(context);
        break;
      case 'wage_detail':
        _showWageDetailDialog(context);
        break;
      case 'payslip_pdf':
        _openPayslipPdf(context);
        break;
      case 'write_review':
          _showBusinessReviewDialog(context);
          break;
      case 'cancel':
        _handleCancel(context);
        break;
    }
  }

  /// 임금명세서 PDF 화면으로 직접 이동
  Future<void> _openPayslipPdf(BuildContext context) async {
    if (attendance?.wageDetail == null) {
      ToastHelper.showWarning('급여 정보가 없습니다');
      return;
    }
    final firestoreService = FirestoreService();
    final user = await firestoreService.getUser(application.uid);
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PayslipViewScreen(
          attendance: attendance!,
          worker: user,
          workerNameOverride: user?.name ?? '근무자',
        ),
      ),
    );
  }

  /// ✅ 급여 명세서 다이얼로그
  Future<void> _showWageDetailDialog(BuildContext context) async {
    if (attendance == null || attendance!.wageDetail == null) {
      ToastHelper.showWarning('급여 정보가 없습니다');
      return;
    }
    
    // 사용자 정보 조회
    final firestoreService = FirestoreService();
    final user = await firestoreService.getUser(application.uid);
    
    // 사업장 이름 조회
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
  
  /// 상세 정보 다이얼로그
  void _showDetailDialog(BuildContext context) {
    DialogHelper.showSheet(
      context,
      isScrollControlled: true,
      builder: (context) => ScheduleDetailDialog(application: application),
    );
  }
  
  /// 지원 취소 처리
  // [오탐 확인] StatelessWidget이지만 BuildContext.mounted는 async gap 후 위젯 트리 마운트 여부를 올바르게 반환함.
  Future<void> _handleCancel(BuildContext context) async {
    final firestoreService = FirestoreService();
    
    // ⭐ 휴무일 취소
    if (selectedDay != null && 
        application.isLongTermApplication && 
        application.isLeaveDateOn(selectedDay!)) {
      await _cancelLeaveDay(context);
      return;
    }
    
    // ⭐ 추가근무일 취소
    if (selectedDay != null && 
        application.isLongTermApplication && 
        application.isExtraWorkDateOn(selectedDay!)) {
      await _cancelExtraWorkDay(context);
      return;
    }
    
    // ⭐ 장기 근무 확정/계약대기 → 휴무 요청
    if (application.isLongTermApplication &&
        (application.status == AppStatus.confirmed ||
         application.status == AppStatus.contractPending)) {
      await _showLeaveRequestDialog(context);
      return;
    }

    // 단기 근무 확정/계약대기 → 취소 요청
    if (application.status == AppStatus.confirmed ||
        application.status == AppStatus.contractPending) {
      final confirmed = await _showConfirmedCancelDialog(context);

      if (confirmed != true) return;

      // [BUG-수정] H-1: cancelApplication은 CONFIRMED/CONTRACT_PENDING 상태를 내부에서 차단해
      // success=false를 반환했음. 확정 취소는 cancelConfirmedApplication을 사용해야 함.
      // 근무자 자기 취소이므로 applyNoShowPenalty: false, canceledBy: null.
      try {
        final success = await firestoreService.cancelConfirmedApplication(
          application.id,
          applyNoShowPenalty: false,
        );
        if (success && context.mounted) {
          ToastHelper.showSuccess('근무가 취소되었습니다.');
          onChanged?.call();
        } else if (!success && context.mounted) {
          ToastHelper.showError('취소 처리에 실패했습니다.');
        }
      } catch (e) {
        debugPrint('❌ 확정 취소 오류: $e');
        if (context.mounted) ToastHelper.showError('취소 처리 중 오류가 발생했습니다.');
      }
    } else if (application.status == AppStatus.pending) {
      // ⭐ 대기중인 경우 - 간단한 확인 후 취소
      final confirmed = await DialogHelper.showCancelConfirm(
        context,
        title: '지원 취소',
        message: '정말 지원을 취소하시겠습니까?',
      );

      if (!confirmed) return;

      try {
        final success = await firestoreService.cancelApplication(
          application.id,
          application.uid,
        );
        if (success && context.mounted) {
          ToastHelper.showSuccess('지원이 취소되었습니다.');
          onChanged?.call();
        } else if (!success && context.mounted) {
          ToastHelper.showError('취소 처리에 실패했습니다.');
        }
      } catch (e) {
        debugPrint('❌ 지원 취소 오류: $e');
        if (context.mounted) ToastHelper.showError('취소 처리 중 오류가 발생했습니다.');
      }
    }
  }
  /// 사업장 리뷰 다이얼로그
  Future<void> _showBusinessReviewDialog(BuildContext context) async {
    final workDate = application.workDate;
    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser;

    if (currentUser == null) return;

    // review_requests 조회 → requestId 연동 (없으면 null)
    final requestKey = ReviewRequestModel.generateKey(
      businessId: application.businessId,
      workerId: application.uid,
      year: workDate.year,
      month: workDate.month,
    );
    final reviewRequest =
        await MonthlyReviewService().getReviewRequest(requestKey);
    if (!context.mounted) return;

    final List<AttendanceModel> attendances =
        await FirestoreService().getMyMonthlyAttendances(
      userId: application.uid,
      year: workDate.year,
      month: workDate.month,
    );
    final workDaysInMonth = attendances
        .where((a) =>
            a.businessId == application.businessId &&
            (a.isWageConfirmed || a.isWageTransferred))
        .length;

    if (!context.mounted) return;

    final result = await showBusinessReviewDialog(
      context,
      reviewerId: application.uid,
      businessId: application.businessId,
      businessName: application.businessName,
      reviewYear: workDate.year,
      reviewMonth: workDate.month,
      workDaysInMonth: workDaysInMonth,
      requestId: reviewRequest?.id,
    );
    
    if (result == true) {
      onChanged?.call();
    }
  }

  /// ✅ 확정 취소 다이얼로그
  Future<bool?> _showConfirmedCancelDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded, 
              color: AppColors.warning, 
              size: ResponsiveHelper.iconSize(context, 28),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '확정 근무 취소',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '확정된 근무를 취소하시겠습니까?',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.error_outline, 
                        color: AppColors.error, 
                        size: ResponsiveHelper.iconSize(context, 20),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                      Text(
                        '⚠️ 주의사항',
                        style: ResponsiveHelper.bodyStyle(context, color: AppColors.error).copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    '• 확정 취소 시 패널티가 부과될 수 있습니다.\n'
                    '• 반복적인 취소는 향후 지원에 불이익이 있을 수 있습니다.\n'
                    '• 부득이한 사유가 있는 경우 관리자에게 먼저 연락해주세요.',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.error).copyWith(
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text(
              '그래도 취소하시겠습니까?',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '돌아가기',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '취소하기',
              style: ResponsiveHelper.bodyStyle(context, color: Colors.white),
            ),
          ),
        ],
      ),
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
          text: '대기중',
          icon: Icons.schedule,
        );
      case AppStatus.contractPending:
        return _StatusInfo(
          color: AppColors.info,
          text: '계약 대기',
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

  /// ⭐ 휴무 요청 다이얼로그 (장기 근무용)
  Future<void> _showLeaveRequestDialog(BuildContext context) async {
    if (selectedDay == null) {
      ToastHelper.showWarning('날짜 정보를 찾을 수 없습니다');
      return;
    }

    // [BUG-수정] M-6: 과거 날짜에 휴무 신청이 가능하던 문제 수정.
    // 오늘 날짜 기준으로 이전 날짜는 휴무 신청 불가.
    final today = DateTime.now();
    final isBeforeToday = selectedDay!.isBefore(DateTime(today.year, today.month, today.day));
    if (isBeforeToday) {
      ToastHelper.showWarning('과거 날짜에는 휴무를 신청할 수 없습니다.');
      return;
    }

    final reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.beach_access, color: AppColors.warning),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '휴무 요청',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              FormatHelper.formatDateLong(selectedDay!),
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              '${application.toTitle} - ${application.selectedWorkType}',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
            ),
            Divider(height: ResponsiveHelper.spacing(context, 24)),
            Text(
              '휴무 사유',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                hintText: '휴무 사유를 입력하세요',
                hintStyle: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () { FocusManager.instance.primaryFocus?.unfocus(); Navigator.pop(context, false); },
            child: Text(
              '취소',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
            ),
          ),
          ElevatedButton(
            onPressed: () { FocusManager.instance.primaryFocus?.unfocus(); Navigator.pop(context, true); },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '요청',
              style: ResponsiveHelper.bodyStyle(context, color: Colors.white),
            ),
          ),
        ],
      ),
    );

    final reason = reasonController.text.trim().isEmpty ? null : reasonController.text.trim();
    reasonController.dispose();

    if (confirmed != true) return;

    // 휴무 요청 생성
    final firestoreService = FirestoreService();

    final request = ScheduleChangeRequestModel(
      id: '',
      businessId: application.businessId,
      applicationId: application.id,
      applicantUid: application.uid,
      // [BUG-수정] L-3: applicantName이 빈 문자열로 알림 발송되던 문제 수정.
      // ApplicationModel에 이름 필드가 없어 uid로 대체 (알림 수신자 식별 가능).
      applicantName: application.uid,
      targetDate: DateTime(selectedDay!.year, selectedDay!.month, selectedDay!.day),
      requestType: RequestType.LEAVE,
      requestedBy: RequesterType.APPLICANT,
      requestedByUid: application.uid,
      requestedAt: DateTime.now(),
      reason: reason,
      wageAmount: application.wage,
    );

    try {
      final requestId = await firestoreService.createScheduleChangeRequest(request);
      if (requestId != null && context.mounted) {
        ToastHelper.showSuccess('휴무 요청이 전송되었습니다');
        onChanged?.call();
      } else if (context.mounted) {
        ToastHelper.showError('휴무 요청 실패');
      }
    } catch (e) {
      debugPrint('❌ 휴무 요청 오류: $e');
      if (context.mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ToastHelper.showError(
          (e is Exception && msg.isNotEmpty && !msg.startsWith('Exception'))
              ? msg
              : '휴무 요청 중 오류가 발생했습니다.',
        );
      }
    }
  }

  /// ⭐ 추가근무일 취소 요청 (관리자 승인 필요)
  // [오탐 확인] BuildContext.mounted는 StatelessWidget에서도 유효.
  Future<void> _cancelExtraWorkDay(BuildContext context) async {
    final reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.remove_circle_outline, color: AppColors.warning),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '추가근무 취소 요청',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              FormatHelper.formatDateLong(selectedDay!),
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              '추가 근무를 취소하시겠습니까?',
              style: ResponsiveHelper.bodyStyle(context),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline, 
                    color: AppColors.info, 
                    size: ResponsiveHelper.iconSize(context, 20),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      '관리자 승인 후 추가 근무가 취소됩니다.',
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.info),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '취소 사유',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                hintText: '취소 사유를 입력하세요',
                hintStyle: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () { FocusManager.instance.primaryFocus?.unfocus(); Navigator.pop(context, false); },
            child: Text(
              '취소',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
            ),
          ),
          ElevatedButton(
            onPressed: () { FocusManager.instance.primaryFocus?.unfocus(); Navigator.pop(context, true); },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '요청',
              style: ResponsiveHelper.bodyStyle(context, color: Colors.white),
            ),
          ),
        ],
      ),
    );

    final reason2 = reasonController.text.trim().isEmpty ? null : reasonController.text.trim();
    reasonController.dispose();

    if (confirmed != true) return;

    // 추가근무 취소 요청 생성
    final firestoreService = FirestoreService();

    final request = ScheduleChangeRequestModel(
      id: '',
      businessId: application.businessId,
      applicationId: application.id,
      applicantUid: application.uid,
      // [BUG-수정] L-3: applicantName이 빈 문자열로 알림 발송되던 문제 수정.
      applicantName: application.uid,
      targetDate: DateTime(selectedDay!.year, selectedDay!.month, selectedDay!.day),
      requestType: RequestType.CANCEL_EXTRA,
      requestedBy: RequesterType.APPLICANT,
      requestedByUid: application.uid,
      requestedAt: DateTime.now(),
      reason: reason2,
      wageAmount: application.wage,
    );

    try {
      final requestId = await firestoreService.createScheduleChangeRequest(request);
      if (requestId != null && context.mounted) {
        ToastHelper.showSuccess('추가근무 취소 요청이 전송되었습니다');
        onChanged?.call();
      } else if (context.mounted) {
        ToastHelper.showError('요청 실패');
      }
    } catch (e) {
      debugPrint('❌ 추가근무 취소 요청 오류: $e');
      if (context.mounted) ToastHelper.showError('추가근무 취소 요청 중 오류가 발생했습니다.');
    }
  }

  /// ⭐ 휴무일 취소 요청 (관리자 승인 필요)
  // [오탐 확인] BuildContext.mounted는 StatelessWidget에서도 유효.
  Future<void> _cancelLeaveDay(BuildContext context) async {
    final reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.refresh, color: AppColors.success),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '휴무 취소 요청',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              FormatHelper.formatDateLong(selectedDay!),
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              '휴무를 취소하고 출근하시겠습니까?',
              style: ResponsiveHelper.bodyStyle(context),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline, 
                    color: AppColors.info, 
                    size: ResponsiveHelper.iconSize(context, 20),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      '관리자 승인 후 정상 출근으로 변경됩니다.',
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.info),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '취소 사유',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                hintText: '출근 가능한 사유를 입력하세요',
                hintStyle: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () { FocusManager.instance.primaryFocus?.unfocus(); Navigator.pop(context, false); },
            child: Text(
              '취소',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
            ),
          ),
          ElevatedButton(
            onPressed: () { FocusManager.instance.primaryFocus?.unfocus(); Navigator.pop(context, true); },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '요청',
              style: ResponsiveHelper.bodyStyle(context, color: Colors.white),
            ),
          ),
        ],
      ),
    );

    final reason3 = reasonController.text.trim().isEmpty ? null : reasonController.text.trim();
    reasonController.dispose();

    if (confirmed != true) return;

    // 휴무 취소 요청 생성
    final firestoreService = FirestoreService();

    final request = ScheduleChangeRequestModel(
      id: '',
      businessId: application.businessId,
      applicationId: application.id,
      applicantUid: application.uid,
      // [BUG-수정] L-3: applicantName이 빈 문자열로 알림 발송되던 문제 수정.
      applicantName: application.uid,
      targetDate: DateTime(selectedDay!.year, selectedDay!.month, selectedDay!.day),
      requestType: RequestType.CANCEL_LEAVE,
      requestedBy: RequesterType.APPLICANT,
      requestedByUid: application.uid,
      requestedAt: DateTime.now(),
      reason: reason3,
      wageAmount: application.wage,
    );

    try {
      final requestId = await firestoreService.createScheduleChangeRequest(request);
      if (requestId != null && context.mounted) {
        ToastHelper.showSuccess('휴무 취소 요청이 전송되었습니다');
        onChanged?.call();
      } else if (context.mounted) {
        ToastHelper.showError('요청 실패');
      }
    } catch (e) {
      debugPrint('❌ 휴무 취소 요청 오류: $e');
      if (context.mounted) ToastHelper.showError('휴무 취소 요청 중 오류가 발생했습니다.');
    }
  }

  /// ⭐ 해당 날짜의 대기중인 요청 가져오기
  Future<ScheduleChangeRequestModel?> _getPendingRequest(DateTime date) async {
    final firestoreService = FirestoreService();
    
    try {
      final requests = await firestoreService.getMyScheduleChangeRequests(application.uid);
      
      for (final r in requests) {
        if (r.isPending &&
            r.applicationId == application.id &&
            r.targetDate.year == date.year &&
            r.targetDate.month == date.month &&
            r.targetDate.day == date.day &&
            r.isApplicantRequest) {
          return r;
        }
      }
      return null;
    } catch (e) {
      return null;
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
        text: attendance!.isWageTransferred ? '송금완료' : '정산완료',
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
        text: '근무완료',
        color: AppColors.purple,
        icon: Icons.task_alt,
      );
    }
    
    // 7. 출근만 완료
    if (attendance!.checkIn != null) {
      return _StatusInfo(
        text: '근무중',
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
