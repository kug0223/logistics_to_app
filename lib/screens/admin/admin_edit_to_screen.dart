import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/to_model.dart';
import '../../models/work_detail_model.dart';
import '../../models/business_work_type_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/work_detail_dialog.dart';
import '../../widgets/work_type_icon.dart';
import '../../utils/format_helper.dart';
import '../../widgets/work_type_icon.dart';

/// TO 수정 화면
class AdminEditTOScreen extends StatefulWidget {
  final TOModel to;

  const AdminEditTOScreen({
    Key? key,
    required this.to,
  }) : super(key: key);

  @override
  State<AdminEditTOScreen> createState() => _AdminEditTOScreenState();
}

class _AdminEditTOScreenState extends State<AdminEditTOScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  
  // 컨트롤러
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  
  // 상태 변수
  bool _isLoading = true;
  bool _isSaving = false;
  List<WorkDetailModel> _workDetails = [];
  List<BusinessWorkTypeModel> _businessWorkTypes = [];
  
  // ✅ NEW: 지원 마감 설정
  String _deadlineType = 'HOURS_BEFORE';
  int _hoursBeforeStart = 2;
  DateTime? _selectedDeadlineDate;
  TimeOfDay? _selectedDeadlineTime;
  
  @override
  void initState() {
    super.initState();
    
    // ✅ 컨트롤러 초기화
    _titleController = TextEditingController(text: widget.to.title);
    _descriptionController = TextEditingController(text: widget.to.description ?? '');
    
    // ✅ 기존 TO의 마감 설정 로드
    _deadlineType = widget.to.deadlineType;
    _hoursBeforeStart = widget.to.hoursBeforeStart ?? 2;
    
    // FIXED_TIME인 경우 날짜/시간 파싱
    if (_deadlineType == 'FIXED_TIME') {
      _selectedDeadlineDate = widget.to.applicationDeadline;
      _selectedDeadlineTime = TimeOfDay(
        hour: widget.to.applicationDeadline.hour,
        minute: widget.to.applicationDeadline.minute,
      );
    }
    
    // 데이터 로드
    _loadData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// 데이터 로드 (WorkDetails + 사업장 업무유형)
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        _firestoreService.getWorkDetails(widget.to.id),
        _firestoreService.getBusinessWorkTypes(widget.to.businessId),
      ]);

      setState(() {
        _workDetails = results[0] as List<WorkDetailModel>;
        _businessWorkTypes = results[1] as List<BusinessWorkTypeModel>;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 데이터 로드 실패: $e');
      ToastHelper.showError('데이터를 불러오는데 실패했습니다');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveChanges() async {
    print('🔵 [1단계] 저장 시작');
    
    // 유효성 검증
    if (_titleController.text.trim().isEmpty) {
      ToastHelper.showError('제목을 입력해주세요');
      return;
    }
    
    print('🔵 [2단계] 유효성 검증 통과');
    
    try {
      // 업데이트할 데이터 준비
      final updates = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'deadlineType': _deadlineType,
      };
      
      // 🔥 업무별 마감 방식으로 변경
      if (_deadlineType == 'HOURS_BEFORE') {
        updates['hoursBeforeStart'] = _hoursBeforeStart;
      }
      
      // 🔥 시간 변경 시 마감 상태 초기화
      updates['closedAt'] = FieldValue.delete();
      updates['closedBy'] = FieldValue.delete();
      updates['isManualClosed'] = false;
      updates['reopenedAt'] = Timestamp.now();
      
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      updates['reopenedBy'] = userProvider.currentUser?.uid;
      
      print('🔵 [3단계] Firestore 업데이트 시작');
      print('   TO ID: ${widget.to.id}');
      print('   updates: $updates');
      
      // Firestore 업데이트
      await FirestoreService().updateTO(widget.to.id, updates);
      print('🔵 [4단계] TO 문서 업데이트 완료');
      
      // 🔥 NEW: 각 업무별로 마감시간 계산 및 저장
      print('🔥 [5단계] 업무별 마감시간 계산 시작');
      for (var work in _workDetails) {
        final workDeadline = _calculateWorkDeadline(work);
        
        await _firestoreService.updateWorkDetail(
          toId: widget.to.id,          // 🔥 명명된 인자로 수정!
          workDetailId: work.id,       // 🔥 명명된 인자로 수정!
          updates: {
            'applicationDeadline': workDeadline != null 
                ? Timestamp.fromDate(workDeadline) 
                : null,
            'closedAt': null,
            'closedBy': null,
            'isManualClosed': false,
            'isEmergencyOpen': false,
          },
        );
        
        print('   ${work.workType}: 마감시간 = ${workDeadline?.toString() ?? "없음"}');
      }
      print('✅ [6단계] 업무별 마감시간 설정 완료');
      
      // ✅ 캐시 클리어
      _firestoreService.clearCache();
      print('🔵 [7단계] 캐시 클리어 완료');
      
      ToastHelper.showSuccess('TO가 수정되었습니다');
      
      if (mounted) {
        print('🔵🔵🔵 [8단계] true 반환하며 화면 닫기');
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('❌ TO 수정 실패: $e');
      ToastHelper.showError('수정에 실패했습니다');
    }
  }

  // 🔥 NEW: 업무별 마감시간 계산 함수
  DateTime? _calculateWorkDeadline(WorkDetailModel work) {
    if (_deadlineType != 'HOURS_BEFORE') return null;
    
    // 업무 시작 시간 파싱
    if (work.startTime.isEmpty) return null;
    
    final timeParts = work.startTime.split(':');
    if (timeParts.length < 2) return null;
    
    try {
      final startDateTime = DateTime(
        widget.to.date.year,
        widget.to.date.month,
        widget.to.date.day,
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
      
      return startDateTime.subtract(Duration(hours: _hoursBeforeStart));
    } catch (e) {
      print('⚠️ 시간 파싱 실패: ${work.startTime}');
      return null;
    }
  }
  /// 업무 추가 다이얼로그
  Future<void> _showAddWorkDialog() async {
    final result = await WorkDetailDialog.showAddDialog(
      context: context,
      businessWorkTypes: _businessWorkTypes,
    );

    if (result != null) {
      // WorkDetailInput → WorkDetailModel 변환
      final newWork = WorkDetailModel(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
        workType: result.workType!,
        workTypeIcon: result.workTypeIcon,
        workTypeColor: result.workTypeColor,
        wage: result.wage!,
        requiredCount: result.requiredCount!,
        currentCount: 0,
        startTime: result.startTime!,
        endTime: result.endTime!,
        order: _workDetails.length,
        createdAt: DateTime.now(),
      );

      try {
        final addedWorkId = await _firestoreService.addWorkDetail(
          toId: widget.to.id,
          workDetail: newWork,
        );
        ToastHelper.showSuccess('업무가 추가되었습니다');
        // ✅ 아래 2줄 추가
        setState(() {
          _workDetails.add(newWork.copyWith(id: addedWorkId));
        });
      } catch (e) {
        print('❌ 업무 추가 실패: $e');
        ToastHelper.showError('업무 추가에 실패했습니다');
      }
    }
  }

  /// 업무 수정 다이얼로그
  Future<void> _showEditWorkDialog(WorkDetailModel work) async {
    final wageController = TextEditingController(text: work.wage.toString());
    final countController = TextEditingController(text: work.requiredCount.toString());
    String startTime = work.startTime;
    String endTime = work.endTime;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('${work.workType} 수정'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 시작 시간
                  const Text('시작 시간', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: startTime,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: FormatHelper.generateTimeList().map((time) {
                      return DropdownMenuItem<String>(
                        value: time,
                        child: Text(time),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        startTime = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // 종료 시간
                  const Text('종료 시간', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: endTime,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: FormatHelper.generateTimeList().map((time) {
                      return DropdownMenuItem<String>(
                        value: time,
                        child: Text(time),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        endTime = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // 금액
                  const Text('금액 (원)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: wageController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 16),

                  // 필요 인원
                  const Text('필요 인원', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: countController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      helperText: work.currentCount > 0 
                          ? '⚠️ 현재 확정 인원: ${work.currentCount}명'
                          : null,
                      helperStyle: const TextStyle(color: Colors.orange),
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                  final wage = int.tryParse(wageController.text);
                  final count = int.tryParse(countController.text);

                  if (wage == null || count == null) {
                    ToastHelper.showError('금액과 인원을 입력하세요');
                    return;
                  }

                  // ✅ 확정 인원보다 적게 축소 불가
                  if (count < work.currentCount) {
                    ToastHelper.showError(
                      '필요 인원은 확정 인원(${work.currentCount}명)보다 작을 수 없습니다'
                    );
                    return;
                  }

                  Navigator.pop(context, {
                    'wage': wage,
                    'requiredCount': count,
                    'startTime': startTime,
                    'endTime': endTime,
                  });
                },
                child: const Text('저장'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      // Firestore 업데이트
      try {
        await _firestoreService.updateWorkDetail(
          toId: widget.to.id,
          workDetailId: work.id,
          updates: result,
        );
        ToastHelper.showSuccess('업무가 수정되었습니다');
        await _loadData(); // 새로고침
      } catch (e) {
        print('❌ 업무 수정 실패: $e');
        ToastHelper.showError('업무 수정에 실패했습니다');
      }
    }
  }

  /// 업무 삭제
  Future<void> _deleteWork(WorkDetailModel work) async {
    // ✅ 지원자 있으면 삭제 불가
    if (work.currentCount > 0) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('삭제 불가'),
          content: Text(
            '이 업무에는 ${work.currentCount}명의 확정된 지원자가 있습니다.\n'
            '지원자가 있는 업무는 삭제할 수 없습니다.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('업무 삭제'),
        content: Text('${work.workType} 업무를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _firestoreService.deleteWorkDetail(
          toId: widget.to.id,
          workDetailId: work.id,
        );
        ToastHelper.showSuccess('업무가 삭제되었습니다');
        // ✅ 아래 2줄 추가
        setState(() {
          _workDetails.removeWhere((w) => w.id == work.id);
        });
      } catch (e) {
        print('❌ 업무 삭제 실패: $e');
        ToastHelper.showError('업무 삭제에 실패했습니다');
      }
    }
  }

  /// 마감일 선택
  Future<void> _selectDeadlineDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDeadlineDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: widget.to.date.subtract(const Duration(days: 1)),
    );

    if (picked != null) {
      setState(() {
        _selectedDeadlineDate = picked;
      });
    }
  }

  /// 마감시간 선택
  Future<void> _selectDeadlineTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedDeadlineTime ?? TimeOfDay.now(),
    );

    if (picked != null) {
      setState(() {
        _selectedDeadlineTime = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TO 수정'),
        backgroundColor: Colors.blue[700],
        actions: [
          if (!_isSaving)
            TextButton(
              onPressed: _saveChanges,
              child: const Text(
                '저장',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget(message: '데이터를 불러오는 중...')
          : _isSaving
              ? const LoadingWidget(message: '저장 중...')
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 날짜 표시 (수정 불가)
                        _buildDateSection(),
                        const SizedBox(height: 24),

                        // 제목
                        _buildTitleSection(),
                        const SizedBox(height: 24),

                        // 업무 목록
                        _buildWorkDetailsSection(),
                        const SizedBox(height: 24),

                        // 지원 마감
                        _buildDeadlineSection(),
                        const SizedBox(height: 24),

                        // 설명
                        _buildDescriptionSection(),
                      ],
                    ),
                  ),
                ),
    );
  }

  /// 날짜 섹션 (수정 불가)
  Widget _buildDateSection() {
    final dateFormat = DateFormat('yyyy년 MM월 dd일 (E)', 'ko_KR');
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                const Text(
                  '근무 날짜',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, color: Colors.grey[700], size: 20),
                  const SizedBox(width: 12),
                  Text(
                    dateFormat.format(widget.to.date),
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '⚠️ 날짜는 수정할 수 없습니다. 날짜를 변경하려면 TO를 삭제 후 다시 생성하세요.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 제목 섹션
  Widget _buildTitleSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TO 제목',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: '예: 분류작업, 피킹업무',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.title),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'TO 제목을 입력하세요';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 업무 목록 섹션
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
                Text(
                  '업무 목록 (${_workDetails.length}개)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showAddWorkDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('업무 추가'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_workDetails.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '등록된 업무가 없습니다',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ),
              )
            else
              ..._workDetails.map((work) => _buildWorkCard(work)),
          ],
        ),
      ),
    );
  }

  /// 업무 카드
  Widget _buildWorkCard(WorkDetailModel work) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              // 아이콘
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: FormatHelper.parseColor(work.workTypeColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: WorkTypeIcon.buildFromString(
                    work.workTypeIcon,
                    color: Colors.white,  // ✅ 간단하게 이것만!
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // 업무명
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      work.workType,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${work.timeRange} | ${work.formattedWage}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              
              // 버튼들
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    color: Colors.orange[700],
                    onPressed: () => _showEditWorkDialog(work),
                    tooltip: '수정',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 20),
                    color: work.currentCount > 0 ? Colors.grey : Colors.red[700],
                    onPressed: work.currentCount > 0 ? null : () => _deleteWork(work),
                    tooltip: work.currentCount > 0 ? '지원자가 있어 삭제 불가' : '삭제',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // 인원 정보
          Row(
            children: [
              Icon(Icons.people, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                '확정: ${work.currentCount}/${work.requiredCount}명',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
              ),
              if (work.currentCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '지원자 있음',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 지원 마감 설정 섹션
  Widget _buildDeadlineSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
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
          const SizedBox(height: 16),
          
          // ✅ 옵션 1: 각 업무 시작 N시간 전
          RadioListTile<String>(
            title: const Text('각 업무 시작 N시간 전 마감'),  // 🔥 텍스트 수정!
            subtitle: Text('각 업무별로 시작 시간 기준 $_hoursBeforeStart시간 전에 자동 마감'),
            value: 'HOURS_BEFORE',
            groupValue: _deadlineType,
            onChanged: (value) {
              setState(() {
                _deadlineType = value!;
              });
            },
          ),
          
          // 시간 선택
          if (_deadlineType == 'HOURS_BEFORE')
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: Row(
                children: [
                  const Text('시작 시간'),
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
                ],
              ),
            ),
          
          const Divider(height: 32),
        ],
      ),
    );
  }
  /// 마감 시간 미리보기
  Widget _buildDeadlinePreview() {
    if (widget.to.startTime == null) return const SizedBox();
    
    try {
      final timeParts = widget.to.startTime!.split(':');
      final startDateTime = DateTime(
        widget.to.date.year,
        widget.to.date.month,
        widget.to.date.day,
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
              '${DateFormat('MM/dd (E)', 'ko_KR').format(widget.to.date)} ${widget.to.startTime} 근무',
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

  /// 설명 섹션
  Widget _buildDescriptionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '설명',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                hintText: '추가 설명을 입력하세요 (선택사항)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              maxLines: 5,
            ),
          ],
        ),
      ),
    );
  }

}