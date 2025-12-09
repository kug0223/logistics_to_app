// lib/widgets/dialogs/apply/apply_summary_section.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../models/core/work_detail_model.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../utils/format_helper.dart';
import '../../../../theme/app_colors.dart';

/// 날짜별 지원 정보
class DateApplicationInfo {
  final DateTime date;
  final List<WorkDetailModel> appliedWorks;   // 지원한 업무들
  final List<WorkDetailModel> confirmedWorks; // 확정된 업무들

  const DateApplicationInfo({
    required this.date,
    this.appliedWorks = const [],
    this.confirmedWorks = const [],
  });

  /// 해당 날짜에 지원/확정된 업무가 있는지
  bool get hasApplications => appliedWorks.isNotEmpty || confirmedWorks.isNotEmpty;

  /// 총 예상 급여 계산
  int get totalWage {
    int total = 0;
    
    for (final work in [...appliedWorks, ...confirmedWorks]) {
      if (work.wageType == 'hourly') {
        // 시급: 시간 * 시급
        final hours = _calculateHours(work.startTime, work.endTime);
        total += (hours * work.wage).toInt();
      } else {
        // 일급/월급
        total += work.wage;
      }
    }
    
    return total;
  }

  double _calculateHours(String startTime, String endTime) {
    final startParts = startTime.split(':');
    final endParts = endTime.split(':');
    
    final startMinutes = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
    
    return (endMinutes - startMinutes) / 60;
  }
}

/// 지원 요약 섹션
/// 
/// 선택한 날짜와 업무를 실시간으로 표시
class ApplySummarySection extends StatelessWidget {
  /// 날짜별 지원 정보 목록
  final List<DateApplicationInfo> applicationInfos;
  
  /// 비어있을 때 표시할 메시지
  final String emptyMessage;

  const ApplySummarySection({
    super.key,
    required this.applicationInfos,
    this.emptyMessage = '지원한 업무가 없습니다',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 실제 지원/확정이 있는 날짜만 필터
    final activeInfos = applicationInfos.where((info) => info.hasApplications).toList();
       
    return Container(
      decoration: BoxDecoration(
        color: theme.primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.spacing(context, 12),
        ),
        border: Border.all(
          color: theme.primaryColor.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          _buildHeader(context, theme, activeInfos.length),
          
          // 구분선
          Divider(
            height: 1,
            color: theme.primaryColor.withOpacity(0.1),
          ),
          
          // 내용
          if (activeInfos.isEmpty)
            _buildEmptyState(context)
          else
            _buildContent(context, theme, activeInfos),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 헤더
  // ═══════════════════════════════════════════════════════════

  Widget _buildHeader(BuildContext context, ThemeData theme, int count) {
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      child: Row(
        children: [
          Icon(
            Icons.assignment_outlined,
            size: ResponsiveHelper.iconSize(context, 20),
            color: theme.primaryColor,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            '내 지원 현황',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: theme.primaryColor,
            ),
          ),
          const Spacer(),
          if (count > 0)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8),
                vertical: ResponsiveHelper.spacing(context, 2),
              ),
              decoration: BoxDecoration(
                color: theme.primaryColor,
                borderRadius: BorderRadius.circular(
                  ResponsiveHelper.spacing(context, 10),
                ),
              ),
              child: Text(
                '$count일',
                style: ResponsiveHelper.smallStyle(context, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 빈 상태
  // ═══════════════════════════════════════════════════════════

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.inbox_outlined,
              size: ResponsiveHelper.iconSize(context, 40),
              color: AppColors.grey400,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              emptyMessage,
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 내용 (날짜별 업무 목록)
  // ═══════════════════════════════════════════════════════════

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    List<DateApplicationInfo> infos,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      child: Column(
        children: infos.asMap().entries.map((entry) {
          final index = entry.key;
          final info = entry.value;
          
          return Column(
            children: [
              _buildDateSection(context, theme, info),
              if (index < infos.length - 1)
                Divider(
                  height: ResponsiveHelper.spacing(context, 16),
                  color: theme.primaryColor.withOpacity(0.1),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDateSection(
    BuildContext context,
    ThemeData theme,
    DateApplicationInfo info,
  ) {
    final dateFormat = DateFormat('M/d (E)', 'ko_KR');
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 날짜 헤더
        Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: ResponsiveHelper.iconSize(context, 14),
              color: theme.primaryColor,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(
              dateFormat.format(info.date),
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.w600,
                color: theme.primaryColor,
              ),
            ),
          ],
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        
        // 확정된 업무들
        ...info.confirmedWorks.map((work) => _buildWorkItem(
          context,
          work: work,
          isConfirmed: true,
        )),
        
        // 지원한 업무들
        ...info.appliedWorks.map((work) => _buildWorkItem(
          context,
          work: work,
          isConfirmed: false,
        )),
      ],
    );
  }

  Widget _buildWorkItem(
    BuildContext context, {
    required WorkDetailModel work,
    required bool isConfirmed,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        left: ResponsiveHelper.spacing(context, 20),
        bottom: ResponsiveHelper.spacing(context, 4),
      ),
      child: Row(
        children: [
          // 업무명 + 시간
          Expanded(
            child: Text(
              '• ${work.workType} ${work.timeRange}',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
            ),
          ),
          
          // 상태 뱃지
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 6),
              vertical: ResponsiveHelper.spacing(context, 2),
            ),
            decoration: BoxDecoration(
              color: isConfirmed ? AppColors.successBg : AppColors.infoBg,
              borderRadius: BorderRadius.circular(
                ResponsiveHelper.spacing(context, 4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isConfirmed)
                  Icon(
                    Icons.star,
                    size: ResponsiveHelper.iconSize(context, 10),
                    color: AppColors.successDark,
                  ),
                if (isConfirmed)
                  SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                Text(
                  isConfirmed ? '확정' : '지원완료',
                  style: ResponsiveHelper.tinyStyle(
                    context,
                    color: isConfirmed ? AppColors.successDark : AppColors.infoDark,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 총 예상 급여
  // ═══════════════════════════════════════════════════════════

  Widget _buildTotalWage(BuildContext context, ThemeData theme, int totalWage) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: theme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(ResponsiveHelper.spacing(context, 12)),
          bottomRight: Radius.circular(ResponsiveHelper.spacing(context, 12)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.payments_outlined,
                size: ResponsiveHelper.iconSize(context, 18),
                color: theme.primaryColor,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                '총 예상 급여',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Text(
            '약 ${FormatHelper.formatNumber(totalWage)}원',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: theme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}