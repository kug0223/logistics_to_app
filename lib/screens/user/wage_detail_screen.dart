import 'package:flutter/material.dart';

import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/wage_detail_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/format_helper.dart';
import '../../utils/text_layout.dart';
import '../../utils/transfer_export_plan.dart';
import '../../utils/worker_wage_status.dart';
import '../../widgets/common/viewport_fill_surface.dart';
import '../common/document_management_screen.dart';

/// 급여 상세 화면
///
/// 수입 현황 → 근무 내역 행 탭 시 진입.
/// 해당 근무의 급여 계산 내역(세전 구성 항목 → 공제 → 실수령액 → 지급 상태)을 표시.
///
/// [WageDetailModel]이 있으면 항목별 세부 내역을 표시하고,
/// 없으면 finalWage 또는 예상 일당을 단일 행으로 표시한다.
///
/// 항목이 0원인 경우 표시하지 않는다 — 억지 0원 나열 금지.
///
/// TODO(급여상세-V3): wageStatus='paid' — 금융 API 연결 후 입금 완료 분기 추가
class WageDetailScreen extends StatelessWidget {
  final ApplicationModel application;
  final AttendanceModel? attendance;

  const WageDetailScreen({
    super.key,
    required this.application,
    this.attendance,
  });

  double _s(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 360) return 0.82;
    if (w < 400) return 0.92;
    if (w < 480) return 1.0;
    return 1.08;
  }

  /// 지급 상태 레이블 + 색상
  ///
  /// 상태 흐름:
  ///   wagePending     → 급여 처리 전 (중립 회색)
  ///   wageCalculated  → 정산 중 (중립 회색 · 금액·내역 숨김 — 마감 취소 건 포함 · HB3-VISIBILITY)
  ///   wageConfirmed   → 지급 예정 (brand blue)
  ///   wageTransferred → 이체 처리 완료 (진한 초록)
  ///   [future] paid   → 입금 완료 (금융 API 연결 후)
  ({String label, Color color}) _wageStatusInfo() {
    final att = attendance;
    if (att == null) {
      return (label: '처리 전', color: AppColors.textTertiary);
    }
    // [SIM-WORKER-WAGE-VIEW] 월 근무 내역 행과 같은 판정 한 벌 —
    //   계좌 재확인·노쇼·결근을 두 화면이 같은 말로 한다.
    return WorkerWageStatus.of(att) ??
        (label: '급여 처리 전', color: AppColors.textTertiary);
  }

  /// 확정 금액이 보이는 건인가 — [HB3-VISIBILITY] 확정·이체 완료만(AttendanceModel.displayWage).
  ///   마감 취소로 calculated 로 돌아간 건은 남아 있는 finalWage·wageDetail 을 보여 주지 않는다.
  bool get _hasConfirmedWage => attendance?.displayWage != null;

  /// 표시 금액 — 확정된 금액(displayWage) 우선, 없으면 예상 일당
  int get _displayWage {
    final fw = attendance?.displayWage;
    if (fw != null) return fw;
    if (application.wageType == 'hourly') {
      int toMin(String t) {
        final p = t.split(':');
        if (p.length < 2) return 0;
        return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
      }
      int startMin = toMin(application.startTime);
      int endMin = toMin(application.endTime);
      if (endMin <= startMin) endMin += 1440; // 야간 교대
      return ((endMin - startMin) / 60 * application.wage).round();
    }
    return application.wage;
  }

  /// 분 단위 시간 → 계산식 표시용 소수 포맷 (예: 90 → "1.5시간", 120 → "2시간")
  String _formulaHours(int minutes) {
    if (minutes <= 0) return '0시간';
    if (minutes % 60 == 0) return '${minutes ~/ 60}시간';
    return '${(minutes / 60).toStringAsFixed(1)}시간';
  }

  /// 분 단위 시간 → 한국어 포맷 (예: 480 → "8시간", 90 → "1시간 30분", 45 → "45분")
  String _formatDuration(int minutes) {
    if (minutes <= 0) return '-';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m분';
    if (m == 0) return '$h시간';
    return '$h시간 $m분';
  }

  /// 출퇴근 시각 포맷
  ///
  /// workDate와 날짜가 다를 때만 "M/D HH:mm" 형식으로 날짜를 함께 표시.
  /// 날짜가 같으면 "HH:mm"만 표시.
  ///
  /// 예: 23:30 출근 → 08:30 퇴근(다음날)이면
  ///   실제 출근  23:30
  ///   실제 퇴근  7/22 08:30
  ///
  /// [SIM-WORKER-WAGE-VIEW] 시각·날짜 모두 **KST** 로 읽는다. 기기 성분을 쓰면
  ///   GMT 기기에서 KST 20:00 출근이 '10/17 11:00' 으로 보였다(설치 앱 실측).
  String _formatCheckTime(DateTime? dt) {
    if (dt == null) return '-';
    final time = FormatHelper.formatTime(dt);
    // 날짜가 근무 기준일과 다를 때만 "M/D HH:mm" 형식 추가
    final day = FormatHelper.toKstDate(dt);
    final sameDay = day == FormatHelper.toKstDate(application.workDate);
    if (!sameDay) return '${day.month}/${day.day} $time';
    return time;
  }

  @override
  Widget build(BuildContext context) {
    final s = _s(context);
    final app = application;
    final att = attendance;
    // WageDetailModel — 실근무·통상시급 등 계산 기준.
    // [HB3-VISIBILITY] 확정·이체 완료 건만(displayWageDetail) — 마감 취소된 계산값은 보이지 않는다.
    final wd = att?.displayWageDetail;
    // [SIM-WORKER-WAGE-VIEW] 근무일은 KST 자정 instant 다 — 기기 성분이 아니라
    //   KST 달력일로 읽는다(GMT 기기에서 10/17 근무가 10/16 으로 보였다).
    final d = FormatHelper.toKstDate(app.workDate);
    const dowLabels = ['', '월', '화', '수', '목', '금', '토', '일'];
    final dateStr = '${d.month}월 ${d.day}일(${dowLabels[d.weekday]})';
    final statusInfo = _wageStatusInfo();

    // ── 통상시급 ─────────────────────────────────────────────────
    // 시급제: baseWage 자체가 통상시급
    // 일급제: appliedSupplementWage가 명시된 경우에만 표시 (미설정 시 숨김)
    final int standardHourly = (wd?.appliedSupplementWage ?? 0) > 0
        ? wd!.appliedSupplementWage
        : (wd?.wageType == 'hourly' ? (wd?.baseWage ?? 0) : 0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          '${d.month}월 급여 상세',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.textPrimary,
            size: 20,
          ),
          padding: const EdgeInsets.all(14),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.borderLight),
        ),
      ),
      // [BOTTOM-SURFACE-FILL] 수입 현황과 같은 구성이다 — 전폭 흰 섹션 +
      //   8px 회색 구분선. 근태가 없는 짧은 급여 상세에서는 360x800 기준
      //   297.7px 가 회색으로 남아 "여기에 뭔가 더 있어야 한다"처럼 읽혔다.
      //   같은 흐름(수입 → 급여 상세)에서 한쪽만 고치면 면이 끊기는 화면과
      //   이어지는 화면이 섞인다.
      body: ViewportFillSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 근무 정보 헤더 ───────────────────────────────────
            Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(20 * s, 20 * s, 20 * s, 20 * s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: 4 * s),
                  // [DU334] 320·2.0 '골 / 든패스' 해소 — 낱말 단위(phrases: 구분점은 앞 조각에 붙고, 조각 안 공백에서는
                  //   줄을 바꿀 수 있다). 원문은 낭독용. [DU340] 짧은 업무명은 한 덩어리 — 아래 _BusinessWorkTypeLine.
                  _BusinessWorkTypeLine(
                    businessName: app.businessName,
                    workType: app.selectedWorkType,
                  ),
                ],
              ),
            ),
            Container(height: 8, color: AppColors.background),

            // ── 근무 시간 ─────────────────────────────────────────
            _section(
              s: s,
              title: '근무 시간',
              children: [
                _detailRow(
                  s: s,
                  label: '예정 시간',
                  value: '${app.startTime} ~ ${app.endTime}',
                ),
                if (att?.checkInAt != null) ...[
                  SizedBox(height: 8 * s),
                  _detailRow(
                    s: s,
                    label: '실제 출근',
                    value: _formatCheckTime(att!.checkInAt),
                  ),
                ],
                if (att?.checkOutAt != null) ...[
                  SizedBox(height: 8 * s),
                  _detailRow(
                    s: s,
                    label: '실제 퇴근',
                    value: _formatCheckTime(att!.checkOutAt),
                  ),
                ],
                // ── 시간 요약 (급여 계산이 완료된 경우만 표시) ────────
                // WageDetailModel.workMinutes: CF가 계산한 실 근무 시간 (실 출퇴근 - 실 휴게)
                if (wd != null && wd.workMinutes > 0) ...[
                  SizedBox(height: 12 * s),
                  Divider(height: 1, color: AppColors.borderLight),
                  SizedBox(height: 12 * s),
                  // [Phase 3.1] 실제 적용된 무급휴게 (breakdown 가능 시 분류 표시)
                  if (wd.breakMinutes > 0) ...[
                    if (wd.hasBreakBreakdown) ...[
                      // 신규 레코드: 계약 기본 휴게 + 추가 무급휴게 분리 표시
                      if (wd.effectiveAppliedScheduledBreak > 0 || wd.hasReducedScheduledBreak) ...[
                        _detailRow(
                          s: s,
                          label: '기본 무급휴게',
                          value: wd.hasReducedScheduledBreak
                              ? '${_formatDuration(wd.effectiveAppliedScheduledBreak)} (계약 ${_formatDuration(wd.scheduledBreakMinutes)}에서 조정)'
                              : _formatDuration(wd.effectiveAppliedScheduledBreak),
                        ),
                        SizedBox(height: 8 * s),
                      ],
                      if (wd.effectiveAdditionalBreak > 0) ...[
                        _detailRow(
                          s: s,
                          label: '추가 무급휴게',
                          value: _formatDuration(wd.effectiveAdditionalBreak),
                          valueColor: AppColors.grey600,
                        ),
                        SizedBox(height: 8 * s),
                      ],
                    ] else ...[
                      // 구형 레코드: 합계만 표시
                      _detailRow(
                        s: s,
                        label: '무급휴게',
                        value: _formatDuration(wd.breakMinutes),
                      ),
                      SizedBox(height: 8 * s),
                    ],
                  ],
                  // 실근무 = 실제 출퇴근 시간 - 실제 휴게
                  _detailRow(
                    s: s,
                    label: '실근무',
                    value: _formatDuration(wd.workMinutes),
                    valueBold: true,
                  ),
                  // 미근무 = 예정 순근무 - 실근무 (조퇴·지각으로 부족한 시간)
                  () {
                    final scheduledNet =
                        (wd.scheduledMinutes - wd.scheduledBreakMinutes)
                            .clamp(0, 99999);
                    final unworked =
                        (scheduledNet - wd.workMinutes).clamp(0, 99999);
                    if (unworked <= 0) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: 8 * s),
                        _detailRow(
                          s: s,
                          label: '미근무',
                          value: _formatDuration(unworked),
                          valueColor: AppColors.error,
                        ),
                      ],
                    );
                  }(),
                ],
              ],
            ),
            Container(height: 8, color: AppColors.background),

            // ── 급여 내역 ─────────────────────────────────────────
            _section(
              s: s,
              title: '급여 내역',
              trailing: standardHourly > 0
                  ? Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 8 * s, vertical: 3 * s),
                      decoration: BoxDecoration(
                        color: AppColors.grey100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule_outlined,
                              size: 11 * s,
                              color: AppColors.textTertiary),
                          SizedBox(width: 3 * s),
                          Flexible(child: Text(
                            '통상시급 ${FormatHelper.formatWage(standardHourly)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          )),
                        ],
                      ),
                    )
                  : null,
              children: [_buildWageBreakdown(s)],
            ),
            Container(height: 8, color: AppColors.background),

            // ── 지급 상태 ─────────────────────────────────────────
            _section(
              s: s,
              title: '지급 상태',
              children: [
                Row(
                  children: [
                    Text(
                      '현재 상태',
                      style: AppTextStyles.meta(),
                    ),
                    const Spacer(),
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 10 * s, vertical: 4 * s),
                      decoration: BoxDecoration(
                        color: statusInfo.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusInfo.label,
                        style: AppTextStyles.statusBadge(
                            color: statusInfo.color),
                      ),
                    ),
                  ],
                ),
                // [SIM-WORKER-WAGE-VIEW] 확정된 급여가 언제 지급될 예정인지.
                //   이 값은 원장에 있었지만 근로자 화면 어디에도 없었다.
                //   이체 전 확정 건에만 보인다(이체 완료·노쇼·결근 제외).
                if (att != null && WorkerWageStatus.showsDueDate(att)) ...[
                  SizedBox(height: 8 * s),
                  _detailRow(
                    s: s,
                    label: '지급 예정일',
                    value: WorkerWageStatus.dueDateLabel(att.paymentDueDate!),
                  ),
                  if (att.wageAccountReviewRequired == true) ...[
                    SizedBox(height: 4 * s),
                    Text(
                      '지급정보 확인이 끝나야 이체할 수 있어요.',
                      style: AppTextStyles.meta(),
                    ),
                  ],
                ],
                // [PII-DOC-R1.6] 막혀 있다면 무엇을 해야 풀리는지 말한다.
                //   예전에는 이체가 막힌 건도 '지급 예정'으로만 보였다.
                //   근로자는 자기 급여가 멈춰 있다는 것도, 그것을 푸는 사람이
                //   자기라는 것도 알 수 없었다.
                if (att?.wageAccountReviewRequired == true) ...[
                  SizedBox(height: 12 * s),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12 * s),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          PayrollReadinessReason.labelOf(
                              att!.wageAccountReadinessReason),
                          style: AppTextStyles.statusBadge(
                              color: AppColors.warning),
                        ),
                        SizedBox(height: 4 * s),
                        Text(
                          '${PayrollReadinessReason.workerActionOf(att.wageAccountReadinessReason)}'
                          '\n급여 금액은 그대로 확정되어 있습니다.',
                          style: AppTextStyles.meta(),
                        ),
                        SizedBox(height: 8 * s),
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) => const DocumentManagementScreen()),
                          ),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('서류 관리로 이동'),
                        ),
                      ],
                    ),
                  ),
                ],
                // TODO(급여상세-V3): 금융 API 연결 후 AttendanceModel.paidAt 필드 추가,
                // wageTransferred 상태일 때 지급일 행 표시
                //   지급일      2026.07.31
                // 계좌번호·은행명은 이 화면에 표시하지 않는다.
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── 급여 내역 세부 위젯 ────────────────────────────────────────
  //
  // WageDetailModel 유무에 따라 두 가지 모드:
  //
  // [wageDetail 없음] 단순 모드
  //   총 급여 108,715원
  //
  // [wageDetail 있음] 세부 내역 모드 — 0원 항목은 표시 안 함
  //   기본급            120,000원
  //   연장수당            8,000원    ← overtimeAmount > 0
  //   야간수당            7,000원    ← nightAmount > 0
  //   주휴수당                       ← weeklyHolidayAmount > 0
  //   추가수당                       ← additionalAmount > 0
  //   추가공제          -5,000원    ← deductionAmount > 0
  //   ────────────────────────────
  //   공제 전 급여      135,000원   ← totalAmount (항상 표시)
  //
  //   고용보험           -1,215원   ← employmentInsuranceDeduction > 0
  //   국민연금           -5,400원   ← nationalPensionDeduction > 0
  //   건강보험           -4,250원   ← healthInsuranceDeduction > 0
  //   장기요양보험         -550원   ← ltcInsuranceDeduction > 0
  //   소득세            -14,670원   ← incomeTaxDeduction > 0
  //   소급공제                       ← retroactiveDeduction > 0
  //   ────────────────────────────
  //   실수령액          108,715원   ← effectiveNetWage (brand blue, bold)
  Widget _buildWageBreakdown(double s) {
    // [HB3-VISIBILITY] 확정·이체 완료 건만 세부 내역을 보인다(마감 취소 · 계산 중 건은 숨김).
    final wd = attendance?.displayWageDetail;

    // WageDetailModel 없음 → 간단히 총 급여 1줄
    //   확정 금액이 없으면 지원서 기준 예상 금액이므로 '예상 급여' 라고 말한다.
    if (wd == null) {
      return _detailRow(
        s: s,
        label: _hasConfirmedWage ? '총 급여' : '예상 급여',
        value: FormatHelper.formatWage(_displayWage),
        valueBold: true,
      );
    }

    final rows = <Widget>[];
    // 연장·야간수당 계산 기준 통상시급 — appliedSupplementWage 우선, 없으면 baseWage
    final supp = wd.appliedSupplementWage > 0 ? wd.appliedSupplementWage : wd.baseWage;
    final suppStr = FormatHelper.formatWage(supp);

    // ── 지급 항목 (세전 구성) — 계산 근거가 있는 항목은 _WageItemRow 사용 ──
    void addPayRow(String label, int amount, {String? formula}) {
      if (amount <= 0) return;
      if (rows.isNotEmpty) rows.add(SizedBox(height: 8 * s));
      rows.add(_WageItemRow(
        s: s,
        label: label,
        value: FormatHelper.formatWage(amount),
        formula: formula,
      ));
    }

    // 기본급 — 시급제인 경우 "통상시급 × 기본근로 시간" 공식 표시
    {
      String? formula;
      if (wd.wageType == 'hourly' && wd.workMinutes > 0) {
        final basicMins = (wd.workMinutes - wd.overtimeMinutes).clamp(0, 99999);
        if (basicMins > 0) {
          formula = '기본 근로 ${_formatDuration(basicMins)}\n'
              '$suppStr × ${_formulaHours(basicMins)}\n'
              '= ${FormatHelper.formatWage(wd.baseAmount)}';
        }
      }
      addPayRow('기본급', wd.baseAmount, formula: formula);
    }

    // 추가 근무수당 — [Phase 6] canonical breakdown 있으면 개선 표시, 없으면 legacy 유지
    if (wd.overtimeAmount > 0) {
      if (wd.hasCanonicalExtraWorkBreakdown && wd.contractExcessMinutes! > 0) {
        final totalExtraMins = wd.contractExcessMinutes!;
        final extra1x = wd.extraWork1xMinutes;
        final extra15x = wd.extraWork15xMinutes;
        final buf = StringBuffer('연장 근무  ${_formatDuration(totalExtraMins)}');
        if (extra1x > 0) buf.write('\n· 계약시간 초과 · 1배  ${_formatDuration(extra1x)}');
        if (extra15x > 0) buf.write('\n· 8시간 초과 · 1.5배  ${_formatDuration(extra15x)}');
        buf.write('\n= ${FormatHelper.formatWage(wd.overtimeAmount)}');
        addPayRow('연장 근무수당', wd.overtimeAmount, formula: buf.toString());
      } else {
        // legacy: 기존 표시 그대로 유지
        final formula = wd.overtimeMinutes > 0
            ? '연장 근무 ${_formatDuration(wd.overtimeMinutes)}\n'
                '$suppStr × 1.5배 × ${_formulaHours(wd.overtimeMinutes)}\n'
                '= ${FormatHelper.formatWage(wd.overtimeAmount)}'
            : null;
        addPayRow('연장 근무수당', wd.overtimeAmount, formula: formula);
      }
    }

    // 야간수당 — 22:00~06:00 구간 0.5배 가산
    if (wd.nightAmount > 0) {
      final formula = wd.nightMinutes > 0
          ? '야간근무 ${_formatDuration(wd.nightMinutes)} (22:00~06:00)\n'
              '$suppStr × 0.5배 × ${_formulaHours(wd.nightMinutes)}\n'
              '= ${FormatHelper.formatWage(wd.nightAmount)}'
          : null;
      addPayRow('야간수당', wd.nightAmount, formula: formula);
    }

    // 주휴수당·추가수당 — 계산 방식이 다양해 formula 없음
    addPayRow('주휴수당', wd.weeklyHolidayAmount);
    addPayRow('추가수당', wd.additionalAmount);

    // 추가공제 — 마이너스 표시
    if (wd.deductionAmount > 0) {
      if (rows.isNotEmpty) rows.add(SizedBox(height: 8 * s));
      rows.add(_detailRow(
        s: s,
        label: '추가공제',
        value: '-${FormatHelper.formatWage(wd.deductionAmount)}',
        valueColor: AppColors.textSecondary,
      ));
    }

    // ── 공제 전 급여 소계 ──────────────────────────────────────
    rows.add(SizedBox(height: 12 * s));
    rows.add(Divider(height: 1, color: AppColors.borderLight));
    rows.add(SizedBox(height: 12 * s));
    rows.add(_detailRow(
      s: s,
      label: '공제 전 급여',
      value: FormatHelper.formatWage(wd.totalAmount),
      valueBold: true,
    ));

    // ── 세금·보험 공제 항목 ────────────────────────────────────
    final deductionRows = <Widget>[];
    void addDeductRow(String label, int amount) {
      if (amount <= 0) return;
      deductionRows.add(SizedBox(height: 8 * s));
      deductionRows.add(_detailRow(
        s: s,
        label: label,
        value: '-${FormatHelper.formatWage(amount)}',
        valueColor: AppColors.textSecondary,
      ));
    }

    addDeductRow('고용보험', wd.employmentInsuranceDeduction);
    addDeductRow('국민연금', wd.nationalPensionDeduction);
    addDeductRow('건강보험', wd.healthInsuranceDeduction);
    addDeductRow('장기요양보험', wd.ltcInsuranceDeduction);
    addDeductRow('소득세', wd.incomeTaxDeduction);
    addDeductRow('소급공제', wd.retroactiveDeduction);

    if (deductionRows.isNotEmpty) {
      rows.addAll(deductionRows);
      rows.add(SizedBox(height: 12 * s));
      rows.add(Divider(height: 1, color: AppColors.borderLight));
      rows.add(SizedBox(height: 12 * s));
      rows.add(_detailRow(
        s: s,
        label: '실수령액',
        value: FormatHelper.formatWage(wd.effectiveNetWage),
        valueColor: AppColors.brand,
        valueBold: true,
        valueLarge: true, // 실수령액은 금액 크게
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  // ── 공통 섹션 컨테이너 ────────────────────────────────────────
  // trailing: 섹션 제목 우측에 표시할 위젯 (예: 통상시급 배지)
  Widget _section({
    required double s,
    required String title,
    Widget? trailing,
    required List<Widget> children,
  }) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(20 * s, 16 * s, 20 * s, 16 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [DU1-B2] Row+Spacer 는 320dp·2.0 에서 배지가 24px 넘쳤다(Spacer 는 flex 가 아니다) — 양 끝 Wrap, 모자라면 배지가 다음 줄
          if (trailing != null)
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 6 * s,
                children: [
                  Text(
                    title,
                    // textSecondary: textTertiary 대비 한 단계 진하게 — 섹션 제목 가독성 개선
                    style: AppTextStyles.caption(color: AppColors.textSecondary),
                  ),
                  trailing,
                ],
              ),
            )
          else
            Text(
              title,
              style: AppTextStyles.caption(color: AppColors.textSecondary),
            ),
          SizedBox(height: 12 * s),
          ...children,
        ],
      ),
    );
  }

  // ── 라벨-값 행 ───────────────────────────────────────────────
  Widget _detailRow({
    required double s,
    required String label,
    required String value,
    Color? valueColor,
    bool valueBold = false,
    bool valueLarge = false, // 실수령액 등 강조 금액에만 사용
  }) {
    return Row(
      children: [
        Text(label, style: AppTextStyles.meta()),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: valueLarge ? 18 : (valueBold ? 16 : 14),
            fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
            color: valueColor ?? AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

// ── 급여 항목 행 — 탭 시 계산 근거 펼침 ──────────────────────────────────
//
// formula가 null이면 일반 라벨-값 행처럼 동작 (탭 영역 없음).
// formula가 있으면 label 우측에 ∨ 아이콘이 표시되고,
// 탭 시 회색 박스로 계산식을 펼친다.
//
// 예 (펼침 전):   연장수당 ∨               23,220원
// 예 (펼침 후):   연장수당 ∧               23,220원
//                 ┌──────────────────────────────┐
//                 │ 연장근로 1시간 30분          │
//                 │ 10,320원 × 1.5배 × 1.5시간  │
//                 │ = 23,220원                   │
//                 └──────────────────────────────┘
class _WageItemRow extends StatefulWidget {
  final double s;
  final String label;
  final String value;
  final String? formula; // null이면 확장 불가

  const _WageItemRow({
    required this.s,
    required this.label,
    required this.value,
    this.formula,
  });

  @override
  State<_WageItemRow> createState() => _WageItemRowState();
}

class _WageItemRowState extends State<_WageItemRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final hasFormula = widget.formula != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: hasFormula ? () => setState(() => _expanded = !_expanded) : null,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Text(widget.label, style: AppTextStyles.meta()),
              if (hasFormula) ...[
                SizedBox(width: 3 * s),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 15 * s,
                  color: AppColors.textTertiary,
                ),
              ],
              const Spacer(),
              Text(
                widget.value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        if (_expanded && widget.formula != null)
          Container(
            margin: EdgeInsets.only(top: 8 * s),
            padding:
                EdgeInsets.symmetric(horizontal: 12 * s, vertical: 10 * s),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.formula!,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.7,
              ),
            ),
          ),
      ],
    );
  }
}

