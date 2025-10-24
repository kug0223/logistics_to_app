import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/to_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/toast_helper.dart';
import 'admin_to_detail_screen.dart';
import 'admin_create_to_screen.dart';

/// 관리자 TO 목록 화면 - 신버전
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
  List<_TOWithStats> _allTOsWithStats = [];
  List<_TOWithStats> _filteredTOsWithStats = [];
  bool _isLoading = true;

  // 사업장 목록
  List<String> _businessNames = [];
  
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
      final allTOs = await _firestoreService.getGroupMasterTOs();
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

      // 3. 사업장 목록 추출 (중복 제거 + 정렬)
      final businessSet = allTOs.map((to) => to.businessName).toSet();
      final businessList = businessSet.toList()..sort();

      setState(() {
        _allTOsWithStats = tosWithStats;
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

  /// ✅ 필터 적용 (업무유형 필터 제거)
  void _applyFilters() {
    List<_TOWithStats> filtered = _allTOsWithStats;

    // 1. 날짜 필터
    if (_selectedDate != null) {
      filtered = filtered.where((item) {
        final to = item.to;
        final toDate = DateTime(to.date.year, to.date.month, to.date.day);
        final selectedDate = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
        return toDate == selectedDate;
      }).toList();
    }

    // 2. 사업장 필터
    if (_selectedBusiness != 'ALL') {
      filtered = filtered.where((item) {
        return item.to.businessName == _selectedBusiness;
      }).toList();
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
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('ko', 'KR'),
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
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // 새로고침 버튼
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

  /// ✅ 필터 섹션 (업무유형 필터 제거)
  Widget _buildFilterSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 날짜 필터
          Row(
            children: [
              const Text(
                '📅 날짜',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _selectDate,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    _selectedDate == null
                        ? '전체'
                        : DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(_selectedDate!),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              if (_selectedDate != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    setState(() {
                      _selectedDate = null;
                      _applyFilters();
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 사업장 필터
          const Text(
            '🏢 사업장',
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
                isSelected: _selectedBusiness == 'ALL',
                onSelected: () {
                  setState(() {
                    _selectedBusiness = 'ALL';
                    _applyFilters();
                  });
                },
              ),
              ..._businessNames.map((business) {
                return _buildFilterChip(
                  label: business,
                  isSelected: _selectedBusiness == business,
                  onSelected: () {
                    setState(() {
                      _selectedBusiness = business;
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
      selectedColor: Colors.blue[100],
      checkmarkColor: Colors.blue[700],
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue[700] : Colors.grey[700],
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

    if (_filteredTOsWithStats.isEmpty) {
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

  /// ✅ TO 카드 (수정됨)
  Widget _buildTOCard(_TOWithStats item) {
    final to = item.to;
    final isFull = item.confirmedCount >= to.totalRequired;
    final dateFormat = DateFormat('yyyy-MM-dd (E)', 'ko_KR');
    
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
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 사업장명
              Row(
                children: [
                  Expanded(
                    child: Text(
                      to.businessName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isFull)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green[600],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '마감',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              
              // ✅ 제목
              Text(
                to.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 8),

              // 날짜 + 시간
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    // ✅ 그룹 TO면 범위, 아니면 단일 날짜
                    to.isGroupTO && to.groupPeriodString != null
                        ? '${to.groupPeriodString} (${to.groupDaysCount}일)'
                        : dateFormat.format(to.date),
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${to.startTime} ~ ${to.endTime}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ✅ 통계 (전체 인원 기준)
              Row(
                children: [
                  Icon(Icons.people, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '확정: ${item.confirmedCount}/${to.totalRequired}',
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.pending, size: 16, color: Colors.orange[600]),
                  const SizedBox(width: 4),
                  Text(
                    '대기: ${item.pendingCount}',
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                ],
              ),
            ],
          ),
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