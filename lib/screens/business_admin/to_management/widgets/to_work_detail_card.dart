import 'package:flutter/material.dart';
import '../../../../models/work_detail_input.dart';
import '../../../../models/core/work_detail_model.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../utils/format_helper.dart';
import '../../../../utils/labor_standards.dart';
import '../../../../widgets/work_type_icon.dart';
import '../../../../theme/app_colors.dart';

/// ✨ TO 업무 상세 카드
/// WorkDetailInput (create) / WorkDetailModel (edit) / WorkDetailData (새 아키텍처) 지원
class TOWorkDetailCard extends StatelessWidget {
  // 공통 필드
  final String workType;
  final String workTypeIcon;
  final String workTypeColor;
  final String? workTypeBackgroundColor;
  final int wage;
  final int requiredCount;
  final String startTime;
  final String endTime;
  final String wageType;
  final int breakMinutes;
  final int? baseHourlyWage;
  final String? shiftType;

  // edit에서만 사용
  final int? currentCount;
  final bool canDelete;

  // 콜백
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const TOWorkDetailCard({
    super.key,
    required this.workType,
    required this.workTypeIcon,
    required this.workTypeColor,
    this.workTypeBackgroundColor,
    required this.wage,
    required this.requiredCount,
    required this.startTime,
    required this.endTime,
    this.wageType = 'hourly',
    this.breakMinutes = 0,
    this.baseHourlyWage,
    this.shiftType,
    this.currentCount,
    this.canDelete = true,
    this.onEdit,
    this.onDelete,
  });

