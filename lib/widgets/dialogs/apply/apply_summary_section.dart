// lib/widgets/dialogs/apply/apply_summary_section.dart

import 'package:flutter/material.dart';
import '../../../../utils/format_helper.dart';
import '../../../../models/core/application_model.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../theme/app_colors.dart';

/// 내 지원 일정 섹션 (컴팩트)
///
/// 사용자의 전체 활성 지원 내역(모든 공고 포함)을 최대 2건 미리보기로 표시.
/// - 대기 상태 → Orange 배지 '대기'
/// - 확정 상태 → Green 배지 '확정'
/// - currentToId의 공고 지원 → '현재 공고' 라벨
/// - 3건 이상이면 '전체보기 >' 표시
class ApplySummarySection extends StatelessWidget {
  /// 사용자의 전체 지원 목록 (PENDING + CONFIRMED 포함)
  final List<ApplicationModel> myApplications;

  /// 현재 보고 있는 공고 ID — 이 TO의 지원에 '현재 공고' 라벨 표시
  final String? currentToId;

  final String emptyMessage;

  /// true이면 로드 실패 안내 표시 (emptyMessage 대신)
  final bool isLoadError;

  const ApplySummarySection({
    super.key,
    required this.myApplications,
    this.currentToId,
    this.emptyMessage = '오늘 이후 예정된 지원 건이 없습니다',
    this.isLoadError = false,
  });

  // ─── 활성 지원만 필터 ───────────────────────────────────
  List<ApplicationModel> get _active {
    final today = DateTime.now();
    final todayOnly = FormatHelper.toKstDate(today);

    return myApplications.where((app) {
      if (AppStatus.inactiveStates.contains(app.status)) return false;
      // 장기 지원 중 퇴사 완료된 건 제외
      if (app.isLongTermApplication && app.isTerminationApproved) return false;
      // 단기 지원은 오늘 이전 날짜 제외 (장기는 계약 기간 내내 유지)
      if (!app.isLongTermApplication) {
        final workDateOnly = FormatHelper.toKstDate(app.workDate);
        if (workDateOnly.isBefore(todayOnly)) return false;
      }
      return true;
    }).toList();
  }

  // ─── 날짜순 정렬, 현재 공고 먼저 ─────────────────────────
  List<ApplicationModel> get _sorted {
    final all = _active;
    all.sort((a, b) {
      final aIsCurrent = (currentToId != null && a.toId == currentToId) ? 0 : 1;
      final bIsCurrent = (currentToId != null && b.toId == currentToId) ? 0 : 1;
      final cmpCurrent = aIsCurrent.compareTo(bIsCurrent);
      if (cmpCurrent != 0) return cmpCurrent;
      return a.workDate.compareTo(b.workDate);
    });
    return all;
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sorted;
    final total = sorted.length;
    final preview = sorted.take(2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더 row: 타이틀 + 건수 배지 + "전체보기 >"
        Row(
          children: [
            Icon(
              Icons.event_note_outlined,
              size: ResponsiveHelper.iconSize(context, 15),
              color: AppColors.grey600,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 5)),
            Text(
              '내 지원 일정',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey700, fontWeight: FontWeight.w600),
            ),
            if (total > 0) ...[
              SizedBox(width: ResponsiveHelper.spacing(context, 5)),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 6),
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: AppColors.grey200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$total건',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey600, fontWeight: FontWeight.w600),
                ),
              ),
            ],
            const Spacer(),
            if (total > 2)
              Text(
                '전체보기 >',
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.infoDark, fontWeight: FontWeight.w600),
              ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 7)),
        // 내용
        if (isLoadError)
          _buildErrorState(context)
        else if (total == 0)
          _buildEmptyState(context)
        else
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 10),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.grey200),
            ),
            child: Column(
              children: preview.asMap().entries.map((e) {
                final idx = e.key;
                final app = e.value;
                return Column(
                  children: [
                    _buildAppItem(context, app),
                    if (idx < preview.length - 1)
                      Divider(
                        height: ResponsiveHelper.spacing(context, 12),
                        color: AppColors.grey200,
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  // ─── 빈 상태 ──────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 4)),
      child: Text(
        emptyMessage,
        style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 4)),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined,
              size: ResponsiveHelper.iconSize(context, 13),
              color: AppColors.warning),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            '지원 현황을 불러오지 못했습니다',
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
          ),
        ],
      ),
    );
  }

  // ─── 지원 아이템 ───────────────────────────────────────

  Widget _buildAppItem(BuildContext context, ApplicationModel app) {
    final isConfirmed = AppStatus.confirmedStatuses.contains(app.status);
    final isCurrent = currentToId != null && app.toId == currentToId;
    final timeRange = '${app.startTime} ~ ${app.endTime}';
    final dateLabel = app.isLongTermApplication
        ? '${FormatHelper.formatDateShort(app.workDate)} 시작'
        : FormatHelper.formatDateShort(app.workDate);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 상태 점
        Padding(
          padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 5)),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConfirmed ? AppColors.success : AppColors.warning,
            ),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        // 날짜 + 현재공고 라벨 + 업무/시간/사업장
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    dateLabel,
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.grey600,
                        fontWeight: FontWeight.w600),
                  ),
                  if (isCurrent) ...[
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 4),
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.infoBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '현재 공고',
                        style: ResponsiveHelper.tinyStyle(
                          context,
                          color: AppColors.infoDark,
                          fontWeight: FontWeight.w700,
                        ).copyWith(fontSize: 9),
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 1),
              Text(
                '${app.selectedWorkType}  $timeRange',
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
              ),
              if (app.businessName.isNotEmpty)
                Text(
                  app.businessName,
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
                ),
            ],
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        // 상태 배지 — 대기: Orange, 확정: Green
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 6),
            vertical: ResponsiveHelper.spacing(context, 2),
          ),
          decoration: BoxDecoration(
            color: isConfirmed ? AppColors.successBg : AppColors.warningBg,
            borderRadius: BorderRadius.circular(
                ResponsiveHelper.spacing(context, 4)),
          ),
          child: Text(
            isConfirmed ? '확정' : '대기',
            style: ResponsiveHelper.tinyStyle(
              context,
              color: isConfirmed ? AppColors.successDark : AppColors.warningDark,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
