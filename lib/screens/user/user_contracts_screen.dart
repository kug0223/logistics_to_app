// lib/screens/user/user_contracts_screen.dart
//
// 지원자 계약서 관리 화면
// - 내 계약서 목록 전체 조회 (상태별 필터)
// - 서명 필요 / 완료 상태 확인
// - ContractSignScreen 진입

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../models/core/employment_contract_model.dart';
import '../../providers/user_provider.dart';
import '../../services/contract_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';

class UserContractsScreen extends StatefulWidget {
  const UserContractsScreen({super.key});

  @override
  State<UserContractsScreen> createState() => _UserContractsScreenState();
}

class _UserContractsScreenState extends State<UserContractsScreen>
    with SingleTickerProviderStateMixin {

  final _contractService = ContractService();
  final _scrollCtrl = ScrollController();

  // null = 전체, 순서 중요 (탭 인덱스와 대응)
  static const _tabs = <ContractStatus?>[
    null,
    ContractStatus.pendingWorker,   // 내 서명 필요
    ContractStatus.pendingEmployer, // 사업주 서명 대기
    ContractStatus.completed,
    ContractStatus.voided,
  ];
  static const _tabLabels = ['전체', '서명 필요', '사업주 대기', '완료', '무효'];

  late final TabController _tabCtrl;

  List<EmploymentContractModel> _items = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  DocumentSnapshot? _lastDoc;

  ContractStatus? get _currentFilter => _tabs[_tabCtrl.index];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) _refresh();
    });
    _scrollCtrl.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _scrollCtrl.dispose();
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

  String? get _uid =>
      Provider.of<UserProvider>(context, listen: false).currentUser?.uid;

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null || !mounted) return;
    setState(() { _isLoading = true; _items = []; _lastDoc = null; });
    try {
      final result = await _contractService.getByWorkerPaged(
        uid,
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
    final uid = _uid;
    if (_isLoadingMore || !_hasMore || _lastDoc == null || uid == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await _contractService.getByWorkerPaged(
        uid,
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
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ContractSignScreen(contract: c, role: 'worker'),
    ));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GradientScaffold(
      title: '내 계약서',
      body: Column(
        children: [
          // TabBar — 흰 콘텐츠 영역 최상단 (파란 헤더와 분리)
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
          // 콘텐츠
          Expanded(
            child: _isLoading
                ? const LoadingWidget(message: '계약서 목록을 불러오는 중...')
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: _items.isEmpty
                        ? _buildEmpty(context)
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: ResponsiveHelper.listPadding(context),
                            itemCount:
                                _items.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (ctx, i) {
                              if (i == _items.length) {
                                return const LoadingWidget();
                              }
                              return _UserContractCard(
                                contract: _items[i],
                                onTap: () => _openContract(_items[i]),
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
    final subtitle = _currentFilter == ContractStatus.pendingWorker
        ? '서명이 필요한 계약서가 없습니다'
        : _currentFilter == ContractStatus.completed
            ? '완료된 계약서가 없습니다'
            : '확정된 공고에서 계약서를 받으세요.';
    return AppEmptyState(
      icon: Icons.description_outlined,
      title: '계약서가 없습니다',
      subtitle: subtitle,
    );
  }
}

// ─── 지원자용 계약서 카드 ─────────────────────────────────────────

class _UserContractCard extends StatelessWidget {
  final EmploymentContractModel contract;
  final VoidCallback onTap;

  const _UserContractCard({required this.contract, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = contract.status;
    final statusColor = _statusColor(status);
    final statusBg = _statusBg(status);
    final needSign = status == ContractStatus.pendingWorker;

    return Container(
      margin: EdgeInsets.only(
          bottom: ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: needSign ? AppColors.info : AppColors.grey200,
          width: needSign ? 1.5 : 1,
        ),
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
                // 헤더: 사업장 + 상태
                Row(
                  children: [
                    Container(
                      width: ResponsiveHelper.spacing(context, 38),
                      height: ResponsiveHelper.spacing(context, 38),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.business_outlined,
                          color: theme.primaryColor,
                          size: ResponsiveHelper.iconSize(context, 20)),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            contract.snapshot.businessName,
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
                        status.label,
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

                // 계약 정보
                Wrap(
                  spacing: ResponsiveHelper.spacing(context, 14),
                  runSpacing: ResponsiveHelper.spacing(context, 6),
                  children: [
                    _InfoChip(
                      icon: Icons.calendar_today_outlined,
                      text: _dateLabel(contract),
                    ),
                    _InfoChip(
                      icon: Icons.attach_money,
                      text: '${FormatHelper.formatNumber(contract.snapshot.wage)}원'
                          ' / ${_wageTypeLabel(contract.snapshot.wageType)}',
                    ),
                  ],
                ),

                // 서명 필요 안내 배너
                if (needSign) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 12),
                      vertical: ResponsiveHelper.spacing(context, 8),
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.infoBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.touch_app_outlined,
                            size: ResponsiveHelper.iconSize(context, 14),
                            color: AppColors.info),
                        SizedBox(
                            width: ResponsiveHelper.spacing(context, 6)),
                        Expanded(
                          child: Text(
                            '서명이 필요합니다. 탭하여 계약서를 확인하고 서명하세요.',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.infoDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 완료 일자
                if (status == ContractStatus.completed &&
                    contract.workerSignedAt != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: ResponsiveHelper.iconSize(context, 13),
                          color: AppColors.success),
                      SizedBox(
                          width: ResponsiveHelper.spacing(context, 4)),
                      Text(
                        '${FormatHelper.formatDateDot(contract.workerSignedAt!)} 서명 완료',
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.success),
                      ),
                    ],
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
    if (c.isLongTerm) return FormatHelper.formatDateDot(c.createdAt);
    if (c.slots.isNotEmpty) {
      final first = c.slots.first.workDate;
      final last  = c.slots.last.workDate;
      return first == last ? first : '$first ~ $last';
    }
    return FormatHelper.formatDateDot(c.createdAt);
  }

  String _wageTypeLabel(String t) {
    switch (t) {
      case 'hourly':  return '시급';
      case 'daily':   return '일급';
      case 'monthly': return '월급';
      default:        return t;
    }
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
