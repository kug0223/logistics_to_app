import 'package:flutter/material.dart';

import '../../models/core/employment_contract_model.dart';
import '../../services/contract_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_search_bar.dart';
import '../../widgets/common/app_tab_label.dart';

class AdminContractManagementScreen extends StatefulWidget {
  final String businessId;
  final String? businessName;

  const AdminContractManagementScreen({
    super.key,
    required this.businessId,
    this.businessName,
  });

  @override
  State<AdminContractManagementScreen> createState() =>
      _AdminContractManagementScreenState();
}

class _AdminContractManagementScreenState
    extends State<AdminContractManagementScreen>
    with SingleTickerProviderStateMixin {

  final _contractService = ContractService();
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();

  // 상태 탭 순서 (null = 전체)
  static const _tabs = <ContractStatus?>[
    null,
    ContractStatus.pendingEmployer,
    ContractStatus.pendingWorker,
    ContractStatus.completed,
    ContractStatus.voided,
  ];
  static const _tabLabels = ['전체', '사업주 대기', '근무자 대기', '완료', '무효'];

  late final TabController _tabCtrl;

  List<EmploymentContractModel> _items = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  bool _isVoidingContract = false;
  bool _isRetrying = false;
  String? _lastDoc;

  String _searchQuery = '';

  ContractStatus? get _currentFilter => _tabs[_tabCtrl.index];

  List<EmploymentContractModel> get _filteredItems {
    if (_searchQuery.isEmpty) return _items;
    final q = _searchQuery.toLowerCase();
    return _items
        .where((c) => c.snapshot.workerName.toLowerCase().contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        _searchCtrl.clear();
        _refresh();
      }
    });
    _scrollCtrl.addListener(_onScroll);
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim());
    });
    _load();
  }

  @override
  void dispose() {
    // controller.dispose()가 내부적으로 모든 addListener 리스너를 제거함 — removeListener 별도 불필요
    _tabCtrl.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 200 &&
        _hasMore &&
        !_isLoadingMore) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _items = []; _lastDoc = null; });
    try {
      final result = await _contractService.getByBusinessPaged(
        widget.businessId,
        statusFilter: _currentFilter,
      );
      if (!mounted) return;
      setState(() {
        _items   = result.items;
        _lastDoc = result.lastDocId;
        _hasMore = result.hasMore;
      });
    } catch (e) {
      debugPrint('❌ 계약 목록 로드 실패: $e');
      if (mounted) ToastHelper.showError('계약서 목록을 불러오는데 실패했습니다.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refresh() => _load();

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _lastDoc == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await _contractService.getByBusinessPaged(
        widget.businessId,
        statusFilter: _currentFilter,
        startAfterId: _lastDoc,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _lastDoc = result.lastDocId;
        _hasMore = result.hasMore;
      });
    } catch (e) {
      debugPrint('❌ 계약 목록 추가 로드 실패: $e');
      if (mounted) ToastHelper.showError('계약서를 더 불러오는데 실패했습니다.');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _openContract(EmploymentContractModel c) async {
    final nav = Navigator.of(context);
    await nav.push(MaterialPageRoute(
      builder: (_) => ContractSignScreen(contract: c, role: 'employer'),
    ));
    if (!mounted) return;
    await _refresh(); // 서명 후 목록 갱신
  }

  Future<void> _voidContract(EmploymentContractModel c) async {
    if (_isVoidingContract) return;
    setState(() => _isVoidingContract = true);
    try {
      final ok = await DialogHelper.showConfirm(
        context,
        title: '계약서 무효화',
        message: '${c.snapshot.workerName}님의 계약서를 무효 처리하시겠습니까?\n'
            '무효 처리 후에는 되돌릴 수 없습니다.',
        confirmText: '무효 처리',
        cancelText: '취소',
        confirmColor: AppColors.error,
        icon: Icons.block_outlined,
        iconColor: AppColors.error,
      );
      if (ok != true || !mounted) return;
      await _contractService.voidContract(c.id);
      if (!mounted) return;
      ToastHelper.showSuccess('계약서가 무효 처리되었습니다');
      _refresh();
    } catch (e) {
      if (!mounted) return;
      // voidContract는 app 취소 실패 시에도 계약서 voided는 완료됨 — 경고 토스트 후 목록 갱신
      ToastHelper.showWarning('무효 처리됐으나 일부 지원서 취소에 실패했습니다. 카드에서 재처리하세요.');
      _refresh();
    } finally {
      if (mounted) setState(() => _isVoidingContract = false);
    }
  }

  /// voidFailedAppIds 재처리 — 실패한 application 취소를 다시 시도
  Future<void> _retryVoidFailedApps(EmploymentContractModel c) async {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);
    try {
      await _contractService.retryVoidFailedApps(c);
      if (!mounted) return;
      ToastHelper.showSuccess('지원서 취소 재처리가 완료되었습니다');
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('재처리 실패: $e');
      _refresh();
    } finally {
      if (mounted) setState(() => _isRetrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '계약서 관리',
      onRefresh: _refresh,
      headerBottom: TabBar(
        controller: _tabCtrl,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
        indicatorColor: Colors.white,
        indicatorWeight: 2.5,
        dividerColor: Colors.transparent,
        tabs: _tabLabels.map((l) => Tab(child: AppTabLabel(label: l))).toList(),
      ),
      body: _isLoading
          ? const LoadingWidget(message: '계약서 목록을 불러오는 중...')
          : Column(
              children: [
                // 검색 바
                AppSearchBar(
                  controller: _searchCtrl,
                  hintText: '근무자 이름으로 검색',
                ),
                // 검색 중 hasMore 안내
                if (_searchQuery.isNotEmpty && _hasMore)
                  Container(
                    width: double.infinity,
                    color: AppColors.warningBg,
                    padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 14),
                        vertical: ResponsiveHelper.spacing(context, 6)),
                    child: Text(
                      '로드되지 않은 계약서가 있습니다. 아래로 스크롤해 더 불러오세요.',
                      style: ResponsiveHelper.tinyStyle(context, color: AppColors.warningDark),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: _filteredItems.isEmpty
                        ? _buildEmpty(context)
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: ResponsiveHelper.listPadding(context),
                            itemCount: _filteredItems.length +
                                (_isLoadingMore ? 1 : 0),
                            itemBuilder: (ctx, i) {
                              if (i == _filteredItems.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: LoadingWidget(),
                                );
                              }
                              final item = _filteredItems[i];
                              return _ContractCard(
                                contract: item,
                                onTap: () => _openContract(item),
                                onVoid: (item.status != ContractStatus.voided &&
                                        item.status != ContractStatus.completed)
                                    ? () => _voidContract(item)
                                    : null,
                                onRetry: item.hasVoidFailedApps
                                    ? () => _retryVoidFailedApps(item)
                                    : null,
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final isSearching = _searchQuery.isNotEmpty;
    return AppEmptyState(
      icon: isSearching ? Icons.search_off : Icons.description_outlined,
      title: isSearching ? '"$_searchQuery" 검색 결과 없음' : '계약서가 없습니다',
      subtitle: isSearching
          ? '다른 이름으로 검색하거나 스크롤해 더 불러오세요'
          : (_currentFilter == null
              ? '지원자 확정 후 계약서를 생성하세요'
              : '해당 상태의 계약서가 없습니다'),
    );
  }
}

// ─── 계약서 카드 ──────────────────────────────────────────────────

class _ContractCard extends StatelessWidget {
  final EmploymentContractModel contract;
  final VoidCallback onTap;
  final VoidCallback? onVoid;
  final VoidCallback? onRetry;

  const _ContractCard({
    required this.contract,
    required this.onTap,
    this.onVoid,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(contract.status);
    final statusBg = _statusBg(contract.status);

    return Container(
      margin: EdgeInsets.only(
          bottom: ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 14),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더: 이름 + 상태 배지
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.person_outline,
                          color: theme.primaryColor,
                          size: ResponsiveHelper.iconSize(context, 17)),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            contract.snapshot.workerName,
                            style: ResponsiveHelper.bodyStyle(context)
                                .copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(
                              height: ResponsiveHelper.spacing(context, 2)),
                          Text(
                            contract.snapshot.workType,
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.grey500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (onVoid != null &&
                        contract.status != ContractStatus.voided) ...[
                      SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                      TextButton.icon(
                        onPressed: onVoid,
                        icon: Icon(Icons.block_outlined,
                            size: ResponsiveHelper.iconSize(context, 13),
                            color: AppColors.errorMedium),
                        label: Text('무효',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.errorMedium)),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 6),
                            vertical: ResponsiveHelper.spacing(context, 2),
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    // 상태 배지
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 8),
                        vertical: ResponsiveHelper.spacing(context, 3),
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        contract.status.label,
                        style: ResponsiveHelper.tinyStyle(context)
                            .copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                const Divider(height: 1, color: AppColors.grey100),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                // 계약 정보 행
                Wrap(
                  spacing: ResponsiveHelper.spacing(context, 16),
                  runSpacing: ResponsiveHelper.spacing(context, 6),
                  children: [
                    _InfoChip(
                      icon: Icons.calendar_today_outlined,
                      text: _dateLabel(contract),
                    ),
                    _InfoChip(
                      icon: Icons.attach_money,
                      text: '${FormatHelper.formatNumber(contract.snapshot.wage)}원'
                          ' / ${contract.snapshot.wageType == 'hourly' ? '시급' : '일급'}',
                    ),
                    _InfoChip(
                      icon: contract.isLongTerm
                          ? Icons.date_range_outlined
                          : Icons.today_outlined,
                      text: contract.isLongTerm ? '장기 계약' : '단기 계약',
                    ),
                  ],
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                // 서명 진행 인디케이터
                _SignProgressBar(contract: contract),

                // [V-001] voidFailedAppIds 경고 배너 — 앱 취소 실패 시 재처리 유도
                if (contract.hasVoidFailedApps) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 10),
                      vertical: ResponsiveHelper.spacing(context, 8),
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warningBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: ResponsiveHelper.iconSize(context, 16),
                            color: AppColors.warningDark),
                        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                        Expanded(
                          child: Text(
                            '지원서 ${contract.voidFailedAppIds.length}건 취소 실패 — 재처리 필요',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.warningDark),
                          ),
                        ),
                        if (onRetry != null)
                          TextButton(
                            onPressed: onRetry,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(context, 8),
                                vertical: ResponsiveHelper.spacing(context, 2),
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text('재처리',
                                style: ResponsiveHelper.tinyStyle(context,
                                    color: AppColors.warningDark)
                                    .copyWith(fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  ),
                ],

              ],
            ),
          ),
        ),
      ),
    );
  }

  String _dateLabel(EmploymentContractModel c) {
    if (c.isLongTerm) {
      // 장기: rangeStart ~ rangeEnd (snapshot에 없으면 createdAt 기준)
      return FormatHelper.formatDateDot(c.createdAt);
    }
    if (c.slots.isNotEmpty) {
      // isNotEmpty 가드 내부 — .first/.last 안전
      final first = c.slots.first.workDate;
      final last = c.slots.last.workDate;
      return first == last ? first : '$first ~ $last';
    }
    return FormatHelper.formatDateDot(c.createdAt);
  }

  Color _statusColor(ContractStatus s) {
    switch (s) {
      case ContractStatus.pendingEmployer: return AppColors.warning;
      case ContractStatus.pendingWorker:   return AppColors.info;
      case ContractStatus.completed:       return AppColors.success;
      case ContractStatus.voided:          return AppColors.grey500;
    }
  }

  Color _statusBg(ContractStatus s) {
    switch (s) {
      case ContractStatus.pendingEmployer: return AppColors.warningBg;
      case ContractStatus.pendingWorker:   return AppColors.infoBg;
      case ContractStatus.completed:       return AppColors.successBg;
      case ContractStatus.voided:          return AppColors.grey100;
    }
  }
}

