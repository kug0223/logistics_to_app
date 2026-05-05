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
import '../../models/core/schedule_change_request_model.dart';
import '../../theme/app_colors.dart';
import 'package:intl/intl.dart';
import '../work_type_icon.dart';
import '../dialogs/business_review_dialog.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';

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
        border: application.status == 'CONFIRMED'
            ? Border.all(color: AppColors.success.withValues(alpha: 0.5), width: 1.5)
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
                    Text(
                      '${application.startTime}~${application.endTime}',
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
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
                    ),
                  ],
                ),
                
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
                        Text(
                          '${application.workDaysDisplay ?? ""} · ${application.workPeriodDisplay}',
                          style: ResponsiveHelper.tinyStyle(context, color: AppColors.purple),
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
            color: info.color[700],
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            info.text,
            style: ResponsiveHelper.tinyStyle(context, color: info.color[700]).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ 더보기 팝업 메뉴
  Widget _buildPopupMenu(BuildContext context) {
    return FutureBuilder<bool>(
      future: selectedDay != null && 
              application.isLongTermApplication && 
              application.status == 'CONFIRMED'
          ? _hasPendingRequest(selectedDay!)
          : Future.value(false),
      builder: (context, snapshot) {
        final hasPendingRequest = snapshot.data ?? false;
        
        return PopupMenuButton<String>(
          icon: Icon(
            Icons.more_vert,
            size: ResponsiveHelper.iconSize(context, 22),
            color: AppColors.grey600,
          ),
          padding: EdgeInsets.zero,
          tooltip: '메뉴',
          enabled: !hasPendingRequest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: (value) => _handleMenuAction(context, value),
          itemBuilder: (context) => _buildMenuItems(context, hasPendingRequest),
        );
      },
    );
  }

  /// ✅ 메뉴 아이템 빌드
  List<PopupMenuEntry<String>> _buildMenuItems(BuildContext context, bool hasPendingRequest) {
    final items = <PopupMenuEntry<String>>[];
    final iconSize = ResponsiveHelper.iconSize(context, 20);
    final spacing = ResponsiveHelper.spacing(context, 12);
    
    // 1. 상세 정보
    items.add(
      PopupMenuItem(
        value: 'detail',
        child: Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.info, size: iconSize),
            SizedBox(width: spacing),
            Text('상세 정보', style: ResponsiveHelper.bodyStyle(context)),
          ],
        ),
      ),
    );
    
    // 2. 급여 명세서 (정산완료 상태만)
    if (attendance?.wageStatus == 'confirmed' && attendance?.wageDetail != null) {
      items.add(
        PopupMenuItem(
          value: 'wage_detail',
          child: Row(
            children: [
              Icon(Icons.receipt_long, color: AppColors.success, size: iconSize),
              SizedBox(width: spacing),
              Text('급여 명세서', style: ResponsiveHelper.bodyStyle(context)),
            ],
          ),
        ),
      );
    }
    // 3. 사업장 리뷰 작성 (근무 완료 후)
    final hasWorked = attendance?.checkIn != null || 
                      attendance?.wageStatus == 'confirmed';
    if (hasWorked) {
      items.add(
        PopupMenuItem(
          value: 'write_review',
          child: Row(
            children: [
              Icon(Icons.rate_review, color: Theme.of(context).primaryColor, size: iconSize),
              SizedBox(width: spacing),
              Text('사업장 리뷰', style: ResponsiveHelper.bodyStyle(context)),
            ],
          ),
        ),
      );
    }
    
    // 3. 취소/휴무 관련 메뉴 (출근 이후는 취소 불가)
    final isWageConfirmed = attendance?.wageStatus == 'confirmed';
    final hasCheckedIn = attendance?.checkIn != null;
    final isNoShow = attendance?.status == 'NO_SHOW';
    
    // 정산완료가 아닐 때만 구분선 + 취소 메뉴 표시
    if (!isWageConfirmed) {
      // 구분선
      items.add(const PopupMenuDivider());
      
      if (isNoShow) {
        // 노쇼 처리된 건
        items.add(
          PopupMenuItem(
            enabled: false,
            child: Row(
              children: [
                Icon(Icons.cancel, color: AppColors.error.withValues(alpha: 0.5), size: iconSize),
                SizedBox(width: spacing),
                Text(
                  '노쇼 처리됨', 
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.error.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
        );
      } else if (hasCheckedIn) {
        // 출근 이후는 취소 불가 (급여 지급 대상)
        items.add(
          PopupMenuItem(
            enabled: false,
            child: Row(
              children: [
                Icon(Icons.block, color: AppColors.grey500, size: iconSize),
                SizedBox(width: spacing),
                Text(
                  '출근완료 (취소불가)', 
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
                ),
              ],
            ),
          ),
        );
      } else if (hasPendingRequest) {
        items.add(
          PopupMenuItem(
            enabled: false,
            child: Row(
              children: [
                Icon(Icons.schedule, color: AppColors.grey500, size: iconSize),
                SizedBox(width: spacing),
                Text(
                  '요청 대기중', 
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
                ),
              ],
            ),
          ),
        );
      } else {
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
        } else if (application.isLongTermApplication && application.status == 'CONFIRMED') {
          menuIcon = Icons.beach_access;
          menuText = '휴무 요청';
          menuColor = AppColors.error;
        } else if (application.status == 'CONFIRMED') {
          menuIcon = Icons.cancel_outlined;
          menuText = '확정 취소';
          menuColor = AppColors.error;
        } else {
          menuIcon = Icons.cancel_outlined;
          menuText = '지원 취소';
          menuColor = AppColors.error;
        }
        
        items.add(
          PopupMenuItem(
            value: 'cancel',
            child: Row(
              children: [
                Icon(menuIcon, color: menuColor, size: iconSize),
                SizedBox(width: spacing),
                Text(menuText, style: ResponsiveHelper.bodyStyle(context, color: menuColor)),
              ],
            ),
          ),
        );
      }
    }
    
    return items;
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
      case 'write_review':
          _showBusinessReviewDialog(context);
          break;
      case 'cancel':
        _handleCancel(context);
        break;
    }
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
    );
  }
  
  /// 상세 정보 다이얼로그
  void _showDetailDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => ScheduleDetailDialog(application: application),
    );
  }
  
  /// 지원 취소 처리
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
    
    // ⭐ 장기 근무 확정 → 휴무 요청
    if (application.isLongTermApplication && application.status == 'CONFIRMED') {
      await _showLeaveRequestDialog(context);
      return;
    }
      
    // 단기 근무 확정 → 취소 요청
    if (application.status == 'CONFIRMED') {
      final confirmed = await _showConfirmedCancelDialog(context);
      
      if (confirmed != true) return;
      
      // 확정 취소 처리
      final success = await firestoreService.cancelApplication(
        application.id,
        application.uid,
      );
      
      if (success && context.mounted) {
        ToastHelper.showSuccess('근무가 취소되었습니다.');
        onChanged?.call();
      }
      
    } else if (application.status == 'PENDING') {
      // ⭐ 대기중인 경우 - 간단한 확인 후 취소
      final confirmed = await DialogHelper.showCancelConfirm(
        context,
        title: '지원 취소',
        message: '정말 지원을 취소하시겠습니까?',
      );
      
      if (!confirmed) return;
      
      final success = await firestoreService.cancelApplication(
        application.id,
        application.uid,
      );
      
      if (success && context.mounted) {
        ToastHelper.showSuccess('지원이 취소되었습니다.');
        onChanged?.call();
      }
    }
  }
  /// 사업장 리뷰 다이얼로그
  void _showBusinessReviewDialog(BuildContext context) async {
    final workDate = application.workDate;
    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser;
    
    if (currentUser == null) return;
    
    final result = await showBusinessReviewDialog(
      context,
      reviewerId: application.uid,
      reviewerName: currentUser.name,
      businessId: application.businessId,
      businessName: application.businessName,
      reviewYear: workDate.year,
      reviewMonth: workDate.month,
      workDaysInMonth: 1, // TODO: 해당 월 실제 근무일수 계산
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
      case 'CONFIRMED':
        return _StatusInfo(
          color: Colors.green,
          text: '확정',
          icon: Icons.check_circle,
        );
      case 'PENDING':
        return _StatusInfo(
          color: Colors.orange,
          text: '대기중',
          icon: Icons.schedule,
        );
      case 'REJECTED':
        return _StatusInfo(
          color: Colors.red,
          text: '거절',
          icon: Icons.cancel,
        );
      case 'CANCELED':
        return _StatusInfo(
          color: Colors.grey,
          text: '취소',
          icon: Icons.remove_circle_outline,
        );
      case 'AUTO_CANCELED':
        return _StatusInfo(
          color: Colors.orange,
          text: '자동 취소',
          icon: Icons.block,
        );
      default:
        return _StatusInfo(
          color: Colors.grey,
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

    final reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
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
              DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(selectedDay!),
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
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '취소',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
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

    if (confirmed != true) return;

    // 휴무 요청 생성
    final firestoreService = FirestoreService();
    
    final request = ScheduleChangeRequestModel(
      id: '',
      businessId: application.businessId,
      applicationId: application.id,
      applicantUid: application.uid,
      applicantName: '',
      targetDate: DateTime(selectedDay!.year, selectedDay!.month, selectedDay!.day),
      requestType: RequestType.LEAVE,
      requestedBy: RequesterType.APPLICANT,
      requestedByUid: application.uid,
      requestedAt: DateTime.now(),
      reason: reasonController.text.trim().isEmpty 
          ? null 
          : reasonController.text.trim(),
      wageAmount: application.wage,
    );

    final requestId = await firestoreService.createScheduleChangeRequest(request);

    if (requestId != null && context.mounted) {
      ToastHelper.showSuccess('휴무 요청이 전송되었습니다');
      onChanged?.call();
    } else {
      ToastHelper.showError('휴무 요청 실패');
    }
  }

  /// ⭐ 추가근무일 취소 요청 (관리자 승인 필요)
  Future<void> _cancelExtraWorkDay(BuildContext context) async {
    final reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
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
              DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(selectedDay!),
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
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '취소',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
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

    if (confirmed != true) return;

    // 추가근무 취소 요청 생성
    final firestoreService = FirestoreService();
    
    final request = ScheduleChangeRequestModel(
      id: '',
      businessId: application.businessId,
      applicationId: application.id,
      applicantUid: application.uid,
      applicantName: '',
      targetDate: DateTime(selectedDay!.year, selectedDay!.month, selectedDay!.day),
      requestType: RequestType.CANCEL_EXTRA,
      requestedBy: RequesterType.APPLICANT,
      requestedByUid: application.uid,
      requestedAt: DateTime.now(),
      reason: reasonController.text.trim().isEmpty 
          ? null 
          : reasonController.text.trim(),
      wageAmount: application.wage,
    );

    final requestId = await firestoreService.createScheduleChangeRequest(request);

    if (requestId != null && context.mounted) {
      ToastHelper.showSuccess('추가근무 취소 요청이 전송되었습니다');
      onChanged?.call();
    } else {
      ToastHelper.showError('요청 실패');
    }
  }

  /// ⭐ 휴무일 취소 요청 (관리자 승인 필요)
  Future<void> _cancelLeaveDay(BuildContext context) async {
    final reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
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
              DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(selectedDay!),
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
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              '취소',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
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

    if (confirmed != true) return;

    // 휴무 취소 요청 생성
    final firestoreService = FirestoreService();
    
    final request = ScheduleChangeRequestModel(
      id: '',
      businessId: application.businessId,
      applicationId: application.id,
      applicantUid: application.uid,
      applicantName: '',
      targetDate: DateTime(selectedDay!.year, selectedDay!.month, selectedDay!.day),
      requestType: RequestType.CANCEL_LEAVE,
      requestedBy: RequesterType.APPLICANT,
      requestedByUid: application.uid,
      requestedAt: DateTime.now(),
      reason: reasonController.text.trim().isEmpty 
          ? null 
          : reasonController.text.trim(),
      wageAmount: application.wage,
    );

    final requestId = await firestoreService.createScheduleChangeRequest(request);

    if (requestId != null && context.mounted) {
      ToastHelper.showSuccess('휴무 취소 요청이 전송되었습니다');
      onChanged?.call();
    } else {
      ToastHelper.showError('요청 실패');
    }
  }

  /// ⭐ 해당 날짜에 대기중인 요청이 있는지 확인
  Future<bool> _hasPendingRequest(DateTime date) async {
    final request = await _getPendingRequest(date);
    return request != null;
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
    if (application.status != 'CONFIRMED') {
      return _getStatusInfo(application.status);
    }
    
    // 2. attendance 없으면 "확정"
    if (attendance == null) {
      return _StatusInfo(
        text: '확정',
        color: Colors.green,
        icon: Icons.check_circle,
      );
    }
    
    // 3. 노쇼 처리됨
    if (attendance!.status == 'NO_SHOW') {
      return _StatusInfo(
        text: '노쇼',
        color: Colors.red,
        icon: Icons.cancel,
      );
    }
    
    // 4. 급여 최종 확정
    if (attendance!.wageStatus == 'confirmed') {
      return _StatusInfo(
        text: '정산완료',
        color: Colors.blue,
        icon: Icons.verified,
      );
    }
    
    // 5. 급여 검토중
    if (attendance!.wageStatus == 'calculated') {
      return _StatusInfo(
        text: '검토중',
        color: Colors.orange,
        icon: Icons.hourglass_bottom,
      );
    }
    
    // 6. 퇴근 완료
    if (attendance!.checkOut != null) {
      return _StatusInfo(
        text: '근무완료',
        color: Colors.purple,
        icon: Icons.task_alt,
      );
    }
    
    // 7. 출근만 완료
    if (attendance!.checkIn != null) {
      return _StatusInfo(
        text: '근무중',
        color: Colors.teal,
        icon: Icons.work,
      );
    }
    
    // 8. 기본 - 확정
    return _StatusInfo(
      text: '확정',
      color: Colors.green,
      icon: Icons.check_circle,
    );
  }

  /// ✅ 급여 표시 (wageType 포함) - 모든 상태 통일
  String _getWageDisplay() {
    // 1. 정산완료면 확정 급여 + wageType 표시
    if (attendance?.wageStatus == 'confirmed' && attendance?.finalWage != null) {
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
  final MaterialColor color;
  final String text;
  final IconData icon;
  
  _StatusInfo({
    required this.color,
    required this.text,
    required this.icon,
  });
}
