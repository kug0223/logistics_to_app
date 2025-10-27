import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../models/business_model.dart';
import '../../models/to_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../models/business_work_type_model.dart';
import '../../utils/labor_standards.dart';

// ============================================================
// 📦 데이터 모델
// ============================================================

/// 업무 상세 입력 데이터 클래스
class WorkDetailInput {
  final String? workType;
  final String workTypeIcon;
  final String workTypeColor;
  final int? wage;
  final int? requiredCount;
  final String? startTime;
  final String? endTime;
  final String wageType; // ✅ 추가

  WorkDetailInput({
    this.workType,
    this.workTypeIcon = 'work',
    this.workTypeColor = '#2196F3',
    this.wage,
    this.requiredCount,
    this.startTime,
    this.endTime,
    this.wageType = 'hourly', // ✅ 추가
  });

  bool get isValid =>
      workType != null &&
      wage != null &&
      requiredCount != null &&
      startTime != null &&
      endTime != null;

  Map<String, dynamic> toMap() {
    return {
      'workType': workType!,
      'wage': wage!,
      'requiredCount': requiredCount!,
      'startTime': startTime!,
      'endTime': endTime!,
    };
  }
}

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
  String _dateMode = 'single'; // 'single' or 'multiple'
  List<DateTime> _selectedDates = [];
  List<String> _selectedWeekdays = [];
  DateTime _focusedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  bool _isCalendarExpanded = false;

  // 지원 마감
  DateTime? _selectedDeadlineDate;
  TimeOfDay? _selectedDeadlineTime;

  // 업무 상세
  List<WorkDetailInput> _workDetails = [];

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
      
      // 최근 7일 이내 TO만 필터링
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      
      final recentTOs = myBusinessTOs.where((to) {
        return to.createdAt.isAfter(sevenDaysAgo);
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

  /// TO 생성 실행
  Future<void> _createTO() async {
    if (!_formKey.currentState!.validate()) return;

    // 유효성 검증
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

    if (_selectedDeadlineDate == null || _selectedDeadlineTime == null) {
      ToastHelper.showError('지원 마감 시간을 설정해주세요');
      return;
    }
    // 지원 마감 DateTime 생성
    final applicationDeadline = DateTime(
      _selectedDeadlineDate!.year,
      _selectedDeadlineDate!.month,
      _selectedDeadlineDate!.day,
      _selectedDeadlineTime!.hour,
      _selectedDeadlineTime!.minute,
    );
    // ✅ 지원 마감 시간 검증
    final latestWorkDate = _selectedDates.reduce((a, b) => a.isAfter(b) ? a : b);
    final latestWorkDateTime = DateTime(
      latestWorkDate.year,
      latestWorkDate.month,
      latestWorkDate.day,
      23,
      59,
      59,
    );

    if (applicationDeadline.isAfter(latestWorkDateTime)) {
      ToastHelper.showError('지원 마감은 마지막 근무일(${latestWorkDate.month}/${latestWorkDate.day}) 23:59까지 가능합니다');
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

      // 연속된 날짜 그룹 생성
      final dateGroups = _groupConsecutiveDates();
      
      bool success = false;

      if (dateGroups.length == 1 && dateGroups[0].length == 1) {
        // 단일 날짜 TO
        success = await _createSingleTO(
          date: dateGroups[0][0],
          applicationDeadline: applicationDeadline,
          creatorUID: uid,
        );
      } else if (_isConsecutiveDates()) {
        // 연속된 날짜 그룹 TO
        final sortedDates = List<DateTime>.from(_selectedDates)..sort();
        success = await _createGroupTO(
          startDate: sortedDates.first,
          endDate: sortedDates.last,
          applicationDeadline: applicationDeadline,
          creatorUID: uid,
        );
      } else {
        // 비연속 날짜 - 그룹별로 생성
        success = await _createMultipleGroups(
          dateGroups: dateGroups,
          applicationDeadline: applicationDeadline,
          creatorUID: uid,
        );
      }

      if (success && mounted) {
        ToastHelper.showSuccess('TO가 생성되었습니다');
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('❌ TO 생성 실패: $e');
      ToastHelper.showError('TO 생성에 실패했습니다');
    } finally {
      setState(() => _isCreating = false);
    }
  }

  /// 단일 날짜 TO 생성
  Future<bool> _createSingleTO({
    required DateTime date,
    required DateTime applicationDeadline,
    required String creatorUID,
  }) async {
    try {
      final toId = await _firestoreService.createTOWithDetails(
        businessId: _selectedBusiness!.id,
        businessName: _selectedBusiness!.publicName,
        title: _titleController.text.trim(),
        date: date,
        applicationDeadline: applicationDeadline,
        workDetailsData: _workDetails.map((w) => w.toMap()).toList(),
        description: _descriptionController.text.trim(),
        creatorUID: creatorUID,
      );

      return toId != null;
    } catch (e) {
      print('❌ 단일 TO 생성 실패: $e');
      return false;
    }
  }

  /// 연속 날짜 그룹 TO 생성
  Future<bool> _createGroupTO({
    required DateTime startDate,
    required DateTime endDate,
    required DateTime applicationDeadline,
    required String creatorUID,
  }) async {
    try {
      // 신규 그룹 생성 (그룹 연결 기능은 Phase 2에서 구현 예정)
      return await _firestoreService.createTOGroup(
        businessId: _selectedBusiness!.id,
        businessName: _selectedBusiness!.publicName,
        groupName: _titleController.text.trim(),
        title: _titleController.text.trim(),
        startDate: startDate,
        endDate: endDate,
        workDetails: _workDetails.map((w) => {
          'workType': w.workType!,
          'workTypeIcon': w.workTypeIcon,
          'workTypeColor': w.workTypeColor,
          'wage': w.wage!,
          'requiredCount': w.requiredCount!,
          'startTime': w.startTime!,
          'endTime': w.endTime!,
        }).toList(),
        applicationDeadline: applicationDeadline,
        description: _descriptionController.text.trim(),
        creatorUID: creatorUID,
      );
    } catch (e) {
      print('❌ 그룹 TO 생성 실패: $e');
      return false;
    }
  }

  /// 비연속 날짜 그룹별 TO 생성
  Future<bool> _createMultipleGroups({
    required List<List<DateTime>> dateGroups,
    required DateTime applicationDeadline,
    required String creatorUID,
  }) async {
    try {
      int successCount = 0;

      for (var group in dateGroups) {
        if (group.length == 1) {
          // 단일 날짜
          final success = await _createSingleTO(
            date: group[0],
            applicationDeadline: applicationDeadline,
            creatorUID: creatorUID,
          );
          if (success) successCount++;
        } else {
          // 연속 날짜
          final success = await _createGroupTO(
            startDate: group.first,
            endDate: group.last,
            applicationDeadline: applicationDeadline,
            creatorUID: creatorUID,
          );
          if (success) successCount++;
        }
      }

      return successCount == dateGroups.length;
    } catch (e) {
      print('❌ 다중 그룹 TO 생성 실패: $e');
      return false;
    }
  }

  // ============================================================
  // 🎯 업무 추가/수정/삭제
  // ============================================================

  /// 업무 추가 다이얼로그
  Future<void> _showAddWorkDetailDialog() async {
    BusinessWorkTypeModel? selectedWorkType;
    String selectedWageType = 'hourly'; // ✅ 이 줄 추가
    String? startTime;
    String? endTime;
    final wageController = TextEditingController();
    final countController = TextEditingController();

    final result = await showDialog<WorkDetailInput>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('업무 추가'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 업무 유형 선택
                  const Text('업무 유형', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<BusinessWorkTypeModel>(
                    value: selectedWorkType,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '업무 선택',
                    ),
                    items: _businessWorkTypes.map((workType) {
                      return DropdownMenuItem<BusinessWorkTypeModel>(
                        value: workType,
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: _parseColor(workType.backgroundColor ?? '#2196F3'),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: _buildIconOrEmojiSmall(workType),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(workType.name),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedWorkType = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // ✅ 급여 타입 선택 추가
                  const Text('급여 타입', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildWageTypeButtonInline(
                          context: context,
                          label: '시급',
                          value: 'hourly',
                          selectedValue: selectedWageType,
                          onTap: () {
                            setDialogState(() {
                              selectedWageType = 'hourly';
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildWageTypeButtonInline(
                          context: context,
                          label: '일급',
                          value: 'daily',
                          selectedValue: selectedWageType,
                          onTap: () {
                            setDialogState(() {
                              selectedWageType = 'daily';
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildWageTypeButtonInline(
                          context: context,
                          label: '월급',
                          value: 'monthly',
                          selectedValue: selectedWageType,
                          onTap: () {
                            setDialogState(() {
                              selectedWageType = 'monthly';
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  // 근무 시간
                  const Text('근무 시간', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: startTime,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: '시작',
                          ),
                          items: _generateTimeList().map((time) {
                            return DropdownMenuItem(value: time, child: Text(time));
                          }).toList(),
                          onChanged: (value) => setDialogState(() => startTime = value),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('~', style: TextStyle(fontSize: 18)),
                      ),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: endTime,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: '종료',
                          ),
                          items: _generateTimeList().map((time) {
                            return DropdownMenuItem(value: time, child: Text(time));
                          }).toList(),
                          onChanged: (value) => setDialogState(() => endTime = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 급여 입력
                  Text(
                    _getWageLabelFromType(selectedWageType),  // ✅ 이것만!
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: wageController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      // ✅ 천단위 콤마 포맷터 추가
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        if (newValue.text.isEmpty) {
                          return newValue;
                        }
                        
                        final number = int.tryParse(newValue.text.replaceAll(',', ''));
                        if (number == null) {
                          return oldValue;
                        }
                        
                        final formatted = number.toString().replaceAllMapped(
                          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                          (Match m) => '${m[1]},',
                        );
                        
                        return TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(offset: formatted.length),
                        );
                      }),
                    ],
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: '금액을 입력하세요.',
                      suffixText: '원',
                      helperText: selectedWageType == 'hourly'
                          ? '2025년 최저시급: ${LaborStandards.formatCurrencyWithUnit(LaborStandards.currentMinimumWage)}'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 필요 인원
                  const Text('필요 인원', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: countController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '필요 인원 수 입력하세요.',
                      suffixText: '명',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (selectedWorkType == null ||
                      startTime == null ||
                      endTime == null ||
                      wageController.text.isEmpty ||
                      countController.text.isEmpty) {
                    ToastHelper.showError('모든 정보를 입력해주세요');
                    return;
                  }

                  final wage = int.tryParse(wageController.text.replaceAll(',', ''));
                  final count = int.tryParse(countController.text);

                  if (wage == null || wage <= 0) {
                    ToastHelper.showError('유효한 급여를 입력해주세요');
                    return;
                  }

                  if (count == null || count <= 0) {
                    ToastHelper.showError('유효한 인원 수를 입력해주세요');
                    return;
                  }

                  Navigator.pop(
                    context,
                    WorkDetailInput(
                      workType: selectedWorkType!.name,
                      workTypeIcon: selectedWorkType!.icon,
                      workTypeColor: selectedWorkType!.backgroundColor ?? '#2196F3',
                      wage: wage,
                      requiredCount: count,
                      startTime: startTime,
                      endTime: endTime,
                      wageType: selectedWageType, // ✅ 이 줄 추가
                    ),
                  );
                },
                child: const Text('추가'),
              ),
            ],
          );
        },
      ),
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

      if (_selectedDates.any((d) => _isSameDay(d, normalizedDay))) {
        _selectedDates.removeWhere((d) => _isSameDay(d, normalizedDay));
      } else {
        if (_selectedDates.length >= 30) {
          ToastHelper.showWarning('최대 30일까지만 선택할 수 있습니다');
          return;
        }
        _selectedDates.add(normalizedDay);
      }

      _focusedDay = focusedDay;
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
          value: _selectedBusiness,
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

  /// 제목 입력
  Widget _buildTitleInput() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextFormField(
          controller: _titleController,
          decoration: InputDecoration(
            labelText: 'TO 제목',
            hintText: '예: 물류센터 피킹 작업',
            prefixIcon: const Icon(Icons.title),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'TO 제목을 입력해주세요';
            }
            return null;
          },
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
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _focusedDay = focusedDay;
                    
                    final isAlreadySelected = _selectedDates.any((date) =>
                        date.year == selectedDay.year &&
                        date.month == selectedDay.month &&
                        date.day == selectedDay.day);
                    
                    if (isAlreadySelected) {
                      _selectedDates.removeWhere((date) =>
                          date.year == selectedDay.year &&
                          date.month == selectedDay.month &&
                          date.day == selectedDay.day);
                    } else {
                      if (_selectedDates.length >= 30) {
                        ToastHelper.showWarning('단기 알바는 최대 30일까지 선택 가능합니다');
                        return;
                      }
                      _selectedDates.add(selectedDay);
                    }
                  });
                },
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

  /// 요일 버튼들
  Widget _buildWeekdayButtons() {
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
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
            width: 48,
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
              '${count}일',
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
                    color: _parseColor(detail.workTypeColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: _buildIconFromString(detail.workTypeIcon, Colors.white),
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

  /// 지원 마감 선택
  Widget _buildDeadlineSelector() {
    // ✅ 에러 메시지 계산
    String? deadlineErrorMessage;
    if (_selectedDates.isNotEmpty && _selectedDeadlineDate != null && _selectedDeadlineTime != null) {
      final latestWorkDate = _selectedDates.reduce((a, b) => a.isAfter(b) ? a : b);
      final applicationDeadline = DateTime(
        _selectedDeadlineDate!.year,
        _selectedDeadlineDate!.month,
        _selectedDeadlineDate!.day,
        _selectedDeadlineTime!.hour,
        _selectedDeadlineTime!.minute,
      );
      
      final latestWorkDateTime = DateTime(
        latestWorkDate.year,
        latestWorkDate.month,
        latestWorkDate.day,
        23,
        59,
        59,
      );

      if (applicationDeadline.isAfter(latestWorkDateTime)) {
        deadlineErrorMessage = '⚠️ 지원 마감은 마지막 근무일(${latestWorkDate.month}/${latestWorkDate.day}) 23:59까지 가능합니다';
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '지원 마감 시간',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _selectedDeadlineDate ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                        locale: const Locale('ko', 'KR'),
                      );
                      if (date != null) {
                        setState(() => _selectedDeadlineDate = date);
                      }
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      _selectedDeadlineDate != null
                          ? '${_selectedDeadlineDate!.year}/${_selectedDeadlineDate!.month}/${_selectedDeadlineDate!.day}'
                          : '날짜 선택',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _selectedDeadlineTime ?? TimeOfDay.now(),
                      );
                      if (time != null) {
                        setState(() => _selectedDeadlineTime = time);
                      }
                    },
                    icon: const Icon(Icons.access_time),
                    label: Text(
                      _selectedDeadlineTime != null
                          ? '${_selectedDeadlineTime!.hour.toString().padLeft(2, '0')}:${_selectedDeadlineTime!.minute.toString().padLeft(2, '0')}'
                          : '시간 선택',
                    ),
                  ),
                ),
              ],
            ),
            // ✅ 에러 메시지 표시
            if (deadlineErrorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        deadlineErrorMessage,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.red[900],
                          fontWeight: FontWeight.w500,
                        ),
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
                  onChanged: (value) {
                    setState(() {
                      _linkToExisting = value ?? false;
                      if (_linkToExisting) {
                        _loadRecentTOs();
                      }
                    });
                  },
                ),
                const Expanded(
                  child: Text(
                    '기존 공고와 연결하기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (_linkToExisting) ...[
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
                  value: _myRecentTOs.isNotEmpty && 
                        _myRecentTOs.any((to) => to.groupId == _selectedGroupId)
                      ? _selectedGroupId 
                      : null, // ✅ 유효하지 않으면 null
                  decoration: const InputDecoration(
                    labelText: '연결할 공고 선택',
                    border: OutlineInputBorder(),
                    hintText: '선택하세요', // ✅ hint 추가
                  ),
                  items: _myRecentTOs.map((to) {
                    return DropdownMenuItem(
                      value: to.groupId,
                      child: Text('${to.title} (${to.date.month}/${to.date.day})'),
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

  /// 시간 목록 생성 (00:00 ~ 23:30)
  List<String> _generateTimeList() {
    final times = <String>[];
    for (int hour = 0; hour < 24; hour++) {
      for (int minute = 0; minute < 60; minute += 30) {
        times.add(
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
        );
      }
    }
    return times;
  }


  /// 색상 문자열 파싱
  Color _parseColor(String colorString) {
    try {
      return Color(int.parse(colorString.replaceFirst('#', '0xFF')));
    } catch (e) {
      return Colors.blue[700]!;
    }
  }

  /// 아이콘 문자열 파싱
  IconData _parseIcon(String iconString) {
    if (iconString.startsWith('material:')) {
      try {
        final codePoint = int.parse(iconString.substring(9));
        return IconData(codePoint, fontFamily: 'MaterialIcons');
      } catch (e) {
        return Icons.work_outline;
      }
    }

    switch (iconString.toLowerCase()) {
      case 'work':
      case 'work_outline':
        return Icons.work_outline;
      case 'inventory':
        return Icons.inventory_2_outlined;
      case 'local_shipping':
        return Icons.local_shipping_outlined;
      case 'warehouse':
        return Icons.warehouse_outlined;
      default:
        return Icons.work_outline;
    }
  }

  /// 아이콘 또는 이모지 위젯 생성 (작은 버전)
  Widget _buildIconOrEmojiSmall(BusinessWorkTypeModel workType) {
    if (workType.icon.startsWith('material:')) {
      Color iconColor = Colors.white;
      if (workType.color != null && workType.color!.isNotEmpty) {
        try {
          iconColor = _parseColor(workType.color!);
        } catch (e) {
          iconColor = Colors.white;
        }
      }
      return Icon(_parseIcon(workType.icon), size: 18, color: iconColor);
    } else {
      return Text(workType.icon, style: const TextStyle(fontSize: 16));
    }
  }

  /// 아이콘 또는 이모지 위젯 생성
  Widget _buildIconOrEmoji(BusinessWorkTypeModel workType) {
    if (workType.icon.startsWith('material:')) {
      Color iconColor = Colors.white;
      if (workType.color != null && workType.color!.isNotEmpty) {
        try {
          iconColor = _parseColor(workType.color!);
        } catch (e) {
          iconColor = Colors.white;
        }
      }
      return Icon(_parseIcon(workType.icon), size: 18, color: iconColor);
    } else {
      return Text(workType.icon, style: const TextStyle(fontSize: 16));
    }
  }

  /// 문자열로부터 아이콘 위젯 생성
  Widget _buildIconFromString(String iconString, Color color) {
    if (iconString.startsWith('material:')) {
      return Icon(_parseIcon(iconString), size: 20, color: color);
    } else {
      return Text(iconString, style: const TextStyle(fontSize: 18));
    }
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
  /// 급여 타입 선택 버튼 (인라인)
  Widget _buildWageTypeButtonInline({
    required BuildContext context,
    required String label,
    required String value,
    required String selectedValue,
    required VoidCallback onTap,
  }) {
    final isSelected = selectedValue == value;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[700] : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blue[700]! : Colors.grey[300]!,
            width: 2,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}