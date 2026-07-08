// test/simulation/admin_setup_worktype_wage_simulation_test.dart
//
// 관리자 근무유형(BusinessWorkType) 등록 → 임금(WageDetail) 설정 → 신뢰도(TrustSettings) 설정
// 전 흐름 시뮬레이션 (순수 Dart 로직, Firebase 의존 없음)
//
// 검증 범위:
//   SCENARIO-WT-01: BusinessWorkType 등록 유효성 (name, color, displayOrder, isActive, createdAt)
//   SCENARIO-WT-02: workTypesReady 사전조건 평가 (TO 등록 전 조건 체크)
//   SCENARIO-WT-03: 시급제 임금 계산 (기본급, 연장수당)
//   SCENARIO-WT-04: 일급제 임금 계산 (고정 지급, wageTypeLabel)
//   SCENARIO-WT-05: 야간수당 계산 (nightAllowanceApplied 분기)
//   SCENARIO-WT-06: taxDeductionType별 공제 라벨 (InsuranceRateModel.typeLabel)
//   SCENARIO-WT-07: payScheduleType 유효성 (same_day / next_day / weekly / monthly)
//   SCENARIO-WT-08: WageDetailModel effectiveNetWage getter
//   SCENARIO-WT-09: TrustSettings 유효성 검증
//   SCENARIO-WT-10: 신뢰도 등급 분류 (최우수/우수/보통/주의/경고)
//   SCENARIO-WT-11: 기본값 복원 (TrustSettingsModel.defaults())
//   SCENARIO-WT-12: TrustScoreHelper 기본 동작 + getNoshowPenalty
//
// 실행: flutter test test/simulation/admin_setup_worktype_wage_simulation_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/business_work_type_model.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';
import 'package:ALfit/models/settings/trust_settings_model.dart';
import 'package:ALfit/utils/trust_score_helper.dart';

// ════════════════════════════════════════════════════════════════
// 인라인 검증 헬퍼 (UI/서비스 레이어의 순수 Dart 로직 재현)
// ════════════════════════════════════════════════════════════════

/// BusinessWorkType name 검증 — 빈 문자열·공백 차단
bool _validateWorkTypeName(String name) => name.trim().isNotEmpty;

/// color #hex 6자리 형식 검증 (#RRGGBB)
bool _validateHexColor(String? color) {
  if (color == null) return false;
  return RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color);
}

/// displayOrder 자동 부여: 기존 목록 최대 + 1 (빈 목록이면 1)
int _nextDisplayOrder(List<BusinessWorkTypeModel> existing) {
  if (existing.isEmpty) return 1;
  return existing.map((w) => w.displayOrder).reduce((a, b) => a > b ? a : b) + 1;
}

/// workTypesReady 조건: 비어있지 않고 isActive=true 항목이 하나 이상
bool _workTypesReady(List<BusinessWorkTypeModel> workTypes) {
  return workTypes.isNotEmpty && workTypes.any((w) => w.isActive);
}

/// payScheduleType + payScheduleDay 유효성
bool _validatePaySchedule(String type, int? day) {
  switch (type) {
    case 'same_day':
    case 'next_day':
      return true;
    case 'weekly':
      return day != null && day >= 1 && day <= 7;
    case 'monthly':
      return day != null && day >= 1 && day <= 31;
    default:
      return false;
  }
}

/// TrustSettings 필드 유효성
bool _validateTrustSettings({
  required int startScore,
  required int maxScore,
  required int resetScore,
  required int cooldownDays,
  required int noshowReduction,
  required int lateReduction,
}) {
  if (startScore < 0 || startScore > 100) return false;
  if (maxScore > 100 || maxScore < startScore) return false;
  if (resetScore < 0 || resetScore > 100) return false;
  if (cooldownDays < 1) return false;
  if (noshowReduction < 0) return false;
  if (lateReduction < 0) return false;
  return true;
}

/// 신뢰도 등급 반환
String _trustGrade(int score) {
  if (score >= 90) return '최우수';
  if (score >= 70) return '우수';
  if (score >= 50) return '보통';
  if (score >= 30) return '주의';
  return '경고';
}

/// 시급제 임금 계산 (순수 Dart)
///
/// 기본급: hourlyWage × min(workHours, 8)
/// 연장수당: hourlyWage × 1.5 × max(workHours - 8, 0)
/// 야간수당: hourlyWage × 0.5 × nightHours (nightAllowanceApplied=true 시)
Map<String, int> _calcHourly({
  required int hourlyWage,
  required int workMinutes,
  required int nightMinutes,
  bool nightAllowanceApplied = false,
}) {
  final workHours = workMinutes / 60.0;
  final regularHours = workHours > 8.0 ? 8.0 : workHours;
  final overtimeHours = (workHours - 8.0).clamp(0.0, double.infinity);
  final baseAmount = (hourlyWage * regularHours).round();
  final overtimeAmount = (hourlyWage * 1.5 * overtimeHours).round();
  final nightAmount = nightAllowanceApplied
      ? (hourlyWage * 0.5 * (nightMinutes / 60.0)).round()
      : 0;
  return {
    'baseAmount': baseAmount,
    'overtimeAmount': overtimeAmount,
    'nightAmount': nightAmount,
    'totalAmount': baseAmount + overtimeAmount + nightAmount,
  };
}

