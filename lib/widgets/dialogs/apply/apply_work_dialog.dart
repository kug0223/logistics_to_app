// lib/widgets/dialogs/apply/apply_work_dialog.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../models/core/to_model.dart';
import '../../../../models/core/work_detail_model.dart';
import '../../../../models/core/application_model.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/firestore_service.dart';
import '../../../../services/schedule_conflict_service.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../utils/toast_helper.dart';
import '../../../../utils/dialog_helper.dart';
import '../../../../theme/app_colors.dart';
import 'work_selection_card.dart';
import 'apply_summary_section.dart';
import 'confirm_cancel_dialog.dart';

/// 지원 다이얼로그 결과
class ApplyDialogResult {
  final bool hasChanges;
  final int appliedCount;
  final int canceledCount;

  const ApplyDialogResult({
    this.hasChanges = false,
    this.appliedCount = 0,
    this.canceledCount = 0,
  });
}

/// 통합 지원 다이얼로그
/// 
/// 모든 TO 타입(단일단기, 장기, 그룹단기)에서 사용 가능
class ApplyWorkDialog extends StatefulWidget {
  /// 메인 TO (단일/장기) 또는 그룹 마스터 TO
  final TOModel mainTO;
  
  /// 업무 상세 목록
  final List<WorkDetailModel> workDetails;
  
  /// 그룹 TO인 경우 날짜별 TO 맵
  /// key: DateTime (날짜), value: TOModel
  final Map<DateTime, TOModel>? groupTOsByDate;
  
  /// 그룹 TO인 경우 날짜별 업무 상세 맵
  /// key: DateTime (날짜), value: List<WorkDetailModel>
  final Map<DateTime, List<WorkDetailModel>>? groupWorkDetailsByDate;
  
  /// 사업장명
  final String businessName;

  const ApplyWorkDialog({
    super.key,
    required this.mainTO,
    required this.workDetails,
    this.groupTOsByDate,
    this.groupWorkDetailsByDate,
    required this.businessName,
  });

  /// 다이얼로그 표시 (간편 호출)
  static Future<ApplyDialogResult?> show({
    required BuildContext context,
    required TOModel to,
    required List<WorkDetailModel> workDetails,
    Map<DateTime, TOModel>? groupTOsByDate,
    Map<DateTime, List<WorkDetailModel>>? groupWorkDetailsByDate,
    required String businessName,
  }) {
    return showModalBottomSheet<ApplyDialogResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ApplyWorkDialog(
        mainTO: to,
        workDetails: workDetails,
        groupTOsByDate: groupTOsByDate,
        groupWorkDetailsByDate: groupWorkDetailsByDate,
        businessName: businessName,
      ),
    );
  }

  @override
  State<ApplyWorkDialog> createState() => _ApplyWorkDialogState();
}

