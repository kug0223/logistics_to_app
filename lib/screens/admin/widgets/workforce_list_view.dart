import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

// Models
import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_model.dart';

// Services
import '../../../services/firestore_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Providers
import '../../../providers/user_provider.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/format_helper.dart';

// Widgets
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/common/styled_container.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/inputs/filter_dialog.dart';

// Screens
import '../admin_edit_to_screen.dart';

// Local Models
import '../../../models/ui/admin_to_list_ui_models.dart';

// Local dialogs
import '../dialogs/work_detail_management_dialog.dart';
import '../dialogs/confirmed_list_dialog.dart';
import '../dialogs/to_list_dialogs.dart';
import '../dialogs/work_applicants_dialog.dart';

// Local Widgets

/// 인력 관리 - 리스트 뷰 (admin_to_list_screen 완전 동일)
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
  
  // ✅ Phase 4: 탭 상태
  String _selectedTab = 'ACTIVE'; // 'ACTIVE' or 'CLOSED'

  // 사업장 목록
  List<String> _businessNames = [];
  
  // ✅ 이중 토글 상태 관리
  final Set<String> _expandedGroups = {}; // 펼쳐진 그룹 ID
  final Set<String> _expandedTOs = {}; // 펼쳐진 TO ID

  /// TO 목록 + 지원자 통계 로드 (탭별 분리)
  Future<void> _loadTOsWithStats() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // ✅ 모든 사업장의 TO 조회
      List<TOModel> masterTOs;
      if (_selectedTab == 'ACTIVE') {
        masterTOs = await _firestoreService.getActiveTOs();
      } else {
        masterTOs = await _firestoreService.getClosedTOs();
      }

      // 2. 각 TO별 처리
      List<TOGroupItem> groupItems = [];
      
      for (var masterTO in masterTOs) {
        // 그룹 TO인 경우
        if (masterTO.isGrouped && masterTO.groupId != null) {
          // 같은 그룹의 모든 TO 조회
          final groupTOs = await _firestoreService.getTOsByGroup(masterTO.groupId!);
          final toIds = groupTOs.map((to) => to.id).toList();
          
          // ✅ WorkDetails와 시간 범위만 조회
          final batchResults = await Future.wait([
            _firestoreService.getWorkDetailsBatch(toIds, forceRefresh: true),
            _firestoreService.calculateGroupTimeRange(masterTO.groupId!, forceRefresh: true),
          ]);
          
          final workDetailsMap = batchResults[0] as Map<String, List<WorkDetailModel>>;
          final timeRange = batchResults[1] as Map<String, String>;
          
          // ✅ 병렬로 지원서 일괄 조회
          final applicationsMap = await _firestoreService.getApplicationsByTOIds(toIds);

          // ✅ 각 TO 아이템 생성
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
          // 단일 TO인 경우
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

      // 3. 사업장 목록 추출
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
      setState(() {
        _isLoading = false;
      });
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
  
  String _calculateDeadline(TOModel to, WorkDetailModel work) {
    final hoursBeforeStart = to.hoursBeforeStart ?? 2;
    
    final timeParts = work.startTime.split(':');
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);
    
    final deadlineHour = hour - hoursBeforeStart;
    final deadlineMinute = minute;
    
    return '${deadlineHour.toString().padLeft(2, '0')}:${deadlineMinute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 탭바 + 필터 아이콘
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 탭바
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_selectedTab != 'ACTIVE') {
                              setState(() {
                                _selectedTab = 'ACTIVE';
                                _expandedGroups.clear();
                                _expandedTOs.clear();
                              });
                              _loadTOsWithStats();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _selectedTab == 'ACTIVE' ? Theme.of(context).primaryColor : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _selectedTab == 'ACTIVE'
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
                              '진행중',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _selectedTab == 'ACTIVE' ? Colors.white : Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_selectedTab != 'CLOSED') {
                              setState(() {
                                _selectedTab = 'CLOSED';
                                _expandedGroups.clear();
                                _expandedTOs.clear();
                              });
                              _loadTOsWithStats();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _selectedTab == 'CLOSED' ? Theme.of(context).primaryColor : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _selectedTab == 'CLOSED'
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
                              '마감됨',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _selectedTab == 'CLOSED' ? Colors.white : Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 필터 아이콘
              Stack(
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
              ),
            ],
          ),
        ),
        
        Expanded(child: _buildTOList()),
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
          setState(() {
            _selectedBusiness = value;
          });
          _applyFilters();
        },
        onDateRangeChanged: (value) {
          setState(() {
            _selectedDateRange = value;
          });
          _applyFilters();
        },
      ),
    );
  }

  Widget _buildTOList() {
    if (_isLoading) {
      return const LoadingWidget(message: 'TO 목록을 불러오는 중...');
    }

    if (_filteredGroupItems.isEmpty) {
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
              Icon(Icons.inbox, size: 80, color: Theme.of(context).primaryColor.withOpacity(0.3)),
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
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
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
            child: _buildGroupCard(groupItem),
          );
        },
      ),
    );
  }

  // ===== 여기부터는 admin_to_list_screen.dart의 나머지 모든 메서드를 그대로 복사 =====
  // _buildGroupCard, _buildTOItemCard, _buildWorkDetailRow 등 모든 메서드 포함
  
  Widget _buildGroupCard(TOGroupItem groupItem) {
    final masterTO = groupItem.masterTO;
    final isExpanded = _expandedGroups.contains(masterTO.groupId ?? masterTO.id);
    final dateFormat = DateFormat('MM/dd (E)', 'ko_KR');
    
    int totalConfirmed = 0;
    int totalPending = 0;
    int totalRequired = 0;
    
    for (var toItem in groupItem.groupTOs) {
      totalConfirmed += toItem.confirmedCount;
      totalPending += toItem.pendingCount;
      totalRequired += toItem.totalRequired;
    }
    
    final isFull = groupItem.groupTOs.every((toItem) {
      return toItem.workDetails.every((work) {
        final stats = toItem.workDetailStats?[work.workType];
        final confirmed = stats?['confirmed'] ?? 0;
        return confirmed >= work.requiredCount;
      });
    });

    return Card(
      elevation: isExpanded ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isExpanded 
              ? Theme.of(context).primaryColor
              : (isFull ? Colors.green[200]! : Colors.grey[200]!),
          width: isExpanded ? 2 : (isFull ? 2 : 1),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                final key = masterTO.groupId ?? masterTO.id;
                if (_expandedGroups.contains(key)) {
                  _expandedGroups.remove(key);
                  _expandedTOs.clear();
                } else {
                  _expandedGroups.clear();
                  _expandedTOs.clear();
                  _expandedGroups.add(key);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.business, size: 14, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              masterTO.businessName,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: masterTO.isLongTerm ? Colors.purple[50] : Colors.blue[50],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: masterTO.isLongTerm ? Colors.purple[300]! : Colors.blue[300]!,
                          ),
                        ),
                        child: Text(
                          masterTO.jobTypeLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: masterTO.isLongTerm ? Colors.purple[700] : Colors.blue[700],
                          ),
                        ),
                      ),
                      const Spacer(),
                      () {
                        bool allClosed = groupItem.groupTOs.every((toItem) {
                          return toItem.workDetails.every((work) => 
                            work.isClosed || work.isTimeExpired || work.isFull
                          );
                        });
                        
                        if (allClosed) {
                          return StyledOutlineBadge(
                            label: '마감됨',
                            color: Colors.grey[600]!,
                            backgroundColor: Colors.grey[50],
                            icon: Icons.lock,
                            fontSize: 11,
                          );
                        } else if (isFull) {
                          return StyledOutlineBadge(
                            label: '인원충족',
                            color: Colors.green[600]!,
                            icon: Icons.check_circle,
                            fontSize: 11,
                          );
                        } else {
                          return StyledOutlineBadge(
                            label: '진행중',
                            color: Theme.of(context).primaryColor,
                            icon: Icons.circle,
                            fontSize: 11,
                          );
                        }
                      }(),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (masterTO.groupName != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green[300]!, width: 1.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_open, size: 16, color: Colors.green[700]),
                              const SizedBox(width: 6),
                              Text(
                                masterTO.groupName!,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[800],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (masterTO.groupName == null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[300]!, width: 1.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.work_outline, size: 16, color: Colors.blue[700]),
                              const SizedBox(width: 6),
                              Text(
                                '단일 공고',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[800],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (!groupItem.isGrouped) ...[
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[700]),
                          padding: EdgeInsets.zero,
                          tooltip: '메뉴',
                          onSelected: (value) async {
                            switch (value) {
                              case 'edit':
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AdminEditTOScreen(to: masterTO),
                                  ),
                                ).then((result) {
                                  if (result == true) {
                                    _firestoreService.clearCache();
                                    _loadTOsWithStats();
                                  }
                                });
                                break;
                              case 'delete':
                                _dialogs.showDeleteTODialog(groupItem.groupTOs.first);
                                break;
                              case 'link':
                                _dialogs.showReconnectToGroupDialog(
                                  groupItem.groupTOs.first,
                                  _allGroupItems,
                                );
                                break;
                              case 'confirmedList':
                                _showConfirmedListDialog(groupItem.groupTOs.first);
                                break;
                              case 'manageWorkDetails':
                                WorkDetailManagementDialog(
                                  context: context,
                                  toItem: groupItem.groupTOs.first,
                                  firestoreService: _firestoreService,
                                  onComplete: () => _loadTOsWithStats(),
                                ).show();
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 18, color: Colors.orange[600]),
                                  const SizedBox(width: 12),
                                  const Text('수정'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, size: 18, color: Colors.red[600]),
                                  const SizedBox(width: 12),
                                  const Text('삭제'),
                                ],
                              ),
                            ),
                            if (masterTO.isShortTerm)
                              PopupMenuItem(
                                value: 'link',
                                child: Row(
                                  children: [
                                    Icon(Icons.link, size: 18, color: Colors.blue[600]),
                                    const SizedBox(width: 12),
                                    const Text('그룹 연결'),
                                  ],
                                ),
                              ),
                            PopupMenuItem(
                              value: 'confirmedList',
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle_outline, size: 18, color: Colors.green[600]),
                                  const SizedBox(width: 12),
                                  const Text('확정명단'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'manageWorkDetails',
                              child: Row(
                                children: [
                                  Icon(Icons.assignment_turned_in, size: 18, color: Colors.purple[600]),
                                  const SizedBox(width: 12),
                                  const Text('업무별 마감'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (groupItem.isGrouped && masterTO.groupId != null) ...[
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[700]),
                          padding: EdgeInsets.zero,
                          tooltip: '메뉴',
                          onSelected: (value) async {
                            switch (value) {
                              case 'editGroupName':
                                _dialogs.showEditGroupNameDialog(masterTO);
                                break;
                              case 'closeGroup':
                                _dialogs.showCloseGroupDialog(groupItem);
                                break;
                              case 'reopenGroup':
                                _dialogs.showReopenGroupDialog(groupItem);
                                break;
                              case 'deleteGroup':
                                _dialogs.showDeleteGroupDialog(groupItem);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'editGroupName',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 18, color: Colors.blue[600]),
                                  const SizedBox(width: 12),
                                  const Text('그룹명 수정'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: masterTO.isClosed ? 'reopenGroup' : 'closeGroup',
                              child: Row(
                                children: [
                                  Icon(
                                    masterTO.isClosed ? Icons.lock_open : Icons.lock,
                                    size: 18,
                                    color: masterTO.isClosed ? Colors.green[600] : Colors.orange[600],
                                  ),
                                  const SizedBox(width: 12),
                                  Text(masterTO.isClosed ? '그룹 재오픈' : '그룹 마감'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'deleteGroup',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_forever, size: 18, color: Colors.red[600]),
                                  const SizedBox(width: 12),
                                  const Text('그룹 전체 삭제'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(width: 4),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                  if (masterTO.groupName == null) ...[
                    const SizedBox(height: 8),
                    Text(
                      masterTO.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: masterTO.isLongTerm
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  masterTO.longTermPeriodWithDays,
                                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                                ),
                                if (masterTO.workDays != null && masterTO.workDays!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    masterTO.workDaysLabel,
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ],
                              ],
                            )
                          : Text(
                              groupItem.isGrouped
                                  ? '${dateFormat.format(masterTO.date)} 외 ${groupItem.groupTOs.length - 1}일'
                                  : dateFormat.format(masterTO.date),
                              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                            ),
                      ),
                      if (!groupItem.isGrouped) ...[
                        const Spacer(),
                        _buildDeadlineBadge(masterTO),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [  
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isFull ? Colors.green[50] : Theme.of(context).primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isFull ? Colors.green[200]! : Theme.of(context).primaryColor.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('👥', style: TextStyle(fontSize: 11)),
                            const SizedBox(width: 4),
                            Text(
                              '확정 $totalConfirmed/$totalRequired명',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isFull ? Colors.green[700] : Theme.of(context).primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (totalPending > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange[200]!),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('⏳', style: TextStyle(fontSize: 11)),
                              const SizedBox(width: 4),
                              Text(
                                '대기 $totalPending명',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Spacer()
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded && groupItem.isGrouped) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: groupItem.groupTOs.map((toItem) {
                  return _buildTOItemCard(toItem, groupItem);
                }).toList(),
              ),
            ),
          ],
          if (isExpanded && !groupItem.isGrouped) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '업무 상세',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...groupItem.groupTOs.first.workDetails.map((work) {
                    final stats = groupItem.groupTOs.first.workDetailStats?[work.workType];
                    final confirmed = stats?['confirmed'] ?? 0;
                    final pending = stats?['pending'] ?? 0;
                    return _buildWorkDetailRow(work, confirmed, pending, groupItem.groupTOs.first);
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTOItemCard(TOItem toItem, TOGroupItem groupItem) {
    final to = toItem.to;
    final isExpanded = _expandedTOs.contains(to.id);
    final dateFormat = DateFormat('MM/dd (E)', 'ko_KR');
    
    final isFull = toItem.workDetails.every((work) {
      final stats = toItem.workDetailStats?[work.workType];
      final confirmed = stats?['confirmed'] ?? 0;
      return confirmed >= work.requiredCount;
    });

    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 12),
      decoration: BoxDecoration(
        color: isExpanded ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isExpanded ? Theme.of(context).primaryColor : Colors.grey[300]!,
          width: isExpanded ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (_expandedTOs.contains(to.id)) {
                  _expandedTOs.remove(to.id);
                } else {
                  _expandedTOs.clear();
                  _expandedTOs.add(to.id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        dateFormat.format(to.date),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          to.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      () {
                        final allWorksClosed = toItem.workDetails.every((work) => 
                          work.isClosed || work.isTimeExpired || work.isFull
                        );
                        
                        if (allWorksClosed) {
                          return StyledOutlineBadge(
                            label: '마감됨',
                            color: Colors.grey[600]!,
                            backgroundColor: Colors.grey[300],
                            icon: Icons.lock,
                            fontSize: 10,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            borderRadius: 10,
                          );
                        } else if (isFull) {
                          return StyledOutlineBadge(
                            label: '인원충족',
                            color: Colors.green[600]!,
                            icon: Icons.check_circle,
                            fontSize: 10,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            borderRadius: 10,
                          );
                        } else {
                          return StyledOutlineBadge(
                            label: '진행중',
                            color: Theme.of(context).primaryColor,
                            icon: Icons.circle,
                            fontSize: 10,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            borderRadius: 10,
                          );
                        }
                      }(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: to.isLongTerm 
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  to.longTermPeriodWithDays,
                                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                                ),
                                if (to.workDays != null && to.workDays!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    to.workDaysLabel,
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                  ),
                                ],
                              ],
                            )
                          : Text(
                              dateFormat.format(to.date),
                              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                            ),
                      ),
                      const Spacer(),
                      _buildDeadlineBadge(to),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: toItem.confirmedCount >= toItem.totalRequired ? Colors.green[50] : Theme.of(context).primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: toItem.confirmedCount >= toItem.totalRequired ? Colors.green[200]! : Theme.of(context).primaryColor.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('👥', style: TextStyle(fontSize: 11)),
                            const SizedBox(width: 4),
                            Text(
                              '확정 ${toItem.confirmedCount}/${toItem.totalRequired}명',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: toItem.confirmedCount >= toItem.totalRequired ? Colors.green[700] : Theme.of(context).primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (toItem.pendingCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange[200]!),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('⏳', style: TextStyle(fontSize: 11)),
                              const SizedBox(width: 4),
                              Text(
                                '대기 ${toItem.pendingCount}명',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[700]),
                        padding: EdgeInsets.zero,
                        tooltip: '메뉴',
                        onSelected: (value) async {
                          switch (value) {
                            case 'edit':
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AdminEditTOScreen(to: toItem.to),
                                ),
                              ).then((result) {
                                if (result == true) {
                                  _firestoreService.clearCache();
                                  _loadTOsWithStats();
                                }
                              });
                              break;
                            case 'delete':
                              _dialogs.showDeleteTODialog(toItem);
                              break;
                            case 'unlink':
                              _dialogs.showRemoveFromGroupDialog(toItem);
                              break;
                            case 'confirmedList':
                              _showConfirmedListDialog(toItem);
                              break;
                            case 'manageWorkDetails':
                              WorkDetailManagementDialog(
                                context: context,
                                toItem: toItem,
                                firestoreService: _firestoreService,
                                onComplete: () => _loadTOsWithStats(),
                              ).show();
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 18, color: Colors.orange[700]),
                                const SizedBox(width: 12),
                                const Text('수정'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 18, color: Colors.red[700]),
                                const SizedBox(width: 12),
                                const Text('삭제'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'unlink',
                            child: Row(
                              children: [
                                Icon(Icons.link_off, size: 18, color: Colors.orange[700]),
                                const SizedBox(width: 12),
                                const Text('그룹 해제'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'confirmedList',
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_outline, size: 18, color: Colors.green[600]),
                                const SizedBox(width: 12),
                                const Text('확정명단'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'manageWorkDetails',
                            child: Row(
                              children: [
                                Icon(Icons.task_alt, size: 18, color: Colors.purple[600]),
                                const SizedBox(width: 12),
                                const Text('업무별 마감'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '업무 상세',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...toItem.workDetails.map((work) {
                    final stats = toItem.workDetailStats?[work.workType];
                    final confirmed = stats?['confirmed'] ?? 0;
                    final pending = stats?['pending'] ?? 0;
                    return _buildWorkDetailRow(work, confirmed, pending, toItem);
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkDetailRow(WorkDetailModel work, int confirmedCount, int pendingCount, TOItem toItem) {
    final workStatus = _getWorkStatus(work, confirmedCount);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 24),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: FormatHelper.parseColor(work.workTypeBackgroundColor ?? '#2196F3'),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: WorkTypeIcon.buildFromString(
                    work.workTypeIcon,
                    color: FormatHelper.parseColor(work.workTypeColor),
                    size: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  work.workType,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[600]),
                padding: EdgeInsets.zero,
                onSelected: (value) => _handleWorkDetailMenu(value, work, toItem),
                itemBuilder: (context) {
                  final isClosed = work.isClosed;
                  final isTimeExpired = work.isTimeExpired;
                  final isEmergencyOpen = work.isEmergencyOpen;
                  
                  return [
                    PopupMenuItem(
                      value: 'manage',
                      child: Row(
                        children: [
                          Icon(Icons.people, size: 18, color: Colors.blue[700]),
                          const SizedBox(width: 8),
                          const Text('지원자 관리'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    if (isTimeExpired)
                      PopupMenuItem(
                        enabled: false,
                        value: 'expired',
                        child: Row(
                          children: [
                            Icon(Icons.schedule, size: 18, color: Colors.grey[400]),
                            const SizedBox(width: 8),
                            Text(
                              '시간 만료됨',
                              style: TextStyle(color: Colors.grey[400]),
                            ),
                          ],
                        ),
                      )
                    else if (isClosed)
                      PopupMenuItem(
                        value: 'reopen',
                        child: Row(
                          children: [
                            Icon(Icons.lock_open, size: 18, color: Colors.green[700]),
                            const SizedBox(width: 8),
                            const Text('업무 재오픈'),
                          ],
                        ),
                      )
                    else
                      PopupMenuItem(
                        value: 'close',
                        child: Row(
                          children: [
                            Icon(Icons.block, size: 18, color: Colors.red[700]),
                            const SizedBox(width: 8),
                            const Text('업무 마감'),
                          ],
                        ),
                      ),
                    if (!isClosed && !isTimeExpired) ...[
                      const PopupMenuDivider(),
                      if (!isEmergencyOpen)
                        PopupMenuItem(
                          value: 'emergency_start',
                          child: Row(
                            children: [
                              Icon(Icons.warning, size: 18, color: Colors.orange[700]),
                              const SizedBox(width: 8),
                              const Text('긴급 모집 시작'),
                            ],
                          ),
                        )
                      else
                        PopupMenuItem(
                          value: 'emergency_stop',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, size: 18, color: Colors.green[700]),
                              const SizedBox(width: 8),
                              const Text('긴급 모집 종료'),
                            ],
                          ),
                        ),
                    ],
                  ];
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                '${work.startTime}~${work.endTime}',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(width: 12),
              Icon(Icons.payments, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                '${NumberFormat('#,###').format(work.wage)}원',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              if (toItem.to.deadlineType == 'HOURS_BEFORE') ...[
                const Spacer(),
                Icon(Icons.alarm, size: 13, color: Colors.orange[600]),
                const SizedBox(width: 4),
                Text(
                  '마감: ${_calculateDeadline(toItem.to, work)}까지',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange[700],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: work.isFull ? Colors.green[50] : Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: work.isFull ? Colors.green[200]! : Theme.of(context).primaryColor.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('👥', style: TextStyle(fontSize: 11)),
                    const SizedBox(width: 4),
                    Text(
                      '확정 $confirmedCount/${work.requiredCount}명',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: work.isFull ? Colors.green[700] : Theme.of(context).primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (pendingCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('⏳', style: TextStyle(fontSize: 11)),
                      const SizedBox(width: 4),
                      Text(
                        '대기 $pendingCount명',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: workStatus['color'],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  workStatus['label'],
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleWorkDetailMenu(String value, WorkDetailModel work, TOItem toItem) async {
    switch (value) {
      case 'manage':
        await _showWorkApplicantsDialog(work, toItem);
        break;
      case 'close':
        await _closeWork(work, toItem);
        break;
      case 'reopen':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('업무 재오픈'),
            content: Text('${work.workType} 업무를 재오픈하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('재오픈'),
              ),
            ],
          ),
        );
        
        if (confirm == true) {
          await _firestoreService.reopenWorkDetail(
            toId: toItem.to.id,
            workDetailId: work.id,
            adminUID: FirebaseAuth.instance.currentUser!.uid,
          );
          _loadTOsWithStats();
          ToastHelper.showSuccess('업무가 재오픈되었습니다');
        }
        break;
      case 'expired':
        ToastHelper.showWarning('시간이 지난 업무는 재오픈할 수 없습니다');
        break;
      case 'emergency_start':
        await _startEmergency(work, toItem);
        break;
      case 'emergency_stop':
        await _stopEmergency(work, toItem);
        break;
    }
  }

  Future<void> _showWorkApplicantsDialog(WorkDetailModel work, TOItem toItem) async {
    await showDialog(
      context: context,
      builder: (context) => WorkApplicantsDialog(
        work: work,
        toItem: toItem,
        onChanged: () => _loadTOsWithStats(),
      ),
    );
  }

  Future<void> _closeWork(WorkDetailModel work, TOItem toItem) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${work.workType} 마감'),
        content: const Text('이 업무를 마감하시겠습니까?\n마감 후에도 재오픈할 수 있습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('마감'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUID = userProvider.currentUser?.uid;

      await _firestoreService.updateWorkDetail(
        toId: toItem.to.id,
        workDetailId: work.id,
        updates: {
          'closedAt': Timestamp.now(),
          'closedBy': adminUID,
          'isManualClosed': true,
          'isEmergencyOpen': false,
        },
      );

      ToastHelper.showSuccess('${work.workType} 업무가 마감되었습니다');
      _loadTOsWithStats();
    } catch (e) {
      print('❌ 업무 마감 실패: $e');
      ToastHelper.showError('업무 마감에 실패했습니다');
    }
  }

  void _showConfirmedListDialog(TOItem toItem) {
    ConfirmedListDialog(
      context: context,
      toItem: toItem,
      firestoreService: _firestoreService,
    ).show();
  }

  Future<void> _startEmergency(WorkDetailModel work, TOItem toItem) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🚨 긴급 모집'),
        content: Text('${work.workType} 긴급 모집을 시작하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('시작'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUID = userProvider.currentUser?.uid;

      await _firestoreService.updateWorkDetail(
        toId: toItem.to.id,
        workDetailId: work.id,
        updates: {
          'isEmergencyOpen': true,
          'emergencyOpenedAt': Timestamp.now(),
          'emergencyOpenedBy': adminUID,
        },
      );

      ToastHelper.showSuccess('🚨 ${work.workType} 긴급 모집이 시작되었습니다');
      _loadTOsWithStats();
    } catch (e) {
      print('❌ 긴급 모집 시작 실패: $e');
      ToastHelper.showError('긴급 모집 시작에 실패했습니다');
    }
  }

  Future<void> _stopEmergency(WorkDetailModel work, TOItem toItem) async {
    try {
      await _firestoreService.updateWorkDetail(
        toId: toItem.to.id,
        workDetailId: work.id,
        updates: {
          'isEmergencyOpen': false,
          'emergencyOpenedAt': null,
          'emergencyOpenedBy': null,
        },
      );

      ToastHelper.showSuccess('${work.workType} 긴급 모집이 종료되었습니다');
      _loadTOsWithStats();
    } catch (e) {
      print('❌ 긴급 모집 종료 실패: $e');
      ToastHelper.showError('긴급 모집 종료에 실패했습니다');
    }
  }

  Map<String, dynamic> _getWorkStatus(WorkDetailModel work, int confirmedCount) {
    if (work.isTimeExpired) {
      return {
        'label': '마감됨',
        'color': Colors.grey[600],
      };
    }
    
    if (work.isClosed) {
      return {
        'label': '마감됨',
        'color': Colors.grey[600],
      };
    }
    
    if (work.isEmergencyOpen) {
      return {
        'label': '긴급모집',
        'color': Colors.red[600],
      };
    }
    
    if (confirmedCount >= work.requiredCount) {
      return {
        'label': '인원충족',
        'color': Colors.green[600],
      };
    }
    
    return {
      'label': '진행중',
      'color': Theme.of(context).primaryColor,
    };
  }

  Widget _buildDeadlineBadge(TOModel to) {
    if (to.deadlineType == 'FIXED_TIME') {
      return StyledBadge(
        label: '🕐 ${DateFormat('MM/dd HH:mm').format(to.applicationDeadline)}',
        backgroundColor: Colors.orange[50]!,
        textColor: Colors.orange[700]!,
        fontSize: 12,
        borderRadius: 4,
      );
    }
    
    if (to.deadlineType == 'HOURS_BEFORE' && to.hoursBeforeStart != null) {
      return StyledBadge(
        label: '🕐 각 업무 ${to.hoursBeforeStart}시간 전',
        backgroundColor: Colors.orange[50]!,
        textColor: Colors.orange[700]!,
        fontSize: 12,
        borderRadius: 4,
      );
    }
    
    return const SizedBox.shrink();
  }
}