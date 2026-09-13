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

  /// controller.items 에서 탭·사업장·날짜 필터 적용
  /// [PATCH-IDENTITY] 사업장 필터는 businessId 기반 — 동명 사업장 충돌 방지.
  List<TOGroupItem> _computeFilteredItems(List<TOGroupItem> allItems, WorkforceController controller) {
    final selectedBusinessId = controller.selectedBusinessId;
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
    // [POSTING-V2-01B] ERROR != ZERO.
    // 조회 실패로 보여줄 데이터가 없을 때 '진행중 (0/N)'을 표시하면
    // 장애가 '진행중 공고 0건'으로 확정돼 보인다. 이 경우 count 자체를 숨긴다.
    // 마지막 성공 데이터가 남아 있으면 그 known count를 그대로 유지한다.
    final countIsTrustworthy =
        controller.loadError == null || controller.items.isNotEmpty;
    final activeCount =
        (isActiveTab && countIsTrustworthy) ? controller.activeToCount : null;
    final isMaxed = isActiveTab && (activeCount ?? 0) >= controller.maxActiveTOs;
    // 분모(/N) 표시 여부는 "현재 scope가 단일 사업장인가"로 판단 (item 기반 추론 금지).
    // canonical source: UserProvider.managedBusinessIds.length (jobs_root_screen._computeScopeLabel 동일 기준)
    //   - SubAdmin → effectiveBusinessId 고정 → 단일 → 분모 표시
    //   - managedBusinessIds.length == 1 → 단일 → 분모 표시
    //   - managedBusinessIds.length >= 2 + no business filter → 멀티 전체 scope → 분모 숨김
    //   - managedBusinessIds.length >= 2 + business filter 선택 → 단일 필터 → 분모 표시
    final up = context.read<UserProvider>();
    final isBusinessFiltered = controller.selectedBusinessId != null;
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

  Widget _buildEmptyState() {
    return const AppEmptyState(
      icon: Icons.inbox_outlined,
      title: '조건에 맞는 공고가 없습니다',
      subtitle: '필터를 변경하거나 새로운 공고를 등록하세요',
    );
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
