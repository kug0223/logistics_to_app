// lib/screens/payroll/payslip_period_helper.dart
//
// 임금명세서 기간 계산 유틸리티
// - 월별 주차 분리 (1일 기준 7일 블록)
// - payScheduleType 기반 발행 유형 결정

import '../../models/core/attendance_model.dart';
import '../../models/core/wage_detail_model.dart';

// ─── 발행 유형 ───────────────────────────────────────────────────

enum PayslipIssueType {
  daily,    // 일별 (same_day / next_day)
  weekly,   // 주간 (weekly)
  monthly,  // 월간 (monthly)
}

extension PayslipIssueTypeX on PayslipIssueType {
  String get label {
    switch (this) {
      case PayslipIssueType.daily:   return '일별 임금명세서';
      case PayslipIssueType.weekly:  return '주간 임금명세서';
      case PayslipIssueType.monthly: return '월간 임금명세서';
    }
  }

  static PayslipIssueType fromPayScheduleType(String? type) {
    switch (type) {
      case 'same_day':
      case 'next_day':
        return PayslipIssueType.daily;
      case 'weekly':
        return PayslipIssueType.weekly;
      case 'monthly':
      default:
        return PayslipIssueType.monthly;
    }
  }
}

// ─── 주차 정보 ────────────────────────────────────────────────────

class WeekPeriod {
  final int weekNo;       // 1 ~ 5
  final DateTime start;   // 주 시작일
  final DateTime end;     // 주 종료일 (같은 달 내)
  final int year;
  final int month;

  const WeekPeriod({
    required this.weekNo,
    required this.start,
    required this.end,
    required this.year,
    required this.month,
  });

  String get label => '$year년 $month월 $weekNo주차 (${_fmt(start)}~${_fmt(end)})';
  String get shortLabel => '$month월 $weekNo주차';

  String _fmt(DateTime d) => '${d.month}/${d.day}';

  @override
  String toString() => label;
}

// ─── 기간 계산 헬퍼 ───────────────────────────────────────────────

class PayslipPeriodHelper {
  /// 특정 연월의 주차 목록 반환 — 월요일 기준 월~일(Mon~Sun)
  ///
  /// 이체현황(_calcWeekRanges)과 동일한 기준:
  ///   - 해당 월의 첫 번째 월요일부터 7일씩 끊음
  ///   - 주 종료일이 다음 달로 넘어가도 클립하지 않음 (항상 월~일 전체)
  ///   - 최소 4주차 보장 (UI 칩 표시 용)
  ///   - 월 초 이전 달 주차에 속하는 날(예: 7/1~7/5)은 포함 안 됨
  ///     → 이체현황과 동일하게 제외 처리
  static List<WeekPeriod> weeksOfMonth(int year, int month) {
    final lastDay = DateTime(year, month + 1, 0); // 해당 월 말일

    // 해당 월의 첫 번째 월요일 (weekday: Mon=1, Sun=7)
    final firstDay = DateTime(year, month, 1);
    final daysToMonday = (1 - firstDay.weekday + 7) % 7;
    DateTime weekStart = firstDay.add(Duration(days: daysToMonday));

    final weeks = <WeekPeriod>[];
    int weekNo = 1;
    while (!weekStart.isAfter(lastDay)) {
      final weekEnd = weekStart.add(const Duration(days: 6)); // 일요일
      weeks.add(WeekPeriod(
        weekNo: weekNo,
        start: weekStart,
        end: weekEnd, // 다음 달로 넘어갈 수 있음
        year: year,
        month: month,
      ));
      weekStart = weekStart.add(const Duration(days: 7));
      weekNo++;
    }

    // 최소 4주차 보장
    while (weeks.length < 4) {
      final next = weeks.last.start.add(const Duration(days: 7));
      weeks.add(WeekPeriod(
        weekNo: weeks.length + 1,
        start: next,
        end: next.add(const Duration(days: 6)),
        year: year,
        month: month,
      ));
    }

    return weeks;
  }

  /// AttendanceModel 리스트를 특정 주차로 필터링
  static List<AttendanceModel> filterByWeek(
    List<AttendanceModel> records,
    WeekPeriod week,
  ) {
    return records.where((r) {
      final d = DateTime(r.workDate.year, r.workDate.month, r.workDate.day);
      final s = DateTime(week.start.year, week.start.month, week.start.day);
      final e = DateTime(week.end.year, week.end.month, week.end.day);
      return !d.isBefore(s) && !d.isAfter(e);
    }).toList();
  }

  /// 특정 연월의 모든 레코드를 주차별로 그룹화
  static Map<WeekPeriod, List<AttendanceModel>> groupByWeek(
    List<AttendanceModel> records,
    int year,
    int month,
  ) {
    final weeks = weeksOfMonth(year, month);
    return {
      for (final w in weeks)
        w: filterByWeek(records, w),
    };
  }

