import 'package:flutter/material.dart';
import '../../../../models/work_detail_input.dart';
import '../../../../models/core/work_detail_model.dart';
import '../../../../models/core/insurance_rate_model.dart';
import '../../../../widgets/common/tax_deduction_badge.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../utils/format_helper.dart';
import '../../../../utils/labor_standards.dart';
import '../../../../utils/expected_daily_wage.dart';
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

  // 급여 지급 일정 레이블 (precomputed)
  final String payScheduleLabel;

  // 세금 공제 타입
  final String taxDeductionType;

  /// [F293-WAGE-01] 하루 예상 금액 — 공용 helper(`ExpectedDailyWage`) 결과. null 이면 이 카드의 폼 값으로 계산한다.
  ///   저장된 업무(fromData/fromModel)는 원문 여부(시각·유형)를 아는 `forWorkDetail` 로 넘긴다.
  final ExpectedDailyWage? expected;

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
    this.payScheduleLabel = '',
    this.taxDeductionType = InsuranceRateModel.typeNone,
    this.expected,
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
      taxDeductionType: detail.taxDeductionType,
      payScheduleLabel: _computeLabel(
          detail.payScheduleType, detail.payScheduleDay, detail.payScheduleTime),
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
      // [F293-WAGE-01] 실근무 표시 · 하루 예상 계산이 같은 휴게를 쓴다(예전 이 경로만 휴게를 빠뜨려 0 으로 보였다).
      breakMinutes: work.breakMinutes,
      currentCount: work.currentCount,
      canDelete: work.currentCount == 0,
      taxDeductionType: work.taxDeductionType,
      expected: ExpectedDailyWage.forWorkDetail(work),
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
      taxDeductionType: work.taxDeductionType,
      payScheduleLabel: _computeLabel(
          work.payScheduleType, work.payScheduleDay, work.payScheduleTime),
      canDelete: true,
      expected: ExpectedDailyWage.forWorkDetail(work),
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }

  static const _weekdayLabels = ['', '월', '화', '수', '목', '금', '토', '일'];

  static String _computeLabel(String? type, int? day, String? time) {
    if (type == null) return '';
    final t = time != null ? ' $time' : '';
    switch (type) {
      case 'same_day': return '당일$t';
      case 'next_day': return '익일$t';
      case 'weekly':
        final d = _weekdayLabels[day?.clamp(1, 7) ?? 1];
        return '매주 $d요일$t';
      case 'monthly':
        final n = day ?? 1;
        return '매월 ${n == 31 ? '말일' : '$n일'}$t';
      default: return '';
    }
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

  /// [F293-WAGE-01] 폼 값(등록 · 수정 미리보기) 그대로 — 시급 · 시각 · 등록된 무급 휴게. 시급 원금 · 유형은 바꾸지 않는다.
  ExpectedDailyWage get _expected =>
      expected ??
      ExpectedDailyWage.compute(
        wageType: wageType,
        rate: wage,
        startTime: startTime,
        endTime: endTime,
        breakMinutes: breakMinutes,
      );

  // [F293-WAGE-01 · 판정293 §8] 실근무 표시는 하루 예상 계산과 같은 분 계산이다 — 종료 = 시작을 24시간으로 말하지 않고
  //   (예전 calcNetWorkTime 은 +1,440), 휴게가 체류 이상이면 비운다. 숫자 서식(8h · 7.5h)은 그대로.
  String get _netWorkTimeStr {
    final net = ExpectedDailyWage.netMinutesOf(startTime, endTime, breakMinutes);
    return net == null ? '' : FormatHelper.formatCompactHours(net);
  }

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
                      // [R7-P4.4E.6A] 이 줄에는 줄어들 수 있는 자식이 없었다.
                      //   아이콘·시간·실근무를 고정 폭 자식으로만 늘어놓아서
                      //   '(실근무 ...)' 가 붙는 순간 Row 가 자식 고유 폭의 합을
                      //   그대로 요구했고, 360dp 기기에서 넘쳤다.
                      //   시간은 ALfit 의 핵심 사실이므로 ellipsis 로 감추지
                      //   않는다 — Wrap 으로 줄을 바꿔 전체를 보여준다.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              top: ResponsiveHelper.spacing(context, 2),
                            ),
                            child: Icon(
                              Icons.access_time,
                              size: ResponsiveHelper.iconSize(context, 13),
                              color: AppColors.grey500,
                            ),
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          Expanded(
                            child: Wrap(
                              spacing: ResponsiveHelper.spacing(context, 6),
                              runSpacing: ResponsiveHelper.spacing(context, 2),
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '$startTime ~ $endTime',
                                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                                ),
                                if (netTime.isNotEmpty)
                                  Text(
                                    '(실근무 $netTime)',
                                    style: ResponsiveHelper.tinyStyle(context).copyWith(
                                      color: AppColors.grey500,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 수정 버튼
                if (onEdit != null) ...[
                  // [DU331 ①] 편집 진입은 일반 진행 — brand 톤(이전 주의색 warningDark/warningExtraLight)
                  _ActionButton(
                    icon: Icons.edit_outlined,
                    color: AppColors.brand,
                    bgColor: AppColors.brandSurface,
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
          const Divider(height: 1, color: AppColors.grey100),

          // ── 메인 스탯: 급여 + 인원 ────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 14),
              vertical: ResponsiveHelper.spacing(context, 12),
            ),
            child: Row(
              children: [
                // 급여 stat — [F293-WAGE-01] 시급 업무는 '하루 예상 N원' 주표시 + '시급 N원' 보조 · 짧은 말 '예상·세전'.
                //   계산할 수 없으면 '예상 금액 확인 필요'(0원 금지). 일급 · 월급은 예전 그대로.
                Expanded(
                  child: Builder(builder: (context) {
                    final e = _expected;
                    // [F294-WAGE-01 · C294-WAGE-A] 유형을 모르면 '급여 확인 필요' 를 예상 금액처럼 보이지 않는다 —
                    //   라벨 '급여'(모델 기본 '시급' 아님) · '예상·세전' 짧은 말 0 · 시급 보조 0.
                    if (e.typeUnknown) {
                      return _StatBadge(
                        key: const ValueKey('to-work-wage-unknown'),
                        icon: Icons.payments_outlined,
                        label: '급여',
                        value: ExpectedWageText.wageUnknown,
                        wrapValue: true,
                        color: _wageColor(context),
                        bgColor: _wageBgColor(context),
                      );
                    }
                    final daily = ExpectedWageText.daily(e);
                    if (daily == null) {
                      // [F294-WAGE-01 · C294-WAGE-C] 알려진 비시급 단가 누락(0 이하)은 '0원' 대신 '급여 확인 필요'.
                      return _StatBadge(
                        icon: Icons.payments_outlined,
                        label: _wageTypeLabel,
                        value: ExpectedWageText.rawWage(wage),
                        wrapValue: true,
                        color: _wageColor(context),
                        bgColor: _wageBgColor(context),
                      );
                    }
                    return _StatBadge(
                      key: const ValueKey('to-work-expected-wage'),
                      icon: Icons.payments_outlined,
                      label: ExpectedWageText.shortNote,
                      value: daily,
                      sub: ExpectedWageText.rate(e),
                      color: _wageColor(context),
                      bgColor: _wageBgColor(context),
                    );
                  }),
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

          // ── 보조 칩: 근무시간대 + 휴게 + 통상시급 + 지급일정 + 세금 ──
          if (shiftType != null || breakMinutes > 0 || baseHourlyWage != null || payScheduleLabel.isNotEmpty || taxDeductionType != InsuranceRateModel.typeNone) ...[
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
                  if (payScheduleLabel.isNotEmpty)
                    _DetailChip(
                      icon: Icons.account_balance_wallet_outlined,
                      text: payScheduleLabel,
                      color: AppColors.successDark,
                    ),
                  if (taxDeductionType != InsuranceRateModel.typeNone)
                    _DetailChip(
                      icon: Icons.receipt_long_outlined,
                      text: InsuranceRateModel.typeLabel(taxDeductionType),
                      color: TaxDeductionBadge.colorFor(taxDeductionType),
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

  /// [F293-WAGE-01] 보조 줄(예: '시급 11,000원'). 있으면 금액은 말줄임 없이 줄바꿈한다(금액은 사실이라 자르지 않는다).
  final String? sub;

  /// [F294-WAGE-01] 급여 값(원시 단가 · '급여 확인 필요')은 보조 줄이 없어도 말줄임 없이 줄바꿈한다 — 같은 이유(사실·안내는 자르지 않는다).
  final bool wrapValue;

  const _StatBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
    this.sub,
    this.wrapValue = false,
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
                  overflow: (sub == null && !wrapValue) ? TextOverflow.ellipsis : null,
                ),
                if (sub != null)
                  Text(
                    sub!,
                    style: ResponsiveHelper.tinyStyle(context).copyWith(color: AppColors.grey600),
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
    // [DU331 ②] 보이는 타일은 그대로, 누르는 영역은 투명 48×48(실측 30.6 / 28.9 → 48). 겹침 없이 바깥 receiver 만 넓힌다.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Container(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
              child: Icon(icon, color: color, size: ResponsiveHelper.iconSize(context, 18)),
            ),
          ),
        ),
      ),
    );
  }
}
