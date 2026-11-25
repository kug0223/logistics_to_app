// lib/widgets/dialogs/wage/wage_detail_dialog.dart

import 'package:flutter/material.dart';

import '../../../models/core/application_model.dart';
import '../../../screens/payroll/payslip_view_screen.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/insurance_rate_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/wage_detail_model.dart';
import '../../../services/tax_deduction_service.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/text_layout.dart';
import '../../../utils/wage_calculation_lines.dart';
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
  /// [PAYROLL-DETAIL.32] user 를 읽지 못했을 때(관리자는 users GET 권한이 없다) 머리말에 쓸 이름.
  ///   호출부가 이미 아는 이름을 넘긴다 — 없으면 예전처럼 '이름 없음'.
  final String? fallbackName;

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
    this.fallbackName,
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
    String? fallbackName,
  }) {
    return showDialog<WageDialogResult>(
      context: context,
      barrierDismissible: false,
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
        fallbackName: fallbackName,
      ),
    );
  }

  @override
  State<WageDetailDialog> createState() => _WageDetailDialogState();
}

class _WageDetailDialogState extends State<WageDetailDialog> {
  late WageDetailModel _wage;
  bool _isActing = false;
  bool _isDeductionExpanded = false;
  bool _isGuideExpanded = false;
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

  /// [.82-4] daily_auto_8(8일 이상 근무 시 4대보험 소급) 계산 확정분은 금액을 정정하지 않는다 — 메모만.
  ///   순번·소급분이 그 달 다른 근무와 묶인 계산이라 하루 정정으로 맞출 수 없다(82_audit_04). 서버도 같은 규칙으로 거절한다.
  ///   미확정(pending)은 계산 확정 경로라 해당하지 않는다.
  bool get _amountLocked =>
      (widget.mode == WageDialogMode.calculated || widget.mode == WageDialogMode.editOnly) &&
      widget.wage.taxDeductionType == InsuranceRateModel.typeDailyAuto8;

  void _updateWage() {
    if (_amountLocked) {
      setState(() => _wage = widget.wage.copyWith(memo: _memoController.text.trim()));
      return;
    }
    final additional =
        (int.tryParse(_additionalController.text.replaceAll(',', '')) ?? 0).abs();
    final deduction =
        (int.tryParse(_deductionController.text.replaceAll(',', '')) ?? 0).abs();
    final newTotal = _wage.baseAmount + _wage.overtimeAmount + _wage.nightAmount +
        additional - deduction + _wage.weeklyHolidayAmount;
    setState(() {
      // [.82 F1] 추가수당·추가공제는 세전(사용자 결정 11-04) — 새 총액으로 세금·보험을 다시 계산한다.
      //   예전에는 "보험 공제는 기본급 기준 확정"이라며 공제를 유지해 추가수당만큼 원천징수가 빠졌다.
      //   규칙은 서버 callableUpdateWageDetail 과 같고(TaxDeductionService.recomputeForAdjustment),
      //   저장 뒤에는 서버가 돌려준 값으로 바뀐다.
      _wage = TaxDeductionService.recomputeForAdjustment(
        stored: widget.wage,
        edited: _wage.copyWith(
          additionalAmount: additional,
          deductionAmount: deduction,
          totalAmount: newTotal,
          memo: _memoController.text.trim().isNotEmpty
              ? _memoController.text.trim()
              : null,
        ),
        workYear: TaxDeductionService.kstWorkYear(widget.attendance.workDate),
        calculatedAdjustment: widget.mode != WageDialogMode.pending,
      );
    });
  }

