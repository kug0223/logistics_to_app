import 'package:cloud_firestore/cloud_firestore.dart';
import 'insurance_rate_model.dart';

/// 급여 상세 모델
/// AttendanceModel에 임베디드되어 급여 계산 정보를 저장
class WageDetailModel {
  // ── 기본 정보 ──
  final String wageType;           // 'hourly' | 'daily'
  final int baseWage;              // 시급/일급 단가
  
  // ── 시간 계산 (분 단위) ──
  final int scheduledMinutes;      // 예정 근무시간
  final int actualMinutes;         // 실제 근무시간 (출퇴근 기준)
  final int breakMinutes;          // 휴게시간
  final int workMinutes;           // 실 근무시간 (actual - break)
  final int overtimeMinutes;       // 연장근무 총합 (조출 + 연장, 시급제: 8h 초과 / 일급제: 예정 초과)
  final int earlyArrivalMinutes;   // 그 중 조출분 (예정 시작 전 근무) — 0이면 순수 연장만
  final int nightMinutes;          // 야간근무 (22:00~06:00)
  
  // ── 금액 계산 ──
  final int baseAmount;            // 기본급
  final int overtimeAmount;        // 연장수당 (조출수당 포함 합계)
  final int earlyArrivalAmount;    // 조출수당 (overtimeAmount 중 조출분 — 일급제만, 시급제는 0)
  final int nightAmount;           // 야간수당
  final int additionalAmount;      // 추가수당 (급구 인센티브 등)
  final int deductionAmount;       // 추가공제 (안전화·식비 등 수동 차감)
  final int weeklyHolidayAmount;   // 주휴수당 (주 15h 이상 개근 시)
  final int totalAmount;           // 세전 총액 (기본+연장+야간+추가수당+주휴-수동공제)

  // ── 세금·보험 공제 ──
  /// 공제 방식 — InsuranceRateModel 상수값
  final String taxDeductionType;
  /// 고용보험 공제액
  final int employmentInsuranceDeduction;
  /// 국민연금 공제액
  final int nationalPensionDeduction;
  /// 건강보험 공제액
  final int healthInsuranceDeduction;
  /// 장기요양보험 공제액 (건강보험료 × ltcRate)
  final int ltcInsuranceDeduction;
  /// 소득세·사업소득세 공제액 (지방소득세 포함)
  final int incomeTaxDeduction;
  /// 8일 소급 공제액 (8일차에만 기록, 1~7일분 누적)
  final int retroactiveDeduction;
  /// 실수령액 = totalAmount - 모든 세금·보험 공제
  final int netWage;
  
  // ── 옵션 ──
  final bool nightAllowanceApplied; // 야간수당 별도 적용 여부
  final String? memo;              // 메모
  
  // ── 계산 기준 ──
  final int appliedMinimumWage;    // 적용된 최저시급 (계산 당시 기준)
  final int appliedSupplementWage; // 연장·야간수당 기초 시급 (사업주 설정 우선, 없으면 통상임금 계산)
  
  // ── 1차 확정 (calculated) ──
  final String? calculatedBy;      // 계산한 관리자 UID
  final DateTime? calculatedAt;    // 계산 시각
  
  // ── 최종 확정 (confirmed) ──
  final String? confirmedBy;       // 최종 확정한 관리자 UID
  final DateTime? confirmedAt;     // 최종 확정 시각

  // ── 지급 일정 (paymentDueDate 계산용) ──
  /// 급여 지급 유형 — WorkDetailData에서 복사 저장
  /// 'same_day' | 'next_day' | 'weekly' | 'monthly'
  final String? payScheduleType;
  /// 지급 요일/날짜 — weekly: 1~7(월~일), monthly: 1~31
  final int? payScheduleDay;

