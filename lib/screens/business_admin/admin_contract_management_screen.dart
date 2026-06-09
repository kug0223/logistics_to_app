import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  DocumentSnapshot? _lastDoc;

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
      if (!_tabCtrl.indexIsChanging) _refresh();
    });
    _scrollCtrl.addListener(_onScroll);
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim());
    });
    _load();
  }

  @override
  void dispose() {
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
        _lastDoc = result.lastDoc;
        _hasMore = result.hasMore;
      });
    } catch (e) {
      debugPrint('❌ 계약 목록 로드 실패: $e');
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
        startAfter: _lastDoc,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _lastDoc = result.lastDoc;
        _hasMore = result.hasMore;
      });
    } catch (e) {
      debugPrint('❌ 계약 목록 추가 로드 실패: $e');
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
    _refresh(); // 서명 후 목록 갱신
  }

  Future<void> _voidContract(EmploymentContractModel c) async {
    if (_isVoidingContract) return;
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
    setState(() => _isVoidingContract = true);
    try {
      await _contractService.voidContract(c.id);
      if (!mounted) return;
      ToastHelper.showSuccess('계약서가 무효 처리되었습니다');
      _refresh();
    } catch (e) {
      ToastHelper.showError('무효 처리에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isVoidingContract = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GradientScaffold(
      title: '계약서 관리',
      body: _isLoading
          ? const LoadingWidget(message: '계약서 목록을 불러오는 중...')
          : Column(
              children: [
                // 탭 + 검색 (흰 영역)
                Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabCtrl,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: theme.primaryColor,
                    unselectedLabelColor: AppColors.grey400,
                    indicatorColor: theme.primaryColor,
                    indicatorWeight: 2.5,
                    dividerColor: AppColors.grey100,
                    labelStyle: ResponsiveHelper.smallStyle(context)
                        .copyWith(fontWeight: FontWeight.w600),
                    tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
                  ),
                ),
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
                                onVoid: item.status ==
                                        ContractStatus.completed
                                    ? () => _voidContract(item)
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

  const _ContractCard({
    required this.contract,
    required this.onTap,
    this.onVoid,
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
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더: 이름 + 상태 배지
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.person_outline,
                          color: theme.primaryColor,
                          size: ResponsiveHelper.iconSize(context, 20)),
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

                SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                const Divider(height: 1, color: AppColors.grey100),
                SizedBox(height: ResponsiveHelper.spacing(context, 10)),

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

                SizedBox(height: ResponsiveHelper.spacing(context, 10)),

                // 서명 진행 인디케이터
                _SignProgressBar(contract: contract),

                // 무효화 버튼 (완료 상태에서만)
                if (onVoid != null &&
                    contract.status == ContractStatus.completed) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: onVoid,
                      icon: Icon(Icons.block_outlined,
                          size: ResponsiveHelper.iconSize(context, 14),
                          color: AppColors.errorMedium),
                      label: Text('무효 처리',
                          style: ResponsiveHelper.tinyStyle(context,
                              color: AppColors.errorMedium)),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 8),
                          vertical: ResponsiveHelper.spacing(context, 4),
                        ),
                      ),
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
          size: ResponsiveHelper.iconSize(context, 18),
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