  /// 주차 레이블 (e.g. "2026년 5월 3주차 (5/15~5/21)")
  static String weekLabel(int year, int month, int weekNo) {
    final weeks = weeksOfMonth(year, month);
    if (weekNo < 1 || weekNo > weeks.length) return '$year년 $month월 $weekNo주차';
    return weeks[weekNo - 1].label;
  }

  /// 월별 기간 레이블 (e.g. "2026년 5월")
  static String monthLabel(int year, int month) => '$year년 $month월';
}

// ─── 집계 임금명세서 데이터 ────────────────────────────────────────

/// 여러 AttendanceModel을 집계한 임금명세서용 데이터
class AggregatedPayslipData {
  // 사업장
  final String businessName;
  final String businessNumber;
  final String businessAddress;
  final String ownerName;

  // 근무자
  final String workerName;
  final String workerBirthDate;

  // 기간
  final PayslipIssueType issueType;
  final int year;
  final int month;
  final int? weekNo;      // 주간일 때만 사용
  final DateTime periodStart;
  final DateTime periodEnd;

  // 집계 데이터 (wageDetail 합산)
  final int totalWorkDays;
  final int totalWorkMinutes;
  final int totalScheduledMinutes;
  final int totalBreakMinutes;
  final int totalOvertimeMinutes;
  final int totalNightMinutes;

  // 지급 항목 합산
  final int totalBaseAmount;
  final int totalOvertimeAmount;
  final int totalNightAmount;
  final int totalWeeklyHolidayAmount;
  final int totalAdditionalAmount;
  final int totalDeductionAmount;
  final int totalGrossAmount;       // 세전 총액

  // 공제 항목 합산
  final int totalNationalPension;
  final int totalHealthInsurance;
  final int totalLtcInsurance;
  final int totalEmploymentInsurance;
  final int totalIncomeTax;
  final int totalRetroactiveDeduction;
  final int totalInsuranceDeduction; // 총 공제액

  // 실수령액
  final int totalNetWage;

  // 공제 방식 라벨 (첫 번째 레코드 기준)
  final String taxDeductionTypeLabel;

  // 일별 상세 (PDF 2페이지용)
  final List<DailyRecord> dailyRecords;

  // 지급일
  final DateTime? paymentDate;

  const AggregatedPayslipData({
    required this.businessName,
    this.businessNumber = '',
    this.businessAddress = '',
    this.ownerName = '',
    required this.workerName,
    this.workerBirthDate = '',
    required this.issueType,
    required this.year,
    required this.month,
    this.weekNo,
    required this.periodStart,
    required this.periodEnd,
    required this.totalWorkDays,
    required this.totalWorkMinutes,
    required this.totalScheduledMinutes,
    required this.totalBreakMinutes,
    required this.totalOvertimeMinutes,
    required this.totalNightMinutes,
    required this.totalBaseAmount,
    required this.totalOvertimeAmount,
    required this.totalNightAmount,
    required this.totalWeeklyHolidayAmount,
    required this.totalAdditionalAmount,
    required this.totalDeductionAmount,
    required this.totalGrossAmount,
    required this.totalNationalPension,
    required this.totalHealthInsurance,
    required this.totalLtcInsurance,
    required this.totalEmploymentInsurance,
    required this.totalIncomeTax,
    required this.totalRetroactiveDeduction,
    required this.totalInsuranceDeduction,
    required this.totalNetWage,
    required this.taxDeductionTypeLabel,
    required this.dailyRecords,
    this.paymentDate,
  });

