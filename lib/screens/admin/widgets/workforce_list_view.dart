import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Models
import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/toast_helper.dart';

// Widgets
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/inputs/filter_dialog.dart';

// Dialogs
import '../dialogs/to_list_dialogs.dart';

// Local Widgets
import '../../../widgets/cards/admin_to_group_card.dart';

/// 인력 관리 - 리스트 뷰 (리팩토링 완료)
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
        if (_selectedBusiness != null && 
            groupItem.masterTO.businessName != _selectedBusiness) {
          return false;
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
          
          if (groupItem.isGrouped) {
            final hasMatchingDate = groupItem.groupTOs.any((toItem) {
              final toDate = DateTime(
                toItem.to.date.year,
                toItem.to.date.month,
                toItem.to.date.day,
              );
              return toDate.isAfter(filterStart.subtract(const Duration(days: 1))) &&
                    toDate.isBefore(filterEnd.add(const Duration(days: 1)));
            });
            
            if (!hasMatchingDate) return false;
          } else {
            final toDate = DateTime(
              groupItem.masterTO.date.year,
              groupItem.masterTO.date.month,
              groupItem.masterTO.date.day,
            );
            
            if (!(toDate.isAfter(filterStart.subtract(const Duration(days: 1))) &&
                  toDate.isBefore(filterEnd.add(const Duration(days: 1))))) {
              return false;
            }
          }
        }
        
        return true;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTabBar(),
        // ⭐ 마감됨 탭 안내 메시지
          if (_selectedTab == 'CLOSED')
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '최근 마감된 5개만 표시됩니다. 이전 마감은 캘린더를 이용하세요.',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        Expanded(child: _buildTOList()),
      ],
    );
  }

  /// 탭바 + 필터
  Widget _buildTabBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(child: _buildTab('ACTIVE', '진행중')),
                  Expanded(child: _buildTab('CLOSED', '마감됨')),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildFilterButton(),
        ],
      ),
    );
  }

  /// 탭 버튼
  Widget _buildTab(String tab, String label) {
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Theme.of(context).primaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  /// 필터 버튼
  Widget _buildFilterButton() {
    return Stack(
      children: [
        IconButton(
          icon: Icon(
            Icons.filter_list,
            color: _hasActiveFilters() ? Theme.of(context).primaryColor : Colors.grey[700],
          ),
          onPressed: _showFilterDialog,
          tooltip: '필터',
        ),
        if (_hasActiveFilters())
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                '${_getActiveFilterCount()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
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

  /// TO 목록
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
        padding: const EdgeInsets.all(16),
        itemCount: _filteredGroupItems.length,
        itemBuilder: (context, index) {
          final groupItem = _filteredGroupItems[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
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

  /// 빈 상태
  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox,
              size: 80,
              color: Theme.of(context).primaryColor.withOpacity(0.3),
            ),
            const SizedBox(height: 20),
            Text(
              '조건에 맞는 TO가 없습니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '필터를 변경하거나 새로운 TO를 생성하세요',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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