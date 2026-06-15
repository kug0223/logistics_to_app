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
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';

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

  // 필터 상태
  DateTimeRange? _selectedDateRange;
  String? _selectedBusiness;
  String? _selectedTOType;        // null / 'flex' / 'contract'
  String? _selectedPublishStatus; // null / 'published' / 'unpublished' / 'pending'

  // 탭 상태
  String _selectedTab = TOStatus.active;

  // 이중 토글 상태 관리
  final Set<String> _expandedGroups = {};
  final Set<String> _expandedTOs = {};

  // Lazy Loading 로컬 스피너 상태
  final Set<String> _loadingGroups = {};
  final Set<String> _loadingTOs = {};

  // 마감됨 탭 페이지네이션
  static const int _closedPageSize = 5;
  int _closedDisplayCount = _closedPageSize;
  final ScrollController _scrollController = ScrollController();

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
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_selectedTab != TOStatus.closed) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 150) {
      final controller = context.read<WorkforceController>();
      final total = _getFilteredItems(controller.items).length;
      if (_closedDisplayCount < total) {
        setState(() => _closedDisplayCount =
            (_closedDisplayCount + _closedPageSize).clamp(0, total));
      }
    }
  }

  void _reload() {
    setState(() {
      _expandedGroups.clear();
      _expandedTOs.clear();
    });
    context.read<WorkforceController>().reload(context);
  }

  /// controller.items 에서 탭·사업장·날짜 필터 적용
  List<TOGroupItem> _getFilteredItems(List<TOGroupItem> allItems) {
    final Iterable<TOGroupItem> source;
    if (_selectedTab == TOStatus.active) {
      source = allItems.where((g) => !g.isClosed);
    } else {
      source = allItems.where((g) => g.isClosed);
    }

    final filtered = source.where((groupItem) {
      if (_selectedBusiness != null &&
          groupItem.businessName != _selectedBusiness) {
        return false;
      }

      if (_selectedTOType != null &&
          groupItem.masterTO.type != _selectedTOType) {
        return false;
      }

      if (_selectedPublishStatus != null) {
        final to = groupItem.masterTO;
        switch (_selectedPublishStatus) {
          case 'published':
            if (!to.isPublished) return false;
          case 'unpublished':
            if (to.isPublished || to.isPendingPublish) return false;
          case 'pending':
            if (!to.isPendingPublish) return false;
        }
      }

      if (_selectedDateRange != null) {
        final filterStart = DateTime(
          _selectedDateRange!.start.year,
          _selectedDateRange!.start.month,
          _selectedDateRange!.start.day,
        );
        final filterEnd = DateTime(
          _selectedDateRange!.end.year,
          _selectedDateRange!.end.month,
          _selectedDateRange!.end.day,
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
              final day = DateTime(d.year, d.month, d.day);
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
      final toDate = DateTime(to.date.year, to.date.month, to.date.day);
      return !toDate.isBefore(filterStart) && !toDate.isAfter(filterEnd);
    }

    if (to.endDate == null) {
      final toDate = DateTime(to.date.year, to.date.month, to.date.day);
      return !toDate.isBefore(filterStart) && !toDate.isAfter(filterEnd);
    }

    final toStart = DateTime(to.date.year, to.date.month, to.date.day);
    final toEnd = DateTime(
      to.endDate!.year,
      to.endDate!.month,
      to.endDate!.day,
    );
    return !(filterEnd.isBefore(toStart) || filterStart.isAfter(toEnd));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTabBar(),
        Expanded(child: _buildTOList()),
      ],
    );
  }

  Widget _buildTabBar() {
    final theme = Theme.of(context);

    return Container(
      padding: ResponsiveHelper.symmetricPadding(context, horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.primaryColor.withValues(alpha: 0.08),
                    theme.primaryColor.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.primaryColor.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTab(TOStatus.active, '진행중', Icons.play_circle_outline),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  Expanded(
                    child: _buildTab(TOStatus.closed, '마감됨', Icons.check_circle_outline),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          _buildFilterButton(),
        ],
      ),
    );
  }

  Widget _buildTab(String tab, String label, IconData icon) {
    final theme = Theme.of(context);
    final isSelected = _selectedTab == tab;

    return GestureDetector(
      onTap: () {
        if (_selectedTab != tab) {
          setState(() {
            _selectedTab = tab;
            _expandedGroups.clear();
            _expandedTOs.clear();
            _closedDisplayCount = _closedPageSize;
          });
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 9),
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.primaryColor,
                    theme.primaryColor.withValues(alpha: 0.85),
                  ],
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: ResponsiveHelper.iconSize(context, 18),
              color: isSelected
                  ? Colors.white
                  : theme.primaryColor.withValues(alpha: 0.7),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(
              label,
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? Colors.white
                    : theme.primaryColor.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterButton() {
    final theme = Theme.of(context);
    final hasFilters = _hasActiveFilters();

    return Material(
      color: hasFilters
          ? theme.primaryColor.withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _showFilterDialog,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.filter_list,
                color: hasFilters ? theme.primaryColor : AppColors.grey600,
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              if (hasFilters)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding:
                        EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.primaryColor,
                          theme.primaryColor.withValues(alpha: 0.8),
                        ],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: theme.primaryColor.withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    constraints: BoxConstraints(
                      minWidth: ResponsiveHelper.spacing(context, 18),
                      minHeight: ResponsiveHelper.spacing(context, 18),
                    ),
                    child: Center(
                      child: Text(
                        '${_getActiveFilterCount()}',
                        style: ResponsiveHelper.tinyStyle(
                          context,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasActiveFilters() =>
      _selectedBusiness != null ||
      _selectedDateRange != null ||
      _selectedTOType != null ||
      _selectedPublishStatus != null;

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedBusiness != null) count++;
    if (_selectedDateRange != null) count++;
    if (_selectedTOType != null) count++;
    if (_selectedPublishStatus != null) count++;
    return count;
  }

  void _showFilterDialog() {
    final allItems = context.read<WorkforceController>().items;
    final businessNames = allItems
        .map((g) => g.businessName)
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => FilterDialog(
        selectedBusiness: _selectedBusiness,
        selectedDateRange: _selectedDateRange,
        selectedTOType: _selectedTOType,
        selectedPublishStatus: _selectedPublishStatus,
        businessNames: businessNames,
        isUserMode: false,
        showTOTypeFilter: true,
        showPublishStatusFilter: true,
        onBusinessChanged: (value) => setState(() => _selectedBusiness = value),
        onDateRangeChanged: (value) => setState(() => _selectedDateRange = value),
        onTOTypeChanged: (value) => setState(() => _selectedTOType = value),
        onPublishStatusChanged: (value) => setState(() => _selectedPublishStatus = value),
      ),
    );
  }

  Widget _buildTOList() {
    final controller = context.watch<WorkforceController>();

    if (controller.isLoading) {
      return const LoadingWidget(message: 'TO 목록을 불러오는 중...');
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
        padding: ResponsiveHelper.cardPadding(context),
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
                isAnyExpanded: _expandedGroups.isNotEmpty,
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
      });
      return;
    }

    // 먼저 expand → body 안 스피너가 즉시 표시됨
    setState(() {
      _expandedGroups.clear();
      _expandedTOs.clear();
      _expandedGroups.add(key);
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
        } finally {
          if (mounted) setState(() => _loadingGroups.remove(key));
        }
      }
    } else if (!groupItem.isWorkDetailLoaded) {
      // 단건 TO: 업무별 통계 lazy load
      setState(() => _loadingTOs.add(key));
      try {
        final result =
            await _firestoreService.loadTOWorkDetails(groupItem.masterTO);
        groupItem.setWorkDetailStats(
          result['workStats'] as Map<String, Map<String, int>>,
        );
      } catch (e) {
        debugPrint('❌ 그룹 상세 로드 실패: $e');
        ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
      }
      if (!mounted) return;
      setState(() => _loadingTOs.remove(key));
    }
  }

  /// TO 카드 펼침 핸들러
  Future<void> _handleTOExpand(TOItem toItem) async {
    final key = toItem.slot?.id ?? toItem.to.id;

    if (_expandedTOs.contains(key)) {
      setState(() => _expandedTOs.remove(key));
      return;
    }

    // 먼저 expand → body 안 스피너가 즉시 표시됨
    setState(() {
      _expandedTOs.clear();
      _expandedTOs.add(key);
    });

    if (toItem.needsWorkDetailLoad) {
      setState(() => _loadingTOs.add(key));
      try {
        await context.read<WorkforceController>().loadWorkDetails(toItem);
      } catch (e) {
        debugPrint('❌ 업무 상세 로드 실패: $e');
      } finally {
        if (mounted) setState(() => _loadingTOs.remove(key));
      }
    }
  }
}
