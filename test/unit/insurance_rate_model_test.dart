// test/unit/insurance_rate_model_test.dart
// InsuranceRateModel 단위 테스트 — Firebase 의존성 없음 (순수 Dart)
//
// 실행: flutter test test/unit/insurance_rate_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';

void main() {
  // ────────────────────────────────────────────────────────────────
  // 1. defaults2026 — 2026년 기준값 정확성
  // ────────────────────────────────────────────────────────────────
  group('InsuranceRateModel.defaults2026 — 2026년 법정 요율', () {
    late InsuranceRateModel d;
    setUpAll(() => d = InsuranceRateModel.defaults2026());

    test('IRM-01 year == 2026', () => expect(d.year, 2026));
    test('IRM-02 국민연금 4.75% (전체 9.5% × 1/2)', () => expect(d.nationalPensionRate, 4.75));
    test('IRM-03 건강보험 3.595% (전체 7.19% × 1/2, 2026년 인상)', () {
      expect(d.healthInsuranceRate, 3.595);
      // 2025년 요율(3.545%)과 다름 — AI 오분석 방지 테스트
      expect(d.healthInsuranceRate, isNot(3.545));
    });
    test('IRM-04 장기요양 13.14% (0.9448÷7.19×100)', () => expect(d.ltcInsuranceRate, 13.14));
    test('IRM-05 고용보험 0.9%', () => expect(d.employmentInsuranceRate, 0.9));
    test('IRM-06 일용직 비과세 한도 150,000원', () => expect(d.dailyWageExemption, 150000));
    test('IRM-07 일용직 세율 2.7% (6% × 55% 세액공제)', () => expect(d.dailyWorkerTaxRate, 2.7));
    test('IRM-08 지방소득세 소득세 대비 10%', () => expect(d.localIncomeTaxRate, 10.0));
    test('IRM-09 사업소득 원천징수 3.0%', () => expect(d.businessIncomeRate, 3.0));
    test('IRM-10 사업소득 지방세 0.3%', () => expect(d.businessIncomeLocalRate, 0.3));
  });

  // ────────────────────────────────────────────────────────────────
  // 2. fromMap — 정상 파싱
  // ────────────────────────────────────────────────────────────────
  group('InsuranceRateModel.fromMap — 정상 맵 파싱', () {
    final testMap = {
      'year': 2025,
      'nationalPensionRate': 4.5,
      'healthInsuranceRate': 3.545,
      'ltcInsuranceRate': 12.95,
      'employmentInsuranceRate': 0.9,
      'dailyWageExemption': 150000,
      'dailyWorkerTaxRate': 2.7,
      'localIncomeTaxRate': 10.0,
      'businessIncomeRate': 3.0,
      'businessIncomeLocalRate': 0.3,
    };

    test('IRM-FROM-01 year 필드 파싱', () {
      final m = InsuranceRateModel.fromMap(testMap);
      expect(m.year, 2025);
    });

    test('IRM-FROM-02 건강보험 3.545% (2025년 요율) 정확 파싱', () {
      final m = InsuranceRateModel.fromMap(testMap);
      expect(m.healthInsuranceRate, 3.545);
    });

    test('IRM-FROM-03 int 타입 dailyWageExemption 파싱', () {
      final m = InsuranceRateModel.fromMap(testMap);
      expect(m.dailyWageExemption, 150000);
    });

    test('IRM-FROM-04 num(double) → double 변환 정확', () {
      final m = InsuranceRateModel.fromMap({'nationalPensionRate': 4.75});
      expect(m.nationalPensionRate, 4.75);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // 3. fromMap — 누락 필드 → 2026 기본값 폴백
  // ────────────────────────────────────────────────────────────────
  group('InsuranceRateModel.fromMap — 빈 맵 → 2026 기본값', () {
    late InsuranceRateModel fallback;
    setUpAll(() => fallback = InsuranceRateModel.fromMap({}));

    test('IRM-FB-01 year 기본값 2026', () => expect(fallback.year, 2026));
    test('IRM-FB-02 nationalPensionRate 기본값 4.75', () => expect(fallback.nationalPensionRate, 4.75));
    test('IRM-FB-03 healthInsuranceRate 기본값 3.595', () => expect(fallback.healthInsuranceRate, 3.595));
    test('IRM-FB-04 ltcInsuranceRate 기본값 13.14', () => expect(fallback.ltcInsuranceRate, 13.14));
    test('IRM-FB-05 dailyWageExemption 기본값 150,000', () => expect(fallback.dailyWageExemption, 150000));
  });

  // ────────────────────────────────────────────────────────────────
  // 4. fromMap — 극단값 clamp (MEDIUM-01 보안 설계)
  // ────────────────────────────────────────────────────────────────
  group('InsuranceRateModel.fromMap — 극단값 clamp (MEDIUM-01)', () {
    test('IRM-CLAMP-01 nationalPensionRate > 20 → 20으로 clamp', () {
      final m = InsuranceRateModel.fromMap({'nationalPensionRate': 99.0});
      expect(m.nationalPensionRate, 20.0);
    });

    test('IRM-CLAMP-02 nationalPensionRate < 0 → 0으로 clamp', () {
      final m = InsuranceRateModel.fromMap({'nationalPensionRate': -5.0});
      expect(m.nationalPensionRate, 0.0);
    });

    test('IRM-CLAMP-03 healthInsuranceRate 극단값 clamp', () {
      final m = InsuranceRateModel.fromMap({'healthInsuranceRate': 100.0});
      expect(m.healthInsuranceRate, 20.0);
    });

    test('IRM-CLAMP-04 ltcInsuranceRate 상한 30 (건강보험 기반 특성 반영)', () {
      final m = InsuranceRateModel.fromMap({'ltcInsuranceRate': 50.0});
      expect(m.ltcInsuranceRate, 30.0);
    });

    test('IRM-CLAMP-05 dailyWageExemption 상한 500,000원', () {
      final m = InsuranceRateModel.fromMap({'dailyWageExemption': 1000000});
      expect(m.dailyWageExemption, 500000);
    });

    test('IRM-CLAMP-06 dailyWageExemption 하한 0원 (음수 불가)', () {
      final m = InsuranceRateModel.fromMap({'dailyWageExemption': -1});
      expect(m.dailyWageExemption, 0);
    });

    test('IRM-CLAMP-07 정상 범위 값은 clamp 영향 없음', () {
      final m = InsuranceRateModel.fromMap({'nationalPensionRate': 4.75});
      expect(m.nationalPensionRate, 4.75);  // 그대로 유지
    });
  });

  // ────────────────────────────────────────────────────────────────
  // 5. toMap → fromMap 왕복 직렬화
  // ────────────────────────────────────────────────────────────────
  group('InsuranceRateModel 왕복 직렬화 (toMap → fromMap)', () {
    test('IRM-ROUND-01 defaults2026 왕복 후 동일 값', () {
      final original = InsuranceRateModel.defaults2026();
      final roundTripped = InsuranceRateModel.fromMap(original.toMap());
      expect(roundTripped.year, original.year);
      expect(roundTripped.nationalPensionRate, original.nationalPensionRate);
      expect(roundTripped.healthInsuranceRate, original.healthInsuranceRate);
      expect(roundTripped.ltcInsuranceRate, original.ltcInsuranceRate);
      expect(roundTripped.employmentInsuranceRate, original.employmentInsuranceRate);
      expect(roundTripped.dailyWageExemption, original.dailyWageExemption);
      expect(roundTripped.dailyWorkerTaxRate, original.dailyWorkerTaxRate);
      expect(roundTripped.localIncomeTaxRate, original.localIncomeTaxRate);
      expect(roundTripped.businessIncomeRate, original.businessIncomeRate);
      expect(roundTripped.businessIncomeLocalRate, original.businessIncomeLocalRate);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // 6. copyWith
  // ────────────────────────────────────────────────────────────────
  group('InsuranceRateModel.copyWith', () {
    test('IRM-CW-01 단일 필드 변경, 나머지 유지', () {
      final original = InsuranceRateModel.defaults2026();
      final copy = original.copyWith(year: 2027, nationalPensionRate: 4.9);
      expect(copy.year, 2027);
      expect(copy.nationalPensionRate, 4.9);
      expect(copy.healthInsuranceRate, original.healthInsuranceRate);  // 유지
    });
  });

  // ────────────────────────────────────────────────────────────────
  // 7. 공제 타입 상수 및 typeLabel
  // ────────────────────────────────────────────────────────────────
  group('InsuranceRateModel — 공제 타입 상수', () {
    test('IRM-TYPE-01 allTypes 5종 포함', () {
      expect(InsuranceRateModel.allTypes, hasLength(5));
      expect(InsuranceRateModel.allTypes, containsAll([
        InsuranceRateModel.typeNone,
        InsuranceRateModel.typeFreelancer33,
        InsuranceRateModel.typeDailyWorker,
        InsuranceRateModel.typeDailyAuto8,
        InsuranceRateModel.typeFourInsuranceFixed,
      ]));
    });

    test('IRM-TYPE-02 typeLabel — none → 세금 없음', () {
      expect(InsuranceRateModel.typeLabel(InsuranceRateModel.typeNone), '세금 없음');
    });

    test('IRM-TYPE-03 typeLabel — freelancer_3_3 → 3.3% 원천징수', () {
      expect(InsuranceRateModel.typeLabel(InsuranceRateModel.typeFreelancer33), '3.3% 원천징수');
    });

    test('IRM-TYPE-04 typeLabel — daily_worker → 일용직 소득세', () {
      expect(InsuranceRateModel.typeLabel(InsuranceRateModel.typeDailyWorker), '일용직 소득세');
    });

    test('IRM-TYPE-05 typeLabel — daily_auto_8 → 일용직 8일 소급', () {
      expect(InsuranceRateModel.typeLabel(InsuranceRateModel.typeDailyAuto8), '일용직 8일 소급');
    });

    test('IRM-TYPE-06 typeLabel — four_insurance_fixed → 4대보험 고정', () {
      expect(InsuranceRateModel.typeLabel(InsuranceRateModel.typeFourInsuranceFixed), '4대보험 고정');
    });

    test('IRM-TYPE-07 typeLabel — 알 수 없는 타입 → 세금 없음 (default)', () {
      expect(InsuranceRateModel.typeLabel('unknown_garbage'), '세금 없음');
    });

    test('IRM-TYPE-08 typeDescription — typeNone 비어있지 않음', () {
      expect(InsuranceRateModel.typeDescription(InsuranceRateModel.typeNone), isNotEmpty);
    });

    test('IRM-TYPE-09 typeDescription — typeFourInsuranceFixed 초단시간 주의문구 포함', () {
      final desc = InsuranceRateModel.typeDescription(InsuranceRateModel.typeFourInsuranceFixed);
      expect(desc, contains('60시간'));
    });
  });
}
