import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/to_model.dart';
import '../../models/work_detail_model.dart';
import '../../models/application_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/toast_helper.dart';
import 'admin_to_detail_screen.dart';
import 'admin_create_to_screen.dart';
import 'admin_edit_to_screen.dart';
import '../../utils/format_helper.dart';
import '../../widgets/work_type_icon.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';

import '../../utils/test_data_helper.dart';

/// 관리자 TO 목록 화면 - 이중 토글 UI
class AdminTOListScreen extends StatefulWidget {
  const AdminTOListScreen({Key? key}) : super(key: key);

  @override
  State<AdminTOListScreen> createState() => _AdminTOListScreenState();
}

class _AdminTOListScreenState extends State<AdminTOListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  
  // 필터 상태
  DateTime? _selectedDate;
  String _selectedBusiness = 'ALL';
  
  // TO 목록 + 통계
  List<_TOGroupItem> _allGroupItems = [];
  List<_TOGroupItem> _filteredGroupItems = [];
  bool _isLoading = true;
  // ✅ Phase 4: 탭 상태
  String _selectedTab = 'ACTIVE'; // 'ACTIVE' or 'CLOSED'

  // 사업장 목록
  List<String> _businessNames = [];
  
  // ✅ 이중 토글 상태 관리
  final Set<String> _expandedGroups = {}; // 펼쳐진 그룹 ID
  final Set<String> _expandedTOs = {}; // 펼쳐진 TO ID
  
  @override
  void initState() {
    super.initState();
    _loadTOsWithStats();
  }

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
        print('✅ 진행중 TO 조회: ${masterTOs.length}개');
      } else {
        masterTOs = await _firestoreService.getClosedTOs();
        print('✅ 마감된 TO 조회: ${masterTOs.length}개');
      }

      // 2. 각 TO별 처리
      List<_TOGroupItem> groupItems = [];
      
      for (var masterTO in masterTOs) {
        // 그룹 TO인 경우
        if (masterTO.isGrouped && masterTO.groupId != null) {
          // 같은 그룹의 모든 TO 조회
          final groupTOs = await _firestoreService.getTOsByGroup(masterTO.groupId!);
          final toIds = groupTOs.map((to) => to.id).toList();
          
          // ✅ WorkDetails와 시간 범위만 조회 (통계는 TO 문서에 있음!)
          final batchResults = await Future.wait([
            _firestoreService.getWorkDetailsBatch(toIds),
            _firestoreService.calculateGroupTimeRange(masterTO.groupId!),
          ]);
          
          final workDetailsMap = batchResults[0] as Map<String, List<WorkDetailModel>>;
          final timeRange = batchResults[1] as Map<String, String>;
          
          // 각 TO 아이템 생성
          List<_TOItem> toItems = [];
          for (var to in groupTOs) {
            final toWorkDetails = workDetailsMap[to.id] ?? [];
            
            // ✅ TO 문서의 통계 필드 직접 사용 (지원자 조회 불필요!)
            toItems.add(_TOItem(
              to: to,
              workDetails: toWorkDetails,
              confirmedCount: to.totalConfirmed,
              pendingCount: to.totalPending,
            ));
          }
          
          // 시간 범위 설정
          masterTO.setTimeRange(timeRange['minStart']!, timeRange['maxEnd']!);
          
          groupItems.add(_TOGroupItem(
            masterTO: masterTO,
            groupTOs: toItems,
            isGrouped: true,
          ));
          
        } else {
          // 단일 TO인 경우
          final workDetails = await _firestoreService.getWorkDetails(masterTO.id);
          
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
          
          // ✅ 단일 TO 아이템 생성 (통계 필드 사용)
          groupItems.add(_TOGroupItem(
            masterTO: masterTO,
            groupTOs: [
              _TOItem(
                to: masterTO,
                workDetails: workDetails,
                confirmedCount: masterTO.totalConfirmed,
                pendingCount: masterTO.totalPending,
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
        _filteredGroupItems = groupItems;
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

  /// 필터 적용
  void _applyFilters() {
    List<_TOGroupItem> filtered = _allGroupItems;

    // 1. 날짜 필터
    if (_selectedDate != null) {
      filtered = filtered.where((item) {
        final masterDate = DateTime(
          item.masterTO.date.year,
          item.masterTO.date.month,
          item.masterTO.date.day,
        );
        final selectedDate = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
        );
        return masterDate == selectedDate;
      }).toList();
    }

    // 2. 사업장 필터
    if (_selectedBusiness != 'ALL') {
      filtered = filtered.where((item) {
        return item.masterTO.businessName == _selectedBusiness;
      }).toList();
    }

    setState(() {
      _filteredGroupItems = filtered;
    });
  }

  /// 날짜 선택
  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _applyFilters();
      });
    }
  }
  /// 그룹명 수정 다이얼로그
  Future<void> _showEditGroupNameDialog(TOModel to) async {
    if (to.groupId == null || to.groupName == null) return;

    final controller = TextEditingController(text: to.groupName);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit, color: Colors.blue),
            SizedBox(width: 12),
            Text('그룹명 수정'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '그룹에 속한 모든 TO의 이름이 변경됩니다',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: '새 그룹명',
                hintText: '예: 4주차 파트타임 모음',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isEmpty) {
                ToastHelper.showError('그룹명을 입력하세요');
                return;
              }
              Navigator.pop(context, newName);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      // 그룹명 업데이트
      final success = await _firestoreService.updateGroupName(to.groupId!, result);
      if (success) {
        _loadTOsWithStats(); // 목록 새로고침
      }
    }

    controller.dispose();
  }
  /// TO 삭제 다이얼로그
  Future<void> _showDeleteTODialog(_TOItem toItem) async {
    final to = toItem.to;
    
    // 1. 지원자 체크
    final checkResult = await _firestoreService.checkTOBeforeDelete(to.id);
    final hasApplicants = checkResult['hasApplicants'] as bool;
    final confirmedCount = checkResult['confirmedCount'] as int;
    final totalCount = checkResult['totalCount'] as int;
    
    // 2. 그룹 정보 확인
    final isGroupTO = to.groupId != null;
    final isMasterTO = to.isGroupMaster;
    
    String title = 'TO 삭제 확인';
    String content = '';
    
    if (isGroupTO) {
      if (isMasterTO) {
        title = '⚠️ 대표 TO 삭제';
        content = '그룹: "${to.groupName}"의\n대표 TO를 삭제하시겠습니까?\n\n📋 ${DateFormat('MM/dd (E)', 'ko_KR').format(to.date)} ${to.title}\n\n⚠️ 다음 TO가 새로운 대표가 됩니다.\n✅ 그룹은 유지됩니다';
      } else {
        title = '⚠️ TO 삭제 확인';
        content = '그룹: "${to.groupName}"에서\n다음 TO를 삭제하시겠습니까?\n\n📋 ${DateFormat('MM/dd (E)', 'ko_KR').format(to.date)} ${to.title}\n\n✅ 그룹은 유지됩니다\n✅ 다른 TO는 영향 없음';
      }
    } else {
      content = '다음 TO를 삭제하시겠습니까?\n\n📋 ${DateFormat('MM/dd (E)', 'ko_KR').format(to.date)} ${to.title}';
    }
    
    if (hasApplicants) {
      content += '\n\n👤 지원자: $totalCount명 (확정 $confirmedCount명)';
      if (confirmedCount > 0) {
        content += '\n⚠️ 확정된 지원자가 있습니다!';
      }
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final success = await _firestoreService.deleteTO(to.id);
      if (success) {
        _loadTOsWithStats();
      }
    }
  }

  /// 그룹 전체 삭제 다이얼로그
  Future<void> _showDeleteGroupDialog(_TOGroupItem groupItem) async {
    final masterTO = groupItem.masterTO;
    
    // 전체 지원자 수 계산
    int totalApplicants = 0;
    for (var toItem in groupItem.groupTOs) {
      totalApplicants += toItem.confirmedCount + toItem.pendingCount;
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 그룹 전체 삭제'),
        content: Text(
          '다음 그룹을 전체 삭제하시겠습니까?\n\n'
          '🔗 ${masterTO.groupName}\n\n'
          '포함된 TO: ${groupItem.groupTOs.length}개\n'
          '⚠️ 총 ${totalApplicants}명의 지원자가 영향받습니다\n'
          '⚠️ 이 작업은 되돌릴 수 없습니다'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('전체 삭제'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final success = await _firestoreService.deleteGroupTOs(masterTO.groupId!);
      if (success) {
        _loadTOsWithStats();
      }
    }
  }
  /// 그룹 해제 다이얼로그
  Future<void> _showRemoveFromGroupDialog(_TOItem toItem) async {
    final to = toItem.to;
    
    if (to.groupId == null) {
      ToastHelper.showError('그룹 TO가 아닙니다.');
      return;
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link_off, color: Colors.orange),
            SizedBox(width: 12),
            Text('그룹 해제'),
          ],
        ),
        content: Text(
          '그룹: "${to.groupName}"에서\n다음 TO를 해제하시겠습니까?\n\n'
          '📋 ${DateFormat('MM/dd (E)', 'ko_KR').format(to.date)} ${to.title}\n\n'
          '✅ 독립 TO로 전환됩니다\n'
          '✅ 다른 그룹으로 재연결 가능\n'
          '✅ 지원자 정보는 유지됩니다'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('해제'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final success = await _firestoreService.removeFromGroup(to.id);
      if (success) {
        _loadTOsWithStats();
      }
    }
  }
  /// 그룹 연결 다이얼로그 (기존 그룹 또는 새 그룹 생성)
  Future<void> _showReconnectToGroupDialog(_TOItem toItem) async {
    final to = toItem.to;
    
    // 현재 그룹 제외한 다른 그룹 목록 가져오기
    // ✅ 동일 사업장의 그룹만 가져오기
    final allGroups = _allGroupItems
        .where((item) => 
            item.isGrouped && 
            item.masterTO.groupId != to.groupId &&
            item.masterTO.businessId == to.businessId  // 동일 사업장만!
        )
        .toList();
    
    String? selectedOption = 'existing'; // 'existing' or 'new'
    String? selectedGroupId;
    final newGroupNameController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.link, color: Colors.blue),
              SizedBox(width: 12),
              Text('그룹 연결'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '다음 TO를 그룹에 연결합니다:\n\n'
                  '📋 ${DateFormat('MM/dd (E)', 'ko_KR').format(to.date)} ${to.title}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 20),
                
                // 옵션 1: 기존 그룹에 연결
                RadioListTile<String>(
                  title: const Text('기존 그룹에 연결'),
                  value: 'existing',
                  groupValue: selectedOption,
                  onChanged: allGroups.isEmpty ? null : (value) {
                    setState(() => selectedOption = value);
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                
                if (selectedOption == 'existing') ...[
                  const SizedBox(height: 8),
                  if (allGroups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        '연결 가능한 그룹이 없습니다',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: DropdownButtonFormField<String>(
                        value: selectedGroupId,
                        decoration: const InputDecoration(
                          labelText: '그룹 선택',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: allGroups.map((item) {
                          final master = item.masterTO;
                          return DropdownMenuItem(
                            value: master.groupId,
                            child: Text(
                              '${master.groupName} (${master.businessName})',
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => selectedGroupId = value);
                        },
                      ),
                    ),
                ],
                
                const SizedBox(height: 16),
                
                // 옵션 2: 새 그룹 생성
                RadioListTile<String>(
                  title: const Text('새 그룹 생성'),
                  value: 'new',
                  groupValue: selectedOption,
                  onChanged: (value) {
                    setState(() => selectedOption = value);
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                
                if (selectedOption == 'new') ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: newGroupNameController,
                        decoration: const InputDecoration(
                          labelText: '새 그룹명',
                          hintText: '예: 11월 1주차 모음',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '이 TO가 새 그룹의 대표가 됩니다.\n나중에 다른 TO를 이 그룹에 추가할 수 있습니다.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[700],
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedOption == 'existing' && selectedGroupId == null) {
                  ToastHelper.showError('그룹을 선택하세요');
                  return;
                }
                if (selectedOption == 'new' && newGroupNameController.text.trim().isEmpty) {
                  ToastHelper.showError('그룹명을 입력하세요');
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('연결'),
            ),
          ],
        ),
      ),
    );
    
    if (confirmed == true) {
      bool success = false;
      
      if (selectedOption == 'existing' && selectedGroupId != null) {
        // 기존 그룹에 연결
        success = await _firestoreService.reconnectToGroup(
          toId: to.id,
          targetGroupId: selectedGroupId!,
        );
      } else if (selectedOption == 'new') {
        // 새 그룹 생성
        final groupName = newGroupNameController.text.trim();
        success = await _firestoreService.createNewGroupFromTO(
          toId: to.id,
          groupName: groupName,
        );
      }
      
      if (success) {
        _loadTOsWithStats();
      }
    }
    
    newGroupNameController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TO 관리'),
        backgroundColor: Colors.blue[700],
        actions: [
          // ✅ 테스트 데이터 생성 버튼ㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡ
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
          // ✅ 테스트 데이터 생성 버튼끝ㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡ
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTOsWithStats,
          ),
        ],
      ),
      body: Column(
        children: [
          // ✅ Phase 4: 탭 추가
          _buildTabs(),
          const SizedBox(height: 8),
          
          _buildFilterSection(),
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
        backgroundColor: const Color(0xFF1E88E5),  // ✅ 변경
        foregroundColor: Colors.white,
      ),
    );
  }

  /// 필터 섹션
  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 날짜 필터
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _selectDate,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    _selectedDate != null
                        ? DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(_selectedDate!)
                        : '날짜 선택',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
              if (_selectedDate != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _selectedDate = null;
                      _applyFilters();
                    });
                  },
                  icon: const Icon(Icons.clear),
                  tooltip: '날짜 필터 해제',
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          
          // 사업장 필터
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildBusinessFilterChip('전체', 'ALL'),
                const SizedBox(width: 8),
                ..._businessNames.map((name) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildBusinessFilterChip(name, name),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessFilterChip(String label, String value) {
    final isSelected = _selectedBusiness == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _selectedBusiness = value;
          _applyFilters();
        });
      },
      backgroundColor: Colors.white,
      selectedColor: Colors.blue[100],
      checkmarkColor: Colors.blue[700],
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue[900] : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? Colors.blue[700]! : Colors.grey[300]!,
        width: isSelected ? 2 : 1,
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
  Widget _buildGroupCard(_TOGroupItem groupItem) {
    final masterTO = groupItem.masterTO;
    final isExpanded = _expandedGroups.contains(masterTO.groupId ?? masterTO.id);
    final dateFormat = DateFormat('yyyy-MM-dd (E)', 'ko_KR');
    
    // 그룹 전체 통계
    int totalConfirmed = 0;
    int totalPending = 0;
    int totalRequired = 0;
    
    for (var toItem in groupItem.groupTOs) {
      totalConfirmed += toItem.confirmedCount;
      totalPending += toItem.pendingCount;
      totalRequired += toItem.to.totalRequired;
    }
    
    final isFull = totalConfirmed >= totalRequired;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isFull ? Colors.green[200]! : Colors.grey[200]!,
          width: isFull ? 2 : 1,
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
                } else {
                  _expandedGroups.add(key);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ 사업장명 (첫 줄)
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
                        Flexible(
                          child: Text(
                            masterTO.businessName,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
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
                        onSelected: (value) {
                          switch (value) {
                            case 'edit':
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AdminEditTOScreen(to: masterTO),
                                ),
                              ).then((result) {
                                if (result == true) _loadTOsWithStats();
                              });
                              break;
                            case 'delete':
                              _showDeleteTODialog(groupItem.groupTOs.first);
                              break;
                            case 'link':
                              _showReconnectToGroupDialog(groupItem.groupTOs.first);
                              break;
                            case 'detail':
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AdminTODetailScreen(to: masterTO),
                                ),
                              );
                              break;
                            case 'close':  // ✅ 추가
                              _showCloseTODialog(masterTO);
                              break;
                            case 'reopen':  // ✅ 추가
                              _showReopenTODialog(masterTO);
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
                                const Text('TO 수정'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 18, color: Colors.red[600]),
                                const SizedBox(width: 12),
                                const Text('TO 삭제'),
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
                            value: 'detail',
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, size: 18, color: Colors.purple[600]),
                                const SizedBox(width: 12),
                                const Text('지원자 관리'),
                              ],
                            ),
                          ),
                          // ✅ Phase 4: 마감/재오픈 추가
                          PopupMenuItem(
                            value: masterTO.isClosed ? 'reopen' : 'close',
                            child: Row(
                              children: [
                                Icon(
                                  masterTO.isClosed ? Icons.lock_open : Icons.lock,
                                  size: 18,
                                  color: masterTO.isClosed ? Colors.green[600] : Colors.orange[600],
                                ),
                                const SizedBox(width: 12),
                                Text(masterTO.isClosed ? 'TO 재오픈' : 'TO 마감'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    // ✅ Phase 4: 마감 배지
                    if (masterTO.isClosed) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Color(masterTO.closedReasonColor).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Color(masterTO.closedReasonColor)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock, size: 14, color: Color(masterTO.closedReasonColor)),
                            const SizedBox(width: 4),
                            Text(
                              masterTO.closedReason,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(masterTO.closedReasonColor),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                      
                    // ✅ 그룹 TO용 더보기 메뉴
                    if (groupItem.isGrouped && masterTO.groupId != null) ...[
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[700]),
                        padding: EdgeInsets.zero,
                        tooltip: '메뉴',
                        onSelected: (value) {
                          switch (value) {
                            case 'editGroupName':
                              _showEditGroupNameDialog(masterTO);
                              break;
                            case 'closeGroup':  // ✅ 추가
                              _showCloseGroupDialog(groupItem);
                              break;
                            case 'reopenGroup':  // ✅ 추가
                              _showReopenGroupDialog(groupItem);
                              break;
                            case 'deleteGroup':
                              _showDeleteGroupDialog(groupItem);
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
                      Text(
                        groupItem.isGrouped
                            ? '${dateFormat.format(masterTO.date)} 외 ${groupItem.groupTOs.length - 1}일'
                            : dateFormat.format(masterTO.date),
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text(
                        '${masterTO.displayStartTime} ~ ${masterTO.displayEndTime}',
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // ✅ 통계 정보
                  Row(
                    children: [
                      _buildStatChip(
                        '확정',
                        '$totalConfirmed/$totalRequired명',
                        isFull ? Colors.green : Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      _buildStatChip(
                        '대기',
                        '$totalPending명',
                        Colors.orange,
                      ),
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
                  ...groupItem.groupTOs.first.workDetails.map((work) {
                    return _buildWorkDetailRow(work, work.currentCount, work.pendingCount);
                  }).toList(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// ✅ TO 아이템 카드 (2단계 토글 - 개선 버전)
  Widget _buildTOItemCard(_TOItem toItem, _TOGroupItem groupItem) {
    final to = toItem.to;
    final isExpanded = _expandedTOs.contains(to.id);
    final dateFormat = DateFormat('MM/dd (E)', 'ko_KR');
    final isFull = toItem.confirmedCount >= to.totalRequired;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isFull ? Colors.green[200]! : Colors.grey[300]!,
          width: isFull ? 2 : 1,
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
                  _expandedTOs.add(to.id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ 첫 줄: 날짜 + TO 제목
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
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // ✅ 둘째 줄: 통계 + 더보기 메뉴
                  Row(
                    children: [
                      // 통계
                      _buildStatChip(
                        '확정',
                        '${toItem.confirmedCount}/${to.totalRequired}',
                        toItem.confirmedCount >= to.totalRequired
                            ? Colors.green : Colors.blue,
                        small: true,
                      ),
                      const SizedBox(width: 4),
                      _buildStatChip(
                        '대기',
                        '${toItem.pendingCount}',
                        Colors.orange,
                        small: true,
                      ),
                      
                      const Spacer(),
                      
                      // ✅ 더보기 메뉴
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[700]),
                        padding: EdgeInsets.zero,
                        tooltip: '메뉴',
                        onSelected: (value) {
                          switch (value) {
                            case 'edit':
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AdminEditTOScreen(to: to),
                                ),
                              ).then((result) {
                                if (result == true) _loadTOsWithStats();
                              });
                              break;
                            case 'delete':
                              _showDeleteTODialog(toItem);
                              break;
                            case 'unlink':
                              _showRemoveFromGroupDialog(toItem);
                              break;
                            case 'detail':
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AdminTODetailScreen(to: to),
                                ),
                              );
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
                            value: 'detail',
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, size: 18, color: Colors.purple[600]),
                                SizedBox(width: 12),
                                Text('지원자 관리'),
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
                  ...toItem.workDetails.map((work) {
                    return _buildWorkDetailRow(work, work.currentCount, work.pendingCount);
                  }).toList(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkDetailRow(WorkDetailModel work, int confirmedCount, int pendingCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          
          // ✅ 업무 아이콘 + 유형
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
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              work.workType,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          
          // 시간
          Icon(Icons.access_time, size: 12, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            '${work.startTime}~${work.endTime}',
            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
          ),
          const SizedBox(width: 8),
          
          // 급여
          Text(
            '${NumberFormat('#,###').format(work.wage)}원',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(width: 12),

          // 확정 인원
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: work.isFull ? Colors.green[50] : Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: work.isFull ? Colors.green[200]! : Colors.blue[200]!,
              ),
            ),
            child: Text(
              '$confirmedCount/${work.requiredCount}명',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: work.isFull ? Colors.green[700] : Colors.blue[700],
              ),
            ),
          ),
          const SizedBox(width: 6),
          
          // ✅ NEW: 대기 인원 추가
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.orange[100],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.orange[300]!),
            ),
            child: Text(
              '대기 $pendingCount',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 통계 칩
  Widget _buildStatChip(String label, String value, Color color, {bool small = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 10,
        vertical: small ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: small ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: small ? 11 : 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
  /// ✅ Phase 4: 탭 UI (개선 버전)
  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
                  });
                  _loadTOsWithStats();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _selectedTab == 'ACTIVE' ? const Color(0xFF1E88E5) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _selectedTab == 'ACTIVE'
                      ? [
                          BoxShadow(
                            color: const Color(0xFF1E88E5).withOpacity(0.3),
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
                    color: _selectedTab == 'ACTIVE' ? Colors.white : const Color(0xFF757575),
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
                  });
                  _loadTOsWithStats();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _selectedTab == 'CLOSED' ? const Color(0xFF1E88E5) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _selectedTab == 'CLOSED'
                      ? [
                          BoxShadow(
                            color: const Color(0xFF1E88E5).withOpacity(0.3),
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
                    color: _selectedTab == 'CLOSED' ? Colors.white : const Color(0xFF757575),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  // ═══════════════════════════════════════════════════════════
  // ✅ Phase 4: TO 마감/재오픈 다이얼로그
  // ═══════════════════════════════════════════════════════════

  /// 단일 TO 마감 다이얼로그
  Future<void> _showCloseTODialog(TOModel to) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('TO 마감'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('이 TO를 마감 처리하시겠습니까?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      const Text(
                        '마감 후 변경사항',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('• 더 이상 지원을 받을 수 없습니다', style: TextStyle(fontSize: 13)),
                  const Text('• 확정된 지원자는 유지됩니다', style: TextStyle(fontSize: 13)),
                  const Text('• 재오픈으로 다시 열 수 있습니다', style: TextStyle(fontSize: 13)),
                ],
              ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('마감'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 로딩 표시
    if (mounted) {
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
                  Text('마감 처리 중...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUID = userProvider.currentUser?.uid ?? '';

      final success = await _firestoreService.closeTOManually(to.id, adminUID);

      if (mounted) {
        Navigator.pop(context); // 로딩 닫기
      }

      if (success) {
        ToastHelper.showSuccess('TO가 마감되었습니다.');
        _loadTOsWithStats();
      } else {
        ToastHelper.showError('TO 마감에 실패했습니다.');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
      print('❌ TO 마감 실패: $e');
      ToastHelper.showError('TO 마감 중 오류가 발생했습니다.');
    }
  }

  /// 단일 TO 재오픈 다이얼로그
  Future<void> _showReopenTODialog(TOModel to) async {
    // ✅ 시간 초과 체크 - 재오픈 불가!
    if (to.isTimeExpired) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red[700]),
              const SizedBox(width: 8),
              const Text('재오픈 불가'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '근무 시작 시간이 지난 TO는 재오픈할 수 없습니다.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 16, color: Colors.red[700]),
                        const SizedBox(width: 8),
                        Text(
                          '근무일: ${DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(to.date)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red[900],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 16, color: Colors.red[700]),
                        const SizedBox(width: 8),
                        Text(
                          '근무 시간: ${to.startTime} ~ ${to.endTime}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red[900],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '💡 새로운 날짜로 TO를 생성하세요.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }

    // ✅ 인원 충족 체크 - 재오픈 가능하지만 경고
    final isFull = to.isFull;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('TO 재오픈'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('이 TO를 다시 오픈하시겠습니까?'),
            const SizedBox(height: 16),
            
            // ✅ 인원 충족 경고
            if (isFull) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '⚠️ 이미 인원이 충족된 TO입니다.\n추가 지원자를 받으시겠습니까?',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.green[700]),
                      const SizedBox(width: 8),
                      const Text(
                        '재오픈 후 변경사항',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('• 지원자가 다시 지원할 수 있습니다', style: TextStyle(fontSize: 13)),
                  const Text('• 기존 확정 지원자는 유지됩니다', style: TextStyle(fontSize: 13)),
                ],
              ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('재오픈'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) {
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
                  Text('재오픈 중...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUID = userProvider.currentUser?.uid ?? '';

      final success = await _firestoreService.reopenTO(to.id, adminUID);

      if (mounted) {
        Navigator.pop(context);
      }

      if (success) {
        ToastHelper.showSuccess('TO가 재오픈되었습니다.');
        _loadTOsWithStats();
      } else {
        ToastHelper.showError('TO 재오픈에 실패했습니다.');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
      print('❌ TO 재오픈 실패: $e');
      ToastHelper.showError('TO 재오픈 중 오류가 발생했습니다.');
    }
  }

  /// 그룹 전체 마감 다이얼로그
  Future<void> _showCloseGroupDialog(_TOGroupItem groupItem) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('그룹 전체 마감'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('그룹 "${groupItem.masterTO.groupName}"의 모든 TO를 마감하시겠습니까?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '포함된 TO: ${groupItem.groupTOs.length}개',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('• 모든 TO가 마감됩니다', style: TextStyle(fontSize: 13)),
                  const Text('• 더 이상 지원을 받을 수 없습니다', style: TextStyle(fontSize: 13)),
                ],
              ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('전체 마감'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) {
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
                  Text('그룹 마감 중...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUID = userProvider.currentUser?.uid ?? '';

      final success = await _firestoreService.closeGroupTOs(
        groupItem.masterTO.groupId!,
        adminUID,
      );

      if (mounted) {
        Navigator.pop(context);
      }

      if (success) {
        ToastHelper.showSuccess('그룹 전체가 마감되었습니다.');
        _loadTOsWithStats();
      } else {
        ToastHelper.showError('그룹 마감에 실패했습니다.');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
      print('❌ 그룹 마감 실패: $e');
      ToastHelper.showError('그룹 마감 중 오류가 발생했습니다.');
    }
  }

  /// 그룹 전체 재오픈 다이얼로그
  Future<void> _showReopenGroupDialog(_TOGroupItem groupItem) async {
    // ✅ 그룹 내 시간 초과 TO 체크
    final hasExpiredTO = groupItem.groupTOs.any((toItem) => toItem.to.isTimeExpired);
    
    if (hasExpiredTO) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red[700]),
              const SizedBox(width: 8),
              const Text('재오픈 불가'),
            ],
          ),
          content: const Text(
            '그룹 내에 근무 시작 시간이 지난 TO가 있어\n그룹 전체를 재오픈할 수 없습니다.\n\n각 TO를 개별적으로 확인해주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('그룹 전체 재오픈'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('그룹 "${groupItem.masterTO.groupName}"의 모든 TO를 재오픈하시겠습니까?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '포함된 TO: ${groupItem.groupTOs.length}개',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('• 모든 TO가 재오픈됩니다', style: TextStyle(fontSize: 13)),
                  const Text('• 지원자가 다시 지원할 수 있습니다', style: TextStyle(fontSize: 13)),
                ],
              ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('전체 재오픈'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) {
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
                  Text('그룹 재오픈 중...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUID = userProvider.currentUser?.uid ?? '';

      final success = await _firestoreService.reopenGroupTOs(
        groupItem.masterTO.groupId!,
        adminUID,
      );

      if (mounted) {
        Navigator.pop(context);
      }

      if (success) {
        ToastHelper.showSuccess('그룹 전체가 재오픈되었습니다.');
        _loadTOsWithStats();
      } else {
        ToastHelper.showError('그룹 재오픈에 실패했습니다.');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
      print('❌ 그룹 재오픈 실패: $e');
      ToastHelper.showError('그룹 재오픈 중 오류가 발생했습니다.');
    }
  }

  /// 더미 데이터 생성 다이얼로그 ㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡㅡ
  Future<void> _showCreateDummyDataDialog() async {
    // TO 선택
    if (_filteredGroupItems.isEmpty) {
      ToastHelper.showError('생성된 TO가 없습니다');
      return;
    }

    final selectedTO = await showDialog<TOModel>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('TO 선택'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _filteredGroupItems.length,
            itemBuilder: (context, index) {
              final item = _filteredGroupItems[index];
              final to = item.masterTO;
              return ListTile(
                title: Text(to.title),
                subtitle: Text(
                  '${DateFormat('yyyy-MM-dd').format(to.date)} | ${to.businessName}',
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
      _loadTOsWithStats();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
      print('❌ 더미 데이터 삭제 실패: $e');
      ToastHelper.showError('삭제 실패: $e');
    }
  }
}

// ============================================================
// 📦 데이터 모델
// ============================================================

/// 그룹 아이템 (대표 TO + 연결된 TO들)
class _TOGroupItem {
  final TOModel masterTO;
  final List<_TOItem> groupTOs;
  final bool isGrouped;

  _TOGroupItem({
    required this.masterTO,
    required this.groupTOs,
    required this.isGrouped,
  });
}

/// TO 아이템 (TO + WorkDetails + 통계)
class _TOItem {
  final TOModel to;
  final List<WorkDetailModel> workDetails;
  final int confirmedCount;
  final int pendingCount;

  _TOItem({
    required this.to,
    required this.workDetails,
    required this.confirmedCount,
    required this.pendingCount,
  });
}