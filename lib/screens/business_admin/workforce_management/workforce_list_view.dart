import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Models
import '../../../models/core/to_model.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';

// Services
import '../../../services/firestore_service.dart';

// Controllers
import '../../../controllers/workforce_controller.dart';

// Utils
import '../../../utils/format_helper.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';

// Widgets
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/inputs/filter_dialog.dart';

// Dialogs
import '../dialogs/to_list_dialogs.dart';

// Local Widgets
import '../../../widgets/admin/cards/admin_to_group_card.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/app_empty_state.dart';

/// [POSTING-V2-02E.1] 성공 조회 후 0건의 세 가지 의미.
///
/// 조회 실패(ERROR)는 이 집합에 넣지 않는다 — 01B에서 별도 renderer로 분리됐고
/// 그 계약은 그대로다.
enum _PostingEmptyKind {
  /// 공고 자체가 0개 (DRAFT/SCHEDULED 포함해서 0)
  root,

  /// 공고는 있지만 필터가 전부 걸러냄
  filtered,

  /// 필터는 없고 이 탭에만 없음 — 반대 탭에 공고가 있다
  tab,
}

/// 인력 관리 - 리스트 뷰
class WorkforceListView extends StatefulWidget {
  const WorkforceListView({super.key});

  @override
  State<WorkforceListView> createState() => _WorkforceListViewState();
}

class _WorkforceListViewState extends State<WorkforceListView> {
  final FirestoreService _firestoreService = FirestoreService();
  late TOListDialogs _dialogs;
  WorkforceController? _workforceController;

  // 탭 상태
  String _selectedTab = TOStatus.active;

  // 이중 토글 상태 관리
  final Set<String> _expandedGroups = {};
  final Set<String> _expandedTOs = {};
  // 아코디언: 현재 활성화된 그룹 카드 ID
  String? _activeGroupKey;

  // Lazy Loading 로컬 스피너 상태
  final Set<String> _loadingGroups = {};
  final Set<String> _loadingTOs = {};

  // 마감됨 탭 페이지네이션
  static const int _closedPageSize = 5;
  int _closedDisplayCount = _closedPageSize;
  final ScrollController _scrollController = ScrollController();

  // H2: 필터 결과 캐시 — items·필터·탭이 바뀔 때만 재계산
  List<TOGroupItem>? _lastCachedItems;
  String? _lastCachedTab;
  String? _lastCachedBusinessId; // [PATCH-IDENTITY] businessId 기반
  String? _lastCachedTOType;
  String? _lastCachedPublishStatus;
  DateTimeRange? _lastCachedDateRange;
  List<TOGroupItem> _cachedFilteredItems = [];

  @override
  void initState() {
    super.initState();
    _dialogs = TOListDialogs(
      context: context,
      firestoreService: _firestoreService,
      onChanged: _reload,
    );
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 컨트롤러에 필터 다이얼로그 콜백 등록
    _workforceController ??= context.read<WorkforceController>();
    _workforceController!.registerShowFilterCallback(_showFilterDialog);
    _workforceController!.registerOnExternalReload(_clearExpansionState);
  }

  @override
  void dispose() {
    _workforceController?.unregisterShowFilterCallback();
    _workforceController?.unregisterOnExternalReload();
    _scrollController.dispose();
    super.dispose();
  }

  void _clearExpansionState() {
    if (mounted) {
      setState(() {
        _expandedGroups.clear();
        _expandedTOs.clear();
        _activeGroupKey = null;
      });
    }
  }