// ─── 서명 진행 표시 ──────────────────────────────────────────────

class _SignProgressBar extends StatelessWidget {
  final EmploymentContractModel contract;
  const _SignProgressBar({required this.contract});

  @override
  Widget build(BuildContext context) {
    final employerDone = contract.employerSignatureUrl != null;
    final workerDone   = contract.workerSignatureUrl != null;

    return Row(
      children: [
        _SignStep(
          label: '사업주 서명',
          done: employerDone,
          date: contract.employerSignedAt,
        ),
        Expanded(
          child: Container(
            height: 2,
            margin: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 6)),
            color: employerDone ? AppColors.success : AppColors.grey200,
          ),
        ),
        _SignStep(
          label: '근무자 서명',
          done: workerDone,
          date: contract.workerSignedAt,
        ),
      ],
    );
  }
}

class _SignStep extends StatelessWidget {
  final String label;
  final bool done;
  final DateTime? date;
  const _SignStep({required this.label, required this.done, this.date});

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.success : AppColors.grey400;
    return Column(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: color,
          size: ResponsiveHelper.iconSize(context, 16),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 2)),
        Text(label,
            style: ResponsiveHelper.tinyStyle(context, color: color)),
        if (done && date != null)
          Text(
            FormatHelper.formatDateDot(date!),
            style: ResponsiveHelper.tinyStyle(context,
                color: AppColors.grey400),
          ),
      ],
    );
  }
}

// ─── 정보 칩 ─────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: ResponsiveHelper.iconSize(context, 13),
            color: AppColors.grey500),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text(text,
            style: ResponsiveHelper.tinyStyle(context,
                color: AppColors.grey600)),
      ],
    );
  }
}
