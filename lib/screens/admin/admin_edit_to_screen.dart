import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/to_model.dart';
import '../../models/work_detail_model.dart';
import '../../models/business_work_type_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/loading_widget.dart';

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
  
  // 지원 마감 일시
  DateTime? _selectedDeadlineDate;
  TimeOfDay? _selectedDeadlineTime;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.to.title);
    _descriptionController = TextEditingController(text: widget.to.description ?? '');
    _selectedDeadlineDate = widget.to.applicationDeadline;
    _selectedDeadlineTime = TimeOfDay.fromDateTime(widget.to.applicationDeadline);
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

  /// TO 수정 저장
  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedDeadlineDate == null || _selectedDeadlineTime == null) {
      ToastHelper.showError('지원 마감 시간을 설정해주세요');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // 1. TO 기본 정보 업데이트
      final applicationDeadline = DateTime(
        _selectedDeadlineDate!.year,
        _selectedDeadlineDate!.month,
        _selectedDeadlineDate!.day,
        _selectedDeadlineTime!.hour,
        _selectedDeadlineTime!.minute,
      );

      // ✅ 지원 마감 시간 검증 (근무일 이전이어야 함)
      final workDate = DateTime(
        widget.to.date.year,
        widget.to.date.month,
        widget.to.date.day,
      );

      if (!applicationDeadline.isBefore(workDate)) {
        ToastHelper.showError('지원 마감은 근무일(${DateFormat('MM/dd').format(widget.to.date)}) 이전이어야 합니다');
        setState(() {
          _isSaving = false;
        });
        return;
      }

      // TO 전체 필요 인원 재계산
      final totalRequired = _workDetails.fold<int>(
        0,
        (sum, work) => sum + work.requiredCount,
      );

      await _firestoreService.updateTO(widget.to.id, {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'applicationDeadline': applicationDeadline,
        'totalRequired': totalRequired,
      });

      ToastHelper.showSuccess('TO가 수정되었습니다');
      
      if (mounted) {
        Navigator.pop(context, true); // 수정 완료 신호
      }
    } catch (e) {
      print('❌ TO 수정 실패: $e');
      ToastHelper.showError('TO 수정에 실패했습니다');
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  /// 업무 추가 다이얼로그
  Future<void> _showAddWorkDialog() async {
    BusinessWorkTypeModel? selectedWorkType;
    String? startTime;
    String? endTime;
    final wageController = TextEditingController();
    final countController = TextEditingController();

    final result = await showDialog<WorkDetailModel>(
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
                                color: _parseColor(workType.backgroundColor ?? '#E3F2FD'),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(
                                child: _buildIconOrEmoji(workType),
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

                  // 시작 시간
                  const Text('시작 시간', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: startTime,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '시작 시간',
                    ),
                    items: _generateTimeList().map((time) {
                      return DropdownMenuItem<String>(
                        value: time,
                        child: Text(time),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        startTime = value;
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
                      hintText: '종료 시간',
                    ),
                    items: _generateTimeList().map((time) {
                      return DropdownMenuItem<String>(
                        value: time,
                        child: Text(time),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        endTime = value;
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
                      hintText: '예: 50000',
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
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '예: 5',
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
                  if (selectedWorkType == null) {
                    ToastHelper.showError('업무 유형을 선택하세요');
                    return;
                  }
                  if (startTime == null || endTime == null) {
                    ToastHelper.showError('시간을 입력하세요');
                    return;
                  }
                  final wage = int.tryParse(wageController.text);
                  final count = int.tryParse(countController.text);

                  if (wage == null || count == null) {
                    ToastHelper.showError('금액과 인원을 입력하세요');
                    return;
                  }

                  // 새 WorkDetail 생성 (임시 ID)
                  final newWork = WorkDetailModel(
                    id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
                    workType: selectedWorkType!.name,
                    workTypeIcon: selectedWorkType!.icon,
                    workTypeColor: selectedWorkType!.color ?? '#2196F3',
                    wage: wage,
                    requiredCount: count,
                    currentCount: 0,
                    startTime: startTime!,
                    endTime: endTime!,
                    order: _workDetails.length,
                    createdAt: DateTime.now(),
                  );

                  Navigator.pop(context, newWork);
                },
                child: const Text('추가'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      // Firestore에 추가
      try {
        await _firestoreService.addWorkDetail(
          toId: widget.to.id,
          workDetail: result,
        );
        ToastHelper.showSuccess('업무가 추가되었습니다');
        _loadData(); // 새로고침
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
                    items: _generateTimeList().map((time) {
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
                    items: _generateTimeList().map((time) {
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
        _loadData(); // 새로고침
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
        _loadData(); // 새로고침
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
                  color: _parseColor(work.workTypeColor).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    work.workTypeIcon,
                    style: const TextStyle(fontSize: 20),
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

  /// 지원 마감 섹션
  Widget _buildDeadlineSection() {
    final dateFormat = DateFormat('yyyy-MM-dd');
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '지원 마감',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            Row(
              children: [
                // 날짜
                Expanded(
                  child: InkWell(
                    onTap: _selectDeadlineDate,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: Colors.grey[700], size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _selectedDeadlineDate != null
                                ? dateFormat.format(_selectedDeadlineDate!)
                                : '날짜 선택',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                
                // 시간
                Expanded(
                  child: InkWell(
                    onTap: _selectDeadlineTime,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time, color: Colors.grey[700], size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _selectedDeadlineTime != null
                                ? '${_selectedDeadlineTime!.hour.toString().padLeft(2, '0')}:${_selectedDeadlineTime!.minute.toString().padLeft(2, '0')}'
                                : '시간 선택',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '⚠️ 지원 마감은 근무일(${DateFormat('MM/dd').format(widget.to.date)}) 이전이어야 합니다',
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

  // ============================================================
  // 🛠️ 유틸리티 함수
  // ============================================================

  /// 시간 목록 생성
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

  /// 색상 파싱
  Color _parseColor(String colorString) {
    try {
      return Color(int.parse(colorString.replaceFirst('#', '0xFF')));
    } catch (e) {
      return Colors.blue[700]!;
    }
  }

  /// 아이콘 파싱
  IconData _parseIcon(String iconString) {
    if (iconString.startsWith('material:')) {
      try {
        final codePoint = int.parse(iconString.substring(9));
        return IconData(codePoint, fontFamily: 'MaterialIcons');
      } catch (e) {
        return Icons.work_outline;
      }
    }
    return Icons.work_outline;
  }

  /// 아이콘 또는 이모지 위젯
  Widget _buildIconOrEmoji(BusinessWorkTypeModel workType) {
    if (workType.icon.startsWith('material:')) {
      return Icon(
        _parseIcon(workType.icon),
        size: 20,
        color: _parseColor(workType.color ?? '#2196F3'),
      );
    } else {
      return Text(
        workType.icon,
        style: const TextStyle(fontSize: 18),
      );
    }
  }
}