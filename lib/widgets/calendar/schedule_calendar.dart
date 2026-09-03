import 'package:flutter/material.dart';
import '../../models/core/application_model.dart';
import '../../models/core/worker_availability_model.dart';
import '../../utils/calendar_helper.dart';
import '../../theme/app_colors.dart';
import 'app_calendar.dart';

/// 사용자 근무 스케줄 캘린더
/// AppCalendar 위에 ApplicationModel 기반 마커를 올린 래퍼.
///
/// Phase 8.1A: 근무 가능일 표시(availabilityDates) + 에디트 모드(isEditMode) 지원.
class ScheduleCalendar extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final List<ApplicationModel> applications;
  final String selectedFilter;
  final Function(DateTime selectedDay, DateTime focusedDay) onDaySelected;
  final Function(DateTime focusedDay) onPageChanged;
  /// 미리 빌드된 날짜 인덱스 (null이면 O(n) fallback)
  final Map<String, List<ApplicationModel>>? dateIndex;

  // ── Phase 8.1A: 근무 가능일 ──────────────────────────────────
  /// 저장된 근무 가능일 날짜 키 Set ("YYYY-MM-DD").
  /// 평상시에 달력 날짜 아래 파란 dot으로 표시.
  final Set<String>? availabilityDates;

  /// 에디트 모드에서 현재 선택(토글) 중인 날짜 키 Set.
  /// selectedDayPredicateOverride로 파란 원 표시.
  final Set<String>? editingDates;

  /// 에디트 모드 활성화 여부.
  ///   · true: today~+90 이내만 tap 가능, editingDates 원형 표시
  ///   · false: 기존 동작 유지
  final bool isEditMode;

  const ScheduleCalendar({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.applications,
    required this.selectedFilter,
    required this.onDaySelected,
    required this.onPageChanged,
    this.dateIndex,
    this.availabilityDates,
    this.editingDates,
    this.isEditMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    final maxDate = todayOnly.add(const Duration(days: 90));

    // 에디트 모드 enabledDayPredicate: today~+90 이내만 활성화
    bool editModePredicate(DateTime day) {
      final dayOnly = DateTime(day.year, day.month, day.day);
      return !dayOnly.isBefore(todayOnly) && !dayOnly.isAfter(maxDate);
    }

    // 일반 모드 enabledDayPredicate: 과거는 이벤트 있을 때만, 미래 항상
    bool normalModePredicate(DateTime day) {
      final dayOnly = DateTime(day.year, day.month, day.day);
      if (!dayOnly.isBefore(todayOnly)) return true;
      final events = dateIndex != null
          ? CalendarHelper.getEventsForDayFromIndex(day, dateIndex!)
          : CalendarHelper.getEventsForDay(day, applications, selectedFilter);
      return events.isNotEmpty;
    }

    return AppCalendar(
      focusedDay: focusedDay,
      selectedDay: selectedDay,
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      rowHeight: 36,
      headerVerticalPadding: 4,
      enabledDayPredicate: isEditMode ? editModePredicate : normalModePredicate,
      // 에디트 모드: 복수 선택 원형 표시 (editingDates Set으로 판단)
      selectedDayPredicateOverride: isEditMode && editingDates != null
          ? (day) => editingDates!.contains(WorkerAvailabilityModel.dateKeyFrom(day))
          : null,
      eventLoader: (day) => dateIndex != null
          ? CalendarHelper.getEventsForDayFromIndex(day, dateIndex!)
          : CalendarHelper.getEventsForDay(day, applications, selectedFilter),
      markerBuilder: (context, date, events) {
        final apps = events.whereType<ApplicationModel>().toList();
        final dateKey = WorkerAvailabilityModel.dateKeyFrom(date);

        // 에디트 모드에서는 application 마커 숨기고, 선택 원만 표시
        if (isEditMode) {
          // 에디트 모드에서는 마커 없음 (selectedDayPredicateOverride가 원 표시)
          return null;
        }

        final shortTermApps = apps.where((a) => !a.isLongTermApplication).toList();
        final longTermApps = apps.where((a) => a.isLongTermApplication).toList();

        final hasConfirmed = apps.any((a) => AppStatus.confirmedStatuses.contains(a.status));
        final hasPending = apps.any((a) => a.status == AppStatus.pending);
        // 가능일 파란 dot
        final hasAvailability = availabilityDates?.contains(dateKey) ?? false;

        final markers = <Widget>[];

        if (hasConfirmed) {
          final hasShortConfirmed = shortTermApps.any(
              (a) => AppStatus.confirmedStatuses.contains(a.status));
          final hasLongConfirmed = longTermApps.any(
              (a) => AppStatus.confirmedStatuses.contains(a.status));
          final hasLeaveDay = longTermApps.any(
              (a) => AppStatus.confirmedStatuses.contains(a.status) &&
                     a.isLeaveDateOn(date));

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
          if (shortTermApps.any((a) => a.status == AppStatus.pending)) {
            markers.add(_dot(AppColors.warningMedium, isLongTerm: false));
          }
          if (longTermApps.any((a) => a.status == AppStatus.pending)) {
            markers.add(_dot(AppColors.warningFaded, isLongTerm: true));
          }
        }

        // 가능일 마커 — 다른 마커가 없을 때만 표시 (마커 3개 초과 방지)
        // 이미 markers 3개면 공간 없으므로 생략
        if (hasAvailability && markers.isEmpty) {
          markers.add(_availabilityDot());
        } else if (hasAvailability && markers.length < 3) {
          markers.add(_availabilityDot());
        }

        if (markers.isEmpty) return null;

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

  /// 근무 가능일 파란 dot (AppColors.info = 0xFF2196F3)
  Widget _availabilityDot() {
    return Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: const BoxDecoration(
        color: AppColors.info,
        shape: BoxShape.circle,
      ),
    );
  }
}
