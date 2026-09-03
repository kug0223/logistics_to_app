import 'package:cloud_firestore/cloud_firestore.dart';
import 'insurance_rate_model.dart';
import '../../utils/firestore_helper.dart';

/// 급여 상세 모델
/// AttendanceModel에 임베디드되어 급여 계산 정보를 저장
class WageDetailModel {
  static final _commaRe = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
  // ── 기본 정보 ──
  final String wageType;           // 'hourly' | 'daily'
  final int baseWage;              // 시급/일급 단가
  
  // ── 시간 계산 (분 단위) ──
  final int scheduledMinutes;      // 예정 근무시간
  final int scheduledBreakMinutes; // 예정 휴게시간 (TO 기준) — 실제와 다를 수 있음 (석식/야식 추가 시)
  final int actualMinutes;         // 실제 근무시간 (출퇴근 기준)
  final int breakMinutes;          // 실제 적용 총 휴게시간 = appliedScheduledBreakMinutes + additionalBreakMinutes
  final int workMinutes;           // 실 근무시간 (actual - break)

  // ── 휴게 상세 (Phase 3.1 — 신규 레코드만, 구형 레코드는 null) ──
  /// 계약 기본 휴게 중 실제 적용한 시간 (관리자 확정값, <= scheduledBreakMinutes)
  final int? appliedScheduledBreakMinutes;
  /// 계약 기본 휴게 외 추가 적용 무급휴게 (석식·야식 등)
  final int? additionalBreakMinutes;
  // [LEGACY MIXED SEMANTIC — Phase 6]
  // HOURLY: 8시간 초과 유급 시간 (8h 기준)
  // DAILY: 계약 유급 초과 시간 (scheduledWork 기준)
  // → canonical breakdown은 contractExcessMinutes / premiumOvertimeMinutes 사용
  final int overtimeMinutes;       // 연장근무 총합 (조출 + 연장, 시급제: 8h 초과 / 일급제: 예정 초과)
  final int earlyArrivalMinutes;   // 그 중 조출분 (예정 시작 전 근무) — 0이면 순수 연장만
  final int nightMinutes;          // 야간근무 (22:00~06:00)

