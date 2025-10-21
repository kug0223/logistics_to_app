import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../services/firestore_service.dart';
import '../../models/to_model.dart';
import '../../models/application_model.dart';
import '../../widgets/loading_widget.dart';
import 'admin_to_detail_screen.dart';
import 'package:intl/intl.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({Key? key}) : super(key: key);

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<TOModel> _allTOList = [];
  List<TOModel> _filteredTOList = [];
  Map<String, Map<String, int>> _toStats = {}; // TO별 통계 (확정/대기)
  bool _isLoading = true;
  
  // 필터 상태
  DateTime? _selectedDate;
  String _selectedCenter = 'ALL'; // ALL, CENTER_A, CENTER_B, CENTER_C
  String _selectedStatus = 'ALL'; // ALL, OPEN(미마감), CLOSED(마감)

  @override
  void initState() {
    super.initState();
    _loadTOs();
  }

  /// TO 목록 + 지원자 통계 로드
  Future<void> _loadTOs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. 모든 TO 조회
      List<TOModel> toList = await _firestoreService.getAllTOs();

      // 2. 각 TO별 지원자 통계 계산
      Map<String, Map<String, int>> stats = {};
      for (var to in toList) {
        final applicants = await _firestoreService.getApplicationsByTO(to.id);
        
        // 확정 인원
        final confirmedCount = applicants.where((app) => app.status == 'CONFIRMED').length;
        
        // 대기 인원 (PENDING만)
        final pendingCount = applicants.where((app) => app.status == 'PENDING').length;
        
        stats[to.id] = {
          'confirmed': confirmedCount,
          'pending': pendingCount,
        };
      }

      setState(() {
        _allTOList = toList;
        _toStats = stats;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      print('❌ TO 로드 실패: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 필터 적용
  void _applyFilters() {
    List<TOModel> filtered = _allTOList;

    // 1. 날짜 필터
    if (_selectedDate != null) {
      final startOfDay = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
      final endOfDay = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, 23, 59, 59);
      
      filtered = filtered.where((to) {
        return to.date.isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
               to.date.isBefore(endOfDay.add(const Duration(seconds: 1)));
      }).toList();
    }

    // 2. 센터 필터
    if (_selectedCenter != 'ALL') {
      filtered = filtered.where((to) => to.centerId == _selectedCenter).toList();
    }

    // 3. 상태 필터 (미마감/마감)
    if (_selectedStatus == 'OPEN') {
      // 미마감: 확정 인원 < 필요 인원
      filtered = filtered.where((to) {
        final confirmedCount = _toStats[to.id]?['confirmed'] ?? 0;
        return confirmedCount < to.requiredCount;
      }).toList();
    } else if (_selectedStatus == 'CLOSED') {
      // 마감: 확정 인원 >= 필요 인원
      filtered = filtered.where((to) {
        final confirmedCount = _toStats[to.id]?['confirmed'] ?? 0;
        return confirmedCount >= to.requiredCount;
      }).toList();
    }

    setState(() {
      _filteredTOList = filtered;
    });
  }

  /// 날짜 선택
  Future<void> _selectDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
        _applyFilters();
      });
    }
  }

  /// 오늘 버튼
  void _setToday() {
    setState(() {
      _selectedDate = DateTime.now();
      _applyFilters();
    });
  }

  /// 전체 날짜 버튼
  void _showAllDates() {
    setState(() {
      _selectedDate = null;
      _applyFilters();
    });
  }

  /// 요일 한글 변환
  String _getKoreanWeekday(DateTime date) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return weekdays[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자 - TO 관리'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              bool? confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('로그아웃'),
                  content: const Text('로그아웃 하시겠습니까?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('취소'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('확인'),
                    ),
                  ],
                ),
              );

              if (confirm == true && context.mounted) {
                context.read<UserProvider>().signOut();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 헤더
          _buildHeader(userProvider),
          
          // 필터
          _buildFilters(),
          
          // TO 목록
          Expanded(
            child: _buildTOList(),
          ),
        ],
      ),
    );
  }

  /// 헤더
  Widget _buildHeader(UserProvider userProvider) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple[700]!, Colors.purple[500]!],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.admin_panel_settings,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '관리자 모드',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${userProvider.currentUser?.name ?? '관리자'}님',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 필터
  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 날짜 필터
          const Text(
            '📅 날짜 필터',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _selectDate,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    _selectedDate == null
                        ? '날짜 선택'
                        : '${_selectedDate!.year}.${_selectedDate!.month}.${_selectedDate!.day}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _setToday,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('오늘', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: _showAllDates,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('전체', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 센터 필터
          const Text(
            '🏢 센터 필터',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('전체', 'ALL', _selectedCenter, (value) {
                  setState(() {
                    _selectedCenter = value;
                    _applyFilters();
                  });
                }),
                const SizedBox(width: 8),
                _buildFilterChip('송파', 'CENTER_A', _selectedCenter, (value) {
                  setState(() {
                    _selectedCenter = value;
                    _applyFilters();
                  });
                }),
                const SizedBox(width: 8),
                _buildFilterChip('강남', 'CENTER_B', _selectedCenter, (value) {
                  setState(() {
                    _selectedCenter = value;
                    _applyFilters();
                  });
                }),
                const SizedBox(width: 8),
                _buildFilterChip('서초', 'CENTER_C', _selectedCenter, (value) {
                  setState(() {
                    _selectedCenter = value;
                    _applyFilters();
                  });
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 상태 필터
          const Text(
            '📊 상태 필터',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildFilterChip('전체', 'ALL', _selectedStatus, (value) {
                setState(() {
                  _selectedStatus = value;
                  _applyFilters();
                });
              }),
              const SizedBox(width: 8),
              _buildFilterChip('미마감', 'OPEN', _selectedStatus, (value) {
                setState(() {
                  _selectedStatus = value;
                  _applyFilters();
                });
              }),
              const SizedBox(width: 8),
              _buildFilterChip('마감', 'CLOSED', _selectedStatus, (value) {
                setState(() {
                  _selectedStatus = value;
                  _applyFilters();
                });
              }),
            ],
          ),
        ],
      ),
    );
  }

  /// 필터 칩
  Widget _buildFilterChip(String label, String value, String currentValue, Function(String) onSelected) {
    final isSelected = currentValue == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) => onSelected(value),
      selectedColor: Colors.purple[100],
      checkmarkColor: Colors.purple[800],
      labelStyle: TextStyle(
        color: isSelected ? Colors.purple[800] : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 13,
      ),
    );
  }

  /// TO 목록
  Widget _buildTOList() {
    if (_isLoading) {
      return const LoadingWidget(message: 'TO 목록을 불러오는 중...');
    }

    if (_filteredTOList.isEmpty) {
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
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTOs,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredTOList.length,
        itemBuilder: (context, index) {
          return _buildTOCard(_filteredTOList[index]);
        },
      ),
    );
  }

  /// TO 카드
  Widget _buildTOCard(TOModel to) {
    final dateFormat = DateFormat('M월 d일');
    final koreanWeekday = _getKoreanWeekday(to.date);
    
    // 통계 가져오기
    final confirmedCount = _toStats[to.id]?['confirmed'] ?? 0;
    final pendingCount = _toStats[to.id]?['pending'] ?? 0;
    final isClosed = confirmedCount >= to.requiredCount;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdminTODetailScreen(to: to),
            ),
          ).then((_) => _loadTOs()); // 돌아올 때 새로고침
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 센터명 + 마감 배지
              Row(
                children: [
                  Icon(Icons.business, color: Colors.purple[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      to.centerName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // 마감 상태 배지
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isClosed ? Colors.red[100] : Colors.green[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isClosed ? '마감' : '모집중',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isClosed ? Colors.red[700] : Colors.green[700],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),

              // 날짜/시간/업무 + 인원 현황 (2단 레이아웃)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 왼쪽: 날짜/시간/업무 정보
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 날짜
                        Row(
                          children: [
                            Icon(Icons.calendar_today, color: Colors.grey[600], size: 16),
                            const SizedBox(width: 8),
                            Text(
                              '${dateFormat.format(to.date)} ($koreanWeekday)',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // 시간
                        Row(
                          children: [
                            Icon(Icons.access_time, color: Colors.grey[600], size: 16),
                            const SizedBox(width: 8),
                            Text(
                              '${to.startTime} ~ ${to.endTime}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // 업무 유형
                        Row(
                          children: [
                            Icon(Icons.work_outline, color: Colors.grey[600], size: 16),
                            const SizedBox(width: 8),
                            Text(
                              to.workType,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // 오른쪽: 인원 현황 (컴팩트)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      children: [
                        _buildCompactStat('확정', confirmedCount, Colors.green[700]!),
                        const SizedBox(height: 4),
                        _buildCompactStat('대기', pendingCount, Colors.orange[700]!),
                        const SizedBox(height: 4),
                        _buildCompactStat('필요', to.requiredCount, Colors.blue[700]!),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 컴팩트 통계 행
  Widget _buildCompactStat(String label, int value, Color color) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}