import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../models/core/application_model.dart';
import '../../utils/calendar_helper.dart';

/// 근무 스케줄 캘린더 위젯 (workforce_calendar_view 스타일 통일)
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
      
      daysOfWeekHeight: 30,
      rowHeight: 40,
      
      selectedDayPredicate: (day) => DateUtils.isSameDay(selectedDay, day),
      
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      
      // 이벤트 마커
      eventLoader: (day) {
        return CalendarHelper.getEventsForDay(day, applications, selectedFilter);
      },
      
      // ✨ 커스텀 마커 빌더 (workforce_calendar_view 스타일)
      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, date, events) {
          if (events.isEmpty) return null;
          
          final apps = events.cast<ApplicationModel>();
          
          // 단기/장기 구분
          final shortTermApps = apps.where((app) => !app.isLongTermApplication).toList();
          final longTermApps = apps.where((app) => app.isLongTermApplication).toList();
          
          // 상태별 구분
          final hasConfirmed = apps.any((app) => app.status == 'CONFIRMED');
          final hasPending = apps.any((app) => app.status == 'PENDING');
          final hasRejected = apps.any((app) => app.status == 'REJECTED');
          
          List<Widget> markers = [];
          
          // ✨ 확정 마커 - workforce_calendar_view와 동일한 색상
          if (hasConfirmed) {
            final hasShortConfirmed = shortTermApps.any((app) => app.status == 'CONFIRMED');
            final hasLongConfirmed = longTermApps.any((app) => app.status == 'CONFIRMED');
            
            // 휴무일 체크
            final hasLeaveDay = longTermApps.any((app) => 
              app.status == 'CONFIRMED' && app.isLeaveDateOn(date)
            );
            
            if (hasShortConfirmed) {
              markers.add(_buildMarker(
                Theme.of(context).primaryColor,  // ← workforce_calendar_view와 동일
                isLongTerm: false,
              ));
            }
            if (hasLongConfirmed) {
              if (hasLeaveDay) {
                markers.add(_buildMarker(
                  Colors.grey[400]!,
                  isLongTerm: true,
                ));
              } else {
                markers.add(_buildMarker(
                  Colors.amber[700]!,  // ← workforce_calendar_view와 동일
                  isLongTerm: true,
                ));
              }
            }
          }
          
          // ✨ 대기 마커
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
          
          // ✨ 거절 마커 (최대 3개까지만)
          if (hasRejected && markers.length < 3) {
            markers.add(_buildMarker(Colors.red[600]!, isLongTerm: false));
          }
          
          // 최대 3개까지만 표시
          if (markers.length > 3) {
            markers = markers.sublist(0, 3);
          }
          
          return Positioned(
            bottom: 3,  // ← workforce_calendar_view와 동일한 위치
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: markers,
            ),
          );
        },
      ),
      
      // ✨ workforce_calendar_view와 동일한 스타일
      calendarStyle: CalendarStyle(
        markersMaxCount: 2,
        todayDecoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        selectedDecoration: BoxDecoration(
          color: Theme.of(context).primaryColor,
          shape: BoxShape.circle,
        ),
      ),
      
      // ✨ workforce_calendar_view와 동일한 헤더
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        headerPadding: EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }
  
  /// ✨ 마커 위젯 생성 (workforce_calendar_view와 동일)
  Widget _buildMarker(Color color, {required bool isLongTerm}) {
    if (isLongTerm) {
      // 장기 근무: 별 모양 (workforce_calendar_view와 동일)
      return Icon(
        Icons.star,
        size: 10,  // ← workforce_calendar_view와 동일한 크기
        color: color,
      );
    } else {
      // 단기 근무: 원형 (workforce_calendar_view와 동일)
      return Container(
        width: 7,  // ← workforce_calendar_view와 동일한 크기
        height: 7,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),  // ← workforce_calendar_view와 동일
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      );
    }
  }
}