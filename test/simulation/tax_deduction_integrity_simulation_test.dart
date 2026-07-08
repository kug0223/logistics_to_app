// test/simulation/tax_deduction_integrity_simulation_test.dart
//
// 세금 공제 데이터 무결성 심화 검증 시뮬레이션
// 목적: 기존 test/unit/ 에서 미커버된 영역을 집중 검증한다.
//
//   커버 범위 (기존 테스트와 중복 최소화):
//   1. InsuranceRateModel.toMap() 키 정확성 + 커스텀 요율 왕복 직렬화
//   2. InsuranceRateService.getRates 연도 폴백 (B04 설계: 미등록 연도 → 최근 연도)
//   3. WageCalculator.getMinimumWage fallback 체인 (2020~2026 + 미래/미지 연도)
//   4. WageDetailModel.totalInsuranceDeduction 집계 getter
//   5. WageDetailModel.effectiveNetWage — clamp, T-01 fix (netWage=0 + totalAmount>0)
//   6. daily_worker 비과세 경계 심화 (155556원, 0원, 음수 gross)
//   7. freelancer_3_3 소액(1,000원)/0원/음수 심화
//   8. four_insurance_fixed totalInsuranceDeduction 집계 + totalAmount=0/1 경계
//   9. applyDay8Retroactive 음수 prevGrossTotal, 소급공제 > 당일급여 netWage 음수
//  10. WageCalculator.calculate → TaxDeductionService.applyDeduction 통합 체인
//  11. calculateWeeklyHolidayPay 0분·20시간·40시간 초과 경계
//
// 실행: flutter test test/simulation/tax_deduction_integrity_simulation_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/services/tax_deduction_service.dart';
import 'package:ALfit/services/insurance_rate_service.dart';
import 'package:ALfit/utils/wage_calculator.dart';

// ── 테스트 헬퍼 ─────────────────────────────────────────────────────────────

/// 최소 WageDetailModel (totalAmount만 지정)
WageDetailModel _base(int totalAmount) => WageDetailModel(
      wageType: 'hourly',
      baseWage: 10320,
      totalAmount: totalAmount,
    );

/// 확정된 WageDetailModel (calculatedAt 설정 → isCalculated=true)
WageDetailModel _baseCalculated({
  required int totalAmount,
  int netWage = 0,
  int incomeTaxDeduction = 0,
  int nationalPensionDeduction = 0,
  int healthInsuranceDeduction = 0,
  int ltcInsuranceDeduction = 0,
  int employmentInsuranceDeduction = 0,
  int retroactiveDeduction = 0,
}) =>
    WageDetailModel(
      wageType: 'hourly',
      baseWage: 10320,
      totalAmount: totalAmount,
      netWage: netWage,
      incomeTaxDeduction: incomeTaxDeduction,
      nationalPensionDeduction: nationalPensionDeduction,
      healthInsuranceDeduction: healthInsuranceDeduction,
      ltcInsuranceDeduction: ltcInsuranceDeduction,
      employmentInsuranceDeduction: employmentInsuranceDeduction,
      retroactiveDeduction: retroactiveDeduction,
      calculatedAt: DateTime(2026, 6, 1), // isCalculated = true
    );

int _r(double v) => v.round();

// 2026년 기준 보험료율 상수
const _pension    = 4.75;
const _health     = 3.595;
const _ltcRate    = 13.14;   // 건강보험료 대비 비율
const _employment = 0.9;
const _exemption  = 150000;
const _dailyTax   = 2.7;
const _localTax   = 10.0;
const _bizIncome  = 3.0;

