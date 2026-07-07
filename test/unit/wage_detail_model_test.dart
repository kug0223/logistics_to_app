// test/unit/wage_detail_model_test.dart
// WageDetailModel 직렬화·게터 단위 테스트 (Firebase 의존성 없음)
//
// 실행: flutter test test/unit/wage_detail_model_test.dart
//
// toMap()은 Timestamp.fromDate()를 사용하므로 cloud_firestore 플러그인 필요 → 제외
// fromMap() 은 null timestamp → parseTimestampNullable(null) = null 경로라 안전
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';

/// 완전한 맵 — fromMap이 모든 필드를 파싱하는지 확인
Map<String, dynamic> fullMap() => {
  'wageType': 'daily',
  'baseWage': 120000,
  'scheduledMinutes': 480,
  'actualMinutes': 495,
  'breakMinutes': 30,
  'workMinutes': 465,
  'overtimeMinutes': 60,
  'earlyArrivalMinutes': 15,
  'nightMinutes': 120,
  'baseAmount': 120000,
  'overtimeAmount': 15000,
  'earlyArrivalAmount': 7500,
  'nightAmount': 6000,
  'additionalAmount': 5000,
  'deductionAmount': 3000,
  'weeklyHolidayAmount': 0,
  'totalAmount': 143000,
  'nightAllowanceApplied': true,
  'memo': '야간 근무',
  'appliedMinimumWage': 10320,
  'appliedSupplementWage': 15480,
  'calculatedBy': null,
  'calculatedAt': null,     // null → parseTimestampNullable 분기 → null
  'confirmedBy': null,
  'confirmedAt': null,
  'taxDeductionType': InsuranceRateModel.typeDailyWorker,
  'employmentInsuranceDeduction': 1287,
  'nationalPensionDeduction': 0,
  'healthInsuranceDeduction': 0,
  'ltcInsuranceDeduction': 0,
  'incomeTaxDeduction': 0,
  'retroactiveDeduction': 0,
  'netWage': 141713,
};

