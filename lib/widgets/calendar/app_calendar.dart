import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';

/// 앱 공통 캘린더 베이스 위젯
///
/// 공통 스타일(locale, 테마색, 헤더, 요일, 과거날짜 회색처리)을 고정 담당.
/// 데이터(eventLoader)와 마커 모양(markerBuilder)만 호출부에서 주입.
///
/// 사용 예:
/// ```dart
/// AppCalendar(
///   focusedDay: _focusedDay,
///   selectedDay: _selectedDay,
///   onDaySelected: (sel, foc) => setState(() { ... }),
///   onPageChanged: (foc) => setState(() => _focusedDay = foc),
///   eventLoader: (day) => myData[day] ?? [],
///   markerBuilder: (ctx, date, events) => ...,  // null이면 마커 없음
/// )
/// ```
class AppCalendar extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final Function(DateTime selectedDay, DateTime focusedDay) onDaySelected;
  final Function(DateTime focusedDay) onPageChanged;
  final List<Object?> Function(DateTime day) eventLoader;
  final Widget? Function(BuildContext, DateTime, List<Object?>)? markerBuilder;
  final bool Function(DateTime day)? enabledDayPredicate;
  final double rowHeight;
  /// 헤더(월 선택 영역) 상하 내부 패딩. 기본 8. 공간을 줄이려면 4 등 소값 전달.
  final double headerVerticalPadding;
  /// [DU193] 달력이 받는 제스처. 기본 all(기존 동작 그대로). 세로 스크롤 부모 안에서 세로 drag 를 부모에 넘기려면 horizontalSwipe.
  final AvailableGestures availableGestures;
  /// [DU194] 날짜 칸 바깥 여백. null 이면 패키지 기본(기존 표현 그대로). 큰 글자에서 두 자리 날짜가 칸 안에서 줄바뀜되지 않게 호출부가 좁힐 수 있다.
  final EdgeInsets? cellMargin;
  /// selectedDayPredicate 재정의.
  ///
  /// null이면 기본값(`DateUtils.isSameDay(selectedDay, day)`) 사용.
  /// 에디트 모드에서 복수 날짜를 선택 표시할 때 사용:
  ///   `selectedDayPredicateOverride: (d) => editingDates.contains(dateKey(d))`
  final bool Function(DateTime)? selectedDayPredicateOverride;

  static final DateTime _firstDay = DateTime.utc(2024, 1, 1);
  static final DateTime _lastDay = DateTime.utc(2050, 12, 31);

  const AppCalendar({
    super.key,
    required this.focusedDay,
    this.selectedDay,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.eventLoader,
    this.markerBuilder,
    this.enabledDayPredicate,
    this.selectedDayPredicateOverride,
    this.rowHeight = 40,
    this.headerVerticalPadding = 8,
    this.availableGestures = AvailableGestures.all,
    this.cellMargin,
  });

  /// [SCALE-BALANCE.34] 달력 칸 높이 — 기본 높이 + **글자가 커진 만큼의 줄 높이**.
  ///   고정 높이(40·28)에서 사용자 글자 2.0 이면 날짜 숫자 줄끼리 겹치고 아래가 잘렸다(근로자 일정 기기).
  ///   글자를 줄이지 않고 칸을 늘린다. 배율 1.0 이면 기본 높이 그대로. TableCalendar 를 직접 쓰는 곳도 이 식을 쓴다.
  static double scaledHeight(BuildContext context, double base, {double fontSize = 15}) {
    final grow = MediaQuery.textScalerOf(context).scale(fontSize) - fontSize;
    return grow <= 0 ? base : base + grow * 1.3;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // [E1-KSTDAY] 달력의 '오늘'은 **기기 날짜가 아니라 KST 날짜**다.
    //
    //   `TableCalendar` 는 `currentDay` 를 주지 않으면 `DateTime.now()` 로
    //   today 를 정한다(패키지 284행). 그러면 기기 시간대에 따라 하루가
    //   밀리는데, 이 앱의 근무일·가능일·저장 필터는 전부 KST day key 로
    //   판정한다 — 한 화면에서 두 자를 섞으면 "오늘"이 서로 달라진다.
    //
    //   `isSameDay` 는 연·월·일 **성분만** 비교하므로(패키지 51행),
    //   KST 날짜의 성분을 그대로 넘기면 기기 시간대와 무관하게 맞는다.
    final kstToday = FormatHelper.toKstDate(DateTime.now());
    final today = DateTime(kstToday.year, kstToday.month, kstToday.day);

    return TableCalendar(
      locale: 'ko_KR',
      currentDay: today,
      firstDay: _firstDay,
      lastDay: _lastDay,
      focusedDay: focusedDay,
      calendarFormat: CalendarFormat.month,
      availableGestures: availableGestures,
      sixWeekMonthsEnforced: true, // 항상 6행 → 달 전환 시 높이 고정
      daysOfWeekHeight: scaledHeight(context, 28, fontSize: 13),
      rowHeight: scaledHeight(context, rowHeight),
      selectedDayPredicate: selectedDayPredicateOverride ??
          (day) => DateUtils.isSameDay(selectedDay, day),
      enabledDayPredicate: enabledDayPredicate,
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      eventLoader: eventLoader,
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (context, day, _) {
          if (!day.isBefore(today)) return null;
          final isWeekend = day.weekday == DateTime.saturday ||
              day.weekday == DateTime.sunday;
          return Center(
            child: Text(
              '${day.day}',
              style: TextStyle(
                color: isWeekend ? AppColors.errorLight : AppColors.grey400,
                fontWeight: FontWeight.normal,
              ),
            ),
          );
        },
        markerBuilder: markerBuilder,
        // [DU293 WM4] 머리 '2026년 11월' 이 큰 글자에서 '11 | 월' 로 끊겼다 — 낱말 단위(읽기 이름은 원문).
        //   글은 table_calendar 기본(ko_KR yMMMM)과 같은 '연년 월월', 받은 날짜 성분 그대로다.
        headerTitleBuilder: (context, day) {
          final title = '${day.year}년 ${day.month}월';
          return Text(
            TextLayout.keepWords(title),
            semanticsLabel: title,
            textAlign: TextAlign.center,
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          );
        },
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: ResponsiveHelper.smallStyle(context).copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.grey600,
        ),
        weekendStyle: ResponsiveHelper.smallStyle(context).copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.grey500,
        ),
      ),
      calendarStyle: CalendarStyle(
        outsideDaysVisible: false,
        cellMargin: cellMargin ?? const CalendarStyle().cellMargin,
        markersMaxCount: 3,
        weekendTextStyle: const TextStyle(
          color: AppColors.errorFaded,
          fontWeight: FontWeight.w500,
        ),
        todayDecoration: BoxDecoration(
          color: theme.primaryColor.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        todayTextStyle: TextStyle(
          color: theme.primaryColor,
          fontWeight: FontWeight.bold,
        ),
        selectedDecoration: BoxDecoration(
          color: theme.primaryColor,
          shape: BoxShape.circle,
        ),
        selectedTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: ResponsiveHelper.subtitleStyle(context).copyWith(
          fontWeight: FontWeight.bold,
        ),
        headerPadding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, headerVerticalPadding),
          horizontal: ResponsiveHelper.spacing(context, 8),
        ),
        leftChevronIcon: Icon(Icons.chevron_left, color: theme.primaryColor, size: 24),
        rightChevronIcon: Icon(Icons.chevron_right, color: theme.primaryColor, size: 24),
      ),
    );
  }
}
