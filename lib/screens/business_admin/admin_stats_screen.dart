import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../services/admin_stats_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import 'admin_month_detail_screen.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/toast_helper.dart';

class AdminStatsScreen extends StatefulWidget {
  final List<String> businessIds;

  const AdminStatsScreen({super.key, required this.businessIds});

  @override
  State<AdminStatsScreen> createState() => _AdminStatsScreenState();
}

class _AdminStatsScreenState extends State<AdminStatsScreen> {
  final _service = AdminStatsService();

  late int _selectedYear;
  String? _filterBusinessId; // null = 전체
  bool _isLoading = true;
  bool _isFetching = false;
  final _touchedBarIndex = ValueNotifier<int>(-1);

  AnnualStatsData? _data;
  List<BusinessOption> _businesses = [];
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
    _init();
  }

  @override
  void dispose() {
    _touchedBarIndex.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    // 사업장 목록과 통계를 동시에 요청 — 서로 독립적
    final bizFuture = _service.getBusinessOptions(widget.businessIds);
    _loadStats(); // 내부 에러 처리 있음, await 없이 병렬 시작
    try {
      final bizOptions = await bizFuture;
      if (!mounted) return;
      setState(() => _businesses = bizOptions);
    } catch (e) {
      debugPrint('⚠️ 사업장 목록 로드 실패: $e');
    }
  }

  Future<void> _loadStats() async {
    if (_isFetching) return;  // 중복 실행만 차단 (_isLoading 초기값=true 문제 해결)
    if (!mounted) return;
    setState(() { _isLoading = true; _isFetching = true; });
    try {
      final data = await _service.getAnnualStats(
        businessIds: widget.businessIds,
        filterBusinessId: _filterBusinessId,
        year: _selectedYear,
      );
      if (mounted) setState(() { _data = data; _hasError = false; });
    } catch (e) {
      debugPrint('❌ 연간 통계 로드 실패: $e');
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() { _isLoading = false; _isFetching = false; });
    }
  }

  void _showBizPicker() {
    DialogHelper.showSheet(
      context,
      builder: (ctx) {
        final allItems = [null, ..._businesses];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들바
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            // 헤더
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '사업장 선택',
                      style: ResponsiveHelper.subtitleStyle(ctx)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                    visualDensity: VisualDensity.compact,
                    color: AppColors.grey600,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.grey200),
            // 목록
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: allItems.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.grey100),
                itemBuilder: (_, i) {
                  final biz = allItems[i];
                  final isSelected = biz == null
                      ? _filterBusinessId == null
                      : _filterBusinessId == biz.id;
                  return InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      if (!mounted) return;
                      setState(() => _filterBusinessId = biz?.id);
                      _loadStats();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 13),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              biz?.name ?? '전체 사업장',
                              style: ResponsiveHelper.bodyStyle(ctx,
                                      color: isSelected
                                          ? Theme.of(ctx).primaryColor
                                          : AppColors.textPrimary)
                                  .copyWith(
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal),
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check,
                                color: Theme.of(ctx).primaryColor, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  void _openMonthDetail(int month) {
    if (!mounted || widget.businessIds.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminMonthDetailScreen(
          businessIds: widget.businessIds,
          filterBusinessId: _filterBusinessId,
          year: _selectedYear,
          month: month,
          businesses: _businesses,
        ),
      ),
    );
  }

  // ─── 빌드 ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GradientScaffold(
      title: '통계',
      showNotificationBell: true,
      onRefresh: _loadStats,
      headerContent: _buildHeader(theme),
      body: _isLoading
          ? const LoadingWidget(message: '통계 불러오는 중...')
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: _buildContent(),
            ),
    );
  }

  // ─── 헤더 (사업장 선택 + 연도) ───────────────────────────────

  Widget _buildHeader(ThemeData theme) {
    final now = DateTime.now();
    return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 사업장 선택 — 1개면 숨김, 2개 이상이면 드롭다운
          if (_businesses.length > 1)
            Padding(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 8),
                ResponsiveHelper.spacing(context, 16),
                0,
              ),
              child: GestureDetector(
                onTap: () => _showBizPicker(),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 14),
                    vertical: ResponsiveHelper.spacing(context, 9),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.business_outlined,
                          color: Colors.white,
                          size: ResponsiveHelper.iconSize(context, 16)),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Text(
                        // _businesses.isEmpty 체크가 단락 평가되므로
                        // orElse의 _businesses.first는 리스트가 비어있을 때 도달 불가 — 안전
                        _filterBusinessId == null || _businesses.isEmpty
                            ? '전체 사업장'
                            : _businesses
                                .firstWhere((b) => b.id == _filterBusinessId,
                                    orElse: () => _businesses.first)
                                .name,
                        style: ResponsiveHelper.smallStyle(context,
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.white.withValues(alpha: 0.8),
                          size: ResponsiveHelper.iconSize(context, 18)),
                    ],
                  ),
                ),
              ),
            ),

          // 연도 선택
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ArrowBtn(
                  icon: Icons.chevron_left,
                  onTap: _isFetching ? null : () {
                    setState(() => _selectedYear--);
                    _loadStats();
                  },
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 20)),
                  child: Text(
                    '$_selectedYear년',
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                _ArrowBtn(
                  icon: Icons.chevron_right,
                  onTap: (_isFetching || _selectedYear >= now.year)
                      ? null
                      : () {
                          setState(() => _selectedYear++);
                          _loadStats();
                        },
                ),
              ],
            ),
          ),
        ],
    );
  }

  // ─── 메인 콘텐츠 ─────────────────────────────────────────────

  Widget _buildContent() {
    final data = _data;
    if (data == null) return _buildEmpty();

    final hasAnyData = data.totalWorkCount > 0;

    return ListView(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      children: [
        // 데이터 없음 안내
        if (!hasAnyData) ...[
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
            decoration: BoxDecoration(
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    color: AppColors.grey500,
                    size: ResponsiveHelper.iconSize(context, 18)),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text('$_selectedYear년 근태 데이터가 없습니다',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.grey600)),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
        ],

        // KPI
        _buildKpiSection(data),
        SizedBox(height: ResponsiveHelper.spacing(context, 14)),

        // 예외 알림
        if (data.exceptions.isNotEmpty) ...[
          _buildExceptionSection(data),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
        ],

        // 업무별 인건비 (스크롤 없이 바로 보이도록 차트 위)
        _buildWorkTypeWageSection(data),
        SizedBox(height: ResponsiveHelper.spacing(context, 14)),

        // 월별 차트
        _buildAnnualChart(data),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),

        if (hasAnyData)
          Center(
            child: Text(
              '막대를 탭하면 해당 월 상세 보기',
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.grey400),
            ),
          ),
        SizedBox(height: ResponsiveHelper.spacing(context, 14)),

        // 신뢰점수 분포
        if (data.workerTrustScores.isNotEmpty) ...[
          _buildTrustScoreSection(data),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
        ],

        SizedBox(height: ResponsiveHelper.spacing(context, 32)),
      ],
    );
  }

  // ─── KPI: Hero + 보조 그리드 ────────────────────────────────

  Widget _buildKpiSection(AnnualStatsData data) {
    final theme = Theme.of(context);
    final hasPrevWage = data.prevYearTotalWage > 0;
    final hasPrevCount = data.prevYearTotalWorkCount > 0;
    final hasPrevAtt = data.prevYearAttendanceRate > 0;
    final hasPrevNoShow = data.prevYearNoShowRate > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Hero: 총 인건비 (관리자가 가장 먼저 보는 숫자)
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            ResponsiveHelper.spacing(context, 18),
            ResponsiveHelper.spacing(context, 16),
            ResponsiveHelper.spacing(context, 18),
            ResponsiveHelper.spacing(context, 16),
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('총 인건비',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.grey500)),
                const Spacer(),
                Text(
                  '$_selectedYear년 전체',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey400),
                ),
                if (hasPrevWage && data.wageDeltaPct != 0) ...[
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  _DeltaBadge(delta: data.wageDeltaPct),
                ],
              ]),
              SizedBox(height: ResponsiveHelper.spacing(context, 6)),
              Text(
                _fmtWage(data.totalWage),
                style: TextStyle(
                  fontSize: ResponsiveHelper.titleStyle(context).fontSize! * 1.6,
                  fontWeight: FontWeight.w800,
                  color: theme.primaryColor,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 8)),

        // ── 보조 그리드: 근무건수 · 출근율 · 노쇼율 · 재고용
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _StatCell(
                  label: '근무 건수',
                  value: '${data.totalWorkCount}건',
                  valueColor: AppColors.grey900,
                  delta: hasPrevCount ? data.workCountDeltaPct : null,
                )),
                _VLine(),
                Expanded(child: _StatCell(
                  label: '출근율',
                  value: data.attendanceRate == 0
                      ? '-' : '${data.attendanceRate.toStringAsFixed(1)}%',
                  valueColor: AppColors.success,
                  delta: hasPrevAtt
                      ? data.attendanceRate - data.prevYearAttendanceRate
                      : null,
                )),
                _VLine(),
                Expanded(child: _StatCell(
                  label: '노쇼율',
                  value: data.noShowRate == 0
                      ? '-' : '${data.noShowRate.toStringAsFixed(1)}%',
                  valueColor: data.noShowRate > 0 ? AppColors.error : AppColors.grey400,
                  delta: hasPrevNoShow
                      ? -(data.noShowRate - data.prevYearNoShowRate)
                      : null,
                )),
                _VLine(),
                Expanded(child: _StatCell(
                  label: '재고용률',
                  value: data.rehireRate == 0
                      ? '-' : '${data.rehireRate.toStringAsFixed(0)}%',
                  valueColor: AppColors.amber,
                  subValue: data.avgRating > 0
                      ? '★ ${data.avgRating.toStringAsFixed(1)}' : null,
                )),
            ]),
          ),
        ),
      ],
    );
  }

  // ─── 예외 알림 ────────────────────────────────────────────

  Widget _buildExceptionSection(AnnualStatsData data) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: AppColors.error,
                  size: ResponsiveHelper.iconSize(context, 16)),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                '${data.exceptionMonth}월 주의 직원',
                style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: AppColors.error, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          ...data.exceptions
              .where((e) =>
                  e.userName.isNotEmpty && e.userName != '알 수 없음')
              .take(3)
              .map((e) => Padding(
                padding: EdgeInsets.only(
                    bottom: ResponsiveHelper.spacing(context, 4)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.userName,
                        style: ResponsiveHelper.smallStyle(context),
                      ),
                    ),
                    if (e.lateCount > 0)
                      _ExBadge(
                          label: '지각 ${e.lateCount}회',
                          color: AppColors.warning),
                    if (e.absentCount > 0) ...[
                      SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                      _ExBadge(
                          label: '결근 ${e.absentCount}회',
                          color: AppColors.error),
                    ],
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ─── 연간 바 차트 ────────────────────────────────────────

  Widget _buildAnnualChart(AnnualStatsData data) {
    final theme = Theme.of(context);
    final trends = data.monthlyTrends;
    final maxWage = trends.map((t) => t.totalWage).fold(0, (a, b) => a > b ? a : b);

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '월별 인건비',
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              // 범례
              _LegendDot(color: theme.primaryColor, label: '이달'),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _LegendDot(
                  color: theme.primaryColor.withValues(alpha: 0.3),
                  label: '기타'),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ValueListenableBuilder<int>(
            valueListenable: _touchedBarIndex,
            builder: (context, touchedIdx, _) => SizedBox(
              height: 180,
              child: maxWage == 0
                  ? Center(
                      child: Text('데이터 없음',
                          style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.grey400)),
                    )
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: maxWage * 1.3,
                        barTouchData: BarTouchData(
                          touchCallback: (event, response) {
                            final spot = response?.spot;
                            if (event is FlTapUpEvent && spot != null) {
                              final idx = spot.touchedBarGroupIndex;
                              _touchedBarIndex.value = idx;
                              _openMonthDetail(idx + 1);
                            } else {
                              _touchedBarIndex.value = -1;
                            }
                          },
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, gi, rod, ri) {
                              final t = trends[gi];
                              if (t.totalWage == 0) return null;
                              return BarTooltipItem(
                                '${t.month}월\n${_fmtWage(t.totalWage)}\n${t.workCount}건',
                                ResponsiveHelper.tinyStyle(context)
                                    .copyWith(color: Colors.white),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 22,
                              getTitlesWidget: (v, _) {
                                final idx = v.toInt();
                                if (idx < 0 || idx >= 12) {
                                  return const SizedBox();
                                }
                                final m = idx + 1;
                                final isCurrent =
                                    m == DateTime.now().month &&
                                        _selectedYear == DateTime.now().year;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '$m',
                                    style: ResponsiveHelper.tinyStyle(context)
                                        .copyWith(
                                      color: isCurrent
                                          ? theme.primaryColor
                                          : AppColors.grey400,
                                      fontWeight: isCurrent
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        gridData: FlGridData(
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => const FlLine(
                              color: AppColors.grey100, strokeWidth: 1),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: trends.asMap().entries.map((e) {
                          final isCurrent =
                              e.value.month == DateTime.now().month &&
                                  _selectedYear == DateTime.now().year;
                          final isTouched = touchedIdx == e.key;
                          return BarChartGroupData(
                            x: e.key,
                            barRods: [
                              BarChartRodData(
                                toY: e.value.totalWage.toDouble(),
                                color: isTouched
                                    ? theme.primaryColor
                                        .withValues(alpha: 0.85)
                                    : isCurrent
                                        ? theme.primaryColor
                                        : theme.primaryColor
                                            .withValues(alpha: 0.3),
                                width: 18,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ),
          // 근무 건수 서브 행
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: trends.map((t) {
              final isCurrent = t.month == DateTime.now().month &&
                  _selectedYear == DateTime.now().year;
              return Text(
                t.workCount > 0 ? '${t.workCount}' : '',
                textAlign: TextAlign.center,
                style: ResponsiveHelper.tinyStyle(context).copyWith(
                  color: isCurrent
                      ? theme.primaryColor
                      : AppColors.grey400,
                  fontWeight: isCurrent
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkTypeWageSection(AnnualStatsData data) {
    final map = data.wageByWorkType;
    final filtered = map.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (filtered.isEmpty) return const SizedBox.shrink();

    final maxWage = filtered.fold(0, (a, b) => a > b.value ? a : b.value);
    final colors = [AppColors.info, AppColors.success, AppColors.warning, AppColors.purple, AppColors.error];

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('업무별 인건비',
              style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold)),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
          ...filtered.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            final ratio = maxWage == 0 ? 0.0 : e.value / maxWage;
            final color = colors[i % colors.length];
            return Padding(
              padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(e.key,
                          style: ResponsiveHelper.smallStyle(context),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(_fmtWage(e.value),
                        style: ResponsiveHelper.smallStyle(context, color: color)
                            .copyWith(fontWeight: FontWeight.w600)),
                  ]),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: AppColors.grey100,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTrustScoreSection(AnnualStatsData data) {
    final scores = data.workerTrustScores.values.toList();
    if (scores.isEmpty) return const SizedBox.shrink();

    // 등급별 인원 집계
    int excellent = 0, good = 0, average = 0, caution = 0, warning = 0;
    for (final s in scores) {
      if (s >= 90) { excellent++; }
      else if (s >= 70) { good++; }
      else if (s >= 50) { average++; }
      else if (s >= 30) { caution++; }
      else { warning++; }
    }
    final total = scores.length;
    final avgScore = total == 0 ? 0 : (scores.reduce((a, b) => a + b) / total).round();

    final grades = [
      ('최우수', excellent, AppColors.success, '90~100'),
      ('우수',   good,      AppColors.info,    '70~89'),
      ('보통',   average,   AppColors.warning,  '50~69'),
      ('주의',   caution,   AppColors.error,    '30~49'),
      ('경고',   warning,   AppColors.grey500,  '0~29'),
    ].where((g) => g.$2 > 0).toList();

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('근로자 신뢰점수 분포',
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('평균 $avgScore점 · $total명',
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.grey500)),
          ]),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
          ...grades.map((g) {
            final ratio = total == 0 ? 0.0 : g.$2 / total;
            return Padding(
              padding: EdgeInsets.only(
                  bottom: ResponsiveHelper.spacing(context, 10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    SizedBox(
                      width: ResponsiveHelper.spacing(context, 48),
                      child: Text(g.$1,
                          style: ResponsiveHelper.smallStyle(context)),
                    ),
                    Text(g.$4,
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.grey400)),
                    const Spacer(),
                    Text('${g.$2}명 (${(ratio * 100).round()}%)',
                        style: ResponsiveHelper.smallStyle(context,
                                color: g.$3)
                            .copyWith(fontWeight: FontWeight.w600)),
                  ]),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: AppColors.grey100,
                      valueColor: AlwaysStoppedAnimation<Color>(g.$3),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    if (_hasError) {
      return AppEmptyState(
        icon: Icons.cloud_off_outlined,
        title: '통계를 불러오지 못했습니다',
        subtitle: '네트워크 상태를 확인 후 당겨서 새로고침하세요',
      );
    }
    return AppEmptyState(
      icon: Icons.bar_chart_outlined,
      title: '$_selectedYear년 데이터가 없습니다',
    );
  }

  // ─── 유틸 ─────────────────────────────────────────────────

  String _fmtWage(int wage) {
    if (wage == 0) return '-';
    if (wage >= 100000000) return '${(wage / 100000000).toStringAsFixed(1)}억';
    if (wage >= 10000000) return '${(wage / 10000000).toStringAsFixed(1)}천만';
    if (wage >= 1000000) return '${wage ~/ 10000}만';
    return '${wage ~/ 1000}천';
  }
}

// ─── 서브 위젯 ────────────────────────────────────────────────

class _ArrowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _ArrowBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
        decoration: BoxDecoration(
          color: Colors.white
              .withValues(alpha: onTap == null ? 0.05 : 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            color:
                Colors.white.withValues(alpha: onTap == null ? 0.3 : 1.0),
            size: ResponsiveHelper.iconSize(context, 20)),
      ),
    );
  }
}

// ── 보조 통계 셀 (라벨 위, 숫자 아래) ──────────────────────────
class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final double? delta;
  final String? subValue;

  const _StatCell({
    required this.label,
    required this.value,
    required this.valueColor,
    this.delta,
    this.subValue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 라벨 먼저 (작게, 회색)
          Text(label,
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.grey400)),
          SizedBox(height: ResponsiveHelper.spacing(context, 5)),
          // 숫자가 주인공 (크게, 컬러)
          Text(value,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.w800, color: valueColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          // 별점 등 부가정보
          if (subValue != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 2)),
            Text(subValue!,
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.amber,
                    fontWeight: FontWeight.w600)),
          ],
          // delta (있을 때만)
          if (delta != null && delta != 0) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 3)),
            _DeltaBadge(delta: delta!),
          ],
        ],
      ),
    );
  }
}

// ── 구분선 ───────────────────────────────────────────────────────
class _VLine extends StatelessWidget {
  const _VLine();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, color: AppColors.grey100);
}

class _DeltaBadge extends StatelessWidget {
  final double delta;
  const _DeltaBadge({required this.delta});

  @override
  Widget build(BuildContext context) {
    final isPos = delta > 0;
    final color = isPos ? AppColors.success : AppColors.error;
    final icon = isPos ? Icons.arrow_upward : Icons.arrow_downward;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 5),
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          Text(
            '${delta.abs().toStringAsFixed(1)}%',
            style: ResponsiveHelper.tinyStyle(context)
                .copyWith(color: color, fontWeight: FontWeight.bold, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _ExBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _ExBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: ResponsiveHelper.tinyStyle(context)
              .copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        Text(label,
            style: ResponsiveHelper.tinyStyle(context,
                color: AppColors.grey500)),
      ],
    );
  }
}

// ─── 진입점 ──────────────────────────────────────────────────

Future<void> pushAdminStatsScreen(BuildContext context) async {
  final userProvider = context.read<UserProvider>();
  final user = userProvider.currentUser;
  if (user == null) {
    ToastHelper.showWarning('로그인 정보를 불러올 수 없습니다');
    return;
  }
  final ids = user.managedBusinessIds;
  // 다중 사업장 관리자
  if (ids.isNotEmpty) {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => AdminStatsScreen(businessIds: ids)));
    return;
  }
  // 단일 사업장: BUSINESS_ADMIN은 businessId, SubAdmin은 subAdminOf → effectiveBusinessId로 통합
  final effectiveBizId = userProvider.effectiveBusinessId;
  if (effectiveBizId != null) {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => AdminStatsScreen(businessIds: [effectiveBizId])));
    return;
  }
  ToastHelper.showWarning('등록된 사업장이 없습니다');
}
