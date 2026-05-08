import 'package:flutter/material.dart';

// Models
import '../../../models/core/work_detail_model.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';

// Services
import '../../../services/firestore_service.dart';

// Providers

// Utils
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';

// Theme
import '../../../theme/app_colors.dart';

// Widgets
import '../../work_type_icon.dart';

// Dialogs
import '../../../screens/business_admin/dialogs/work_applicants_dialog.dart';

/// ✨ 업무 상세 행 위젯 (간소화된 디자인)
/// 
/// 개선 사항:
/// - 좌측 컬러 인디케이터
/// - 정보 간소화 (업무명 + 시간 + 인원)
/// - 상태별 색상 적용
class WorkDetailRow extends StatefulWidget {
  final WorkDetailModel work;
  final int confirmedCount;
  final int pendingCount;
  final TOItem toItem;
  final FirestoreService firestoreService;
  final VoidCallback onChanged;
  final VoidCallback? onLocalStatsChanged;
  final void Function(Set<String> affectedTOIds)? onAffectedTOsChanged;  // 🔥 추가

  const WorkDetailRow({
    super.key,
    required this.work,
    required this.confirmedCount,
    required this.pendingCount,
    required this.toItem,
    required this.firestoreService,
    required this.onChanged,
    this.onLocalStatsChanged,
    this.onAffectedTOsChanged,  // 🔥 추가
  });

  @override
  State<WorkDetailRow> createState() => _WorkDetailRowState();
}

class _WorkDetailRowState extends State<WorkDetailRow> {
  
  // ✅ workDetailId로 조회
  int get _confirmedCount {
    final stats = widget.toItem.workDetailStats?[widget.work.id];
    return stats?['confirmed'] ?? widget.confirmedCount;
  }
  
  int get _pendingCount {
    final stats = widget.toItem.workDetailStats?[widget.work.id];
    return stats?['pending'] ?? widget.pendingCount;
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFull = _confirmedCount >= widget.work.requiredCount;
    // work.isFull은 항상 false(모델에 통계 없음) → 로컬 isFull 사용
    final isClosed = widget.toItem.slot?.isManualClosed == true ||
        widget.work.isClosed || widget.work.isTimeExpired || isFull;
    final isEmergency = widget.work.isEmergencyOpen;

    Color statusColor;
    if (isClosed) {
      statusColor = AppColors.grey400;
    } else if (isEmergency) {
      statusColor = AppColors.error;
    } else if (isFull) {
      statusColor = AppColors.success;
    } else {
      statusColor = widget.toItem.to.isLongTerm ? AppColors.longTerm : AppColors.shortTerm;
    }

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 좌측 상태 인디케이터
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),

            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showApplicantsDialog(context),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.grey200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildWorkIcon(context),
                        SizedBox(width: ResponsiveHelper.spacing(context, 12)),

