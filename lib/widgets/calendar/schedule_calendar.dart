import 'package:flutter/material.dart';
import '../../models/core/application_model.dart';
import '../../utils/calendar_helper.dart';
import '../../theme/app_colors.dart';
import 'app_calendar.dart';

/// 사용자 근무 스케줄 캘린더
/// AppCalendar 위에 ApplicationModel 기반 마커를 올린 래퍼.
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
    return AppCalendar(
      focusedDay: focusedDay,
      selectedDay: selectedDay,
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      rowHeight: 40,
      enabledDayPredicate: (day) {
        final today = DateTime.now();
        final todayOnly = DateTime(today.year, today.month, today.day);
        final dayOnly = DateTime(day.year, day.month, day.day);
        if (!dayOnly.isBefore(todayOnly)) return true;
        return CalendarHelper.getEventsForDay(day, applications, selectedFilter).isNotEmpty;
      },
      eventLoader: (day) =>
          CalendarHelper.getEventsForDay(day, applications, selectedFilter),
      markerBuilder: (context, date, events) {
        if (events.isEmpty) return null;
        final apps = events.cast<ApplicationModel>();

        final shortTermApps = apps.where((a) => !a.isLongTermApplication).toList();
        final longTermApps = apps.where((a) => a.isLongTermApplication).toList();

        final hasConfirmed = apps.any((a) => a.status == 'CONFIRMED');
        final hasPending = apps.any((a) => a.status == 'PENDING');
        final hasRejected = apps.any((a) => a.status == 'REJECTED');

        final markers = <Widget>[];

        if (hasConfirmed) {
          final hasShortConfirmed = shortTermApps.any((a) => a.status == 'CONFIRMED');
          final hasLongConfirmed = longTermApps.any((a) => a.status == 'CONFIRMED');
          final hasLeaveDay = longTermApps.any(
              (a) => a.status == 'CONFIRMED' && a.isLeaveDateOn(date));

          if (hasShortConfirmed) {
            markers.add(_dot(Theme.of(context).primaryColor, isLongTerm: false));
          }
          if (hasLongConfirmed) {
            markers.add(_dot(
              hasLeaveDay ? AppColors.grey400 : AppColors.amberDark,
              isLongTerm: true,
            ));
          }
        }

        if (hasPending) {
          if (shortTermApps.any((a) => a.status == 'PENDING')) {
            markers.add(_dot(AppColors.warningMedium, isLongTerm: false));
          }
          if (longTermApps.any((a) => a.status == 'PENDING')) {
            markers.add(_dot(AppColors.warningFaded, isLongTerm: true));
          }
        }

        if (hasRejected && markers.length < 3) {
          markers.add(_dot(AppColors.errorMedium, isLongTerm: false));
        }

        return Positioned(
          bottom: 3,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: markers.take(3).toList(),
          ),
        );
      },
    );
  }

  Widget _dot(Color color, {required bool isLongTerm}) {
    if (isLongTerm) {
      return Icon(Icons.star, size: 10, color: color);
    }
    return Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