  /// 무급 휴게시간 수정 bottom sheet — [Phase 3.1] applied + additional 분리 편집
  ///
  /// 기본 무급휴게(계약 내 실제 적용)와 추가 무급휴게(석식·야식 등)를 별도 선택.
  /// legacy 레코드도 effectiveAppliedScheduledBreak / effectiveAdditionalBreak getter로 초기화.
  /// 저장 시 breakdown이 보존되어 auditability 유지.
  void _showEditBreakSheet(BuildContext context) {
    final legalMax = WageCalculator.legalMaxBreakMinutes(_wage.actualMinutes);
    final scheduledBreak = _effectiveScheduledBreak; // TO 계약 기준값

    // 초기값: 현재 effective 값 (legacy도 getter로 추론)
    int selApplied = _wage.effectiveAppliedScheduledBreak;
    int selAdditional = _wage.effectiveAdditionalBreak;

    // 기본 휴게 프리셋: 0 ~ scheduledBreak 범위
    final appliedPresets = <int>[0];
    if (scheduledBreak >= 30 && !appliedPresets.contains(30)) appliedPresets.add(30);
    if (scheduledBreak >= 60 && !appliedPresets.contains(60)) appliedPresets.add(60);
    if (scheduledBreak > 0 && !appliedPresets.contains(scheduledBreak)) appliedPresets.add(scheduledBreak);
    appliedPresets.sort();

    const additionalPresets = [0, 30, 60, 90];

    DialogHelper.showSheet<void>(
      context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) {
          final totalBreak = selApplied + selAdditional;
          final isOver = legalMax > 0 && totalBreak > legalMax;
          return SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20, 20, 20,
                MediaQuery.of(ctx2).viewInsets.bottom + 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('무급 휴게시간 수정',
                      style: ResponsiveHelper.subtitleStyle(ctx2)
                          .copyWith(fontWeight: FontWeight.bold)),
                  SizedBox(height: ResponsiveHelper.spacing(ctx2, 6)),
                  // 법정 기준 안내
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: isOver ? AppColors.errorBg : AppColors.grey100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isOver ? Icons.warning_amber_outlined : Icons.info_outline,
                          size: ResponsiveHelper.iconSize(ctx2, 13),
                          color: isOver ? AppColors.errorDark : AppColors.grey600,
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(ctx2, 6)),
                        Expanded(
                          child: Text(
                            legalMax == 0
                                ? '4시간 미만 근무 — 법정 휴게 없음'
                                : '체류 ${FormatHelper.formatCompactHours(_wage.actualMinutes)} 기준  법정 최대: $legalMax분',
                            style: ResponsiveHelper.tinyStyle(ctx2,
                                color: isOver ? AppColors.errorDark : AppColors.grey700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(ctx2, 16)),
                  // ── 기본 무급휴게 (계약 범위 내) ──
                  if (scheduledBreak > 0) ...[
                    Text(
                      '기본 무급휴게  (계약 $scheduledBreak분 기준)',
                      style: ResponsiveHelper.smallStyle(ctx2, color: AppColors.textSecondary),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(ctx2, 8)),
                    Wrap(
                      spacing: ResponsiveHelper.spacing(ctx2, 8),
                      runSpacing: ResponsiveHelper.spacing(ctx2, 8),
                      children: appliedPresets.map((min) {
                        final isSelected = selApplied == min;
                        return GestureDetector(
                          onTap: () => setS(() => selApplied = min),
                          child: _buildBreakChip(ctx2, min, isSelected, isNone: min == 0),
                        );
                      }).toList(),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(ctx2, 14)),
                  ],
                  // ── 추가 무급휴게 (석식·야식 등) ──
                  Text('추가 무급휴게  (석식·야식 등)',
                      style: ResponsiveHelper.smallStyle(ctx2, color: AppColors.textSecondary)),
                  SizedBox(height: ResponsiveHelper.spacing(ctx2, 8)),
                  Wrap(
                    spacing: ResponsiveHelper.spacing(ctx2, 8),
                    runSpacing: ResponsiveHelper.spacing(ctx2, 8),
                    children: additionalPresets.map((min) {
                      final isSelected = selAdditional == min;
                      return GestureDetector(
                        onTap: () => setS(() => selAdditional = min),
                        child: _buildBreakChip(ctx2, min, isSelected, isNone: min == 0),
                      );
                    }).toList(),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(ctx2, 14)),
                  // ── 합계 ──
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.grey50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.grey200),
                    ),
                    child: Row(
                      children: [
                        Text('총 무급휴게',
                            style: ResponsiveHelper.smallStyle(ctx2, color: AppColors.grey600)
                                .copyWith(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text(
                          totalBreak == 0 ? '없음' : '$totalBreak분',
                          style: ResponsiveHelper.bodyStyle(ctx2).copyWith(
                            color: isOver ? AppColors.errorDark : AppColors.grey900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(ctx2, 16)),
                  // ── 적용 버튼 ──
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _applyBreakComponents(selApplied, selAdditional);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.spacing(ctx2, 12)),
                      ),
                      child: Text('적용',
                          style: ResponsiveHelper.bodyStyle(ctx2)
                              .copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 휴게 칩 빌더
  Widget _buildBreakChip(BuildContext ctx, int minutes, bool isSelected, {bool isNone = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.brand : AppColors.grey100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isSelected ? AppColors.brand : AppColors.grey200),
      ),
      child: Text(
        isNone ? '없음' : '$minutes분',
        style: ResponsiveHelper.smallStyle(ctx,
                color: isSelected ? Colors.white : AppColors.grey700)
            .copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  /// [Phase 3.1] breakdown 컴포넌트로 급여 재계산 — applied + additional 각각 보존
  ///
  /// 기존 _applyNewBreak(total) + clearBreakBreakdown() 패턴을 대체.
  /// applied와 additional을 명시적으로 copyWith에 전달하므로 breakdown auditability 유지.
  void _applyBreakComponents(int appliedScheduledBreak, int additionalBreak) {
    final checkIn = widget.attendance.checkIn;
    final checkOut = widget.attendance.checkOut;
    if (checkIn == null || checkOut == null) return;

    final currentDeduction = (int.tryParse(_deductionController.text.replaceAll(',', '')) ?? 0).abs();
    final newBreakMinutes = appliedScheduledBreak + additionalBreak;

    final recalculated = WageCalculator.calculate(
      wageType: _wage.wageType,
      baseWage: _wage.baseWage,
      workDate: widget.attendance.workDate,
      scheduledStart: widget.effStart ?? widget.app.startTime,
      scheduledEnd: widget.effEnd ?? widget.app.endTime,
      actualStart: checkIn,
      actualEnd: checkOut,
      breakMinutes: newBreakMinutes,
      scheduledBreakMinutes: _effectiveScheduledBreak,
      nightAllowanceApplied: _wage.nightAllowanceApplied,
      nightIncluded: widget.nightIncluded,
      additionalAmount: _wage.additionalAmount,
      memo: _wage.memo,
      baseHourlyWage: widget.baseHourlyWage,
    );

    setState(() {
      // [Phase 3.1] breakdown 보존: applied + additional 각각 명시적으로 저장
      // legacy record도 이 편집을 거치면 신규 breakdown 형식으로 upgrade됨
      // [.82 F1] 휴게 변경도 총액이 바뀌면 세금·보험을 다시 계산한다(서버와 같은 규칙).
      //   주휴수당은 WageCalculator 가 계산하지 않아(수동 입력 정책) 새 모델에서 0 이 됐다 — 저장값을 이어 붙인다.
      _wage = TaxDeductionService.recomputeForAdjustment(
        stored: widget.wage,
        edited: recalculated.copyWith(
          appliedScheduledBreakMinutes: appliedScheduledBreak,
          additionalBreakMinutes: additionalBreak,
          // 수동 공제 유지
          deductionAmount: currentDeduction,
          weeklyHolidayAmount: _wage.weeklyHolidayAmount,
          totalAmount: recalculated.totalAmount - currentDeduction + _wage.weeklyHolidayAmount,
          // 계산 타임스탬프 유지
          calculatedBy: _wage.calculatedBy,
          calculatedAt: _wage.calculatedAt,
        ),
        workYear: TaxDeductionService.kstWorkYear(widget.attendance.workDate),
        calculatedAdjustment: widget.mode != WageDialogMode.pending,
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
        // [FC-07 FIX] 수정 즉시 pop — pop 전 unfocus
        FocusManager.instance.primaryFocus?.unfocus();
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
        confirmMessage = '$userName의 급여 확정을 되돌리시겠습니까?\n\n입력 오류 수정이 필요한 경우에 사용하세요.\n미확정 상태로 돌아가며, 수정 후 재확정이 필요합니다.';
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
        // [FC-07 FIX] confirm/cancel/final_confirm 성공 pop — pop 전 unfocus
        FocusManager.instance.primaryFocus?.unfocus();
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

  // _effectiveEarlyArrivalAmount 제거 — wage_calculation_lines.dart로 이전

  /// scheduledBreakMinutes=0으로 저장된 레코드(WorkDetail 조회 실패·구형 레코드) 대비 폴백.
  ///
  /// 정상 레코드: _wage.scheduledBreakMinutes = TO 정의 휴게시간 (예: 60)
  /// 구형/버그 레코드: scheduledBreakMinutes 미저장 → 0 → breakMinutes(실제 휴게)로 대체
  ///
  /// ⚠️ 급여 재계산(_applyNewBreak) 시에도 동일 값을 사용해 scheduledBreakMinutes를
  ///    올바르게 복원한다 — 이후 재계산부터는 _wage.scheduledBreakMinutes가 정상 저장됨.
  int get _effectiveScheduledBreak =>
      _wage.scheduledBreakMinutes > 0
          ? _wage.scheduledBreakMinutes
          : _wage.breakMinutes;

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
        (_wage.scheduledMinutes - _effectiveScheduledBreak).clamp(1, 9999);
    return (_wage.baseWage / schedNetMins * 60).round();
  }

  // ── BUILD ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.user?.name ??
        ((widget.fallbackName?.isNotEmpty ?? false) ? widget.fallbackName! : '이름 없음');


    // [FC-07 FIX] DialogFocusSafeArea — deactivate()에서 unfocus하여
    // _dependents.isEmpty assertion 크래시 방지
    return DialogFocusSafeArea(
      child: Dialog(
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
                    _buildMetaRow(context),             // 메타 (사업장·업무유형·이체일)
                    SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                    _buildWorkTimeCard(context),        // C. 근무정보 (행 구조)
                    SizedBox(height: ResponsiveHelper.spacing(context, 14)),
                    _buildPaySection(context),          // D+E. 급여명세+실수령액 통합
                    SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                    _buildCalculationGuide(context),   // F.계산기준
                    if (_isEditable) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      _buildEditSection(context, theme), // G.관리자편집
                    ],
                  ],
                ),
              ),
            ),
            _buildBottomButtons(context, theme),
          ],
        ),
      ),
    ),   // Dialog
    );   // DialogFocusSafeArea
  }

