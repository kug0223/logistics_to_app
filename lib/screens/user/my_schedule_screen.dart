import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/core/application_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../utils/calendar_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/calendar/schedule_calendar.dart';
import '../../widgets/calendar/schedule_card.dart';
import '../../models/core/attendance_model.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/notification_badge.dart';
import '../../screens/common/notification_screen.dart';
import 'all_to_list_screen.dart';
import '../../theme/app_colors.dart';
import '../../screens/payroll/payslip_period_helper.dart';
import '../../screens/payroll/payslip_pdf_builder.dart';
import 'package:printing/printing.dart';
import '../../widgets/common/app_empty_state.dart';

class MyScheduleScreen extends StatefulWidget {
  const MyScheduleScreen({super.key});

  @override
  State<MyScheduleScreen> createState() => _MyScheduleScreenState();
}

class _MyScheduleScreenState extends State<MyScheduleScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  List<ApplicationModel> _applications = [];
  bool _isLoading = true;

  // 필터: ALL / CONFIRMED / PENDING
  String _selectedFilter = 'ALL';

  // 날짜별 인덱스 캐시 (getEventsForDay O(n) → O(1))
  Map<String, List<ApplicationModel>> _dateIndex = {};

  // 출근 기록 — Map으로 O(1) 조회
  // key: "${applicationId}_${yyyy}-${M}-${d}"
  Map<String, AttendanceModel> _attendanceMap = {};

  // ─── 월별 통계 캐시 (build()마다 재계산 방지) ─────────────
  int _cachedConfirmedCount = 0;
  int _cachedPendingCount = 0;
  int _cachedTotalIncome = 0;
  int _cachedActualDays = 0;
  int _cachedConfirmedIncome = 0;

  void _recomputeStats() {
    // 날짜 인덱스 재빌드 (필터 변경 또는 데이터 갱신 시)
    _dateIndex = CalendarHelper.buildDateIndex(_applications, _selectedFilter);

    final thisMonth = CalendarHelper.getThisMonthApplications(_applications, _focusedDay);
    final attendances = _attendanceMap.values.toList();
    _cachedConfirmedCount  = CalendarHelper.getConfirmedCount(thisMonth);
    _cachedPendingCount    = CalendarHelper.getPendingCount(thisMonth);
    _cachedTotalIncome     = CalendarHelper.getTotalIncome(thisMonth, _focusedDay);
    _cachedActualDays      = CalendarHelper.getActualWorkDays(attendances, _focusedDay);
    _cachedConfirmedIncome = CalendarHelper.getConfirmedIncome(attendances, _focusedDay);
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime(
      _focusedDay.year,
      _focusedDay.month,
      _focusedDay.day,
    );
    _loadApplications();
  }

  // ─── 데이터 로드 ────────────────────────────────────────────

  Future<void> _loadApplications() async {
    setState(() => _isLoading = true);
    try {
      final uid = context.read<UserProvider>().currentUser?.uid;
      if (uid == null) {
        ToastHelper.showError('로그인이 필요합니다.');
        setState(() => _isLoading = false);
        return;
      }

      // [특이사항] Future.wait — 한 쪽 실패 시 outer catch(108행)가 처리, mounted 체크(103행)로 setState 안전
      final results = await Future.wait([
        _firestoreService.getMyApplications(uid),
        _firestoreService.getMyMonthlyAttendances(
          userId: uid,
          year: _focusedDay.year,
          month: _focusedDay.month,
        ),
      ]);

      if (!mounted) return;
      _applications  = results[0] as List<ApplicationModel>;
      _attendanceMap = _buildAttendanceMap(results[1] as List<AttendanceModel>);
      _recomputeStats(); // 데이터 확정 후 1회 계산
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('❌ 지원 내역 로드 실패: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
      }
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
      if (mounted) {
        setState(() {
          _applications  = results[0] as List<ApplicationModel>;
          _attendanceMap = _buildAttendanceMap(results[1] as List<AttendanceModel>);
          _recomputeStats();
        });
      }
    } catch (e) {
      debugPrint('❌ 월별 출근 기록 로드 실패: $e');
      if (mounted) ToastHelper.showError('출근 기록을 불러오지 못했습니다');
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
    return GradientScaffold(
      title: '내 스케줄',
      onRefresh: _loadApplications,
      // [특이사항] 스케줄 변경 승인/거절 후 캘린더 자동 갱신 — onChanged 콜백으로 _loadMonthlyAttendances 재호출
      // GradientScaffold 기본 알림 벨 대신 커스텀 벨을 사용해 NotificationScreen pop 시 _loadApplications 재호출
      showNotificationBell: false,
      actions: [
        NotificationBadge(
          child: Material(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            child: Semantics(
              label: '알림',
              button: true,
              child: InkWell(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NotificationScreen()),
                  );
                  // 알림 화면에서 스케줄 변경 승인/거절이 처리됐을 수 있으므로 캘린더 갱신
                  if (mounted) await _loadApplications();
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.all(
                      ResponsiveHelper.spacing(context, 8)),
                  child: Icon(Icons.notifications_outlined,
                      color: Colors.white,
                      size: ResponsiveHelper.iconSize(context, 24)),
                ),
              ),
            ),
          ),
        ),
      ],
      body: _isLoading
          ? const LoadingWidget(message: '일정을 불러오는 중...')
          : _buildContent(),
    );
  }

  // ─── 컨텐츠 ─────────────────────────────────────────────────

  Widget _buildContent() {
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

          // 선택 날짜 헤더
          if (_selectedDay != null)
            SliverToBoxAdapter(child: _buildDayHeader()),

          // 일정 리스트
          _buildSliverScheduleList(),

          SliverToBoxAdapter(
            child: SizedBox(height: ResponsiveHelper.spacing(context, 32)),
          ),
        ],
      ),
    );
  }

  /// 캘린더 + 범례 + 통계를 하나의 흰 배경 구역으로 통합
  /// 카드 효과(margin/radius/shadow) 없이 풀너비로 배치 → 스크롤 매끄러움
  Widget _buildWhiteZone() {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 캘린더 (패딩만, 카드 없음)
          Padding(
            padding: EdgeInsets.only(
              top: ResponsiveHelper.spacing(context, 8),
            ),
            child: ScheduleCalendar(
              focusedDay: _focusedDay,
              selectedDay: _selectedDay,
              applications: _applications,
              selectedFilter: _selectedFilter,
              dateIndex: _dateIndex,
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay  = focusedDay;
                });
              },
              onPageChanged: (focusedDay) async {
                _focusedDay = focusedDay;
                await _loadMonthlyAttendances(focusedDay);
              },
            ),
          ),

          // 구분선
          const Divider(height: 1, thickness: 1, color: AppColors.grey100),

          // 범례 (풀너비, 카드 없음)
          _buildLegendRow(),

          // 구분선
          const Divider(height: 1, thickness: 1, color: AppColors.grey100),

          // 통계 (풀너비, 카드 없음)
          _buildStatsInline(
            confirmedCount:  _cachedConfirmedCount,
            pendingCount:    _cachedPendingCount,
            actualDays:      _cachedActualDays,
            totalIncome:     _cachedTotalIncome,
            confirmedIncome: _cachedConfirmedIncome,
          ),

          // 흰→회색 전환 구분선
          Container(height: 8, color: AppColors.grey100),
        ],
      ),
    );
  }

  // ─── 캘린더 ─────────────────────────────────────────────────

  // ─── 범례 (풀너비, 카드 없음) ──────────────────────────────────

  Widget _buildLegendRow() {
    final primaryColor = Theme.of(context).primaryColor;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendDot(primaryColor, '확정', star: false),
          SizedBox(width: ResponsiveHelper.spacing(context, 14)),
          _legendDot(AppColors.amberDark, '고정', star: true),
          SizedBox(width: ResponsiveHelper.spacing(context, 14)),
          _legendDot(AppColors.warningMedium, '대기', star: false),
          SizedBox(width: ResponsiveHelper.spacing(context, 14)),
          _legendDot(AppColors.grey400, '휴무', star: true),
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

  // ─── 통계 (풀너비, 카드 없음) ──────────────────────────────────

  Widget _buildStatsInline({
    required int confirmedCount,
    required int pendingCount,
    required int actualDays,
    required int totalIncome,
    required int confirmedIncome,
  }) {
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Center(child: _statItem(Icons.schedule, '대기', '$pendingCount건', AppColors.warning))),
              _vDivider(),
              Expanded(child: Center(child: _statItem(Icons.check_circle, '확정', '$confirmedCount일', AppColors.success))),
              _vDivider(),
              Expanded(child: Center(child: _statItem(Icons.directions_run, '실근무', '$actualDays일', AppColors.teal))),
            ],
          ),
          Padding(
            padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 10)),
            child: const Divider(height: 1, color: AppColors.grey200),
          ),
          Row(
            children: [
              Expanded(child: Center(child: _statItem(Icons.payments, '예상수입(세전)',
                  '${NumberFormat('#,###').format(totalIncome)}원', AppColors.info))),
              _vDivider(),
              Expanded(child: Center(child: _statItem(Icons.paid, '확정수입',
                  '${NumberFormat('#,###').format(confirmedIncome)}원',
                  AppColors.success))),
            ],
          ),
          if (_confirmedWageRecords.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
              child: const Divider(height: 1, color: AppColors.grey200),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _isGeneratingPayslip ? null : _generateMonthlyPayslip,
                icon: _isGeneratingPayslip
                    ? SizedBox(
                        width: ResponsiveHelper.iconSize(context, 14),
                        height: ResponsiveHelper.iconSize(context, 14),
                        child: const CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.receipt_long_outlined,
                        size: ResponsiveHelper.iconSize(context, 14),
                        color: AppColors.infoDark),
                label: Text(
                  _isGeneratingPayslip ? '생성 중...' : '이번 달 임금명세서',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.infoDark, fontWeight: FontWeight.w600),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 6)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 확정 급여 출근 기록 (현재 월)
  List<AttendanceModel> get _confirmedWageRecords {
    final year  = _focusedDay.year;
    final month = _focusedDay.month;
    return _attendanceMap.values.where((a) =>
      a.workDate.year  == year  &&
      a.workDate.month == month &&
      (a.wageStatus == AttendanceModel.wageConfirmed ||
       a.wageStatus == AttendanceModel.wageTransferred) &&
      a.wageDetail != null,
    ).toList();
  }

  bool _isGeneratingPayslip = false;

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

  Widget _statItem(IconData icon, String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: ResponsiveHelper.spacing(context, 16), color: color),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
            Text(value,
                style: ResponsiveHelper.smallStyle(context,
                    color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _vDivider() =>
      Container(width: 1, height: 24, color: AppColors.grey200);

  // ─── 필터 칩 (노출형) ────────────────────────────────────────

  // ─── 필터 칩 (회색 구역) ────────────────────────────────────────

  Widget _buildFilterChipsRow() {
    final theme = Theme.of(context);
    final filters = [
      ('ALL', '전체', Icons.list_alt),
      (AppStatus.confirmed, '확정', Icons.check_circle),
      (AppStatus.pending, '대기', Icons.schedule),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final (value, label, icon) = f;
          final selected = _selectedFilter == value;
          return Padding(
            padding:
                EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
            child: ChoiceChip(
              avatar: Icon(icon,
                  size: 14,
                  color: selected ? Colors.white : AppColors.grey500),
              label: Text(
                label,
                style: ResponsiveHelper.tinyStyle(context,
                    color: selected ? Colors.white : AppColors.grey600)
                    .copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              selected: selected,
              selectedColor: theme.primaryColor,
              backgroundColor: Colors.white,
              side: BorderSide(
                  color:
                      selected ? theme.primaryColor : AppColors.grey200),
              padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 4), vertical: 0),
              onSelected: (_) => setState(() {
                _selectedFilter = value;
                _recomputeStats();
              }),
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── 날짜 헤더 ───────────────────────────────────────────────

  Widget _buildDayHeader() {
    final theme = Theme.of(context);
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
        gradient: LinearGradient(
          colors: [
            theme.primaryColor.withValues(alpha: 0.1),
            theme.primaryColor.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event,
            color: theme.primaryColor,
            size: ResponsiveHelper.iconSize(context, 18),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            FormatHelper.formatDateKorean(_selectedDay!),
            style: ResponsiveHelper.bodyStyle(
              context,
              color: theme.primaryColor,
            ).copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          // 선택 날짜의 일정 수
          _buildDayEventCount(),
        ],
      ),
    );
  }

  Widget _buildDayEventCount() {
    final events = CalendarHelper.getEventsForDayFromIndex(
      _selectedDay!, _dateIndex,
    );
    if (events.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${events.length}건',
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

    final events = CalendarHelper.getEventsForDayFromIndex(
      _selectedDay!, _dateIndex,
    );

    if (events.isEmpty) return _buildEmptyState();

    events.sort((a, b) => _statusOrder(a.status).compareTo(_statusOrder(b.status)));

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 4),
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 4) + MediaQuery.of(context).padding.bottom,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final app = events[index];
            final key =
                '${app.id}_${_selectedDay!.year}-${_selectedDay!.month}-${_selectedDay!.day}';
            final attendance = _attendanceMap[key];
            return ScheduleCard(
              application: app,
              attendance: attendance,
              onChanged: _loadApplications,
              selectedDay: _selectedDay,
            );
          },
          childCount: events.length,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sel = DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
    final isFutureOrToday = !sel.isBefore(today);

    return AppEmptyState(
      icon: isFutureOrToday ? Icons.work_outline : Icons.event_busy,
      iconColor: isFutureOrToday
          ? Theme.of(context).primaryColor.withValues(alpha: 0.4)
          : AppColors.grey300,
      title: isFutureOrToday ? '등록된 일정이 없습니다' : '기록이 없습니다',
      subtitle: isFutureOrToday ? '새로운 공고에 지원해보세요!' : '과거 날짜입니다',
      action: isFutureOrToday
          ? FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AllTOListScreen()),
              ),
              icon: const Icon(Icons.search, size: 18),
              label: const Text('공고 보러가기'),
            )
          : null,
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
