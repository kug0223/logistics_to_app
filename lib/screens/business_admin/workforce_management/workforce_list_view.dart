import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Models
import '../../../models/core/to_model.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';

// Services
import '../../../services/firestore_service.dart';

// Controllers
import '../../../controllers/workforce_controller.dart';

// Providers
import '../../../providers/user_provider.dart';

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
  String? _lastCachedBusiness;
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
    await context.read<WorkforceController>().reload(context);
  }

  /// 탭·필터가 바뀌지 않으면 이전 결과를 그대로 반환 (H2)
  List<TOGroupItem> _getFilteredItems(List<TOGroupItem> allItems) {
    final controller = context.read<WorkforceController>();
    if (identical(allItems, _lastCachedItems) &&
        _selectedTab == _lastCachedTab &&
        controller.selectedBusiness == _lastCachedBusiness &&
        controller.selectedTOType == _lastCachedTOType &&
        controller.selectedPublishStatus == _lastCachedPublishStatus &&
        controller.selectedDateRange == _lastCachedDateRange) {
      return _cachedFilteredItems;
    }
    _lastCachedItems = allItems;
    _lastCachedTab = _selectedTab;
    _lastCachedBusiness = controller.selectedBusiness;
    _lastCachedTOType = controller.selectedTOType;
    _lastCachedPublishStatus = controller.selectedPublishStatus;
    _lastCachedDateRange = controller.selectedDateRange;
    _cachedFilteredItems = _computeFilteredItems(allItems, controller);
    return _cachedFilteredItems;
  }

  /// controller.items 에서 탭·사업장·날짜 필터 적용
  List<TOGroupItem> _computeFilteredItems(List<TOGroupItem> allItems, WorkforceController controller) {
    final selectedBusiness = controller.selectedBusiness;
    final selectedTOType = controller.selectedTOType;
    final selectedPublishStatus = controller.selectedPublishStatus;
    final selectedDateRange = controller.selectedDateRange;

    final Iterable<TOGroupItem> source;
    if (_selectedTab == TOStatus.active) {
      source = allItems.where((g) => !g.isClosed);
    } else {
      source = allItems.where((g) => g.isClosed);
    }

    final filtered = source.where((groupItem) {
      if (selectedBusiness != null &&
          groupItem.businessName != selectedBusiness) {
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
    });

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
    final activeCount = isActiveTab ? controller.activeToCount : null;
    final isMaxed = isActiveTab && (activeCount ?? 0) >= controller.maxActiveTOs;
    // 분모(/N) 표시 여부는 "현재 scope가 단일 사업장인가"로 판단 (item 기반 추론 금지).
    // canonical source: UserProvider.managedBusinessIds.length (jobs_root_screen._computeScopeLabel 동일 기준)
    //   - SubAdmin → effectiveBusinessId 고정 → 단일 → 분모 표시
    //   - managedBusinessIds.length == 1 → 단일 → 분모 표시
    //   - managedBusinessIds.length >= 2 + no business filter → 멀티 전체 scope → 분모 숨김
    //   - managedBusinessIds.length >= 2 + business filter 선택 → 단일 필터 → 분모 표시
    final up = context.read<UserProvider>();
    final isBusinessFiltered = controller.selectedBusiness != null;
    final managedCount = up.currentUser?.managedBusinessIds.length ?? 1;
    final showDenominator = up.isSubAdmin || managedCount <= 1 || isBusinessFiltered;
    final displayLabel = isActiveTab && activeCount != null
        ? showDenominator
            ? '$label ($activeCount/${controller.maxActiveTOs})'
            : '$label ($activeCount)'
        : label;

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
            Icon(
              icon,
              size: ResponsiveHelper.iconSize(context, 16),
              color: isSelected
                  ? (isMaxed ? AppColors.error : theme.primaryColor)
                  : AppColors.grey500,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 5)),
            Flexible(
              child: Text(
                displayLabel,
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? (isMaxed ? AppColors.error : theme.primaryColor)
                      : AppColors.grey500,
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
    final businessNames = controller.items
        .map((g) => g.businessName)
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    DialogHelper.showSheet(
      context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => FilterDialog(
        selectedBusiness: controller.selectedBusiness,
        selectedDateRange: controller.selectedDateRange,
        selectedTOType: controller.selectedTOType,
        selectedPublishStatus: controller.selectedPublishStatus,
        businessNames: businessNames,
        isUserMode: false,
        showTOTypeFilter: true,
        showPublishStatusFilter: true,
        onBusinessChanged: (v) { setState(() { _expandedGroups.clear(); _expandedTOs.clear(); _activeGroupKey = null; }); controller.setBusinessFilter(v); },
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

    final allFilteredItems = _getFilteredItems(controller.items);

    if (allFilteredItems.isEmpty) {
      return _buildEmptyState();
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

  Widget _buildEmptyState() {
    return const AppEmptyState(
      icon: Icons.inbox_outlined,
      title: '조건에 맞는 TO가 없습니다',
      subtitle: '필터를 변경하거나 새로운 TO를 생성하세요',
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
          groupItem.setWorkDetailStats(workStats);
        }
      } catch (e) {
        debugPrint('❌ 그룹 상세 로드 실패: $e');
        if (mounted) ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
      } finally {
        if (mounted) setState(() => _loadingTOs.remove(key));
      }
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
