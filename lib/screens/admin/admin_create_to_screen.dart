import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart'; // ✅ NEW
import '../../models/business_model.dart';
import '../../models/to_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../models/business_work_type_model.dart';
import '../../utils/labor_standards.dart'; // ✅ NEW

/// ✅ 업무 상세 입력 데이터 클래스 (시간 정보 포함)
class WorkDetailInput {
  final String? workType;
  final String workTypeIcon;      // ✅ 추가
  final String workTypeColor;     // ✅ 추가
  final int? wage;
  final int? requiredCount;
  final String? startTime; // ✅ NEW
  final String? endTime; // ✅ NEW

  WorkDetailInput({
    this.workType,
    this.workTypeIcon = 'work',      // ✅ 기본값 추가
    this.workTypeColor = '#2196F3',  // ✅ 기본값 추가
    this.wage,
    this.requiredCount,
    this.startTime, // ✅ NEW
    this.endTime, // ✅ NEW
  });

  bool get isValid =>
      workType != null &&
      wage != null &&
      requiredCount != null &&
      startTime != null && // ✅ NEW
      endTime != null; // ✅ NEW

  Map<String, dynamic> toMap() {
    return {
      'workType': workType!,
      'wage': wage!,
      'requiredCount': requiredCount!,
      'startTime': startTime!, // ✅ NEW
      'endTime': endTime!, // ✅ NEW
    };
  }
}

/// TO 생성 화면 - 업무별 근무시간 포함
class AdminCreateTOScreen extends StatefulWidget {
  const AdminCreateTOScreen({super.key});

  @override
  State<AdminCreateTOScreen> createState() => _AdminCreateTOScreenState();
}

