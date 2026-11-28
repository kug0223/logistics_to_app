// lib/screens/business_admin/admin_review_list_screen.dart

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/core/attendance_model.dart';
import '../../utils/toast_helper.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../theme/app_colors.dart';

// Widgets
import '../../widgets/common/review_card.dart';

// Providers
import '../../providers/user_provider.dart';

// Models
import '../../models/core/monthly_review_model.dart';
import '../../models/core/review_request_model.dart';

// Services
import '../../services/monthly_review_service.dart';

// Dialogs
import '../../widgets/dialogs/monthly_review_dialog.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/app_search_bar.dart';
import '../../widgets/common/app_tab_label.dart';
import '../../widgets/common/app_filter_chip.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/first_line_icon.dart';
import '../../widgets/common/notification_badge.dart';
import '../../utils/business_picker_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/text_layout.dart';
import '../common/notification_screen.dart';
import '../../utils/action_guard.dart';

enum _DividerMarker { expired }

/// 관리자용 리뷰 목록 화면
class AdminReviewListScreen extends StatefulWidget {
  final String? businessId;

  const AdminReviewListScreen({
    super.key,
    this.businessId,
  });

  @override
  State<AdminReviewListScreen> createState() => _AdminReviewListScreenState();
}

class _AdminReviewListScreenState extends State<AdminReviewListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _reviewService = MonthlyReviewService();

  bool _isLoading = true;
  bool _hasError = false;
  bool _isProcessing = false;

  // 전량 원본 데이터 (DB 재쿼리 없이 메모리 필터 사용)
  List<MonthlyReviewModel> _rawWritten = [];
  List<MonthlyReviewModel> _rawReceived = [];
  List<ReviewRequestModel> _rawPending = [];
  Map<String, DateTime> _requestDeadlines = {};
  // workerName 이 비어있는 경우 users 컬렉션에서 보완 조회한 이름 캐시
  Map<String, String> _resolvedWorkerNames = {};

  // 페이지네이션 상태 — CF 전환으로 DocumentSnapshot 대신 문서 ID 문자열 사용
  String? _cursorWritten;
  String? _cursorReceived;
  bool _hasMoreWritten = false;
  bool _hasMoreReceived = false;
  bool _isLoadingMoreWritten = false;
  bool _isLoadingMoreReceived = false;
  String? _cachedBusinessId;

  // 필터 상태
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = 0; // 0 = 전체

  // 파생 상태 (캐시) — _recomputeDerived()로 일괄 갱신
  List<int> _availableYears = [];
  Map<int, int> _availableMonths = {};
  List<MonthlyReviewModel> _writtenReviews = [];
  List<MonthlyReviewModel> _receivedReviews = [];
  List<ReviewRequestModel> _pendingRequests = [];
  bool _pendingIsUrgent = false;
  // 검색+기한 파생값 — _recomputePendingFiltered()로 갱신
  List<ReviewRequestModel> _filteredActivePending = [];
  List<ReviewRequestModel> _filteredExpiredPending = [];
  DateTime _pendingNow = DateTime.now();

  /// raw 데이터 또는 필터(_selectedYear/_selectedMonth)가 바뀔 때마다 호출.
  /// setState 밖에서 필드를 갱신하고, 호출부가 setState로 rebuild를 트리거한다.
  void _recomputeDerived() {
    final now = DateTime.now();

    final years = <int>{};
    for (final r in _rawWritten)  { years.add(r.reviewYear); }
    for (final r in _rawReceived) { years.add(r.reviewYear); }
    for (final r in _rawPending)  { years.add(r.reviewYear); }
    if (years.isEmpty) years.add(now.year);
    _availableYears = (years.toList()..sort()).reversed.toList();

    final monthMap = <int, int>{};
    for (final r in _rawWritten) {
      if (r.reviewYear == _selectedYear) monthMap[r.reviewMonth] = (monthMap[r.reviewMonth] ?? 0) + 1;
    }
    for (final r in _rawReceived) {
      if (r.reviewYear == _selectedYear) monthMap[r.reviewMonth] = (monthMap[r.reviewMonth] ?? 0) + 1;
    }
    for (final r in _rawPending) {
      if (r.reviewYear == _selectedYear) monthMap[r.reviewMonth] = (monthMap[r.reviewMonth] ?? 0) + 1;
    }
    _availableMonths = monthMap;

    _writtenReviews = _rawWritten
        .where((r) => r.reviewYear == _selectedYear &&
            (_selectedMonth == 0 || r.reviewMonth == _selectedMonth))
        .toList();
    _receivedReviews = _rawReceived
        .where((r) => r.reviewYear == _selectedYear &&
            (_selectedMonth == 0 || r.reviewMonth == _selectedMonth))
        .toList();
    _pendingRequests = _rawPending
        .where((r) => r.reviewYear == _selectedYear &&
            (_selectedMonth == 0 || r.reviewMonth == _selectedMonth))
        .toList();

    _pendingIsUrgent = _pendingRequests.any(
      (r) => !r.isDeadlinePassed && r.deadline.difference(now).inDays <= 3,
    );
    _recomputePendingFiltered();
  }

  void _recomputePendingFiltered() {
    _pendingNow = DateTime.now();
    final filtered = _searchQuery.isEmpty
        ? _pendingRequests
        : _pendingRequests.where((r) {
            final name = r.workerName.isNotEmpty
                ? r.workerName
                : (_resolvedWorkerNames[r.workerId] ?? '');
            return name.toLowerCase().contains(_searchQuery);
          }).toList();
    _filteredActivePending  = filtered.where((r) => !r.isDeadlinePassed).toList();
    _filteredExpiredPending = filtered.where((r) =>  r.isDeadlinePassed).toList();
  }

  // 검색
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchCtrl.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        final q = _searchCtrl.text.trim().toLowerCase();
        if (q == _searchQuery) return;
        _searchQuery = q;
        _recomputePendingFiltered();
        setState(() {});
      });
    });
    // addPostFrameCallback: 피커 등 UI 작업을 위해 첫 프레임 이후 로드
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadReviews());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // [I9 · impl_16] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 — 창이 뜨기 전 연타의
  //   두 번째 진입이 창·mutation 을 한 번 더 내지 않게(본문 `_showReplyDialogLocked` 은 그대로 · 화면 플래그는 진행 표시로 유지).
  Future<void> _showReplyDialog(MonthlyReviewModel review) =>
      ActionGuard.runVoid(ActionGuard.ownerKey('adminReviewList._isProcessing', this), () => _showReplyDialogLocked(review));

  Future<void> _showReplyDialogLocked(MonthlyReviewModel review) async {
    if (_isProcessing) return;
    // [FC-ADM-01 OWNERSHIP FIX] _ReviewReplyDialog(StatefulWidget)이 ctrl을
    // 직접 소유하고 State.dispose()에서 해제한다.
    // addPostFrameCallback dispose 패턴 제거.
    final text = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ReviewReplyDialog(),
    );
    if (text == null || text.isEmpty || !mounted) return;
    setState(() => _isProcessing = true);
    try {
      final ok = await _reviewService.addBusinessResponse(
        reviewId: review.id,
        response: text,
      );
      if (!mounted) return;
      if (ok) {
        await _loadReviews();
      } else {
        ToastHelper.showError('답변 등록에 실패했습니다');
      }
    } catch (e) {
      debugPrint('❌ 리뷰 답변 등록 실패: $e');
      if (mounted) ToastHelper.showError('답변 등록 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _loadReviews() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    _cursorWritten = null;
    _cursorReceived = null;
    _hasMoreWritten = false;
    _hasMoreReceived = false;

    final userProvider = context.read<UserProvider>();
    // C-07: widget.businessId → effectiveBusinessId → 캐시 → 피커 순으로 결정
    String? businessId = widget.businessId
        ?? userProvider.effectiveBusinessId
        ?? _cachedBusinessId;

    if (businessId == null) {
      // BUSINESS_ADMIN N사업장: 피커로 선택 (캐시되지 않은 첫 번째 호출만)
      if (!mounted) return;
      final picked =
          await BusinessPickerHelper.pick(context, includeClosed: true);
      if (!mounted) return;
      if (picked == null) {
        setState(() => _isLoading = false);
        return;
      }
      businessId = picked.id;
    }

    _cachedBusinessId = businessId;

    try {
      final results = await Future.wait([
        _reviewService.getReviewsByBusinessPaged(businessId: businessId),
        _reviewService.getPublishedReviewsForBusinessPaged(businessId: businessId),
        _reviewService.getPendingRequestsForBusiness(businessId),
        _reviewService.getAllNonPublishedRequestsForBusiness(businessId),
      ]);

      // [S-01 fix] Future.wait 이후 mounted 체크 — CF 과금·dispose된 State 쓰기 방지
      if (!mounted) return;

      final writtenPage = results[0] as ReviewPage<MonthlyReviewModel>;
      final receivedPage = results[1] as ReviewPage<MonthlyReviewModel>;

      // raw 전량 저장 — 필터는 getter에서 처리
      _rawWritten  = writtenPage.records;
      _rawReceived = receivedPage.records;
      _rawPending  = results[2] as List<ReviewRequestModel>;
      _cursorWritten = writtenPage.cursor;
      _cursorReceived = receivedPage.cursor;
      _hasMoreWritten = writtenPage.hasMore;
      _hasMoreReceived = receivedPage.hasMore;

      final allNonPublished = results[3] as List<ReviewRequestModel>;
      _requestDeadlines = {for (final r in allNonPublished) r.id: r.deadline};
      final missingNameIds = _rawPending
          .where((r) => r.workerName.isEmpty && r.workerId.isNotEmpty)
          .map((r) => r.workerId)
          .toSet();
      if (missingNameIds.isNotEmpty && _cachedBusinessId != null) {
        final ids = missingNameIds.take(30).toList();
        final resolvedMap = <String, String>{};
        try {
          final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
              .httpsCallable('callableGetUsersBatch',
                  options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
          final response = await callable.call<Map<String, dynamic>>({
            'uids': ids,
            'businessId': _cachedBusinessId,
          });
          final usersRaw = (response.data['users'] as Map?)?.cast<String, dynamic>() ?? {};
          for (final entry in usersRaw.entries) {
            final name = (entry.value as Map)['name'] as String? ?? '';
            resolvedMap[entry.key] = name.isNotEmpty ? name : '근무자';
          }
        } catch (e) { debugPrint('⚠️ 근무자 이름 조회 실패: $e'); }
        for (final uid in ids) {
          resolvedMap.putIfAbsent(uid, () => '근무자');
        }
        if (mounted) _resolvedWorkerNames = resolvedMap;
      }

      // 파생 상태 선계산 (연도 자동 이동 전 _availableYears 확정 필요)
      _recomputeDerived();
      if (_availableYears.isNotEmpty && !_availableYears.contains(_selectedYear)) {
        _selectedYear = _availableYears.first;
        _selectedMonth = 0;
        _recomputeDerived(); // 연도/월 변경 후 재계산
      }
    } catch (e) {
      debugPrint('❌ 리뷰 로드 실패: $e');
      if (!mounted) return;
      setState(() { _isLoading = false; _hasError = true; });
      return;
    }

    if (!mounted) return;
    setState(() { _isLoading = false; _hasError = false; });
  }

  Future<void> _loadMoreWritten() async {
    final businessId = _cachedBusinessId;
    if (businessId == null || !_hasMoreWritten || _isLoadingMoreWritten) return;
    setState(() => _isLoadingMoreWritten = true);
    try {
      final page = await _reviewService.getReviewsByBusinessPaged(
        businessId: businessId,
        startAfterId: _cursorWritten,
      );
      if (!mounted) return;
      setState(() {
        _rawWritten = [..._rawWritten, ...page.records];
        _cursorWritten = page.cursor;
        _hasMoreWritten = page.hasMore;
        _isLoadingMoreWritten = false;
      });
      _recomputeDerived();
    } catch (e) {
      debugPrint('❌ 리뷰 추가 로드 실패: $e');
      if (mounted) {
        setState(() => _isLoadingMoreWritten = false);
        ToastHelper.showError('리뷰를 더 불러오지 못했습니다');
      }
    }
  }

  Future<void> _loadMoreReceived() async {
    final businessId = _cachedBusinessId;
    if (businessId == null || !_hasMoreReceived || _isLoadingMoreReceived) return;
    setState(() => _isLoadingMoreReceived = true);
    try {
      final page = await _reviewService.getPublishedReviewsForBusinessPaged(
        businessId: businessId,
        startAfterId: _cursorReceived,
      );
      if (!mounted) return;
      setState(() {
        _rawReceived = [..._rawReceived, ...page.records];
        _cursorReceived = page.cursor;
        _hasMoreReceived = page.hasMore;
        _isLoadingMoreReceived = false;
      });
      _recomputeDerived();
    } catch (e) {
      debugPrint('❌ 수신 리뷰 추가 로드 실패: $e');
      if (mounted) {
        setState(() => _isLoadingMoreReceived = false);
        ToastHelper.showError('리뷰를 더 불러오지 못했습니다');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasActiveFilter = _selectedMonth > 0;
    // [DU430] 탭 셋이 한 줄에 안 들어가면(320@2.0: '미작성' 자연폭 71.8 > 칸 52.9 → 두 줄 · 탭 높이에 잘림, 진단 du430) 가로 스크롤로.
    //   탭 이름은 줄이지 않고 한 줄 원문 그대로다. 출결 다이얼로그(COMMON-TEXT-LAYOUT.28) · 급여 대시보드(UI-INTEGRATION.33)와 같은 판정이다.
    final tabsFit = TextLayout.tabsFit(context, MediaQuery.sizeOf(context).width, 3);

    return AppPageScaffold(
      title: hasActiveFilter
          ? '리뷰 관리 · $_selectedYear년 $_selectedMonth월'
          : '리뷰 관리',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loadReviews,
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
      // [DESIGN-PATCH-4] TabBar → AppPageScaffold.bottom (기존 body Container 제거)
      bottom: TabBar(
        controller: _tabController,
        isScrollable: !tabsFit,
        tabAlignment: tabsFit ? null : TabAlignment.start,
        labelPadding: tabsFit
            ? null
            : EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 12)),
        indicatorColor: theme.primaryColor,
        indicatorWeight: 3,
        labelColor: theme.primaryColor,
        unselectedLabelColor: AppColors.textSecondary, // [DU429] grey400(1.88:1) → DU242 · DU342 탭과 같은 보조 글자
        dividerColor: AppColors.grey100,
        labelStyle: ResponsiveHelper.smallStyle(context,
            fontWeight: FontWeight.w600),
        unselectedLabelStyle: ResponsiveHelper.smallStyle(context),
        tabs: [
          Tab(child: AppTabLabel(label: '작성',
              count: _writtenReviews.length, badgeColor: theme.primaryColor)),
          Tab(child: AppTabLabel(label: '받음',
              count: _receivedReviews.length, badgeColor: AppColors.brand)),
          Tab(child: AppTabLabel(
              label: '미작성',
              count: _pendingRequests.length,
              badgeColor: AppColors.brand,
              urgent: _pendingIsUrgent)),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget()
          : _hasError
              ? AppEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: '리뷰를 불러오지 못했습니다',
                  subtitle: '네트워크 상태를 확인 후 당겨서 새로고침하세요',
                )
              : Column(
                  children: [
                    // [DU431] 320@2.0 에서 '근무자 이름…' 으로 잘리던 안내를 두 줄까지 낱말 사이에서 바꿔 전문을 보인다(문구 그대로).
                    AppSearchBar(
                      controller: _searchCtrl,
                      hintText: '근무자 이름으로 검색',
                      hintMaxLines: 2,
                    ),
                    _buildMonthFilter(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildReviewList(
                            _writtenReviews,
                            isWritten: true,
                            hasMore: _hasMoreWritten,
                            isLoadingMore: _isLoadingMoreWritten,
                            onLoadMore: _loadMoreWritten,
                          ),
                          _buildReviewList(
                            _receivedReviews,
                            isWritten: false,
                            hasMore: _hasMoreReceived,
                            isLoadingMore: _isLoadingMoreReceived,
                            onLoadMore: _loadMoreReceived,
                          ),
                          _buildPendingRequestList(),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  // ─── 연도+월 필터 ────────────────────────────────────────────

  Widget _buildMonthFilter() {
    final years = _availableYears;
    final months = _availableMonths; // {월: 건수}
    final yearIdx = years.indexOf(_selectedYear);

    return Container(
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, thickness: 1, color: AppColors.grey100),

          // ── 연도 네비게이션 (데이터가 1개 연도뿐이면 숨김)
          if (years.length > 1)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
                vertical: ResponsiveHelper.spacing(context, 6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _YearNavButton(
                    icon: Icons.chevron_left,
                    enabled: yearIdx < years.length - 1,
                    onTap: () => setState(() {
                      _selectedYear = years[yearIdx + 1];
                      _selectedMonth = 0;
                      _recomputeDerived();
                    }),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                  Text(
                    '$_selectedYear년',
                    style: ResponsiveHelper.bodyStyle(context)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                  _YearNavButton(
                    icon: Icons.chevron_right,
                    enabled: yearIdx > 0,
                    onTap: () => setState(() {
                      _selectedYear = years[yearIdx - 1];
                      _selectedMonth = 0;
                      _recomputeDerived();
                    }),
                  ),
                ],
              ),
            ),

          // ── 월 칩: 데이터 있는 달만 + 건수 표시
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            child: Row(
              children: [
                _buildMonthChip(label: '전체', value: 0),
                ...(() {
                  final sorted = months.entries.toList()
                    ..sort((a, b) => a.key.compareTo(b.key));
                  return sorted.map((e) => Padding(
                    padding: EdgeInsets.only(
                        left: ResponsiveHelper.spacing(context, 6)),
                    child: _buildMonthChip(
                        label: '${e.key}월',
                        value: e.key,
                        count: e.value),
                  ));
                })(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthChip({
    required String label,
    required int value,
    int? count,
  }) {
    final isSelected = _selectedMonth == value;
    // 월 칩 label: count 있으면 "5월 3" 형태로 표시
    final chipLabel = count != null && count > 0
        ? '$label  $count'
        : label;
    return AppFilterChip(
      label: chipLabel,
      isSelected: isSelected,
      onTap: () => setState(() {
        _selectedMonth = value;
        _recomputeDerived();
      }),
    );
  }

  // ─── 리뷰 목록 탭 ─────────────────────────────────────────────

  Widget _buildReviewList(
    List<MonthlyReviewModel> reviews, {
    required bool isWritten,
    bool hasMore = false,
    bool isLoadingMore = false,
    VoidCallback? onLoadMore,
  }) {
    if (reviews.isEmpty) {
      return AppEmptyState(
        icon: isWritten ? Icons.rate_review : Icons.reviews,
        title: isWritten ? '작성한 리뷰가 없습니다' : '받은 리뷰가 없습니다',
        subtitle: _selectedMonth > 0 ? '$_selectedMonth월 필터 적용 중' : null,
      );
    }

    // 검색 필터 적용
    final filtered = _searchQuery.isEmpty
        ? reviews
        : reviews.where((r) {
            final name = (isWritten
                    ? (r.targetUserName ?? '')
                    : r.reviewerName)
                .toLowerCase();
            return name.contains(_searchQuery);
          }).toList();

    if (filtered.isEmpty && _searchQuery.isNotEmpty) {
      return AppEmptyState(
        icon: Icons.search_off_rounded,
        title: '검색 결과가 없습니다',
        subtitle: '"$_searchQuery"에 해당하는 근무자가 없습니다',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReviews,
      child: ListView.builder(
        padding: ResponsiveHelper.listPadding(context),
        itemCount: filtered.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (hasMore && index == filtered.length) {
            return Padding(
              padding: EdgeInsets.only(
                top: ResponsiveHelper.spacing(context, 4),
                bottom: ResponsiveHelper.spacing(context, 16),
              ),
              child: Center(
                child: isLoadingMore
                    ? const CircularProgressIndicator()
                    : TextButton.icon(
                        onPressed: onLoadMore,
                        icon: const Icon(Icons.expand_more),
                        label: const Text('더 보기'),
                      ),
              ),
            );
          }
          final r = filtered[index];
          return ReviewCard(
            review: r,
            perspective: isWritten
                ? ReviewCardPerspective.adminWritten
                : ReviewCardPerspective.adminReceived,
            onReply: isWritten ? null : () => _showReplyDialog(r),
            deadlineSubtext: _deadlineSubtext(r.requestId),
          );
        },
      ),
    );
  }

  // ─── 미작성 탭 ────────────────────────────────────────────────

  Widget _buildPendingRequestList() {
    if (_pendingRequests.isEmpty) {
      return const AppEmptyState(
        icon: Icons.check_circle_outline,
        title: '미작성 리뷰가 없습니다',
      );
    }

    final activePending  = _filteredActivePending;
    final expiredPending = _filteredExpiredPending;
    final now = _pendingNow;

    // 구분선 포함 전체 아이템 목록 사전 구성 — ListView.builder 에서 지연 렌더링
    final items = <Object>[
      ...activePending,
      if (expiredPending.isNotEmpty) ...[
        if (activePending.isNotEmpty) _DividerMarker.expired,
        ...expiredPending,
      ],
    ];

    return RefreshIndicator(
      onRefresh: _loadReviews,
      child: ListView.builder(
        padding: ResponsiveHelper.listPadding(context),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          if (item == _DividerMarker.expired) {
            return Padding(
              padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 8)),
              child: Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 8)),
                    child: Text(
                      '기한 만료',
                      style: ResponsiveHelper.tinyStyle(
                          context, color: AppColors.textTertiary),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
            );
          }
          final req = item as ReviewRequestModel;
          return _buildPendingRequestCard(context, req,
              now: now, isExpired: expiredPending.contains(req));
        },
      ),
    );
  }

  Widget _buildPendingRequestCard(BuildContext context, ReviewRequestModel req,
      {bool isExpired = false, required DateTime now}) {
    final theme = Theme.of(context);
    final isDeadlineSoon =
        !req.isDeadlinePassed && req.deadline.difference(now).inDays <= 3;
    final displayName = req.workerName.isNotEmpty
        ? req.workerName
        : (_resolvedWorkerNames[req.workerId] ?? '근무자');
    // [DU430] '임박!' 은 마감 글과 따로 항목이다(아래 Wrap) — 장식 '·' 없이.
    final deadlineText = isExpired ? '기한 만료' : '마감 ${_formatDate(req.deadline)}';

    // [DU429] 만료 카드를 Opacity(0.5)로 흐리게 하던 것을 뺐다 — 글자가 통째로 반투명이라 약 1.5:1 이었다.
    //   만료는 '기한 만료' 글 · 아이콘 · 그림자 없음 · 작성 버튼 없음 · 낮은 강조 글자(textTertiary)로 구분한다.
    return Container(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDeadlineSoon
                ? AppColors.error.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
          boxShadow: isExpired
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Padding(
          padding: ResponsiveHelper.symmetricPadding(
            context,
            horizontal: 16,
            vertical: 12,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: ResponsiveHelper.iconSize(context, 20),
                backgroundColor: isExpired
                    ? AppColors.grey200
                    : theme.primaryColor.withValues(alpha: 0.15),
                child: displayName.isNotEmpty
                    ? Text(
                        displayName[0],
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                          color: isExpired
                              ? AppColors.textTertiary
                              : theme.primaryColor,
                        ),
                      )
                    : Icon(Icons.person,
                        size: ResponsiveHelper.iconSize(context, 18),
                        color: isExpired ? AppColors.textTertiary : theme.primaryColor),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TextLayout.identity(displayName),
                      semanticsLabel: displayName,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                        color: isExpired ? AppColors.textTertiary : null,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                    // 기간 + 마감일을 한 줄로 합쳐 카드 높이 절감
                    // [TEXT-LAYOUT-CONSUMER.29] 들어가면 한 줄, 모자라면 마감 묶음이 통째로 다음 줄.
                    //   기기 320dp·1.0 에서 '마감 2026.11…' 로 날짜가 잘렸고 큰 글자에서 '2026년 / 10월' 로 갈렸다.
                    Wrap(
                      spacing: ResponsiveHelper.spacing(context, 10),
                      runSpacing: ResponsiveHelper.spacing(context, 2),
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          TextLayout.keepWords(req.periodText),
                          semanticsLabel: req.periodText,
                          style: ResponsiveHelper.smallStyle(
                              context, color: AppColors.textSecondary),
                        ),
                        // [DU440] 320@2.0 에서 마감 글이 '마감' / 날짜 두 줄이 되면 아이콘이 두 줄 가운데에 떠 어느 줄 표시인지 흐렸다.
                        //   공용 FirstLineIcon 으로 첫 줄 가운데에 둔다(크기는 그대로 — DU361 규칙: 배율로 아이콘을 키우지 않음).
                        Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        FirstLineIcon(
                          isExpired
                              ? Icons.event_busy
                              : isDeadlineSoon
                                  ? Icons.alarm
                                  : Icons.schedule,
                          size: ResponsiveHelper.iconSize(context, 12),
                          textStyle: ResponsiveHelper.tinyStyle(context),
                          color: isExpired
                              ? AppColors.textTertiary
                              : isDeadlineSoon
                                  ? AppColors.error
                                  : AppColors.textSecondary,
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                        // [DU429 · DU430] 마감 글이 칸보다 길면(320@2.0) '마감' / 날짜 사이 공백에서만 줄을 바꾼다 — softWrap:false 는 넘쳤다.
                        //   날짜 단독 122.4 ≤ 마감 칸 135.0(진단 du430)이라 날짜는 한 덩어리로 읽힌다.
                        Flexible(
                          child: Text(
                            TextLayout.keepWords(deadlineText),
                            semanticsLabel: deadlineText,
                            style: ResponsiveHelper.tinyStyle(
                              context,
                              color: isExpired
                                  ? AppColors.textTertiary
                                  : isDeadlineSoon
                                      ? AppColors.errorDark
                                      : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        ]),
                        // [DU430] '임박!' 따로 항목 — 320@2.0 에서 '· 임박!' 이 줄 첫머리에 오던 것을 없앴다(감사108 F108-1).
                        if (isDeadlineSoon)
                          Text(
                            '임박!',
                            style: ResponsiveHelper.tinyStyle(context, color: AppColors.errorDark),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!req.isDeadlinePassed)
                ElevatedButton(
                  onPressed: () => _openReviewFromRequest(req),
                  style: ElevatedButton.styleFrom(
                    // [DU429] 임박이어도 주 버튼은 브랜드 채움이다(흰 글자 / error 는 3.68:1 · 빨강은 확인 순간에만).
                    //   임박은 카드 빨간 테두리 · 알람 아이콘 · '임박!' errorDark 글자가 알린다.
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 14),
                      vertical: ResponsiveHelper.spacing(context, 8),
                    ),
                  ),
                  child: Text(
                    '작성',
                    style: ResponsiveHelper.smallStyle(context,
                        color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
    );
  }

  Future<void> _openReviewFromRequest(ReviewRequestModel req) async {
    final userProvider = context.read<UserProvider>();
    final reviewer = userProvider.currentUser;
    if (reviewer == null) return;

    // [R7-RER.2 §5] 급여 마감을 되돌린 달은 근거가 없다 — 폼을 열지 않는다.
    //   관리자 자신이 마감을 취소한 경우도 포함된다. 영구 차단이 아니라
    //   보류이므로 복구 경로를 함께 말한다. canonical 경계는 서버다.
    if (req.isEligibilitySuspended) {
      ToastHelper.showInfo(MonthlyReviewService.eligibilitySuspendedMessage);
      return;
    }

    // worker 성별/나이 + 실제 근무일 수 병렬 조회
    String? workerGender;
    int? workerAge;
    int workDaysInMonth = 0;
    int onTimeDays = 0;
    int lateDays = 0;

    final yearMonthStr =
        '${req.reviewYear}-${req.reviewMonth.toString().padLeft(2, '0')}';

    try {
      // CF 경유: callableGetUsersBatch + callableGetAdminAttendances 병렬 실행
      final usersBatchCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetUsersBatch',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final attendanceCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetAdminAttendances',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final results = await Future.wait([
        usersBatchCallable.call<Map<String, dynamic>>({
          'uids': [req.workerId],
          'businessId': req.businessId,
        }),
        attendanceCallable.call<Map<String, dynamic>>({
          'businessId': req.businessId,
          'yearMonth': yearMonthStr,
          'userId': req.workerId,
        }),
      ]);

      final usersResult = results[0] as HttpsCallableResult<Map<String, dynamic>>;
      // 플러그인은 최상위만 Map<String, dynamic> 으로 바꾼다 — 안쪽은
      //   Map<Object?, Object?> 이므로 cast 로 감싼다(직접 캐스팅은 TypeError).
      final users =
          (usersResult.data['users'] as Map?)?.cast<String, dynamic>() ?? {};
      final workerData =
          (users[req.workerId] as Map?)?.cast<String, dynamic>();
      if (workerData != null) {
        workerGender = workerData['gender'] as String?;
        final birthDateRaw = workerData['birthDate'];
        if (birthDateRaw is Map) {
          final s = (birthDateRaw['_seconds'] as num? ?? 0).toInt();
          workerAge = DateTime.now().year -
              DateTime.fromMillisecondsSinceEpoch(s * 1000).year;
        }
      }

      final cfResult = results[1] as HttpsCallableResult<Map<String, dynamic>>;
      final cfItems = (cfResult.data['items'] as List<dynamic>? ?? []);
      // [R7-P1-4 §11] canonical 실근무 판정 — 서버 srvIsActualFinalizedWork와 같다.
      //   이전에는 wageStatus만 봤다. 그런데 callableBatchSetNoShow는 노쇼에도
      //   wageStatus를 confirmed로 쓰므로(0원 마감), 오지 않은 날이 근무일로
      //   집계되고 있었다. 리뷰 작성자에게 보이는 `이번 달 N일 근무`가
      //   실제보다 많아지는 경로다.
      // [REVIEW-ABSENCE-METRIC] 정시·지각도 같은 실근무 확정 행에서 센다 —
      //   넘기지 않으면 작성창이 `근무일 − 0 − 0` 을 결근으로 그렸다.
      final summary =
          AttendanceModel.reviewAttendanceSummary(cfItems.whereType<Map>());
      workDaysInMonth = summary.workDays;
      onTimeDays = summary.onTime;
      lateDays = summary.late;
    } catch (e) {
      debugPrint('❌ 리뷰 요청 정보 로드 실패: $e');
      if (mounted) ToastHelper.showError('추가 정보를 불러오는 데 실패했습니다');
    }

    if (!mounted) return;

    final result = await showMonthlyReviewDialog(
      context,
      reviewerId: reviewer.uid,
      reviewerName: reviewer.name,
      businessId: req.businessId,
      businessName: req.businessName,
      targetUserId: req.workerId,
      targetUserName: req.workerName,
      targetUserGender: workerGender,
      targetUserAge: workerAge,
      reviewYear: req.reviewYear,
      reviewMonth: req.reviewMonth,
      workDaysInMonth: workDaysInMonth,
      normalAttendanceDays: onTimeDays,
      lateDays: lateDays,
      requestId: req.id,
    );

    if (result == true && mounted) {
      await _loadReviews();
    }
  }

  String _deadlineSubtext(String? requestId) {
    if (requestId == null) return '상대방 작성 후 공개';
    final deadline = _requestDeadlines[requestId];
    if (deadline == null) return '상대방 작성 후 공개';
    return '상대방 미작성 시 ${deadline.month}/${deadline.day} 자동공개';
  }

  String _formatDate(DateTime date) => FormatHelper.formatDateDot(date);
}

// ─── 연도 네비게이션 버튼 ────────────────────────────────────────

class _YearNavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _YearNavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.grey100 : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
          child: Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 20),
            color: enabled ? AppColors.grey600 : AppColors.grey300,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FC-ADM-01 — 리뷰 답변 작성 다이얼로그
// AlertDialog + TextEditingController 소유권: State가 직접 소유·해제
// ══════════════════════════════════════════════════════════════════════════════
class _ReviewReplyDialog extends StatefulWidget {
  const _ReviewReplyDialog();

  @override
  State<_ReviewReplyDialog> createState() => _ReviewReplyDialogState();
}

class _ReviewReplyDialogState extends State<_ReviewReplyDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('답변 작성'),
      content: TextField(
        controller: _ctrl,
        maxLines: 4,
        maxLength: 500,
        decoration: const InputDecoration(
          hintText: '리뷰에 대한 답변을 작성해주세요',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(context); // null = 취소
          },
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(context, _ctrl.text.trim()); // String = 확인
          },
          child: const Text('등록'),
        ),
      ],
    );
  }
}
