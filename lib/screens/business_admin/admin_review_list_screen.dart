// lib/screens/business_admin/admin_review_list_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
import '../../models/core/user_model.dart';

// Services
import '../../services/monthly_review_service.dart';

// Dialogs
import '../../widgets/dialogs/monthly_review_dialog.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/app_search_bar.dart';
import '../../widgets/common/app_tab_label.dart';
import '../../widgets/common/app_filter_chip.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../utils/business_picker_helper.dart';

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

  // 페이지네이션 상태
  DocumentSnapshot? _cursorWritten;
  DocumentSnapshot? _cursorReceived;
  bool _hasMoreWritten = false;
  bool _hasMoreReceived = false;
  bool _isLoadingMoreWritten = false;
  bool _isLoadingMoreReceived = false;
  String? _cachedBusinessId;

  // 필터 상태
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = 0; // 0 = 전체

  // 데이터 있는 연도 목록 (자동 추출)
  List<int> get _availableYears {
    final years = <int>{};
    for (final r in _rawWritten)  { years.add(r.reviewYear); }
    for (final r in _rawReceived) { years.add(r.reviewYear); }
    for (final r in _rawPending)  { years.add(r.reviewYear); }
    if (years.isEmpty) years.add(DateTime.now().year);
    return (years.toList()..sort()).reversed.toList();
  }

  // 선택된 연도에서 데이터 있는 월 목록 (건수 포함)
  Map<int, int> get _availableMonths {
    final map = <int, int>{};
    for (final r in _rawWritten) {
      if (r.reviewYear == _selectedYear) {
        map[r.reviewMonth] = (map[r.reviewMonth] ?? 0) + 1;
      }
    }
    for (final r in _rawReceived) {
      if (r.reviewYear == _selectedYear) {
        map[r.reviewMonth] = (map[r.reviewMonth] ?? 0) + 1;
      }
    }
    for (final r in _rawPending) {
      if (r.reviewYear == _selectedYear) {
        map[r.reviewMonth] = (map[r.reviewMonth] ?? 0) + 1;
      }
    }
    return map;
  }

  // 현재 필터 적용된 리스트
  List<MonthlyReviewModel> get _writtenReviews => _rawWritten
      .where((r) => r.reviewYear == _selectedYear &&
          (_selectedMonth == 0 || r.reviewMonth == _selectedMonth))
      .toList();

  List<MonthlyReviewModel> get _receivedReviews => _rawReceived
      .where((r) => r.reviewYear == _selectedYear &&
          (_selectedMonth == 0 || r.reviewMonth == _selectedMonth))
      .toList();

  List<ReviewRequestModel> get _pendingRequests => _rawPending
      .where((r) => r.reviewYear == _selectedYear &&
          (_selectedMonth == 0 || r.reviewMonth == _selectedMonth))
      .toList();

  // 검색
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
    // addPostFrameCallback: 피커 등 UI 작업을 위해 첫 프레임 이후 로드
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadReviews());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _showReplyDialog(MonthlyReviewModel review) async {
    if (_isProcessing) return;
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('답변 작성'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: '리뷰에 대한 답변을 작성해주세요',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('등록'),
          ),
        ],
      ),
    );
    final text = ctrl.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (confirmed != true || !mounted) return;
    if (text.isEmpty) return;
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
      final picked = await BusinessPickerHelper.pick(context);
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

      // workerName 누락 항목 보완 조회 (CF callableGetUsersBatch 경유 — 서버 소속 검증)
      // [S-01 fix] Future.wait 이후 mounted 체크 — CF 과금·dispose된 State 쓰기 방지
      if (!mounted) return;
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
        } catch (_) {}
        for (final uid in ids) {
          resolvedMap.putIfAbsent(uid, () => '근무자');
        }
        _resolvedWorkerNames = resolvedMap;
      }

      // 선택된 연도가 데이터에 없으면 최신 연도로 자동 이동
      final years = _availableYears;
      if (years.isNotEmpty && !years.contains(_selectedYear)) {
        _selectedYear = years.first;
        _selectedMonth = 0;
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
        startAfter: _cursorWritten,
      );
      if (!mounted) return;
      setState(() {
        _rawWritten = [..._rawWritten, ...page.records];
        _cursorWritten = page.cursor;
        _hasMoreWritten = page.hasMore;
        _isLoadingMoreWritten = false;
      });
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
        startAfter: _cursorReceived,
      );
      if (!mounted) return;
      setState(() {
        _rawReceived = [..._rawReceived, ...page.records];
        _cursorReceived = page.cursor;
        _hasMoreReceived = page.hasMore;
        _isLoadingMoreReceived = false;
      });
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

    return GradientScaffold(
      title: hasActiveFilter
          ? '리뷰 관리 · $_selectedYear년 $_selectedMonth월'
          : '리뷰 관리',
      onRefresh: _loadReviews,
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
                // 탭 (흰 영역) — 균등 폭, 텍스트만
                Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: theme.primaryColor,
                    indicatorWeight: 3,
                    labelColor: theme.primaryColor,
                    unselectedLabelColor: AppColors.grey400,
                    dividerColor: AppColors.grey100,
                    labelStyle: ResponsiveHelper.smallStyle(context,
                        fontWeight: FontWeight.w600),
                    unselectedLabelStyle:
                        ResponsiveHelper.smallStyle(context),
                    tabs: [
                      Tab(child: AppTabLabel(label: '작성',
                          count: _writtenReviews.length, badgeColor: theme.primaryColor)),
                      Tab(child: AppTabLabel(label: '받음',
                          count: _receivedReviews.length, badgeColor: AppColors.info)),
                      Tab(child: AppTabLabel(
                          label: '미작성',
                          count: _pendingRequests.length,
                          badgeColor: AppColors.error,
                          urgent: _pendingRequests.any((r) => !r.isDeadlinePassed && r.deadline.difference(DateTime.now()).inDays <= 3))),
                    ],
                  ),
                ),
                // 검색바
                Container(
                  color: Colors.white,
                  padding: EdgeInsets.fromLTRB(
                    ResponsiveHelper.spacing(context, 12),
                    0,
                    ResponsiveHelper.spacing(context, 12),
                    ResponsiveHelper.spacing(context, 8),
                  ),
                  child: AppSearchBar(
                    controller: _searchCtrl,
                    hintText: '근무자 이름으로 검색',
                  ),
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
      color: Colors.white,
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
      onTap: () => setState(() => _selectedMonth = value),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isWritten ? Icons.rate_review : Icons.reviews,
              size: ResponsiveHelper.iconSize(context, 64),
              color: AppColors.grey300,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              isWritten ? '작성한 리뷰가 없습니다' : '받은 리뷰가 없습니다',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
            ),
            if (_selectedMonth > 0) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              Text(
                '$_selectedMonth월 필터 적용 중',
                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
              ),
            ],
          ],
        ),
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
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.search_off_rounded,
              size: ResponsiveHelper.iconSize(context, 48),
              color: AppColors.grey300),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Text('"$_searchQuery" 검색 결과 없음',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500)),
        ]),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: ResponsiveHelper.iconSize(context, 64),
              color: AppColors.grey300,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '미작성 리뷰가 없습니다',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
            ),
          ],
        ),
      );
    }

    final filteredPending = _searchQuery.isEmpty
        ? _pendingRequests
        : _pendingRequests.where((r) {
            final name = r.workerName.isNotEmpty
                ? r.workerName
                : (_resolvedWorkerNames[r.workerId] ?? '');
            return name.toLowerCase().contains(_searchQuery);
          }).toList();

    final activePending = filteredPending.where((r) => !r.isDeadlinePassed).toList();
    final expiredPending = filteredPending.where((r) => r.isDeadlinePassed).toList();

    return RefreshIndicator(
      onRefresh: _loadReviews,
      child: ListView(
        padding: ResponsiveHelper.listPadding(context),
        children: [
          ...activePending.map((req) => _buildPendingRequestCard(context, req)),
          if (expiredPending.isNotEmpty) ...[
            if (activePending.isNotEmpty)
              Padding(
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
                            context, color: AppColors.grey400),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
              ),
            ...expiredPending.map(
                (req) => _buildPendingRequestCard(context, req, isExpired: true)),
          ],
        ],
      ),
    );
  }

  Widget _buildPendingRequestCard(BuildContext context, ReviewRequestModel req,
      {bool isExpired = false}) {
    final theme = Theme.of(context);
    final isDeadlineSoon =
        !req.isDeadlinePassed && req.deadline.difference(DateTime.now()).inDays <= 3;
    final displayName = req.workerName.isNotEmpty
        ? req.workerName
        : (_resolvedWorkerNames[req.workerId] ?? '근무자');

    return Opacity(
      opacity: isExpired ? 0.5 : 1.0,
      child: Container(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: Colors.white,
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
                              ? AppColors.grey400
                              : theme.primaryColor,
                        ),
                      )
                    : Icon(Icons.person,
                        size: ResponsiveHelper.iconSize(context, 18),
                        color: isExpired ? AppColors.grey400 : theme.primaryColor),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                        color: isExpired ? AppColors.grey500 : null,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                    // 기간 + 마감일을 한 줄로 합쳐 카드 높이 절감
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            req.periodText,
                            style: ResponsiveHelper.smallStyle(
                                context, color: AppColors.grey500),
                          ),
                        ),
                        Icon(
                          isExpired
                              ? Icons.event_busy
                              : isDeadlineSoon
                                  ? Icons.alarm
                                  : Icons.schedule,
                          size: ResponsiveHelper.iconSize(context, 12),
                          color: isExpired
                              ? AppColors.grey400
                              : isDeadlineSoon
                                  ? AppColors.error
                                  : AppColors.grey500,
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                        Flexible(
                          child: Text(
                            isExpired
                                ? '기한 만료'
                                : '마감 ${_formatDate(req.deadline)}'
                                    '${isDeadlineSoon ? ' · 임박!' : ''}',
                            style: ResponsiveHelper.tinyStyle(
                              context,
                              color: isExpired
                                  ? AppColors.grey400
                                  : isDeadlineSoon
                                      ? AppColors.error
                                      : AppColors.grey500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
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
                    backgroundColor:
                        isDeadlineSoon ? AppColors.error : theme.primaryColor,
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
      ),
    );
  }

  Future<void> _openReviewFromRequest(ReviewRequestModel req) async {
    final userProvider = context.read<UserProvider>();
    final reviewer = userProvider.currentUser;
    if (reviewer == null) return;

    // worker 성별/나이 + 실제 근무일 수 병렬 조회
    String? workerGender;
    int? workerAge;
    int workDaysInMonth = 0;

    final yearMonthStr =
        '${req.reviewYear}-${req.reviewMonth.toString().padLeft(2, '0')}';

    try {
      // CF 경유: callableGetAdminAttendances yearMonth 모드 + user 조회 병렬 실행
      final attendanceCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetAdminAttendances',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(req.workerId).get(),
        attendanceCallable.call<Map<String, dynamic>>({
          'businessId': req.businessId,
          'yearMonth': yearMonthStr,
          'userId': req.workerId,
        }),
      ]);

      final userSnap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      if (userSnap.exists && userSnap.data() != null) {
        final worker = UserModel.tryFromMap(userSnap.data()!, userSnap.id);
        workerGender = worker?.gender;
        workerAge = worker?.age;
      }

      final cfResult = results[1] as HttpsCallableResult<Map<String, dynamic>>;
      final cfItems = (cfResult.data['items'] as List<dynamic>? ?? []);
      // wageStatus confirmed/transferred 인 건수만 근무일 수로 집계
      workDaysInMonth = cfItems.where((e) {
        final status = (e as Map)['wageStatus'] as String?;
        return status == 'confirmed' || status == 'transferred';
      }).length;
    } catch (e) {
      debugPrint('❌ 리뷰 요청 정보 로드 실패: $e');
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
