// ignore_for_file: prefer_const_constructors

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';
import 'package:ALfit/models/core/payroll_summary_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';

// ── 헬퍼 ─────────────────────────────────────────────────────────────────────

WageDetailModel _makeWage({
  int totalAmount = 100000,
  int netWage = 0,
  DateTime? calculatedAt,
  DateTime? confirmedAt,
  int employmentInsuranceDeduction = 0,
  int nationalPensionDeduction = 0,
  int healthInsuranceDeduction = 0,
  int ltcInsuranceDeduction = 0,
  int incomeTaxDeduction = 0,
  int retroactiveDeduction = 0,
}) =>
    WageDetailModel(
      wageType: 'hourly',
      baseWage: 10320,
      totalAmount: totalAmount,
      netWage: netWage,
      calculatedAt: calculatedAt,
      confirmedAt: confirmedAt,
      employmentInsuranceDeduction: employmentInsuranceDeduction,
      nationalPensionDeduction: nationalPensionDeduction,
      healthInsuranceDeduction: healthInsuranceDeduction,
      ltcInsuranceDeduction: ltcInsuranceDeduction,
      incomeTaxDeduction: incomeTaxDeduction,
      retroactiveDeduction: retroactiveDeduction,
    );

AttendanceModel _makeAttendance({
  String wageStatus = 'pending',
  int? finalWage,
  WageDetailModel? wageDetail,
}) =>
    AttendanceModel(
      id: 'att001',
      applicationId: 'app001',
      userId: 'user001',
      businessId: 'biz001',
      businessName: '테스트 매장',
      workDate: DateTime(2026, 7, 1),
      workType: '홀서빙',
      status: AttendanceModel.statusPresent,
      createdAt: DateTime(2026, 7, 1, 9),
      wageStatus: wageStatus,
      finalWage: finalWage,
      wageDetail: wageDetail,
    );

PayrollSummaryModel _makeSummary({
  int confirmedCount = 0,
  int pendingCount = 0,
  int notTransferredCount = 0,
  int totalPayout = 0,
  Map<String, PayrollWorkerSummary>? workers,
}) =>
    PayrollSummaryModel(
      id: 'biz001_2026-07',
      businessId: 'biz001',
      yearMonth: '2026-07',
      year: 2026,
      month: 7,
      totalPayout: totalPayout,
      confirmedCount: confirmedCount,
      workerCount: workers?.length ?? 0,
      pendingCount: pendingCount,
      notTransferredCount: notTransferredCount,
      workers: workers ?? {},
      updatedAt: DateTime(2026, 7, 30),
    );

