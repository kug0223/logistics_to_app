import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/business_work_type_model.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';  // ⭐ 추가
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/pickers/work_detail_dialog.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../utils/format_helper.dart';

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
    _fixedDeadline = widget.to.isLongTerm ? widget.to.applicationDeadline : null;
    
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

      setState(() {
        _workDetails = results[0] as List<WorkDetailModel>;
        _businessWorkTypes = results[1] as List<BusinessWorkTypeModel>;
        _isLoading = false;
      });
      
      print('✅ _loadData 완료: ${_workDetails.length}개 업무');
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
        'hoursBeforeStart': _hoursBeforeStart,
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
                  Text(
                    '시작 시간', 
                    style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
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
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경

                  // 종료 시간
                  Text(
                    '종료 시간', 
                    style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
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
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경

                  // 금액
                  Text(
                    '금액 (원)', 
                    style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                  TextField(
                    controller: wageController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경

                  // 필요 인원
                  Text(
                    '필요 인원', 
                    style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
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
        backgroundColor: Theme.of(context).primaryColor,
        actions: [
          if (!_isSaving)
            TextButton(
              onPressed: _saveChanges,
              child: Text(
                '저장',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(  // ⭐ 변경
                  color: Colors.white,
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
                  padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 날짜 표시 (수정 불가)
                        _buildDateSection(),
                        SizedBox(height: ResponsiveHelper.spacing(context, 24)),  // ⭐ 변경

                        // 제목
                        _buildTitleSection(),
                        SizedBox(height: ResponsiveHelper.spacing(context, 24)),  // ⭐ 변경

                        // 업무 목록
                        _buildWorkDetailsSection(),
                        SizedBox(height: ResponsiveHelper.spacing(context, 24)),  // ⭐ 변경

                        // 지원 마감
                        _buildDeadlineSection(),
                        SizedBox(height: ResponsiveHelper.spacing(context, 24)),  // ⭐ 변경

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
        padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline, 
                  color: Theme.of(context).primaryColor,
                  size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 변경
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                Text(
                  '근무 정보',
                  style: ResponsiveHelper.subtitleStyle(context),  // ⭐ 변경
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
            
            // ⭐ 채용 유형 표시
            Container(
              padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
              decoration: BoxDecoration(
                color: widget.to.isLongTerm 
                    ? Colors.purple.withOpacity(0.1)
                    : Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.to.isLongTerm 
                      ? Colors.purple.withOpacity(0.3)
                      : Theme.of(context).primaryColor.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.to.isLongTerm ? Icons.event_repeat : Icons.event,
                    color: widget.to.isLongTerm ? Colors.purple : Theme.of(context).primaryColor,
                    size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 변경
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
                  Text(
                    widget.to.jobTypeLabel,
                    style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                      context,
                      color: widget.to.isLongTerm ? Colors.purple : Theme.of(context).primaryColor,
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
            
            // ⭐ 날짜 표시 (단기/장기 분기)
            Container(
              padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today, 
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                        size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 변경
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
                      Expanded(
                        child: widget.to.isLongTerm
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '계약 기간',
                                  style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                                    context,
                                    color: Theme.of(context).textTheme.bodySmall?.color,
                                  ),
                                ),
                                SizedBox(height: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                                Text(
                                  widget.to.longTermPeriodWithDays,
                                  style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                                    context,
                                  ).copyWith(fontWeight: FontWeight.w500),
                                ),
                                if (widget.to.workDays != null && widget.to.workDays!.isNotEmpty) ...[
                                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                                  Text(
                                    widget.to.workDaysLabel,
                                    style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                                      context,
                                      color: Theme.of(context).textTheme.bodyMedium?.color,
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : Text(
                              dateFormat.format(widget.to.date),
                              style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                                context,
                                color: Theme.of(context).textTheme.bodyMedium?.color,
                              ).copyWith(fontWeight: FontWeight.w500),
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
            Text(
              '⚠️ ${widget.to.isLongTerm ? "계약 기간과 근무 요일" : "날짜"}은(는) 수정할 수 없습니다. 변경하려면 TO를 삭제 후 다시 생성하세요.',
              style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                context,
                color: Colors.orange,
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
        padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TO 제목',
              style: ResponsiveHelper.subtitleStyle(context),  // ⭐ 변경
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
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
        padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '업무 목록 (${_workDetails.length}개)',
                  style: ResponsiveHelper.subtitleStyle(context),  // ⭐ 변경
                ),
                ElevatedButton.icon(
                  onPressed: _showAddWorkDialog,
                  icon: Icon(Icons.add, size: ResponsiveHelper.iconSize(context, 18)),  // ⭐ 변경
                  label: const Text('업무 추가'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경

            if (_workDetails.isEmpty)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),  // ⭐ 변경
                  child: Text(
                    '등록된 업무가 없습니다',
                    style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                      context,
                      color: Theme.of(context).textTheme.bodySmall?.color,
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
      margin: EdgeInsets.only(  // ⭐ const 제거
        bottom: ResponsiveHelper.spacing(context, 12),  // ⭐ 변경
      ),
      padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 아이콘
              Container(
                width: ResponsiveHelper.iconSize(context, 40),  // ⭐ 변경
                height: ResponsiveHelper.iconSize(context, 40),  // ⭐ 변경
                decoration: BoxDecoration(
                  color: FormatHelper.parseColor(work.workTypeBackgroundColor ?? '#2196F3'),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: WorkTypeIcon.buildFromString(
                    work.workTypeIcon,
                    color: FormatHelper.parseColor(work.workTypeColor),
                    size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 변경
                  ),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
              
              // 업무명
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      work.workType,
                      style: ResponsiveHelper.subtitleStyle(context),  // ⭐ 변경
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                    Text(
                      '${work.timeRange} | ${work.formattedWage}',
                      style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                        context,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                  ],
                ),
              ),
              
              // 버튼들
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.edit, 
                      size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 변경
                    ),
                    color: Colors.orange,
                    onPressed: () => _showEditWorkDialog(work),
                    tooltip: '수정',
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete, 
                      size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 변경
                    ),
                    color: work.currentCount > 0 ? Colors.grey : Colors.red,
                    onPressed: work.currentCount > 0 ? null : () => _deleteWork(work),
                    tooltip: work.currentCount > 0 ? '지원자가 있어 삭제 불가' : '삭제',
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
          
          // 인원 정보
          Row(
            children: [
              Icon(
                Icons.people, 
                size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
              Text(
                '확정: ${work.currentCount}/${work.requiredCount}명',
                style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                  context,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
              if (work.currentCount > 0) ...[
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 6),  // ⭐ 변경
                    vertical: ResponsiveHelper.spacing(context, 2),  // ⭐ 변경
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '지원자 있음',
                    style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                      context,
                      color: Colors.orange,
                    ).copyWith(fontWeight: FontWeight.bold),
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
        padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '지원 마감 설정',
              style: ResponsiveHelper.subtitleStyle(context),  // ⭐ 변경
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
            
            // ⭐ 단기/장기 분기
            if (widget.to.isLongTerm) ...[
              // 🟣 장기 TO: 고정 시간 선택
              Container(
                padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_available, 
                      color: Colors.purple,
                      size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 변경
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                    Expanded(
                      child: Text(
                        '모든 업무가 동일한 마감 시간을 사용합니다',
                        style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                          context,
                          color: Colors.purple,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
              
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
                    lastDate: widget.to.endDate ?? now.add(const Duration(days: 365)),
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
                  padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.access_time, color: Colors.purple),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '지원 마감 일시',
                              style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                                context,
                                color: Theme.of(context).disabledColor,
                              ),
                            ),
                            SizedBox(height: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                            Text(
                              DateFormat('yyyy년 MM월 dd일 HH:mm', 'ko_KR').format(
                                _fixedDeadline ?? widget.to.applicationDeadline
                              ),
                              style: ResponsiveHelper.subtitleStyle(context),  // ⭐ 변경
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios, 
                        size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
                      ),
                    ],
                  ),
                ),
              ),
              
            ] else ...[
              // 🔵 단기 TO: N시간 전 설정
              Container(
                padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline, 
                      color: Theme.of(context).primaryColor,
                      size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 변경
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                    Expanded(
                      child: Text(
                        '각 업무별로 시작 시간 기준으로 자동 마감됩니다',
                        style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                          context,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
              
              // 시간 선택
              Row(
                children: [
                  Text(
                    '업무 시작',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
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
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                  Text(
                    '마감', 
                    style: ResponsiveHelper.bodyStyle(context),  // ⭐ 변경
                  ),
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
        padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '설명',
              style: ResponsiveHelper.subtitleStyle(context),  // ⭐ 변경
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
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