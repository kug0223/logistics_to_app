import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/core/application_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../models/core/user_model.dart';
import '../../models/core/work_detail_data.dart';
import '../../services/contract_service.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../utils/navigation_helper.dart';
import '../../screens/common/notification_screen.dart';
import '../../widgets/common/notification_badge.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_search_bar.dart';
import '../../widgets/common/app_tab_label.dart';
import '../../providers/user_provider.dart';
import '../../services/member_service.dart';
import '../../widgets/dialogs/contract_template_selector_dialog.dart';

class AdminContractManagementScreen extends StatefulWidget {
  final String businessId;
  final String? businessName;
  final int initialTab;

  const AdminContractManagementScreen({
    super.key,
    required this.businessId,
    this.businessName,
    this.initialTab = 0,
  });

  @override
  State<AdminContractManagementScreen> createState() =>
      _AdminContractManagementScreenState();
}

class _AdminContractManagementScreenState
    extends State<AdminContractManagementScreen>
    with SingleTickerProviderStateMixin {

  final _contractService = ContractService();
  final _firestoreService = FirestoreService();
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();

  // 탭 순서 — index 1("미발송")은 _isUnsentTab으로 분기
  static const _tabs = <ContractStatus?>[
    null,                         // 0: 전체
    null,                         // 1: 미발송 (ApplicationModel 목록)
    ContractStatus.pendingWorker, // 2: 근무자 대기
    ContractStatus.completed,     // 3: 완료
    ContractStatus.voided,        // 4: 무효
  ];
  static const _tabLabels = ['전체', '미발송', '근무자 대기', '완료', '무효'];

  late final TabController _tabCtrl;

  List<EmploymentContractModel> _items = [];
  bool _isLoading = true;
  bool _fetchInProgress = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  bool _isVoidingContract = false;
  bool _isRetrying = false;
  String? _lastDoc;

  List<ApplicationModel> _unsentApps = [];
  bool _isSendingContract = false;

  // 탭별 캐시 — 동일 탭 재방문 시 CF 재호출 없이 즉시 표시
  final Map<int, ({List<EmploymentContractModel> items, String? lastDocId, bool hasMore})> _tabCache = {};
  List<ApplicationModel>? _unsentCache;

  String _searchQuery = '';
  Timer? _searchDebounce;

  bool get _isUnsentTab => _tabCtrl.index == 1;

  ContractStatus? get _currentFilter =>
      _isUnsentTab ? null : _tabs[_tabCtrl.index];

  List<EmploymentContractModel> get _filteredItems {
    if (_isUnsentTab) return [];
    if (_searchQuery.isEmpty) return _items;
    final q = _searchQuery.toLowerCase();
    return _items
        .where((c) => c.snapshot.workerName.toLowerCase().contains(q))
        .toList();
  }

  List<ApplicationModel> get _filteredUnsentApps {
    if (_searchQuery.isEmpty) return _unsentApps;
    final q = _searchQuery.toLowerCase();
    return _unsentApps
        .where((a) =>
            (a.applicantName ?? '').toLowerCase().contains(q) ||
            a.selectedWorkType.toLowerCase().contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this, initialIndex: widget.initialTab.clamp(0, _tabs.length - 1));
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        _searchCtrl.clear();
        _load(); // 캐시 히트 시 CF 재호출 없이 즉시 표시
      }
    });
    _scrollCtrl.addListener(_onScroll);
    _searchCtrl.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 250), () {
        if (mounted) setState(() => _searchQuery = _searchCtrl.text.trim());
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // [PATCH-CONTRACT-MGMT-PERMISSION-01] target-B 기준 canManageContract 재검증
      // — up.can()의 current-selected-A snapshot에서 widget.businessId(B) 기준으로 교체.
      // [AUDIT.2-M002] screen-level guard — caller가 guard하더라도 직접 진입 경로 방어
      final allowed = await _canAccessTargetBusiness();
      if (!mounted) return;
      if (!allowed) {
        Navigator.of(context).pop();
        return;
      }
      _load();
    });
  }

  /// widget.businessId(target B) 기준 canManageContract 권한 확인.
  /// BUSINESS_ADMIN → 항상 허용 (서버가 소속 검증).
  /// SUB_ADMIN → target business 멤버십 + canManageContract 재검증.
  /// up.can()의 current-selected-A snapshot을 B 기준으로 교체하는 screen-local helper.
  Future<bool> _canAccessTargetBusiness() async {
    final up = context.read<UserProvider>();

    // BUSINESS_ADMIN(OWNER/SUPER_ADMIN 포함) → 서버가 소속 검증하므로 client gate 통과
    if (!up.isSubAdmin) return true;

    final uid = up.currentUser?.uid;
    if (uid == null) return false;

    // SUB_ADMIN: target business 멤버십 확인 (subAdminBusinessIds 포함 여부)
    final inList = up.currentUser?.subAdminBusinessIds.contains(widget.businessId) ?? false;
    if (!inList) return false;

    // 현재 선택 사업장 == target이고 권한이 로드됐으면 캐시 사용 (네트워크 절약)
    if (up.permissionsLoaded && up.selectedSubAdminBusinessId == widget.businessId) {
      return up.can((p) => p.canManageContract);
    }

    // 다른 사업장 선택 중이거나 캐시 미로드 → target-local Firestore 직접 조회
    try {
      final perms = await MemberService().getMemberPermissions(widget.businessId, uid);
      return perms?.canManageContract == true;
    } catch (e) {
      debugPrint('❌ [CONTRACT-MGMT] target business 권한 조회 실패: $e');
      return false; // fail closed
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
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

  Future<void> _load({bool useCache = true}) async {
    if (!mounted || _fetchInProgress) return;
    final tabIdx = _tabCtrl.index;

    // 캐시 히트: 스피너 없이 즉시 표시
    if (useCache) {
      if (_isUnsentTab && _unsentCache != null) {
        setState(() { _unsentApps = List.from(_unsentCache!); _isLoading = false; });
        return;
      }
      if (!_isUnsentTab) {
        final cached = _tabCache[tabIdx];
        if (cached != null) {
          setState(() {
            _items   = List.from(cached.items);
            _lastDoc = cached.lastDocId;
            _hasMore = cached.hasMore;
            _isLoading = false;
          });
          return;
        }
      }
    }

    _fetchInProgress = true;
    setState(() { _isLoading = true; _items = []; _unsentApps = []; _lastDoc = null; _hasMore = false; });
    try {
      if (_isUnsentTab) {
        await _loadUnsentContracts();
        _unsentCache = List.from(_unsentApps);
      } else {
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
        _tabCache[tabIdx] = (items: List.from(result.items), lastDocId: result.lastDocId, hasMore: result.hasMore);
      }
    } catch (e) {
      debugPrint('❌ 계약 목록 로드 실패: $e');
      if (mounted) ToastHelper.showError('계약서 목록을 불러오는데 실패했습니다.');
    } finally {
      _fetchInProgress = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // pull-to-refresh: 현재 탭 캐시만 무효화
  Future<void> _refresh() {
    if (_isUnsentTab) {
      _unsentCache = null;
    } else {
      _tabCache.remove(_tabCtrl.index);
    }
    return _load(useCache: false);
  }

  // 뮤테이션 후 호출: 전체 탭 캐시 무효화
  void _invalidateAllCaches() {
    _tabCache.clear();
    _unsentCache = null;
  }

  Future<void> _loadUnsentContracts() async {
    try {
      final unsent = await _firestoreService.getUnsentApplicationsByBusiness(widget.businessId)
        ..sort((a, b) => a.workDate.compareTo(b.workDate));
      if (!mounted) return;
      setState(() => _unsentApps = unsent);
    } catch (e) {
      debugPrint('❌ 미발송 계약서 조회 실패: $e');
    }
  }

  Future<void> _loadMore() async {
    if (_isUnsentTab || _isLoadingMore || !_hasMore || _lastDoc == null) return;
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
      // 페이지네이션 결과도 캐시에 반영
      final tabIdx = _tabCtrl.index;
      _tabCache[tabIdx] = (items: List.from(_items), lastDocId: _lastDoc, hasMore: _hasMore);
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
    final tabIdx = _tabCtrl.index;
    if (!_isUnsentTab) {
      _tabCache[tabIdx] = (items: List.from(_items), lastDocId: _lastDoc, hasMore: _hasMore);
    }
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
      _invalidateAllCaches();
      _load(useCache: false);
    } catch (e) {
      if (!mounted) return;
      // CF 무효화 완료 후 app 취소 일부 실패 vs CF 자체 실패 분기
      if (e.toString().contains('계약서가 무효화되었으나')) {
        ToastHelper.showWarning('무효 처리됐으나 일부 지원서 취소에 실패했습니다. 카드에서 재처리하세요.');
      } else {
        ToastHelper.showError('무효 처리에 실패했습니다. 다시 시도해주세요.');
      }
      _invalidateAllCaches();
      _load(useCache: false);
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
      _invalidateAllCaches();
      _load(useCache: false);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('재처리 실패: $e');
      _invalidateAllCaches();
      _load(useCache: false);
    } finally {
      if (mounted) setState(() => _isRetrying = false);
    }
  }

  /// 미발송 카드 탭 → 템플릿 선택 → 계약서 생성 → 사업주 서명 화면 이동
  Future<void> _sendContractFromApp(ApplicationModel app) async {
    if (_isSendingContract) return;
    setState(() => _isSendingContract = true);
    try {
      // ① 템플릿 선택 — null이면 사용자 취소
      if (!mounted) return;
      final articles = await ContractTemplateSelectorDialog.show(
        context,
        businessId: widget.businessId,
      );
      if (articles == null || !mounted) return;

      // ②③④⑤ 모두 독립적 — 병렬 조회
      // [SEC-FIX 2026-08-10] getUser(app.uid) 직접 호출 제거 →
      //   callableGetWorkerBasicProfile CF 경유 (assertBizAdmin + 지원자 재검증)
      final toId = app.toId ?? '';
      final workerProfileCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetWorkerBasicProfile');

      final fetchResults = await Future.wait([
        toId.isNotEmpty
            ? _firestoreService.getWorkDetails(toId)
            : Future<dynamic>.value(<WorkDetailData>[]),
        _firestoreService.getBusinessById(widget.businessId),
        workerProfileCallable.call<Map<String, dynamic>>({
          'workerUid': app.uid,
          'businessId': widget.businessId,
        }),
        FirebaseFirestore.instance
            .collection('applications')
            .doc(app.id)
            .get(const GetOptions(source: Source.server)),
      ]);
      if (!mounted) return;

      final workDetails = fetchResults[0] as List<WorkDetailData>;
      final business = fetchResults[1] as BusinessModel?;
      final workerResult = fetchResults[2] as HttpsCallableResult<Map<String, dynamic>>;
      final workerData = workerResult.data;
      // CF 반환값으로 최소 UserModel 구성 (계약서 작성에 필요한 필드만)
      final worker = UserModel(
        uid: app.uid,
        username: '',
        email: '',
        role: UserRole.USER,
        name: (workerData['name'] as String?) ?? '',
        phone: workerData['phone'] as String?,
        birthDate: workerData['birthDateMs'] != null
            ? DateTime.fromMillisecondsSinceEpoch(workerData['birthDateMs'] as int)
            : null,
        address: workerData['address'] as String?,
        detailAddress: workerData['detailAddress'] as String?,
      );
      final freshAppDoc = fetchResults[3] as DocumentSnapshot<Map<String, dynamic>>;

      if (workDetails.isEmpty) {
        ToastHelper.showError('업무 정보를 불러올 수 없습니다');
        return;
      }
      if (business == null) {
        ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
        return;
      }
      if (!freshAppDoc.exists) throw Exception('지원서를 찾을 수 없습니다');
      final freshApp = ApplicationModel.tryFromMap(freshAppDoc.data()!, freshAppDoc.id);
      if (freshApp == null) throw Exception('지원서 데이터가 손상되었습니다');
      if (!mounted) return;

      final WorkDetailData workDetail;
      if (app.workDetailId?.isNotEmpty == true) {
        workDetail = workDetails.firstWhere(
          (w) => w.id == app.workDetailId || w.legacyId == app.workDetailId,
          orElse: () => workDetails.firstWhere(
            (w) => w.workType == app.selectedWorkType,
            orElse: () => workDetails.first,
          ),
        );
      } else {
        workDetail = workDetails.firstWhere(
          (w) => w.workType == app.selectedWorkType,
          orElse: () => workDetails.first,
        );
      }

      // ⑥ 계약서 생성 (번들 있으면 슬롯 추가, 없으면 신규)
      final contract = await ContractService().findOrCreateContract(
        application: freshApp,
        business: business,
        worker: worker,
        workDetail: workDetail,
        articles: articles,
      );
      if (!mounted) return;

      // ⑦ 사업주 서명 화면으로 이동 — 서명 완료 시 status: pendingWorker 전환
      final nav = Navigator.of(context);
      await nav.push(MaterialPageRoute(
        builder: (_) => ContractSignScreen(contract: contract, role: 'employer'),
      ));
      if (!mounted) return;

      // ⑧ 서명 완료 후 목록 갱신 — 발송된 항목이 미발송 탭에서 제거됨
      _invalidateAllCaches();
      await _load(useCache: false);
    } catch (e) {
      debugPrint('❌ 계약서 발송 실패: $e');
      if (mounted) ToastHelper.showError('계약서 생성에 실패했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isSendingContract = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPageScaffold(
      title: '계약서 관리',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _refresh,
          color: AppColors.textSecondary,
        ),
        IconButton(
          icon: const Icon(Icons.home_outlined),
          onPressed: () => NavigationHelper.goHome(context),
          color: AppColors.textSecondary,
        ),
        NotificationBadge(
          child: IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
            color: AppColors.textSecondary,
          ),
        ),
      ],
      bottom: TabBar(
        controller: _tabCtrl,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: theme.primaryColor,
        unselectedLabelColor: AppColors.grey500,
        indicatorColor: theme.primaryColor,
        indicatorWeight: 2,
        dividerColor: Colors.transparent,
        tabs: _tabLabels.map((l) => Tab(child: AppTabLabel(label: l))).toList(),
      ),
      body: _isLoading
          ? const LoadingWidget(message: '계약서 목록을 불러오는 중...')
          : Column(
              children: [
                AppSearchBar(
                  controller: _searchCtrl,
                  hintText: _isUnsentTab ? '이름 또는 업무로 검색' : '근무자 이름으로 검색',
                ),
                if (!_isUnsentTab && _searchQuery.isNotEmpty && _hasMore)
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
                    child: Builder(builder: (context) {
                      final filteredUnsent = _filteredUnsentApps;
                      final filteredItems = _filteredItems;
                      return _isUnsentTab
                        ? (filteredUnsent.isEmpty
                            ? _buildEmpty(context)
                            : ListView.builder(
                                padding: ResponsiveHelper.listPadding(context),
                                itemCount: filteredUnsent.length,
                                itemBuilder: (ctx, i) => _UnsentAppCard(
                                  app: filteredUnsent[i],
                                  onTap: _isSendingContract
                                      ? null
                                      : () => _sendContractFromApp(filteredUnsent[i]),
                                ),
                              ))
                        : (filteredItems.isEmpty
                            ? _buildEmpty(context)
                            : ListView.builder(
                                controller: _scrollCtrl,
                                padding: ResponsiveHelper.listPadding(context),
                                itemCount: filteredItems.length + (_isLoadingMore ? 1 : 0),
                                itemBuilder: (ctx, i) {
                                  if (i == filteredItems.length) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: LoadingWidget(),
                                    );
                                  }
                                  final item = filteredItems[i];
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
                              ));
                    }),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final isSearching = _searchQuery.isNotEmpty;
    if (_isUnsentTab) {
      return AppEmptyState(
        icon: isSearching ? Icons.search_off : Icons.check_circle_outline,
        title: isSearching ? '"$_searchQuery" 검색 결과 없음' : '미발송 계약서 없음',
        subtitle: isSearching
            ? '다른 이름으로 검색해 보세요'
            : '확정된 모든 지원자에게 계약서가 발송되었습니다',
      );
    }
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
        color: AppColors.surface,
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
                // 헤더: 이름 · 업무 한 줄 + 상태 배지
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(Icons.person_outline,
                          color: theme.primaryColor,
                          size: ResponsiveHelper.iconSize(context, 14)),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(
                        '${contract.snapshot.workerName}  ·  ${contract.snapshot.workType}',
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
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

// ─── 서명 진행 표시 (한 줄) ──────────────────────────────────────

class _SignProgressBar extends StatelessWidget {
  final EmploymentContractModel contract;
  const _SignProgressBar({required this.contract});

  String _shortDate(DateTime d) => FormatHelper.formatDateDot(d).substring(5); // "MM.dd"

  @override
  Widget build(BuildContext context) {
    final employerDone = contract.employerSignatureUrl != null;
    final workerDone   = contract.workerSignatureUrl != null;
    final employerColor = employerDone ? AppColors.success : AppColors.grey400;
    final workerColor   = workerDone   ? AppColors.success : AppColors.grey400;

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
          '근무자 서명',
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

// ─── 미발송 탭 — 지원서 카드 ──────────────────────────────────────

class _UnsentAppCard extends StatelessWidget {
  final ApplicationModel app;
  final VoidCallback? onTap;
  const _UnsentAppCard({required this.app, this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = app.applicantName?.isNotEmpty == true
        ? app.applicantName!
        : '이름 미상';

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
              vertical: ResponsiveHelper.spacing(context, 12),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.assignment_late_outlined,
                      color: AppColors.warning,
                      size: ResponsiveHelper.iconSize(context, 18)),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$name  ·  ${app.selectedWorkType}',
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                      Text(
                        FormatHelper.formatDateDot(app.workDate),
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.grey500),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 3),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '미발송',
                    style: ResponsiveHelper.tinyStyle(context).copyWith(
                        color: AppColors.warningDark,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