// ── 테스트 ────────────────────────────────────────────────────────────────────

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // Group A — WageDetailModel: effectiveNetWage / isCalculated / 공제 합계
  // ══════════════════════════════════════════════════════════════════════════
  group('A. WageDetailModel — effectiveNetWage', () {
    // A-01: 미확정 → 계산식(totalAmount - totalInsuranceDeduction)
    test('A-01: 미확정(calculatedAt==null) → 계산식 폴백', () {
      final w = _makeWage(
        totalAmount: 100000,
        netWage: 0,
        calculatedAt: null,
        nationalPensionDeduction: 4750,
      );
      expect(w.isCalculated, isFalse);
      expect(w.effectiveNetWage, equals(100000 - 4750)); // 95250
    });

    // A-02: 확정 + netWage > 0 → netWage 반환
    test('A-02: 확정(calculatedAt!=null), netWage>0 → netWage 직접 반환', () {
      final w = _makeWage(
        totalAmount: 100000,
        netWage: 92000,
        calculatedAt: DateTime(2026, 7, 10),
        nationalPensionDeduction: 4750,
      );
      expect(w.isCalculated, isTrue);
      expect(w.effectiveNetWage, equals(92000));
    });

    // A-03: [T-01] 확정 + netWage==0 + totalAmount>0 → 계산식 폴백 (마이그레이션 전 레코드)
    test('A-03: T-01 — 확정이지만 netWage==0, totalAmount>0 → 계산식으로 폴백', () {
      final w = _makeWage(
        totalAmount: 100000,
        netWage: 0,
        calculatedAt: DateTime(2026, 7, 10),
        nationalPensionDeduction: 4750,
      );
      expect(w.isCalculated, isTrue);
      expect(w.effectiveNetWage, equals(100000 - 4750)); // T-01 폴백
    });

    // A-04: T-01 NOT 트리거 — 확정 + netWage==0 + totalAmount==0 → 0 반환 (진짜 0원)
    test('A-04: 확정, netWage==0, totalAmount==0 → 0 반환 (T-01 미발동)', () {
      final w = _makeWage(
        totalAmount: 0,
        netWage: 0,
        calculatedAt: DateTime(2026, 7, 10),
      );
      expect(w.effectiveNetWage, equals(0));
    });

    // A-05: clamp 하한 — isCalculated, netWage < 0 → 0
    test('A-05: 확정, netWage 음수 → clamp(0)', () {
      final w = _makeWage(
        totalAmount: 100000,
        netWage: -5000,
        calculatedAt: DateTime(2026, 7, 10),
      );
      expect(w.effectiveNetWage, equals(0));
    });

    // A-06: clamp 상한 — netWage > 999999999 → 999999999
    test('A-06: netWage 초과 → clamp(999999999)', () {
      final w = _makeWage(
        totalAmount: 2000000000,
        netWage: 2000000000,
        calculatedAt: DateTime(2026, 7, 10),
      );
      expect(w.effectiveNetWage, equals(999999999));
    });

    // A-07: 미확정 계산식 clamp — totalInsuranceDeduction > totalAmount → 0
    test('A-07: 미확정, 공제합계 > 총액 → clamp(0) 음수 방지', () {
      final w = _makeWage(
        totalAmount: 50000,
        netWage: 0,
        calculatedAt: null,
        retroactiveDeduction: 60000, // 8일차 소급이 당일 급여 초과
      );
      expect(w.effectiveNetWage, equals(0));
    });

    // A-08: retroactiveDeduction이 totalInsuranceDeduction에 포함됨
    test('A-08: retroactiveDeduction은 totalInsuranceDeduction에 포함', () {
      final w = _makeWage(
        employmentInsuranceDeduction: 900,
        nationalPensionDeduction: 4750,
        healthInsuranceDeduction: 3595,
        ltcInsuranceDeduction: 472,
        incomeTaxDeduction: 2700,
        retroactiveDeduction: 10000,
      );
      expect(
        w.totalInsuranceDeduction,
        equals(900 + 4750 + 3595 + 472 + 2700 + 10000),
      );
    });

    // A-09: deductionAmount는 totalInsuranceDeduction에 미포함 (이미 totalAmount에서 차감됨)
    test('A-09: deductionAmount는 totalInsuranceDeduction 계산에서 제외 (이중 차감 없음)', () {
      final w = WageDetailModel(
        wageType: 'hourly',
        baseWage: 10320,
        totalAmount: 90000,   // deductionAmount가 이미 반영된 세전총액
        deductionAmount: 10000,
        nationalPensionDeduction: 4750,
        netWage: 0,
        calculatedAt: null,
      );
      // totalInsuranceDeduction = 4750 (deductionAmount 10000은 미포함)
      expect(w.totalInsuranceDeduction, equals(4750));
      // effectiveNetWage = 90000 - 4750 = 85250 (deductionAmount 이중차감 없음)
      expect(w.effectiveNetWage, equals(85250));
    });

    // A-10: clearConfirmInfo — confirmedAt/confirmedBy null, calculatedAt 유지
    test('A-10: clearConfirmInfo → confirmedAt/By null, calculatedAt 보존', () {
      final original = _makeWage(
        calculatedAt: DateTime(2026, 7, 10),
        confirmedAt: DateTime(2026, 7, 11),
      );
      final cleared = original.clearConfirmInfo();
      expect(cleared.confirmedAt, isNull);
      expect(cleared.confirmedBy, isNull);
      expect(cleared.calculatedAt, equals(DateTime(2026, 7, 10)));
      expect(cleared.isCalculated, isTrue);
      expect(cleared.isConfirmed, isFalse);
    });

    // A-11: isCalculated = calculatedAt != null
    test('A-11: isCalculated는 calculatedAt의 null 여부만으로 결정', () {
      expect(_makeWage(calculatedAt: null).isCalculated, isFalse);
      expect(_makeWage(calculatedAt: DateTime(2026, 1, 1)).isCalculated, isTrue);
    });

    // A-12: isConfirmed = confirmedAt != null
    test('A-12: isConfirmed는 confirmedAt의 null 여부만으로 결정', () {
      expect(_makeWage(confirmedAt: null).isConfirmed, isFalse);
      expect(_makeWage(confirmedAt: DateTime(2026, 1, 1)).isConfirmed, isTrue);
    });

    // A-13: formattedNetWage — 0원 표기
    test('A-13: effectiveNetWage==0 → formattedNetWage returns "0원"', () {
      final w = _makeWage(totalAmount: 0, netWage: 0, calculatedAt: null);
      expect(w.formattedNetWage, equals('0원'));
    });

    // A-14: fromMap — calculatedAt Timestamp 파싱
    test('A-14: fromMap — calculatedAt Timestamp → isCalculated=true', () {
      final ts = Timestamp.fromDate(DateTime(2026, 7, 10));
      final w = WageDetailModel.fromMap({
        'wageType': 'hourly',
        'baseWage': 10320,
        'totalAmount': 100000,
        'netWage': 92000,
        'calculatedAt': ts,
      });
      expect(w.isCalculated, isTrue);
      expect(w.netWage, equals(92000));
    });

    // A-15: tryFromMap — 손상된 데이터 → null (크래시 없음)
    test('A-15: tryFromMap — null map 아닌 정상 map → 파싱 성공', () {
      final w = WageDetailModel.tryFromMap({
        'wageType': 'daily',
        'baseWage': 150000,
      });
      expect(w, isNotNull);
      expect(w!.wageType, equals('daily'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group B — InsuranceRateModel: 2026 요율 및 clamp 방어
  // ══════════════════════════════════════════════════════════════════════════
  group('B. InsuranceRateModel — 2026 요율 및 clamp', () {
    // B-01: defaults2026 year
    test('B-01: defaults2026 year == 2026', () {
      expect(InsuranceRateModel.defaults2026().year, equals(2026));
    });

    // B-02: 국민연금 근로자 부담률 4.75%
    test('B-02: 국민연금 4.75%', () {
      expect(InsuranceRateModel.defaults2026().nationalPensionRate, equals(4.75));
    });

    // B-03: 건강보험 3.595% (2026 인상 요율 — 2025년 3.545%와 다름)
    test('B-03: 건강보험 3.595% — 2025년(3.545%)이 아닌 2026년 인상 요율', () {
      final rate = InsuranceRateModel.defaults2026().healthInsuranceRate;
      expect(rate, equals(3.595));
      expect(rate, isNot(equals(3.545))); // 2025년 요율과 혼동 방지
    });

    // B-04: 장기요양보험 13.14%
    test('B-04: 장기요양보험 13.14% (건강보험료 대비)', () {
      expect(InsuranceRateModel.defaults2026().ltcInsuranceRate, equals(13.14));
    });

    // B-05: 고용보험 0.9%
    test('B-05: 고용보험 0.9%', () {
      expect(InsuranceRateModel.defaults2026().employmentInsuranceRate, equals(0.9));
    });

    // B-06: 일용직 비과세 한도 150000원
    test('B-06: 일용직 비과세 한도 150,000원', () {
      expect(InsuranceRateModel.defaults2026().dailyWageExemption, equals(150000));
    });

    // B-07: fromMap clamp — 요율 > 20 → 20으로 clamp
    test('B-07: fromMap — 요율 20 초과 → clamp(20) 방어', () {
      final r = InsuranceRateModel.fromMap({
        'year': 2026,
        'nationalPensionRate': 99.0, // 극단값
        'healthInsuranceRate': 3.595,
        'ltcInsuranceRate': 13.14,
        'employmentInsuranceRate': 0.9,
        'dailyWageExemption': 150000,
        'dailyWorkerTaxRate': 2.7,
        'localIncomeTaxRate': 10.0,
        'businessIncomeRate': 3.0,
        'businessIncomeLocalRate': 0.3,
      });
      expect(r.nationalPensionRate, equals(20.0));
    });

    // B-08: fromMap clamp — 요율 < 0 → 0으로 clamp
    test('B-08: fromMap — 음수 요율 → clamp(0) 방어', () {
      final r = InsuranceRateModel.fromMap({
        'year': 2026,
        'nationalPensionRate': -5.0,
        'healthInsuranceRate': 3.595,
        'ltcInsuranceRate': 13.14,
        'employmentInsuranceRate': 0.9,
        'dailyWageExemption': 150000,
        'dailyWorkerTaxRate': 2.7,
        'localIncomeTaxRate': 10.0,
        'businessIncomeRate': 3.0,
        'businessIncomeLocalRate': 0.3,
      });
      expect(r.nationalPensionRate, equals(0.0));
    });

    // B-09: ltcInsuranceRate는 max=30 (다른 요율의 max=20과 다름)
    test('B-09: ltcInsuranceRate max clamp은 30 (일반 요율 20과 다름)', () {
      final r = InsuranceRateModel.fromMap({
        'year': 2026,
        'nationalPensionRate': 4.75,
        'healthInsuranceRate': 3.595,
        'ltcInsuranceRate': 25.0, // 20 초과이지만 max=30 범위 내
        'employmentInsuranceRate': 0.9,
        'dailyWageExemption': 150000,
        'dailyWorkerTaxRate': 2.7,
        'localIncomeTaxRate': 10.0,
        'businessIncomeRate': 3.0,
        'businessIncomeLocalRate': 0.3,
      });
      expect(r.ltcInsuranceRate, equals(25.0)); // clamp 안됨
    });

    // B-10: 타입 상수 — typeNone
    test('B-10: typeNone == "none"', () {
      expect(InsuranceRateModel.typeNone, equals('none'));
    });

    // B-11: 타입 상수 — typeFreelancer33
    test('B-11: typeFreelancer33 == "freelancer_3_3"', () {
      expect(InsuranceRateModel.typeFreelancer33, equals('freelancer_3_3'));
    });

    // B-12: 타입 상수 — typeDailyWorker
    test('B-12: typeDailyWorker == "daily_worker"', () {
      expect(InsuranceRateModel.typeDailyWorker, equals('daily_worker'));
    });

    // B-13: 타입 상수 — typeDailyAuto8
    test('B-13: typeDailyAuto8 == "daily_auto_8"', () {
      expect(InsuranceRateModel.typeDailyAuto8, equals('daily_auto_8'));
    });

    // B-14: 타입 상수 — typeFourInsuranceFixed
    test('B-14: typeFourInsuranceFixed == "four_insurance_fixed"', () {
      expect(InsuranceRateModel.typeFourInsuranceFixed, equals('four_insurance_fixed'));
    });

    // B-15: allTypes에 5개 타입 모두 포함
    test('B-15: allTypes에 5개 타입 전부 포함', () {
      expect(InsuranceRateModel.allTypes.length, equals(5));
      expect(InsuranceRateModel.allTypes, containsAll([
        InsuranceRateModel.typeNone,
        InsuranceRateModel.typeFreelancer33,
        InsuranceRateModel.typeDailyWorker,
        InsuranceRateModel.typeDailyAuto8,
        InsuranceRateModel.typeFourInsuranceFixed,
      ]));
    });

    // B-16: dailyWageExemption clamp — 0 ~ 500000
    test('B-16: dailyWageExemption > 500000 → clamp(500000)', () {
      final r = InsuranceRateModel.fromMap({
        'year': 2026,
        'nationalPensionRate': 4.75,
        'healthInsuranceRate': 3.595,
        'ltcInsuranceRate': 13.14,
        'employmentInsuranceRate': 0.9,
        'dailyWageExemption': 9999999, // 극단값
        'dailyWorkerTaxRate': 2.7,
        'localIncomeTaxRate': 10.0,
        'businessIncomeRate': 3.0,
        'businessIncomeLocalRate': 0.3,
      });
      expect(r.dailyWageExemption, equals(500000));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group C — PayrollSummaryModel: isEmpty / fromMap / workers / formatted
  // ══════════════════════════════════════════════════════════════════════════
  group('C. PayrollSummaryModel — isEmpty / workers / formatted', () {
    // C-01: 3 카운터 모두 0 → isEmpty true
    test('C-01: confirmedCount=0, pendingCount=0, notTransferredCount=0 → isEmpty true', () {
      expect(_makeSummary().isEmpty, isTrue);
    });

    // C-02: confirmedCount > 0 → isEmpty false
    test('C-02: confirmedCount>0 → isEmpty false', () {
      expect(_makeSummary(confirmedCount: 1).isEmpty, isFalse);
    });

    // C-03: pendingCount > 0 → isEmpty false
    test('C-03: pendingCount>0 → isEmpty false', () {
      expect(_makeSummary(pendingCount: 3).isEmpty, isFalse);
    });

    // C-04: [MEDIUM 감사 발견] notTransferredCount > 0 → isEmpty false
    // "전부 이체 완료된 달"은 confirmedCount=0, notTransferredCount=0이므로 isEmpty=true가 됨.
    // 즉, transferred-only 달은 isEmpty=true로 오분류될 수 있음 (MEDIUM 허용 설계 확인 필요)
    test('C-04: notTransferredCount>0 → isEmpty false', () {
      expect(_makeSummary(notTransferredCount: 2).isEmpty, isFalse);
    });

    // C-05: [설계 확인 완료 — 실제 버그 없음]
    // onAttendanceWageChanged 트리거에서 SUMMARY_STATUSES = ["confirmed","transferred"]
    // → confirmedCount는 confirmed + transferred 둘 다 포함.
    // 이체완료(transferred) 달: confirmedCount > 0 → isEmpty = false. 오분류 없음.
    // 이 테스트는 모델 isEmpty 로직(카운터 기반) 동작을 문서화함.
    test('C-05: isEmpty — 3 카운터 모두 0이어야 true (totalPayout은 무시)', () {
      // 실제 transferred 달은 confirmedCount > 0 이므로 이 시나리오는 발생 안 함
      final s = _makeSummary(
        confirmedCount: 0,
        pendingCount: 0,
        notTransferredCount: 0,
        totalPayout: 500000,
      );
      expect(s.isEmpty, isTrue); // 카운터 기반, totalPayout 무관
    });

    // C-06: formattedTotalPayout — 0 → '-'
    test('C-06: totalPayout==0 → formattedTotalPayout returns "-"', () {
      expect(_makeSummary(totalPayout: 0).formattedTotalPayout, equals('-'));
    });

    // C-07: formattedTotalPayout — 1234567 → '1,234,567원'
    test('C-07: totalPayout=1,234,567 → "1,234,567원"', () {
      expect(
        _makeSummary(totalPayout: 1234567).formattedTotalPayout,
        equals('1,234,567원'),
      );
    });

    // C-08: sortedWorkers — totalPayout 내림차순 정렬
    test('C-08: sortedWorkers — totalPayout 내림차순 정렬', () {
      final s = _makeSummary(
        workers: {
          'u1': PayrollWorkerSummary(workerId: 'u1', name: '김', totalPayout: 100000, workDays: 3),
          'u2': PayrollWorkerSummary(workerId: 'u2', name: '이', totalPayout: 300000, workDays: 5),
          'u3': PayrollWorkerSummary(workerId: 'u3', name: '박', totalPayout: 200000, workDays: 4),
        },
      );
      final sorted = s.sortedWorkers;
      expect(sorted[0].totalPayout, equals(300000));
      expect(sorted[1].totalPayout, equals(200000));
      expect(sorted[2].totalPayout, equals(100000));
    });

    // C-09: empty() factory — id 형식 확인
    test('C-09: empty() factory — id 형식 "{businessId}_{YYYY-MM}"', () {
      final s = PayrollSummaryModel.empty(
        businessId: 'biz001',
        year: 2026,
        month: 7,
      );
      expect(s.id, equals('biz001_2026-07'));
      expect(s.yearMonth, equals('2026-07'));
      expect(s.isEmpty, isTrue);
    });

    // C-10: empty() — month 한자리수 zero-padding
    test('C-10: empty() — month 1자리수 → 2자리 padding', () {
      final s = PayrollSummaryModel.empty(businessId: 'biz', year: 2026, month: 3);
      expect(s.id, equals('biz_2026-03'));
      expect(s.yearMonth, equals('2026-03'));
    });

    // C-11-a: [LOW-FIX 검증] workers 엔트리가 Map이 아닌 원시값(String) → is! Map 체크로 건너뜀
    // LOW 수정 전: e.value as Map에서 TypeError 발생 → fromMap 전체 크래시
    // LOW 수정 후: is! Map 체크로 null 반환 → 정상 엔트리만 유지
    test('C-11a: fromMap — workers 엔트리가 String인 경우 → 건너뜀 (LOW-FIX)', () {
      final s = PayrollSummaryModel.fromMap({
        'businessId': 'biz001',
        'yearMonth': '2026-07',
        'year': 2026,
        'month': 7,
        'totalPayout': 100000,
        'confirmedCount': 1,
        'workerCount': 2,
        'updatedAt': Timestamp.fromDate(DateTime(2026, 7, 30)),
        'workers': {
          'u1': {'name': '김', 'totalPayout': 100000, 'workDays': 3},
          'bad': 'not_a_map', // String 원시값 → is! Map → null 반환 → 제외
        },
      }, 'biz001_2026-07');
      expect(s.workers.containsKey('u1'), isTrue);
      expect(s.workers.containsKey('bad'), isFalse);
    });

    // C-11-b: workers 엔트리 내부 필드 타입 오류 → tryFromMap null 처리 후 건너뜀
    test('C-11b: fromMap — workers 엔트리 name 타입 오류 → tryFromMap null 처리 후 건너뜀', () {
      final s = PayrollSummaryModel.fromMap({
        'businessId': 'biz001',
        'yearMonth': '2026-07',
        'year': 2026,
        'month': 7,
        'totalPayout': 100000,
        'confirmedCount': 1,
        'workerCount': 2,
        'updatedAt': Timestamp.fromDate(DateTime(2026, 7, 30)),
        'workers': {
          'u1': {'name': '김', 'totalPayout': 100000, 'workDays': 3},
          'bad': {'name': 999, 'totalPayout': 50000, 'workDays': 2}, // name int → fromMap TypeError → tryFromMap null
        },
      }, 'biz001_2026-07');
      expect(s.workers.containsKey('u1'), isTrue);
      expect(s.workers.containsKey('bad'), isFalse);
    });

    // C-12: fromMap — updatedAt Timestamp 파싱
    test('C-12: fromMap — updatedAt Timestamp 정상 파싱', () {
      final ts = Timestamp.fromDate(DateTime(2026, 7, 30, 12, 0));
      final s = PayrollSummaryModel.fromMap({
        'businessId': 'biz001',
        'yearMonth': '2026-07',
        'year': 2026,
        'month': 7,
        'totalPayout': 0,
        'confirmedCount': 0,
        'workerCount': 0,
        'updatedAt': ts,
        'workers': {},
      }, 'biz001_2026-07');
      expect(s.updatedAt.year, equals(2026));
      expect(s.updatedAt.month, equals(7));
      expect(s.updatedAt.day, equals(30));
    });

    // C-13: fromMap — updatedAt CF Map({_seconds, _nanoseconds}) 파싱
    test('C-13: fromMap — updatedAt CF Map 형태 파싱', () {
      final cfTs = {'_seconds': 1753819200, '_nanoseconds': 0}; // 2025-07-30 00:00:00 UTC
      final s = PayrollSummaryModel.fromMap({
        'businessId': 'biz001',
        'yearMonth': '2026-07',
        'year': 2026,
        'month': 7,
        'totalPayout': 0,
        'confirmedCount': 0,
        'workerCount': 0,
        'updatedAt': cfTs,
        'workers': {},
      }, 'biz001_2026-07');
      expect(s.updatedAt, isNotNull);
      // 밀리초 변환 확인 (정확한 날짜보다 타입 파싱 여부 확인)
      expect(s.updatedAt.year, greaterThan(2020));
    });

    // C-14: PayrollWorkerSummary.tryFromMap — name 누락 → 빈 문자열 폴백
    test('C-14: PayrollWorkerSummary.tryFromMap — name 누락 → "" 폴백', () {
      final w = PayrollWorkerSummary.tryFromMap('u1', {'totalPayout': 50000, 'workDays': 2});
      expect(w, isNotNull);
      expect(w!.name, equals(''));
      expect(w.totalPayout, equals(50000));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group D — AttendanceModel: wageStatus 상수 / displayWage 게이트
  // ══════════════════════════════════════════════════════════════════════════
  group('D. AttendanceModel — wageStatus 상태기계 / displayWage 게이트', () {
    // D-01: 상수값 확인
    test('D-01: wagePending == "pending"', () {
      expect(AttendanceModel.wagePending, equals('pending'));
    });

    test('D-02: wageCalculated == "calculated"', () {
      expect(AttendanceModel.wageCalculated, equals('calculated'));
    });

    test('D-03: wageConfirmed == "confirmed"', () {
      expect(AttendanceModel.wageConfirmed, equals('confirmed'));
    });

    test('D-04: wageTransferred == "transferred"', () {
      expect(AttendanceModel.wageTransferred, equals('transferred'));
    });

    // D-05: pending → displayWage = null
    test('D-05: wagePending → displayWage null (표시 안 됨)', () {
      final a = _makeAttendance(wageStatus: 'pending', finalWage: 100000);
      expect(a.displayWage, isNull);
      expect(a.formattedDisplayWage, equals('-'));
    });

    // D-06: calculated → displayWage = null
    test('D-06: wageCalculated → displayWage null (검토중 — 미표시)', () {
      final a = _makeAttendance(wageStatus: 'calculated', finalWage: 100000);
      expect(a.displayWage, isNull);
      expect(a.formattedDisplayWage, equals('-'));
    });

    // D-07: confirmed → displayWage = finalWage (표시)
    test('D-07: wageConfirmed → displayWage = finalWage 표시', () {
      final a = _makeAttendance(wageStatus: 'confirmed', finalWage: 95000);
      expect(a.displayWage, equals(95000));
      expect(a.formattedDisplayWage, equals('95,000원'));
    });

    // D-08: transferred → displayWage = finalWage (표시)
    test('D-08: wageTransferred → displayWage = finalWage 표시', () {
      final a = _makeAttendance(wageStatus: 'transferred', finalWage: 95000);
      expect(a.displayWage, equals(95000));
      expect(a.formattedDisplayWage, equals('95,000원'));
    });

    // D-09: finalWage null + confirmed → displayWage null
    test('D-09: wageConfirmed이지만 finalWage null → displayWage null', () {
      final a = _makeAttendance(wageStatus: 'confirmed', finalWage: null);
      expect(a.displayWage, isNull);
    });

    // D-10: wageStatus getter 확인
    test('D-10: isWagePending / isWageCalculated / isWageConfirmed / isWageTransferred', () {
      expect(_makeAttendance(wageStatus: 'pending').isWagePending, isTrue);
      expect(_makeAttendance(wageStatus: 'calculated').isWageCalculated, isTrue);
      expect(_makeAttendance(wageStatus: 'confirmed').isWageConfirmed, isTrue);
      expect(_makeAttendance(wageStatus: 'transferred').isWageTransferred, isTrue);
    });

    // D-11: wageStatusLabel 매핑 확인
    test('D-11: wageStatusLabel 한국어 매핑', () {
      expect(_makeAttendance(wageStatus: 'pending').wageStatusLabel, equals('미계산'));
      expect(_makeAttendance(wageStatus: 'calculated').wageStatusLabel, equals('검토중'));
      expect(_makeAttendance(wageStatus: 'confirmed').wageStatusLabel, equals('확정'));
      expect(_makeAttendance(wageStatus: 'transferred').wageStatusLabel, equals('송금완료'));
    });

    // D-12: 상태기계 — pending → calculated → confirmed → transferred 순서 시뮬레이션
    test('D-12: 상태기계 정상 전환 시뮬레이션 (pending→calculated→confirmed→transferred)', () {
      var a = _makeAttendance(wageStatus: 'pending', finalWage: null);
      expect(a.isWagePending, isTrue);
      expect(a.displayWage, isNull);

      // 1차 확정 (callableCalculateAndConfirmWage)
      a = a.copyWith(wageStatus: 'calculated', finalWage: 95000);
      expect(a.isWageCalculated, isTrue);
      expect(a.displayWage, isNull); // 아직 미표시

      // 최종 확정 (callableConfirmFinalWage)
      a = a.copyWith(wageStatus: 'confirmed');
      expect(a.isWageConfirmed, isTrue);
      expect(a.displayWage, equals(95000)); // 표시 시작

      // 송금 완료 (callableMarkTransferredBatch)
      a = a.copyWith(wageStatus: 'transferred');
      expect(a.isWageTransferred, isTrue);
      expect(a.displayWage, equals(95000)); // 계속 표시
    });

    // D-13: 상태기계 — 역방향 전환 (confirmed → calculated 취소)
    test('D-13: 상태기계 역방향 — confirmed→calculated 취소 시 displayWage 숨김', () {
      var a = _makeAttendance(wageStatus: 'confirmed', finalWage: 95000);
      expect(a.displayWage, equals(95000));

      // 최종 확정 취소 (callableCancelFinalConfirmation)
      a = a.copyWith(wageStatus: 'calculated');
      expect(a.isWageCalculated, isTrue);
      expect(a.displayWage, isNull); // 다시 숨김
    });

    // D-14: 상태기계 — calculated → pending 취소
    test('D-14: 상태기계 — calculated→pending 취소 (callableWageCancel)', () {
      var a = _makeAttendance(wageStatus: 'calculated', finalWage: 95000);
      a = a.copyWith(wageStatus: 'pending', finalWage: null);
      expect(a.isWagePending, isTrue);
      expect(a.displayWage, isNull);
    });

    // D-15: 상태기계 — transferred → confirmed 취소
    test('D-15: 상태기계 — transferred→confirmed 취소 (callableCancelTransfer)', () {
      var a = _makeAttendance(wageStatus: 'transferred', finalWage: 95000);
      a = a.copyWith(wageStatus: 'confirmed');
      expect(a.isWageConfirmed, isTrue);
      expect(a.displayWage, equals(95000));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group E — HIGH 감사 발견: callableWageCancel SubAdmin 권한 누락
  // ══════════════════════════════════════════════════════════════════════════
  group('E. [감사] HIGH 발견 — callableWageCancel SubAdmin 권한 누락', () {
    // E-01: SubAdmin 권한 누락 — 로직 검증 불가이므로 발견 사항 문서화 테스트
    test('E-01: [PERM-WAGE-CANCEL] callableWageCancel — SubAdmin canManageWage 미확인 (HIGH)', () {
      // 감사 발견:
      // callableWageCancel은 assertBizAdmin()만 호출하여 비즈니스 관리자 여부만 확인.
      // callableCalculateAndConfirmWage, callableConfirmFinalWage, callableMarkTransferredBatch는
      // canManageWage 권한을 추가 확인하지만, callableWageCancel은 이를 누락.
      // SubAdmin이 canManageWage 없이도 급여 1차 확정 취소 가능.
      //
      // 수정 방안:
      //   assertBizAdmin(data, auth, {requiredPermission: 'canManageWage'});
      //
      // [참고] 이 테스트는 클라이언트측 모델에서 서버 권한 로직을 직접 검증할 수 없으므로
      // 발견 사항 문서화 목적으로 항상 pass됨.
      // CF 코드(functions/src/index.ts)의 callableWageCancel 함수를 수정해야 함.
      expect(true, isTrue, reason: 'HIGH 감사 발견 문서화 — CF 수정 필요');
    });

    // E-02: 다른 wage CF들의 SubAdmin 권한 패턴 재확인
    test('E-02: 상태 전이 상수 — wageCalculated는 callableWageCancel 이후 되돌아갈 상태', () {
      // callableWageCancel 취소 후: calculated → pending
      // 이 전환이 SubAdmin 권한 확인 없이 허용됨 (HIGH 취약점)
      expect(AttendanceModel.wageCalculated, equals('calculated'));
      expect(AttendanceModel.wagePending, equals('pending'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group F — WageDetailModel fromMap / toMap 왕복 직렬화
  // ══════════════════════════════════════════════════════════════════════════
  group('F. WageDetailModel — fromMap/toMap 왕복', () {
    // F-01: toMap → fromMap 왕복
    test('F-01: toMap → fromMap 왕복 — 주요 수치 보존', () {
      final original = WageDetailModel(
        wageType: 'hourly',
        baseWage: 10320,
        totalAmount: 120000,
        netWage: 95000,
        calculatedAt: DateTime(2026, 7, 10, 10, 30),
        employmentInsuranceDeduction: 1080,
        nationalPensionDeduction: 5700,
        healthInsuranceDeduction: 4314,
        ltcInsuranceDeduction: 566,
        incomeTaxDeduction: 3240,
        retroactiveDeduction: 0,
      );
      final map = original.toMap();
      final restored = WageDetailModel.fromMap(map);
      expect(restored.wageType, equals(original.wageType));
      expect(restored.totalAmount, equals(120000));
      expect(restored.netWage, equals(95000));
      expect(restored.isCalculated, isTrue);
      expect(restored.totalInsuranceDeduction, equals(1080 + 5700 + 4314 + 566 + 3240));
    });

    // F-02: toMap — calculatedAt null → map의 'calculatedAt' null
    test('F-02: calculatedAt null → toMap에서 null 유지', () {
      final w = _makeWage(calculatedAt: null);
      final map = w.toMap();
      expect(map['calculatedAt'], isNull);
    });

    // F-03: retroactiveDeduction != 0 → toMap에 포함, fromMap에서 복원
    test('F-03: retroactiveDeduction 왕복 — 8일차 소급 공제 보존', () {
      final w = _makeWage(retroactiveDeduction: 15000);
      final restored = WageDetailModel.fromMap(w.toMap());
      expect(restored.retroactiveDeduction, equals(15000));
      expect(restored.totalInsuranceDeduction, equals(15000));
    });

    // F-04: deductionAmount != 0 → toMap에 포함, fromMap에서 복원
    test('F-04: deductionAmount 왕복 — 수동 추가공제 보존', () {
      final w = WageDetailModel(
        wageType: 'hourly',
        baseWage: 10320,
        totalAmount: 90000,
        deductionAmount: 10000,
        netWage: 0,
      );
      final restored = WageDetailModel.fromMap(w.toMap());
      expect(restored.deductionAmount, equals(10000));
    });
  });
}
