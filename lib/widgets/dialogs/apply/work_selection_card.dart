// lib/widgets/dialogs/apply/work_selection_card.dart

import 'package:flutter/material.dart';
import '../../../../models/core/work_detail_model.dart';
import '../../../../services/schedule_conflict_service.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../utils/format_helper.dart';
import '../../../../theme/app_colors.dart';
import '../../work_type_icon.dart';

/// 업무 지원 상태
enum WorkApplicationStatus {
  /// 미지원 - 지원 가능
  notApplied,
  
  /// 지원 완료 (PENDING)
  pending,
  
  /// 확정됨 (CONFIRMED)
  confirmed,
  
  /// 마감됨
  closed,
}

/// 업무 선택 카드
/// 
/// 지원 다이얼로그에서 각 업무를 표시하고 상태에 따른 버튼을 제공
class WorkSelectionCard extends StatelessWidget {
  /// 업무 상세 정보
  final WorkDetailModel workDetail;
  
  /// 현재 지원 상태
  final WorkApplicationStatus status;
  
  /// 시간 충돌 정보
  final ConflictInfo conflictInfo;
  
  /// 지원하기 콜백
  final VoidCallback? onApply;
  
  /// 지원취소 콜백
  final VoidCallback? onCancelApplication;
  
  /// 확정취소 콜백
  final VoidCallback? onCancelConfirm;
  
  /// 로딩 상태
  final bool isLoading;

  const WorkSelectionCard({
    super.key,
    required this.workDetail,
    required this.status,
    this.conflictInfo = const ConflictInfo(level: ConflictLevel.ok),
    this.onApply,
    this.onCancelApplication,
    this.onCancelConfirm,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 선택 가능 여부 결정
    final bool canInteract = _canInteract();
    
    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.spacing(context, 12),
        ),
        border: Border.all(
          color: _getBorderColor(theme),
          width: 1.5,
        ),
      ),
      child: Opacity(
        opacity: canInteract ? 1.0 : 0.6,
        child: Padding(
          padding: ResponsiveHelper.cardPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단: 업무 정보 + 상태 뱃지
              _buildHeader(context, theme),
              
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              
              // 중단: 시간 + 급여 + 인원
              _buildDetails(context, theme),
              
              // 충돌 경고 메시지
              if (conflictInfo.hasConflict)
                _buildConflictMessage(context),
              
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              
              // 하단: 액션 버튼
              _buildActionButton(context, theme),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 상단: 업무 정보 + 상태 뱃지
  // ═══════════════════════════════════════════════════════════

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        // 업무 아이콘
        WorkTypeIcon.buildWithBackground(
          iconString: workDetail.workTypeIcon,
          iconColor: workDetail.workTypeColor,
          backgroundColor: workDetail.workTypeBackgroundColor,
          size: ResponsiveHelper.spacing(context, 20),
          containerSize: ResponsiveHelper.spacing(context, 36),
        ),
        
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        
        // 업무명
        Expanded(
          child: Text(
            workDetail.workType,
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        
        // 상태 뱃지
        _buildStatusBadge(context),
      ],
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    String text;
    Color bgColor;
    Color textColor;

    // 충돌이 BLOCKED면 최우선
    if (conflictInfo.level == ConflictLevel.blocked) {
      text = '시간 충돌';
      bgColor = AppColors.errorBg;
      textColor = AppColors.errorDark;
    } else {
      switch (status) {
        case WorkApplicationStatus.confirmed:
          text = '확정';
          bgColor = AppColors.successBg;
          textColor = AppColors.successDark;
          break;
        case WorkApplicationStatus.pending:
          text = '지원완료';
          bgColor = AppColors.infoBg;
          textColor = AppColors.infoDark;
          break;
        case WorkApplicationStatus.closed:
          text = '마감';
          bgColor = AppColors.grey200;
          textColor = AppColors.grey600;
          break;
        case WorkApplicationStatus.notApplied:
          // 마감 여부 체크
          if (workDetail.isFull) {
            text = '마감';
            bgColor = AppColors.grey200;
            textColor = AppColors.grey600;
          } else {
            return const SizedBox.shrink(); // 미지원은 뱃지 없음
          }
          break;
      }
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.spacing(context, 8),
        ),
      ),
      child: Text(
        text,
        style: ResponsiveHelper.smallStyle(context, color: textColor).copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 중단: 시간 + 급여 + 인원
  // ═══════════════════════════════════════════════════════════

  Widget _buildDetails(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        // 시간
        _buildDetailItem(
          context,
          icon: Icons.access_time,
          text: workDetail.timeRange,
        ),
        
        SizedBox(width: ResponsiveHelper.spacing(context, 16)),
        
        // 급여
        _buildDetailItem(
          context,
          icon: Icons.payments_outlined,
          text: '${FormatHelper.formatNumber(workDetail.wage)}원/${workDetail.wageTypeLabel}',
        ),
        
        SizedBox(width: ResponsiveHelper.spacing(context, 16)),
        
        // 인원
        _buildDetailItem(
          context,
          icon: Icons.people_outline,
          text: workDetail.countInfo,
          highlight: workDetail.isFull,
        ),
      ],
    );
  }

  Widget _buildDetailItem(
    BuildContext context, {
    required IconData icon,
    required String text,
    bool highlight = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: ResponsiveHelper.iconSize(context, 16),
          color: highlight ? AppColors.errorDark : AppColors.grey500,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text(
          text,
          style: ResponsiveHelper.smallStyle(
            context,
            color: highlight ? AppColors.errorDark : AppColors.grey600,
          ).copyWith(
            fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 충돌 경고 메시지
  // ═══════════════════════════════════════════════════════════

  Widget _buildConflictMessage(BuildContext context) {
    final isBlocked = conflictInfo.level == ConflictLevel.blocked;
    
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        color: isBlocked ? AppColors.errorBg : AppColors.warningBg,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.spacing(context, 8),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isBlocked ? Icons.block : Icons.warning_amber_rounded,
            size: ResponsiveHelper.iconSize(context, 18),
            color: isBlocked ? AppColors.errorDark : AppColors.warningDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              conflictInfo.message ?? '',
              style: ResponsiveHelper.smallStyle(
                context,
                color: isBlocked ? AppColors.errorDark : AppColors.warningDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 하단: 액션 버튼
  // ═══════════════════════════════════════════════════════════

  Widget _buildActionButton(BuildContext context, ThemeData theme) {
    // 로딩 중
    if (isLoading) {
      return SizedBox(
        height: ResponsiveHelper.spacing(context, 36),
        child: Center(
          child: SizedBox(
            width: ResponsiveHelper.spacing(context, 20),
            height: ResponsiveHelper.spacing(context, 20),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.primaryColor,
            ),
          ),
        ),
      );
    }

    // BLOCKED면 선택 불가 표시
    if (conflictInfo.level == ConflictLevel.blocked) {
      return _buildDisabledButton(context, '선택 불가');
    }

    // 상태별 버튼
    switch (status) {
      case WorkApplicationStatus.notApplied:
        // 마감 체크
        if (workDetail.isFull || workDetail.isClosed) {
          return _buildDisabledButton(context, '마감');
        }
        return _buildApplyButton(context, theme);
        
      case WorkApplicationStatus.pending:
        return _buildCancelApplicationButton(context);
        
      case WorkApplicationStatus.confirmed:
        return _buildCancelConfirmButton(context);
        
      case WorkApplicationStatus.closed:
        return _buildDisabledButton(context, '마감');
    }
  }

  /// 지원하기 버튼 (초록)
  Widget _buildApplyButton(BuildContext context, ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      height: ResponsiveHelper.spacing(context, 40),
      child: ElevatedButton.icon(
        onPressed: onApply,
        icon: Icon(
          Icons.check_circle_outline,
          size: ResponsiveHelper.iconSize(context, 18),
        ),
        label: Text(
          '지원하기',
          style: ResponsiveHelper.bodyStyle(context, color: Colors.white).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.success,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              ResponsiveHelper.spacing(context, 10),
            ),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  /// 지원취소 버튼 (회색 아웃라인)
  Widget _buildCancelApplicationButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: ResponsiveHelper.spacing(context, 40),
      child: OutlinedButton.icon(
        onPressed: onCancelApplication,
        icon: Icon(
          Icons.cancel_outlined,
          size: ResponsiveHelper.iconSize(context, 18),
        ),
        label: Text(
          '지원취소',
          style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.grey600,
          side: BorderSide(color: AppColors.grey400),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              ResponsiveHelper.spacing(context, 10),
            ),
          ),
        ),
      ),
    );
  }

  /// 확정취소 버튼 (빨강)
  Widget _buildCancelConfirmButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: ResponsiveHelper.spacing(context, 40),
      child: OutlinedButton.icon(
        onPressed: onCancelConfirm,
        icon: Icon(
          Icons.warning_amber_rounded,
          size: ResponsiveHelper.iconSize(context, 18),
        ),
        label: Text(
          '확정취소',
          style: ResponsiveHelper.bodyStyle(context, color: AppColors.error).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: BorderSide(color: AppColors.error),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              ResponsiveHelper.spacing(context, 10),
            ),
          ),
        ),
      ),
    );
  }

