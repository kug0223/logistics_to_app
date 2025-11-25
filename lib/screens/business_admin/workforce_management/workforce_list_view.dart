import 'package:flutter/material.dart';

// Models
import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';

// Services
import '../../../services/firestore_service.dart';

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

/// 인력 관리 - 리스트 뷰 (business_admin_home_screen 스타일 통일)
class WorkforceListView extends StatefulWidget {
  const WorkforceListView({super.key});

  @override
  State<WorkforceListView> createState() => _WorkforceListViewState();
}

class _WorkforceListViewState extends State<WorkforceListView> {
  final FirestoreService _firestoreService = FirestoreService();
  late TOListDialogs _dialogs;
  
  @override
  void initState() {
    super.initState();
    _dialogs = TOListDialogs(
      context: context,
      firestoreService: _firestoreService,
      onChanged: _loadTOsWithStats,
    );
    _loadTOsWithStats();
  }
  
  // 필터 상태
  DateTimeRange? _selectedDateRange;
  String? _selectedBusiness;
  
  // TO 목록 + 통계
  List<TOGroupItem> _allGroupItems = [];
  List<TOGroupItem> _filteredGroupItems = [];
  bool _isLoading = true;
  
  // 탭 상태
  String _selectedTab = 'ACTIVE'; // 'ACTIVE' or 'CLOSED'

  // 사업장 목록
  List<String> _businessNames = [];
  
  // 이중 토글 상태 관리
  final Set<String> _expandedGroups = {};
  final Set<String> _expandedTOs = {};

