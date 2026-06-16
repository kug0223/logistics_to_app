import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/core/insurance_rate_model.dart';
import '../models/core/wage_detail_model.dart';
import 'insurance_rate_service.dart';

/// 5종 공제 계산 서비스
///
/// WageCalculator.calculate()로 세전 총액(totalAmount)을 구한 뒤,
/// 이 서비스로 공제액·실수령액이 추가된 WageDetailModel을 반환한다.
///
/// [taxDeductionType] 별 계산 방식:
///   none              → 공제 없음, netWage = totalAmount
///   freelancer_3_3    → 총액 × 3.3% (소득세 3% + 지방소득세 0.3%)
///   daily_worker      → (총액 - 150,000원 비과세) × 2.97% (소득세 2.7% + 지방 0.27%)
///                       단, 총액 ≤ 150,000원이면 공제 0
///   daily_auto_8      → [별도 처리] 이 메서드는 1~7일(고용보험만) 계산만 담당
///                       8일 소급은 RetroactiveDeductionService에서 처리
///   four_insurance_fixed → 총액 × (국민연금 + 건강보험 + 장기요양 + 고용보험)
class TaxDeductionService {
  /// 공제 계산 적용 — WageDetailModel에 공제 필드·netWage 채워서 반환
  ///
  /// [base]: WageCalculator.calculate()가 반환한 원본 모델
  /// [taxDeductionType]: 공제 방식
  /// [workYear]: 근무일 연도 (보험료율 조회용)
  static WageDetailModel applyDeduction({
    required WageDetailModel base,
    required String taxDeductionType,
    required int workYear,
  }) {
    final rates = InsuranceRateService.getRates(workYear);
    final gross = base.totalAmount;

    switch (taxDeductionType) {
      case InsuranceRateModel.typeNone:
        return base.copyWith(
          taxDeductionType: taxDeductionType,
          netWage: gross,
        );

      case InsuranceRateModel.typeFreelancer33:
        return _applyFreelancer33(base, rates, gross);

      case InsuranceRateModel.typeDailyWorker:
        return _applyDailyWorker(base, rates, gross);

      case InsuranceRateModel.typeDailyAuto8:
        // 7일 이하 구간: 고용보험 + 일용직 소득세 (4대보험 중 고용보험만, 나머지는 8일째 소급)
        return _applyEmploymentAndIncomeTax(base, rates, gross);

      case InsuranceRateModel.typeFourInsuranceFixed:
        return _applyFourInsurance(base, rates, gross);

      default:
        return base.copyWith(
          taxDeductionType: InsuranceRateModel.typeNone,
          netWage: gross,
        );
    }
  }

  // ── 3.3% 원천징수 (프리랜서·사업소득) ─────────────────────────

  static WageDetailModel _applyFreelancer33(
    WageDetailModel base,
    InsuranceRateModel rates,
    int gross,
  ) {
    final incomeTax = (gross * rates.businessIncomeRate / 100).round();
    final localTax = (incomeTax * rates.localIncomeTaxRate / 100).round();
    final totalTax = incomeTax + localTax;
    return base.copyWith(
      taxDeductionType: InsuranceRateModel.typeFreelancer33,
      incomeTaxDeduction: totalTax,
      netWage: gross - totalTax,
    );
  }

  // ── 일용직 소득세 (15만원 초과분 × 2.97%) + 고용보험 0.9% ────

  static WageDetailModel _applyDailyWorker(
    WageDetailModel base,
    InsuranceRateModel rates,
    int gross,
  ) {
    final taxableAmount = (gross - rates.dailyWageExemption).clamp(0, gross);
    final incomeTax = taxableAmount > 0
        ? (taxableAmount * rates.dailyWorkerTaxRate / 100).round()
        : 0;
    final localTax = incomeTax > 0
        ? (incomeTax * rates.localIncomeTaxRate / 100).round()
        : 0;
    final totalTax = incomeTax + localTax;
    final employment = (gross * rates.employmentInsuranceRate / 100).round();
    return base.copyWith(
      taxDeductionType: InsuranceRateModel.typeDailyWorker,
      employmentInsuranceDeduction: employment,
      incomeTaxDeduction: totalTax,
      netWage: gross - totalTax - employment,
    );
  }

  // ── 고용보험 + 일용직 소득세 (daily_auto_8의 1~7일 구간) ──────
  // 4대보험 중 고용보험만 공제 (국민연금·건강·장기요양은 8일째 소급). 소득세는 1일차부터 공제.

  static WageDetailModel _applyEmploymentAndIncomeTax(
    WageDetailModel base,
    InsuranceRateModel rates,
    int gross,
  ) {
    final employment = (gross * rates.employmentInsuranceRate / 100).round();
    final taxableAmount = (gross - rates.dailyWageExemption).clamp(0, gross);
    final incomeTax = taxableAmount > 0
        ? (taxableAmount * rates.dailyWorkerTaxRate / 100).round()
        : 0;
    final localTax = incomeTax > 0
        ? (incomeTax * rates.localIncomeTaxRate / 100).round()
        : 0;
    final totalTax = incomeTax + localTax;
    return base.copyWith(
      taxDeductionType: InsuranceRateModel.typeDailyAuto8,
      employmentInsuranceDeduction: employment,
      incomeTaxDeduction: totalTax,
      netWage: gross - employment - totalTax,
    );
  }

