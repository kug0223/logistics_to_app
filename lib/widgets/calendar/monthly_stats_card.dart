import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/core/application_model.dart';
import '../../utils/calendar_helper.dart';

/// 월별 통계 카드
class MonthlyStatsCard extends StatelessWidget {
  final List<ApplicationModel> applications;
  final DateTime focusedDay;
  
  const MonthlyStatsCard({
    super.key,
    required this.applications,
    required this.focusedDay,
  });
  
  @override
  Widget build(BuildContext context) {
    // 이번 달 데이터만 필터링
    final thisMonth = CalendarHelper.getThisMonthApplications(applications, focusedDay);
    
    final confirmedCount = CalendarHelper.getConfirmedCount(thisMonth);
    final pendingCount = CalendarHelper.getPendingCount(thisMonth);
    final totalIncome = CalendarHelper.getTotalIncome(thisMonth);
    
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            icon: Icons.check_circle,
            label: '확정 근무',
            value: '$confirmedCount일',
            color: Colors.green,
          ),
          _buildStatItem(
            icon: Icons.schedule,
            label: '대기 중',
            value: '$pendingCount건',
            color: Colors.orange,
          ),
          _buildStatItem(
            icon: Icons.attach_money,
            label: '예상 수입',
            value: '${NumberFormat('#,###').format(totalIncome)}원',
            color: Colors.blue,
          ),
        ],
      ),
    );
  }
  
  /// 통계 아이템
  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required MaterialColor color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color[600], size: 24),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color[700],
          ),
        ),
      ],
    );
  }
}