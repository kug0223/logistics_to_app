import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

// Models
import '../../../models/core/business_model.dart';
import '../../../models/core/to_model.dart';
import '../../../models/core/business_work_type_model.dart';
import '../../../models/work_detail_input.dart';
import '../../../models/core/work_detail_model.dart';

// Services & Providers
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/navigation_helper.dart';
import '../../../utils/dialog_helper.dart';

// Theme
import '../../../theme/app_colors.dart';

// Widgets
import '../../../widgets/pickers/create&edit_work_detail_dialog.dart';

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
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  // 지원 마감
  int _hoursBeforeStart = 2;
  DateTime? _fixedDeadline; 
  // 예약 공개
  String _publishMode = 'immediate';  // 'immediate' | 'scheduled'
  int _publishDaysBefore = 1;         // D-1, D-2, D-3
  String _publishTime = '14:00';      // 공개 시간

  // 업무 상세
  final List<WorkDetailInput> _workDetails = [];

  // 그룹 연결
  bool _linkToExisting = false;
  String? _selectedGroupId;
  List<TOModel> _myRecentTOs = [];
  // 기존 공고 불러오기
  List<TOModel> _recentTOsForLoad = [];


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
      debugPrint('❌ 사업장 로드 실패: $e');
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
      debugPrint('❌ 업무 유형 로드 실패: $e');
      ToastHelper.showError('업무 유형을 불러올 수 없습니다');
    }
  }
  // ============================================================
  // 📋 기존 공고 불러오기
  // ============================================================

  /// 기존 공고 불러오기 다이얼로그
  Future<void> _showLoadFromExistingDialog() async {
    if (_selectedBusiness == null) {
      ToastHelper.showWarning('먼저 사업장을 선택해주세요');
      return;
    }

    DialogHelper.showLoading(context, message: '공고 목록 불러오는 중...');

    try {
      final allTOs = await _firestoreService.getTOsByBusiness(_selectedBusiness!.id);
      allTOs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _recentTOsForLoad = allTOs.take(30).toList();
    } catch (e) {
      debugPrint('❌ TO 목록 로드 실패: $e');
      if (mounted) Navigator.pop(context);
      ToastHelper.showError('공고 목록을 불러올 수 없습니다');
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);

    final selectedTO = await showDialog<TOModel>(
      context: context,
      builder: (context) => _buildLoadFromExistingDialog(),
    );

    if (selectedTO != null) {
      await _loadDataFromTO(selectedTO);
    }
  }

  /// 선택한 TO에서 데이터 불러오기
  Future<void> _loadDataFromTO(TOModel to) async {
    DialogHelper.showLoading(context, message: '데이터 불러오는 중...');

    try {
      final workDetails = await _firestoreService.getWorkDetails(to.id);

      if (!mounted) return;
      Navigator.pop(context);

      setState(() {
        _titleController.text = to.title;
        _descriptionController.text = to.description ?? '';
        _workDetails.clear();
        for (var work in workDetails) {
          _workDetails.add(WorkDetailInput(
            workType: work.workType,
            workTypeIcon: work.workTypeIcon,
            workTypeColor: work.workTypeColor,
            workTypeBackgroundColor: work.workTypeBackgroundColor,
            wage: work.wage,
            wageType: work.wageType,
            requiredCount: work.requiredCount,
            startTime: work.startTime,
            endTime: work.endTime,
          ));
        }
      });

      ToastHelper.showSuccess('공고 정보를 불러왔습니다');
    } catch (e) {
      debugPrint('❌ 데이터 불러오기 실패: $e');
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      ToastHelper.showError('데이터를 불러오는데 실패했습니다');
    }
  }

  /// 기존 공고 불러오기 다이얼로그 UI
  Widget _buildLoadFromExistingDialog() {
    final theme = Theme.of(context);
    String searchQuery = '';

    return StatefulBuilder(
      builder: (context, setDialogState) {
        final filteredTOs = searchQuery.isEmpty
            ? _recentTOsForLoad
            : _recentTOsForLoad.where((to) =>
                to.title.toLowerCase().contains(searchQuery.toLowerCase())).toList();

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
              maxWidth: 500,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 헤더
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                  decoration: BoxDecoration(
                    color: theme.primaryColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.file_copy_outlined,
                        color: Colors.white,
                        size: ResponsiveHelper.iconSize(context, 24),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Expanded(
                        child: Text(
                          '기존 공고 불러오기',
                          style: ResponsiveHelper.subtitleStyle(context).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: Colors.white,
                          size: ResponsiveHelper.iconSize(context, 24),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // 검색
                Padding(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '공고 제목 검색...',
                      prefixIcon: Icon(Icons.search, size: ResponsiveHelper.iconSize(context, 20)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 16),
                        vertical: ResponsiveHelper.spacing(context, 12),
                      ),
                    ),
                    style: ResponsiveHelper.bodyStyle(context),
                    onChanged: (value) => setDialogState(() => searchQuery = value),
                  ),
                ),

                // 목록
                Expanded(
                  child: filteredTOs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: ResponsiveHelper.iconSize(context, 48),
                                color: AppColors.grey400,
                              ),
                              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                              Text(
                                searchQuery.isEmpty ? '등록된 공고가 없습니다' : '검색 결과가 없습니다',
                                style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 12)),
                          itemCount: filteredTOs.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.divider),
                          itemBuilder: (context, index) {
                            final to = filteredTOs[index];
                            return _buildTOListTile(to);
                          },
                        ),
                ),

                // 안내
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                  color: AppColors.grey100,
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: ResponsiveHelper.iconSize(context, 16),
                        color: AppColors.grey600,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Text(
                        '제목, 업무상세, 설명만 불러옵니다',
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// TO 목록 아이템
  Widget _buildTOListTile(TOModel to) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(context, to),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 4),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          child: Row(
            children: [
              // 날짜 배지
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 10),
                  vertical: ResponsiveHelper.spacing(context, 6),
                ),
                decoration: BoxDecoration(
                  color: to.isLongTerm ? AppColors.longTermBg : theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  DateFormat('MM/dd').format(to.date),
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: to.isLongTerm ? AppColors.longTermDark : theme.primaryColor,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),

              // 제목 및 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      to.title,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                    Row(
                      children: [
                        if (to.isLongTerm) ...[
                          Icon(
                            Icons.repeat,
                            size: ResponsiveHelper.iconSize(context, 12),
                            color: AppColors.longTermDark,
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            '장기',
                            style: ResponsiveHelper.tinyStyle(context, color: AppColors.longTermDark),
                          ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        ],
                        Icon(
                          Icons.people_outline,
                          size: ResponsiveHelper.iconSize(context, 12),
                          color: AppColors.grey500,
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                        Text(
                          '${to.totalRequired}명',
                          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 화살표
              Icon(
                Icons.chevron_right,
                color: AppColors.grey400,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 최근 TO 목록 로드 (그룹 연결용)
  Future<void> _loadRecentTOs() async {
    if (_selectedBusiness == null) return;

    setState(() => _isLoadingRecentTOs = true);

    try {
      final allTOs = await _firestoreService.getMasterTOsOnly();
      
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
      debugPrint('❌ 최근 TO 로드 실패: $e');
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
  /// 업무 수정 다이얼로그
  Future<void> _editWorkDetail(int index) async {
    final detail = _workDetails[index];
    
    // WorkDetailInput → 임시 WorkDetailModel 변환
    final tempModel = WorkDetailModel(
      id: 'temp',
      workType: detail.workType!,
      workTypeIcon: detail.workTypeIcon,
      workTypeColor: detail.workTypeColor,
      workTypeBackgroundColor: detail.workTypeBackgroundColor,
      wage: detail.wage!,
      wageType: detail.wageType,
      requiredCount: detail.requiredCount!,
      currentCount: 0,
      startTime: detail.startTime!,
      endTime: detail.endTime!,
      order: index,
      createdAt: DateTime.now(),
    );

    final result = await WorkDetailDialog.showEditDialog(
      context: context,
      work: tempModel,
      businessWorkTypes: _businessWorkTypes,  // ✅ 업무 유형 변경 가능
    );

    if (result != null) {
      setState(() {
        _workDetails[index] = WorkDetailInput(
          workType: result['workType'] ?? detail.workType,
          workTypeIcon: result['workTypeIcon'] ?? detail.workTypeIcon,
          workTypeColor: result['workTypeColor'] ?? detail.workTypeColor,
          workTypeBackgroundColor: result['workTypeBackgroundColor'] ?? detail.workTypeBackgroundColor,
          wage: result['wage'],
          wageType: result['wageType'],
          requiredCount: result['requiredCount'],
          startTime: result['startTime'],
          endTime: result['endTime'],
        );
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
  void _onDateToggle(DateTime date) {
    setState(() {
      final normalizedDay = DateTime(date.year, date.month, date.day);
      
      if (_selectedDates.any((d) => _isSameDay(d, normalizedDay))) {
        _selectedDates.removeWhere((d) => _isSameDay(d, normalizedDay));
        
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
  /// 요일 선택/해제
  void _onWeekdayToggle(String day) {
    setState(() {
      if (_selectedWeekdays.contains(day)) {
        _selectedWeekdays.remove(day);
      } else {
        _selectedWeekdays.add(day);
      }
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
      // 예약 공개 초기화
      _publishMode = 'immediate';
      _publishDaysBefore = 1;
      _publishTime = '14:00';
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
      debugPrint('❌ TO 생성 실패: $e');
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
        finalDeadline = startDateTime.subtract(Duration(hours: _hoursBeforeStart)).toUtc();  // 🔥 .toUtc() 추가
      } else {
        if (_fixedDeadline == null) {
          ToastHelper.showError('지원 마감 시간을 설정해주세요');
          return false;
        }
        finalDeadline = _fixedDeadline!.toUtc();  // 🔥 .toUtc() 추가
      }
      
      final toId = await _firestoreService.createTOWithDetails(
        businessId: _selectedBusiness!.id,
        businessName: _selectedBusiness!.name,
        title: _titleController.text.trim(),
        date: date,
        workDetailsData: _workDetails.map((w) => w.toMap()).toList(),
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
        // ✅ 예약 공개 설정
        publishMode: _publishMode,
        publishDaysBefore: _publishMode == 'scheduled' ? _publishDaysBefore : null,
        publishTime: _publishMode == 'scheduled' ? _publishTime : null,
      );

      return toId != null;
    } catch (e) {
      debugPrint('❌ 단일 TO 생성 실패: $e');
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
      final startDate = sortedDates.first;
      final endDate = sortedDates.last;

      // ═══════════════════════════════════════════════════════════
      // Step 1: 그룹명 결정
      // ═══════════════════════════════════════════════════════════
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

      // ═══════════════════════════════════════════════════════════
      // Step 2: 그룹 정보 계산
      // ═══════════════════════════════════════════════════════════
      int totalRequiredPerDay = 0;
      for (var detail in _workDetails) {
        totalRequiredPerDay += detail.requiredCount ?? 0;
      }
      
      final wages = _workDetails.map((d) => d.wage ?? 0).toList();
      final minWage = wages.isNotEmpty ? wages.reduce((a, b) => a < b ? a : b) : 0;
      final maxWage = wages.isNotEmpty ? wages.reduce((a, b) => a > b ? a : b) : 0;
      final wageType = _workDetails.isNotEmpty ? (_workDetails.first.wageType ?? 'hourly') : 'hourly';
      
      // 예약 공개 시간 계산
      DateTime? publishAt;
      bool shouldPublishImmediately = _publishMode == 'immediate';
      
      if (_publishMode == 'scheduled') {
        final targetDate = startDate.subtract(Duration(days: _publishDaysBefore));
        final timeParts = _publishTime.split(':');
        publishAt = DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
        
        if (publishAt.isBefore(DateTime.now())) {
          shouldPublishImmediately = true;
        }
      }

      // ═══════════════════════════════════════════════════════════
      // Step 3: groups 컬렉션에 그룹 문서 먼저 생성
      // ═══════════════════════════════════════════════════════════
      final groupId = await _firestoreService.createGroup(
        groupName: finalGroupName,
        businessId: _selectedBusiness!.id,
        businessName: _selectedBusiness!.name,
        businessAddress: _selectedBusiness!.address,
        businessCity: _selectedBusiness!.city,
        businessDistrict: _selectedBusiness!.district,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        startDate: startDate,
        endDate: endDate,
        totalRequired: totalRequiredPerDay * sortedDates.length,
        minWage: minWage,
        maxWage: maxWage,
        wageType: wageType,
        workDetailCount: _workDetails.length,
        publishMode: _publishMode,
        publishAt: publishAt,
        isPublished: shouldPublishImmediately,
        publishDaysBefore: _publishMode == 'scheduled' ? _publishDaysBefore : null,
        publishTime: _publishMode == 'scheduled' ? _publishTime : null,
        creatorUID: creatorUID,
      );
      
      if (groupId == null) {
        ToastHelper.showError('그룹 생성에 실패했습니다.');
        return false;
      }
      
      debugPrint('✅ groups 컬렉션 문서 생성 완료: $groupId');

      // ═══════════════════════════════════════════════════════════
      // Step 4: 각 날짜별 TO 생성
      // ═══════════════════════════════════════════════════════════
      bool allSuccess = true;

      for (int i = 0; i < sortedDates.length; i++) {
        final date = sortedDates[i];
        
        final localDate = date.toLocal();
        final firstWorkStart = _workDetails.first.startTime!;
        final timeParts = firstWorkStart.split(':');
        final startDateTime = DateTime(
          localDate.year,
          localDate.month,
          localDate.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
        final finalDeadline = startDateTime.subtract(Duration(hours: _hoursBeforeStart)).toUtc();

        final toId = await _firestoreService.createTOWithDetails(
          businessId: _selectedBusiness!.id,
          businessName: _selectedBusiness!.name,
          title: _titleController.text.trim(),
          date: date,
          workDetailsData: _workDetails.map((w) => w.toMap()).toList(),
          applicationDeadline: finalDeadline,
          description: _descriptionController.text.trim(),
          creatorUID: creatorUID,
          hoursBeforeStart: _hoursBeforeStart,
          groupId: groupId,
          groupName: finalGroupName,
          startDate: startDate,
          endDate: endDate,
          isGroupMaster: false,  // 🔄 groups 컬렉션 사용으로 모두 false
          // 예약 공개 설정
          publishMode: _publishMode,
          publishDaysBefore: _publishMode == 'scheduled' ? _publishDaysBefore : null,
          publishTime: _publishMode == 'scheduled' ? _publishTime : null,
        );

        if (toId == null) {
          allSuccess = false;
          debugPrint('❌ TO 생성 실패: ${DateFormat('yyyy-MM-dd').format(date)}');
        }
      }

      // ═══════════════════════════════════════════════════════════
      // Step 5: 그룹 통계 동기화
      // ═══════════════════════════════════════════════════════════
      await _firestoreService.syncGroupStats(groupId);

      return allSuccess;
    } catch (e) {
      debugPrint('❌ 그룹 TO 생성 실패: $e');
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
      appBar: AppBar(
        title: const Text('TO 생성'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.file_copy_outlined,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
            onPressed: _selectedBusiness != null ? _showLoadFromExistingDialog : null,
            tooltip: '기존 공고 불러오기',
          ),
        ],
      ),
      body: Container(
        color: AppColors.grey50,
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
                onEditWorkByIndex: _editWorkDetail,
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
              
              // ✅ 예약 공개 설정
              TOPublishSection(
                publishMode: _publishMode,
                onPublishModeChanged: (mode) => setState(() => _publishMode = mode),
                publishDaysBefore: _publishDaysBefore,
                onDaysBeforeChanged: (days) => setState(() => _publishDaysBefore = days),
                publishTime: _publishTime,
                onTimeChanged: (time) => setState(() => _publishTime = time),
                previewDates: _selectedJobType == 'long_term' 
                    ? (_rangeStart != null ? [_rangeStart!] : [])
                    : _selectedDates,
                isLongTerm: _selectedJobType == 'long_term',
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
                color: AppColors.grey600,
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
        initialValue: _selectedBusiness,
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
            borderSide: BorderSide(color: AppColors.grey300!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.grey300!),
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
                  label: '단기 근무',
                  value: 'short',
                  icon: Icons.today,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: _buildJobTypeChip(
                  theme: theme,
                  label: '고정 근무',
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
          color: isSelected ? null : AppColors.grey100,
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
              color: isSelected ? Colors.white : AppColors.grey700,
              size: ResponsiveHelper.iconSize(context, 20),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              label,
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                color: isSelected ? Colors.white : AppColors.grey700,
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
    return TODateSelector(
      isLongTerm: _selectedJobType == 'long_term',
      // 단기 알바용
      selectedDates: _selectedDates,
      onDateToggle: _onDateToggle,
      onClearAll: _clearAllDates,
      // 장기 근무용
      rangeStart: _rangeStart,
      rangeEnd: _rangeEnd,
      selectedWeekdays: _selectedWeekdays,
      onRangeStartChanged: (date) => setState(() => _rangeStart = date),
      onRangeEndChanged: (date) => setState(() => _rangeEnd = date),
      onWeekdayToggle: _onWeekdayToggle,
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
                activeThumbColor: theme.primaryColor,
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
                  color: AppColors.grey600,
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _myRecentTOs.any((to) => to.groupId == _selectedGroupId)
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