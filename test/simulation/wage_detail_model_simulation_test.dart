// test/simulation/wage_detail_model_simulation_test.dart
//
// WageDetailModel 전체 직렬화/역직렬화·effectiveNetWage getter·
// wageStatus 4단계 흐름 종합 시뮬레이션 테스트
//
// ▶ 기존 테스트에서 미커버된 영역
//   - toMap() 조건부 키 포함/제외 검증
//   - toMap→fromMap 왕복 (null DateTime 경로 — Timestamp.fromDate 없이 안전하게)
//   - effectiveNetWage T-01 레거시 폴백 (isCalculated=true, netWage=0, totalAmount>0)
//   - wageStatus 4단계와 WageDetailModel isCalculated/isConfirmed 연동
//   - checkOut 수정 차단 조건 로직
//   - payScheduleDay 유효성 범위
//
// ⚠️ [T-01 수정 주의]
//   test/models/wage_detail_model_test.dart 의 "확정 시 netWage가 0이어도 0 반환" 테스트는
//   T-01 fix 이전에 작성된 것으로 현재 코드와 다름.
//   실제 코드: isCalculated=true AND netWage=0 AND totalAmount>0 → totalAmount-deduction 반환.
//   이 파일의 SCENARIO-WDM-C02, C07 케이스가 정확한 현재 동작을 검증한다.
//
// Firebase 의존성 없음 — 순수 모델 로직 검증
// (DateTime 필드 없는 경로만 toMap() 호출. DateTime 파싱은 CF Map 형식으로 테스트.)
//
// 실행: flutter test test/simulation/wage_detail_model_simulation_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';

// ── 헬퍼: 최소 WageDetailModel 생성 (DateTime 필드 없음) ────────────────────
WageDetailModel _model({
  String wageType = 'hourly',
  int baseWage = 10000,
  int scheduledMinutes = 0,
  int actualMinutes = 0,
  int breakMinutes = 0,
  int workMinutes = 0,
  int overtimeMinutes = 0,
  int earlyArrivalMinutes = 0,
  int nightMinutes = 0,
  int baseAmount = 0,
  int overtimeAmount = 0,
  int earlyArrivalAmount = 0,
  int nightAmount = 0,
  int additionalAmount = 0,
  int deductionAmount = 0,
  int weeklyHolidayAmount = 0,
  int totalAmount = 0,
  bool nightAllowanceApplied = false,
  String? memo,
  int appliedMinimumWage = 10320,
  int appliedSupplementWage = 0,
  String? calculatedBy,
  DateTime? calculatedAt,
  String? confirmedBy,
  DateTime? confirmedAt,
  String? payScheduleType,
  int? payScheduleDay,
  String taxDeductionType = InsuranceRateModel.typeNone,
  int employmentInsuranceDeduction = 0,
  int nationalPensionDeduction = 0,
  int healthInsuranceDeduction = 0,
  int ltcInsuranceDeduction = 0,
  int incomeTaxDeduction = 0,
  int retroactiveDeduction = 0,
  int netWage = 0,
}) {
  return WageDetailModel(
    wageType: wageType,
    baseWage: baseWage,
    scheduledMinutes: scheduledMinutes,
    actualMinutes: actualMinutes,
    breakMinutes: breakMinutes,
    workMinutes: workMinutes,
    overtimeMinutes: overtimeMinutes,
    earlyArrivalMinutes: earlyArrivalMinutes,
    nightMinutes: nightMinutes,
    baseAmount: baseAmount,
    overtimeAmount: overtimeAmount,
    earlyArrivalAmount: earlyArrivalAmount,
    nightAmount: nightAmount,
    additionalAmount: additionalAmount,
    deductionAmount: deductionAmount,
    weeklyHolidayAmount: weeklyHolidayAmount,
    totalAmount: totalAmount,
    nightAllowanceApplied: nightAllowanceApplied,
    memo: memo,
    appliedMinimumWage: appliedMinimumWage,
    appliedSupplementWage: appliedSupplementWage,
    calculatedBy: calculatedBy,
    calculatedAt: calculatedAt,
    confirmedBy: confirmedBy,
    confirmedAt: confirmedAt,
    payScheduleType: payScheduleType,
    payScheduleDay: payScheduleDay,
    taxDeductionType: taxDeductionType,
    employmentInsuranceDeduction: employmentInsuranceDeduction,
    nationalPensionDeduction: nationalPensionDeduction,
    healthInsuranceDeduction: healthInsuranceDeduction,
    ltcInsuranceDeduction: ltcInsuranceDeduction,
    incomeTaxDeduction: incomeTaxDeduction,
    retroactiveDeduction: retroactiveDeduction,
    netWage: netWage,
  );
}

/// checkOut 수정 가능 여부 판단 (AttendanceModel.wageStatus 기반 비즈니스 로직)
/// 실제 코드: pending 상태만 수정 허용
bool canModifyCheckOut(String wageStatus) {
  return wageStatus == AttendanceModel.wagePending;
}