  /// TO 목록 + 지원자 통계 로드
  Future<void> _loadTOsWithStats() async {
    setState(() => _isLoading = true);

    try {
      List<TOModel> masterTOs;
      if (_selectedTab == 'ACTIVE') {
        masterTOs = await _firestoreService.getActiveTOs();
      } else {
        masterTOs = await _firestoreService.getClosedTOs();
      }

      List<TOGroupItem> groupItems = [];
      
      for (var masterTO in masterTOs) {
        if (masterTO.isGrouped && masterTO.groupId != null) {
          final groupTOs = await _firestoreService.getTOsByGroup(masterTO.groupId!);
          final toIds = groupTOs.map((to) => to.id).toList();
          
          final batchResults = await Future.wait([
            _firestoreService.getWorkDetailsBatch(toIds, forceRefresh: true),
            _firestoreService.calculateGroupTimeRange(masterTO.groupId!, forceRefresh: true),
          ]);
          
          final workDetailsMap = batchResults[0] as Map<String, List<WorkDetailModel>>;
          final timeRange = batchResults[1] as Map<String, String>;
          final applicationsMap = await _firestoreService.getApplicationsByTOIds(toIds);

          List<TOItem> toItems = [];
          for (var to in groupTOs) {
            final toWorkDetails = workDetailsMap[to.id] ?? [];
            final apps = applicationsMap[to.id] ?? [];

            int confirmed = apps.where((a) => a.status == 'CONFIRMED').length;
            int pending = apps.where((a) => a.status == 'PENDING').length;
            
            int totalRequired = 0;
            for (var work in toWorkDetails) {
              totalRequired += work.requiredCount;
            }
            
            Map<String, Map<String, int>> workStats = {};
            for (var work in toWorkDetails) {
              final workApps = apps.where((a) => a.selectedWorkType == work.workType);
              workStats[work.workType] = {
                'confirmed': workApps.where((a) => a.status == 'CONFIRMED').length,
                'pending': workApps.where((a) => a.status == 'PENDING').length,
              };
            }

            toItems.add(TOItem(
              to: to,
              workDetails: toWorkDetails,
              confirmedCount: confirmed,
              pendingCount: pending,
              totalRequired: totalRequired,
              workDetailStats: workStats,
            ));
          }
          
          masterTO.setTimeRange(timeRange['minStart']!, timeRange['maxEnd']!);
          
          groupItems.add(TOGroupItem(
            masterTO: masterTO,
            groupTOs: toItems,
            isGrouped: true,
          ));
          
        } else {
          final workDetails = await _firestoreService.getWorkDetails(
            masterTO.id,
            forceRefresh: true
          );
          
          if (workDetails.isNotEmpty) {
            String? minStart;
            String? maxEnd;
            
            for (var work in workDetails) {
              if (minStart == null || work.startTime.compareTo(minStart) < 0) {
                minStart = work.startTime;
              }
              if (maxEnd == null || work.endTime.compareTo(maxEnd) > 0) {
                maxEnd = work.endTime;
              }
            }
            
            if (minStart != null && maxEnd != null) {
              masterTO.setTimeRange(minStart, maxEnd);
            }
          }
          
          final apps = await _firestoreService.getApplicationsByTO(
            masterTO.businessId,
            masterTO.title,
            masterTO.date,
          );
          
          Map<String, Map<String, int>> workStats = {};
          for (var work in workDetails) {
            final workApps = apps.where((a) => a.selectedWorkType == work.workType);            
            workStats[work.workType] = {
              'confirmed': workApps.where((a) => a.status == 'CONFIRMED').length,
              'pending': workApps.where((a) => a.status == 'PENDING').length,
            };
          }
          
          int totalConfirmed = 0;
          int totalPending = 0;
          for (var stats in workStats.values) {
            totalConfirmed += stats['confirmed'] as int;
            totalPending += stats['pending'] as int;
          }
          
          int totalRequired = 0;
          for (var work in workDetails) {
            totalRequired += work.requiredCount;
          }
          
          groupItems.add(TOGroupItem(
            masterTO: masterTO.copyWith(totalRequired: totalRequired),
            groupTOs: [
              TOItem(
                to: masterTO.copyWith(totalRequired: totalRequired),
                workDetails: workDetails,
                confirmedCount: totalConfirmed,
                pendingCount: totalPending,
                totalRequired: totalRequired,
                workDetailStats: workStats,
              ),
            ],
            isGrouped: false,
          ));
        }
      }

      final businessSet = masterTOs.map((to) => to.businessName).toSet();
      final businessList = businessSet.toList()..sort();

      setState(() {
        _allGroupItems = groupItems;
        _businessNames = businessList;
        _isLoading = false;
      });
      
      _applyFilters();
    } catch (e) {
      print('❌ TO 목록 로드 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('TO 목록을 불러오는데 실패했습니다.');
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredGroupItems = _allGroupItems.where((groupItem) {
        // 1. 사업장 필터
        if (_selectedBusiness != null && 
            groupItem.masterTO.businessName != _selectedBusiness) {
          return false;
        }
        
        // 2. 날짜 필터
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
          
          // 그룹 TO인 경우
          if (groupItem.isGrouped) {
            final hasMatchingDate = groupItem.groupTOs.any((toItem) {
              return _isDateInRange(toItem.to, filterStart, filterEnd);
            });
            
            if (!hasMatchingDate) return false;
          } 
          // 단일 TO인 경우
          else {
            if (!_isDateInRange(groupItem.masterTO, filterStart, filterEnd)) {
              return false;
            }
          }
        }
        
        return true;
      }).toList();
    });
  }

  /// ⭐ 날짜 범위 체크 (장기/단기 공고 모두 고려)
  bool _isDateInRange(TOModel to, DateTime filterStart, DateTime filterEnd) {
    // 단기 공고
    if (!to.isLongTerm) {
      final toDate = DateTime(
        to.date.year,
        to.date.month,
        to.date.day,
      );
      
      return toDate.isAfter(filterStart.subtract(const Duration(days: 1))) &&
            toDate.isBefore(filterEnd.add(const Duration(days: 1)));
    }
    
    // 장기 공고
    if (to.endDate == null) {
      // endDate가 없으면 date만 체크
      final toDate = DateTime(
        to.date.year,
        to.date.month,
        to.date.day,
      );
      
      return toDate.isAfter(filterStart.subtract(const Duration(days: 1))) &&
            toDate.isBefore(filterEnd.add(const Duration(days: 1)));
    }
    
    // 장기 공고 기간 체크
    final toStart = DateTime(
      to.date.year,
      to.date.month,
      to.date.day,
    );
    
    final toEnd = DateTime(
      to.endDate!.year,
      to.endDate!.month,
      to.endDate!.day,
    );
    
    // 필터 범위와 TO 기간이 겹치는지 확인
    // 겹치지 않는 경우: filterEnd < toStart OR filterStart > toEnd
    // 겹치는 경우: 위의 반대
    return !(filterEnd.isBefore(toStart) || filterStart.isAfter(toEnd));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTabBar(),
        // ⭐ 마감됨 탭 안내 메시지
        if (_selectedTab == 'CLOSED')
          _buildClosedTabNotice(),
        Expanded(child: _buildTOList()),
      ],
    );
  }

  /// ✨ 마감됨 탭 안내 메시지 - 테마 기반
  Widget _buildClosedTabNotice() {
    final theme = Theme.of(context);
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor.withOpacity(0.1),
            theme.primaryColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.primaryColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.info_outline,
              color: theme.primaryColor,
              size: ResponsiveHelper.iconSize(context, 20),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Text(
              '최근 마감된 5개만 표시됩니다. 이전 마감은 캘린더를 이용하세요.',
              style: ResponsiveHelper.smallStyle(
                context,
                color: theme.primaryColor.withOpacity(0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 탭바 + 필터 (business_admin_home_screen 스타일)
  Widget _buildTabBar() {
    final theme = Theme.of(context);
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
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
                    theme.primaryColor.withOpacity(0.08),
                    theme.primaryColor.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.primaryColor.withOpacity(0.2),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(child: _buildTab('ACTIVE', '진행중', Icons.play_circle_outline)),
                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  Expanded(child: _buildTab('CLOSED', '마감됨', Icons.check_circle_outline)),
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

  /// ✨ 탭 버튼 - 그라데이션 스타일
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
          });
          _loadTOsWithStats();
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 12),
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.primaryColor,
                    theme.primaryColor.withOpacity(0.85),
                  ],
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.primaryColor.withOpacity(0.4),
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
              color: isSelected ? Colors.white : theme.primaryColor.withOpacity(0.7),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(
              label,
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : theme.primaryColor.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ✨ 필터 버튼 - 세련된 배지
  Widget _buildFilterButton() {
    final theme = Theme.of(context);
    final hasFilters = _hasActiveFilters();
    
    return Material(
      color: hasFilters
          ? theme.primaryColor.withOpacity(0.1)
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
                color: hasFilters ? theme.primaryColor : Colors.grey[600],
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              if (hasFilters)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.primaryColor,
                          theme.primaryColor.withOpacity(0.8),
                        ],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.primaryColor.withOpacity(0.4),
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

  bool _hasActiveFilters() {
    return _selectedBusiness != null || _selectedDateRange != null;
  }

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedBusiness != null) count++;
    if (_selectedDateRange != null) count++;
    return count;
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => FilterDialog(
        selectedBusiness: _selectedBusiness,
        selectedDateRange: _selectedDateRange,
        businessNames: _businessNames,
        isUserMode: true,
        onBusinessChanged: (value) {
          setState(() => _selectedBusiness = value);
          _applyFilters();
        },
        onDateRangeChanged: (value) {
          setState(() => _selectedDateRange = value);
          _applyFilters();
        },
      ),
    );
  }

  /// ✨ TO 목록
  Widget _buildTOList() {
    if (_isLoading) {
      return const LoadingWidget(message: 'TO 목록을 불러오는 중...');
    }

    if (_filteredGroupItems.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadTOsWithStats,
      child: ListView.builder(
        padding: ResponsiveHelper.cardPadding(context),
        itemCount: _filteredGroupItems.length,
        itemBuilder: (context, index) {
          final groupItem = _filteredGroupItems[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: ResponsiveHelper.spacing(context, 16),
            ),
            child: TOGroupCard(
              groupItem: groupItem,
              firestoreService: _firestoreService,
              dialogs: _dialogs,
              allGroupItems: _allGroupItems,
              onChanged: _loadTOsWithStats,
              isExpanded: _expandedGroups.contains(
                groupItem.masterTO.groupId ?? groupItem.masterTO.id
              ),
              expandedTOs: _expandedTOs,
              onToggleExpand: () => _handleGroupToggle(groupItem),
              onToggleTOExpand: _handleTOToggle,
            ),
          );
        },
      ),
    );
  }

  /// ✨ 빈 상태 - 세련된 디자인
  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    
    return Center(
      child: Container(
        margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 40)),
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 40)),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.primaryColor.withOpacity(0.08),
              theme.primaryColor.withOpacity(0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.primaryColor.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inbox_outlined,
                size: ResponsiveHelper.iconSize(context, 64),
                color: theme.primaryColor.withOpacity(0.4),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 24)),
            Text(
              '조건에 맞는 TO가 없습니다',
              style: ResponsiveHelper.titleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: theme.primaryColor.withOpacity(0.8),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text(
              '필터를 변경하거나 새로운 TO를 생성하세요',
              style: ResponsiveHelper.bodyStyle(
                context,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 그룹 토글 핸들러
  void _handleGroupToggle(TOGroupItem groupItem) {
    setState(() {
      final key = groupItem.masterTO.groupId ?? groupItem.masterTO.id;
      if (_expandedGroups.contains(key)) {
        _expandedGroups.remove(key);
        _expandedTOs.clear();
      } else {
        _expandedGroups.clear();
        _expandedTOs.clear();
        _expandedGroups.add(key);
      }
    });
  }

  /// TO 토글 핸들러
  void _handleTOToggle(String toId) {
    setState(() {
      if (_expandedTOs.contains(toId)) {
        _expandedTOs.remove(toId);
      } else {
        _expandedTOs.clear();
        _expandedTOs.add(toId);
      }
    });
  }
}