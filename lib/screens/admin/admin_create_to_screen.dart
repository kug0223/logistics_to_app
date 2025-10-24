import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/business_model.dart';
import '../../models/to_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../models/business_work_type_model.dart';

/// ✅ 업무 상세 입력 데이터 클래스 (시간 정보 포함)
class WorkDetailInput {
  final String? workType;
  final String? workTypeIcon;      // ✅ 추가
  final String? workTypeColor;     // ✅ 추가
  final int? wage;
  final int? requiredCount;
  final String? startTime; // ✅ NEW
  final String? endTime; // ✅ NEW

  WorkDetailInput({
    this.workType,
    this.workTypeIcon,             // ✅ 추가
    this.workTypeColor,            // ✅ 추가
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

  /// TO 생성
  Future<void> _createTO() async {
    if (!_formKey.currentState!.validate()) return;

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

  /// ✅ 업무 추가 다이얼로그 (시간 입력 포함)
  Future<void> _showAddWorkDetailDialog() async {
    if (_workDetails.length >= 3) {
      ToastHelper.showWarning('최대 3개까지만 추가할 수 있습니다.');
      return;
    }

    if (_businessWorkTypes.isEmpty) {
      ToastHelper.showWarning('등록된 업무 유형이 없습니다.');
      return;
    }

    String? selectedWorkType;
    final wageController = TextEditingController();
    final countController = TextEditingController();
    String? startTime = '09:00'; // ✅ NEW: 기본값
    String? endTime = '18:00'; // ✅ NEW: 기본값

    final result = await showDialog<WorkDetailInput>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('업무 추가'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 업무 유형 선택
              const Text('업무 유형 *', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedWorkType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '업무 선택',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                isExpanded: true,  // ✅ 추가: 전체 너비 사용
                // ✅ 선택 후 버튼에 표시 (Material Icon 또는 Emoji)
                selectedItemBuilder: (BuildContext context) {
                  return _businessWorkTypes.map((workType) {
                    return Row(
                      children: [
                        // 배경색이 있으면 Container로 감싸기
                        if (workType.backgroundColor != null && workType.backgroundColor!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: _parseColor(workType.backgroundColor!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: _buildIconOrEmoji(workType),
                          )
                        else
                          _buildIconOrEmoji(workType),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            workType.name,
                            style: const TextStyle(fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    );
                  }).toList();
                },
                
                // ✅ 드롭다운 목록 (Material Icon 또는 Emoji)
                items: _businessWorkTypes.map((workType) {
                return DropdownMenuItem(
                  value: workType.name,
                  child: Row(
                    children: [
                      // 배경색이 있으면 Container로 감싸기
                      if (workType.backgroundColor != null && workType.backgroundColor!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _parseColor(workType.backgroundColor!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _buildIconOrEmoji(workType),
                        )
                      else
                        _buildIconOrEmoji(workType),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          workType.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
                
                onChanged: (value) {
                  selectedWorkType = value;
                },
              ),
              const SizedBox(height: 16),

              // 금액 입력
              const Text('금액 (원) *', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: wageController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '50000',
                  suffixText: '원',
                ),
              ),
              const SizedBox(height: 16),

              // 필요 인원 입력
              const Text('필요 인원 (명) *', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: countController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '5',
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
              // 유효성 검사
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
                workType: selectedWorkType,
                wage: int.tryParse(wageController.text),
                requiredCount: int.tryParse(countController.text),
                startTime: startTime, // ✅ NEW
                endTime: endTime, // ✅ NEW
              );

              Navigator.pop(context, detail);
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _workDetails.add(result);
      });
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 제목 입력
            _buildSectionTitle('📝 TO 제목'),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: '예: 파트타임알바구인합니다',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'TO 제목을 입력하세요';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // 사업장 선택
            _buildSectionTitle('🏢 사업장'),
            _buildBusinessDropdown(),
            if (_selectedBusiness != null) ...[
              const SizedBox(height: 8),
              _buildBusinessInfoCard(_selectedBusiness!),
            ],
            const SizedBox(height: 24),
            
            // ✅ NEW Phase 2: 그룹 연결 섹션 추가 (여기에 추가!)
            _buildSectionTitle('🔗 기존 공고와 연결 (선택사항)'),
            _buildGroupLinkSection(),
            const SizedBox(height: 24),

            // ✅ NEW: 날짜 선택 방식
            _buildSectionTitle('📅 근무 날짜'),
            _buildDateModeSelector(),
            const SizedBox(height: 12),

            if (_dateMode == 'single')
              _buildSingleDatePicker()
            else
              _buildDateRangePicker(),

            // ❌ 제거: TO 레벨 근무 시간 입력
            // _buildSectionTitle('⏰ 근무 시간'),
            // Row(
            //   children: [
            //     Expanded(child: _buildStartTimePicker()),
            //     const SizedBox(width: 16),
            //     Expanded(child: _buildEndTimePicker()),
            //   ],
            // ),
            // const SizedBox(height: 24),

            // 지원 마감 시간
            _buildSectionTitle('⏱️ 지원 마감 시간'),
            _buildDeadlinePicker(),
            const SizedBox(height: 12),

            // ✅ NEW: 마감시간 검증 메시지 (범위 모드)
            if (_dateMode == 'range' && 
              _endDate != null && 
              _selectedDeadlineDate != null) ...[
            Builder(
              builder: (context) {
                final endDateOnly = DateTime(_endDate!.year, _endDate!.month, _endDate!.day);
                final deadlineDateOnly = DateTime(
                  _selectedDeadlineDate!.year, 
                  _selectedDeadlineDate!.month, 
                  _selectedDeadlineDate!.day
                );
                
                final isInvalid = deadlineDateOnly.isAfter(endDateOnly);
                
                if (!isInvalid) return const SizedBox.shrink();
                
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 16, color: Colors.red[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '⚠️ 마감 시간은 종료일(${_endDate!.month}/${_endDate!.day}) 이전 또는 당일이어야 합니다',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
              const SizedBox(height: 12),
            ],

            // ✅ NEW: 마감시간 검증 메시지 (단일 모드)
            if (_dateMode == 'single' && 
                _selectedDate != null && 
                _selectedDeadlineDate != null) ...[
              Builder(
                builder: (context) {
                  final dateDateOnly = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
                  final deadlineDateOnly = DateTime(
                    _selectedDeadlineDate!.year, 
                    _selectedDeadlineDate!.month, 
                    _selectedDeadlineDate!.day
                  );
                  
                  final isInvalid = deadlineDateOnly.isAfter(dateDateOnly);
                  
                  if (!isInvalid) return const SizedBox.shrink();
                  
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[300]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 16, color: Colors.red[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '⚠️ 마감 시간은 근무일(${_selectedDate!.month}/${_selectedDate!.day}) 이전 또는 당일이어야 합니다',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.red[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],

            // ✅ 업무 상세 (최대 3개, 시간 정보 포함)
            _buildSectionTitle('💼 업무 상세 (최대 3개)'),
            const SizedBox(height: 8),
            if (_workDetails.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  children: [
                    Icon(Icons.work_outline, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text(
                      '업무를 추가해주세요',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              )
            else
              ..._workDetails.asMap().entries.map((entry) {
                final index = entry.key;
                final detail = entry.value;
                return _buildWorkDetailCard(detail, index);
              }),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _workDetails.length < 3 ? _showAddWorkDetailDialog : null,
              icon: const Icon(Icons.add),
              label: Text('업무 추가 (${_workDetails.length}/3)'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 24),

            // 설명
            _buildSectionTitle('📄 설명 (선택사항)'),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '업무에 대한 상세 설명을 입력하세요',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),

            // 생성 버튼
            ElevatedButton(
              onPressed: _isCreating || _hasValidationError() ? null : _createTO,
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
                  : Text(
                      _dateMode == 'single' ? 'TO 생성' : 'TO 그룹 생성',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
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

  Widget _buildSingleDatePicker() {
    return InkWell(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _selectedDate ?? DateTime.now().add(const Duration(days: 1)),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date != null) {
          setState(() => _selectedDate = date);
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
            Icon(Icons.calendar_today, color: Colors.blue[700]),
            const SizedBox(width: 12),
            Text(
              _selectedDate == null
                  ? '날짜를 선택하세요'
                  : '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 16,
                color: _selectedDate == null ? Colors.grey : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
  /// ✅ NEW: 날짜 범위 선택
  Widget _buildDateRangePicker() {
    return Column(
      children: [
        // 시작일
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _startDate ?? DateTime.now().add(const Duration(days: 1)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (date != null) {
              setState(() {
                _startDate = date;
                if (_endDate != null && _endDate!.isBefore(date)) {
                  _endDate = null;
                }
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
                Icon(Icons.calendar_today, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '시작일',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _startDate == null
                            ? '날짜를 선택하세요'
                            : '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 16,
                          color: _startDate == null ? Colors.grey : Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        
        // 종료일
        InkWell(
          onTap: _startDate == null
              ? null
              : () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _endDate ?? _startDate!.add(const Duration(days: 1)),
                    firstDate: _startDate!,
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() => _endDate = date);
                  }
                },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: _startDate == null ? Colors.grey[100] : null,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  color: _startDate == null ? Colors.grey : Colors.blue[700],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '종료일',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _endDate == null
                            ? (_startDate == null ? '시작일을 먼저 선택하세요' : '날짜를 선택하세요')
                            : '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 16,
                          color: _endDate == null ? Colors.grey : Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // 기간 표시
        if (_startDate != null && _endDate != null) ...[
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final daysDiff = _endDate!.difference(_startDate!).inDays + 1;
              final isOverLimit = daysDiff > 30;
              
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isOverLimit ? Colors.red[50] : Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isOverLimit ? Colors.red[300]! : Colors.blue[200]!,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isOverLimit ? Icons.error_outline : Icons.info_outline,
                      size: 16,
                      color: isOverLimit ? Colors.red[700] : Colors.blue[700],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isOverLimit
                            ? '⚠️ 최대 30일까지만 선택 가능합니다 (현재 ${daysDiff}일)'
                            : '총 ${daysDiff}일간의 TO가 생성됩니다',
                        style: TextStyle(
                          fontSize: 14,
                          color: isOverLimit ? Colors.red[700] : Colors.blue[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildDeadlinePicker() {
    return Column(
      children: [
        // 마감 날짜
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _selectedDeadlineDate ?? DateTime.now(),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 90)),
            );
            if (date != null) {
              setState(() {  // ✅ setState 추가
                _selectedDeadlineDate = date;
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[400]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.grey[700]),
                const SizedBox(width: 12),
                Text(
                  _selectedDeadlineDate != null
                      ? '${_selectedDeadlineDate!.year}-${_selectedDeadlineDate!.month.toString().padLeft(2, '0')}-${_selectedDeadlineDate!.day.toString().padLeft(2, '0')}'
                      : '마감 날짜 선택',
                  style: TextStyle(
                    fontSize: 16,
                    color: _selectedDeadlineDate != null ? Colors.black : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 마감 시간
        InkWell(
          onTap: () async {
            final time = await showTimePicker(
              context: context,
              initialTime: _selectedDeadlineTime ?? TimeOfDay.now(),
            );
            if (time != null) {
              setState(() {  // ✅ setState 추가
                _selectedDeadlineTime = time;
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[400]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, color: Colors.grey[700]),
                const SizedBox(width: 12),
                Text(
                  _selectedDeadlineTime != null
                      ? '${_selectedDeadlineTime!.hour.toString().padLeft(2, '0')}:${_selectedDeadlineTime!.minute.toString().padLeft(2, '0')}'
                      : '마감 시간 선택',
                  style: TextStyle(
                    fontSize: 16,
                    color: _selectedDeadlineTime != null ? Colors.black : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
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
  
  Color _parseColor(String? colorHex) {  // ✅ nullable 허용
    if (colorHex == null || colorHex.isEmpty) {
      return Colors.blue[700]!;  // ✅ null/빈문자열이면 기본값
    }
    
    try {
      String hex = colorHex.replaceFirst('#', '');
      if (hex.length == 6) {
        hex = 'FF$hex';  // 알파값 추가
      }
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      print('⚠️ 색상 파싱 실패: $colorHex, 기본 파란색 사용');
      return Colors.blue[700]!;
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
  /// ✅ NEW: 날짜 선택 방식 토글
Widget _buildDateModeSelector() {
  return Container(
    decoration: BoxDecoration(
      color: Colors.grey[200],
      borderRadius: BorderRadius.circular(12),
    ),
    padding: const EdgeInsets.all(4),
    child: Row(
      children: [
        Expanded(
          child: _buildModeButton(
            label: '단일 날짜',
            icon: Icons.calendar_today,
            isSelected: _dateMode == 'single',
            onTap: () => setState(() => _dateMode = 'single'),
          ),
        ),
        Expanded(
          child: _buildModeButton(
            label: '날짜 범위',
            icon: Icons.date_range,
            isSelected: _dateMode == 'range',
            onTap: () => setState(() => _dateMode = 'range'),
          ),
        ),
      ],
    ),
  );
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