  /// 비활성 버튼
  Widget _buildDisabledButton(BuildContext context, String text) {
    return SizedBox(
      width: double.infinity,
      height: ResponsiveHelper.spacing(context, 40),
      child: ElevatedButton(
        onPressed: null,
        child: Text(
          text,
          style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.grey200,
          foregroundColor: AppColors.grey500,
          disabledBackgroundColor: AppColors.grey200,
          disabledForegroundColor: AppColors.grey500,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              ResponsiveHelper.spacing(context, 10),
            ),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 헬퍼 메서드
  // ═══════════════════════════════════════════════════════════

  bool _canInteract() {
    // BLOCKED면 불가
    if (conflictInfo.level == ConflictLevel.blocked) return false;
    
    // 마감이면 불가
    if (status == WorkApplicationStatus.closed) return false;
    if (workDetail.isFull && status == WorkApplicationStatus.notApplied) return false;
    
    return true;
  }

  Color _getBackgroundColor() {
    if (conflictInfo.level == ConflictLevel.blocked) {
      return AppColors.grey100;
    }
    
    switch (status) {
      case WorkApplicationStatus.confirmed:
        return AppColors.successBg.withOpacity(0.3);
      case WorkApplicationStatus.pending:
        return AppColors.infoBg.withOpacity(0.3);
      case WorkApplicationStatus.closed:
        return AppColors.grey100;
      case WorkApplicationStatus.notApplied:
        return Colors.white;
    }
  }

  Color _getBorderColor(ThemeData theme) {
    if (conflictInfo.level == ConflictLevel.blocked) {
      return AppColors.grey300;
    }
    
    switch (status) {
      case WorkApplicationStatus.confirmed:
        return AppColors.success.withOpacity(0.5);
      case WorkApplicationStatus.pending:
        return AppColors.info.withOpacity(0.5);
      case WorkApplicationStatus.closed:
        return AppColors.grey300;
      case WorkApplicationStatus.notApplied:
        return AppColors.grey300;
    }
  }
}