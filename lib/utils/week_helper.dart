import '../models/core/attendance_model.dart';
import 'format_helper.dart';

/// 주 단위 계산 유틸리티 (월요일 시작 ~ 일요일 종료)
class WeekHelper {
  /// 해당 날짜가 속한 주의 월요일 (0시 기준)
  static DateTime weekStart(DateTime date) {
    final d = FormatHelper.toKstDate(date);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  /// 해당 날짜가 속한 주의 일요일 (0시 기준)
  static DateTime weekEnd(DateTime date) =>
      weekStart(date).add(const Duration(days: 6));

  /// [R7-P1-2 DEVICE.1G] `주N회` 배지의 **유일한** 산출식.
  ///
  ///   같은 사람·같은 날짜인데 화면마다 다른 수가 나왔다. DEV 실측:
  ///
  ///     9/22~9/28 창 → 1        (공고탭 인력 현황이 `주1회`)
  ///     9/28~10/4 창 → 0        (홈 일자별이 `주0회`)
  ///     9/21~9/27 창 → 2
  ///
  ///   두 화면이 주간 창을 각자 계산했고, 한쪽은 기준일이 대상 날짜가
  ///   아니라 **오늘**이었다. 그리고 둘 다 **문서 수**를 셌다 — 같은 사람의
  ///   9/20 에 출근 문서가 4건 있어서 하루가 `주4회` 가 될 수 있었다.
  ///   코드 주석은 처음부터 "근무한 날 기준"이라고 적고 있었다.
  ///
  ///   그래서 세는 규칙을 한 곳에 둔다: **실제 출근한 KST 달력일의 수.**
  ///     · checkIn 이 있어야 한다(예정이 아니라 실적이다).
  ///     · 결근·노쇼는 근무한 날이 아니다.
  ///     · 같은 날 문서가 여러 건이어도 하루다.
  ///
  ///   [records] 는 한 사람의 주간 출근 기록이다.
  static int workedDayCount(Iterable<AttendanceModel> records) {
    final days = <String>{};
    for (final a in records) {
      if (a.checkIn == null) continue;
      if (a.status == AttendanceModel.statusAbsent) continue;
      if (a.status == AttendanceModel.statusNoShow) continue;
      days.add(FormatHelper.toKstDateKey(a.workDate));
    }
    return days.length;
  }

  /// uid → 주간 근무일 수. 두 화면이 같은 map 을 만든다.
  static Map<String, int> workedDayCounts(
          Map<String, List<AttendanceModel>> byUid) =>
      byUid.map((uid, list) => MapEntry(uid, workedDayCount(list)));
}

/// 주휴수당 자격 판정 결과
class WeeklyHolidayEligibility {
  final bool isEligible;
  final int workedDays;
  final int scheduledDaysPerWeek;
  final int totalWorkMinutes;
  final int weeklyHolidayAmount;
  final DateTime weekStart;
  final DateTime weekEnd;

  const WeeklyHolidayEligibility({
    required this.isEligible,
    required this.workedDays,
    required this.scheduledDaysPerWeek,
    required this.totalWorkMinutes,
    required this.weeklyHolidayAmount,
    required this.weekStart,
    required this.weekEnd,
  });

  bool get meetsHours => totalWorkMinutes >= 15 * 60;
  bool get meetsDays => workedDays >= scheduledDaysPerWeek;

  double get totalWorkHours => totalWorkMinutes / 60.0;
}