class _ApplyWorkDialogState extends State<ApplyWorkDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  final ScheduleConflictService _conflictService = ScheduleConflictService();

  // 상태
  bool _isLoading = true;
  bool _hasChanges = false;
  String? _currentUserId;
  int _userNoShowCount = 0;

  // 그룹 TO용 선택된 날짜들
  final Set<DateTime> _selectedDates = {};

  // 날짜별 충돌 정보 캐시
  final Map<String, Map<String, ConflictInfo>> _conflictCache = {};

  // 날짜별 지원 상태 (workDetailId -> ApplicationModel)
  final Map<DateTime, Map<String, ApplicationModel>> _applicationsByDate = {};

  // 로딩 중인 업무 ID
  final Set<String> _loadingWorkIds = {};

  @override
  void initState() {
    super.initState();
    _initDialog();
  }

  Future<void> _initDialog() async {
    final userProvider = context.read<UserProvider>();
    _currentUserId = userProvider.currentUser?.uid;
    _userNoShowCount = userProvider.currentUser?.noShowCount ?? 0;

    if (_currentUserId == null) {
      ToastHelper.showError('로그인이 필요합니다');
      Navigator.pop(context);
      return;
    }

    // 이용 제한 체크
    final restrictedUntil = await _conflictService.checkUserRestriction(_currentUserId!);
    if (restrictedUntil != null && mounted) {
      final dateFormat = DateFormat('M/d (E) HH:mm', 'ko_KR');
      await DialogHelper.showError(
        context,
        message: '노쇼 3회로 인해 이용이 제한되었습니다.\n해제일: ${dateFormat.format(restrictedUntil)}',
      );
      Navigator.pop(context);
      return;
    }

    await _loadApplicationStatus();
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// 기존 지원 상태 로드
  Future<void> _loadApplicationStatus() async {
    if (_currentUserId == null) return;

    try {
      if (_isGroupTO) {
        // 그룹 TO: 각 날짜별로 지원 상태 로드
        for (final entry in widget.groupTOsByDate!.entries) {
          final date = entry.key;
          final to = entry.value;
          
          final applications = await _firestoreService.getApplicationsForTO(
            toId: to.id,
            uid: _currentUserId!,
          );
          
          _applicationsByDate[date] = {
            for (final app in applications)
              app.selectedWorkType: app
          };
          
          // 충돌 체크
          final workDetails = widget.groupWorkDetailsByDate?[date] ?? [];
          if (workDetails.isNotEmpty) {
            final conflicts = await _conflictService.checkConflictsForWorkDetails(
              uid: _currentUserId!,
              workDate: date,
              workDetails: workDetails,
            );
            _conflictCache[_dateKey(date)] = conflicts;
          }
        }
      } else {
        // 단일/장기 TO
        final applications = await _firestoreService.getApplicationsForTO(
          toId: widget.mainTO.id,
          uid: _currentUserId!,
        );
        
        print('📋 로드된 지원서 수: ${applications.length}');
        for (final app in applications) {
          print('  - ${app.selectedWorkType}: ${app.status}');
        }
        
        _applicationsByDate[widget.mainTO.date] = {
        for (final app in applications)
          _makeWorkKey(app.selectedWorkType, app.startTime, app.endTime): app
      };
        
        print('📋 _applicationsByDate 키: ${_applicationsByDate[widget.mainTO.date]?.keys.toList()}');
        
        // 충돌 체크
        final conflicts = await _conflictService.checkConflictsForWorkDetails(
          uid: _currentUserId!,
          workDate: widget.mainTO.date,
          workDetails: widget.workDetails,
        );
        _conflictCache[_dateKey(widget.mainTO.date)] = conflicts;
      }
    } catch (e) {
      print('❌ 지원 상태 로드 실패: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Getters
  // ═══════════════════════════════════════════════════════════

  bool get _isGroupTO => 
      widget.groupTOsByDate != null && widget.groupTOsByDate!.isNotEmpty;

  bool get _isLongTerm => widget.mainTO.jobType == 'long_term';

  String _dateKey(DateTime date) => 
      '${date.year}-${date.month}-${date.day}';

  // ═══════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.85,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(ResponsiveHelper.spacing(context, 24)),
          topRight: Radius.circular(ResponsiveHelper.spacing(context, 24)),
        ),
      ),
      child: Column(
        children: [
          // 핸들바
          _buildHandle(context),
          
          // 헤더
          _buildHeader(context, theme),
          
          // 구분선
          Divider(height: 1, color: AppColors.grey200),
          
          // 내용
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildContent(context, theme),
          ),
          
          // 하단 버튼
          _buildBottomButton(context, theme),
        ],
      ),
    );
  }

  Widget _buildHandle(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 12)),
      width: ResponsiveHelper.spacing(context, 40),
      height: ResponsiveHelper.spacing(context, 4),
      decoration: BoxDecoration(
        color: AppColors.grey300,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    final dateFormat = DateFormat('M/d (E)', 'ko_KR');
    
    String subtitle;
    if (_isLongTerm) {
      subtitle = widget.mainTO.longTermPeriodWithDays;
    } else if (_isGroupTO) {
      final dates = widget.groupTOsByDate!.keys.toList()..sort();
      subtitle = '${dateFormat.format(dates.first)} ~ ${dateFormat.format(dates.last)} (${dates.length}일)';
    } else {
      subtitle = dateFormat.format(widget.mainTO.date);
    }

    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '지원하기',
            style: ResponsiveHelper.titleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Row(
            children: [
              Icon(
                Icons.business,
                size: ResponsiveHelper.iconSize(context, 16),
                color: AppColors.grey600,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text(
                widget.businessName,
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Icon(
                Icons.calendar_today,
                size: ResponsiveHelper.iconSize(context, 16),
                color: AppColors.grey600,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Expanded(
                child: Text(
                  subtitle,
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          
          // 장기 공고 안내
          if (_isLongTerm) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
              decoration: BoxDecoration(
                color: AppColors.infoBg,
                borderRadius: BorderRadius.circular(
                  ResponsiveHelper.spacing(context, 8),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: ResponsiveHelper.iconSize(context, 18),
                    color: AppColors.infoDark,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      '장기 근무는 전체 기간에 대해 일괄 지원됩니다.\n${widget.mainTO.workDaysLabel}',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: AppColors.infoDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, ThemeData theme) {
    if (_isGroupTO) {
      return _buildGroupTOContent(context, theme);
    } else {
      return _buildSingleTOContent(context, theme);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 단일/장기 TO 내용
  // ═══════════════════════════════════════════════════════════

  Widget _buildSingleTOContent(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 업무 선택 섹션
          _buildSectionTitle(context, '업무 선택'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          ...widget.workDetails.map((work) {
            final workKey = _makeWorkKey(work.workType, work.startTime, work.endTime);
            final application = _applicationsByDate[widget.mainTO.date]?[workKey];
            final conflictInfo = _conflictCache[_dateKey(widget.mainTO.date)]?[work.id] 
                ?? ConflictInfo.ok;
            
            print('🔍 ${work.workType}: application=${application?.status}, status=${_getApplicationStatus(application)}');
            
            return WorkSelectionCard(
              workDetail: work,
              status: _getApplicationStatus(application),
              conflictInfo: conflictInfo,
              isLoading: _loadingWorkIds.contains(work.id),
              onApply: () => _applyForWork(widget.mainTO, work),
              onCancelApplication: application != null
                  ? () => _cancelApplication(application)
                  : null,
              onCancelConfirm: application != null
                  ? () => _cancelConfirm(application, work)
                  : null,
            );
          }),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 지원 요약
          ApplySummarySection(
            applicationInfos: [
              DateApplicationInfo(
                date: widget.mainTO.date,
                appliedWorks: _getAppliedWorks(widget.mainTO.date, widget.workDetails),
                confirmedWorks: _getConfirmedWorks(widget.mainTO.date, widget.workDetails),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 그룹 TO 내용
  // ═══════════════════════════════════════════════════════════

  Widget _buildGroupTOContent(BuildContext context, ThemeData theme) {
    final sortedDates = widget.groupTOsByDate!.keys.toList()..sort();

    return SingleChildScrollView(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 날짜 선택 섹션
          _buildSectionTitle(context, '날짜 선택'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          _buildDateSelector(context, theme, sortedDates),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 선택된 날짜별 업무 목록
          if (_selectedDates.isNotEmpty) ...[
            ...(_selectedDates.toList()..sort()).map((date) {
              return _buildDateWorkSection(context, theme, date);
            }),
          ] else
            _buildEmptyDateSelection(context),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 지원 요약
          ApplySummarySection(
            applicationInfos: sortedDates.map((date) {
              final workDetails = widget.groupWorkDetailsByDate?[date] ?? [];
              return DateApplicationInfo(
                date: date,
                appliedWorks: _getAppliedWorks(date, workDetails),
                confirmedWorks: _getConfirmedWorks(date, workDetails),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector(
    BuildContext context,
    ThemeData theme,
    List<DateTime> dates,
  ) {
    final dateFormat = DateFormat('M/d', 'ko_KR');
    final dayFormat = DateFormat('E', 'ko_KR');

    return Wrap(
      spacing: ResponsiveHelper.spacing(context, 8),
      runSpacing: ResponsiveHelper.spacing(context, 8),
      children: dates.map((date) {
        final isSelected = _selectedDates.contains(date);
        final hasApplication = _hasAnyApplication(date);
        
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedDates.remove(date);
              } else {
                _selectedDates.add(date);
              }
            });
          },
          child: Container(
            width: ResponsiveHelper.spacing(context, 60),
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            decoration: BoxDecoration(
              color: isSelected 
                  ? theme.primaryColor 
                  : (hasApplication ? AppColors.successBg : Colors.white),
              borderRadius: BorderRadius.circular(
                ResponsiveHelper.spacing(context, 10),
              ),
              border: Border.all(
                color: isSelected 
                    ? theme.primaryColor 
                    : (hasApplication ? AppColors.success : AppColors.grey300),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Text(
                  dateFormat.format(date),
                  style: ResponsiveHelper.bodyStyle(
                    context,
                    color: isSelected ? Colors.white : AppColors.grey800,
                  ).copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  dayFormat.format(date),
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: isSelected ? Colors.white70 : AppColors.grey500,
                  ),
                ),
                if (hasApplication) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                  Icon(
                    Icons.check_circle,
                    size: ResponsiveHelper.iconSize(context, 14),
                    color: isSelected ? Colors.white : AppColors.success,
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDateWorkSection(
    BuildContext context,
    ThemeData theme,
    DateTime date,
  ) {
    final dateFormat = DateFormat('M/d (E)', 'ko_KR');
    final to = widget.groupTOsByDate![date];
    final workDetails = widget.groupWorkDetailsByDate?[date] ?? [];

    if (to == null || workDetails.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 날짜 헤더
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 8),
          ),
          decoration: BoxDecoration(
            color: theme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(
              ResponsiveHelper.spacing(context, 8),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: ResponsiveHelper.iconSize(context, 16),
                color: theme.primaryColor,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                dateFormat.format(date),
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        
        // 업무 목록
        ...workDetails.map((work) {
          final workKey = _makeWorkKey(work.workType, work.startTime, work.endTime);
          final application = _applicationsByDate[date]?[workKey];
          final conflictInfo = _conflictCache[_dateKey(date)]?[work.id] 
              ?? ConflictInfo.ok;
          
          return WorkSelectionCard(
            workDetail: work,
            status: _getApplicationStatus(application),
            conflictInfo: conflictInfo,
            isLoading: _loadingWorkIds.contains('${date.millisecondsSinceEpoch}_${work.id}'),
            onApply: () => _applyForWork(to, work, date: date),
            onCancelApplication: application != null
                ? () => _cancelApplication(application)
                : null,
            onCancelConfirm: application != null
                ? () => _cancelConfirm(application, work, date: date)
                : null,
          );
        }),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
      ],
    );
  }

  Widget _buildEmptyDateSelection(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: ResponsiveHelper.iconSize(context, 48),
              color: AppColors.grey400,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text(
              '위에서 날짜를 선택하세요',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 공통 위젯
  // ═══════════════════════════════════════════════════════════

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: ResponsiveHelper.subtitleStyle(context).copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildBottomButton(BuildContext context, ThemeData theme) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: ResponsiveHelper.spacing(context, 50),
          child: ElevatedButton(
            onPressed: () => Navigator.pop(
              context,
              ApplyDialogResult(hasChanges: _hasChanges),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  ResponsiveHelper.spacing(context, 12),
                ),
              ),
              elevation: 0,
            ),
            child: Text(
              '닫기',
              style: ResponsiveHelper.subtitleStyle(context, color: Colors.white).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 헬퍼 메서드
  // ═══════════════════════════════════════════════════════════

  WorkApplicationStatus _getApplicationStatus(ApplicationModel? application) {
    if (application == null) return WorkApplicationStatus.notApplied;
    
    switch (application.status) {
      case 'CONFIRMED':
        return WorkApplicationStatus.confirmed;
      case 'PENDING':
        return WorkApplicationStatus.pending;
      case 'REJECTED':
      case 'CANCELED':
      case 'AUTO_CANCELED':
        return WorkApplicationStatus.notApplied;
      default:
        return WorkApplicationStatus.notApplied;
    }
  }

  bool _hasAnyApplication(DateTime date) {
    final apps = _applicationsByDate[date];
    if (apps == null || apps.isEmpty) return false;
    
    return apps.values.any((app) => 
      app.status == 'PENDING' || app.status == 'CONFIRMED'
    );
  }

  List<WorkDetailModel> _getAppliedWorks(DateTime date, List<WorkDetailModel> workDetails) {
    final apps = _applicationsByDate[date];
    if (apps == null) return [];
    
    return workDetails.where((work) {
      final app = apps[work.workType];
      return app != null && app.status == 'PENDING';
    }).toList();
  }

  List<WorkDetailModel> _getConfirmedWorks(DateTime date, List<WorkDetailModel> workDetails) {
    final apps = _applicationsByDate[date];
    if (apps == null) return [];
    
    return workDetails.where((work) {
      final app = apps[work.workType];
      return app != null && app.status == 'CONFIRMED';
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // 액션 메서드
  // ═══════════════════════════════════════════════════════════

  /// 지원하기
  Future<void> _applyForWork(TOModel to, WorkDetailModel work, {DateTime? date}) async {
    final loadingKey = date != null 
        ? '${date.millisecondsSinceEpoch}_${work.id}' 
        : work.id;
    
    setState(() => _loadingWorkIds.add(loadingKey));

    try {
      await _firestoreService.applyForTO(
        toId: to.id,
        workDetailId: work.id,
        workType: work.workType,
        uid: _currentUserId!,
      );

      // 상태 새로고침
      await _refreshApplicationStatus(date ?? to.date, work.workType);
      
      _hasChanges = true;
      ToastHelper.showSuccess('지원이 완료되었습니다');
    } catch (e) {
      print('❌ 지원 실패: $e');
      ToastHelper.showError('지원에 실패했습니다');
    } finally {
      if (mounted) {
        setState(() => _loadingWorkIds.remove(loadingKey));
      }
    }
  }

  /// 지원 취소
  Future<void> _cancelApplication(ApplicationModel application) async {
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '지원 취소',
      message: '${application.selectedWorkType} 지원을 취소하시겠습니까?',
      confirmText: '취소하기',
    );

    if (!confirmed) return;

    setState(() => _loadingWorkIds.add(application.selectedWorkType));

    try {
      await _firestoreService.cancelApplication(application.id, _currentUserId!);
      
      // 상태 새로고침
      await _refreshApplicationStatus(application.workDate, application.selectedWorkType);
      
      _hasChanges = true;
      ToastHelper.showSuccess('지원이 취소되었습니다');
    } catch (e) {
      print('❌ 지원 취소 실패: $e');
      ToastHelper.showError('지원 취소에 실패했습니다');
    } finally {
      if (mounted) {
        setState(() => _loadingWorkIds.remove(application.selectedWorkType));
      }
    }
  }

  /// 확정 취소
  Future<void> _cancelConfirm(
    ApplicationModel application,
    WorkDetailModel work, {
    DateTime? date,
  }) async {
    final result = await ConfirmCancelDialog.show(
      context: context,
      workDate: date ?? application.workDate,
      workType: work.workType,
      timeRange: work.timeRange,
      businessName: widget.businessName,
      currentNoShowCount: _userNoShowCount,
    );

    if (result != ConfirmCancelResult.proceed) return;

    final loadingKey = date != null 
        ? '${date.millisecondsSinceEpoch}_${work.id}' 
        : work.id;
    
    setState(() => _loadingWorkIds.add(loadingKey));

    try {
      // 패널티 적용 여부
      final hasPenalty = _conflictService.shouldApplyPenalty(date ?? application.workDate);
      
      await _firestoreService.cancelConfirmedApplication(
        application.id,
        applyNoShowPenalty: hasPenalty,
      );
      
      if (hasPenalty) {
        _userNoShowCount++;
      }
      
      // 상태 새로고침
      await _refreshApplicationStatus(date ?? application.workDate, application.selectedWorkType);
      
      _hasChanges = true;
      
      if (hasPenalty) {
        ToastHelper.showWarning('확정이 취소되었습니다. 노쇼 1회가 기록되었습니다.');
      } else {
        ToastHelper.showSuccess('확정이 취소되었습니다');
      }
    } catch (e) {
      print('❌ 확정 취소 실패: $e');
      ToastHelper.showError('확정 취소에 실패했습니다');
    } finally {
      if (mounted) {
        setState(() => _loadingWorkIds.remove(loadingKey));
      }
    }
  }

  /// 특정 날짜/업무의 상태 새로고침
  Future<void> _refreshApplicationStatus(DateTime date, String workType) async {
    if (_currentUserId == null) return;

    try {
      TOModel? to;
      
      if (_isGroupTO) {
        to = widget.groupTOsByDate?[date];
      } else {
        to = widget.mainTO;
      }
      
      if (to == null) return;

      final applications = await _firestoreService.getApplicationsForTO(
        toId: to.id,
        uid: _currentUserId!,
      );

      if (mounted) {
        setState(() {
          _applicationsByDate[date] = {
            for (final app in applications)
              app.selectedWorkType: app
          };
        });
      }
    } catch (e) {
      print('❌ 상태 새로고침 실패: $e');
    }
  }
  /// 업무 고유 키 생성 (workType + 시간)
  String _makeWorkKey(String workType, String startTime, String endTime) {
    return '${workType}_${startTime}_$endTime';
  }
}