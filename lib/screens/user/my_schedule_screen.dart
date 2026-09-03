import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/core/application_model.dart';
import '../../models/core/worker_availability_model.dart';
import '../../services/firestore_service.dart';
import '../../services/availability_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../utils/calendar_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/calendar/schedule_calendar.dart';
import '../../widgets/calendar/schedule_card.dart';
import '../../models/core/attendance_model.dart';
import '../../theme/app_colors.dart';
import '../../screens/payroll/payslip_period_helper.dart';
import '../../screens/payroll/payslip_pdf_builder.dart';
import 'package:printing/printing.dart';
import '../../widgets/common/app_empty_state.dart';
import 'user_tab_scope.dart';

class MyScheduleScreen extends StatefulWidget {
  const MyScheduleScreen({super.key});

  @override
  State<MyScheduleScreen> createState() => _MyScheduleScreenState();
}

class _MyScheduleScreenState extends State<MyScheduleScreen> {
  static final _fmt = NumberFormat('#,###');
  final FirestoreService _firestoreService = FirestoreService();
  final AvailabilityService _availabilityService = AvailabilityService();

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  // 월 빠른 전환 시 stale 배치 무시 — _loadMonthlyAttendances와 세대 비교
  int _monthGeneration = 0;

  List<ApplicationModel> _applications = [];
  bool _isLoading = true;
  bool _initialLoadStarted = false;

  // 필터: ALL / CONFIRMED / PENDING
  String _selectedFilter = 'ALL';

  // 날짜별 인덱스 캐시 (getEventsForDay O(n) → O(1))
  Map<String, List<ApplicationModel>> _dateIndex = {};

  // 출근 기록 — Map으로 O(1) 조회
  // key: "${applicationId}_${yyyy}-${M}-${d}"
  Map<String, AttendanceModel> _attendanceMap = {};

  // ─── Phase 8.1A: 근무 가능일 ────────────────────────────────
  /// 저장된 가능일 날짜 키 Set — 캘린더 파란 dot, 배너 카운트에 사용
  Set<String> _availabilityDates = {};
  /// 에디트 모드 활성화 여부
  bool _isEditMode = false;
  /// 에디트 모드에서 현재 선택 중인 날짜 키 Set
  Set<String> _editingDates = {};
  /// 저장 중 상태 (중복 호출 방지)
  bool _isSavingAvailability = false;

  // ─── 월별 통계 캐시 (build()마다 재계산 방지) ─────────────
  int _cachedConfirmedCount = 0;
  int _cachedTotalIncome = 0;
  int _cachedActualDays = 0;
  int _cachedConfirmedIncome = 0;
  List<AttendanceModel> _cachedConfirmedWageRecords = []; // H2: getter 대신 캐시
  List<ApplicationModel> _selectedDayEvents = []; // H1: 선택 날짜 이벤트 캐시 (정렬 포함)

  void _recomputeStats() {
    _dateIndex = CalendarHelper.buildDateIndex(_applications, _selectedFilter);

    final thisMonth = CalendarHelper.getThisMonthApplications(_applications, _focusedDay);
    final attendances = _attendanceMap.values.toList();
    _cachedConfirmedCount  = CalendarHelper.getConfirmedCount(thisMonth);
    _cachedTotalIncome     = CalendarHelper.getTotalIncome(thisMonth, _focusedDay);
    _cachedActualDays      = CalendarHelper.getActualWorkDays(attendances, _focusedDay);
    _cachedConfirmedIncome = CalendarHelper.getConfirmedIncome(attendances, _focusedDay);
    // H2: 확정 급여 기록 — 월 기준으로 필터링 후 캐시
    final year = _focusedDay.year;
    final month = _focusedDay.month;
    _cachedConfirmedWageRecords = attendances.where((a) =>
      a.workDate.year == year && a.workDate.month == month &&
      (a.wageStatus == AttendanceModel.wageConfirmed ||
       a.wageStatus == AttendanceModel.wageTransferred) &&
      a.wageDetail != null,
    ).toList();
    _recomputeSelectedDayEvents(); // H1: dateIndex 갱신 후 선택 날짜 이벤트 재계산
  }

