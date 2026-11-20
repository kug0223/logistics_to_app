// [.82 F1] 급여 정정 미리보기 — 추가수당·추가공제 모두 세전(사용자 결정 2026-11-04).
//   TaxDeductionService.recomputeForAdjustment 는 서버 callableUpdateWageDetail(c82 후보)과 같은 규칙이다.
//   기대값은 이 파일의 독립 산식(2026 기본 요율 상수)으로 계산한다 — 서비스 함수를 기대값에 쓰지 않는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/services/tax_deduction_service.dart';
import 'package:ALfit/utils/wage_calculator.dart';

// InsuranceRateModel.defaults2026() 의 값을 그대로 적는다(독립 기대값).
const pen = 4.75, hlt = 3.595, ltc = 13.14, emp = 0.9, ex = 150000, dtax = 2.7, loc = 10.0, biz = 3.0;
int rd(num v) => v.round();
int tax33(int g) { final i = rd(g * biz / 100); return i + rd(i * loc / 100); }
int dailyTax(int g) { final t = g - ex > 0 ? g - ex : 0; final i = t > 0 ? rd(t * dtax / 100) : 0; return i + (i > 0 ? rd(i * loc / 100) : 0); }
({int pen, int hlt, int ltc, int emp}) four(int g) { final h = rd(g * hlt / 100); return (pen: rd(g * pen / 100), hlt: h, ltc: rd(h * ltc / 100), emp: rd(g * emp / 100)); }

WageDetailModel gross(int wage) => WageCalculator.calculate(
      wageType: 'hourly', baseWage: wage, workDate: DateTime.utc(2026, 11, 3, 15),
      scheduledStart: '09:00', scheduledEnd: '18:00', actualStart: '09:00', actualEnd: '18:00', breakMinutes: 60);
WageDetailModel stored(String type, int wage) =>
    TaxDeductionService.applyDeduction(base: gross(wage), taxDeductionType: type, workYear: 2026);
WageDetailModel edit(WageDetailModel s, {int add = 0, int ded = 0, String? memo}) => s.copyWith(
      additionalAmount: add, deductionAmount: ded, memo: memo,
      totalAmount: s.baseAmount + s.overtimeAmount + s.nightAmount + add - ded + s.weeklyHolidayAmount);
WageDetailModel re(WageDetailModel s, WageDetailModel e) =>
    TaxDeductionService.recomputeForAdjustment(stored: s, edited: e, workYear: 2026);

