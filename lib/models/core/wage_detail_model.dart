import 'package:cloud_firestore/cloud_firestore.dart';

/// 급여 상세 모델
/// AttendanceModel에 임베디드되어 급여 계산 정보를 저장
class WageDetailModel {
  // ========== 기본 정보 ==========
  final String wageType;           // 'hourly' | 'daily'
  final int baseWage;              // 시급/일급 단가
  
  // ========== 시간 계산 (분 단위) ==========
  final int scheduledMinutes;      // 예정 근무시간
  final int actualMinutes;         // 실제 근무시간 (출퇴근 기준)
  final int breakMinutes;          // 휴게시간
  final int workMinutes;           // 실 근무시간 (actual - break)
  final int overtimeMinutes;       // 연장근무 (시급제: 8시간 초과분 / 일급제: 예정시간 초과분)
  final int nightMinutes;          // 야간근무 (22:00~06:00)
  
  // ========== 금액 계산 ==========
  final int baseAmount;            // 기본급
  final int overtimeAmount;        // 연장수당
  final int nightAmount;           // 야간수당
  final int additionalAmount;      // 추가수당 (급구 인센티브 등)
  final int deductionAmount;       // 추가공제 (안전화·식비 등 차감)
  final int weeklyHolidayAmount;   // 주휴수당 (주 15h 이상 개근 시)
  final int totalAmount;           // 총액 (세전)
  
  // ========== 옵션 ==========
  final bool nightAllowanceApplied; // 야간수당 별도 적용 여부
  final String? memo;              // 메모
  
  // ========== 계산 기준 ==========
  final int appliedMinimumWage;    // 적용된 최저시급 (계산 당시 기준)
  
  // ========== 1차 확정 (calculated) ==========
  final String? calculatedBy;      // 계산한 관리자 UID
  final DateTime? calculatedAt;    // 계산 시각
  
  // ========== 최종 확정 (confirmed) ==========
  final String? confirmedBy;       // 최종 확정한 관리자 UID
  final DateTime? confirmedAt;     // 최종 확정 시각

  WageDetailModel({
    required this.wageType,
    required this.baseWage,
    this.scheduledMinutes = 0,
    this.actualMinutes = 0,
    this.breakMinutes = 0,
    this.workMinutes = 0,
    this.overtimeMinutes = 0,
    this.nightMinutes = 0,
    this.baseAmount = 0,
    this.overtimeAmount = 0,
    this.nightAmount = 0,
    this.additionalAmount = 0,
    this.deductionAmount = 0,
    this.weeklyHolidayAmount = 0,
    this.totalAmount = 0,
    this.nightAllowanceApplied = false,
    this.memo,
    this.appliedMinimumWage = 10030,
    this.calculatedBy,
    this.calculatedAt,
    this.confirmedBy,
    this.confirmedAt,
  });

  /// Map → WageDetailModel
  factory WageDetailModel.fromMap(Map<String, dynamic> map) {
    return WageDetailModel(
      wageType: map['wageType'] ?? 'hourly',
      baseWage: map['baseWage'] ?? 0,
      scheduledMinutes: map['scheduledMinutes'] ?? 0,
      actualMinutes: map['actualMinutes'] ?? 0,
      breakMinutes: map['breakMinutes'] ?? 0,
      workMinutes: map['workMinutes'] ?? 0,
      overtimeMinutes: map['overtimeMinutes'] ?? 0,
      nightMinutes: map['nightMinutes'] ?? 0,
      baseAmount: map['baseAmount'] ?? 0,
      overtimeAmount: map['overtimeAmount'] ?? 0,
      nightAmount: map['nightAmount'] ?? 0,
      additionalAmount: map['additionalAmount'] ?? 0,
      deductionAmount: map['deductionAmount'] ?? 0,
      weeklyHolidayAmount: map['weeklyHolidayAmount'] ?? 0,
      totalAmount: map['totalAmount'] ?? 0,
      nightAllowanceApplied: map['nightAllowanceApplied'] ?? false,
      memo: map['memo'],
      appliedMinimumWage: map['appliedMinimumWage'] ?? 10030,
      calculatedBy: map['calculatedBy'],
      calculatedAt: map['calculatedAt'] != null
          ? (map['calculatedAt'] as Timestamp).toDate().toLocal()
          : null,
      confirmedBy: map['confirmedBy'],
      confirmedAt: map['confirmedAt'] != null
          ? (map['confirmedAt'] as Timestamp).toDate().toLocal()
          : null,
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
      'nightMinutes': nightMinutes,
      'baseAmount': baseAmount,
      'overtimeAmount': overtimeAmount,
      'nightAmount': nightAmount,
      'additionalAmount': additionalAmount,
      'deductionAmount': deductionAmount,
      'weeklyHolidayAmount': weeklyHolidayAmount,
      'totalAmount': totalAmount,
      'nightAllowanceApplied': nightAllowanceApplied,
      'memo': memo,
      'appliedMinimumWage': appliedMinimumWage,
      'calculatedBy': calculatedBy,
      'calculatedAt': calculatedAt != null 
          ? Timestamp.fromDate(calculatedAt!) 
          : null,
      'confirmedBy': confirmedBy,
      'confirmedAt': confirmedAt != null 
          ? Timestamp.fromDate(confirmedAt!) 
          : null,
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
    int? nightMinutes,
    int? baseAmount,
    int? overtimeAmount,
    int? nightAmount,
    int? additionalAmount,
    int? deductionAmount,
    int? weeklyHolidayAmount,
    int? totalAmount,
    bool? nightAllowanceApplied,
    String? memo,
    int? appliedMinimumWage,
    String? calculatedBy,
    DateTime? calculatedAt,
    String? confirmedBy,
    DateTime? confirmedAt,
  }) {
    return WageDetailModel(
      wageType: wageType ?? this.wageType,
      baseWage: baseWage ?? this.baseWage,
      scheduledMinutes: scheduledMinutes ?? this.scheduledMinutes,
      actualMinutes: actualMinutes ?? this.actualMinutes,
      breakMinutes: breakMinutes ?? this.breakMinutes,
      workMinutes: workMinutes ?? this.workMinutes,
      overtimeMinutes: overtimeMinutes ?? this.overtimeMinutes,
      nightMinutes: nightMinutes ?? this.nightMinutes,
      baseAmount: baseAmount ?? this.baseAmount,
      overtimeAmount: overtimeAmount ?? this.overtimeAmount,
      nightAmount: nightAmount ?? this.nightAmount,
      additionalAmount: additionalAmount ?? this.additionalAmount,
      deductionAmount: deductionAmount ?? this.deductionAmount,
      weeklyHolidayAmount: weeklyHolidayAmount ?? this.weeklyHolidayAmount,
      totalAmount: totalAmount ?? this.totalAmount,
      nightAllowanceApplied: nightAllowanceApplied ?? this.nightAllowanceApplied,
      memo: memo ?? this.memo,
      appliedMinimumWage: appliedMinimumWage ?? this.appliedMinimumWage,
      calculatedBy: calculatedBy ?? this.calculatedBy,
      calculatedAt: calculatedAt ?? this.calculatedAt,
      confirmedBy: confirmedBy ?? this.confirmedBy,
      confirmedAt: confirmedAt ?? this.confirmedAt,
    );
  }

  // ========== Getter ==========
  
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