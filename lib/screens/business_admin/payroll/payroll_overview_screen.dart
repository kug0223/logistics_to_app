import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';

import '../../../models/core/business_model.dart';
import '../../../models/core/payroll_summary_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/firestore_service.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import 'payroll_worker_detail_screen.dart';
import 'payroll_payment_dashboard_screen.dart';
import '../../../services/payroll_payment_service.dart';
import '../../../widgets/common/gradient_scaffold.dart';
import '../../../widgets/common/skeleton_widget.dart';
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
  int _todayPaymentCount = 0; // null(조회실패) 시 이전 값 유지

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
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      List<BusinessModel> businesses;
      // SubAdmin은 adminIds에 없으므로 effectiveBusinessId로 직접 조회
      final effectiveBizId = userProvider.effectiveBusinessId;
      if (userProvider.isSubAdmin && effectiveBizId != null) {
        final biz = await FirestoreService().getBusinessById(effectiveBizId);
        businesses = biz != null ? [biz] : [];
      } else {
        final managedIds = userProvider.currentUser?.managedBusinessIds ?? [];
        businesses = await FirestoreService().getBusinessesByIds(managedIds);
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
      // [PERF] 두 CF 병렬 호출 — 순차 최대 90초 → 병렬로 절반 단축
      final psCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetPayrollSummaries',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final attCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetAdminAttendances',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 60)));

      HttpsCallableResult<Map<String, dynamic>>? attResult;
      final results = await Future.wait<Object?>([
        psCallable.call<Map<String, dynamic>>({'businessId': bizId, 'year': year}),
        () async {
          try {
            attResult = await attCallable.call<Map<String, dynamic>>({
              'businessId': bizId,
              'yearMonthGte': '$year-01',
              'yearMonthLte': '$year-12',
            });
          } catch (e) {
            debugPrint('⚠️ 출근 집계 CF 실패: $e');
            if (mounted) ToastHelper.showWarning('출근 집계를 불러오지 못했습니다. 새로고침 해주세요.');
          }
          return null;
        }(),
      ]);
      final psResult = results[0] as HttpsCallableResult<Map<String, dynamic>>;

      // 1. payroll_summaries 파싱
      // [RULE-FIX-CF 2026-07-13] 직접 Firestore → CF 이전, year 서버 필터링으로 전환
      final psItems = (psResult.data['items'] as List<dynamic>?) ?? [];

      final summaryMap = <int, PayrollSummaryModel>{};
      for (final e in psItems.whereType<Map>()) {
        final raw = Map<String, dynamic>.from(e);
        final id = raw.remove('id') as String? ?? '';
        final m = PayrollSummaryModel.tryFromMap(raw, id);
        if (m != null) summaryMap[m.month] = m;
      }

      // 2. pendingCount + notTransferredCount
      //    [CF 이전 2026-07-13] callableGetAdminAttendances (yearMonthGte/Lte)
      //    wageStatus·yearMonth 집계는 클라이언트에서 처리
      final pendingByMonth      = List.filled(12, 0);
      final confirmedByMonth    = List.filled(12, 0); // wageStatus='confirmed' (미이체)
      final transferredByMonth  = List.filled(12, 0); // wageStatus='transferred' (이체완료)
      final totalPayoutByMonth  = List.filled(12, 0);
      final workersByMonth      = List.generate(12, (_) => <String>{});
      for (final raw in (attResult?.data['items'] as List? ?? [])) {
        final data = raw as Map? ?? {};
        final ym = data['yearMonth'] as String?;
        final ws = data['wageStatus'] as String?;
        if (ym == null) continue;
        final parts = ym.split('-');
        if (parts.length != 2) continue;
        final month = int.tryParse(parts[1]);
        if (month == null || month < 1 || month > 12) continue;
        final idx = month - 1;
        if (ws == 'pending' || ws == 'calculated') {
          pendingByMonth[idx]++;
        } else if (ws == 'confirmed' || ws == 'transferred') {
          // payroll_summaries 미생성 시 attendance에서 직접 집계
          // confirmed(미이체) + transferred(이체완료) 모두 월별 인건비에 포함
          if (ws == 'confirmed') {
            confirmedByMonth[idx]++;
          } else {
            transferredByMonth[idx]++;
          }
          final wage = (data['finalWage'] as num?)?.toInt() ?? 0;
          totalPayoutByMonth[idx] += wage;
          final uid = data['userId'] as String?;
          if (uid != null) workersByMonth[idx].add(uid);
        }
      }
      final pendingResults        = pendingByMonth;
      final notTransferredResults = confirmedByMonth;

      // 3. 12개 PayrollSummaryModel 구성
      final summaries = List.generate(12, (i) {
        final month = i + 1;
        final mm    = month.toString().padLeft(2, '0');
        final pCount  = pendingResults[i];
        final ntCount = notTransferredResults[i];
        final tCount  = transferredByMonth[i]; // 이체완료 건수
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

        // payroll_summaries 문서 없음 — transferred 포함해서 빈 달 여부 판단
        if (pCount == 0 && ntCount == 0 && tCount == 0) {
          return PayrollSummaryModel.empty(businessId: bizId, year: year, month: month);
        }

        // attendance에서 직접 집계 (confirmed + transferred 합산)
        return PayrollSummaryModel(
          id: '${bizId}_$year-$mm',
          businessId: bizId,
          yearMonth: '$year-$mm',
          year: year,
          month: month,
          totalPayout: totalPayoutByMonth[i],
          confirmedCount: ntCount + tCount, // 확정+이체완료 합계
          workerCount: workersByMonth[i].length,
          pendingCount: pCount,
          notTransferredCount: ntCount,
          workers: {},
          updatedAt: DateTime.now(),
        );
      });

      if (mounted) setState(() { _summaries = summaries; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _loadError = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadTodayCount() async {
    final bizId = _businessId;
    if (bizId == null) return;
    try {
      final count = await PayrollPaymentService().getTodayPaymentCount(
        businessId: bizId,
      );
      if (mounted && count != null) setState(() => _todayPaymentCount = count);
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
            const Expanded(child: PayrollGridSkeleton())
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
                  final now = DateTime.now();
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PayrollPaymentDashboardScreen(
                        businessId: _businessId!,
                        year: now.year,
                        month: now.month,
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
    final gridPadding = ResponsiveHelper.spacing(context, 16);
    final columnSpacing = ResponsiveHelper.spacing(context, 12);
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - gridPadding * 2 - columnSpacing) / 2;
        // 미이체 행까지 포함한 최대 콘텐츠 높이를 dp로 고정 (기기 폭과 무관하게 일정)
        const itemHeight = 100.0;
        final ratio = itemWidth / itemHeight;
        return GridView.builder(
          padding: EdgeInsets.all(gridPadding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: columnSpacing,
            mainAxisSpacing: ResponsiveHelper.spacing(context, 12),
            childAspectRatio: ratio,
          ),
          itemCount: 12,
          itemBuilder: (context, i) {
            final summary = _summaries[i];
            final isFuture = _selectedYear > now.year ||
                (_selectedYear == now.year && (i + 1) > now.month);
            return _buildMonthCard(theme, summary, isFuture);
          },
        );
      },
    );
  }

  Widget _buildMonthCard(ThemeData theme, PayrollSummaryModel summary, bool isFuture) {
    final isEmpty = summary.isEmpty || isFuture;
    return GestureDetector(
      onTap: isEmpty
          ? null
          : () async {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => PayrollMonthScreen(summary: summary),
                ),
              );
              if (!mounted) return;
              // 이체 처리/취소 등 변경사항이 있을 수 있으므로 항상 리로드
              _loadYear(_selectedYear);
            },
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
              if (isFuture)
                const SizedBox.shrink()
              else
                Text(
                  '데이터 없음',
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
              if (summary.notTransferredCount > 0) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  '미이체 ${summary.notTransferredCount}',
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                    color: AppColors.error,
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
  Timer? _searchDebounce;
  String _searchQuery = '';
  _SortOrder _sortOrder = _SortOrder.amountDesc;
  List<PayrollWorkerSummary> _workers = [];
  bool _workersLoading = true;
  bool _isRepairing = false;

  // 이체 취소 후 notTransferredCount가 변경될 수 있으므로 mutable로 유지
  late PayrollSummaryModel _liveSummary;

  // 필터·정렬 결과 캐시 — _workers/sort/search 변경 시 null로 무효화
  List<PayrollWorkerSummary>? _cachedFiltered;

  List<PayrollWorkerSummary> get _filteredWorkers {
    if (_cachedFiltered != null) return _cachedFiltered!;
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
    if (_searchQuery.isEmpty) {
      return _cachedFiltered = workers;
    }
    final q = _searchQuery.toLowerCase();
    return _cachedFiltered = workers
        .where((w) => w.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _liveSummary = widget.summary;
    _searchCtrl.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        final q = _searchCtrl.text.trim();
        if (q == _searchQuery) return;
        setState(() { _searchQuery = q; _cachedFiltered = null; });
      });
    });
    _loadWorkers();
  }

  /// 지급현황 화면에서 돌아올 때 notTransferredCount 재조회
  Future<void> _refreshSummary() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('payroll_summaries')
          .doc(_liveSummary.id)
          .get();
      if (!snap.exists || !mounted) return;
      final fresh = PayrollSummaryModel.tryFromFirestore(snap);
      if (fresh == null) return;
      setState(() => _liveSummary = fresh);
    } catch (_) {}
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
      setState(() { _workers = loaded; _workersLoading = false; _cachedFiltered = null; });
    } catch (e) {
      // payroll_summaries 문서 미존재 시 workers 서브컬렉션 접근이 PERMISSION_DENIED 됨
      // → 에러 토스트 대신 조용히 실패 후 UI에서 "집계 데이터 복원" 버튼으로 처리
      debugPrint('⚠️ workers 서브컬렉션 로드 실패 (payroll_summaries 미존재 가능): $e');
      if (!mounted) return;
      setState(() => _workersLoading = false);
    }
  }

  // payroll_summaries 문서 누락 시 서버에서 재집계 후 overview 리로드 신호 반환
  Future<void> _repairSummary() async {
    setState(() => _isRepairing = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableRepairPayrollSummaries',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      await callable.call<Map<String, dynamic>>({
        'businessId': widget.summary.businessId,
        'yearMonth': widget.summary.yearMonth,
      });
      if (!mounted) return;
      ToastHelper.showSuccess('집계가 복원되었습니다.');
      Navigator.pop(context, true); // overview에서 true 수신 시 리로드
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('복원 실패: $e');
    } finally {
      if (mounted) setState(() => _isRepairing = false);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
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
              IconButton(
                onPressed: _showSortSheet,
                icon: Icon(
                  Icons.sort,
                  color: _sortOrder == _SortOrder.amountDesc
                      ? AppColors.grey400
                      : theme.primaryColor,
                ),
              ),
            ],
          ),
          Expanded(
            child: _workersLoading
                ? const ApplicationListSkeleton(itemCount: 4)
                : filtered.isEmpty
                    ? (_searchQuery.isEmpty && widget.summary.confirmedCount > 0
                        // payroll_summaries 문서 누락 — 집계 복원 버튼 노출
                        ? Column(
                            children: [
                              // Expanded로 감싸야 AppEmptyState 내 LayoutBuilder.maxHeight가 유한값
                              Expanded(
                                child: AppEmptyState(
                                  icon: Icons.warning_amber_outlined,
                                  title: '집계 데이터가 없습니다',
                                ),
                              ),
                              SafeArea(
                                top: false,
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    ResponsiveHelper.spacing(context, 24),
                                    0,
                                    ResponsiveHelper.spacing(context, 24),
                                    ResponsiveHelper.spacing(context, 24),
                                  ),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: _isRepairing ? null : _repairSummary,
                                      icon: _isRepairing
                                          ? const SizedBox(
                                              width: 14, height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : const Icon(Icons.refresh),
                                      label: Text(_isRepairing ? '복원 중…' : '집계 데이터 복원'),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : AppEmptyState(
                            icon: _searchQuery.isNotEmpty
                                ? Icons.search_off
                                : Icons.inbox_outlined,
                            title: _searchQuery.isNotEmpty
                                ? '"$_searchQuery" 검색 결과 없음'
                                : '확정된 급여가 없습니다',
                          ))
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

  void _showSortSheet() {
    final options = [
      (_SortOrder.amountDesc,   '지급액 높은순',   Icons.arrow_downward),
      (_SortOrder.amountAsc,    '지급액 낮은순',   Icons.arrow_upward),
      (_SortOrder.nameAsc,      '이름순',          Icons.sort_by_alpha),
      (_SortOrder.workDaysDesc, '근무일수 많은순',  Icons.calendar_today),
    ];
    DialogHelper.showSheet(
      context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(context);
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 핸들
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 타이틀 + 닫기 버튼
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
                child: Row(children: [
                  Expanded(
                    child: Text('정렬',
                        style: ResponsiveHelper.subtitleStyle(context)
                            .copyWith(fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: AppColors.grey600),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ]),
              ),
              const Divider(height: 1, color: AppColors.grey100),
              // 옵션 목록
              ...options.map((e) {
                final (order, label, icon) = e;
                final isSelected = _sortOrder == order;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() { _sortOrder = order; _cachedFiltered = null; });
                          Navigator.pop(ctx);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          child: Row(children: [
                            Icon(icon,
                                size: 18,
                                color: isSelected
                                    ? theme.primaryColor
                                    : AppColors.grey500),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(label,
                                  style: ResponsiveHelper.bodyStyle(context,
                                      color: isSelected
                                          ? theme.primaryColor
                                          : AppColors.grey800,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.normal)),
                            ),
                            if (isSelected)
                              Icon(Icons.check_rounded,
                                  size: 18, color: theme.primaryColor),
                          ]),
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.grey100),
                  ],
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryHeader(BuildContext context, ThemeData theme) {
    // CF 트리거(비동기) 갱신 지연으로 confirmedCount < notTransferredCount 가능 → clamp
    final transferredCount = (_liveSummary.confirmedCount - _liveSummary.notTransferredCount).clamp(0, 999999);
    final pendingCount     = _liveSummary.notTransferredCount;
    final hasPending       = pendingCount > 0;

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
                  _liveSummary.formattedTotalPayout,
                  style: ResponsiveHelper.titleStyle(context,
                      color: AppColors.successDark),
                ),
              ]),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text('총 지급액',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey700)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PayrollPaymentDashboardScreen(
                        businessId: widget.summary.businessId,
                        year: widget.summary.year,
                        month: widget.summary.month,
                      ),
                    ),
                  );
                  if (mounted) await _refreshSummary();
                },
                icon: Icon(Icons.receipt_long_outlined,
                    size: ResponsiveHelper.iconSize(context, 13),
                    color: theme.primaryColor),
                label: Text('지급 현황',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: theme.primaryColor,
                        fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 10),
                    vertical: ResponsiveHelper.spacing(context, 5),
                  ),
                  side: BorderSide(color: theme.primaryColor.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          const Divider(height: 1, color: AppColors.grey200),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          // ── 2행: 이체완료 | 미이체 상태
          Row(children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.success, shape: BoxShape.circle),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 5)),
              Text('이체완료',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey500)),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text('$transferredCount건',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.successDark,
                      fontWeight: FontWeight.w700)),
            ]),
            Container(
                width: 1, height: 12,
                color: AppColors.grey200,
                margin: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12))),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: hasPending ? AppColors.warning : AppColors.grey300,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 5)),
              Text('미이체',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey500)),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text('$pendingCount건',
                  style: ResponsiveHelper.smallStyle(context,
                      color: hasPending ? AppColors.warningDark : AppColors.grey400,
                      fontWeight: FontWeight.w700)),
            ]),
            const Spacer(),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.people_outline, size: 12, color: AppColors.grey400),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text('${widget.summary.workerCount}명',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey500,
                      fontWeight: FontWeight.w600)),
              SizedBox(width: ResponsiveHelper.spacing(context, 10)),
              Icon(Icons.receipt_outlined, size: 12, color: AppColors.grey400),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text('${_liveSummary.confirmedCount}건',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey500,
                      fontWeight: FontWeight.w600)),
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
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                4 + ResponsiveHelper.spacing(context, 14),
                ResponsiveHelper.spacing(context, 13),
                ResponsiveHelper.spacing(context, 14),
                ResponsiveHelper.spacing(context, 13),
              ),
              child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              worker.name.isNotEmpty ? worker.name : '(이름 없음)',
                              style: ResponsiveHelper.bodyStyle(context)
                                  .copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                            Text(
                              '${worker.workDays}일 근무',
                              style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.grey500),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
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
            Positioned(
              top: 0, left: 0, bottom: 0,
              child: Container(
                width: 4,
                color: theme.primaryColor.withValues(alpha: 0.6),
              ),
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