  // ── 헤더 ─────────────────────────────────────────────────────

  // A. 헤더 — "급여 명세" 제목 / "이름 · 날짜" / 모드 상태 배지 / 닫기
  Widget _buildHeader(BuildContext context, String name) {
    // [PAYROLL-DETAIL.32] workDate 는 KST 자정 instant — 기기 시간대(GMT 등)로 읽으면 하루 앞 날짜였다.
    final d = FormatHelper.toKstDate(widget.attendance.workDate);
    final dateStr =
        '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
    return Container(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 8),
        ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(ResponsiveHelper.spacing(context, 20)),
          topRight: Radius.circular(ResponsiveHelper.spacing(context, 20)),
        ),
        border: const Border(bottom: BorderSide(color: AppColors.grey200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 모드 컬러 accent bar
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: _headerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '급여 명세',
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold, color: AppColors.grey900),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                // [DU1 후속41 B2-W] 320·2.0 에서 상태 배지가 줄지 않아 32px 넘쳤고, 옆 '이름 · 날짜'(Flexible)가 0 폭으로 사라졌다.
                //   Row → Wrap: 좁으면 배지가 다음 줄로 내려가고 이름·날짜는 낱말 단위로 보인다(말줄임 없음). 넓은 폭은 한 줄 그대로.
                Wrap(
                  spacing: ResponsiveHelper.spacing(context, 6),
                  runSpacing: ResponsiveHelper.spacing(context, 3),
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      TextLayout.phrases('$name · $dateStr'),
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: _headerColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _headerSubtitle,
                        style: ResponsiveHelper.tinyStyle(context, color: _headerColor)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(context);
            },
            icon: Icon(Icons.close, color: AppColors.textSecondary,
                size: ResponsiveHelper.iconSize(context, 20)),
            padding: EdgeInsets.zero,
            // [DU1 후속41 B2-W] 실측 IconButton 외곽 40×40(compact) — 공통 기준 터치 48×48. 아이콘 크기는 그대로
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ],
      ),
    );
  }

  // ── 메타정보 · 근무정보 섹션 ─────────────────────────────────

  /// B. compact 메타 텍스트 (사업장·업무유형·임금유형·이체일 한 줄)
  Widget _buildMetaRow(BuildContext context) {
    final parts = <String>[];
    if (widget.businessName != null && widget.businessName!.isNotEmpty) {
      parts.add(widget.businessName!);
    }
    parts.add(widget.app.selectedWorkType);
    if (widget.shiftType != null) parts.add(widget.shiftType!);
    parts.add(_wage.wageTypeLabel);

    final transferDate = widget.attendance.transferDate;
    final transferStr = _isTransferred
        ? (transferDate != null
            ? '이체일 ${transferDate.month}.${transferDate.day}'
            : '이체 완료')
        : null;

    return Row(
      children: [
        Flexible(
          child: Text(
            parts.join(' · '),
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (transferStr != null) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Text('·', style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey300)),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Icon(Icons.account_balance,
              size: ResponsiveHelper.iconSize(context, 10), color: AppColors.infoDark),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Flexible(
            child: Text(
              transferStr,
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.infoDark)
                  .copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  /// C. 근무정보 — 계약시간/실제 출퇴근/무급휴게/실근무 위계 구조
  Widget _buildWorkTimeCard(BuildContext context) {
    final legalMax = WageCalculator.legalMaxBreakMinutes(_wage.actualMinutes);
    final isBreakExceeded = _wage.breakMinutes > legalMax;
    final scheduledNetMins =
        (_wage.scheduledMinutes - _effectiveScheduledBreak).clamp(0, 9999);
    final unworkedMins = (scheduledNetMins - _wage.workMinutes).clamp(0, scheduledNetMins);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        children: [
          // 계약시간 — 보조 정보 (secondary)
          _buildTimeInfoRow(
            context,
            label: '계약시간',
            labelColor: AppColors.textSecondary,
            child: Text(
              '${widget.effStart ?? widget.app.startTime}  ~  ${widget.effEnd ?? widget.app.endTime}',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 7)),
          // 실제 출퇴근 — 핵심 근태 원본 (primary)
          _buildTimeInfoRow(
            context,
            label: '실제 출퇴근',
            labelColor: AppColors.grey700,
            // [DU1 후속41 B2-W] 출근·퇴근 한 쌍이 좁은 폭에서 넘쳤다 — Wrap 으로 줄바꿈 허용(순서·아이콘·값 그대로)
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: ResponsiveHelper.spacing(context, 2),
              children: [
                Icon(Icons.login_outlined,
                    size: ResponsiveHelper.iconSize(context, 12),
                    color: AppColors.successDark),
                SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                Text(
                  widget.attendance.checkIn ?? '-',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey800)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                Icon(Icons.logout_outlined,
                    size: ResponsiveHelper.iconSize(context, 12),
                    color: AppColors.warningDark),
                SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                Text(
                  widget.attendance.checkOut ?? '-',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey800)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (_wage.breakMinutes > 0) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 7)),
            // [Phase 3.1] 무급휴게 — breakdown 있을 때 기본/추가 분리 표시
            _buildTimeInfoRow(
              context,
              label: '무급휴게',
              labelColor: AppColors.textSecondary,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_wage.hasBreakBreakdown) ...[
                          // 기본 휴게
                          Text(
                            _wage.hasReducedScheduledBreak
                                ? '기본 ${_formatKoreanHours(_wage.effectiveAppliedScheduledBreak)} (계약 ${_formatKoreanHours(_wage.scheduledBreakMinutes)}에서 조정)'
                                : '기본 ${_formatKoreanHours(_wage.effectiveAppliedScheduledBreak)}',
                            style: ResponsiveHelper.smallStyle(
                              context,
                              color: isBreakExceeded ? AppColors.errorDark : AppColors.grey600,
                            ),
                          ),
                          if (_wage.effectiveAdditionalBreak > 0)
                            Padding(
                              padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 2)),
                              child: Text(
                                '추가 ${_formatKoreanHours(_wage.effectiveAdditionalBreak)}',
                                style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary),
                              ),
                            ),
                        ] else ...[
                          // 구형 레코드 — 합계만 표시
                          Text(
                            _formatKoreanHours(_wage.breakMinutes),
                            style: ResponsiveHelper.smallStyle(
                              context,
                              color: isBreakExceeded ? AppColors.errorDark : AppColors.grey600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_isEditable && !_amountLocked) ...[
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    // [DU1 후속42 B2-W2] 실측 클릭 외곽 10.8×10.8(392·1.0)·10.2(320·2.0) — 터치 48. 아이콘 크기는 그대로, 누르는 영역만 48×48
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showEditBreakSheet(context),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: Icon(Icons.edit_outlined,
                              size: ResponsiveHelper.iconSize(context, 12),
                              color: isBreakExceeded ? AppColors.errorDark : AppColors.textTertiary),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          // 실근무 구분선 — 결과값 시각적 분리
          Padding(
            padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 6)),
            child: const Divider(height: 1, color: AppColors.grey200),
          ),
          // 실근무 — 최종 결과값 (가장 강한 emphasis)
          _buildTimeInfoRow(
            context,
            label: '실근무',
            labelColor: AppColors.grey800,
            child: Text(
              _formatKoreanHours(_wage.workMinutes),
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey900)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (unworkedMins > 0 && _wage.wageType == 'daily') ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 7)),
            _buildTimeInfoRow(
              context,
              label: '미근무',
              child: Text(
                _formatKoreanHours(unworkedMins),
                style: ResponsiveHelper.smallStyle(context, color: AppColors.errorDark)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
          if (_wage.overtimeMinutes > 0) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 7)),
            _buildTimeInfoRow(
              context,
              label: '연장',
              child: Text(
                _formatKoreanHours(_wage.overtimeMinutes),
                style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
          if (_wage.nightMinutes > 0) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 7)),
            _buildTimeInfoRow(
              context,
              label: '야간',
              child: Text(
                _formatKoreanHours(_wage.nightMinutes),
                style: ResponsiveHelper.smallStyle(context, color: AppColors.purpleDark)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeInfoRow(
    BuildContext context, {
    required String label,
    required Widget child,
    bool isHighlight = false,
    Color? labelColor,
  }) {
    final resolvedLabelColor = labelColor ??
        (isHighlight ? AppColors.grey700 : AppColors.textTertiary);
    final labelText = Text(
      TextLayout.keepWords(label),
      style: ResponsiveHelper.tinyStyle(
        context,
        color: resolvedLabelColor,
      ).copyWith(fontWeight: FontWeight.w600),
    );
    // [DU1 후속41 B2-W] 320·2.0 에서 고정 폭 70 레이블이 '계약시|간'·'무급휴|게' 로 끊기고 옆 값이 넘쳤다.
    //   글자 배율이 클 때(>1.5)만 레이블을 값 위 줄로 올린다 — 기본 배율은 기존 70 폭 한 줄 그대로.
    if (MediaQuery.textScalerOf(context).scale(1) > 1.5) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          labelText,
          SizedBox(height: ResponsiveHelper.spacing(context, 2)),
          child,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 70, child: labelText),
        Expanded(child: child),
      ],
    );
  }

  /// 분을 한국어 시간 표시로 변환 — UI 표시 전용, 데이터/계산 변경 없음
  /// 60분 → '1시간', 90분 → '1.5시간'
  String _formatKoreanHours(int mins) {
    if (mins <= 0) return '0시간';
    if (mins < 60) return '$mins분';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '$h시간' : '$h시간 $m분';
  }

  // ── 급여명세 + 공제 + 실수령액 (단일 카드) ─────────────────────

  /// D+E. 지급 항목·공제·실수령액을 하나의 카드 surface에 통합
  /// 공제 row는 탭하면 같은 카드 안에서 상세 항목 확장
  Widget _buildPaySection(BuildContext context) {
    final isDaily = _wage.wageType == 'daily';
    final workStr = FormatHelper.formatCompactHours(_wage.workMinutes);
    final nightStr = _wage.nightMinutes > 0
        ? FormatHelper.formatCompactHours(_wage.nightMinutes)
        : null;

    final absenceDeduction = isDaily
        ? (_wage.baseWage - _wage.baseAmount).clamp(0, _wage.baseWage)
        : 0;
    final absenceDeductionStr = absenceDeduction > 0
        ? FormatHelper.formatCompactHours(
            (_wage.scheduledMinutes - _effectiveScheduledBreak - _wage.workMinutes)
                .clamp(0, _wage.scheduledMinutes))
        : null;

    final hasDeductions = _wage.taxDeductionType != InsuranceRateModel.typeNone &&
        _wage.totalInsuranceDeduction > 0;
    final totalDeduction = _wage.totalInsuranceDeduction;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 섹션 헤더 + 통상시급 배지
        Row(
          children: [
            _buildSectionTitle(context, '급여'),
            const Spacer(),
            if (_wage.overtimeAmount > 0 || _wage.nightAmount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.grey200),
                ),
                child: Text(
                  '통상시급 ${FormatHelper.formatWage(_supplementWage)}',
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),

        // 급여 카드 (지급항목 + 공제 요약/상세 — 실수령액 제외)
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.grey200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // ── 지급 항목들 ──────────────────────────────────
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
                const Divider(height: 1, color: AppColors.grey100),
                _buildWageLineItem(context,
                    label: '미근무 공제',
                    subLabel: absenceDeductionStr,
                    amount: absenceDeduction,
                    color: AppColors.errorDark,
                    icon: Icons.remove_circle_outline,
                    isDeduction: true),
              ],
              // Phase 7.1: canonical extra-work breakdown
              if (_wage.hasCanonicalExtraWorkBreakdown && (_wage.contractExcessMinutes ?? 0) > 0) ...[
                const Divider(height: 1, color: AppColors.grey100),
                // Phase 7.1: overtimeAmount=0이면 "추가 근무수당 0원" 표시 생략 (시간 breakdown은 유지)
                if (_wage.overtimeAmount > 0)
                  _buildWageLineItem(context,
                      label: '연장 근무수당',
                      subLabel: FormatHelper.formatCompactHours(_wage.contractExcessMinutes!),
                      amount: _wage.overtimeAmount,
                      color: AppColors.warningDark,
                      icon: Icons.trending_up),
                if (_wage.extraWork1xMinutes > 0)
                  Padding(
                    padding: EdgeInsets.only(
                      left: ResponsiveHelper.spacing(context, 52),
                      right: ResponsiveHelper.spacing(context, 14),
                      bottom: ResponsiveHelper.spacing(context, 8),
                    ),
                    child: Row(
                      children: [
                        Text('· 계약시간 초과 · 1배',
                            style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary)),
                        const Spacer(),
                        Text(FormatHelper.formatCompactHours(_wage.extraWork1xMinutes),
                            style: ResponsiveHelper.tinyStyle(context, color: AppColors.warningDark)
                                .copyWith(fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                if (_wage.extraWork15xMinutes > 0)
                  Padding(
                    padding: EdgeInsets.only(
                      left: ResponsiveHelper.spacing(context, 52),
                      right: ResponsiveHelper.spacing(context, 14),
                      bottom: ResponsiveHelper.spacing(context, 8),
                    ),
                    child: Row(
                      children: [
                        Text('· 8시간 초과 · 1.5배',
                            style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary)),
                        const Spacer(),
                        Text(FormatHelper.formatCompactHours(_wage.extraWork15xMinutes),
                            style: ResponsiveHelper.tinyStyle(context, color: AppColors.warningDark)
                                .copyWith(fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
              ] else if (_wage.overtimeAmount > 0 || _wage.overtimeMinutes > 0) ...[
                // legacy path: label만 변경, breakdown 없음
                const Divider(height: 1, color: AppColors.grey100),
                _buildWageLineItem(context,
                    label: '연장 근무수당',
                    subLabel: _wage.overtimeMinutes > 0
                        ? FormatHelper.formatCompactHours(_wage.overtimeMinutes)
                        : null,
                    amount: _wage.overtimeAmount,
                    color: AppColors.warningDark,
                    icon: Icons.trending_up),
              ],
              if (_wage.nightAmount > 0) ...[
                const Divider(height: 1, color: AppColors.grey100),
                _buildWageLineItem(context,
                    label: '야간수당',
                    subLabel: nightStr,
                    amount: _wage.nightAmount,
                    color: AppColors.purpleDark,
                    icon: Icons.nights_stay_outlined),
              ],
              if (_wage.additionalAmount > 0) ...[
                const Divider(height: 1, color: AppColors.grey100),
                _buildWageLineItem(context,
                    label: '추가수당',
                    amount: _wage.additionalAmount,
                    color: AppColors.infoDark,
                    icon: Icons.add_circle_outline),
              ],
              if (_wage.deductionAmount > 0) ...[
                const Divider(height: 1, color: AppColors.grey100),
                _buildWageLineItem(context,
                    label: '추가공제',
                    amount: _wage.deductionAmount,
                    color: AppColors.errorDark,
                    icon: Icons.remove_circle_outline,
                    isDeduction: true),
              ],
              if (_wage.weeklyHolidayAmount > 0) ...[
                const Divider(height: 1, color: AppColors.grey100),
                _buildWageLineItem(context,
                    label: '주휴수당',
                    amount: _wage.weeklyHolidayAmount,
                    color: AppColors.successDark,
                    icon: Icons.event_available_outlined),
              ],

              // ── 공제 row (4대보험, 탭 → 확장) ─────────────
              if (hasDeductions) ...[
                const Divider(height: 1, color: AppColors.grey200),
                GestureDetector(
                  onTap: () =>
                      setState(() => _isDeductionExpanded = !_isDeductionExpanded),
                  child: Container(
                    color: Colors.transparent,
                    // [DU1 후속42 B2-W2] 실측 펼침 외곽 332.4×38.8(392·1.0) — 터치 48. 세로 최소만 늘리고 내용은 가운데
                    constraints: const BoxConstraints(minHeight: 48),
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 14),
                      vertical: ResponsiveHelper.spacing(context, 11),
                    ),
                    // [DU1 후속42 B2-W2] 320·2.0 '공제 (3.3% / 원천징 / 수)' — 금액·화살표가 폭을 가져가 레이블 칸이 좁았다.
                    //   폭/글자 배율이 좁을 때만 [아이콘·레이블·화살표] 한 줄 + 금액 다음 줄 오른쪽. 넓은 폭은 기존 한 줄.
                    child: LayoutBuilder(builder: (context, constraints) {
                      final icon = Icon(Icons.remove_circle_outline,
                          size: ResponsiveHelper.iconSize(context, 13),
                          color: AppColors.textSecondary);
                      // [DU1-B2] Text+Spacer 는 320dp·1.3 / 392dp·2.0 에서 넘쳤다(Spacer 는 flex 가 아니다) — 라벨이 줄바꿈, 금액은 고정
                      final label = Expanded(
                        child: Text(
                          // [DU1 후속41 B2-W] 320·2.0 '원천징|수)' 끊김 — 단어 단위
                          TextLayout.keepWords('공제 (${_wage.taxDeductionLabel})'),
                          style: ResponsiveHelper.smallStyle(
                                  context, color: AppColors.grey600)
                              .copyWith(fontWeight: FontWeight.w500),
                        ),
                      );
                      final amount = Text(
                        '- ${FormatHelper.formatWage(totalDeduction)}',
                        style: ResponsiveHelper.smallStyle(
                                context, color: AppColors.errorDark)
                            .copyWith(fontWeight: FontWeight.w700),
                      );
                      final arrow = Icon(
                        _isDeductionExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: AppColors.textTertiary,
                        size: ResponsiveHelper.iconSize(context, 16),
                      );
                      final narrow = constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) < 260;
                      if (!narrow) {
                        return Row(children: [
                          icon,
                          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                          label,
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          amount,
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          arrow,
                        ]);
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(children: [
                            icon,
                            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                            label,
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            arrow,
                          ]),
                          Align(alignment: Alignment.centerRight, child: amount),
                        ],
                      );
                    }),
                  ),
                ),
                // 공제 상세 항목 (펼침 시)
                if (_isDeductionExpanded) ...[
                  if (_wage.employmentInsuranceDeduction > 0) ...[
                    const Divider(height: 1, color: AppColors.grey100),
                    _buildDeductionDetailItem(context, '고용보험',
                        _wage.employmentInsuranceDeduction, Icons.work_outline),
                  ],
                  if (_wage.nationalPensionDeduction > 0) ...[
                    const Divider(height: 1, color: AppColors.grey100),
                    _buildDeductionDetailItem(context, '국민연금',
                        _wage.nationalPensionDeduction, Icons.savings),
                  ],
                  if (_wage.healthInsuranceDeduction > 0) ...[
                    const Divider(height: 1, color: AppColors.grey100),
                    _buildDeductionDetailItem(context, '건강보험',
                        _wage.healthInsuranceDeduction, Icons.favorite_border),
                  ],
                  if (_wage.ltcInsuranceDeduction > 0) ...[
                    const Divider(height: 1, color: AppColors.grey100),
                    _buildDeductionDetailItem(context, '장기요양보험',
                        _wage.ltcInsuranceDeduction, Icons.elderly),
                  ],
                  if (_wage.incomeTaxDeduction > 0) ...[
                    const Divider(height: 1, color: AppColors.grey100),
                    _buildDeductionDetailItem(context, '소득세·지방세',
                        _wage.incomeTaxDeduction, Icons.account_balance),
                  ],
                  if (_wage.retroactiveDeduction > 0) ...[
                    const Divider(height: 1, color: AppColors.grey100),
                    _buildDeductionDetailItem(context, '소급 공제 (1~7일분)',
                        _wage.retroactiveDeduction, Icons.history_outlined),
                  ],
                ],
              ],

            ],
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),

        // ── 실수령액 히어로 (급여 카드 밖, 독립 카드) ──────────
        // ⚠️ effectiveNetWage 사용 — UI 재계산 금지
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 16),
          ),
          decoration: BoxDecoration(
            color: AppColors.brandSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          // [DU1-B2] Row+Spacer 는 320dp·1.3 / 392dp·2.0 에서 금액(26sp)이 12~67px 넘쳤다 — 양 끝 Wrap, 금액은 줄이지 않고 다음 줄로
          child: SizedBox(
            width: double.infinity, // Wrap 은 내용 폭만 잡는다 — 양 끝 정렬을 위해 전폭
            child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: ResponsiveHelper.spacing(context, 4),
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: AppColors.brand),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                hasDeductions ? '실수령액' : '총 급여',
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(fontWeight: FontWeight.w700, color: AppColors.brand),
              ),
              ]),
              Text(
                FormatHelper.formatWage(
                    hasDeductions ? _wage.effectiveNetWage : _wage.totalAmount),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brand,
                ),
              ),
            ],
          ),
          ),
        ),
      ],
    );
  }

  /// 공제 상세 항목 행 (compact, 금액만 semantic red)
  Widget _buildDeductionDetailItem(
      BuildContext context, String label, int amount, IconData icon) {
    final labelRow = [
      SizedBox(width: ResponsiveHelper.spacing(context, 4)),
      Icon(icon,
          size: ResponsiveHelper.iconSize(context, 12), color: AppColors.textTertiary),
      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
      Expanded(
        child: Text(
          TextLayout.keepWords(label),
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey700),
        ),
      ),
    ];
    final amountText = Text(
      '- ${FormatHelper.formatWage(amount)}',
      style: ResponsiveHelper.tinyStyle(context, color: AppColors.errorDark)
          .copyWith(fontWeight: FontWeight.w600),
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      // [DU1 후속42 B2-W2] 320·2.0 에서 금액이 줄지 않아 레이블 칸이 좁아져 '소득세·지/방세' 로 끊겼다(keepWords 로도 칸보다 긴 낱말은 강제 분할).
      //   폭/글자 배율이 좁을 때만 레이블 전폭 한 줄 + 금액을 다음 줄 오른쪽에 둔다. 넓은 폭은 기존 한 줄 그대로. 금액·문구 그대로.
      child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) < 260;
        if (!narrow) return Row(children: [...labelRow, amountText]);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: labelRow),
            Align(alignment: Alignment.centerRight, child: amountText),
          ],
        );
      }),
    );
  }

  // ── 계산 공식 안내 ────────────────────────────────────────────

  Widget _buildCalculationGuide(BuildContext context) {
    // 계산 기준 문자열 목록 — 공통 헬퍼(wage_calculation_lines.dart) 사용
    // WageDetailModel에 저장된 값만 포매팅하므로 재계산 없음
    final lines = buildWageCalculationLines(_wage);

    if (lines.isEmpty) return const SizedBox.shrink();

    // plain text 아코디언 (기존 파란 카드 → 텍스트 링크 스타일)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [DU1 후속42 B2-W2] 실측 클릭 외곽 105.2×17.0(392·1.0)·175.1×34.0(320·2.0) — 터치 48. 세로 최소 48, 내용 크기·위치(왼쪽) 그대로
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _isGuideExpanded = !_isGuideExpanded),
          child: ConstrainedBox(
           constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
           child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calculate_outlined,
                  size: ResponsiveHelper.iconSize(context, 13),
                  color: AppColors.grey600),
              SizedBox(width: ResponsiveHelper.spacing(context, 5)),
              Text(
                '계산 기준 보기',
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey700)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 3)),
              Icon(
                _isGuideExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: ResponsiveHelper.iconSize(context, 14),
                color: AppColors.grey600,
              ),
            ],
           ),
          ),
        ),
        // 펼침: floating card 없이 plain key-value rows — tertiary 정보
        if (_isGuideExpanded) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          ...lines.map(
            (line) => Padding(
              padding: EdgeInsets.only(
                top: ResponsiveHelper.spacing(context, 5),
                left: ResponsiveHelper.spacing(context, 2),
              ),
              child: Text(
                line,
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600)
                    .copyWith(height: 1.6),
              ),
            ),
          ),
        ],
      ],
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

        if (_amountLocked) ...[
          Text(
            '8일 이상 근무하면 보험료가 소급되는 공제 방식이라 이 화면에서는 금액을 바꿀 수 없어요. 메모만 수정할 수 있어요.',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        ],
        // 추가수당 / 추가공제 — 나란히 배치
        // [DU1 후속41 B2-W] 320·2.0 에서 두 칸을 나란히 두면 '추가수당'·'추가공제' 제목이 각 칸을 넘쳤다(6.3·7.3px).
        //   폭/글자 배율이 좁을 때만 세로로 쌓는다(각 칸 전폭) — 넓은 폭은 기존처럼 반씩 나란히. 입력·잠금·계산 그대로.
        LayoutBuilder(builder: (context, constraints) {
          final gap = ResponsiveHelper.spacing(context, 10);
          final stacked = constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) < 260;
          final fieldW = stacked ? constraints.maxWidth : (constraints.maxWidth - gap) / 2;
          return Wrap(
          spacing: gap,
          runSpacing: ResponsiveHelper.spacing(context, 12),
          children: [
            SizedBox(
              width: fieldW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(context, '추가수당'),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  TextField(
                    controller: _additionalController,
                    enabled: !_amountLocked,
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
                        borderSide: BorderSide(color: AppColors.brand),
                      ),
                      contentPadding: ResponsiveHelper.symmetricPadding(
                          context, horizontal: 12, vertical: 12),
                    ),
                    onChanged: (_) => _updateWage(),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: fieldW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(context, '추가공제'),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  TextField(
                    controller: _deductionController,
                    enabled: !_amountLocked,
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
                        borderSide: BorderSide(color: AppColors.brand),
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
        );
        }),
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
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 10),
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 12),
      ),
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
            confirmColor: AppColors.brand,
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
            confirmColor: AppColors.brand,
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
                  foregroundColor: AppColors.brand,
                  side: const BorderSide(color: AppColors.brand),
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
                onPressed: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  // primary CTA: ALfit brand blue (#1565C0), 초록은 확정/완료 semantic
                  backgroundColor: AppColors.brand,
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
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(context);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.grey600,
              side: BorderSide(color: theme.dividerColor),
              // [DU1 후속41 B2-W] 실측 48(392·1.0) → 공통 기준 52(같은 줄 저장과 같은 높이)
              minimumSize: const Size.fromHeight(52),
              padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 11)),
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
              // [DU1 후속41 B2-W] 실측 48 → 기준 주 버튼 52
              minimumSize: const Size.fromHeight(52),
              padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 11)),
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
                // [DU1 후속41 B2-W] 320·2.0 '소득세·지|방세' 끊김 — 단어 단위(문구 그대로)
                Text(TextLayout.keepWords(label),
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
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