void main() {
  // ══════════════════════════════════════════════════════════════════════
  // Group A: toMap() 조건부 키 포함/제외
  // ══════════════════════════════════════════════════════════════════════
  group('SCENARIO-WDM-A: toMap() 조건부 키 포함/제외', () {
    test('SCENARIO-WDM-A01: earlyArrivalMinutes=0 → toMap에서 키 제외', () {
      final m = _model(earlyArrivalMinutes: 0);
      final map = m.toMap();
      expect(map.containsKey('earlyArrivalMinutes'), isFalse);
    });

    test('SCENARIO-WDM-A02: earlyArrivalMinutes>0 → toMap에서 키 포함', () {
      final m = _model(earlyArrivalMinutes: 30);
      final map = m.toMap();
      expect(map.containsKey('earlyArrivalMinutes'), isTrue);
      expect(map['earlyArrivalMinutes'], 30);
    });

    test('SCENARIO-WDM-A03: earlyArrivalAmount=0 → toMap에서 키 제외', () {
      final m = _model(earlyArrivalAmount: 0);
      final map = m.toMap();
      expect(map.containsKey('earlyArrivalAmount'), isFalse);
    });

    test('SCENARIO-WDM-A04: earlyArrivalAmount>0 → toMap에서 키 포함', () {
      final m = _model(earlyArrivalAmount: 7500);
      final map = m.toMap();
      expect(map.containsKey('earlyArrivalAmount'), isTrue);
      expect(map['earlyArrivalAmount'], 7500);
    });

    test('SCENARIO-WDM-A05: appliedSupplementWage=0 → toMap에서 키 제외', () {
      final m = _model(appliedSupplementWage: 0);
      final map = m.toMap();
      expect(map.containsKey('appliedSupplementWage'), isFalse);
    });

    test('SCENARIO-WDM-A06: appliedSupplementWage>0 → toMap에서 키 포함', () {
      final m = _model(appliedSupplementWage: 15480);
      final map = m.toMap();
      expect(map.containsKey('appliedSupplementWage'), isTrue);
      expect(map['appliedSupplementWage'], 15480);
    });

    test('SCENARIO-WDM-A07: employmentInsuranceDeduction=0 → toMap에서 키 제외', () {
      final m = _model(employmentInsuranceDeduction: 0);
      final map = m.toMap();
      expect(map.containsKey('employmentInsuranceDeduction'), isFalse);
    });

    test('SCENARIO-WDM-A08: employmentInsuranceDeduction>0 → toMap에서 키 포함', () {
      final m = _model(employmentInsuranceDeduction: 900);
      final map = m.toMap();
      expect(map.containsKey('employmentInsuranceDeduction'), isTrue);
      expect(map['employmentInsuranceDeduction'], 900);
    });

    test('SCENARIO-WDM-A09: payScheduleType=null → toMap에서 키 제외', () {
      final m = _model(payScheduleType: null);
      final map = m.toMap();
      expect(map.containsKey('payScheduleType'), isFalse);
    });

    test('SCENARIO-WDM-A10: payScheduleType 있음 → toMap에서 키 포함', () {
      final m = _model(payScheduleType: 'monthly', payScheduleDay: 25);
      final map = m.toMap();
      expect(map.containsKey('payScheduleType'), isTrue);
      expect(map['payScheduleType'], 'monthly');
    });

    test('SCENARIO-WDM-A11: payScheduleDay=null → toMap에서 키 제외', () {
      final m = _model(payScheduleDay: null);
      final map = m.toMap();
      expect(map.containsKey('payScheduleDay'), isFalse);
    });

    test('SCENARIO-WDM-A12: payScheduleDay 있음 → toMap에서 키 포함', () {
      final m = _model(payScheduleType: 'weekly', payScheduleDay: 5);
      final map = m.toMap();
      expect(map.containsKey('payScheduleDay'), isTrue);
      expect(map['payScheduleDay'], 5);
    });

    test('SCENARIO-WDM-A13: netWage 항상 toMap에 포함', () {
      final m = _model(netWage: 0);
      final map = m.toMap();
      expect(map.containsKey('netWage'), isTrue);
    });

    test('SCENARIO-WDM-A14: 6개 공제 모두 0이면 공제 키 전부 제외', () {
      final m = _model();
      final map = m.toMap();
      expect(map.containsKey('employmentInsuranceDeduction'), isFalse);
      expect(map.containsKey('nationalPensionDeduction'), isFalse);
      expect(map.containsKey('healthInsuranceDeduction'), isFalse);
      expect(map.containsKey('ltcInsuranceDeduction'), isFalse);
      expect(map.containsKey('incomeTaxDeduction'), isFalse);
      expect(map.containsKey('retroactiveDeduction'), isFalse);
    });

    test('SCENARIO-WDM-A15: calculatedAt=null → toMap에 null로 저장', () {
      final m = _model(calculatedAt: null);
      final map = m.toMap();
      expect(map.containsKey('calculatedAt'), isTrue);
      expect(map['calculatedAt'], isNull);
    });

    test('SCENARIO-WDM-A16: memo=null → toMap에 null로 저장', () {
      final m = _model(memo: null);
      final map = m.toMap();
      expect(map.containsKey('memo'), isTrue);
      expect(map['memo'], isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Group B: toMap→fromMap 왕복 (null DateTime 경로, Timestamp 생성 없음)
  // ══════════════════════════════════════════════════════════════════════
  group('SCENARIO-WDM-B: toMap→fromMap 왕복 (null DateTime)', () {
    test('SCENARIO-WDM-B01: wageType/baseWage 왕복', () {
      final original = _model(wageType: 'daily', baseWage: 120000);
      final roundtrip = WageDetailModel.fromMap(original.toMap());
      expect(roundtrip.wageType, original.wageType);
      expect(roundtrip.baseWage, original.baseWage);
    });

    test('SCENARIO-WDM-B02: 시간 분 단위 필드 왕복', () {
      final original = _model(
        scheduledMinutes: 480,
        actualMinutes: 495,
        breakMinutes: 30,
        workMinutes: 465,
        overtimeMinutes: 60,
        earlyArrivalMinutes: 15,
        nightMinutes: 120,
      );
      final roundtrip = WageDetailModel.fromMap(original.toMap());
      expect(roundtrip.scheduledMinutes, 480);
      expect(roundtrip.actualMinutes, 495);
      expect(roundtrip.breakMinutes, 30);
      expect(roundtrip.workMinutes, 465);
      expect(roundtrip.overtimeMinutes, 60);
      expect(roundtrip.earlyArrivalMinutes, 15);
      expect(roundtrip.nightMinutes, 120);
    });

    test('SCENARIO-WDM-B03: 금액 필드 왕복', () {
      final original = _model(
        baseAmount: 100000,
        overtimeAmount: 15000,
        earlyArrivalAmount: 7500,
        nightAmount: 6000,
        additionalAmount: 5000,
        deductionAmount: 3000,
        weeklyHolidayAmount: 10000,
        totalAmount: 133000,
        netWage: 130000,
      );
      final roundtrip = WageDetailModel.fromMap(original.toMap());
      expect(roundtrip.baseAmount, 100000);
      expect(roundtrip.overtimeAmount, 15000);
      expect(roundtrip.earlyArrivalAmount, 7500);
      expect(roundtrip.nightAmount, 6000);
      expect(roundtrip.additionalAmount, 5000);
      expect(roundtrip.deductionAmount, 3000);
      expect(roundtrip.weeklyHolidayAmount, 10000);
      expect(roundtrip.totalAmount, 133000);
      expect(roundtrip.netWage, 130000);
    });

    test('SCENARIO-WDM-B04: 6개 공제 필드 왕복', () {
      final original = _model(
        taxDeductionType: InsuranceRateModel.typeDailyAuto8,
        employmentInsuranceDeduction: 900,
        nationalPensionDeduction: 4750,
        healthInsuranceDeduction: 3595,
        ltcInsuranceDeduction: 472,
        incomeTaxDeduction: 1050,
        retroactiveDeduction: 8000,
      );
      final roundtrip = WageDetailModel.fromMap(original.toMap());
      expect(roundtrip.taxDeductionType, InsuranceRateModel.typeDailyAuto8);
      expect(roundtrip.employmentInsuranceDeduction, 900);
      expect(roundtrip.nationalPensionDeduction, 4750);
      expect(roundtrip.healthInsuranceDeduction, 3595);
      expect(roundtrip.ltcInsuranceDeduction, 472);
      expect(roundtrip.incomeTaxDeduction, 1050);
      expect(roundtrip.retroactiveDeduction, 8000);
    });

    test('SCENARIO-WDM-B05: paySchedule 필드 왕복', () {
      final original = _model(payScheduleType: 'monthly', payScheduleDay: 31);
      final roundtrip = WageDetailModel.fromMap(original.toMap());
      expect(roundtrip.payScheduleType, 'monthly');
      expect(roundtrip.payScheduleDay, 31);
    });

    test('SCENARIO-WDM-B06: bool/String 필드 왕복', () {
      final original = _model(
        nightAllowanceApplied: true,
        memo: '야간 근무 특이사항',
        appliedMinimumWage: 10320,
        appliedSupplementWage: 15480,
      );
      final roundtrip = WageDetailModel.fromMap(original.toMap());
      expect(roundtrip.nightAllowanceApplied, isTrue);
      expect(roundtrip.memo, '야간 근무 특이사항');
      expect(roundtrip.appliedMinimumWage, 10320);
      expect(roundtrip.appliedSupplementWage, 15480);
    });

    test('SCENARIO-WDM-B07: 최소 모델 왕복 — 기본값 유지', () {
      final original = _model();
      final roundtrip = WageDetailModel.fromMap(original.toMap());
      expect(roundtrip.wageType, 'hourly');
      expect(roundtrip.baseWage, 10000);
      expect(roundtrip.totalAmount, 0);
      expect(roundtrip.netWage, 0);
      expect(roundtrip.isCalculated, isFalse);
      expect(roundtrip.isConfirmed, isFalse);
    });

    test('SCENARIO-WDM-B08: earlyArrival 필드 0→제외→0 복원 왕복', () {
      // earlyArrivalMinutes=0 이면 toMap에서 키 제외 → fromMap에서 기본값 0으로 복원
      final original = _model(earlyArrivalMinutes: 0, earlyArrivalAmount: 0);
      final map = original.toMap();
      expect(map.containsKey('earlyArrivalMinutes'), isFalse);
      final roundtrip = WageDetailModel.fromMap(map);
      expect(roundtrip.earlyArrivalMinutes, 0);
      expect(roundtrip.earlyArrivalAmount, 0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Group C: effectiveNetWage T-01 레거시 폴백
  // ══════════════════════════════════════════════════════════════════════
  group('SCENARIO-WDM-C: effectiveNetWage T-01 레거시 폴백', () {
    test('SCENARIO-WDM-C01: isCalculated=true + netWage>0 → netWage 그대로 반환', () {
      final m = _model(
        totalAmount: 143000,
        netWage: 140000,
        calculatedAt: DateTime(2026, 6, 15, 12),
      );
      expect(m.isCalculated, isTrue);
      expect(m.effectiveNetWage, 140000);
    });

    test('SCENARIO-WDM-C02: [T-01] isCalculated=true + netWage=0 + totalAmount>0 → totalAmount-deduction 반환', () {
      // 마이그레이션 전 레코드: netWage 필드 부재 → 기본값 0
      // T-01 fix: 계산식으로 폴백하여 0원 오표시 방지
      final m = _model(
        totalAmount: 143000,
        netWage: 0, // 마이그레이션 전 상태
        employmentInsuranceDeduction: 1287,
        calculatedAt: DateTime(2026, 6, 15, 12),
      );
      expect(m.isCalculated, isTrue);
      expect(m.effectiveNetWage, 143000 - 1287); // = 141713
    });

    test('SCENARIO-WDM-C03: [T-01] isCalculated=true + netWage=0 + totalAmount=0 → 0 반환', () {
      // 진짜 0원 레코드 (totalAmount도 0): T-01 조건 불충족 → 0 유지
      final m = _model(
        totalAmount: 0,
        netWage: 0,
        calculatedAt: DateTime(2026, 6, 15, 12),
      );
      expect(m.isCalculated, isTrue);
      // netWage==0 AND totalAmount==0 → T-01 분기 미진입 → netWage.clamp(0) = 0
      expect(m.effectiveNetWage, 0);
    });

    test('SCENARIO-WDM-C04: isCalculated=false → totalAmount-totalInsuranceDeduction 반환', () {
      final m = _model(
        totalAmount: 100000,
        employmentInsuranceDeduction: 900,
        nationalPensionDeduction: 4500,
        // calculatedAt=null → isCalculated=false
      );
      expect(m.isCalculated, isFalse);
      expect(m.effectiveNetWage, 100000 - 900 - 4500);
    });

    test('SCENARIO-WDM-C05: isCalculated=false + 공제합계>totalAmount → 0 clamp', () {
      final m = _model(
        totalAmount: 1000,
        retroactiveDeduction: 50000, // 8일차 소급공제가 당일 급여 초과
      );
      expect(m.isCalculated, isFalse);
      expect(m.effectiveNetWage, 0);
    });

    test('SCENARIO-WDM-C06: netWage 음수 → 0 clamp (isCalculated=true)', () {
      // 음수 netWage 방어
      final m = _model(
        netWage: -5000,
        calculatedAt: DateTime(2026, 6, 15, 12),
      );
      expect(m.isCalculated, isTrue);
      expect(m.effectiveNetWage, 0);
    });

    test('SCENARIO-WDM-C07: [T-01 경계] netWage=0, totalAmount=200000, deduction=50000 → 150000', () {
      final m = _model(
        totalAmount: 200000,
        netWage: 0,
        nationalPensionDeduction: 50000,
        calculatedAt: DateTime(2026, 6, 15, 12),
      );
      expect(m.isCalculated, isTrue);
      expect(m.effectiveNetWage, 150000);
    });

    test('SCENARIO-WDM-C08: [T-01] 폴백 공제 후 음수 → 0 clamp', () {
      final m = _model(
        totalAmount: 50000,
        netWage: 0,
        retroactiveDeduction: 80000, // 공제가 totalAmount 초과
        calculatedAt: DateTime(2026, 6, 15, 12),
      );
      expect(m.isCalculated, isTrue);
      expect(m.effectiveNetWage, 0);
    });

    test('SCENARIO-WDM-C09: isCalculated=true + 대규모 netWage → 그대로 반환', () {
      const bigAmount = 999999999;
      final m = _model(
        totalAmount: bigAmount,
        netWage: bigAmount,
        calculatedAt: DateTime(2026, 6, 15, 12),
      );
      expect(m.effectiveNetWage, bigAmount);
    });

    test('SCENARIO-WDM-C10: isCalculated=false + totalAmount=0 → 0', () {
      final m = _model(totalAmount: 0);
      expect(m.isCalculated, isFalse);
      expect(m.effectiveNetWage, 0);
    });

    test('SCENARIO-WDM-C11: [T-01] netWage=0, totalAmount>0, 공제=0 → totalAmount 그대로', () {
      final m = _model(
        totalAmount: 80000,
        netWage: 0,
        calculatedAt: DateTime(2026, 6, 1),
      );
      // 공제 없음 → totalAmount - 0 = 80000
      expect(m.effectiveNetWage, 80000);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Group D: totalInsuranceDeduction 집계 정합성
  // ══════════════════════════════════════════════════════════════════════
  group('SCENARIO-WDM-D: totalInsuranceDeduction 집계', () {
    test('SCENARIO-WDM-D01: 6개 공제 전부 합산', () {
      final m = _model(
        employmentInsuranceDeduction: 900,
        nationalPensionDeduction: 4750,
        healthInsuranceDeduction: 3595,
        ltcInsuranceDeduction: 472,
        incomeTaxDeduction: 1050,
        retroactiveDeduction: 8000,
      );
      expect(m.totalInsuranceDeduction, 900 + 4750 + 3595 + 472 + 1050 + 8000);
    });

    test('SCENARIO-WDM-D02: 모두 0 → totalInsuranceDeduction=0', () {
      final m = _model();
      expect(m.totalInsuranceDeduction, 0);
    });

    test('SCENARIO-WDM-D03: retroactiveDeduction만 있음 → 해당 금액만 합산', () {
      final m = _model(retroactiveDeduction: 12000);
      expect(m.totalInsuranceDeduction, 12000);
    });

    test('SCENARIO-WDM-D04: 일부만 있을 때 나머지는 0으로 처리', () {
      final m = _model(
        employmentInsuranceDeduction: 1000,
        incomeTaxDeduction: 2000,
      );
      expect(m.totalInsuranceDeduction, 3000);
    });

    test('SCENARIO-WDM-D05: 단일 종류만 있을 때 합산', () {
      final m = _model(nationalPensionDeduction: 5000);
      expect(m.totalInsuranceDeduction, 5000);
    });

    test('SCENARIO-WDM-D06: 실제 일용직 시나리오 공제 합산 검증', () {
      // typeDailyWorker: employment + income tax
      final m = _model(
        taxDeductionType: InsuranceRateModel.typeDailyWorker,
        employmentInsuranceDeduction: 1287,
        incomeTaxDeduction: 810,
      );
      expect(m.totalInsuranceDeduction, 1287 + 810);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Group E: isCalculated / isConfirmed getter
  // ══════════════════════════════════════════════════════════════════════
  group('SCENARIO-WDM-E: isCalculated / isConfirmed getter', () {
    test('SCENARIO-WDM-E01: calculatedAt=null → isCalculated=false', () {
      final m = _model(calculatedAt: null);
      expect(m.isCalculated, isFalse);
    });

    test('SCENARIO-WDM-E02: calculatedAt != null → isCalculated=true', () {
      final m = _model(calculatedAt: DateTime(2026, 6, 15, 12, 30));
      expect(m.isCalculated, isTrue);
    });

    test('SCENARIO-WDM-E03: confirmedAt=null → isConfirmed=false', () {
      final m = _model(confirmedAt: null);
      expect(m.isConfirmed, isFalse);
    });

    test('SCENARIO-WDM-E04: confirmedAt != null → isConfirmed=true', () {
      final m = _model(confirmedAt: DateTime(2026, 6, 16, 9, 0));
      expect(m.isConfirmed, isTrue);
    });

    test('SCENARIO-WDM-E05: 둘 다 null → isCalculated=false, isConfirmed=false', () {
      final m = _model();
      expect(m.isCalculated, isFalse);
      expect(m.isConfirmed, isFalse);
    });

    test('SCENARIO-WDM-E06: calculatedAt만 있음 → isCalculated=true, isConfirmed=false', () {
      final m = _model(calculatedAt: DateTime(2026, 6, 15, 12));
      expect(m.isCalculated, isTrue);
      expect(m.isConfirmed, isFalse);
    });

    test('SCENARIO-WDM-E07: 둘 다 있음 → isCalculated=true, isConfirmed=true', () {
      final m = _model(
        calculatedAt: DateTime(2026, 6, 15, 12),
        confirmedAt: DateTime(2026, 6, 16, 9),
      );
      expect(m.isCalculated, isTrue);
      expect(m.isConfirmed, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Group F: copyWith isCalculated/isConfirmed 흐름
  // ══════════════════════════════════════════════════════════════════════
  group('SCENARIO-WDM-F: copyWith — isCalculated/isConfirmed 흐름', () {
    test('SCENARIO-WDM-F01: calculatedBy+calculatedAt 설정 → isCalculated=true, 다른 필드 유지', () {
      final base = _model(totalAmount: 100000, netWage: 98000);
      final calc = base.copyWith(
        calculatedBy: 'admin-uid',
        calculatedAt: DateTime(2026, 6, 15, 12),
      );
      expect(calc.isCalculated, isTrue);
      expect(calc.totalAmount, 100000);
      expect(calc.netWage, 98000);
      expect(calc.wageType, 'hourly');
    });

    test('SCENARIO-WDM-F02: confirmedBy+confirmedAt 설정 → isConfirmed=true, calculatedAt 유지', () {
      final base = _model(calculatedAt: DateTime(2026, 6, 15, 12));
      final conf = base.copyWith(
        confirmedBy: 'owner-uid',
        confirmedAt: DateTime(2026, 6, 16, 9),
      );
      expect(conf.isCalculated, isTrue);
      expect(conf.isConfirmed, isTrue);
    });

    test('SCENARIO-WDM-F03: calculatedAt만 설정 (calculatedBy 없음) → isCalculated=true', () {
      final base = _model();
      final updated = base.copyWith(calculatedAt: DateTime(2026, 6, 15, 12));
      expect(updated.isCalculated, isTrue);
      expect(updated.calculatedBy, isNull);
    });

    test('SCENARIO-WDM-F04: calculatedBy만 설정 (calculatedAt 없음) → isCalculated=false', () {
      final base = _model();
      final updated = base.copyWith(calculatedBy: 'admin-uid');
      expect(updated.isCalculated, isFalse);
      expect(updated.calculatedBy, 'admin-uid');
    });

    test('SCENARIO-WDM-F05: 원본 불변성 — copyWith 후 원본 isCalculated 유지', () {
      final original = _model(totalAmount: 50000);
      original.copyWith(calculatedAt: DateTime(2026, 6, 15, 12));
      // 원본은 변경되지 않음
      expect(original.isCalculated, isFalse);
      expect(original.totalAmount, 50000);
    });

    test('SCENARIO-WDM-F06: netWage 업데이트 후 effectiveNetWage 반영', () {
      final base = _model(totalAmount: 100000, calculatedAt: DateTime(2026, 6, 15));
      // T-01: netWage=0, totalAmount>0 → totalAmount 폴백
      expect(base.effectiveNetWage, 100000);
      // netWage 업데이트
      final updated = base.copyWith(netWage: 95000);
      expect(updated.effectiveNetWage, 95000);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Group G: wageStatus 4단계 + checkOut 수정 차단
  // ══════════════════════════════════════════════════════════════════════
  group('SCENARIO-WDM-G: wageStatus 4단계 + checkOut 수정 차단', () {
    test('SCENARIO-WDM-G01: wagePending 상수 = "pending"', () {
      expect(AttendanceModel.wagePending, 'pending');
    });

    test('SCENARIO-WDM-G02: wageCalculated 상수 = "calculated"', () {
      expect(AttendanceModel.wageCalculated, 'calculated');
    });

    test('SCENARIO-WDM-G03: wageConfirmed 상수 = "confirmed"', () {
      expect(AttendanceModel.wageConfirmed, 'confirmed');
    });

    test('SCENARIO-WDM-G04: wageTransferred 상수 = "transferred"', () {
      expect(AttendanceModel.wageTransferred, 'transferred');
    });

    test('SCENARIO-WDM-G05: pending → checkOut 수정 허용', () {
      expect(canModifyCheckOut(AttendanceModel.wagePending), isTrue);
    });

    test('SCENARIO-WDM-G06: calculated → checkOut 수정 차단', () {
      expect(canModifyCheckOut(AttendanceModel.wageCalculated), isFalse);
    });

    test('SCENARIO-WDM-G07: confirmed → checkOut 수정 차단', () {
      expect(canModifyCheckOut(AttendanceModel.wageConfirmed), isFalse);
    });

    test('SCENARIO-WDM-G08: transferred → checkOut 수정 차단', () {
      expect(canModifyCheckOut(AttendanceModel.wageTransferred), isFalse);
    });

    test('SCENARIO-WDM-G09: pending 상태에서만 canModifyCheckOut=true', () {
      final statuses = [
        AttendanceModel.wagePending,
        AttendanceModel.wageCalculated,
        AttendanceModel.wageConfirmed,
        AttendanceModel.wageTransferred,
      ];
      final results = statuses.map(canModifyCheckOut).toList();
      // pending만 true
      expect(results, [true, false, false, false]);
    });

    test('SCENARIO-WDM-G10: 4단계 상수 모두 서로 다른 값', () {
      final constants = {
        AttendanceModel.wagePending,
        AttendanceModel.wageCalculated,
        AttendanceModel.wageConfirmed,
        AttendanceModel.wageTransferred,
      };
      expect(constants.length, 4);
    });

    test('SCENARIO-WDM-G11: calculated → AttendanceModel.isWageCalculated=true', () {
      final att = AttendanceModel(
        id: 'test',
        applicationId: 'app',
        userId: 'user',
        businessId: 'biz',
        businessName: '테스트',
        workDate: DateTime(2026, 6, 15),
        workType: '서빙',
        status: 'present',
        createdAt: DateTime(2026, 6, 15, 9),
        wageStatus: AttendanceModel.wageCalculated,
        wageDetail: _model(
          totalAmount: 100000,
          netWage: 98000,
          calculatedAt: DateTime(2026, 6, 15, 12),
        ),
      );
      expect(att.isWageCalculated, isTrue);
      expect(att.wageDetail?.isCalculated, isTrue);
    });

    test('SCENARIO-WDM-G12: confirmed → AttendanceModel.isWageConfirmed=true, wageDetail.isConfirmed=true', () {
      final att = AttendanceModel(
        id: 'test',
        applicationId: 'app',
        userId: 'user',
        businessId: 'biz',
        businessName: '테스트',
        workDate: DateTime(2026, 6, 15),
        workType: '서빙',
        status: 'present',
        createdAt: DateTime(2026, 6, 15, 9),
        wageStatus: AttendanceModel.wageConfirmed,
        wageDetail: _model(
          totalAmount: 100000,
          netWage: 98000,
          calculatedAt: DateTime(2026, 6, 15, 12),
          confirmedAt: DateTime(2026, 6, 16, 9),
        ),
      );
      expect(att.isWageConfirmed, isTrue);
      expect(att.wageDetail?.isConfirmed, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Group H: payScheduleDay 유효성
  // ══════════════════════════════════════════════════════════════════════
  group('SCENARIO-WDM-H: payScheduleDay 유효성', () {
    test('SCENARIO-WDM-H01: payScheduleType=weekly → payScheduleDay=1(월) 저장/복원', () {
      final m = _model(payScheduleType: 'weekly', payScheduleDay: 1);
      final roundtrip = WageDetailModel.fromMap(m.toMap());
      expect(roundtrip.payScheduleType, 'weekly');
      expect(roundtrip.payScheduleDay, 1);
    });

    test('SCENARIO-WDM-H02: payScheduleType=weekly → payScheduleDay=7(일) 저장/복원', () {
      final m = _model(payScheduleType: 'weekly', payScheduleDay: 7);
      final roundtrip = WageDetailModel.fromMap(m.toMap());
      expect(roundtrip.payScheduleDay, 7);
    });

    test('SCENARIO-WDM-H03: payScheduleType=monthly → payScheduleDay=31(말일) 저장/복원', () {
      final m = _model(payScheduleType: 'monthly', payScheduleDay: 31);
      final roundtrip = WageDetailModel.fromMap(m.toMap());
      expect(roundtrip.payScheduleType, 'monthly');
      expect(roundtrip.payScheduleDay, 31);
    });

    test('SCENARIO-WDM-H04: payScheduleType=same_day → payScheduleDay 없음', () {
      final m = _model(payScheduleType: 'same_day');
      expect(m.payScheduleDay, isNull);
      final roundtrip = WageDetailModel.fromMap(m.toMap());
      expect(roundtrip.payScheduleType, 'same_day');
      expect(roundtrip.payScheduleDay, isNull);
    });

    test('SCENARIO-WDM-H05: payScheduleType=next_day → payScheduleDay 없음', () {
      final m = _model(payScheduleType: 'next_day');
      expect(m.payScheduleDay, isNull);
      final map = m.toMap();
      expect(map.containsKey('payScheduleDay'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Group I: wageType별 필드 정합성
  // ══════════════════════════════════════════════════════════════════════
  group('SCENARIO-WDM-I: wageType별 필드 정합성', () {
    test('SCENARIO-WDM-I01: wageType=hourly → wageTypeLabel=시급', () {
      final m = _model(wageType: 'hourly', baseWage: 10320);
      expect(m.wageTypeLabel, '시급');
    });

    test('SCENARIO-WDM-I02: wageType=daily → wageTypeLabel=일급', () {
      final m = _model(wageType: 'daily', baseWage: 120000);
      expect(m.wageTypeLabel, '일급');
    });

    test('SCENARIO-WDM-I03: appliedMinimumWage 기록 — 계산 당시 최저시급 보존', () {
      final m = _model(appliedMinimumWage: 10320);
      expect(m.appliedMinimumWage, 10320);
      // 기본값도 10320 확인
      final defaultM = _model();
      expect(defaultM.appliedMinimumWage, 10320);
    });

    test('SCENARIO-WDM-I04: appliedSupplementWage 기록 — 연장·야간 기초시급 보존', () {
      final m = _model(appliedSupplementWage: 15480);
      expect(m.appliedSupplementWage, 15480);
    });

    test('SCENARIO-WDM-I05: wageType 알 수 없는 값 → wageTypeLabel=급여 폴백', () {
      final m = _model(wageType: 'contract');
      expect(m.wageTypeLabel, '급여');
    });

    test('SCENARIO-WDM-I06: workHours = workMinutes / 60.0', () {
      final m = _model(workMinutes: 465);
      expect(m.workHours, closeTo(465 / 60.0, 0.001));
    });

    test('SCENARIO-WDM-I07: overtimeHours = overtimeMinutes / 60.0', () {
      final m = _model(overtimeMinutes: 60);
      expect(m.overtimeHours, closeTo(1.0, 0.001));
    });

    test('SCENARIO-WDM-I08: nightHours = nightMinutes / 60.0', () {
      final m = _model(nightMinutes: 120);
      expect(m.nightHours, closeTo(2.0, 0.001));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Group J: fromMap CF Map 형식 DateTime 파싱
  // ══════════════════════════════════════════════════════════════════════
  group('SCENARIO-WDM-J: fromMap CF Map 형식 DateTime 파싱', () {
    // CF(Cloud Functions)는 Timestamp를 {_seconds: N, _nanoseconds: N} Map으로 반환한다.
    // parseTimestampNullable이 이 형식을 올바르게 DateTime으로 변환하는지 검증.

    test('SCENARIO-WDM-J01: calculatedAt CF Map 형식 → isCalculated=true', () {
      // 2026-06-15 12:00:00 UTC = 1750334400 seconds
      final map = <String, dynamic>{
        'wageType': 'hourly',
        'baseWage': 10000,
        'totalAmount': 100000,
        'netWage': 98000,
        'calculatedAt': {'_seconds': 1750334400, '_nanoseconds': 0},
      };
      final m = WageDetailModel.fromMap(map);
      expect(m.isCalculated, isTrue);
      expect(m.calculatedAt, isNotNull);
    });

    test('SCENARIO-WDM-J02: confirmedAt CF Map 형식 → isConfirmed=true', () {
      final map = <String, dynamic>{
        'wageType': 'hourly',
        'baseWage': 10000,
        'calculatedAt': {'_seconds': 1750334400, '_nanoseconds': 0},
        'confirmedAt': {'_seconds': 1750420800, '_nanoseconds': 0},
      };
      final m = WageDetailModel.fromMap(map);
      expect(m.isCalculated, isTrue);
      expect(m.isConfirmed, isTrue);
    });

    test('SCENARIO-WDM-J03: calculatedAt=null CF 응답 → isCalculated=false', () {
      final map = <String, dynamic>{
        'wageType': 'hourly',
        'baseWage': 10000,
        'calculatedAt': null,
        'confirmedAt': null,
      };
      final m = WageDetailModel.fromMap(map);
      expect(m.isCalculated, isFalse);
      expect(m.isConfirmed, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Group K: tryFromMap null-safe 방어
  // ══════════════════════════════════════════════════════════════════════
  group('SCENARIO-WDM-K: tryFromMap null-safe 방어', () {
    test('SCENARIO-WDM-K01: 빈 맵 → null 아닌 WageDetailModel 반환', () {
      final m = WageDetailModel.tryFromMap({});
      expect(m, isNotNull);
    });

    test('SCENARIO-WDM-K02: 완전한 맵 → 정상 파싱', () {
      final m = WageDetailModel.tryFromMap({
        'wageType': 'daily',
        'baseWage': 120000,
        'totalAmount': 143000,
        'netWage': 141713,
      });
      expect(m, isNotNull);
      expect(m!.totalAmount, 143000);
    });

    test('SCENARIO-WDM-K03: tryFromMap 크래시 없이 반환', () {
      expect(() => WageDetailModel.tryFromMap({}), returnsNormally);
      expect(() => WageDetailModel.tryFromMap({'wageType': 'hourly'}), returnsNormally);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Group L: 급여 금액 필드 정합성 검증
  // ══════════════════════════════════════════════════════════════════════
  group('SCENARIO-WDM-L: 급여 금액 필드 정합성', () {
    test('SCENARIO-WDM-L01: effectiveNetWage - formattedNetWage 연동 (미확정)', () {
      final m = _model(totalAmount: 123456);
      // effectiveNetWage = 123456
      expect(m.effectiveNetWage, 123456);
      expect(m.formattedNetWage, '123,456원');
    });

    test('SCENARIO-WDM-L02: effectiveNetWage - formattedNetWage 연동 (확정)', () {
      final m = _model(
        netWage: 1234567,
        calculatedAt: DateTime(2026, 6, 15, 12),
      );
      expect(m.effectiveNetWage, 1234567);
      expect(m.formattedNetWage, '1,234,567원');
    });

    test('SCENARIO-WDM-L03: totalAmount=0 → formattedTotal = "0원"', () {
      final m = _model(totalAmount: 0);
      expect(m.formattedTotal, '0원');
    });

    test('SCENARIO-WDM-L04: taxDeductionLabel — typeNone → 세금 없음', () {
      final m = _model(taxDeductionType: InsuranceRateModel.typeNone);
      expect(m.taxDeductionLabel, '세금 없음');
    });

    test('SCENARIO-WDM-L05: taxDeductionLabel — typeFreelancer33 → 3.3% 원천징수', () {
      final m = _model(taxDeductionType: InsuranceRateModel.typeFreelancer33);
      expect(m.taxDeductionLabel, '3.3% 원천징수');
    });

    test('SCENARIO-WDM-L06: taxDeductionLabel — typeFourInsuranceFixed → 4대보험 고정', () {
      final m = _model(taxDeductionType: InsuranceRateModel.typeFourInsuranceFixed);
      expect(m.taxDeductionLabel, '4대보험 고정');
    });

    test('SCENARIO-WDM-L07: toString 표현에 핵심 필드 포함', () {
      final m = _model(
        wageType: 'hourly',
        baseWage: 10320,
        totalAmount: 100000,
        calculatedAt: DateTime(2026, 6, 15, 12),
      );
      final str = m.toString();
      expect(str, contains('hourly'));
      expect(str, contains('10320'));
      expect(str, contains('100000'));
      expect(str, contains('isCalculated: true'));
    });
  });
}
