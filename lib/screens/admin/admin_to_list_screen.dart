import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/to_model.dart';
import '../../models/work_detail_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/toast_helper.dart';
import 'admin_to_detail_screen.dart';
import 'admin_create_to_screen.dart';
import 'admin_edit_to_screen.dart';

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

  /// TO 목록 + 지원자 통계 로드 (병렬 처리)
  Future<void> _loadTOsWithStats() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. 대표 TO만 조회
      final masterTOs = await _firestoreService.getGroupMasterTOs();
      print('✅ 조회된 대표 TO 개수: ${masterTOs.length}');

      // 2. 각 TO별 처리
      List<_TOGroupItem> groupItems = [];
      
      for (var masterTO in masterTOs) {
        // 그룹 TO인 경우
        if (masterTO.isGrouped && masterTO.groupId != null) {
          // 같은 그룹의 모든 TO 조회
          final groupTOs = await _firestoreService.getTOsByGroup(masterTO.groupId!);
          
          // 각 TO의 지원자 통계 + WorkDetails 조회
          List<_TOItem> toItems = [];
          for (var to in groupTOs) {
            final applications = await _firestoreService.getApplicationsByTOId(to.id);
            final workDetails = await _firestoreService.getWorkDetails(to.id);
            // ✅ 각 WorkDetail별로 대기 인원 수 계산
            for (var work in workDetails) {
              work.pendingCount = applications
                  .where((app) => app.selectedWorkType == work.workType && app.status == 'PENDING')
                  .length;
            }
            
            toItems.add(_TOItem(
              to: to,
              workDetails: workDetails,
              confirmedCount: applications.where((app) => app.status == 'CONFIRMED').length,
              pendingCount: applications.where((app) => app.status == 'PENDING').length,
            ));
          }
          
          // 시간 범위 계산
          final timeRange = await _firestoreService.calculateGroupTimeRange(masterTO.groupId!);
          masterTO.setTimeRange(timeRange['minStart']!, timeRange['maxEnd']!);
          
          groupItems.add(_TOGroupItem(
            masterTO: masterTO,
            groupTOs: toItems,
            isGrouped: true,
          ));
        } 
        // 단일 TO인 경우
        else {
          final applications = await _firestoreService.getApplicationsByTOId(masterTO.id);
          final workDetails = await _firestoreService.getWorkDetails(masterTO.id);
          
          groupItems.add(_TOGroupItem(
            masterTO: masterTO,
            groupTOs: [
              _TOItem(
                to: masterTO,
                workDetails: workDetails,
                confirmedCount: applications.where((app) => app.status == 'CONFIRMED').length,
                pendingCount: applications.where((app) => app.status == 'PENDING').length,
              )
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
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      print('❌ TO 목록 로드 실패: $e');
      ToastHelper.showError('TO 목록을 불러오는데 실패했습니다.');
      setState(() {
        _isLoading = false;
      });
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTOsWithStats,
          ),
        ],
      ),
      body: Column(
        children: [
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
        backgroundColor: Colors.blue[700],
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              '조건에 맞는 TO가 없습니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '필터를 변경하거나 새로운 TO를 생성하세요',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
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
                      
                      const Spacer(),
                      
                      // ✅ 단일 TO인 경우 수정/삭제 버튼
                      if (!groupItem.isGrouped) ...[
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          color: Colors.orange[600],
                          tooltip: 'TO 수정',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminEditTOScreen(to: masterTO),
                              ),
                            );
                            if (result == true) _loadTOsWithStats();
                          },
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18),
                          color: Colors.red[600],
                          tooltip: 'TO 삭제',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _showDeleteTODialog(groupItem.groupTOs.first),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.link, size: 18),
                          color: Colors.blue[600],
                          tooltip: '그룹 연결',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _showReconnectToGroupDialog(groupItem.groupTOs.first),
                        ),
                      ],
                      
                      // ✅ 그룹 TO인 경우 그룹명 수정/전체 삭제 버튼
                      if (groupItem.isGrouped && masterTO.groupId != null) ...[
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          color: Colors.blue[600],
                          tooltip: '그룹명 수정',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _showEditGroupNameDialog(masterTO),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_forever, size: 18),
                          color: Colors.red[600],
                          tooltip: '그룹 전체 삭제',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _showDeleteGroupDialog(groupItem),
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
                  
                  // ✅ 제목 제거! (그룹 카드에서는 제목 안 보여줌)
                  
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
                  
                  // ✅ 둘째 줄: 통계 + 버튼들
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
                      
                      // 수정 버튼
                      IconButton(
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AdminEditTOScreen(to: to),
                            ),
                          );
                          if (result == true) _loadTOsWithStats();
                        },
                        icon: const Icon(Icons.edit, size: 16),
                        color: Colors.orange[700],
                        tooltip: '수정',
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),

                      // 삭제 버튼
                      IconButton(
                        onPressed: () => _showDeleteTODialog(toItem),
                        icon: const Icon(Icons.delete, size: 16),
                        color: Colors.red[700],
                        tooltip: '삭제',
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                      
                      // 상세 보기 버튼
                      IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AdminTODetailScreen(to: to),
                            ),
                          ).then((result) {
                            if (result == true) _loadTOsWithStats();
                          });
                        },
                        icon: const Icon(Icons.arrow_forward_ios, size: 14),
                        tooltip: '상세 보기',
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                      
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
          Text(
            work.workTypeIcon,
            style: const TextStyle(fontSize: 16),
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

  /// 색상 파싱
  Color _parseColor(String? colorString) {
    if (colorString == null || colorString.isEmpty) {
      return Colors.blue;
    }
    
    try {
      final hexColor = colorString.replaceAll('#', '');
      return Color(int.parse('FF$hexColor', radix: 16));
    } catch (e) {
      return Colors.blue;
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