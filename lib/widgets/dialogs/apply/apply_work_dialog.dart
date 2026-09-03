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
import '../../../utils/format_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../theme/app_colors.dart';
import 'work_selection_card.dart';

import 'confirm_cancel_dialog.dart';
import 'apply_confirm_dialog.dart';
import '../../../utils/navigation_helper.dart';
import '../../../utils/network_checker.dart';
import '../../../screens/common/job_posting_screen.dart';
import '../../../screens/user/apply_prerequisites_screen.dart';
import '../../../services/tooltip_service.dart';
import '../../../services/analytics_service.dart';
import '../../../widgets/common/loading_widget.dart';
import '../styled_dialog.dart';

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

  /// 단일 슬롯 지원 시 슬롯 ID (flex TO)
  final String? slotId;

  /// 다중 슬롯 지원 시 날짜별 슬롯 ID 맵
  final Map<DateTime, String>? groupSlotIdsByDate;

  /// 사업장명
  final String businessName;

  /// 사전 로드된 내 전체 지원 목록 (없으면 다이얼로그 내에서 로드)
  final List<ApplicationModel>? myApplications;

  const ApplyWorkDialog({
    super.key,
    required this.mainTO,
    required this.workDetails,
    this.groupTOsByDate,
    this.groupWorkDetailsByDate,
    this.slotId,
    this.groupSlotIdsByDate,
    required this.businessName,
    this.myApplications,
  });

  /// 다이얼로그 표시 (간편 호출)
  static Future<ApplyDialogResult?> show({
    required BuildContext context,
    required TOModel to,
    required List<WorkDetailModel> workDetails,
    Map<DateTime, TOModel>? groupTOsByDate,
    Map<DateTime, List<WorkDetailModel>>? groupWorkDetailsByDate,
    String? slotId,
    Map<DateTime, String>? groupSlotIdsByDate,
    required String businessName,
    List<ApplicationModel>? myApplications,
  }) {
    return DialogHelper.showSheet<ApplyDialogResult>(
      context,
      isScrollControlled: true,
      builder: (context) => ApplyWorkDialog(
        mainTO: to,
        workDetails: workDetails,
        groupTOsByDate: groupTOsByDate,
        groupWorkDetailsByDate: groupWorkDetailsByDate,
        slotId: slotId,
        groupSlotIdsByDate: groupSlotIdsByDate,
        businessName: businessName,
        myApplications: myApplications,
      ),
    );
  }

  @override
  State<ApplyWorkDialog> createState() => _ApplyWorkDialogState();
}

class _ApplyWorkDialogState extends State<ApplyWorkDialog> {
  // ─── 포맷터 캐싱 (build 헬퍼마다 재생성 방지) ────────────────
  static final _mdeFmt  = DateFormat('M/d (E)', 'ko_KR');   // M월 d일 (요일) — 단기·스케줄
  static final _mdeKoFmt = DateFormat('M월 d일 (E)', 'ko_KR'); // M월 d일 (요일) — 상세
  static final _mdFmt   = DateFormat('M/d', 'ko_KR');       // M/d — 기간 표시
  static final _isoFmt  = DateFormat('yyyy-MM-dd');          // ISO 날짜 파싱용

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

  // 지원 요청이 처리 중인지 여부 (중복 동시 지원 방지)
  bool _isSubmitting = false;

  // 내 확정 스케줄 (해당 날짜)
  List<ApplicationModel> _myConfirmedSchedules = [];

  // ✅ 이미 알림 표시한 날짜 (중복 표시 방지)
  final Set<DateTime> _shownAlertDates = {};


  // ✅ 출퇴근 기록이 있는 application ID (장기공고용)
  final Set<String> _hasAttendanceIds = {};
  // ✅ 장기공고 희망 시작일
  DateTime? _desiredStartDate;
  // [BUG-1-FIX] 장기공고 캘린더 달 이동 스냅백 방지 — onPageChanged에서 업데이트
  DateTime? _longTermFocusedDay;

  // ═══════════════════════════════════════════════════════════
  // Getter
  // ═══════════════════════════════════════════════════════════
  
  bool get _isGroupTO =>
      widget.groupTOsByDate != null && widget.groupTOsByDate!.isNotEmpty;

  bool get _isLongTerm => widget.mainTO.isLongTerm;

  /// preset 기간이면 desiredStartDate 기준으로 종료일 계산, 아니면 rangeEnd 사용
  DateTime get _effectiveEndDate {
    final to = widget.mainTO;
    if (to.hasPresetPeriod && _desiredStartDate != null) {
      return to.computeContractEndDate(_desiredStartDate!);
    }
    return to.endDate ?? to.date;
  }

  /// 캘린더 표시 범위 최대일 (preset이면 1년 후, 아니면 rangeEnd) — initState에서 1회 계산
  late final DateTime _calendarLastDay;
  
  // 🔥 이미 지원 완료 상태인지 체크
  bool get _hasActiveApplication {
    final dateKey = FormatHelper.toKstDate(widget.mainTO.date);
    final apps = _applicationsByDate[dateKey];
    if (apps == null) return false;
    return apps.values.any((app) => app.status == AppStatus.pending || AppStatus.confirmedStatuses.contains(app.status));
  }

  // 🔥 지원된 희망시작일 가져오기
  DateTime? get _appliedDesiredStartDate {
    final dateKey = FormatHelper.toKstDate(widget.mainTO.date);
    final apps = _applicationsByDate[dateKey];
    if (apps == null) return null;
    final activeApp = apps.values.cast<ApplicationModel?>().firstWhere(
      (app) => app?.status == AppStatus.pending || AppStatus.confirmedStatuses.contains(app?.status),
      orElse: () => null,
    );
    return activeApp?.desiredStartDate ?? activeApp?.workDate;
  }