  // Phase 6: canonical extra-work breakdown
  // wageType과 무관하게 동일 공식
  final int? contractExcessMinutes;  // max(0, workMinutes - scheduledWorkMins)
  final int? premiumOvertimeMinutes; // max(0, workMinutes - 480)
  
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
  // [PHASE5.2] night snapshot auditability — nullable (legacy safe)
  /// 일급에 야간수당 포함 여부 (계약 구간 내 야간 제외, 초과분만 적용)
  final bool? nightIncluded;
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
    this.scheduledBreakMinutes = 0,
    this.actualMinutes = 0,
    this.breakMinutes = 0,
    this.workMinutes = 0,
    this.appliedScheduledBreakMinutes,
    this.additionalBreakMinutes,
    this.overtimeMinutes = 0,
    this.earlyArrivalMinutes = 0,
    this.nightMinutes = 0,
    this.contractExcessMinutes,
    this.premiumOvertimeMinutes,
    this.baseAmount = 0,
    this.overtimeAmount = 0,
    this.earlyArrivalAmount = 0,
    this.nightAmount = 0,
    this.additionalAmount = 0,
    this.deductionAmount = 0,
    this.weeklyHolidayAmount = 0,
    this.totalAmount = 0,
    this.nightAllowanceApplied = false,
    this.nightIncluded,
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
      scheduledBreakMinutes: (map['scheduledBreakMinutes'] as num?)?.toInt() ?? 0,
      actualMinutes: (map['actualMinutes'] as num?)?.toInt() ?? 0,
      breakMinutes: (map['breakMinutes'] as num?)?.toInt() ?? 0,
      workMinutes: (map['workMinutes'] as num?)?.toInt() ?? 0,
      appliedScheduledBreakMinutes: (map['appliedScheduledBreakMinutes'] as num?)?.toInt(),
      additionalBreakMinutes: (map['additionalBreakMinutes'] as num?)?.toInt(),
      overtimeMinutes: (map['overtimeMinutes'] as num?)?.toInt() ?? 0,
      earlyArrivalMinutes: (map['earlyArrivalMinutes'] as num?)?.toInt() ?? 0,
      nightMinutes: (map['nightMinutes'] as num?)?.toInt() ?? 0,
      contractExcessMinutes: (map['contractExcessMinutes'] as num?)?.toInt(),
      premiumOvertimeMinutes: (map['premiumOvertimeMinutes'] as num?)?.toInt(),
      baseAmount: (map['baseAmount'] as num?)?.toInt() ?? 0,
      overtimeAmount: (map['overtimeAmount'] as num?)?.toInt() ?? 0,
      earlyArrivalAmount: (map['earlyArrivalAmount'] as num?)?.toInt() ?? 0,
      nightAmount: (map['nightAmount'] as num?)?.toInt() ?? 0,
      additionalAmount: (map['additionalAmount'] as num?)?.toInt() ?? 0,
      deductionAmount: (map['deductionAmount'] as num?)?.toInt() ?? 0,
      weeklyHolidayAmount: (map['weeklyHolidayAmount'] as num?)?.toInt() ?? 0,
      totalAmount: (map['totalAmount'] as num?)?.toInt() ?? 0,
      nightAllowanceApplied: map['nightAllowanceApplied'] ?? false,
      nightIncluded: map['nightIncluded'] as bool?,
      memo: map['memo'],
      appliedMinimumWage: (map['appliedMinimumWage'] as num?)?.toInt() ?? 10320,
      appliedSupplementWage: (map['appliedSupplementWage'] as num?)?.toInt() ?? 0,
      calculatedBy: map['calculatedBy'],
      calculatedAt: parseTimestampNullable(map['calculatedAt']),
      confirmedBy: map['confirmedBy'],
      confirmedAt: parseTimestampNullable(map['confirmedAt']),
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

  static WageDetailModel? tryFromMap(Map<String, dynamic> map) {
    try { return WageDetailModel.fromMap(map); } catch (_) { return null; }
  }

