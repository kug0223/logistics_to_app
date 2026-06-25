import 'package:flutter/material.dart';

// Models
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/insurance_rate_model.dart';
import '../../../models/core/to_model.dart';
import '../../common/tax_deduction_badge.dart';
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
  
  String get _netWorkTimeStr => FormatHelper.calcNetWorkTime(
        widget.work.startTime,
        widget.work.endTime,
        breakMinutes: widget.work.breakMinutes,
      );

  /// 저장된 마감 시각 — 데이터 초기화 후 항상 존재
  DateTime? get _effectiveDeadline => widget.work.applicationDeadline;

  // 급여 색상 — 일급: 주황, 시급: 초록
  Color _wageColor(bool isClosed) {
    if (isClosed) return AppColors.grey400;
    return widget.work.wageType == 'daily'
        ? AppColors.warningDark
        : AppColors.successDark;
  }

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
    final slotDate = widget.toItem.slot?.date;
    final isClosed = (widget.toItem.slot?.isEffectivelyClosed ?? false) ||
        (slotDate != null
            ? widget.work.isEffectivelyClosed(slotDate)
            : widget.work.isClosed || widget.work.isTimeExpired) ||
        isFull;
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildWorkIcon(context),
                        SizedBox(width: ResponsiveHelper.spacing(context, 12)),

                        // 업무 정보 — Expanded로 가용 너비 최대화
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 업무명 — 전체 너비 사용
                              Text(
                                widget.work.workType,
                                style: ResponsiveHelper.bodyStyle(context).copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isClosed ? AppColors.grey500 : AppColors.textPrimary,
                                ),
                              ),
                              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                              // 근무시간 — Flexible로 긴 텍스트 overflow 방지
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: ResponsiveHelper.iconSize(context, 12),
                                    color: AppColors.grey400,
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                                  Flexible(
                                    child: Text.rich(
                                      TextSpan(children: [
                                        TextSpan(
                                          text: '${widget.work.startTime} ~ ${widget.work.endTime}',
                                          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                                        ),
                                        if (_netWorkTimeStr.isNotEmpty)
                                          TextSpan(
                                            text: '  ($_netWorkTimeStr)',
                                            style: ResponsiveHelper.tinyStyle(context).copyWith(
                                              color: AppColors.grey500,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                      ]),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              // 마감시간 + 상태배지 (단기만)
                              if (!widget.toItem.to.isLongTerm) ...[
                                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                                Wrap(
                                  spacing: ResponsiveHelper.spacing(context, 6),
                                  runSpacing: ResponsiveHelper.spacing(context, 4),
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (_effectiveDeadline != null)
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
                                            '마감 ${FormatHelper.formatTime(_effectiveDeadline!)}',
                                            style: ResponsiveHelper.smallStyle(
                                              context,
                                              color: isClosed ? AppColors.grey400 : AppColors.warningDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    _buildWorkStatusBadge(context, isClosed: isClosed),
                                  ],
                                ),
                              ],
                              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                              // 급여 + 정산 주기
                              Wrap(
                                spacing: ResponsiveHelper.spacing(context, 6),
                                runSpacing: ResponsiveHelper.spacing(context, 2),
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.paid,
                                        size: ResponsiveHelper.iconSize(context, 12),
                                        color: _wageColor(isClosed),
                                      ),
                                      SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                      Text(
                                        '${widget.work.wageTypeLabel} ${FormatHelper.formatWage(widget.work.wage)}',
                                        style: ResponsiveHelper.smallStyle(
                                          context,
                                          color: _wageColor(isClosed),
                                        ).copyWith(fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  if (widget.work.payScheduleTypeLabel.isNotEmpty)
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: ResponsiveHelper.spacing(context, 6),
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _wageColor(isClosed).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        widget.work.payScheduleTypeLabel,
                                        style: ResponsiveHelper.tinyStyle(
                                          context,
                                          color: _wageColor(isClosed),
                                        ).copyWith(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                ],
                              ),
                              // 입금일 상세 (주급/월급일 때만)
                              if (widget.work.payScheduleDetail.isNotEmpty) ...[
                                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.account_balance_wallet_outlined,
                                      size: ResponsiveHelper.iconSize(context, 12),
                                      color: AppColors.grey500,
                                    ),
                                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                    Flexible(
                                      child: Text(
                                        '${widget.work.payScheduleDetail} 입금',
                                        style: ResponsiveHelper.smallStyle(
                                          context,
                                          color: AppColors.grey600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (widget.work.taxDeductionType != InsuranceRateModel.typeNone) ...[
                                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                                TaxDeductionBadge.row(
                                  taxDeductionType: widget.work.taxDeductionType,
                                ),
                              ],
                              // 인원현황 — 텍스트 영역 안 마지막 줄로 이동
                              SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                              _buildPersonnelStatus(context, isFull, isClosed, statusColor),
                            ],
                          ),
                        ),

                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        // 오른쪽: 지원자 버튼만 (인원현황은 텍스트 영역으로 이동)
                        _buildApplicantButton(context, theme),
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
          color: AppColors.grey100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock,
              size: ResponsiveHelper.iconSize(context, 9),
              color: AppColors.grey600,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 3)),
            Text(
              '마감',
              style: ResponsiveHelper.tinyStyle(
                context,
                color: AppColors.grey600,
              ),
            ),
          ],
        ),
      );
    }
    
    // 2. 예약 — TO 상태가 SCHEDULED이거나 isPendingPublish인 경우
    // [특이사항] status='SCHEDULED'는 isPendingPublish와 별개 경로 — 둘 다 체크해야 예약 배지가 표시됨
    if (to.status == TOStatus.scheduled || to.isPendingPublish) {
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
      widget.onChanged();  // 그룹 카드 헤더 통계 갱신 (전체 reload)

      // 🔥 충돌로 영향받은 다른 TO가 있으면 상위에 알림
      if (result.affectedTOIds.isNotEmpty) {
        widget.onAffectedTOsChanged?.call(result.affectedTOIds);
      }
    }
  }
}