  // H1: 선택 날짜 이벤트를 캐싱 + 정렬 — _buildDayEventCount·_buildSliverScheduleList 공유
  void _recomputeSelectedDayEvents() {
    if (_selectedDay == null) {
      _selectedDayEvents = [];
      return;
    }
    final events = CalendarHelper.getEventsForDayFromIndex(_selectedDay!, _dateIndex);
    events.sort((a, b) => _statusOrder(a.status).compareTo(_statusOrder(b.status)));
    _selectedDayEvents = events;
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime(
      _focusedDay.year,
      _focusedDay.month,
      _focusedDay.day,
    );
    // 근무 가능일 백그라운드 로드 (캘린더 로드를 블로킹하지 않음)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAvailability();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadStarted) {
      _initialLoadStarted = true;
      _loadApplications();
    }
    // pendingScheduleMonth: 홈 "근무 기록 보기" 경유 진입 시 현재 달로 리셋.
    // UserJobTab.didChangeDependencies의 pendingJobDate 소비 패턴과 동일.
    // clearFn을 여기서 캡처 — postFrameCallback 안에서 context 재호출 시
    // debug assertion이 터지므로 클로저로 미리 캡처한다.
    final scope = UserTabScope.of(context);
    final pending = scope?.pendingScheduleMonth;
    if (pending != null) {
      final clearFn = scope!.clearPendingScheduleMonth;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        clearFn();
        final now = DateTime.now();
        // 이미 현재 달이면 스킵 (불필요한 리로드 방지)
        if (_focusedDay.year == now.year && _focusedDay.month == now.month) return;
        _monthGeneration++;
        setState(() {
          _focusedDay = DateTime(now.year, now.month, now.day);
          _selectedDay = DateTime(now.year, now.month, now.day);
        });
        _loadMonthlyAttendances(_focusedDay);
      });
    }
  }

  // ─── 데이터 로드 ────────────────────────────────────────────

  Future<void> _loadApplications() async {
    if (!mounted) return;
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) {
      ToastHelper.showError('로그인이 필요합니다.');
      setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);

    // Phase 1: 지원 내역 먼저 로드 (1분 TTL 캐시 — 재방문 시 즉시 반환)
    try {
      final applications = await _firestoreService.getMyApplications(uid);
      if (!mounted) return;
      _applications = applications;
      _attendanceMap = {};
      _recomputeStats();
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('❌ 지원 내역 로드 실패: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
      }
      return;
    }

    // Phase 2: 출근 기록 백그라운드 로드 (2분 TTL 캐시)
    // 실패해도 스케줄 카드는 이미 표시되어 있으므로 토스트 없이 조용히 처리
    try {
      final attendances = await _firestoreService.getMyMonthlyAttendances(
        userId: uid,
        year: _focusedDay.year,
        month: _focusedDay.month,
      );
      if (!mounted) return;
      setState(() {
        _attendanceMap = _buildAttendanceMap(attendances);
        _recomputeStats();
      });
    } catch (e) {
      debugPrint('❌ 출근 기록 로드 실패: $e');
    }
  }

  /// 월 이동 시 호출 — 출근 기록 + 지원 내역 모두 갱신
  ///
  /// [B03] 이전 코드는 _loadMonthlyAttendances에서 출근 기록만 재조회하고
  /// _applications(getMyApplications)는 재조회하지 않았다.
  /// TTL 캐시(1분)가 있어 서버 부담이 거의 없고, 장기 지원서는 월별로
  /// isScheduledOnDate 판단이 달라지므로 _applications도 함께 갱신해야
  /// 통계·캘린더 인덱스가 올바르게 갱신된다.
  Future<void> _loadMonthlyAttendances(DateTime focusedDay) async {
    if (!mounted) return;
    final gen = _monthGeneration; // 빠른 전환 시 stale 배치 폐기용
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) return;
    try {
      final results = await Future.wait([
        _firestoreService.getMyApplications(uid),
        _firestoreService.getMyMonthlyAttendances(
          userId: uid,
          year: focusedDay.year,
          month: focusedDay.month,
        ),
      ]);
      if (!mounted || _monthGeneration != gen) return;
      setState(() {
        _applications  = results[0] as List<ApplicationModel>;
        _attendanceMap = _buildAttendanceMap(results[1] as List<AttendanceModel>);
        _recomputeStats();
      });
    } catch (e) {
      debugPrint('❌ 월별 출근 기록 로드 실패: $e');
      if (mounted) ToastHelper.showError('출근 기록을 불러오지 못했습니다');
    }
  }

  // ─── Phase 8.1A: 근무 가능일 CRUD ──────────────────────────

  /// 저장된 근무 가능일 로드. 실패 시 조용히 무시 (핵심 기능이 아님).
  Future<void> _loadAvailability() async {
    if (!mounted) return;
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) return;
    try {
      final model = await _availabilityService.loadMyAvailability(uid);
      if (!mounted) return;
      setState(() {
        _availabilityDates = model?.dateSet ?? {};
      });
    } catch (e) {
      debugPrint('❌ 근무 가능일 로드 실패: $e');
    }
  }

  /// 에디트 모드 진입. 기존 가능일로 editingDates 초기화.
  void _enterEditMode() {
    setState(() {
      _isEditMode = true;
      _editingDates = Set<String>.from(_availabilityDates);
    });
  }

  /// 에디트 모드 취소. 변경사항 버림.
  void _cancelEdit() {
    setState(() {
      _isEditMode = false;
      _editingDates = {};
    });
  }

  /// 에디트 모드에서 날짜 토글 (tap = 선택/해제)
  void _toggleDate(DateTime day) {
    final key = WorkerAvailabilityModel.dateKeyFrom(day);
    setState(() {
      if (_editingDates.contains(key)) {
        _editingDates.remove(key);
      } else {
        if (_editingDates.length >= 60) {
          ToastHelper.showWarning('최대 60일까지 등록할 수 있습니다.');
          return;
        }
        _editingDates.add(key);
      }
    });
  }

  /// 에디트 모드에서 저장. Rules에서 city canonical 검증 수행.
  Future<void> _saveAvailability() async {
    if (_isSavingAvailability) return;
    final user = context.read<UserProvider>().currentUser;
    if (user == null) {
      ToastHelper.showError('로그인이 필요합니다.');
      return;
    }
    final city = user.homeRegion?.city;
    if (city == null || city.isEmpty) {
      ToastHelper.showError('지역 정보가 없습니다. 프로필에서 거주 지역을 먼저 설정해주세요.');
      return;
    }

    setState(() => _isSavingAvailability = true);
    try {
      await _availabilityService.saveAvailability(
        uid: user.uid,
        dates: _editingDates,
        city: city,
        district: user.homeRegion?.district,
      );
      if (!mounted) return;
      final saved = Set<String>.from(_editingDates);
      setState(() {
        _availabilityDates = saved;
        _isEditMode = false;
        _editingDates = {};
        _isSavingAvailability = false;
      });
      ToastHelper.showSuccess('${saved.length}일 근무 가능일이 저장되었습니다.');
    } catch (e) {
      debugPrint('❌ 근무 가능일 저장 실패: $e');
      if (mounted) {
        setState(() => _isSavingAvailability = false);
        ToastHelper.showError('저장에 실패했습니다. 다시 시도해주세요.');
      }
    }
  }

  /// attendance 리스트 → Map 변환 (applicationId + 날짜 복합키)
  ///
  /// 키 포맷: '${applicationId}_${year}-${month}-${day}' (월·일 미패딩)
  /// 동일 applicationId + 날짜가 중복이면 나중 항목이 덮어쓰지만,
  /// docId = '${applicationId}_yyyyMMdd'이므로 Firestore에서 중복 방지됨.
  ///
  /// ⚠️ CalendarHelper.getActualWorkDays의 uniqueDates 키 포맷('year-month-day' 미패딩)과
  ///    스케줄 목록 조회 키 포맷이 이 포맷과 일치해야 함 — 변경 시 세 곳 동시 수정 필요.
  Map<String, AttendanceModel> _buildAttendanceMap(List<AttendanceModel> list) {
    final map = <String, AttendanceModel>{};
    for (final att in list) {
      final key = '${att.applicationId}_${att.workDate.year}-${att.workDate.month}-${att.workDate.day}';
      map[key] = att;
    }
    return map;
  }

  // ─── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _isEditMode ? '근무 가능일 선택' : '일정',
          style: ResponsiveHelper.subtitleStyle(context)
              .copyWith(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        centerTitle: false,
        // 에디트 모드가 아닐 때만 "근무 가능일 등록" CTA 표시
        actions: _isEditMode
            ? null
            : [
                TextButton.icon(
                  onPressed: _enterEditMode,
                  icon: const Icon(Icons.event_available_outlined, size: 18),
                  label: const Text('가능일'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.info,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
      ),
      // 에디트 모드 하단 sticky 바 (SafeArea(top: false) 필수)
      bottomNavigationBar: _isEditMode
          ? SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _cancelEdit,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.grey300),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _isSavingAvailability ? null : _saveAvailability,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.info,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.grey300,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _isSavingAvailability
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _editingDates.isEmpty
                                    ? '저장 (삭제)'
                                    : '${_editingDates.length}일 저장',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: _isLoading
          ? const LoadingWidget(message: '일정을 불러오는 중...')
          : _buildContent(),
    );
  }

  // ─── 컨텐츠 ─────────────────────────────────────────────────

  Widget _buildContent() {
    // 에디트 모드: 달력만 보이고 일정 목록 숨김
    if (_isEditMode) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: _buildWhiteZone(),
      );
    }

    // SliverFillRemaining(hasScrollBody: false) 은 반드시 마지막 sliver이어야 한다.
    // 뒤에 SliverToBoxAdapter를 추가하면 그 높이만큼 스크롤이 발생한다.
    // 빈 상태(선택 날짜 있고 이벤트 없음)일 때 trailing 여백 sliver를 제외한다.
    final showEmptyState = _selectedDay != null && _selectedDayEvents.isEmpty;

    return RefreshIndicator(
      onRefresh: _loadApplications,
      color: Theme.of(context).primaryColor,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── 흰 구역: 캘린더 + 범례 + 통계 (카드 없이 연결)
          SliverToBoxAdapter(child: _buildWhiteZone()),

          // ── 회색 구역: 필터 칩
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 12),
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 4),
              ),
              child: _buildFilterChipsRow(),
            ),
          ),

          // 선택 날짜 헤더 — 일정이 있을 때만 표시
          // 일정이 없으면 헤더 없이 빈 상태 바로 시작 (헤더가 기대감을 유발하는 문제 방지)
          if (_selectedDay != null && _selectedDayEvents.isNotEmpty)
            SliverToBoxAdapter(child: _buildDayHeader()),

          // 일정 리스트 or 빈 상태(SliverFillRemaining)
          _buildSliverScheduleList(),

          // 홈 인디케이터 + 하단 여백:
          // 빈 상태(SliverFillRemaining)가 마지막 sliver일 때는 추가하지 않는다.
          // → SafeArea bottom은 AppEmptyState 내부 Padding으로 처리됨
          if (!showEmptyState)
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.of(context).padding.bottom +
                    ResponsiveHelper.spacing(context, 16),
              ),
            ),
        ],
      ),
    );
  }

  /// 캘린더 + 범례 + 월 요약을 하나의 흰 배경 구역으로 통합
  Widget _buildWhiteZone() {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 캘린더
          ScheduleCalendar(
            focusedDay: _focusedDay,
            selectedDay: _isEditMode ? null : _selectedDay,
            applications: _applications,
            selectedFilter: _selectedFilter,
            dateIndex: _dateIndex,
            // Phase 8.1A: 가능일 마커 + 에디트 모드 파라미터
            availabilityDates: _availabilityDates,
            editingDates: _isEditMode ? _editingDates : null,
            isEditMode: _isEditMode,
            onDaySelected: (selectedDay, focusedDay) {
              if (_isEditMode) {
                // 에디트 모드: 날짜 tap = 선택/해제
                _toggleDate(selectedDay);
                setState(() => _focusedDay = focusedDay);
              } else {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay  = focusedDay;
                  _recomputeSelectedDayEvents(); // H1
                });
              }
            },
            onPageChanged: (focusedDay) {
              _monthGeneration++;
              setState(() => _focusedDay = focusedDay);
              if (!_isEditMode) _loadMonthlyAttendances(focusedDay);
            },
          ),

          // 범례 (에디트 모드에서는 간소화 표시)
          _buildLegendRow(),

          // 근무 가능일 배너 (에디트 모드가 아닐 때만 표시)
          if (!_isEditMode) _buildAvailabilityBanner(),

          // 에디트 모드 안내 문구
          if (_isEditMode) _buildEditModeHint(),

          // 구분선
          const Divider(height: 1, thickness: 1, color: AppColors.grey100),

          // N월 요약 (2×2 KPI) — 에디트 모드에서는 숨김
          if (!_isEditMode) _buildMonthlySummary(),

          // 흰→회색 전환 구분선 (에디트 모드에서는 회색 구역 없음)
          if (!_isEditMode) Container(height: 8, color: AppColors.grey100),
        ],
      ),
    );
  }

  /// 근무 가능일 배너 — 평상시에 가능일 현황 표시
  ///
  /// count == 0 : 가능일 미등록 → 근무 제안 안내 타일 표시
  /// count > 0  : 등록된 일 수 표시 + 근무 제안 설명 부제목
  Widget _buildAvailabilityBanner() {
    final count = _availabilityDates.length;
    const descText =
        '가능일을 등록하면 조건이 맞는 사업장에서 근무 제안을 받을 수 있어요.';

    if (count == 0) {
      // 미등록 상태 — 등록 유도 타일
      return Container(
        margin: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 6),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        decoration: BoxDecoration(
          color: AppColors.infoBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 16, color: AppColors.info),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Expanded(
              child: Text(
                descText,
                style: ResponsiveHelper.smallStyle(
                    context, color: AppColors.infoDark),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            GestureDetector(
              onTap: _enterEditMode,
              child: Text(
                '등록',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: AppColors.infoDark,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    // 등록 상태 — 현황 + 부제목
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_available_outlined,
              size: 16, color: AppColors.info),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '근무 가능일 $count일 등록됨',
                  style: ResponsiveHelper.smallStyle(
                      context, color: AppColors.infoDark)
                    ..copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  descText,
                  style: ResponsiveHelper.tinyStyle(
                      context, color: AppColors.infoDark),
                ),
              ],
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          GestureDetector(
            onTap: _enterEditMode,
            child: Text(
              '수정',
              style: ResponsiveHelper.smallStyle(
                context,
                color: AppColors.infoDark,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// 에디트 모드 안내 문구
  Widget _buildEditModeHint() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      child: Text(
        '날짜를 눌러 근무 가능일을 선택/해제하세요 (최대 60일, 오늘~90일 이내)',
        style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ─── 캘린더 ─────────────────────────────────────────────────

  // ─── 범례 (풀너비, 카드 없음) ──────────────────────────────────

  Widget _buildLegendRow() {
    final primaryColor = Theme.of(context).primaryColor;
    // 에디트 모드: 파란 원(선택) 안내만 표시
    if (_isEditMode) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: primaryColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '선택됨',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendDot(primaryColor, '확정', star: false),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          _legendDot(AppColors.amberDark, '고정', star: true),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          _legendDot(AppColors.warningMedium, '대기', star: false),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          _legendDot(AppColors.grey400, '휴무', star: true),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          _legendDot(AppColors.info, '가능', star: false),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label, {required bool star}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        star
            ? Icon(Icons.star, size: 10, color: color)
            : Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
        const SizedBox(width: 4),
        Text(
          label,
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
        ),
      ],
    );
  }

  // ─── N월 요약 (2×2 KPI 그리드) ─────────────────────────────────

  Widget _buildMonthlySummary() {
    final month = _focusedDay.month;
    final primaryColor = Theme.of(context).primaryColor;
    // 값이 0이면 비활성(textTertiary), 값이 있으면 semantic 색상 활성화
    final confirmedWorkColor = _cachedConfirmedCount > 0
        ? AppColors.textPrimary
        : AppColors.textTertiary;
    final actualDaysColor = _cachedActualDays > 0
        ? AppColors.textPrimary
        : AppColors.textTertiary;
    final incomeColor = _cachedTotalIncome > 0 ? primaryColor : AppColors.textTertiary;
    final confirmedIncomeColor = _cachedConfirmedIncome > 0
        ? const Color(0xFF2E9D45)
        : AppColors.textTertiary;

    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$month월 요약',
            style: ResponsiveHelper.bodyStyle(context)
                .copyWith(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
          Row(
            children: [
              Expanded(
                child: _kpiItem('확정 근무', '$_cachedConfirmedCount일', confirmedWorkColor),
              ),
              Expanded(
                child: _kpiItem('실근무', '$_cachedActualDays일', actualDaysColor),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Row(
            children: [
              Expanded(
                child: _kpiItem(
                  '예상수입',
                  '${_fmt.format(_cachedTotalIncome)}원',
                  incomeColor,
                ),
              ),
              Expanded(
                child: _kpiItem(
                  '확정수입',
                  '${_fmt.format(_cachedConfirmedIncome)}원',
                  confirmedIncomeColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiItem(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 3)),
        Text(
          value,
          style: ResponsiveHelper.subtitleStyle(context)
              .copyWith(fontWeight: FontWeight.bold, color: valueColor),
        ),
      ],
    );
  }

  // H2: build()마다 _attendanceMap 재순회 방지 — _recomputeStats()에서 갱신
  List<AttendanceModel> get _confirmedWageRecords => _cachedConfirmedWageRecords;

  // [임금명세서 UI 제거 — 향후 수입 현황/급여 상세 화면에서 재활용 예정]
  // ignore: unused_field
  bool _isGeneratingPayslip = false;

  // ignore: unused_element
  Future<void> _generateMonthlyPayslip() async {
    final records = _confirmedWageRecords;
    if (records.isEmpty) {
      ToastHelper.showWarning('이번 달 확정된 급여 내역이 없습니다');
      return;
    }
    final uid = context.read<UserProvider>().currentUser;
    if (uid == null) {
      ToastHelper.showWarning('로그인이 필요합니다');
      return;
    }

    setState(() => _isGeneratingPayslip = true);
    try {
      final data = AggregatedPayslipData.fromRecords(
        records: records,
        workerName: uid.name,
        issueType: PayslipIssueType.monthly,
        year: _focusedDay.year,
        month: _focusedDay.month,
        periodStart: DateTime(_focusedDay.year, _focusedDay.month, 1),
        periodEnd: DateTime(_focusedDay.year, _focusedDay.month + 1, 0),
        workerBirthDate: uid.birthDate != null
            ? FormatHelper.formatDateDot(uid.birthDate!)
            : '',
      );
      final bytes = await PayslipPdfBuilder.buildAggregated(data);
      final filename = '${uid.name}_${_focusedDay.year}년${_focusedDay.month}월_임금명세서.pdf';
      if (!mounted) return;
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (e) {
      if (mounted) ToastHelper.showError('임금명세서 생성에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isGeneratingPayslip = false);
    }
  }

  // ─── 필터 칩 (노출형) ────────────────────────────────────────

  // ─── 필터 칩 ─────────────────────────────────────────────────

  Widget _buildFilterChipsRow() {
    final theme = Theme.of(context);
    const bgSurface = Color(0xFFF5F6F8);
    final filters = [
      ('ALL', '전체'),
      (AppStatus.confirmed, '확정'),
      (AppStatus.pending, '대기'),
    ];
    return Row(
      children: filters.map((f) {
        final (value, label) = f;
        final selected = _selectedFilter == value;
        return Padding(
          padding: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
          child: GestureDetector(
            onTap: () => setState(() {
              _selectedFilter = value;
              _recomputeStats();
            }),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 14),
                vertical: ResponsiveHelper.spacing(context, 7),
              ),
              decoration: BoxDecoration(
                color: selected ? theme.primaryColor : bgSurface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: selected ? Colors.white : AppColors.grey600,
                ).copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── 날짜 헤더 ───────────────────────────────────────────────

  Widget _buildDayHeader() {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_outlined,
            color: AppColors.grey600,
            size: ResponsiveHelper.iconSize(context, 16),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            FormatHelper.formatDateKorean(_selectedDay!),
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.textSecondary)
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          _buildDayEventCount(),
        ],
      ),
    );
  }

  Widget _buildDayEventCount() {
    // H1: 캐시된 _selectedDayEvents 사용 — getEventsForDayFromIndex 중복 호출 제거
    if (_selectedDayEvents.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${_selectedDayEvents.length}건',
        style: ResponsiveHelper.tinyStyle(
          context,
          color: Theme.of(context).primaryColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ─── 일정 리스트 ─────────────────────────────────────────────

  Widget _buildSliverScheduleList() {
    if (_selectedDay == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    // H1: 캐시된 _selectedDayEvents 사용 — 중복 조회·정렬 제거
    if (_selectedDayEvents.isEmpty) return _buildEmptyState();

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 4),
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 4), // 하단은 마지막 SliverToBoxAdapter에서 일괄 처리
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final app = _selectedDayEvents[index];
            final key =
                '${app.id}_${_selectedDay!.year}-${_selectedDay!.month}-${_selectedDay!.day}';
            final attendance = _attendanceMap[key];
            return RepaintBoundary( // L1: 카드별 GPU 재래스터 방지
              child: ScheduleCard(
                application: app,
                attendance: attendance,
                onChanged: _loadApplications,
                selectedDay: _selectedDay,
              ),
            );
          },
          childCount: _selectedDayEvents.length,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isFiltered = _selectedFilter != 'ALL';
    final sel = _selectedDay!;
    final dateLabel = '${sel.month}월 ${sel.day}일';

    // 필터 ON — "전체 보기" 텍스트 링크만 제공 (CTA 버튼 불필요)
    // SliverFillRemaining(hasScrollBody: false) → 필터+헤더 아래 남은 영역을 정확히 채워
    // 스크롤 오버플로 없이 콘텐츠를 수직 중앙 정렬
    if (isFiltered) {
      final filterLabel = _selectedFilter == AppStatus.confirmed ? '확정' : '대기';
      return AppEmptyState(
        icon: Icons.filter_list_off,
        iconColor: AppColors.grey300,
        title: "'$filterLabel' 일정이 없어요",
        subtitle: '다른 필터를 선택하거나 전체 보기를 눌러보세요',
        action: TextButton(
          onPressed: () => setState(() {
            _selectedFilter = 'ALL';
            _recomputeStats();
          }),
          child: const Text('전체 보기'),
        ),
        asSliver: true,
      );
    }

    // 필터 OFF — 날짜 포함 제목, 캘린더 유도 문구, CTA 버튼 없음
    // 사용자는 위 캘린더에서 다른 날짜를 선택하면 되고,
    // 일자리는 하단 탭에서 접근 가능 — 빈 상태에서 구직 행동 강요 불필요
    return AppEmptyState(
      icon: Icons.calendar_today_outlined,
      iconColor: AppColors.grey300,
      title: '$dateLabel 일정이 없어요',
      subtitle: '다른 날짜를 선택해 확인해보세요',
      asSliver: true,
    );
  }

  int _statusOrder(String status) {
    switch (status) {
      case AppStatus.confirmed:
      case AppStatus.contractPending:
        return 1;
      case AppStatus.pending:
        return 2;
      case AppStatus.rejected:
        return 3;
      case AppStatus.canceled:
        return 4;
      case AppStatus.autoCanceled:
        return 5;
      default:
        return 6;
    }
  }
}
