import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../services/firestore_service.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/common/styled_container.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../providers/theme_provider.dart';
import '../../../widgets/work_type_icon.dart';
import '../dialogs/work_applicants_dialog.dart';
import '../dialogs/confirmed_list_dialog.dart';
import '../dialogs/work_detail_management_dialog.dart';
import '../dialogs/to_list_dialogs.dart';
import '../admin_edit_to_screen.dart';

/// 인력 관리 - 리스트 뷰 (admin_to_list 완전 동일)
class WorkforceListView extends StatefulWidget {
  final String businessId;

  const WorkforceListView({
    super.key,
    required this.businessId,
  });

  @override
  State<WorkforceListView> createState() => _WorkforceListViewState();
}

class _WorkforceListViewState extends State<WorkforceListView> {
  final FirestoreService _firestoreService = FirestoreService();
  late TOListDialogs _dialogs;
  
  List<TOGroupItem> _allGroupItems = [];
  List<TOGroupItem> _filteredGroupItems = [];
  bool _isLoading = true;
  String _filter = 'ACTIVE'; // 'ACTIVE', 'CLOSED'
  
  final Set<String> _expandedGroups = {};
  final Set<String> _expandedTOs = {};

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

  /// TO 목록 + 통계 로드
  Future<void> _loadTOsWithStats() async {
    setState(() => _isLoading = true);

    try {
      List<TOModel> masterTOs;
      if (_filter == 'ACTIVE') {
        masterTOs = await _firestoreService.getActiveTOsByBusinessId(widget.businessId);
        masterTOs = masterTOs.where((to) => !to.isClosed).toList();
      } else {
        masterTOs = await _firestoreService.getClosedTOsByBusinessId(widget.businessId);
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

      setState(() {
        _allGroupItems = groupItems;
        _filteredGroupItems = groupItems;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ TO 로드 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('TO 목록을 불러오는데 실패했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const LoadingWidget(message: 'TO 목록을 불러오는 중...');
    }

    return Column(
      children: [
        _buildFilterAndStats(),
        const Divider(height: 1),
        Expanded(
          child: _filteredGroupItems.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadTOsWithStats,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredGroupItems.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildGroupCard(_filteredGroupItems[index]),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
  /// 필터 & 통계
  Widget _buildFilterAndStats() {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    
    int totalRequired = 0;
    int totalConfirmed = 0;
    
    for (var groupItem in _allGroupItems) {
      for (var toItem in groupItem.groupTOs) {
        totalRequired += toItem.totalRequired;
        totalConfirmed += toItem.confirmedCount;
      }
    }
    
    final fillRate = totalRequired > 0 
        ? (totalConfirmed / totalRequired * 100).toInt() 
        : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[50],
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _filter = 'ACTIVE';
                    });
                    _loadTOsWithStats();
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _filter == 'ACTIVE' ? primaryColor : Colors.white,
                    foregroundColor: _filter == 'ACTIVE' ? Colors.white : primaryColor,
                    side: BorderSide(color: primaryColor),
                  ),
                  child: const Text('진행 중'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _filter = 'CLOSED';
                    });
                    _loadTOsWithStats();
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _filter == 'CLOSED' ? primaryColor : Colors.white,
                    foregroundColor: _filter == 'CLOSED' ? Colors.white : primaryColor,
                    side: BorderSide(color: primaryColor),
                  ),
                  child: const Text('마감됨'),
                ),
              ),
            ],
          ),
          
