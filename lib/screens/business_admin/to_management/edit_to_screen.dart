import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Models
import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/business_work_type_model.dart';

// Services & Providers
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/navigation_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/format_helper.dart';

// Widgets
import '../../../widgets/pickers/work_detail_dialog.dart';
import '../../../widgets/work_type_icon.dart';

// 공통 위젯
import 'widgets/to_widgets.dart';

/// ✨ TO 수정 화면 - 공통 위젯 적용
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
  bool _isSaving = false;
  List<WorkDetailModel> _workDetails = [];
  List<BusinessWorkTypeModel> _businessWorkTypes = [];
  
  // 지원 마감 설정
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

  // ============================================================
  // 📡 데이터 로딩
  // ============================================================

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

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
      setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // 💾 저장 로직
  // ============================================================

  Future<void> _saveChanges() async {
    print('🔵 [1단계] 저장 시작');
    
    if (_titleController.text.trim().isEmpty) {
      ToastHelper.showError('제목을 입력해주세요');
      return;
    }
    
    print('🔵 [2단계] 유효성 검증 통과');
    
    setState(() => _isSaving = true);
    
    try {
      final updates = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'hoursBeforeStart': _hoursBeforeStart,
      };
      
      // 재오픈 처리
      updates['closedAt'] = FieldValue.delete();
      updates['closedBy'] = FieldValue.delete();
      updates['isManualClosed'] = false;
      updates['reopenedAt'] = Timestamp.now();
      
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      updates['reopenedBy'] = userProvider.currentUser?.uid;
      
      print('🔵 [3단계] Firestore 업데이트 시작');
      
      await FirestoreService().updateTO(widget.to.id, updates);
      print('🔵 [4단계] TO 문서 업데이트 완료');
      
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
        NavigationHelper.popWithChange(context);
      }
    } catch (e) {
      print('❌ TO 수정 실패: $e');
      ToastHelper.showError('수정에 실패했습니다');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  // ============================================================
  // 🛠️ 업무 관리 함수들
  // ============================================================

  /// 업무 추가 다이얼로그
  Future<void> _showAddWorkDialog() async {
    final result = await WorkDetailDialog.showAddDialog(
      context: context,
      businessWorkTypes: _businessWorkTypes,
    );

    if (result != null) {
      final newWork = WorkDetailModel(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
        workType: result.workType!,
        workTypeIcon: result.workTypeIcon,
        workTypeColor: result.workTypeColor,
        workTypeBackgroundColor: result.workTypeBackgroundColor,
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
    final result = await _showWorkEditDialog(work);

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
    if (work.currentCount > 0) {
      _showCannotDeleteDialog(work);
      return;
    }

    final confirmed = await _showDeleteConfirmDialog(work);

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

  // ============================================================
  // 🎨 UI 빌드
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('TO 수정')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_isSaving) {
      return Scaffold(
        appBar: AppBar(title: const Text('TO 수정')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              SizedBox(height: ResponsiveHelper.spacing(context, 24)),
              Text(
                '저장 중...',
                style: ResponsiveHelper.titleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('TO 수정')),
      body: Container(
        color: Colors.grey[50],
        child: Form(
          key: _formKey,
          child: ListView(
            padding: ResponsiveHelper.cardPadding(context),
            children: [
              // ✅ 공통 위젯 사용 - 날짜 섹션 (수정 불가)
              TODateSelector(
                isLongTerm: widget.to.isLongTerm,
                isReadOnly: true,
                displayDate: widget.to.date,
                rangeStart: widget.to.startDate,
                rangeEnd: widget.to.endDate,
                displayWorkDays: widget.to.workDays,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              
              // ✅ 공통 위젯 사용 - 제목 섹션
              TOTitleSection(
                titleController: _titleController,
                showGroupNameInput: false,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              
              // ✅ 공통 위젯 사용 - 업무 목록 섹션
              TOWorkDetailsSection(
                workDetailModels: _workDetails,
                onAddWork: _showAddWorkDialog,
                onEditWork: _showEditWorkDialog,
                onDeleteWork: _deleteWork,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              
              // ✅ 공통 위젯 사용 - 마감 설정 섹션
              TODeadlineSection(
                isLongTerm: widget.to.isLongTerm,
                hoursBeforeStart: _hoursBeforeStart,
                onHoursChanged: (hours) => setState(() => _hoursBeforeStart = hours),
                fixedDeadline: _fixedDeadline,
                onFixedDeadlineChanged: (dt) => setState(() => _fixedDeadline = dt),
                rangeEndDate: widget.to.endDate,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              
              // ✅ 공통 위젯 사용 - 설명 섹션
              TODescriptionSection(controller: _descriptionController),
              SizedBox(height: ResponsiveHelper.spacing(context, 24)),
              
              // ✅ 공통 위젯 사용 - 저장 버튼
              TOActionButton.save(
                onPressed: _saveChanges,
                isLoading: _isSaving,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 40)),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 🛠️ 다이얼로그 헬퍼 함수들
  // ============================================================

  Future<Map<String, dynamic>?> _showWorkEditDialog(WorkDetailModel work) async {
    final wageController = TextEditingController(text: work.wage.toString());
    final countController = TextEditingController(text: work.requiredCount.toString());
    String startTime = work.startTime;
    String endTime = work.endTime;
    String selectedWageType = work.wageType;
    final theme = Theme.of(context);

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              '${work.workType} 수정',
              style: ResponsiveHelper.titleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 급여 타입 선택
                  Row(
                    children: [
                      _buildWageTypeChip(
                        context, theme, '시급', 'hourly', selectedWageType,
                        () => setDialogState(() => selectedWageType = 'hourly'),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      _buildWageTypeChip(
                        context, theme, '일급', 'daily', selectedWageType,
                        () => setDialogState(() => selectedWageType = 'daily'),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      _buildWageTypeChip(
                        context, theme, '월급', 'monthly', selectedWageType,
                        () => setDialogState(() => selectedWageType = 'monthly'),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                  // 급여
                  TextFormField(
                    controller: wageController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _getWageLabel(selectedWageType),  // ✅ 동적 라벨
                      prefixIcon: const Icon(Icons.payments),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  
                  // 인원
                  TextFormField(
                    controller: countController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '필요 인원',
                      prefixIcon: const Icon(Icons.people),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      helperText: work.currentCount > 0
                          ? '⚠️ 현재 확정 인원: ${work.currentCount}명'
                          : null,
                      helperStyle: const TextStyle(color: Colors.orange),
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  
                  // 시작 시간
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time),
                    title: const Text('시작 시간'),
                    trailing: TextButton(
                      onPressed: () async {
                        final timeParts = startTime.split(':');
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(
                            hour: int.parse(timeParts[0]),
                            minute: int.parse(timeParts[1]),
                          ),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            startTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                          });
                        }
                      },
                      child: Text(
                        startTime,
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  
                  // 종료 시간
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time_filled),
                    title: const Text('종료 시간'),
                    trailing: TextButton(
                      onPressed: () async {
                        final timeParts = endTime.split(':');
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(
                            hour: int.parse(timeParts[0]),
                            minute: int.parse(timeParts[1]),
                          ),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            endTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                          });
                        }
                      },
                      child: Text(
                        endTime,
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                    'wageType': selectedWageType,
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
  }

  void _showCannotDeleteDialog(WorkDetailModel work) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
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
  }

  Future<bool?> _showDeleteConfirmDialog(WorkDetailModel work) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
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
  }
  /// 급여 타입 칩 위젯
  Widget _buildWageTypeChip(
    BuildContext context,
    ThemeData theme,
    String label,
    String value,
    String selectedValue,
    VoidCallback onTap,
  ) {
    final isSelected = value == selectedValue;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        decoration: BoxDecoration(
          color: isSelected ? theme.primaryColor : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? theme.primaryColor : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: ResponsiveHelper.smallStyle(context).copyWith(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// 급여 라벨 반환
  String _getWageLabel(String wageType) {
    switch (wageType) {
      case 'hourly': return '시급 (원)';
      case 'daily': return '일급 (원)';
      case 'monthly': return '월급 (원)';
      default: return '급여 (원)';
    }
  }
}