  void _onScroll() {
    if (_selectedTab != TOStatus.closed) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 150) {
      // H1: 스크롤 이벤트마다 재계산 방지 — 마지막 build에서 채운 캐시 사용
      final total = _cachedFilteredItems.length;
      if (_closedDisplayCount < total) {
        setState(() => _closedDisplayCount =
            (_closedDisplayCount + _closedPageSize).clamp(0, total));
      }
    }
  }

  // [WF-UI-03] async로 변환 — RefreshIndicator의 onRefresh가 완료를 await할 수 있도록
  Future<void> _reload() async {
    setState(() {
      _expandedGroups.clear();
      _expandedTOs.clear();
      _loadingGroups.clear();
      _loadingTOs.clear();
      _activeGroupKey = null;
      _closedDisplayCount = _closedPageSize;
      _lastCachedItems = null;
    });
    final controller = context.read<WorkforceController>();
    await controller.reload(context);
    // [POSTING-V2-01B] refresh 실패는 기존 목록을 지우지 않으므로 화면만으로는
    // 알 수 없다. 마지막 성공 데이터를 계속 보여주되 실패 사실은 알린다.
    if (!mounted) return;
    if (controller.loadError != null && controller.items.isNotEmpty) {
      ToastHelper.showError('공고 목록을 새로고침하지 못했습니다');
    }
  }

  /// 탭·필터가 바뀌지 않으면 이전 결과를 그대로 반환 (H2)
  List<TOGroupItem> _getFilteredItems(List<TOGroupItem> allItems) {
    final controller = context.read<WorkforceController>();
    if (identical(allItems, _lastCachedItems) &&
        _selectedTab == _lastCachedTab &&
        controller.selectedBusinessId == _lastCachedBusinessId &&
        controller.selectedTOType == _lastCachedTOType &&
        controller.selectedPublishStatus == _lastCachedPublishStatus &&
        controller.selectedDateRange == _lastCachedDateRange) {
      return _cachedFilteredItems;
    }
    _lastCachedItems = allItems;
    _lastCachedTab = _selectedTab;
    _lastCachedBusinessId = controller.selectedBusinessId;
    _lastCachedTOType = controller.selectedTOType;
    _lastCachedPublishStatus = controller.selectedPublishStatus;
    _lastCachedDateRange = controller.selectedDateRange;
    _cachedFilteredItems = _computeFilteredItems(allItems, controller);
    return _cachedFilteredItems;
  }

  /// [POSTING-V2-02A.1] 탭을 제외한 필터 술어 — 목록 렌더와 탭 count의 단일 source.
  ///
  /// 탭 숫자가 "바로 아래 보이는 카드 수"를 말하려면 같은 조건을 써야 한다.
  /// 술어를 복제하면 다시 어긋나므로 여기 한 곳에만 둔다.
  /// [PATCH-IDENTITY] 사업장 필터는 businessId 기반 — 동명 사업장 충돌 방지.
  bool _matchesFilters(TOGroupItem groupItem, WorkforceController controller) {
    final selectedBusinessId = controller.selectedBusinessId;
    final selectedTOType = controller.selectedTOType;
    final selectedPublishStatus = controller.selectedPublishStatus;
    final selectedDateRange = controller.selectedDateRange;

    if (selectedBusinessId != null &&
        groupItem.businessId != selectedBusinessId) {
      return false;
    }

    if (selectedTOType != null &&
        groupItem.masterTO.type != selectedTOType) {
      return false;
    }

    if (selectedPublishStatus != null) {
      final to = groupItem.masterTO;
      switch (selectedPublishStatus) {
        case 'published':
          if (!to.isPublished) return false;
        case 'unpublished':
          if (to.isPublished || to.isPendingPublish) return false;
        case 'pending':
          if (!to.isPendingPublish) return false;
      }
    }

    if (selectedDateRange != null) {
      final filterStart = DateTime.utc(
        selectedDateRange.start.year,
        selectedDateRange.start.month,
        selectedDateRange.start.day,
      );
      final filterEnd = DateTime.utc(
        selectedDateRange.end.year,
        selectedDateRange.end.month,
        selectedDateRange.end.day,
        23, 59, 59,
      );

      if (groupItem.masterTO.isFlexType) {
        // flex TO: 슬롯별 날짜로 필터 (로드 순서: groupTOs → slotDates → masterTO.date)
        final slotDates = groupItem.groupTOs.isNotEmpty
            ? groupItem.groupTOs
                .map((t) => t.slot?.date)
                .whereType<DateTime>()
                .toList()
            : groupItem.slotDates;
        if (slotDates.isNotEmpty) {
          final hasMatch = slotDates.any((d) {
            final day = FormatHelper.toKstDate(d);
            return !day.isBefore(filterStart) && !day.isAfter(filterEnd);
          });
          if (!hasMatch) return false;
        } else {
          if (!_isDateInRange(groupItem.masterTO, filterStart, filterEnd)) {
            return false;
          }
        }
      } else {
        if (!_isDateInRange(groupItem.masterTO, filterStart, filterEnd)) {
          return false;
        }
      }
    }

    return true;
  }

  /// [POSTING-V2-02A.1] 진행중 탭에 실제 렌더되는 카드 수.
  ///
  /// quota가 아니다. 서버 생성 한도는 owner 전체 scope에서 ACTIVE+FULL을 세고
  /// DRAFT/SCHEDULED를 빼지만, 이 숫자는 오직 "이 탭에 몇 개가 보이는가"만 말한다.
  /// 두 모집단이 다르므로 하나의 숫자로 묶지 않는다.
  int _visibleActiveCount(WorkforceController controller) => controller.items
      .where((g) => !g.isClosed && _matchesFilters(g, controller))
      .length;

  /// controller.items 에서 탭·사업장·날짜 필터 적용
  List<TOGroupItem> _computeFilteredItems(List<TOGroupItem> allItems, WorkforceController controller) {
    final Iterable<TOGroupItem> source;
    if (_selectedTab == TOStatus.active) {
      source = allItems.where((g) => !g.isClosed);
    } else {
      source = allItems.where((g) => g.isClosed);
    }

    final filtered = source.where((g) => _matchesFilters(g, controller));

    if (_selectedTab != TOStatus.closed) return filtered.toList();

    // 마감됨 탭: closedAt 기준 최신순 정렬
    return filtered.toList()
      ..sort((a, b) {
        final aDate = a.masterTO.closedAt ??
            a.masterTO.statusUpdatedAt ??
            a.masterTO.date;
        final bDate = b.masterTO.closedAt ??
            b.masterTO.statusUpdatedAt ??
            b.masterTO.date;
        return bDate.compareTo(aDate);
      });
  }

  /// 날짜 범위 체크 (장기/단기 공고 모두 고려)
  bool _isDateInRange(TOModel to, DateTime filterStart, DateTime filterEnd) {
    if (!to.isLongTerm) {
      final toDate = FormatHelper.toKstDate(to.date);
      return !toDate.isBefore(filterStart) && !toDate.isAfter(filterEnd);
    }

    // contract TO 시작일 결정: 신규 preset → workStartAvailableFrom / custom·legacy → rangeStart
    final DateTime rawStart = to.hasWorkStartAvailableRange
        ? to.workStartAvailableFrom!
        : (to.rangeStart ?? to.date);
    // contract TO 종료일 결정: 신규 preset → workStartAvailableUntil / custom·legacy → endDate(=rangeEnd)
    final DateTime? rawEnd = to.hasWorkStartAvailableRange
        ? to.workStartAvailableUntil
        : to.endDate;

    final toStart = FormatHelper.toKstDate(rawStart);
    if (rawEnd == null) {
      // 종료일 미설정 (구 데이터): 시작일 단일점으로 체크
      return !toStart.isBefore(filterStart) && !toStart.isAfter(filterEnd);
    }
    final toEnd = FormatHelper.toKstDate(rawEnd);
    return !(filterEnd.isBefore(toStart) || filterStart.isAfter(toEnd));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WorkforceController>();
    return Column(
      children: [
        _buildTabBar(controller),
        Expanded(child: _buildTOList(controller)),
      ],
    );
  }

  Widget _buildTabBar(WorkforceController controller) {
    return Container(
      padding: ResponsiveHelper.symmetricPadding(context, horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 3)),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTab(controller, TOStatus.active, '진행중', Icons.play_circle_outline),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                  Expanded(
                    child: _buildTab(controller, TOStatus.closed, '마감됨', Icons.check_circle_outline),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(WorkforceController controller, String tab, String label, IconData icon) {
    final theme = Theme.of(context);
    final isSelected = _selectedTab == tab;
    final isActiveTab = tab == TOStatus.active;
    // [POSTING-V2-01B] ERROR != ZERO.
    // 조회 실패로 보여줄 데이터가 없을 때 '진행중 (0)'을 표시하면
    // 장애가 '진행중 공고 0건'으로 확정돼 보인다. 이 경우 count 자체를 숨긴다.
    // 마지막 성공 데이터가 남아 있으면 그 known count를 그대로 유지한다.
    final countIsTrustworthy =
        controller.loadError == null || controller.items.isNotEmpty;
    // [POSTING-V2-02A.1] 탭 숫자는 렌더되는 카드 수다 — quota가 아니다.
    // 이전에는 '(N/max)'로 목록 수와 생성 한도를 한 숫자에 묶었는데,
    // 서버 quota는 owner 전체 scope의 ACTIVE+FULL을 세고 DRAFT/SCHEDULED를 빼므로
    // 두 모집단이 애초에 다르다. 분모·isMaxed 경고 색을 모두 제거하고,
    // 한도는 실제로 작동하는 순간(생성·공개)에 서버가 안내한다.
    final activeCount =
        (isActiveTab && countIsTrustworthy) ? _visibleActiveCount(controller) : null;
    final displayLabel =
        activeCount != null ? '$label ($activeCount)' : label;

    return GestureDetector(
      onTap: () {
        if (_selectedTab != tab) {
          setState(() {
            _selectedTab = tab;
            _expandedGroups.clear();
            _expandedTOs.clear();
            _activeGroupKey = null;
            _closedDisplayCount = _closedPageSize;
          });
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 9),
        ),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // [POSTING-V2-02A.1] 탭 count는 정보이지 경고가 아니다.
            // 한도 도달 여부를 탭이 추정하던 error 색상(isMaxed)을 제거했다.
            Icon(
              icon,
              size: ResponsiveHelper.iconSize(context, 16),
              color: isSelected ? theme.primaryColor : AppColors.grey500,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 5)),
            Flexible(
              child: Text(
                displayLabel,
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? theme.primaryColor : AppColors.grey500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterDialog() {
    final controller = context.read<WorkforceController>();
    // [POSTING-V2-01B] 사업장 옵션은 controller.items에서 파생된다.
    // 목록 조회가 실패해 items가 비어 있으면 '사업장 0개'처럼 보이므로 열지 않는다.
    // (새 사업장 query를 추가하지 않는다 — 목록이 복구되면 옵션도 복구된다)
    if (controller.loadError != null && controller.items.isEmpty) {
      ToastHelper.showError('공고 목록을 불러온 뒤 필터를 사용할 수 있습니다');
      return;
    }
    // [PATCH-IDENTITY] key=businessId, value=businessName.
    // id로 필터링하고 name을 chip label로 표시.
    // 동명 사업장이 있어도 id가 다르면 별개 항목으로 유지됨.
    final businessOptions = <String, String>{
      for (final g in controller.items)
        if (g.businessId.isNotEmpty) g.businessId: g.businessName,
    };

    DialogHelper.showSheet(
      context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => FilterDialog(
        selectedBusinessId: controller.selectedBusinessId,
        selectedDateRange: controller.selectedDateRange,
        selectedTOType: controller.selectedTOType,
        selectedPublishStatus: controller.selectedPublishStatus,
        businessOptions: businessOptions,
        isUserMode: false,
        showTOTypeFilter: true,
        showPublishStatusFilter: true,
        onBusinessChanged: (v) { setState(() { _expandedGroups.clear(); _expandedTOs.clear(); _activeGroupKey = null; }); controller.setBusinessIdFilter(v); },
        onDateRangeChanged: (v) { setState(() { _expandedGroups.clear(); _expandedTOs.clear(); _activeGroupKey = null; }); controller.setDateRangeFilter(v); },
        onTOTypeChanged: (v) { setState(() { _expandedGroups.clear(); _expandedTOs.clear(); _activeGroupKey = null; }); controller.setTOTypeFilter(v); },
        onPublishStatusChanged: (v) { setState(() { _expandedGroups.clear(); _expandedTOs.clear(); _activeGroupKey = null; }); controller.setPublishStatusFilter(v); },
      ),
    );
  }

  Widget _buildTOList(WorkforceController controller) {

    if (controller.isLoading) {
      return const LoadingWidget(message: '공고 목록을 불러오는 중...');
    }

    // [POSTING-V2-01B] ERROR != EMPTY.
    // 조회 실패 + 보여줄 데이터 없음 → empty state가 아니라 error state.
    // 실패 상태에서 '새 공고를 등록하세요'를 권하면 장애 중에 잘못된 행동을 유도한다.
    // 마지막 성공 데이터가 남아 있으면 그것을 계속 보여준다(_reload의 토스트가 실패를 알림).
    if (controller.loadError != null && controller.items.isEmpty) {
      return _buildErrorState();
    }

    // [POSTING-V2-02E.1] 성공 조회 후의 0건은 원인이 셋이고 다음 행동도 다르다.
    //   공고 자체가 없음 / 필터가 걸러냄 / 이 탭에만 없음.
    //   items.isEmpty를 필터보다 먼저 본다 — 공고가 0개면 필터는 원인이 아니다.
    if (controller.items.isEmpty) {
      return _buildEmptyState(_PostingEmptyKind.root);
    }

    final allFilteredItems = _getFilteredItems(controller.items);

    if (allFilteredItems.isEmpty) {
      return _buildEmptyState(controller.hasActiveFilters
          ? _PostingEmptyKind.filtered
          : _PostingEmptyKind.tab);
    }

    // 마감됨 탭: 표시 개수 제한 (스크롤 시 추가 로드)
    final isClosedTab = _selectedTab == TOStatus.closed;
    final filteredItems = isClosedTab
        ? allFilteredItems.take(_closedDisplayCount).toList()
        : allFilteredItems;
    final hasMore = isClosedTab && _closedDisplayCount < allFilteredItems.length;

    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView.builder(
        controller: _scrollController,
        padding: ResponsiveHelper.listPadding(context),
        itemCount: filteredItems.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == filteredItems.length) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 16)),
              child: const LoadingWidget(),
            );
          }
          final groupItem = filteredItems[index];
          return RepaintBoundary(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: ResponsiveHelper.spacing(context, 10),
              ),
              child: TOGroupCard(
                groupItem: groupItem,
                firestoreService: _firestoreService,
                dialogs: _dialogs,
                onChanged: _reload,
                isExpanded: _expandedGroups.contains(groupItem.id),
                expandedTOs: _expandedTOs,
                onToggleExpand: () => _handleGroupExpand(groupItem),
                onToggleTOExpand: (toId) async {
                  if (groupItem.groupTOs.isEmpty) return;
                  final matches = groupItem.groupTOs
                      .where((item) => (item.slot?.id ?? item.to.id) == toId);
                  if (matches.isEmpty) return;
                  await _handleTOExpand(matches.first);
                },
                isGroupLoading: _loadingGroups.contains(groupItem.id),
                // [POSTING-V2-01B] 슬롯 조회 실패를 '슬롯 없음'으로 보이게 하지 않는다.
                // 범위는 이 카드까지 — root 전체를 ERROR로 올리지 않는다.
                hasGroupDetailError:
                    controller.hasGroupDetailError(groupItem.id),
                onRetryGroupDetail: () => _handleGroupDetailRetry(groupItem),
                loadingTOs: _loadingTOs,
                onAffectedTOsChanged: (_) => _reload(),
                isAnyExpanded: _expandedGroups.isNotEmpty || _activeGroupKey != null,
                activeGroupKey: _activeGroupKey,
                onGroupActivated: (groupId) => setState(() {
                  _activeGroupKey = groupId;
                  // Phase 4C.1+: expand/collapse는 onToggleExpand(_handleGroupExpand)에서 관리.
                  // 여기서 _expandedGroups를 clear하면 chip 탭 시 card가 collapse됨 (4D.1 회귀 수정).
                  _expandedTOs.clear();
                }),
                onGroupDeactivated: () { if (_activeGroupKey != null) setState(() => _activeGroupKey = null); },
                isLastCard: index == filteredItems.length - 1,
              ),
            ),
          );
        },
      ),
    );
  }

  /// [POSTING-V2-02E.1] 성공 조회 후의 빈 목록 — 세 의미를 한 renderer에서 분기.
  ///
  /// 이전에는 네 상황이 '조건에 맞는 공고가 없습니다 / 필터를 변경하거나 새로운
  /// 공고를 등록하세요' 하나로 수렴했다. 필터가 없는데 필터를 의심하게 만들고,
  /// 마감됨 탭에서는 실행해도 그 탭이 채워지지 않는 행동을 권했다.
  ///
  /// readiness는 보지 않는다 — '왜 공고를 만들 수 없는가'는 CreateTO 사전조건
  /// 화면과 Home 준비 카드가 canonical하게 갖는다. 여기서 다시 판단하면
  /// 같은 사실을 세 곳이 따로 계산하게 된다.
  Widget _buildEmptyState(_PostingEmptyKind kind) {
    final (String title, String subtitle) copy = switch (kind) {
      // 헤더 '+ 공고 등록'이 같은 화면에 이미 있다 — 본문에 중복 CTA를 두지 않는다.
      _PostingEmptyKind.root => (
          '등록된 공고가 없습니다',
          '상단 + 버튼에서 새 공고를 등록할 수 있습니다',
        ),
      _PostingEmptyKind.filtered => (
          '조건에 맞는 공고가 없습니다',
          '필터를 초기화하거나 조건을 변경해 보세요',
        ),
      // items가 있는데 이 탭만 0 → 반대 탭에 공고가 있다.
      // 탭 전환 버튼은 두지 않는다 — 탭 바가 바로 위에 있고 진행중은 수까지 보인다.
      _PostingEmptyKind.tab => _selectedTab == TOStatus.active
          ? (
              '진행중인 공고가 없습니다',
              '마감된 공고는 마감됨 탭에서 확인할 수 있습니다',
            )
          : (
              '마감된 공고가 없습니다',
              '진행 중인 공고는 진행중 탭에서 확인할 수 있습니다',
            ),
    };

    return AppEmptyState(
      icon: Icons.inbox_outlined,
      title: copy.$1,
      subtitle: copy.$2,
      // 유일하게 body action을 갖는 상태. 여기서 '공고 등록'을 권하면
      // 필터만 풀면 보이는 기존 공고를 놓치고 중복 공고를 만들게 된다.
      action: kind == _PostingEmptyKind.filtered
          ? TextButton.icon(
              onPressed: _clearFilters,
              icon: Icon(Icons.filter_alt_off_outlined,
                  size: ResponsiveHelper.iconSize(context, 16)),
              label: const Text('필터 초기화'),
            )
          : null,
    );
  }

  /// [POSTING-V2-02E.1] 필터 전체 해제 — 기존 목록을 그대로 다시 거른다.
  /// Firestore 재조회 없음. 확장 상태 초기화는 필터 변경 콜백과 같은 처리다.
  void _clearFilters() {
    setState(() {
      _expandedGroups.clear();
      _expandedTOs.clear();
      _activeGroupKey = null;
    });
    context.read<WorkforceController>().clearFilters();
  }

  /// [POSTING-V2-01B] 목록 조회 실패 — 공통 AppEmptyState를 error 톤으로 재사용한다.
  /// primary action은 '공고 등록'이 아니라 '다시 시도'다.
  Widget _buildErrorState() {
    return AppEmptyState(
      icon: Icons.cloud_off_rounded,
      iconColor: AppColors.grey400,
      title: '공고 목록을 불러오지 못했습니다',
      subtitle: '네트워크 상태를 확인한 뒤 다시 시도해주세요',
      action: TextButton.icon(
        onPressed: _reload,
        icon: Icon(Icons.refresh,
            size: ResponsiveHelper.iconSize(context, 16)),
        label: const Text('다시 시도'),
      ),
    );
  }

  /// 그룹 카드 펼침 핸들러
  Future<void> _handleGroupExpand(TOGroupItem groupItem) async {
    final key = groupItem.id;

    if (_expandedGroups.contains(key)) {
      setState(() {
        _expandedGroups.remove(key);
        _expandedTOs.clear();
        _activeGroupKey = null;
      });
      return;
    }

    // 먼저 expand → body 안 스피너가 즉시 표시됨
    setState(() {
      _expandedGroups.clear();
      _expandedTOs.clear();
      _expandedGroups.add(key);
      _activeGroupKey = key;
    });

    final controller = context.read<WorkforceController>();

    if (groupItem.masterTO.isFlexType) {
      // Flex TO: 슬롯 미로드 시에만 로드
      if (!groupItem.isGroupDetailLoaded) {
        setState(() => _loadingGroups.add(key));
        try {
          await controller.loadGroupDetails(context, groupItem);
        } catch (e) {
          debugPrint('❌ 그룹 상세 로드 실패: $e');
          if (mounted) ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
        } finally {
          if (mounted) setState(() => _loadingGroups.remove(key));
        }
      }
      // 단일 슬롯 flex TO: 업무 상세 통계도 로드 (다중 슬롯은 TOItemCard 개별 확장 시 로드)
      if (!mounted) return;
      if (groupItem.groupTOs.length == 1 &&
          groupItem.groupTOs.first.needsWorkDetailLoad) {
        await controller.loadWorkDetails(groupItem.groupTOs.first);
      }
    } else if (!groupItem.isWorkDetailLoaded) {
      // 단건 TO: 업무별 통계 lazy load
      setState(() => _loadingTOs.add(key));
      try {
        final result =
            await _firestoreService.loadTOWorkDetails(groupItem.masterTO);
        final workStats = result['workStats'] as Map<String, Map<String, int>>?;
        if (workStats != null) {
          groupItem.setWorkDetailStats(
            workStats,
            // [POSTING-V2-01B] 통계 조회 실패를 0으로 표시하지 않도록 전달
            statsFailed: result['statsFailed'] == true,
          );
        } else {
          groupItem.markWorkDetailStatsFailed();
        }
      } catch (e) {
        debugPrint('❌ 그룹 상세 로드 실패: $e');
        // [POSTING-V2-01B] 실패를 '확정 0 / 대기 0'으로 남기지 않는다
        groupItem.markWorkDetailStatsFailed();
        if (mounted) ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
      } finally {
        if (mounted) setState(() => _loadingTOs.remove(key));
      }
    }
  }

  /// [POSTING-V2-01B] 슬롯/상세 조회 재시도 — 기존 canonical load 경로를 그대로 쓴다.
  /// 신규 API를 만들지 않는다.
  Future<void> _handleGroupDetailRetry(TOGroupItem groupItem) async {
    final key = groupItem.id;
    final controller = context.read<WorkforceController>();
    setState(() => _loadingGroups.add(key));
    try {
      await controller.loadGroupDetails(context, groupItem);
    } finally {
      if (mounted) setState(() => _loadingGroups.remove(key));
    }
    if (!mounted) return;
    // 단일 슬롯 flex TO: 업무 상세 통계도 함께 복구
    if (groupItem.groupTOs.length == 1 &&
        groupItem.groupTOs.first.needsWorkDetailLoad) {
      await controller.loadWorkDetails(groupItem.groupTOs.first);
    }
  }

  /// TO 카드 펼침 핸들러
  Future<void> _handleTOExpand(TOItem toItem) async {
    final key = toItem.slot?.id ?? toItem.to.id;

    if (_expandedTOs.contains(key)) {
      setState(() => _expandedTOs.remove(key));
      return;
    }

    setState(() {
      _expandedTOs.clear();
      _expandedTOs.add(key);
      if (toItem.needsWorkDetailLoad) _loadingTOs.add(key);
    });

    if (toItem.needsWorkDetailLoad) {
      try {
        await context.read<WorkforceController>().loadWorkDetails(toItem);
      } catch (e) {
        debugPrint('❌ 업무 상세 로드 실패: $e');
        if (mounted) ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
      } finally {
        if (mounted) setState(() => _loadingTOs.remove(key));
      }
    }
  }
}