          if (_filter == 'ACTIVE') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatItem('TO 수', '${_allGroupItems.length}건', Colors.blue),
                  ),
                  Expanded(
                    child: _buildStatItem('필요', '$totalRequired명', Colors.orange),
                  ),
                  Expanded(
                    child: _buildStatItem('확정', '$totalConfirmed명', Colors.green),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      '충족률',
                      '$fillRate%',
                      fillRate >= 80 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _filter == 'ACTIVE' ? '진행 중인 TO가 없습니다' : '마감된 TO가 없습니다',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
  /// 그룹 카드 (admin_to_list와 완전 동일)
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
              ? Colors.blue[400]!
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
                  // 첫 줄: 사업장명 + 장기/단기 배지 + 상태 배지 + 더보기
                  Row(
                    children: [
                      // 사업장명
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1976D2),
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
                      
                      // 장기/단기 배지
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: masterTO.isLongTerm ? Colors.purple[50] : Colors.orange[50],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: masterTO.isLongTerm ? Colors.purple[300]! : Colors.orange[300]!,
                          ),
                        ),
                        child: Text(
                          masterTO.jobTypeLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: masterTO.isLongTerm ? Colors.purple[900] : Colors.orange[900],
                          ),
                        ),
                      ),
                      
                      const Spacer(),
                      
                      // 상태 배지
                      () {
                        final allWorksClosed = groupItem.groupTOs.every((toItem) =>
                          toItem.workDetails.every((work) => 
                            work.isClosed || work.isTimeExpired || work.isFull
                          )
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
                            color: Colors.blue[600]!,
                            icon: Icons.circle,
                            fontSize: 10,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            borderRadius: 10,
                          );
                        }
                      }(),
                      
                      // 단일 TO 더보기 메뉴
                      if (!groupItem.isGrouped)
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[700]),
                          padding: EdgeInsets.zero,
                          onSelected: (value) async {
                            switch (value) {
                              case 'edit':
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AdminEditTOScreen(to: masterTO),
                                  ),
                                );
                                _loadTOsWithStats();
                                break;
                              case 'delete':
                                _dialogs.showDeleteTODialog(groupItem.groupTOs.first);
                                break;
                              case 'link':  // ✅ 추가
                                // ⭐ 장기공고는 그룹연결 불가
                                if (masterTO.isLongTerm) {
                                  ToastHelper.showError('장기 공고는 그룹 연결을 할 수 없습니다');
                                  return;
                                }
                                _dialogs.showReconnectToGroupDialog(
                                  groupItem.groupTOs.first,
                                  _allGroupItems,
                                );
                                break;
                              case 'confirmedList':
                                _showConfirmedListDialog(groupItem.groupTOs.first);
                                break;
                              case 'manageWorkDetails':
                                _showWorkDetailManagementDialog(groupItem.groupTOs.first);
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
                            PopupMenuItem(  // ✅ 추가
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
                      
                      // 그룹 TO 더보기 메뉴
                      if (groupItem.isGrouped && masterTO.groupId != null)
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[700]),
                          padding: EdgeInsets.zero,
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
                      
                      const SizedBox(width: 4),
                      
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                  
                  // 그룹명 표시 (그룹 TO만)
                  if (masterTO.groupName != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
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
                      ],
                    ),
                  ],
                  
                  // 단일 TO 제목 (단일만)
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
                  
                  // 날짜 + 마감시간
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: masterTO.isLongTerm
                            ? Text(
                                _buildLongTermDisplay(masterTO),
                                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                              )
                            : Text(
                                groupItem.isGrouped && masterTO.groupDateRangeDisplay != null
                                    ? masterTO.groupDateRangeDisplay!
                                    : dateFormat.format(masterTO.date),
                                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                              ),
                      ),
                      const SizedBox(width: 12),
                      
                      // ⭐ 마감시간 (오른쪽으로 이동)
                      Icon(Icons.alarm, size: 16, color: Colors.orange[600]),
                      const SizedBox(width: 6),
                      Text(
                        _buildDeadlineDisplay(masterTO),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange[700],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  
                  // 인원 배지
                  Row(
                    children: [
                      if (totalConfirmed > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green[200]!),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('✓', style: TextStyle(fontSize: 11)),
                              const SizedBox(width: 4),
                              Text(
                                '확정 $totalConfirmed명',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (totalConfirmed > 0) const SizedBox(width: 8),
                      
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
                      const Spacer(),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // 펼쳐진 경우
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: groupItem.isGrouped
                  ? Column(
                      children: groupItem.groupTOs.map((toItem) {
                        return _buildTOItemCard(toItem, groupItem);
                      }).toList(),
                    )
                  : Column(
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

  // 헬퍼 메서드들
  void _showConfirmedListDialog(TOItem toItem) {
    ConfirmedListDialog(
      context: context,
      toItem: toItem,
      firestoreService: _firestoreService,
    ).show();
  }

  void _showWorkDetailManagementDialog(TOItem toItem) {
    WorkDetailManagementDialog(
      context: context,
      toItem: toItem,
      firestoreService: _firestoreService,
      onComplete: _loadTOsWithStats,
    ).show();
  }
  

  Widget _buildStatusBadge(TOItem toItem) {
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
    } else if (toItem.confirmedCount >= toItem.totalRequired) {
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
        color: Colors.blue[600]!,
        icon: Icons.circle,
        fontSize: 10,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        borderRadius: 10,
      );
    }
  }

  /// 업무 상세 행
  Widget _buildWorkDetailRow(WorkDetailModel work, int confirmedCount, int pendingCount, TOItem toItem) {
    final workStatus = _getWorkStatus(work, confirmedCount);
    final theme = Theme.of(context);
    
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
              
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(workStatus).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _getStatusColor(workStatus).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getStatusIcon(workStatus),
                      size: 12,
                      color: _getStatusColor(workStatus),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _getStatusLabel(workStatus),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _getStatusColor(workStatus),
                      ),
                    ),
                  ],
                ),
              ),
              
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 18, color: Colors.grey[600]),
                padding: EdgeInsets.zero,
                onSelected: (value) async {
                  switch (value) {
                    case 'applicants':
                      showDialog(
                        context: context,
                        builder: (context) => WorkApplicantsDialog(
                          work: work,
                          toItem: toItem,
                          onChanged: _loadTOsWithStats,
                        ),
                      );
                      break;
                    case 'close':
                      final confirm = await DialogHelper.showConfirm(
                        context,
                        title: '업무 마감',
                        message: '${work.workType}을(를) 마감하시겠습니까?',
                        confirmText: '마감',
                        confirmColor: Colors.red,
                      );
                      if (confirm) {
                        await _firestoreService.closeWorkDetail(
                          toId: toItem.to.id,
                          workDetailId: work.id,
                          adminUID: FirebaseAuth.instance.currentUser!.uid,
                        );
                        ToastHelper.showSuccess('업무가 마감되었습니다');
                        _loadTOsWithStats();
                      }
                      break;
                    case 'reopen':
                      final confirm = await DialogHelper.showConfirm(
                        context,
                        title: '업무 재오픈',
                        message: '${work.workType}을(를) 재오픈하시겠습니까?',
                        confirmText: '재오픈',
                        confirmColor: Colors.green,
                      );
                      if (confirm) {
                        await _firestoreService.reopenWorkDetail(
                          toId: toItem.to.id,
                          workDetailId: work.id,
                          adminUID: FirebaseAuth.instance.currentUser!.uid,
                        );
                        ToastHelper.showSuccess('업무가 재오픈되었습니다');
                        _loadTOsWithStats();
                      }
                      break;
                    case 'emergency':
                      final confirm = await DialogHelper.showConfirm(
                        context,
                        title: '긴급 모집',
                        message: '${work.workType}을(를) 긴급 모집하시겠습니까?',
                        confirmText: '긴급모집',
                        confirmColor: Colors.red,
                      );
                      if (confirm) {
                        await _firestoreService.startEmergencyRecruitment(
                          toId: toItem.to.id,
                          workDetailId: work.id,
                          adminUID: FirebaseAuth.instance.currentUser!.uid,
                        );
                        ToastHelper.showSuccess('긴급 모집이 시작되었습니다');
                        _loadTOsWithStats();
                      }
                      break;
                    case 'stopEmergency':
                      final confirm = await DialogHelper.showConfirm(
                        context,
                        title: '긴급모집 종료',
                        message: '${work.workType}의 긴급모집을 종료하시겠습니까?',
                        confirmText: '종료',
                        confirmColor: Colors.orange,
                      );
                      if (confirm) {
                        await _firestoreService.stopEmergencyRecruitment(
                          toId: toItem.to.id,
                          workDetailId: work.id,
                          adminUID: FirebaseAuth.instance.currentUser!.uid,
                        );
                        ToastHelper.showSuccess('긴급모집이 종료되었습니다');
                        _loadTOsWithStats();
                      }
                      break;
                  }
                },
                itemBuilder: (context) => _buildWorkMenuItems(workStatus),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          Row(
            children: [
              Icon(Icons.access_time, size: 14, color: theme.hintColor),
              const SizedBox(width: 4),
              Text(
                work.timeRange,
                style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
              ),
              const SizedBox(width: 12),
              Icon(Icons.people, size: 14, color: theme.hintColor),
              const SizedBox(width: 4),
              Text(
                '$confirmedCount/${work.requiredCount}명',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: work.isFull ? Colors.green : Colors.orange,
                ),
              ),
              if (pendingCount > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '(+$pendingCount)',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange[600],
                  ),
                ),
              ],
              const SizedBox(width: 12),
              Icon(Icons.payments, size: 14, color: theme.hintColor),
              const SizedBox(width: 4),
              Text(
                work.formattedWage,
                style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
              ),
              // ⭐ 단기 TO인 경우만 업무별 마감 시간 표시
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
          
          const SizedBox(height: 8),
          
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: work.requiredCount > 0 
                  ? confirmedCount / work.requiredCount 
                  : 0,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                work.isFull ? Colors.green : Colors.orange,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildWorkMenuItems(String status) {
    final List<PopupMenuEntry<String>> items = [
      PopupMenuItem(
        value: 'applicants',
        child: Row(
          children: [
            Icon(Icons.people, size: 18, color: Colors.blue[600]),
            const SizedBox(width: 12),
            const Text('지원자 관리'),
          ],
        ),
      ),
    ];

    switch (status) {
      case 'TIME_EXPIRED':
      case 'CLOSED':
        items.add(
          PopupMenuItem(
            value: 'reopen',
            child: Row(
              children: [
                Icon(Icons.lock_open, size: 18, color: Colors.green[600]),
                const SizedBox(width: 12),
                const Text('재오픈'),
              ],
            ),
          ),
        );
        items.add(
          PopupMenuItem(
            value: 'emergency',
            child: Row(
              children: [
                Icon(Icons.warning_amber, size: 18, color: Colors.red[600]),
                const SizedBox(width: 12),
                const Text('긴급 모집'),
              ],
            ),
          ),
        );
        break;
      case 'EMERGENCY':
        items.add(
          PopupMenuItem(
            value: 'stopEmergency',
            child: Row(
              children: [
                Icon(Icons.stop_circle, size: 18, color: Colors.orange[600]),
                const SizedBox(width: 12),
                const Text('긴급모집 종료'),
              ],
            ),
          ),
        );
        break;
      case 'FULL':
        items.add(
          PopupMenuItem(
            value: 'close',
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: Colors.green[600]),
                const SizedBox(width: 12),
                const Text('인원충족'),
              ],
            ),
          ),
        );
        break;
      case 'ACTIVE':
        items.add(
          PopupMenuItem(
            value: 'close',
            child: Row(
              children: [
                Icon(Icons.lock, size: 18, color: Colors.red[600]),
                const SizedBox(width: 12),
                const Text('마감'),
              ],
            ),
          ),
        );
        break;
    }

    return items;
  }

  String _getWorkStatus(WorkDetailModel work, int confirmed) {
    if (work.isTimeExpired) return 'TIME_EXPIRED';
    if (work.isClosed) return 'CLOSED';
    if (work.isEmergencyOpen) return 'EMERGENCY';
    if (confirmed >= work.requiredCount) return 'FULL';
    return 'ACTIVE';
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'TIME_EXPIRED': return '마감됨';
      case 'CLOSED': return '마감됨';
      case 'EMERGENCY': return '긴급모집';
      case 'FULL': return '인원충족';
      case 'ACTIVE': return '진행중';
      default: return '알 수 없음';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'TIME_EXPIRED': return Colors.grey[600]!;
      case 'CLOSED': return Colors.grey[600]!;
      case 'EMERGENCY': return Colors.red[600]!;
      case 'FULL': return Colors.green[600]!;
      case 'ACTIVE': return Colors.blue[600]!;
      default: return Colors.grey[600]!;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'TIME_EXPIRED': return Icons.lock;
      case 'CLOSED': return Icons.lock;
      case 'EMERGENCY': return Icons.warning_amber;
      case 'FULL': return Icons.check_circle;
      case 'ACTIVE': return Icons.circle;
      default: return Icons.help;
    }
  }
  String _buildLongTermDisplay(TOModel to) {
    final period = to.startDate != null && to.endDate != null
        ? '${to.startDate!.month}/${to.startDate!.day}~${to.endDate!.month}/${to.endDate!.day}'
        : '기간 미정';
    
    final days = to.workDays != null && to.workDays!.isNotEmpty
        ? '주 ${to.workDays!.length}일 (${to.workDays!.join(",")})'
        : '요일 미정';
    
    return '$period · $days';
  }
  /// 업무별 마감시간 계산
  String _calculateDeadline(TOModel to, WorkDetailModel work) {
    final hoursBeforeStart = to.hoursBeforeStart ?? 2;
    
    final timeParts = work.startTime.split(':');
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);
    
    final deadlineHour = hour - hoursBeforeStart;
    final deadlineMinute = minute;
    
    return '${deadlineHour.toString().padLeft(2, '0')}:${deadlineMinute.toString().padLeft(2, '0')}';
  }
  /// TO 아이템 카드 (2단계 토글)
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
        color: isExpanded ? Colors.blue[50] : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isExpanded ? Colors.blue[300]! : Colors.grey[300]!,
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
                  // 첫 줄: 날짜 + 마감시간
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: to.isLongTerm 
                          ? Text(
                              _buildLongTermDisplay(to),
                              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                            )
                          : Text(
                              dateFormat.format(to.date),
                              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                            ),
                      ),
                      
                      const Spacer(),
                      
                      // 🔥 마감시간 배지
                      _buildDeadlineBadge(to),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // 둘째 줄: TO 제목 + 상태 배지 + 더보기
                  Row(
                    children: [
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
                      
                      _buildStatusBadge(toItem),
                      
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, size: 18, color: Colors.grey[600]),
                        padding: EdgeInsets.zero,
                        onSelected: (value) async {
                          switch (value) {
                            case 'edit':
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AdminEditTOScreen(to: to),
                                ),
                              );
                              _loadTOsWithStats();
                              break;
                            case 'unlink':
                              _dialogs.showRemoveFromGroupDialog(toItem);
                              break;
                            case 'confirmedList':
                              _showConfirmedListDialog(toItem);
                              break;
                            case 'manageWorkDetails':
                              _showWorkDetailManagementDialog(toItem);
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
                            value: 'unlink',
                            child: Row(
                              children: [
                                Icon(Icons.link_off, size: 18, color: Colors.red[600]),
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
                  
                  const SizedBox(height: 8),
                  
                  // 셋째 줄: 시간 + 인원 배지
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text(
                        to.displayTimeRange,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      const SizedBox(width: 12),
                      
                      if (toItem.confirmedCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green[200]!),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('✓', style: TextStyle(fontSize: 11)),
                              const SizedBox(width: 4),
                              Text(
                                '확정 ${toItem.confirmedCount}명',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (toItem.confirmedCount > 0) const SizedBox(width: 8),
                      
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

  /// 마감시간 표시 (업무별 마감 방식 반영)
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
  String _buildDeadlineDisplay(TOModel to) {
    if (to.deadlineType == 'FIXED_TIME' && to.applicationDeadline != null) {
      return '마감: ${DateFormat('MM/dd HH:mm').format(to.applicationDeadline!)}';
    } else if (to.deadlineType == 'HOURS_BEFORE' && to.hoursBeforeStart != null) {
      return '마감: 각 업무 ${to.hoursBeforeStart}시간 전';
    }
    return '마감: 미설정';
  }
}