void main() {
  test('요율 상수가 앱 2026 기본값과 같다(기대값 전제)', () {
    final r = InsuranceRateModel.defaults2026();
    expect([r.nationalPensionRate, r.healthInsuranceRate, r.ltcInsuranceRate, r.employmentInsuranceRate, r.businessIncomeRate, r.localIncomeTaxRate],
        [pen, hlt, ltc, emp, biz, loc]);
  });

  group('3.3% — .82 실측 사례(18,000원 근무, 추가수당 1,000)', () {
    // 18,000 = 1.5h × 12,000. 계산 확정 공제 594 / 실수령 17,406 (DEV r20)
    final s = TaxDeductionService.applyDeduction(
        base: gross(12000).copyWith(baseAmount: 18000, overtimeAmount: 0, nightAmount: 0, totalAmount: 18000),
        taxDeductionType: InsuranceRateModel.typeFreelancer33, workYear: 2026);
    test('저장 공제 594', () => expect(s.incomeTaxDeduction, 594));
    test('추가수당 1,000 → 공제 627 · 실수령 18,373 (예전 594 · 18,406)', () {
      final r = re(s, edit(s, add: 1000));
      expect(r.totalAmount, 19000);
      expect(r.incomeTaxDeduction, 627);
      expect(r.netWage, 18373);
      expect(r.taxDeductionType, InsuranceRateModel.typeFreelancer33);
    });
    test('추가공제 1,000(대가감액) → 총액 17,000 · 공제 561 · 실수령 16,439', () {
      final r = re(s, edit(s, ded: 1000));
      expect([r.totalAmount, r.incomeTaxDeduction, r.netWage], [17000, tax33(17000), 17000 - tax33(17000)]);
      expect(r.incomeTaxDeduction, 561);
    });
  });

  test('총액이 그대로면(메모만) 저장 공제를 그대로 둔다 — 요율 시점이 돈을 바꾸지 않는다', () {
    final s = stored(InsuranceRateModel.typeFreelancer33, 12000).copyWith(incomeTaxDeduction: 600, netWage: 96000 - 600);
    final r = re(s, edit(s, memo: '메모'));
    expect([r.incomeTaxDeduction, r.netWage, r.memo], [600, 95400, '메모']);
  });

  test('추가수당 후 0으로 되돌리면 저장 공제로 돌아온다', () {
    final s = stored(InsuranceRateModel.typeFreelancer33, 12000);
    expect(re(s, edit(s, add: 0)).netWage, s.netWage);
  });

  test('none — 공제 없음', () {
    final s = stored(InsuranceRateModel.typeNone, 12000);
    final r = re(s, edit(s, add: 5000));
    expect([r.totalAmount, r.netWage, r.totalInsuranceDeduction], [101000, 101000, 0]);
  });

  test('daily_worker — 비과세 초과분 과세 + 고용보험', () {
    final s = stored(InsuranceRateModel.typeDailyWorker, 25000);
    final g = 203000; final r = re(s, edit(s, add: 3000));
    expect([r.incomeTaxDeduction, r.employmentInsuranceDeduction, r.netWage], [dailyTax(g), rd(g * emp / 100), g - dailyTax(g) - rd(g * emp / 100)]);
  });

  test('four_insurance_fixed — 추가수당·추가공제 함께', () {
    final s = stored(InsuranceRateModel.typeFourInsuranceFixed, 12000);
    final g = 96000 + 2000 - 500; final f = four(g); final r = re(s, edit(s, add: 2000, ded: 500));
    expect([r.nationalPensionDeduction, r.healthInsuranceDeduction, r.ltcInsuranceDeduction, r.employmentInsuranceDeduction, r.incomeTaxDeduction],
        [f.pen, f.hlt, f.ltc, f.emp, 0]);
    expect(r.netWage, g - f.pen - f.hlt - f.ltc - f.emp);
  });

  group('daily_auto_8 — 금액 정정 없음, 메모만 (.82-4 · 82_audit_04)', () {
    // 순번·소급분은 월 단위 계산이라 하루 정정으로 맞출 수 없다 — 미리보기는 저장값 그대로, 메모만 바뀐다(서버 D8_AMOUNT_LOCKED 와 같은 규칙).
    void same(WageDetailModel s, WageDetailModel r) {
      expect([r.totalAmount, r.netWage, r.additionalAmount, r.deductionAmount, r.nationalPensionDeduction, r.healthInsuranceDeduction,
          r.ltcInsuranceDeduction, r.employmentInsuranceDeduction, r.incomeTaxDeduction, r.retroactiveDeduction],
          [s.totalAmount, s.netWage, s.additionalAmount, s.deductionAmount, s.nationalPensionDeduction, s.healthInsuranceDeduction,
          s.ltcInsuranceDeduction, s.employmentInsuranceDeduction, s.incomeTaxDeduction, s.retroactiveDeduction]);
    }
    test('1~7일차 — 추가수당을 넣어도 저장값 그대로', () {
      final s = stored(InsuranceRateModel.typeDailyAuto8, 25000);
      same(s, re(s, edit(s, add: 4000)));
    });
    test('8일차 — 소급분 포함 저장값 그대로, 메모만 바뀐다', () {
      final s = TaxDeductionService.applyDay8Retroactive(day8Base: gross(25000), prevGrossTotal: 350000, workYear: 2026);
      expect(s.retroactiveDeduction, greaterThan(0));
      final r = re(s, edit(s, add: 4000, memo: '메모'));
      same(s, r);
      expect(r.memo, '메모');
    });
    test('9일차 이후 — 총액을 0원으로 만드는 추가공제도 반영하지 않는다(F1a 0원 왕복 경로 없음)', () {
      final b = gross(25000); final f0 = four(200000);
      final s = b.copyWith(taxDeductionType: InsuranceRateModel.typeDailyAuto8, nationalPensionDeduction: f0.pen, healthInsuranceDeduction: f0.hlt,
          ltcInsuranceDeduction: f0.ltc, employmentInsuranceDeduction: f0.emp, incomeTaxDeduction: dailyTax(200000),
          netWage: 200000 - f0.pen - f0.hlt - f0.ltc - f0.emp - dailyTax(200000));
      same(s, re(s, edit(s, ded: s.totalAmount)));
    });
  });

  group('daily_auto_8 미확정 미리보기 — 입력 반영 (.82-5, calculatedAdjustment: false)', () {
    WageDetailModel pre(WageDetailModel s, WageDetailModel e) =>
        TaxDeductionService.recomputeForAdjustment(stored: s, edited: e, workYear: 2026, calculatedAdjustment: false);
    test('1~7일차 미리보기 — 고용보험+소득세 재계산', () {
      final s = stored(InsuranceRateModel.typeDailyAuto8, 25000);
      final g = 204000; final r = pre(s, edit(s, add: 4000));
      expect(r.totalAmount, g);
      expect(r.nationalPensionDeduction, 0);
      expect(r.netWage, g - rd(g * emp / 100) - dailyTax(g));
    });
    test('9일차 이후 미리보기 — 4대보험+소득세 재계산', () {
      final b = gross(25000); final f0 = four(200000);
      final s = b.copyWith(taxDeductionType: InsuranceRateModel.typeDailyAuto8, nationalPensionDeduction: f0.pen, healthInsuranceDeduction: f0.hlt,
          ltcInsuranceDeduction: f0.ltc, employmentInsuranceDeduction: f0.emp, incomeTaxDeduction: dailyTax(200000),
          netWage: 200000 - f0.pen - f0.hlt - f0.ltc - f0.emp - dailyTax(200000));
      final g = 204000; final f = four(g); final r = pre(s, edit(s, add: 4000));
      expect(r.netWage, g - f.pen - f.hlt - f.ltc - f.emp - dailyTax(g));
    });
  });

  test('주휴수당은 총액에 남는다(휴게 변경 경로가 0으로 만들던 값)', () {
    final s = stored(InsuranceRateModel.typeFreelancer33, 12000).copyWith(weeklyHolidayAmount: 3000, totalAmount: 99000);
    final r = re(s, edit(s, add: 1000));
    expect([r.totalAmount, r.incomeTaxDeduction, r.netWage], [100000, tax33(100000), 100000 - tax33(100000)]);
  });
}
