// test/payroll_simulation_test.dart
// 급여 계산 핵심 시나리오 10개
// Firebase 미사용 (WageCalculator/InsuranceRateService 로컬 백업 사용)

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/wage_calculator.dart';
import 'package:ALfit/services/tax_deduction_service.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';

void main() {
  final d2026 = DateTime(2026, 6, 1); // 최저시급 10,320원

  // ────────────────────────────────────────────────────────────────────
  // S01. 시급제 — 정상 근무 (09:00~18:00, break=60, 시급=10,000)
  // workMinutes=480, 연장/야간 없음, baseAmount=80,000
  // ────────────────────────────────────────────────────────────────────
  group('S01 시급제 정상 근무', () {
    late var r = WageCalculator.calculate(
      wageType: 'hourly',
      baseWage: 10000,
      workDate: d2026,
      scheduledStart: '09:00',
      scheduledEnd: '18:00',
      actualStart: '09:00',
      actualEnd: '18:00',
      breakMinutes: 60,
    );
    test('workMinutes = 480', () => expect(r.workMinutes, 480));
    test('overtimeMinutes = 0', () => expect(r.overtimeMinutes, 0));
    test('nightMinutes = 0', () => expect(r.nightMinutes, 0));
    test('baseAmount = 80000', () => expect(r.baseAmount, 80000));
    test('totalAmount = 80000', () => expect(r.totalAmount, 80000));
    test('appliedMinimumWage = 10320', () => expect(r.appliedMinimumWage, 10320));
  });

  // ────────────────────────────────────────────────────────────────────
  // S02. 시급제 — 조출 (실제 08:00 출근, 예정 09:00~18:00, break=60)
  // workMinutes=540, 연장 60분, overtimeAmount=15,000
  // ────────────────────────────────────────────────────────────────────
  group('S02 시급제 조출', () {
    late var r = WageCalculator.calculate(
      wageType: 'hourly',
      baseWage: 10000,
      workDate: d2026,
      scheduledStart: '09:00',
      scheduledEnd: '18:00',
      actualStart: '08:00',
      actualEnd: '18:00',
      breakMinutes: 60,
    );
    test('workMinutes = 540', () => expect(r.workMinutes, 540));
    test('overtimeMinutes = 60', () => expect(r.overtimeMinutes, 60));
    // baseAmount = (480 * 10000 / 60).round() = 80,000
    test('baseAmount = 80000', () => expect(r.baseAmount, 80000));
    // overtimeAmount = (60 * 10000 * 1.5 / 60).round() = 15,000
    test('overtimeAmount = 15000', () => expect(r.overtimeAmount, 15000));
    test('totalAmount = 95000', () => expect(r.totalAmount, 95000));
  });

  // ────────────────────────────────────────────────────────────────────
  // S03. 시급제 — 지각 (실제 10:00 출근, 예정 09:00~18:00, break=60)
  // workMinutes=420, 연장 없음, baseAmount=70,000
  // ────────────────────────────────────────────────────────────────────
  group('S03 시급제 지각', () {
    late var r = WageCalculator.calculate(
      wageType: 'hourly',
      baseWage: 10000,
      workDate: d2026,
      scheduledStart: '09:00',
      scheduledEnd: '18:00',
      actualStart: '10:00',
      actualEnd: '18:00',
      breakMinutes: 60,
    );
    test('workMinutes = 420', () => expect(r.workMinutes, 420));
    test('overtimeMinutes = 0', () => expect(r.overtimeMinutes, 0));
    // baseAmount = (420 * 10000 / 60).round() = 70,000
    test('baseAmount = 70000', () => expect(r.baseAmount, 70000));
    test('totalAmount = 70000', () => expect(r.totalAmount, 70000));
  });

  // ────────────────────────────────────────────────────────────────────
  // S04. 시급제 — 조퇴 (09:00~15:00, break=60, 시급=10,000)
  // workMinutes=300, baseAmount=50,000
  // ────────────────────────────────────────────────────────────────────
  group('S04 시급제 조퇴', () {
    late var r = WageCalculator.calculate(
      wageType: 'hourly',
      baseWage: 10000,
      workDate: d2026,
      scheduledStart: '09:00',
      scheduledEnd: '18:00',
      actualStart: '09:00',
      actualEnd: '15:00',
      breakMinutes: 60,
    );
    test('actualMinutes = 360', () => expect(r.actualMinutes, 360));
    test('workMinutes = 300', () => expect(r.workMinutes, 300));
    test('overtimeMinutes = 0', () => expect(r.overtimeMinutes, 0));
    // baseAmount = (300 * 10000 / 60).round() = 50,000
    test('baseAmount = 50000', () => expect(r.baseAmount, 50000));
    test('totalAmount = 50000', () => expect(r.totalAmount, 50000));
  });

  // ────────────────────────────────────────────────────────────────────
  // S05. 시급제 — 연장 (09:00~20:00, break=60, 시급=10,000)
  // workMinutes=600, 연장 120분, overtimeAmount=30,000
  // ────────────────────────────────────────────────────────────────────
  group('S05 시급제 연장 2시간', () {
    late var r = WageCalculator.calculate(
      wageType: 'hourly',
      baseWage: 10000,
      workDate: d2026,
      scheduledStart: '09:00',
      scheduledEnd: '18:00',
      actualStart: '09:00',
      actualEnd: '20:00',
      breakMinutes: 60,
    );
    test('workMinutes = 600', () => expect(r.workMinutes, 600));
    test('overtimeMinutes = 120', () => expect(r.overtimeMinutes, 120));
    test('baseAmount = 80000', () => expect(r.baseAmount, 80000));
    // overtimeAmount = (120 * 10000 * 1.5 / 60).round() = 30,000
    test('overtimeAmount = 30000', () => expect(r.overtimeAmount, 30000));
    test('totalAmount = 110000', () => expect(r.totalAmount, 110000));
  });

  // ────────────────────────────────────────────────────────────────────
  // S06. 시급제 — 심야 전체 (22:00~06:00, break=0, 시급=12,000)
  // workMinutes=480, nightMinutes=480
  // nightAmount = (480 * 12000 * 0.5 / 60).round() = 48,000
  // ────────────────────────────────────────────────────────────────────
  group('S06 시급제 심야 전체 (22:00~06:00)', () {
    late var r = WageCalculator.calculate(
      wageType: 'hourly',
      baseWage: 12000,
      workDate: d2026,
      scheduledStart: '22:00',
      scheduledEnd: '06:00',
      actualStart: '22:00',
      actualEnd: '06:00',
      breakMinutes: 0,
    );
    test('actualMinutes = 480', () => expect(r.actualMinutes, 480));
    test('workMinutes = 480', () => expect(r.workMinutes, 480));
    test('overtimeMinutes = 0', () => expect(r.overtimeMinutes, 0));
    test('nightMinutes = 480', () => expect(r.nightMinutes, 480));
    test('baseAmount = 96000', () => expect(r.baseAmount, 96000));
    test('nightAmount = 48000', () => expect(r.nightAmount, 48000));
    test('totalAmount = 144000', () => expect(r.totalAmount, 144000));
  });

  // ────────────────────────────────────────────────────────────────────
  // S07. 시급제 — 연장+야간 (17:00~03:00, break=60, 시급=12,000)
  // actualMinutes=600, workMinutes=540, overtime=60, nightMinutes=300
  // baseAmount=(480*12000/60)=96000, ot=(60*12000*1.5/60)=18000
  // nightAmount=(300*12000*0.5/60)=30000, total=144000
  // ────────────────────────────────────────────────────────────────────
  group('S07 시급제 연장+야간 (17:00~03:00)', () {
    late var r = WageCalculator.calculate(
      wageType: 'hourly',
      baseWage: 12000,
      workDate: d2026,
      scheduledStart: '17:00',
      scheduledEnd: '03:00',
      actualStart: '17:00',
      actualEnd: '03:00',
      breakMinutes: 60,
    );
    test('workMinutes = 540', () => expect(r.workMinutes, 540));
    test('overtimeMinutes = 60', () => expect(r.overtimeMinutes, 60));
    test('nightMinutes = 300', () => expect(r.nightMinutes, 300));
    test('baseAmount = 96000', () => expect(r.baseAmount, 96000));
    test('overtimeAmount = 18000', () => expect(r.overtimeAmount, 18000));
    test('nightAmount = 30000', () => expect(r.nightAmount, 30000));
    test('totalAmount = 144000', () => expect(r.totalAmount, 144000));
  });

  // ────────────────────────────────────────────────────────────────────
  // S08. 일급제 — 조퇴 (09:00~15:00, break=60, sched=09:00~18:00, 일급=100,000)
  // scheduledWorkMinutes=480, workMinutes=300
  // baseAmount=(100000*300/480).round()=62500
  // ────────────────────────────────────────────────────────────────────
  group('S08 일급제 조퇴 (비율 계산)', () {
    late var r = WageCalculator.calculate(
      wageType: 'daily',
      baseWage: 100000,
      workDate: d2026,
      scheduledStart: '09:00',
      scheduledEnd: '18:00',
      actualStart: '09:00',
      actualEnd: '15:00',
      breakMinutes: 60,
      scheduledBreakMinutes: 60,
    );
    test('scheduledMinutes = 540', () => expect(r.scheduledMinutes, 540));
    test('workMinutes = 300', () => expect(r.workMinutes, 300));
    test('overtimeMinutes = 0', () => expect(r.overtimeMinutes, 0));
    // 300/480 비율 적용
    test('baseAmount = 62500', () => expect(r.baseAmount, 62500));
    test('totalAmount = 62500', () => expect(r.totalAmount, 62500));
  });

  // ────────────────────────────────────────────────────────────────────
  // S09. 일급제 — 연장 (09:00~21:00, break=60, sched=09:00~16:00 schedBreak=60, 일급=100,000)
  // scheduledWorkMinutes=360, workMinutes=660, overtime=300
  // supplementWage=max((100000/360*60).round(), 10320)=16667
  // workMinutes(660)>480: over8=180, within8=120
  // ot1x=(120*16667/60)=33334, ot15x=(180*16667*1.5/60)=75002
  // total=100000+108336=208336
  // ────────────────────────────────────────────────────────────────────
  group('S09 일급제 연장 8h 초과 (1배+1.5배 분리)', () {
    late var r = WageCalculator.calculate(
      wageType: 'daily',
      baseWage: 100000,
      workDate: d2026,
      scheduledStart: '09:00',
      scheduledEnd: '16:00',
      actualStart: '09:00',
      actualEnd: '21:00',
      breakMinutes: 60,
      scheduledBreakMinutes: 60,
    );
    test('workMinutes = 660', () => expect(r.workMinutes, 660));
    test('overtimeMinutes = 300', () => expect(r.overtimeMinutes, 300));
    test('baseAmount = 100000 (일급 전액)', () => expect(r.baseAmount, 100000));
    // ot1x(120*16667/60)+ot15x(180*16667*1.5/60)=33334+75002=108336
    test('overtimeAmount = 108336', () => expect(r.overtimeAmount, 108336));
    test('totalAmount = 208336', () => expect(r.totalAmount, 208336));
  });

  // ────────────────────────────────────────────────────────────────────
  // S10. 세금 공제 — freelancer_3_3 + daily_worker + four_insurance (gross=100,000, 2026년)
  // 시급 12,500 × 8h = (480*12500/60) = 100,000
  // freelancer: incomeTax=(100000*3%=3000), local=(3000*10%=300) → net=96700
  // daily_worker: taxable=0(100000<150000), employment=(100000*0.9%=900) → net=99100
  // four_insurance: pension=4750, health=3595, ltc=472, employment=900 → net=90283
  // ────────────────────────────────────────────────────────────────────
  group('S10 세금 공제 5종 (gross=100,000)', () {
    // 시급 12,500 × 8h = totalAmount 100,000
    final base = WageCalculator.calculate(
      wageType: 'hourly',
      baseWage: 12500,
      workDate: d2026,
      scheduledStart: '09:00',
      scheduledEnd: '18:00',
      actualStart: '09:00',
      actualEnd: '18:00',
      breakMinutes: 60,
    );
    // gross = 100,000원 확인
    test('gross = 100000', () => expect(base.totalAmount, 100000));

    group('none', () {
      final r = TaxDeductionService.applyDeduction(
        base: base, taxDeductionType: InsuranceRateModel.typeNone, workYear: 2026,
      );
      test('netWage = 100000', () => expect(r.netWage, 100000));
      test('incomeTaxDeduction = 0', () => expect(r.incomeTaxDeduction, 0));
    });

    group('freelancer_3_3', () {
      final r = TaxDeductionService.applyDeduction(
        base: base, taxDeductionType: InsuranceRateModel.typeFreelancer33, workYear: 2026,
      );
      // incomeTax=(100000*3.0/100).round()=3000, local=(3000*10/100).round()=300
      test('incomeTaxDeduction = 3300', () => expect(r.incomeTaxDeduction, 3300));
      test('netWage = 96700', () => expect(r.netWage, 96700));
    });

    group('daily_worker (100,000원 ≤ 150,000 비과세)', () {
      final r = TaxDeductionService.applyDeduction(
        base: base, taxDeductionType: InsuranceRateModel.typeDailyWorker, workYear: 2026,
      );
      // taxable=0, incomeTax=0, employment=(100000*0.9/100).round()=900
      test('incomeTaxDeduction = 0', () => expect(r.incomeTaxDeduction, 0));
      test('employmentInsuranceDeduction = 900', () => expect(r.employmentInsuranceDeduction, 900));
      test('netWage = 99100', () => expect(r.netWage, 99100));
    });

    group('daily_auto_8 1~7일차', () {
      final r = TaxDeductionService.applyDeduction(
        base: base, taxDeductionType: InsuranceRateModel.typeDailyAuto8, workYear: 2026,
      );
      // 고용보험만: employment=900, incomeTax=0 (100000<150000)
      test('employmentInsuranceDeduction = 900', () => expect(r.employmentInsuranceDeduction, 900));
      test('nationalPensionDeduction = 0 (소급 전)', () => expect(r.nationalPensionDeduction, 0));
      test('netWage = 99100', () => expect(r.netWage, 99100));
    });

    group('four_insurance_fixed', () {
      final r = TaxDeductionService.applyDeduction(
        base: base, taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed, workYear: 2026,
      );
      // pension=4750, health=3595, ltc=(3595*13.14/100).round()=472, employment=900
      test('nationalPensionDeduction = 4750', () => expect(r.nationalPensionDeduction, 4750));
      test('healthInsuranceDeduction = 3595', () => expect(r.healthInsuranceDeduction, 3595));
      test('ltcInsuranceDeduction = 472', () => expect(r.ltcInsuranceDeduction, 472));
      test('employmentInsuranceDeduction = 900', () => expect(r.employmentInsuranceDeduction, 900));
      test('netWage = 90283', () => expect(r.netWage, 90283));
    });
  });
}