/// 일급제 임금 계산 (순수 Dart)
///
/// 기본급: dailyWage 고정
/// 야간수당: supplementWage × 0.5 × nightHours (nightAllowanceApplied=true 시)
Map<String, int> _calcDaily({
  required int dailyWage,
  required int nightMinutes,
  required int supplementWage,
  bool nightAllowanceApplied = false,
}) {
  final nightAmount = nightAllowanceApplied
      ? (supplementWage * 0.5 * (nightMinutes / 60.0)).round()
      : 0;
  return {
    'baseAmount': dailyWage,
    'nightAmount': nightAmount,
    'totalAmount': dailyWage + nightAmount,
  };
}

// ════════════════════════════════════════════════════════════════
// 모델 생성 헬퍼 (생성자 직접 사용 — Firebase 의존 없음)
// ════════════════════════════════════════════════════════════════

BusinessWorkTypeModel _wt({
  String id = 'wt-001',
  String businessId = 'biz-001',
  String name = '피킹',
  String icon = '📦',
  String? color = '#FF5733',
  int displayOrder = 1,
  bool isActive = true,
}) {
  return BusinessWorkTypeModel(
    id: id,
    businessId: businessId,
    name: name,
    icon: icon,
    color: color,
    displayOrder: displayOrder,
    isActive: isActive,
    createdAt: DateTime(2026, 7, 1, 9, 0),
  );
}

WageDetailModel _wage({
  String wageType = 'hourly',
  int baseWage = 10320,
  int workMinutes = 480,
  int overtimeMinutes = 0,
  int nightMinutes = 0,
  int baseAmount = 0,
  int overtimeAmount = 0,
  int nightAmount = 0,
  int totalAmount = 0,
  int netWage = 0,
  bool nightAllowanceApplied = false,
  String taxDeductionType = InsuranceRateModel.typeNone,
  int employmentInsuranceDeduction = 0,
  int nationalPensionDeduction = 0,
  int healthInsuranceDeduction = 0,
  int ltcInsuranceDeduction = 0,
  int incomeTaxDeduction = 0,
  int retroactiveDeduction = 0,
  DateTime? calculatedAt,
  DateTime? confirmedAt,
  String? payScheduleType,
  int? payScheduleDay,
}) {
  return WageDetailModel(
    wageType: wageType,
    baseWage: baseWage,
    workMinutes: workMinutes,
    overtimeMinutes: overtimeMinutes,
    nightMinutes: nightMinutes,
    baseAmount: baseAmount,
    overtimeAmount: overtimeAmount,
    nightAmount: nightAmount,
    totalAmount: totalAmount,
    netWage: netWage,
    nightAllowanceApplied: nightAllowanceApplied,
    taxDeductionType: taxDeductionType,
    employmentInsuranceDeduction: employmentInsuranceDeduction,
    nationalPensionDeduction: nationalPensionDeduction,
    healthInsuranceDeduction: healthInsuranceDeduction,
    ltcInsuranceDeduction: ltcInsuranceDeduction,
    incomeTaxDeduction: incomeTaxDeduction,
    retroactiveDeduction: retroactiveDeduction,
    calculatedAt: calculatedAt,
    confirmedAt: confirmedAt,
    payScheduleType: payScheduleType,
    payScheduleDay: payScheduleDay,
  );
}

/// TrustScoreHelper.calculateFromData 단순 래퍼
int _score({
  int days = 0,
  double avg = 0.0,
  int rc = 0,
  double rr = 0.0,
  int ns = 0,
  int late = 0,
}) {
  return TrustScoreHelper.calculateFromData(
    totalWorkDays: days,
    averageRating: avg,
    reviewCount: rc,
    rehireRate: rr,
    noShowCount: ns,
    lateCount: late,
  );
}

// ════════════════════════════════════════════════════════════════
// main
// ════════════════════════════════════════════════════════════════