  // ── 4대보험 고정 공제 ─────────────────────────────────────────
  // 소득세(incomeTax)를 포함하지 않는다 — 의도된 설계.
  // four_insurance_fixed 대상(9일 이상 장기 일용직)은 연말정산으로 소득세를 정산하므로
  // 매 근무일마다 원천징수하지 않는다.

  static WageDetailModel _applyFourInsurance(
    WageDetailModel base,
    InsuranceRateModel rates,
    int gross,
  ) {
    final pension    = (gross * rates.nationalPensionRate / 100).round();
    final health     = (gross * rates.healthInsuranceRate / 100).round();
    final ltc        = (health * rates.ltcInsuranceRate / 100).round();
    final employment = (gross * rates.employmentInsuranceRate / 100).round();
    final total      = pension + health + ltc + employment;
    return base.copyWith(
      taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed,
      nationalPensionDeduction: pension,
      healthInsuranceDeduction: health,
      ltcInsuranceDeduction: ltc,
      employmentInsuranceDeduction: employment,
      netWage: gross - total,
    );
  }

  // ── 8일 소급 계산 ─────────────────────────────────────────────

  /// 8일째 소급 공제 계산
  ///
  /// [prevGrossTotal]: 1~7일치 세전 임금 합계
  /// [currentGross]: 8일차 세전 임금
  /// [workYear]: 근무일 연도
  ///
  /// 반환값: 8일차 WageDetailModel (소급분 포함)
  /// - retroactiveDeduction: 1~7일분 4대보험 소급액
  /// - employmentInsuranceDeduction: 8일차 고용보험 (이전에 이미 공제했으므로 소급분에서 차감)
  /// - 나머지 보험: 1~7일 소급 + 8일차 당일분 합산
  static WageDetailModel applyDay8Retroactive({
    required WageDetailModel day8Base,
    required int prevGrossTotal,
    required int workYear,
  }) {
    final rates = InsuranceRateService.getRates(workYear);
    final gross8 = day8Base.totalAmount;

    // 1~7일치: 이미 고용보험(0.9%)만 공제했음
    // 소급분 = 1~7일 기준 (국민연금 + 건강보험 + 장기요양) 공제액
    final prevPension    = (prevGrossTotal * rates.nationalPensionRate / 100).round();
    final prevHealth     = (prevGrossTotal * rates.healthInsuranceRate / 100).round();
    final prevLtc        = (prevHealth * rates.ltcInsuranceRate / 100).round();
    // 고용보험: 1~7일 이미 공제됨 → 소급 추가 없음
    final retroactive    = prevPension + prevHealth + prevLtc;

    // 8일차 당일분 4대보험
    final pension8    = (gross8 * rates.nationalPensionRate / 100).round();
    final health8     = (gross8 * rates.healthInsuranceRate / 100).round();
    final ltc8        = (health8 * rates.ltcInsuranceRate / 100).round();
    final employment8 = (gross8 * rates.employmentInsuranceRate / 100).round();

    // 8일차 당일분 일용직 소득세 (1~7일분은 이미 각 날짜에서 공제됨, 소급 없음)
    final taxable8 = (gross8 - rates.dailyWageExemption).clamp(0, gross8);
    final incomeTax8 = taxable8 > 0
        ? (taxable8 * rates.dailyWorkerTaxRate / 100).round()
        : 0;
    final localTax8 = incomeTax8 > 0
        ? (incomeTax8 * rates.localIncomeTaxRate / 100).round()
        : 0;
    final totalTax8 = incomeTax8 + localTax8;

    final totalDeduction = retroactive + pension8 + health8 + ltc8 + employment8 + totalTax8;

    debugPrint('📊 8일 소급 계산: 이전합계=$prevGrossTotal원, 소급=$retroactive원, 당일4대보험=${pension8 + health8 + ltc8 + employment8}원, 당일소득세=$totalTax8원');

    return day8Base.copyWith(
      taxDeductionType: InsuranceRateModel.typeDailyAuto8,
      nationalPensionDeduction: pension8,
      healthInsuranceDeduction: health8,
      ltcInsuranceDeduction: ltc8,
      employmentInsuranceDeduction: employment8,
      incomeTaxDeduction: totalTax8,
      retroactiveDeduction: retroactive,
      netWage: gross8 - totalDeduction,
    );
  }

  /// 월별 근무일수 조회 (8일 소급 판단용)
  ///
  /// [userId], [businessId], [yearMonth] ('yyyy-MM') 기준
  /// wageStatus가 'pending'이 아닌(= 이미 확정 처리된) attendance 수를 반환
  static Future<int> getMonthlyWorkDays({
    required String userId,
    required String businessId,
    required String yearMonth,
    String? excludeAttendanceId,
  }) async {
    try {
      var query = FirebaseFirestore.instance
          .collection('attendance')
          .where('userId', isEqualTo: userId)
          .where('businessId', isEqualTo: businessId)
          .where('yearMonth', isEqualTo: yearMonth)
          .where('wageStatus', whereIn: ['calculated', 'confirmed', 'transferred']);

      final snapshot = await query.get();
      var count = snapshot.docs.length;

      // 현재 처리 중인 attendance는 카운트에서 제외 (중복 방지)
      if (excludeAttendanceId != null) {
        count = snapshot.docs
            .where((d) => d.id != excludeAttendanceId)
            .length;
      }
      return count;
    } catch (e) {
      debugPrint('⚠️ 월별 근무일수 조회 실패: $e');
      return 0;
    }
  }
}
