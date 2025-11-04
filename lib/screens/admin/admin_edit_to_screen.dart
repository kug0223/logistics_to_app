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

/// TO 수정 화면
class AdminEditTOScreen extends StatefulWidget {
  final TOModel to;

  const AdminEditTOScreen({
    super.key,
    required this.to,
  });

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
  final bool _isSaving = false;
  List<WorkDetailModel> _workDetails = [];
  List<BusinessWorkTypeModel> _businessWorkTypes = [];
  
  // ✅ NEW: 지원 마감 설정
  int _hoursBeforeStart = 2;
  DateTime? _fixedDeadline;
  
  @override
  void initState() {
    super.initState();
    
    _titleController = TextEditingController(text: widget.to.title);
    _descriptionController = TextEditingController(text: widget.to.description ?? '');
    
    _hoursBeforeStart = widget.to.hoursBeforeStart ?? 2;
    _fixedDeadline = widget.to.isLongTerm ? widget.to.applicationDeadline : null;  // ⭐ 추가!
    
    _loadData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        _firestoreService.getWorkDetails(widget.to.id),
        _firestoreService.getBusinessWorkTypes(widget.to.businessId),
      ]);

      setState(() {  // 🔥 여기서 setState 확인!
        _workDetails = results[0] as List<WorkDetailModel>;
        _businessWorkTypes = results[1] as List<BusinessWorkTypeModel>;
        _isLoading = false;
      });
      
      print('✅ _loadData 완료: ${_workDetails.length}개 업무');  // 🔥 로그 추가
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
        'hoursBeforeStart': _hoursBeforeStart,  // ✅ 항상 저장
      };
      
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
      
      // 🔥 모든 WorkDetail 업데이트
      print('🔥 [5단계] 모든 업무 상세 업데이트 시작');
      for (var work in _workDetails) {
        await _firestoreService.updateWorkDetail(
          toId: widget.to.id,
          workDetailId: work.id,
          updates: {
            'wage': work.wage,
            'requiredCount': work.requiredCount,
            'startTime': work.startTime,
            'endTime': work.endTime,
          },
        );
        print('   ✅ ${work.workType} 업데이트 완료');
      }
      
      // 🔥 마감시간 재계산
      print('🔥 [6단계] 업무별 마감시간 재계산 시작');
      await _firestoreService.recalculateWorkDetailDeadlines(
        toId: widget.to.id,
        workDate: widget.to.date,
        hoursBeforeStart: _hoursBeforeStart,
        resetClosedStatus: true,
      );
      print('✅ [7단계] 업무별 마감시간 재계산 완료');
      
      _firestoreService.clearCache(toId: widget.to.id);
      _firestoreService.clearCache();
      print('🔵 [8단계] 캐시 클리어 완료');
      
      ToastHelper.showSuccess('TO가 수정되었습니다');
      
      if (mounted) {
        print('🔵🔵🔵 [9단계] true 반환하며 화면 닫기');
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('❌ TO 수정 실패: $e');
      ToastHelper.showError('수정에 실패했습니다');
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
                    initialValue: startTime,
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
                    initialValue: endTime,
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
      // 🔥 로컬 상태만 업데이트 (Firestore는 저장 버튼 클릭 시!)
      setState(() {
        final index = _workDetails.indexWhere((w) => w.id == work.id);
        if (index != -1) {
          _workDetails[index] = _workDetails[index].copyWith(
            wage: result['wage'],
            requiredCount: result['requiredCount'],
            startTime: result['startTime'],
            endTime: result['endTime'],
          );
        }
      });
      
      ToastHelper.showInfo('업무가 수정되었습니다 (저장 버튼을 눌러주세요)');
      print('✅ 업무 로컬 수정 완료: ${work.workType}');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('수정'),
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
    // ⭐ 올해면 연도 생략, 다른 해면 연도 표시
    final now = DateTime.now();
    final isSameYear = widget.to.date.year == now.year;
    final dateFormat = DateFormat(
      isSameYear ? 'MM월 dd일 (E)' : 'yyyy년 MM월 dd일 (E)',
      'ko_KR'
    );
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
                  '근무 정보',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // ⭐ 채용 유형 표시
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.to.isLongTerm ? Colors.purple[50] : Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.to.isLongTerm ? Colors.purple[200]! : Colors.blue[200]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.to.isLongTerm ? Icons.event_repeat : Icons.event,
                    color: widget.to.isLongTerm ? Colors.purple[700] : Colors.blue[700],
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.to.jobTypeLabel,  // "단기 알바" or "1개월+ 계약직"
                    style: TextStyle(
                      fontSize: 15,
                      color: widget.to.isLongTerm ? Colors.purple[900] : Colors.blue[900],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 12),
            
            // ⭐ 날짜 표시 (단기/장기 분기)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_today, color: Colors.grey[700], size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: widget.to.isLongTerm
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '계약 기간',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.to.longTermPeriodWithDays,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.grey[800],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (widget.to.workDays != null && widget.to.workDays!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.to.workDaysLabel,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : Text(
                              dateFormat.format(widget.to.date),
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            Text(
              '⚠️ ${widget.to.isLongTerm ? "계약 기간과 근무 요일" : "날짜"}은(는) 수정할 수 없습니다. 변경하려면 TO를 삭제 후 다시 생성하세요.',
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

  /// 지원 마감 섹션
  Widget _buildDeadlineSection() {
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
            
            // ⭐ 단기/장기 분기
            if (widget.to.isLongTerm) ...[
              // 🟣 장기 TO: 고정 시간 선택
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_available, color: Colors.purple[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '모든 업무가 동일한 마감 시간을 사용합니다',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.purple[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // ⭐ 마감 시간 선택
              InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final initialDate = widget.to.applicationDeadline.isAfter(now)
                      ? widget.to.applicationDeadline
                      : now;
                  
                  final selectedDate = await showDatePicker(
                    context: context,
                    initialDate: initialDate,
                    firstDate: now,
                    lastDate: widget.to.endDate ?? now.add(const Duration(days: 365)),  // ⭐ 이미 맞게 되어 있음!
                    locale: const Locale('ko', 'KR'),
                  );
                  
                  if (selectedDate != null && mounted) {
                    final selectedTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(initialDate),
                    );
                    
                    if (selectedTime != null) {
                      final selectedDeadline = DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day,
                        selectedTime.hour,
                        selectedTime.minute,
                      );
                      
                      // ⭐ 검증 추가!
                      if (widget.to.endDate != null) {
                        final endDateTime = DateTime(
                          widget.to.endDate!.year,
                          widget.to.endDate!.month,
                          widget.to.endDate!.day,
                          23,
                          59,
                        );
                        
                        if (selectedDeadline.isAfter(endDateTime)) {
                          ToastHelper.showError('마감 시간은 근무 종료일 이전이어야 합니다');
                          return;
                        }
                      }
                      
                      setState(() {
                        _fixedDeadline = selectedDeadline;
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
                    children: [
                      Icon(Icons.access_time, color: Colors.purple[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '지원 마감 일시',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('yyyy년 MM월 dd일 HH:mm', 'ko_KR').format(
                                _fixedDeadline ?? widget.to.applicationDeadline
                              ),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                ),
              ),
              
            ] else ...[
              // 🔵 단기 TO: N시간 전 설정
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

}