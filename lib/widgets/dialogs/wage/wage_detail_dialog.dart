// lib/widgets/dialogs/wage/wage_detail_dialog.dart

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../models/core/application_model.dart';
import '../../../screens/payroll/payslip_view_screen.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/insurance_rate_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/wage_detail_model.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/wage_calculator.dart';
import '../../../theme/app_colors.dart';
import '../styled_dialog.dart';

enum WageDialogMode {
  pending,
  calculated,
  confirmed,
  editOnly,
}

class WageDialogResult {
  final String action;
  final WageDetailModel wage;
  const WageDialogResult({required this.action, required this.wage});
}

class WageDetailDialog extends StatefulWidget {
  final ApplicationModel app;
  final UserModel? user;
  final AttendanceModel attendance;
  final WageDetailModel wage;
  final WageDialogMode mode;
  final String? businessName;
  final String? shiftType;
  final bool nightIncluded;
  final int scheduledBreakMinutes;
  final int? baseHourlyWage; // 사업주가 업무상세에 입력한 통상시급
  // TO 수정 후 최신 스케줄 시간 (미전달 시 app.startTime/endTime 폴백)
  final String? effStart;
  final String? effEnd;

  const WageDetailDialog({
    super.key,
    required this.app,
    required this.user,
    required this.attendance,
    required this.wage,
    required this.mode,
    this.businessName,
    this.shiftType,
    this.nightIncluded = false,
    this.scheduledBreakMinutes = 0,
    this.baseHourlyWage,
    this.effStart,
    this.effEnd,
  });

  static Future<WageDialogResult?> show({
    required BuildContext context,
    required ApplicationModel app,
    required UserModel? user,
    required AttendanceModel attendance,
    required WageDetailModel wage,
    required WageDialogMode mode,
    String? businessName,
    String? shiftType,
    bool nightIncluded = false,
    int scheduledBreakMinutes = 0,
    int? baseHourlyWage,
    String? effStart,
    String? effEnd,
  }) {
    return showDialog<WageDialogResult>(
      context: context,
      builder: (context) => WageDetailDialog(
        app: app,
        user: user,
        attendance: attendance,
        wage: wage,
        mode: mode,
        businessName: businessName,
        shiftType: shiftType,
        nightIncluded: nightIncluded,
        scheduledBreakMinutes: scheduledBreakMinutes,
        baseHourlyWage: baseHourlyWage,
        effStart: effStart,
        effEnd: effEnd,
      ),
    );
  }

  @override
  State<WageDetailDialog> createState() => _WageDetailDialogState();
}

