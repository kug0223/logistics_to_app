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
  /// 특정 연월의 주차 목록 반환 (7일 블록, 월 경계 내)
  ///
  /// 방식 A: 1일부터 7일씩 끊음
  ///   1주차: 1~7, 2주차: 8~14, 3주차: 15~21, 4주차: 22~28, 5주차: 29~말일
  static List<WeekPeriod> weeksOfMonth(int year, int month) {
    final weeks = <WeekPeriod>[];
    final lastDay = DateTime(year, month + 1, 0).day;

    for (int weekNo = 1; weekNo <= 5; weekNo++) {
      final startDay = (weekNo - 1) * 7 + 1;
      if (startDay > lastDay) break;
      final endDay = (startDay + 6).clamp(startDay, lastDay);
      weeks.add(WeekPeriod(
        weekNo: weekNo,
        start: DateTime(year, month, startDay),
        end: DateTime(year, month, endDay),
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
    assert(records.isNotEmpty, 'records는 비어있을 수 없습니다');

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
      taxDeductionTypeLabel: valid.isNotEmpty
          ? (valid.first.wageDetail!.taxDeductionLabel)
          : '세금 없음',
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
      checkIn: a.checkIn,
      checkOut: a.checkOut,
      workMinutes: wd?.workMinutes ?? 0,
      overtimeMinutes: wd?.overtimeMinutes ?? 0,
      nightMinutes: wd?.nightMinutes ?? 0,
      netWage: net,
      status: a.status,
      memo: wd?.memo,
    );
  }
}
