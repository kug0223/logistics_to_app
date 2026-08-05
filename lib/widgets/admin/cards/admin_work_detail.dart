import 'package:flutter/material.dart';

// Models
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/to_model.dart';
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
  DateTime _buildNow = DateTime.now();

  @override
  void didUpdateWidget(WorkDetailRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.work != widget.work) _buildNow = DateTime.now();
  }

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

    final wageColor = _wageColor(isClosed);
    final totalApplicants = _confirmedCount + _pendingCount;
    final missing = (widget.work.requiredCount - _confirmedCount).clamp(0, widget.work.requiredCount);

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showApplicantsDialog(context),
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(
                  3 + ResponsiveHelper.spacing(context, 12),
                  ResponsiveHelper.spacing(context, 12),
                  ResponsiveHelper.spacing(context, 12),
                  ResponsiveHelper.spacing(context, 12),
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.grey200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                // ① 업무명(소형아이콘 포함) + 지원자 칩
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: FormatHelper.parseColor(widget.work.workTypeBackgroundColor),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: WorkTypeIcon.buildFromString(
                          widget.work.workTypeIcon,
                          color: FormatHelper.parseColor(widget.work.workTypeColor),
                          size: 11,
                        ),
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    Expanded(
                      child: Text(
                        widget.work.workType,
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          fontWeight: FontWeight.w600,
                          color: isClosed ? AppColors.grey500 : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (totalApplicants > 0) ...[
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people, size: 11, color: theme.primaryColor),
                            const SizedBox(width: 3),
                            Text(
                              '지원자 $totalApplicants',
                              style: ResponsiveHelper.tinyStyle(context,
                                      color: theme.primaryColor)
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                // ② 데이터 바
                SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                _buildProgressBar(isClosed),
                SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                // ③ 시간 + 임금 (한 줄)
                Row(
                  children: [
                    Icon(Icons.access_time,
                        size: ResponsiveHelper.iconSize(context, 12),
                        color: AppColors.grey400),
                    SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                    Flexible(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: '${widget.work.startTime} ~ ${widget.work.endTime}',
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.grey600),
                          ),
                          if (_netWorkTimeStr.isNotEmpty)
                            TextSpan(
                              text: ' ($_netWorkTimeStr)',
                              style: ResponsiveHelper.tinyStyle(context)
                                  .copyWith(color: AppColors.grey500),
                            ),
                          TextSpan(
                            text: '  ·  ${widget.work.wageTypeLabel} ${FormatHelper.formatWage(widget.work.wage)}',
                            style: ResponsiveHelper.smallStyle(context,
                                    color: wageColor)
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                // ④ 상태배지 + 마감시간 (단기만)
                if (!widget.toItem.to.isLongTerm) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 5)),
                  Row(
                    children: [
                      _buildWorkStatusBadge(context, isClosed: isClosed),
                      if (_effectiveDeadline != null) ...[
                        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                        Icon(Icons.timer_off_outlined,
                            size: ResponsiveHelper.iconSize(context, 12),
                            color: isClosed ? AppColors.grey400 : AppColors.warningDark),
                        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                        Text(
                          '마감 ${FormatHelper.formatTime(_effectiveDeadline!)}',
                          style: ResponsiveHelper.smallStyle(context,
                              color: isClosed ? AppColors.grey400 : AppColors.warningDark),
                        ),
                      ],
                    ],
                  ),
                ],
                SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                // ⑤ 확정/대기/미충원 도트 + N/total
                _buildPersonnelStatus(context, isFull, isClosed, missing),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 확정(녹색) + 대기(앰버) + 잔여(회색) 수평 데이터 바
  Widget _buildProgressBar(bool isClosed) {
    final total = widget.work.requiredCount;
    if (total <= 0) return const SizedBox.shrink();
    final confirmedRatio = (_confirmedCount / total).clamp(0.0, 1.0);
    final pendingRatio = ((_confirmedCount + _pendingCount) / total).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 5,
            child: Stack(
              children: [
                Container(width: w, color: AppColors.grey100),
                if (pendingRatio > 0)
                  Container(
                    width: w * pendingRatio,
                    color: isClosed
                        ? AppColors.grey300
                        : AppColors.warning.withValues(alpha: 0.55),
                  ),
                if (confirmedRatio > 0)
                  Container(
                    width: w * confirmedRatio,
                    color: isClosed ? AppColors.grey400 : AppColors.success,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

/// 인원 현황 — 확정/대기/미충원 컬러 도트 + N/total 우측 정렬
  Widget _buildPersonnelStatus(
    BuildContext context,
    bool isFull,
    bool isClosed,
    int missing,
  ) {
    final confirmedColor = isClosed ? AppColors.grey400 : AppColors.success;
    final pendingColor = isClosed ? AppColors.grey400 : AppColors.warning;
    final missingColor = AppColors.grey400;
    final textColor = isClosed ? AppColors.grey500 : AppColors.grey700;

    return Row(
      children: [
        _buildDot(confirmedColor),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        Text('확정 $_confirmedCount',
            style: ResponsiveHelper.tinyStyle(context, color: textColor)),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        _buildDot(pendingColor),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        Text('대기 $_pendingCount',
            style: ResponsiveHelper.tinyStyle(context, color: textColor)),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        _buildDot(missingColor),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        Text('미충원 $missing',
            style: ResponsiveHelper.tinyStyle(context, color: textColor)),
        const Spacer(),
        Text(
          '$_confirmedCount/${widget.work.requiredCount}',
          style: ResponsiveHelper.smallStyle(context,
                  color: isFull && !isClosed
                      ? AppColors.successDark
                      : AppColors.grey600)
              .copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildDot(Color color) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
  /// ✨ 업무 상태 배지 (마감/예약/모집중)
  Widget _buildWorkStatusBadge(BuildContext context, {required bool isClosed}) {
    final to = widget.toItem.to;
    final slot = widget.toItem.slot;

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
    
    // 2. 예약 — slot.visibleFrom(슬롯 레벨) 또는 TO 레벨 스케줄
    // slot.visibleFrom은 슬롯 레벨 예약공개 — SlotStatusUtil과 동일 우선순위로 체크 필수
    // status='SCHEDULED'는 isPendingPublish와 별개 경로 — 둘 다 체크해야 예약 배지가 표시됨
    final slotScheduled = slot?.visibleFrom != null && slot!.visibleFrom!.isAfter(_buildNow);
    if (slotScheduled || to.status == TOStatus.scheduled || to.isPendingPublish) {
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