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
    final todayOnly = DateTime(today.year, today.month, today.day);
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
    final monthStr = DateFormat('yyyy년 M월').format(_currentMonth);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDialogSize.borderRadius),
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppDialogSize.insetH,
        vertical: AppDialogSize.insetV,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
        ),
        child: Column(
          children: [
            _buildHeader(theme, monthStr),
            if (!isLoading) _buildSummaryCard(),
            Expanded(
              child: isLoading
                  ? const LoadingWidget(message: '승인 대기 현황 조회 중...')
                  : _pendingCountByDate.isEmpty
                      ? _buildEmptyState()
                      : _buildContent(theme),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, String monthStr) {
    final hasBizFilter = widget.businesses.length > 1;

    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.warning,
            AppColors.warning.withValues(alpha: 0.80),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppDialogSize.borderRadius),
          topRight: Radius.circular(AppDialogSize.borderRadius),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.assignment_late_outlined,
                  color: Colors.white,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '승인 대기 현황',
                      style: ResponsiveHelper.titleStyle(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '날짜별 미승인 지원자 분포',
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: '닫기',
                icon: Icon(
                  Icons.close,
                  color: Colors.white,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ),
            ],
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          if (hasBizFilter) ...[
            _buildBusinessFilter(),
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          ],

          // 월 선택
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: _previousMonth,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
                    child: Icon(Icons.chevron_left,
                        color: AppColors.warning,
                        size: ResponsiveHelper.iconSize(context, 24)),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  monthStr,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.warning,
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                InkWell(
                  onTap: _nextMonth,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
                    child: Icon(Icons.chevron_right,
                        color: AppColors.warning,
                        size: ResponsiveHelper.iconSize(context, 24)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessFilter() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedBusinessId,
          dropdownColor: Colors.white,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          iconEnabledColor: Colors.white,
          isExpanded: true,
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('전체 사업장',
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(color: AppColors.grey800)),
            ),
            ...widget.businesses.map((b) => DropdownMenuItem<String?>(
                  value: b.id,
                  child: Text(
                    b.name,
                    style: ResponsiveHelper.bodyStyle(context)
                        .copyWith(color: AppColors.grey800),
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
    final todayOnly = DateTime(today.year, today.month, today.day);

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

        final dateStr = DateFormat('M/d(E)', 'ko_KR').format(date);

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

  Widget _buildBottomBar() {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppDialogSize.borderRadius),
          bottomRight: Radius.circular(AppDialogSize.borderRadius),
        ),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.grey200,
            foregroundColor: AppColors.grey700,
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 14),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: Text(
            '닫기',
            style: ResponsiveHelper.bodyStyle(context)
                .copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
