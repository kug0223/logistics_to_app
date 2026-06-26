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
    // 소득세 3%: gross × businessIncomeRate / 100
    // 지방소득세: incomeTax × localIncomeTaxRate(10%) / 100 = gross × 0.3%
    //
    // ✅ 의도된 설계: 지방소득세를 businessIncomeLocalRate(0.3%)로 직접 계산하지 않고
    // incomeTax × localIncomeTaxRate(10%)로 계산한다. 수학적으로 동일한 결과
    // (소득세3% × 10% = 0.3%)이며, round() 시 1원 차이가 발생하는 경우를 소득세 계산
    // 이후 10% 적용으로 통일하는 방식이다. (세법상 지방소득세 = 소득세의 10%)
    // businessIncomeLocalRate 필드는 슈퍼관리자 설정화면 표시용으로만 사용된다.
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
    // ✅ 비과세 경계값 설계:
    //   - gross = 150,000원: taxableAmount = 0 → 소득세 0원 (비과세 한도 내)
    //   - gross = 150,001원: taxableAmount = 1, incomeTax = (1 × 2.7/100).round() = 0원
    //
    // round() 특성상 taxableAmount가 최소 19원(0.027원 × 19 ≈ 0.513 → round() = 1)이
    // 되어야 소득세 1원이 공제된다. 즉 150,018원까지 실질 소득세가 0원이 된다.
    // 이는 의도된 설계: 원(₩) 단위로 round()를 사용하면 미소 과세금액은 0이 되고,
    // 납세자에게 유리한 방향으로 처리된다. ceil()로 변경하면 납세자에게 불리하다.
    final safeGross = gross < 0 ? 0 : gross;
    final taxableAmount = (safeGross - rates.dailyWageExemption).clamp(0, safeGross);
    final incomeTax = taxableAmount > 0
        ? (taxableAmount * rates.dailyWorkerTaxRate / 100).round()
        : 0;
    final localTax = incomeTax > 0
        ? (incomeTax * rates.localIncomeTaxRate / 100).round()
        : 0;
    final totalTax = incomeTax + localTax;
    final employment = (safeGross * rates.employmentInsuranceRate / 100).round();
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
    final safeGross = gross < 0 ? 0 : gross;
    final employment = (safeGross * rates.employmentInsuranceRate / 100).round();
    final taxableAmount = (safeGross - rates.dailyWageExemption).clamp(0, safeGross);
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
  //
  // ⚠️ B16 설계 방침: 국민연금 월 소득 상한(2026년 기준 617만원)을 적용하지 않는다.
  // 이유: 일용직 특성상 일당 단위로 계산하며 월 누적 소득을 추적하지 않으므로
  // 일당 기준 상한 계산이 불가하다. 실무에서 일용직은 일단 전체에 요율을 적용하고
  // 월 마감 시 세무사가 조정하는 방식을 채택하므로 의도된 트레이드오프다.
  // 정확한 상한 적용이 필요하면 급여 정산 단계에서 별도 처리가 필요하다.

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
      // 8일차 소급 공제 총액이 당일 세전 급여(gross8)를 초과하면 netWage가 음수.
      // 이는 1~7일치 4대보험 소급분이 클 때 발생할 수 있는 설계상 한계.
      // 실수령액 표시는 effectiveNetWage(clamp 0)를 사용하므로 UI는 0원으로 보임.
      // 초과분은 실무상 다음 급여에서 추가 공제하며, 앱에서는 별도 추적하지 않는다.
      netWage: gross8 - totalDeduction,
    );
  }

  /// 월별 근무일수 조회 (8일 소급 판단용)
  ///
  /// [userId], [businessId], [yearMonth] ('yyyy-MM') 기준
  /// wageStatus가 'pending'이 아닌(= 이미 확정 처리된) attendance 수를 반환.
  ///
  /// [B16 동시성 한계] 두 관리자가 같은 근무자의 서로 다른 날짜를 동시에 급여 확정할 때:
  /// A가 7번째 날짜를 확정하는 도중, B가 8번째 날짜를 확정하면서
  /// getMonthlyWorkDays를 호출하면 A의 wageStatus 변경이 아직 반영 안 된 상태에서
  /// prevDays=6으로 읽혀 B가 8일차임을 못 알아볼 수 있다 (소급 공제 누락).
  ///
  /// 반대로 A의 확정이 B보다 먼저 커밋되고 B가 조회하면 prevDays=7 → 8일차 정확히 감지.
  /// Firestore는 eventual consistency이므로 완전한 방어는 Cloud Functions에서
  /// 트랜잭션 단위로 처리해야 한다. 현재는 클라이언트 최선 노력(best effort) 수준 허용.
  static Future<int> getMonthlyWorkDays({
    required String userId,
    required String businessId,
    required String yearMonth,
    String? excludeAttendanceId,
  }) async {
    try {
      // whereIn 복합 쿼리 → PERMISSION_DENIED 방지를 위해 status별 병렬 쿼리로 대체
      final snaps = await Future.wait(
        ['calculated', 'confirmed', 'transferred'].map((ws) =>
            FirebaseFirestore.instance
                .collection('attendance')
                .where('userId', isEqualTo: userId)
                .where('businessId', isEqualTo: businessId)
                .where('yearMonth', isEqualTo: yearMonth)
                .where('wageStatus', isEqualTo: ws)
                .get()),
      );
      final allDocs = snaps.expand((snap) => snap.docs).toList();
      var count = allDocs.length;

      // 현재 처리 중인 attendance는 카운트에서 제외 (중복 방지)
      if (excludeAttendanceId != null) {
        count = allDocs.where((d) => d.id != excludeAttendanceId).length;
      }
      return count;
    } catch (e) {
      // 0 반환(silent fail): 조회 실패 시 8일차 소급이 누락되는 방향으로 처리.
      // _getPrevGrossTotal()은 소급 금액 계산에 필수이므로 rethrow(확정 전체 차단)하는 반면,
      // 여기서는 소급 미적용(근무자에게 유리한 방향)으로 처리해 확정 자체는 완료되도록 허용.
      debugPrint('⚠️ 월별 근무일수 조회 실패: $e');
      return 0;
    }
  }
}
