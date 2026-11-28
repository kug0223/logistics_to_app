import 'dart:async';
import 'user_job_tab_reads.dart';
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
import '../tab_revisit_watch.dart';
import '../user_tab_scope.dart';

/// 일자리 탭 — 일자리 찾기 + 내 지원 탭 구조 (Phase 2)
///
/// 탭:
///   0: 일자리 찾기 — 공고 목록 (검색·빠른필터·컴팩트 카드)
///   1: 내 지원 — MyApplicationsScreen
///
/// Phase 1 허브 화면('무엇을 찾으시나요?') 제거.
/// 공고 데이터 로딩·필터 로직을 담당하는 canonical 일자리 탭.
class UserJobTab extends StatefulWidget {
  const UserJobTab({super.key, this.reads, this.clock});

  /// [R7-P2-2 P22-L] 목록을 만들 때의 읽기 경계. production 은 null.
  final UserJobTabReads? reads;

  /// [PERF-L18·P9] "지금"의 출처(자동 이어읽기 시간 상한·재방문 신선도). production 은 null → `DateTime.now`.
  final DateTime Function()? clock;

  @override
  State<UserJobTab> createState() => _UserJobTabState();
}

class _UserJobTabState extends State<UserJobTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── 공고 목록 상태 ────────────────────────────────────────────────
  final FirestoreService _firestoreService = FirestoreService();
  late final UserJobTabReads _reads =
      widget.reads ?? UserJobTabReads.of(_firestoreService);
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

  /// [JOBS-LOST-REFRESH] 진행 중에 들어온 재조회 요청(검색·필터 변경 등). 버리지 않고
  ///   진행 중 로드가 **성공으로** 끝난 직후 한 번만 다시 돈다(지원 내역도 새로 읽는다).
  ///   여러 번 들어와도 플래그 하나라 마지막 필터로 한 번 수렴한다.
  bool _reloadPending = false;

  /// [R8-P7.4] 목록을 **읽지 못했다**.
  ///
  /// 빈 목록이 "등록된 공고가 없습니다"가 되는 자리라서, 비어 있는 이유를
  /// 따로 들고 있어야 한다. 실패를 "공고 없음"으로 말하면 사용자는 앱이
  /// 정상이라고 믿은 채 지원 기회를 놓친다.
  bool _loadFailed = false;

  /// [DU209 J15] 마지막 **전체조회가 성공으로 확정**됐다 — 필터 시트가 수·'없음'을
  ///   말해도 되는 모집단인가. 전체조회 시작에 false, 성공 commit 에서 보류 재조회가
  ///   없을 때만 true, 실패는 false 그대로다. `_loadFailed`(본문·머리말: 비어 있는데
  ///   못 읽음)와 다르다 — 이전 목록이 남아 있으면 실패해도 `_loadFailed` 는 false 다.
  ///   추가 페이지 실패는 이 값을 건드리지 않는다(이미 성공한 부분 모집단).
  bool _populationSucceeded = false;
  bool _myApplicationsLoaded = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  // ── [PERF-L18 · 판정291 §1] 빈 결과 자동 이어읽기 예산 ─────────────────────
  //   화면이 비고 hasMore 면 다음 페이지를 이어 읽는데(날짜 같은 로컬 조건), 예전에는 상한이 없어
  //   끝까지 직렬로 읽었다. **페이지 수·경과 시간** 두 상한 중 먼저 닿으면 새 자동 요청을 시작하지 않고,
  //   "여기까지 확인했어요 · 더 찾아보기" 로 사용자가 다음 묶음을 고르게 한다. 정상 0 은 서버가
  //   끝(hasMore=false)이라고 한 때만이다. 새 조회·필터·검색은 새 예산이다. 빈 프레임·재build·스크롤은 초기화하지 않는다.
  static const int _autoChainMaxPages = 3;
  static const Duration _autoChainMaxElapsed = Duration(seconds: 8);
  int _autoChainPages = 0;
  DateTime? _autoChainStartedAt;

  /// 예산이 다 됐거나(또는 서버 응답이 진행하지 않아) 자동 이어읽기를 멈췄다 — hasMore 는 그대로다.
  bool _autoChainStopped = false;

  void _resetAutoChainBudget() {
    _autoChainPages = 0;
    _autoChainStartedAt = null;
    _autoChainStopped = false;
  }

  /// 화면이 빈 채 남은 페이지가 있을 때의 **자동** 이어읽기 — 예산 안에서만.
  void _autoLoadMore() {
    if (!mounted || _autoChainStopped) return;
    final started = _autoChainStartedAt ??= _now();
    if (_autoChainPages >= _autoChainMaxPages ||
        _now().difference(started) >= _autoChainMaxElapsed) {
      setState(() => _autoChainStopped = true);
      return;
    }
    _autoChainPages++;
    _loadMoreTOs();
  }

  /// 사용자가 고른 "더 찾아보기 / 더 많은 공고 보기" — 같은 조건·커서의 다음 묶음을 새 예산으로 시작한다.
  void _loadMoreByUser() {
    _resetAutoChainBudget();
    _loadMoreTOs();
  }

  // ── [PERF-P9 · 판정291 §8] 재방문 신선도 ─────────────────────────────────
  //   다시 보이거나(다른 탭·상세에서 돌아옴) 보이는 채로 앱이 복귀하면 데이터별로 본다.
  //   · 지원 내역: 무효화 세대가 바뀌었거나(지원·취소·확정 등) 1분(서비스 TTL)이 지났으면 다시 읽는다.
  //   · 공고 목록: 3분이 지났거나 KST 날짜가 바뀌었고, **첫 페이지만** 보고 있을 때 화면을 비우지 않고 다시 읽는다.
  //     더 불러온 뒤(커서 진행)면 사용자가 본 위치를 지키려고 목록은 다시 읽지 않는다.
  //   실패는 각 경로의 기존 정책 그대로다(첫 페이지 실패 = DU210 실패 화면 · 지원 내역 실패 = 이전 값 유지).
  //   이미 신선하면 호출 0. 계정이 바뀌었으면 처음부터 다시 읽는다.
  static const Duration _appsFreshFor = Duration(minutes: 1);
  static const Duration _listFreshFor = Duration(minutes: 3);
  late final TabRevisitWatch _revisit = TabRevisitWatch(onRevisit: _onRevisit);
  DateTime? _listLoadedAt;
  DateTime? _appsLoadedAt;
  int? _appsRevAtLoad;
  String? _loadedUid;
  int _pagesLoaded = 0;

  int? _appsRevision(String? uid) =>
      uid == null ? null : _reads.applicationsRevision?.call(uid);

  void _onRevisit() {
    if (!mounted || _isLoading || _fetchInProgress) return;
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (_loadedUid != null && uid != _loadedUid) {
      _loadAllTOs(forceRefresh: true);
      return;
    }
    final now = _now();
    final appsAt = _appsLoadedAt;
    final appsStale = uid != null &&
        (appsAt == null ||
            now.difference(appsAt) >= _appsFreshFor ||
            _appsRevision(uid) != _appsRevAtLoad);
    final listAt = _listLoadedAt;
    final listStale = listAt != null &&
        !_loadFailed &&
        _pagesLoaded <= 1 &&
        (now.difference(listAt) >= _listFreshFor ||
            FormatHelper.toKstDate(now) != FormatHelper.toKstDate(listAt));
    if (listStale) {
      if (appsStale) _myApplicationsLoaded = false;
      _loadAllTOs(quiet: true);
    } else if (appsStale) {
      _refreshMyApplications();
    }
  }

  // ── 초기화 ──────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _revisit.attach();
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
  /// [PERF-L5] 첫 didChangeDependencies 를 지났는가 — 첫 생성(= 지연 생성 뒤 첫 방문)과 기방문을 가른다.
  bool _depsInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _revisit.updateFrom(context);
    final scope = UserTabScope.of(context);
    final pending = scope?.pendingJobDate;
    final firstMount = !_depsInitialized;
    _depsInitialized = true;
    if (pending != null) {
      // clearFn을 여기서 캡처한다.
      // postFrameCallback 안에서 UserTabScope.of(context)를 재호출하면
      // 빌드 페이즈 밖에서의 dependOnInheritedWidgetOfExactType 호출로
      // debug assertion이 터져 콜백이 중단되므로, 반드시 클로저로 미리 캡처해야 한다.
      final clearFn = scope!.clearPendingJobDate;
      if (firstMount) {
        // [PERF-L5] 첫 생성 — 첫 그리기·첫 조회(initState postFrame `_loadAllTOs`) **전에** 하루 필터를 둔다.
        //   날짜는 서버 조건이 아니라 로컬 조건이라(`_onFilterChanged` needsServerFetch 제외) 조회 수는 그대로 1이다.
        //   날짜 미적용 목록이 한 프레임 보였다 바뀌는 일이 없다.
        _filter = _filter.copyWith(dateRange: DateTimeRange(start: pending, end: pending));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) clearFn(); // root 상태 소비만
        });
        return;
      }
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
    _revisit.dispose();
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

  /// [quiet] — [PERF-P9] 재방문 재검증. 보이는 목록을 비우거나 뼈대로 바꾸지 않고 다시 읽어 성공하면 바꾼다.
  ///   실패는 일반 조회와 같다(DU210 — 첫 페이지를 못 읽으면 목록을 지우고 실패 화면).
  Future<void> _loadAllTOs({bool forceRefresh = false, bool quiet = false}) async {
    if (_fetchInProgress) {
      _reloadPending = true;
      return;
    }
    _fetchInProgress = true;
    _generation++;
    _resetAutoChainBudget(); // [PERF-L18] 새 조회 = 새 예산
    if (quiet) {
      if (forceRefresh) _myApplicationsLoaded = false;
    } else {
      setState(() {
        _isLoading = true;
        _lastToId = null;
        _hasMoreData = true;
        _populationSucceeded = false;
        _allTOList = [];
        _workDetailsCache.clear();
        _slotsCache.clear();
        if (forceRefresh) _myApplicationsLoaded = false;
      });
    }

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      final fetchApps = uid != null && !_myApplicationsLoaded;
      final appsRevAtStart = fetchApps ? _appsRevision(uid) : null;
      final appsFuture = fetchApps
          ? _reads.myApplications(uid)
          : Future.value(_myApplications);

      List<TOModel> toList;
      String? lastToId;
      bool hasMore;

      if (_filter.showFavoritesOnly) {
        final favoriteIds =
            userProvider.currentUser?.favoriteToIds ?? const [];
        toList = favoriteIds.isEmpty
            ? []
            : await _reads.tosByIds(favoriteIds);
        lastToId = null;
        hasMore = false;
      } else if (_filter.keyword?.isNotEmpty == true &&
          AlgoliaService.isConfigured) {
        final ids = await AlgoliaService.searchTOIds(_filter.keyword!,
            filter: _filter);
        toList = await _reads.tosByIds(ids);
        lastToId = null;
        hasMore = false;
      } else {
        final tosResult =
            await _reads.publishedTOsPaged(filter: _filter);
        toList = tosResult['items'] as List<TOModel>;
        lastToId = tosResult['lastToId'] as String?;
        hasMore = tosResult['hasMore'] as bool;
      }

      final myApps = await appsFuture;
      if (!mounted) return;

      final regionResult = _computeRegionOptions(toList);
      final displayList = _computeDisplayList(toList);
      _fetchInProgress = false;
      // [PERF-P9] 신선도 기준점 — 이 조회가 성공한 시각·계정·지원 내역 세대.
      final loadedAt = _now();
      _listLoadedAt = loadedAt;
      _loadedUid = uid;
      _pagesLoaded = 1;
      if (fetchApps) {
        _appsLoadedAt = loadedAt;
        _appsRevAtLoad = appsRevAtStart;
      }
      setState(() {
        _workDetailsCache.clear();
        _slotsCache.clear();
        _allTOList = toList;
        _lastToId = lastToId;
        _hasMoreData = hasMore;
        _myApplications = myApps;
        _myApplicationsLoaded = true;
        _availableCities = regionResult.cities;
        _districtMap = regionResult.districtMap;
        _displayList = displayList;
        _isLoading = false;
        _loadFailed = false;
        // [DU209 J15] 보류 재조회가 걸려 있으면 이 응답은 현재 조건의 성공이 아니다.
        _populationSucceeded = !_reloadPending;
      });
      // [R7-P2-2 P22-L] 기준은 **화면에 남은 것**이다. 서버 페이지가 비지
      //   않았어도 날짜 같은 클라이언트 조건이 전부 걸러 냈으면 화면은
      //   비어 있고, 그때도 남은 페이지를 이어 읽어야 한다.
      //   (예전에는 서버 페이지가 빌 때만 이어 읽어, 홈에서 날짜를 골라
      //    들어온 사람이 첫 페이지에 그 날이 없으면 거기서 멈췄다.)
      if (_reloadPending) {
        // 진행 중에 들어온 요청 — 그 사이 지원 내역이 바뀌었을 수 있으니 새로 읽는다.
        _reloadPending = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadAllTOs(forceRefresh: true);
        });
        return;
      }
      if (displayList.isEmpty && hasMore) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _autoLoadMore(); // [PERF-L18] 예산 안에서만
        });
      }
    } catch (e) {
      debugPrint('❌ TO 목록 로드 실패: $e');
      // 실패면 보류 요청을 자동으로 다시 돌리지 않는다 — 실패 화면의 다시 시도가 현재 필터로 읽는다.
      _reloadPending = false;
      if (!mounted) return;
      _fetchInProgress = false;
      setState(() {
        _isLoading = false;
        // [DU210 C209-1] 첫 페이지를 읽지 못했으면 이전 표시 목록을 지운다 — 같은 조건
        //   새로고침이더라도 그 목록은 현재 선택 조건의 성공 결과가 아니다. 기존 실패
        //   머리말·본문·다시 시도로 간다(R8-P7.4 의 '이전 목록 유지'를 대체한다).
        //   hasMore=false 는 읽을 cursor 가 없다는 뜻일 뿐 성공 0 이 아니다 — 성공
        //   인증은 _populationSucceeded(false 그대로)가 맡는다. 추가 페이지 실패의
        //   일부 목록 보존은 _loadMoreTOs 의 catch 그대로다.
        _displayList = [];
        _hasMoreData = false;
        _loadFailed = true;
        // [PERF-P9] 조용한 재검증이 실패해도 같다 — 이전 목록을 현재 조건의 성공으로 남기지 않는다.
        _allTOList = [];
        _lastToId = null;
        _populationSucceeded = false;
        _listLoadedAt = null;
      });
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
      final tosResult = await _reads.publishedTOsPaged(
        lastToId: _lastToId,
        filter: _filter,
      );
      final toList = tosResult['items'] as List<TOModel>;
      final nextCursor = tosResult['lastToId'] as String?;
      final serverHasMore = tosResult['hasMore'] as bool;

      if (!mounted || _generation != gen) {
        _isLoadingMore = false;
        return;
      }
      if (toList.isEmpty) {
        // [PERF-L18 · 판정291 §1] 빈 페이지를 "끝"으로 단정하지 않는다 — 서버가 끝이라고 할 때만 끝이다.
        //   서버가 더 있다고 하면 자동 연쇄만 멈추고 hasMore 는 그대로 둔다(정상 0 인증 0 · 사용자가 더 찾아볼 수 있다).
        setState(() {
          if (serverHasMore && nextCursor != null && nextCursor != _lastToId) {
            _lastToId = nextCursor;
            _autoChainStopped = true;
          } else if (serverHasMore) {
            _autoChainStopped = true;
          } else {
            _hasMoreData = false;
          }
          _isLoadingMore = false;
        });
        return;
      }
      // [PERF-L18] 같은 커서를 다시 받으면(진행 없음) 자동 연쇄를 멈춘다 — 무한 반복 방지 · hasMore 는 서버 값 그대로.
      final cursorStalled = serverHasMore && nextCursor == _lastToId;
      // 이미 받은 공고가 다시 오면 겹쳐 그리지 않는다.
      final seen = {for (final t in _allTOList) t.id};
      final fresh = toList.where((t) => !seen.contains(t.id)).toList();

      final mergedList = [..._allTOList, ...fresh];
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
      _pagesLoaded++;
      setState(() {
        _allTOList = mergedList;
        _lastToId = nextCursor;
        _hasMoreData = serverHasMore;
        _availableCities = mergedCities;
        _districtMap = mergedDistricts;
        _displayList = displayList;
        _isLoadingMore = false;
        if (cursorStalled) _autoChainStopped = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _displayList.isEmpty && _hasMoreData && !_isLoadingMore) {
          _autoLoadMore(); // [PERF-L18] 예산 안에서만
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

    // [R8-P9C] flex 노출 판정용 오늘 날짜 키 — 공고 문서 `dates`와 같은 포맷.
    final todayKey = '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';

    final result = toList.where((to) {
      if (to.isManualClosed) return false;
      if (!to.isLongTerm) {
        // [R8-P9C] rangeEnd 로 flex 노출을 판단하지 않는다.
        //
        //   rangeEnd 는 공고 생성 때 한 번 기록되고 슬롯 추가·삭제로는
        //   갱신되지 않는다. 그런데 이 자리는 `rangeEnd == null`이면 곧바로
        //   제외했다 — DEV 에서 서버가 돌려준 공개 flex 공고 4건이 전부
        //   rangeEnd 가 없어, 오늘 근무가 열려 있는 공고까지 목록에서
        //   통째로 사라져 있었다.
        //
        //   판단은 갱신되는 값(isManualClosed·status·isPublished)으로 하고,
        //   날짜는 확실히 알 때만 쓴다. 모르면 노출하고 서버가 판정한다.
        if (!to.isVisibleToWorkerFlex(todayKey)) return false;
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
        // [R8-P9D] flex 는 실제 슬롯 날짜와 겹치는지로 본다.
        //
        //   이전에는 `to.rangeEnd ?? to.date` 를 끝 경계로 썼는데, flex 는
        //   rangeEnd 가 없는 경우가 많고 그러면 `to.date` = createdAt 으로
        //   떨어진다. DEV 의 kcwGL5K4 는 오늘(9/22) 근무가 있는데 createdAt
        //   이 9/15 라, "이번 주" 필터에서 `toEnd < rangeStart` 로 걸러졌다.
        //   등록한 날짜가 근무 날짜를 대신할 수 없다.
        if (!to.isLongTerm) {
          if (to.slotDateKeys.isNotEmpty && to.slotDatesLookComplete) {
            final fromKey = FormatHelper.toKstDateKey(rangeStart);
            final toKey = FormatHelper.toKstDateKey(rangeEnd);
            final hit = to.slotDateKeys.any((d) =>
                d.compareTo(fromKey) >= 0 && d.compareTo(toKey) <= 0);
            if (!hit) return false;
          }
          // 날짜를 모르면 걸러내지 않는다 — 모르는 것으로 숨기지 않는다.
          return true;
        }

        final toStart = FormatHelper.toKstDate(to.date);
        // 신규 preset: workStartAvailableUntil / custom·legacy: endDate(=rangeEnd)
        final toEndRaw = to.hasWorkStartAvailableRange
            ? to.workStartAvailableUntil!
            : (to.endDate ?? to.date);
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
        _resetAutoChainBudget(); // [PERF-L18] 새 조건 = 새 예산
      });
      // [R7-P2-2 P22-L] 서버에 다시 묻지 않는 조건(날짜 등)이라도, 그 조건이
      //   **이미 받아 온 페이지**를 모두 걸러 냈다면 남은 페이지를 이어 읽는다.
      //   `_loadMoreTOs` 가 이미 같은 방식으로 꼬리를 문다(빈 결과면 계속) — 예산 안에서만.
      if (_displayList.isEmpty && _hasMoreData && !_isLoadingMore && !_isLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _autoLoadMore();
        });
      }
    }
  }

  Future<void> _refreshMyApplications() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;
      if (uid != null) {
        final rev = _appsRevision(uid);
        final myApps = await _reads.myApplications(uid);
        if (mounted) {
          _appsLoadedAt = _now(); // [PERF-P9] 신선도 기준점
          _appsRevAtLoad = rev;
          setState(() => _myApplications = myApps);
        }
      }
    } catch (e) {
      debugPrint('❌ 지원 내역 새로고침 실패: $e');
    }
  }

  void _showAllFilters() {
    // [DU209 J15] 시트를 여는 순간의 모집단·서버조건·성공/로딩·hasMore 를 함께 고정한다.
    //   미리보기 수는 이 같은 자료에 로컬 선택만 적용한다(live 목록과 개방 시 hasMore 를
    //   섞지 않는다). 모르는 결과는 null → 시트는 '적용하기'(활성)로 말한다.
    final population = List<TOModel>.unmodifiable(_allTOList);
    final serverFilter = _filter;
    final populationKnown = _populationSucceeded && !_isLoading;
    final hasMore = _hasMoreData;
    DialogHelper.showSheet(
      context,
      isScrollControlled: true,
      builder: (_) => _JobFilterSheet(
        initialFilter: _filter,
        availableCities: _availableCities,
        districtMap: _districtMap,
        onApply: _onSheetApply,
        countOf: (f) {
          // 로딩 중·성공 미확정(실패·보류)·서버조건이 다른 선택은 아직 묻지 않은 결과다.
          if (!populationKnown || !_sameServerCondition(f, serverFilter)) {
            return null;
          }
          final n = _computeDisplayList(population, withFilter: f).length;
          // 읽을 페이지가 남은 부분 모집단의 0 은 '없음'이 아니다.
          if (n == 0 && hasMore) return null;
          return n;
        },
        hasMore: hasMore,
      ),
    );
  }

  /// [DU209 J15] 서버 재조회 조건 — `_onFilterChanged` 의 needsServerFetch 와 같은 집합
  ///   (type·city·district·keyword·showFavoritesOnly). dateRange·sortBy 는 로컬 조건이다.
  bool _sameServerCondition(TOFilterState a, TOFilterState b) =>
      a.type == b.type &&
      a.city == b.city &&
      a.district == b.district &&
      a.keyword == b.keyword &&
      a.showFavoritesOnly == b.showFavoritesOnly;

  /// [DU209 J15] 시트 적용 — 마지막 전체조회가 성공으로 확정되지 않았고(실패·보류)
  ///   지금 읽는 중이 아니면, 고른 조건으로 첫 페이지부터 다시 읽는다(같은 조건의 초기
  ///   실패도 포함). 그 밖에는 기존 `_onFilterChanged` 그대로다 — 진행 중 조회의
  ///   보류/수렴, 같은 성공 조건의 재조회 0, 부분 0 의 이어읽기를 바꾸지 않는다.
  void _onSheetApply(TOFilterState f) {
    if (!_populationSucceeded && !_isLoading) {
      _filter = f;
      _loadAllTOs();
      return;
    }
    _onFilterChanged(f);
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

  /// [DU310 J13] 머리 제목 스타일(표시·높이 측정 공용).
  static const TextStyle _titleStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  /// [DU310 r1 J13] AppBar 가 제목 위에 까는 바탕 글자 스타일 — SDK app_bar.dart:958–961 의
  ///   `widget.titleTextStyle ?? appBarTheme.titleTextStyle ?? defaults.titleTextStyle`(M3 기본 = textTheme.titleLarge)과
  ///   같은 순서다. 이 AppBar 는 titleTextStyle 을 지정하지 않으므로 앞 항은 없다. 앱 통합 테마는
  ///   appBarTheme.titleTextStyle(role_theme.dart:55, NotoSansKR 20 bold)을 준다. :969 의 색 투명도는 높이와 무관하다.
  TextStyle _titleBaseStyle(ThemeData theme) =>
      theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge ?? const TextStyle();

  /// [DU310 r1 J13] 머리 높이 — 1.0 기준 44 는 그대로 두고, 실제 제목 한 줄(아래 Text 와 같은 유효 스타일·
  ///   사용자 글자 배율·굵게·locale·줄 높이 동작)이 44 안에 들어가지 않으면 줄 높이 + 위아래 4 로 늘린다.
  ///   [scaler] 는 AppBar 바깥(build)의 실제 배율 — AppBar 가 제목에 거는 1.34 상한(app_bar.dart:45·:1073)을
  ///   제목 Text 에 직접 넘겨 벗어나므로 측정도 같은 값을 쓴다(글자를 줄이거나 자르지 않는다).
  double _titleBarHeight(BuildContext context, TextScaler scaler) {
    // Text.build 와 같은 병합: AppBar 의 DefaultTextStyle(바탕) ← _titleStyle(inherit) ← boldText.
    var style = _titleBaseStyle(Theme.of(context)).merge(_titleStyle);
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final tp = TextPainter(
      text: TextSpan(text: '일자리', style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      locale: Localizations.maybeLocaleOf(context),
      // AppBar 의 DefaultTextStyle 은 textHeightBehavior 를 주지 않는다 → Text 는 DefaultTextHeightBehavior 를 쓴다.
      textHeightBehavior: DefaultTextHeightBehavior.maybeOf(context),
      maxLines: 1,
    )..layout();
    final need = tp.height + 8;
    tp.dispose();
    return need > 44 ? need : 44;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // [DU310 r1 J13] AppBar 바깥의 실제 사용자 배율(1.34 상한 적용 전).
    final titleScaler = MediaQuery.textScalerOf(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: _titleBarHeight(context, titleScaler),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text(
            '일자리',
            style: _titleStyle,
            // [DU310 r1 J13] AppBar 의 제목 배율 상한(1.34)을 벗어나 사용자 배율 그대로 그린다(SDK 주석의 opt-out 경로:
            //   Text.textScaler 가 MediaQuery 보다 우선). 높이는 위 _titleBarHeight 가 같은 값으로 확보한다.
            textScaler: titleScaler,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                labelColor: theme.primaryColor,
                // [DU310 J10] 미선택 탭 글자 grey500(흰 바탕 2.68:1) → textSecondary(5.92:1). 선택 brand·굵기 위계는 그대로.
                unselectedLabelColor: AppColors.textSecondary,
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
        // 결과 요약 라인 — 로딩 완료 후 표시.
        //   [PERF-P11] 자리는 처음부터 잡아 둔다 — 응답 뒤 한 줄이 끼어들며 목록이 밀리던 흔들림 0.
        //   로딩 중에는 보이지 않고(이전·0 숫자를 말하지 않는다) 읽기 보조에도 나오지 않는다.
        Visibility(
          visible: !_isLoading,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: _buildResultSummary(context),
        ),
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
    // [DU1 R6] 첫 페이지를 읽지 못했으면 머리말이 '0개'라고 말하지 않는다 — 아래 오류 본문(다시 시도)과 같은 사실.
    //   정상 0개·확인된 일부(목록이 있는 뒤 추가 실패)는 그대로 둔다(_loadFailed 는 목록이 비었을 때만 참).
    final shown = _loadFailed ? '일자리를 확인하지 못했어요' : label;

    return Container(
      width: double.infinity,
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        shown,
        // [DU1] 머리말 수치는 읽는 정보 — grey500(2.68:1) → textSecondary
        style: ResponsiveHelper.smallStyle(context,
            color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildSearchHeader(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // 검색바 행
          // [DU310 J11] 아래 칩 줄의 receiver 가 48 로 커지면서 생기는 위아래 여유가 보이는 간격을 일부 대신한다 — 아래 8 → 4.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 4),
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
      // [DU310 J11] 칩 receiver 48 의 아래 여유가 간격을 대신한다 — 아래 10 → 6.
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          // 즐겨찾기 — 하트 아이콘 칩: 기본 Neutral, 활성 시 다른 빠른 칩과 같은 brand 선택(DU310, 이전 Red)
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

  /// [DU310 J11·J12] 칩 누름 영역 — 보이는 칩 모양·크기는 그대로 두고 receiver 만 최소 48×48
  ///   (글자 확대로 칩이 더 크면 칩 크기). 버튼·선택 의미는 이 노드가 말한다(칩 글자는 그대로 읽힌다).
  Widget _chipReceiver({
    required Widget chip,
    required VoidCallback onTap,
    bool? selected,
  }) {
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Align(widthFactor: 1, heightFactor: 1, child: chip),
        ),
      ),
    );
  }

  /// 즐겨찾기 칩 — 하트 아이콘 + "즐겨찾기" 텍스트
  /// 기본: Neutral 테두리, 비활성 아이콘
  /// 활성: [DU310 Standards §9.1·사용자 기준 "선택은 대표색"] 다른 빠른 칩(단기·장기)과 같은 brand 채움 + 흰 글자·채운 하트.
  ///   이전 Red 테두리/글자/옅은 Red 바탕은 선택 상태를 위험색으로 칠했다.
  Widget _favoriteIconChip(BuildContext context, ThemeData theme) {
    final active = _filter.showFavoritesOnly;
    return _chipReceiver(
      selected: active,
      onTap: () => _onFilterChanged(
          _filter.copyWith(showFavoritesOnly: !_filter.showFavoritesOnly)),
      chip: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            Icon(
              active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 13,
              // [DU310] 비활성 하트 grey400(1.88:1) → textSecondary
              color: active ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              '즐겨찾기',
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: active ? Colors.white : AppColors.grey700,
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
    // [DU310 J12] 해제 X 의 receiver 가 아이콘 14 뿐이었다 — 이 칩의 유일한 행동이 해제이므로 칩 전체(최소 48)를
    //   같은 onClear 로 누른다. 보이는 X·값·색은 그대로다.
    return _chipReceiver(
      selected: true,
      onTap: onClear,
      chip: _activeFilterChipFace(theme, label),
    );
  }

  Widget _activeFilterChipFace(ThemeData theme, String label) {
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
          // 해제 표시 — 누름은 칩 전체(_activeFilterChip)가 받는다.
          Icon(Icons.close, size: 14, color: theme.primaryColor),
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
    // [DU310 J11] 보이는 칩은 그대로, receiver 만 최소 48×48(_chipReceiver).
    return _chipReceiver(
      selected: active,
      onTap: onTap,
      chip: AnimatedContainer(
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
                // [DU310] 비활성 칩 아이콘 grey500(2.68:1) → textSecondary
                color: active ? Colors.white : AppColors.textSecondary,
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
            // [DU310 J11] 버튼 42×42 → 최소 48×48(옆 검색창 높이 48 과 같은 줄). 아이콘 22·색은 그대로.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Icon(
                  Icons.tune,
                  color: hasActive ? Colors.white : AppColors.grey600,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
        if (hasActive)
          Positioned(
            top: -5,
            right: -5,
            // [DU310 §12.2] 적용 개수는 오류가 아니다 — 빨간 원(error) 대신 흰 바탕·brand 테두리/숫자.
            //   크기는 고정 17×17 대신 최소 17·숫자 자연 크기(큰 글씨에서 숫자가 원 밖으로 잘리지 않게).
            // [DU310 r1] 장식 배지는 누름을 받지 않는다 — Stack 은 마지막 자식부터 hit 를 시험해 멈추므로(SDK stack.dart:693,
            //   box.dart:3336) 버튼과 겹친 배지 아래 지점의 누름이 InkWell 에 가지 못했다(원본에도 있던 경로).
            //   IgnorePointer 로 그 지점의 누름도 필터 버튼 하나로 간다. 버튼 밖으로 나온 배지 부분은 receiver 가 아니다.
            child: IgnorePointer(
              child: Container(
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: theme.primaryColor, width: 1.5),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  '$badgeCount',
                  style: TextStyle(
                    color: theme.primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ),
            ),
            ),
          ),
      ],
    );
  }

  /// 목록 조건이 **하루**를 가리킬 때만 그 날짜. 범위·미선택이면 null.
  DateTime? get _singleSelectedDate {
    final dr = _filter.dateRange;
    if (dr == null) return null;
    final s = FormatHelper.toKstDate(dr.start);
    final e = FormatHelper.toKstDate(dr.end);
    return s == e ? dr.start : null;
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
                  onPressed: _loadMoreByUser,
                  icon: const Icon(Icons.expand_more, size: 18),
                  label: const Text('더 많은 공고 보기'),
                  style: OutlinedButton.styleFrom(
                    // [DU310 J17] 최소 높이 44 → 48(실 receiver 기준). 테두리·색·문구는 그대로.
                    minimumSize: const Size(double.infinity, 48),
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
              // [R7-P2-2 P22-N] 목록에서 하루를 고른 채로 상세에 들어가면
              //   그 날짜가 상세에서도 선택돼 있어야 한다. 범위 선택은
              //   가리키는 하루가 없으므로 넘기지 않는다.
              selectedDate: _singleSelectedDate,
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    // [R8-P7.4] 읽지 못한 것을 "없다"고 말하지 않는다. 즐겨찾기·필터 문구보다
    //   먼저 온다 — 목록을 못 읽었으면 그 어떤 "없음"도 사실이 아니다.
    if (_loadFailed) {
      return AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: '공고를 불러오지 못했습니다',
        subtitle: '네트워크 상태를 확인하고\n다시 시도해주세요',
        action: TextButton(
          onPressed: _loadAllTOs,
          child: const Text('다시 시도'),
        ),
      );
    }
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

    // [R7-P2-2 P22-L] 아직 **읽지 않은 페이지가 남아 있으면** "없다"가 아니다.
    //
    //   날짜·정렬 같은 조건은 서버가 아니라 이미 받아 온 페이지 위에서
    //   걸러진다(`_computeDisplayList`). 그래서 첫 페이지에 그 날짜가
    //   없으면 목록이 비는데, 그때 화면은 "조건에 맞는 공고가 없습니다"라고
    //   말하면서 **더 보기 버튼까지 감췄다**(그 버튼은 ListView 안에 있고
    //   빈 목록에서는 ListView 자체가 그려지지 않는다). 같은 화면의 머리말은
    //   `N개 이상` 이라고 말하는데 본문은 없다고 말하는 상태였다.
    //   읽을 것이 남아 있는 동안에는 **찾는 중**이라고 말하고 길을 연다.
    if (_hasMoreData) {
      // [PERF-L18 · 판정291 §1] 자동 이어읽기 예산이 다 됐으면 "여기까지 확인했다"고 말하고 다음 묶음을 사용자에게 맡긴다.
      //   "없다"·"0개"라고 하지 않는다(서버가 끝이라고 하지 않았다). 읽는 중이 아니면 스피너를 두지 않는다.
      final stopped = _autoChainStopped && !_isLoadingMore;
      return AppEmptyState(
        icon: Icons.manage_search_rounded,
        title: '아직 이 조건의 공고를 찾지 못했어요',
        subtitle: stopped
            ? '여기까지 확인했어요 · 더 찾아볼 수 있어요'
            : '더 불러와서 확인할 수 있어요',
        action: _isLoadingMore
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LoadingWidget(),
              )
            : OutlinedButton.icon(
                onPressed: _loadMoreByUser,
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text(stopped ? '더 찾아보기' : '더 많은 공고 보기'),
              ),
      );
    }

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

  /// 시트를 연 순간 고정한 모집단 기준 예상 결과 수 (필터 변경 시 실시간 업데이트)
  /// null이면 "적용하기" 텍스트 사용 — [DU209 J15] 모르는 결과(로딩·성공 미확정·
  /// 서버조건 변경·읽을 페이지가 남은 0)도 null 이다. 0 은 알려진 '없음'뿐이다.
  final int? Function(TOFilterState)? countOf;

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
                // [DU289 FS3] 초기화 글 grey500(2.68) → 보조색
                child: Text('초기화',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.textSecondary)),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // [DU289 FS6] 가운데 구역만 스크롤한다 — 큰 글자(320·2.0)에서 시트가 화면보다 길어 아래로 128px 넘치고
          //   적용 버튼이 화면 밖으로 나갔다. 손잡이·제목·초기화와 적용 버튼은 고정이다.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                ],
              ),
            ),
          ),
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
                  // [DU289 FS5] 비활성 글 grey500(#EEEEEE 위 2.31) → 보조색, 주 버튼 높이 52
                  disabledForegroundColor: AppColors.textSecondary,
                  minimumSize: const Size.fromHeight(52),
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
                    color: count == 0 ? AppColors.textSecondary : Colors.white,
                  ),
                ),
              ),
            );
          }(),
        ],
      ),
    );
  }

  // [DU289 FS1] 구역 제목 — 다른 시트(DU268·269·272)와 같은 16 bold 본문색(글자만).
  Widget _sectionLabel(BuildContext context, String label) => Text(
        label,
        style: ResponsiveHelper.bodyStyle(context).copyWith(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
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
          // [DU289 FS2] 터치 48(글은 세로 가운데), 비선택 글 grey600 → 보조색. 선택 모양(대표색 채움·흰 글)은 그대로.
          constraints: const BoxConstraints(minHeight: 48),
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
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
          // [DU289 FS2] 터치 48(글은 가운데), 비선택 글 grey600 → 보조색. 선택 모양은 그대로.
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
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
              color: isSelected ? Colors.white : AppColors.textSecondary,
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
          // [DU289 FS2] 터치 48(글은 가운데), 비선택 글 grey600 → 보조색. 선택 모양은 그대로.
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
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
              color: isSelected ? Colors.white : AppColors.textSecondary,
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
        // [DU289 FS4] 행 최소 52. 빈 행 글 grey600(4.41) → 보조색, 꺾쇠 grey400(1.80) → textTertiary,
        //   지우기 '×' 16×16 → 48×48 누름(IconButton, 보조색). 지우기는 행(선택기 열기)과 따로 눌린다.
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: EdgeInsets.only(
            left: ResponsiveHelper.spacing(context, 14),
            right: ResponsiveHelper.spacing(context, onClear != null ? 2 : 14),
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
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 12)),
                  child: Text(
                    label,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: isSet ? theme.primaryColor : AppColors.textSecondary,
                      fontWeight:
                          isSet ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
              if (onClear != null)
                IconButton(
                  onPressed: onClear,
                  tooltip: '지우기',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.close,
                      size: 18, color: AppColors.textSecondary),
                )
              else
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      );

  String _fmt(DateTime dt) => '${dt.month}/${dt.day}';
}