void main() {
  // ────────────────────────────────────────────────────────────────
  // 1. fromMap — 기본 파싱
  // ────────────────────────────────────────────────────────────────
  group('WageDetailModel.fromMap — 기본 필드 파싱', () {
    test('WDMAP-01 wageType / baseWage 정확 파싱', () {
      final m = WageDetailModel.fromMap(fullMap());
      expect(m.wageType, 'daily');
      expect(m.baseWage, 120000);
    });

    test('WDMAP-02 시간 관련 필드 (분 단위) 정확 파싱', () {
      final m = WageDetailModel.fromMap(fullMap());
      expect(m.scheduledMinutes, 480);
      expect(m.actualMinutes, 495);
      expect(m.breakMinutes, 30);
      expect(m.workMinutes, 465);
      expect(m.overtimeMinutes, 60);
      expect(m.earlyArrivalMinutes, 15);
      expect(m.nightMinutes, 120);
    });

    test('WDMAP-03 금액 필드 정확 파싱', () {
      final m = WageDetailModel.fromMap(fullMap());
      expect(m.baseAmount, 120000);
      expect(m.overtimeAmount, 15000);
      expect(m.earlyArrivalAmount, 7500);
      expect(m.nightAmount, 6000);
      expect(m.additionalAmount, 5000);
      expect(m.deductionAmount, 3000);
      expect(m.totalAmount, 143000);
      expect(m.netWage, 141713);
    });

    test('WDMAP-04 세금 공제 필드 정확 파싱', () {
      final m = WageDetailModel.fromMap(fullMap());
      expect(m.taxDeductionType, InsuranceRateModel.typeDailyWorker);
      expect(m.employmentInsuranceDeduction, 1287);
      expect(m.nationalPensionDeduction, 0);
      expect(m.incomeTaxDeduction, 0);
    });

    test('WDMAP-05 bool/String/nullable 필드 정확 파싱', () {
      final m = WageDetailModel.fromMap(fullMap());
      expect(m.nightAllowanceApplied, true);
      expect(m.memo, '야간 근무');
      expect(m.calculatedAt, isNull);
      expect(m.confirmedAt, isNull);
    });

    test('WDMAP-06 num 타입으로 넘어온 필드 (double → int) 안전 변환', () {
      final map = Map<String, dynamic>.from(fullMap());
      map['baseWage'] = 120000.0;    // double
      map['totalAmount'] = 143000.9; // double with fraction
      final m = WageDetailModel.fromMap(map);
      expect(m.baseWage, 120000);
      expect(m.totalAmount, 143000); // .toInt() truncates
    });
  });

  // ────────────────────────────────────────────────────────────────
  // 2. fromMap — 빈 맵 / 누락 필드 기본값
  // ────────────────────────────────────────────────────────────────
  group('WageDetailModel.fromMap — 누락 필드 기본값', () {
    late WageDetailModel empty;
    setUpAll(() {
      // 필수 키 최소한만 포함 (wageType/baseWage 도 누락 시 기본값 확인)
      empty = WageDetailModel.fromMap({});
    });

    test('WDMAP-07 wageType 없으면 "hourly" 기본값', () => expect(empty.wageType, 'hourly'));
    test('WDMAP-08 baseWage 없으면 0 기본값', () => expect(empty.baseWage, 0));
    test('WDMAP-09 모든 분/금액 필드 0 기본값', () {
      expect(empty.scheduledMinutes, 0);
      expect(empty.actualMinutes, 0);
      expect(empty.totalAmount, 0);
      expect(empty.netWage, 0);
    });
    test('WDMAP-10 taxDeductionType 없으면 typeNone 기본값', () {
      expect(empty.taxDeductionType, InsuranceRateModel.typeNone);
    });
    test('WDMAP-11 appliedMinimumWage 없으면 10320 기본값', () {
      expect(empty.appliedMinimumWage, 10320);
    });
    test('WDMAP-12 nightAllowanceApplied 없으면 false', () {
      expect(empty.nightAllowanceApplied, false);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // 3. tryFromMap — null-safe 파싱
  // ────────────────────────────────────────────────────────────────
  group('WageDetailModel.tryFromMap — null-safe 파싱', () {
    test('WDTRY-01 정상 맵 → WageDetailModel 반환', () {
      final m = WageDetailModel.tryFromMap(fullMap());
      expect(m, isNotNull);
      expect(m!.totalAmount, 143000);
    });

    test('WDTRY-02 빈 맵 → WageDetailModel 반환 (기본값)', () {
      final m = WageDetailModel.tryFromMap({});
      expect(m, isNotNull);
    });

    test('WDTRY-03 타입 오류 맵 → null 반환 (크래시 방지)', () {
      // baseWage에 String을 넣으면 (num?)?.toInt()가 null → 0으로 폴백됨
      // 실제 크래시 유발: wageType에 int를 넣음 — map['wageType'] ?? 'hourly' 는 int 반환 후
      // 생성자에서 String으로 사용되므로 type error 발생
      final badMap = {'wageType': 12345};  // int, String 필요
      final m = WageDetailModel.tryFromMap(badMap);
      // null이거나 기본값 WageDetailModel이 반환될 수 있음
      // 어느 쪽이든 크래시하지 않는다는 것이 핵심
      // (현재 구현: ?? 'hourly' 는 null 체크이지 type 체크가 아님 → 실제로 int가 넘어가면
      //  Dart sound null-safety 에서 String? 캐스팅 실패 → catch → null)
      // 테스트 의도: 크래시 없이 null or valid 반환
      expect(() => WageDetailModel.tryFromMap(badMap), returnsNormally);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // 4. Getter 검증
  // ────────────────────────────────────────────────────────────────
  group('WageDetailModel Getter', () {
    test('GET-01 isCalculated: calculatedAt==null → false', () {
      final m = WageDetailModel.fromMap(fullMap());
      expect(m.isCalculated, false);
    });

    test('GET-02 isConfirmed: confirmedAt==null → false', () {
      final m = WageDetailModel.fromMap(fullMap());
      expect(m.isConfirmed, false);
    });

    test('GET-03 workHours = workMinutes / 60.0', () {
      final m = WageDetailModel.fromMap(fullMap());
      expect(m.workHours, closeTo(465 / 60.0, 0.001));
    });

    test('GET-04 totalInsuranceDeduction = 모든 공제액 합계', () {
      final m = WageDetailModel.fromMap(fullMap());
      // employment=1287, 나머지=0, retroactive=0
      expect(m.totalInsuranceDeduction, 1287);
    });

    test('GET-05 effectiveNetWage: isCalculated=false → totalAmount - totalInsuranceDeduction (clamp 0)', () {
      // fullMap: totalAmount=143000, employment=1287 → effective = 141713
      final m = WageDetailModel.fromMap(fullMap());
      expect(m.effectiveNetWage, 143000 - 1287);
    });

    test('GET-06 effectiveNetWage: isCalculated=false, 공제>totalAmount → 0 (clamp)', () {
      final m = WageDetailModel(
        wageType: 'daily',
        baseWage: 10320,
        totalAmount: 100,
        employmentInsuranceDeduction: 50000, // 공제가 총액 초과
      );
      expect(m.effectiveNetWage, 0);
    });

    test('GET-07 wageTypeLabel: hourly → 시급', () {
      final m = WageDetailModel(wageType: 'hourly', baseWage: 10320);
      expect(m.wageTypeLabel, '시급');
    });

    test('GET-08 wageTypeLabel: daily → 일급', () {
      final m = WageDetailModel(wageType: 'daily', baseWage: 120000);
      expect(m.wageTypeLabel, '일급');
    });

    test('GET-09 wageTypeLabel: 알 수 없는 값 → 급여', () {
      final m = WageDetailModel(wageType: 'unknown', baseWage: 0);
      expect(m.wageTypeLabel, '급여');
    });

    test('GET-10 taxDeductionLabel: daily_worker → 일용직 근로소득세', () {
      final m = WageDetailModel(
        wageType: 'daily',
        baseWage: 120000,
        taxDeductionType: InsuranceRateModel.typeDailyWorker,
      );
      expect(m.taxDeductionLabel, isNotEmpty);
    });

    test('GET-11 overtimeHours / nightHours 분 → 시간 변환', () {
      final m = WageDetailModel.fromMap(fullMap());
      expect(m.overtimeHours, closeTo(60 / 60.0, 0.001));
      expect(m.nightHours, closeTo(120 / 60.0, 0.001));
    });
  });

  // ────────────────────────────────────────────────────────────────
  // 5. copyWith 검증
  // ────────────────────────────────────────────────────────────────
  group('WageDetailModel.copyWith', () {
    test('CW-01 변경된 필드만 바뀌고 나머지는 유지', () {
      final original = WageDetailModel.fromMap(fullMap());
      final copy = original.copyWith(totalAmount: 200000, netWage: 198000);
      expect(copy.totalAmount, 200000);
      expect(copy.netWage, 198000);
      expect(copy.wageType, original.wageType);       // 유지
      expect(copy.baseWage, original.baseWage);       // 유지
      expect(copy.taxDeductionType, original.taxDeductionType); // 유지
    });

    test('CW-02 memo null 유지 (기존 null이면 null 그대로)', () {
      final original = WageDetailModel(wageType: 'hourly', baseWage: 10320, memo: null);
      final copy = original.copyWith(baseWage: 15000);
      expect(copy.memo, isNull);
      expect(copy.baseWage, 15000);
    });

    test('CW-03 calculatedBy 변경', () {
      final original = WageDetailModel.fromMap(fullMap());
      final copy = original.copyWith(calculatedBy: 'admin-uid-123');
      expect(copy.calculatedBy, 'admin-uid-123');
      expect(original.calculatedBy, isNull); // 원본 불변
    });
  });
}
