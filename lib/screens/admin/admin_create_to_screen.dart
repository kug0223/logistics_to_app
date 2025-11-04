import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../../models/business_model.dart';
import '../../models/to_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../models/business_work_type_model.dart';
import '../../widgets/work_detail_dialog.dart';
import '../../models/work_detail_input.dart';
import '../../widgets/work_type_icon.dart';
import '../../utils/format_helper.dart'; 


// ============================================================
// 🎨 메인 화면
// ============================================================

/// TO 생성 화면
class AdminCreateTOScreen extends StatefulWidget {
  const AdminCreateTOScreen({super.key});

  @override
  State<AdminCreateTOScreen> createState() => _AdminCreateTOScreenState();
}

class _AdminCreateTOScreenState extends State<AdminCreateTOScreen> {
  // ============================================================
  // 🔧 서비스 & 컨트롤러
  // ============================================================
  
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _hoursBeforeController = TextEditingController(text: '2');

  // ============================================================
  // 📊 상태 변수
  // ============================================================
  
  // 로딩 상태
  bool _isLoading = true;
  bool _isCreating = false;
  bool _isLoadingRecentTOs = false;

  // 사업장 관련
  List<BusinessModel> _myBusinesses = [];
  BusinessModel? _selectedBusiness;
  List<BusinessWorkTypeModel> _businessWorkTypes = [];

  // TO 설정
  String _selectedJobType = 'short'; // 'short' or 'long_term'

  // 날짜 선택
  final String _dateMode = 'single'; // 'single' or 'multiple'
  final List<DateTime> _selectedDates = [];
  final List<String> _selectedWeekdays = [];
  DateTime _focusedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  bool _isCalendarExpanded = false;
  // 🔥 범위 선택용 변수 추가
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  // 지원 마감
  int _hoursBeforeStart = 2;  // 기본값: 2시간 전
  DateTime? _fixedDeadline; 

  // 업무 상세
  final List<WorkDetailInput> _workDetails = [];

  // 그룹 연결
  bool _linkToExisting = false;
  String? _selectedGroupId;
  List<TOModel> _myRecentTOs = [];

  // ============================================================
  // 🚀 라이프사이클
  // ============================================================

  @override
  void initState() {
    super.initState();
    _hoursBeforeController.text = _hoursBeforeStart.toString();
    _loadMyBusinesses();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _groupNameController.dispose(); // ✅ NEW 추가
    _hoursBeforeController.dispose();
    super.dispose();
  }

  // ============================================================
  // 📡 데이터 로딩
  // ============================================================

  /// 내 사업장 목록 로드
  Future<void> _loadMyBusinesses() async {
    setState(() => _isLoading = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }

      final businesses = await _firestoreService.getMyBusiness(uid);

      setState(() {
        _myBusinesses = businesses;
        if (_myBusinesses.isNotEmpty) {
          _selectedBusiness = _myBusinesses.first;
          _loadWorkTypes();
        }
        _isLoading = false;
      });

      if (businesses.isEmpty) {
        ToastHelper.showInfo('등록된 사업장이 없습니다');
      }
    } catch (e) {
      print('❌ 사업장 로드 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
    }
  }

  /// 업무 유형 로드
  Future<void> _loadWorkTypes() async {
    if (_selectedBusiness == null) return;

    try {
      final workTypes = await _firestoreService.getBusinessWorkTypes(_selectedBusiness!.id);
      setState(() {
        _businessWorkTypes = workTypes;
      });
    } catch (e) {
      print('❌ 업무 유형 로드 실패: $e');
      ToastHelper.showError('업무 유형을 불러올 수 없습니다');
    }
  }

