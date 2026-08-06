import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../../models/core/to_model.dart';
import '../../models/core/application_model.dart';
import '../../models/core/to_filter_state.dart';
import '../../models/core/work_detail_model.dart';
import '../../models/core/slot_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/skeleton_widget.dart';
import '../../widgets/user/cards/user_to_card.dart';
import '../../utils/toast_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../widgets/inputs/region_picker_sheet.dart';
import '../../services/algolia_service.dart';
import '../../widgets/pickers/date_picker_bottom_sheet.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_search_bar.dart';
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

  // 페이지네이션 — [CF-MIGRATED D6-CP2] DocumentSnapshot → lastToId(String)
  String? _lastToId;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;
  // 필터 변경 시 진행 중인 페이지네이션 배치를 버리기 위한 세대 카운터
  int _generation = 0;

  // workDetails 캐시 (toId → List<WorkDetailModel>)
  final Map<String, List<WorkDetailModel>> _workDetailsCache = {};
  // 슬롯 캐시: flex TO 날짜별 슬롯 (toId → List<SlotModel>)
  final Map<String, List<SlotModel>> _slotsCache = {};

  // 검색 디바운스
  Timer? _searchDebounce;

  // UI 상태
  bool _isLoading = true;
  bool _fetchInProgress = false;
  bool _myApplicationsLoaded = false; // M4: 필터 변경 시 재호출 방지
  String? _selectedTOId;

  // H2: 카드별 ValueNotifier — 슬롯/업무상세 로드 시 해당 카드만 리빌드
  final Map<String, ValueNotifier<List<SlotModel>?>> _slotNotifiers = {};
  final Map<String, ValueNotifier<List<WorkDetailModel>?>> _workDetailsNotifiers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadAllTOs();
    });
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    for (final n in _slotNotifiers.values) { n.dispose(); }
    for (final n in _workDetailsNotifiers.values) { n.dispose(); }
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
      // H2: 로딩 전환 시점에 notifier 해제 (이 시점 카드는 트리에서 제거됨)
      for (final n in _slotNotifiers.values) { n.dispose(); }
      _slotNotifiers.clear();
      for (final n in _workDetailsNotifiers.values) { n.dispose(); }
      _workDetailsNotifiers.clear();
      _selectedTOId = null;
      if (forceRefresh) _myApplicationsLoaded = false; // M4
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      // M4: 필터 변경 시 재호출 방지 — 이미 로드한 경우 기존 목록 재사용
      final appsFuture = (uid != null && !_myApplicationsLoaded)
          ? _firestoreService.getMyApplications(uid)
          : Future.value(_myApplications);

      List<TOModel> toList;
      String? lastToId;
      bool hasMore;

      if (_filter.showFavoritesOnly) {
        // 즐겨찾기 경로: 사용자의 favoriteToIds로 batch fetch
        final favoriteIds = userProvider.currentUser?.favoriteToIds ?? const [];
        // favoriteToIds는 UserProvider 인메모리 캐시 기반 — 다른 기기에서
        // 즐겨찾기를 변경해도 이 세션이 refreshCurrentUser() 호출 전까지 구 목록을 사용
        // 실제 데이터 조회는 Firestore에서 하므로 삭제된 TO는 결과에서 자동 제외됨
        toList = favoriteIds.isEmpty
            ? []
            : await _firestoreService.getTOsByIds(favoriteIds);
        lastToId = null;
        hasMore = false;
      } else if (_filter.keyword?.isNotEmpty == true && AlgoliaService.isConfigured) {
        // Algolia 경로: 키워드 검색 → ID 목록 → Firestore batch fetch
        final ids = await AlgoliaService.searchTOIds(_filter.keyword!, filter: _filter);
        toList = await _firestoreService.getTOsByIds(ids);
        lastToId = null;
        hasMore = false;
      } else {
        final tosResult = await _firestoreService.getPublishedTOsPaged(filter: _filter);
        toList = tosResult['items'] as List<TOModel>;
        lastToId = tosResult['lastToId'] as String?;
        hasMore = tosResult['hasMore'] as bool;
      }

      final myApps = await appsFuture;

      if (!mounted) return;
      // 지역 옵션·필터 결과를 사전 계산 후 단일 setState로 반영 — 연속 3회 setState(리빌드 낭비) 방지
      final regionResult = _computeRegionOptions(toList);
      final displayList = _computeDisplayList(toList);
      _fetchInProgress = false;
      setState(() {
        _allTOList = toList;
        _lastToId = lastToId;
        _hasMoreData = hasMore;
        _myApplications = myApps;
        _myApplicationsLoaded = true; // M4
        _availableCities = regionResult.cities;
        _districtMap = regionResult.districtMap;
        _displayList = displayList;
        _isLoading = false;
      });
      // [H-1-FIX] 초기 로드에서 status 클라이언트 필터 후 toList가 비어도 hasMore=true이면
      // 스크롤이 불가능해 _loadMoreTOs가 트리거되지 않는 버그 → postFrame에서 자동 로드
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

  /// 다음 페이지 로드
  Future<void> _loadMoreTOs() async {
    if (_isLoading || _isLoadingMore || !_hasMoreData) return;
    // lastToId 없으면 cursor를 잃은 상태 — 재로드 방지
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
      // M5: 새 배치만 계산 후 기존 지역 옵션과 증분 병합 (전체 재계산 방지)
      final newRegionResult = _computeRegionOptions(toList);
      final mergedCities = {..._availableCities, ...newRegionResult.cities}.toList()..sort();
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
      // H5: 클라이언트 필터 후 화면에 표시될 항목이 없으면 스크롤 없이 다음 페이지 자동 로드
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

  /// 불러온 TO에서 지역 목록을 계산하여 반환 (setState 없음 — 호출자가 일괄 반영)
  ({List<String> cities, Map<String, List<String>> districtMap}) _computeRegionOptions(List<TOModel> toList) {
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
      districtMap: districtMap.map((k, v) => MapEntry(k, v.toList()..sort())),
    );
  }

  /// 만료 체크·날짜 범위 필터를 적용한 정렬된 목록을 계산하여 반환 (setState 없음 — 호출자가 일괄 반영)
  ///
  /// 만료 체크와 날짜 범위 필터를 단일 순회(O(n))로 처리.
  List<TOModel> _computeDisplayList(List<TOModel> toList) {
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

    final result = toList.where((to) {
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

      // ── 2. 키워드 클라이언트 폴백 (Algolia 미설정 시 — H3)
      //    Algolia 설정 시에는 getTOsByIds로 이미 키워드 필터된 결과만 toList에 들어옴
      final kw = _filter.keyword;
      if (kw != null && kw.isNotEmpty && !AlgoliaService.isConfigured) {
        final kwLower = kw.toLowerCase();
        if (!to.title.toLowerCase().contains(kwLower) &&
            !to.businessName.toLowerCase().contains(kwLower)) {
          return false;
        }
      }

      // ── 3. 날짜 범위 필터 (설정된 경우만) ─────────────────
      if (rangeStart != null && rangeEnd != null) {
        final toStart = DateTime(to.date.year, to.date.month, to.date.day);
        final toEndRaw = to.isLongTerm ? (to.endDate ?? to.date) : (to.rangeEnd ?? to.date);
        final toEnd = DateTime(toEndRaw.year, toEndRaw.month, toEndRaw.day);
        // 기간이 선택 범위와 겹치지 않으면 제외
        if (toStart.isAfter(rangeEnd) || toEnd.isBefore(rangeStart)) return false;
      }

      return true;
    }).toList();

    if (_filter.sortBy == 'date') {
      result.sort((a, b) => a.date.compareTo(b.date));
    } else {
      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return result;
  }

  /// 필터 변경 — 서버 필터 변경 시 재조회, 클라이언트 필터(sortBy/dateRange)는 로컬 재계산 (H1)
  void _onFilterChanged(TOFilterState newFilter) {
    final needsServerFetch =
        newFilter.type != _filter.type ||
        newFilter.city != _filter.city ||
        newFilter.district != _filter.district ||
        newFilter.keyword != _filter.keyword ||
        newFilter.showFavoritesOnly != _filter.showFavoritesOnly;

    if (needsServerFetch) {
      _filter = newFilter; // H4: 필드만 갱신 — _loadAllTOs의 setState가 리빌드 담당
      _loadAllTOs();
    } else {
      // sortBy / dateRange 변경만 → 서버 호출 없이 클라이언트 재정렬
      setState(() {
        _filter = newFilter;
        _displayList = _computeDisplayList(_allTOList);
      });
    }
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
      _slotsCache[toId] = slots;
      if (mounted) _slotNotifiers[toId]?.value = slots; // H2: 해당 카드만 리빌드
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
      _workDetailsCache[toId] = details;
      if (mounted) _workDetailsNotifiers[toId]?.value = details; // H2: 해당 카드만 리빌드
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

  /// 통합 필터 바텀시트
  void _showAllFilters() {
    DialogHelper.showSheet(
      context,
      isScrollControlled: true,
      builder: (_) => _AllFilterSheet(
        initialFilter: _filter,
        availableCities: _availableCities,
        districtMap: _districtMap,
        onApply: _onFilterChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '공고 찾기',
      onRefresh: () => _loadAllTOs(forceRefresh: true),
      body: Column(
        children: [
                      // 검색바 + 필터 버튼 — 스크롤되지 않는 고정 영역 (흰 배경)
                      Container(
                        color: Colors.white,
                        child: Column(
                          children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                ResponsiveHelper.spacing(context, 16),
                                ResponsiveHelper.spacing(context, 12),
                                ResponsiveHelper.spacing(context, 12),
                                ResponsiveHelper.spacing(context, 12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: AppSearchBar(
                                      controller: _searchController,
                                      hintText: '공고 제목, 사업장명 검색',
                                      padding: EdgeInsets.zero,
                                      onClear: () {
                                        _searchDebounce?.cancel();
                                        _onFilterChanged(_filter.copyWith(clearKeyword: true));
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
                                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                  _buildFilterButton(context),
                                ],
                              ),
                            ),
                            const Divider(height: 1, thickness: 1, color: AppColors.grey100),
                          ],
                        ),
                      ),

                      // TO 목록 (스크롤)
                      Expanded(
                        child: _isLoading
                            ? const TOListSkeleton()
                            : _displayList.isEmpty
                                ? _buildEmptyState()
                                : RefreshIndicator(
                                    onRefresh: () => _loadAllTOs(forceRefresh: true),
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
                                        // H2: 카드별 notifier — 슬롯/업무상세 로드 시 해당 카드만 리빌드
                                        final slotsN = _slotNotifiers.putIfAbsent(
                                            to.id, () => ValueNotifier(_slotsCache[to.id]));
                                        final detailsN = _workDetailsNotifiers.putIfAbsent(
                                            to.id, () => ValueNotifier(_workDetailsCache[to.id]));
                                        return RepaintBoundary(
                                          child: ValueListenableBuilder<List<SlotModel>?>(
                                            valueListenable: slotsN,
                                            builder: (_, slots, __) =>
                                                ValueListenableBuilder<List<WorkDetailModel>?>(
                                              valueListenable: detailsN,
                                              builder: (_, workDetails, __) => UserTOCard(
                                                to: to,
                                                isSelected: isSelected,
                                                onTap: () =>
                                                    _toggleTOSelection(to.id),
                                                myApplications: _myApplications,
                                                onApplySuccess:
                                                    _refreshMyApplications,
                                                workDetails: workDetails,
                                                onFetchWorkDetails:
                                                    _fetchWorkDetails,
                                                slots: slots,
                                                onFetchSlots: _fetchSlots,
                                                isAnyOtherExpanded:
                                                    _selectedTOId != null &&
                                                        _selectedTOId != to.id,
                                              ),
                                            ),
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

  Widget _buildFilterButton(BuildContext context) {
    final theme = Theme.of(context);
    // sortBy=='date'도 배지에 포함 (기본값 'createdAt'과 다를 때)
    final badgeCount = _filter.activeCount + (_filter.sortBy == 'date' ? 1 : 0);
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
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
              child: Icon(
                Icons.tune,
                color: hasActive ? Colors.white : AppColors.grey600,
                size: ResponsiveHelper.iconSize(context, 22),
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
                color: Colors.red,
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

// ── 통합 필터 바텀시트 ──────────────────────────────────────────

class _AllFilterSheet extends StatefulWidget {
  const _AllFilterSheet({
    required this.initialFilter,
    required this.onApply,
    required this.availableCities,
    required this.districtMap,
  });

  final TOFilterState initialFilter;
  final ValueChanged<TOFilterState> onApply;
  final List<String> availableCities;
  final Map<String, List<String>> districtMap;

  @override
  State<_AllFilterSheet> createState() => _AllFilterSheetState();
}

class _AllFilterSheetState extends State<_AllFilterSheet> {
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
      setState(() => _local = _local.copyWith(city: result.city, district: result.district));
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
        color: Colors.white,
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
              width: 40, height: 4,
              margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(color: AppColors.grey300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // 타이틀 + 초기화
          Row(
            children: [
              Text('필터', style: ResponsiveHelper.titleStyle(context).copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _local = const TOFilterState()),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 8)),
                ),
                child: Text('초기화', style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500)),
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
            onTap: () => setState(() => _local = _local.copyWith(showFavoritesOnly: !_local.showFavoritesOnly)),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // ─ 근무 유형
          _sectionLabel(context, '근무 유형'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Row(
            children: [
              _typeChip(context, theme, null, '전체'),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _typeChip(context, theme, 'flex', '단기'),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _typeChip(context, theme, 'contract', '장기'),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // ─ 지역
          _sectionLabel(context, '지역'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          _rowSelector(
            context, theme,
            label: _local.city != null
                ? (_local.district != null ? '${_local.city} ${_local.district}' : _local.city!)
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
                ? () => setState(() => _local = _local.copyWith(clearDateRange: true))
                : null,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // ─ 정렬
          _sectionLabel(context, '정렬'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Row(
            children: [
              _sortChip(context, theme, 'createdAt', '최신순'),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _sortChip(context, theme, 'date', '마감임박순'),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 20)),

          // ─ 적용 버튼
          SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onApply(_local);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 14)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  '적용하기',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
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

  // 즐겨찾기 토글 칩
  Widget _toggleItem(BuildContext context, ThemeData theme, {
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
            border: Border.all(color: isSelected ? theme.primaryColor : AppColors.grey300),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: isSelected ? Colors.white : AppColors.grey600,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      );

  // 근무유형 칩 (Expanded row)
  Widget _typeChip(BuildContext context, ThemeData theme, String? value, String label) {
    final isSelected = _local.type == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _local = _local.copyWith(type: value, clearType: value == null)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 10)),
          decoration: BoxDecoration(
            color: isSelected ? theme.primaryColor : Colors.transparent,
            border: Border.all(color: isSelected ? theme.primaryColor : AppColors.grey300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: isSelected ? Colors.white : AppColors.grey600,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  // 정렬 칩 (Expanded row)
  Widget _sortChip(BuildContext context, ThemeData theme, String value, String label) {
    final isSelected = _local.sortBy == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _local = _local.copyWith(sortBy: value)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 10)),
          decoration: BoxDecoration(
            color: isSelected ? theme.primaryColor : Colors.transparent,
            border: Border.all(color: isSelected ? theme.primaryColor : AppColors.grey300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: isSelected ? Colors.white : AppColors.grey600,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  // 지역·날짜 선택 행
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
            color: isSet ? theme.primaryColor.withValues(alpha: 0.06) : AppColors.grey50,
            border: Border.all(
              color: isSet ? theme.primaryColor.withValues(alpha: 0.4) : AppColors.grey200,
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
                    fontWeight: isSet ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: const Icon(Icons.close, size: 16, color: AppColors.grey400),
                )
              else
                const Icon(Icons.chevron_right, size: 18, color: AppColors.grey400),
            ],
          ),
        ),
      );

  String _fmt(DateTime dt) => '${dt.month}/${dt.day}';
}
