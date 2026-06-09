// lib/widgets/dialogs/apply/apply_summary_section.dart

import 'package:flutter/material.dart';
import '../../../../utils/format_helper.dart';
import '../../../../models/core/application_model.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../theme/app_colors.dart';

/// 지원 요약 섹션
///
/// 사용자의 전체 활성 지원 내역(모든 공고 포함)을 날짜별로 그루핑하여 표시.
/// 단일 공고는 물론 여러 공고에 동시 지원한 경우도 한눈에 파악 가능.
class ApplySummarySection extends StatelessWidget {
  /// 사용자의 전체 지원 목록 (PENDING + CONFIRMED 포함)
  final List<ApplicationModel> myApplications;

  final String emptyMessage;

  /// true이면 로드 실패 안내 표시 (emptyMessage 대신)
  final bool isLoadError;

  const ApplySummarySection({
    super.key,
    required this.myApplications,
    this.emptyMessage = '지원한 업무가 없습니다',
    this.isLoadError = false,
  });

  // ─── 활성 지원만 필터 ───────────────────────────────────
  List<ApplicationModel> get _active => myApplications.where((app) {
    if (AppStatus.inactiveStates.contains(app.status)) return false;
    // 장기 지원 중 퇴사 완료된 건 제외
    if (app.isLongTermApplication && app.isTerminationApproved) return false;
    return true;
  }).toList();

  // ─── 날짜별 그루핑 ─────────────────────────────────────
  /// workDate 기준으로 그루핑, 날짜 오름차순 정렬
  Map<DateTime, List<ApplicationModel>> get _byDate {
    final map = <DateTime, List<ApplicationModel>>{};
    for (final app in _active) {
      final key = DateTime(
        app.workDate.year, app.workDate.month, app.workDate.day,
      );
      map.putIfAbsent(key, () => []).add(app);
    }
    return Map.fromEntries(
      map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byDate = _byDate;
    final hasAny = byDate.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.spacing(context, 12),
        ),
        border: Border.all(
          color: theme.primaryColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, theme, byDate.length),
          Divider(height: 1, color: theme.primaryColor.withValues(alpha: 0.1)),
          if (!hasAny)
            _buildEmptyState(context)
          else
            _buildContent(context, theme, byDate),
        ],
      ),
    );
  }

  // ─── 헤더 ─────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, ThemeData theme, int dateCount) {
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
          if (dateCount > 0)
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
                '$dateCount일',
                style: ResponsiveHelper.smallStyle(context, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  // ─── 빈 상태 ──────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    final icon = isLoadError
        ? Icons.cloud_off_outlined
        : Icons.assignment_late_outlined;
    final message = isLoadError
        ? '지원 현황을 불러오지 못했습니다.\n잠시 후 다시 시도해주세요.'
        : emptyMessage;

    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
      child: Center(
        child: Column(
          children: [
            Icon(
              icon,
              size: ResponsiveHelper.iconSize(context, 40),
              color: isLoadError ? AppColors.warning : AppColors.grey400,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              message,
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── 날짜별 내용 ───────────────────────────────────────

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    Map<DateTime, List<ApplicationModel>> byDate,
  ) {
    final entries = byDate.entries.toList();
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      child: Column(
        children: entries.asMap().entries.map((e) {
          final idx = e.key;
          final entry = e.value;
          return Column(
            children: [
              _buildDateSection(context, theme, entry.key, entry.value),
              if (idx < entries.length - 1)
                Divider(
                  height: ResponsiveHelper.spacing(context, 16),
                  color: theme.primaryColor.withValues(alpha: 0.1),
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
    DateTime date,
    List<ApplicationModel> apps,
  ) {
    // 확정 우선 정렬
    final sorted = [...apps]..sort((a, b) {
      final aConf = AppStatus.confirmedStatuses.contains(a.status) ? 0 : 1;
      final bConf = AppStatus.confirmedStatuses.contains(b.status) ? 0 : 1;
      return aConf.compareTo(bConf);
    });

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
              FormatHelper.formatDate(date),
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.w600,
                color: theme.primaryColor,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        ...sorted.map((app) => _buildAppItem(context, app)),
      ],
    );
  }

  Widget _buildAppItem(BuildContext context, ApplicationModel app) {
    final isConfirmed = AppStatus.confirmedStatuses.contains(app.status);
    final timeRange = '${app.startTime} ~ ${app.endTime}';

    return Padding(
      padding: EdgeInsets.only(
        left: ResponsiveHelper.spacing(context, 20),
        bottom: ResponsiveHelper.spacing(context, 6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 업무명 + 시간 + 사업장명
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• ${app.selectedWorkType}  $timeRange',
                  style: ResponsiveHelper.smallStyle(
                    context, color: AppColors.grey700),
                ),
                if (app.businessName.isNotEmpty)
                  Text(
                    app.businessName,
                    style: ResponsiveHelper.tinyStyle(
                        context, color: AppColors.grey500),
                  ),
              ],
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          // 상태 배지
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 6),
              vertical: ResponsiveHelper.spacing(context, 2),
            ),
            decoration: BoxDecoration(
              color: isConfirmed ? AppColors.successBg : AppColors.infoBg,
              borderRadius: BorderRadius.circular(
                  ResponsiveHelper.spacing(context, 4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isConfirmed) ...[
                  Icon(Icons.star,
                      size: ResponsiveHelper.iconSize(context, 10),
                      color: AppColors.successDark),
                  SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                ],
                Text(
                  isConfirmed ? '확정' : '지원완료',
                  style: ResponsiveHelper.tinyStyle(
                    context,
                    color: isConfirmed
                        ? AppColors.successDark
                        : AppColors.infoDark,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
