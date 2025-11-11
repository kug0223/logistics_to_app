import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../../models/core/application_model.dart';
import '../../utils/calendar_helper.dart';

/// 근무 스케줄 캘린더 위젯
class ScheduleCalendar extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final List<ApplicationModel> applications;
  final String selectedFilter;
  final Function(DateTime selectedDay, DateTime focusedDay) onDaySelected;
  final Function(DateTime focusedDay) onPageChanged;
  
  const ScheduleCalendar({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.applications,
    required this.selectedFilter,
    required this.onDaySelected,
    required this.onPageChanged,
  });
  
  @override
  Widget build(BuildContext context) {
    return TableCalendar(
      locale: 'ko_KR',
      firstDay: DateTime.utc(2024, 1, 1),
      lastDay: DateTime.utc(2050, 12, 31),
      focusedDay: focusedDay,
      calendarFormat: CalendarFormat.month,
      
      // ⭐ 요일 행 높이 증가
      daysOfWeekHeight: 40,  // 기본값 16 → 40으로 증가
      
      // ⭐ 날짜 셀 높이도 조정 (선택)
      rowHeight: 48,  // 기본값보다 조금 증가
      
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextFormatter: (date, locale) {
          return DateFormat.yMMMM('ko_KR').format(date);
        },
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        leftChevronIcon: const Icon(Icons.chevron_left),
        rightChevronIcon: const Icon(Icons.chevron_right),
      ),
      
      selectedDayPredicate: (day) {
        return isSameDay(selectedDay, day);
      },
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      
      eventLoader: (day) {
        return CalendarHelper.getEventsForDay(day, applications, selectedFilter);
      },
      
      // ⭐ 커스텀 마커 빌더 (상태별 색상)
      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, date, events) {
          if (events.isEmpty) return const SizedBox.shrink();
          
          final apps = events.cast<ApplicationModel>();
          
          final hasConfirmed = apps.any((app) => app.status == 'CONFIRMED');
          final hasPending = apps.any((app) => app.status == 'PENDING');
          final hasRejected = apps.any((app) => app.status == 'REJECTED');
          
          List<Color> colors = [];
          
          if (hasConfirmed) colors.add(Colors.green[600]!);
          if (hasPending) colors.add(Colors.orange[600]!);
          if (hasRejected) colors.add(Colors.red[600]!);
          // 색상이 없으면 표시 안 함
          if (colors.isEmpty) return const SizedBox.shrink();
          
          final displayColors = colors.take(3).toList();
          
          return Positioned(
            bottom: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: displayColors.map((color) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
      
      calendarStyle: CalendarStyle(
        todayDecoration: BoxDecoration(
          color: Colors.blue[100],
          shape: BoxShape.circle,
        ),
        todayTextStyle: TextStyle(
          color: Colors.blue[900],
          fontWeight: FontWeight.bold,
        ),
        selectedDecoration: BoxDecoration(
          color: Colors.blue[600],
          shape: BoxShape.circle,
        ),
        selectedTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        markersMaxCount: 0,
      ),
      
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(
          color: Colors.grey[800],
          fontWeight: FontWeight.w600,
          fontSize: 14,  // ⭐ 폰트 크기 명시
        ),
        weekendStyle: TextStyle(
          color: Colors.red[600],
          fontWeight: FontWeight.w600,
          fontSize: 14,  // ⭐ 폰트 크기 명시
        ),
      ),
    );
  }
}