/// [DU340] 급여 명세 머리의 '사업장 · 업무' 줄(소급 감사 6 §3 채택).
///   낱말 단위(phrases)를 기본으로 하고, **업무명 전체가 이 줄의 가용 폭에 한 줄로 들어가면** 업무명 안에서는
///   줄을 바꾸지 않는다(`· QA / 분류` 해소). 한 줄 폭은 실제 글꼴 · 스타일 · 글자 배율 · 방향 · locale 로 잰다
///   (TextLayout.fits 는 문자열 측정기가 아니다 — 배율을 두 번 곱하지 않는다). 길면 phrases 그대로(낱말 경계 줄바꿈).
///   빈 업무명은 사업장만(구분점 없음). 낭독 이름은 원문이다.
class _BusinessWorkTypeLine extends StatelessWidget {
  final String businessName;
  final String workType;
  const _BusinessWorkTypeLine({required this.businessName, required this.workType});

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.businessName();
    final full = businessName + (workType.isNotEmpty ? ' · $workType' : '');
    final phrased = TextLayout.phrases(full);
    if (workType.isEmpty) {
      return Text(phrased, semanticsLabel: full, style: style);
    }
    return LayoutBuilder(builder: (ctx, c) {
      final painter = TextPainter(
        text: TextSpan(text: workType, style: DefaultTextStyle.of(ctx).style.merge(style)),
        textDirection: Directionality.of(ctx),
        textScaler: MediaQuery.textScalerOf(ctx),
        locale: Localizations.maybeLocaleOf(ctx),
        maxLines: 1,
      )..layout();
      final fitsOneLine = !c.hasBoundedWidth || painter.width <= c.maxWidth;
      painter.dispose();
      final tailWords = TextLayout.keepWords(workType);
      final shown = fitsOneLine && phrased.endsWith(tailWords)
          ? phrased.substring(0, phrased.length - tailWords.length) + TextLayout.unit(workType)
          : phrased;
      return Text(shown, semanticsLabel: full, style: style);
    });
  }
}
