import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

// Widgets
import '../../../widgets/pickers/create&edit_work_detail_dialog.dart';

// 공통 위젯
import 'widgets/to_widgets.dart';
import '../../../theme/app_colors.dart';

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
  
  // 예약 공개 설정
  String _publishMode = 'immediate';
  int _publishDaysBefore = 1;
  String _publishTime = '14:00';
  
  @override
  void initState() {
    super.initState();
    
    _titleController = TextEditingController(text: widget.to.title);
    _descriptionController = TextEditingController(text: widget.to.description ?? '');
    
    _hoursBeforeStart = widget.to.hoursBeforeStart ?? 2;
    _fixedDeadline = widget.to.isLongTerm ? widget.to.applicationDeadline : null;
    
    // 예약 공개 설정 로드
    _publishMode = widget.to.publishMode;
    _publishDaysBefore = widget.to.publishDaysBefore ?? 1;
    _publishTime = widget.to.publishTime ?? '14:00';
    
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
      
      debugPrint('✅ _loadData 완료: ${_workDetails.length}개 업무');
    } catch (e) {
      debugPrint('❌ 데이터 로드 실패: $e');
      ToastHelper.showError('데이터를 불러오는데 실패했습니다');
      setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // 💾 저장 로직
  // ============================================================

  Future<void> _saveChanges() async {
    debugPrint('🔵 [1단계] 저장 시작');
    
    if (_titleController.text.trim().isEmpty) {
      ToastHelper.showError('제목을 입력해주세요');
      return;
    }
    
    debugPrint('🔵 [2단계] 유효성 검증 통과');
    
    setState(() => _isSaving = true);
    
    try {
      // ✅ publishAt 계산 (예약 공개인 경우)
      DateTime? publishAt;
      bool shouldPublishImmediately = _publishMode == 'immediate';
      
      if (_publishMode == 'scheduled') {
        final targetDate = widget.to.date.subtract(Duration(days: _publishDaysBefore));
        final timeParts = _publishTime.split(':');
        publishAt = DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
        
        // ✅ 과거 날짜면 즉시 공개로 전환
        if (publishAt.isBefore(DateTime.now())) {
          shouldPublishImmediately = true;
          ToastHelper.showInfo('공개 예정 시간이 지나 즉시 공개로 전환됩니다');
        }
      }
      
      final updates = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'hoursBeforeStart': _hoursBeforeStart,
        // ✅ 예약 공개 설정
        'publishMode': _publishMode,
        'publishAt': publishAt != null ? Timestamp.fromDate(publishAt) : null,
        'isPublished': shouldPublishImmediately,
        'publishDaysBefore': _publishMode == 'scheduled' ? _publishDaysBefore : null,
        'publishTime': _publishMode == 'scheduled' ? _publishTime : null,
      };
      
      // ✅ 장기공고: applicationDeadline 업데이트
      if (widget.to.isLongTerm && _fixedDeadline != null) {
        updates['applicationDeadline'] = Timestamp.fromDate(_fixedDeadline!);
      }
      // 재오픈 처리
      updates['closedAt'] = FieldValue.delete();
      updates['closedBy'] = FieldValue.delete();
      updates['isManualClosed'] = false;
      updates['reopenedAt'] = Timestamp.now();
      
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      updates['reopenedBy'] = userProvider.currentUser?.uid;
      
      debugPrint('🔵 [3단계] Firestore 업데이트 시작');
      
      await FirestoreService().updateTO(widget.to.id, updates);
      debugPrint('🔵 [4단계] TO 문서 업데이트 완료');
      
      debugPrint('🔥 [5단계] 모든 업무 상세 업데이트 시작');
      for (var work in _workDetails) {
        await _firestoreService.updateWorkDetail(
          toId: widget.to.id,
          workDetailId: work.id,
          updates: {
            'wage': work.wage,
            'wageType': work.wageType,
            'requiredCount': work.requiredCount,
            'startTime': work.startTime,
            'endTime': work.endTime,
          },
        );
        debugPrint('   ✅ ${work.workType} 업데이트 완료');
      }
      
      // 🔥 [6단계] 업무별 마감시간 재계산 또는 상태 초기화
      if (widget.to.isLongTerm) {
        // 장기공고: WorkDetails 마감 상태만 초기화 (마감시간은 TO 레벨)
        debugPrint('🔥 [6단계] 장기공고 WorkDetails 마감 상태 초기화');
        await _firestoreService.resetWorkDetailsClosedStatus(widget.to.id);
      } else {
        // 단기공고: 업무별 마감시간 재계산
        debugPrint('🔥 [6단계] 단기공고 업무별 마감시간 재계산');
        await _firestoreService.recalculateWorkDetailDeadlines(
          toId: widget.to.id,
          workDate: widget.to.date,
          hoursBeforeStart: _hoursBeforeStart,
          resetClosedStatus: true,
        );
      }
      debugPrint('✅ [7단계] 완료');
      
      _firestoreService.clearCache(toId: widget.to.id);
      _firestoreService.clearCache();
      debugPrint('🔵 [8단계] 캐시 클리어 완료');
      
      ToastHelper.showSuccess('TO가 수정되었습니다');
      
      if (mounted) {
        debugPrint('🔵🔵🔵 [9단계] true 반환하며 화면 닫기');
        NavigationHelper.popWithChange(context);
      }
    } catch (e) {
      debugPrint('❌ TO 수정 실패: $e');
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
        debugPrint('❌ 업무 추가 실패: $e');
        ToastHelper.showError('업무 추가에 실패했습니다');
      }
    }
  }

  /// 업무 수정 다이얼로그
  Future<void> _showEditWorkDialog(WorkDetailModel work) async {
    final result = await WorkDetailDialog.showEditDialog(
      context: context,
      work: work,
    );

    if (result != null) {
      setState(() {
        final index = _workDetails.indexWhere((w) => w.id == work.id);
        if (index != -1) {
          _workDetails[index] = _workDetails[index].copyWith(
            wage: result['wage'],
            wageType: result['wageType'],
            requiredCount: result['requiredCount'],
            startTime: result['startTime'],
            endTime: result['endTime'],
          );
        }
      });
      
      ToastHelper.showInfo('업무가 수정되었습니다 (저장 버튼을 눌러주세요)');
      debugPrint('✅ 업무 로컬 수정 완료: ${work.workType}');
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
        debugPrint('❌ 업무 삭제 실패: $e');
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
        color: AppColors.grey50,
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
              
              // ✅ 예약 공개 설정 섹션
              TOPublishSection(
                publishMode: _publishMode,
                onPublishModeChanged: (mode) => setState(() => _publishMode = mode),
                publishDaysBefore: _publishDaysBefore,
                onDaysBeforeChanged: (days) => setState(() => _publishDaysBefore = days),
                publishTime: _publishTime,
                onTimeChanged: (time) => setState(() => _publishTime = time),
                previewDates: [widget.to.date],
                isLongTerm: widget.to.isLongTerm,
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
}
