// lib/screens/user/user_contracts_screen.dart
//
// 지원자 계약서 관리 화면
// - 내 계약서 목록 전체 조회 (상태별 필터)
// - 서명 필요 / 완료 상태 확인
// - ContractSignScreen 진입

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/core/employment_contract_model.dart';
import '../../providers/user_provider.dart';
import '../../services/contract_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_tab_label.dart';

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
  // pendingEmployer 제거 — 계약서는 사업주 서명 시 최초 저장(pendingWorker)되므로 해당 탭은 항상 비어있음
  static const _tabs = <ContractStatus?>[
    null,
    ContractStatus.pendingWorker, // 내 서명 필요
    ContractStatus.completed,
    ContractStatus.voided,
  ];
  static const _tabLabels = ['전체', '서명 필요', '완료', '무효'];

  late final TabController _tabCtrl;

  List<EmploymentContractModel> _items = [];
  bool _isLoading = true;
  bool _fetchInProgress = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  bool _isContractOpening = false;
  String? _lastDocId;

  // 탭별 캐시 — 동일 탭 재방문 시 CF 재호출 없이 즉시 표시
  final Map<int, ({List<EmploymentContractModel> items, String? lastDocId, bool hasMore})> _tabCache = {};

  ContractStatus? get _currentFilter => _tabs[_tabCtrl.index];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) _load(); // 캐시 히트 시 CF 재호출 없이 즉시 표시
    });
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
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

  Future<void> _load({bool useCache = true}) async {
    if (!mounted || _fetchInProgress) return;
    final uid = _uid;
    if (uid == null) { if (mounted) setState(() => _isLoading = false); return; }
    final tabIdx = _tabCtrl.index;

    // 캐시 히트: 스피너 없이 즉시 표시
    if (useCache) {
      final cached = _tabCache[tabIdx];
      if (cached != null) {
        setState(() {
          _items     = List.from(cached.items);
          _lastDocId = cached.lastDocId;
          _hasMore   = cached.hasMore;
          _isLoading = false;
        });
        return;
      }
    }

    _fetchInProgress = true;
    setState(() { _isLoading = true; _items = []; _lastDocId = null; _hasMore = false; });
    try {
      final result = await _contractService.getByWorkerPaged(
        uid,
        statusFilter: _currentFilter,
      );
      if (!mounted) return;
      setState(() {
        _items     = result.items;
        _lastDocId = result.lastDocId;
        _hasMore   = result.hasMore;
      });
      _tabCache[tabIdx] = (items: List.from(result.items), lastDocId: result.lastDocId, hasMore: result.hasMore);
    } catch (e) {
      debugPrint('❌ 계약 목록 로드 실패: $e');
      if (mounted) ToastHelper.showError('계약서 목록을 불러오지 못했습니다');
    } finally {
      _fetchInProgress = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // pull-to-refresh: 현재 탭 캐시만 무효화
  Future<void> _refresh() {
    _tabCache.remove(_tabCtrl.index);
    return _load(useCache: false);
  }

  Future<void> _loadMore() async {
    final uid = _uid;
    if (_isLoadingMore || !_hasMore || _lastDocId == null || uid == null) return;
    if (!mounted) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await _contractService.getByWorkerPaged(
        uid,
        statusFilter: _currentFilter,
        startAfter: _lastDocId,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _lastDocId = result.lastDocId;
        _hasMore   = result.hasMore;
      });
      // 페이지네이션 결과도 캐시에 반영
      final tabIdx = _tabCtrl.index;
      _tabCache[tabIdx] = (items: List.from(_items), lastDocId: _lastDocId, hasMore: _hasMore);
    } catch (e) {
      debugPrint('❌ 계약 목록 추가 로드 실패: $e');
      if (mounted) ToastHelper.showError('계약서를 더 불러오지 못했습니다');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _openContract(EmploymentContractModel c) async {
    if (_isContractOpening || !mounted) return;
    setState(() => _isContractOpening = true);
    final nav = Navigator.of(context);
    try {
    await nav.push(MaterialPageRoute(
      builder: (_) => ContractSignScreen(contract: c, role: 'worker'),
    ));
    } finally {
      if (mounted) setState(() => _isContractOpening = false);
    }
    if (!mounted) return;
    // 단건 갱신 — 전체 탭 재조회 대신 해당 계약서만 업데이트
    final updated = await _contractService.getById(c.id);
    if (!mounted) return;
    setState(() {
      final idx = _items.indexWhere((item) => item.id == c.id);
      if (idx < 0) return;
      if (updated == null) {
        _items.removeAt(idx);
      } else if (_currentFilter != null && updated.status != _currentFilter) {
        // 상태 변경으로 현재 탭 필터 조건에서 벗어남 — 목록에서 제거
        _items.removeAt(idx);
      } else {
        _items[idx] = updated;
      }
    });
    // 단건 변경을 캐시에도 반영
    _tabCache[_tabCtrl.index] = (items: List.from(_items), lastDocId: _lastDocId, hasMore: _hasMore);
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '내 계약서',
      showNotificationBell: true,
      showPendingContractBar: false,
      onRefresh: _refresh,
      headerBottom: TabBar(
        controller: _tabCtrl,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
        indicatorColor: Colors.white,
        indicatorWeight: 2.5,
        dividerColor: Colors.transparent,
        tabs: _tabLabels.map((l) => Tab(child: AppTabLabel(label: l))).toList(),
      ),
      body: _isLoading
          ? const LoadingWidget(message: '계약서 목록을 불러오는 중...')
          : RefreshIndicator(
              onRefresh: _refresh,
              child: _items.isEmpty
                  ? _buildEmpty(context)
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: ResponsiveHelper.listPadding(context),
                      itemCount: _items.length + (_isLoadingMore ? 1 : 0),
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
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final subtitle = switch (_currentFilter) {
      null                         => '확정된 공고에서 계약서를 받으세요.',
      ContractStatus.pendingWorker => '서명이 필요한 계약서가 없습니다.',
      ContractStatus.completed     => '완료된 계약서가 없습니다.',
      ContractStatus.voided        => '무효 처리된 계약서가 없습니다.',
      _                            => '해당 계약서가 없습니다.',
    };
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
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
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
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 14),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더: 사업장 · 업무 한 줄 + 상태 배지
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(Icons.business_outlined,
                          color: theme.primaryColor,
                          size: ResponsiveHelper.iconSize(context, 14)),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(
                        '${contract.snapshot.businessName}  ·  ${contract.snapshot.workType}',
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
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
                        style: ResponsiveHelper.tinyStyle(context).copyWith(
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

                // 계약 정보 칩
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
                          ' / ${_wageTypeLabel(contract.snapshot.wageType)}',
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

                // 서명 진행 바 (완료 날짜 포함)
                _SignProgressBar(contract: contract),

                // 서명 필요 안내 (pendingWorker만 — 한 줄 텍스트)
                if (needSign) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                  Row(
                    children: [
                      Icon(Icons.touch_app_outlined,
                          size: ResponsiveHelper.iconSize(context, 12),
                          color: AppColors.info),
                      SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                      Text(
                        '탭하여 계약서를 확인하고 서명하세요',
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.infoDark),
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

// ─── 서명 진행 바 ─────────────────────────────────────────────────

class _SignProgressBar extends StatelessWidget {
  final EmploymentContractModel contract;
  const _SignProgressBar({required this.contract});

  String _shortDate(DateTime d) =>
      FormatHelper.formatDateDot(d).substring(5); // "MM.dd"

  @override
  Widget build(BuildContext context) {
    final employerDone = contract.employerSignatureUrl != null;
    final workerDone   = contract.workerSignatureUrl != null;
    final employerColor = employerDone ? AppColors.success : AppColors.grey400;
    // 내 서명 대기 상태면 파란색으로 강조
    final workerColor = workerDone
        ? AppColors.success
        : (contract.status == ContractStatus.pendingWorker
            ? AppColors.info
            : AppColors.grey400);

    return Row(
      children: [
        Icon(
          employerDone ? Icons.check_circle : Icons.radio_button_unchecked,
          color: employerColor,
          size: ResponsiveHelper.iconSize(context, 14),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        Text(
          '사업주 서명',
          style: ResponsiveHelper.tinyStyle(context, color: employerColor),
        ),
        if (employerDone && contract.employerSignedAt != null) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text(
            _shortDate(contract.employerSignedAt!),
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
          ),
        ],
        Expanded(
          child: Container(
            height: 2,
            margin: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8)),
            color: employerDone ? AppColors.success : AppColors.grey200,
          ),
        ),
        Icon(
          workerDone ? Icons.check_circle : Icons.radio_button_unchecked,
          color: workerColor,
          size: ResponsiveHelper.iconSize(context, 14),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        Text(
          '내 서명',
          style: ResponsiveHelper.tinyStyle(context, color: workerColor),
        ),
        if (workerDone && contract.workerSignedAt != null) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text(
            _shortDate(contract.workerSignedAt!),
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
          ),
        ],
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
