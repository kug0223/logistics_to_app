import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../utils/calendar_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../theme/app_colors.dart';

/// 월별 통계 카드 (2행 레이아웃: 예정 + 완료)
class MonthlyStatsCard extends StatelessWidget {
  final List<ApplicationModel> applications;
  final List<AttendanceModel> attendances;
  final DateTime focusedDay;
  
  const MonthlyStatsCard({
    super.key,
    required this.applications,
    required this.attendances,
    required this.focusedDay,
  });
  
  @override
  Widget build(BuildContext context) {
    // 이번 달 데이터만 필터링
    final thisMonth = CalendarHelper.getThisMonthApplications(applications, focusedDay);
    
    // 예정 통계
    final confirmedCount = CalendarHelper.getConfirmedCount(thisMonth);
    final pendingCount = CalendarHelper.getPendingCount(thisMonth);
    final totalIncome = CalendarHelper.getTotalIncome(thisMonth);
    
    // 완료 통계
    final actualWorkDays = CalendarHelper.getActualWorkDays(attendances, focusedDay);
    final confirmedIncome = CalendarHelper.getConfirmedIncome(attendances, focusedDay);
    
    // 완료 데이터 존재 여부
    final hasCompletedData = actualWorkDays > 0 || confirmedIncome > 0;
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // ═══════════════════════════════════════════════════════
          // 📅 예정 섹션
          // ═══════════════════════════════════════════════════════
          _buildSectionHeader(context, '📅 예정', AppColors.infoDark!),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                context,
                icon: Icons.check_circle,
                label: '확정 근무',
                value: '$confirmedCount일',
                color: Colors.green,
              ),
              _buildStatItem(
                context,
                icon: Icons.schedule,
                label: '대기 중',
                value: '$pendingCount건',
                color: Colors.orange,
              ),
              _buildStatItem(
                context,
                icon: Icons.attach_money,
                label: '예상 수입',
                value: '${NumberFormat('#,###').format(totalIncome)}원',
                color: Colors.blue,
              ),
            ],
          ),
          
          // ═══════════════════════════════════════════════════════
          // ✅ 완료 섹션 (데이터 있을 때만 표시)
          // ═══════════════════════════════════════════════════════
          if (hasCompletedData) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Divider(color: AppColors.grey200, height: 1),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _buildSectionHeader(context, '✅ 완료', AppColors.successDark!),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatItem(
                  context,
                  icon: Icons.directions_run,
                  label: '실근무',
                  value: '$actualWorkDays일',
                  color: Colors.teal,
                ),
                _buildStatItem(
                  context,
                  icon: Icons.paid,
                  label: '확정 수입',
                  value: '${NumberFormat('#,###').format(confirmedIncome)}원',
                  color: Colors.green,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
  
  /// 섹션 헤더
  Widget _buildSectionHeader(BuildContext context, String title, Color color) {
    return Row(
      children: [
        Text(
          title,
          style: ResponsiveHelper.smallStyle(
            context,
            color: color,
          ).copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
  
  /// 통계 아이템
  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required MaterialColor color,
  }) {
    return Column(
      children: [
        Icon(
          icon, 
          color: color[600], 
          size: ResponsiveHelper.iconSize(context, 24)
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        Text(
          label,
          style: ResponsiveHelper.smallStyle(
            context,
            color: AppColors.grey600,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 2)),
        Text(
          value,
          style: ResponsiveHelper.bodyStyle(
            context,
            color: color[700],
          ).copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