                        // 업무 정보 (3줄 압축)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 1줄: 업무명 + 상태배지 (단기만)
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.work.workType,
                                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: isClosed ? AppColors.grey500 : AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (!widget.toItem.to.isLongTerm) ...[
                                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                    _buildWorkStatusBadge(context, isClosed: isClosed),
                                  ],
                                ],
                              ),
                              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                              // 2줄: 근무시간 + 마감시간 — Wrap으로 좁은 화면에서 자동 줄바꿈
                              Wrap(
                                spacing: ResponsiveHelper.spacing(context, 8),
                                runSpacing: ResponsiveHelper.spacing(context, 2),
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: ResponsiveHelper.iconSize(context, 12),
                                        color: AppColors.grey400,
                                      ),
                                      SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                                      Text(
                                        '${widget.work.startTime} ~ ${widget.work.endTime}',
                                        style: ResponsiveHelper.smallStyle(
                                          context,
                                          color: AppColors.grey600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (!widget.toItem.to.isLongTerm)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.timer_off_outlined,
                                          size: ResponsiveHelper.iconSize(context, 12),
                                          color: isClosed ? AppColors.grey400 : AppColors.warningDark,
                                        ),
                                        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                                        Text(
                                          '마감 ${widget.work.applicationDeadline != null ? FormatHelper.formatTime(widget.work.applicationDeadline!) : widget.work.startTime}',
                                          style: ResponsiveHelper.smallStyle(
                                            context,
                                            color: isClosed ? AppColors.grey400 : AppColors.warningDark,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                              // 3줄: 급여
                              Row(
                                children: [
                                  Icon(
                                    Icons.paid,
                                    size: ResponsiveHelper.iconSize(context, 12),
                                    color: isClosed ? AppColors.grey400 : AppColors.successDark,
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                  Text(
                                    '${FormatHelper.formatWage(widget.work.wage)} / ${widget.work.wageTypeLabel}',
                                    style: ResponsiveHelper.smallStyle(
                                      context,
                                      color: isClosed ? AppColors.grey400 : AppColors.successDark,
                                    ).copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        // 오른쪽: 인원 + 지원자버튼
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildPersonnelStatus(context, isFull, isClosed, statusColor),
                            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                            _buildApplicantButton(context, theme),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 업무 아이콘
  Widget _buildWorkIcon(BuildContext context) {
    return Container(
      width: ResponsiveHelper.iconSize(context, 36),
      height: ResponsiveHelper.iconSize(context, 36),
      decoration: BoxDecoration(
        color: FormatHelper.parseColor(widget.work.workTypeBackgroundColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: WorkTypeIcon.buildFromString(
          widget.work.workTypeIcon,
          color: FormatHelper.parseColor(widget.work.workTypeColor),
          size: ResponsiveHelper.iconSize(context, 18),
        ),
      ),
    );
  }

  /// 인원 현황 (항상 표시 + 상태별 색상)
  Widget _buildPersonnelStatus(
    BuildContext context,
    bool isFull,
    bool isClosed,
    Color statusColor,
  ) {
    // 상태별 색상: 마감=회색, 충족=초록, 진행중=파랑
    Color displayColor;
    if (isClosed) {
      displayColor = AppColors.grey500;
    } else if (isFull) {
      displayColor = AppColors.successDark;
    } else {
      displayColor = AppColors.infoDark;
    }
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isFull ? Icons.check_circle : Icons.people_outline,
          size: ResponsiveHelper.iconSize(context, 14),
          color: displayColor,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text(
          '$_confirmedCount/${widget.work.requiredCount}',
          style: ResponsiveHelper.bodyStyle(
            context,
            color: displayColor,
          ).copyWith(fontWeight: FontWeight.bold),
        ),
        if (_pendingCount > 0) ...[
          Text(
            ' +$_pendingCount',
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.warningDark,
            ),
          ),
        ],
      ],
    );
  }

  /// 지원자 보기 버튼
  Widget _buildApplicantButton(BuildContext context, ThemeData theme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showApplicantsDialog(context),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          decoration: BoxDecoration(
            color: theme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.people,
            size: ResponsiveHelper.iconSize(context, 18),
            color: theme.primaryColor,
          ),
        ),
      ),
    );
  }
  /// ✨ 업무 상태 배지 (마감/예약/모집중)
  Widget _buildWorkStatusBadge(BuildContext context, {required bool isClosed}) {
    final to = widget.toItem.to;
    
    // 1. 마감됨
    if (isClosed) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 6),
          vertical: ResponsiveHelper.spacing(context, 2),
        ),
        decoration: BoxDecoration(
          color: AppColors.grey200,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '마감됨',
          style: ResponsiveHelper.tinyStyle(
            context,
            color: AppColors.grey600,
          ),
        ),
      );
    }
    
    // 2. 예약 공개 대기
    if (to.isPendingPublish) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 6),
          vertical: ResponsiveHelper.spacing(context, 2),
        ),
        decoration: BoxDecoration(
          color: AppColors.scheduledBg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '예약',
          style: ResponsiveHelper.tinyStyle(
            context,
            color: AppColors.scheduledDark,
          ),
        ),
      );
    }
    
    // 3. 모집중
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '모집중',
        style: ResponsiveHelper.tinyStyle(
          context,
          color: AppColors.successDark,
        ),
      ),
    );
  }

  /// 지원자 다이얼로그 표시
  Future<void> _showApplicantsDialog(BuildContext context) async {
    final result = await showDialog<WorkApplicantsDialogResult>(
      context: context,
      builder: (context) => WorkApplicantsDialog(
        toItem: widget.toItem,
        work: widget.work,
        onChanged: widget.onChanged,
      ),
    );
    
    // ⭐ 다이얼로그 닫힌 후 로컬 업데이트 반영
    if (result != null && result.hasChanges && mounted) {
      setState(() {});  // 자기 자신 rebuild
      widget.onLocalStatsChanged?.call();  // 부모 TOGroupCard rebuild
      
      // 🔥 충돌로 영향받은 다른 TO가 있으면 상위에 알림
      if (result.affectedTOIds.isNotEmpty) {
        widget.onAffectedTOsChanged?.call(result.affectedTOIds);
      }
    }
  }
}