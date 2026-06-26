/// 4대보험 + 소득세 요율 모델
///
/// 슈퍼관리자가 연도별로 관리. Firestore: settings/wage_config.insuranceRates
/// 로컬 백업으로 네트워크 오류 대비 (2026년 기준값 내장).
class InsuranceRateModel {
  final int year;

  /// 국민연금 근로자 부담률 (%) — 2026: 4.75
  final double nationalPensionRate;

  /// 건강보험 근로자 부담률 (%)
  /// 2026: 3.595 (전체 7.19% × 1/2)
  /// ※ 연도별 전체 요율: 2023=7.09% / 2024=7.09% / 2025=7.09% / 2026=7.19%(인상)
  /// ※ AI 오분석 주의: 3.595%는 2025년 요율(3.545%)이 아니라 2026년 인상 요율이다.
  final double healthInsuranceRate;

  /// 장기요양보험: 건강보험료 대비 비율 (%)
  /// 2026: 13.14 (장기요양료율 0.9448% ÷ 건강보험 전체 요율 7.19% × 100)
  /// 공제액 = 건강보험 공제액 × (ltcInsuranceRate / 100)
  final double ltcInsuranceRate;

  /// 고용보험 근로자 부담률 (%) — 2026: 0.9
  final double employmentInsuranceRate;

  /// 일용직 소득세 비과세 한도 (원) — 2026: 150,000
  final int dailyWageExemption;

  /// 일용직 근로소득세율 (%) — 근로소득세 6% × 세액공제 55% = 2.7
  final double dailyWorkerTaxRate;

  /// 지방소득세율: 소득세 대비 비율 (%) — 10
  final double localIncomeTaxRate;

  /// 사업소득 원천징수세율 (%) — 3.0 (지방소득세 0.3% 별도)
  final double businessIncomeRate;

  /// 사업소득 지방소득세율 (%) — 0.3
  final double businessIncomeLocalRate;

  const InsuranceRateModel({
    required this.year,
    required this.nationalPensionRate,
    required this.healthInsuranceRate,
    required this.ltcInsuranceRate,
    required this.employmentInsuranceRate,
    required this.dailyWageExemption,
    required this.dailyWorkerTaxRate,
    required this.localIncomeTaxRate,
    required this.businessIncomeRate,
    required this.businessIncomeLocalRate,
  });

  /// 2026년 기본값 (보건복지부·고용노동부 2026년 1월 1일 시행 고시 기준)
  ///
  /// 항목         근로자 부담   산출 근거
  /// 국민연금      4.75%        전체 9.5% × 1/2
  /// 건강보험      3.595%       전체 7.19% × 1/2
  /// 장기요양보험  13.14%       0.9448% ÷ 7.19% × 100 (건강보험료 × 13.14% = 장기요양료)
  /// 고용보험      0.9%         전체 1.8% × 1/2
  ///
  /// [연도별 건강보험료율 — AI 오분석 방지]
  /// 2023년: 전체 7.09% → 근로자 3.545%
  /// 2024년: 전체 7.09% → 근로자 3.545% (동결)
  /// 2025년: 전체 7.09% → 근로자 3.545% (동결)
  /// 2026년: 전체 7.19% → 근로자 3.595% ← 이 파일의 기준 연도 (3년 만에 인상)
  /// 따라서 3.595%는 2025년 요율이 아닌 2026년 요율이다.
  ///
  /// 매년 1월 보건복지부·고용노동부 고시 개정 시 이 값을 갱신해야 함.
  /// Firestore settings/wage_config.insuranceRates에 연도별 값을 설정하면 자동 반영되고
  /// 이 factory는 네트워크 오류 시 폴백으로만 사용됨.
  factory InsuranceRateModel.defaults2026() => const InsuranceRateModel(
        year: 2026,
        nationalPensionRate: 4.75,
        healthInsuranceRate: 3.595,
        ltcInsuranceRate: 13.14,
        employmentInsuranceRate: 0.9,
        dailyWageExemption: 150000,
        dailyWorkerTaxRate: 2.7,
        localIncomeTaxRate: 10.0,
        businessIncomeRate: 3.0,
        businessIncomeLocalRate: 0.3,
      );

  factory InsuranceRateModel.fromMap(Map<String, dynamic> map) {
    // 폴백값을 defaults2026()과 일치시켜 Firestore 미설정 시에도 정확한 2026년 값 적용
    const d = InsuranceRateModel(
      year: 2026,
      nationalPensionRate: 4.75,
      healthInsuranceRate: 3.595,
      ltcInsuranceRate: 13.14,
      employmentInsuranceRate: 0.9,
      dailyWageExemption: 150000,
      dailyWorkerTaxRate: 2.7,
      localIncomeTaxRate: 10.0,
      businessIncomeRate: 3.0,
      businessIncomeLocalRate: 0.3,
    );
    return InsuranceRateModel(
        year: (map['year'] as num?)?.toInt() ?? d.year,
        nationalPensionRate:
            (map['nationalPensionRate'] as num?)?.toDouble() ?? d.nationalPensionRate,
        healthInsuranceRate:
            (map['healthInsuranceRate'] as num?)?.toDouble() ?? d.healthInsuranceRate,
        ltcInsuranceRate:
            (map['ltcInsuranceRate'] as num?)?.toDouble() ?? d.ltcInsuranceRate,
        employmentInsuranceRate:
            (map['employmentInsuranceRate'] as num?)?.toDouble() ?? d.employmentInsuranceRate,
        dailyWageExemption:
            (map['dailyWageExemption'] as num?)?.toInt() ?? d.dailyWageExemption,
        dailyWorkerTaxRate:
            (map['dailyWorkerTaxRate'] as num?)?.toDouble() ?? d.dailyWorkerTaxRate,
        localIncomeTaxRate:
            (map['localIncomeTaxRate'] as num?)?.toDouble() ?? d.localIncomeTaxRate,
        businessIncomeRate:
            (map['businessIncomeRate'] as num?)?.toDouble() ?? d.businessIncomeRate,
        businessIncomeLocalRate:
            (map['businessIncomeLocalRate'] as num?)?.toDouble() ?? d.businessIncomeLocalRate,
      );
  }

