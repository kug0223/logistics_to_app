// lib/screens/business_admin/dialogs/pending_approval_calendar_dialog.dart
// 승인 대기 현황 캘린더 다이얼로그
//
// 월별 날짜별 PENDING 지원자 분포를 표시하고,
// 날짜 탭 시 DayApplicantsDialog로 연결한다.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/core/business_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/loading_state_mixin.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/dialogs/styled_dialog.dart';

import 'day_applicants_dialog.dart';

class PendingApprovalCalendarDialog extends StatefulWidget {
  final DateTime initialMonth;
  final List<String> businessIds;
  final List<BusinessModel> businesses;

  const PendingApprovalCalendarDialog({
    super.key,
    required this.initialMonth,
    required this.businessIds,
    required this.businesses,
  });

  @override
  State<PendingApprovalCalendarDialog> createState() =>
      _PendingApprovalCalendarDialogState();
}

class _PendingApprovalCalendarDialogState
    extends State<PendingApprovalCalendarDialog> with LoadingStateMixin {
  // ─── 포맷터 캐싱 (build마다 재생성 방지) ─────────────────────
  static final _monthFmt  = DateFormat('yyyy년 M월');
  static final _dateFmtKo = DateFormat('M/d(E)', 'ko_KR');

  late DateTime _currentMonth;
  String? _selectedBusinessId; // null = 전체 사업장

  // 날짜별 PENDING 카운트: 'yyyy-MM-dd' → count
  Map<String, int> _pendingCountByDate = {};

  // 요약 통계
  int _totalCount = 0;
  int _todayCount = 0;
  int _overdueCount = 0; // workDate가 오늘 이전인 PENDING

  final _svc = FirestoreService();

  @override
  void initState() {
    super.initState();
    _currentMonth =
        DateTime(widget.initialMonth.year, widget.initialMonth.month, 1);
    _loadData();
  }

  Future<void> _loadData() => runWithLoading(() async {
        final bizIds = _selectedBusinessId != null
            ? [_selectedBusinessId!]
            : widget.businessIds;

        final results = await Future.wait(
          bizIds.map((id) => _svc.getPendingApplicationsByMonthAndBusiness(
                month: _currentMonth,
                businessId: id,
              )),
        );

        final allApps = results.expand((list) => list).toList();
        final Map<String, int> countMap = {};
        for (final app in allApps) {
          final key = DateFormat('yyyy-MM-dd').format(app.workDate);
          countMap[key] = (countMap[key] ?? 0) + 1;
        }

        _pendingCountByDate = countMap;
        _calculateStats();
      },
      errorTag: '승인대기 캘린더',
      errorMessage: '승인 대기 현황을 불러오는데 실패했습니다');

  void _calculateStats() {
    final today = DateTime.now();
    final todayOnly = FormatHelper.toKstDate(today);
    final todayKey = DateFormat('yyyy-MM-dd').format(today);

    int total = 0;
    int todayC = 0;
    int overdue = 0;

    for (final entry in _pendingCountByDate.entries) {
      total += entry.value;
      if (entry.key == todayKey) {
        todayC += entry.value;
      } else {
        final date = DateTime.parse(entry.key);
        if (date.isBefore(todayOnly)) overdue += entry.value;
      }
    }

    _totalCount = total;
    _todayCount = todayC;
    _overdueCount = overdue;
  }

  void _previousMonth() {
    if (isLoading) return;
    setState(() => _currentMonth =
        DateTime(_currentMonth.year, _currentMonth.month - 1, 1));
    _loadData();
  }

  void _nextMonth() {
    if (isLoading) return;
    setState(() => _currentMonth =
        DateTime(_currentMonth.year, _currentMonth.month + 1, 1));
    _loadData();
  }

  Future<void> _openDayApplicants(DateTime date) async {
    final businesses = _selectedBusinessId != null
        ? widget.businesses.where((b) => b.id == _selectedBusinessId).toList()
        : widget.businesses;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DayApplicantsDialog(
        date: date,
        businessIds: businesses.map((b) => b.id).toList(),
        businesses: businesses,
      ),
    );
    // 당일 다이얼로그에서 승인 처리 후 돌아오면 새로고침
    if (mounted) _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppModalShell(
      children: [
        AppModalHeader(
          title: '승인 대기 현황',
          subtitle: '날짜별 미승인 지원자 분포',
          onClose: () => Navigator.pop(context),
          trailing: _buildHeaderTrailing(),
        ),
        if (!isLoading) _buildSummaryCard(),
        Expanded(
          child: isLoading
              ? const LoadingWidget(message: '승인 대기 현황 조회 중...')
              : _pendingCountByDate.isEmpty
                  ? _buildEmptyState()
                  : _buildContent(theme),
        ),
        // 닫기 Footer 없음 — Header X 버튼으로 충분
      ],
    );
  }

  /// Header trailing: 월 네비게이션 + 사업장 필터(다중 사업장 시)
  Widget _buildHeaderTrailing() {
    final hasBizFilter = widget.businesses.length > 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 월 네비게이션
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: isLoading ? null : _previousMonth,
              icon: const Icon(Icons.chevron_left),
              color: AppColors.grey700,
              iconSize: 22,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            Text(
              _monthFmt.format(_currentMonth),
              style: ResponsiveHelper.bodyStyle(context)
                  .copyWith(fontWeight: FontWeight.w700, color: AppColors.grey800),
            ),
            IconButton(
              onPressed: isLoading ? null : _nextMonth,
              icon: const Icon(Icons.chevron_right),
              color: AppColors.grey700,
              iconSize: 22,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
        // 사업장 필터 (다중 사업장)
        if (hasBizFilter) _buildBusinessFilter(),
      ],
    );
  }

  Widget _buildBusinessFilter() {
    return DropdownButtonHideUnderline(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.grey100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.grey200),
        ),
        child: DropdownButton<String?>(
          value: _selectedBusinessId,
          dropdownColor: Colors.white,
          style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey800),
          iconEnabledColor: AppColors.grey500,
          isExpanded: true,
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('전체 사업장',
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey800)),
            ),
            ...widget.businesses.map((b) => DropdownMenuItem<String?>(
                  value: b.id,
                  child: Text(
                    b.name,
                    style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey800),
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
          ],
          onChanged: (val) {
            setState(() => _selectedBusinessId = val);
            _loadData();
          },
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      margin: ResponsiveHelper.cardPadding(context),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem('전체 대기', '$_totalCount명', AppColors.grey600),
          Container(
              width: 1,
              height: ResponsiveHelper.spacing(context, 30),
              color: AppColors.border),
          _buildStatItem('오늘 처리', '$_todayCount명', AppColors.warning),
          Container(
              width: 1,
              height: ResponsiveHelper.spacing(context, 30),
              color: AppColors.border),
          _buildStatItem('기한 지남', '$_overdueCount명', AppColors.error),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 2)),
        Text(label,
            style:
                ResponsiveHelper.smallStyle(context, color: AppColors.grey500)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: ResponsiveHelper.cardPadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: ResponsiveHelper.iconSize(context, 64),
                color: AppColors.grey300),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '해당 월에 승인 대기 중인 지원자가 없습니다',
              style: ResponsiveHelper.bodyStyle(context,
                  color: AppColors.grey500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final today = DateTime.now();
    final todayOnly = FormatHelper.toKstDate(today);

    final sortedEntries = _pendingCountByDate.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return ListView.separated(
      padding: ResponsiveHelper.cardPadding(context),
      itemCount: sortedEntries.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
      itemBuilder: (context, index) {
        final entry = sortedEntries[index];
        final date = DateTime.parse(entry.key);
        final count = entry.value;

        final isPast = date.isBefore(todayOnly);
        final isToday = date.year == today.year &&
            date.month == today.month &&
            date.day == today.day;

        final Color indicatorColor;
        final Color countColor;
        final String urgencyLabel;

        if (isPast) {
          indicatorColor = AppColors.error;
          countColor = AppColors.error;
          urgencyLabel = '기한 지남';
        } else if (isToday) {
          indicatorColor = AppColors.warning;
          countColor = AppColors.warning;
          urgencyLabel = '오늘';
        } else {
          indicatorColor = theme.primaryColor;
          countColor = theme.primaryColor;
          urgencyLabel = '';
        }

        final dateStr = _dateFmtKo.format(date);

        return InkWell(
          onTap: () => _openDayApplicants(date),
          child: Row(
            children: [
              Container(
                width: 4,
                height: ResponsiveHelper.spacing(context, 56),
                color: indicatorColor,
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 16),
                    vertical: ResponsiveHelper.spacing(context, 12),
                  ),
                  child: Row(
                    children: [
                      Text(
                        dateStr,
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      if (urgencyLabel.isNotEmpty)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 6),
                            vertical: ResponsiveHelper.spacing(context, 2),
                          ),
                          decoration: BoxDecoration(
                            color: indicatorColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            urgencyLabel,
                            style: ResponsiveHelper.smallStyle(context)
                                .copyWith(
                              color: indicatorColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      const Spacer(),
                      Text(
                        '$count명 대기',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          fontWeight: FontWeight.w700,
                          color: countColor,
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Icon(
                        Icons.chevron_right,
                        size: ResponsiveHelper.iconSize(context, 20),
                        color: AppColors.grey400,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

}