void main() {
  // ════════════════════════════════════════════════════════════════
  // SCENARIO-WT-01: BusinessWorkType 등록 유효성 검증
  // ════════════════════════════════════════════════════════════════
  group('SCENARIO-WT-01. BusinessWorkType 등록 유효성', () {
    test('WT-01-01: name 빈 문자열 → 차단', () {
      expect(_validateWorkTypeName(''), isFalse);
    });

    test('WT-01-02: name 공백만 → 차단', () {
      expect(_validateWorkTypeName('   '), isFalse);
    });

    test('WT-01-03: name 정상값 \'피킹\' → 통과', () {
      expect(_validateWorkTypeName('피킹'), isTrue);
    });

    test('WT-01-04: color #hex 6자리 대문자 → 유효', () {
      expect(_validateHexColor('#FF5733'), isTrue);
    });

    test('WT-01-05: color #hex 6자리 소문자 → 유효', () {
      expect(_validateHexColor('#ffffff'), isTrue);
    });

    test('WT-01-06: color # 없음 → 무효', () {
      expect(_validateHexColor('FF5733'), isFalse);
    });

    test('WT-01-07: color 잘못된 문자(G) 포함 → 무효', () {
      expect(_validateHexColor('#GGGGGG'), isFalse);
    });

    test('WT-01-08: color null → 무효', () {
      expect(_validateHexColor(null), isFalse);
    });

    test('WT-01-09: displayOrder 빈 목록 → 1 자동 부여', () {
      expect(_nextDisplayOrder([]), 1);
    });

    test('WT-01-10: displayOrder 기존 최대=3 → 4 자동 부여', () {
      final existing = [
        _wt(id: 'a', displayOrder: 1),
        _wt(id: 'b', displayOrder: 3),
        _wt(id: 'c', displayOrder: 2),
      ];
      expect(_nextDisplayOrder(existing), 4);
    });

    test('WT-01-11: 생성 시 isActive=true 기본값', () {
      final wt = _wt();
      expect(wt.isActive, isTrue);
    });

    test('WT-01-12: 생성 시 createdAt 설정 확인', () {
      final wt = _wt();
      expect(wt.createdAt, isNotNull);
    });

    test('WT-01-13: copyWith로 name 업데이트 — 원본 불변', () {
      final wt = _wt(name: '피킹');
      final updated = wt.copyWith(name: '패킹');
      expect(updated.name, '패킹');
      expect(wt.name, '피킹');
    });

    test('WT-01-14: copyWith로 isActive 비활성화', () {
      final wt = _wt(isActive: true);
      final deactivated = wt.copyWith(isActive: false);
      expect(deactivated.isActive, isFalse);
      expect(wt.isActive, isTrue); // 원본 불변
    });
  });

  // ════════════════════════════════════════════════════════════════
  // SCENARIO-WT-02: workTypesReady 사전조건 평가
  // ════════════════════════════════════════════════════════════════
  group('SCENARIO-WT-02. workTypesReady 사전조건', () {
    test('WT-02-01: workTypes 비어있음 → workTypesReady=false', () {
      expect(_workTypesReady([]), isFalse);
    });

    test('WT-02-02: isActive=true 1개 → workTypesReady=true', () {
      expect(_workTypesReady([_wt(isActive: true)]), isTrue);
    });

    test('WT-02-03: 모두 isActive=false → workTypesReady=false', () {
      final wts = [
        _wt(id: 'a', isActive: false),
        _wt(id: 'b', isActive: false),
      ];
      expect(_workTypesReady(wts), isFalse);
    });

    test('WT-02-04: 일부 true + 일부 false → workTypesReady=true', () {
      final wts = [
        _wt(id: 'a', isActive: false),
        _wt(id: 'b', isActive: true),
      ];
      expect(_workTypesReady(wts), isTrue);
    });

    test('WT-02-05: isActive=false → copyWith(isActive:true) 후 ready=true', () {
      final wt = _wt(isActive: false);
      final activated = wt.copyWith(isActive: true);
      expect(_workTypesReady([activated]), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // SCENARIO-WT-03: 시급제 임금 계산
  // ════════════════════════════════════════════════════════════════
  group('SCENARIO-WT-03. 시급제 임금 계산', () {
    test('WT-03-01: 4시간 × 시급10000 → baseAmount=40000, overtimeAmount=0', () {
      final r = _calcHourly(
        hourlyWage: 10000,
        workMinutes: 240,
        nightMinutes: 0,
      );
      expect(r['baseAmount'], 40000);
      expect(r['overtimeAmount'], 0);
    });

    test('WT-03-02: 8시간 × 시급12000 → baseAmount=96000, 연장 없음', () {
      final r = _calcHourly(
        hourlyWage: 12000,
        workMinutes: 480,
        nightMinutes: 0,
      );
      expect(r['baseAmount'], 96000);
      expect(r['overtimeAmount'], 0);
    });

    test('WT-03-03: 9시간 → 1시간 연장 × 1.5배 (시급10000)', () {
      final r = _calcHourly(
        hourlyWage: 10000,
        workMinutes: 540,
        nightMinutes: 0,
      );
      // 기본: 8h × 10000 = 80000, 연장: 1h × 1.5 × 10000 = 15000
      expect(r['baseAmount'], 80000);
      expect(r['overtimeAmount'], 15000);
      expect(r['totalAmount'], 95000);
    });

    test('WT-03-04: 10시간 → 2시간 연장 (시급10000, 연장=30000)', () {
      final r = _calcHourly(
        hourlyWage: 10000,
        workMinutes: 600,
        nightMinutes: 0,
      );
      expect(r['overtimeAmount'], 30000); // 2h × 1.5 × 10000
      expect(r['totalAmount'], 110000);   // 80000 + 30000
    });

    test('WT-03-05: 최저시급 10320 × 8시간 = 82560', () {
      final r = _calcHourly(
        hourlyWage: 10320,
        workMinutes: 480,
        nightMinutes: 0,
      );
      expect(r['baseAmount'], 82560);
    });

    test('WT-03-06: 정확히 8시간 — 연장수당 0 경계값 확인', () {
      final r = _calcHourly(
        hourlyWage: 15000,
        workMinutes: 480,
        nightMinutes: 0,
      );
      expect(r['overtimeAmount'], 0);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // SCENARIO-WT-04: 일급제 임금 계산
  // ════════════════════════════════════════════════════════════════
  group('SCENARIO-WT-04. 일급제 임금 계산', () {
    test('WT-04-01: 일급 150000 고정 지급 — 근무시간 무관', () {
      final r = _calcDaily(
        dailyWage: 150000,
        nightMinutes: 0,
        supplementWage: 10320,
      );
      expect(r['baseAmount'], 150000);
      expect(r['totalAmount'], 150000);
    });

    test('WT-04-02: 일급제 야간수당 미적용 → totalAmount=일급', () {
      final r = _calcDaily(
        dailyWage: 120000,
        nightMinutes: 120,
        supplementWage: 15000,
        nightAllowanceApplied: false,
      );
      expect(r['nightAmount'], 0);
      expect(r['totalAmount'], 120000);
    });

    test('WT-04-03: WageDetailModel wageTypeLabel \'daily\' → \'일급\'', () {
      final w = _wage(wageType: 'daily');
      expect(w.wageTypeLabel, '일급');
    });

    test('WT-04-04: WageDetailModel wageTypeLabel \'hourly\' → \'시급\'', () {
      final w = _wage(wageType: 'hourly');
      expect(w.wageTypeLabel, '시급');
    });

    test('WT-04-05: WageDetailModel wageTypeLabel 알 수 없는 값 → \'급여\' 폴백', () {
      final w = _wage(wageType: 'unknown');
      expect(w.wageTypeLabel, '급여');
    });
  });

  // ════════════════════════════════════════════════════════════════
  // SCENARIO-WT-05: 야간수당 계산
  // ════════════════════════════════════════════════════════════════
  group('SCENARIO-WT-05. 야간수당 계산', () {
    test('WT-05-01: nightAllowanceApplied=false → nightAmount=0', () {
      final r = _calcHourly(
        hourlyWage: 10000,
        workMinutes: 480,
        nightMinutes: 120,
        nightAllowanceApplied: false,
      );
      expect(r['nightAmount'], 0);
    });

    test('WT-05-02: 시급제 야간 2시간 → 시급 × 0.5 × 2h = 10000', () {
      final r = _calcHourly(
        hourlyWage: 10000,
        workMinutes: 480,
        nightMinutes: 120,
        nightAllowanceApplied: true,
      );
      // 10000 × 0.5 × 2 = 10000
      expect(r['nightAmount'], 10000);
    });

    test('WT-05-03: 일급제 야간 1시간 → 보조시급 × 0.5', () {
      final r = _calcDaily(
        dailyWage: 120000,
        nightMinutes: 60,
        supplementWage: 15480,
        nightAllowanceApplied: true,
      );
      // 15480 × 0.5 × 1h = 7740
      expect(r['nightAmount'], 7740);
      expect(r['totalAmount'], 127740);
    });

    test('WT-05-04: 야간 0분 → nightAmount=0 (적용 여부 무관)', () {
      final r = _calcHourly(
        hourlyWage: 10000,
        workMinutes: 480,
        nightMinutes: 0,
        nightAllowanceApplied: true,
      );
      expect(r['nightAmount'], 0);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // SCENARIO-WT-06: taxDeductionType별 공제 라벨
  // ════════════════════════════════════════════════════════════════
  group('SCENARIO-WT-06. taxDeductionType 공제 라벨', () {
    test('WT-06-01: \'none\' → \'세금 없음\'', () {
      expect(
        InsuranceRateModel.typeLabel(InsuranceRateModel.typeNone),
        '세금 없음',
      );
    });

    test('WT-06-02: \'freelancer_3_3\' → \'3.3% 원천징수\'', () {
      expect(
        InsuranceRateModel.typeLabel(InsuranceRateModel.typeFreelancer33),
        '3.3% 원천징수',
      );
    });

    test('WT-06-03: \'daily_worker\' → \'일용직 소득세\'', () {
      expect(
        InsuranceRateModel.typeLabel(InsuranceRateModel.typeDailyWorker),
        '일용직 소득세',
      );
    });

    test('WT-06-04: \'daily_auto_8\' → \'일용직 8일 소급\'', () {
      expect(
        InsuranceRateModel.typeLabel(InsuranceRateModel.typeDailyAuto8),
        '일용직 8일 소급',
      );
    });

    test('WT-06-05: \'four_insurance_fixed\' → \'4대보험 고정\'', () {
      expect(
        InsuranceRateModel.typeLabel(InsuranceRateModel.typeFourInsuranceFixed),
        '4대보험 고정',
      );
    });

    test('WT-06-06: 알 수 없는 타입 → \'세금 없음\' 폴백', () {
      expect(InsuranceRateModel.typeLabel('unknown_type'), '세금 없음');
    });

    test('WT-06-07: WageDetailModel.taxDeductionLabel getter 연동', () {
      final w = _wage(taxDeductionType: InsuranceRateModel.typeDailyWorker);
      expect(w.taxDeductionLabel, '일용직 소득세');
    });

    test('WT-06-08: allTypes에 5가지 타입 모두 포함', () {
      expect(InsuranceRateModel.allTypes.length, 5);
      expect(InsuranceRateModel.allTypes, contains(InsuranceRateModel.typeNone));
      expect(InsuranceRateModel.allTypes, contains(InsuranceRateModel.typeFreelancer33));
      expect(InsuranceRateModel.allTypes, contains(InsuranceRateModel.typeDailyWorker));
      expect(InsuranceRateModel.allTypes, contains(InsuranceRateModel.typeDailyAuto8));
      expect(InsuranceRateModel.allTypes, contains(InsuranceRateModel.typeFourInsuranceFixed));
    });
  });

  // ════════════════════════════════════════════════════════════════
  // SCENARIO-WT-07: payScheduleType 유효성
  // ════════════════════════════════════════════════════════════════
  group('SCENARIO-WT-07. payScheduleType 유효성', () {
    test('WT-07-01: \'same_day\' → 유효', () {
      expect(_validatePaySchedule('same_day', null), isTrue);
    });

    test('WT-07-02: \'next_day\' → 유효', () {
      expect(_validatePaySchedule('next_day', null), isTrue);
    });

    test('WT-07-03: \'weekly\', day=0 → 무효 (1 미만)', () {
      expect(_validatePaySchedule('weekly', 0), isFalse);
    });

    test('WT-07-04: \'weekly\', day=1 (월요일) → 유효', () {
      expect(_validatePaySchedule('weekly', 1), isTrue);
    });

    test('WT-07-05: \'weekly\', day=7 (일요일) → 유효', () {
      expect(_validatePaySchedule('weekly', 7), isTrue);
    });

    test('WT-07-06: \'weekly\', day=8 → 무효 (7 초과)', () {
      expect(_validatePaySchedule('weekly', 8), isFalse);
    });

    test('WT-07-07: \'weekly\', day=null → 무효', () {
      expect(_validatePaySchedule('weekly', null), isFalse);
    });

    test('WT-07-08: \'monthly\', day=0 → 무효', () {
      expect(_validatePaySchedule('monthly', 0), isFalse);
    });

    test('WT-07-09: \'monthly\', day=15 → 유효', () {
      expect(_validatePaySchedule('monthly', 15), isTrue);
    });

    test('WT-07-10: \'monthly\', day=31 (말일) → 유효', () {
      expect(_validatePaySchedule('monthly', 31), isTrue);
    });

    test('WT-07-11: \'monthly\', day=32 → 무효', () {
      expect(_validatePaySchedule('monthly', 32), isFalse);
    });

    test('WT-07-12: 알 수 없는 type → 무효', () {
      expect(_validatePaySchedule('bi_weekly', 14), isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // SCENARIO-WT-08: WageDetailModel effectiveNetWage getter
  // ════════════════════════════════════════════════════════════════
  group('SCENARIO-WT-08. effectiveNetWage getter', () {
    test('WT-08-01: 미확정(calculatedAt=null) → totalAmount - deductions', () {
      final w = _wage(
        totalAmount: 100000,
        netWage: 0,
        employmentInsuranceDeduction: 900,
      );
      expect(w.isCalculated, isFalse);
      expect(w.effectiveNetWage, 99100); // 100000 - 900
    });

    test('WT-08-02: isCalculated=true, netWage>0 → netWage 반환', () {
      final w = _wage(
        totalAmount: 100000,
        netWage: 97000,
        calculatedAt: DateTime(2026, 7, 1),
      );
      expect(w.isCalculated, isTrue);
      expect(w.effectiveNetWage, 97000);
    });

    test('WT-08-03: isCalculated=true, netWage=0, totalAmount>0 → 폴백 계산 (레거시)', () {
      // netWage 필드 미설정 레거시 레코드 — 폴백으로 계산식 사용
      final w = _wage(
        totalAmount: 80000,
        netWage: 0,
        employmentInsuranceDeduction: 800,
        calculatedAt: DateTime(2026, 7, 1),
      );
      expect(w.effectiveNetWage, 79200); // 80000 - 800
    });

    test('WT-08-04: isCalculated=true, netWage=0, totalAmount=0 → 0 반환', () {
      final w = _wage(
        totalAmount: 0,
        netWage: 0,
        calculatedAt: DateTime(2026, 7, 1),
      );
      expect(w.effectiveNetWage, 0);
    });

    test('WT-08-05: retroactiveDeduction이 totalAmount 초과 → 0 clamp', () {
      final w = _wage(
        totalAmount: 10000,
        netWage: 0,
        retroactiveDeduction: 50000, // 8일차 소급 공제 초과
      );
      expect(w.effectiveNetWage, 0); // 음수 방지
    });

    test('WT-08-06: totalInsuranceDeduction 5개 항목 합산', () {
      final w = _wage(
        employmentInsuranceDeduction: 900,
        nationalPensionDeduction: 4750,
        healthInsuranceDeduction: 3595,
        ltcInsuranceDeduction: 472,
        incomeTaxDeduction: 1000,
        retroactiveDeduction: 0,
      );
      expect(w.totalInsuranceDeduction, 10717); // 900+4750+3595+472+1000
    });

    test('WT-08-07: isCalculated getter = calculatedAt != null', () {
      expect(_wage(calculatedAt: null).isCalculated, isFalse);
      expect(_wage(calculatedAt: DateTime(2026, 7, 1)).isCalculated, isTrue);
    });

    test('WT-08-08: isConfirmed getter = confirmedAt != null', () {
      expect(_wage(confirmedAt: null).isConfirmed, isFalse);
      expect(_wage(confirmedAt: DateTime(2026, 7, 1)).isConfirmed, isTrue);
    });

    test('WT-08-09: workHours getter = workMinutes / 60.0', () {
      expect(_wage(workMinutes: 480).workHours, 8.0);
      expect(_wage(workMinutes: 540).workHours, 9.0);
    });

    test('WT-08-10: 공제 없으면 effectiveNetWage = totalAmount', () {
      final w = _wage(totalAmount: 82560);
      expect(w.effectiveNetWage, 82560);
    });

    test('WT-08-11: isConfirmed=true이면 isCalculated도 true', () {
      final now = DateTime(2026, 7, 1);
      final w = _wage(calculatedAt: now, confirmedAt: now);
      expect(w.isConfirmed, isTrue);
      expect(w.isCalculated, isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // SCENARIO-WT-09: TrustSettings 유효성 검증
  // ════════════════════════════════════════════════════════════════
  group('SCENARIO-WT-09. TrustSettings 유효성 검증', () {
    test('WT-09-01: 모든 값 정상 → 통과', () {
      expect(
        _validateTrustSettings(
          startScore: 60, maxScore: 100,
          resetScore: 50, cooldownDays: 60,
          noshowReduction: 1, lateReduction: 1,
        ),
        isTrue,
      );
    });

    test('WT-09-02: startScore=-1 → 차단 (0 미만)', () {
      expect(
        _validateTrustSettings(
          startScore: -1, maxScore: 100,
          resetScore: 50, cooldownDays: 60,
          noshowReduction: 1, lateReduction: 1,
        ),
        isFalse,
      );
    });

    test('WT-09-03: startScore=101 → 차단 (100 초과)', () {
      expect(
        _validateTrustSettings(
          startScore: 101, maxScore: 101,
          resetScore: 50, cooldownDays: 60,
          noshowReduction: 1, lateReduction: 1,
        ),
        isFalse,
      );
    });

    test('WT-09-04: maxScore < startScore → 차단', () {
      expect(
        _validateTrustSettings(
          startScore: 80, maxScore: 70,
          resetScore: 50, cooldownDays: 60,
          noshowReduction: 1, lateReduction: 1,
        ),
        isFalse,
      );
    });

    test('WT-09-05: maxScore=101 → 차단 (100 초과)', () {
      expect(
        _validateTrustSettings(
          startScore: 60, maxScore: 101,
          resetScore: 50, cooldownDays: 60,
          noshowReduction: 1, lateReduction: 1,
        ),
        isFalse,
      );
    });

    test('WT-09-06: cooldownDays=0 → 차단 (1 미만)', () {
      expect(
        _validateTrustSettings(
          startScore: 60, maxScore: 100,
          resetScore: 50, cooldownDays: 0,
          noshowReduction: 1, lateReduction: 1,
        ),
        isFalse,
      );
    });

    test('WT-09-07: noshowReduction=-1 → 차단 (음수 불가)', () {
      expect(
        _validateTrustSettings(
          startScore: 60, maxScore: 100,
          resetScore: 50, cooldownDays: 60,
          noshowReduction: -1, lateReduction: 1,
        ),
        isFalse,
      );
    });

    test('WT-09-08: lateReduction=-1 → 차단 (음수 불가)', () {
      expect(
        _validateTrustSettings(
          startScore: 60, maxScore: 100,
          resetScore: 50, cooldownDays: 60,
          noshowReduction: 1, lateReduction: -1,
        ),
        isFalse,
      );
    });

    test('WT-09-09: resetScore=-1 → 차단', () {
      expect(
        _validateTrustSettings(
          startScore: 60, maxScore: 100,
          resetScore: -1, cooldownDays: 60,
          noshowReduction: 1, lateReduction: 1,
        ),
        isFalse,
      );
    });

    test('WT-09-10: startScore=maxScore 경계값 → 통과 (동일해도 유효)', () {
      expect(
        _validateTrustSettings(
          startScore: 80, maxScore: 80,
          resetScore: 50, cooldownDays: 60,
          noshowReduction: 0, lateReduction: 0,
        ),
        isTrue,
      );
    });

    test('WT-09-11: 모든 최소값 → 통과 (startScore=0, cooldownDays=1)', () {
      expect(
        _validateTrustSettings(
          startScore: 0, maxScore: 0,
          resetScore: 0, cooldownDays: 1,
          noshowReduction: 0, lateReduction: 0,
        ),
        isTrue,
      );
    });
  });

  // ════════════════════════════════════════════════════════════════
  // SCENARIO-WT-10: 신뢰도 등급 분류
  // ════════════════════════════════════════════════════════════════
  group('SCENARIO-WT-10. 신뢰도 등급 분류', () {
    test('WT-10-01: score=100 → 최우수', () => expect(_trustGrade(100), '최우수'));
    test('WT-10-02: score=90 → 최우수 (경계값 하한)', () => expect(_trustGrade(90), '최우수'));
    test('WT-10-03: score=89 → 우수', () => expect(_trustGrade(89), '우수'));
    test('WT-10-04: score=70 → 우수 (경계값 하한)', () => expect(_trustGrade(70), '우수'));
    test('WT-10-05: score=69 → 보통', () => expect(_trustGrade(69), '보통'));
    test('WT-10-06: score=50 → 보통 (경계값 하한)', () => expect(_trustGrade(50), '보통'));
    test('WT-10-07: score=49 → 주의', () => expect(_trustGrade(49), '주의'));
    test('WT-10-08: score=30 → 주의 (경계값 하한)', () => expect(_trustGrade(30), '주의'));
    test('WT-10-09: score=29 → 경고', () => expect(_trustGrade(29), '경고'));
    test('WT-10-10: score=0 → 경고 (clamp 하한)', () => expect(_trustGrade(0), '경고'));
  });

  // ════════════════════════════════════════════════════════════════
  // SCENARIO-WT-11: 기본값 복원 (TrustSettingsModel.defaults())
  // ════════════════════════════════════════════════════════════════
  group('SCENARIO-WT-11. 기본값 복원', () {
    final defaults = TrustSettingsModel.defaults();

    test('WT-11-01: startScore=60 복원', () {
      expect(defaults.startScore, 60);
    });

    test('WT-11-02: maxScore=100 복원', () {
      expect(defaults.maxScore, 100);
    });

    test('WT-11-03: restartProgram.resetScore=50 복원', () {
      expect(defaults.restartProgram.resetScore, 50);
    });

    test('WT-11-04: restartProgram.cooldownDays=60 복원', () {
      expect(defaults.restartProgram.cooldownDays, 60);
    });

    test('WT-11-05: increaseRules 비어있지 않음', () {
      expect(defaults.increaseRules, isNotEmpty);
    });

    test('WT-11-06: decreaseRules 비어있지 않음', () {
      expect(defaults.decreaseRules, isNotEmpty);
    });

    test('WT-11-07: work_complete 규칙 존재 → +1점', () {
      final r = defaults.increaseRules.firstWhere((r) => r.type == 'work_complete');
      expect(r.points, 1);
    });

    test('WT-11-08: good_review 규칙 존재 → +2점', () {
      final r = defaults.increaseRules.firstWhere((r) => r.type == 'good_review');
      expect(r.points, 2);
    });

    test('WT-11-09: rehire_yes 규칙 존재 → +1점', () {
      final r = defaults.increaseRules.firstWhere((r) => r.type == 'rehire_yes');
      expect(r.points, 1);
    });

    test('WT-11-10: noshow_1 규칙 존재 → -5점', () {
      final r = defaults.decreaseRules.firstWhere((r) => r.type == 'noshow_1');
      expect(r.points, -5);
    });

    test('WT-11-11: noshow_2 규칙 존재 → -8점 (누진)', () {
      final r = defaults.decreaseRules.firstWhere((r) => r.type == 'noshow_2');
      expect(r.points, -8);
    });

    test('WT-11-12: noshow_3plus 규칙 존재 → -10점 (누진)', () {
      final r = defaults.decreaseRules.firstWhere((r) => r.type == 'noshow_3plus');
      expect(r.points, -10);
    });

    test('WT-11-13: bad_review 규칙 존재 → -2점', () {
      final r = defaults.decreaseRules.firstWhere((r) => r.type == 'bad_review');
      expect(r.points, -2);
    });

    test('WT-11-14: fromMap(toMap()) 직렬화 왕복 — startScore/maxScore 일치', () {
      final map = defaults.toMap();
      final restored = TrustSettingsModel.fromMap(map);
      expect(restored.startScore, defaults.startScore);
      expect(restored.maxScore, defaults.maxScore);
    });

    test('WT-11-15: fromMap(toMap()) — rules 개수 일치', () {
      final map = defaults.toMap();
      final restored = TrustSettingsModel.fromMap(map);
      expect(restored.increaseRules.length, defaults.increaseRules.length);
      expect(restored.decreaseRules.length, defaults.decreaseRules.length);
    });

    test('WT-11-16: fromMap(toMap()) — restartProgram 복원', () {
      final map = defaults.toMap();
      final restored = TrustSettingsModel.fromMap(map);
      expect(restored.restartProgram.cooldownDays, 60);
      expect(restored.restartProgram.resetScore, 50);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // SCENARIO-WT-12: TrustScoreHelper 기본 동작 + getNoshowPenalty
  // ════════════════════════════════════════════════════════════════
  group('SCENARIO-WT-12. TrustScoreHelper 기본 동작', () {
    test('WT-12-01: 이력 없음 → 기준점 60', () {
      expect(_score(), 60);
    });

    test('WT-12-02: 점수 범위 0~100 — 극단 상한 clamp', () {
      final s = _score(days: 300, avg: 5.0, rc: 100, rr: 1.0);
      expect(s, inInclusiveRange(0, 100));
    });

    test('WT-12-03: 점수 범위 0~100 — 극단 하한 clamp', () {
      final s = _score(ns: 100, late: 50);
      expect(s, inInclusiveRange(0, 100));
    });

    test('WT-12-04: getNoshowPenalty(1) == -5', () {
      expect(TrustSettingsModel.defaults().getNoshowPenalty(1), -5);
    });

    test('WT-12-05: getNoshowPenalty(2) == -8', () {
      expect(TrustSettingsModel.defaults().getNoshowPenalty(2), -8);
    });

    test('WT-12-06: getNoshowPenalty(3) == -10', () {
      expect(TrustSettingsModel.defaults().getNoshowPenalty(3), -10);
    });

    test('WT-12-07: getNoshowPenalty(99) == -10 (3회+ 동일)', () {
      expect(TrustSettingsModel.defaults().getNoshowPenalty(99), -10);
    });

    test('WT-12-08: 신뢰도 점수 + 등급 통합 — 우수 근무자 → 최우수', () {
      // 60일 근무, 평점4.8, 리뷰8, 재고용1.0
      final s = _score(days: 60, avg: 4.8, rc: 8, rr: 1.0);
      expect(_trustGrade(s), '최우수');
    });

    test('WT-12-09: 신뢰도 점수 + 등급 통합 — 노쇼 다수 근무자 → 경고', () {
      final s = _score(ns: 5, late: 10);
      expect(_trustGrade(s), anyOf('경고', '주의'));
    });

    test('WT-12-10: TrustSettingsModel 유효성 + defaults() 통합 확인', () {
      // defaults()에서 얻은 값으로 유효성 검증
      final d = TrustSettingsModel.defaults();
      expect(
        _validateTrustSettings(
          startScore: d.startScore,
          maxScore: d.maxScore,
          resetScore: d.restartProgram.resetScore,
          cooldownDays: d.restartProgram.cooldownDays,
          noshowReduction: d.restartProgram.noshowReduction,
          lateReduction: d.restartProgram.lateReduction,
        ),
        isTrue,
        reason: 'defaults() 값이 유효성 검증을 통과해야 함',
      );
    });
  });
}