  // ═══════════════════════════════════════════════════════════
  // 라이프사이클
  // ═══════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    final to = widget.mainTO;
    // 신규 preset: workStartAvailableUntil / legacy preset: 1년 후 fallback / custom·flex: endDate(=rangeEnd)
    _calendarLastDay = to.hasPresetPeriod
        ? (to.workStartAvailableUntil ?? DateTime.now().add(const Duration(days: 365)))
        : to.endDate ?? to.date;
    // postFrameCallback: context 완전히 준비된 후 실행 (initState 내 직접 context 사용 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initializeData();
    });
  }

  Future<void> _initializeData() async {
    final userProvider = context.read<UserProvider>();
    _currentUserId = userProvider.currentUser?.uid;
    _userNoShowCount = userProvider.currentUser?.recentNoShowCount ?? 0;

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
      final todayOnly = FormatHelper.toKstDate(today);

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

        // 선택된 날짜의 충돌/스케줄 로드 — 두 쿼리는 독립적이므로 병렬 실행
        if (_selectedDate != null) {
          await Future.wait([
            _loadMyConfirmedSchedules(_selectedDate!),
            _loadConflictsForDate(_selectedDate!),
          ]);
        }
      } else {
        // 단일/장기 TO: 세 쿼리가 독립적이므로 병렬 실행
        await Future.wait([
          _loadDateApplications(widget.mainTO.date),
          _loadMyConfirmedSchedules(widget.mainTO.date),
          _loadConflictsForDate(widget.mainTO.date),
        ]);

        // ✅ 장기공고: _applicationsByDate 확인이 필요하므로 위 Future.wait 완료 후 실행
        if (_isLongTerm) {
          await _loadConfirmedDatesInRange();
        }
      }
    } catch (e) {
      debugPrint('❌ 초기 데이터 로드 실패: $e');
      if (mounted) ToastHelper.showError('데이터를 불러오는데 실패했습니다');
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
      final dateKey = DateTime.utc(date.year, date.month, date.day);
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
          ? FormatHelper.toKstDate(widget.mainTO.date)
          : DateTime.utc(date.year, date.month, date.day);

      // 날짜/슬롯 필터 + 활성 상태 필터를 통합 처리해 캐시에 저장
      _applicationsByDate[dateKey] = _buildActiveDateCache(applications, dateKey);

      // ✅ 장기공고: 확정된 application의 출퇴근 기록 확인
      // [CF-MIGRATED 2026-07-15] attendance list USER 직접 차단 → workerHasAttendanceRecord CF 경유
      if (_isLongTerm) {
        final confirmedApps = applications.where((a) => AppStatus.confirmedStatuses.contains(a.status)).toList();
        if (confirmedApps.isNotEmpty) {
          final checks = await Future.wait(
            confirmedApps.map((app) async {
              final hasRecord = await _firestoreService.workerHasAttendanceRecord(app.id);
              return (app.id, hasRecord);
            }),
          );
          for (final (id, hasRecord) in checks) {
            if (hasRecord) _hasAttendanceIds.add(id);
          }
        }

        final activeApp = _applicationsByDate[dateKey]?.values
            .where((a) => a.status == AppStatus.pending || AppStatus.confirmedStatuses.contains(a.status))
            .firstOrNull;

        if (activeApp != null && mounted) {
          setState(() {
            _desiredStartDate = activeApp.desiredStartDate ?? activeApp.workDate;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ 지원 상태 로드 실패: $e');
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
      debugPrint('❌ 확정 스케줄 로드 실패: $e');
    }
  }
  /// ✅ 장기공고용: 전체 기간 내 확정된 근무가 있는 날짜 조회 (성능 최적화)
  Future<void> _loadConfirmedDatesInRange() async {
    if (_currentUserId == null) return;
    
    // 🔥 성능 최적화: 이미 지원한 상태면 충돌 체크 스킵
    // _hasActiveApplication은 Provider 캐시 기반 스냅샷 — 다중 기기 동시 지원 시
    // 미세한 레이스 컨디션으로 최신 상태를 반영 못할 수 있음. 실제 중복 지원은 Firestore
    // 트랜잭션으로 차단되므로 여기서는 UI 중복 조회 방지 목적으로만 사용 (안전 설계)
    if (_hasActiveApplication) {
      debugPrint('🔍 [장기충돌] 이미 지원 완료 - 충돌 체크 스킵');
      return;
    }
    
    final startDate = widget.mainTO.date;
    final endDate = _calendarLastDay;
    final workDays = widget.mainTO.workDays;
    final workStartTime = widget.workDetails.isNotEmpty ? widget.workDetails.first.startTime : '';
    final workEndTime = widget.workDetails.isNotEmpty ? widget.workDetails.first.endTime : '';
    
    try {
      // [CF-MIGRATED 2026-07-15] applications list isSuperAdmin() only
      // → getMyConfirmedApplicationsForConflictCheck() CF 경유 (uid 서버 검증)
      final allConfirmed = await _firestoreService.getMyConfirmedApplicationsForConflictCheck();
      
      debugPrint('📅 [장기충돌] 전체 CONFIRMED: ${allConfirmed.length}개');
      
      final confirmedDates = <DateTime>{};
      final conflictInfoByDate = <DateTime, ApplicationModel>{};
      
      // ✅ 2. 기간 내 모든 근무 요일에 대해 충돌 체크 (메모리에서!)
      var currentDate = startDate;
      while (!currentDate.isAfter(endDate)) {
        final dayOfWeek = FormatHelper.weekday(currentDate);
        
        // 근무 요일인 경우만 체크
        if (workDays.isEmpty || workDays.contains(dayOfWeek)) {
          // 해당 날짜에 근무하는 확정 스케줄 찾기
          for (final app in allConfirmed) {
            if (app.isWorkingOnDate(currentDate)) {
              // 시간 충돌 체크
              if (ApplicationModel.hasTimeOverlap(workStartTime, workEndTime, app.startTime, app.endTime)) {
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
        final dayOfWeek = FormatHelper.weekday(checkDate);
        final dateKey = DateTime(checkDate.year, checkDate.month, checkDate.day);
        
        // 근무 요일이고 충돌 없으면 → 첫 선택 가능일!
        if ((workDays.isEmpty || workDays.contains(dayOfWeek)) && !confirmedDates.contains(dateKey)) {
          // 이 날짜부터 끝까지 충돌 없는지 확인
          bool hasConflictAfter = false;
          var futureDate = checkDate;
          while (!futureDate.isAfter(endDate)) {
            final futureDayOfWeek = FormatHelper.weekday(futureDate);
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
      
      debugPrint('✅ [장기충돌] 충돌 날짜: ${confirmedDates.length}개, 첫 선택 가능: ${firstSelectable?.toString() ?? "없음"}');
    } catch (e) {
      debugPrint('❌ 확정 날짜 로드 실패: $e');
    }
  }
  
/// 특정 날짜의 충돌 정보 로드
  Future<void> _loadConflictsForDate(DateTime date) async {
    if (_currentUserId == null) return;

    List<WorkDetailModel> workDetails;
    if (_isGroupTO) {
      final dateKey = DateTime.utc(date.year, date.month, date.day);
      workDetails = widget.groupWorkDetailsByDate?[dateKey] ?? [];
    } else {
      workDetails = widget.workDetails;
    }

    if (workDetails.isEmpty) return;

    try {
      final conflicts = await _conflictService.checkConflictsForWorkDetails(
        workDate: date,
        workDetails: workDetails,
      );

      if (mounted) {
        setState(() => _conflictCache[_dateKey(date)] = conflicts);
      }
    } catch (e) {
      debugPrint('❌ 충돌 정보 로드 실패: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // UI 빌드
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    
    // 다이얼로그 높이 계산
    final dialogHeight = mediaQuery.size.height * AppDialogSize.maxHeightRatio;

    // ⭐ PopScope 추가: 외부 탭으로 닫아도 변경 여부 반환
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pop(context, ApplyDialogResult(hasChanges: _hasChanges));
        }
      },
      child: Container(
        constraints: BoxConstraints(maxHeight: dialogHeight),
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
          const Divider(height: 1, color: AppColors.divider),
          
          // 내용
          Expanded(
            child: _isLoading
                ? const LoadingWidget()
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
    final dateFormat = _mdeFmt;

    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목 + 공고명
          Text(
            '지원하기',
            style: ResponsiveHelper.titleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 3)),
          Text(
            widget.mainTO.title,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: theme.primaryColor,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 10)),

          // 사업장 & 날짜 정보
          Row(
            children: [
              Icon(
                Icons.business,
                size: ResponsiveHelper.iconSize(context, 15),
                color: AppColors.grey500,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Expanded(
                child: Text(
                  widget.businessName,
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              if (_isGroupTO || _isLongTerm) ...[
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Icon(
                  Icons.calendar_today,
                  size: ResponsiveHelper.iconSize(context, 15),
                  color: AppColors.grey500,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                Flexible(
                  child: Text(
                    _isGroupTO
                        ? () { final sortedDates = widget.groupTOsByDate!.keys.toList()..sort(); return '${dateFormat.format(sortedDates.first)} ~ ${dateFormat.format(sortedDates.last)} (${widget.groupTOsByDate!.length}일)'; }()
                        : widget.mainTO.hasPresetPeriod
                            ? widget.mainTO.contractPeriodLabel
                            : '${dateFormat.format(widget.mainTO.date)} ~ ${dateFormat.format(widget.mainTO.endDate ?? widget.mainTO.date)}',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
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
          // 캘린더(장기) / 날짜 카드(단기)
          if (_isLongTerm) ...[
            _buildLongTermCalendarSection(context, theme),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ] else ...[
            _buildSingleDateInfo(context, theme),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ],

          // 내 확정 스케줄 경고 - 캘린더 아래로 (장기공고는 ConflictWarningBox에서 표시하므로 제외)
          if (_myConfirmedSchedules.isNotEmpty && !_isLongTerm)
            _buildMyScheduleWarning(context, theme),

          // 업무 선택 섹션 + 상세보기 버튼
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: _buildSectionTitle(context, '업무 선택')),
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
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.primaryColor.withValues(alpha: 0.3)),
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
              slotDate: widget.mainTO.date,
              isLongTerm: _isLongTerm,
              onApply: (hasConflictAndNoDate || _isSubmitting) ? null : () => _applyForWork(widget.mainTO, work),
              onCancelApplication: application != null
                  ? () => _cancelApplication(application)
                  : null,
              onCancelConfirm: canCancelConfirm
                  ? () => _cancelConfirm(application, work)
                  : null,
            );
          }),
          
        ],
      ),
    );
  }
  // ═══════════════════════════════════════════════════════════
  // 단기 TO 날짜 정보 카드 (캘린더 대체)
  // ═══════════════════════════════════════════════════════════

  Widget _buildSingleDateInfo(BuildContext context, ThemeData theme) {
    final to = widget.mainTO;
    final dateFormat = _mdeKoFmt;

    // 모든 업무 시간이 동일하면 시간 표시, 다르면 업무 수 표시
    String timeText;
    if (widget.workDetails.isEmpty) {
      timeText = '';
    } else if (widget.workDetails.length == 1 ||
        widget.workDetails.every((w) =>
            w.startTime == widget.workDetails.first.startTime &&
            w.endTime == widget.workDetails.first.endTime)) {
      timeText = widget.workDetails.first.timeRange;
    } else {
      timeText = '${widget.workDetails.length}개 업무 (시간 상이)';
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 14),
      ),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: ResponsiveHelper.spacing(context, 44),
            height: ResponsiveHelper.spacing(context, 44),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.event,
              size: ResponsiveHelper.iconSize(context, 24),
              color: theme.primaryColor,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '근무 날짜',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey500, fontWeight: FontWeight.w500),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                Text(
                  dateFormat.format(to.date),
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.grey800,
                  ),
                ),
                if (timeText.isNotEmpty) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: ResponsiveHelper.iconSize(context, 13),
                          color: AppColors.grey500),
                      SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                      Text(timeText,
                          style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.grey600)),
                    ],
                  ),
                ],
              ],
            ),
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
    if (apps != null && apps.values.any((app) => app.status == AppStatus.pending || AppStatus.confirmedStatuses.contains(app.status))) {
      return const SizedBox.shrink();
    }
    
    final sortedDates = _conflictInfoByDate.keys.toList()..sort();
    // 선택 가능 날짜 텍스트
    String selectableText = '';
    if (_firstSelectableDate != null) {
      final dayOfWeek = FormatHelper.weekday(_firstSelectableDate!);
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
            // sortedDates = _conflictInfoByDate.keys — 모든 date가 맵에 존재 보장, ! 안전
            final app = _conflictInfoByDate[date]!;
            final dayOfWeek = FormatHelper.weekday(date);
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
    final endDate = _calendarLastDay;
    final workDays = widget.mainTO.workDays;
    
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
        border: Border.all(color: AppColors.infoLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
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
              color: AppColors.infoBg,
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
                  color: AppColors.infoDark,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    '희망 시작일을 선택하세요',
                    style: ResponsiveHelper.bodyStyle(context, color: AppColors.infoDark).copyWith(
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
            focusedDay: _longTermFocusedDay ?? _desiredStartDate ?? selectableStartDate,
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
                if (!workDays.contains(FormatHelper.weekday(day))) return false;
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
                _longTermFocusedDay = selectedDay;
              });
            },

            // [BUG-1-FIX] onPageChanged에서 _longTermFocusedDay 업데이트 — 누락 시 setState 후 원래 달로 스냅백
            onPageChanged: (focusedDay) {
              setState(() { _longTermFocusedDay = focusedDay; });
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
                _buildLegendItem(context, AppColors.warning, '대기'),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                _buildLegendItem(context, AppColors.infoBg, '선택가능'),
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
                            ? '${_mdeFmt.format(_desiredStartDate!)}부터 ${_mdFmt.format(_effectiveEndDate)}까지 일괄 지원됩니다.\n${widget.mainTO.workDaysLabel}'
                            : '희망 시작일을 선택하면 해당일부터 ${widget.mainTO.hasPresetPeriod ? widget.mainTO.contractPeriodLabel : "종료일"}까지 일괄 지원됩니다.\n${widget.mainTO.workDaysLabel}',
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
        isWorkDay = workDays.contains(FormatHelper.weekday(day));
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
      bgColor = AppColors.infoBg;
      textColor = AppColors.infoDark;
    } else if (isApplied && isInAppliedRange) {
      // 지원된 기간 내 휴무일
      bgColor = AppColors.infoBg.withValues(alpha: 0.5);
      textColor = AppColors.grey500;
    } else if (isSelected) {
      // 선택된 날짜 (희망 시작일)
      bgColor = AppColors.infoDark;
      textColor = Colors.white;
    } else if (isOutside) {
      bgColor = Colors.transparent;
      textColor = AppColors.grey300;
    } else if (isSelectable) {
      // 선택 가능한 날짜
      bgColor = AppColors.infoBg;
      textColor = AppColors.infoDark;
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
                ? Border.all(color: AppColors.infoDark, width: 2)
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
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.spacing(context, 12),
        ),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
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
              _loadConflictsForDate(selectedDay);
              // _checkAndShowDateAlert 내부에서 _loadMyConfirmedSchedules를
              // await하므로 여기서 중복 호출하지 않음 (race condition 방지)

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
              final dateKey = DateTime.utc(day.year, day.month, day.day);
              final apps = _applicationsByDate[dateKey];
              if (apps == null || apps.isEmpty) return [];
              
              // 마커용 이벤트 리스트 반환
              final events = <String>[];
              for (final app in apps.values) {
                if (AppStatus.confirmedStatuses.contains(app.status)) {
                  events.add('confirmed');
                } else if (app.status == AppStatus.pending) {
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
                final dateKey = DateTime.utc(day.year, day.month, day.day);
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
                  isClosed: isAvailable && _isDateAllClosed(dateKey),
                );
              },

              // 선택된 날짜
              selectedBuilder: (context, day, focusedDay) {
                return _buildDayCell(
                  context,
                  day,
                  isAvailable: true,
                  isSelected: true,
                  isToday: DateUtils.isSameDay(day, todayOnly),
                );
              },

              // 오늘
              todayBuilder: (context, day, focusedDay) {
                final isAvailable = availableDates.any(
                  (d) => DateUtils.isSameDay(d, day),
                );
                final isSelected = _selectedDate != null &&
                    DateUtils.isSameDay(_selectedDate, day);
                final dateKey = DateTime.utc(day.year, day.month, day.day);

                return _buildDayCell(
                  context,
                  day,
                  isAvailable: isAvailable,
                  isSelected: isSelected,
                  isToday: true,
                  isClosed: isAvailable && !isSelected && _isDateAllClosed(dateKey),
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
  Widget _buildDayCell(
    BuildContext context,
    DateTime day, {
    required bool isAvailable,
    required bool isSelected,
    required bool isToday,
    bool isPendingPublish = false,
    DateTime? publishAt,
    bool isClosed = false,
  }) {
    final theme = Theme.of(context);

    Color backgroundColor;
    Color textColor;
    BoxBorder? border;

    // 마감 날짜: 회색 배경 + 취소선
    if (isAvailable && isClosed && !isSelected) {
      return Container(
        margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 2)),
        decoration: BoxDecoration(
          color: AppColors.grey100,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '${day.day}',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400).copyWith(
              decoration: TextDecoration.lineThrough,
              decorationColor: AppColors.grey400,
            ),
          ),
        ),
      );
    }

    if (isSelected) {
      backgroundColor = theme.primaryColor;
      textColor = Colors.white;
    } else if (isToday && isAvailable) {
      backgroundColor = theme.primaryColor.withValues(alpha: 0.1);
      textColor = theme.primaryColor;
      border = Border.all(color: theme.primaryColor, width: 1.5);
    } else if (isAvailable) {
      backgroundColor = theme.primaryColor.withValues(alpha: 0.05);
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

  /// 날짜의 모든 업무가 마감됐는지 (isTimeExpired 포함)
  bool _isDateAllClosed(DateTime dateKey) {
    final now = DateTime.now();
    if (dateKey.isBefore(FormatHelper.toKstDate(now))) return true;
    final workDetails = widget.groupWorkDetailsByDate?[dateKey] ?? [];
    if (workDetails.isEmpty) return false;
    return workDetails.every((d) => d.isClosed || d.isTimeExpired || d.isFull);
  }

  /// 내 확정 스케줄 경고
  Widget _buildMyScheduleWarning(BuildContext context, ThemeData theme) {
    final dateFormat = _mdeFmt;
    final targetDate = _isGroupTO ? _selectedDate : widget.mainTO.date;
    // 그룹TO에서 날짜 미선택(_selectedDate=null) 상태이면 경고 표시 대상이 없음
    if (targetDate == null) return const SizedBox.shrink();

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
                '${dateFormat.format(targetDate)} 확정된 근무가 있습니다',
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
    final dateFormat = _mdeFmt;
    final dateKey = DateTime.utc(date.year, date.month, date.day);
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
            color: theme.primaryColor.withValues(alpha: 0.1),
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
                    color: theme.primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.primaryColor.withValues(alpha: 0.3)),
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
                slotDate: date,
                onApply: (isPending || _isSubmitting) ? null : () => _applyForWork(to, work, date: date),
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
        ? '${FormatHelper.formatDateTime(publishAt)}에 오픈됩니다'
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
    return SafeArea(
      top: false,
      child: Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: ResponsiveHelper.spacing(context, 52),
        child: ElevatedButton(
            onPressed: () => Navigator.pop(
              context,
              ApplyDialogResult(hasChanges: _hasChanges),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                height: 1.2,
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
    if (application.isLongTermApplication && application.isTerminationApproved) {
      return WorkApplicationStatus.notApplied;
    }

    if (AppStatus.confirmedStatuses.contains(application.status)) {
      return WorkApplicationStatus.confirmed;
    }
    if (application.status == AppStatus.pending) {
      return WorkApplicationStatus.pending;
    }
    return WorkApplicationStatus.notApplied;
  }

  String _dateKey(DateTime date) {
    return _isoFmt.format(date);
  }

  String _makeWorkKey(String workType, String startTime, String endTime) {
    return '${workType}_${startTime}_$endTime';
  }

  /// 날짜/슬롯 기준으로 지원서를 필터링한다.
  /// 그룹 TO는 같은 toId를 여러 날짜가 공유하므로, 다른 날짜의 지원서가
  /// 현재 dateKey 캐시에 섞여드는 것을 방지하기 위해 사용한다.
  List<ApplicationModel> _filterApplicationsByDateOrSlot(
      List<ApplicationModel> apps, DateTime dateKey) {
    // 슬롯 ID 결정: 그룹 TO는 날짜별 슬롯, 단일 flex TO는 widget.slotId
    final String? expectedSlotId;
    if (_isGroupTO) {
      expectedSlotId = widget.groupSlotIdsByDate?[dateKey];
    } else {
      expectedSlotId = widget.slotId;
    }

    if (expectedSlotId != null) {
      // slotId 기준 필터 (가장 정확)
      final bySlot = apps.where((a) => a.slotId == expectedSlotId).toList();
      if (bySlot.isNotEmpty) return bySlot;
      // slotId 미부여 기존 데이터 호환: workDate 기준으로 fallback
    }

    // workDate 기준 필터 (비 flex TO 또는 slotId 없는 기존 데이터)
    return apps.where((a) {
      final d = DateTime(a.workDate.year, a.workDate.month, a.workDate.day);
      return d == dateKey;
    }).toList();
  }

  /// Firestore에서 받아온 지원서 목록을 _applicationsByDate에 저장할 형태로 변환한다.
  ///
  /// - 단기/그룹: _filterApplicationsByDateOrSlot으로 해당 날짜/슬롯의 지원서만 추출
  /// - 장기공고: 날짜 필터 없이 전체 사용 (dateKey = TO 시작일 고정)
  /// - 공통: 퇴사/해지 완료된 장기공고 지원서 제거
  Map<String, ApplicationModel> _buildActiveDateCache(
      List<ApplicationModel> applications, DateTime dateKey) {
    final scoped = _isLongTerm
        ? applications
        : _filterApplicationsByDateOrSlot(applications, dateKey);

    final active = scoped.where((app) {
      // [BUG-2-FIX] 단기 TO도 CANCELED/REJECTED 제외
      // 동일 workKey에 CANCELED→PENDING 순으로 존재 시 CANCELED가 마지막에 Map에 기록되어 PENDING을 덮어쓰는 버그
      // 장기/단기 모두 pending/confirmed 계열만 캐시에 포함
      return app.status == AppStatus.pending || AppStatus.confirmedStatuses.contains(app.status);
    }).toList();

    return {
      for (final app in active)
        _makeWorkKey(app.selectedWorkType, app.startTime, app.endTime): app
    };
  }

  // ═══════════════════════════════════════════════════════════
  // 액션 메서드
  // ═══════════════════════════════════════════════════════════

  /// 지원하기
  Future<void> _applyForWork(TOModel to, WorkDetailModel work, {DateTime? date}) async {
    // 중복 동시 지원 방지 — 다른 카드의 지원이 처리 중이면 즉시 차단
    if (_isSubmitting) return;
    // [H-01-FIX] async gap(선결조건 화면) 진입 전 즉시 lock — 대기 중 이중 지원 차단
    setState(() => _isSubmitting = true);

    // 지원 선결조건 게이트 (job_posting_screen 경로와 동일하게 유지)
    final user = context.read<UserProvider>().currentUser;
    if (user == null) {
      if (mounted) setState(() => _isSubmitting = false);
      return;
    }
    if (!meetsApplyPrerequisites(user, isFlexType: to.isFlexType)) {
      final ok = await ApplyPrerequisitesScreen.show(context, isFlexType: to.isFlexType);
      if (ok != true || !mounted) {
        if (mounted) setState(() => _isSubmitting = false);
        return;
      }
    }

    // 🔥 장기공고: 희망 시작일 유효성 검사
    if (_isLongTerm) {
      // 1. 희망 시작일이 선택되지 않은 경우
      if (_desiredStartDate == null) {
        if (mounted) setState(() => _isSubmitting = false);
        ToastHelper.showWarning('희망 시작일을 선택해주세요');
        return;
      }

      // 2. 선택된 날짜가 선택 가능한 날짜인지 확인
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      final startDate = to.date;
      final endDate = _calendarLastDay;
      final workDays = to.workDays;
      final selectableStartDate = todayOnly.isAfter(startDate) ? todayOnly : startDate;

      final selectedDayOnly = DateTime(_desiredStartDate!.year, _desiredStartDate!.month, _desiredStartDate!.day);

      // 과거 날짜인지
      if (selectedDayOnly.isBefore(selectableStartDate)) {
        if (mounted) setState(() => _isSubmitting = false);
        ToastHelper.showWarning('선택한 날짜는 지원할 수 없습니다.\n캘린더에서 희망 시작일을 다시 선택해주세요.');
        return;
      }

      // 종료일 이후인지 (preset 타입이면 미래 제한 없음)
      if (!to.hasPresetPeriod && selectedDayOnly.isAfter(endDate)) {
        if (mounted) setState(() => _isSubmitting = false);
        ToastHelper.showWarning('선택한 날짜가 근무 종료일 이후입니다.');
        return;
      }

      // 근무 요일인지
      if (workDays.isNotEmpty) {
        if (!workDays.contains(FormatHelper.weekday(selectedDayOnly))) {
          if (mounted) setState(() => _isSubmitting = false);
          ToastHelper.showWarning('선택한 날짜는 근무 요일이 아닙니다.');
          return;
        }
      }

      // 충돌 날짜인지 (이 날짜 이후에 확정 근무가 있으면 불가)
      for (final conflictDate in _confirmedDatesInRange) {
        if (!conflictDate.isBefore(selectedDayOnly)) {
          if (mounted) setState(() => _isSubmitting = false);
          ToastHelper.showWarning('선택한 시작일 이후에 확정된 근무가 있습니다.\n다른 날짜를 선택해주세요.');
          return;
        }
      }
    }
    // (H-01-FIX: _isSubmitting은 이미 메서드 진입 시 true로 설정됨)

    // ✅ 지원 확인 팝업
    final confirmed = await ApplyConfirmDialog.show(
      context: context,
      businessName: widget.businessName,
      work: work,
      isLongTerm: _isLongTerm,
      workDate: date ?? to.date,
      desiredStartDate: _isLongTerm ? _desiredStartDate : null,
      endDate: _isLongTerm ? _effectiveEndDate : null,
      workDays: _isLongTerm ? to.workDays : null,
    );

    if (!confirmed || !mounted) {
      if (mounted) setState(() => _isSubmitting = false);
      return;  // 취소 시 종료
    }

    final loadingKey = date != null
        ? '${date.millisecondsSinceEpoch}_${work.id}'
        : work.id;

    setState(() => _loadingWorkIds.add(loadingKey));

    // slotId: 단일 슬롯이면 widget.slotId, 다중 슬롯이면 날짜 맵에서 조회
    final resolvedSlotId = widget.slotId ?? (date == null
        ? null
        : widget.groupSlotIdsByDate?[DateTime.utc(date.year, date.month, date.day)]);

    try {
      final success = await _firestoreService.applyToTOWithWorkType(
        uid: _currentUserId!,
        businessId: to.businessId,
        businessName: to.businessName,
        toTitle: to.title,
        workDate: date ?? to.date,
        selectedWorkType: work.workType,
        workDetailId: work.id,
        wage: work.wage,
        wageType: work.wageType,
        workTypeIcon: work.workTypeIcon,
        workTypeColor: work.workTypeColor,
        workTypeBackgroundColor: work.workTypeBackgroundColor,
        startTime: work.startTime,
        endTime: work.endTime,
        workEndDate: _isLongTerm ? _effectiveEndDate : to.endDate,
        workDays: to.workDays,
        type: to.type,
        toId: to.id,
        slotId: resolvedSlotId,
        desiredStartDate: _isLongTerm ? _desiredStartDate : null,
      );
      if (!success) return; // 에러 메시지는 applyToTOWithWorkType 내부에서 이미 표시됨

      // 상태 새로고침
      await _refreshApplicationStatus(date ?? to.date, work.workType);

      if (!mounted) return;
      _hasChanges = true;
      ToastHelper.showSuccess('지원이 완료되었습니다');
      AnalyticsService.logApply(
        toId: to.id,
        businessName: to.businessName,
        workType: work.workType,
        appType: _isLongTerm ? 'long_term' : 'short',
      );
      
      // 🆕 첫 지원 툴팁
      if (mounted) {
        TooltipContents.showFirstApplication(context);
      }
    } catch (e) {
      debugPrint('❌ 지원 실패: $e');
      if (mounted) {
        ToastHelper.showError(
          e is NetworkOfflineException ? e.message : '지원에 실패했습니다',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _loadingWorkIds.remove(loadingKey);
        });
      }
    }
  }

  /// 지원 취소
  Future<void> _cancelApplication(ApplicationModel application) async {
    // [LOCK-01] 다이얼로그 await 이전 이중 진입 방지 — 연속 탭 시 두 번째 취소 요청 차단
    if (_isSubmitting) return;
    // AUTO_CANCELED 상태면 이미 취소된 것
    if (application.status == AppStatus.autoCanceled) {
      ToastHelper.showInfo('이미 자동취소된 지원입니다 (시간 충돌)');
      return;
    }
    setState(() => _isSubmitting = true);

    final confirmed = await DialogHelper.showCancelConfirm(
      context,
      title: '지원 취소',
      message: '${application.selectedWorkType} 지원을 취소하시겠습니까?',
    );

    if (!confirmed || !mounted) {
      if (mounted) setState(() => _isSubmitting = false);
      return;
    }

    // ✅ 로딩 키 통일 (applyForWork와 동일한 방식)
    final loadingKey = _makeWorkKey(
      application.selectedWorkType,
      application.startTime,
      application.endTime,
    );
    setState(() {
      _loadingWorkIds.add(loadingKey);
    });

    try {
      final success = await _firestoreService.cancelApplication(application.id, _currentUserId!);
      if (!success) return; // 서비스에서 이미 에러 토스트 표시 — finally에서 로딩 해제

      // 상태 새로고침
      await _refreshApplicationStatus(application.workDate, application.selectedWorkType);

      if (!mounted) return;
      _hasChanges = true;
      // 성공 토스트 생략 — cancelApplication 서비스에서 이미 "지원이 취소되었습니다." 표시
    } catch (e) {
      debugPrint('❌ 지원 취소 후 상태 갱신 실패: $e');
      if (mounted) ToastHelper.showError('지원 취소 후 상태 갱신에 실패했습니다');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _loadingWorkIds.remove(loadingKey);
        });
      }
    }
  }

  /// 확정 취소
  Future<void> _cancelConfirm(
    ApplicationModel application,
    WorkDetailModel work, {
    DateTime? date,
  }) async {
    // [LOCK-01] 다이얼로그 await 이전 이중 진입 방지
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    final result = await ConfirmCancelDialog.show(
      context: context,
      workDate: date ?? application.workDate,
      workType: work.workType,
      timeRange: work.timeRange,
      businessName: widget.businessName,
      currentNoShowCount: _userNoShowCount,
    );

    if (result != ConfirmCancelResult.proceed || !mounted) {
      if (mounted) setState(() => _isSubmitting = false);
      return;
    }

    final loadingKey = date != null
        ? '${date.millisecondsSinceEpoch}_${work.id}'
        : work.id;

    setState(() {
      _loadingWorkIds.add(loadingKey); // _isSubmitting은 이미 true
    });

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
      // 장기공고: 확정 취소 후 기간 내 충돌 날짜 재계산
      if (_isLongTerm) await _loadConfirmedDatesInRange();

      if (!mounted) return;
      _hasChanges = true;

      if (hasPenalty) {
        ToastHelper.showWarning('확정이 취소되었습니다. 노쇼 1회가 기록되었습니다.');
      } else {
        ToastHelper.showSuccess('확정이 취소되었습니다');
      }
    } catch (e) {
      debugPrint('❌ 확정 취소 실패: $e');
      if (mounted) ToastHelper.showError('확정 취소에 실패했습니다');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _loadingWorkIds.remove(loadingKey);
        });
      }
    }
  }

  Future<void> _refreshApplicationStatus(DateTime date, String workType) async {
    if (_currentUserId == null) return;

    try {
      TOModel? to;
      // 장기공고는 _loadDateApplications와 동일한 고정 키 사용
      // (_desiredStartDate ≠ mainTO.date인 경우 getter들이 stale 데이터를 보는 불일치 방지)
      final dateKey = _isLongTerm
          ? FormatHelper.toKstDate(widget.mainTO.date)
          : DateTime.utc(date.year, date.month, date.day);

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
          _applicationsByDate[dateKey] = _buildActiveDateCache(applications, dateKey);
        });
      }
    } catch (e) {
      debugPrint('❌ 상태 새로고침 실패: $e');
    }
  }
  /// 상세보기 화면 이동
  void _goToJobPosting(TOModel to, List<WorkDetailModel> workDetails) {
    // pop 전에 context를 캡처 — pop 이후 nav.context는 dispose된 subtree를 참조할 수 있음
    final navigatorContext = context;
    Navigator.of(context).pop();
    NavigationHelper.push(
      navigatorContext,
      destination: JobPostingScreen(
        to: to,
        workDetails: workDetails,
        // flex TO 그룹 슬롯 → rangeStart에 슬롯 날짜 복사됨 → slotDate로 전달
        slotDate: to.isFlexType ? to.date : null,
      ),
    );
  }
  // ═══════════════════════════════════════════════════════════
  // ✅ 날짜 선택 시 상황별 알림 다이얼로그
  // ═══════════════════════════════════════════════════════════

  /// 그룹 TO 날짜 선택 시 특이사항 체크 및 알림 표시
  Future<void> _checkAndShowDateAlert(DateTime selectedDay) async {
    final dateKey = DateTime.utc(selectedDay.year, selectedDay.month, selectedDay.day);

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

    final nowDay = DateTime.now();
    final isDatePast = dateKey.isBefore(FormatHelper.toKstDate(nowDay));
    bool isWorkClosed(WorkDetailData d) => d.isClosed || d.isTimeExpired || d.isFull;

    // 2. 전체 마감 체크 (날짜 경과 포함)
    final allClosed = isDatePast ||
        (workDetails.isNotEmpty && workDetails.every(isWorkClosed));
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
    final hasClosed = workDetails.any(isWorkClosed);
    final hasOpen = workDetails.any((w) => !isWorkClosed(w));
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
    if (apps != null && apps.values.any((app) => app.status == AppStatus.pending || AppStatus.confirmedStatuses.contains(app.status))) {
      debugPrint('🔍 [장기공고] 이미 지원 중 - 충돌 알림 스킵');
      return;  // 이미 지원했으면 알림 표시 안 함
    }
    
    // 1. 확정 근무로 인한 충돌 날짜가 있으면 알림
    if (_confirmedDatesInRange.isNotEmpty) {
      await _showLongTermConflictAlert();
      return;
    }
    
    // 2. 전체 마감 체크
    final workDetails = widget.workDetails;
    bool isWClosed(WorkDetailData d) => d.isClosed || d.isTimeExpired || d.isFull;
    final allClosed = workDetails.isNotEmpty && workDetails.every(isWClosed);
    if (allClosed) {
      await _showClosedAlert(widget.mainTO.date);
      return;
    }

    // 3. 부분 마감 체크
    final hasClosed = workDetails.any(isWClosed);
    final hasOpen = workDetails.any((w) => !isWClosed(w));
    if (hasClosed && hasOpen) {
      await _showPartialClosedAlert(widget.mainTO.date);
      return;
    }
  }

  /// 단일 단기공고 초기 알림 체크
  Future<void> _checkAndShowSingleTOAlert() async {
    final workDate = widget.mainTO.date;
    final workDetails = widget.workDetails;
    final nowDay = DateTime.now();
    final isWorkDatePast = FormatHelper.toKstDate(workDate)
        .isBefore(FormatHelper.toKstDate(nowDay));
    bool isSClosed(WorkDetailData d) => d.isClosed || d.isTimeExpired || d.isFull;

    // 1. 전체 마감 체크 (날짜 경과 포함)
    final allClosed = isWorkDatePast ||
        (workDetails.isNotEmpty && workDetails.every(isSClosed));
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
    final hasClosed = workDetails.any(isSClosed);
    final hasOpen = workDetails.any((w) => !isSClosed(w));
    if (hasClosed && hasOpen) {
      await _showPartialClosedAlert(workDate);
      return;
    }
  }

  /// 예약 대기 알림
  Future<void> _showScheduledAlert(DateTime date, TOModel to) async {
    final dateStr = _mdeFmt.format(date);
    final publishAt = to.publishAt;
    final publishStr = publishAt != null
        ? FormatHelper.formatDateTime(publishAt)
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
    final dateStr = _mdeFmt.format(date);

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
    final dateStr = _mdeFmt.format(date);
    
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
    final dateStr = _mdeFmt.format(date);

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
    final sortedConflicts = _confirmedDatesInRange.toList()..sort();
    final conflictDatesStr = sortedConflicts.take(3).map((d) {
      final dayOfWeek = FormatHelper.weekday(d);
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
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(ctx, 20)),
        ),
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(ResponsiveHelper.spacing(ctx, 20)),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(ResponsiveHelper.spacing(ctx, 20)),
                  topRight: Radius.circular(ResponsiveHelper.spacing(ctx, 20)),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(ctx, 12)),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: ResponsiveHelper.iconSize(ctx, 28), color: iconColor),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(ctx, 12)),
                  Text(
                    title,
                    style: ResponsiveHelper.subtitleStyle(ctx).copyWith(
                      fontWeight: FontWeight.bold,
                      color: iconColor,
                    ),
                  ),
                ],
              ),
            ),

            // 내용
            Padding(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(ctx, 20)),
              child: Column(
                children: [
                  Text(
                    message,
                    style: ResponsiveHelper.bodyStyle(ctx).copyWith(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  if (detail != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(ctx, 12)),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(ctx, 12)),
                      decoration: BoxDecoration(
                        color: AppColors.grey100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        detail,
                        style: ResponsiveHelper.smallStyle(ctx, color: AppColors.grey700),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  if (subMessage != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(ctx, 12)),
                    Text(
                      subMessage,
                      style: ResponsiveHelper.smallStyle(ctx, color: AppColors.grey600),
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
                padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(ctx, 12)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                '확인',
                style: ResponsiveHelper.bodyStyle(ctx, color: Colors.white).copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
        actionsPadding: EdgeInsets.fromLTRB(
          ResponsiveHelper.spacing(ctx, 20),
          0,
          ResponsiveHelper.spacing(ctx, 20),
          ResponsiveHelper.spacing(ctx, 16),
        ),
      ),
    );
  }

}
