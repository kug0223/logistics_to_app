import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/core/to_model.dart';
import '../../models/core/application_model.dart';
import '../../models/core/to_filter_state.dart';
import '../../models/core/work_detail_model.dart';
import '../../models/core/slot_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/user/cards/user_to_card.dart';
import '../../utils/toast_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/inputs/region_picker_sheet.dart';
import '../../services/algolia_service.dart';
import '../../widgets/pickers/date_picker_bottom_sheet.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_search_bar.dart';
import '../../widgets/common/app_filter_chip.dart';
import '../../widgets/common/gradient_scaffold.dart';

/// 전체 TO 목록 화면 (지원자용)
class AllTOListScreen extends StatefulWidget {
  const AllTOListScreen({super.key});

  @override
  State<AllTOListScreen> createState() => _AllTOListScreenState();
}

class _AllTOListScreenState extends State<AllTOListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  // [C05] 최근 검색어 저장 미구현:
  //   현재 검색어는 메모리에만 유지되며 앱 재시작 시 초기화됨.
  //   향후 SharedPreferences에 최근 검색어(최대 10개) 저장 후 검색 창 포커스 시 표시 예정.

  // 필터 상태
  TOFilterState _filter = const TOFilterState();

  // 데이터
  List<TOModel> _allTOList = [];
  List<TOModel> _displayList = [];  // 만료 필터 적용 후 최종 목록
  List<ApplicationModel> _myApplications = [];

  // 지역 목록 (불러온 TO에서 추출)
  List<String> _availableCities = [];
  Map<String, List<String>> _districtMap = {};

  // 페이지네이션
  DocumentSnapshot? _lastDoc;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;

  // workDetails 캐시 (toId → List<WorkDetailModel>)
  final Map<String, List<WorkDetailModel>> _workDetailsCache = {};
  // 슬롯 캐시: flex TO 날짜별 슬롯 (toId → List<SlotModel>)
  final Map<String, List<SlotModel>> _slotsCache = {};

  // 검색 디바운스
  Timer? _searchDebounce;

  // UI 상태
  bool _isLoading = true;
  String? _selectedTOId;

  @override
  void initState() {
    super.initState();
    _loadAllTOs();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

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
    // 이미 로딩 중이거나 더 이상 데이터 없으면 스킵 (중복 호출 방지)
    if (_isLoading || _isLoadingMore || !_hasMoreData) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMoreTOs();
    }
  }

  /// 첫 페이지 로드 (새로고침 포함)
  Future<void> _loadAllTOs() async {
    setState(() {
      _isLoading = true;
      _lastDoc = null;
      _hasMoreData = true;
      _allTOList = [];
      _workDetailsCache.clear();
      _slotsCache.clear();
      _selectedTOId = null;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      final appsFuture = uid != null
          ? _firestoreService.getMyApplications(uid)
          : Future.value(<ApplicationModel>[]);

      List<TOModel> toList;
      DocumentSnapshot? lastDoc;
      bool hasMore;

      if (_filter.showFavoritesOnly) {
        // 즐겨찾기 경로: 사용자의 favoriteToIds로 batch fetch
        final favoriteIds = userProvider.currentUser?.favoriteToIds ?? const [];
        // [특이사항] favoriteToIds는 UserProvider 인메모리 캐시 기반 — 다른 기기에서
        // 즐겨찾기를 변경해도 이 세션이 refreshCurrentUser() 호출 전까지 구 목록을 사용
        // 실제 데이터 조회는 Firestore에서 하므로 삭제된 TO는 결과에서 자동 제외됨
        toList = favoriteIds.isEmpty
            ? []
            : await _firestoreService.getTOsByIds(favoriteIds);
        lastDoc = null;
        hasMore = false;
      } else if (_filter.keyword?.isNotEmpty == true && AlgoliaService.isConfigured) {
        // Algolia 경로: 키워드 검색 → ID 목록 → Firestore batch fetch
        final ids = await AlgoliaService.searchTOIds(_filter.keyword!, filter: _filter);
        toList = await _firestoreService.getTOsByIds(ids);
        lastDoc = null;
        hasMore = false;
      } else {
        final tosResult = await _firestoreService.getPublishedTOsPaged(filter: _filter);
        toList = tosResult['items'] as List<TOModel>;
        lastDoc = tosResult['lastDoc'] as DocumentSnapshot?;
        hasMore = tosResult['hasMore'] as bool;
      }

      final myApps = await appsFuture;

      if (!mounted) return;
      setState(() {
        _allTOList = toList;
        _lastDoc = lastDoc;
        _hasMoreData = hasMore;
        _myApplications = myApps;
        _isLoading = false;
      });

      _updateRegionOptions();
      _applyExpiredFilter();
    } catch (e) {
      debugPrint('❌ TO 목록 로드 실패: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ToastHelper.showError('공고 목록을 불러오는데 실패했습니다.');
    }
  }

  /// 다음 페이지 로드
  Future<void> _loadMoreTOs() async {
    if (_isLoading || _isLoadingMore || !_hasMoreData) return;
    // lastDoc 없으면 cursor를 잃은 상태 — 재로드 방지
    if (_lastDoc == null) return;
    if (!mounted) return;

    setState(() => _isLoadingMore = true);

    try {
      final tosResult = await _firestoreService.getPublishedTOsPaged(
        startAfter: _lastDoc,
        filter: _filter,
      );
      final toList = tosResult['items'] as List<TOModel>;

      if (!mounted) {
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

      setState(() {
        _allTOList = [..._allTOList, ...toList];
        _lastDoc = tosResult['lastDoc'] as DocumentSnapshot?;
        _hasMoreData = tosResult['hasMore'] as bool;
        _isLoadingMore = false;
      });

      _updateRegionOptions();
      _applyExpiredFilter();
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

  /// 불러온 TO에서 지역 목록 추출
  void _updateRegionOptions() {
    final cities = <String>{};
    final districtMap = <String, Set<String>>{};

    for (final to in _allTOList) {
      final city = to.businessCity;
      if (city != null && city.isNotEmpty) {
        cities.add(city);
        final district = to.businessDistrict;
        if (district != null && district.isNotEmpty) {
          districtMap.putIfAbsent(city, () => {}).add(district);
        }
      }
    }

    setState(() {
      _availableCities = cities.toList()..sort();
      _districtMap = districtMap.map((k, v) => MapEntry(k, v.toList()..sort()));
    });
  }

  /// 만료된 날짜 필터 (클라이언트 사이드 유지)
  ///
  /// 만료 체크와 날짜 범위 필터를 단일 순회(O(n))로 처리.
  void _applyExpiredFilter() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 날짜 범위 필터 경계값 — 루프 밖에서 한 번만 계산
    final dr = _filter.dateRange;
    final rangeStart = dr != null
        ? DateTime(dr.start.year, dr.start.month, dr.start.day)
        : null;
    final rangeEnd = dr != null
        ? DateTime(dr.end.year, dr.end.month, dr.end.day)
        : null;

    final result = _allTOList.where((to) {
      // ── 0. 수동 마감 체크 — CF status 갱신 전(최대 30분) 즉시 반영
      if (to.isManualClosed) return false;

      // ── 1. 만료 체크 ─────────────────────────────────────
      if (!to.isLongTerm) {
        if (to.rangeEnd == null) return false; // 구 데이터: 날짜 미상 → 표시 제외
        final toEnd = DateTime(to.rangeEnd!.year, to.rangeEnd!.month, to.rangeEnd!.day);
        if (toEnd.isBefore(today)) return false;
      } else {
        if (to.isPostingExpired || to.isDeadlinePassed) return false;
        if (to.endDate != null) {
          final end = DateTime(to.endDate!.year, to.endDate!.month, to.endDate!.day);
          if (end.isBefore(today)) return false;
        }
      }

      // ── 2. 날짜 범위 필터 (설정된 경우만) ─────────────────
      if (rangeStart != null && rangeEnd != null) {
        final toStart = DateTime(to.date.year, to.date.month, to.date.day);
        final toEndRaw = to.isLongTerm ? (to.endDate ?? to.date) : (to.rangeEnd ?? to.date);
        final toEnd = DateTime(toEndRaw.year, toEndRaw.month, toEndRaw.day);
        // 기간이 선택 범위와 겹치지 않으면 제외
        if (toStart.isAfter(rangeEnd) || toEnd.isBefore(rangeStart)) return false;
      }

      return true;
    }).toList();

    setState(() {
      if (_filter.sortBy == 'date') {
        _displayList = result..sort((a, b) => a.date.compareTo(b.date));
      } else {
        _displayList = result..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
    });
  }

  /// 필터 변경 — 서버에서 새로 fetch
  void _onFilterChanged(TOFilterState newFilter) {
    setState(() => _filter = newFilter);
    _loadAllTOs();
  }

  /// TO 선택/해제
  void _toggleTOSelection(String toId) {
    setState(() {
      _selectedTOId = _selectedTOId == toId ? null : toId;
    });
  }

  /// flex TO 슬롯 캐시 fetch (없을 때만 서버 호출)
  /// 반환값: 이번 호출에서 로드/이미 캐시된 슬롯 목록 (카드가 즉시 사용)
  Future<List<SlotModel>> _fetchSlots(String toId) async {
    if (_slotsCache.containsKey(toId)) return _slotsCache[toId]!;
    try {
      final slots = await _firestoreService.getSlots(toId, visibleOnly: true);
      if (mounted) setState(() => _slotsCache[toId] = slots);
      return slots;
    } catch (e) {
      debugPrint('❌ slots 로드 실패 ($toId): $e');
      return [];
    }
  }

  /// workDetails 캐시 fetch (없을 때만 서버 호출)
  /// 반환값: 이번 호출에서 로드/이미 캐시된 workDetails (카드가 즉시 사용)
  Future<List<WorkDetailModel>> _fetchWorkDetails(String toId) async {
    if (_workDetailsCache.containsKey(toId)) return _workDetailsCache[toId]!;
    try {
      final details = await _firestoreService.getWorkDetails(toId);
      if (mounted) setState(() => _workDetailsCache[toId] = details);
      return details;
    } catch (e) {
      debugPrint('❌ workDetails 로드 실패 ($toId): $e');
      return [];
    }
  }

  /// 내 지원 내역만 새로고침
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

  /// 지역 필터 바텀시트
  Future<void> _showRegionPicker() async {
    final result = await RegionPickerSheet.show(
      context: context,
      cities: _availableCities,
      districtOf: (city) => _districtMap[city] ?? [],
      selectedCity: _filter.city,
      selectedDistrict: _filter.district,
    );
    if (result != null) {
      _onFilterChanged(_filter.copyWith(city: result.city, district: result.district));
    }
  }

  /// 날짜 범위 피커
  Future<void> _showDateRangePicker() async {
    final now = DateTime.now();
    final picked = await DateRangePickerBottomSheet.show(
      context: context,
      initialStart: _filter.dateRange?.start,
      initialEnd: _filter.dateRange?.end,
      title: '날짜 범위 선택',
      minDate: now,
      maxDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      _onFilterChanged(_filter.copyWith(dateRange: picked));
    }
  }

  /// 정렬 바텀시트
  void _showSortSheet() {
    // [오탐 확인] shape 생략 — _SortSheet 내부 BoxDecoration이 borderRadius를 담당 (backgroundColor: transparent로 투시).
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SortSheet(
        sortBy: _filter.sortBy,
        onChanged: (sort) => _onFilterChanged(_filter.copyWith(sortBy: sort)),
      ),
    );
  }

  /// 근무유형 필터 바텀시트
  void _showTypeFilter() {
    // [오탐 확인] shape 생략 — _TypeFilterSheet 내부 BoxDecoration이 borderRadius를 담당.
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TypeFilterSheet(
        selectedType: _filter.type,
        onChanged: (type) => _onFilterChanged(_filter.copyWith(
          type: type,
          clearType: type == null,
        )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '공고 찾기',
      onRefresh: _loadAllTOs,
      body: Column(
        children: [
                      // 검색바 + 필터 — 스크롤되지 않는 고정 영역 (흰 배경)
                      Container(
                        color: Colors.white,
                        child: Column(
                          children: [
                            // 검색바
                            AppSearchBar(
                              controller: _searchController,
                              hintText: '공고 제목, 사업장명 검색',
                              padding: EdgeInsets.fromLTRB(
                                ResponsiveHelper.spacing(context, 16),
                                ResponsiveHelper.spacing(context, 16),
                                ResponsiveHelper.spacing(context, 16),
                                ResponsiveHelper.spacing(context, 10),
                              ),
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
                            // 필터 칩 행
                            SizedBox(
                              height: ResponsiveHelper.spacing(context, 40),
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                padding: EdgeInsets.symmetric(
                                  horizontal:
                                      ResponsiveHelper.spacing(context, 16),
                                ),
                                children: [
                                  AppFilterChip(
                                    label: '♥ 즐겨찾기',
                                    isSelected: _filter.showFavoritesOnly,
                                    solid: true,
                                    onTap: () => _onFilterChanged(_filter.copyWith(
                                        showFavoritesOnly: !_filter.showFavoritesOnly)),
                                    onClear: _filter.showFavoritesOnly
                                        ? () => _onFilterChanged(_filter.copyWith(
                                            showFavoritesOnly: false))
                                        : null,
                                  ),
                                  SizedBox(
                                      width: ResponsiveHelper.spacing(context, 8)),
                                  AppFilterChip(
                                    label: _filter.city != null
                                        ? (_filter.district != null
                                            ? '${_filter.city} ${_filter.district}'
                                            : _filter.city!)
                                        : '전체지역',
                                    isSelected: _filter.city != null,
                                    solid: true,
                                    onTap: _showRegionPicker,
                                    onClear: _filter.city != null
                                        ? () => _onFilterChanged(
                                            _filter.clearRegion())
                                        : null,
                                  ),
                                  SizedBox(
                                      width:
                                          ResponsiveHelper.spacing(context, 8)),
                                  AppFilterChip(
                                    label: _filter.type == 'flex'
                                        ? '단기'
                                        : _filter.type == 'contract'
                                            ? '장기'
                                            : '전체유형',
                                    isSelected: _filter.type != null,
                                    solid: true,
                                    onTap: _showTypeFilter,
                                    onClear: _filter.type != null
                                        ? () => _onFilterChanged(_filter
                                            .copyWith(clearType: true))
                                        : null,
                                  ),
                                  SizedBox(
                                      width:
                                          ResponsiveHelper.spacing(context, 8)),
                                  AppFilterChip(
                                    label: _filter.dateRange != null
                                        ? '${_formatDate(_filter.dateRange!.start)}~${_formatDate(_filter.dateRange!.end)}'
                                        : '날짜',
                                    isSelected: _filter.dateRange != null,
                                    solid: true,
                                    onTap: _showDateRangePicker,
                                    onClear: _filter.dateRange != null
                                        ? () => _onFilterChanged(_filter
                                            .copyWith(clearDateRange: true))
                                        : null,
                                  ),
                                  SizedBox(
                                      width:
                                          ResponsiveHelper.spacing(context, 8)),
                                  AppFilterChip(
                                    label: _filter.sortBy == 'date'
                                        ? '마감임박순'
                                        : '최신순',
                                    isSelected: _filter.sortBy == 'date',
                                    solid: true,
                                    onTap: _showSortSheet,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Divider(
                                height: 1, thickness: 1, color: AppColors.grey100),
                          ],
                        ),
                      ),

                      // TO 목록 (스크롤)
                      Expanded(
                        child: _isLoading
                            ? const LoadingWidget(message: '공고 목록을 불러오는 중...')
                            : _displayList.isEmpty
                                ? _buildEmptyState()
                                : RefreshIndicator(
                                    onRefresh: _loadAllTOs,
                                    child: ListView.builder(
                                      controller: _scrollController,
                                      padding:
                                          ResponsiveHelper.listPadding(context),
                                      itemCount: _displayList.length +
                                          (_hasMoreData ? 1 : 0),
                                      itemBuilder: (context, index) {
                                        if (index == _displayList.length) {
                                          return Padding(
                                            padding: EdgeInsets.symmetric(
                                              vertical: ResponsiveHelper.spacing(
                                                  context, 16),
                                            ),
                                            child: _isLoadingMore
                                                ? const LoadingWidget()
                                                : const SizedBox.shrink(),
                                          );
                                        }
                                        final to = _displayList[index];
                                        final isSelected =
                                            _selectedTOId == to.id;
                                        return RepaintBoundary(
                                          child: UserTOCard(
                                            to: to,
                                            isSelected: isSelected,
                                            onTap: () =>
                                                _toggleTOSelection(to.id),
                                            myApplications: _myApplications,
                                            onApplySuccess:
                                                _refreshMyApplications,
                                            workDetails:
                                                _workDetailsCache[to.id],
                                            onFetchWorkDetails:
                                                _fetchWorkDetails,
                                            slots: _slotsCache[to.id],
                                            onFetchSlots: _fetchSlots,
                                            isAnyOtherExpanded: _selectedTOId !=
                                                    null &&
                                                _selectedTOId != to.id,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                      ),
                    ],
                  ),
      );
  }

  String _formatDate(DateTime dt) => '${dt.month}/${dt.day}';

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
      title: hasFilters ? '필터 조건에 맞는 공고가 없습니다' : '등록된 공고가 없습니다',
      subtitle: hasFilters ? '필터를 변경해보세요' : '잠시 후 다시 시도해보세요',
      action: hasFilters
          ? OutlinedButton.icon(
              onPressed: () => _onFilterChanged(const TOFilterState()),
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

// ── 정렬 선택 바텀시트 ────────────────────────────────────────

class _SortSheet extends StatelessWidget {
  const _SortSheet({required this.sortBy, required this.onChanged});

  final String sortBy;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 20)),
              decoration: BoxDecoration(
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('정렬', style: ResponsiveHelper.titleStyle(context).copyWith(fontWeight: FontWeight.bold)),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          _sortOption(context, theme, 'createdAt', '최신순', Icons.fiber_new_outlined),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          _sortOption(context, theme, 'date', '마감임박순', Icons.timer_outlined),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        ],
      ),
    );
  }

  Widget _sortOption(BuildContext context, ThemeData theme, String value, String label, IconData icon) {
    final isSelected = sortBy == value;
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onChanged(value);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: isSelected ? theme.primaryColor.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? theme.primaryColor : AppColors.grey200),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? theme.primaryColor : AppColors.grey500,
                size: ResponsiveHelper.iconSize(context, 20)),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Text(label, style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? theme.primaryColor : null,
            )),
            if (isSelected) ...[
              const Spacer(),
              Icon(Icons.check, color: theme.primaryColor, size: ResponsiveHelper.iconSize(context, 18)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 근무유형 선택 바텀시트 ──────────────────────────────────────

class _TypeFilterSheet extends StatelessWidget {
  const _TypeFilterSheet({required this.selectedType, required this.onChanged});

  final String? selectedType;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 20)),
              decoration: BoxDecoration(
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('근무 유형', style: ResponsiveHelper.titleStyle(context).copyWith(fontWeight: FontWeight.bold)),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          _typeOption(context, theme, null, '전체', Icons.all_inclusive),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          _typeOption(context, theme, 'flex', '단기 (알바)', Icons.calendar_today),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          _typeOption(context, theme, 'contract', '장기 (고정)', Icons.work_outline),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        ],
      ),
    );
  }

  Widget _typeOption(BuildContext context, ThemeData theme, String? value, String label, IconData icon) {
    final isSelected = selectedType == value;
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onChanged(value);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: isSelected ? theme.primaryColor.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? theme.primaryColor : AppColors.grey200,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? theme.primaryColor : AppColors.grey500,
                size: ResponsiveHelper.iconSize(context, 20)),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Text(label, style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? theme.primaryColor : null,
            )),
            if (isSelected) ...[
              const Spacer(),
              Icon(Icons.check, color: theme.primaryColor, size: ResponsiveHelper.iconSize(context, 18)),
            ],
          ],
        ),
      ),
    );
  }
}