  factory TOWorkDetailCard.fromInput({
    required WorkDetailInput detail,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    return TOWorkDetailCard(
      workType: detail.workType ?? '',
      workTypeIcon: detail.workTypeIcon,
      workTypeColor: detail.workTypeColor,
      workTypeBackgroundColor: detail.workTypeBackgroundColor,
      wage: detail.wage ?? 0,
      requiredCount: detail.requiredCount ?? 0,
      startTime: detail.startTime ?? '',
      endTime: detail.endTime ?? '',
      wageType: detail.wageType,
      breakMinutes: detail.breakMinutes,
      baseHourlyWage: detail.baseHourlyWage,
      shiftType: detail.shiftType,
      canDelete: true,
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }

  factory TOWorkDetailCard.fromModel({
    required WorkDetailModel work,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    return TOWorkDetailCard(
      workType: work.workType,
      workTypeIcon: work.workTypeIcon,
      workTypeColor: work.workTypeColor,
      workTypeBackgroundColor: work.workTypeBackgroundColor,
      wage: work.wage,
      requiredCount: work.requiredCount,
      startTime: work.startTime,
      endTime: work.endTime,
      wageType: work.wageType,
      currentCount: work.currentCount,
      canDelete: work.currentCount == 0,
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }

  factory TOWorkDetailCard.fromData({
    required WorkDetailData work,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    return TOWorkDetailCard(
      workType: work.workType,
      workTypeIcon: work.workTypeIcon,
      workTypeColor: work.workTypeColor,
      workTypeBackgroundColor: work.workTypeBackgroundColor,
      wage: work.wage,
      requiredCount: work.requiredCount,
      startTime: work.startTime,
      endTime: work.endTime,
      wageType: work.wageType,
      breakMinutes: work.breakMinutes,
      baseHourlyWage: work.baseHourlyWage,
      shiftType: work.shiftType,
      canDelete: true,
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }

  String get _wageTypeLabel {
    switch (wageType) {
      case 'hourly': return '시급';
      case 'daily':  return '일급';
      default: return '급여';
    }
  }

  Color _wageColor(BuildContext context) {
    switch (wageType) {
      case 'daily': return AppColors.warningDark;   // 주황 — 일급 (고액 주의)
      default:      return AppColors.successDark;   // 초록 — 시급 (일반)
    }
  }

  Color _wageBgColor(BuildContext context) {
    switch (wageType) {
      case 'daily': return AppColors.warningBg;
      default:      return AppColors.successBg;
    }
  }

  String get _formattedWage =>
      wage.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );

  String get _netWorkTimeStr =>
      FormatHelper.calcNetWorkTime(startTime, endTime, breakMinutes: breakMinutes);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = FormatHelper.parseColor(workTypeBackgroundColor ?? '#2196F3');
    final iconColor = FormatHelper.parseColor(workTypeColor);
    final netTime = _netWorkTimeStr;

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
            color: AppColors.grey400.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 상단: 아이콘 + 업무명/시간 + 버튼 ──────────────────
          Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
            child: Row(
              children: [
                // 업무 유형 아이콘
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: iconColor.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: WorkTypeIcon.buildFromString(
                    workTypeIcon,
                    color: iconColor,
                    size: ResponsiveHelper.iconSize(context, 22),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),

                // 업무명 + 시간
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workType,
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: ResponsiveHelper.iconSize(context, 13),
                            color: AppColors.grey500,
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            '$startTime ~ $endTime',
                            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                          ),
                          if (netTime.isNotEmpty) ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                            Text(
                              '(실근무 $netTime)',
                              style: ResponsiveHelper.tinyStyle(context).copyWith(
                                color: AppColors.grey500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // 수정 버튼
                if (onEdit != null) ...[
                  _ActionButton(
                    icon: Icons.edit_outlined,
                    color: AppColors.warningDark,
                    bgColor: AppColors.warningExtraLight,
                    onTap: onEdit!,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                ],

                // 삭제 버튼
                if (onDelete != null)
                  _ActionButton(
                    icon: Icons.delete_outline,
                    color: canDelete ? AppColors.errorDark : AppColors.grey400,
                    bgColor: canDelete ? AppColors.errorBg : AppColors.grey100,
                    onTap: canDelete ? onDelete! : null,
                  ),
              ],
            ),
          ),

          // ── 구분선 ────────────────────────────────────────────
          Divider(height: 1, color: AppColors.grey100),

          // ── 메인 스탯: 급여 + 인원 ────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 14),
              vertical: ResponsiveHelper.spacing(context, 12),
            ),
            child: Row(
              children: [
                // 급여 stat
                Expanded(
                  child: _StatBadge(
                    icon: Icons.payments_outlined,
                    label: _wageTypeLabel,
                    value: '$_formattedWage원',
                    color: _wageColor(context),
                    bgColor: _wageBgColor(context),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                // 인원 stat
                Expanded(
                  child: _StatBadge(
                    icon: Icons.people_outlined,
                    label: '필요 인원',
                    value: '$requiredCount명'
                        '${currentCount != null && currentCount! > 0 ? ' ($currentCount명 확정)' : ''}',
                    color: theme.primaryColor,
                    bgColor: theme.primaryColor.withValues(alpha: 0.08),
                  ),
                ),
              ],
            ),
          ),

          // ── 보조 칩: 근무시간대 + 휴게 + 통상시급 ─────────────
          if (shiftType != null || breakMinutes > 0 || baseHourlyWage != null) ...[
            Padding(
              padding: EdgeInsets.only(
                left: ResponsiveHelper.spacing(context, 14),
                right: ResponsiveHelper.spacing(context, 14),
                bottom: ResponsiveHelper.spacing(context, 12),
              ),
              child: Wrap(
                spacing: ResponsiveHelper.spacing(context, 8),
                runSpacing: ResponsiveHelper.spacing(context, 6),
                children: [
                  if (shiftType != null)
                    _DetailChip(
                      icon: Icons.wb_twilight_outlined,
                      text: shiftType!,
                      color: _shiftTypeColor(shiftType!),
                    ),
                  if (breakMinutes > 0)
                    _DetailChip(
                      icon: Icons.pause_circle_outline,
                      text: '휴게 ${FormatHelper.formatCompactHours(breakMinutes)}',
                      color: AppColors.successDark,
                    ),
                  if (baseHourlyWage != null)
                    _DetailChip(
                      icon: Icons.gavel_outlined,
                      text: '통상시급 ${LaborStandards.formatCurrencyWithUnit(baseHourlyWage!)}',
                      color: AppColors.grey700,
                    )
                  else if (wageType == 'daily' && netTime.isNotEmpty)
                    _DetailChip(
                      icon: Icons.gavel_outlined,
                      text: '통상시급 자동계산',
                      color: AppColors.grey500,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Color _shiftTypeColor(String type) {
    switch (type) {
      case '주간': return AppColors.amberDark;    // ☀️ 앰버 — 낮
      case '석간': return AppColors.warningDeep;  // 🌅 딥오렌지 — 노을
      case '야간': return AppColors.purpleDark;   // 🌙 퍼플 — 밤
      default:    return AppColors.amberDark;
    }
  }
}

// ── 메인 스탯 배지 ────────────────────────────────────────────
class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color bgColor;

  const _StatBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 18), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: ResponsiveHelper.tinyStyle(context).copyWith(color: color.withValues(alpha: 0.8)),
                ),
                Text(
                  value,
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 보조 정보 칩 ─────────────────────────────────────────────
class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _DetailChip({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 12), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            text,
            style: ResponsiveHelper.tinyStyle(context).copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 액션 버튼 (수정/삭제) ────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.bgColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          child: Icon(icon, color: color, size: ResponsiveHelper.iconSize(context, 18)),
        ),
      ),
    );
  }
}
