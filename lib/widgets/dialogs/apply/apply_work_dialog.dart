// lib/widgets/dialogs/apply/apply_work_dialog.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
import 'apply_confirm_dialog.dart';
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

  // 충돌 정보 캐시: Map<날짜키, Map<workDetailId, ConflictInfo>>
  final Map<String, Map<String, ConflictInfo>> _conflictCache = {};
  
  // ✅ 장기공고용: 확정된 근무가 있는 날짜 Set
  Set<DateTime> _confirmedDatesInRange = {};
  Map<DateTime, ApplicationModel> _conflictInfoByDate = {};  // 날짜별 충돌 스케줄
  DateTime? _firstSelectableDate;  // 첫 선택 가능 날짜

  // 로딩 중인 업무 ID 목록
  final Set<String> _loadingWorkIds = {};

  // 내 확정 스케줄 (해당 날짜)
  List<ApplicationModel> _myConfirmedSchedules = [];

  // ✅ 이미 알림 표시한 날짜 (중복 표시 방지)
  final Set<DateTime> _shownAlertDates = {};

  // ✅ 출퇴근 기록이 있는 application ID (장기공고용)
  final Set<String> _hasAttendanceIds = {};
  // ✅ 장기공고 희망 시작일
  DateTime? _desiredStartDate;

  // ═══════════════════════════════════════════════════════════
  // Getter
  // ═══════════════════════════════════════════════════════════
  
  bool get _isGroupTO => 
      widget.groupTOsByDate != null && widget.groupTOsByDate!.isNotEmpty;

  bool get _isLongTerm => widget.mainTO.isLongTerm;
  
  // 🔥 이미 지원 완료 상태인지 체크
  bool get _hasActiveApplication {
    final dateKey = DateTime(widget.mainTO.date.year, widget.mainTO.date.month, widget.mainTO.date.day);
    final apps = _applicationsByDate[dateKey];
    if (apps == null) return false;
    return apps.values.any((app) => app.status == 'PENDING' || app.status == 'CONFIRMED');
  }
  
  // 🔥 지원된 희망시작일 가져오기
  DateTime? get _appliedDesiredStartDate {
    final dateKey = DateTime(widget.mainTO.date.year, widget.mainTO.date.month, widget.mainTO.date.day);
    final apps = _applicationsByDate[dateKey];
    if (apps == null) return null;
    final activeApp = apps.values.cast<ApplicationModel?>().firstWhere(
      (app) => app?.status == 'PENDING' || app?.status == 'CONFIRMED',
      orElse: () => null,
    );
    return activeApp?.desiredStartDate ?? activeApp?.workDate;
  }

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

    // ✅ 장기공고: 희망 시작일 기본값 = null (사용자가 직접 선택해야 함)
    // 🔥 기본값 설정 제거 - 사용자가 캘린더에서 선택 가능한 날짜를 직접 선택해야 함
    if (_isLongTerm) {
      _desiredStartDate = null;  // 사용자가 선택해야 함
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
    } else if (!_isLongTerm) {
      // ✅ 단일 단기공고: 날짜 자동 선택 (하나뿐이니까)
      _selectedDate = widget.mainTO.date;
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
        
        // ✅ 장기공고: 전체 기간 내 확정 날짜 로드
        if (_isLongTerm) {
          await _loadConfirmedDatesInRange();
        }
      }
    } catch (e) {
      print('❌ 초기 데이터 로드 실패: $e');
     } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        
        // ✅ 초기 로드 완료 후 알림 표시 (UI 빌드 완료 후)
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _showInitialAlert();
          }
        });
      }
    }
  }

  /// ✅ 초기 알림 표시 (TO 타입별 분기)
  Future<void> _showInitialAlert() async {
    if (_isGroupTO && _selectedDate != null) {
      // 그룹 TO: 선택된 날짜 알림
      await _checkAndShowDateAlert(_selectedDate!);
    } else if (_isLongTerm) {
      // 장기공고: 충돌 날짜 알림
      await _checkAndShowLongTermAlert();
    } else {
      // 단일 단기공고: 메인 날짜 알림
      await _checkAndShowSingleTOAlert();
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

      // 🔥 FIX: 장기공고는 TO 시작일을 고정 키로 사용 (desiredStartDate와 무관하게)
      final dateKey = _isLongTerm 
          ? DateTime(widget.mainTO.date.year, widget.mainTO.date.month, widget.mainTO.date.day)
          : DateTime(date.year, date.month, date.day);
      // 🔥 퇴사/해지 완료된 장기공고 필터링
      final activeApplications = applications.where((app) {
        if (app.isLongTermApplication) {
          // ✅ PENDING/CONFIRMED 상태면 무조건 활성 (재지원 케이스 포함)
          if (app.status == 'PENDING' || app.status == 'CONFIRMED') {
            return true;
          }
          if (app.resignStatus == 'APPROVED' || app.resignStatus == 'AUTO_APPROVED' ||
              app.terminationStatus == 'APPROVED' || app.terminationStatus == 'AUTO_APPROVED') {
            return false;
          }
        }
        return true;
      }).toList();
      
      _applicationsByDate[dateKey] = {
        for (final app in activeApplications)
          _makeWorkKey(app.selectedWorkType, app.startTime, app.endTime): app
      };
      
      // 🔍 디버그: 저장된 workKey 확인
      print('🔍 [_loadDateApplications] dateKey: $dateKey');
      print('   activeApplications: ${activeApplications.length}개');
      for (final app in activeApplications) {
        final wk = _makeWorkKey(app.selectedWorkType, app.startTime, app.endTime);
        print('   workKey: "$wk" → status: ${app.status}');
      }
      
      // ✅ 장기공고: 확정된 application의 출퇴근 기록 확인
      if (_isLongTerm) {
        for (final app in applications.where((a) => a.status == 'CONFIRMED')) {
          final hasRecord = await _firestoreService.hasAttendanceRecord(app.id);
          if (hasRecord) {
            _hasAttendanceIds.add(app.id);
          }
        }
        
        // activeApplications = 필터링 후
        final activeApp = activeApplications.where((a) => 
          a.status == 'PENDING' || a.status == 'CONFIRMED'
        ).firstOrNull;
        
        if (activeApp != null && mounted) {
          setState(() {
            // desiredStartDate가 있으면 사용, 없으면 workDate 사용 (기존 데이터 호환)
            _desiredStartDate = activeApp.desiredStartDate ?? activeApp.workDate;
          });
        }
      }
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
  /// ✅ 장기공고용: 전체 기간 내 확정된 근무가 있는 날짜 조회 (성능 최적화)
  Future<void> _loadConfirmedDatesInRange() async {
    if (_currentUserId == null) return;
    
    // 🔥 성능 최적화: 이미 지원한 상태면 충돌 체크 스킵
    if (_hasActiveApplication) {
      print('🔍 [장기충돌] 이미 지원 완료 - 충돌 체크 스킵');
      return;
    }
    
    final startDate = widget.mainTO.date;
    final endDate = widget.mainTO.endDate ?? widget.mainTO.date;
    final workDays = widget.mainTO.workDays ?? [];
    final workStartTime = widget.workDetails.isNotEmpty ? widget.workDetails.first.startTime : '';
    final workEndTime = widget.workDetails.isNotEmpty ? widget.workDetails.first.endTime : '';
    
    try {
      // ✅ 1. 사용자의 모든 CONFIRMED 지원서 한 번에 조회
      final snapshot = await FirebaseFirestore.instance
          .collection('applications')
          .where('uid', isEqualTo: _currentUserId)
          .where('status', isEqualTo: 'CONFIRMED')
          .get();
      
      final allConfirmed = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
      
      print('📅 [장기충돌] 전체 CONFIRMED: ${allConfirmed.length}개');
      
      final confirmedDates = <DateTime>{};
      final conflictInfoByDate = <DateTime, ApplicationModel>{};
      
      // ✅ 2. 기간 내 모든 근무 요일에 대해 충돌 체크 (메모리에서!)
      var currentDate = startDate;
      while (!currentDate.isAfter(endDate)) {
        final dayOfWeek = ['월', '화', '수', '목', '금', '토', '일'][currentDate.weekday - 1];
        
        // 근무 요일인 경우만 체크
        if (workDays.isEmpty || workDays.contains(dayOfWeek)) {
          // 해당 날짜에 근무하는 확정 스케줄 찾기
          for (final app in allConfirmed) {
            if (_isWorkingOnDate(app, currentDate)) {
              // 시간 충돌 체크
              if (_hasTimeOverlap(workStartTime, workEndTime, app.startTime, app.endTime)) {
                final dateKey = DateTime(currentDate.year, currentDate.month, currentDate.day);
                confirmedDates.add(dateKey);
                conflictInfoByDate[dateKey] = app;
                break;
              }
            }
          }
        }
        
        currentDate = currentDate.add(const Duration(days: 1));
      }
      
      // ✅ 3. 첫 선택 가능 날짜 계산 (충돌 이후 첫 근무일)
      DateTime? firstSelectable;
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      final selectableStart = todayOnly.isAfter(startDate) ? todayOnly : startDate;
      
      var checkDate = selectableStart;
      while (!checkDate.isAfter(endDate)) {
        final dayOfWeek = ['월', '화', '수', '목', '금', '토', '일'][checkDate.weekday - 1];
        final dateKey = DateTime(checkDate.year, checkDate.month, checkDate.day);
        
        // 근무 요일이고 충돌 없으면 → 첫 선택 가능일!
        if ((workDays.isEmpty || workDays.contains(dayOfWeek)) && !confirmedDates.contains(dateKey)) {
          // 이 날짜부터 끝까지 충돌 없는지 확인
          bool hasConflictAfter = false;
          var futureDate = checkDate;
          while (!futureDate.isAfter(endDate)) {
            final futureDayOfWeek = ['월', '화', '수', '목', '금', '토', '일'][futureDate.weekday - 1];
            final futureDateKey = DateTime(futureDate.year, futureDate.month, futureDate.day);
            if ((workDays.isEmpty || workDays.contains(futureDayOfWeek)) && confirmedDates.contains(futureDateKey)) {
              hasConflictAfter = true;
              break;
            }
            futureDate = futureDate.add(const Duration(days: 1));
          }
          
          if (!hasConflictAfter) {
            firstSelectable = checkDate;
            break;
          }
        }
        
        checkDate = checkDate.add(const Duration(days: 1));
      }
      
      if (mounted) {
        setState(() {
          _confirmedDatesInRange = confirmedDates;
          _conflictInfoByDate = conflictInfoByDate;
          _firstSelectableDate = firstSelectable;
        });
      }
      
      print('✅ [장기충돌] 충돌 날짜: ${confirmedDates.length}개, 첫 선택 가능: ${firstSelectable?.toString() ?? "없음"}');
    } catch (e) {
      print('❌ 확정 날짜 로드 실패: $e');
    }
  }
  
  /// 특정 날짜에 근무하는지 확인 (장기공고 포함)
  bool _isWorkingOnDate(ApplicationModel app, DateTime targetDate) {
    final isLongTerm = app.workDays != null && app.workDays!.isNotEmpty;
    
    // 단기: workDate만 비교
    if (!isLongTerm) {
      return app.workDate.year == targetDate.year &&
             app.workDate.month == targetDate.month &&
             app.workDate.day == targetDate.day;
    }
    
    // 장기: 기간 + 요일 체크
    // 🔥 퇴사일이 있으면 그 날짜까지만
    final endDate = app.actualResignDate ?? app.workEndDate;
    if (endDate == null) return false;
    
    // 🔥 시작일 계산: 확정일이 공고 시작일보다 이후면 확정일 기준
    DateTime effectiveStartDate = app.workDate;
    if (app.confirmedAt != null) {
      final confirmedDate = DateTime(
        app.confirmedAt!.year,
        app.confirmedAt!.month,
        app.confirmedAt!.day,
      );
      if (confirmedDate.isAfter(app.workDate)) {
        effectiveStartDate = confirmedDate;
      }
    }
    
    final targetOnly = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final startOnly = DateTime(effectiveStartDate.year, effectiveStartDate.month, effectiveStartDate.day);
    final endOnly = DateTime(endDate.year, endDate.month, endDate.day);
    
    // 기간 체크
    if (targetOnly.isBefore(startOnly) || targetOnly.isAfter(endOnly)) return false;
    
    // 🔥 휴무일 체크 - 휴무일이면 근무 안함
    if (app.leaveDates != null && app.leaveDates!.isNotEmpty) {
      final isLeaveDay = app.leaveDates!.any((leaveDate) =>
          leaveDate.year == targetOnly.year &&
          leaveDate.month == targetOnly.month &&
          leaveDate.day == targetOnly.day);
      if (isLeaveDay) return false;
    }
    
    // 요일 체크
    final dayOfWeek = ['월', '화', '수', '목', '금', '토', '일'][targetDate.weekday - 1];
    return app.workDays!.contains(dayOfWeek);
  }
  
  /// 시간 겹침 체크 헬퍼
  bool _hasTimeOverlap(String start1, String end1, String start2, String end2) {
    if (start1.isEmpty || end1.isEmpty || start2.isEmpty || end2.isEmpty) return false;
    
    int toMinutes(String time) {
      final parts = time.split(':');
      if (parts.length < 2) return 0;
      return int.parse(parts[0]) * 60 + int.parse(parts[1]);
    }
    
    final s1 = toMinutes(start1);
    final e1 = toMinutes(end1);
    final s2 = toMinutes(start2);
    final e2 = toMinutes(end2);
    
    return !(e1 <= s2 || e2 <= s1);
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
          // ✅ 캘린더 (단일 단기 / 장기 모두 표시)
          if (_isLongTerm) ...[
            _buildLongTermCalendarSection(context, theme),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ] else ...[
            // ✅ 단일 단기: 기존 캘린더 재활용 (날짜 1개)
            _buildCalendarSection(context, theme, [widget.mainTO.date]),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ],
          
          // 내 확정 스케줄 경고 - 캘린더 아래로 (장기공고는 ConflictWarningBox에서 표시하므로 제외)
          if (_myConfirmedSchedules.isNotEmpty && !_isLongTerm)
            _buildMyScheduleWarning(context, theme),
          
          // 업무 선택 섹션 + 상세보기 버튼
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionTitle(context, '업무 선택'),
              // ✅ 상세보기 버튼 추가
              InkWell(
                onTap: () => _goToJobPosting(widget.mainTO, widget.workDetails),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 10),
                    vertical: ResponsiveHelper.spacing(context, 6),
                  ),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
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
                        '상세보기',
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
          
          // ✅ 장기공고 + 출퇴근 기록 있으면 안내
          if (_isLongTerm && _hasAttendanceIds.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
              decoration: BoxDecoration(
                color: AppColors.infoBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.infoLight),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: ResponsiveHelper.iconSize(context, 16),
                    color: AppColors.infoDark,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      '출퇴근 기록이 있어 단순 취소가 불가합니다.\n퇴사를 원하시면 내 스케줄 > 고정근무 관리를 이용하세요.',
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          ...widget.workDetails.map((work) {
            final workKey = _makeWorkKey(work.workType, work.startTime, work.endTime);
            // 🔥 dateKey를 동일한 방식으로 생성
            final dateKey = DateTime(widget.mainTO.date.year, widget.mainTO.date.month, widget.mainTO.date.day);
            final application = _applicationsByDate[dateKey]?[workKey];
            
            // ✅ 장기공고: 상단에 충돌 경고 박스가 있으므로 개별 카드 충돌 메시지 숨김
            // ✅ 희망시작일 미선택 + 충돌 날짜 있으면 지원 불가
            final hasConflictAndNoDate = _confirmedDatesInRange.isNotEmpty && _desiredStartDate == null;
            final conflictInfo = hasConflictAndNoDate
                ? ConflictInfo(
                    level: ConflictLevel.blocked,
                    message: '희망 시작일을 먼저 선택해주세요',
                  )
                : ConflictInfo.ok;  // 장기공고는 개별 충돌 메시지 숨김
            
            // ✅ 장기공고 + 출퇴근 기록 있으면 확정취소 불가
            final canCancelConfirm = application != null && 
                !(_isLongTerm && _hasAttendanceIds.contains(application.id));

            return WorkSelectionCard(
              workDetail: work,
              status: _getApplicationStatus(application),
              conflictInfo: conflictInfo,
              isLoading: _loadingWorkIds.contains(work.id),
              onApply: hasConflictAndNoDate ? null : () => _applyForWork(widget.mainTO, work),
              onCancelApplication: application != null
                  ? () => _cancelApplication(application)
                  : null,
              onCancelConfirm: canCancelConfirm
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
                // ✅ 장기공고 정보 추가
                isLongTerm: _isLongTerm,
                desiredStartDate: _desiredStartDate,
                endDate: widget.mainTO.endDate,
                workDays: widget.mainTO.workDays,
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
  /// ✅ 충돌 경고 박스
  Widget _buildConflictWarningBox(BuildContext context) {
    if (_conflictInfoByDate.isEmpty) return const SizedBox.shrink();
    
    // 🔥 FIX: 이미 지원한 상태면 경고 박스 숨김
    final dateKey = DateTime(widget.mainTO.date.year, widget.mainTO.date.month, widget.mainTO.date.day);
    final apps = _applicationsByDate[dateKey];
    if (apps != null && apps.values.any((app) => app.status == 'PENDING' || app.status == 'CONFIRMED')) {
      return const SizedBox.shrink();
    }
    
    // 첫 충돌 정보
    final sortedDates = _conflictInfoByDate.keys.toList()..sort();
    final firstConflictDate = sortedDates.first;
    final firstConflict = _conflictInfoByDate[firstConflictDate]!;
    
    // 선택 가능 날짜 텍스트
    String selectableText = '';
    if (_firstSelectableDate != null) {
      final dayOfWeek = ['월', '화', '수', '목', '금', '토', '일'][_firstSelectableDate!.weekday - 1];
      selectableText = '${_firstSelectableDate!.month}/${_firstSelectableDate!.day}($dayOfWeek)부터 선택 가능';
    } else {
      selectableText = '선택 가능한 날짜가 없습니다';
    }
    
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(8),
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
              Expanded(
                child: Text(
                  '기간 내 확정된 근무가 있습니다',
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.warningDark).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          // 충돌 날짜 목록 (최대 3개)
          ...sortedDates.take(3).map((date) {
            final app = _conflictInfoByDate[date]!;
            final dayOfWeek = ['월', '화', '수', '목', '금', '토', '일'][date.weekday - 1];
            return Padding(
              padding: EdgeInsets.only(
                left: ResponsiveHelper.spacing(context, 26),
                bottom: ResponsiveHelper.spacing(context, 4),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.warningDark,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      '${date.month}/${date.day}($dayOfWeek) ${app.startTime}~${app.endTime} (${app.businessName})',
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark),
                    ),
                  ),
                ],
              ),
            );
          }),
          
          if (sortedDates.length > 3)
            Padding(
              padding: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 26)),
              child: Text(
                '외 ${sortedDates.length - 3}개 날짜',
                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
              ),
            ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          // 선택 가능 날짜 안내
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: AppColors.info,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                Expanded(
                  child: Text(
                    selectableText,
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.info).copyWith(
                      fontWeight: FontWeight.w600,
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

  /// 장기공고용 캘린더 (희망 시작일 선택 가능)
  Widget _buildLongTermCalendarSection(BuildContext context, ThemeData theme) {
    final startDate = widget.mainTO.date;
    final endDate = widget.mainTO.endDate ?? widget.mainTO.date;
    final workDays = widget.mainTO.workDays ?? [];
    
    // 오늘 날짜
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    
    // 선택 가능한 시작일: 오늘 또는 공고시작일 중 늦은 날짜부터
    final selectableStartDate = todayOnly.isAfter(startDate) ? todayOnly : startDate;
    
    // 🔥 성능 최적화: 지원 상태 한 번만 계산
    final isApplied = _hasActiveApplication;
    final appliedStart = _appliedDesiredStartDate;
    
    return Column(
      children: [        
        Container(
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
          // 헤더: 희망 시작일 선택 안내
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
                  Icons.touch_app,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: AppColors.longTermDark,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    '희망 시작일을 선택하세요',
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
            focusedDay: _desiredStartDate ?? selectableStartDate,
            calendarFormat: CalendarFormat.month,
            
            // 컴팩트한 사이즈
            daysOfWeekHeight: ResponsiveHelper.spacing(context, 28),
            rowHeight: ResponsiveHelper.spacing(context, 40),
            
            // ✅ 선택된 날짜 (희망 시작일)
            selectedDayPredicate: (day) {
              if (_desiredStartDate == null) return false;
              return DateUtils.isSameDay(_desiredStartDate, day);
            },
            
            // ✅ 선택 가능한 날짜: 오늘 이후 + 근무기간 내 + 근무요일 + 확정 근무 없음
            enabledDayPredicate: (day) {
              // 🔥 FIX: 이미 지원한 상태면 모든 날짜 선택 불가
              if (_hasActiveApplication) return false;
              
              // 과거 날짜 불가
              if (day.isBefore(selectableStartDate)) return false;
              // 종료일 이후 불가
              if (day.isAfter(endDate)) return false;
              // 근무 요일 체크
              if (workDays.isNotEmpty) {
                const dayNames = ['월', '화', '수', '목', '금', '토', '일'];
                final dayName = dayNames[day.weekday - 1];
                if (!workDays.contains(dayName)) return false;
              }
              
              // ✅ 이 날짜 선택 시, 이후 충돌 있으면 선택 불가
              final dayOnly = DateTime(day.year, day.month, day.day);
              for (final conflictDate in _confirmedDatesInRange) {
                if (!conflictDate.isBefore(dayOnly)) {
                  // dayOnly 이후에 충돌 날짜 있으면 선택 불가
                  return false;
                }
              }
              
              return true;
            },
            
            // ✅ 날짜 선택 시 희망 시작일 업데이트
            onDaySelected: (selectedDay, focusedDay) {
              // 🔥 FIX: 이미 지원한 상태면 선택 무시
              if (_hasActiveApplication) return;
              
              setState(() {
                _desiredStartDate = selectedDay;
              });
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
              weekendStyle: ResponsiveHelper.smallStyle(context, color: Colors.red),
            ),
            
            // 커스텀 빌더
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                return _buildLongTermDayCell(context, day, startDate, endDate, workDays, selectableStartDate, false, isApplied: isApplied, appliedStart: appliedStart);
              },
              outsideBuilder: (context, day, focusedDay) {
                return _buildLongTermDayCell(context, day, startDate, endDate, workDays, selectableStartDate, true, isApplied: isApplied, appliedStart: appliedStart);
              },
              todayBuilder: (context, day, focusedDay) {
                return _buildLongTermDayCell(context, day, startDate, endDate, workDays, selectableStartDate, false, isToday: true, isApplied: isApplied, appliedStart: appliedStart);
              },
              selectedBuilder: (context, day, focusedDay) {
                return _buildLongTermDayCell(context, day, startDate, endDate, workDays, selectableStartDate, false, isSelected: true, isApplied: isApplied, appliedStart: appliedStart);
              },
              disabledBuilder: (context, day, focusedDay) {
                return _buildLongTermDayCell(context, day, startDate, endDate, workDays, selectableStartDate, false, isApplied: isApplied, appliedStart: appliedStart);
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
                _buildLegendItem(context, AppColors.longTerm, '선택가능'),
              ],
            ),
          ),
          
          // ✅ 동적 안내 메시지
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
                // 일괄 지원 안내 (동적)
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
                        _desiredStartDate != null
                            ? '${DateFormat('M/d (E)', 'ko_KR').format(_desiredStartDate!)}부터 ${DateFormat('M/d', 'ko_KR').format(endDate)}까지 일괄 지원됩니다.\n${widget.mainTO.workDaysLabel}'
                            : '희망 시작일을 선택하면 해당일부터 종료일까지 일괄 지원됩니다.\n${widget.mainTO.workDaysLabel}',
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
        ),
        // ✅ 충돌 경고 메시지 (캘린더 아래)
        if (_conflictInfoByDate.isNotEmpty) 
          Padding(
            padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 12)),
            child: _buildConflictWarningBox(context),
          ),
      ],
      
    );
  }

  Widget _buildLongTermDayCell(
    BuildContext context,
    DateTime day,
    DateTime startDate,
    DateTime endDate,
    List<String> workDays,
    DateTime selectableStartDate,
    bool isOutside, {
    bool isToday = false,
    bool isSelected = false,
    // 🔥 성능 최적화: 파라미터로 전달
    bool isApplied = false,
    DateTime? appliedStart,
  }) {
    // 근무 기간 내인지 확인
    final isInRange = !day.isBefore(startDate) && !day.isAfter(endDate);
    
    // 🔥 지원 완료 상태 - 파라미터로 전달받음 (성능 최적화)
    // (isApplied, appliedStart는 파라미터로 받음)
    
    // 🔥 지원 완료 시: 희망시작일 ~ 종료일 범위 체크
    final dayOnly = DateTime(day.year, day.month, day.day);
    bool isInAppliedRange = false;
    if (isApplied && appliedStart != null) {
      final appliedStartOnly = DateTime(appliedStart.year, appliedStart.month, appliedStart.day);
      isInAppliedRange = !dayOnly.isBefore(appliedStartOnly) && !dayOnly.isAfter(endDate);
    }
    
    // 선택 가능한지 확인 (과거 아니고, 근무요일이면)
    // 🔥 지원 완료 시 선택 불가
    bool isSelectable = !isApplied && isInRange && !day.isBefore(selectableStartDate);
    
    // 근무 요일인지 확인
    bool isWorkDay = false;
    if (isInRange) {
      if (workDays.isEmpty) {
        isWorkDay = true;
      } else {
        const dayNames = ['월', '화', '수', '목', '금', '토', '일'];
        final dayName = dayNames[day.weekday - 1];
        isWorkDay = workDays.contains(dayName);
      }
    }
    
    // 선택 가능 여부 최종 결정
    isSelectable = isSelectable && isWorkDay;
    
    // ✅ 충돌로 인해 선택 불가 체크 (이 날짜 이후에 충돌 있으면 불가)
    if (isSelectable && _confirmedDatesInRange.isNotEmpty) {
      for (final conflictDate in _confirmedDatesInRange) {
        if (!conflictDate.isBefore(dayOnly)) {
          isSelectable = false;
          break;
        }
      }
    }
    
    // 배경색/텍스트색 결정
    Color bgColor;
    Color textColor;
    
    // 🔥 지원 완료 상태일 때 스타일
    if (isApplied && isInAppliedRange && isWorkDay) {
      // 지원된 근무 기간 (희망시작일 ~ 종료일)
      bgColor = AppColors.longTerm.withOpacity(0.5);
      textColor = AppColors.longTermDark;
    } else if (isApplied && isInAppliedRange) {
      // 지원된 기간 내 휴무일
      bgColor = AppColors.longTerm.withOpacity(0.15);
      textColor = AppColors.grey500;
    } else if (isSelected) {
      // 선택된 날짜 (희망 시작일)
      bgColor = AppColors.longTerm;
      textColor = Colors.white;
    } else if (isOutside) {
      bgColor = Colors.transparent;
      textColor = AppColors.grey300;
    } else if (isSelectable) {
      // 선택 가능한 날짜
      bgColor = AppColors.longTerm.withOpacity(0.3);
      textColor = AppColors.longTermDark;
    } else if (isInRange && isWorkDay) {
      // 근무일이지만 과거 (선택 불가)
      bgColor = AppColors.grey200;
      textColor = AppColors.grey400;
    } else if (isInRange) {
      // 휴무일
      bgColor = AppColors.grey100;
      textColor = AppColors.grey400;
    } else {
      bgColor = Colors.transparent;
      textColor = AppColors.grey400;
    }
    
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: isToday 
            ? Border.all(color: Theme.of(context).primaryColor, width: 2) 
            : isSelected 
                ? Border.all(color: AppColors.longTermDark, width: 2)
                : null,
      ),
      child: Center(
        child: Text(
          '${day.day}',
          style: ResponsiveHelper.smallStyle(context, color: textColor).copyWith(
            fontWeight: (isSelected || isToday) ? FontWeight.bold : FontWeight.normal,
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
            // 확정 근무 경고 (있으면) - 장기공고는 상단 ConflictWarningBox에서 이미 표시하므로 제외
          if (_myConfirmedSchedules.isNotEmpty && !_isLongTerm)
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
            
            // 활성화된 날짜 (등록된 날짜만 - 예약 포함)
            enabledDayPredicate: (day) {
              // 등록된 날짜인지 확인 (파라미터 사용)
              return availableDates.any((d) => DateUtils.isSameDay(d, day));
            },
            
            // 날짜 선택
            onDaySelected: (selectedDay, focusedDay) {
              // 등록된 날짜인지 확인 (파라미터 사용)
              final isAvailable = availableDates.any(
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
              
              // ✅ 상황별 알림 다이얼로그 표시
              _checkAndShowDateAlert(selectedDay);
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
                final isAvailable = availableDates.any(
                  (d) => DateUtils.isSameDay(d, day),
                );
                
                // ✅ 예약 공개 체크
                final dateKey = DateTime(day.year, day.month, day.day);
                final to = widget.groupTOsByDate?[dateKey];
                final isPending = to?.isPendingPublish ?? false;
                
                return _buildDayCell(
                  context,
                  day,
                  isAvailable: isAvailable,
                  isSelected: false,
                  isToday: false,
                  isPendingPublish: isPending,
                  publishAt: to?.publishAt,
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
                final isAvailable = availableDates.any(
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
    bool isPendingPublish = false,
    DateTime? publishAt,
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
    // ✅ 예약 중이면 주황색 배경 (동그란 모양)
    if (isPendingPublish && isAvailable) {
      return Container(
        margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 2)),
        decoration: BoxDecoration(
          color: AppColors.warningBg,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.warningLight),
        ),
        child: Center(
          child: Text(
            '${day.day}',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.warningDark).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
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

    // ✅ 예약 공개 체크
    final isPending = to.isPendingPublish;

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
                onTap: () => _goToJobPosting(to, workDetails),
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
                        '상세보기',
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
        
        // ✅ 예약 공개 대기 중이면 오픈 예정 메시지
        if (isPending) ...[
          _buildPendingPublishNotice(context, to),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        ],
        
        // 업무 목록 (예약 중이면 반투명)
        Opacity(
          opacity: isPending ? 0.4 : 1.0,
          child: Column(
            children: workDetails.map((work) {
              final workKey = _makeWorkKey(work.workType, work.startTime, work.endTime);
              final application = _applicationsByDate[dateKey]?[workKey];
              final conflictInfo = _conflictCache[_dateKey(date)]?[work.id] 
                  ?? ConflictInfo.ok;
              
              return WorkSelectionCard(
                workDetail: work,
                status: isPending ? WorkApplicationStatus.closed : _getApplicationStatus(application),
                conflictInfo: isPending 
                    ? const ConflictInfo(
                        level: ConflictLevel.blocked,
                        message: '예약',
                      )
                    : conflictInfo,
                isLoading: _loadingWorkIds.contains('${date.millisecondsSinceEpoch}_${work.id}'),
                onApply: isPending ? null : () => _applyForWork(to, work, date: date),
                onCancelApplication: application != null
                    ? () => _cancelApplication(application)
                    : null,
                onCancelConfirm: application != null
                    ? () => _cancelConfirm(application, work, date: date)
                    : null,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
  /// ✅ 예약 공개 대기 메시지
  Widget _buildPendingPublishNotice(BuildContext context, TOModel to) {
    final publishAt = to.publishAt;
    final displayText = publishAt != null 
        ? '${publishAt.month}/${publishAt.day} ${publishAt.hour.toString().padLeft(2, '0')}:${publishAt.minute.toString().padLeft(2, '0')}에 오픈됩니다'
        : '곧 오픈 예정입니다';
    
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warningLight),
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule,
            size: ResponsiveHelper.iconSize(context, 18),
            color: AppColors.warningDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Text(
              displayText,
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.warningDark).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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
    
    // 🔥 퇴사/해지 완료된 장기공고는 미지원 취급
    if (application.isLongTermApplication) {
      if (application.resignStatus == 'APPROVED' || application.resignStatus == 'AUTO_APPROVED' ||
          application.terminationStatus == 'APPROVED' || application.terminationStatus == 'AUTO_APPROVED') {
        return WorkApplicationStatus.notApplied;
      }
    }
    
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
    // 🔥 장기공고: 희망 시작일 유효성 검사
    if (_isLongTerm) {
      // 1. 희망 시작일이 선택되지 않은 경우
      if (_desiredStartDate == null) {
        ToastHelper.showWarning('희망 시작일을 선택해주세요');
        return;
      }
      
      // 2. 선택된 날짜가 선택 가능한 날짜인지 확인
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      final startDate = to.date;
      final endDate = to.endDate ?? to.date;
      final workDays = to.workDays ?? [];
      final selectableStartDate = todayOnly.isAfter(startDate) ? todayOnly : startDate;
      
      final selectedDayOnly = DateTime(_desiredStartDate!.year, _desiredStartDate!.month, _desiredStartDate!.day);
      
      // 과거 날짜인지
      if (selectedDayOnly.isBefore(selectableStartDate)) {
        ToastHelper.showWarning('선택한 날짜는 지원할 수 없습니다.\n캘린더에서 희망 시작일을 다시 선택해주세요.');
        return;
      }
      
      // 종료일 이후인지
      if (selectedDayOnly.isAfter(endDate)) {
        ToastHelper.showWarning('선택한 날짜가 근무 종료일 이후입니다.');
        return;
      }
      
      // 근무 요일인지
      if (workDays.isNotEmpty) {
        const dayNames = ['월', '화', '수', '목', '금', '토', '일'];
        final dayName = dayNames[selectedDayOnly.weekday - 1];
        if (!workDays.contains(dayName)) {
          ToastHelper.showWarning('선택한 날짜는 근무 요일이 아닙니다.');
          return;
        }
      }
      
      // 충돌 날짜인지 (이 날짜 이후에 확정 근무가 있으면 불가)
      for (final conflictDate in _confirmedDatesInRange) {
        if (!conflictDate.isBefore(selectedDayOnly)) {
          ToastHelper.showWarning('선택한 시작일 이후에 확정된 근무가 있습니다.\n다른 날짜를 선택해주세요.');
          return;
        }
      }
    }
    
    // ✅ 지원 확인 팝업
    final confirmed = await ApplyConfirmDialog.show(
      context: context,
      businessName: widget.businessName,
      work: work,
      isLongTerm: _isLongTerm,
      workDate: date ?? to.date,
      desiredStartDate: _isLongTerm ? _desiredStartDate : null,
      endDate: _isLongTerm ? to.endDate : null,
      workDays: _isLongTerm ? to.workDays : null,
    );
    
    if (!confirmed) return;  // 취소 시 종료
    
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
        desiredStartDate: _isLongTerm ? _desiredStartDate : null,
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

    // ✅ 로딩 키 통일 (applyForWork와 동일한 방식)
    final loadingKey = _makeWorkKey(
      application.selectedWorkType, 
      application.startTime, 
      application.endTime,
    );
    setState(() => _loadingWorkIds.add(loadingKey));

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
        // ✅ 로딩 키 통일
        final loadingKey = _makeWorkKey(
          application.selectedWorkType, 
          application.startTime, 
          application.endTime,
        );
        setState(() => _loadingWorkIds.remove(loadingKey));
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
          // ✅ PENDING, CONFIRMED만 유지 (CANCELED, REJECTED, AUTO_CANCELED 제외)
          final activeApps = applications.where((app) => 
            app.status == 'PENDING' || app.status == 'CONFIRMED'
          ).toList();
          
          _applicationsByDate[dateKey] = {
            for (final app in activeApps)
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
  // ═══════════════════════════════════════════════════════════
  // ✅ 날짜 선택 시 상황별 알림 다이얼로그
  // ═══════════════════════════════════════════════════════════

  /// 그룹 TO 날짜 선택 시 특이사항 체크 및 알림 표시
  Future<void> _checkAndShowDateAlert(DateTime selectedDay) async {
    final dateKey = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
    
    // 이미 알림 표시한 날짜면 스킵
    if (_shownAlertDates.contains(dateKey)) return;
    
    // 해당 날짜의 TO 정보
    final to = widget.groupTOsByDate?[dateKey];
    final workDetails = widget.groupWorkDetailsByDate?[dateKey] ?? [];
    
    // 1. 예약 대기 체크
    if (to?.isPendingPublish == true) {
      _shownAlertDates.add(dateKey);
      await _showScheduledAlert(selectedDay, to!);
      return;
    }
    
    // 2. 전체 마감 체크
    final allClosed = workDetails.isNotEmpty && 
        workDetails.every((w) => w.isClosed || w.isTimeExpired || w.isFull);
    if (allClosed) {
      _shownAlertDates.add(dateKey);
      await _showClosedAlert(selectedDay);
      return;
    }
    
    // 3. 확정 근무 있음 체크 (로드 후)
    await _loadMyConfirmedSchedules(selectedDay);
    if (_myConfirmedSchedules.isNotEmpty && !_shownAlertDates.contains(dateKey)) {
      _shownAlertDates.add(dateKey);
      await _showConfirmedScheduleAlert(selectedDay, _myConfirmedSchedules);
      return;
    }
    
    // 4. 부분 마감 체크
    final hasClosed = workDetails.any((w) => w.isClosed || w.isTimeExpired || w.isFull);
    final hasOpen = workDetails.any((w) => !w.isClosed && !w.isTimeExpired && !w.isFull);
    if (hasClosed && hasOpen) {
      _shownAlertDates.add(dateKey);
      await _showPartialClosedAlert(selectedDay);
      return;
    }
  }

  /// 장기공고 초기 알림 체크
  Future<void> _checkAndShowLongTermAlert() async {
    // 🔥 FIX: 이미 지원한 상태면 충돌 알림 표시 안 함
    final dateKey = DateTime(widget.mainTO.date.year, widget.mainTO.date.month, widget.mainTO.date.day);
    final apps = _applicationsByDate[dateKey];
    if (apps != null && apps.values.any((app) => app.status == 'PENDING' || app.status == 'CONFIRMED')) {
      print('🔍 [장기공고] 이미 지원 중 - 충돌 알림 스킵');
      return;  // 이미 지원했으면 알림 표시 안 함
    }
    
    // 1. 확정 근무로 인한 충돌 날짜가 있으면 알림
    if (_confirmedDatesInRange.isNotEmpty) {
      await _showLongTermConflictAlert();
      return;
    }
    
    // 2. 전체 마감 체크
    final workDetails = widget.workDetails;
    final allClosed = workDetails.isNotEmpty && 
        workDetails.every((w) => w.isClosed || w.isTimeExpired || w.isFull);
    if (allClosed) {
      await _showClosedAlert(widget.mainTO.date);
      return;
    }
    
    // 3. 부분 마감 체크
    final hasClosed = workDetails.any((w) => w.isClosed || w.isTimeExpired || w.isFull);
    final hasOpen = workDetails.any((w) => !w.isClosed && !w.isTimeExpired && !w.isFull);
    if (hasClosed && hasOpen) {
      await _showPartialClosedAlert(widget.mainTO.date);
      return;
    }
  }

  /// 단일 단기공고 초기 알림 체크
  Future<void> _checkAndShowSingleTOAlert() async {
    final workDate = widget.mainTO.date;
    final workDetails = widget.workDetails;
    
    // 1. 전체 마감 체크
    final allClosed = workDetails.isNotEmpty && 
        workDetails.every((w) => w.isClosed || w.isTimeExpired || w.isFull);
    if (allClosed) {
      await _showClosedAlert(workDate);
      return;
    }
    
    // 2. 확정 근무 있음 체크
    if (_myConfirmedSchedules.isNotEmpty) {
      await _showConfirmedScheduleAlert(workDate, _myConfirmedSchedules);
      return;
    }
    
    // 3. 부분 마감 체크
    final hasClosed = workDetails.any((w) => w.isClosed || w.isTimeExpired || w.isFull);
    final hasOpen = workDetails.any((w) => !w.isClosed && !w.isTimeExpired && !w.isFull);
    if (hasClosed && hasOpen) {
      await _showPartialClosedAlert(workDate);
      return;
    }
  }

  /// 예약 대기 알림
  Future<void> _showScheduledAlert(DateTime date, TOModel to) async {
    final dateStr = DateFormat('M/d (E)', 'ko_KR').format(date);
    final publishAt = to.publishAt;
    final publishStr = publishAt != null
        ? '${publishAt.month}/${publishAt.day} ${publishAt.hour.toString().padLeft(2, '0')}:${publishAt.minute.toString().padLeft(2, '0')}'
        : '예정된 시간';

    await _showAlertDialog(
      icon: Icons.schedule,
      iconColor: AppColors.info,
      bgColor: AppColors.infoBg,
      title: '$dateStr 안내',
      message: '이 날짜의 공고는 아직 오픈되지 않았습니다.',
      detail: '$publishStr에 오픈 예정입니다.',
    );
  }

  /// 전체 마감 알림
  Future<void> _showClosedAlert(DateTime date) async {
    final dateStr = DateFormat('M/d (E)', 'ko_KR').format(date);

    await _showAlertDialog(
      icon: Icons.lock,
      iconColor: AppColors.error,
      bgColor: AppColors.errorBg,
      title: '$dateStr 안내',
      message: '이 날짜의 모든 업무가 마감되었습니다.',
      detail: '다른 날짜를 선택해주세요.',
    );
  }

  /// 확정 근무 있음 알림
  Future<void> _showConfirmedScheduleAlert(
    DateTime date, 
    List<ApplicationModel> confirmedSchedules,
  ) async {
    final dateStr = DateFormat('M/d (E)', 'ko_KR').format(date);
    
    final scheduleInfo = confirmedSchedules.map((app) {
      return '${app.businessName} ${app.startTime}~${app.endTime}';
    }).join('\n');

    await _showAlertDialog(
      icon: Icons.event_busy,
      iconColor: AppColors.warning,
      bgColor: AppColors.warningBg,
      title: '$dateStr 안내',
      message: '이 날짜에 확정된 근무가 있습니다.',
      detail: scheduleInfo,
      subMessage: '시간이 겹치는 업무는 지원할 수 없습니다.',
    );
  }

  /// 부분 마감 알림
  Future<void> _showPartialClosedAlert(DateTime date) async {
    final dateStr = DateFormat('M/d (E)', 'ko_KR').format(date);

    await _showAlertDialog(
      icon: Icons.info_outline,
      iconColor: AppColors.warning,
      bgColor: AppColors.warningBg,
      title: '$dateStr 안내',
      message: '일부 업무가 마감되었습니다.',
      detail: '지원 가능한 업무를 확인해주세요.',
    );
  }

  /// 장기공고 충돌 날짜 알림
  Future<void> _showLongTermConflictAlert() async {
    final startDate = widget.mainTO.date;
    final endDate = widget.mainTO.endDate ?? widget.mainTO.date;
    
    final sortedConflicts = _confirmedDatesInRange.toList()..sort();
    final conflictDatesStr = sortedConflicts.take(3).map((d) {
      final dayOfWeek = ['월', '화', '수', '목', '금', '토', '일'][d.weekday - 1];
      final app = _conflictInfoByDate[d];
      final timeInfo = app != null ? ' ${app.startTime}~${app.endTime}' : '';
      return '${d.month}/${d.day}($dayOfWeek)$timeInfo';
    }).join('\n');
    
    final extraCount = sortedConflicts.length > 3 ? '\n외 ${sortedConflicts.length - 3}일' : '';

    await _showAlertDialog(
      icon: Icons.event_busy,
      iconColor: AppColors.warning,
      bgColor: AppColors.warningBg,
      title: '장기공고 안내',
      message: '근무 기간 내 확정된 일정이 있습니다.',
      detail: '$conflictDatesStr$extraCount',
      subMessage: '충돌 날짜 이전까지만 지원 가능합니다.\n희망 시작일을 선택해주세요.',
    );
  }

  /// 공통 알림 다이얼로그
  Future<void> _showAlertDialog({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String message,
    String? detail,
    String? subMessage,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 20)),
        ),
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(ResponsiveHelper.spacing(context, 20)),
                  topRight: Radius.circular(ResponsiveHelper.spacing(context, 20)),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: ResponsiveHelper.iconSize(context, 28), color: iconColor),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  Text(
                    title,
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      color: iconColor,
                    ),
                  ),
                ],
              ),
            ),
            
            // 내용
            Padding(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
              child: Column(
                children: [
                  Text(
                    message,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  if (detail != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                      decoration: BoxDecoration(
                        color: AppColors.grey100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        detail,
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  if (subMessage != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    Text(
                      subMessage,
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                backgroundColor: iconColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                '확인',
                style: ResponsiveHelper.bodyStyle(context, color: Colors.white).copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
        actionsPadding: EdgeInsets.fromLTRB(
          ResponsiveHelper.spacing(context, 20),
          0,
          ResponsiveHelper.spacing(context, 20),
          ResponsiveHelper.spacing(context, 16),
        ),
      ),
    );
  }

}