  WageDetailModel({
    required this.wageType,
    required this.baseWage,
    this.scheduledMinutes = 0,
    this.actualMinutes = 0,
    this.breakMinutes = 0,
    this.workMinutes = 0,
    this.overtimeMinutes = 0,
    this.earlyArrivalMinutes = 0,
    this.nightMinutes = 0,
    this.baseAmount = 0,
    this.overtimeAmount = 0,
    this.earlyArrivalAmount = 0,
    this.nightAmount = 0,
    this.additionalAmount = 0,
    this.deductionAmount = 0,
    this.weeklyHolidayAmount = 0,
    this.totalAmount = 0,
    this.nightAllowanceApplied = false,
    this.memo,
    this.appliedMinimumWage = 10320,
    this.appliedSupplementWage = 0,
    this.calculatedBy,
    this.calculatedAt,
    this.confirmedBy,
    this.confirmedAt,
    this.payScheduleType,
    this.payScheduleDay,
    this.taxDeductionType = InsuranceRateModel.typeNone,
    this.employmentInsuranceDeduction = 0,
    this.nationalPensionDeduction = 0,
    this.healthInsuranceDeduction = 0,
    this.ltcInsuranceDeduction = 0,
    this.incomeTaxDeduction = 0,
    this.retroactiveDeduction = 0,
    this.netWage = 0,
  });

  /// Map → WageDetailModel
  factory WageDetailModel.fromMap(Map<String, dynamic> map) {
    return WageDetailModel(
      wageType: map['wageType'] ?? 'hourly',
      baseWage: (map['baseWage'] as num?)?.toInt() ?? 0,
      scheduledMinutes: (map['scheduledMinutes'] as num?)?.toInt() ?? 0,
      actualMinutes: (map['actualMinutes'] as num?)?.toInt() ?? 0,
      breakMinutes: (map['breakMinutes'] as num?)?.toInt() ?? 0,
      workMinutes: (map['workMinutes'] as num?)?.toInt() ?? 0,
      overtimeMinutes: (map['overtimeMinutes'] as num?)?.toInt() ?? 0,
      earlyArrivalMinutes: (map['earlyArrivalMinutes'] as num?)?.toInt() ?? 0,
      nightMinutes: (map['nightMinutes'] as num?)?.toInt() ?? 0,
      baseAmount: (map['baseAmount'] as num?)?.toInt() ?? 0,
      overtimeAmount: (map['overtimeAmount'] as num?)?.toInt() ?? 0,
      earlyArrivalAmount: (map['earlyArrivalAmount'] as num?)?.toInt() ?? 0,
      nightAmount: (map['nightAmount'] as num?)?.toInt() ?? 0,
      additionalAmount: (map['additionalAmount'] as num?)?.toInt() ?? 0,
      deductionAmount: (map['deductionAmount'] as num?)?.toInt() ?? 0,
      weeklyHolidayAmount: (map['weeklyHolidayAmount'] as num?)?.toInt() ?? 0,
      totalAmount: (map['totalAmount'] as num?)?.toInt() ?? 0,
      nightAllowanceApplied: map['nightAllowanceApplied'] ?? false,
      memo: map['memo'],
      appliedMinimumWage: (map['appliedMinimumWage'] as num?)?.toInt() ?? 10320,
      appliedSupplementWage: (map['appliedSupplementWage'] as num?)?.toInt() ?? 0,
      calculatedBy: map['calculatedBy'],
      calculatedAt: map['calculatedAt'] != null
          ? (map['calculatedAt'] as Timestamp).toDate().toLocal()
          : null,
      confirmedBy: map['confirmedBy'],
      confirmedAt: map['confirmedAt'] != null
          ? (map['confirmedAt'] as Timestamp).toDate().toLocal()
          : null,
      taxDeductionType: map['taxDeductionType'] as String? ?? InsuranceRateModel.typeNone,
      employmentInsuranceDeduction: (map['employmentInsuranceDeduction'] as num?)?.toInt() ?? 0,
      nationalPensionDeduction: (map['nationalPensionDeduction'] as num?)?.toInt() ?? 0,
      healthInsuranceDeduction: (map['healthInsuranceDeduction'] as num?)?.toInt() ?? 0,
      ltcInsuranceDeduction: (map['ltcInsuranceDeduction'] as num?)?.toInt() ?? 0,
      incomeTaxDeduction: (map['incomeTaxDeduction'] as num?)?.toInt() ?? 0,
      retroactiveDeduction: (map['retroactiveDeduction'] as num?)?.toInt() ?? 0,
      netWage: (map['netWage'] as num?)?.toInt() ?? 0,
      payScheduleType: map['payScheduleType'] as String?,
      payScheduleDay:  (map['payScheduleDay'] as num?)?.toInt(),
    );
  }

