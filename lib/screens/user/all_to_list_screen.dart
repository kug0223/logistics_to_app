import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/core/to_model.dart';
import '../../models/core/application_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/cards/to_card_widget.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/inputs/filter_dialog.dart';


/// 전체 TO 목록 화면 (지원자용)
class AllTOListScreen extends StatefulWidget {
  const AllTOListScreen({super.key});

  @override
  State<AllTOListScreen> createState() => _AllTOListScreenState();
}

class _AllTOListScreenState extends State<AllTOListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  
  // 필터 상태
  DateTimeRange? _selectedDateRange;
  String? _selectedBusiness;
  String _jobTypeFilter = 'ALL'; // 'ALL', 'short', 'long_term'
  
  // 데이터
  List<TOModel> _allTOList = [];
  List<TOModel> _filteredTOList = [];
  List<ApplicationModel> _myApplications = [];
  List<String> _businessNames = [];
  
  // UI 상태
  bool _isLoading = true;
  String? _selectedTOId;

  @override
  void initState() {
    super.initState();
    _loadAllTOs();
  }

  /// 전체 TO 목록 로드
  Future<void> _loadAllTOs() async {
    print('🔄 _loadAllTOs 호출됨!'); // ✅ 디버깅 로그
    setState(() => _isLoading = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;
      
      // 병렬 로딩
      final results = await Future.wait([
        _firestoreService.getActiveTOs(), // 진행중인 TO만
        uid != null 
            ? _firestoreService.getMyApplications(uid)
            : Future.value(<ApplicationModel>[]),
      ]);

      final toList = results[0] as List<TOModel>;
      final myApps = results[1] as List<ApplicationModel>;

      print('✅ 조회된 전체 TO 개수: ${toList.length}');
      print('✅ 내 지원 내역 개수: ${myApps.length}');

      // 사업장 목록 추출
      final businessSet = toList.map((to) => to.businessName).toSet();
      final businessList = businessSet.toList()..sort();
      
      // 그룹 TO 시간 범위 계산
      final groupTOs = toList.where((to) => to.isGrouped && to.groupId != null).toList();
      if (groupTOs.isNotEmpty) {
        final timeRangeFutures = groupTOs.map((to) => 
          _firestoreService.calculateGroupTimeRange(to.groupId!)
        ).toList();
        
        final timeRanges = await Future.wait(timeRangeFutures);
        
        for (int i = 0; i < groupTOs.length; i++) {
          groupTOs[i].setTimeRange(
            timeRanges[i]['minStart']!, 
            timeRanges[i]['maxEnd']!
          );
        }
      }

      setState(() {
        _allTOList = toList;
        _businessNames = businessList;
        _myApplications = myApps;
        _isLoading = false;
      });

      _applyFilters();
    } catch (e) {
      print('❌ TO 목록 로드 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('TO 목록을 불러오는데 실패했습니다.');
    }
  }

  /// 필터 적용
  void _applyFilters() {
    List<TOModel> filtered = _allTOList;

    // 1. 날짜 필터 - ✅ 당일 포함, 이전 날짜는 제외
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    filtered = filtered.where((to) {
      // ✅ 단기: 당일 또는 미래만
      if (!to.isLongTerm) {
        final toDate = DateTime(to.date.year, to.date.month, to.date.day);
        return toDate.isAtSameMomentAs(today) || toDate.isAfter(today);
      }
      
      // ✅ 장기: 종료일이 오늘 이후거나 오늘인 것만
      if (to.endDate != null) {
        final endDate = DateTime(to.endDate!.year, to.endDate!.month, to.endDate!.day);
        return endDate.isAtSameMomentAs(today) || endDate.isAfter(today);
      }
      
      return true; // 장기인데 endDate가 없으면 일단 표시
    }).toList();
    
    // 2. 날짜 범위 필터 (사용자가 캘린더에서 선택한 경우)
    if (_selectedDateRange != null) {
      final rangeStart = DateTime(
        _selectedDateRange!.start.year,
        _selectedDateRange!.start.month,
        _selectedDateRange!.start.day,
      );
      final rangeEnd = DateTime(
        _selectedDateRange!.end.year,
        _selectedDateRange!.end.month,
        _selectedDateRange!.end.day,
      );
      
      filtered = filtered.where((to) {
        if (to.isLongTerm && to.endDate != null) {
          // ✅ 장기: TO의 시작일~종료일이 선택 범위와 겹치는지 확인
          final toStart = DateTime(to.date.year, to.date.month, to.date.day);
          final toEnd = DateTime(to.endDate!.year, to.endDate!.month, to.endDate!.day);
          
          // 범위가 겹치는 경우: TO 시작 <= 선택 종료 AND TO 종료 >= 선택 시작
          return (toStart.isBefore(rangeEnd) || toStart.isAtSameMomentAs(rangeEnd)) &&
                (toEnd.isAfter(rangeStart) || toEnd.isAtSameMomentAs(rangeStart));
        } else {
          // ✅ 단기: TO 날짜가 선택 범위 안에 있는지 확인
          final toDate = DateTime(to.date.year, to.date.month, to.date.day);
          return (toDate.isAtSameMomentAs(rangeStart) || toDate.isAfter(rangeStart)) &&
                (toDate.isAtSameMomentAs(rangeEnd) || toDate.isBefore(rangeEnd));
        }
      }).toList();
    }
    
    // 3. 사업장 필터
    if (_selectedBusiness != null) {
      filtered = filtered.where((to) => to.businessName == _selectedBusiness).toList();
    }

    // 4. 장기/단기 필터
    if (_jobTypeFilter != 'ALL') {
      filtered = filtered.where((to) => to.jobType == _jobTypeFilter).toList();
    }

    // 5. 날짜순 정렬
    filtered.sort((a, b) => a.date.compareTo(b.date));

    setState(() {
      _filteredTOList = filtered;
    });
  }

  /// TO 선택/해제
  void _toggleTOSelection(String toId) {
    setState(() {
      _selectedTOId = _selectedTOId == toId ? null : toId;
    });
  }
  /// ✅ 내 지원 내역만 새로고침 (TO 목록은 유지)
  Future<void> _refreshMyApplications() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;
      
      if (uid != null) {
        final myApps = await _firestoreService.getMyApplications(uid);
        
        if (mounted) {
          setState(() {
            _myApplications = myApps;
          });
        }
        
        print('✅ 내 지원 내역만 새로고침: ${myApps.length}개');
      }
    } catch (e) {
      print('❌ 지원 내역 새로고침 실패: $e');
    }
  }

  /// 필터 다이얼로그 표시
  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => FilterDialog(
        selectedBusiness: _selectedBusiness,
        selectedDateRange: _selectedDateRange,
        businessNames: _businessNames,
        isUserMode: true,
        onBusinessChanged: (value) {
          setState(() => _selectedBusiness = value);
          _applyFilters();
        },
        onDateRangeChanged: (value) {
          setState(() => _selectedDateRange = value);
          _applyFilters();
        },
      ),
    );
  }

  /// 활성화된 필터 개수
  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedDateRange != null) count++;
    if (_selectedBusiness != null) count++;
    if (_jobTypeFilter != 'ALL') count++;
    return count;
  }

  /// 필터가 활성화되어 있는지 확인
  bool get _hasActiveFilters {
    return _selectedDateRange != null || 
           _selectedBusiness != null || 
           _jobTypeFilter != 'ALL';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
        title: const Text('지원하기'),
        actions: [
          // 필터 버튼
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.filter_alt),
                if (_hasActiveFilters)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
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
            onPressed: _showFilterDialog,
            tooltip: '필터',
          ),
        ],
      ),
      body: _isLoading
      ? const LoadingWidget(message: 'TO 목록을 불러오는 중...')
      : _filteredTOList.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadAllTOs,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _filteredTOList.length,
                itemBuilder: (context, index) {
                  final to = _filteredTOList[index];
                  final isSelected = _selectedTOId == to.id;
                  
                  return UserTOCard(
                    to: to,
                    isSelected: isSelected,
                    onTap: () => _toggleTOSelection(to.id),
                    myApplications: _myApplications,
                    onApplySuccess: _refreshMyApplications,
                  );
                },
              ),
            ),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '조건에 맞는 TO가 없습니다',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '필터를 변경하거나 새로고침해보세요',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

}