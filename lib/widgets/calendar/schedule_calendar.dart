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
      
      // ⭐ 커스텀 마커 빌더 (상태별 색상 + 단기/장기 구분)
      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, date, events) {
          if (events.isEmpty) return const SizedBox.shrink();
          
          final apps = events.cast<ApplicationModel>();
          
          // 단기/장기 구분
          final shortTermApps = apps.where((app) => !app.isLongTermApplication).toList();
          final longTermApps = apps.where((app) => app.isLongTermApplication).toList();
          
          // 상태별 구분
          final hasConfirmed = apps.any((app) => app.status == 'CONFIRMED');
          final hasPending = apps.any((app) => app.status == 'PENDING');
          final hasRejected = apps.any((app) => app.status == 'REJECTED');
          
          List<Widget> markers = [];
          
          // 확정 마커
          if (hasConfirmed) {
            final hasShortConfirmed = shortTermApps.any((app) => app.status == 'CONFIRMED');
            final hasLongConfirmed = longTermApps.any((app) => app.status == 'CONFIRMED');
            
            if (hasShortConfirmed) {
              markers.add(_buildMarker(Colors.green[600]!, isLongTerm: false));
            }
            if (hasLongConfirmed) {
              markers.add(_buildMarker(Colors.green[400]!, isLongTerm: true));
            }
          }
          
          // 대기 마커
          if (hasPending) {
            final hasShortPending = shortTermApps.any((app) => app.status == 'PENDING');
            final hasLongPending = longTermApps.any((app) => app.status == 'PENDING');
            
            if (hasShortPending) {
              markers.add(_buildMarker(Colors.orange[600]!, isLongTerm: false));
            }
            if (hasLongPending) {
              markers.add(_buildMarker(Colors.orange[400]!, isLongTerm: true));
            }
          }
          
          // 거절 마커 (최대 3개까지만)
          if (hasRejected && markers.length < 3) {
            markers.add(_buildMarker(Colors.red[600]!, isLongTerm: false));
          }
          
          // 최대 3개까지만 표시
          if (markers.length > 3) {
            markers = markers.sublist(0, 3);
          }
          
          return Positioned(
            bottom: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: markers,
            ),
          );
        },
      ),
    );
  }
  
  /// 마커 위젯 생성 (단기: 원형, 고정: 별)
  Widget _buildMarker(Color color, {required bool isLongTerm}) {
    if (isLongTerm) {
      // 고정 근무: 별 모양
      return Icon(
        Icons.star,
        size: 7,
        color: color,
      );
    } else {
      // 단기 근무: 원형
      return Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 0.5),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      );
    }
  }
}
