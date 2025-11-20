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
import '../../../utils/responsive_helper.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/pickers/work_detail_dialog.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../utils/format_helper.dart';

/// ✨ TO 수정 화면 - 세련된 디자인
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
        Navigator.pop(context, true);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('TO 수정'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_isSaving) {
      return Scaffold(
        appBar: AppBar(
          title: Text('TO 수정'),
        ),
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
      appBar: AppBar(
        title: Text('TO 수정'),
      ),
      body: Container(
        color: Colors.grey[50],
        child: Form(
          key: _formKey,
          child: ListView(
            padding: ResponsiveHelper.cardPadding(context),
            children: [
              _buildDateSection(theme),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              _buildTitleSection(theme),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              _buildWorkDetailsSection(theme),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              _buildDeadlineSection(theme),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              _buildDescriptionSection(theme),
              SizedBox(height: ResponsiveHelper.spacing(context, 24)),
              _buildSaveButton(theme),
              SizedBox(height: ResponsiveHelper.spacing(context, 40)),
            ],
          ),
        ),
      ),
    );
  }

  /// ✨ 날짜 섹션 (수정 불가)
  Widget _buildDateSection(ThemeData theme) {
    final now = DateTime.now();
    final isSameYear = widget.to.date.year == now.year;
    final dateFormat = DateFormat(
      isSameYear ? 'MM월 dd일 (E)' : 'yyyy년 MM월 dd일 (E)',
      'ko_KR'
    );

    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.info_outline,
                  color: theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 20),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text(
                '근무 정보',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 채용 유형
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.to.isLongTerm
                    ? [
                        Colors.purple.withOpacity(0.1),
                        Colors.purple.withOpacity(0.05),
                      ]
                    : [
                        theme.primaryColor.withOpacity(0.1),
                        theme.primaryColor.withOpacity(0.05),
                      ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.to.isLongTerm
                    ? Colors.purple.withOpacity(0.3)
                    : theme.primaryColor.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  widget.to.isLongTerm ? Icons.event_repeat : Icons.event,
                  color: widget.to.isLongTerm ? Colors.purple : theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Text(
                  widget.to.jobTypeLabel,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    color: widget.to.isLongTerm ? Colors.purple : theme.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 날짜 표시
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  color: Colors.grey[700],
                  size: ResponsiveHelper.iconSize(context, 20),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: widget.to.isLongTerm
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '계약 기간',
                              style: ResponsiveHelper.tinyStyle(
                                context,
                                color: Colors.grey[600],
                              ),
                            ),
                            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                            Text(
                              widget.to.longTermPeriodWithDays,
                              style: ResponsiveHelper.bodyStyle(context).copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (widget.to.workDays != null && widget.to.workDays!.isNotEmpty) ...[
                              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                              Text(
                                widget.to.workDaysLabel,
                                style: ResponsiveHelper.smallStyle(
                                  context,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ],
                        )
                      : Text(
                          dateFormat.format(widget.to.date),
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // 경고 메시지
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber,
                  color: Colors.orange[700],
                  size: ResponsiveHelper.iconSize(context, 18),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Text(
                    '${widget.to.isLongTerm ? "계약 기간과 근무 요일" : "날짜"}은(는) 수정할 수 없습니다',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: Colors.orange[900],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 제목 섹션
  Widget _buildTitleSection(ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TO 제목',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          TextFormField(
            controller: _titleController,
            style: ResponsiveHelper.bodyStyle(context),
            decoration: InputDecoration(
              hintText: '예: 분류작업, 피킹업무',
              hintStyle: ResponsiveHelper.smallStyle(
                context,
                color: Colors.grey[400],
              ),
              prefixIcon: Icon(
                Icons.title,
                color: theme.primaryColor,
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.primaryColor, width: 2),
              ),
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
    );
  }

  /// ✨ 업무 목록 섹션
  Widget _buildWorkDetailsSection(ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '업무 목록 (${_workDetails.length}개)',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Material(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _showAddWorkDialog,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 16),
                      vertical: ResponsiveHelper.spacing(context, 12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add,
                          size: ResponsiveHelper.iconSize(context, 18),
                          color: Colors.green[700],
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Text(
                          '업무 추가',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          if (_workDetails.isEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 24)),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.work_outline,
                    size: ResponsiveHelper.iconSize(context, 48),
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  Text(
                    '등록된 업무가 없습니다',
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          ] else ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            ..._workDetails.map((work) => _buildWorkCard(theme, work)),
          ],
        ],
      ),
    );
  }

  /// ✨ 업무 카드
  Widget _buildWorkCard(ThemeData theme, WorkDetailModel work) {
    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 12),
      ),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey[50]!,
            Colors.grey[100]!,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 아이콘
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                decoration: BoxDecoration(
                  color: FormatHelper.parseColor(work.workTypeBackgroundColor ?? '#2196F3'),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: FormatHelper.parseColor(work.workTypeColor).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: WorkTypeIcon.buildFromString(
                  work.workTypeIcon,
                  color: FormatHelper.parseColor(work.workTypeColor),
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 16)),
              
              // 업무명
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      work.workType,
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: ResponsiveHelper.iconSize(context, 14),
                          color: Colors.grey[600],
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                        Text(
                          work.timeRange,
                          style: ResponsiveHelper.smallStyle(
                            context,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // 버튼들
              Material(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => _showEditWorkDialog(work),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                    child: Icon(
                      Icons.edit,
                      color: Colors.orange[700],
                      size: ResponsiveHelper.iconSize(context, 20),
                    ),
                  ),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Material(
                color: work.currentCount > 0 ? Colors.grey[200] : Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: work.currentCount > 0 ? null : () => _deleteWork(work),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                    child: Icon(
                      Icons.delete,
                      color: work.currentCount > 0 ? Colors.grey[400] : Colors.red[700],
                      size: ResponsiveHelper.iconSize(context, 20),
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Divider(color: Colors.grey[300]),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // 급여 & 인원
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '급여',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      work.formattedWage,
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.grey[300],
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '인원',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Row(
                      children: [
                        Text(
                          '${work.currentCount}/${work.requiredCount}명',
                          style: ResponsiveHelper.subtitleStyle(context).copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor,
                          ),
                        ),
                        if (work.currentCount > 0) ...[
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 6),
                              vertical: ResponsiveHelper.spacing(context, 2),
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '확정',
                              style: ResponsiveHelper.tinyStyle(
                                context,
                                color: Colors.orange[900],
                              ).copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ✨ 지원 마감 섹션
  Widget _buildDeadlineSection(ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '지원 마감 설정',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          if (widget.to.isLongTerm) ...[
            // 장기 TO: 고정 시간
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.purple.withOpacity(0.1),
                    Colors.purple.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.event_available,
                    color: Colors.purple,
                    size: ResponsiveHelper.iconSize(context, 20),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Text(
                      '모든 업무가 동일한 마감 시간을 사용합니다',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: Colors.purple,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _selectFixedDeadline(),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: Colors.purple,
                        size: ResponsiveHelper.iconSize(context, 24),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '지원 마감 일시',
                              style: ResponsiveHelper.smallStyle(
                                context,
                                color: Colors.grey[600],
                              ),
                            ),
                            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                            Text(
                              DateFormat('yyyy년 MM월 dd일 HH:mm', 'ko_KR').format(
                                _fixedDeadline ?? widget.to.applicationDeadline
                              ),
                              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: ResponsiveHelper.iconSize(context, 16),
                        color: Colors.grey[400],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else ...[
            // 단기 TO: N시간 전
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.primaryColor.withOpacity(0.1),
                    theme.primaryColor.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: theme.primaryColor,
                    size: ResponsiveHelper.iconSize(context, 20),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Text(
                      '각 업무별로 시작 시간 기준으로 자동 마감됩니다',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: theme.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            Row(
              children: [
                Text(
                  '업무 시작',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 16),
                    vertical: ResponsiveHelper.spacing(context, 8),
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.primaryColor),
                  ),
                  child: DropdownButton<int>(
                    value: _hoursBeforeStart,
                    underline: const SizedBox(),
                    items: List.generate(24, (index) => index + 1)
                        .map((hour) => DropdownMenuItem(
                              value: hour,
                              child: Text(
                                '$hour시간 전',
                                style: ResponsiveHelper.bodyStyle(context),
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _hoursBeforeStart = value!;
                      });
                    },
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  '마감',
                  style: ResponsiveHelper.bodyStyle(context),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// ✨ 설명 섹션
  Widget _buildDescriptionSection(ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '상세 설명 (선택)',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          TextFormField(
            controller: _descriptionController,
            maxLines: 5,
            style: ResponsiveHelper.bodyStyle(context),
            decoration: InputDecoration(
              hintText: '추가 설명을 입력하세요',
              hintStyle: ResponsiveHelper.smallStyle(
                context,
                color: Colors.grey[400],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.primaryColor, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 저장 버튼
  Widget _buildSaveButton(ThemeData theme) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor,
            theme.primaryColor.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.primaryColor.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _saveChanges,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: Colors.white,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Text(
                  '저장하기',
                  style: ResponsiveHelper.titleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
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
              style: ResponsiveHelper.titleStyle(context),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '시작 시간',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  DropdownButtonFormField<String>(
                    initialValue: startTime,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
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
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  Text(
                    '종료 시간',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  DropdownButtonFormField<String>(
                    initialValue: endTime,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
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
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  Text(
                    '금액 (원)',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  TextField(
                    controller: wageController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  Text(
                    '필요 인원',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  TextField(
                    controller: countController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
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

  Future<void> _selectFixedDeadline() async {
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
  }
}