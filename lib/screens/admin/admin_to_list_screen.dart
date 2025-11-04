import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

// Models
import '../../models/to_model.dart';
import '../../models/work_detail_model.dart';

// Services
import '../../services/firestore_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Providers
import '../../providers/user_provider.dart';

// Utils
import '../../utils/toast_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/test_data_helper.dart';

// Widgets
import '../../widgets/loading_widget.dart';
import '../../widgets/work_type_icon.dart';

// Screens
import 'admin_create_to_screen.dart';
import 'admin_edit_to_screen.dart';

// Local Models
import 'models/to_list_models.dart';
// Local dialogs
import 'dialogs/work_detail_management_dialog.dart';
import 'dialogs/confirmed_list_dialog.dart';
import 'dialogs/filter_dialog.dart';

// Local Widgets
import 'widgets/to_list_tabs.dart';
import 'widgets/to_list_dialogs.dart';
import 'widgets/work_applicants_dialog.dart';

/// 관리자 TO 목록 화면 - 이중 토글 UI
class AdminTOListScreen extends StatefulWidget {
  const AdminTOListScreen({super.key});

  @override
  State<AdminTOListScreen> createState() => _AdminTOListScreenState();
}

class _AdminTOListScreenState extends State<AdminTOListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  late TOListDialogs _dialogs;  // 🔥 추가
  
  @override
  void initState() {
    super.initState();
    // 🔥 한 번만 초기화
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
      // ✅ 탭에 따라 다른 쿼리 실행
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
          
          // ✅ WorkDetails와 시간 범위만 조회 (통계는 TO 문서에 있음!)
          final batchResults = await Future.wait([
            _firestoreService.getWorkDetailsBatch(toIds, forceRefresh: true),
            _firestoreService.calculateGroupTimeRange(masterTO.groupId!, forceRefresh: true),
          ]);
          
          final workDetailsMap = batchResults[0] as Map<String, List<WorkDetailModel>>;
          final timeRange = batchResults[1] as Map<String, String>;
          
          // 각 TO 아이템 생성
          List<TOItem> toItems = [];
          for (var to in groupTOs) {
            final toWorkDetails = workDetailsMap[to.id] ?? [];            
            // ✅ 변경: 실제 지원서 조회해서 계산
            final apps = await _firestoreService.getApplicationsByTO(
              to.businessId,
              to.title,
              to.date,
            );

            int confirmed = apps.where((a) => a.status == 'CONFIRMED').length;
            int pending = apps.where((a) => a.status == 'PENDING').length;
            // 🔥 NEW: totalRequired 실시간 계산
            int totalRequired = 0;
            for (var work in toWorkDetails) {
              totalRequired += work.requiredCount;
            }
            
            // 🔥 WorkDetail별 통계 계산
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
              workDetailStats: workStats, // 🔥 추가!
            ));
          }
          
          // 시간 범위 설정
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
          
          // ✅ 단일 TO 시간 범위 계산
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
          
          // 🔥 지원서 조회해서 WorkDetail별 통계 계산
          final apps = await _firestoreService.getApplicationsByTO(
            masterTO.businessId,
            masterTO.title,
            masterTO.date,
          );
          
          // WorkDetail별 통계 매핑
          Map<String, Map<String, int>> workStats = {};
          for (var work in workDetails) {
            final workApps = apps.where((a) => a.selectedWorkType == work.workType);            
            workStats[work.workType] = {
              'confirmed': workApps.where((a) => a.status == 'CONFIRMED').length,
              'pending': workApps.where((a) => a.status == 'PENDING').length,
            };
          }
          // 🔥 전체 통계 계산
          int totalConfirmed = 0;
          int totalPending = 0;
          for (var stats in workStats.values) {
            totalConfirmed += stats['confirmed'] as int;
            totalPending += stats['pending'] as int;
          
          }
          // 🔥 NEW: totalRequired 실시간 계산
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
                confirmedCount: totalConfirmed,  // 🔥 수정!
                pendingCount: totalPending,      // 🔥 수정!
                totalRequired: totalRequired,
                workDetailStats: workStats, // 🔥 추가!
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
      // 4. 필터 적용
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
        // 1. 사업장 필터
        if (_selectedBusiness != null && 
            groupItem.masterTO.businessName != _selectedBusiness) {
          return false;
        }
        
        // 2. 날짜 범위 필터
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
            23, 59, 59,  // 🔥 하루의 끝까지
          );
          
          if (groupItem.isGrouped) {
            // 그룹 TO: 범위 내에 하나라도 있으면 표시
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
            // 단일 TO: 범위 내에 있어야 함
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
  
  /// 업무별 마감시간 계산
  String _calculateDeadline(TOModel to, WorkDetailModel work) {
    // TO에 설정된 hoursBeforeStart 값 사용
    final hoursBeforeStart = to.hoursBeforeStart ?? 2; // 기본값 2시간
    
    final timeParts = work.startTime.split(':');
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);
    
    // N시간 전 계산
    final deadlineHour = hour - hoursBeforeStart;
    final deadlineMinute = minute;
    
    return '${deadlineHour.toString().padLeft(2, '0')}:${deadlineMinute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TO 관리'),
        backgroundColor: Colors.blue[700],
        actions: [
          // 🔥 필터 아이콘 추가
          Stack(
            children: [
              IconButton(
                icon: Icon(
                  Icons.filter_list,
                  color: _hasActiveFilters() ? Colors.amber : Colors.white,
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
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Center(
                      child: Text(
                        '${_getActiveFilterCount()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          
          // 새로고침
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _firestoreService.clearCache();
              _loadTOsWithStats();
            },
          ),
          
          // 테스트 데이터
          PopupMenuButton<String>(
            icon: const Icon(Icons.science),
            tooltip: '테스트 데이터',
            onSelected: (value) {
              switch (value) {
                case 'create':
                  _showCreateDummyDataDialog();
                  break;
                case 'clear':
                  _showClearDummyDataDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'create',
                child: Row(
                  children: [
                    Icon(Icons.add_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('더미 데이터 생성'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, color: Colors.red),
                    SizedBox(width: 8),
                    Text('더미 데이터 삭제'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 탭
          TOListTabs(
            selectedTab: _selectedTab,
            onTabChanged: (tab) {
              setState(() {
                _selectedTab = tab;
              });
              _loadTOsWithStats();
            },
          ),
          const SizedBox(height: 8),
          
          // 🔥 필터 UI 제거!
          // TOListFilter(...),  ← 이 부분 삭제 또는 주석 처리
          
          Expanded(child: _buildTOList()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AdminCreateTOScreen(),
            ),
          );
          if (result == true) {
            _loadTOsWithStats();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('TO 생성'),
        backgroundColor: const Color(0xFF1E88E5),
        foregroundColor: Colors.white,
      ),
    );
  }

  // 🔥 필터 관련 메서드 추가
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
        selectedDateRange: _selectedDateRange,  // 🔥 DateTimeRange 전달
        businessNames: _businessNames,
        onBusinessChanged: (value) {
          setState(() {
            _selectedBusiness = value;
          });
          _applyFilters();
        },
        onDateRangeChanged: (value) {
          setState(() {
            _selectedDateRange = value;  // 🔥 DateTimeRange 저장
          });
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
      return Center(
        child: Container(
          margin: const EdgeInsets.all(40),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox, size: 80, color: Colors.blue[200]),
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

  /// ✅ 그룹 카드 (1단계 토글) - 개선 버전
  Widget _buildGroupCard(TOGroupItem groupItem) {
    final masterTO = groupItem.masterTO;
    final isExpanded = _expandedGroups.contains(masterTO.groupId ?? masterTO.id);
    final dateFormat = DateFormat('MM/dd (E)', 'ko_KR');
    // 그룹 전체 통계
    int totalConfirmed = 0;
    int totalPending = 0;
    int totalRequired = 0;
    
    for (var toItem in groupItem.groupTOs) {
      totalConfirmed += toItem.confirmedCount;
      totalPending += toItem.pendingCount;
      totalRequired += toItem.totalRequired;
    }
    
    // ✅ 모든 TO의 모든 업무가 충족되었는지 확인
    final isFull = groupItem.groupTOs.every((toItem) {
      return toItem.workDetails.every((work) {
        final stats = toItem.workDetailStats?[work.workType];
        final confirmed = stats?['confirmed'] ?? 0;
        return confirmed >= work.requiredCount;
      });
    });

    return Card(
      elevation: isExpanded ? 4 : 2,  // 🔥 펼치면 그림자 강조
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isExpanded 
              ? Colors.blue[400]!  // 🔥 펼치면 파란색
              : (isFull ? Colors.green[200]! : Colors.grey[200]!),
          width: isExpanded ? 2 : (isFull ? 2 : 1),  // 🔥 펼치면 두껍게
        ),
      ),
      child: Column(
        children: [
          // 헤더 (클릭 가능)
          InkWell(
            onTap: () {
              setState(() {
                final key = masterTO.groupId ?? masterTO.id;
                if (_expandedGroups.contains(key)) {
                  _expandedGroups.remove(key);
                  _expandedTOs.clear();  // 🔥 하위 TO들도 모두 닫기
                } else {
                  _expandedGroups.clear();  // 🔥 다른 그룹들 모두 닫기
                  _expandedTOs.clear();      // 🔥 모든 TO 닫기
                  _expandedGroups.add(key);  // 🔥 현재만 열기
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ 사업장명 + 상태 배지 (한 줄로)
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
                            const Icon(
                              Icons.business,
                              size: 14,
                              color: Colors.white,
                            ),
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
                      const SizedBox(width: 8),  // ⭐ 추가
    
                      // ⭐ 장기/단기 뱃지 추가
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
                          masterTO.jobTypeLabel,  // "단기 알바" or "1개월+ 계약직"
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: masterTO.isLongTerm ? Colors.purple[700] : Colors.blue[700],
                          ),
                        ),
                      ),
                      
                      const Spacer(),
                      
                      // ✅ 상태 배지
                      () {
                        // 🔥 모든 개별 TO가 마감됐는지 확인
                        bool allClosed = groupItem.groupTOs.every((toItem) {
                          return toItem.workDetails.every((work) => 
                            work.isClosed || work.isTimeExpired || work.isFull
                          );
                        });
                        
                        if (allClosed) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[600]!, width: 1.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock, size: 12, color: Colors.grey[700]),
                                const SizedBox(width: 4),
                                Text(
                                  '마감됨',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          );
                        } else if (isFull) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green[600]!, width: 1.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, size: 12, color: Colors.green[600]),
                                const SizedBox(width: 4),
                                Text(
                                  '인원충족',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[700],
                                  ),
                                ),
                              ],
                            ),
                          );
                        } else {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue[600]!, width: 1.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, size: 12, color: Colors.blue[600]),
                                const SizedBox(width: 4),
                                Text(
                                  '진행중',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                      }(),
                    ],
                  ),
                  const SizedBox(height: 10),
                  
                  // ✅ 그룹명 + 버튼들 (두 번째 줄)
                  Row(
                    children: [
                      // ✅ 그룹명 (그룹 TO일 때만 표시)
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
                              Icon(
                                Icons.folder_open,
                                size: 16,
                                color: Colors.green[700],
                              ),
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
                      
                      // ✅ 단일 TO: 파란 박스
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
                      
                      // ✅ 단일 TO인 경우
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
                                print('🔍 수정 결과: $result');
                                if (result == true) {
                                  print('🔄 재로딩 시작');
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
                                _allGroupItems,  // 🔥 추가!
                              );
                              break;
                            case 'confirmedList':  // 🔥 'detail' → 'confirmedList'로 변경!
                              _showConfirmedListDialog(groupItem.groupTOs.first);
                              break;
                            case 'manageWorkDetails':  // 🔥 추가!
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
                            value: 'confirmedList',  // 🔥 변경!
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_outline, size: 18, color: Colors.green[600]),  // 🔥 변경!
                                const SizedBox(width: 12),
                                const Text('확정명단'),  // 🔥 변경!
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'manageWorkDetails',  // 🔥 추가!
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
                      
                    // ✅ 그룹 TO용 더보기 메뉴
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
                            case 'closeGroup':  // ✅ 추가
                              _dialogs.showCloseGroupDialog(groupItem);
                              break;
                            case 'reopenGroup':  // ✅ 추가
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
                          // ✅ Phase 4: 그룹 마감/재오픈
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

                    // ✅ 토글 아이콘
                    Icon(
                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                  
                  // ✅ 단일 TO 제목은 별도 줄에 (배지 아래)
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
                  
                  // ✅ 날짜 및 시간 정보
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: masterTO.isLongTerm
                          ? Column(  // ⭐ 장기 TO는 2줄
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  masterTO.longTermPeriodWithDays,  // "1/7 ~ 2/7"
                                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                                ),
                                if (masterTO.workDays != null && masterTO.workDays!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    masterTO.workDaysLabel,  // "주 3일 (월, 수, 금)"
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
                      // 🔥 단일 TO인 경우 마감시간 추가!
                      if (!groupItem.isGrouped) ...[
                        const Spacer(),
                        _buildDeadlineBadge(masterTO),
                      ],
                    ],
 
                  ),
                  const SizedBox(height: 12),
                  
                    // 통계
                  Row(
                    children: [  
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isFull ? Colors.green[50] : Colors.blue[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isFull ? Colors.green[200]! : Colors.blue[200]!,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('👥', style: TextStyle(fontSize: 11)),
                              SizedBox(width: 4),
                              Text(
                                '확정 $totalConfirmed/$totalRequired명',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isFull ? Colors.green[700] : Colors.blue[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 8),

                        // 대기
                      if (totalPending > 0)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange[200]!),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('⏳', style: TextStyle(fontSize: 11)),
                              SizedBox(width: 4),
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
          
          // ✅ 펼쳐진 경우: 연결된 TO 목록 (그룹 TO)
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
          
          // ✅ 펼쳐진 경우: 업무 상세 (단일 TO)
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
                  
                  // 🔥 FutureBuilder 제거! 바로 표시
                  ...groupItem.groupTOs.first.workDetails.map((work) {
                    final stats = groupItem.groupTOs.first.workDetailStats?[work.workType];
                    final confirmed = stats?['confirmed'] ?? 0;
                    final pending = stats?['pending'] ?? 0;
                    print('🔍 [UI] ${work.workType}: stats=$stats, 확정=$confirmed, 대기=$pending'); // 🔥 로그 추가
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

  /// ✅ TO 아이템 카드 (2단계 토글 - 개선 버전)
  Widget _buildTOItemCard(TOItem toItem, TOGroupItem groupItem) {
    final to = toItem.to;
    final isExpanded = _expandedTOs.contains(to.id);
    final dateFormat = DateFormat('MM/dd (E)', 'ko_KR');
    // ✅ 수정
    final isFull = toItem.workDetails.every((work) {
      final stats = toItem.workDetailStats?[work.workType];
      final confirmed = stats?['confirmed'] ?? 0;
      return confirmed >= work.requiredCount;
    });

    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 12),  // 🔥 들여쓰기
      decoration: BoxDecoration(
        color: isExpanded ? Colors.blue[50] : Colors.grey[50],  // 🔥 펼치면 파란 배경
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isExpanded ? Colors.blue[300]! : Colors.grey[300]!,  // 🔥 펼치면 파란 테두리
          width: isExpanded ? 2 : 1,  // 🔥 두껍게
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
                  _expandedTOs.clear();     // 🔥 다른 TO들 모두 닫기
                  _expandedTOs.add(to.id);  // 🔥 현재만 열기
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ 첫 줄: 날짜 + TO 제목 + 상태 배지
                  Row(
                    children: [
                      // 날짜
                      Text(
                        dateFormat.format(to.date),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(width: 12),
                      
                      // TO 제목 (확장)
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
                      
                      // ✅ 상태 배지 (WorkDetail 기반으로 계산)
                    () {
                      // 🔥 모든 WorkDetail이 마감됐는지 확인
                      final allWorksClosed = toItem.workDetails.every((work) => 
                        work.isClosed || work.isTimeExpired || work.isFull
                      );
                      
                      Color bgColor;
                      Color borderColor;
                      Color textColor;
                      IconData icon;
                      String text;
                      
                      if (allWorksClosed) {
                        // 마감됨
                        bgColor = Colors.grey[300]!;
                        borderColor = Colors.grey[600]!;
                        textColor = Colors.grey[700]!;
                        icon = Icons.lock;
                        text = '마감됨';
                      } else if (isFull) {
                        // 인원충족
                        bgColor = Colors.green[50]!;
                        borderColor = Colors.green[600]!;
                        textColor = Colors.green[700]!;
                        icon = Icons.check_circle;
                        text = '인원충족';
                      } else {
                        // 진행중
                        bgColor = Colors.blue[50]!;
                        borderColor = Colors.blue[600]!;
                        textColor = Colors.blue[700]!;
                        icon = Icons.circle;
                        text = '진행중';
                      }
                      
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: borderColor, width: 1.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 10, color: textColor),
                            const SizedBox(width: 3),
                            Text(
                              text,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    }(),
                    ],
                  ),
                  const SizedBox(height: 8),
                
                  // 🔥 둘째 줄: 날짜 + 마감시간 (한 줄로!)
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: to.isLongTerm 
                          ? Column(  // ⭐ 장기 TO는 2줄
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
                      
                      // 🔥 마감시간 배지
                      _buildDeadlineBadge(to),
                    ],
                  ),
                  
                  // ✅ 셋째 줄: 통계 + 더보기 메뉴
                  Row(
                    children: [
                      // 통계
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: toItem.confirmedCount >= toItem.totalRequired ? Colors.green[50] : Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: toItem.confirmedCount >= toItem.totalRequired ? Colors.green[200]! : Colors.blue[200]!,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('👥', style: TextStyle(fontSize: 11)),
                            SizedBox(width: 4),
                            Text(
                              '확정 ${toItem.confirmedCount}/${toItem.totalRequired}명',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: toItem.confirmedCount >= toItem.totalRequired ? Colors.green[700] : Colors.blue[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 8),

                      // 대기
                      if (toItem.pendingCount > 0)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange[200]!),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('⏳', style: TextStyle(fontSize: 11)),
                              SizedBox(width: 4),
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
                      
                      // ✅ 더보기 메뉴
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
                            case 'confirmedList':  // 🔥 'detail' → 'confirmedList'로 변경!
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
                                SizedBox(width: 12),
                                Text('수정'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 18, color: Colors.red[700]),
                                SizedBox(width: 12),
                                Text('삭제'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'unlink',
                            child: Row(
                              children: [
                                Icon(Icons.link_off, size: 18, color: Colors.orange[700]),
                                SizedBox(width: 12),
                                Text('그룹 해제'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'confirmedList',
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_outline, size: 18, color: Colors.green[600]),  // 🔥 변경!
                                const SizedBox(width: 12),
                                Text('확정명단'),
                              ],
                            ),
                          ),
                          // 🔥 NEW: 업무별 마감
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
                      
                      // 펼치기/접기 아이콘
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
          
          // ✅ 펼쳐진 경우: 업무 상세
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
                  
                  // 🔥 FutureBuilder 제거!
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

  Widget _buildWorkDetailRow(WorkDetailModel work, int confirmedCount, int pendingCount, TOItem toItem) {  // 🔥 toItem 추가!
    final workStatus = _getWorkStatus(work, confirmedCount);
    
    return Container(
      margin: EdgeInsets.only(bottom: 8, left: 24),  // 🔥 더 깊은 들여쓰기
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔥 1줄: 업무명 + 더보기 버튼
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: FormatHelper.parseColor(work.workTypeColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: WorkTypeIcon.buildFromString(
                    work.workTypeIcon,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  work.workType,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              
              // 🔥 더보기 버튼 추가!
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[600]),
                padding: EdgeInsets.zero,
                onSelected: (value) => _handleWorkDetailMenu(value, work, toItem),
                itemBuilder: (context) {
                  // 🔥 현재 상태 확인
                  final isClosed = work.isClosed;
                  final isTimeExpired = work.isTimeExpired;
                  final isEmergencyOpen = work.isEmergencyOpen;
                  
                  return [
                    // 지원자 관리 (항상 표시)
                    PopupMenuItem(
                      value: 'manage',
                      child: Row(
                        children: [
                          Icon(Icons.people, size: 18, color: Colors.blue[700]),
                          SizedBox(width: 8),
                          Text('지원자 관리'),
                        ],
                      ),
                    ),
                    
                    PopupMenuDivider(),
                    
                    // 🔥 마감/재오픈 (조건부)
                    if (isTimeExpired)
                      // 시간 만료: 재오픈 불가
                      PopupMenuItem(
                        enabled: false,
                        value: 'expired',
                        child: Row(
                          children: [
                            Icon(Icons.schedule, size: 18, color: Colors.grey[400]),
                            SizedBox(width: 8),
                            Text(
                              '시간 만료됨',
                              style: TextStyle(color: Colors.grey[400]),
                            ),
                          ],
                        ),
                      )
                    else if (isClosed)
                      // 수동 마감: 재오픈 가능
                      PopupMenuItem(
                        value: 'reopen',
                        child: Row(
                          children: [
                            Icon(Icons.lock_open, size: 18, color: Colors.green[700]),
                            SizedBox(width: 8),
                            Text('업무 재오픈'),
                          ],
                        ),
                      )
                    else
                      // 진행중: 마감 가능
                      PopupMenuItem(
                        value: 'close',
                        child: Row(
                          children: [
                            Icon(Icons.block, size: 18, color: Colors.red[700]),
                            SizedBox(width: 8),
                            Text('업무 마감'),
                          ],
                        ),
                      ),
                    
                    // 🔥 긴급모집 (진행중이고 마감 안 된 경우만)
                    if (!isClosed && !isTimeExpired) ...[
                      PopupMenuDivider(),
                      
                      if (!isEmergencyOpen)
                        PopupMenuItem(
                          value: 'emergency_start',
                          child: Row(
                            children: [
                              Icon(Icons.warning, size: 18, color: Colors.orange[700]),
                              SizedBox(width: 8),
                              Text('긴급 모집 시작'),
                            ],
                          ),
                        )
                      else
                        PopupMenuItem(
                          value: 'emergency_stop',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, size: 18, color: Colors.green[700]),
                              SizedBox(width: 8),
                              Text('긴급 모집 종료'),
                            ],
                          ),
                        ),
                    ],
                  ];
                },
              ),
            ],
          ),
          SizedBox(height: 8),
          
          // 🔥 2줄: 시간 + 금액
          Row(
            children: [
              Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
              SizedBox(width: 4),
              Text(
                '${work.startTime}~${work.endTime}',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              SizedBox(width: 12),
              Icon(Icons.payments, size: 14, color: Colors.grey[600]),
              SizedBox(width: 4),
              Text(
                '${NumberFormat('#,###').format(work.wage)}원',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[700],
                ),
              ),
              Spacer(),  // 🔥 추가: 오른쪽 정렬
                  Icon(Icons.alarm, size: 13, color: Colors.orange[600]),  // 🔥 추가
                  SizedBox(width: 4),  // 🔥 추가
                  Text(  // 🔥 추가
                    '마감: ${_calculateDeadline(toItem.to, work)}까지',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[700],
                    ),
                  ),
                ],
              ),
          SizedBox(height: 6),
          
          // 🔥 3줄: 인원 + 대기 + 상태
          Row(
            children: [
              // 확정 인원
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: work.isFull ? Colors.green[50] : Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: work.isFull ? Colors.green[200]! : Colors.blue[200]!,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '👥',
                      style: TextStyle(fontSize: 11),
                    ),
                    SizedBox(width: 4),
                    Text(
                      '확정 $confirmedCount/${work.requiredCount}명',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: work.isFull ? Colors.green[700] : Colors.blue[700],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              
              // 대기 인원
              if (pendingCount > 0)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('⏳', style: TextStyle(fontSize: 11)),
                      SizedBox(width: 4),
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
              
              Spacer(),
              
              // 상태 배지
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: workStatus['color'],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  workStatus['label'],
                  style: TextStyle(
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
  // 🔥 업무별 메뉴 핸들러 (새로 추가)
  Future<void> _handleWorkDetailMenu(String value, WorkDetailModel work, TOItem toItem) async {
    switch (value) {
      case 'manage':
        await _showWorkApplicantsDialog(work, toItem);  // 🔥 다이얼로그로 변경!
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
          
          _loadTOsWithStats();  // 🔥 새로고침
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
  // 🔥 다이얼로그 표시 함수
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

  // 🔥 업무 마감
  Future<void> _closeWork(WorkDetailModel work, TOItem toItem) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${work.workType} 마감'),
        content: Text('이 업무를 마감하시겠습니까?\n마감 후에도 재오픈할 수 있습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('마감'),
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

  /// 확정 명단 다이얼로그  // 🔥 여기에 추가!
  void _showConfirmedListDialog(TOItem toItem) {
    ConfirmedListDialog(
      context: context,
      toItem: toItem,
      firestoreService: _firestoreService,
    ).show();
  }



  // 🔥 긴급 모집 시작
  Future<void> _startEmergency(WorkDetailModel work, TOItem toItem) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('🚨 긴급 모집'),
        content: Text('${work.workType} 긴급 모집을 시작하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text('시작'),
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

  // 🔥 긴급 모집 종료
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
    // 🔥 1순위: 시간 초과 체크
    if (work.isTimeExpired) {
      return {
        'label': '마감됨',
        'color': Colors.grey[600],
      };
    }
    
    // 🔥 2순위: 수동 마감 체크
    if (work.isClosed) {
      return {
        'label': '마감됨',
        'color': Colors.grey[600],
      };
    }
    
    // 🔥 3순위: 긴급 모집 체크
    if (work.isEmergencyOpen) {
      return {
        'label': '긴급모집',
        'color': Colors.red[600],
      };
    }
    
    // 🔥 4순위: 인원 충족 체크
    if (confirmedCount >= work.requiredCount) {
      return {
        'label': '인원충족',
        'color': Colors.green[600],
      };
    }
    
    // 🔥 기본: 진행중
    return {
      'label': '진행중',
      'color': Colors.blue[600],
    };
  }

  Future<void> _showCreateDummyDataDialog() async {
    // TO 선택
    if (_filteredGroupItems.isEmpty) {
      ToastHelper.showError('생성된 TO가 없습니다');
      return;
    }

    // ✅ 모든 TO를 평면화 (그룹 TO + 단일 TO)
    List<TOModel> allTOs = [];
    for (var groupItem in _filteredGroupItems) {
      if (groupItem.isGrouped) {
        // 그룹 TO: 내부의 모든 TO 추가
        for (var toItem in groupItem.groupTOs) {
          allTOs.add(toItem.to);
        }
      } else {
        // 단일 TO: 바로 추가
        allTOs.add(groupItem.masterTO);
      }
    }

    // 날짜순 정렬
    allTOs.sort((a, b) => a.date.compareTo(b.date));

    final selectedTO = await showDialog<TOModel>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('TO 선택'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allTOs.length,
            itemBuilder: (context, index) {
              final to = allTOs[index];
              
              // ✅ 그룹 TO인지 단일 TO인지 표시
              final badge = to.groupName != null
                  ? '[${to.groupName}]'
                  : '[단일 공고]';
              
              return ListTile(
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        to.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: to.groupName != null ? Colors.green[50] : Colors.blue[50],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: to.groupName != null ? Colors.green[300]! : Colors.blue[300]!,
                        ),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 10,
                          color: to.groupName != null ? Colors.green[700] : Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  '${DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(to.date)} | ${to.businessName}',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.pop(context, to),
              );
            },
          ),
        ),
      ),
    );

    if (selectedTO == null) return;

    // 인원 입력
    final TextEditingController pendingController = TextEditingController(text: '3');
    final TextEditingController confirmedController = TextEditingController(text: '2');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('더미 지원자 생성'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('TO: ${selectedTO.title}'),
            const SizedBox(height: 16),
            TextField(
              controller: pendingController,
              decoration: const InputDecoration(
                labelText: '대기 인원',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmedController,
              decoration: const InputDecoration(
                labelText: '확정 인원',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('생성'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 생성 실행
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('더미 데이터 생성 중...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await TestDataHelper.createDummyApplications(
        toId: selectedTO.id,
        workTypes: [],
        pendingCount: int.parse(pendingController.text),
        confirmedCount: int.parse(confirmedController.text),
      );

      if (mounted) {
        Navigator.pop(context);
      }

      ToastHelper.showSuccess('더미 데이터 생성 완료!');
      _loadTOsWithStats();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
      print('❌ 더미 데이터 생성 실패: $e');
      ToastHelper.showError('생성 실패: $e');
    }
  }

  /// 더미 데이터 삭제 다이얼로그
  Future<void> _showClearDummyDataDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('더미 데이터 삭제'),
        content: const Text(
          '모든 더미 지원자와 지원서를 삭제하시겠습니까?\n\n'
          '이 작업은 되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('더미 데이터 삭제 중...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await TestDataHelper.clearAllDummyData();

      if (mounted) {
        Navigator.pop(context);
      }

      ToastHelper.showSuccess('더미 데이터 삭제 완료!');
      await _loadTOsWithStats();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
      print('❌ 더미 데이터 삭제 실패: $e');
      ToastHelper.showError('삭제 실패: $e');
    }
  }
  /// 마감시간 표시 (업무별 마감 방식 반영)
  Widget _buildDeadlineBadge(TOModel to) {
    // ⭐ FIXED_TIME 방식 (장기 근무)
    if (to.deadlineType == 'FIXED_TIME') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          border: Border.all(color: Colors.orange[300]!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🕐', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 4),
            Text(
              DateFormat('MM/dd HH:mm').format(to.applicationDeadline),
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange[700],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    
    // ⭐ HOURS_BEFORE 방식 (단기 알바)
    if (to.deadlineType == 'HOURS_BEFORE' && to.hoursBeforeStart != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          border: Border.all(color: Colors.orange[300]!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🕐', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 4),
            Text(
              '각 업무 ${to.hoursBeforeStart}시간 전',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange[700],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    
    // 마감시간이 없는 경우
    return const SizedBox.shrink();
  }


}
