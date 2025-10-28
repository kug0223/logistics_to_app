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

  /// ✅ 그룹 카드 (1단계 토글)
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
            onTap: groupItem.isGrouped
                ? () {
                    setState(() {
                      final key = masterTO.groupId ?? masterTO.id;
                      if (_expandedGroups.contains(key)) {
                        _expandedGroups.remove(key);
                      } else {
                        _expandedGroups.add(key);
                      }
                    });
                  }
                : () {
                    // 단일 TO는 바로 상세 화면으로
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdminTODetailScreen(to: masterTO),
                      ),
                    ).then((result) {
                      if (result == true) _loadTOsWithStats();
                    });
                  },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 그룹명 + 사업장명
                  Row(
                    children: [
                      if (masterTO.isGrouped && masterTO.groupName != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_open, size: 16, color: Colors.blue[700]),
                              const SizedBox(width: 6),
                              Text(
                                masterTO.groupName!,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[900],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          masterTO.businessName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (groupItem.isGrouped)
                        Icon(
                          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: Colors.grey[600],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // 제목
                  Text(
                    masterTO.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // 날짜 및 시간 정보
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
                  
                  // 통계 정보
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
          
          // ✅ 펼쳐진 경우: 연결된 TO 목록 (2단계 토글)
          if (isExpanded && groupItem.isGrouped) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: groupItem.groupTOs.map((toItem) {
                  return _buildTOItemCard(toItem);
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// ✅ TO 아이템 카드 (2단계 토글 - 각 TO)
  Widget _buildTOItemCard(_TOItem toItem) {
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
          // TO 헤더
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
              child: Row(
                children: [
                  // 날짜
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Text(
                      dateFormat.format(to.date),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // 통계
                  Expanded(
                    child: Row(
                      children: [
                        _buildStatChip(
                          '확정',
                          '${toItem.confirmedCount}/${to.totalRequired}',
                          isFull ? Colors.green : Colors.blue,
                          small: true,
                        ),
                        const SizedBox(width: 6),
                        _buildStatChip(
                          '대기',
                          '${toItem.pendingCount}',
                          Colors.orange,
                          small: true,
                        ),
                      ],
                    ),
                  ),
                  
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
                  ),

                  // 삭제 버튼
                  IconButton(
                    onPressed: () {
                      // TODO: 삭제 다이얼로그
                      ToastHelper.showInfo('삭제 기능은 다음 단계에서 구현됩니다');
                    },
                    icon: const Icon(Icons.delete, size: 16),
                    color: Colors.red[700],
                    tooltip: '삭제',
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
                    icon: const Icon(Icons.arrow_forward_ios, size: 16),
                    tooltip: '상세 보기',
                  ),
                  
                  // 펼치기/접기 아이콘
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
          
          // ✅ 펼쳐진 경우: WorkDetails 표시
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
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...toItem.workDetails.map((work) {
                    return _buildWorkDetailRow(work);
                  }).toList(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// ✅ WorkDetail 행
  Widget _buildWorkDetailRow(WorkDetailModel work) {
    final isFull = work.currentCount >= work.requiredCount;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isFull ? Colors.green[200]! : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          // 업무 유형
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _parseColor(work.workTypeColor).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  work.workTypeIcon,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 4),
                Text(
                  work.workType,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _parseColor(work.workTypeColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          
          // 시간
          Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            '${work.startTime}~${work.endTime}',
            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
          ),
          const SizedBox(width: 12),
          
          // 급여
          Icon(Icons.attach_money, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            work.formattedWage,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          
          const Spacer(),
          
          // 인원
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: isFull ? Colors.green[50] : Colors.blue[50],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isFull ? Colors.green[300]! : Colors.blue[300]!,
              ),
            ),
            child: Text(
              '${work.currentCount}/${work.requiredCount}명',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isFull ? Colors.green[700] : Colors.blue[700],
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