  /// AttendanceModel 리스트 → AggregatedPayslipData
  factory AggregatedPayslipData.fromRecords({
    required List<AttendanceModel> records,
    required String workerName,
    required PayslipIssueType issueType,
    required int year,
    required int month,
    int? weekNo,
    required DateTime periodStart,
    required DateTime periodEnd,
    String businessNumber = '',
    String businessAddress = '',
    String ownerName = '',
    String workerBirthDate = '',
    DateTime? paymentDate,
  }) {
    if (records.isEmpty) throw ArgumentError('records는 비어있을 수 없습니다');

    // wageDetail이 있는 레코드만 집계
    final valid = records.where((r) => r.wageDetail != null).toList();

    int sumInt(int Function(AttendanceModel) f) =>
        valid.fold(0, (acc, r) => acc + f(r));

    WageDetailModel wd(AttendanceModel r) => r.wageDetail!;

    return AggregatedPayslipData(
      businessName: records.first.businessName,
      businessNumber: businessNumber,
      businessAddress: businessAddress,
      ownerName: ownerName,
      workerName: workerName,
      workerBirthDate: workerBirthDate,
      issueType: issueType,
      year: year,
      month: month,
      weekNo: weekNo,
      periodStart: periodStart,
      periodEnd: periodEnd,
      totalWorkDays: valid.length,
      totalWorkMinutes:        sumInt((r) => wd(r).workMinutes),
      totalScheduledMinutes:   sumInt((r) => wd(r).scheduledMinutes),
      totalBreakMinutes:       sumInt((r) => wd(r).breakMinutes),
      totalOvertimeMinutes:    sumInt((r) => wd(r).overtimeMinutes),
      totalNightMinutes:       sumInt((r) => wd(r).nightMinutes),
      totalBaseAmount:         sumInt((r) => wd(r).baseAmount),
      totalOvertimeAmount:     sumInt((r) => wd(r).overtimeAmount),
      totalNightAmount:        sumInt((r) => wd(r).nightAmount),
      totalWeeklyHolidayAmount:sumInt((r) => wd(r).weeklyHolidayAmount),
      totalAdditionalAmount:   sumInt((r) => wd(r).additionalAmount),
      totalDeductionAmount:    sumInt((r) => wd(r).deductionAmount),
      totalGrossAmount:        sumInt((r) => wd(r).totalAmount),
      totalNationalPension:    sumInt((r) => wd(r).nationalPensionDeduction),
      totalHealthInsurance:    sumInt((r) => wd(r).healthInsuranceDeduction),
      totalLtcInsurance:       sumInt((r) => wd(r).ltcInsuranceDeduction),
      totalEmploymentInsurance:sumInt((r) => wd(r).employmentInsuranceDeduction),
      totalIncomeTax:          sumInt((r) => wd(r).incomeTaxDeduction),
      totalRetroactiveDeduction:sumInt((r) => wd(r).retroactiveDeduction),
      totalInsuranceDeduction: sumInt((r) => wd(r).totalInsuranceDeduction),
      totalNetWage:            sumInt((r) => wd(r).effectiveNetWage),
      // [Q-03 fix] 기간 내 공제 유형이 혼재할 때 first 레코드 라벨만 사용하던 문제 수정.
      // 유의미한(non-none) 라벨 집합을 구해 단일이면 그 라벨, 복수이면 '·' 구분 결합.
      taxDeductionTypeLabel: () {
        final meaningful = valid
            .map((r) => r.wageDetail!.taxDeductionLabel)
            .where((l) => l != '세금 없음')
            .toSet();
        if (meaningful.isEmpty) return '세금 없음';
        return meaningful.join('·');
      }(),
      // wageDetail 있는 레코드만 일별 상세에 포함 (빈 행 방지)
      dailyRecords: valid.map((r) => DailyRecord.fromAttendance(r)).toList()
        ..sort((a, b) => a.workDate.compareTo(b.workDate)),
      paymentDate: paymentDate,
    );
  }

  /// 기간 제목 (PDF 헤더용)
  String get periodTitle {
    switch (issueType) {
      case PayslipIssueType.weekly:
        final w = weekNo ?? 1;
        final s = '${periodStart.month}/${periodStart.day}';
        final e = '${periodEnd.month}/${periodEnd.day}';
        return '$year년 $month월 $w주차 임금명세서 ($s~$e)';
      case PayslipIssueType.monthly:
        return '$year년 $month월 임금명세서';
      case PayslipIssueType.daily:
        return '$year년 $month월 ${periodStart.day}일 임금명세서';
    }
  }

  bool get hasDeductions => totalInsuranceDeduction > 0;

  /// 메모가 있는 일별 레코드 목록 (특이사항 섹션용)
  List<DailyRecord> get memoRecords =>
      dailyRecords.where((r) => r.memo != null && r.memo!.isNotEmpty).toList();

  bool get hasMemos => memoRecords.isNotEmpty;
}

/// 일별 상세 행 (PDF 2페이지 테이블용)
class DailyRecord {
  final DateTime workDate;
  final String? checkIn;
  final String? checkOut;
  final int workMinutes;
  final int overtimeMinutes;
  final int nightMinutes;
  /// ✅ 의도된 netWage 필드명:
  ///   WageDetailModel.netWage와 이름이 같지만 별개 클래스의 필드다.
  ///   fromAttendance()에서 wageDetail.effectiveNetWage로 채우므로
  ///   미확정 레코드도 totalAmount - totalInsuranceDeduction으로 올바르게 계산된다.
  ///   이 필드를 직접 참조해도 effectiveNetWage 규칙 위반이 아니다.
  final int netWage;
  final String status;
  final String? memo;

  const DailyRecord({
    required this.workDate,
    this.checkIn,
    this.checkOut,
    required this.workMinutes,
    required this.overtimeMinutes,
    required this.nightMinutes,
    required this.netWage,
    required this.status,
    this.memo,
  });

  factory DailyRecord.fromAttendance(AttendanceModel a) {
    final wd = a.wageDetail;
    final net = wd?.effectiveNetWage ?? 0;
    return DailyRecord(
      workDate: a.workDate,
      checkIn: a.checkIn?.split(':').take(2).join(':'),
      checkOut: a.checkOut?.split(':').take(2).join(':'),
      workMinutes: wd?.workMinutes ?? 0,
      overtimeMinutes: wd?.overtimeMinutes ?? 0,
      nightMinutes: wd?.nightMinutes ?? 0,
      netWage: net,
      status: a.status,
      memo: wd?.memo,
    );
  }
}