  /// WageDetailModel → Map
  Map<String, dynamic> toMap() {
    return {
      'wageType': wageType,
      'baseWage': baseWage,
      'scheduledMinutes': scheduledMinutes,
      'actualMinutes': actualMinutes,
      'breakMinutes': breakMinutes,
      'workMinutes': workMinutes,
      'overtimeMinutes': overtimeMinutes,
      if (earlyArrivalMinutes != 0) 'earlyArrivalMinutes': earlyArrivalMinutes,
      'nightMinutes': nightMinutes,
      'baseAmount': baseAmount,
      'overtimeAmount': overtimeAmount,
      if (earlyArrivalAmount != 0) 'earlyArrivalAmount': earlyArrivalAmount,
      'nightAmount': nightAmount,
      'additionalAmount': additionalAmount,
      'deductionAmount': deductionAmount,
      'weeklyHolidayAmount': weeklyHolidayAmount,
      'totalAmount': totalAmount,
      'nightAllowanceApplied': nightAllowanceApplied,
      'memo': memo,
      'appliedMinimumWage': appliedMinimumWage,
      if (appliedSupplementWage != 0) 'appliedSupplementWage': appliedSupplementWage,
      'calculatedBy': calculatedBy,
      'calculatedAt': calculatedAt != null 
          ? Timestamp.fromDate(calculatedAt!) 
          : null,
      'confirmedBy': confirmedBy,
      'confirmedAt': confirmedAt != null
          ? Timestamp.fromDate(confirmedAt!)
          : null,
      'taxDeductionType': taxDeductionType,
      if (employmentInsuranceDeduction != 0) 'employmentInsuranceDeduction': employmentInsuranceDeduction,
      if (nationalPensionDeduction != 0) 'nationalPensionDeduction': nationalPensionDeduction,
      if (healthInsuranceDeduction != 0) 'healthInsuranceDeduction': healthInsuranceDeduction,
      if (ltcInsuranceDeduction != 0) 'ltcInsuranceDeduction': ltcInsuranceDeduction,
      if (incomeTaxDeduction != 0) 'incomeTaxDeduction': incomeTaxDeduction,
      if (retroactiveDeduction != 0) 'retroactiveDeduction': retroactiveDeduction,
      'netWage': netWage,
      if (payScheduleType != null) 'payScheduleType': payScheduleType,
      if (payScheduleDay != null)  'payScheduleDay':  payScheduleDay,
    };
  }

