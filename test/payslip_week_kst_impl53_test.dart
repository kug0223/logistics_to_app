import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/screens/payroll/payslip_period_helper.dart';

/// [impl_53 · AUD-4 H8] 주급 명세 주차 필터 · PDF 일자 — KST 달력으로(기기 시간대 무관).
///   workDate 는 KST 자정 instant 이다. isUtc DateTime 은 UTC 기기와 같은 성분을 주므로 UTC 기기 재현에 쓴다(AUD-4 재현과 같은 방식).
AttendanceModel _att(String id, DateTime workDate) => AttendanceModel(
    id: id, applicationId: 'app_$id', userId: 'u1', businessId: 'b1', businessName: 'QA',
    workDate: workDate, workType: '분류', status: AttendanceModel.statusPresent, createdAt: DateTime.utc(2026, 11, 1));

DateTime _kstMid(int y, int m, int d) => DateTime.utc(y, m, d).subtract(const Duration(hours: 9));

void main() {
  test('W1 KST 월요일 근무는 그 주에 들어가고 다음 주 월요일은 빠진다(UTC 성분 기기에서도)', () {
    final weeks = PayslipPeriodHelper.weeksOfMonth(2026, 11);
    final wk = weeks.firstWhere((w) => w.start.day == 2); // 2026-11-02(월) 주
    final mon = _att('mon', _kstMid(2026, 11, 2)); // UTC 11-01 15:00
    final sun = _att('sun', _kstMid(2026, 11, 8)); // 그 주 일요일
    final nextMon = _att('next', _kstMid(2026, 11, 9)); // UTC 11-08 15:00 — 기기 성분이면 일요일로 읽혀 들어온다
    final prevSun = _att('prev', _kstMid(2026, 11, 1));
    final got = PayslipPeriodHelper.filterByWeek([mon, sun, nextMon, prevSun], wk).map((r) => r.id).toList();
    expect(got, ['mon', 'sun']);
  });

  test('W2 소스 — 주차 필터·PDF 일자는 toKstDate', () {
    final h = File('lib/screens/payroll/payslip_period_helper.dart').readAsStringSync();
    final f = h.substring(h.indexOf('static List<AttendanceModel> filterByWeek('));
    expect(f.substring(0, f.indexOf('groupByWeek')).contains('FormatHelper.toKstDate(r.workDate)'), isTrue);
    final pdf = File('lib/screens/payroll/payslip_pdf_builder.dart').readAsStringSync();
    expect("FormatHelper.toKstDate(r.workDate).month}/\${FormatHelper.toKstDate(r.workDate).day}".allMatches(pdf).length, 2);
    expect(RegExp(r"'\$\{r\.workDate\.month\}/\$\{r\.workDate\.day\}'").hasMatch(pdf), isFalse);
  });
}
