// test/payroll_simulation_extended_test.dart
// 급여 계산 확장 시나리오 — 야간/연장/일급 복합, 세금공제, 지급예정일, 주휴수당, 경계값

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/wage_calculator.dart';
import 'package:ALfit/utils/payment_due_date_calculator.dart';
import 'package:ALfit/services/tax_deduction_service.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';

void main() {
  final d2026 = DateTime(2026, 6, 1);
  final d2025 = DateTime(2025, 6, 1);
  final d2024 = DateTime(2024, 6, 1);
  final d2023 = DateTime(2023, 6, 1);

  // ════════════════════════════════════════════════════════════════════
  // Group A2: 시급제 추가 케이스
  // ════════════════════════════════════════════════════════════════════
  group('A2 시급제 추가', () {

    group('A2-01 부분 심야 (20:00~02:00, break=30, 시급=12000)', () {
      late final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 12000, workDate: d2026,
        scheduledStart: '20:00', scheduledEnd: '02:00',
        actualStart: '20:00', actualEnd: '02:00', breakMinutes: 30,
      );
      // actual=360, work=330, night: overlap(1320~1440)=120 + overlap(1440~1560)=120 = 240
      test('workMinutes = 330',   () => expect(r.workMinutes, 330));
      test('overtimeMinutes = 0', () => expect(r.overtimeMinutes, 0));
      test('nightMinutes = 240',  () => expect(r.nightMinutes, 240));
      // base=(330*12000/60)=66000, night=(240*12000*0.5/60)=24000
      test('baseAmount = 66000',  () => expect(r.baseAmount, 66000));
      test('nightAmount = 24000', () => expect(r.nightAmount, 24000));
      test('totalAmount = 90000', () => expect(r.totalAmount, 90000));
    });

    group('A2-02 자정 넘기 단시간 (23:30~00:30, break=0, 시급=10000)', () {
      late final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 10000, workDate: d2026,
        scheduledStart: '23:30', scheduledEnd: '00:30',
        actualStart: '23:30', actualEnd: '00:30', breakMinutes: 0,
      );
      // actual=60, night: overlap(1320~1440→30) + overlap(1440~1470→30) = 60
      test('actualMinutes = 60',  () => expect(r.actualMinutes, 60));
      test('workMinutes = 60',    () => expect(r.workMinutes, 60));
      test('nightMinutes = 60',   () => expect(r.nightMinutes, 60));
      // base=(60*10000/60)=10000, night=(60*10000*0.5/60)=5000
      test('baseAmount = 10000',  () => expect(r.baseAmount, 10000));
      test('nightAmount = 5000',  () => expect(r.nightAmount, 5000));
      test('totalAmount = 15000', () => expect(r.totalAmount, 15000));
    });

    group('A2-03 야간수당 미적용 플래그 (22:00~06:00, break=0, 시급=12000)', () {
      late final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 12000, workDate: d2026,
        scheduledStart: '22:00', scheduledEnd: '06:00',
        actualStart: '22:00', actualEnd: '06:00', breakMinutes: 0,
        nightAllowanceApplied: false,
      );
      test('nightMinutes = 0 (미적용)', () => expect(r.nightMinutes, 0));
      test('nightAmount = 0',          () => expect(r.nightAmount, 0));
      // 야간수당 없이 기본급만: 96,000
      test('baseAmount = 96000',       () => expect(r.baseAmount, 96000));
      test('totalAmount = 96000',      () => expect(r.totalAmount, 96000));
      test('nightAllowanceApplied=false', () => expect(r.nightAllowanceApplied, false));
    });

    group('A2-04 추가수당 포함 (09:00~18:00, break=60, 시급=10000, +5000)', () {
      late final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 10000, workDate: d2026,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00',
        breakMinutes: 60, additionalAmount: 5000,
      );
      test('baseAmount = 80000',      () => expect(r.baseAmount, 80000));
      test('additionalAmount = 5000', () => expect(r.additionalAmount, 5000));
      test('totalAmount = 85000',     () => expect(r.totalAmount, 85000));
    });

    group('A2-05 연장+심야 (18:00~05:00, break=60, 시급=15000)', () {
      late final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 15000, workDate: d2026,
        scheduledStart: '18:00', scheduledEnd: '05:00',
        actualStart: '18:00', actualEnd: '05:00', breakMinutes: 60,
      );
      // actual=660, work=600, overtime=120, night=420
      test('workMinutes = 600',     () => expect(r.workMinutes, 600));
      test('overtimeMinutes = 120', () => expect(r.overtimeMinutes, 120));
      test('nightMinutes = 420',    () => expect(r.nightMinutes, 420));
      // base=(480*15000/60)=120000, ot=(120*15000*1.5/60)=45000
      // night=(420*15000*0.5/60)=52500
      test('baseAmount = 120000',   () => expect(r.baseAmount, 120000));
      test('overtimeAmount = 45000', () => expect(r.overtimeAmount, 45000));
      test('nightAmount = 52500',   () => expect(r.nightAmount, 52500));
      test('totalAmount = 217500',  () => expect(r.totalAmount, 217500));
    });

    group('A2-06 workMinutes=0 (break > actual, 1h 근무 90min break)', () {
      late final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 10000, workDate: d2026,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '10:00', breakMinutes: 90,
      );
      // (60 - 90).clamp(0, 9999) = 0
      test('workMinutes = 0',   () => expect(r.workMinutes, 0));
      test('baseAmount = 0',    () => expect(r.baseAmount, 0));
      test('totalAmount = 0',   () => expect(r.totalAmount, 0));
    });

    group('A2-07 경계값: 정확히 8시간 (workMinutes=480) — 연장 없음', () {
      late final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 10000, workDate: d2026,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00', breakMinutes: 60,
      );
      test('overtimeMinutes = 0', () => expect(r.overtimeMinutes, 0));
      test('baseAmount = 80000', () => expect(r.baseAmount, 80000));
    });

    group('A2-08 경계값: 8시간 + 1분 (workMinutes=481) — 연장 1분', () {
      late final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 10000, workDate: d2026,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:01',
        breakMinutes: 60,
      );
      // workMinutes = (61min - 60break = 541 actual minutes... wait:
      // 09:00~18:01 = 541min, work=541-60=481
      test('workMinutes = 481',   () => expect(r.workMinutes, 481));
      test('overtimeMinutes = 1', () => expect(r.overtimeMinutes, 1));
      test('baseAmount = 80000',  () => expect(r.baseAmount, 80000));
      // overtime=(1*10000*1.5/60).round()=250
      test('overtimeAmount = 250', () => expect(r.overtimeAmount, 250));
      test('totalAmount = 80250', () => expect(r.totalAmount, 80250));
    });

    group('A2-09 2025년 최저시급 적용 (시급=10000, 8h)', () {
      late final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 10000, workDate: d2025,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00', breakMinutes: 60,
      );
      test('appliedMinimumWage = 10030 (2025년)', () => expect(r.appliedMinimumWage, 10030));
      test('baseAmount = 80000 (설정 시급 유지)', () => expect(r.baseAmount, 80000));
    });

    group('A2-10 2024년 최저시급 적용 (시급=9860, 8h)', () {
      late final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 9860, workDate: d2024,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00', breakMinutes: 60,
      );
      test('appliedMinimumWage = 9860 (2024년)', () => expect(r.appliedMinimumWage, 9860));
      // base=(480*9860/60)=78880
      test('baseAmount = 78880', () => expect(r.baseAmount, 78880));
    });

    group('A2-11 00:00~06:00 순수 심야 (break=0, 시급=10000)', () {
      late final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 10000, workDate: d2026,
        scheduledStart: '00:00', scheduledEnd: '06:00',
        actualStart: '00:00', actualEnd: '06:00', breakMinutes: 0,
      );
      // night: overlap(0,360)=360
      test('actualMinutes = 360', () => expect(r.actualMinutes, 360));
      test('nightMinutes = 360',  () => expect(r.nightMinutes, 360));
      // base=(360*10000/60)=60000, night=(360*10000*0.5/60)=30000
      test('baseAmount = 60000',  () => expect(r.baseAmount, 60000));
      test('nightAmount = 30000', () => expect(r.nightAmount, 30000));
      test('totalAmount = 90000', () => expect(r.totalAmount, 90000));
    });

    group('A2-12 심야 야간 경계 22:00 이전 (09:00~21:59) — nightMinutes=0', () {
      late final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 10000, workDate: d2026,
        scheduledStart: '09:00', scheduledEnd: '21:59',
        actualStart: '09:00', actualEnd: '21:59', breakMinutes: 0,
      );
      // 21:59 = 1319분 → overlap(1320,1440)=max(0,1319-1320)=0
      test('nightMinutes = 0', () => expect(r.nightMinutes, 0));
    });

    group('A2-13 심야 22:00 시작 1분 (22:00~22:01)', () {
      late final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 10000, workDate: d2026,
        scheduledStart: '22:00', scheduledEnd: '22:01',
        actualStart: '22:00', actualEnd: '22:01', breakMinutes: 0,
      );
      // overlap(1320,1440)=max(0,min(1321,1440)-1320)=1
      test('nightMinutes = 1',  () => expect(r.nightMinutes, 1));
      test('nightAmount = 83',  () {
        // (1*10000*0.5/60).round() = 83.33... → 83
        expect(r.nightAmount, 83);
      });
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Group B2: 일급제 추가 케이스
  // ════════════════════════════════════════════════════════════════════
  group('B2 일급제 추가', () {

    group('B2-01 일급제 정상 (09:00~18:00, schedBreak=60, 일급=120000)', () {
      late final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 120000, workDate: d2026,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
      );
      test('workMinutes = 480',      () => expect(r.workMinutes, 480));
      test('overtimeMinutes = 0',    () => expect(r.overtimeMinutes, 0));
      test('baseAmount = 120000',    () => expect(r.baseAmount, 120000));
      test('totalAmount = 120000',   () => expect(r.totalAmount, 120000));
    });

    group('B2-02 일급제 조출 (08:00~18:00, sched=09:00~18:00, 일급=100000)', () {
      late final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 100000, workDate: d2026,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '08:00', actualEnd: '18:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
      );
      // scheduledWorkMins=480, workMins=540 → 전액+연장 60분
      test('workMinutes = 540',      () => expect(r.workMinutes, 540));
      test('overtimeMinutes = 60',   () => expect(r.overtimeMinutes, 60));
      test('baseAmount = 100000',    () => expect(r.baseAmount, 100000));
      // workMins(540)>480 → over8=60, within8=0 → ot15x=(60*12500*1.5/60)=18750
      test('overtimeAmount = 18750', () => expect(r.overtimeAmount, 18750));
      test('totalAmount = 118750',   () => expect(r.totalAmount, 118750));
    });

    group('B2-03 일급제 지각 (10:00~18:00, sched=09:00~18:00, break=60, 일급=100000)', () {
      late final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 100000, workDate: d2026,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '10:00', actualEnd: '18:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
      );
      // workMins=420, schedWorkMins=480 → 비율
      test('workMinutes = 420',      () => expect(r.workMinutes, 420));
      // base=(100000*420/480).round()=87500
      test('baseAmount = 87500',     () => expect(r.baseAmount, 87500));
      test('overtimeMinutes = 0',    () => expect(r.overtimeMinutes, 0));
      test('totalAmount = 87500',    () => expect(r.totalAmount, 87500));
    });

    group('B2-04 일급제 연장 8h 이하 (sched=09:00~16:00, actual=09:00~18:00, 일급=100000)', () {
      late final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 100000, workDate: d2026,
        scheduledStart: '09:00', scheduledEnd: '16:00',
        actualStart: '09:00', actualEnd: '18:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
      );
      // schedWorkMins=360, workMins=480, overtime=120
      test('workMinutes = 480',      () => expect(r.workMinutes, 480));
      test('overtimeMinutes = 120',  () => expect(r.overtimeMinutes, 120));
      test('baseAmount = 100000',    () => expect(r.baseAmount, 100000));
      // workMins(480)<=480 → 1배: (120*16667/60)=33334
      test('overtimeAmount = 33334', () => expect(r.overtimeAmount, 33334));
      test('totalAmount = 133334',   () => expect(r.totalAmount, 133334));
    });

    group('B2-05 일급제 nightIncluded=true 정상 (21:00~06:00, 일급=100000)', () {
      late final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 100000, workDate: d2026,
        scheduledStart: '21:00', scheduledEnd: '06:00',
        actualStart: '21:00', actualEnd: '06:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        nightIncluded: true,
      );
      // overtime=0 → nightIncluded=true이지만 초과 없음 → nightMinutes=0
      test('overtimeMinutes = 0',    () => expect(r.overtimeMinutes, 0));
      test('nightMinutes = 0 (포함)', () => expect(r.nightMinutes, 0));
      test('nightAmount = 0',        () => expect(r.nightAmount, 0));
      test('totalAmount = 100000',   () => expect(r.totalAmount, 100000));
    });

    group('B2-06 일급제 nightIncluded=true 연장 (21:00~06:00→09:00, 일급=100000)', () {
      late final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 100000, workDate: d2026,
        scheduledStart: '21:00', scheduledEnd: '06:00',
        actualStart: '21:00', actualEnd: '09:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        nightIncluded: true,
      );
      // overtime=180: _calculateNightMinutes("06:00","09:00")=0 (06:00~09:00은 주간)
      test('overtimeMinutes = 180',  () => expect(r.overtimeMinutes, 180));
      test('nightMinutes = 0',       () => expect(r.nightMinutes, 0));
      // workMins(660)>480: over8=180,within8=0 → ot15x=(180*12500*1.5/60)=56250
      test('overtimeAmount = 56250', () => expect(r.overtimeAmount, 56250));
      test('totalAmount = 156250',   () => expect(r.totalAmount, 156250));
    });

    group('B2-07 일급제 baseHourlyWage 설정 (연장 수당 기초시급=15000)', () {
      late final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 100000, workDate: d2026,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '20:00',
        breakMinutes: 60, scheduledBreakMinutes: 60,
        baseHourlyWage: 15000,
      );
      // overtime=120, workMins(600)>480: over8=120, within8=0
      // ot15x=(120*15000*1.5/60)=45000
      test('overtimeMinutes = 120',  () => expect(r.overtimeMinutes, 120));
      test('overtimeAmount = 45000', () => expect(r.overtimeAmount, 45000));
      test('totalAmount = 145000',   () => expect(r.totalAmount, 145000));
      // appliedSupplementWage = baseHourlyWage = 15000
      test('appliedSupplementWage = 15000', () => expect(r.appliedSupplementWage, 15000));
    });

    group('B2-08 일급제 scheduledWorkMinutes=0 (예정시간=0) → 일급 전액', () {
      late final r = WageCalculator.calculate(
        wageType: 'daily', baseWage: 80000, workDate: d2026,
        scheduledStart: '09:00', scheduledEnd: '09:00',
        actualStart: '09:00', actualEnd: '17:00',
        breakMinutes: 0, scheduledBreakMinutes: 0,
      );
      // schedWorkMins=0 → baseAmount=dailyWage, overtimeAmount=0
      test('baseAmount = 80000',     () => expect(r.baseAmount, 80000));
      test('overtimeAmount = 0',     () => expect(r.overtimeAmount, 0));
      test('totalAmount = 80000',    () => expect(r.totalAmount, 80000));
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Group C2: 세금 공제 추가
  // ════════════════════════════════════════════════════════════════════
  group('C2 세금 공제 추가', () {

    // gross=200,000원 기준 WageDetailModel (시급 25000 × 8h)
    // (480 * 25000 / 60).round() = 200000
    final base200k = WageCalculator.calculate(
      wageType: 'hourly', baseWage: 25000, workDate: d2026,
      scheduledStart: '09:00', scheduledEnd: '18:00',
      actualStart: '09:00', actualEnd: '18:00', breakMinutes: 60,
    );

    test('C2 gross 200000 확인', () => expect(base200k.totalAmount, 200000));

    group('C2-01 daily_worker 200,000원 (15만 초과분 과세)', () {
      final r = TaxDeductionService.applyDeduction(
        base: base200k, taxDeductionType: InsuranceRateModel.typeDailyWorker, workYear: 2026,
      );
      // taxable=50000, incomeTax=(50000*2.7/100)=1350, local=(1350*10/100)=135 → tax=1485
      // employment=(200000*0.9/100)=1800
      test('incomeTaxDeduction = 1485', () => expect(r.incomeTaxDeduction, 1485));
      test('employmentInsuranceDeduction = 1800', () => expect(r.employmentInsuranceDeduction, 1800));
      test('netWage = 196715', () => expect(r.netWage, 196715));
    });

    group('C2-02 daily_auto_8 200,000원 1~7일차', () {
      final r = TaxDeductionService.applyDeduction(
        base: base200k, taxDeductionType: InsuranceRateModel.typeDailyAuto8, workYear: 2026,
      );
      // 고용보험+소득세: employment=1800, tax=1485
      test('employmentInsuranceDeduction = 1800', () => expect(r.employmentInsuranceDeduction, 1800));
      test('incomeTaxDeduction = 1485', () => expect(r.incomeTaxDeduction, 1485));
      test('nationalPensionDeduction = 0 (소급 전)', () => expect(r.nationalPensionDeduction, 0));
      test('netWage = 196715', () => expect(r.netWage, 196715));
    });

    group('C2-03 four_insurance_fixed 200,000원', () {
      final r = TaxDeductionService.applyDeduction(
        base: base200k, taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed, workYear: 2026,
      );
      // pension=(200000*4.75/100)=9500
      // health=(200000*3.595/100)=7190
      // ltc=(7190*13.14/100).round()=945
      // employment=(200000*0.9/100)=1800
      test('nationalPensionDeduction = 9500', () => expect(r.nationalPensionDeduction, 9500));
      test('healthInsuranceDeduction = 7190', () => expect(r.healthInsuranceDeduction, 7190));
      test('ltcInsuranceDeduction = 945',     () => expect(r.ltcInsuranceDeduction, 945));
      test('employmentInsuranceDeduction = 1800', () => expect(r.employmentInsuranceDeduction, 1800));
      // net=200000-(9500+7190+945+1800)=180565
      test('netWage = 180565', () => expect(r.netWage, 180565));
    });

    group('C2-04 freelancer_3_3 200,000원', () {
      final r = TaxDeductionService.applyDeduction(
        base: base200k, taxDeductionType: InsuranceRateModel.typeFreelancer33, workYear: 2026,
      );
      // incomeTax=(200000*3/100)=6000, local=(6000*10/100)=600 → totalTax=6600
      test('incomeTaxDeduction = 6600', () => expect(r.incomeTaxDeduction, 6600));
      test('netWage = 193400', () => expect(r.netWage, 193400));
    });

    group('C2-05 8일 소급 계산 (prevGrossTotal=700000, gross8=100000)', () {
      // 기준 8일차 WageDetailModel
      final day8Base = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 12500, workDate: d2026,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00', breakMinutes: 60,
      );
      final r = TaxDeductionService.applyDay8Retroactive(
        day8Base: day8Base, prevGrossTotal: 700000, workYear: 2026,
      );
      // prevPension=(700000*4.75/100)=33250
      // prevHealth=(700000*3.595/100)=25165
      // prevLtc=(25165*13.14/100).round()=3307
      // retroactive=61722
      // pension8=4750, health8=3595, ltc8=472, employment8=900
      // taxable8=0, incomeTax8=0 (100000<150000)
      // totalDeduction=61722+4750+3595+472+900=71439
      test('gross8 = 100000',             () => expect(day8Base.totalAmount, 100000));
      test('retroactiveDeduction = 61722', () => expect(r.retroactiveDeduction, 61722));
      test('nationalPensionDeduction = 4750', () => expect(r.nationalPensionDeduction, 4750));
      test('healthInsuranceDeduction = 3595', () => expect(r.healthInsuranceDeduction, 3595));
      test('ltcInsuranceDeduction = 472',     () => expect(r.ltcInsuranceDeduction, 472));
      test('employmentInsuranceDeduction = 900', () => expect(r.employmentInsuranceDeduction, 900));
      test('incomeTaxDeduction = 0',         () => expect(r.incomeTaxDeduction, 0));
      test('netWage = 28561', () => expect(r.netWage, 28561));
    });

    group('C2-06 8일 소급 (prevGrossTotal=1400000, gross8=200000)', () {
      final day8Base200 = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 25000, workDate: d2026,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00', breakMinutes: 60,
      );
      final r = TaxDeductionService.applyDay8Retroactive(
        day8Base: day8Base200, prevGrossTotal: 1400000, workYear: 2026,
      );
      // prevPension=66500, prevHealth=50330, prevLtc=(50330*13.14/100).round()=6613
      // retroactive=123443
      // pension8=9500, health8=7190, ltc8=945, employment8=1800
      // taxable8=50000 → incomeTax8=1350, local8=135 → totalTax8=1485
      // totalDeduction=123443+9500+7190+945+1800+1485=144363
      test('retroactiveDeduction = 123443', () => expect(r.retroactiveDeduction, 123443));
      test('incomeTaxDeduction = 1485',     () => expect(r.incomeTaxDeduction, 1485));
      // net=200000-144363=55637
      test('netWage = 55637', () => expect(r.netWage, 55637));
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Group D2: 지급 예정일 계산
  // ════════════════════════════════════════════════════════════════════
  group('D2 지급 예정일', () {
    final jun15 = DateTime(2026, 6, 15); // 월요일

    test('D2-01 same_day → 당일 반환', () {
      final r = PaymentDueDateCalculator.calculate(
        payScheduleType: 'same_day', payScheduleDay: null, workDate: jun15,
      );
      expect(r, DateTime(2026, 6, 15));
    });

    test('D2-02 next_day → 익일 반환', () {
      final r = PaymentDueDateCalculator.calculate(
        payScheduleType: 'next_day', payScheduleDay: null, workDate: jun15,
      );
      expect(r, DateTime(2026, 6, 16));
    });

    test('D2-03 weekly 금요일 (2026-06-15 월→금)', () {
      // from=Mon(1), target=Fri(5), diff=(5-1)%7=4 → +4일=6/19
      final r = PaymentDueDateCalculator.calculate(
        payScheduleType: 'weekly', payScheduleDay: 5, workDate: jun15,
      );
      expect(r, DateTime(2026, 6, 19));
    });

    test('D2-04 weekly 당일 일치 (2026-06-19 금→금)', () {
      final r = PaymentDueDateCalculator.calculate(
        payScheduleType: 'weekly', payScheduleDay: 5,
        workDate: DateTime(2026, 6, 19),
      );
      expect(r, DateTime(2026, 6, 19));
    });

    test('D2-05 weekly 월요일 (2026-06-15 월→월, 당일)', () {
      final r = PaymentDueDateCalculator.calculate(
        payScheduleType: 'weekly', payScheduleDay: 1, workDate: jun15,
      );
      expect(r, DateTime(2026, 6, 15));
    });

    test('D2-06 weekly 수요일 (2026-06-15 월→수, +2일)', () {
      // diff=(3-1)%7=2
      final r = PaymentDueDateCalculator.calculate(
        payScheduleType: 'weekly', payScheduleDay: 3, workDate: jun15,
      );
      expect(r, DateTime(2026, 6, 17));
    });

    test('D2-07 monthly 25일 (2026-06-15 → 2026-06-25)', () {
      final r = PaymentDueDateCalculator.calculate(
        payScheduleType: 'monthly', payScheduleDay: 25, workDate: jun15,
      );
      expect(r, DateTime(2026, 6, 25));
    });

    test('D2-08 monthly 25일 지난 후 (2026-06-28 → 2026-07-25)', () {
      final r = PaymentDueDateCalculator.calculate(
        payScheduleType: 'monthly', payScheduleDay: 25,
        workDate: DateTime(2026, 6, 28),
      );
      expect(r, DateTime(2026, 7, 25));
    });

    test('D2-09 monthly 31일 2월 (이월 → 2026-02-28)', () {
      final r = PaymentDueDateCalculator.calculate(
        payScheduleType: 'monthly', payScheduleDay: 31,
        workDate: DateTime(2026, 2, 15),
      );
      expect(r, DateTime(2026, 2, 28));
    });

    test('D2-10 monthly 연말이월 (2026-12-31 → 2027-01-25)', () {
      final r = PaymentDueDateCalculator.calculate(
        payScheduleType: 'monthly', payScheduleDay: 25,
        workDate: DateTime(2026, 12, 31),
      );
      expect(r, DateTime(2027, 1, 25));
    });

    test('D2-11 null payScheduleType → null 반환', () {
      final r = PaymentDueDateCalculator.calculate(
        payScheduleType: null, payScheduleDay: null, workDate: jun15,
      );
      expect(r, isNull);
    });

    test('D2-12 isDueOnOrBefore: 지난 날짜 → true', () {
      expect(
        PaymentDueDateCalculator.isDueOnOrBefore(
          DateTime(2026, 6, 10), reference: DateTime(2026, 6, 11),
        ),
        isTrue,
      );
    });

    test('D2-13 isDueOnOrBefore: 당일 → true', () {
      expect(
        PaymentDueDateCalculator.isDueOnOrBefore(
          DateTime(2026, 6, 11), reference: DateTime(2026, 6, 11),
        ),
        isTrue,
      );
    });

    test('D2-14 isDueOnOrBefore: 미래 날짜 → false', () {
      expect(
        PaymentDueDateCalculator.isDueOnOrBefore(
          DateTime(2026, 6, 12), reference: DateTime(2026, 6, 11),
        ),
        isFalse,
      );
    });

    test('D2-15 isDueOnOrBefore: null → false', () {
      expect(PaymentDueDateCalculator.isDueOnOrBefore(null), isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Group E2: 주휴수당 참고값 계산
  // 설계 방침: 자동 적용 없음 — 사업주가 additionalAmount로 수동 처리.
  // calculateWeeklyHolidayPay()는 사업주 안내용 참고값 계산 전용.
  // ════════════════════════════════════════════════════════════════════
  group('E2 주휴수당 (참고값 계산, 자동 적용 없음)', () {
    test('E2-01 주 14h(840분) → 0 (15h 미달)', () {
      expect(WageCalculator.calculateWeeklyHolidayPay(
        ordinaryHourlyWage: 10000, weeklyWorkMinutes: 840,
      ), 0);
    });

    test('E2-02 주 14h 59분(899분) → 0', () {
      expect(WageCalculator.calculateWeeklyHolidayPay(
        ordinaryHourlyWage: 10000, weeklyWorkMinutes: 899,
      ), 0);
    });

    test('E2-03 주 정확히 15h(900분) → 비례 계산', () {
      // (15/40)*8*10000 = 30000
      expect(WageCalculator.calculateWeeklyHolidayPay(
        ordinaryHourlyWage: 10000, weeklyWorkMinutes: 900,
      ), 30000);
    });

    test('E2-04 주 20h(1200분) → 40000', () {
      // (20/40)*8*10000 = 40000
      expect(WageCalculator.calculateWeeklyHolidayPay(
        ordinaryHourlyWage: 10000, weeklyWorkMinutes: 1200,
      ), 40000);
    });

    test('E2-05 주 40h(2400분) → 최대 80000', () {
      // (40/40)*8*10000 = 80000
      expect(WageCalculator.calculateWeeklyHolidayPay(
        ordinaryHourlyWage: 10000, weeklyWorkMinutes: 2400,
      ), 80000);
    });

    test('E2-06 주 50h(3000분) → 40h 상한 적용 → 80000', () {
      // clamp(0, 40) → 40h
      expect(WageCalculator.calculateWeeklyHolidayPay(
        ordinaryHourlyWage: 10000, weeklyWorkMinutes: 3000,
      ), 80000);
    });

    test('E2-07 최저시급 10320, 주 40h → 82560', () {
      // (40/40)*8*10320 = 82560
      expect(WageCalculator.calculateWeeklyHolidayPay(
        ordinaryHourlyWage: 10320, weeklyWorkMinutes: 2400,
      ), 82560);
    });

    test('E2-08 주 15h, 시급 12000 → 36000', () {
      // (15/40)*8*12000 = 36000
      expect(WageCalculator.calculateWeeklyHolidayPay(
        ordinaryHourlyWage: 12000, weeklyWorkMinutes: 900,
      ), 36000);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Group F2: 최저시급 연도별
  // ════════════════════════════════════════════════════════════════════
  group('F2 최저시급 연도별', () {
    test('F2-01 2026년 = 10320', () => expect(WageCalculator.getMinimumWage(2026), 10320));
    test('F2-02 2025년 = 10030', () => expect(WageCalculator.getMinimumWage(2025), 10030));
    test('F2-03 2024년 = 9860',  () => expect(WageCalculator.getMinimumWage(2024), 9860));
    test('F2-04 2023년 = 9620',  () => expect(WageCalculator.getMinimumWage(2023), 9620));
    test('F2-05 2022년 = 9160',  () => expect(WageCalculator.getMinimumWage(2022), 9160));
    test('F2-06 2021년 = 8720',  () => expect(WageCalculator.getMinimumWage(2021), 8720));
    test('F2-07 2020년 = 8590',  () => expect(WageCalculator.getMinimumWage(2020), 8590));
    test('F2-08 미등록 연도(2019) → 최신 백업(10320) 반환', () {
      expect(WageCalculator.getMinimumWage(2019), 10320);
    });

    group('F2-09 2025년 근무일 → appliedMinimumWage=10030', () {
      late final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 10000, workDate: d2025,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00', breakMinutes: 60,
      );
      test('appliedMinimumWage = 10030', () => expect(r.appliedMinimumWage, 10030));
    });

    group('F2-10 2023년 근무일 → appliedMinimumWage=9620', () {
      late final r = WageCalculator.calculate(
        wageType: 'hourly', baseWage: 9000, workDate: d2023,
        scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00', breakMinutes: 60,
      );
      test('appliedMinimumWage = 9620', () => expect(r.appliedMinimumWage, 9620));
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Group G2: 유틸 메서드
  // ════════════════════════════════════════════════════════════════════
  group('G2 유틸 메서드', () {

    group('G2-01 legalMaxBreakMinutes', () {
      test('0분 → 0',   () => expect(WageCalculator.legalMaxBreakMinutes(0),   0));
      test('239분 → 0', () => expect(WageCalculator.legalMaxBreakMinutes(239), 0));
      test('240분 → 30', () => expect(WageCalculator.legalMaxBreakMinutes(240), 30));
      test('300분 → 30', () => expect(WageCalculator.legalMaxBreakMinutes(300), 30));
      test('479분 → 30', () => expect(WageCalculator.legalMaxBreakMinutes(479), 30));
      test('480분 → 60', () => expect(WageCalculator.legalMaxBreakMinutes(480), 60));
      test('600분 → 60', () => expect(WageCalculator.legalMaxBreakMinutes(600), 60));
    });

    group('G2-02 minutesToTimeString', () {
      test('0 → "0분"',        () => expect(WageCalculator.minutesToTimeString(0),   '0분'));
      test('30 → "30분"',      () => expect(WageCalculator.minutesToTimeString(30),  '30분'));
      test('60 → "1시간"',     () => expect(WageCalculator.minutesToTimeString(60),  '1시간'));
      test('90 → "1시간 30분"', () => expect(WageCalculator.minutesToTimeString(90),  '1시간 30분'));
      test('480 → "8시간"',    () => expect(WageCalculator.minutesToTimeString(480), '8시간'));
      test('510 → "8시간 30분"', () => expect(WageCalculator.minutesToTimeString(510), '8시간 30분'));
    });

    group('G2-03 elapsedMinutes', () {
      test('"09:00"~"18:00" = 540', () => expect(WageCalculator.elapsedMinutes('09:00', '18:00'), 540));
      test('"22:00"~"06:00" = 480', () => expect(WageCalculator.elapsedMinutes('22:00', '06:00'), 480));
      test('"00:00"~"00:00" = 0',   () => expect(WageCalculator.elapsedMinutes('00:00', '00:00'), 0));
      test('"09:00:30"~"18:00:00" = 540 (HH:mm:ss 파싱)', () {
        expect(WageCalculator.elapsedMinutes('09:00:30', '18:00:00'), 540);
      });
    });

    group('G2-04 computeOrdinaryHourlyWage', () {
      test('09:00~18:00 break=60 일급=100000 → 12500', () {
        expect(WageCalculator.computeOrdinaryHourlyWage(
          scheduledStart: '09:00', scheduledEnd: '18:00',
          breakMinutes: 60, dailyWage: 100000,
        ), 12500);
      });
      test('09:00~17:00 break=60 일급=100000 → 14286', () {
        // schedWorkMins=(480-60)=420, (100000/420*60).round()=14286
        expect(WageCalculator.computeOrdinaryHourlyWage(
          scheduledStart: '09:00', scheduledEnd: '17:00',
          breakMinutes: 60, dailyWage: 100000,
        ), 14286);
      });
      test('dailyWage=0 → null 반환', () {
        expect(WageCalculator.computeOrdinaryHourlyWage(
          scheduledStart: '09:00', scheduledEnd: '18:00',
          breakMinutes: 60, dailyWage: 0,
        ), isNull);
      });
    });
  });
}
