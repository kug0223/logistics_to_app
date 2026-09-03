import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/core/to_model.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/to_filter_state.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/slot_model.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/common/skeleton_widget.dart';
import '../../../widgets/user/cards/user_to_card.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../widgets/inputs/region_picker_sheet.dart';
import '../../../services/algolia_service.dart';
import '../../../widgets/pickers/date_picker_bottom_sheet.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_search_bar.dart';
import '../../../theme/app_colors.dart';
import '../my_applications_screen.dart';
import '../user_tab_scope.dart';

/// 일자리 탭 — 일자리 찾기 + 내 지원 탭 구조 (Phase 2)
///
/// 탭:
///   0: 일자리 찾기 — 공고 목록 (검색·빠른필터·컴팩트 카드)
///   1: 내 지원 — MyApplicationsScreen
///
/// Phase 1 허브 화면('무엇을 찾으시나요?') 제거.
/// AllTOListScreen의 데이터 로딩·필터 로직을 이 화면으로 통합.
class UserJobTab extends StatefulWidget {
  const UserJobTab({super.key});

  @override
  State<UserJobTab> createState() => _UserJobTabState();
}

class _UserJobTabState extends State<UserJobTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── 공고 목록 상태 ────────────────────────────────────────────────
  final FirestoreService _firestoreService = FirestoreService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  TOFilterState _filter = const TOFilterState();

  List<TOModel> _allTOList = [];
  List<TOModel> _displayList = [];
  List<ApplicationModel> _myApplications = [];

  List<String> _availableCities = [];
  Map<String, List<String>> _districtMap = {};

  String? _lastToId;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;
  int _generation = 0;

  final Map<String, List<WorkDetailModel>> _workDetailsCache = {};
  final Map<String, List<SlotModel>> _slotsCache = {};

  Timer? _searchDebounce;

  bool _isLoading = true;
  bool _fetchInProgress = false;
  bool _myApplicationsLoaded = false;

  // ── 초기화 ──────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadAllTOs();
    });
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
  }

  /// 홈 CTA → 날짜 지정 진입 감지.
  ///
  /// [UserTabScope.pendingJobDate]가 non-null이면 홈에서 날짜를 지정해서
  /// 이 탭으로 진입한 것이다. 해당 날짜를 _filter.dateRange에 적용하고
  /// 즉시 clearPendingJobDate()로 소비 처리한다.
  ///
  /// 하단 BottomNavigationBar로 직접 진입한 경우 pendingJobDate는 null이므로
  /// 기존 _filter 상태를 그대로 유지한다.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = UserTabScope.of(context);
    final pending = scope?.pendingJobDate;
    if (pending != null) {
      // clearFn을 여기서 캡처한다.
      // postFrameCallback 안에서 UserTabScope.of(context)를 재호출하면
      // 빌드 페이즈 밖에서의 dependOnInheritedWidgetOfExactType 호출로
      // debug assertion이 터져 콜백이 중단되므로, 반드시 클로저로 미리 캡처해야 한다.
      final clearFn = scope!.clearPendingJobDate;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        clearFn(); // root 상태 소비 — context 조회 없이 직접 호출
        _onFilterChanged(_filter.copyWith(
          dateRange: DateTimeRange(start: pending, end: pending),
        ));
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── 이벤트 핸들러 ────────────────────────────────────────────────

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      final keyword = _searchController.text.trim();
      final current = _filter.keyword ?? '';
      if (keyword == current) return;
      _onFilterChanged(keyword.isEmpty
          ? _filter.copyWith(clearKeyword: true)
          : _filter.copyWith(keyword: keyword));
    });
  }

  void _onScroll() {
    if (_isLoading || _isLoadingMore || !_hasMoreData) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMoreTOs();
    }
  }

  // ── 데이터 로딩 ──────────────────────────────────────────────────

  Future<void> _loadAllTOs({bool forceRefresh = false}) async {
    if (_fetchInProgress) return;
    _fetchInProgress = true;
    _generation++;
    setState(() {
      _isLoading = true;
      _lastToId = null;
      _hasMoreData = true;
      _allTOList = [];
      _workDetailsCache.clear();
      _slotsCache.clear();
      if (forceRefresh) _myApplicationsLoaded = false;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      final appsFuture = (uid != null && !_myApplicationsLoaded)
          ? _firestoreService.getMyApplications(uid)
          : Future.value(_myApplications);

      List<TOModel> toList;
      String? lastToId;
      bool hasMore;

      if (_filter.showFavoritesOnly) {
        final favoriteIds =
            userProvider.currentUser?.favoriteToIds ?? const [];
        toList = favoriteIds.isEmpty
            ? []
            : await _firestoreService.getTOsByIds(favoriteIds);
        lastToId = null;
        hasMore = false;
      } else if (_filter.keyword?.isNotEmpty == true &&
          AlgoliaService.isConfigured) {
        final ids = await AlgoliaService.searchTOIds(_filter.keyword!,
            filter: _filter);
        toList = await _firestoreService.getTOsByIds(ids);
        lastToId = null;
        hasMore = false;
      } else {
        final tosResult =
            await _firestoreService.getPublishedTOsPaged(filter: _filter);
        toList = tosResult['items'] as List<TOModel>;
        lastToId = tosResult['lastToId'] as String?;
        hasMore = tosResult['hasMore'] as bool;
      }

      final myApps = await appsFuture;
      if (!mounted) return;

      final regionResult = _computeRegionOptions(toList);
      final displayList = _computeDisplayList(toList);
      _fetchInProgress = false;
      setState(() {
        _allTOList = toList;
        _lastToId = lastToId;
        _hasMoreData = hasMore;
        _myApplications = myApps;
        _myApplicationsLoaded = true;
        _availableCities = regionResult.cities;
        _districtMap = regionResult.districtMap;
        _displayList = displayList;
        _isLoading = false;
      });
      if (toList.isEmpty && hasMore) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadMoreTOs();
        });
      }
    } catch (e) {
      debugPrint('❌ TO 목록 로드 실패: $e');
      if (!mounted) return;
      _fetchInProgress = false;
      setState(() => _isLoading = false);
      ToastHelper.showError('공고 목록을 불러오는데 실패했습니다.');
    }
  }

  Future<void> _loadMoreTOs() async {
    if (_isLoading || _isLoadingMore || !_hasMoreData) return;
    if (_lastToId == null) return;
    if (!mounted) return;

    final gen = _generation;
    setState(() => _isLoadingMore = true);

    try {
      final tosResult = await _firestoreService.getPublishedTOsPaged(
        lastToId: _lastToId,
        filter: _filter,
      );
      final toList = tosResult['items'] as List<TOModel>;

      if (!mounted || _generation != gen) {
        _isLoadingMore = false;
        return;
      }
      if (toList.isEmpty) {
        setState(() {
          _hasMoreData = false;
          _isLoadingMore = false;
        });
        return;
      }

      final mergedList = [..._allTOList, ...toList];
      final newRegionResult = _computeRegionOptions(toList);
      final mergedCities =
          {..._availableCities, ...newRegionResult.cities}.toList()..sort();
      final mergedDistricts = <String, List<String>>{};
      for (final city in mergedCities) {
        final existing = _districtMap[city] ?? const [];
        final added = newRegionResult.districtMap[city] ?? const [];
        mergedDistricts[city] = ({...existing, ...added}).toList()..sort();
      }
      final displayList = _computeDisplayList(mergedList);
      setState(() {
        _allTOList = mergedList;
        _lastToId = tosResult['lastToId'] as String?;
        _hasMoreData = tosResult['hasMore'] as bool;
        _availableCities = mergedCities;
        _districtMap = mergedDistricts;
        _displayList = displayList;
        _isLoadingMore = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _displayList.isEmpty && _hasMoreData && !_isLoadingMore) {
          _loadMoreTOs();
        }
      });
    } catch (e) {
      debugPrint('❌ TO 추가 로드 실패: $e');
      if (!mounted) {
        _isLoadingMore = false;
        return;
      }
      setState(() => _isLoadingMore = false);
      ToastHelper.showError('추가 공고를 불러오지 못했습니다');
    }
  }

  // ── 필터 유틸 ────────────────────────────────────────────────────

  ({List<String> cities, Map<String, List<String>> districtMap})
      _computeRegionOptions(List<TOModel> toList) {
    final cities = <String>{};
    final districtMap = <String, Set<String>>{};
    for (final to in toList) {
      final city = to.businessCity;
      if (city != null && city.isNotEmpty) {
        cities.add(city);
        final district = to.businessDistrict;
        if (district != null && district.isNotEmpty) {
          districtMap.putIfAbsent(city, () => {}).add(district);
        }
      }
    }
    return (
      cities: cities.toList()..sort(),
      districtMap:
          districtMap.map((k, v) => MapEntry(k, v.toList()..sort())),
    );
  }

  /// 로컬 표시 목록 계산
  /// [withFilter]: 임시 필터 적용 (필터 시트 실시간 카운트 미리보기용)
  ///               생략 시 현재 _filter 사용
  List<TOModel> _computeDisplayList(List<TOModel> toList,
      {TOFilterState? withFilter}) {
    final f = withFilter ?? _filter;
    final now = DateTime.now();
    // [TZ-FIX] device-local DateTime(y,m,d)는 UTC+12에서 하루 밀림 → KST 고정 calendar date 사용
    final today = FormatHelper.toKstDate(now);
    final dr = f.dateRange;
    final rangeStart = dr != null
        ? FormatHelper.toKstDate(dr.start)
        : null;
    final rangeEnd = dr != null
        ? FormatHelper.toKstDate(dr.end)
        : null;

    final result = toList.where((to) {
      if (to.isManualClosed) return false;
      if (!to.isLongTerm) {
        if (to.rangeEnd == null) return false;
        final toEnd = FormatHelper.toKstDate(to.rangeEnd!);
        if (toEnd.isBefore(today)) return false;
      } else {
        if (to.isPostingExpired || to.isDeadlinePassed) return false;
        if (to.endDate != null) {
          final end = FormatHelper.toKstDate(to.endDate!);
          if (end.isBefore(today)) return false;
        }
      }
      final kw = f.keyword;
      if (kw != null && kw.isNotEmpty && !AlgoliaService.isConfigured) {
        final kwLower = kw.toLowerCase();
        if (!to.title.toLowerCase().contains(kwLower) &&
            !to.businessName.toLowerCase().contains(kwLower)) {
          return false;
        }
      }
      if (rangeStart != null && rangeEnd != null) {
        final toStart = FormatHelper.toKstDate(to.date);
        // 신규 preset: workStartAvailableUntil / custom·legacy: endDate(=rangeEnd) / flex: rangeEnd
        final toEndRaw = to.isLongTerm
            ? (to.hasWorkStartAvailableRange
                ? to.workStartAvailableUntil!
                : (to.endDate ?? to.date))
            : (to.rangeEnd ?? to.date);
        final toEnd = FormatHelper.toKstDate(toEndRaw);
        if (toStart.isAfter(rangeEnd) || toEnd.isBefore(rangeStart)) {
          return false;
        }
      }
      return true;
    }).toList();

    if (f.sortBy == 'date') {
      result.sort((a, b) => a.date.compareTo(b.date));
    } else {
      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return result;
  }

  void _onFilterChanged(TOFilterState newFilter) {
    final needsServerFetch =
        newFilter.type != _filter.type ||
        newFilter.city != _filter.city ||
        newFilter.district != _filter.district ||
        newFilter.keyword != _filter.keyword ||
        newFilter.showFavoritesOnly != _filter.showFavoritesOnly;

    if (needsServerFetch) {
      _filter = newFilter;
      _loadAllTOs();
    } else {
      setState(() {
        _filter = newFilter;
        _displayList = _computeDisplayList(_allTOList);
      });
    }
  }

  Future<void> _refreshMyApplications() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;
      if (uid != null) {
        final myApps = await _firestoreService.getMyApplications(uid);
        if (mounted) setState(() => _myApplications = myApps);
      }
    } catch (e) {
      debugPrint('❌ 지원 내역 새로고침 실패: $e');
    }
  }

  void _showAllFilters() {
    DialogHelper.showSheet(
      context,
      isScrollControlled: true,
      builder: (_) => _JobFilterSheet(
        initialFilter: _filter,
        availableCities: _availableCities,
        districtMap: _districtMap,
        onApply: _onFilterChanged,
        // 로컬 목록 기준 실시간 카운트 미리보기 (서버 재요청 없이 추정)
        countOf: (f) => _computeDisplayList(_allTOList, withFilter: f).length,
        hasMore: _hasMoreData,
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await DateRangePickerBottomSheet.show(
      context: context,
      initialStart: _filter.dateRange?.start,
      initialEnd: _filter.dateRange?.end,
      title: '날짜 범위 선택',
      minDate: now,
      maxDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      _onFilterChanged(_filter.copyWith(dateRange: picked));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 44,
        titleSpacing: 0,
        title: const Padding(
          padding: EdgeInsets.only(left: 16),
          child: Text(
            '일자리',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                labelColor: theme.primaryColor,
                unselectedLabelColor: AppColors.grey500,
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                indicatorColor: theme.primaryColor,
                indicatorWeight: 2,
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: '일자리 찾기'),
                  Tab(text: '내 지원'),
                ],
              ),
              Container(height: 1, color: AppColors.borderLight),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildJobListTab(context),
          // onBack: TabBarView 임베드 환경에서 Navigator.pop() 대신 탭 0으로 전환
          // (pop() 호출 시 탭 네비게이터에 라우트가 없어 assertion 오류 발생)
          MyApplicationsScreen(
            onBack: () => _tabController.animateTo(0),
          ),
        ],
      ),
    );
  }

  // ── 일자리 찾기 탭 ────────────────────────────────────────────────

  Widget _buildJobListTab(BuildContext context) {
    return Column(
      children: [
        // 검색바 + 빠른필터 — 스크롤 고정
        _buildSearchHeader(context),
        // 결과 요약 라인 — 로딩 완료 후 표시
        if (!_isLoading) _buildResultSummary(context),
        // TO 목록
        Expanded(child: _buildList(context)),
      ],
    );
  }

  /// 검색 결과 요약 라인
  ///
  /// 필터 없음:         "조건에 맞는 일자리 N개"
  /// 날짜 (단일):       "8월 12일 일자리 N개"
  /// 날짜 (범위):       "8/12~8/20 일자리 N개"
  /// 날짜 + 지역:       "8월 12일 · 오산시 일자리 N개"
  /// 키워드:            '"키워드" 일자리 N개'
  /// hasMore:           "N개 이상" 표시
  Widget _buildResultSummary(BuildContext context) {
    final count = _displayList.length;
    final countStr = _hasMoreData ? '$count개 이상' : '$count개';

    final kw = _filter.keyword;
    final String label;

    if (kw != null && kw.isNotEmpty) {
      // 키워드 검색
      label = '"$kw" 일자리 $countStr';
    } else {
      final parts = <String>[];

      // 날짜: 단일 "8월 12일" / 범위 "8/12~8/20"
      final dr = _filter.dateRange;
      if (dr != null) {
        final isSingleDay = dr.start.year == dr.end.year &&
            dr.start.month == dr.end.month &&
            dr.start.day == dr.end.day;
        parts.add(isSingleDay
            ? '${dr.start.month}월 ${dr.start.day}일'
            : '${dr.start.month}/${dr.start.day}~'
                '${dr.end.month}/${dr.end.day}');
      }

      // 지역
      if (_filter.city != null) {
        parts.add(_filter.district != null
            ? '${_filter.city} ${_filter.district}'
            : _filter.city!);
      }

      // 근무 유형 (단기/장기)
      if (_filter.type != null) {
        parts.add(_filter.type == 'flex' ? '단기' : '장기');
      }

      // 즐겨찾기
      if (_filter.showFavoritesOnly) {
        parts.add('즐겨찾기');
      }

      // 조건이 있으면 조건을 명시, 없으면 "조건에 맞는"
      label = parts.isEmpty
          ? '조건에 맞는 일자리 $countStr'
          : '${parts.join(' · ')} 일자리 $countStr';
    }

    return Container(
      width: double.infinity,
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        label,
        style: ResponsiveHelper.smallStyle(context,
            color: AppColors.grey500),
      ),
    );
  }

  Widget _buildSearchHeader(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // 검색바 행
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: AppSearchBar(
                    controller: _searchController,
                    hintText: '공고 제목, 사업장명 검색',
                    padding: EdgeInsets.zero,
                    onClear: () {
                      _searchDebounce?.cancel();
                      _onFilterChanged(
                          _filter.copyWith(clearKeyword: true));
                    },
                    onSubmitted: (value) {
                      _searchDebounce?.cancel();
                      final keyword = value.trim();
                      _onFilterChanged(keyword.isEmpty
                          ? _filter.copyWith(clearKeyword: true)
                          : _filter.copyWith(keyword: keyword));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                _buildFilterIconButton(context),
              ],
            ),
          ),
          // 빠른 필터 칩 행
          _buildQuickChips(context),
          Container(height: 1, color: AppColors.grey100),
        ],
      ),
    );
  }

  Widget _buildQuickChips(BuildContext context) {
    final theme = Theme.of(context);
    final hasDateRange = _filter.dateRange != null;
    final hasRegion = _filter.city != null;
    final dr = _filter.dateRange;
    final regionLabel = _filter.district != null
        ? '${_filter.city} ${_filter.district}'
        : (_filter.city ?? '');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          // 즐겨찾기 — 하트 아이콘 단독 칩: 기본 Neutral, 활성 시 Red
          _favoriteIconChip(context, theme),
          const SizedBox(width: 8),
          _quickChip(
            context, theme,
            label: '단기',
            active: _filter.type == 'flex',
            onTap: () => _onFilterChanged(_filter.type == 'flex'
                ? _filter.copyWith(clearType: true)
                : _filter.copyWith(type: 'flex')),
          ),
          const SizedBox(width: 8),
          _quickChip(
            context, theme,
            label: '장기',
            active: _filter.type == 'contract',
            onTap: () => _onFilterChanged(_filter.type == 'contract'
                ? _filter.copyWith(clearType: true)
                : _filter.copyWith(type: 'contract')),
          ),
          const SizedBox(width: 8),
          // 날짜 범위 칩 — 선택 후 X버튼 포함
          if (hasDateRange)
            _activeFilterChip(
              context, theme,
              label:
                  '${dr!.start.month}/${dr.start.day}~${dr.end.month}/${dr.end.day}',
              onClear: () => _onFilterChanged(
                  _filter.copyWith(clearDateRange: true)),
            )
          else
            _quickChip(
              context, theme,
              label: '날짜',
              icon: Icons.calendar_today_outlined,
              active: false,
              onTap: _pickDateRange,
            ),
          const SizedBox(width: 8),
          // 지역 칩 — 선택 후 X버튼 포함
          if (hasRegion)
            _activeFilterChip(
              context, theme,
              label: regionLabel,
              onClear: () => _onFilterChanged(_filter.clearRegion()),
            )
          else
            _quickChip(
              context, theme,
              label: '지역',
              icon: Icons.location_on_outlined,
              active: false,
              onTap: _pickRegionQuick,
            ),
        ],
      ),
    );
  }

  /// 즐겨찾기 칩 — 하트 아이콘 + "즐겨찾기" 텍스트
  /// 기본: Neutral 테두리, 비활성 아이콘
  /// 활성: Red 테두리/아이콘 + 연한 Red 배경
  Widget _favoriteIconChip(BuildContext context, ThemeData theme) {
    final active = _filter.showFavoritesOnly;
    return GestureDetector(
      onTap: () => _onFilterChanged(
          _filter.copyWith(showFavoritesOnly: !_filter.showFavoritesOnly)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AppColors.error.withValues(alpha: 0.08)
              : Colors.white,
          border: Border.all(
            color: active ? AppColors.error : AppColors.grey300,
            width: active ? 1.2 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 13,
              color: active ? AppColors.error : AppColors.grey400,
            ),
            const SizedBox(width: 4),
            Text(
              '즐겨찾기',
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: active ? AppColors.error : AppColors.grey700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 활성 필터 칩 (날짜·지역 공통) — 선택된 값 + X 버튼
  Widget _activeFilterChip(
    BuildContext context,
    ThemeData theme, {
    required String label,
    required VoidCallback onClear,
  }) {
    return Container(
      padding:
          const EdgeInsets.only(left: 13, right: 6, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.08),
        border: Border.all(
            color: theme.primaryColor.withValues(alpha: 0.5), width: 1.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.primaryColor,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onClear,
            child: Icon(Icons.close, size: 14, color: theme.primaryColor),
          ),
        ],
      ),
    );
  }

  /// 지역 빠른 필터 — RegionPickerSheet 호출
  Future<void> _pickRegionQuick() async {
    final result = await RegionPickerSheet.show(
      context: context,
      cities: _availableCities,
      districtOf: (city) => _districtMap[city] ?? [],
      selectedCity: _filter.city,
      selectedDistrict: _filter.district,
    );
    if (result != null && mounted) {
      _onFilterChanged(
          _filter.copyWith(city: result.city, district: result.district));
    }
  }

  Widget _quickChip(
    BuildContext context,
    ThemeData theme, {
    required String label,
    required bool active,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: active ? theme.primaryColor : Colors.white,
          border: Border.all(
            color: active ? theme.primaryColor : AppColors.grey300,
            width: active ? 1.2 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 12,
                color: active ? Colors.white : AppColors.grey500,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    active ? FontWeight.w600 : FontWeight.normal,
                color: active ? Colors.white : AppColors.grey700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterIconButton(BuildContext context) {
    final theme = Theme.of(context);
    final badgeCount =
        _filter.activeCount + (_filter.sortBy == 'date' ? 1 : 0);
    final hasActive = badgeCount > 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: hasActive ? theme.primaryColor : AppColors.grey100,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: _showAllFilters,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                Icons.tune,
                color: hasActive ? Colors.white : AppColors.grey600,
                size: 22,
              ),
            ),
          ),
        ),
        if (hasActive)
          Positioned(
            top: -5,
            right: -5,
            child: Container(
              width: 17,
              height: 17,
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildList(BuildContext context) {
    if (_isLoading) return const TOListSkeleton(compact: true);
    if (_displayList.isEmpty) return _buildEmptyState();

    return RefreshIndicator(
      onRefresh: () => _loadAllTOs(forceRefresh: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: ResponsiveHelper.listPadding(context),
        itemCount: _displayList.length + (_hasMoreData ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _displayList.length) {
            if (_isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LoadingWidget(),
              );
            }
            if (_hasMoreData) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: OutlinedButton.icon(
                  onPressed: _loadMoreTOs,
                  icon: const Icon(Icons.expand_more, size: 18),
                  label: const Text('더 많은 공고 보기'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    side: const BorderSide(color: AppColors.grey300),
                    foregroundColor: AppColors.grey600,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }

          final to = _displayList[index];
          // compact 모드: 카드 탭 → JobPostingScreen, 확장 없음
          return RepaintBoundary(
            child: UserTOCard(
              to: to,
              compact: true,
              myApplications: _myApplications,
              onApplySuccess: _refreshMyApplications,
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    if (_filter.showFavoritesOnly) {
      return AppEmptyState(
        icon: Icons.favorite_border_rounded,
        title: '즐겨찾기한 공고가 없습니다',
        subtitle: '공고 목록에서 ♥ 버튼을 눌러\n관심 공고를 저장해보세요',
        action: TextButton(
          onPressed: () => _onFilterChanged(
              _filter.copyWith(showFavoritesOnly: false)),
          child: const Text('전체 공고 보기'),
        ),
      );
    }
    final hasFilters = _filter.hasFilters;
    return AppEmptyState(
      icon: hasFilters ? Icons.filter_list_off : Icons.search_off,
      title: hasFilters
          ? '필터 조건에 맞는 공고가 없습니다'
          : '등록된 공고가 없습니다',
      subtitle: hasFilters ? '필터를 변경해보세요' : '잠시 후 다시 시도해보세요',
      action: hasFilters
          ? OutlinedButton.icon(
              onPressed: () =>
                  _onFilterChanged(const TOFilterState()),
              icon: const Icon(Icons.filter_list_off),
              label: const Text('필터 초기화'),
            )
          : TextButton(
              onPressed: _loadAllTOs,
              child: const Text('새로고침'),
            ),
    );
  }
}

// ── 통합 필터 바텀시트 ────────────────────────────────────────────────

class _JobFilterSheet extends StatefulWidget {
  const _JobFilterSheet({
    required this.initialFilter,
    required this.onApply,
    required this.availableCities,
    required this.districtMap,
    this.countOf,
    this.hasMore = false,
  });

  final TOFilterState initialFilter;
  final ValueChanged<TOFilterState> onApply;
  final List<String> availableCities;
  final Map<String, List<String>> districtMap;

  /// 현재 로컬 목록 기준 예상 결과 수 (필터 변경 시 실시간 업데이트)
  /// null이면 "적용하기" 텍스트 사용
  final int Function(TOFilterState)? countOf;

  /// 서버에 아직 로드 안 된 데이터가 있을 때 true → 카운트에 "이상" 표시
  final bool hasMore;

  @override
  State<_JobFilterSheet> createState() => _JobFilterSheetState();
}

class _JobFilterSheetState extends State<_JobFilterSheet> {
  late TOFilterState _local;

  @override
  void initState() {
    super.initState();
    _local = widget.initialFilter;
  }

  Future<void> _pickRegion() async {
    final result = await RegionPickerSheet.show(
      context: context,
      cities: widget.availableCities,
      districtOf: (city) => widget.districtMap[city] ?? [],
      selectedCity: _local.city,
      selectedDistrict: _local.district,
    );
    if (result != null && mounted) {
      setState(() => _local =
          _local.copyWith(city: result.city, district: result.district));
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await DateRangePickerBottomSheet.show(
      context: context,
      initialStart: _local.dateRange?.start,
      initialEnd: _local.dateRange?.end,
      title: '날짜 범위 선택',
      minDate: now,
      maxDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _local = _local.copyWith(dateRange: picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 드래그 핸들
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.only(
                  bottom: ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // 타이틀 + 초기화
          Row(
            children: [
              Text('필터',
                  style: ResponsiveHelper.titleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    setState(() => _local = const TOFilterState()),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 8)),
                ),
                child: Text('초기화',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.grey500)),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // ─ 즐겨찾기
          _sectionLabel(context, '즐겨찾기'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          _toggleItem(
            context, theme,
            label: '♥ 즐겨찾기만 보기',
            isSelected: _local.showFavoritesOnly,
            onTap: () => setState(() => _local = _local.copyWith(
                showFavoritesOnly: !_local.showFavoritesOnly)),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // ─ 근무 유형
          _sectionLabel(context, '근무 유형'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Row(children: [
            _typeChip(context, theme, null, '전체'),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            _typeChip(context, theme, 'flex', '단기'),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            _typeChip(context, theme, 'contract', '장기'),
          ]),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // ─ 지역
          _sectionLabel(context, '지역'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          _rowSelector(
            context, theme,
            label: _local.city != null
                ? (_local.district != null
                    ? '${_local.city} ${_local.district}'
                    : _local.city!)
                : '전체 지역',
            isSet: _local.city != null,
            onTap: _pickRegion,
            onClear: _local.city != null
                ? () => setState(() => _local = _local.clearRegion())
                : null,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // ─ 날짜 범위
          _sectionLabel(context, '날짜 범위'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          _rowSelector(
            context, theme,
            label: _local.dateRange != null
                ? '${_fmt(_local.dateRange!.start)} ~ ${_fmt(_local.dateRange!.end)}'
                : '전체 날짜',
            isSet: _local.dateRange != null,
            onTap: _pickDateRange,
            onClear: _local.dateRange != null
                ? () => setState(
                    () => _local = _local.copyWith(clearDateRange: true))
                : null,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // ─ 정렬
          _sectionLabel(context, '정렬'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Row(children: [
            _sortChip(context, theme, 'createdAt', '최신순'),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            _sortChip(context, theme, 'date', '마감임박순'),
          ]),
          SizedBox(height: ResponsiveHelper.spacing(context, 20)),

          // ─ 적용 — 로컬 목록 기준 결과 수 실시간 표시
          // countOf가 있으면 "N개 일자리 보기", 없으면 "적용하기"
          // hasMore=true(미로드 페이지 있음)이면 "N개 이상" 표시
          () {
            final count = widget.countOf?.call(_local);
            final String label;
            if (count == null) {
              label = '적용하기';
            } else if (count == 0) {
              label = '조건에 맞는 공고 없음';
            } else if (widget.hasMore) {
              label = '$count개 이상의 일자리 보기';
            } else {
              label = '$count개 일자리 보기';
            }
            return SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: count == 0
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.onApply(_local);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.grey200,
                  disabledForegroundColor: AppColors.grey500,
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 14)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  label,
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: count == 0 ? AppColors.grey500 : Colors.white,
                  ),
                ),
              ),
            );
          }(),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) => Text(
        label,
        style: ResponsiveHelper.smallStyle(context).copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.grey600,
        ),
      );

  Widget _toggleItem(
    BuildContext context,
    ThemeData theme, {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 9),
          ),
          decoration: BoxDecoration(
            color: isSelected ? theme.primaryColor : Colors.transparent,
            border: Border.all(
                color: isSelected ? theme.primaryColor : AppColors.grey300),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: isSelected ? Colors.white : AppColors.grey600,
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      );

  Widget _typeChip(
      BuildContext context, ThemeData theme, String? value, String label) {
    final isSelected = _local.type == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() =>
            _local = _local.copyWith(type: value, clearType: value == null)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 10)),
          decoration: BoxDecoration(
            color: isSelected ? theme.primaryColor : Colors.transparent,
            border: Border.all(
                color:
                    isSelected ? theme.primaryColor : AppColors.grey300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: isSelected ? Colors.white : AppColors.grey600,
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sortChip(
      BuildContext context, ThemeData theme, String value, String label) {
    final isSelected = _local.sortBy == value;
    return Expanded(
      child: GestureDetector(
        onTap: () =>
            setState(() => _local = _local.copyWith(sortBy: value)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 10)),
          decoration: BoxDecoration(
            color: isSelected ? theme.primaryColor : Colors.transparent,
            border: Border.all(
                color:
                    isSelected ? theme.primaryColor : AppColors.grey300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: isSelected ? Colors.white : AppColors.grey600,
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowSelector(
    BuildContext context,
    ThemeData theme, {
    required String label,
    required bool isSet,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 14),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          decoration: BoxDecoration(
            color: isSet
                ? theme.primaryColor.withValues(alpha: 0.06)
                : AppColors.grey50,
            border: Border.all(
              color: isSet
                  ? theme.primaryColor.withValues(alpha: 0.4)
                  : AppColors.grey200,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: isSet ? theme.primaryColor : AppColors.grey600,
                    fontWeight:
                        isSet ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: const Icon(Icons.close,
                      size: 16, color: AppColors.grey400),
                )
              else
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.grey400),
            ],
          ),
        ),
      );

  String _fmt(DateTime dt) => '${dt.month}/${dt.day}';
}