class _AdminCreateTOScreenState extends State<AdminCreateTOScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();

  // 컨트롤러
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  
  // ✅ 근무 유형
  String _selectedJobType = 'short'; // 'short' 또는 'long_term'
  // ✅ NEW: 급여 유형
  String _wageType = 'hourly'; // 'hourly', 'daily', 'per_task', 'monthly'

  // 상태 변수
  bool _isLoading = true;
  bool _isCreating = false;
  List<BusinessModel> _myBusinesses = [];
  BusinessModel? _selectedBusiness;
  List<BusinessWorkTypeModel> _businessWorkTypes = [];

  // 기본 입력 값
  String _dateMode = 'single'; // 'single' 또는 'range'
  DateTime? _selectedDate;      // 단일 날짜
  DateTime? _startDate;         // 범위 시작일
  DateTime? _endDate;           // 범위 종료일
  
  // ✅ NEW Phase A: 캘린더 복수 선택
  List<DateTime> _selectedDates = []; // 선택된 날짜 목록
  DateTime _focusedDay = DateTime.now(); // 캘린더 포커스
  CalendarFormat _calendarFormat = CalendarFormat.month; // 캘린더 형식
  bool _isCalendarExpanded = false; // ✅ NEW: 캘린더 펼침 상태
  bool _isRangeSelecting = false; // ✅ NEW: 범위 선택 모드
  
  DateTime? _selectedDeadlineDate;
  TimeOfDay? _selectedDeadlineTime;

  // ✅ 업무 상세 리스트 (최대 3개, 시간 정보 포함)
  List<WorkDetailInput> _workDetails = [];
  
  // ✅ NEW Phase 2: 그룹 연결 관련 변수 추가 (여기에 추가!)
  bool _linkToExisting = false; // 기존 공고와 연결 여부
  String? _selectedGroupId; // 선택한 그룹 ID
  List<TOModel> _myRecentTOs = []; // 최근 TO 목록
  bool _isLoadingRecentTOs = false; // 최근 TO 로딩 상태

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
  /// 업무 추가 다이얼로그
  Future<void> _showAddWorkDetailDialog() async {
    BusinessWorkTypeModel? selectedWorkType;
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
                            // ✅ 아이콘 표시
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: _parseColor(workType.color ?? '#2196F3').withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _parseIcon(workType.icon ?? 'work'),
                                color: _parseColor(workType.color ?? '#2196F3'),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(workType.name),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedWorkType = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
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
                          onChanged: (value) {
                            setDialogState(() => startTime = value);
                          },
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('~'),
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
                          onChanged: (value) {
                            setDialogState(() => endTime = value);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // 시급/급여
                  Text(
                    _wageType == 'hourly' ? '시급'
                    : _wageType == 'daily' ? '일급'
                    : _wageType == 'per_task' ? '건별 금액'
                    : '월급',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: wageController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: '15000',
                      suffixText: '원',
                      helperText: '2025년 최저시급: ${LaborStandards.formatCurrencyWithUnit(LaborStandards.currentMinimumWage)}',
                      helperStyle: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 필요 인원
                  const Text('필요 인원', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: countController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '1',
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
                  if (selectedWorkType == null) {
                    ToastHelper.showWarning('업무 유형을 선택하세요.');
                    return;
                  }
                  if (startTime == null || endTime == null) {
                    ToastHelper.showWarning('근무 시간을 선택하세요.');
                    return;
                  }
                  if (wageController.text.isEmpty) {
                    ToastHelper.showWarning('금액을 입력하세요.');
                    return;
                  }
                  if (countController.text.isEmpty) {
                    ToastHelper.showWarning('필요 인원을 입력하세요.');
                    return;
                  }

                  final detail = WorkDetailInput(
                    workType: selectedWorkType!.name,
                    workTypeIcon: selectedWorkType!.icon ?? 'work', // ✅
                    workTypeColor: selectedWorkType!.color ?? '#2196F3', // ✅
                    wage: int.tryParse(wageController.text),
                    requiredCount: int.tryParse(countController.text),
                    startTime: startTime,
                    endTime: endTime,
                  );

                  Navigator.pop(context, detail);
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

  /// 내 사업장 불러오기
  Future<void> _loadMyBusinesses() async {
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
        if (_myBusinesses.length == 1) {
          _selectedBusiness = _myBusinesses.first;
          _loadBusinessWorkTypes(_myBusinesses.first.id);
        }
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 사업장 불러오기 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
    }
  }

  /// 사업장별 업무 유형 로드
  Future<void> _loadBusinessWorkTypes(String businessId) async {
    try {
      final workTypes = await _firestoreService.getBusinessWorkTypes(businessId);
      
      setState(() {
        _businessWorkTypes = workTypes;
      });

      print('✅ 업무 유형 로드: ${workTypes.length}개');
      
      // ✅ NEW: 각 업무 유형 정보 출력
      for (var wt in workTypes) {
        print('  - ${wt.name}: icon=${wt.icon}, color=${wt.color}');
      }
      
      if (workTypes.isEmpty) {
        ToastHelper.showWarning('등록된 업무 유형이 없습니다.\n설정에서 업무 유형을 먼저 등록하세요.');
      }
    } catch (e) {
      print('❌ 업무 유형 로드 실패: $e');
      ToastHelper.showError('업무 유형을 불러올 수 없습니다');
    }
  }
  // ✅ NEW Phase 2: 최근 TO 로드 메서드 추가 (여기에 추가!)
  /// 최근 TO 목록 로드 (그룹 연결용)
  Future<void> _loadRecentTOs() async {
    setState(() => _isLoadingRecentTOs = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) return;

      final recentTOs = await _firestoreService.getRecentTOsByUser(uid, days: 30);
      
      setState(() {
        _myRecentTOs = recentTOs;
        _isLoadingRecentTOs = false;
      });

      print('✅ 최근 TO 로드 완료: ${recentTOs.length}개');
    } catch (e) {
      print('❌ 최근 TO 로드 실패: $e');
      setState(() => _isLoadingRecentTOs = false);
    }
  }
  /// 범위 내 날짜 추가
  void _addDateRange(DateTime start, DateTime end) {
    final daysInRange = <DateTime>[];
    DateTime current = start;
    
    while (!current.isAfter(end)) {
      final normalized = DateTime(current.year, current.month, current.day);
      daysInRange.add(normalized);
      current = current.add(const Duration(days: 1));
    }
    
    print('📅 범위 내 날짜: ${daysInRange.length}개');
    
    // 중복 제거
    final newDates = daysInRange.where((date) {
      return !_selectedDates.any((d) => 
        d.year == date.year && d.month == date.month && d.day == date.day
      );
    }).toList();
    
    print('➕ 새로 추가할 날짜: ${newDates.length}개');
    
    // 30일 체크
    if (_selectedDates.length + newDates.length > 30) {
      ToastHelper.showWarning('최대 30일까지만 선택할 수 있습니다.');
      return;
    }
    
    _selectedDates.addAll(newDates);
    _selectedDates.sort(); // ✅ 정렬
    
    print('📊 전체 선택된 날짜: ${_selectedDates.length}개');
    print('📆 날짜 목록: ${_selectedDates.map((d) => '${d.month}/${d.day}').join(', ')}');
  }
  /// 날짜 토글 또는 추가
  void _toggleOrAddDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    
    print('🔍 _toggleOrAddDate: ${normalized.month}/${normalized.day}');
    
    // 이미 선택되어 있는지 확인
    final existingIndex = _selectedDates.indexWhere((d) => 
      d.year == normalized.year && 
      d.month == normalized.month && 
      d.day == normalized.day
    );
    
    if (existingIndex != -1) {
      // 해제
      print('❌ 해제');
      _selectedDates.removeAt(existingIndex);
    } else {
      // 추가
      if (_selectedDates.length < 30) {
        print('✅ 추가');
        _selectedDates.add(normalized);
      } else {
        ToastHelper.showWarning('최대 30일까지만 선택할 수 있습니다.');
        return;
      }
    }
    
    // 정렬
    _selectedDates.sort();
    
    print('📊 현재 선택: ${_selectedDates.length}개');
    print('📆 ${_selectedDates.map((d) => '${d.month}/${d.day}').join(', ')}');
  }

  /// 단일 날짜 토글
  void _toggleSingleDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    
    final existingIndex = _selectedDates.indexWhere((d) {
      return d.year == normalized.year && 
            d.month == normalized.month && 
            d.day == normalized.day;
    });
    
    if (existingIndex != -1) {
      _selectedDates.removeAt(existingIndex);
    } else {
      if (_selectedDates.length < 30) {
        _selectedDates.add(normalized);
        _selectedDates.sort();
      } else {
        ToastHelper.showWarning('최대 30일까지만 선택할 수 있습니다.');
      }
    }
  }

  /// 연속된 날짜 그룹화
  List<List<DateTime>> _groupConsecutiveDates() {
    if (_selectedDates.isEmpty) return [];
    
    // ✅ 정렬 확실히
    final sorted = List<DateTime>.from(_selectedDates)..sort();
    
    print('🔍 그룹화 시작: ${sorted.length}개 날짜');
    print('   날짜 목록: ${sorted.map((d) => '${d.month}/${d.day}').join(', ')}');
    
    final groups = <List<DateTime>>[];
    List<DateTime> currentGroup = [sorted.first];
    
    for (int i = 1; i < sorted.length; i++) {
      final diff = sorted[i].difference(currentGroup.last).inDays;
      
      print('   ${sorted[i-1].month}/${sorted[i-1].day} → ${sorted[i].month}/${sorted[i].day}: 차이 ${diff}일');
      
      if (diff == 1) {
        // 연속됨
        currentGroup.add(sorted[i]);
        print('     ✅ 연속 - 현재 그룹에 추가');
      } else {
        // 끊김
        groups.add(List.from(currentGroup));
        print('     ❌ 끊김 - 새 그룹 시작');
        currentGroup = [sorted[i]];
      }
    }
    
    groups.add(List.from(currentGroup));
    
    print('🔍 그룹화 완료: ${groups.length}개 그룹');
    for (var i = 0; i < groups.length; i++) {
      if (groups[i].length == 1) {
        print('  그룹 ${i+1}: ${groups[i].first.month}/${groups[i].first.day} (단일)');
      } else {
        print('  그룹 ${i+1}: ${groups[i].first.month}/${groups[i].first.day} ~ ${groups[i].last.month}/${groups[i].last.day} (${groups[i].length}일)');
      }
    }
    
    return groups;
  }

  /// 연속 날짜인지 확인
  bool _isConsecutiveDates() {
    if (_selectedDates.length <= 1) return true;
    
    final sorted = List<DateTime>.from(_selectedDates)..sort();
    
    for (int i = 0; i < sorted.length - 1; i++) {
      final diff = sorted[i + 1].difference(sorted[i]).inDays;
      if (diff != 1) return false;
    }
    
    return true;
  }
  /// TO 생성
  Future<void> _createTO() async {
    if (!_formKey.currentState!.validate()) return;
    
    // ✅ NEW: 날짜 선택 검증 추가
    if (_selectedJobType == 'short' && _selectedDates.isEmpty) {
      ToastHelper.showWarning('근무 날짜를 선택하세요.');
      return;
    }

    // 업무 상세 검증
    if (_workDetails.isEmpty) {
      ToastHelper.showWarning('최소 1개의 업무를 추가해주세요.');
      return;
    }

    if (_workDetails.any((w) => !w.isValid)) {
      ToastHelper.showWarning('모든 업무 정보를 입력해주세요.');
      return;
    }

    // 사업장 선택 확인
    if (_selectedBusiness == null) {
      ToastHelper.showWarning('사업장을 선택해주세요.');
      return;
    }

    // ✅ NEW: 날짜 선택 확인 (모드별 분기)
    if (_dateMode == 'single') {
      if (_selectedDate == null) {
        ToastHelper.showWarning('근무 날짜를 선택해주세요.');
        return;
      }
    } else {
      if (_startDate == null || _endDate == null) {
        ToastHelper.showWarning('시작일과 종료일을 선택해주세요.');
        return;
      }
      if (_endDate!.isBefore(_startDate!)) {
        ToastHelper.showWarning('종료일은 시작일 이후여야 합니다.');
        return;
      }
    }

    // 마감 시간 확인
    if (_selectedDeadlineDate == null || _selectedDeadlineTime == null) {
      ToastHelper.showWarning('지원 마감 시간을 선택해주세요.');
      return;
    }

    final applicationDeadline = DateTime(
      _selectedDeadlineDate!.year,
      _selectedDeadlineDate!.month,
      _selectedDeadlineDate!.day,
      _selectedDeadlineTime!.hour,
      _selectedDeadlineTime!.minute,
    );
    // ✅ NEW: 날짜 범위 모드 추가 검증
    if (_dateMode == 'range') {
      // 1. 최대 30일 제한
      final daysDiff = _endDate!.difference(_startDate!).inDays + 1;
      if (daysDiff > 30) {
        ToastHelper.showWarning('최대 30일까지만 선택할 수 있습니다.');
        return;
      }
      
      // 2. 마감 시간은 시작일 이전이어야 함
      final startDateOnly = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
      final deadlineDateOnly = DateTime(applicationDeadline.year, applicationDeadline.month, applicationDeadline.day);
      
      if (deadlineDateOnly.isAfter(startDateOnly)) {
        ToastHelper.showWarning('마감 시간은 시작일 이전 또는 당일이어야 합니다.');
        return;
        }
    }
    

    setState(() => _isCreating = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }

      bool success;

      if (_dateMode == 'single') {
        // ✅ 단일 날짜 TO 생성 (기존 방식)
        success = await _createSingleTO(uid, applicationDeadline);
      } else {
        // ✅ 날짜 범위 TO 그룹 생성 (신규)
        success = await _createTOGroup(uid, applicationDeadline);
      }

      if (success && mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('❌ TO 생성 실패: $e');
      ToastHelper.showError('TO 생성 중 오류가 발생했습니다.');
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }
  /// ✅ NEW: 실시간 검증 에러 체크 (여기에 추가!)
  bool _hasValidationError() {
    if (_dateMode == 'range') {
      // 1. 30일 초과
      if (_startDate != null && _endDate != null) {
        final daysDiff = _endDate!.difference(_startDate!).inDays + 1;
        if (daysDiff > 30) return true;
      }
      
      // 2. 마감시간 검증 (종료일 당일까지 허용)
      if (_endDate != null && _selectedDeadlineDate != null) {
        final endDateOnly = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
        final deadlineDateOnly = DateTime(
          _selectedDeadlineDate!.year, 
          _selectedDeadlineDate!.month, 
          _selectedDeadlineDate!.day
        );
        
        // 마감이 종료일보다 이후면 에러
        if (deadlineDateOnly.isAfter(endDateOnly)) {
          return true;
        }
      }
    } 
    // ✅ NEW: 단일 날짜 모드도 검증
    else if (_dateMode == 'single') {
      if (_selectedDate != null && _selectedDeadlineDate != null) {
        final dateDateOnly = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
        final deadlineDateOnly = DateTime(
          _selectedDeadlineDate!.year, 
          _selectedDeadlineDate!.month, 
          _selectedDeadlineDate!.day
        );
        
        // 마감시간이 근무일보다 이후면 에러 (당일까지 허용)
        if (deadlineDateOnly.isAfter(dateDateOnly)) {
          return true;
        }
      }
    }
    
    return false;
  }

  /// ✅ 단일 날짜 TO 생성 (기존 방식 그대로)
  Future<bool> _createSingleTO(String uid, DateTime applicationDeadline) async {
    try {
      // 총 필요 인원 계산
      int totalRequired = 0;
      for (var work in _workDetails) {
        totalRequired += work.requiredCount!;
      }

      final toData = {
        'businessId': _selectedBusiness!.id,
        'businessName': _selectedBusiness!.name,
        'groupId': null,
        'groupName': null,
        'startDate': null,
        'endDate': null,
        'isGroupMaster': false,
        'title': _titleController.text.trim(),
        'date': Timestamp.fromDate(_selectedDate!),
        'startTime': _workDetails[0].startTime!,
        'endTime': _workDetails[0].endTime!,
        'applicationDeadline': Timestamp.fromDate(applicationDeadline),
        'totalRequired': totalRequired,
        'totalConfirmed': 0,
        'description': _descriptionController.text.trim(),
        'creatorUID': uid,
        'createdAt': FieldValue.serverTimestamp(),
      };

      final toDoc = await FirebaseFirestore.instance.collection('tos').add(toData);

      // WorkDetails 생성
      for (int i = 0; i < _workDetails.length; i++) {
        await FirebaseFirestore.instance
            .collection('tos')
            .doc(toDoc.id)
            .collection('workDetails')
            .add({
          'workType': _workDetails[i].workType!,
          'workTypeIcon': _workDetails[i].workTypeIcon,
          'workTypeColor': _workDetails[i].workTypeColor,
          'wage': _workDetails[i].wage!,
          'requiredCount': _workDetails[i].requiredCount!,
          'currentCount': 0,
          'startTime': _workDetails[i].startTime!,
          'endTime': _workDetails[i].endTime!,
          'order': i,
        });
      }

      ToastHelper.showSuccess('TO가 생성되었습니다!');
      return true;
    } catch (e) {
      print('❌ 단일 TO 생성 실패: $e');
      return false;
    }
  }

  /// ✅ NEW: 날짜 범위 TO 그룹 생성
  Future<bool> _createTOGroup(String uid, DateTime applicationDeadline) async {
    try {
      return await _firestoreService.createTOGroup(
        businessId: _selectedBusiness!.id,
        businessName: _selectedBusiness!.name,
        groupName: _titleController.text.trim(),
        title: _titleController.text.trim(),
        startDate: _startDate!,
        endDate: _endDate!,
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
        creatorUID: uid,
      );
    } catch (e) {
      print('❌ TO 그룹 생성 실패: $e');
      return false;
    }
  }

  /// ✅ NEW: 시간 목록 생성 (00:00 ~ 23:30, 30분 단위)
  List<String> _generateTimeList() {
    final times = <String>[];
    for (int hour = 0; hour < 24; hour++) {
      for (int minute = 0; minute < 60; minute += 30) {
        final h = hour.toString().padLeft(2, '0');
        final m = minute.toString().padLeft(2, '0');
        times.add('$h:$m');
      }
    }
    return times;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_myBusinesses.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('TO 생성'),
          backgroundColor: Colors.blue[700],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.business, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '등록된 사업장이 없습니다',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Text(
                '사업장을 먼저 등록해주세요',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
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
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🏢 사업장 선택
              _buildSectionTitle('🏢 사업장 선택'),
              _buildBusinessDropdown(),
              const SizedBox(height: 24),
              
              // 📝 공고 제목
              _buildSectionTitle('📝 공고 제목'),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  hintText: '예: 피킹 보조 구합니다',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '공고 제목을 입력하세요';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              
              // ✅ NEW: 근무 유형 선택
              _buildSectionTitle('💼 근무 유형'),
              _buildJobTypeSelector(),
              const SizedBox(height: 24),
              
              // ✅ 조건부 렌더링
              if (_selectedJobType == 'short')
                _buildShortTermForm()
              else
                _buildLongTermForm(),
            ],
          ),
        ),
      ),
    );
  }
  /// ✅ NEW: 근무 유형 선택 (버튼 형식)
  Widget _buildJobTypeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _buildJobTypeButton(
              label: '단기 (~30일)',
              icon: Icons.calendar_today,
              description: '시급 기준',
              isSelected: _selectedJobType == 'short',
              onTap: () {
                setState(() {
                  _selectedJobType = 'short';
                  _workDetails.clear();
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildJobTypeButton(
              label: '1개월+',
              icon: Icons.work,
              description: '월급 기준',
              isSelected: _selectedJobType == 'long_term',
              onTap: () {
                setState(() {
                  _selectedJobType = 'long_term';
                  _workDetails.clear();
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobTypeButton({
    required String label,
    required IconData icon,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[700] : Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 28,
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.grey[800],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? Colors.white70 : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ✅ 단기 폼
  Widget _buildShortTermForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 📅 근무 날짜
        _buildSectionTitle('📅 근무 날짜 (최대 30일)'),
        _buildCalendarSection(),
        const SizedBox(height: 24),
        
        // 💰 급여 유형
        _buildSectionTitle('💰 급여 유형'),
        _buildWageTypeSelector(),
        const SizedBox(height: 24),
        
        // ⏰ 지원 마감
        _buildSectionTitle('⏰ 지원 마감'),
        _buildDeadlinePicker(),
        const SizedBox(height: 24),
        
        // 💼 업무 상세
        _buildSectionTitle('💼 업무 상세'),
        _buildWorkDetailsSection(),
        const SizedBox(height: 24),
        
        // 📋 상세 설명
        _buildSectionTitle('📋 상세 설명 (선택)'),
        TextFormField(
          controller: _descriptionController,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '추가 설명을 입력하세요',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        
        // 생성 버튼
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _hasValidationError() ? null : _createTO,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _isCreating
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'TO 생성',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildWageTypeChip(String label, String value) {
    final isSelected = _wageType == value;
    
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _wageType = value;
        });
      },
      selectedColor: Colors.blue[700],
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.grey[800],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: isSelected ? Colors.blue[700]! : Colors.grey[300]!,
      ),
    );
  }
  Widget _buildWageTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 급여 유형 버튼들
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildWageTypeChip('시급', 'hourly'),
            _buildWageTypeChip('일급', 'daily'),
            _buildWageTypeChip('건별', 'per_task'),
            _buildWageTypeChip('월급', 'monthly'),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // 금액 입력 (업무 추가 시 입력하므로 여기서는 안내만)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.grey[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '구체적인 금액은 아래 업무 추가에서 입력하세요',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 업무 상세 섹션
  Widget _buildWorkDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 추가된 업무들 표시
        if (_workDetails.isNotEmpty) ...[
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _workDetails.length,
            itemBuilder: (context, index) {
              final work = _workDetails[index];
              
              // ✅ 해당 업무 유형 정보 찾기 (null-safe)
              BusinessWorkTypeModel? workTypeInfo;
              if (work.workType != null && work.workType!.isNotEmpty) {
                try {
                  workTypeInfo = _businessWorkTypes.firstWhere(
                    (wt) => wt.name == work.workType!,
                  );
                } catch (e) {
                  workTypeInfo = null;
                }
              }
              
              final iconName = workTypeInfo?.icon ?? 'work';
              final colorHex = workTypeInfo?.color ?? '#2196F3';
              final workTypeName = work.workType ?? '업무';
              
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _parseColor(colorHex).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _parseIcon(iconName), // ✅ 이미 기본값 처리됨
                      color: _parseColor(colorHex), // ✅ 이미 기본값 처리됨
                    ),
                  ),
                  title: Text(
                    workTypeName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            '${work.startTime ?? '00:00'} ~ ${work.endTime ?? '00:00'}',
                            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.payments, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            LaborStandards.formatCurrencyWithUnit(work.wage ?? 0),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.people, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            '${work.requiredCount ?? 0}명',
                            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _workDetails.removeAt(index);
                      });
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        
        // 업무 추가 버튼
        if (_workDetails.length < 3)
          OutlinedButton.icon(
            onPressed: _businessWorkTypes.isEmpty ? null : _showAddWorkDetailDialog,
            icon: const Icon(Icons.add),
            label: Text('업무 추가 (${_workDetails.length}/3)'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              side: BorderSide(
                color: _businessWorkTypes.isEmpty ? Colors.grey[300]! : Colors.blue[700]!,
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  '최대 3개까지 추가할 수 있습니다',
                  style: TextStyle(color: Colors.orange[900]),
                ),
              ],
            ),
          ),
          
        // ✅ 업무 유형 없을 때 안내
        if (_businessWorkTypes.isEmpty && _selectedBusiness != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.grey[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '등록된 업무 유형이 없습니다.\n설정에서 업무 유형을 먼저 등록하세요.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// ✅ 아이콘 파싱
  IconData _parseIcon(String iconName) {
    final iconMap = {
      'work': Icons.work,
      'local_shipping': Icons.local_shipping,
      'inventory': Icons.inventory,
      'warehouse': Icons.warehouse,
      'shopping_cart': Icons.shopping_cart,
      'construction': Icons.construction,
      'cleaning_services': Icons.cleaning_services,
      'restaurant': Icons.restaurant,
      'store': Icons.store,
      'agriculture': Icons.agriculture,
    };
    return iconMap[iconName] ?? Icons.work;
  }

  /// ✅ 색상 파싱
  Color _parseColor(String colorHex) {
    try {
      return Color(int.parse(colorHex.replaceAll('#', '0xFF')));
    } catch (e) {
      return Colors.blue;
    }
  }

  /// ✅ 1개월+ 폼 (Phase B에서 구현)
  Widget _buildLongTermForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green[200]!),
          ),
          child: Row(
            children: [
              Icon(Icons.construction, color: Colors.green[700]),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '1개월+ 계약직: Phase B에서 구현 예정\n(요일 선택, 월급, 4대보험 등)',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.green[900],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        
        Center(
          child: Column(
            children: [
              Icon(Icons.work_outline, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '준비 중입니다',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildBusinessDropdown() {
    if (_myBusinesses.length == 1) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.business, color: Colors.blue[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _myBusinesses.first.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<BusinessModel>(
      value: _selectedBusiness,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        hintText: '사업장 선택',
      ),
      items: _myBusinesses.map((business) {
        return DropdownMenuItem(
          value: business,
          child: Text(business.name),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedBusiness = value;
          if (value != null) {
            _loadBusinessWorkTypes(value.id);
          }
        });
      },
      validator: (value) {
        if (value == null) return '사업장을 선택하세요';
        return null;
      },
    );
  }

  Widget _buildBusinessInfoCard(BusinessModel business) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  business.address,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ✅ 지원 마감 선택
  Widget _buildDeadlinePicker() {
    // ✅ 마감일 검증
    String? deadlineError;
    if (_selectedDates.isNotEmpty && _selectedDeadlineDate != null) {
      // 가장 빠른 근무 날짜
      final earliestWorkDate = _selectedDates.reduce((a, b) => a.isBefore(b) ? a : b);
      final workDateOnly = DateTime(earliestWorkDate.year, earliestWorkDate.month, earliestWorkDate.day);
      final deadlineDateOnly = DateTime(_selectedDeadlineDate!.year, _selectedDeadlineDate!.month, _selectedDeadlineDate!.day);
      
      if (deadlineDateOnly.isAfter(workDateOnly)) {
        deadlineError = '⚠️ 마감일은 근무 시작일(${earliestWorkDate.month}/${earliestWorkDate.day}) 이전이어야 합니다';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 마감 날짜 선택
        InkWell(
          onTap: () async {
            final DateTime? picked = await showDatePicker(
              context: context,
              initialDate: _selectedDeadlineDate ?? DateTime.now(),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 90)),
              locale: const Locale('ko', 'KR'),
            );
            
            if (picked != null) {
              setState(() {
                _selectedDeadlineDate = picked;
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(
                color: deadlineError != null ? Colors.red[300]! : Colors.grey[300]!,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  color: deadlineError != null ? Colors.red[700] : Colors.blue[700],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedDeadlineDate == null
                        ? '마감 날짜 선택'
                        : '${_selectedDeadlineDate!.year}-${_selectedDeadlineDate!.month.toString().padLeft(2, '0')}-${_selectedDeadlineDate!.day.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 16,
                      color: _selectedDeadlineDate == null ? Colors.grey[600] : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // 마감 시간 선택
        InkWell(
          onTap: () async {
            final TimeOfDay? picked = await showTimePicker(
              context: context,
              initialTime: _selectedDeadlineTime ?? const TimeOfDay(hour: 18, minute: 0),
              builder: (context, child) {
                return Localizations.override(
                  context: context,
                  locale: const Locale('ko', 'KR'),
                  child: child,
                );
              },
            );
            
            if (picked != null) {
              setState(() {
                _selectedDeadlineTime = picked;
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedDeadlineTime == null
                        ? '마감 시간 선택'
                        : '${_selectedDeadlineTime!.hour.toString().padLeft(2, '0')}:${_selectedDeadlineTime!.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 16,
                      color: _selectedDeadlineTime == null ? Colors.grey[600] : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // ✅ 에러 메시지 표시
        if (deadlineError != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    deadlineError,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.red[900],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// ✅ 업무 상세 카드 (시간 정보 표시)
  Widget _buildWorkDetailCard(WorkDetailInput detail, int index) {
    // ✅ 해당 업무 유형 찾기
    final workType = _businessWorkTypes.firstWhere(
      (wt) => wt.name == detail.workType,
      orElse: () => _businessWorkTypes.first,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ 아이콘 + 업무명 표시
                Row(
                  children: [
                    // 배경색이 있으면 Container로 감싸기
                    if (workType.backgroundColor != null && workType.backgroundColor!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _parseColor(workType.backgroundColor!),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: _buildIconOrEmoji(workType),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildIconOrEmoji(workType),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        detail.workType ?? '',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                
                // ✅ NEW: 근무 시간 표시
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${detail.startTime} ~ ${detail.endTime}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.payments, size: 14, color: Colors.green[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${detail.wage?.toString().replaceAllMapped(
                        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                        (Match m) => '${m[1]},',
                      )}원',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.people, size: 14, color: Colors.blue[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${detail.requiredCount}명',
                      style: TextStyle(fontSize: 13, color: Colors.blue[700]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () {
              setState(() {
                _workDetails.removeAt(index);
              });
            },
          ),
        ],
      ),
    );
  }
  // ✅ NEW Phase 2: 그룹 연결 섹션 위젯 추가 (여기에 추가!)
  /// 그룹 연결 섹션
  Widget _buildGroupLinkSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 체크박스
          CheckboxListTile(
            value: _linkToExisting,
            onChanged: (value) {
              setState(() {
                _linkToExisting = value ?? false;
                if (_linkToExisting && _myRecentTOs.isEmpty) {
                  _loadRecentTOs(); // 최근 TO 로드
                }
              });
            },
            title: const Text(
              '기존 공고와 같은 TO입니다',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '지원자 명단이 합쳐집니다',
              style: TextStyle(fontSize: 13),
            ),
            contentPadding: EdgeInsets.zero,
          ),

          // 연결할 TO 선택 (체크박스 선택 시에만 표시)
          if (_linkToExisting) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            
            if (_isLoadingRecentTOs)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_myRecentTOs.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '최근 30일 이내 생성한 TO가 없습니다.\n새 그룹으로 생성됩니다.',
                  style: TextStyle(fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              )
            else ...[
              const Text(
                '연결할 공고 선택',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedGroupId,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  hintText: '공고 선택',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                // ✅ 선택된 항목 표시 (제목만)
                selectedItemBuilder: (BuildContext context) {
                  return _myRecentTOs.map((to) {
                    return Text(
                      to.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    );
                  }).toList();
                },
                // ✅ 드롭다운 펼쳤을 때 표시 (제목 + 날짜)
                items: _myRecentTOs.map((to) {
                  return DropdownMenuItem<String>(
                    value: to.id,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          to.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${to.formattedDate} (${to.weekday})',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedGroupId = value;
                  });
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
  
  /// ✅ 캘린더 섹션 (단순 클릭 방식)
  Widget _buildCalendarSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 캘린더 토글 버튼
        InkWell(
          onTap: () {
            setState(() {
              _isCalendarExpanded = !_isCalendarExpanded;
            });
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Row(
              children: [
                Icon(
                  _isCalendarExpanded ? Icons.calendar_today : Icons.calendar_month,
                  color: Colors.blue[700],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedDates.isEmpty 
                        ? '날짜 선택 (최대 30일)'
                        : '캘린더 ${_isCalendarExpanded ? "접기" : "펼치기"}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[900],
                    ),
                  ),
                ),
                Icon(
                  _isCalendarExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.blue[700],
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // ✅ 캘린더
        if (_isCalendarExpanded) ...[
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TableCalendar(
              firstDay: DateTime.now(),
              lastDay: DateTime.now().add(const Duration(days: 90)),
              focusedDay: _focusedDay,
              
              // ✅ 범위 선택 모드 OFF
              rangeSelectionMode: RangeSelectionMode.toggledOff,
              
              // 선택된 날짜
              selectedDayPredicate: (day) {
                return _selectedDates.any((selectedDate) =>
                  isSameDay(selectedDate, day)
                );
              },
              
              // ✅ 단순 클릭
              onDaySelected: (selectedDay, focusedDay) {
                print('📅 날짜 클릭: ${selectedDay.month}/${selectedDay.day}');
                
                setState(() {
                  _focusedDay = focusedDay;
                  _toggleOrAddDate(selectedDay);
                });
              },
              
              // 캘린더 형식
              calendarFormat: _calendarFormat,
              onFormatChanged: (format) {
                setState(() {
                  _calendarFormat = format;
                });
              },
              
              // 페이지 변경
              onPageChanged: (focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                });
              },
              
              // 스타일링
              calendarStyle: CalendarStyle(
                selectedDecoration: BoxDecoration(
                  color: Colors.blue[700]!,
                  shape: BoxShape.circle,
                ),
                selectedTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                todayDecoration: BoxDecoration(
                  color: Colors.blue[200]!,
                  shape: BoxShape.circle,
                ),
                todayTextStyle: TextStyle(
                  color: Colors.blue[900],
                  fontWeight: FontWeight.bold,
                ),
                outsideDaysVisible: false,
              ),
              
              // ✅ 연속 날짜 시각화
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, focusedDay) {
                  final isSelected = _selectedDates.any((d) => 
                    d.year == day.year && d.month == day.month && d.day == day.day
                  );
                  
                  if (!isSelected) return null;
                  
                  // 연속 체크
                  final yesterday = day.subtract(const Duration(days: 1));
                  final tomorrow = day.add(const Duration(days: 1));
                  
                  final hasYesterday = _selectedDates.any((d) => 
                    d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day
                  );
                  
                  final hasTomorrow = _selectedDates.any((d) => 
                    d.year == tomorrow.year && d.month == tomorrow.month && d.day == tomorrow.day
                  );
                  
                  return Container(
                    margin: EdgeInsets.only(
                      left: hasYesterday ? 0 : 4,
                      right: hasTomorrow ? 0 : 4,
                      top: 4,
                      bottom: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue[700],
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(hasYesterday ? 0 : 20),
                        right: Radius.circular(hasTomorrow ? 0 : 20),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
                todayBuilder: (context, day, focusedDay) {
                  final isSelected = _selectedDates.any((d) => 
                    d.year == day.year && d.month == day.month && d.day == day.day
                  );
                  
                  if (isSelected) {
                    return Container(
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.blue[700],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.orange, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          '${day.day}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }
                  
                  return Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          color: Colors.blue[900],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
              
              headerStyle: HeaderStyle(
                formatButtonVisible: true,
                titleCentered: true,
                formatButtonShowsNext: false,
                formatButtonDecoration: BoxDecoration(
                  color: Colors.blue[100]!,
                  borderRadius: BorderRadius.circular(8),
                ),
                formatButtonTextStyle: TextStyle(
                  color: Colors.blue[900]!,
                  fontSize: 12,
                ),
              ),
              
              locale: 'ko_KR',
            ),
          ),
          
          const SizedBox(height: 12),
          
          // 사용 가이드
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue[50]!, Colors.blue[100]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.touch_app, size: 18, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Text(
                      '사용 방법',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[900],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildGuideRow('1️⃣', '날짜 클릭: 선택/해제'),
                const SizedBox(height: 4),
                _buildGuideRow('2️⃣', '연속된 날짜는 자동으로 연결됨'),
                const SizedBox(height: 4),
                _buildGuideRow('3️⃣', '최대 30일까지 선택 가능'),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
        ],
        
        // 선택된 날짜 표시
        if (_selectedDates.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue[700],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '선택된 날짜',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '총 ${_selectedDates.length}일',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[900],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _selectedDates.clear();
                        });
                      },
                      icon: Icon(Icons.clear_all, color: Colors.red[700]),
                      tooltip: '전체 삭제',
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                _buildDateChips(),
                
                const SizedBox(height: 12),
                
                _buildConsecutiveIndicator(),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 가이드 행
  Widget _buildGuideRow(String emoji, String text) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue[800],
            ),
          ),
        ),
      ],
    );
  }

  /// 날짜 칩들 (연속된 날짜는 그룹화)
  Widget _buildDateChips() {
    if (_selectedDates.isEmpty) return const SizedBox.shrink();
    
    // 연속된 날짜 그룹 찾기
    final groups = _groupConsecutiveDates();
    
    print('🎨 칩 생성: ${groups.length}개 그룹');
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: groups.map((group) {
        if (group.length == 1) {
          print('  📌 단일: ${group.first.month}/${group.first.day}');
          return _buildDateChip(group.first, null);
        } else {
          print('  📦 범위: ${group.first.month}/${group.first.day} ~ ${group.last.month}/${group.last.day} (${group.length}일)');
          return _buildRangeChip(group.first, group.last);
        }
      }).toList(),
    );
  }

  /// 단일 날짜 칩
  Widget _buildDateChip(DateTime date, DateTime? endDate) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue[700],
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
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
                _selectedDates.removeWhere((d) => 
                  d.year == date.year && 
                  d.month == date.month && 
                  d.day == date.day
                );
              });
            },
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 범위 날짜 칩
  Widget _buildRangeChip(DateTime start, DateTime end) {
    final count = end.difference(start).inDays + 1; // ✅ 일수 계산
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[700]!, Colors.blue[500]!],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
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
            child: Icon(
              Icons.arrow_forward,
              size: 12,
              color: Colors.white,
            ),
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
          // ✅ 일수 표시
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
                // 범위 내 모든 날짜 삭제
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
              child: const Icon(
                Icons.close,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 연속 표시
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

  /// 아이콘 또는 Emoji 위젯 생성 (색상 포함)
  Widget _buildIconOrEmoji(BusinessWorkTypeModel workType) {
    if (workType.icon.startsWith('material:')) {
      // Material Icon
      Color iconColor = Colors.white; // 기본값
    
      if (workType.color != null && workType.color!.isNotEmpty) {
        try {
          iconColor = Color(int.parse(workType.color!.replaceFirst('#', '0xFF')));
        } catch (e) {
          print('⚠️ 아이콘 색상 파싱 실패: ${workType.color}');
          iconColor = Colors.white;
        }
      }
      return Icon(
        _getIconFromString(workType.icon),
        size: 18,
        color: iconColor,
      );
    } else {
      // Emoji
      return Text(
        workType.icon,
        style: const TextStyle(fontSize: 16),
      );
    }
  }
  /// 아이콘 문자열을 IconData로 변환
  IconData _getIconFromString(String iconString) {
    print('🔍 아이콘 변환: "$iconString"');
    
    // ✅ "material:57672" 형식 처리
    if (iconString.startsWith('material:')) {
      try {
        final codePoint = int.parse(iconString.substring(9));
        print('✅ Material 유니코드: $codePoint');
        return IconData(codePoint, fontFamily: 'MaterialIcons');
      } catch (e) {
        print('❌ 유니코드 파싱 실패: $e');
        return Icons.work_outline;
      }
    }
    
    // ✅ 일반 문자열 처리
    switch (iconString.toLowerCase()) {
      case 'work':
      case 'work_outline':
        return Icons.work_outline;
      case 'inventory':
      case 'inventory_2':
        return Icons.inventory_2_outlined;
      case 'local_shipping':
      case 'shipping':
        return Icons.local_shipping_outlined;
      case 'warehouse':
      case 'store':
        return Icons.warehouse_outlined;
      case 'shopping_cart':
      case 'cart':
        return Icons.shopping_cart_outlined;
      case 'construction':
      case 'build':
        return Icons.construction_outlined;
      default:
        print('⚠️ 알 수 없는 아이콘: $iconString');
        return Icons.work_outline;
    }
  }

Widget _buildModeButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[700] : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }


}