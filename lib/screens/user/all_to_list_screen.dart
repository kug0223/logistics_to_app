import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/to_model.dart';
import '../../models/application_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/user_to_card.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/toast_helper.dart';
import 'to_detail_screen.dart';

/// 전체 TO 목록 화면 (모든 사업장의 TO 조회) - 지원자용 신버전
class AllTOListScreen extends StatefulWidget {
  const AllTOListScreen({super.key});

  @override
  State<AllTOListScreen> createState() => _AllTOListScreenState();
}

class _AllTOListScreenState extends State<AllTOListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  
  // 필터 상태
  DateTime? _selectedDate; // 단일 날짜 선택용
  String _selectedBusiness = 'ALL'; // 사업장 필터
  
  List<TOModel> _allTOList = []; // Firestore에서 가져온 전체 TO
  List<TOModel> _filteredTOList = []; // 필터 적용 후 TO
  List<ApplicationModel> _myApplications = [];
  List<String> _businessNames = []; // 사업장 목록 (필터용)
  bool _isLoading = true;
  String? _selectedTOId; // ⭐ 선택된 TO ID

  @override
  void initState() {
    super.initState();
    _loadAllTOs();
  }

  /// 전체 TO 목록 + 내 지원 내역 병렬 로드 (최적화)
  Future<void> _loadAllTOs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;
      
      // ⚡ 병렬로 TO 목록과 내 지원 내역을 동시에 조회!
      final results = await Future.wait([
        _firestoreService.getAllTOs(), // ✅ 대표 TO만!
        uid != null 
            ? _firestoreService.getMyApplications(uid)
            : Future.value(<ApplicationModel>[]),
      ]);

      final toList = results[0] as List<TOModel>;
      final myApps = results[1] as List<ApplicationModel>;

      print('✅ 조회된 전체 TO 개수: ${toList.length}');
      print('✅ 내 지원 내역 개수: ${myApps.length}');

      // 사업장 목록 추출 (중복 제거)
      final businessSet = toList.map((to) => to.businessName).toSet();
      final businessList = businessSet.toList()..sort();
      
      // ✅ 그룹 TO의 시간 범위 계산 (병렬 처리)
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
        _myApplications = myApps;
        _businessNames = businessList;
        _isLoading = false;
      });

      // ⭐ setState 밖에서 호출
      _applyFilters();
    } catch (e) {
      print('❌ 에러 발생: $e');
      setState(() {
        _isLoading = false;
      });
      ToastHelper.showError('TO 목록을 불러올 수 없습니다');
    }
  }
  /// ⭐ TO 선택/선택 해제
  void _toggleTOSelection(String toId) {
    setState(() {
      if (_selectedTOId == toId) {
        // 같은 카드 클릭 → 접기
        _selectedTOId = null;
      } else {
        // 다른 카드 클릭 → 펼치기
        _selectedTOId = toId;
      }
    });
  }

  /// ✅ 필터 적용 (업무유형 필터 제거)
  void _applyFilters() {
    List<TOModel> filtered = _allTOList;

    // 1. 날짜 필터 (오늘 이전 TO는 무조건 제외!)
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    
    filtered = filtered.where((to) {
      return to.date.isAfter(todayStart.subtract(const Duration(days: 1)));
    }).toList();

    // 2. 특정 날짜 선택 시
    if (_selectedDate != null) {
      filtered = filtered.where((to) {
        return to.date.year == _selectedDate!.year &&
               to.date.month == _selectedDate!.month &&
               to.date.day == _selectedDate!.day;
      }).toList();
    }

    // 3. 사업장 필터
    if (_selectedBusiness != 'ALL') {
      filtered = filtered.where((to) => to.businessName == _selectedBusiness).toList();
    }

    // 4. 날짜/시간 순 정렬
    filtered.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return a.startTime.compareTo(b.startTime);
    });


    _filteredTOList = filtered;
 
    print('📊 필터 적용 결과: ${filtered.length}개 TO');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TO 지원하기'),
        elevation: 0,
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          // 새로고침 버튼
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllTOs,
          ),
        ],
      ),
      body: Column(
        children: [
          // 필터 섹션
          _buildFilterSection(),
          
          // TO 목록
          Expanded(
            child: _isLoading
                ? const LoadingWidget(message: 'TO 목록을 불러오는 중...')
                : _filteredTOList.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(  // ⭐ 추가
                        onRefresh: _loadAllTOs,
                        child: ListView.builder(  // ⭐ 추가
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
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
  

  /// ✅ 필터 섹션 (업무유형 필터 제거)
  Widget _buildFilterSection() {
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 날짜 선택
          _buildDateFilter(),
          
          const SizedBox(height: 12),
          
          // 사업장 필터만 표시
          _buildBusinessFilter(),
        ],
      ),
    );
  }

  /// 날짜 필터
  Widget _buildDateFilter() {
    return InkWell(
      onTap: _selectDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: Colors.blue[700], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedDate == null
                    ? '날짜 선택 (전체)'
                    : '${_selectedDate!.month}/${_selectedDate!.day} (${_getWeekday(_selectedDate!)})',
                style: TextStyle(
                  fontSize: 14,
                  color: _selectedDate == null ? Colors.grey[600] : Colors.black87,
                ),
              ),
            ),
            if (_selectedDate != null)
              IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  setState(() {
                    _selectedDate = null;
                  });
                  _applyFilters();
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      locale: const Locale('ko', 'KR'),
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
      });
      _applyFilters();
    }
  }

  /// 사업장 필터
  Widget _buildBusinessFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedBusiness,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: Colors.blue[700]),
          items: [
            const DropdownMenuItem(value: 'ALL', child: Text('전체 사업장')),
            ..._businessNames.map((name) {
              return DropdownMenuItem(
                value: name,
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
          ],
          onChanged: (value) {
            setState(() {
              _selectedBusiness = value!;
            });
            _applyFilters();
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
          Icon(
            Icons.search_off,
            size: 80,
            color: Colors.grey[400],
          ),
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
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  /// 요일 반환
  String _getWeekday(DateTime date) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return weekdays[date.weekday - 1];
  }
}