  /// WageDetailModel → Map
  Map<String, dynamic> toMap() {
    return {
      'wageType': wageType,
      'baseWage': baseWage,
      'scheduledMinutes': scheduledMinutes,
      if (scheduledBreakMinutes != 0) 'scheduledBreakMinutes': scheduledBreakMinutes,
      'actualMinutes': actualMinutes,
      'breakMinutes': breakMinutes,
      if (appliedScheduledBreakMinutes != null) 'appliedScheduledBreakMinutes': appliedScheduledBreakMinutes,
      if (additionalBreakMinutes != null) 'additionalBreakMinutes': additionalBreakMinutes,
      'workMinutes': workMinutes,
      'overtimeMinutes': overtimeMinutes,
      if (earlyArrivalMinutes != 0) 'earlyArrivalMinutes': earlyArrivalMinutes,
      'nightMinutes': nightMinutes,
      if (contractExcessMinutes != null) 'contractExcessMinutes': contractExcessMinutes!,
      if (premiumOvertimeMinutes != null) 'premiumOvertimeMinutes': premiumOvertimeMinutes!,
      'baseAmount': baseAmount,
      'overtimeAmount': overtimeAmount,
      if (earlyArrivalAmount != 0) 'earlyArrivalAmount': earlyArrivalAmount,
      'nightAmount': nightAmount,
      'additionalAmount': additionalAmount,
      'deductionAmount': deductionAmount,
      'weeklyHolidayAmount': weeklyHolidayAmount,
      'totalAmount': totalAmount,
      'nightAllowanceApplied': nightAllowanceApplied,
      if (nightIncluded != null) 'nightIncluded': nightIncluded,
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
    int? scheduledBreakMinutes,
    int? actualMinutes,
    int? breakMinutes,
    int? appliedScheduledBreakMinutes,
    int? additionalBreakMinutes,
    int? workMinutes,
    int? overtimeMinutes,
    int? earlyArrivalMinutes,
    int? nightMinutes,
    int? contractExcessMinutes,
    int? premiumOvertimeMinutes,
    int? baseAmount,
    int? overtimeAmount,
    int? earlyArrivalAmount,
    int? nightAmount,
    int? additionalAmount,
    int? deductionAmount,
    int? weeklyHolidayAmount,
    int? totalAmount,
    bool? nightAllowanceApplied,
    bool? nightIncluded,
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
      scheduledBreakMinutes: scheduledBreakMinutes ?? this.scheduledBreakMinutes,
      actualMinutes: actualMinutes ?? this.actualMinutes,
      breakMinutes: breakMinutes ?? this.breakMinutes,
      appliedScheduledBreakMinutes: appliedScheduledBreakMinutes ?? this.appliedScheduledBreakMinutes,
      additionalBreakMinutes: additionalBreakMinutes ?? this.additionalBreakMinutes,
      workMinutes: workMinutes ?? this.workMinutes,
      overtimeMinutes: overtimeMinutes ?? this.overtimeMinutes,
      earlyArrivalMinutes: earlyArrivalMinutes ?? this.earlyArrivalMinutes,
      nightMinutes: nightMinutes ?? this.nightMinutes,
      contractExcessMinutes: contractExcessMinutes ?? this.contractExcessMinutes,
      premiumOvertimeMinutes: premiumOvertimeMinutes ?? this.premiumOvertimeMinutes,
      baseAmount: baseAmount ?? this.baseAmount,
      overtimeAmount: overtimeAmount ?? this.overtimeAmount,
      earlyArrivalAmount: earlyArrivalAmount ?? this.earlyArrivalAmount,
      nightAmount: nightAmount ?? this.nightAmount,
      additionalAmount: additionalAmount ?? this.additionalAmount,
      deductionAmount: deductionAmount ?? this.deductionAmount,
      weeklyHolidayAmount: weeklyHolidayAmount ?? this.weeklyHolidayAmount,
      totalAmount: totalAmount ?? this.totalAmount,
      nightAllowanceApplied: nightAllowanceApplied ?? this.nightAllowanceApplied,
      nightIncluded: nightIncluded ?? this.nightIncluded,
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

  /// 확정 정보 초기화 복사본 — 마감 취소 시 사용.
  /// copyWith(confirmedBy: null)은 내부 ?? 패턴으로 null 초기화가 불가능하므로 별도 메서드 제공.
  WageDetailModel clearConfirmInfo() {
    return WageDetailModel(
      wageType: wageType,
      baseWage: baseWage,
      scheduledMinutes: scheduledMinutes,
      scheduledBreakMinutes: scheduledBreakMinutes,
      actualMinutes: actualMinutes,
      breakMinutes: breakMinutes,
      appliedScheduledBreakMinutes: appliedScheduledBreakMinutes,
      additionalBreakMinutes: additionalBreakMinutes,
      workMinutes: workMinutes,
      overtimeMinutes: overtimeMinutes,
      earlyArrivalMinutes: earlyArrivalMinutes,
      nightMinutes: nightMinutes,
      contractExcessMinutes: contractExcessMinutes,
      premiumOvertimeMinutes: premiumOvertimeMinutes,
      baseAmount: baseAmount,
      overtimeAmount: overtimeAmount,
      earlyArrivalAmount: earlyArrivalAmount,
      nightAmount: nightAmount,
      additionalAmount: additionalAmount,
      deductionAmount: deductionAmount,
      weeklyHolidayAmount: weeklyHolidayAmount,
      totalAmount: totalAmount,
      nightAllowanceApplied: nightAllowanceApplied,
      nightIncluded: nightIncluded,
      memo: memo,
      appliedMinimumWage: appliedMinimumWage,
      appliedSupplementWage: appliedSupplementWage,
      calculatedBy: calculatedBy,
      calculatedAt: calculatedAt,
      confirmedBy: null,
      confirmedAt: null,
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

  // ── Getter ──
  
  // ── 휴게 breakdown getters (Phase 3.1) ──

  /// 계약 기본 휴게 중 실제 적용값 (legacy 레코드는 min(scheduled, break) 추론)
  int get effectiveAppliedScheduledBreak =>
      appliedScheduledBreakMinutes ??
      scheduledBreakMinutes.clamp(0, breakMinutes);

  /// 추가 무급휴게 (석식·야식 등) (legacy 레코드는 max(0, break - scheduled) 추론)
  int get effectiveAdditionalBreak =>
      additionalBreakMinutes ??
      (breakMinutes - effectiveAppliedScheduledBreak).clamp(0, 99999);

  /// 휴게 상세 분류가 저장된 레코드인지 여부
  bool get hasBreakBreakdown => appliedScheduledBreakMinutes != null;

  /// 계약 기본 휴게에서 실제 적용량이 축소된 경우 (review된 조기퇴근 등)
  bool get hasReducedScheduledBreak =>
      hasBreakBreakdown && appliedScheduledBreakMinutes! < scheduledBreakMinutes;

  /// 추가 무급휴게가 적용된 경우
  bool get hasAdditionalBreak =>
      effectiveAdditionalBreak > 0;

  // ── 상태 getters ──

  /// 1차 확정 여부
  // [오탐 확인] calculatedAt은 급여 확정 시 항상 DateTime.now()로 함께 설정되므로 wageStatus == 'calculated'와 항상 동기화됨.
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
  int get effectiveNetWage {
    if (isCalculated) {
      // [T-01 fix] netWage==0이지만 totalAmount>0이면 마이그레이션 전 레코드(netWage 필드 부재 → 기본값 0).
      // 계산식으로 폴백하여 실수령액 0원 오표시 방지.
      // 진짜로 실수령액이 0인 경우(totalAmount==0 또는 공제합계==totalAmount)도 계산식 결과가 0이므로 안전.
      if (netWage == 0 && totalAmount > 0) {
        return (totalAmount - totalInsuranceDeduction).clamp(0, 999999999);
      }
      return netWage.clamp(0, 999999999);
    }
    return (totalAmount - totalInsuranceDeduction).clamp(0, 999999999);
  }

  /// 포맷팅된 실수령액
  String get formattedNetWage {
    final n = effectiveNetWage;
    return '${n.toString().replaceAllMapped(
      _commaRe,
      (Match m) => '${m[1]},',
    )}원';
  }

  /// 공제 방식 라벨
  String get taxDeductionLabel => InsuranceRateModel.typeLabel(taxDeductionType);

  /// 포맷팅된 총액 (예: "59,045원")
  String get formattedTotal {
    return '${totalAmount.toString().replaceAllMapped(
      _commaRe,
      (Match m) => '${m[1]},',
    )}원';
  }

  // Phase 6: canonical extra-work breakdown getters
  bool get hasCanonicalExtraWorkBreakdown =>
      contractExcessMinutes != null && premiumOvertimeMinutes != null;

  /// 8시간 초과 × 1.5배 구간 (분)
  /// = min(contractExcessMinutes, premiumOvertimeMinutes)
  int get extraWork15xMinutes {
    if (!hasCanonicalExtraWorkBreakdown) return 0;
    final c = contractExcessMinutes!;
    final p = premiumOvertimeMinutes!;
    return c < p ? c : p;
  }

  /// 계약 초과 × 1배 구간 (분)
  /// = contractExcessMinutes - extraWork15xMinutes
  int get extraWork1xMinutes {
    if (!hasCanonicalExtraWorkBreakdown) return 0;
    return contractExcessMinutes! - extraWork15xMinutes;
  }

  @override
  String toString() {
    return 'WageDetailModel(wageType: $wageType, baseWage: $baseWage, '
        'totalAmount: $totalAmount, isCalculated: $isCalculated, isConfirmed: $isConfirmed)';
  }
}