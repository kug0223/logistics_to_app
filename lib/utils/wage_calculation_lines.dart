// lib/utils/wage_calculation_lines.dart
//
// 급여 계산 기준 문자열 목록 생성 — Flutter 의존 없는 순수 Dart 함수
//
// WageDetailDialog._buildCalculationGuide()의 lines 생성 로직과
// PayslipPdfBuilder._buildCalculationSection()이 이 함수를 공유한다.
//
// 규칙:
//   - 급여 재계산 없음 — WageDetailModel에 저장된 결과값만 포매팅
//   - lines가 비면 빈 List 반환 → 호출자가 섹션을 숨김
//   - Flutter/Material 의존 금지 (pdf 빌더에서도 직접 import)

import 'dart:math';

import '../models/core/wage_detail_model.dart';
import 'format_helper.dart';
import 'wage_calculator.dart';

/// [WageDetailModel]의 저장된 계산 결과를 설명 문자열 목록으로 변환한다.
///
/// 반환 예시 ([FormatHelper.formatCompactHours] 소수 h 형식 사용):
///   '기본급 = 10,030원/h × 6.5h = 65,195원'
///   '연장수당 = 10,030원/h × 1.5h × 1.5 = 22,568원'
///   '야간수당 = 10,030원/h × 2h × 0.5 = 10,030원'
///
/// 빈 List를 반환하면 해당 레코드에 수당 항목이 없음을 의미한다.
///
/// ⚠️ 구형 레코드 주의:
///   - `appliedSupplementWage == 0`이면 역산 fallback 사용 (`baseWage ÷ scheduledNetMins × 60`)
///     (구 WageDetailDialog에서 widget.baseHourlyWage를 추가 fallback으로 사용했으나
///      확정 레코드는 항상 appliedSupplementWage가 저장되므로 실질 차이 없음)
///   - `scheduledBreakMinutes == 0`으로 저장된 구형 레코드는
///     미근무 공제/석식 공제 줄의 시간 표기가 다를 수 있음
List<String> buildWageCalculationLines(WageDetailModel wd) {
  final isDaily = wd.wageType == 'daily';

  // ── 보조 변수 ────────────────────────────────────────────────────
  // scheduledBreakMinutes=0으로 저장된 레코드(WorkDetail 조회 실패·구형) 대비 폴백.
  // 정상 레코드에서는 scheduledBreakMinutes > 0 이므로 폴백이 발동하지 않는다.
  final effectiveSchedBreak =
      wd.scheduledBreakMinutes > 0 ? wd.scheduledBreakMinutes : wd.breakMinutes;
  final scheduledNetMins =
      (wd.scheduledMinutes - effectiveSchedBreak).clamp(0, 9999);
  final unworkedMins =
      (scheduledNetMins - wd.workMinutes).clamp(0, scheduledNetMins);
  final absenceDeduction = isDaily
      ? (wd.baseWage - wd.baseAmount).clamp(0, wd.baseWage)
      : 0;

  // ── 보조 시급 (appliedSupplementWage 우선) ────────────────────
  final int supplementWage;
  if (wd.appliedSupplementWage > 0) {
    supplementWage = wd.appliedSupplementWage;
  } else if (wd.wageType == 'hourly') {
    supplementWage = wd.baseWage;
  } else {
    final schedNetMinsCalc =
        (wd.scheduledMinutes - effectiveSchedBreak).clamp(1, 9999);
    supplementWage = (wd.baseWage / schedNetMinsCalc * 60).round();
  }

  final lines = <String>[];

  // ── 기본급 / 일급 ────────────────────────────────────────────────
  if (isDaily) {
    if (absenceDeduction > 0) {
      final scheduledH = FormatHelper.formatCompactHours(scheduledNetMins);
      final unworkH = FormatHelper.formatCompactHours(unworkedMins);
      lines.add('일급(전체) = ${FormatHelper.formatWage(wd.baseWage)}');
      lines.add(
          '미근무 공제 = ${FormatHelper.formatWage(wd.baseWage)} × $unworkH / $scheduledH'
          ' = -${FormatHelper.formatWage(absenceDeduction)}');
    } else {
      lines.add('일급 = ${FormatHelper.formatWage(wd.baseWage)}');
    }
  } else {
    // 시급제: 기본급은 정규 근무(연장 제외)만 포함
    final regularMins = wd.workMinutes - wd.overtimeMinutes;
    final regularH = FormatHelper.formatCompactHours(regularMins);
    lines.add('기본급 = ${FormatHelper.formatWage(wd.baseWage)}/h'
        ' × $regularH = ${FormatHelper.formatWage(wd.baseAmount)}');
  }

  // ── 석식/야식 공제 안내 (추가 무급 휴게가 있을 때) ──────────────
  final mealMinsGuide =
      (wd.breakMinutes - effectiveSchedBreak).clamp(0, 9999).toInt();
  if (mealMinsGuide > 0) {
    final mealH = FormatHelper.formatCompactHours(mealMinsGuide);
    lines.add('석식/야식 공제 $mealH → 연장 $mealH 차감');
  }

  // ── 조출/연장수당 (근로기준법 제56조) ──────────────────────────
  if (wd.overtimeAmount > 0) {
    final wageStr = FormatHelper.formatWage(supplementWage);
    final fEarlyMins = wd.earlyArrivalMinutes;
    final fRegularMins = wd.overtimeMinutes - fEarlyMins;

    // _effectiveEarlyArrivalAmount 인라인:
    //   저장된 earlyArrivalAmount 우선 (일급제 신규 레코드),
    //   없으면 overtimeAmount를 earlyMins 비율로 배분 (구형 레코드 fallback)
    final fEarlyAmt = wd.earlyArrivalAmount > 0
        ? wd.earlyArrivalAmount
        : (wd.overtimeMinutes > 0 && fEarlyMins > 0)
            ? (wd.overtimeAmount * fEarlyMins / wd.overtimeMinutes).round()
            : 0;
    final fRegularAmt = wd.overtimeAmount - fEarlyAmt;

    if (!isDaily) {
      // 시급제: overtimeMinutes는 이미 8h 초과분 → 모두 1.5배
      if (fEarlyMins > 0 && fEarlyAmt > 0) {
        lines.add('조출수당 = $wageStr/h'
            ' × ${FormatHelper.formatCompactHours(fEarlyMins)} × 1.5'
            ' = ${FormatHelper.formatWage(fEarlyAmt)}');
      }
      if (fRegularMins > 0 && fRegularAmt > 0) {
        lines.add('연장수당 = $wageStr/h'
            ' × ${FormatHelper.formatCompactHours(fRegularMins)} × 1.5'
            ' = ${FormatHelper.formatWage(fRegularAmt)}');
      }
    } else {
      // 일급제: 8h 초과 여부로 배율 분기
      final over8 = (wd.workMinutes - WageCalculator.standardWorkMinutes)
          .clamp(0, wd.overtimeMinutes);
      final within8 = wd.overtimeMinutes - over8;

      // 조출 공식
      if (fEarlyMins > 0 && fEarlyAmt > 0) {
        final earlyIn8 = min(fEarlyMins, within8);
        final h = FormatHelper.formatCompactHours(fEarlyMins);
        if (earlyIn8 >= fEarlyMins) {
          // 조출 전체 8h 이내 → 1.0배
          lines.add('조출수당 = $wageStr/h × $h × 1.0'
              ' = ${FormatHelper.formatWage(fEarlyAmt)}');
        } else if (earlyIn8 <= 0) {
          // 조출 전체 8h 초과 → 1.5배
          lines.add('조출수당 = $wageStr/h × $h × 1.5'
              ' = ${FormatHelper.formatWage(fEarlyAmt)}');
        } else {
          // 조출이 8h 이내/초과 혼합 → 금액만
          lines.add('조출수당 ($h) = ${FormatHelper.formatWage(fEarlyAmt)}');
        }
      }

      // 연장 공식
      if (fRegularMins > 0 && fRegularAmt > 0) {
        final earlyIn8 = min(fEarlyMins, within8);
        final regularIn8 =
            (within8 - earlyIn8).clamp(0, fRegularMins).toInt();
        final regularOver8 = fRegularMins - regularIn8;

        if (regularOver8 <= 0) {
          lines.add('연장수당 = $wageStr/h'
              ' × ${FormatHelper.formatCompactHours(fRegularMins)} × 1.0'
              ' = ${FormatHelper.formatWage(fRegularAmt)}');
        } else if (regularIn8 <= 0) {
          lines.add('연장수당 = $wageStr/h'
              ' × ${FormatHelper.formatCompactHours(fRegularMins)} × 1.5'
              ' = ${FormatHelper.formatWage(fRegularAmt)}');
        } else {
          // 8h 이내분 1배 + 초과분 1.5배 분리
          final aw = (regularIn8 * supplementWage / 60).round();
          final ao = (regularOver8 * supplementWage * 1.5 / 60).round();
          lines.add(
              '연장수당 (8h이내 ${FormatHelper.formatCompactHours(regularIn8)})'
              ' = $wageStr/h × 1.0 = ${FormatHelper.formatWage(aw)}');
          lines.add(
              '연장수당 (8h초과 ${FormatHelper.formatCompactHours(regularOver8)})'
              ' = $wageStr/h × 1.5 = ${FormatHelper.formatWage(ao)}');
        }
      }
    }
  }

  // ── 야간수당 ────────────────────────────────────────────────────
  if (wd.nightAmount > 0) {
    final h = FormatHelper.formatCompactHours(wd.nightMinutes);
    lines.add('야간수당 = ${FormatHelper.formatWage(supplementWage)}/h'
        ' × $h × 0.5 = ${FormatHelper.formatWage(wd.nightAmount)}');
  }

  return lines;
}
