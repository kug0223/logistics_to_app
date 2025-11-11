import 'package:flutter/material.dart';
import '../../models/core/application_model.dart';
import '../../utils/calendar_helper.dart';
import 'schedule_card.dart';

/// 선택한 날짜의 일정 리스트
class DayScheduleList extends StatelessWidget {
  final DateTime? selectedDay;
  final List<ApplicationModel> applications;
  final String selectedFilter;
  
  const DayScheduleList({
    super.key,
    required this.selectedDay,
    required this.applications,
    required this.selectedFilter,
  });
  
  @override
  Widget build(BuildContext context) {
    if (selectedDay == null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 200),  // ⭐ 최소 높이
        child: _buildEmptyState(
          '날짜를 선택해주세요',
          Icons.touch_app,
          '캘린더에서 날짜를 클릭하면 일정을 확인할 수 있습니다',
        ),
      );
    }
    
    final events = CalendarHelper.getEventsForDay(
      selectedDay!,
      applications,
      selectedFilter,
    );
    
    if (events.isEmpty) {
      return Container(
        constraints: const BoxConstraints(minHeight: 200),  // ⭐ 최소 높이
        child: _buildEmptyState(
          '이 날짜에는 일정이 없습니다',
          Icons.event_busy,
          '다른 날짜를 선택해보세요',
        ),
      );
    }
    
    // 상태별 정렬: 확정 > 대기 > 나머지
    events.sort((a, b) {
      final aOrder = _getStatusOrder(a.status);
      final bOrder = _getStatusOrder(b.status);
      return aOrder.compareTo(bOrder);
    });
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      itemBuilder: (context, index) {
        return ScheduleCard(application: events[index]);
      },
    );
  }
  
  /// 빈 상태 표시
  Widget _buildEmptyState(String message, IconData icon, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  /// 상태별 정렬 순서
  int _getStatusOrder(String status) {
    switch (status) {
      case 'CONFIRMED':
        return 1;
      case 'PENDING':
        return 2;
      case 'REJECTED':
        return 3;
      case 'CANCELED':
        return 4;
      case 'AUTO_CANCELED':
        return 5;
      default:
        return 6;
    }
  }
}