class _WageDetailDialogState extends State<WageDetailDialog> {
  late WageDetailModel _wage;
  bool _isActing = false;
  final _additionalController = TextEditingController();
  final _deductionController = TextEditingController();
  final _memoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _wage = widget.wage;
    _additionalController.text =
        widget.wage.additionalAmount > 0 ? widget.wage.additionalAmount.toString() : '';
    _deductionController.text =
        widget.wage.deductionAmount > 0 ? widget.wage.deductionAmount.toString() : '';
    _memoController.text = widget.wage.memo ?? '';
  }

  @override
  void dispose() {
    _additionalController.dispose();
    _deductionController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  void _updateWage() {
    final additional =
        (int.tryParse(_additionalController.text.replaceAll(',', '')) ?? 0).abs();
    final deduction =
        (int.tryParse(_deductionController.text.replaceAll(',', '')) ?? 0).abs();
    final newTotal = _wage.baseAmount + _wage.overtimeAmount + _wage.nightAmount +
        additional - deduction + _wage.weeklyHolidayAmount;
    setState(() {
      _wage = _wage.copyWith(
        additionalAmount: additional,
        deductionAmount: deduction,
        totalAmount: newTotal,
        // 보험 공제액은 기본급 기준으로 이미 확정됐으므로 그대로 유지.
        // ✅ 의도된 netWage 직접 할당:
        //   이 다이얼로그는 isCalculated=true(calculatedAt != null) 상태에서 편집한다.
        //   effectiveNetWage 게터는 isCalculated=true이면 netWage를 반환하므로,
        //   추가수당/수동공제 변경 시 UI 미리보기를 즉시 동기화하려면
        //   copyWith(netWage: ...)로 직접 갱신해야 한다.
        //   최종 저장(_onAction) 시점에도 이 값이 Firestore에 기록된다.
        netWage: newTotal - _wage.totalInsuranceDeduction,
        memo: _memoController.text.trim().isNotEmpty
            ? _memoController.text.trim()
            : null,
      );
    });
  }

  /// 무급 휴게시간 수정 bottom sheet
  void _showEditBreakSheet(BuildContext context) {
    final legalMax = WageCalculator.legalMaxBreakMinutes(_wage.actualMinutes);
    final isOver = _wage.breakMinutes > legalMax;
    final legalLabel = legalMax == 0
        ? '없음 (4시간 미만 근무)'
        : '$legalMax분';

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('무급 휴게시간 수정',
                style: ResponsiveHelper.subtitleStyle(ctx)
                    .copyWith(fontWeight: FontWeight.bold)),
            SizedBox(height: ResponsiveHelper.spacing(ctx, 10)),
            // 법정 기준 안내
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isOver ? AppColors.errorBg : AppColors.infoBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    isOver
                        ? Icons.warning_amber_outlined
                        : Icons.info_outline,
                    size: ResponsiveHelper.iconSize(ctx, 14),
                    color: isOver ? AppColors.errorDark : AppColors.infoDark,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(ctx, 6)),
                  Expanded(
                    child: Text(
                      '체류 ${FormatHelper.formatCompactHours(_wage.actualMinutes)} 기준  법정 최대: $legalLabel',
                      style: ResponsiveHelper.tinyStyle(ctx,
                          color: isOver
                              ? AppColors.errorDark
                              : AppColors.infoDark),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(ctx, 16)),
            Text('적용할 휴게시간 선택',
                style: ResponsiveHelper.smallStyle(ctx,
                    color: AppColors.grey500)),
            SizedBox(height: ResponsiveHelper.spacing(ctx, 10)),
            Wrap(
              spacing: ResponsiveHelper.spacing(ctx, 8),
              runSpacing: ResponsiveHelper.spacing(ctx, 8),
              children: [0, 30, 60, 90].map((min) {
                final isSelected = _wage.breakMinutes == min;
                final exceedsLegal = legalMax > 0 && min > legalMax;
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _applyNewBreak(min);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.info
                          : exceedsLegal
                              ? AppColors.errorBg
                              : AppColors.grey100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.info
                            : exceedsLegal
                                ? AppColors.errorDark
                                : AppColors.grey200,
                      ),
                    ),
                    child: Text(
                      min == 0 ? '없음' : '$min분',
                      style: ResponsiveHelper.smallStyle(ctx,
                              color: isSelected
                                  ? Colors.white
                                  : exceedsLegal
                                      ? AppColors.errorDark
                                      : AppColors.grey700)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  /// 새 휴게시간으로 급여 재계산 (보험공제·추가수당·메모 유지)
  void _applyNewBreak(int newBreakMinutes) {
    final checkIn = widget.attendance.checkIn;
    final checkOut = widget.attendance.checkOut;
    if (checkIn == null || checkOut == null) return;

    // 컨트롤러의 최신 공제 값 직접 파싱 (미반영 상태의 _wage.deductionAmount 사용 방지)
    final currentDeduction = (int.tryParse(_deductionController.text.replaceAll(',', '')) ?? 0).abs();

    final recalculated = WageCalculator.calculate(
      wageType: _wage.wageType,
      baseWage: _wage.baseWage,
      workDate: widget.attendance.workDate,
      scheduledStart: widget.effStart ?? widget.app.startTime,
      scheduledEnd: widget.effEnd ?? widget.app.endTime,
      actualStart: checkIn,
      actualEnd: checkOut,
      breakMinutes: newBreakMinutes,
      scheduledBreakMinutes: widget.scheduledBreakMinutes,
      nightAllowanceApplied: _wage.nightAllowanceApplied,
      nightIncluded: widget.nightIncluded,
      additionalAmount: _wage.additionalAmount,
      memo: _wage.memo,
      baseHourlyWage: widget.baseHourlyWage,
    );

    setState(() {
      _wage = recalculated.copyWith(
        // 수동 공제는 컨트롤러 최신 값 사용
        deductionAmount: currentDeduction,
        totalAmount: recalculated.totalAmount - currentDeduction,
        // 보험·세금 공제는 기확정 값 유지
        taxDeductionType: _wage.taxDeductionType,
        employmentInsuranceDeduction: _wage.employmentInsuranceDeduction,
        nationalPensionDeduction: _wage.nationalPensionDeduction,
        healthInsuranceDeduction: _wage.healthInsuranceDeduction,
        ltcInsuranceDeduction: _wage.ltcInsuranceDeduction,
        incomeTaxDeduction: _wage.incomeTaxDeduction,
        retroactiveDeduction: _wage.retroactiveDeduction,
        // ✅ 의도된 netWage 직접 할당 (_updateWage()와 동일한 이유):
        //   휴게시간 변경 후 재계산된 recalculated는 isCalculated=false (calculatedAt=null)
        //   이므로 효과적으로는 totalAmount - totalInsuranceDeduction을 반환하겠지만,
        //   calculatedAt을 아래에서 유지하므로 effectiveNetWage가 netWage를 참조한다.
        //   따라서 recalculated.copyWith(calculatedAt: ...) 후 netWage를 명시적으로
        //   갱신해야 UI 미리보기가 정확하다.
        netWage: recalculated.totalAmount - currentDeduction -
            _wage.totalInsuranceDeduction,
        // 계산 타임스탬프 유지
        calculatedBy: _wage.calculatedBy,
        calculatedAt: _wage.calculatedAt,
      );
    });
  }

  Future<void> _onAction(String action) async {
    if (_isActing) return; // 중복 탭 방지
    _updateWage();
    final userName = widget.user?.name ?? '근무자';
    final hasDeductions = _wage.taxDeductionType != InsuranceRateModel.typeNone &&
        _wage.totalInsuranceDeduction > 0;
    final grossText = FormatHelper.formatWage(_wage.totalAmount);
    final netText = FormatHelper.formatWage(_wage.effectiveNetWage);

    String confirmTitle, confirmMessage, confirmText;
    bool isDanger = false;

    switch (action) {
      case 'confirm':
        confirmTitle = '급여 확정';
        confirmMessage = hasDeductions
            ? '$userName의 급여를 확정하시겠습니까?\n\n세전: $grossText\n실수령액: $netText'
            : '$userName의 급여를 확정하시겠습니까?\n\n총 급여: $grossText';
        confirmText = '확정';
        break;
      case 'update':
        Navigator.pop(context, WageDialogResult(action: action, wage: _wage));
        return;
      case 'final_confirm':
        confirmTitle = '최종 확정';
        confirmMessage = hasDeductions
            ? '$userName의 급여를 최종 확정하시겠습니까?\n\n세전: $grossText\n실수령액: $netText\n\n⚠️ 최종 확정 후에는 수정이 불가합니다.'
            : '$userName의 급여를 최종 확정하시겠습니까?\n\n총 급여: $grossText\n\n⚠️ 최종 확정 후에는 수정이 불가합니다.';
        confirmText = '최종 확정';
        break;
      case 'cancel':
        confirmTitle = '급여 확정 되돌리기';
        confirmMessage = '$userName의 급여 확정을 되돌리시겠습니까?\n\n입력 오류 수정이 필요한 경우에 사용하세요.\n미확정 상태로 돌아가며, 근무자에게 재조정 안내 알림이 발송됩니다.';
        confirmText = '되돌리기';
        isDanger = true;
        break;
      default:
        return;
    }

    if (!mounted) return;
    setState(() => _isActing = true);
    try {
      bool confirmed = false;
      if (isDanger) {
        confirmed = await DialogHelper.showDangerConfirm(
          context,
          title: confirmTitle,
          message: confirmMessage,
          confirmText: confirmText,
        );
      } else {
        confirmed = await DialogHelper.showConfirm(
          context,
          title: confirmTitle,
          message: confirmMessage,
          confirmText: confirmText,
        );
      }
      if (confirmed && mounted) {
        Navigator.pop(context, WageDialogResult(action: action, wage: _wage));
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  // ── UI 속성 ──────────────────────────────────────────────────

  /// 임금명세서 화면 진입
  void _openPayslip(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PayslipViewScreen(
          attendance: widget.attendance,
          worker: widget.user,
          workerNameOverride: widget.user?.name ?? '근무자',
        ),
      ),
    );
  }

  bool get _isTransferred => widget.attendance.isWageTransferred;

  Color get _headerColor {
    switch (widget.mode) {
      case WageDialogMode.pending:    return AppColors.warning;
      case WageDialogMode.calculated:
      case WageDialogMode.editOnly:   return AppColors.info;
      case WageDialogMode.confirmed:
        return _isTransferred ? AppColors.info : AppColors.success;
    }
  }

  IconData get _headerIcon {
    switch (widget.mode) {
      case WageDialogMode.pending:    return Icons.receipt_long;
      case WageDialogMode.calculated:
      case WageDialogMode.editOnly:   return Icons.edit_outlined;
      case WageDialogMode.confirmed:
        return _isTransferred ? Icons.account_balance : Icons.verified;
    }
  }

  String get _headerSubtitle {
    switch (widget.mode) {
      case WageDialogMode.pending:    return '미확정 · 급여 확정 필요';
      case WageDialogMode.calculated: return '급여 확정됨 · 수정 가능';
      case WageDialogMode.editOnly:   return '급여 수정';
      case WageDialogMode.confirmed:
        return _isTransferred ? '이체 완료' : '최종 확정됨';
    }
  }

  bool get _isEditable => widget.mode != WageDialogMode.confirmed;

  /// 조출수당 금액 (저장된 earlyArrivalAmount 우선, 구형 레코드는 비율 fallback)
  int _effectiveEarlyArrivalAmount(int earlyMins) {
    if (_wage.earlyArrivalAmount > 0) return _wage.earlyArrivalAmount;
    if (_wage.overtimeMinutes > 0 && earlyMins > 0) {
      return (_wage.overtimeAmount * earlyMins / _wage.overtimeMinutes).round();
    }
    return 0;
  }

  /// 연장·야간수당 기초 시급 — 사업주 설정값 우선
  int get _supplementWage {
    // 1순위: 최근 계산 레코드에 저장된 값
    if (_wage.appliedSupplementWage > 0) return _wage.appliedSupplementWage;
    // 2순위: 호출자가 넘긴 업무상세의 baseHourlyWage
    if (widget.baseHourlyWage != null && widget.baseHourlyWage! > 0) {
      return widget.baseHourlyWage!;
    }
    // 3순위: 시급제는 시급 자체
    if (_wage.wageType == 'hourly') return _wage.baseWage;
    // 4순위: 일급÷예정순근무 역산 (구형 레코드 + baseHourlyWage 미입력)
    final schedNetMins =
        (_wage.scheduledMinutes - widget.scheduledBreakMinutes).clamp(1, 9999);
    return (_wage.baseWage / schedNetMins * 60).round();
  }

  Color get _wageColor =>
      _wage.wageType == 'daily' ? AppColors.warningDark : AppColors.successDark;
  Color get _wageBg =>
      _wage.wageType == 'daily' ? AppColors.warningBg : AppColors.successBg;

  static Color _shiftTypeColor(String type) {
    switch (type) {
      case '주간': return AppColors.amberDark;
      case '석간': return AppColors.warningDeep;
      case '야간': return AppColors.purpleDark;
      default:    return AppColors.amberDark;
    }
  }

  static IconData _shiftTypeIcon(String type) {
    switch (type) {
      case '주간': return Icons.wb_sunny_outlined;
      case '석간': return Icons.wb_twilight_outlined;
      case '야간': return Icons.nights_stay_outlined;
      default:    return Icons.wb_sunny_outlined;
    }
  }

  // ── BUILD ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.user?.name ?? '이름 없음';


    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: AppDialogSize.insetV,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, name),
            Flexible(
              child: SingleChildScrollView(
                padding: ResponsiveHelper.cardPadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoSection(context),
                    SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                    _buildWageSection(context),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    _buildCalculationGuide(context),
                    if (_isEditable) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                      _buildEditSection(context, theme),
                    ],
                  ],
                ),
              ),
            ),
            _buildBottomButtons(context, theme),
          ],
        ),
      ),
    );
  }

  // ── 헤더 ─────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, String name) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: _headerColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(ResponsiveHelper.spacing(context, 20)),
          topRight: Radius.circular(ResponsiveHelper.spacing(context, 20)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
            ),
            child: Icon(_headerIcon, color: Colors.white,
                size: ResponsiveHelper.iconSize(context, 24)),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name 급여 명세',
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  _headerSubtitle,
                  style: ResponsiveHelper.tinyStyle(context)
                      .copyWith(color: Colors.white.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close, color: Colors.white,
                size: ResponsiveHelper.iconSize(context, 24)),
          ),
        ],
      ),
    );
  }

  // ── 근무 정보 섹션 ────────────────────────────────────────────

  Widget _buildTransferBanner(BuildContext context) {
    final transferDate = widget.attendance.transferDate;
    final transferNote = widget.attendance.transferNote;
    final dateStr = transferDate != null
        ? '${transferDate.year}.${transferDate.month.toString().padLeft(2, '0')}.${transferDate.day.toString().padLeft(2, '0')}'
        : null;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance, color: AppColors.info,
              size: ResponsiveHelper.iconSize(context, 20)),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('급여 이체 완료',
                    style: ResponsiveHelper.smallStyle(context)
                        .copyWith(color: AppColors.info, fontWeight: FontWeight.bold)),
                if (dateStr != null)
                  Text('이체일: $dateStr',
                      style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600)),
                if (transferNote != null && transferNote.isNotEmpty)
                  Text(transferNote,
                      style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context) {
    final d = widget.attendance.workDate;
    final dateStr = '${d.year}년 ${d.month}월 ${d.day}일';

    final contractNetTime = FormatHelper.formatCompactHours(_wage.scheduledMinutes);
    final workTimeStr = FormatHelper.formatCompactHours(_wage.workMinutes);
    final breakTimeStr = _wage.breakMinutes > 0
        ? FormatHelper.formatCompactHours(_wage.breakMinutes)
        : null;
    final nightStr = _wage.nightMinutes > 0
        ? FormatHelper.formatCompactHours(_wage.nightMinutes)
        : null;

    // 미근무 시간: (계약 순근무 - 실근무), 일급제에서 조퇴/지각 시 발생
    // scheduledBreakMinutes(예정 휴게) 기준 — breakMinutes는 실제 휴게로 달라질 수 있음
    final scheduledNetMins = (_wage.scheduledMinutes - widget.scheduledBreakMinutes).clamp(0, 9999);
    final unworkedMins = (scheduledNetMins - _wage.workMinutes).clamp(0, scheduledNetMins);
    final unworkedStr = (unworkedMins > 0 && _wage.wageType == 'daily')
        ? FormatHelper.formatCompactHours(unworkedMins)
        : null;

    // 법정 휴게 초과 여부 (체류 시간 기준)
    final legalMax = WageCalculator.legalMaxBreakMinutes(_wage.actualMinutes);
    final isBreakExceeded = _wage.breakMinutes > legalMax;
    // 석식/야식 공제 분리 (total - 기본 scheduled)
    final mealMins = (_wage.breakMinutes - widget.scheduledBreakMinutes).clamp(0, 9999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 이체 완료 배너 (transferred 상태)
        if (_isTransferred) ...[
          _buildTransferBanner(context),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        ],

        _buildSectionTitle(context, '근무 정보'),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        // 기본 정보 칩
        Wrap(
          spacing: ResponsiveHelper.spacing(context, 6),
          runSpacing: ResponsiveHelper.spacing(context, 6),
          children: [
            _buildInfoChip(context, Icons.calendar_today_outlined, dateStr,
                AppColors.grey600, AppColors.grey100),
            if (widget.businessName != null && widget.businessName!.isNotEmpty)
              _buildInfoChip(context, Icons.business_outlined, widget.businessName!,
                  AppColors.grey700, AppColors.grey100),
            _buildInfoChip(context, Icons.work_outline, widget.app.selectedWorkType,
                _headerColor, _headerColor.withValues(alpha: 0.1)),
            if (widget.shiftType != null)
              _buildInfoChip(
                context,
                _shiftTypeIcon(widget.shiftType!),
                widget.shiftType!,
                _shiftTypeColor(widget.shiftType!),
                _shiftTypeColor(widget.shiftType!).withValues(alpha: 0.1),
              ),
            _buildInfoChip(context, Icons.payments_outlined, _wage.wageTypeLabel,
                _wageColor, _wageBg),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 14)),

        // 시간 정보 카드
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _headerColor.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: _headerColor.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // 계약 시간
              Row(
                children: [
                  Icon(Icons.schedule_outlined,
                      size: ResponsiveHelper.iconSize(context, 13),
                      color: AppColors.grey500),
                  SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                  Text('계약',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey500)),
                  const Spacer(),
                  Text('${widget.effStart ?? widget.app.startTime} ~ ${widget.effEnd ?? widget.app.endTime}',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey700)),
                  if (contractNetTime.isNotEmpty) ...[
                    SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                    Text('($contractNetTime)',
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.grey400)),
                  ],
                ],
              ),

              Padding(
                padding: EdgeInsets.symmetric(
                    vertical: ResponsiveHelper.spacing(context, 8)),
                child: Divider(height: 1, color: AppColors.grey200),
              ),

              // 실제 출퇴근
              Row(
                children: [
                  Icon(Icons.login_outlined,
                      size: ResponsiveHelper.iconSize(context, 13),
                      color: AppColors.successDark),
                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  Text('출근',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.successDark)),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Text(widget.attendance.checkIn ?? '-',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey700)
                          .copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Icon(Icons.logout_outlined,
                      size: ResponsiveHelper.iconSize(context, 13),
                      color: AppColors.warningDark),
                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  Text('퇴근',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.warningDark)),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Text(widget.attendance.checkOut ?? '-',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey700)
                          .copyWith(fontWeight: FontWeight.w600)),
                ],
              ),

              if (breakTimeStr != null) ...[
                Padding(
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 8)),
                  child: Divider(height: 1, color: AppColors.grey200),
                ),
                // 총 근무시간 (체류 시간 = 실근무 + 휴게)
                Row(
                  children: [
                    Icon(Icons.timelapse_outlined,
                        size: ResponsiveHelper.iconSize(context, 13),
                        color: AppColors.grey500),
                    SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                    Text('총 근무시간',
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.grey500)),
                    const Spacer(),
                    Text(
                      FormatHelper.formatCompactHours(
                          _wage.workMinutes + _wage.breakMinutes),
                      style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.grey700)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 8)),
                  child: Divider(height: 1, color: AppColors.grey200),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.pause_circle_outline,
                            size: ResponsiveHelper.iconSize(context, 13),
                            color: isBreakExceeded
                                ? AppColors.errorDark
                                : AppColors.amber),
                        SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                        Text('무급 휴게',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: isBreakExceeded
                                    ? AppColors.errorDark
                                    : AppColors.amber)),
                        const Spacer(),
                        Text('- $breakTimeStr',
                            style: ResponsiveHelper.smallStyle(context,
                                    color: isBreakExceeded
                                        ? AppColors.errorDark
                                        : AppColors.amber)
                                .copyWith(fontWeight: FontWeight.w600)),
                        if (_isEditable) ...[
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          GestureDetector(
                            onTap: () => _showEditBreakSheet(context),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: AppColors.grey100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.edit_outlined,
                                  size: ResponsiveHelper.iconSize(context, 12),
                                  color: AppColors.grey600),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (mealMins > 0 && widget.scheduledBreakMinutes > 0) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                      Padding(
                        padding: EdgeInsets.only(
                            left: ResponsiveHelper.spacing(context, 18)),
                        child: Text(
                          '기본 ${FormatHelper.formatCompactHours(widget.scheduledBreakMinutes)} · 석식/야식 +${FormatHelper.formatCompactHours(mealMins)}',
                          style: ResponsiveHelper.tinyStyle(context,
                              color: AppColors.grey400),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),

        // 시간 내역 stat boxes
        Row(
          children: [
            Expanded(
              child: _buildTimeStatBox(context, '실근무', workTimeStr,
                  AppColors.grey700, AppColors.grey100),
            ),
            if (unworkedStr != null) ...[
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: _buildTimeStatBox(context, '미근무', unworkedStr,
                    AppColors.errorDark, AppColors.errorBg),
              ),
            ],
            // 조출/연장 분리: 둘 다 있으면 각각, 하나만 있으면 해당 라벨
            if (_wage.earlyArrivalMinutes > 0) ...[
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: _buildTimeStatBox(
                  context, '조출',
                  FormatHelper.formatCompactHours(_wage.earlyArrivalMinutes),
                  AppColors.warningDark, AppColors.warningBg,
                ),
              ),
            ],
            if (_wage.overtimeMinutes - _wage.earlyArrivalMinutes > 0) ...[
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: _buildTimeStatBox(
                  context, '연장',
                  FormatHelper.formatCompactHours(
                      _wage.overtimeMinutes - _wage.earlyArrivalMinutes),
                  AppColors.warningDark, AppColors.warningBg,
                ),
              ),
            ],
            if (nightStr != null) ...[
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: _buildTimeStatBox(context, '야간', nightStr,
                    AppColors.purpleDark, AppColors.purpleBg),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ── 급여 명세 섹션 ────────────────────────────────────────────

  Widget _buildWageSection(BuildContext context) {
    final isDaily = _wage.wageType == 'daily';
    final workStr = FormatHelper.formatCompactHours(_wage.workMinutes);
    final nightStr = _wage.nightMinutes > 0
        ? FormatHelper.formatCompactHours(_wage.nightMinutes)
        : null;

    // 조출/연장 분리
    final earlyMins = _wage.earlyArrivalMinutes;
    final regularMins = _wage.overtimeMinutes - earlyMins;
    final earlyArrivalAmount = _effectiveEarlyArrivalAmount(earlyMins);
    final regularOvertimeAmount = _wage.overtimeAmount - earlyArrivalAmount;

    // 일급제 미근무 공제: 원래 일급과 실제 기본급의 차이
    final absenceDeduction = isDaily
        ? (_wage.baseWage - _wage.baseAmount).clamp(0, _wage.baseWage)
        : 0;
    final absenceDeductionStr = absenceDeduction > 0
        ? FormatHelper.formatCompactHours(
            (_wage.scheduledMinutes - widget.scheduledBreakMinutes - _wage.workMinutes)
                .clamp(0, _wage.scheduledMinutes))
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSectionTitle(context, '급여 명세'),
            const Spacer(),
            // 통상시급 뱃지
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.grey200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.gavel_outlined,
                      size: ResponsiveHelper.iconSize(context, 11),
                      color: AppColors.grey600),
                  SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                  Text(
                    '통상시급 ${FormatHelper.formatWage(_supplementWage)}',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.grey600),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        // 급여 항목 카드
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.grey200),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // 기본급 / 일급
              // 일급제 + 미근무 공제가 있으면: 원래 일급 → 미근무 공제 두 줄로 표시
              _buildWageLineItem(
                context,
                label: isDaily
                    ? (absenceDeduction > 0 ? '일급 (전체)' : '일급')
                    : '기본급',
                subLabel: isDaily ? null : workStr,
                amount: isDaily && absenceDeduction > 0
                    ? _wage.baseWage
                    : _wage.baseAmount,
                color: AppColors.grey800,
                icon: Icons.payments_outlined,
                isFirst: true,
              ),
              if (absenceDeduction > 0) ...[
                Divider(height: 1, color: AppColors.grey100),
                _buildWageLineItem(
                  context,
                  label: '미근무 공제',
                  subLabel: absenceDeductionStr,
                  amount: absenceDeduction,
                  color: AppColors.errorDark,
                  icon: Icons.remove_circle_outline,
                  isDeduction: true,
                ),
              ],
              if (earlyArrivalAmount > 0) ...[
                Divider(height: 1, color: AppColors.grey100),
                _buildWageLineItem(
                  context,
                  label: '조출수당',
                  subLabel: FormatHelper.formatCompactHours(earlyMins),
                  amount: earlyArrivalAmount,
                  color: AppColors.warningDark,
                  icon: Icons.trending_up,
                ),
              ],
              if (regularMins > 0) ...[
                Divider(height: 1, color: AppColors.grey100),
                _buildWageLineItem(
                  context,
                  label: '연장수당',
                  subLabel: FormatHelper.formatCompactHours(regularMins),
                  amount: regularOvertimeAmount,
                  color: AppColors.warningDark,
                  icon: Icons.trending_up,
                ),
              ],
              if (_wage.nightAmount > 0) ...[
                Divider(height: 1, color: AppColors.grey100),
                _buildWageLineItem(
                  context,
                  label: '야간수당',
                  subLabel: nightStr,
                  amount: _wage.nightAmount,
                  color: AppColors.purpleDark,
                  icon: Icons.nights_stay_outlined,
                ),
              ],
              if (_wage.additionalAmount > 0) ...[
                Divider(height: 1, color: AppColors.grey100),
                _buildWageLineItem(
                  context,
                  label: '추가수당',
                  amount: _wage.additionalAmount,
                  color: AppColors.infoDark,
                  icon: Icons.add_circle_outline,
                ),
              ],
              if (_wage.deductionAmount > 0) ...[
                Divider(height: 1, color: AppColors.grey100),
                _buildWageLineItem(
                  context,
                  label: '추가공제',
                  amount: _wage.deductionAmount,
                  color: AppColors.errorDark,
                  icon: Icons.remove_circle_outline,
                  isDeduction: true,
                ),
              ],
              if (_wage.weeklyHolidayAmount > 0) ...[
                Divider(height: 1, color: AppColors.grey100),
                _buildWageLineItem(
                  context,
                  label: '주휴수당',
                  amount: _wage.weeklyHolidayAmount,
                  color: AppColors.successDark,
                  icon: Icons.event_available_outlined,
                ),
              ],
              // ── 세전 총급여 소계 (공제가 있는 경우) ──────────────
              if (_wage.taxDeductionType != InsuranceRateModel.typeNone &&
                  _wage.totalInsuranceDeduction > 0) ...[
                Divider(height: 1, color: AppColors.grey200),
                Container(
                  color: AppColors.grey50,
                  child: _buildWageLineItem(
                    context,
                    label: '세전 총급여',
                    amount: _wage.totalAmount,
                    color: AppColors.grey700,
                    icon: Icons.receipt_long_outlined,
                  ),
                ),
              ],
              // ── 세금·보험 공제 항목 ────────────────────────────
              if (_wage.taxDeductionType != InsuranceRateModel.typeNone) ...[
                Divider(height: 1, color: AppColors.grey200),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 14),
                    vertical: ResponsiveHelper.spacing(context, 8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_outlined,
                          size: 13, color: AppColors.grey500),
                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                      Text(
                        '공제 (${_wage.taxDeductionLabel})',
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.grey500)
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (_wage.employmentInsuranceDeduction > 0) ...[
                  Divider(height: 1, color: AppColors.grey100),
                  _buildWageLineItem(
                    context,
                    label: '고용보험',
                    amount: _wage.employmentInsuranceDeduction,
                    color: AppColors.errorDark,
                    icon: Icons.work_outline,
                    isDeduction: true,
                  ),
                ],
                if (_wage.nationalPensionDeduction > 0) ...[
                  Divider(height: 1, color: AppColors.grey100),
                  _buildWageLineItem(
                    context,
                    label: '국민연금',
                    amount: _wage.nationalPensionDeduction,
                    color: AppColors.errorDark,
                    icon: Icons.savings,
                    isDeduction: true,
                  ),
                ],
                if (_wage.healthInsuranceDeduction > 0) ...[
                  Divider(height: 1, color: AppColors.grey100),
                  _buildWageLineItem(
                    context,
                    label: '건강보험',
                    amount: _wage.healthInsuranceDeduction,
                    color: AppColors.errorDark,
                    icon: Icons.favorite_border,
                    isDeduction: true,
                  ),
                ],
                if (_wage.ltcInsuranceDeduction > 0) ...[
                  Divider(height: 1, color: AppColors.grey100),
                  _buildWageLineItem(
                    context,
                    label: '장기요양보험',
                    amount: _wage.ltcInsuranceDeduction,
                    color: AppColors.errorDark,
                    icon: Icons.elderly,
                    isDeduction: true,
                  ),
                ],
                if (_wage.incomeTaxDeduction > 0) ...[
                  Divider(height: 1, color: AppColors.grey100),
                  _buildWageLineItem(
                    context,
                    label: '소득세·지방세',
                    amount: _wage.incomeTaxDeduction,
                    color: AppColors.errorDark,
                    icon: Icons.account_balance,
                    isDeduction: true,
                  ),
                ],
                if (_wage.retroactiveDeduction > 0) ...[
                  Divider(height: 1, color: AppColors.grey100),
                  _buildWageLineItem(
                    context,
                    label: '소급 공제 (1~7일분)',
                    amount: _wage.retroactiveDeduction,
                    color: AppColors.errorDark,
                    icon: Icons.history_outlined,
                    isDeduction: true,
                  ),
                ],
              ],
            ],
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),

        // 총 급여
        _buildTotalRow(context),
      ],
    );
  }

  Widget _buildTotalRow(BuildContext context) {
    final hasDeductions = _wage.taxDeductionType != InsuranceRateModel.typeNone &&
        _wage.totalInsuranceDeduction > 0;

    return Column(
      children: [
        // 실수령액 (또는 공제 없을 때 "총 급여")
        Container(
          padding: ResponsiveHelper.symmetricPadding(context, horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _headerColor.withValues(alpha: 0.12),
                _headerColor.withValues(alpha: 0.06),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _headerColor.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: _headerColor.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: ResponsiveHelper.iconSize(context, 18), color: _headerColor),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                hasDeductions ? '실수령액' : '총 급여',
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(fontWeight: FontWeight.bold, color: AppColors.grey800),
              ),
              const Spacer(),
              Text(
                FormatHelper.formatWage(
                    hasDeductions ? _wage.effectiveNetWage : _wage.totalAmount),
                style: ResponsiveHelper.titleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: _headerColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 계산 공식 안내 ────────────────────────────────────────────

  Widget _buildCalculationGuide(BuildContext context) {
    final isDaily = _wage.wageType == 'daily';
    final supplementWage = _supplementWage;
    final scheduledNetMins =
        (_wage.scheduledMinutes - widget.scheduledBreakMinutes).clamp(0, 9999);
    final unworkedMins =
        (scheduledNetMins - _wage.workMinutes).clamp(0, scheduledNetMins);
    final absenceDeduction = isDaily
        ? (_wage.baseWage - _wage.baseAmount).clamp(0, _wage.baseWage)
        : 0;

    final lines = <String>[];

    // ── 기본급 / 일급 ──
    if (isDaily) {
      if (absenceDeduction > 0) {
        final scheduledH = FormatHelper.formatCompactHours(scheduledNetMins);
        final unworkH = FormatHelper.formatCompactHours(unworkedMins);
        lines.add('일급(전체) = ${FormatHelper.formatWage(_wage.baseWage)}');
        lines.add(
            '미근무 공제 = ${FormatHelper.formatWage(_wage.baseWage)} × $unworkH / $scheduledH = -${FormatHelper.formatWage(absenceDeduction)}');
      } else {
        lines.add('일급 = ${FormatHelper.formatWage(_wage.baseWage)} (전일 근무)');
      }
    } else {
      // 시급제: 기본급은 정규 근무(연장 제외)만 포함
      final regularMins = _wage.workMinutes - _wage.overtimeMinutes;
      final regularH = FormatHelper.formatCompactHours(regularMins);
      lines.add(
          '기본급 = ${FormatHelper.formatWage(_wage.baseWage)}/h × $regularH = ${FormatHelper.formatWage(_wage.baseAmount)}');
    }

    // ── 조출/연장수당 (근로기준법 제56조: 1일 8h 초과분만 1.5배) ──
    if (_wage.overtimeAmount > 0) {
      final wageStr = FormatHelper.formatWage(supplementWage);
      final fEarlyMins = _wage.earlyArrivalMinutes;
      final fRegularMins = _wage.overtimeMinutes - fEarlyMins;
      final fEarlyAmt = _effectiveEarlyArrivalAmount(fEarlyMins);
      final fRegularAmt = _wage.overtimeAmount - fEarlyAmt;

      if (!isDaily) {
        // 시급제: overtimeMinutes는 이미 8h 초과분 → 모두 1.5배
        if (fEarlyMins > 0 && fEarlyAmt > 0) {
          lines.add('조출수당 = $wageStr/h × ${FormatHelper.formatCompactHours(fEarlyMins)} × 1.5 = ${FormatHelper.formatWage(fEarlyAmt)}');
        }
        if (fRegularMins > 0 && fRegularAmt > 0) {
          lines.add('연장수당 = $wageStr/h × ${FormatHelper.formatCompactHours(fRegularMins)} × 1.5 = ${FormatHelper.formatWage(fRegularAmt)}');
        }
      } else {
        // 일급제: 8h 초과 여부로 배율 분기
        final over8 = (_wage.workMinutes - WageCalculator.standardWorkMinutes).clamp(0, _wage.overtimeMinutes);
        final within8 = _wage.overtimeMinutes - over8;

        // 조출 공식
        if (fEarlyMins > 0 && fEarlyAmt > 0) {
          final earlyIn8 = min(fEarlyMins, within8);
          final h = FormatHelper.formatCompactHours(fEarlyMins);
          if (earlyIn8 >= fEarlyMins) {
            // 조출 전체 8h 이내 → 1.0배
            lines.add('조출수당 = $wageStr/h × $h × 1.0 = ${FormatHelper.formatWage(fEarlyAmt)}');
          } else if (earlyIn8 <= 0) {
            // 조출 전체 8h 초과 → 1.5배
            lines.add('조출수당 = $wageStr/h × $h × 1.5 = ${FormatHelper.formatWage(fEarlyAmt)}');
          } else {
            // 조출이 8h 이내/초과 혼합 → 금액만
            lines.add('조출수당 ($h) = ${FormatHelper.formatWage(fEarlyAmt)}');
          }
        }

        // 연장 공식
        if (fRegularMins > 0 && fRegularAmt > 0) {
          final earlyIn8 = min(fEarlyMins, within8);
          final regularIn8 = (within8 - earlyIn8).clamp(0, fRegularMins).toInt();
          final regularOver8 = fRegularMins - regularIn8;

          if (regularOver8 <= 0) {
            lines.add('연장수당 = $wageStr/h × ${FormatHelper.formatCompactHours(fRegularMins)} × 1.0 = ${FormatHelper.formatWage(fRegularAmt)}');
          } else if (regularIn8 <= 0) {
            lines.add('연장수당 = $wageStr/h × ${FormatHelper.formatCompactHours(fRegularMins)} × 1.5 = ${FormatHelper.formatWage(fRegularAmt)}');
          } else {
            // 8h 이내분 1배 + 초과분 1.5배 분리
            final aw = (regularIn8 * supplementWage / 60).round();
            final ao = (regularOver8 * supplementWage * 1.5 / 60).round();
            lines.add('연장수당 (8h이내 ${FormatHelper.formatCompactHours(regularIn8)}) = $wageStr/h × 1.0 = ${FormatHelper.formatWage(aw)}');
            lines.add('연장수당 (8h초과 ${FormatHelper.formatCompactHours(regularOver8)}) = $wageStr/h × 1.5 = ${FormatHelper.formatWage(ao)}');
          }
        }
      }
    }

    // ── 야간수당 ──
    if (_wage.nightAmount > 0) {
      final h = FormatHelper.formatCompactHours(_wage.nightMinutes);
      lines.add(
          '야간수당 = ${FormatHelper.formatWage(supplementWage)}/h × $h × 0.5 = ${FormatHelper.formatWage(_wage.nightAmount)}');
    }


    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.calculate_outlined,
              color: AppColors.infoDark,
              size: ResponsiveHelper.iconSize(context, 16)),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '급여 계산 공식',
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                    color: AppColors.infoDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                ...lines.map(
                  (line) => Padding(
                    padding: EdgeInsets.only(
                        top: ResponsiveHelper.spacing(context, 2)),
                    child: Text(
                      '• $line',
                      style: ResponsiveHelper.tinyStyle(context).copyWith(
                        color: AppColors.infoDark,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 수정 섹션 (에디터블 모드) ─────────────────────────────────

  Widget _buildEditSection(BuildContext context, ThemeData theme) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

        // 추가수당 / 추가공제 — 나란히 배치
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(context, '추가수당'),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  TextField(
                    controller: _additionalController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [NumberInputFormatter()],
                    style: ResponsiveHelper.bodyStyle(context).copyWith(color: AppColors.grey800),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
                      suffixText: '원',
                      suffixStyle: ResponsiveHelper.bodyStyle(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                        borderSide: const BorderSide(color: AppColors.grey300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                        borderSide: const BorderSide(color: AppColors.grey300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                        borderSide: BorderSide(color: AppColors.infoDark),
                      ),
                      contentPadding: ResponsiveHelper.symmetricPadding(
                          context, horizontal: 12, vertical: 12),
                    ),
                    onChanged: (_) => _updateWage(),
                  ),
                ],
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(context, '추가공제'),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  TextField(
                    controller: _deductionController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [NumberInputFormatter()],
                    style: ResponsiveHelper.bodyStyle(context).copyWith(color: AppColors.grey800),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
                      suffixText: '원',
                      suffixStyle: ResponsiveHelper.bodyStyle(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                        borderSide: const BorderSide(color: AppColors.grey300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                        borderSide: const BorderSide(color: AppColors.grey300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                        borderSide: BorderSide(color: AppColors.errorDark),
                      ),
                      contentPadding: ResponsiveHelper.symmetricPadding(
                          context, horizontal: 12, vertical: 12),
                    ),
                    onChanged: (_) => _updateWage(),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),

        // 메모
        _buildSectionTitle(context, '메모'),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        TextField(
          controller: _memoController,
          maxLines: 2,
          style: ResponsiveHelper.bodyStyle(context).copyWith(color: AppColors.grey800),
          decoration: InputDecoration(
            hintText: '메모 입력 (선택)',
            hintStyle: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
            ),
            contentPadding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
          ),
        ),
      ],
    ),
    );
  }

  // ── 하단 버튼 ─────────────────────────────────────────────────

  Widget _buildBottomButtons(BuildContext context, ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(ResponsiveHelper.spacing(context, 20)),
          bottomRight: Radius.circular(ResponsiveHelper.spacing(context, 20)),
        ),
      ),
      child: _buildMainButtons(context, theme),
    );
  }

  Widget _buildMainButtons(BuildContext context, ThemeData theme) {
    switch (widget.mode) {
      case WageDialogMode.pending:
        return _buildTwoButtons(context, theme,
            cancelLabel: '취소',
            confirmLabel: '급여 확정',
            confirmColor: AppColors.warning,
            confirmIcon: Icons.check,
            onConfirm: () => _onAction('confirm'));
      case WageDialogMode.calculated:
        return _buildTwoButtons(context, theme,
            cancelLabel: '취소',
            confirmLabel: '저장',
            confirmColor: theme.primaryColor,
            confirmIcon: Icons.save,
            onConfirm: () => _onAction('update'));
      case WageDialogMode.editOnly:
        return _buildTwoButtons(context, theme,
            cancelLabel: '취소',
            confirmLabel: '저장',
            confirmColor: AppColors.info,
            confirmIcon: Icons.save,
            onConfirm: () => _onAction('update'));
      case WageDialogMode.confirmed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 임금명세서 보기 버튼 (wageDetail 있을 때만)
            if (widget.attendance.wageDetail != null)
              OutlinedButton.icon(
                onPressed: () => _openPayslip(context),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('임금명세서 보기'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.infoDark,
                  side: const BorderSide(color: AppColors.info),
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 12)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          ResponsiveHelper.spacing(context, 12))),
                ),
              ),
            if (widget.attendance.wageDetail != null)
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 14)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          ResponsiveHelper.spacing(context, 12))),
                ),
                child: Text('확인',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildTwoButtons(
    BuildContext context,
    ThemeData theme, {
    required String cancelLabel,
    required String confirmLabel,
    required Color confirmColor,
    required IconData confirmIcon,
    required VoidCallback onConfirm,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.grey600,
              side: BorderSide(color: theme.dividerColor),
              padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 14)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12))),
            ),
            child: Text(cancelLabel, style: ResponsiveHelper.bodyStyle(context)),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: onConfirm,
            icon: Icon(confirmIcon, size: ResponsiveHelper.iconSize(context, 20)),
            label: Text(
              confirmLabel,
              style: ResponsiveHelper.bodyStyle(context)
                  .copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 14)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12))),
            ),
          ),
        ),
      ],
    );
  }

  // ── 헬퍼 위젯 ────────────────────────────────────────────────

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: _headerColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Text(
          title,
          style: ResponsiveHelper.bodyStyle(context)
              .copyWith(fontWeight: FontWeight.bold, color: AppColors.grey800),
        ),
      ],
    );
  }

  Widget _buildInfoChip(
    BuildContext context,
    IconData icon,
    String text,
    Color color,
    Color bgColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 11), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            text,
            style: ResponsiveHelper.tinyStyle(context, color: color)
                .copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeStatBox(
    BuildContext context,
    String label,
    String value,
    Color color,
    Color bgColor,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label,
              style: ResponsiveHelper.tinyStyle(context,
                  color: color.withValues(alpha: 0.8))),
          SizedBox(height: ResponsiveHelper.spacing(context, 2)),
          Text(
            value,
            style: ResponsiveHelper.bodyStyle(context)
                .copyWith(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildWageLineItem(
    BuildContext context, {
    required String label,
    String? subLabel,
    required int amount,
    required Color color,
    required IconData icon,
    bool isFirst = false,
    bool isDeduction = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: ResponsiveHelper.iconSize(context, 14), color: color),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: ResponsiveHelper.bodyStyle(context)
                        .copyWith(color: AppColors.grey800)),
                if (subLabel != null)
                  Text(subLabel,
                      style: ResponsiveHelper.tinyStyle(context, color: color)
                          .copyWith(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Text(
            '${isDeduction ? '-' : ''}${FormatHelper.formatWage(amount)}',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
