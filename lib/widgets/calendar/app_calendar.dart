import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

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
    this.rowHeight = 40,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    return TableCalendar(
      locale: 'ko_KR',
      firstDay: _firstDay,
      lastDay: _lastDay,
      focusedDay: focusedDay,
      calendarFormat: CalendarFormat.month,
      sixWeekMonthsEnforced: true, // 항상 6행 → 달 전환 시 높이 고정
      daysOfWeekHeight: 28,
      rowHeight: rowHeight,
      selectedDayPredicate: (day) => DateUtils.isSameDay(selectedDay, day),
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
          vertical: ResponsiveHelper.spacing(context, 8),
          horizontal: ResponsiveHelper.spacing(context, 8),
        ),
        leftChevronIcon: Icon(Icons.chevron_left, color: theme.primaryColor, size: 24),
        rightChevronIcon: Icon(Icons.chevron_right, color: theme.primaryColor, size: 24),
      ),
    );
  }
}
