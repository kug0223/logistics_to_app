import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../../models/core/business_model.dart';
import '../../../models/core/payroll_summary_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/firestore_service.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import 'payroll_worker_detail_screen.dart';
import 'payroll_payment_dashboard_screen.dart';
import 'today_payment_screen.dart';
import '../../../services/payroll_payment_service.dart';
import '../../../widgets/common/gradient_scaffold.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/common/app_search_bar.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../utils/business_picker_helper.dart';

class PayrollOverviewScreen extends StatefulWidget {
  const PayrollOverviewScreen({super.key});

  @override
  State<PayrollOverviewScreen> createState() => _PayrollOverviewScreenState();
}

class _PayrollOverviewScreenState extends State<PayrollOverviewScreen> {
  int _selectedYear = DateTime.now().year;
  String? _businessId;
  bool _isLoading = true;
  String? _loadError;
  List<PayrollSummaryModel> _summaries = [];
  int _todayPaymentCount = 0;

  static const List<String> _monthLabels = [
    '1월', '2월', '3월', '4월', '5월', '6월',
    '7월', '8월', '9월', '10월', '11월', '12월',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;
    if (uid == null) return;

    try {
      List<BusinessModel> businesses;
      // SubAdmin은 adminIds에 없으므로 effectiveBusinessId로 직접 조회
      final effectiveBizId = userProvider.effectiveBusinessId;
      if (userProvider.isSubAdmin && effectiveBizId != null) {
        final biz = await FirestoreService().getBusinessById(effectiveBizId);
        businesses = biz != null ? [biz] : [];
      } else {
        businesses = await FirestoreService().getMyBusiness(uid);
      }
      if (!mounted) return;
      if (businesses.isEmpty) {
        setState(() => _isLoading = false);
        if (!mounted) return;
        ToastHelper.showWarning('사업장을 먼저 등록해주세요');
        Navigator.pop(context);
        return;
      }
      // C-08: N사업장 지원 — BusinessPickerHelper로 선택 (1개면 자동 선택)
      if (!mounted) return;
      final picked = await BusinessPickerHelper.pickFromList(context, businesses);
      if (!mounted) return;
      if (picked == null) {
        setState(() => _isLoading = false);
        Navigator.pop(context);
        return;
      }
      _businessId = picked.id;
      await Future.wait([
        _loadYear(_selectedYear),
        _loadTodayCount(),
      ]);
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _loadError = e.toString(); });
    }
  }

  Future<void> _loadYear(int year) async {
    final bizId = _businessId;
    if (bizId == null) return;
    if (!mounted) return;
    setState(() { _isLoading = true; _loadError = null; });

    try {
      final db = FirebaseFirestore.instance;

      // 1. payroll_summaries Firestore 직접 읽기 (CF 집계 결과)
      final summarySnap = await db
          .collection('payroll_summaries')
          .where('businessId', isEqualTo: bizId)
          .where('year', isEqualTo: year)
          .get();

      final summaryMap = <int, PayrollSummaryModel>{};
      for (final doc in summarySnap.docs) {
        final m = PayrollSummaryModel.tryFromFirestore(doc);
        if (m != null) summaryMap[m.month] = m;
      }

      // 2. pendingCount + notTransferredCount — attendance count() 쿼리 24개 병렬
      //    yearMonth 필드 기반 (인덱스: businessId ASC, yearMonth ASC, wageStatus ASC)
      final pendingResults = await Future.wait(List.generate(12, (i) async {
        final mm = (i + 1).toString().padLeft(2, '0');
        try {
          final snap = await db
              .collection('attendance')
              .where('businessId', isEqualTo: bizId)
              .where('yearMonth', isEqualTo: '$year-$mm')
              .where('wageStatus', whereIn: ['pending', 'calculated'])
              .count()
              .get();
          return snap.count ?? 0;
        } catch (_) { return 0; }
      }));

      final notTransferredResults = await Future.wait(List.generate(12, (i) async {
        final mm = (i + 1).toString().padLeft(2, '0');
        try {
          final snap = await db
              .collection('attendance')
              .where('businessId', isEqualTo: bizId)
              .where('yearMonth', isEqualTo: '$year-$mm')
              .where('wageStatus', isEqualTo: 'confirmed')
              .count()
              .get();
          return snap.count ?? 0;
        } catch (_) { return 0; }
      }));

      // 3. 12개 PayrollSummaryModel 구성
      final summaries = List.generate(12, (i) {
        final month = i + 1;
        final mm    = month.toString().padLeft(2, '0');
        final pCount  = pendingResults[i];
        final ntCount = notTransferredResults[i];
        final existing = summaryMap[month];

        if (existing != null) {
          return PayrollSummaryModel(
            id: existing.id,
            businessId: existing.businessId,
            yearMonth: existing.yearMonth,
            year: existing.year,
            month: existing.month,
            totalPayout: existing.totalPayout,
            confirmedCount: existing.confirmedCount,
            workerCount: existing.workerCount,
            pendingCount: pCount,
            notTransferredCount: ntCount,
            workers: existing.workers,
            updatedAt: existing.updatedAt,
          );
        }

        if (pCount == 0 && ntCount == 0) {
          return PayrollSummaryModel.empty(businessId: bizId, year: year, month: month);
        }

        return PayrollSummaryModel(
          id: '${bizId}_$year-$mm',
          businessId: bizId,
          yearMonth: '$year-$mm',
          year: year,
          month: month,
          totalPayout: 0,
          confirmedCount: 0,
          workerCount: 0,
          pendingCount: pCount,
          notTransferredCount: ntCount,
          workers: {},
          updatedAt: DateTime.now(),
        );
      });

      if (mounted) setState(() => _summaries = summaries);
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTodayCount() async {
    final bizId = _businessId;
    if (bizId == null) return;
    try {
      final count = await PayrollPaymentService().getTodayPaymentCount(
        businessId: bizId,
      );
      if (mounted) setState(() => _todayPaymentCount = count);
    } catch (e) {
      debugPrint('⚠️ 오늘 급여 건수 조회 실패: $e');
    }
  }

  void _onYearChanged(int delta) {
    if (_isLoading) return; // 로드 중 연타 방지 — race condition 예방
    final newYear = _selectedYear + delta;
    if (newYear < 2015 || newYear > DateTime.now().year + 1) return;
    setState(() => _selectedYear = newYear);
    _loadYear(newYear);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GradientScaffold(
      title: '급여 관리',
      showNotificationBell: true,
      onRefresh: () => _loadYear(_selectedYear),
      headerContent: _buildYearSelector(theme),
      body: Column(
        children: [
          if (_isLoading)
            const Expanded(child: LoadingWidget())
          else if (_loadError != null || _summaries.length != 12)
            Expanded(
              child: AppEmptyState(
                icon: Icons.error_outline,
                title: '데이터를 불러오지 못했습니다',
                action: TextButton(
                  onPressed: () => _loadYear(_selectedYear),
                  child: const Text('다시 시도'),
                ),
              ),
            )
          else ...[
            if (_todayPaymentCount > 0 && _businessId != null)
              _TodayPaymentBanner(
                count: _todayPaymentCount,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TodayPaymentScreen(
                        businessId: _businessId!,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  _loadTodayCount();
                },
              ),
            Expanded(child: _buildMonthGrid(theme)),
          ],
        ],
      ),
    );
  }

  Widget _buildYearSelector(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 8),
        0,
        ResponsiveHelper.spacing(context, 8),
        ResponsiveHelper.spacing(context, 12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            tooltip: '이전 연도',
            onPressed: () => _onYearChanged(-1),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 24)),
          Text(
            '$_selectedYear년',
            style: ResponsiveHelper.titleStyle(context).copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 24)),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white),
            tooltip: '다음 연도',
            onPressed: () => _onYearChanged(1),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthGrid(ThemeData theme) {
    final now = DateTime.now();
    return GridView.builder(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: ResponsiveHelper.spacing(context, 12),
        mainAxisSpacing: ResponsiveHelper.spacing(context, 12),
        childAspectRatio: 1.8,
      ),
      itemCount: 12,
      itemBuilder: (context, i) {
        final summary = _summaries[i];
        final isFuture = _selectedYear > now.year ||
            (_selectedYear == now.year && (i + 1) > now.month);
        return _buildMonthCard(theme, summary, isFuture);
      },
    );
  }

  Widget _buildMonthCard(ThemeData theme, PayrollSummaryModel summary, bool isFuture) {
    final isEmpty = summary.isEmpty || isFuture;
    return GestureDetector(
      onTap: isEmpty
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PayrollMonthScreen(summary: summary),
                ),
              ),
      child: Container(
        decoration: BoxDecoration(
          color: isEmpty ? AppColors.grey100 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isEmpty ? AppColors.grey200 : theme.primaryColor.withValues(alpha: 0.2),
          ),
          boxShadow: isEmpty
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  _monthLabels[summary.month - 1],
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: isEmpty ? AppColors.grey400 : theme.primaryColor,
                  ),
                ),
                if (!isEmpty) ...[
                  const Spacer(),
                  Icon(Icons.chevron_right,
                      size: ResponsiveHelper.iconSize(context, 13),
                      color: AppColors.grey400),
                ],
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            if (isEmpty)
              Text(
                isFuture ? '' : '데이터 없음',
                style: ResponsiveHelper.tinyStyle(context).copyWith(
                  color: AppColors.grey400,
                ),
              )
            else ...[
              Text(
                summary.formattedTotalPayout,
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.successDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 2)),
              Text(
                '${summary.workerCount}명 · ${summary.confirmedCount}건',
                style: ResponsiveHelper.tinyStyle(context).copyWith(
                  color: AppColors.grey500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (summary.pendingCount > 0 || summary.notTransferredCount > 0) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  [
                    if (summary.pendingCount > 0) '미확정 ${summary.pendingCount}',
                    if (summary.notTransferredCount > 0) '미이체 ${summary.notTransferredCount}',
                  ].join(' · '),
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                    color: summary.pendingCount > 0
                        ? AppColors.warningDark
                        : AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 월별 근무자 목록 화면
// ─────────────────────────────────────────────────────────────────────────────

enum _SortOrder { amountDesc, amountAsc, nameAsc, workDaysDesc }

class PayrollMonthScreen extends StatefulWidget {
  final PayrollSummaryModel summary;

  const PayrollMonthScreen({super.key, required this.summary});

  @override
  State<PayrollMonthScreen> createState() => _PayrollMonthScreenState();
}

class _PayrollMonthScreenState extends State<PayrollMonthScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  _SortOrder _sortOrder = _SortOrder.amountDesc;
  List<PayrollWorkerSummary> _workers = [];
  bool _workersLoading = true;

  List<PayrollWorkerSummary> get _filteredWorkers {
    final workers = List<PayrollWorkerSummary>.of(_workers);

    switch (_sortOrder) {
      case _SortOrder.amountDesc:
        workers.sort((a, b) => b.totalPayout.compareTo(a.totalPayout));
      case _SortOrder.amountAsc:
        workers.sort((a, b) => a.totalPayout.compareTo(b.totalPayout));
      case _SortOrder.nameAsc:
        workers.sort((a, b) => a.name.compareTo(b.name));
      case _SortOrder.workDaysDesc:
        workers.sort((a, b) => b.workDays.compareTo(a.workDays));
    }

    if (_searchQuery.isEmpty) return workers;
    final q = _searchQuery.toLowerCase();
    return workers.where((w) => w.name.toLowerCase().contains(q)).toList();
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim());
    });
    _loadWorkers();
  }

  Future<void> _loadWorkers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('payroll_summaries')
          .doc(widget.summary.id)
          .collection('workers')
          .get();
      final loaded = snap.docs.map((doc) {
        return PayrollWorkerSummary.tryFromMap(doc.id, doc.data());
      }).whereType<PayrollWorkerSummary>().toList();
      if (!mounted) return;
      setState(() { _workers = loaded; _workersLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _workersLoading = false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredWorkers;

    return GradientScaffold(
      title: '${widget.summary.year}년 ${widget.summary.month}월 급여현황',
      body: Column(
        children: [
          _buildSummaryHeader(context, theme),
          // 검색 바 + 정렬 버튼
          Row(
            children: [
              Expanded(
                child: AppSearchBar(
                  controller: _searchCtrl,
                  hintText: '근무자 이름으로 검색',
                  padding: EdgeInsets.fromLTRB(
                    ResponsiveHelper.spacing(context, 16),
                    ResponsiveHelper.spacing(context, 8),
                    0,
                    ResponsiveHelper.spacing(context, 8),
                  ),
                ),
              ),
              PopupMenuButton<_SortOrder>(
                initialValue: _sortOrder,
                onSelected: (order) => setState(() => _sortOrder = order),
                icon: Icon(
                  Icons.sort,
                  color: _sortOrder == _SortOrder.amountDesc
                      ? AppColors.grey400
                      : theme.primaryColor,
                ),
                itemBuilder: (ctx) => [
                  _sortMenuItem(ctx, _SortOrder.amountDesc, '지급액 높은순', Icons.arrow_downward),
                  _sortMenuItem(ctx, _SortOrder.amountAsc,  '지급액 낮은순', Icons.arrow_upward),
                  _sortMenuItem(ctx, _SortOrder.nameAsc,    '이름순',        Icons.sort_by_alpha),
                  _sortMenuItem(ctx, _SortOrder.workDaysDesc, '근무일수 많은순', Icons.calendar_today),
                ],
              ),
            ],
          ),
          Expanded(
            child: _workersLoading
                ? const LoadingWidget()
                : filtered.isEmpty
                    ? AppEmptyState(
                        icon: _searchQuery.isNotEmpty
                            ? Icons.search_off
                            : Icons.inbox_outlined,
                        title: _searchQuery.isNotEmpty
                            ? '"$_searchQuery" 검색 결과 없음'
                            : '확정된 급여가 없습니다',
                      )
                    : ListView.separated(
                        padding: EdgeInsets.all(
                            ResponsiveHelper.spacing(context, 16)),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                        itemBuilder: (context, i) =>
                            _buildWorkerTile(context, theme, filtered[i]),
                      ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_SortOrder> _sortMenuItem(
    BuildContext ctx,
    _SortOrder value,
    String label,
    IconData icon,
  ) {
    final isSelected = _sortOrder == value;
    final color = isSelected ? Theme.of(ctx).primaryColor : AppColors.grey700;
    return PopupMenuItem<_SortOrder>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(label,
              style: ResponsiveHelper.smallStyle(ctx,
                  color: color,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal)),
          if (isSelected) ...[
            const Spacer(),
            Icon(Icons.check, size: 14, color: color),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(BuildContext context, ThemeData theme) {
    return Container(
      color: theme.primaryColor.withValues(alpha: 0.06),
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 14),
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1행: 총 지급액 히어로 + 지급 현황 버튼
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.payments_outlined,
                    size: 16, color: AppColors.successDark),
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                Text(
                  widget.summary.formattedTotalPayout,
                  style: ResponsiveHelper.titleStyle(context,
                      color: AppColors.successDark),
                ),
              ]),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text('총 지급액',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey700)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PayrollPaymentDashboardScreen(
                      businessId: widget.summary.businessId,
                      year: widget.summary.year,
                      month: widget.summary.month,
                    ),
                  ),
                ),
                icon: Icon(Icons.receipt_long_outlined,
                    size: ResponsiveHelper.iconSize(context, 13),
                    color: theme.primaryColor),
                label: Text('지급 현황',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: theme.primaryColor,
                        fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 4),
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          const Divider(height: 1, color: AppColors.grey200),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          // ── 2행: 근무자 수 | 급여 건수 — 보조
          Row(children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.people_outline,
                  size: 12, color: theme.primaryColor),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text('${widget.summary.workerCount}명',
                  style: ResponsiveHelper.smallStyle(context,
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w600)),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text('근무자 수',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey700)),
            ]),
            Container(
                width: 1, height: 14,
                color: AppColors.grey200,
                margin: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12))),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.receipt_outlined,
                  size: 12, color: theme.primaryColor),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text('${widget.summary.confirmedCount}건',
                  style: ResponsiveHelper.smallStyle(context,
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w600)),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text('급여 건수',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey700)),
            ]),
          ]),
        ],
      ),
    );
  }

  Widget _buildWorkerTile(
    BuildContext context,
    ThemeData theme,
    PayrollWorkerSummary worker,
  ) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PayrollWorkerDetailScreen(
            businessId: widget.summary.businessId,
            workerId: worker.workerId,
            workerName: worker.name,
            year: widget.summary.year,
            month: widget.summary.month,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    worker.name.isNotEmpty ? worker.name : '(이름 없음)',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                  Text(
                    '${worker.workDays}일 근무',
                    style: ResponsiveHelper.tinyStyle(context).copyWith(
                      color: AppColors.grey500,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  FormatHelper.formatWage(worker.totalPayout),
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.successDark,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Icon(Icons.chevron_right,
                    size: ResponsiveHelper.iconSize(context, 16),
                    color: AppColors.grey300),
              ],
            ),
          ],
        ),
      ),
    );
  }

}

// ── 오늘 처리할 송금 배너 ────────────────────────────────────────────

class _TodayPaymentBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _TodayPaymentBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.fromLTRB(ResponsiveHelper.spacing(context, 16), ResponsiveHelper.spacing(context, 12), ResponsiveHelper.spacing(context, 16), 0),
        padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16), vertical: ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: AppColors.warningBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.payment,
                  size: ResponsiveHelper.iconSize(context, 20), color: AppColors.warningDark),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '오늘 처리할 송금',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '지급 예정일이 오늘 이하인 확정 급여 $count건',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.warningDark),
          ],
        ),
      ),
    );
  }
}