  /// 최근 TO 목록 로드 (그룹 연결용)
  Future<void> _loadRecentTOs() async {
    if (_selectedBusiness == null) return;

    setState(() => _isLoadingRecentTOs = true);

    try {
      // ✅ 대표 TO만 조회하도록 수정!
      final allTOs = await _firestoreService.getGroupMasterTOs();
      
      // 내 사업장의 TO만 필터링
      final myBusinessTOs = allTOs.where((to) => 
        to.businessId == _selectedBusiness!.id
      ).toList();
      
      // ✅ 오늘 이전 TO 제외 (그룹 TO는 endDate 기준!)
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      final recentTOs = myBusinessTOs.where((to) {
        // 그룹 TO: endDate 기준, 단일 TO: date 기준
        final checkDate = to.endDate ?? to.date;
        return checkDate.isAfter(today.subtract(const Duration(days: 1)));
      }).toList();

      // 최신순 정렬
      recentTOs.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _myRecentTOs = recentTOs.take(10).toList();
        _selectedGroupId = null;
        _isLoadingRecentTOs = false;
      });
    } catch (e) {
      print('❌ 최근 TO 로드 실패: $e');
      setState(() => _isLoadingRecentTOs = false);
    }
  }

  // ============================================================
  // 💾 TO 생성
  // ============================================================
  Future<void> _createTO() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedBusiness == null) {
      ToastHelper.showError('사업장을 선택해주세요');
      return;
    }

    if (_selectedDates.isEmpty) {
      ToastHelper.showError('날짜를 선택해주세요');
      return;
    }

    if (_workDetails.isEmpty) {
      ToastHelper.showError('최소 1개의 업무를 추가해주세요');
      return;
    }

    if (_workDetails.any((w) => !w.isValid)) {
      ToastHelper.showError('모든 업무 정보를 입력해주세요');
      return;
    }

    setState(() => _isCreating = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }

      bool success = false;

      if (_selectedDates.length == 1) {
        // 🔥 단일 날짜 TO
        success = await _createSingleTO(
          date: _selectedDates[0],
          creatorUID: uid,
        );
      } else {
        // 🔥 2개 이상이면 무조건 그룹 TO
        final sortedDates = List<DateTime>.from(_selectedDates)..sort();
        success = await _createGroupTO(
          dates: sortedDates,
          creatorUID: uid,
        );
      }

      if (success && mounted) {
        if (_selectedDates.length > 1) {
          ToastHelper.showSuccess('${_selectedDates.length}개의 TO가 그룹으로 생성되었습니다');
        } else {
          ToastHelper.showSuccess('TO가 생성되었습니다');
        }
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('❌ TO 생성 실패: $e');
      ToastHelper.showError('TO 생성에 실패했습니다');
    } finally {
      setState(() => _isCreating = false);
    }
  }

  /// TO 생성 실행
  Future<bool> _createSingleTO({
    required DateTime date,
    required String creatorUID,
  }) async {
    try {
      // 🔥 근무 시작 N시간 전으로 마감시간 계산
      final firstWorkStart = _workDetails.first.startTime!;
      final timeParts = firstWorkStart.split(':');
      final startDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
      final finalDeadline = startDateTime.subtract(Duration(hours: _hoursBeforeStart));
      
      final toId = await _firestoreService.createTOWithDetails(
        businessId: _selectedBusiness!.id,
        businessName: _selectedBusiness!.publicName,
        title: _titleController.text.trim(),
        date: date,
        workDetailsData: _workDetails.map((w) => {
          'workType': w.workType!,
          'workTypeIcon': w.workTypeIcon,
          'workTypeColor': w.workTypeColor,
          'wage': w.wage!,
          'requiredCount': w.requiredCount!,
          'startTime': w.startTime!,
          'endTime': w.endTime!,
        }).toList(),
        applicationDeadline: finalDeadline,
        description: _descriptionController.text.trim(),
        creatorUID: creatorUID,
        hoursBeforeStart: _hoursBeforeStart,  // 🔥 유지
        groupId: _linkToExisting ? _selectedGroupId : null,
        groupName: _linkToExisting && _selectedGroupId != null
            ? _myRecentTOs.firstWhere((to) => to.groupId == _selectedGroupId).groupName
            : null,
      );

      return toId != null;
    } catch (e) {
      print('❌ 단일 TO 생성 실패: $e');
      return false;
    }
  }

  Future<bool> _createGroupTO({
    required List<DateTime> dates,
    required String creatorUID,
  }) async {
    try {
      if (dates.isEmpty) return false;

      final sortedDates = List<DateTime>.from(dates)..sort();
      final groupId = 'group_${DateTime.now().millisecondsSinceEpoch}';
      final startDate = sortedDates.first;
      final endDate = sortedDates.last;

      // 그룹명 결정
      String finalGroupName;
      if (_groupNameController.text.trim().isNotEmpty) {
        // 사용자가 그룹명 입력한 경우
        finalGroupName = _groupNameController.text.trim();
      } else {
        // 🔥 자동 생성 로직 개선
        if (_isConsecutiveDates()) {
          // 연속된 날짜
          finalGroupName = '${DateFormat('MM/dd').format(startDate)} ~ ${DateFormat('MM/dd').format(endDate)} (${sortedDates.length}일)';
        } else {
          // 비연속 날짜
          final dateGroups = _groupConsecutiveDates();
          finalGroupName = '${DateFormat('MM월').format(startDate)} 선택 근무 (${sortedDates.length}일, ${dateGroups.length}개 그룹)';
        }
      }

      bool allSuccess = true;

      for (int i = 0; i < sortedDates.length; i++) {
        final date = sortedDates[i];
        
        // 각 날짜별로 마감 시간 계산
        final firstWorkStart = _workDetails.first.startTime!;
        final timeParts = firstWorkStart.split(':');
        final startDateTime = DateTime(
          date.year,
          date.month,
          date.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
        final finalDeadline = startDateTime.subtract(Duration(hours: _hoursBeforeStart));

        final toId = await _firestoreService.createTOWithDetails(
          businessId: _selectedBusiness!.id,
          businessName: _selectedBusiness!.publicName,
          title: _titleController.text.trim(),
          date: date,
          workDetailsData: _workDetails.map((w) => {
            'workType': w.workType!,
            'workTypeIcon': w.workTypeIcon,
            'workTypeColor': w.workTypeColor,
            'wage': w.wage!,
            'requiredCount': w.requiredCount!,
            'startTime': w.startTime!,
            'endTime': w.endTime!,
          }).toList(),
          applicationDeadline: finalDeadline,
          description: _descriptionController.text.trim(),
          creatorUID: creatorUID,
          hoursBeforeStart: _hoursBeforeStart,
          groupId: groupId,
          groupName: finalGroupName,
          startDate: startDate,
          endDate: endDate,
          isGroupMaster: i == 0,
        );

        if (toId == null) {
          allSuccess = false;
          print('❌ TO 생성 실패: ${DateFormat('yyyy-MM-dd').format(date)}');
        }
      }

      return allSuccess;
    } catch (e) {
      print('❌ 그룹 TO 생성 실패: $e');
      return false;
    }
  }

  // ============================================================
  // 🎯 업무 추가/수정/삭제
  // ============================================================

  /// 업무 추가 다이얼로그
  Future<void> _showAddWorkDetailDialog() async {
    final result = await WorkDetailDialog.showAddDialog(
      context: context,
      businessWorkTypes: _businessWorkTypes,
      
    );

    if (result != null) {
      setState(() {
        _workDetails.add(result);
      });
    }
  }

  /// 업무 삭제
  void _removeWorkDetail(int index) {
    setState(() {
      _workDetails.removeAt(index);
    });
  }

  // ============================================================
  // 📅 날짜 관리
  // ============================================================

  /// 날짜 선택/해제
  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      final normalizedDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
      _focusedDay = focusedDay;
      
      // 🔥 이미 선택된 날짜를 클릭한 경우: 해제
      if (_selectedDates.any((d) => _isSameDay(d, normalizedDay))) {
        _selectedDates.removeWhere((d) => _isSameDay(d, normalizedDay));
        
        if (_rangeStart != null && _isSameDay(_rangeStart!, normalizedDay)) {
          _rangeStart = null;
          _rangeEnd = null;
        }
        if (_rangeEnd != null && _isSameDay(_rangeEnd!, normalizedDay)) {
          _rangeEnd = null;
        }
        
        if (_selectedDates.length <= 1 && _linkToExisting) {
          _linkToExisting = false;
          _selectedGroupId = null;
        }
        
        return;
      }
      
      // 🔥 범위 선택 로직
      if (_rangeStart == null) {
        // 1단계: 시작점 선택
        
        // 30일 제한 체크
        if (_selectedDates.length >= 30) {
          ToastHelper.showWarning('최대 30일까지만 선택할 수 있습니다');
          return;
        }
        
        // 🔥 똑똑한 추가: 인접한 날짜가 있는지 확인
        final yesterday = normalizedDay.subtract(const Duration(days: 1));
        final tomorrow = normalizedDay.add(const Duration(days: 1));
        
        final hasYesterday = _selectedDates.any((d) => _isSameDay(d, yesterday));
        final hasTomorrow = _selectedDates.any((d) => _isSameDay(d, tomorrow));
        
        if (hasYesterday && hasTomorrow) {
          // 양쪽에 날짜가 있음 → 중간 채우기
          _selectedDates.add(normalizedDay);
          ToastHelper.showInfo('인접한 날짜와 자동 연결되었습니다');
        } else if (hasYesterday || hasTomorrow) {
          // 한쪽에만 날짜가 있음 → 범위 시작점으로 설정
          _rangeStart = normalizedDay;
          _rangeEnd = null;
          _selectedDates.add(normalizedDay);
        } else {
          // 인접한 날짜 없음 → 단독 추가
          _rangeStart = normalizedDay;
          _rangeEnd = null;
          _selectedDates.add(normalizedDay);
        }
        
      } else if (_rangeEnd == null) {
        // 2단계: 끝점 선택 → 범위 전체 선택
        _rangeEnd = normalizedDay;
        
        final start = _rangeStart!.isBefore(normalizedDay) ? _rangeStart! : normalizedDay;
        final end = _rangeStart!.isBefore(normalizedDay) ? normalizedDay : _rangeStart!;
        
        final daysInRange = end.difference(start).inDays + 1;
        
        // 30일 제한 체크
        final totalDays = _selectedDates.length + daysInRange - 1;
        if (totalDays > 30) {
          ToastHelper.showWarning('최대 30일까지만 선택할 수 있습니다');
          _rangeStart = null;
          _rangeEnd = null;
          return;
        }
        
        // 범위 내 모든 날짜 추가
        for (int i = 0; i < daysInRange; i++) {
          final date = start.add(Duration(days: i));
          if (!_selectedDates.any((d) => _isSameDay(d, date))) {
            _selectedDates.add(date);
          }
        }
        
        // 범위 선택 완료 후 리셋
        _rangeStart = null;
        _rangeEnd = null;
      }
      
      // 그룹 TO가 되면 기존 연결 해제
      if (_selectedDates.length > 1 && _linkToExisting) {
        _linkToExisting = false;
        _selectedGroupId = null;
        ToastHelper.showInfo('그룹 TO는 기존 공고와 연결할 수 없습니다');
      }
    });
  }

  /// 선택된 날짜인지 확인
  bool _isDateSelected(DateTime day) {
    return _selectedDates.any((d) => _isSameDay(d, day));
  }

  /// 같은 날짜인지 확인
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// 연속된 날짜인지 확인
  bool _isConsecutiveDates() {
    if (_selectedDates.length <= 1) return true;

    final sorted = List<DateTime>.from(_selectedDates)..sort();

    for (int i = 0; i < sorted.length - 1; i++) {
      final diff = sorted[i + 1].difference(sorted[i]).inDays;
      if (diff != 1) return false;
    }

    return true;
  }

  /// 연속된 날짜 그룹으로 나누기
  List<List<DateTime>> _groupConsecutiveDates() {
    if (_selectedDates.isEmpty) return [];

    final sorted = List<DateTime>.from(_selectedDates)..sort();
    final groups = <List<DateTime>>[];
    var currentGroup = <DateTime>[sorted[0]];

    for (int i = 1; i < sorted.length; i++) {
      final diff = sorted[i].difference(sorted[i - 1]).inDays;

      if (diff == 1) {
        currentGroup.add(sorted[i]);
      } else {
        groups.add(currentGroup);
        currentGroup = [sorted[i]];
      }
    }

    groups.add(currentGroup);
    return groups;
  }

  /// 모든 날짜 선택 해제
  void _clearAllDates() {
    setState(() {
      _selectedDates.clear();
    });
  }

  // ============================================================
  // 🎨 UI 빌드
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_myBusinesses.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('TO 생성')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.business_outlined, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '등록된 사업장이 없습니다',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('TO 생성'),
        backgroundColor: Colors.blue[700],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildBusinessSelector(),
            const SizedBox(height: 16),
            _buildJobTypeSelector(),
            const SizedBox(height: 16),
            _buildTitleInput(),
            const SizedBox(height: 16),
            _buildDateSelector(),
            const SizedBox(height: 16),
            _buildWorkDetailsSection(),
            const SizedBox(height: 16),
            _buildDeadlineSelector(),
            const SizedBox(height: 16),
            _buildDescriptionInput(),
            const SizedBox(height: 24),
            _buildGroupLinkSection(),
            const SizedBox(height: 24),
            _buildCreateButton(),
          ],
        ),
      ),
    );
  }

  /// 사업장 선택
  Widget _buildBusinessSelector() {
    if (_myBusinesses.length == 1) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.business, color: Colors.blue[700]),
          title: Text(_selectedBusiness?.name ?? ''),
          subtitle: const Text('선택된 사업장'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DropdownButtonFormField<BusinessModel>(
          initialValue: _selectedBusiness,
          decoration: InputDecoration(
            labelText: '사업장 선택',
            prefixIcon: const Icon(Icons.business),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: _myBusinesses.map((business) {
            return DropdownMenuItem(
              value: business,
              child: Text(business.name),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedBusiness = value;
                _workDetails.clear();
              });
              _loadWorkTypes();
            }
          },
        ),
      ),
    );
  }

  /// 근무 유형 선택
  Widget _buildJobTypeSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '근무 유형',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildJobTypeChip(
                    label: '단기 알바',
                    value: 'short',
                    icon: Icons.today,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildJobTypeChip(
                    label: '1개월 이상',
                    value: 'long_term',
                    icon: Icons.event_note,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobTypeChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final isSelected = _selectedJobType == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedJobType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[700] : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.grey[700], size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 제목 입력 (+ 그룹명 입력)
  Widget _buildTitleInput() {
    final isGroupTO = _selectedDates.length > 1;  // 🔥 2개 이상이면 그룹 TO!
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TO 제목 입력
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'TO 제목 *',
                hintText: '예: 분류작업, 피킹업무',
                prefixIcon: const Icon(Icons.title),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'TO 제목을 입력해주세요';
                }
                return null;
              },
            ),
            
            // 🔥 2개 이상 날짜 선택 시 그룹명 입력
            if (isGroupTO) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.link, size: 18, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          '그룹 TO 생성 (${_selectedDates.length}일)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                      ],
                    ),
                    if (!_isConsecutiveDates()) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '비연속 날짜도 하나의 그룹으로 묶입니다',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange[900],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _groupNameController,
                      decoration: InputDecoration(
                        labelText: '그룹명 (선택)',
                        hintText: '예: 11월 파트타임 모음',
                        prefixIcon: Icon(Icons.folder_open, color: Colors.blue[700]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        helperText: '비워두면 자동으로 생성됩니다',
                        helperStyle: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 날짜 선택 - jobType에 따라 분기
  Widget _buildDateSelector() {
    // 단기 알바인 경우: 캘린더
    if (_selectedJobType == 'short') {
      return _buildCalendarDateSelector();
    }
    
    // 1개월 이상인 경우: 요일 선택
    return _buildWeekdaySelector();
  }

  /// 캘린더 날짜 선택 (단기 알바용)
  Widget _buildCalendarDateSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '근무 날짜 선택',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: _selectedDates.isNotEmpty ? _clearAllDates : null,
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('전체 해제'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // 선택된 날짜 요약
            if (_selectedDates.isNotEmpty) ...[
              _buildDateSummary(),
              const SizedBox(height: 12),
            ],

            // 30일 제한 경고
            if (_selectedDates.length >= 30) ...[
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
                        '단기 알바는 최대 30일까지 선택 가능합니다',
                        style: TextStyle(fontSize: 13, color: Colors.orange[900]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 캘린더 펼치기/접기
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _isCalendarExpanded = !_isCalendarExpanded;
                });
              },
              icon: Icon(_isCalendarExpanded ? Icons.expand_less : Icons.expand_more),
              label: Text(_isCalendarExpanded ? '캘린더 접기' : '캘린더 펼치기'),
            ),

            // 캘린더
            if (_isCalendarExpanded) ...[
              const SizedBox(height: 12),
              TableCalendar(
                locale: 'ko_KR', // ✅ 이 줄 추가!
                firstDay: DateTime.now(),
                lastDay: DateTime.now().add(const Duration(days: 90)),
                focusedDay: _focusedDay,
                calendarFormat: _calendarFormat,
                selectedDayPredicate: (day) {
                  return _selectedDates.any((date) =>
                      date.year == day.year &&
                      date.month == day.month &&
                      date.day == day.day);
                },
                onDaySelected: _onDaySelected,
                calendarStyle: CalendarStyle(
                  selectedDecoration: BoxDecoration(
                    color: Colors.blue[700],
                    shape: BoxShape.circle,
                  ),
                  todayDecoration: BoxDecoration(
                    color: Colors.blue[200],
                    shape: BoxShape.circle,
                  ),
                ),
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 요일 선택 (1개월 이상용)
  Widget _buildWeekdaySelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ⭐ 시작일/종료일 선택 추가
            const Text(
              '계약 기간',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildDateField(
                    label: '시작일',
                    date: _rangeStart,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _rangeStart ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => _rangeStart = picked);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.arrow_forward, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDateField(
                    label: '종료일',
                    date: _rangeEnd,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _rangeEnd ?? _rangeStart ?? DateTime.now(),
                        firstDate: _rangeStart ?? DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => _rangeEnd = picked);
                      }
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            
            // 기존 요일 선택
            const Text(
              '근무 요일 선택',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '※ 매주 반복되는 근무 요일을 선택하세요',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            
            // 요일 버튼들
            _buildWeekdayButtons(),
            
            const SizedBox(height: 16),
            
            // 선택 요약
            if (_selectedWeekdays.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green[700], size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '주 ${_selectedWeekdays.length}일 근무',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[900],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '선택된 요일: ${_selectedWeekdays.join(', ')}',
                      style: TextStyle(fontSize: 13, color: Colors.green[800]),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              date != null
                  ? DateFormat('yyyy-MM-dd').format(date)
                  : '선택하세요',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: date != null ? Colors.black : Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 요일 버튼들
  Widget _buildWeekdayButtons() {
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // 7개 버튼 + 6개 간격(8px)
        final buttonWidth = (constraints.maxWidth - (6 * 8)) / 7;
        
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: weekdays.map((day) {
            final isSelected = _selectedWeekdays.contains(day);
            
            return InkWell(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedWeekdays.remove(day);
                  } else {
                    _selectedWeekdays.add(day);
                  }
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: buttonWidth,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue[700] : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? Colors.blue[700]! : Colors.grey[300]!,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.grey[700],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// 날짜 요약 표시
  Widget _buildDateSummary() {
    final groups = _groupConsecutiveDates();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Text(
                '선택된 날짜: ${_selectedDates.length}일',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: groups.map((group) {
              if (group.length == 1) {
                return _buildSingleDateChip(group[0]);
              } else {
                return _buildDateRangeChip(group.first, group.last, group.length);
              }
            }).toList(),
          ),
          if (!_isConsecutiveDates()) ...[
            const SizedBox(height: 8),
            _buildConsecutiveIndicator(),
          ],
        ],
      ),
    );
  }

  /// 단일 날짜 칩
  Widget _buildSingleDateChip(DateTime date) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue[700],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${date.month}/${date.day}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedDates.removeWhere((d) => _isSameDay(d, date));
              });
            },
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// 날짜 범위 칩
  Widget _buildDateRangeChip(DateTime start, DateTime end, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue[700],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${start.month}/${start.day}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.arrow_forward, size: 12, color: Colors.white),
          ),
          Text(
            '${end.month}/${end.day}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count일',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedDates.removeWhere((d) {
                  return !d.isBefore(start) && !d.isAfter(end);
                });
              });
            },
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// 연속 여부 표시
  Widget _buildConsecutiveIndicator() {
    if (_isConsecutiveDates()) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green[200]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
            const SizedBox(width: 6),
            Text(
              '연속된 날짜입니다',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green[900],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange[200]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
            const SizedBox(width: 6),
            Text(
              '비연속 날짜 (${_groupConsecutiveDates().length}개 그룹)',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange[900],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
  }

  /// 캘린더
  Widget _buildCalendar() {
    return TableCalendar(
      firstDay: DateTime.now(),
      lastDay: DateTime.now().add(const Duration(days: 90)),
      focusedDay: _focusedDay,
      calendarFormat: _calendarFormat,
      selectedDayPredicate: _isDateSelected,
      onDaySelected: _onDaySelected,
      onFormatChanged: (format) {
        setState(() {
          _calendarFormat = format;
        });
      },
      onPageChanged: (focusedDay) {
        _focusedDay = focusedDay;
      },
      calendarStyle: CalendarStyle(
        selectedDecoration: BoxDecoration(
          color: Colors.blue[700],
          shape: BoxShape.circle,
        ),
        todayDecoration: BoxDecoration(
          color: Colors.blue[300],
          shape: BoxShape.circle,
        ),
      ),
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
      ),
    );
  }

  /// 업무 상세 섹션
  Widget _buildWorkDetailsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '업무 상세',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: _businessWorkTypes.isEmpty
                      ? null
                      : () {
                          if (_workDetails.length >= 3) {
                            ToastHelper.showWarning('최대 3개까지만 추가할 수 있습니다');
                            return;
                          }
                          _showAddWorkDetailDialog();
                        },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('업무 추가'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
            if (_businessWorkTypes.isEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '업무 유형을 먼저 등록해주세요',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
            if (_workDetails.isNotEmpty) ...[
              const SizedBox(height: 16),
              ..._workDetails.asMap().entries.map((entry) {
                return _buildWorkDetailCard(entry.key, entry.value);
              }),
            ],
          ],
        ),
      ),
    );
  }

  /// 업무 상세 카드
  Widget _buildWorkDetailCard(int index, WorkDetailInput detail) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.grey[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: FormatHelper.parseColor(detail.workTypeColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: WorkTypeIcon.buildFromString(
                      detail.workTypeIcon,  // ✅ 문자열 직접 전달
                      color: Colors.white,
                      size: 20,
                    ),
                    ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.workType ?? '업무',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${detail.startTime} ~ ${detail.endTime}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => _removeWorkDetail(index),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getWageLabelFromType(detail.wageType),  // ✅ 수정됨
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Text(
                        '${detail.wage?.toString().replaceAllMapped(
                              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                              (m) => '${m[1]},',
                            )}원',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '필요 인원',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Text(
                        '${detail.requiredCount}명',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 지원 마감 설정 - jobType에 따라 분기
  Widget _buildDeadlineSelector() {
    // 단기 알바: N시간 전 자동 마감
    if (_selectedJobType == 'short') {
      return _buildHoursBeforeDeadline();
    }
    
    // 장기 근무: 특정 날짜+시간 고정
    return _buildFixedDateTimeDeadline();
  }

  /// N시간 전 자동 마감 (단기 알바용)
  Widget _buildHoursBeforeDeadline() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '지원 마감 설정',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            // 🔥 설명
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '각 업무별로 시작 시간 기준으로 자동 마감됩니다',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 시간 선택
            Row(
              children: [
                const Text(
                  '업무 시작',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 16),
                DropdownButton<int>(
                  value: _hoursBeforeStart,
                  items: List.generate(24, (index) => index + 1)
                      .map((hour) => DropdownMenuItem(
                            value: hour,
                            child: Text('$hour시간 전'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _hoursBeforeStart = value!;
                    });
                  },
                ),
                const SizedBox(width: 8),
                const Text('마감', style: TextStyle(fontSize: 14)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 특정 날짜+시간 고정 마감 (장기 근무용)
  Widget _buildFixedDateTimeDeadline() {
    // 상태 변수에 DateTime? _fixedDeadline 필요
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '지원 마감 설정',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '지원 마감 날짜와 시간을 직접 설정하세요',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 날짜+시간 선택 버튼
            InkWell(
              onTap: () async {
                final pickedDate = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                
                if (pickedDate != null && mounted) {
                  final pickedTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  
                  if (pickedTime != null) {
                    setState(() {
                      _fixedDeadline = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );
                    });
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '마감 일시',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fixedDeadline != null
                              ? DateFormat('yyyy-MM-dd HH:mm').format(_fixedDeadline!)
                              : '날짜와 시간을 선택하세요',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _fixedDeadline != null ? Colors.black : Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                    Icon(Icons.calendar_today, color: Colors.blue[700]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 마감 시간 미리보기
  Widget _buildDeadlinePreview() {
    if (_workDetails.isEmpty || _selectedDates.isEmpty) {
      return const SizedBox();
    }
    
    try {
      final firstWorkStart = _workDetails.first.startTime!;
      final earliestDate = _selectedDates.reduce((a, b) => a.isBefore(b) ? a : b);
      
      final timeParts = firstWorkStart.split(':');
      final startDateTime = DateTime(
        earliestDate.year,
        earliestDate.month,
        earliestDate.day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
      final deadline = startDateTime.subtract(Duration(hours: _hoursBeforeStart));
      
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${DateFormat('MM/dd (E)', 'ko_KR').format(earliestDate)} $firstWorkStart 근무',
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
            ),
            Text(
              '→ 마감: ${DateFormat('MM/dd (E) HH:mm', 'ko_KR').format(deadline)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.blue[700],
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      return const SizedBox();
    }
  }

  /// 설명 입력
  Widget _buildDescriptionInput() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextFormField(
          controller: _descriptionController,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: '상세 설명 (선택)',
            hintText: '추가 안내사항을 입력하세요',
            alignLabelWithHint: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }

  /// 그룹 연결 섹션
  Widget _buildGroupLinkSection() {
    final isGroupTO = _selectedDates.length > 1;  // 🔥 그룹 TO 여부 확인
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: _linkToExisting,
                  onChanged: isGroupTO ? null : (value) {  // 🔥 그룹 TO면 비활성화
                    setState(() {
                      _linkToExisting = value ?? false;
                      if (_linkToExisting) {
                        _loadRecentTOs();
                      }
                    });
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '기존 공고와 연결하기',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isGroupTO ? Colors.grey[400] : Colors.black,  // 🔥 비활성화 색상
                        ),
                      ),
                      if (isGroupTO) ...[
                        const SizedBox(height: 4),
                        Text(
                          '그룹 TO는 다른 공고와 연결할 수 없습니다',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            
            // 🔥 그룹 TO일 때는 드롭다운 숨김
            if (_linkToExisting && !isGroupTO) ...[
              const SizedBox(height: 12),
              if (_isLoadingRecentTOs)
                const Center(child: CircularProgressIndicator())
              else if (_myRecentTOs.isEmpty)
                Text(
                  '연결 가능한 최근 공고가 없습니다',
                  style: TextStyle(color: Colors.grey[600]),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _myRecentTOs.isNotEmpty && 
                        _myRecentTOs.any((to) => to.groupId == _selectedGroupId)
                      ? _selectedGroupId 
                      : null,
                  decoration: const InputDecoration(
                    labelText: '연결할 공고 선택',
                    border: OutlineInputBorder(),
                    hintText: '선택하세요',
                  ),
                  items: _myRecentTOs.map((to) {
                    String displayText;
                    
                    if (to.isGrouped && to.endDate != null) {
                      displayText = '${to.groupName ?? to.title} (${to.date.month}/${to.date.day}~${to.endDate!.month}/${to.endDate!.day})';
                    } else {
                      displayText = '${to.title} (${to.date.month}/${to.date.day})';
                    }
                    
                    return DropdownMenuItem(
                      value: to.groupId,
                      child: Text(displayText),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedGroupId = value);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 생성 버튼
  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isCreating ? null : _createTO,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[700],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: _isCreating
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'TO 생성',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  // ============================================================
  // 🛠️ 유틸리티 함수
  // ============================================================

  // ✅ NEW: 월의 몇 번째 주인지 계산
  /// 해당 날짜가 월의 몇 번째 주인지 반환
  int _getWeekOfMonth(DateTime date) {
    final firstDayOfMonth = DateTime(date.year, date.month, 1);
    final dayOfMonth = date.day;
    
    // 첫째 주는 1일부터 시작
    // 월요일 기준으로 주차 계산
    final firstMonday = firstDayOfMonth.weekday;
    
    // 간단한 계산: (일 + 첫째날 요일 - 1) / 7 + 1
    return ((dayOfMonth + firstMonday - 1) / 7).ceil();
  }

   /// 급여 타입 라벨 반환
  String _getWageLabelFromType(String wageType) {
    switch (wageType) {
      case 'hourly':
        return '시급';
      case 'daily':
        return '일급';
      case 'monthly':
        return '월급';
      default:
        return '급여';
    }
  }
}