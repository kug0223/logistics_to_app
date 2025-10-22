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

/// 관리자 TO 목록 화면
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
    _filteredTOsWithStats = _allTOsWithStats.where((item) {
      final to = item.to;
      
      // 날짜 필터
      if (_selectedDate != null) {
        final toDate = DateTime(to.date.year, to.date.month, to.date.day);
        final selectedDate = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
        if (toDate != selectedDate) return false;
      }
      
      // 센터 필터
      if (_selectedCenter != 'ALL' && to.centerId != _selectedCenter) {
        return false;
      }
      
      // 업무 유형 필터
      if (_selectedWorkType != 'ALL' && to.workType != _selectedWorkType) {
        return false;
      }
      
      return true;
    }).toList();
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
        backgroundColor: Colors.purple[700], // ✅ shade700 → [700]
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
        backgroundColor: Colors.purple[700], // ✅ shade700 → [700]
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
      color: Colors.grey[100], // ✅ shade100 → [100]
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
                        : DateFormat('yyyy-MM-dd').format(_selectedDate!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _setToday,
                child: const Text('오늘'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _showAllDates,
                child: const Text('전체'),
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
          Wrap(
            spacing: 8,
            children: [
              _buildFilterChip(
                label: '전체',
                isSelected: _selectedCenter == 'ALL',
                onSelected: () {
                  setState(() {
                    _selectedCenter = 'ALL';
                    _applyFilters();
                  });
                },
              ),
              ...AppConstants.centers.map((center) {
                return _buildFilterChip(
                  label: center['name']!,
                  isSelected: _selectedCenter == center['id'],
                  onSelected: () {
                    setState(() {
                      _selectedCenter = center['id']!;
                      _applyFilters();
                    });
                  },
                );
              }),
            ],
          ),
          const SizedBox(height: 16),

          // 3. 업무 유형 필터
          const Text(
            '⚙️ 업무 유형',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _buildFilterChip(
                label: '전체',
                isSelected: _selectedWorkType == 'ALL',
                onSelected: () {
                  setState(() {
                    _selectedWorkType = 'ALL';
                    _applyFilters();
                  });
                },
              ),
              ...AppConstants.workTypes.map((workType) {
                return _buildFilterChip(
                  label: workType,
                  isSelected: _selectedWorkType == workType,
                  onSelected: () {
                    setState(() {
                      _selectedWorkType = workType;
                      _applyFilters();
                    });
                  },
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  /// 필터 칩
  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      backgroundColor: Colors.white,
      selectedColor: Colors.purple[100], // ✅ shade100 → [100]
      checkmarkColor: Colors.purple[700], // ✅ shade700 → [700]
      labelStyle: TextStyle(
        color: isSelected ? Colors.purple[700] : Colors.grey[700], // ✅ shade → []
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? Colors.purple[700]! : Colors.grey[300]!, // ✅ shade → []
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
            Icon(Icons.inbox, size: 80, color: Colors.grey[300]), // ✅ shade300 → [300]
            const SizedBox(height: 16),
            Text(
              '조건에 맞는 TO가 없습니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700], // ✅ shade700 → [700]
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '필터를 변경하거나 새로운 TO를 생성하세요',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500], // ✅ shade500 → [500]
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
          border: Border.all(color: Colors.grey[200]!), // ✅ shade200 → [200]
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
                      color: Colors.red[100], // ✅ shade100 → [100]
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '마감',
                      style: TextStyle(
                        color: Colors.red[700], // ✅ shade700 → [700]
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // 날짜 + 시간
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '${to.formattedDate} (${to.weekday})',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]), // ✅ shade → []
                ),
                const SizedBox(width: 16),
                Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  to.timeRange,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]), // ✅ shade → []
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 업무 유형
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue[100], // ✅ shade100 → [100]
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                to.workType,
                style: TextStyle(
                  color: Colors.blue[700], // ✅ shade700 → [700]
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 통계
            Row(
              children: [
                Icon(Icons.people, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '확정: ${item.confirmedCount}/${to.requiredCount}',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]), // ✅ shade → []
                ),
                const SizedBox(width: 16),
                Icon(Icons.pending, size: 16, color: Colors.orange[600]),
                const SizedBox(width: 4),
                Text(
                  '대기: ${item.pendingCount}',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]), // ✅ shade → []
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// TO + 지원자 통계
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