import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/to_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/toast_helper.dart';
import '../../utils/constants.dart';
import 'admin_to_detail_screen.dart';
import 'admin_create_to_screen.dart';

/// 관리자 TO 목록 화면 (기존 admin_home_screen의 TO 목록 부분)
class AdminTOListScreen extends StatefulWidget {
  const AdminTOListScreen({Key? key}) : super(key: key);

  @override
  State<AdminTOListScreen> createState() => _AdminTOListScreenState();
}

class _AdminTOListScreenState extends State<AdminTOListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  
  // 필터 상태
  DateTime? _selectedDate;
  String _selectedCenter = 'ALL';
  String _selectedWorkType = 'ALL';
  
  // TO 목록 + 통계
  List<_TOWithStats> _allTOsWithStats = [];
  List<_TOWithStats> _filteredTOsWithStats = [];
  bool _isLoading = true;

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
      // 1. 모든 TO 조회
      final allTOs = await _firestoreService.getAllTOs();
      print('✅ 조회된 TO 개수: ${allTOs.length}');

      // 2. 각 TO별 지원자 통계를 병렬로 조회
      final tosWithStats = await Future.wait(
        allTOs.map((to) async {
          final applications = await _firestoreService.getApplicationsByTOId(to.id);
          
          final confirmedCount = applications
              .where((app) => app.status == 'CONFIRMED')
              .length;
          
          final pendingCount = applications
              .where((app) => app.status == 'PENDING')
              .length;
          
          return _TOWithStats(
            to: to,
            confirmedCount: confirmedCount,
            pendingCount: pendingCount,
          );
        }).toList(),
      );

      setState(() {
        _allTOsWithStats = tosWithStats;
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
    var filtered = _allTOsWithStats;

    // 날짜 필터
    if (_selectedDate != null) {
      filtered = filtered.where((item) {
        final toDate = DateTime(
          item.to.date.year,
          item.to.date.month,
          item.to.date.day,
        );
        final filterDate = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
        );
        return toDate.isAtSameMomentAs(filterDate);
      }).toList();
    }

    // 센터 필터
    if (_selectedCenter != 'ALL') {
      filtered = filtered.where((item) => item.to.centerId == _selectedCenter).toList();
    }

    // 업무 유형 필터
    if (_selectedWorkType != 'ALL') {
      filtered = filtered.where((item) => item.to.workType == _selectedWorkType).toList();
    }

    setState(() {
      _filteredTOsWithStats = filtered;
    });
  }

  /// 날짜 선택
  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _applyFilters();
      });
    }
  }

  /// 오늘 설정
  void _setToday() {
    setState(() {
      _selectedDate = DateTime.now();
      _applyFilters();
    });
    ToastHelper.showSuccess('오늘 날짜로 설정되었습니다');
  }

  /// 전체 날짜 보기
  void _showAllDates() {
    setState(() {
      _selectedDate = null;
      _applyFilters();
    });
    ToastHelper.showSuccess('전체 날짜를 표시합니다');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TO 관리'),
        backgroundColor: Colors.purple.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTOsWithStats,
            tooltip: '새로고침',
          ),
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
        backgroundColor: Colors.purple.shade700,
        foregroundColor: Colors.white,
      ),
      
      body: Column(
        children: [
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

  /// 필터
  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 날짜 필터
          const Text(
            '📅 날짜',
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
                  backgroundColor: Colors.purple.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('오늘', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _showAllDates,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('전체', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          
          const SizedBox(height: 16),

          // 2. 센터 필터
          const Text(
            '🏢 센터',
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

          // 3. 업무 유형 필터
          const Text(
            '💼 업무 유형',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFilterChip('전체', 'ALL', _selectedWorkType, (value) {
                setState(() {
                  _selectedWorkType = value;
                  _applyFilters();
                });
              }),
              ...AppConstants.workTypes.map((workType) {
                return _buildFilterChip(workType, workType, _selectedWorkType, (value) {
                  setState(() {
                    _selectedWorkType = value;
                    _applyFilters();
                  });
                });
              }),
            ],
          ),
        ],
      ),
    );
  }

  /// 필터 칩
  Widget _buildFilterChip(
    String label,
    String value,
    String currentValue,
    Function(String) onSelected,
  ) {
    final isSelected = currentValue == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(value),
      backgroundColor: Colors.white,
      selectedColor: Colors.purple.shade100,
      checkmarkColor: Colors.purple.shade700,
      labelStyle: TextStyle(
        color: isSelected ? Colors.purple.shade700 : Colors.grey.shade700,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? Colors.purple.shade700 : Colors.grey.shade300,
        width: isSelected ? 2 : 1,
      ),
    );
  }

  /// TO 목록
  Widget _buildTOList() {
    if (_isLoading) {
      return const LoadingWidget(message: 'TO 목록을 불러오는 중...');
    }

    if (_filteredTOsWithStats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              '조건에 맞는 TO가 없습니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '필터를 변경하거나 새로운 TO를 생성하세요',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
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
        itemCount: _filteredTOsWithStats.length,
        itemBuilder: (context, index) {
          final item = _filteredTOsWithStats[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildTOCard(item),
          );
        },
      ),
    );
  }

  /// TO 카드
  Widget _buildTOCard(_TOWithStats item) {
    final to = item.to;
    final isFull = item.confirmedCount >= to.requiredCount;
    
    return InkWell(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AdminTODetailScreen(to: to),
          ),
        );

        if (result == true) {
          _loadTOsWithStats();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 센터명 + 마감 여부
            Row(
              children: [
                Expanded(
                  child: Text(
                    to.centerName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isFull)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '마감',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // 날짜
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  DateFormat('M월 d일 (E)', 'ko_KR').format(to.date),
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // 시간
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  '${to.startTime} - ${to.endTime}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // 업무 유형
            Row(
              children: [
                Icon(Icons.work, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  to.workType,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 통계 (컴팩트)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatChip(
                  '확정',
                  item.confirmedCount,
                  Colors.green.shade700,
                  Colors.green.shade50,
                ),
                _buildStatChip(
                  '대기',
                  item.pendingCount,
                  Colors.orange.shade700,
                  Colors.orange.shade50,
                ),
                _buildStatChip(
                  '필요',
                  to.requiredCount,
                  Colors.purple.shade700,
                  Colors.purple.shade50,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 통계 칩
  Widget _buildStatChip(String label, int count, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// TO + 통계 데이터 클래스
class _TOWithStats {
  final TOModel to;
  final int confirmedCount;
  final int pendingCount;

  _TOWithStats({
    required this.to,
    required this.confirmedCount,
    required this.pendingCount,
  });
}