import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';

// ── 헬퍼: 기본 WageDetailModel 생성 ──────────────────────────────────────────

WageDetailModel _base({
  int totalAmount = 100000,
  int netWage = 0,
  int employmentInsuranceDeduction = 0,
  int nationalPensionDeduction = 0,
  int healthInsuranceDeduction = 0,
  int ltcInsuranceDeduction = 0,
  int incomeTaxDeduction = 0,
  int retroactiveDeduction = 0,
  DateTime? calculatedAt,
  String taxDeductionType = InsuranceRateModel.typeNone,
}) {
  return WageDetailModel(
    wageType: 'hourly',
    baseWage: 10000,
    totalAmount: totalAmount,
    netWage: netWage,
    employmentInsuranceDeduction: employmentInsuranceDeduction,
    nationalPensionDeduction: nationalPensionDeduction,
    healthInsuranceDeduction: healthInsuranceDeduction,
    ltcInsuranceDeduction: ltcInsuranceDeduction,
    incomeTaxDeduction: incomeTaxDeduction,
    retroactiveDeduction: retroactiveDeduction,
    calculatedAt: calculatedAt,
    taxDeductionType: taxDeductionType,
  );
}

void main() {
  group('WageDetailModel.isCalculated', () {
    test('calculatedAt == null → false', () {
      final m = _base();
      expect(m.isCalculated, isFalse);
    });

    test('calculatedAt != null → true', () {
      final m = _base(calculatedAt: DateTime(2025, 1, 1));
      expect(m.isCalculated, isTrue);
    });
  });

  group('WageDetailModel.totalInsuranceDeduction', () {
    test('공제 없음 → 0', () {
      expect(_base().totalInsuranceDeduction, 0);
    });

    test('개별 공제액 합산', () {
      final m = _base(
        employmentInsuranceDeduction: 900,
        nationalPensionDeduction: 4500,
        healthInsuranceDeduction: 3550,
        ltcInsuranceDeduction: 460,
        incomeTaxDeduction: 1050,
        retroactiveDeduction: 500,
      );
      expect(m.totalInsuranceDeduction, 900 + 4500 + 3550 + 460 + 1050 + 500);
    });

    test('일부 공제만 있을 때', () {
      final m = _base(
        employmentInsuranceDeduction: 1000,
        incomeTaxDeduction: 2000,
      );
      expect(m.totalInsuranceDeduction, 3000);
    });
  });

  group('WageDetailModel.effectiveNetWage', () {
    test('미확정(calculatedAt=null) → totalAmount - totalInsuranceDeduction', () {
      final m = _base(
        totalAmount: 100000,
        employmentInsuranceDeduction: 900,
        nationalPensionDeduction: 4500,
      );
      expect(m.effectiveNetWage, 100000 - 900 - 4500);
    });

    test('확정(calculatedAt!=null) → netWage 그대로', () {
      final m = _base(
        totalAmount: 100000,
        netWage: 93050,
        employmentInsuranceDeduction: 900,
        nationalPensionDeduction: 4500,
        calculatedAt: DateTime(2025, 6, 1),
      );
      expect(m.effectiveNetWage, 93050);
    });

    test('공제 없고 미확정 → totalAmount 그대로', () {
      final m = _base(totalAmount: 80000);
      expect(m.effectiveNetWage, 80000);
    });

    test('확정 시 netWage가 0이어도 0 반환 (totalAmount 폴백 없음)', () {
      final m = _base(
        totalAmount: 100000,
        netWage: 0,
        calculatedAt: DateTime(2025, 6, 1),
      );
      expect(m.effectiveNetWage, 0);
    });
  });

  group('WageDetailModel.formattedNetWage', () {
    test('미확정 — 천 단위 포맷', () {
      final m = _base(totalAmount: 123456);
      expect(m.formattedNetWage, '123,456원');
    });

    test('확정 — netWage 기반 포맷', () {
      final m = _base(
        netWage: 1234567,
        calculatedAt: DateTime(2025, 1, 1),
      );
      expect(m.formattedNetWage, '1,234,567원');
    });

    test('0원 포맷', () {
      final m = _base(totalAmount: 0);
      expect(m.formattedNetWage, '0원');
    });
  });
}