  /// 복사본 생성
  WageDetailModel copyWith({
    String? wageType,
    int? baseWage,
    int? scheduledMinutes,
    int? actualMinutes,
    int? breakMinutes,
    int? workMinutes,
    int? overtimeMinutes,
    int? earlyArrivalMinutes,
    int? nightMinutes,
    int? baseAmount,
    int? overtimeAmount,
    int? earlyArrivalAmount,
    int? nightAmount,
    int? additionalAmount,
    int? deductionAmount,
    int? weeklyHolidayAmount,
    int? totalAmount,
    bool? nightAllowanceApplied,
    String? memo,
    int? appliedMinimumWage,
    int? appliedSupplementWage,
    String? calculatedBy,
    DateTime? calculatedAt,
    String? confirmedBy,
    DateTime? confirmedAt,
    String? payScheduleType,
    int? payScheduleDay,
    String? taxDeductionType,
    int? employmentInsuranceDeduction,
    int? nationalPensionDeduction,
    int? healthInsuranceDeduction,
    int? ltcInsuranceDeduction,
    int? incomeTaxDeduction,
    int? retroactiveDeduction,
    int? netWage,
  }) {
    return WageDetailModel(
      wageType: wageType ?? this.wageType,
      baseWage: baseWage ?? this.baseWage,
      scheduledMinutes: scheduledMinutes ?? this.scheduledMinutes,
      actualMinutes: actualMinutes ?? this.actualMinutes,
      breakMinutes: breakMinutes ?? this.breakMinutes,
      workMinutes: workMinutes ?? this.workMinutes,
      overtimeMinutes: overtimeMinutes ?? this.overtimeMinutes,
      earlyArrivalMinutes: earlyArrivalMinutes ?? this.earlyArrivalMinutes,
      nightMinutes: nightMinutes ?? this.nightMinutes,
      baseAmount: baseAmount ?? this.baseAmount,
      overtimeAmount: overtimeAmount ?? this.overtimeAmount,
      earlyArrivalAmount: earlyArrivalAmount ?? this.earlyArrivalAmount,
      nightAmount: nightAmount ?? this.nightAmount,
      additionalAmount: additionalAmount ?? this.additionalAmount,
      deductionAmount: deductionAmount ?? this.deductionAmount,
      weeklyHolidayAmount: weeklyHolidayAmount ?? this.weeklyHolidayAmount,
      totalAmount: totalAmount ?? this.totalAmount,
      nightAllowanceApplied: nightAllowanceApplied ?? this.nightAllowanceApplied,
      memo: memo ?? this.memo,
      appliedMinimumWage: appliedMinimumWage ?? this.appliedMinimumWage,
      appliedSupplementWage: appliedSupplementWage ?? this.appliedSupplementWage,
      calculatedBy: calculatedBy ?? this.calculatedBy,
      calculatedAt: calculatedAt ?? this.calculatedAt,
      confirmedBy: confirmedBy ?? this.confirmedBy,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      payScheduleType: payScheduleType ?? this.payScheduleType,
      payScheduleDay:  payScheduleDay  ?? this.payScheduleDay,
      taxDeductionType: taxDeductionType ?? this.taxDeductionType,
      employmentInsuranceDeduction: employmentInsuranceDeduction ?? this.employmentInsuranceDeduction,
      nationalPensionDeduction: nationalPensionDeduction ?? this.nationalPensionDeduction,
      healthInsuranceDeduction: healthInsuranceDeduction ?? this.healthInsuranceDeduction,
      ltcInsuranceDeduction: ltcInsuranceDeduction ?? this.ltcInsuranceDeduction,
      incomeTaxDeduction: incomeTaxDeduction ?? this.incomeTaxDeduction,
      retroactiveDeduction: retroactiveDeduction ?? this.retroactiveDeduction,
      netWage: netWage ?? this.netWage,
    );
  }

  // ── Getter ──
  
  /// 1차 확정 여부
  bool get isCalculated => calculatedAt != null;
  
  /// 최종 확정 여부
  bool get isConfirmed => confirmedAt != null;
  
  /// 실 근무시간 (시간 단위)
  double get workHours => workMinutes / 60.0;
  
  /// 연장근무 시간 (시간 단위)
  double get overtimeHours => overtimeMinutes / 60.0;
  
  /// 야간근무 시간 (시간 단위)
  double get nightHours => nightMinutes / 60.0;
  
  /// 급여 타입 라벨
  String get wageTypeLabel {
    switch (wageType) {
      case 'hourly':
        return '시급';
      case 'daily':
        return '일급';
      default:
        return '급여';
    }
  }
  
  /// 세금·보험 공제 합계
  int get totalInsuranceDeduction =>
      employmentInsuranceDeduction +
      nationalPensionDeduction +
      healthInsuranceDeduction +
      ltcInsuranceDeduction +
      incomeTaxDeduction +
      retroactiveDeduction;

  /// 실수령액 (미확정 시 총액에서 공제액 차감)
  /// clamp(0): 8일차 소급 공제가 당일 세전 급여를 초과해도 음수가 되지 않도록 보호
  int get effectiveNetWage =>
      (isCalculated ? netWage : totalAmount - totalInsuranceDeduction).clamp(0, 999999999);

  /// 포맷팅된 실수령액
  String get formattedNetWage {
    final n = effectiveNetWage;
    return '${n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )}원';
  }

  /// 공제 방식 라벨
  String get taxDeductionLabel => InsuranceRateModel.typeLabel(taxDeductionType);

  /// 포맷팅된 총액 (예: "59,045원")
  String get formattedTotal {
    return '${totalAmount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )}원';
  }

  @override
  String toString() {
    return 'WageDetailModel(wageType: $wageType, baseWage: $baseWage, '
        'totalAmount: $totalAmount, isCalculated: $isCalculated, isConfirmed: $isConfirmed)';
  }
}