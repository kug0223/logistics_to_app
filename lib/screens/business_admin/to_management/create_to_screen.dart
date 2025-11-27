import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

// Models
import '../../../models/core/business_model.dart';
import '../../../models/core/to_model.dart';
import '../../../models/core/business_work_type_model.dart';
import '../../../models/work_detail_input.dart';

// Services & Providers
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/navigation_helper.dart';

// Widgets
import '../../../widgets/pickers/work_detail_dialog.dart';
import '../../../widgets/work_type_icon.dart';

// 공통 위젯
import 'widgets/to_widgets.dart';

/// ✨ TO 생성 화면 - 공통 위젯 적용
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
  final List<DateTime> _selectedDates = [];
  final List<String> _selectedWeekdays = [];
  DateTime _focusedDay = DateTime.now();
  bool _isCalendarExpanded = true; // ✅ 기본 펼침으로 변경
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  // 지원 마감
  int _hoursBeforeStart = 2;
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
    _loadMyBusinesses();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  // ============================================================
  // 📡 데이터 로딩
  // ============================================================

  /// 내 사업장 목록 로드 (승인된 것만)
  Future<void> _loadMyBusinesses() async {
    setState(() => _isLoading = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }

      final allBusinesses = await _firestoreService.getMyBusiness(uid);
      final approvedBusinesses = allBusinesses.where((b) => b.isApproved).toList();

      setState(() {
        _myBusinesses = approvedBusinesses;
        if (_myBusinesses.isNotEmpty) {
          _selectedBusiness = _myBusinesses.first;
          _loadWorkTypes();
        }
        _isLoading = false;
      });

      if (allBusinesses.isNotEmpty && approvedBusinesses.isEmpty) {
        ToastHelper.showWarning('승인된 사업장이 없습니다\n관리자 승인 후 TO를 생성할 수 있습니다');
      } else if (approvedBusinesses.isEmpty) {
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
      final allTOs = await _firestoreService.getGroupMasterTOs();
      
      final myBusinessTOs = allTOs.where((to) => 
        to.businessId == _selectedBusiness!.id
      ).toList();
      
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      final recentTOs = myBusinessTOs.where((to) {
        final checkDate = to.endDate ?? to.date;
        return checkDate.isAfter(today.subtract(const Duration(days: 1)));
      }).toList();

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
  // 🛠️ 유틸리티 함수
  // ============================================================

  /// 업무 추가 다이얼로그
  Future<void> _showAddWorkDetailDialog() async {
    if (_selectedBusiness == null) {
      ToastHelper.showWarning('사업장을 먼저 선택해주세요');
      return;
    }
    
    if (_businessWorkTypes.isEmpty) {
      ToastHelper.showWarning('업무 유형을 먼저 등록해주세요');
      return;
    }

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

  /// 날짜 선택/해제
  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      final normalizedDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
      _focusedDay = focusedDay;
      
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
      } else {
        _selectedDates.add(normalizedDay);
        _selectedDates.sort();
        
        if (_selectedDates.length >= 2 && !_linkToExisting) {
          _loadRecentTOs();
        }
      }
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// 연속 날짜 여부 확인
  bool _isConsecutiveDates() {
    if (_selectedDates.length <= 1) return true;
    
    final sorted = List<DateTime>.from(_selectedDates)..sort();
    
    for (int i = 1; i < sorted.length; i++) {
      final diff = sorted[i].difference(sorted[i - 1]).inDays;
      if (diff != 1) return false;
    }
    return true;
  }

  /// 연속 날짜 그룹화
  List<List<DateTime>> _groupConsecutiveDates() {
    if (_selectedDates.isEmpty) return [];
    
    final sorted = List<DateTime>.from(_selectedDates)..sort();
    List<List<DateTime>> groups = [];
    List<DateTime> currentGroup = [sorted[0]];

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
      _linkToExisting = false;
      _selectedGroupId = null;
    });
  }

  /// jobType 변경 시 초기화
  void _onJobTypeChanged(String newType) {
    setState(() {
      _selectedJobType = newType;
      // 이전 선택값 초기화
      _selectedDates.clear();
      _selectedWeekdays.clear();
      _rangeStart = null;
      _rangeEnd = null;
      _fixedDeadline = null;
      _linkToExisting = false;
      _selectedGroupId = null;
    });
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

    if (_selectedJobType == 'short') {
      if (_selectedDates.isEmpty) {
        ToastHelper.showError('날짜를 선택해주세요');
        return;
      }
    } else {
      if (_rangeStart == null || _rangeEnd == null) {
        ToastHelper.showError('계약 기간을 설정해주세요');
        return;
      }
      if (_selectedWeekdays.isEmpty) {
        ToastHelper.showError('근무 요일을 선택해주세요');
        return;
      }
      if (_fixedDeadline == null) {
        ToastHelper.showError('지원 마감 시간을 설정해주세요');
        return;
      }
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

      if (_selectedJobType == 'long_term') {
        success = await _createSingleTO(
          date: _rangeStart!,
          creatorUID: uid,
        );
      } else if (_selectedDates.length == 1) {
        success = await _createSingleTO(
          date: _selectedDates[0],
          creatorUID: uid,
        );
      } else {
        final sortedDates = List<DateTime>.from(_selectedDates)..sort();
        success = await _createGroupTO(
          dates: sortedDates,
          creatorUID: uid,
        );
      }

      if (success && mounted) {
        if (_selectedJobType == 'long_term') {
          ToastHelper.showSuccess('장기 근무 TO가 생성되었습니다');
        } else if (_selectedDates.length > 1) {
          ToastHelper.showSuccess('${_selectedDates.length}개의 TO가 그룹으로 생성되었습니다');
        } else {
          ToastHelper.showSuccess('TO가 생성되었습니다');
        }
        NavigationHelper.popWithChange(context);
      }
    } catch (e) {
      print('❌ TO 생성 실패: $e');
      ToastHelper.showError('TO 생성에 실패했습니다');
    } finally {
      setState(() => _isCreating = false);
    }
  }

  Future<bool> _createSingleTO({
    required DateTime date,
    required String creatorUID,
  }) async {
    try {
      DateTime finalDeadline;
      
      if (_selectedJobType == 'short') {
        final firstWorkStart = _workDetails.first.startTime!;
        final timeParts = firstWorkStart.split(':');
        final startDateTime = DateTime(
          date.year,
          date.month,
          date.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
        finalDeadline = startDateTime.subtract(Duration(hours: _hoursBeforeStart));
      } else {
        if (_fixedDeadline == null) {
          ToastHelper.showError('지원 마감 시간을 설정해주세요');
          return false;
        }
        finalDeadline = _fixedDeadline!;
      }
      
      final toId = await _firestoreService.createTOWithDetails(
        businessId: _selectedBusiness!.id,
        businessName: _selectedBusiness!.name,
        title: _titleController.text.trim(),
        date: date,
        workDetailsData: _workDetails.map((w) => {
          'workType': w.workType!,
          'workTypeIcon': w.workTypeIcon,
          'workTypeColor': w.workTypeColor,
          'workTypeBackgroundColor': w.workTypeBackgroundColor,
          'wage': w.wage!,
          'requiredCount': w.requiredCount!,
          'startTime': w.startTime!,
          'endTime': w.endTime!,
        }).toList(),
        applicationDeadline: finalDeadline,
        description: _descriptionController.text.trim(),
        creatorUID: creatorUID,
        deadlineType: _selectedJobType == 'short' ? 'HOURS_BEFORE' : 'FIXED_TIME',
        hoursBeforeStart: _selectedJobType == 'short' ? _hoursBeforeStart : null,
        jobType: _selectedJobType,
        workDays: _selectedJobType == 'long_term' ? _selectedWeekdays : null,
        startDate: _selectedJobType == 'long_term' ? _rangeStart : null,
        endDate: _selectedJobType == 'long_term' ? _rangeEnd : null,
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

      String finalGroupName;
      if (_groupNameController.text.trim().isNotEmpty) {
        finalGroupName = _groupNameController.text.trim();
      } else {
        if (_isConsecutiveDates()) {
          finalGroupName = '${DateFormat('MM/dd').format(startDate)} ~ ${DateFormat('MM/dd').format(endDate)} (${sortedDates.length}일)';
        } else {
          final dateGroups = _groupConsecutiveDates();
          finalGroupName = '${DateFormat('MM월').format(startDate)} 선택 근무 (${sortedDates.length}일, ${dateGroups.length}개 그룹)';
        }
      }

      bool allSuccess = true;

      for (int i = 0; i < sortedDates.length; i++) {
        final date = sortedDates[i];
        
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
          businessName: _selectedBusiness!.name,
          title: _titleController.text.trim(),
          date: date,
          workDetailsData: _workDetails.map((w) => {
            'workType': w.workType!,
            'workTypeIcon': w.workTypeIcon,
            'workTypeColor': w.workTypeColor,
            'workTypeBackgroundColor': w.workTypeBackgroundColor,
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
  // 🎨 UI 빌드
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('TO 생성')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_myBusinesses.isEmpty) {
      return _buildEmptyBusinessState(theme);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('TO 생성')),
      body: Container(
        color: Colors.grey[50],
        child: Form(
          key: _formKey,
          child: ListView(
            padding: ResponsiveHelper.cardPadding(context),
            children: [
              _buildBusinessSelector(theme),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              
              _buildJobTypeSelector(theme),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              
              // ✅ 공통 위젯 사용
              TOTitleSection(
                titleController: _titleController,
                groupNameController: _groupNameController,
                isGroupTO: _selectedDates.length > 1,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              
              _buildDateSelector(theme),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              
              // ✅ 공통 위젯 사용
              TOWorkDetailsSection(
                workDetailInputs: _workDetails,
                onAddWork: _showAddWorkDetailDialog,
                onRemoveWorkByIndex: _removeWorkDetail,
                showNoWorkTypeWarning: _businessWorkTypes.isEmpty,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              
              // ✅ 공통 위젯 사용
              TODeadlineSection(
                isLongTerm: _selectedJobType == 'long_term',
                hoursBeforeStart: _hoursBeforeStart,
                onHoursChanged: (hours) => setState(() => _hoursBeforeStart = hours),
                fixedDeadline: _fixedDeadline,
                onFixedDeadlineChanged: (dt) => setState(() => _fixedDeadline = dt),
                rangeEndDate: _rangeEnd,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              
              // ✅ 공통 위젯 사용
              TODescriptionSection(controller: _descriptionController),
              SizedBox(height: ResponsiveHelper.spacing(context, 24)),
              
              if (_selectedDates.length > 1) ...[
                _buildGroupLinkSection(theme),
                SizedBox(height: ResponsiveHelper.spacing(context, 24)),
              ],
              
              // ✅ 공통 위젯 사용
              TOActionButton.create(
                onPressed: _createTO,
                isLoading: _isCreating,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 40)),
            ],
          ),
        ),
      ),
    );
  }

  /// 사업장 없음 상태
  Widget _buildEmptyBusinessState(ThemeData theme) {
    return Scaffold(
      appBar: AppBar(title: const Text('TO 생성')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.business_outlined,
                size: ResponsiveHelper.iconSize(context, 64),
                color: theme.primaryColor.withOpacity(0.5),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 24)),
            Text(
              '등록된 사업장이 없습니다',
              style: ResponsiveHelper.titleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text(
              '사업장을 먼저 등록해주세요',
              style: ResponsiveHelper.bodyStyle(
                context,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 사업장 선택
  Widget _buildBusinessSelector(ThemeData theme) {
    return TOSectionContainer(
      child: DropdownButtonFormField<BusinessModel>(
        value: _selectedBusiness,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: '사업장 선택',
          labelStyle: ResponsiveHelper.bodyStyle(context),
          prefixIcon: Icon(
            Icons.business,
            color: theme.primaryColor,
            size: ResponsiveHelper.iconSize(context, 24),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.primaryColor, width: 2),
          ),
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
    );
  }

  /// 근무 유형 선택
  Widget _buildJobTypeSelector(ThemeData theme) {
    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '근무 유형',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Row(
            children: [
              Expanded(
                child: _buildJobTypeChip(
                  theme: theme,
                  label: '단기 알바',
                  value: 'short',
                  icon: Icons.today,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: _buildJobTypeChip(
                  theme: theme,
                  label: '1개월 이상',
                  value: 'long_term',
                  icon: Icons.event_note,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJobTypeChip({
    required ThemeData theme,
    required String label,
    required String value,
    required IconData icon,
  }) {
    final isSelected = _selectedJobType == value;
    return GestureDetector(
      onTap: () => _onJobTypeChanged(value),
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 16),
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.primaryColor,
                    theme.primaryColor.withOpacity(0.8),
                  ],
                )
              : null,
          color: isSelected ? null : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.primaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[700],
              size: ResponsiveHelper.iconSize(context, 20),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              label,
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 날짜 선택 - jobType에 따라 분기
  Widget _buildDateSelector(ThemeData theme) {
    if (_selectedJobType == 'short') {
      return _buildCalendarDateSelector(theme);
    }
    return _buildWeekdaySelector(theme);
  }

  /// 캘린더 날짜 선택 (단기 알바용)
  Widget _buildCalendarDateSelector(ThemeData theme) {
    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '근무 날짜 선택',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_selectedDates.isNotEmpty)
                Material(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: _clearAllDates,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 12),
                        vertical: ResponsiveHelper.spacing(context, 8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.clear_all,
                            size: ResponsiveHelper.iconSize(context, 18),
                            color: Colors.red[700],
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                          Text(
                            '전체 해제',
                            style: ResponsiveHelper.smallStyle(context).copyWith(
                              color: Colors.red[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          
          // 선택된 날짜 요약
          if (_selectedDates.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _buildDateSummary(theme),
          ],

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 캘린더 펼치기/접기
          Material(
            color: theme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () {
                setState(() {
                  _isCalendarExpanded = !_isCalendarExpanded;
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 16),
                  vertical: ResponsiveHelper.spacing(context, 12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isCalendarExpanded ? Icons.expand_less : Icons.expand_more,
                      color: theme.primaryColor,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Text(
                      _isCalendarExpanded ? '캘린더 접기' : '캘린더 펼치기',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: theme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 캘린더
          if (_isCalendarExpanded) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              padding: ResponsiveHelper.cardPadding(context),
              child: TableCalendar(
                locale: 'ko_KR',
                firstDay: DateTime.now(),
                lastDay: DateTime.now().add(const Duration(days: 90)),
                focusedDay: _focusedDay,
                calendarFormat: CalendarFormat.month,
                selectedDayPredicate: (day) {
                  return _selectedDates.any((date) =>
                      date.year == day.year &&
                      date.month == day.month &&
                      date.day == day.day);
                },
                onDaySelected: _onDaySelected,
                calendarStyle: CalendarStyle(
                  selectedDecoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.primaryColor,
                        theme.primaryColor.withOpacity(0.8),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  todayDecoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                ),
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 날짜 요약 표시
  Widget _buildDateSummary(ThemeData theme) {
    final groups = _groupConsecutiveDates();

    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor.withOpacity(0.1),
            theme.primaryColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.primaryColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: ResponsiveHelper.iconSize(context, 16),
                color: theme.primaryColor,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '선택된 날짜: ${_selectedDates.length}일',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: groups.map((group) {
              if (group.length == 1) {
                return _buildSingleDateChip(theme, group[0]);
              } else {
                return _buildDateRangeChip(theme, group.first, group.last, group.length);
              }
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleDateChip(ThemeData theme, DateTime date) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.primaryColor,
            theme.primaryColor.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.primaryColor.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${date.month}/${date.day}',
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedDates.removeWhere((d) => _isSameDay(d, date));
              });
            },
            child: Icon(
              Icons.close,
              size: ResponsiveHelper.iconSize(context, 14),
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeChip(ThemeData theme, DateTime start, DateTime end, int count) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.green[600]!,
            Colors.green[400]!,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${start.month}/${start.day} ~ ${end.month}/${end.day}',
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 6),
              vertical: ResponsiveHelper.spacing(context, 2),
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count일',
              style: ResponsiveHelper.tinyStyle(context).copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedDates.removeWhere((d) {
                  return !d.isBefore(start) && !d.isAfter(end);
                });
              });
            },
            child: Icon(
              Icons.close,
              size: ResponsiveHelper.iconSize(context, 14),
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// 요일 선택기 (장기 근무용)
  Widget _buildWeekdaySelector(ThemeData theme) {
    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '계약 기간',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 시작일/종료일
          Row(
            children: [
              Expanded(
                child: _buildDateField(
                  theme: theme,
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
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                ),
                child: Icon(
                  Icons.arrow_forward,
                  color: theme.primaryColor,
                ),
              ),
              Expanded(
                child: _buildDateField(
                  theme: theme,
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
          
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          Divider(color: Colors.grey[300]),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          Text(
            '근무 요일 선택',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '※ 매주 반복되는 근무 요일을 선택하세요',
            style: ResponsiveHelper.smallStyle(
              context,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 요일 버튼들
          _buildWeekdayButtons(theme),
          
          // 선택 요약
          if (_selectedWeekdays.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.green[50]!,
                    Colors.green[100]!,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.green[700],
                        size: ResponsiveHelper.iconSize(context, 18),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Text(
                        '주 ${_selectedWeekdays.length}일 근무',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: Colors.green[900],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    '선택된 요일: ${_selectedWeekdays.join(', ')}',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: Colors.green[800],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDateField({
    required ThemeData theme,
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              Text(
                date != null
                    ? DateFormat('yyyy-MM-dd').format(date)
                    : '선택하세요',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  color: date != null ? Colors.black : Colors.grey[400],
                  fontWeight: date != null ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeekdayButtons(ThemeData theme) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonWidth = (constraints.maxWidth - 48) / 7;
        
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: weekdays.map((day) {
            final isSelected = _selectedWeekdays.contains(day);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedWeekdays.remove(day);
                  } else {
                    _selectedWeekdays.add(day);
                  }
                });
              },
              child: Container(
                width: buttonWidth,
                height: buttonWidth,
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            theme.primaryColor,
                            theme.primaryColor.withOpacity(0.8),
                          ],
                        )
                      : null,
                  color: isSelected ? null : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: theme.primaryColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    day,
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      color: isSelected ? Colors.white : Colors.grey[700],
                      fontWeight: FontWeight.bold,
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

  /// 그룹 연결 섹션
  Widget _buildGroupLinkSection(ThemeData theme) {
    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '기존 공고에 연결',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Switch(
                value: _linkToExisting,
                onChanged: (value) {
                  setState(() {
                    _linkToExisting = value;
                    if (!value) {
                      _selectedGroupId = null;
                    }
                  });
                },
                activeColor: theme.primaryColor,
              ),
            ],
          ),
          
          if (_linkToExisting) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            if (_isLoadingRecentTOs)
              const Center(child: CircularProgressIndicator())
            else if (_myRecentTOs.isEmpty)
              Text(
                '연결할 수 있는 공고가 없습니다',
                style: ResponsiveHelper.bodyStyle(
                  context,
                  color: Colors.grey[600],
                ),
              )
            else
              DropdownButtonFormField<String>(
                value: _myRecentTOs.any((to) => to.groupId == _selectedGroupId)
                    ? _selectedGroupId
                    : null,
                decoration: InputDecoration(
                  labelText: '연결할 공고 선택',
                  labelStyle: ResponsiveHelper.bodyStyle(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
    );
  }
}