// ═══════════════════════════════════════════════════════════════════════════
void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // 1. InsuranceRateModel.toMap() 키 정확성 + 커스텀 요율 왕복
  // ─────────────────────────────────────────────────────────────────────────
  group('InsuranceRateModel — toMap 키 정확성', () {
    final map = InsuranceRateModel.defaults2026().toMap();

    test('SCENARIO-TAX-01 toMap에 10개 필드 모두 포함', () {
      expect(map.keys, containsAll([
        'year',
        'nationalPensionRate',
        'healthInsuranceRate',
        'ltcInsuranceRate',
        'employmentInsuranceRate',
        'dailyWageExemption',
        'dailyWorkerTaxRate',
        'localIncomeTaxRate',
        'businessIncomeRate',
        'businessIncomeLocalRate',
      ]));
      expect(map.length, equals(10));
    });

    test('SCENARIO-TAX-02 toMap nationalPensionRate 값 4.75', () {
      expect(map['nationalPensionRate'], equals(4.75));
    });

    test('SCENARIO-TAX-03 toMap healthInsuranceRate 값 3.595 (2026년 인상분)', () {
      expect(map['healthInsuranceRate'], equals(3.595));
      expect(map['healthInsuranceRate'], isNot(3.545)); // 2025년 요율과 다름
    });

    test('SCENARIO-TAX-04 toMap ltcInsuranceRate 값 13.14', () {
      expect(map['ltcInsuranceRate'], equals(13.14));
    });

    test('SCENARIO-TAX-05 toMap dailyWorkerTaxRate 값 2.7', () {
      expect(map['dailyWorkerTaxRate'], equals(2.7));
    });
  });

  group('InsuranceRateModel — 커스텀 요율 왕복 직렬화', () {
    // 2025년 가상 요율 (2026과 다른 값으로 왕복 테스트)
    const custom = InsuranceRateModel(
      year: 2025,
      nationalPensionRate: 4.5,
      healthInsuranceRate: 3.545,
      ltcInsuranceRate: 12.95,
      employmentInsuranceRate: 0.85,
      dailyWageExemption: 150000,
      dailyWorkerTaxRate: 2.7,
      localIncomeTaxRate: 10.0,
      businessIncomeRate: 3.0,
      businessIncomeLocalRate: 0.3,
    );
    final rt = InsuranceRateModel.fromMap(custom.toMap());

    test('SCENARIO-TAX-06 커스텀 year 왕복 일치', () {
      expect(rt.year, equals(2025));
    });

    test('SCENARIO-TAX-07 커스텀 nationalPensionRate 왕복 일치 (4.5)', () {
      expect(rt.nationalPensionRate, equals(4.5));
    });

    test('SCENARIO-TAX-08 커스텀 healthInsuranceRate 왕복 일치 (3.545)', () {
      expect(rt.healthInsuranceRate, equals(3.545));
    });

    test('SCENARIO-TAX-09 커스텀 ltcInsuranceRate 왕복 일치 (12.95)', () {
      expect(rt.ltcInsuranceRate, equals(12.95));
    });

    test('SCENARIO-TAX-10 커스텀 employmentInsuranceRate 왕복 일치 (0.85)', () {
      expect(rt.employmentInsuranceRate, equals(0.85));
    });
  });

  group('InsuranceRateModel.fromMap — clamp 경계 심화', () {
    test('SCENARIO-TAX-11 nationalPensionRate=25 → clamp(0,20) → 20', () {
      final m = InsuranceRateModel.fromMap({'nationalPensionRate': 25.0});
      expect(m.nationalPensionRate, equals(20.0));
    });

    test('SCENARIO-TAX-12 ltcInsuranceRate=35 → clamp(0,30) → 30 (상한 30)', () {
      final m = InsuranceRateModel.fromMap({'ltcInsuranceRate': 35.0});
      expect(m.ltcInsuranceRate, equals(30.0));
    });

    test('SCENARIO-TAX-13 ltcInsuranceRate=-1 → clamp(0,30) → 0', () {
      final m = InsuranceRateModel.fromMap({'ltcInsuranceRate': -1.0});
      expect(m.ltcInsuranceRate, equals(0.0));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. InsuranceRateService.getRates 연도 폴백 (B04 설계)
  // ─────────────────────────────────────────────────────────────────────────
  group('InsuranceRateService.getRates — 연도 폴백 (B04 설계)', () {
    // 로컬 백업은 2026년만 내장 → 타 연도는 2026 폴백

    test('SCENARIO-TAX-14 getRates(2026) nationalPensionRate = 4.75', () {
      expect(InsuranceRateService.getRates(2026).nationalPensionRate, equals(4.75));
    });

    test('SCENARIO-TAX-15 getRates(2026) healthInsuranceRate = 3.595', () {
      expect(InsuranceRateService.getRates(2026).healthInsuranceRate, equals(3.595));
    });

    test('SCENARIO-TAX-16 getRates(2025) → 2026 폴백 (B04: 미등록 연도는 최근 연도 반환)', () {
      final rates = InsuranceRateService.getRates(2025);
      expect(rates.nationalPensionRate, equals(4.75)); // 2026년 요율
    });

    test('SCENARIO-TAX-17 getRates(2027) → 2026 폴백 (미래 연도도 폴백)', () {
      final rates = InsuranceRateService.getRates(2027);
      expect(rates.healthInsuranceRate, equals(3.595));
    });

    test('SCENARIO-TAX-18 getRates(1990) → 2026 폴백 (먼 과거 연도)', () {
      final rates = InsuranceRateService.getRates(1990);
      expect(rates.employmentInsuranceRate, equals(0.9));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. WageCalculator.getMinimumWage — 연도별 fallback 체인
  // ─────────────────────────────────────────────────────────────────────────
  group('WageCalculator.getMinimumWage — 연도별 로컬 백업 체인', () {
    // Firestore loadMinimumWages()를 호출하지 않으므로 캐시=null → 로컬 백업 사용

    test('SCENARIO-TAX-19 getMinimumWage(2026) = 10320원 (고용노동부 고시)', () {
      expect(WageCalculator.getMinimumWage(2026), equals(10320));
    });

    test('SCENARIO-TAX-20 getMinimumWage(2025) = 10030원', () {
      expect(WageCalculator.getMinimumWage(2025), equals(10030));
    });

    test('SCENARIO-TAX-21 getMinimumWage(2024) = 9860원', () {
      expect(WageCalculator.getMinimumWage(2024), equals(9860));
    });

    test('SCENARIO-TAX-22 getMinimumWage(2023) = 9620원', () {
      expect(WageCalculator.getMinimumWage(2023), equals(9620));
    });

    test('SCENARIO-TAX-23 getMinimumWage(2022) = 9160원', () {
      expect(WageCalculator.getMinimumWage(2022), equals(9160));
    });

    test('SCENARIO-TAX-24 getMinimumWage(2027) → 최근 연도(2026) 폴백 = 10320원', () {
      // _minimumWageByYear에 2027이 없으므로 keys.reduce(max)=2026 반환
      expect(WageCalculator.getMinimumWage(2027), equals(10320));
    });

    test('SCENARIO-TAX-25 getMinimumWage(1990) → 최근 연도(2026) 폴백 = 10320원', () {
      expect(WageCalculator.getMinimumWage(1990), equals(10320));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. WageDetailModel.totalInsuranceDeduction 집계 getter
  // ─────────────────────────────────────────────────────────────────────────
  group('WageDetailModel.totalInsuranceDeduction — 집계 검증', () {
    test('SCENARIO-TAX-26 전부 0 → totalInsuranceDeduction = 0', () {
      final m = WageDetailModel(wageType: 'hourly', baseWage: 10320);
      expect(m.totalInsuranceDeduction, equals(0));
    });

    test('SCENARIO-TAX-27 employmentInsuranceDeduction만 설정 → 해당 값만 반영', () {
      final m = WageDetailModel(
        wageType: 'hourly', baseWage: 10320,
        employmentInsuranceDeduction: 1350,
      );
      expect(m.totalInsuranceDeduction, equals(1350));
    });

    test('SCENARIO-TAX-28 5개 공제 필드 합계 정확성', () {
      // pension=9500, health=7190, ltc=945, employment=1800, incomeTax=1485
      const expected = 9500 + 7190 + 945 + 1800 + 1485; // = 20920
      final m = WageDetailModel(
        wageType: 'hourly', baseWage: 10320,
        nationalPensionDeduction: 9500,
        healthInsuranceDeduction: 7190,
        ltcInsuranceDeduction: 945,
        employmentInsuranceDeduction: 1800,
        incomeTaxDeduction: 1485,
      );
      expect(m.totalInsuranceDeduction, equals(expected));
    });

    test('SCENARIO-TAX-29 retroactiveDeduction도 합계에 포함', () {
      // 기존 5개 공제 + retroactive=61722 → 82642
      const expected = 9500 + 7190 + 945 + 1800 + 1485 + 61722; // = 82642
      final m = WageDetailModel(
        wageType: 'hourly', baseWage: 10320,
        nationalPensionDeduction: 9500,
        healthInsuranceDeduction: 7190,
        ltcInsuranceDeduction: 945,
        employmentInsuranceDeduction: 1800,
        incomeTaxDeduction: 1485,
        retroactiveDeduction: 61722,
      );
      expect(m.totalInsuranceDeduction, equals(expected));
    });

    test('SCENARIO-TAX-30 four_insurance_fixed 결과 totalInsuranceDeduction = 48587', () {
      // 500000원 → pension=23750, health=17975, ltc=2362, employment=4500
      // (incomeTax=0, retroactive=0)
      final result = TaxDeductionService.applyDeduction(
        base: _base(500000),
        taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed,
        workYear: 2026,
      );
      const expectedPension    = 23750;
      const expectedHealth     = 17975;
      final expectedLtc        = _r(expectedHealth * _ltcRate / 100);  // 2362
      const expectedEmployment = 4500;
      expect(result.nationalPensionDeduction,   equals(expectedPension));
      expect(result.healthInsuranceDeduction,   equals(expectedHealth));
      expect(result.ltcInsuranceDeduction,      equals(expectedLtc));
      expect(result.employmentInsuranceDeduction, equals(expectedEmployment));
      expect(result.totalInsuranceDeduction,
          equals(expectedPension + expectedHealth + expectedLtc + expectedEmployment));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 5. WageDetailModel.effectiveNetWage — clamp 및 T-01 fix
  // ─────────────────────────────────────────────────────────────────────────
  group('WageDetailModel.effectiveNetWage — clamp 및 T-01 fix', () {
    test('SCENARIO-TAX-31 isCalculated=false: totalAmount - totalInsuranceDeduction', () {
      // incomeTaxDeduction=3300, totalAmount=200000 → effectiveNetWage=196700
      final m = WageDetailModel(
        wageType: 'hourly', baseWage: 10320,
        totalAmount: 200000,
        incomeTaxDeduction: 3300,
        // calculatedAt = null → isCalculated = false
      );
      expect(m.effectiveNetWage, equals(196700));
    });

    test('SCENARIO-TAX-32 isCalculated=false: totalInsuranceDeduction > totalAmount → 0 (clamp)', () {
      final m = WageDetailModel(
        wageType: 'hourly', baseWage: 10320,
        totalAmount: 50000,
        retroactiveDeduction: 80000, // 소급공제가 당일 급여 초과
      );
      // (50000 - 80000).clamp(0,...) = 0
      expect(m.effectiveNetWage, equals(0));
    });

    test('SCENARIO-TAX-33 isCalculated=false: totalAmount=0 → 0', () {
      final m = WageDetailModel(wageType: 'hourly', baseWage: 10320, totalAmount: 0);
      expect(m.effectiveNetWage, equals(0));
    });

    test('SCENARIO-TAX-34 isCalculated=true: netWage>0 → netWage 그대로 반환', () {
      final m = _baseCalculated(totalAmount: 200000, netWage: 196700, incomeTaxDeduction: 3300);
      // isCalculated=true, netWage=196700(>0) → 196700.clamp(0,...) = 196700
      expect(m.effectiveNetWage, equals(196700));
    });

    test('SCENARIO-TAX-35 isCalculated=true: netWage<0 (소급공제 초과) → 0 (clamp)', () {
      // 8일 소급공제가 당일 급여 초과 → netWage 음수
      final m = _baseCalculated(totalAmount: 50000, netWage: -16581);
      // (-16581).clamp(0, 999999999) = 0
      expect(m.effectiveNetWage, equals(0));
    });

    test('SCENARIO-TAX-36 isCalculated=true: netWage=0 + totalAmount=0 → 0 (T-01: 조건 미충족)', () {
      // T-01 fix 조건: netWage==0 AND totalAmount>0. totalAmount=0 → 조건 미충족 → 0.clamp=0
      final m = _baseCalculated(totalAmount: 0, netWage: 0);
      expect(m.effectiveNetWage, equals(0));
    });

    test('SCENARIO-TAX-37 isCalculated=true: netWage=0 + totalAmount>0 → T-01 fix 계산식 적용', () {
      // 마이그레이션 전 레코드: netWage 필드가 없어 기본값 0, 실제 공제는 존재
      // → (totalAmount - totalInsuranceDeduction).clamp(0,...) 으로 폴백
      final m = _baseCalculated(
        totalAmount: 200000,
        netWage: 0,              // 마이그레이션 전: netWage 부재 → 기본값 0
        incomeTaxDeduction: 3300, // 이미 공제됨
      );
      // totalInsuranceDeduction = 3300
      // effectiveNetWage = (200000 - 3300).clamp(0,...) = 196700
      expect(m.effectiveNetWage, equals(196700));
    });

    test('SCENARIO-TAX-38 applyDay8Retroactive 결과: effectiveNetWage=0 (소급>당일)', () {
      // prevGrossTotal=700000, day8=50000 → netWage=-16581
      // isCalculated=false → (50000 - totalInsuranceDeduction).clamp(0,...) = 0
      final result = TaxDeductionService.applyDay8Retroactive(
        day8Base: _base(50000),
        prevGrossTotal: 700000,
        workYear: 2026,
      );
      expect(result.effectiveNetWage, equals(0));
      expect(result.netWage, lessThan(0)); // 음수 netWage는 모델에 그대로 저장됨
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 6. daily_worker 비과세 경계 심화
  // ─────────────────────────────────────────────────────────────────────────
  group('TaxDeductionService: daily_worker — 비과세 경계 심화', () {
    test('SCENARIO-TAX-39 totalAmount=0 → incomeTax=0, employment=0, netWage=0', () {
      final r = TaxDeductionService.applyDeduction(
        base: _base(0),
        taxDeductionType: InsuranceRateModel.typeDailyWorker,
        workYear: 2026,
      );
      expect(r.incomeTaxDeduction, equals(0));
      expect(r.employmentInsuranceDeduction, equals(0));
      expect(r.netWage, equals(0));
    });

    test('SCENARIO-TAX-40 totalAmount=150000: 비과세 한도 → incomeTax=0, employment=1350', () {
      // safeGross=150000, taxable=(150000-150000)=0, incomeTax=0
      // employment=(150000*0.9/100).round()=1350
      final r = TaxDeductionService.applyDeduction(
        base: _base(150000),
        taxDeductionType: InsuranceRateModel.typeDailyWorker,
        workYear: 2026,
      );
      expect(r.incomeTaxDeduction, equals(0));
      expect(r.employmentInsuranceDeduction, equals(1350));
      expect(r.netWage, equals(148650));
    });

    test('SCENARIO-TAX-41 totalAmount=150001: taxable=1 → round(0.027)=0 → incomeTax=0', () {
      // taxable=1, (1*2.7/100).round() = (0.027).round() = 0
      // 납세자 유리 방향 처리 (설계 의도)
      final r = TaxDeductionService.applyDeduction(
        base: _base(150001),
        taxDeductionType: InsuranceRateModel.typeDailyWorker,
        workYear: 2026,
      );
      expect(r.incomeTaxDeduction, equals(0));
    });

    test('SCENARIO-TAX-42 totalAmount=155556: taxable=5556 → incomeTax+local=165', () {
      // incomeTax=(5556*2.7/100).round()=(150.012).round()=150
      // local=(150*10/100).round()=15 → total=165
      // employment=(155556*0.9/100).round()=(1400.004).round()=1400
      // netWage=155556-165-1400=153991
      final r = TaxDeductionService.applyDeduction(
        base: _base(155556),
        taxDeductionType: InsuranceRateModel.typeDailyWorker,
        workYear: 2026,
      );
      expect(r.incomeTaxDeduction, equals(165));
      expect(r.employmentInsuranceDeduction, equals(1400));
      expect(r.netWage, equals(153991));
    });

    test('SCENARIO-TAX-43 totalAmount=-1 → safeGross=0, all=0, netWage=0 (BUG-AID-01)', () {
      final r = TaxDeductionService.applyDeduction(
        base: _base(-1),
        taxDeductionType: InsuranceRateModel.typeDailyWorker,
        workYear: 2026,
      );
      expect(r.incomeTaxDeduction, equals(0));
      expect(r.employmentInsuranceDeduction, equals(0));
      expect(r.netWage, equals(0));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 7. freelancer_3_3 심화
  // ─────────────────────────────────────────────────────────────────────────
  group('TaxDeductionService: freelancer_3_3 — 소액/0원/음수 심화', () {
    test('SCENARIO-TAX-44 totalAmount=1000 → incomeTax=30, local=3, totalTax=33, netWage=967', () {
      // incomeTax=(1000*3.0/100).round()=30
      // local=(30*10.0/100).round()=3
      final r = TaxDeductionService.applyDeduction(
        base: _base(1000),
        taxDeductionType: InsuranceRateModel.typeFreelancer33,
        workYear: 2026,
      );
      expect(r.incomeTaxDeduction, equals(33));
      expect(r.netWage, equals(967));
    });

    test('SCENARIO-TAX-45 totalAmount=0 → incomeTax=0, netWage=0', () {
      final r = TaxDeductionService.applyDeduction(
        base: _base(0),
        taxDeductionType: InsuranceRateModel.typeFreelancer33,
        workYear: 2026,
      );
      expect(r.incomeTaxDeduction, equals(0));
      expect(r.netWage, equals(0));
    });

    test('SCENARIO-TAX-46 totalAmount=-500 → safeGross=0, incomeTax=0, netWage=0 (BUG-TAX-02)', () {
      final r = TaxDeductionService.applyDeduction(
        base: _base(-500),
        taxDeductionType: InsuranceRateModel.typeFreelancer33,
        workYear: 2026,
      );
      expect(r.incomeTaxDeduction, equals(0));
      expect(r.netWage, equals(0));
    });

    test('SCENARIO-TAX-47 totalAmount=333333 → incomeTax=10000, local=1000, netWage=322333', () {
      // (333333*3.0/100).round() = (9999.99).round() = 10000
      // (10000*10.0/100).round() = 1000
      // netWage = 333333-11000 = 322333
      final r = TaxDeductionService.applyDeduction(
        base: _base(333333),
        taxDeductionType: InsuranceRateModel.typeFreelancer33,
        workYear: 2026,
      );
      expect(r.incomeTaxDeduction, equals(11000));
      expect(r.netWage, equals(322333));
    });

    test('SCENARIO-TAX-48 nationalPensionDeduction=0 (프리랜서는 4대보험 없음)', () {
      final r = TaxDeductionService.applyDeduction(
        base: _base(500000),
        taxDeductionType: InsuranceRateModel.typeFreelancer33,
        workYear: 2026,
      );
      expect(r.nationalPensionDeduction, equals(0));
      expect(r.healthInsuranceDeduction, equals(0));
      expect(r.ltcInsuranceDeduction, equals(0));
      expect(r.employmentInsuranceDeduction, equals(0));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 8. four_insurance_fixed 심화
  // ─────────────────────────────────────────────────────────────────────────
  group('TaxDeductionService: four_insurance_fixed — 심화', () {
    test('SCENARIO-TAX-49 totalAmount=500000 → 각 공제 정확 계산', () {
      // pension=(500000*4.75/100).round()=23750
      // health=(500000*3.595/100).round()=17975
      // ltc=(17975*13.14/100).round()=(2361.615).round()=2362
      // employment=(500000*0.9/100).round()=4500
      final r = TaxDeductionService.applyDeduction(
        base: _base(500000),
        taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed,
        workYear: 2026,
      );
      expect(r.nationalPensionDeduction, equals(23750));
      expect(r.healthInsuranceDeduction, equals(17975));
      expect(r.ltcInsuranceDeduction, equals(2362));
      expect(r.employmentInsuranceDeduction, equals(4500));
    });

    test('SCENARIO-TAX-50 totalAmount=500000 → netWage=451413', () {
      // total=23750+17975+2362+4500=48587, netWage=500000-48587=451413
      final r = TaxDeductionService.applyDeduction(
        base: _base(500000),
        taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed,
        workYear: 2026,
      );
      expect(r.netWage, equals(451413));
    });

    test('SCENARIO-TAX-51 totalAmount=0 → all=0, netWage=0', () {
      final r = TaxDeductionService.applyDeduction(
        base: _base(0),
        taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed,
        workYear: 2026,
      );
      expect(r.nationalPensionDeduction, equals(0));
      expect(r.healthInsuranceDeduction, equals(0));
      expect(r.netWage, equals(0));
    });

    test('SCENARIO-TAX-52 totalAmount=1 → 모두 round(0)=0, netWage=1', () {
      // pension=(1*4.75/100).round()=(0.0475).round()=0
      // health=(1*3.595/100).round()=(0.03595).round()=0
      // ltc=(0*13.14/100).round()=0, employment=(1*0.9/100).round()=0
      final r = TaxDeductionService.applyDeduction(
        base: _base(1),
        taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed,
        workYear: 2026,
      );
      expect(r.nationalPensionDeduction, equals(0));
      expect(r.healthInsuranceDeduction, equals(0));
      expect(r.ltcInsuranceDeduction, equals(0));
      expect(r.employmentInsuranceDeduction, equals(0));
      expect(r.netWage, equals(1));
    });

    test('SCENARIO-TAX-53 incomeTaxDeduction=0 (연말정산 설계 의도)', () {
      final r = TaxDeductionService.applyDeduction(
        base: _base(500000),
        taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed,
        workYear: 2026,
      );
      expect(r.incomeTaxDeduction, equals(0));
    });

    test('SCENARIO-TAX-54 taxDeductionType = four_insurance_fixed 기록', () {
      final r = TaxDeductionService.applyDeduction(
        base: _base(300000),
        taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed,
        workYear: 2026,
      );
      expect(r.taxDeductionType, equals(InsuranceRateModel.typeFourInsuranceFixed));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 9. applyDay8Retroactive 심화
  // ─────────────────────────────────────────────────────────────────────────
  group('TaxDeductionService: applyDay8Retroactive — 음수 prevGross + 소급 초과', () {
    test('SCENARIO-TAX-55 prevGrossTotal=-100 → safePrev=0 → retroactive=0', () {
      // 음수 prevGrossTotal 방어 (BUG-TAX-02)
      final r = TaxDeductionService.applyDay8Retroactive(
        day8Base: _base(200000),
        prevGrossTotal: -100,
        workYear: 2026,
      );
      expect(r.retroactiveDeduction, equals(0));
    });

    test('SCENARIO-TAX-56 prevGrossTotal=0 → retroactive=0', () {
      final r = TaxDeductionService.applyDay8Retroactive(
        day8Base: _base(200000),
        prevGrossTotal: 0,
        workYear: 2026,
      );
      expect(r.retroactiveDeduction, equals(0));
    });

    test('SCENARIO-TAX-57 prevGrossTotal=700000 → 소급액=61722 (국민연금+건강+장기요양)', () {
      // prevPension=(700000*4.75/100).round()=33250
      // prevHealth=(700000*3.595/100).round()=25165
      // prevLtc=(25165*13.14/100).round()=(3306.681).round()=3307
      // retroactive=33250+25165+3307=61722 (고용보험 제외)
      final prevPension    = _r(700000 * _pension / 100);    // 33250
      final prevHealth     = _r(700000 * _health / 100);     // 25165
      final prevLtc        = _r(prevHealth * _ltcRate / 100);// 3307
      final expectedRetro  = prevPension + prevHealth + prevLtc; // 61722

      final r = TaxDeductionService.applyDay8Retroactive(
        day8Base: _base(200000),
        prevGrossTotal: 700000,
        workYear: 2026,
      );
      expect(r.retroactiveDeduction, equals(expectedRetro));
    });

    test('SCENARIO-TAX-58 8일차 당일 totalAmount=50000, prev=700000 → netWage<0', () {
      // 소급(61722) + 당일4대보험 + 소득세 > 50000 → netWage 음수
      final r = TaxDeductionService.applyDay8Retroactive(
        day8Base: _base(50000),
        prevGrossTotal: 700000,
        workYear: 2026,
      );
      // netWage=-16581 (소급공제가 당일 급여 초과)
      expect(r.netWage, lessThan(0));
    });

    test('SCENARIO-TAX-59 8일차 당일 totalAmount=50000: taxable=(50000-150000)=0 → incomeTax8=0', () {
      // 8일차 당일 50000 < 비과세한도 150000 → 소득세 없음
      final r = TaxDeductionService.applyDay8Retroactive(
        day8Base: _base(50000),
        prevGrossTotal: 0, // 소급 없음으로 고정해 당일분만 확인
        workYear: 2026,
      );
      expect(r.incomeTaxDeduction, equals(0));
    });

    test('SCENARIO-TAX-60 taxDeductionType = daily_auto_8 기록', () {
      final r = TaxDeductionService.applyDay8Retroactive(
        day8Base: _base(200000),
        prevGrossTotal: 700000,
        workYear: 2026,
      );
      expect(r.taxDeductionType, equals(InsuranceRateModel.typeDailyAuto8));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 10. WageCalculator.calculate → TaxDeductionService.applyDeduction 통합
  // ─────────────────────────────────────────────────────────────────────────
  group('통합: WageCalculator.calculate → TaxDeductionService.applyDeduction', () {
    final workDate = DateTime(2026, 6, 1);

    test('SCENARIO-TAX-61 시급 10320 × 8시간(480min) → daily_worker → netWage=81817', () {
      // totalAmount=(480*10320/60).round()=82560
      // taxable=(82560-150000).clamp(0,82560)=0 → incomeTax=0
      // employment=(82560*0.9/100).round()=(743.04).round()=743
      // netWage=82560-743=81817
      final base = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 10320, workDate: workDate,
        scheduledStart: '09:00', scheduledEnd: '17:00',
        actualStart: '09:00', actualEnd: '17:00',
        breakMinutes: 0, nightAllowanceApplied: false,
      );
      expect(base.totalAmount, equals(82560));

      final result = TaxDeductionService.applyDeduction(
        base: base,
        taxDeductionType: InsuranceRateModel.typeDailyWorker,
        workYear: 2026,
      );
      expect(result.incomeTaxDeduction, equals(0));
      expect(result.employmentInsuranceDeduction, equals(743));
      expect(result.netWage, equals(81817));
    });

    test('SCENARIO-TAX-62 시급 15000 × 9시간(540min) → daily_worker → netWage=141217', () {
      // 540min: 정규480 + 연장60
      // baseAmount=(480*15000/60).round()=120000
      // overtimeAmount=(60*15000*1.5/60).round()=22500
      // totalAmount=142500
      // taxable=(142500-150000).clamp(0,142500)=0 → incomeTax=0
      // employment=(142500*0.9/100).round()=(1282.5).round()=1283
      // netWage=142500-0-1283=141217
      final base = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 15000, workDate: workDate,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00',
        breakMinutes: 0, nightAllowanceApplied: false,
      );
      expect(base.totalAmount, equals(142500));

      final result = TaxDeductionService.applyDeduction(
        base: base,
        taxDeductionType: InsuranceRateModel.typeDailyWorker,
        workYear: 2026,
      );
      expect(result.employmentInsuranceDeduction, equals(1283));
      expect(result.netWage, equals(141217));
    });

    test('SCENARIO-TAX-63 일급 100000 × 8시간 → four_insurance_fixed → netWage=90283', () {
      // schedWork=480min, work=480min → baseAmount=100000, totalAmount=100000
      // pension=4750, health=3595, ltc=(3595*13.14/100).round()=472, employment=900
      // total=9717, netWage=90283
      final base = WageCalculator.calculate(
        wageType: 'daily', baseWage: 100000, workDate: workDate,
        scheduledStart: '09:00', scheduledEnd: '17:00',
        actualStart: '09:00', actualEnd: '17:00',
        breakMinutes: 0, nightAllowanceApplied: false,
      );
      expect(base.totalAmount, equals(100000));

      final result = TaxDeductionService.applyDeduction(
        base: base,
        taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed,
        workYear: 2026,
      );
      expect(result.nationalPensionDeduction, equals(4750));
      expect(result.healthInsuranceDeduction, equals(3595));
      expect(result.ltcInsuranceDeduction, equals(472));
      expect(result.employmentInsuranceDeduction, equals(900));
      expect(result.netWage, equals(90283));
    });

    test('SCENARIO-TAX-64 시급 20000 × 4시간 → freelancer_3_3 → netWage=77360', () {
      // totalAmount=(240*20000/60).round()=80000
      // incomeTax=(80000*3.0/100).round()=2400, local=240, total=2640
      // netWage=80000-2640=77360
      final base = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 20000, workDate: workDate,
        scheduledStart: '09:00', scheduledEnd: '13:00',
        actualStart: '09:00', actualEnd: '13:00',
        breakMinutes: 0, nightAllowanceApplied: false,
      );
      expect(base.totalAmount, equals(80000));

      final result = TaxDeductionService.applyDeduction(
        base: base,
        taxDeductionType: InsuranceRateModel.typeFreelancer33,
        workYear: 2026,
      );
      expect(result.incomeTaxDeduction, equals(2640));
      expect(result.netWage, equals(77360));
    });

    test('SCENARIO-TAX-65 none → netWage = totalAmount (공제 없음)', () {
      final base = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 12000, workDate: workDate,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00',
        breakMinutes: 60, nightAllowanceApplied: false,
      );
      // workMins=480-60=420? No: (actualMins=540, breakMins=60) → workMins=480
      // Wait: actualEnd=18:00, actualStart=09:00 → actualMinutes=540 (9h)
      // workMinutes=(540-60).clamp=480, overtime=(480-480)=0
      // baseAmount=(480*12000/60).round()=96000
      // totalAmount=96000
      final result = TaxDeductionService.applyDeduction(
        base: base,
        taxDeductionType: InsuranceRateModel.typeNone,
        workYear: 2026,
      );
      expect(result.netWage, equals(base.totalAmount));
      expect(result.taxDeductionType, equals(InsuranceRateModel.typeNone));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 11. calculateWeeklyHolidayPay 심화
  // ─────────────────────────────────────────────────────────────────────────
  group('WageCalculator.calculateWeeklyHolidayPay — 심화 경계 케이스', () {
    const wage = 10320;

    test('SCENARIO-TAX-66 weeklyWorkMinutes=0 → 0 (15시간 미만)', () {
      expect(
        WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: wage, weeklyWorkMinutes: 0,
        ),
        equals(0),
      );
    });

    test('SCENARIO-TAX-67 weeklyWorkMinutes=900(정확히 15h) → 30960원 비례 계산', () {
      // weeklyHours=15.0, (15/40)*8*10320=30960.0 → round=30960
      expect(
        WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: wage, weeklyWorkMinutes: 900,
        ),
        equals(30960),
      );
    });

    test('SCENARIO-TAX-68 weeklyWorkMinutes=1200(20h) → 41280원', () {
      // weeklyHours=20.0, (20/40)*8*10320=41280.0 → round=41280
      expect(
        WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: wage, weeklyWorkMinutes: 1200,
        ),
        equals(41280),
      );
    });

    test('SCENARIO-TAX-69 weeklyWorkMinutes=2401(>40h) → clamp 40h → 82560원', () {
      // (2401/60.0=40.016...).clamp(0,40)=40.0 → (40/40)*8*10320=82560
      final at40 = WageCalculator.calculateWeeklyHolidayPay(
        ordinaryHourlyWage: wage, weeklyWorkMinutes: 2400,
      );
      final over40 = WageCalculator.calculateWeeklyHolidayPay(
        ordinaryHourlyWage: wage, weeklyWorkMinutes: 2401,
      );
      expect(over40, equals(at40));
      expect(over40, equals(82560));
    });

    test('SCENARIO-TAX-70 (weeklyHours/40)*8*ordinaryWage 공식: 12000원 × 30h → 72000원', () {
      // (30/40)*8*12000=(0.75)*8*12000=72000
      expect(
        WageCalculator.calculateWeeklyHolidayPay(
          ordinaryHourlyWage: 12000, weeklyWorkMinutes: 1800,
        ),
        equals(72000),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 12. WageDetailModel getter 보조 검증
  // ─────────────────────────────────────────────────────────────────────────
  group('WageDetailModel — wageTypeLabel / taxDeductionLabel getter', () {
    test('SCENARIO-TAX-71 wageTypeLabel: hourly → 시급', () {
      final m = WageDetailModel(wageType: 'hourly', baseWage: 10320);
      expect(m.wageTypeLabel, equals('시급'));
    });

    test('SCENARIO-TAX-72 wageTypeLabel: daily → 일급', () {
      final m = WageDetailModel(wageType: 'daily', baseWage: 100000);
      expect(m.wageTypeLabel, equals('일급'));
    });

    test('SCENARIO-TAX-73 taxDeductionLabel: four_insurance_fixed → 4대보험 고정', () {
      final m = TaxDeductionService.applyDeduction(
        base: _base(300000),
        taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed,
        workYear: 2026,
      );
      expect(m.taxDeductionLabel, equals('4대보험 고정'));
    });

    test('SCENARIO-TAX-74 taxDeductionLabel: freelancer_3_3 → 3.3% 원천징수', () {
      final m = TaxDeductionService.applyDeduction(
        base: _base(100000),
        taxDeductionType: InsuranceRateModel.typeFreelancer33,
        workYear: 2026,
      );
      expect(m.taxDeductionLabel, equals('3.3% 원천징수'));
    });

    test('SCENARIO-TAX-75 isCalculated: calculatedAt=null → false', () {
      final m = WageDetailModel(wageType: 'hourly', baseWage: 10320);
      expect(m.isCalculated, isFalse);
    });

    test('SCENARIO-TAX-76 isCalculated: calculatedAt 설정 → true', () {
      final m = WageDetailModel(
        wageType: 'hourly', baseWage: 10320,
        calculatedAt: DateTime(2026, 6, 1),
      );
      expect(m.isCalculated, isTrue);
    });
  });
}
