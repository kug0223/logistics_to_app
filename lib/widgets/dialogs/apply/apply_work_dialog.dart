// lib/widgets/dialogs/apply/apply_work_dialog.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/firestore_service.dart';
import '../../../services/schedule_conflict_service.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../theme/app_colors.dart';
import 'work_selection_card.dart';
import 'apply_summary_section.dart';
import 'confirm_cancel_dialog.dart';
import '../../../utils/navigation_helper.dart';
import '../../../screens/common/job_posting_screen.dart';

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
  final Map<DateTime, TOModel>? groupTOsByDate;
  
  /// 그룹 TO인 경우 날짜별 업무 상세 맵
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

  // ═══════════════════════════════════════════════════════════
  // 상태 변수
  // ═══════════════════════════════════════════════════════════
  
  bool _isLoading = true;
  bool _hasChanges = false;
  String? _currentUserId;
  int _userNoShowCount = 0;

  // 그룹 TO용 - 단일 날짜 선택 (캘린더)
  DateTime? _selectedDate;
  DateTime _focusedDay = DateTime.now();

  // 날짜별 지원 상태 캐시
  // key: DateTime, value: Map<workKey, ApplicationModel>
  final Map<DateTime, Map<String, ApplicationModel>> _applicationsByDate = {};

  // 날짜별 충돌 정보 캐시
  // key: 'yyyy-MM-dd', value: Map<workDetailId, ConflictInfo>
  final Map<String, Map<String, ConflictInfo>> _conflictCache = {};

  // 로딩 중인 업무 ID 목록
  final Set<String> _loadingWorkIds = {};

  // 내 확정 스케줄 (해당 날짜)
  List<ApplicationModel> _myConfirmedSchedules = [];

  // ═══════════════════════════════════════════════════════════
  // Getter
  // ═══════════════════════════════════════════════════════════
  
  bool get _isGroupTO => 
      widget.groupTOsByDate != null && widget.groupTOsByDate!.isNotEmpty;

  bool get _isLongTerm => widget.mainTO.isLongTerm;

  /// 등록된 날짜 목록 (그룹 TO)
  Set<DateTime> get _availableDates {
    if (!_isGroupTO) return {};
    return widget.groupTOsByDate!.keys
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();
  }

  // ═══════════════════════════════════════════════════════════
  // 라이프사이클
  // ═══════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    final userProvider = context.read<UserProvider>();
    _currentUserId = userProvider.currentUser?.uid;
    _userNoShowCount = userProvider.currentUser?.noShowCount ?? 0;

    if (_currentUserId == null) {
      ToastHelper.showError('로그인이 필요합니다');
      Navigator.pop(context);
      return;
    }

    // 그룹 TO인 경우 첫 날짜 자동 선택
    if (_isGroupTO) {
      final sortedDates = widget.groupTOsByDate!.keys.toList()..sort();
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      
      // 오늘 이후 가장 가까운 날짜 선택
      final futureDate = sortedDates.cast<DateTime?>().firstWhere(
        (d) => !d!.isBefore(todayOnly),
        orElse: () => null,
      );
      
      _selectedDate = futureDate ?? sortedDates.last;
      _focusedDay = _selectedDate!;
    }

    await _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    try {
      if (_isGroupTO) {
        // 그룹 TO: ✅ 모든 날짜의 지원 상태 로드 (마커 표시용)
        final allDates = widget.groupTOsByDate!.keys.toList();
        await Future.wait(allDates.map((date) => _loadDateApplications(date)));
        
        // 선택된 날짜의 충돌/스케줄 로드
        if (_selectedDate != null) {
          await _loadMyConfirmedSchedules(_selectedDate!);
          await _loadConflictsForDate(_selectedDate!);
        }
      } else {
        // 단일/장기 TO: 메인 TO의 지원 상태 로드
        await _loadDateApplications(widget.mainTO.date);
        await _loadMyConfirmedSchedules(widget.mainTO.date);
        await _loadConflictsForDate(widget.mainTO.date);
      }
    } catch (e) {
      print('❌ 초기 데이터 로드 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 특정 날짜의 지원 상태 로드
  Future<void> _loadDateApplications(DateTime date) async {
    if (_currentUserId == null) return;

    TOModel? to;
    if (_isGroupTO) {
      final dateKey = DateTime(date.year, date.month, date.day);
      to = widget.groupTOsByDate?[dateKey];
    } else {
      to = widget.mainTO;
    }

    if (to == null) return;

    try {
      final applications = await _firestoreService.getApplicationsForTO(
        toId: to.id,
        uid: _currentUserId!,
      );

      final dateKey = DateTime(date.year, date.month, date.day);
      _applicationsByDate[dateKey] = {
        for (final app in applications)
          _makeWorkKey(app.selectedWorkType, app.startTime, app.endTime): app
      };
    } catch (e) {
      print('❌ 지원 상태 로드 실패: $e');
    }
  }

  /// 특정 날짜의 내 확정 스케줄 로드
  /// ✅ 현재 보고 있는 TO의 확정 근무는 제외 (이미 표시되니까)
  Future<void> _loadMyConfirmedSchedules(DateTime date) async {
    if (_currentUserId == null) return;

    try {
      final schedules = await _firestoreService.getConfirmedSchedules(
        uid: _currentUserId!,
        workDate: date,
      );
      
      if (mounted) {
        setState(() {
          // ✅ 해당 날짜의 모든 확정 근무 표시 (같은 TO 포함)
          _myConfirmedSchedules = schedules;
        });
      }
    } catch (e) {
      print('❌ 확정 스케줄 로드 실패: $e');
    }
  }

  /// 특정 날짜의 충돌 정보 로드
  Future<void> _loadConflictsForDate(DateTime date) async {
    if (_currentUserId == null) return;

    List<WorkDetailModel> workDetails;
    if (_isGroupTO) {
      final dateKey = DateTime(date.year, date.month, date.day);
      workDetails = widget.groupWorkDetailsByDate?[dateKey] ?? [];
    } else {
      workDetails = widget.workDetails;
    }

    if (workDetails.isEmpty) return;

    try {
      final conflicts = await _conflictService.checkConflictsForWorkDetails(
        uid: _currentUserId!,
        workDate: date,
        workDetails: workDetails,
      );

      _conflictCache[_dateKey(date)] = conflicts;
    } catch (e) {
      print('❌ 충돌 정보 로드 실패: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // UI 빌드
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    
    // 다이얼로그 높이 계산 (화면의 90%)
    final dialogHeight = mediaQuery.size.height * 0.9;

    // ⭐ PopScope 추가: 외부 탭으로 닫아도 변경 여부 반환
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pop(context, ApplyDialogResult(hasChanges: _hasChanges));
        }
      },
      child: Container(
        height: dialogHeight,
        decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ResponsiveHelper.spacing(context, 24)),
        ),
      ),
      child: Column(
        children: [
          // 핸들바
          _buildHandle(context),
          
          // 헤더
          _buildHeader(context, theme),
          
          // 구분선
          Divider(height: 1, color: AppColors.divider),
          
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
    ),  // ⭐ PopScope child 닫기
    );  // ⭐ PopScope 닫기
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
    
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목
          Text(
            '지원하기',
            style: ResponsiveHelper.titleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          // 사업장 & 날짜 정보
          Row(
            children: [
              Icon(
                Icons.business,
                size: ResponsiveHelper.iconSize(context, 16),
                color: AppColors.grey600,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Expanded(
                child: Text(
                  widget.businessName,
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              
              Icon(
                Icons.calendar_today,
                size: ResponsiveHelper.iconSize(context, 16),
                color: AppColors.grey600,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text(
                _isGroupTO
                    ? '${dateFormat.format(widget.groupTOsByDate!.keys.first)} ~ ${dateFormat.format(widget.groupTOsByDate!.keys.last)} (${widget.groupTOsByDate!.length}일)'
                    : _isLongTerm
                        ? '${dateFormat.format(widget.mainTO.date)} ~ ${dateFormat.format(widget.mainTO.endDate ?? widget.mainTO.date)}'
                        : dateFormat.format(widget.mainTO.date),
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
              ),
            ],
          ),
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
          // ✅ 장기공고 캘린더 (읽기전용 - 전체 기간 표시) - 맨 위로!
          if (_isLongTerm) ...[
            _buildLongTermCalendarSection(context, theme),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ],
          
          // 내 확정 스케줄 경고 - 캘린더 아래로
          if (_myConfirmedSchedules.isNotEmpty)
            _buildMyScheduleWarning(context, theme),
          
          // 업무 선택 섹션
          _buildSectionTitle(context, '업무 선택'),
          
          ...widget.workDetails.map((work) {
            final workKey = _makeWorkKey(work.workType, work.startTime, work.endTime);
            final application = _applicationsByDate[widget.mainTO.date]?[workKey];
            final conflictInfo = _conflictCache[_dateKey(widget.mainTO.date)]?[work.id] 
                ?? ConflictInfo.ok;
            
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
  // 장기공고 캘린더 섹션 (읽기전용)
  // ═══════════════════════════════════════════════════════════

  /// 장기공고용 읽기전용 캘린더
  /// - 전체 기간 표시 (선택 불가)
  /// - 근무 요일 강조
  Widget _buildLongTermCalendarSection(BuildContext context, ThemeData theme) {
    final startDate = widget.mainTO.date;
    final endDate = widget.mainTO.endDate ?? widget.mainTO.date;
    final workDays = widget.mainTO.workDays ?? [];
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.spacing(context, 12),
        ),
        border: Border.all(color: AppColors.longTermLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 헤더: 근무 기간 안내
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: AppColors.longTermBg,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(ResponsiveHelper.spacing(context, 11)),
                topRight: Radius.circular(ResponsiveHelper.spacing(context, 11)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.date_range,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: AppColors.longTermDark,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    '근무 기간 (전체 선택됨)',
                    style: ResponsiveHelper.bodyStyle(context, color: AppColors.longTermDark).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 캘린더
          TableCalendar(
            locale: 'ko_KR',
            firstDay: DateTime(startDate.year, startDate.month, 1),
            lastDay: DateTime(endDate.year, endDate.month + 1, 0),
            focusedDay: startDate,
            calendarFormat: CalendarFormat.month,
            
            // 컴팩트한 사이즈
            daysOfWeekHeight: ResponsiveHelper.spacing(context, 28),
            rowHeight: ResponsiveHelper.spacing(context, 40),
            
            // 선택 비활성화 (읽기전용 - 선택해도 아무 동작 안함)
            selectedDayPredicate: (day) => false,
            enabledDayPredicate: (day) => true, // 표시는 하되
            
            // 선택해도 아무 동작 안함 (읽기전용)
            onDaySelected: (selectedDay, focusedDay) {
              // 아무 동작 안함 - 읽기전용
            },
            onPageChanged: (focusedDay) {},
            
            // 헤더 스타일
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
              leftChevronIcon: Icon(
                Icons.chevron_left,
                color: AppColors.grey600,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
              rightChevronIcon: Icon(
                Icons.chevron_right,
                color: AppColors.grey600,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
            ),
            
            // 요일 헤더 스타일
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
              weekendStyle: ResponsiveHelper.smallStyle(context, color: AppColors.error),
            ),
            
            // 커스텀 빌더 (근무일 강조)
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                return _buildLongTermDayCell(context, day, startDate, endDate, workDays, false);
              },
              outsideBuilder: (context, day, focusedDay) {
                return _buildLongTermDayCell(context, day, startDate, endDate, workDays, true);
              },
              todayBuilder: (context, day, focusedDay) {
                return _buildLongTermDayCell(context, day, startDate, endDate, workDays, false, isToday: true);
              },
              disabledBuilder: (context, day, focusedDay) {
                return _buildLongTermDayCell(context, day, startDate, endDate, workDays, true);
              },
            ),
          ),
          
          // 범례
          Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(context, theme.primaryColor, '확정'),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                _buildLegendItem(context, Colors.orange, '대기'),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                _buildLegendItem(context, AppColors.grey400, '지원가능'),
              ],
            ),
          ),
          
          // ✅ 안내 메시지 (일괄 지원 + 여러 업무 안내)
          Container(
            margin: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 12),
              0,
              ResponsiveHelper.spacing(context, 12),
              ResponsiveHelper.spacing(context, 12),
            ),
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
            decoration: BoxDecoration(
              color: AppColors.infoBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.infoLight),
            ),
            child: Column(
              children: [
                // 일괄 지원 안내
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: ResponsiveHelper.iconSize(context, 16),
                      color: AppColors.infoDark,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(
                        '고정 근무는 전체 기간에 대해 일괄 지원됩니다.\n${widget.mainTO.workDaysLabel}',
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                // 여러 업무 지원 안내
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: ResponsiveHelper.iconSize(context, 16),
                      color: AppColors.infoDark,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(
                        '같은 시간대에 여러 업무 지원 가능!\n확정 시 겹치는 지원은 자동 취소돼요.',
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 장기공고 캘린더 날짜 셀
  Widget _buildLongTermDayCell(
    BuildContext context,
    DateTime day,
    DateTime startDate,
    DateTime endDate,
    List<String> workDays,
    bool isOutside, {
    bool isToday = false,
  }) {
    // 근무 기간 내인지 확인
    final isInRange = !day.isBefore(startDate) && !day.isAfter(endDate);
    
    // 근무 요일인지 확인
    bool isWorkDay = false;
    if (isInRange) {
      if (workDays.isEmpty) {
        isWorkDay = true; // 요일 설정 없으면 매일 근무
      } else {
        const dayNames = ['월', '화', '수', '목', '금', '토', '일'];
        final dayName = dayNames[day.weekday - 1];
        isWorkDay = workDays.contains(dayName);
      }
    }
    
    // 배경색 결정
    Color bgColor;
    Color textColor;
    if (isOutside) {
      bgColor = Colors.transparent;
      textColor = AppColors.grey300;
    } else if (isInRange && isWorkDay) {
      bgColor = AppColors.longTerm.withOpacity(0.3);
      textColor = AppColors.longTermDark;
    } else if (isInRange) {
      bgColor = AppColors.grey100;
      textColor = AppColors.grey500;
    } else {
      bgColor = Colors.transparent;
      textColor = AppColors.grey400;
    }
    
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: isToday ? Border.all(color: Theme.of(context).primaryColor, width: 2) : null,
      ),
      child: Center(
        child: Text(
          '${day.day}',
          style: ResponsiveHelper.smallStyle(context, color: textColor).copyWith(
            fontWeight: isInRange && isWorkDay ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// 범례 아이템
  Widget _buildLegendItem(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: ResponsiveHelper.spacing(context, 12),
          height: ResponsiveHelper.spacing(context, 12),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text(
          label,
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 그룹 TO 내용 (캘린더 UI)
  // ═══════════════════════════════════════════════════════════

  Widget _buildGroupTOContent(BuildContext context, ThemeData theme) {
    final sortedDates = widget.groupTOsByDate!.keys.toList()..sort();

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 캘린더 섹션
          _buildCalendarSection(context, theme, sortedDates),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 선택된 날짜가 있으면 상세 표시
          if (_selectedDate != null) ...[
            // 내 확정 스케줄 경고
            if (_myConfirmedSchedules.isNotEmpty)
              _buildMyScheduleWarning(context, theme),
            
            // 업무 목록
            _buildDateWorkSection(context, theme, _selectedDate!),
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
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        ],
      ),
    );
  }

  /// 캘린더 섹션 (그룹 TO용)
  Widget _buildCalendarSection(
    BuildContext context, 
    ThemeData theme,
    List<DateTime> availableDates,
  ) {
    // 캘린더 범위 설정 (등록된 날짜 기준)
    final firstDate = availableDates.first;
    final lastDate = availableDates.last;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.spacing(context, 12),
        ),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 캘린더
          TableCalendar(
            locale: 'ko_KR',
            firstDay: DateTime(firstDate.year, firstDate.month, 1),
            lastDay: DateTime(lastDate.year, lastDate.month + 1, 0),
            focusedDay: _focusedDay,
            calendarFormat: CalendarFormat.month,
            
            // 컴팩트한 사이즈
            daysOfWeekHeight: ResponsiveHelper.spacing(context, 28),
            rowHeight: ResponsiveHelper.spacing(context, 40),
            
            // 선택된 날짜
            selectedDayPredicate: (day) {
              if (_selectedDate == null) return false;
              return DateUtils.isSameDay(_selectedDate, day);
            },
            
            // 활성화된 날짜 (등록된 날짜만)
            enabledDayPredicate: (day) {
              return _availableDates.any((d) => DateUtils.isSameDay(d, day));
            },
            
            // 날짜 선택
            onDaySelected: (selectedDay, focusedDay) {
              // 등록된 날짜인지 확인
              final isAvailable = _availableDates.any(
                (d) => DateUtils.isSameDay(d, selectedDay),
              );
              
              if (!isAvailable) return;
              
              setState(() {
                _selectedDate = selectedDay;
                _focusedDay = focusedDay;
                _myConfirmedSchedules = [];
              });
              
              // 해당 날짜 데이터 로드
              _loadDateApplications(selectedDay);
              _loadMyConfirmedSchedules(selectedDay);
              _loadConflictsForDate(selectedDay);
            },
            
            onPageChanged: (focusedDay) {
              setState(() {
                _focusedDay = focusedDay;
              });
            },
            
            // 이벤트 마커 (지원/확정 상태)
            eventLoader: (day) {
              final dateKey = DateTime(day.year, day.month, day.day);
              final apps = _applicationsByDate[dateKey];
              if (apps == null || apps.isEmpty) return [];
              
              // 마커용 이벤트 리스트 반환
              final events = <String>[];
              for (final app in apps.values) {
                if (app.status == 'CONFIRMED') {
                  events.add('confirmed');
                } else if (app.status == 'PENDING') {
                  events.add('pending');
                }
              }
              return events;
            },
            
            // 헤더 스타일
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
              leftChevronIcon: Icon(
                Icons.chevron_left,
                size: ResponsiveHelper.iconSize(context, 24),
                color: theme.primaryColor,
              ),
              rightChevronIcon: Icon(
                Icons.chevron_right,
                size: ResponsiveHelper.iconSize(context, 24),
                color: theme.primaryColor,
              ),
              headerPadding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 8),
              ),
            ),
            
            // 요일 스타일
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: ResponsiveHelper.smallStyle(
                context,
                color: AppColors.grey600,
              ),
              weekendStyle: ResponsiveHelper.smallStyle(
                context,
                color: AppColors.errorDark,
              ),
            ),
            
            // 날짜 셀 빌더
            calendarBuilders: CalendarBuilders(
              // 기본 날짜
              defaultBuilder: (context, day, focusedDay) {
                final isAvailable = _availableDates.any(
                  (d) => DateUtils.isSameDay(d, day),
                );
                
                return _buildDayCell(
                  context,
                  day,
                  isAvailable: isAvailable,
                  isSelected: false,
                  isToday: false,
                );
              },
              
              // 선택된 날짜
              selectedBuilder: (context, day, focusedDay) {
                return _buildDayCell(
                  context,
                  day,
                  isAvailable: true,
                  isSelected: true,
                  isToday: DateUtils.isSameDay(day, DateTime.now()),
                );
              },
              
              // 오늘
              todayBuilder: (context, day, focusedDay) {
                final isAvailable = _availableDates.any(
                  (d) => DateUtils.isSameDay(d, day),
                );
                final isSelected = _selectedDate != null && 
                    DateUtils.isSameDay(_selectedDate, day);
                
                return _buildDayCell(
                  context,
                  day,
                  isAvailable: isAvailable,
                  isSelected: isSelected,
                  isToday: true,
                );
              },
              
              // 비활성 날짜
              disabledBuilder: (context, day, focusedDay) {
                return _buildDayCell(
                  context,
                  day,
                  isAvailable: false,
                  isSelected: false,
                  isToday: false,
                );
              },
              
              // 마커 빌더
              markerBuilder: (context, day, events) {
                if (events.isEmpty) return null;
                
                final hasConfirmed = events.contains('confirmed');
                final hasPending = events.contains('pending');
                
                return Positioned(
                  bottom: ResponsiveHelper.spacing(context, 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasConfirmed)
                        Container(
                          width: ResponsiveHelper.spacing(context, 6),
                          height: ResponsiveHelper.spacing(context, 6),
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                      if (hasConfirmed && hasPending)
                        SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                      if (hasPending)
                        Container(
                          width: ResponsiveHelper.spacing(context, 6),
                          height: ResponsiveHelper.spacing(context, 6),
                          decoration: const BoxDecoration(
                            color: AppColors.warning,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          
          // 범례
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            decoration: BoxDecoration(
              color: AppColors.grey50,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(context, AppColors.success, '확정'),
                SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                _buildLegendItem(context, AppColors.warning, '대기'),
                SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                _buildLegendItem(context, theme.primaryColor, '지원가능'),
              ],
            ),
          ),
          
          // ✅ 안내 메시지
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
            margin: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 12),
              0,
              ResponsiveHelper.spacing(context, 12),
              ResponsiveHelper.spacing(context, 12),
            ),
            decoration: BoxDecoration(
              color: AppColors.infoBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.infoLight),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: AppColors.infoDark,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    '같은 시간대에 여러 업무 지원 가능! \n확정 시 겹치는 지원은 자동 취소돼요.',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 날짜 셀 빌드

  /// 날짜 셀 빌드
  Widget _buildDayCell(
    BuildContext context,
    DateTime day, {
    required bool isAvailable,
    required bool isSelected,
    required bool isToday,
  }) {
    final theme = Theme.of(context);
    
    Color backgroundColor;
    Color textColor;
    BoxBorder? border;
    
    if (isSelected) {
      backgroundColor = theme.primaryColor;
      textColor = Colors.white;
    } else if (isToday && isAvailable) {
      backgroundColor = theme.primaryColor.withOpacity(0.1);
      textColor = theme.primaryColor;
      border = Border.all(color: theme.primaryColor, width: 1.5);
    } else if (isAvailable) {
      backgroundColor = theme.primaryColor.withOpacity(0.05);
      textColor = AppColors.grey800;
    } else {
      backgroundColor = Colors.transparent;
      textColor = AppColors.grey300;
    }
    
    return Container(
      margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 2)),
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: border,
      ),
      child: Center(
        child: Text(
          '${day.day}',
          style: ResponsiveHelper.bodyStyle(context, color: textColor).copyWith(
            fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// 내 확정 스케줄 경고
  Widget _buildMyScheduleWarning(BuildContext context, ThemeData theme) {
    final dateFormat = DateFormat('M/d (E)', 'ko_KR');
    final targetDate = _isGroupTO ? _selectedDate : widget.mainTO.date;
    
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.spacing(context, 10),
        ),
        border: Border.all(color: AppColors.warningLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.warningDark,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '${dateFormat.format(targetDate!)} 확정된 근무가 있습니다',
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.warningDark).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          // 확정된 스케줄 목록
          ..._myConfirmedSchedules.map((schedule) => Padding(
            padding: EdgeInsets.only(
              left: ResponsiveHelper.spacing(context, 26),
              bottom: ResponsiveHelper.spacing(context, 4),
            ),
            child: Row(
              children: [
                Container(
                  width: ResponsiveHelper.spacing(context, 6),
                  height: ResponsiveHelper.spacing(context, 6),
                  decoration: const BoxDecoration(
                    color: AppColors.warningDark,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    '${schedule.businessName} ${schedule.startTime}~${schedule.endTime}',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark),
                  ),
                ),
              ],
            ),
          )),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Padding(
            padding: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 26)),
            child: Text(
              '시간이 겹치는 업무는 지원할 수 없습니다',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
            ),
          ),
        ],
      ),
    );
  }

  /// 날짜별 업무 섹션
  Widget _buildDateWorkSection(
    BuildContext context,
    ThemeData theme,
    DateTime date,
  ) {
    final dateFormat = DateFormat('M/d (E)', 'ko_KR');
    final dateKey = DateTime(date.year, date.month, date.day);
    final to = widget.groupTOsByDate![dateKey];
    final workDetails = widget.groupWorkDetailsByDate?[dateKey] ?? [];

    if (to == null || workDetails.isEmpty) {
      return Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
        child: Center(
          child: Text(
            '해당 날짜에 등록된 업무가 없습니다',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 날짜 헤더
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 10),
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
                style: ResponsiveHelper.bodyStyle(context, color: theme.primaryColor).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${workDetails.length}개 업무',
                style: ResponsiveHelper.smallStyle(context, color: theme.primaryColor),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              // ✅ 상세보기 버튼 (텍스트 포함)
              InkWell(
                onTap: () => _goToJobPosting(to!, workDetails),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 4),
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: ResponsiveHelper.iconSize(context, 14),
                        color: theme.primaryColor,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                      Text(
                        '상세',
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: theme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        
        // 업무 목록
        ...workDetails.map((work) {
          final workKey = _makeWorkKey(work.workType, work.startTime, work.endTime);
          final application = _applicationsByDate[dateKey]?[workKey];
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
      ],
    );
  }

  Widget _buildEmptyDateSelection(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 32)),
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
              '캘린더에서 날짜를 선택하세요',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              '색이 있는 날짜만 지원 가능합니다',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
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
    final dateKey = DateTime(date.year, date.month, date.day);
    final apps = _applicationsByDate[dateKey];
    if (apps == null || apps.isEmpty) return false;
    
    return apps.values.any((app) => 
      app.status == 'PENDING' || app.status == 'CONFIRMED'
    );
  }

  List<WorkDetailModel> _getAppliedWorks(DateTime date, List<WorkDetailModel> workDetails) {
    final dateKey = DateTime(date.year, date.month, date.day);
    final apps = _applicationsByDate[dateKey];
    if (apps == null) return [];
    
    return workDetails.where((work) {
      final workKey = _makeWorkKey(work.workType, work.startTime, work.endTime);
      final app = apps[workKey];
      return app != null && app.status == 'PENDING';
    }).toList();
  }

  List<WorkDetailModel> _getConfirmedWorks(DateTime date, List<WorkDetailModel> workDetails) {
    final dateKey = DateTime(date.year, date.month, date.day);
    final apps = _applicationsByDate[dateKey];
    if (apps == null) return [];
    
    return workDetails.where((work) {
      final workKey = _makeWorkKey(work.workType, work.startTime, work.endTime);
      final app = apps[workKey];
      return app != null && app.status == 'CONFIRMED';
    }).toList();
  }

  String _dateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  String _makeWorkKey(String workType, String startTime, String endTime) {
    return '${workType}_${startTime}_$endTime';
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
    // AUTO_CANCELED 상태면 이미 취소된 것
    if (application.status == 'AUTO_CANCELED') {
      ToastHelper.showInfo('이미 자동취소된 지원입니다 (시간 충돌)');
      return;
    }
    
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
      
      final targetDate = date ?? application.workDate;
      
      // ✅ 전체 상태 새로고침 (지원상태 + 확정스케줄 + 충돌정보)
      await _refreshApplicationStatus(targetDate, application.selectedWorkType);
      await _loadMyConfirmedSchedules(targetDate);
      await _loadConflictsForDate(targetDate);
      
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
      final dateKey = DateTime(date.year, date.month, date.day);
      
      if (_isGroupTO) {
        to = widget.groupTOsByDate?[dateKey];
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
          _applicationsByDate[dateKey] = {
            for (final app in applications)
              _makeWorkKey(app.selectedWorkType, app.startTime, app.endTime): app
          };
        });
      }
    } catch (e) {
      print('❌ 상태 새로고침 실패: $e');
    }
  }
  /// 상세보기 화면 이동
  void _goToJobPosting(TOModel to, List<WorkDetailModel> workDetails) {
    Navigator.pop(context); // 다이얼로그 닫기
    
    NavigationHelper.push(
      context,
      destination: JobPostingScreen(
        to: to,
        workDetails: workDetails,
      ),
    );
  }
}