// test/unit/tax_deduction_service_test.dart
// TaxDeductionService 단위 테스트 — Firebase 의존성 없음 (순수 계산 로직)
//
// 실행: flutter test test/unit/tax_deduction_service_test.dart
//
// InsuranceRateService.getRates(2026)은 로컬 백업(defaults2026)을 반환하므로
// Firestore 연결 없이 실행 가능.
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/services/tax_deduction_service.dart';

// 테스트용 WageDetailModel 팩토리 — totalAmount만 지정
WageDetailModel makeBase(int totalAmount) => WageDetailModel(
      wageType: 'hourly',
      baseWage: 10320,
      totalAmount: totalAmount,
    );

// 2026년 기준 보험료율 (InsuranceRateModel.defaults2026 값)
const _pension = 4.75;
const _health = 3.595;
const _ltcRate = 13.14;      // 건강보험료 × 13.14%
const _employment = 0.9;
const _dailyExemption = 150000;
const _dailyTaxRate = 2.7;
const _localTaxRate = 10.0;
const _bizIncomeRate = 3.0;

int _round(double v) => v.round();

void main() {
  group('InsuranceRateModel.defaults2026 — 2026년 요율 정확성', () {
    final rates = InsuranceRateModel.defaults2026();

    test('국민연금 근로자 부담률 4.75%', () => expect(rates.nationalPensionRate, 4.75));
    test('건강보험 근로자 부담률 3.595%', () => expect(rates.healthInsuranceRate, 3.595));
    test('장기요양 비율 13.14%', () => expect(rates.ltcInsuranceRate, 13.14));
    test('고용보험 근로자 부담률 0.9%', () => expect(rates.employmentInsuranceRate, 0.9));
    test('일용직 비과세 한도 150,000원', () => expect(rates.dailyWageExemption, 150000));
    test('일용직 소득세율 2.7%', () => expect(rates.dailyWorkerTaxRate, 2.7));
    test('지방소득세 소득세 대비 10%', () => expect(rates.localIncomeTaxRate, 10.0));
  });

  // ────────────────────────────────────────────────────────────────────
  // 1. none — 공제 없음
  // ────────────────────────────────────────────────────────────────────
  group('TaxDeductionService: none (공제 없음)', () {
    test('NONE-01 공제 없음: netWage == totalAmount', () {
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(200000),
        taxDeductionType: InsuranceRateModel.typeNone,
        workYear: 2026,
      );
      expect(result.netWage, 200000);
      expect(result.incomeTaxDeduction, 0);
      expect(result.employmentInsuranceDeduction, 0);
    });

    test('NONE-02 음수 gross에서도 netWage == totalAmount (음수 그대로)', () {
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(-5000),
        taxDeductionType: InsuranceRateModel.typeNone,
        workYear: 2026,
      );
      expect(result.netWage, -5000);
    });

    test('NONE-03 0원에서 netWage == 0', () {
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(0),
        taxDeductionType: InsuranceRateModel.typeNone,
        workYear: 2026,
      );
      expect(result.netWage, 0);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // 2. freelancer_3_3 — 프리랜서 3.3%
  // ────────────────────────────────────────────────────────────────────
  group('TaxDeductionService: freelancer_3_3 (3.3% 원천징수)', () {
    test('FREL-01 100,000원 → 소득세 3,000원 + 지방세 300원 = 공제 3,300원', () {
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(100000),
        taxDeductionType: InsuranceRateModel.typeFreelancer33,
        workYear: 2026,
      );
      final incomeTax = _round(100000 * _bizIncomeRate / 100); // 3000
      final localTax = _round(incomeTax * _localTaxRate / 100); // 300
      expect(result.incomeTaxDeduction, incomeTax + localTax);
      expect(result.netWage, 100000 - (incomeTax + localTax));
    });

    test('FREL-02 음수 gross → safeGross=0으로 처리 (BUG-TAX-02)', () {
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(-10000),
        taxDeductionType: InsuranceRateModel.typeFreelancer33,
        workYear: 2026,
      );
      expect(result.incomeTaxDeduction, 0);
      expect(result.netWage, 0);
    });

    test('FREL-03 세전 1,000,000원 정확 계산', () {
      final gross = 1000000;
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(gross),
        taxDeductionType: InsuranceRateModel.typeFreelancer33,
        workYear: 2026,
      );
      final incomeTax = _round(gross * _bizIncomeRate / 100); // 30000
      final localTax = _round(incomeTax * _localTaxRate / 100); // 3000
      expect(result.incomeTaxDeduction, 33000);
      expect(result.netWage, gross - 33000);
    });

    test('FREL-04 taxDeductionType 필드가 freelancer_3_3 으로 기록', () {
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(100000),
        taxDeductionType: InsuranceRateModel.typeFreelancer33,
        workYear: 2026,
      );
      expect(result.taxDeductionType, InsuranceRateModel.typeFreelancer33);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // 3. daily_worker — 일용직 소득세 + 고용보험
  // ────────────────────────────────────────────────────────────────────
  group('TaxDeductionService: daily_worker (일용직 소득세)', () {
    test('DAILY-01 150,000원 이하 → 소득세 0, 고용보험만 공제', () {
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(150000),
        taxDeductionType: InsuranceRateModel.typeDailyWorker,
        workYear: 2026,
      );
      expect(result.incomeTaxDeduction, 0);
      final employment = _round(150000 * _employment / 100);
      expect(result.employmentInsuranceDeduction, employment);
      expect(result.netWage, 150000 - employment);
    });

    test('DAILY-02 200,000원 → (200,000 - 150,000) × 2.97% 소득세', () {
      final gross = 200000;
      final taxable = gross - _dailyExemption; // 50,000
      final incomeTax = _round(taxable * _dailyTaxRate / 100); // 1350
      final localTax = _round(incomeTax * _localTaxRate / 100);  // 135
      final employment = _round(gross * _employment / 100); // 1800
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(gross),
        taxDeductionType: InsuranceRateModel.typeDailyWorker,
        workYear: 2026,
      );
      expect(result.incomeTaxDeduction, incomeTax + localTax);
      expect(result.employmentInsuranceDeduction, employment);
      expect(result.netWage, gross - (incomeTax + localTax) - employment);
    });

    test('DAILY-03 비과세 경계 150,001원 → 소득세 0원 (round 특성)', () {
      // taxableAmount=1, incomeTax = round(1 × 0.027) = 0
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(150001),
        taxDeductionType: InsuranceRateModel.typeDailyWorker,
        workYear: 2026,
      );
      expect(result.incomeTaxDeduction, 0);
    });

    test('DAILY-04 음수 gross → safeGross=0 처리 (BUG-AID-01)', () {
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(-1000),
        taxDeductionType: InsuranceRateModel.typeDailyWorker,
        workYear: 2026,
      );
      expect(result.netWage, 0);
      expect(result.employmentInsuranceDeduction, 0);
      expect(result.incomeTaxDeduction, 0);
    });

    test('DAILY-05 정확한 netWage = gross - 소득세 - 고용보험', () {
      final gross = 300000;
      final taxable = gross - _dailyExemption; // 150,000
      final incomeTax = _round(taxable * _dailyTaxRate / 100);
      final localTax = _round(incomeTax * _localTaxRate / 100);
      final employment = _round(gross * _employment / 100);
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(gross),
        taxDeductionType: InsuranceRateModel.typeDailyWorker,
        workYear: 2026,
      );
      expect(result.netWage, gross - (incomeTax + localTax) - employment);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // 4. daily_auto_8 (1~7일 구간) — 고용보험 + 일용직 소득세
  // ────────────────────────────────────────────────────────────────────
  group('TaxDeductionService: daily_auto_8 1~7일 구간', () {
    test('AUTO8-01 150,000원 이하 → 소득세 0 + 고용보험만', () {
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(100000),
        taxDeductionType: InsuranceRateModel.typeDailyAuto8,
        workYear: 2026,
      );
      expect(result.incomeTaxDeduction, 0);
      final employment = _round(100000 * _employment / 100);
      expect(result.employmentInsuranceDeduction, employment);
      expect(result.nationalPensionDeduction, 0); // 1~7일: 국민연금 없음
      expect(result.healthInsuranceDeduction, 0); // 1~7일: 건강보험 없음
    });

    test('AUTO8-02 200,000원 → 고용보험 + 일용직 소득세 공제 (4대보험 없음)', () {
      final gross = 200000;
      final employment = _round(gross * _employment / 100);
      final taxable = gross - _dailyExemption;
      final incomeTax = _round(taxable * _dailyTaxRate / 100);
      final localTax = _round(incomeTax * _localTaxRate / 100);
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(gross),
        taxDeductionType: InsuranceRateModel.typeDailyAuto8,
        workYear: 2026,
      );
      expect(result.employmentInsuranceDeduction, employment);
      expect(result.incomeTaxDeduction, incomeTax + localTax);
      expect(result.nationalPensionDeduction, 0);
      expect(result.healthInsuranceDeduction, 0);
    });

    test('AUTO8-03 taxDeductionType이 daily_auto_8 으로 기록', () {
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(200000),
        taxDeductionType: InsuranceRateModel.typeDailyAuto8,
        workYear: 2026,
      );
      expect(result.taxDeductionType, InsuranceRateModel.typeDailyAuto8);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // 5. four_insurance_fixed — 4대보험 고정 공제
  // ────────────────────────────────────────────────────────────────────
  group('TaxDeductionService: four_insurance_fixed (4대보험)', () {
    test('FOUR-01 300,000원 → 국민연금+건강+장기요양+고용보험 정확 계산', () {
      final gross = 300000;
      final pension = _round(gross * _pension / 100);
      final health = _round(gross * _health / 100);
      final ltc = _round(health * _ltcRate / 100);
      final employment = _round(gross * _employment / 100);
      final total = pension + health + ltc + employment;
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(gross),
        taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed,
        workYear: 2026,
      );
      expect(result.nationalPensionDeduction, pension);
      expect(result.healthInsuranceDeduction, health);
      expect(result.ltcInsuranceDeduction, ltc);
      expect(result.employmentInsuranceDeduction, employment);
      expect(result.netWage, gross - total);
    });

    test('FOUR-02 소득세(incomeTaxDeduction) = 0 (의도된 설계: 연말정산으로 처리)', () {
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(300000),
        taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed,
        workYear: 2026,
      );
      expect(result.incomeTaxDeduction, 0);
    });

    test('FOUR-03 음수 gross → safeGross=0, netWage=0 (BUG-TAX-01)', () {
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(-5000),
        taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed,
        workYear: 2026,
      );
      expect(result.nationalPensionDeduction, 0);
      expect(result.netWage, 0);
    });

    test('FOUR-04 장기요양 = 건강보험공제액 × 13.14% (건강보험료 기반)', () {
      final gross = 500000;
      final health = _round(gross * _health / 100);
      final ltc = _round(health * _ltcRate / 100);
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(gross),
        taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed,
        workYear: 2026,
      );
      expect(result.ltcInsuranceDeduction, ltc);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // 6. applyDay8Retroactive — 8일 소급 공제
  // ────────────────────────────────────────────────────────────────────
  group('TaxDeductionService: applyDay8Retroactive (8일 소급)', () {
    test('RETRO-01 1~7일 총액 700,000원 → 국민연금+건강+장기요양 소급 계산', () {
      final prevGross = 700000;
      final prevPension = _round(prevGross * _pension / 100);
      final prevHealth = _round(prevGross * _health / 100);
      final prevLtc = _round(prevHealth * _ltcRate / 100);
      final expectedRetroactive = prevPension + prevHealth + prevLtc;

      final result = TaxDeductionService.applyDay8Retroactive(
        day8Base: makeBase(100000),
        prevGrossTotal: prevGross,
        workYear: 2026,
      );
      expect(result.retroactiveDeduction, expectedRetroactive);
    });

    test('RETRO-02 8일차 당일 4대보험 + 소득세 모두 공제', () {
      final gross8 = 200000;
      final result = TaxDeductionService.applyDay8Retroactive(
        day8Base: makeBase(gross8),
        prevGrossTotal: 700000,
        workYear: 2026,
      );
      // 8일차 당일분 공제가 있어야 함
      expect(result.nationalPensionDeduction, greaterThan(0));
      expect(result.healthInsuranceDeduction, greaterThan(0));
      expect(result.ltcInsuranceDeduction, greaterThan(0));
      expect(result.employmentInsuranceDeduction, greaterThan(0));
    });

    test('RETRO-03 8일차 gross=0 → 소급분만 공제, netWage 음수 가능', () {
      final prevGross = 700000;
      final retroactive = _round(prevGross * _pension / 100) +
          _round(prevGross * _health / 100) +
          _round(_round(prevGross * _health / 100) * _ltcRate / 100);
      final result = TaxDeductionService.applyDay8Retroactive(
        day8Base: makeBase(0),
        prevGrossTotal: prevGross,
        workYear: 2026,
      );
      // netWage = 0 - totalDeduction → 음수
      expect(result.netWage, lessThanOrEqualTo(0));
      expect(result.retroactiveDeduction, retroactive);
    });

    test('RETRO-04 prevGrossTotal=0 → 소급분 0, 8일차 당일분만 공제', () {
      final result = TaxDeductionService.applyDay8Retroactive(
        day8Base: makeBase(200000),
        prevGrossTotal: 0,
        workYear: 2026,
      );
      expect(result.retroactiveDeduction, 0);
    });

    test('RETRO-05 taxDeductionType이 daily_auto_8 으로 기록', () {
      final result = TaxDeductionService.applyDay8Retroactive(
        day8Base: makeBase(200000),
        prevGrossTotal: 700000,
        workYear: 2026,
      );
      expect(result.taxDeductionType, InsuranceRateModel.typeDailyAuto8);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // 7. 알 수 없는 taxDeductionType → typeNone 폴백
  // ────────────────────────────────────────────────────────────────────
  group('TaxDeductionService: unknown type → none 폴백', () {
    test('UNKNOWN-01 알 수 없는 공제 방식 → netWage == totalAmount', () {
      final result = TaxDeductionService.applyDeduction(
        base: makeBase(200000),
        taxDeductionType: 'unknown_type',
        workYear: 2026,
      );
      expect(result.netWage, 200000);
      expect(result.taxDeductionType, InsuranceRateModel.typeNone);
    });
  });
}