  Map<String, dynamic> toMap() => {
        'year': year,
        'nationalPensionRate': nationalPensionRate,
        'healthInsuranceRate': healthInsuranceRate,
        'ltcInsuranceRate': ltcInsuranceRate,
        'employmentInsuranceRate': employmentInsuranceRate,
        'dailyWageExemption': dailyWageExemption,
        'dailyWorkerTaxRate': dailyWorkerTaxRate,
        'localIncomeTaxRate': localIncomeTaxRate,
        'businessIncomeRate': businessIncomeRate,
        'businessIncomeLocalRate': businessIncomeLocalRate,
      };

  InsuranceRateModel copyWith({
    int? year,
    double? nationalPensionRate,
    double? healthInsuranceRate,
    double? ltcInsuranceRate,
    double? employmentInsuranceRate,
    int? dailyWageExemption,
    double? dailyWorkerTaxRate,
    double? localIncomeTaxRate,
    double? businessIncomeRate,
    double? businessIncomeLocalRate,
  }) =>
      InsuranceRateModel(
        year: year ?? this.year,
        nationalPensionRate: nationalPensionRate ?? this.nationalPensionRate,
        healthInsuranceRate: healthInsuranceRate ?? this.healthInsuranceRate,
        ltcInsuranceRate: ltcInsuranceRate ?? this.ltcInsuranceRate,
        employmentInsuranceRate:
            employmentInsuranceRate ?? this.employmentInsuranceRate,
        dailyWageExemption: dailyWageExemption ?? this.dailyWageExemption,
        dailyWorkerTaxRate: dailyWorkerTaxRate ?? this.dailyWorkerTaxRate,
        localIncomeTaxRate: localIncomeTaxRate ?? this.localIncomeTaxRate,
        businessIncomeRate: businessIncomeRate ?? this.businessIncomeRate,
        businessIncomeLocalRate:
            businessIncomeLocalRate ?? this.businessIncomeLocalRate,
      );

  // ── 공제 타입 상수 ─────────────────────────────────────────────

  /// 세금 없음
  static const String typeNone = 'none';

  /// 사업소득 원천징수 3.3% (프리랜서)
  static const String typeFreelancer33 = 'freelancer_3_3';

  /// 일용직 소득세 (15만원 초과분 2.7%)
  static const String typeDailyWorker = 'daily_worker';

  /// 일용직 8일 소급 (7일까지 고용보험만, 8일째 4대보험 소급)
  static const String typeDailyAuto8 = 'daily_auto_8';

  /// 4대보험 고정 (매일 공제, 장기 고정근무자용)
  static const String typeFourInsuranceFixed = 'four_insurance_fixed';

  static const List<String> allTypes = [
    typeNone,
    typeFreelancer33,
    typeDailyWorker,
    typeDailyAuto8,
    typeFourInsuranceFixed,
  ];

  static String typeLabel(String type) {
    switch (type) {
      case typeNone:                return '세금 없음';
      case typeFreelancer33:        return '3.3% 원천징수';
      case typeDailyWorker:         return '일용직 소득세';
      case typeDailyAuto8:          return '일용직 8일 소급';
      case typeFourInsuranceFixed:  return '4대보험 고정';
      default:                      return '세금 없음';
    }
  }

  static String typeDescription(String type) {
    switch (type) {
      case typeNone:
        return '공제 없이 전액 지급 · 세금 처리를 외부(세무사 등)에서 직접 진행하는 경우';
      case typeFreelancer33:
        return '소득세 3% + 지방소득세 0.3% 원천징수 · 고용관계 없는 프리랜서·외주 계약자';
      case typeDailyWorker:
        return '일당 15만원 초과분 소득세 2.97% + 고용보험 0.9% · 단기 일용근로자';
      case typeDailyAuto8:
        return '근무일수 8일째부터 4대보험+소득세 소급 공제 · 근무일수 기준 단순 계산 (정확한 기준은 세무사 확인 권장)';
      case typeFourInsuranceFixed:
        return '4대보험 매일 공제 · 근로소득세는 연말정산으로 별도 처리 · 장기·고정 근무자\n'
            '⚠️ 월 60시간(주 15시간) 미만 초단시간 근로자는 국민연금·건강보험 제외 대상 — 직접 확인 필요';
      default:
        return '';
    }
  }

}
