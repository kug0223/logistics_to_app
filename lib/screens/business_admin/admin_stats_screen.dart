import 'package:fl_chart/fl_chart.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../services/admin_stats_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import 'admin_month_detail_screen.dart';
import 'admin_stats_access.dart';
import 'stats_attendance_list_screen.dart';
import '../../utils/text_layout.dart';
import '../../models/core/attendance_model.dart';
import '../../screens/common/notification_screen.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/notification_badge.dart';

class AdminStatsScreen extends StatefulWidget {
  final List<String> businessIds;

  /// [R7-P1-7 후속 P17-S] 통계 reader 주입점.
  ///
  ///   production 은 null → `AdminStatsService()` 그대로다. 화면의 파싱·파생·
  ///   문구·필터는 **바뀌지 않는다** — 읽기 한 칸만 갈아끼워 실제 콘텐츠를 그릴 수
  ///   있게 한 것이다. 테스트가 막혔던 이유는 화면의 lifecycle 이 아니라
  ///   `AdminStatsService.getBusinessOptions` 안의 `Future.timeout(15s)` 가
  ///   끝나지 않는 Firestore future 위에서 타이머로 남았기 때문이다(아래 참조).
  final AdminStatsService? service;

  /// [STATS-TO-ATTENDANCE.27] 시험 주입점 — 내역 목록이 근태 화면 대신 부른다. production 은 null.
  final Future<bool?> Function(AttendanceModel r)? debugOpenAttendance;

  const AdminStatsScreen(
      {super.key, required this.businessIds, this.service, this.debugOpenAttendance});

  @override
  State<AdminStatsScreen> createState() => _AdminStatsScreenState();
}

class _AdminStatsScreenState extends State<AdminStatsScreen> {
  late final AdminStatsService _service = widget.service ?? AdminStatsService();

  DateTime _buildNow = DateTime.now();
  late int _selectedYear;
  String? _filterBusinessId; // null = 전체
  bool _isLoading = true;
  bool _isFetching = false;
  // [RACE-FIX] request generation counter.
  // 비즈니스 필터 변경 중 이전 fetch가 진행 중이면
  // 새 요청도 시작되고, 먼저 도착하는 stale response는 state 반영 금지.
  int _statsRequestId = 0;
  final _touchedBarIndex = ValueNotifier<int>(-1);

  AnnualStatsData? _data;
  List<BusinessOption> _businesses = [];
  bool _hasError = false;
  /// [ADMIN-STATS-CLOSEOUT] 마지막 불러오기 시점의 조회 대상 급여 권한. allowed 가 아니면 숫자를 그리지 않는다.
  PermissionCheck _access = PermissionCheck.allowed;

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
    _init();
  }

  @override
  void dispose() {
    _touchedBarIndex.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    // 사업장 목록과 통계를 동시에 요청 — 서로 독립적
    final bizFuture = _service.getBusinessOptions(widget.businessIds);
    _loadStats(); // 내부 에러 처리 있음, await 없이 병렬 시작
    try {
      final bizOptions = await bizFuture;
      if (!mounted) return;
      setState(() => _businesses = bizOptions);
    } catch (e) {
      debugPrint('⚠️ 사업장 목록 로드 실패: $e');
    }
  }

  /// [STATS-TO-ATTENDANCE.27] 정정 뒤 다시 읽기에 실패했다 — 아래 숫자는 정정 전 기준이다.
  bool _staleAfterChange = false;

  /// [quiet] 내역·월 상세에서 정정하고 돌아온 갱신 — 화면을 로딩으로 바꾸지 않는다(스크롤 유지).
  ///   근태를 못 읽은 응답이면 이전 숫자를 '확인 불가'·0 으로 덮지 않고 정정 전 기준이라고 말한다.
  Future<void> _loadStats({bool quiet = false}) async {
    if (!mounted) return;
    final keepOld = quiet && _data != null;
    // [RACE-FIX] request generation counter — latest request wins.
    // 이전 if (_isFetching) return; 제거: 새 요청을 drop하지 않고 항상 시작.
    // stale response가 현재 state를 덮어쓰는 것은 requestId 불일치로 방지.
    // (async 중 _filterBusinessId / _selectedYear 변경에 무관하게 동작)
    final requestId = ++_statsRequestId;
    final requestedFilterId = _filterBusinessId; // request 시점 스냅샷
    final requestedYear = _selectedYear;         // request 시점 스냅샷
    // [ADMIN-STATS-CLOSEOUT] 조회 대상 사업장마다 급여 권한 — 없거나 모르면 부르지 않고 이전 숫자도 지운다.
    final access = AdminStatsAccess.check(context.read<UserProvider>(),
        requestedFilterId != null ? [requestedFilterId] : widget.businessIds);
    if (access != PermissionCheck.allowed) {
      setState(() { _access = access; _data = null; _hasError = false; _isLoading = false; _isFetching = false; });
      return;
    }
    setState(() { _access = PermissionCheck.allowed; if (!keepOld) _isLoading = true; _isFetching = true; });
    try {
      final data = await _service.getAnnualStats(
        businessIds: widget.businessIds,
        filterBusinessId: requestedFilterId, // 스냅샷 사용 — live state 재참조 금지
        year: requestedYear,                 // 스냅샷 사용
      );
      // stale response guard: 최신 request만 state 반영
      if (!mounted || requestId != _statsRequestId) return;
      if (keepOld && data.attendanceStatsState != AttendanceStatsState.available) {
        setState(() { _staleAfterChange = true; _isLoading = false; _isFetching = false; });
        return;
      }
      setState(() { _data = data; _hasError = false; _isLoading = false; _isFetching = false; _buildNow = DateTime.now(); _staleAfterChange = false; });
    } catch (e) {
      debugPrint('❌ 연간 통계 로드 실패: $e');
      // stale error도 무시: 최신 request의 결과만 반영
      if (!mounted || requestId != _statsRequestId) return;
      setState(() { if (keepOld) { _staleAfterChange = true; } else { _hasError = true; } _isLoading = false; _isFetching = false; _buildNow = DateTime.now(); });
    }
  }

  void _showBizPicker() {
    DialogHelper.showSheet(
      context,
      builder: (ctx) {
        final allItems = [null, ..._businesses];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들바
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            // 헤더
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '사업장 선택',
                      style: ResponsiveHelper.subtitleStyle(ctx)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                    visualDensity: VisualDensity.compact,
                    color: AppColors.grey600,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.grey200),
            // 목록
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: allItems.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.grey100),
                itemBuilder: (_, i) {
                  final biz = allItems[i];
                  final isSelected = biz == null
                      ? _filterBusinessId == null
                      : _filterBusinessId == biz.id;
                  return InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      if (!mounted) return;
                      setState(() => _filterBusinessId = biz?.id);
                      _loadStats();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 13),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              biz?.name ?? '전체 사업장',
                              style: ResponsiveHelper.bodyStyle(ctx,
                                      color: isSelected
                                          ? Theme.of(ctx).primaryColor
                                          : AppColors.textPrimary)
                                  .copyWith(
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal),
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check,
                                color: Theme.of(ctx).primaryColor, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Future<void> _openMonthDetail(int month) async {
    if (!mounted || widget.businessIds.isEmpty) return;
    var corrected = false;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminMonthDetailScreen(
          onCorrected: () => corrected = true,
          businessIds: widget.businessIds,
          filterBusinessId: _filterBusinessId,
          year: _selectedYear,
          month: month,
          businesses: _businesses,
          service: widget.service,
          debugOpenAttendance: widget.debugOpenAttendance,
        ),
      ),
    );
    if (mounted && corrected) await _loadStats(quiet: true);
  }

  // ─── [STATS-TO-ATTENDANCE.27] 숫자 → 그 근무들 ──────────────────────

  String get _scopeName => _filterBusinessId == null || _businesses.isEmpty
      ? (_businesses.length == 1 ? _businesses.first.name : '전체 사업장')
      : _businesses
          .firstWhere((b) => b.id == _filterBusinessId,
              orElse: () => _businesses.first)
          .name;

  Future<void> _openList({
    required String title,
    required String scope,
    required int? month,
    required bool Function(AttendanceModel r) matches,
    bool resultOnly = false,
  }) async {
    // 연 · 사업장을 지금 선택 그대로 고정한다 — 목록이 열린 사이 선택이 바뀌어도 섞이지 않는다.
    final filter = _filterBusinessId;
    final year = _selectedYear;
    var corrected = false;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => StatsAttendanceListScreen(
          onCorrected: () => corrected = true,
          title: title,
          scopeLabel: scope,
          load: () => _service.getAttendanceSnapshot(
            businessIds: widget.businessIds,
            filterBusinessId: filter,
            year: year,
            month: month,
          ),
          matches: matches,
          resultOnly: resultOnly,
          debugOpenAttendance: widget.debugOpenAttendance,
        ),
      ),
    );
    if (mounted && corrected) await _loadStats(quiet: true);
  }

  void _openUnconfirmed() => _openList(
        title: '근태 확인 필요 내역',
        scope: '$_selectedYear년 전체 · $_scopeName',
        month: null,
        matches: (r) =>
            AdminStatsService.bucketOf(r) == StatsAttendanceBucket.unconfirmed,
      );

  void _openException(WorkerException e, int month) => _openList(
        title: '지각·결근 내역',
        scope: '$_selectedYear년 $month월 · $_scopeName · ${e.userName}',
        month: month,
        // 이 칸의 집계식 그대로 — 지각, 결근(노쇼 포함).
        matches: (r) {
          if (r.userId != e.userId) return false;
          final b = AdminStatsService.bucketOf(r);
          return b == StatsAttendanceBucket.late || b == StatsAttendanceBucket.absent;
        },
        resultOnly: true,
      );

  // ─── 빌드 ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // [DESIGN-PATCH-3] GradientScaffold → AppPageScaffold — 관리자 통계 화면 flat admin 정렬
    // headerContent(interactive filter) → body 상단 persistent filter로 이동
    // loading/error/empty 상태에서도 filter 접근 가능하도록 Column([header, Expanded(body)])
    return AppPageScaffold(
      title: '통계',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loadStats,
          color: AppColors.textSecondary,
        ),
        IconButton(
          icon: const Icon(Icons.home_outlined),
          onPressed: () => NavigationHelper.goHome(context),
          color: AppColors.textSecondary,
        ),
        NotificationBadge(
          child: IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
            color: AppColors.textSecondary,
          ),
        ),
      ],
      body: Column(
        children: [
          _buildHeader(theme),
          Expanded(
            child: _isLoading
                ? const LoadingWidget(message: '통계 불러오는 중...')
                : RefreshIndicator(
                    onRefresh: _loadStats,
                    child: _buildContent(),
                  ),
          ),
        ],
      ),
    );
  }

  // ─── 헤더 (사업장 선택 + 연도) ───────────────────────────────

  Widget _buildHeader(ThemeData theme) {
    final now = _buildNow;
    return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 사업장 선택 — 1개면 숨김, 2개 이상이면 드롭다운
          if (_businesses.length > 1)
            Padding(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 8),
                ResponsiveHelper.spacing(context, 16),
                0,
              ),
              child: GestureDetector(
                onTap: () => _showBizPicker(),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 14),
                    vertical: ResponsiveHelper.spacing(context, 9),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.grey100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.business_outlined,
                          color: AppColors.textSecondary,
                          size: ResponsiveHelper.iconSize(context, 16)),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Flexible(
                        child: Text(
                          // _businesses.isEmpty 체크가 단락 평가되므로
                          // orElse의 _businesses.first는 리스트가 비어있을 때 도달 불가 — 안전
                          _filterBusinessId == null || _businesses.isEmpty
                              ? '전체 사업장'
                              : _businesses
                                  .firstWhere((b) => b.id == _filterBusinessId,
                                      orElse: () => _businesses.first)
                                  .name,
                          style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textSecondary,
                          size: ResponsiveHelper.iconSize(context, 18)),
                    ],
                  ),
                ),
              ),
            ),

          // 연도 선택
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ArrowBtn(
                  icon: Icons.chevron_left,
                  onTap: _isFetching ? null : () {
                    setState(() => _selectedYear--);
                    _loadStats();
                  },
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 20)),
                  child: Text(
                    '$_selectedYear년',
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                  ),
                ),
                _ArrowBtn(
                  icon: Icons.chevron_right,
                  onTap: (_isFetching || _selectedYear >= now.year)
                      ? null
                      : () {
                          setState(() => _selectedYear++);
                          _loadStats();
                        },
                ),
              ],
            ),
          ),
        ],
    );
  }

  // ─── 메인 콘텐츠 ─────────────────────────────────────────────

  Widget _buildContent() {
    if (_access != PermissionCheck.allowed) {
      return AppEmptyState(
        icon: Icons.lock_outline,
        title: AdminStatsAccess.title(_access),
        subtitle: AdminStatsAccess.subtitle(_access),
      );
    }
    final data = _data;
    if (data == null) return _buildEmpty();

    // [SECURITY-ADMIN-STATS-ATTENDANCE-COMPLETENESS 2026-09-05]
    // A: UNAVAILABLE — callable 실패 / limitReached / envelope 오류 / 행 파싱 실패
    // B: AVAILABLE + 0 records — 정상 응답, 해당 연도 출근 기록 없음
    // C: AVAILABLE + data — 정상 집계
    final attUnavailable =
        data.attendanceStatsState == AttendanceStatsState.unavailable;
    final hasAnyData = !attUnavailable && data.totalWorkCount > 0;

    return ListView(
      padding: ResponsiveHelper.listPadding(context),
      children: [
        if (_staleAfterChange) ...[
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 12),
                vertical: ResponsiveHelper.spacing(context, 8)),
            // [DU579] 정정 전 숫자 띠 = 흰 면 + 기존 선(grey200) + warningDark 글(판정141 R1 (b) — 8% 면 4.42 → 흰 면 5.24) · 문구 · 다시 조회 그대로.
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.grey200),
            ),
            child: Row(children: [
              Expanded(
                child: Text('최신 집계를 불러오지 못했어요. 아래 숫자는 정정 전 기준이에요.',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark)),
              ),
              TextButton(
                onPressed: _isFetching ? null : () => _loadStats(quiet: true),
                child: const Text('다시 조회'),
              ),
            ]),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        ],
        // A: 출근 데이터 조회 실패 배너
        if (attUnavailable) ...[
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
            // [DU546] 조회 실패 띠 = 흰 면 · grey200 선(같은 화면 예외 카드 짝) + 글 errorDark(월 상세 DU426 같은 뜻) · 아이콘 error 그대로
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.grey200),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_off_outlined,
                    color: AppColors.error,
                    size: ResponsiveHelper.iconSize(context, 18)),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                // [DU579] B(320·2.0) 오른쪽 127px 넘침(판정141 F141) — 남은 폭에서 낱말 사이로만 줄을 바꾼다(읽는 이름 원문).
                Expanded(
                  child: Text(TextLayout.keepWords('출근 데이터를 불러올 수 없습니다'),
                      semanticsLabel: '출근 데이터를 불러올 수 없습니다',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.errorDark)),
                ),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
        ]
        // B: 정상 응답 + 해당 연도 데이터 없음
        else if (!hasAnyData) ...[
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
            decoration: BoxDecoration(
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // [DU546] 데이터 없음 띠 — 아이콘 grey600 · 글 textSecondary(grey100 위 4.23 → 5.43 · 월 상세 DU426 같은 뜻의 글과 같다)
                Icon(Icons.info_outline,
                    color: AppColors.grey600,
                    size: ResponsiveHelper.iconSize(context, 18)),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                // [DU579] B 오른쪽 104px 넘침(판정141 F141) — 위 조회 실패 띠와 같이 남은 폭 · 낱말 사이 줄바꿈(읽는 이름 원문).
                Expanded(
                  child: Text(TextLayout.keepWords('$_selectedYear년 근태 데이터가 없습니다'),
                      semanticsLabel: '$_selectedYear년 근태 데이터가 없습니다',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.textSecondary)),
                ),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
        ],

        // KPI — 출근 셀은 attUnavailable 시 '확인 불가', 리뷰는 독립 표시
        _buildKpiSection(data),
        SizedBox(height: ResponsiveHelper.spacing(context, 14)),

        // 예외 알림 — 출근 데이터 필요, unavailable 시 숨김
        if (!attUnavailable && data.exceptions.isNotEmpty) ...[
          _buildExceptionSection(data),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
        ],

        // 업무별 인건비 — unavailable 시 wageByWorkType 비어 있어 auto-hidden
        _buildWorkTypeWageSection(data),
        SizedBox(height: ResponsiveHelper.spacing(context, 14)),

        // 월별 차트 — unavailable 시 '조회 실패' 표시
        _buildAnnualChart(data),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),

        if (hasAnyData)
          Center(
            child: Text(
              '막대를 탭하면 해당 월 상세 보기',
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.textTertiary), // [DU329] 보조 안내
            ),
          ),
        SizedBox(height: ResponsiveHelper.spacing(context, 14)),

        // 신뢰점수 분포
        if (data.workerTrustScores.isNotEmpty) ...[
          _buildTrustScoreSection(data),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
        ],

        SizedBox(height: ResponsiveHelper.spacing(context, 32)),
      ],
    );
  }

  // ─── KPI: Hero + 보조 그리드 ────────────────────────────────

  Widget _buildKpiSection(AnnualStatsData data) {
    final theme = Theme.of(context);
    // [SECURITY-ADMIN-STATS-ATTENDANCE-COMPLETENESS 2026-09-05]
    final attOk =
        data.attendanceStatsState == AttendanceStatsState.available;
    final prevAttOk =
        data.prevAttendanceStatsState == AttendanceStatsState.available;
    final hasPrevWage = data.prevYearTotalWage > 0;
    final hasPrevCount = data.prevYearTotalWorkCount > 0;
    final hasPrevAtt = data.prevYearAttendanceRate > 0;
    final hasPrevNoShow = data.prevYearNoShowRate > 0;
    // [UNKNOWN-ATTENDANCE] status 를 확인할 수 없는 근태가 있으면 비율을 숫자로 말하지 않는다 —
    //   분자에 넣지도, 분모에서 조용히 빼지도 않고 건수와 함께 '확인 필요'로 둔다. 어느 해든 있으면 전년 대비도 없다.
    final unconfirmed = data.unconfirmedAttendanceCount;
    final rateComparable = unconfirmed == 0 && data.prevUnconfirmedAttendanceCount == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Hero: 총 인건비 (관리자가 가장 먼저 보는 숫자)
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            ResponsiveHelper.spacing(context, 18),
            ResponsiveHelper.spacing(context, 16),
            ResponsiveHelper.spacing(context, 18),
            ResponsiveHelper.spacing(context, 16),
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // [R7-P1-7 후속 P17-S] 세 조각이 flex 없이 서 있어서 큰 글자·좁은 폭
              //   에서 가로로 넘쳤다(320dp·배율 1.3 에서 53px). 금액 머리말이라
              //   글자를 줄이지 않고, 모자라면 **기간 라벨부터** 줄인다.
              // [STATS-TO-ATTENDANCE.27] 라벨을 '…' 로 자르지 않는다 — 모자라면 기간 묶음이 다음 줄로 간다.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: ResponsiveHelper.spacing(context, 8),
                runSpacing: ResponsiveHelper.spacing(context, 2),
                children: [
                  Text('총 인건비',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.textSecondary)), // [DU329] 지표 제목
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: ResponsiveHelper.spacing(context, 6),
                    runSpacing: ResponsiveHelper.spacing(context, 2),
                    children: [
                    Text(
                      '$_selectedYear년 전체',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.textTertiary), // [DU329] 집계 범위
                    ),
                    // [DU579] 금액 증감 = 중립 화살표 · 글(판정141 R4 (b) — 비용 증가를 '좋음' 초록으로 칠하지 않는다 · 부호/문구/단위 그대로).
                    if (attOk && prevAttOk && hasPrevWage && data.wageDeltaPct != 0)
                      _DeltaBadge(delta: data.wageDeltaPct, neutral: true),
                  ]),
                ],
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 6)),
              Text(
                // [ADMIN-STATS-CLOSEOUT] 확정 근무가 있는데 합이 0원이면 '0원'(노쇼 확정 등) — '-' 는 확정 근무 0건일 때만.
                attOk
                    ? (data.totalWage == 0 && data.totalWorkCount > 0
                        ? '0원'
                        : _fmtWage(data.totalWage))
                    : '확인 불가',
                style: TextStyle(
                  fontSize: ResponsiveHelper.titleStyle(context).fontSize! * 1.6,
                  fontWeight: FontWeight.w800,
                  color: attOk ? theme.primaryColor : AppColors.textTertiary, // [DU329] '확인 불가' 큰 값
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 8)),

        // ── 보조 그리드: 근무건수 · 출근율 · 노쇼율 · 재고용
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10, offset: const Offset(0, 2))],
          ),
          // [STATS-TO-ATTENDANCE.27-T1] 네 칸 한 줄은 좁은 폭·큰 글자에서 칸마다 라벨이 세 줄로 갈렸다 —
          //   글자를 줄이지 않고, 칸이 좁으면 2×2 로 바꾼다(글자 배율을 곱해 판정, 큰 글자는 더 일찍).
          child: LayoutBuilder(builder: (context, c) {
            final cells = <Widget>[
                Expanded(child: _StatCell(
                  // [ADMIN-STATS-CLOSEOUT] 값은 급여 확정·이체 근무(MED-STAT) — 월 막대의 '전체 근태'와 단위가 다르다.
                  label: '급여 확정 근무',
                  value: attOk ? '${data.totalWorkCount}건' : '확인 불가',
                  valueColor: attOk ? AppColors.grey900 : AppColors.textTertiary, // [DU329] '확인 불가' 값
                  delta: (attOk && prevAttOk && hasPrevCount)
                      ? data.workCountDeltaPct
                      : null,
                  deltaNeutral: true, // [DU579] 건수 증감 = 중립(판정141 R4 (b))
                )),
                Expanded(child: _StatCell(
                  key: const ValueKey('annual-unconfirmed-att'),
                  onTap: attOk && unconfirmed > 0 ? _openUnconfirmed : null,
                  label: '출근율',
                  value: attOk
                      // [ADMIN-STATS-CLOSEOUT] 분모가 있으면 0% 도 값이다 — '-' 는 근태가 0건일 때만.
                      ? (data.attendanceRecordCount == 0
                          ? '-'
                          : unconfirmed > 0
                              ? '확인 필요'
                              : '${data.attendanceRate.toStringAsFixed(1)}%')
                      : '확인 불가',
                  valueColor: attOk
                      ? (unconfirmed > 0 ? AppColors.purple : AppColors.textPrimary) // [DU546] 출근율 = 일반 숫자 중립(DU536 J5 · DU541 B)
                      : AppColors.textTertiary, // [DU329] 출근율 '확인 불가' 값
                  subValue: attOk && unconfirmed > 0 ? '미확인 $unconfirmed건 ›' : null,
                  subValueColor: AppColors.purple,
                  delta: (attOk && prevAttOk && hasPrevAtt && rateComparable)
                      ? data.attendanceRate - data.prevYearAttendanceRate
                      : null,
                )),
                Expanded(child: _StatCell(
                  key: const ValueKey('annual-unconfirmed-noshow'),
                  onTap: attOk && unconfirmed > 0 ? _openUnconfirmed : null,
                  label: '노쇼율',
                  value: attOk
                      ? (data.attendanceRecordCount == 0
                          ? '-'
                          : unconfirmed > 0
                              ? '확인 필요'
                              : '${data.noShowRate.toStringAsFixed(1)}%')
                      : '확인 불가',
                  valueColor: attOk
                      ? (unconfirmed > 0
                          ? AppColors.purple
                          : data.noShowRate > 0
                              ? AppColors.errorDark // [DU546] 노쇼율 양수 = 위험 숫자 진한 짝(DU541 B)
                              : AppColors.textTertiary) // [DU329] 노쇼율 0 값
                      : AppColors.textTertiary, // [DU329] 노쇼율 '확인 불가' 값
                  subValue: attOk && unconfirmed > 0 ? '미확인 $unconfirmed건 ›' : null,
                  subValueColor: AppColors.purple,
                  delta: (attOk && prevAttOk && hasPrevNoShow && rateComparable)
                      ? -(data.noShowRate - data.prevYearNoShowRate)
                      : null,
                )),
                Expanded(child: _StatCell(
                  label: '재고용률',
                  // [SECURITY-ADMIN-REVIEW-STATS-AGGREGATE 2026-09-05]
                  // NO_DATA / SUPPRESSED / UNAVAILABLE / AVAILABLE 명시적 구분
                  value: switch (data.reviewStatsState) {
                    ReviewStatsState.available =>
                        data.rehireRate == 0 ? '-' : '${data.rehireRate.toStringAsFixed(0)}%',
                    ReviewStatsState.noData => '-',
                    ReviewStatsState.suppressed => '표본 부족',
                    ReviewStatsState.unavailable => '확인 불가',
                  },
                  valueColor: data.reviewStatsState == ReviewStatsState.available ? AppColors.textPrimary : AppColors.textTertiary, // [DU546] 감사138 R2
                  subValue: data.reviewStatsState == ReviewStatsState.available && data.avgRating > 0
                      ? '★ ${data.avgRating.toStringAsFixed(1)}' : null,
                )),
            ];
            Widget row(List<Widget> cs) => IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < cs.length; i++) ...[if (i > 0) _VLine(), cs[i]],
                  ]),
                );
            if (TextLayout.fits(context, c.maxWidth, _StatCell.minCellWidth * 4)) return row(cells);
            return Column(children: [
              row(cells.sublist(0, 2)),
              const Divider(height: 1, color: AppColors.grey100),
              row(cells.sublist(2)),
            ]);
          }),
        ),
      ],
    );
  }

  // ─── 예외 알림 ────────────────────────────────────────────

  Widget _buildExceptionSection(AnnualStatsData data) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      // [STATS-TO-ATTENDANCE.27] '주의 직원' 은 근태 사건을 사람 평가처럼 읽히게 했다 — 같은 집계
      //   (지각 2회 이상 또는 결근·노쇼 1회 이상)를 사실 중심 제목으로 두고, 경고 색을 뺀다.
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_note_outlined,
                  color: AppColors.grey600,
                  size: ResponsiveHelper.iconSize(context, 16)),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Flexible(
                child: Text(
                  '${data.exceptionMonth}월 지각·결근 내역',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                      color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 2)),
          Text('지각 2회 이상 또는 결근·노쇼가 있는 근로자',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary)), // [DU329] 설명
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          ...data.exceptions
              .where((e) =>
                  e.userName.isNotEmpty && e.userName != '알 수 없음')
              .take(3)
              .map((e) => InkWell(
                key: ValueKey('exception-row-${e.userId}'),
                onTap: () => _openException(e, data.exceptionMonth),
                child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.userName,
                        style: ResponsiveHelper.smallStyle(context),
                      ),
                    ),
                    // [DU546] 지각 · 결근 배지 = 월 상세 DU427 과 같은 짝(결근은 관리자 쪽 error 계열 그대로 · DU544 판정 요청 3)
                    if (e.lateCount > 0)
                      _ExBadge(
                          label: '지각 ${e.lateCount}회',
                          color: AppColors.warningDark, bg: AppColors.warningBg),
                    if (e.absentCount > 0) ...[
                      SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                      _ExBadge(
                          label: '결근 ${e.absentCount}회',
                          color: AppColors.errorDark, bg: AppColors.errorBg),
                    ],
                    Icon(Icons.chevron_right,
                        size: ResponsiveHelper.iconSize(context, 16),
                        color: AppColors.grey600), // [DU329] 이동 표시
                  ],
                ),
                ),
              )),
        ],
      ),
    );
  }

  // ─── 연간 바 차트 ────────────────────────────────────────

  Widget _buildAnnualChart(AnnualStatsData data) {
    final theme = Theme.of(context);
    final trends = data.monthlyTrends;
    final maxWage = trends.map((t) => t.totalWage).fold(0, (a, b) => a > b ? a : b);
    // _buildNow 는 build() 진입 시 한 번 캡처 — getTitlesWidget·barGroups·workCount Row 에서 재사용
    final nowMonth = _buildNow.month;
    final isCurrentYear = _selectedYear == _buildNow.year;

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [R7-P1-7 후속 P17-S] 제목과 범례가 flex 없이 한 줄에 있어 배율 2.0 에서
          //   가로로 넘쳤다 — 범례를 지우지 않고 제목부터 줄인다.
          // [STATS-TO-ATTENDANCE.27] 제목이 범례와 한 줄을 나눠 '월별 …' 로 잘렸다 — 제목은 자르지 않고,
          //   모자라면 범례가 다음 줄로 간다.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: ResponsiveHelper.spacing(context, 8),
            runSpacing: ResponsiveHelper.spacing(context, 4),
            children: [
              Text(
                '월별 인건비',
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              // 범례
              Wrap(spacing: ResponsiveHelper.spacing(context, 8), children: [
                _LegendDot(color: theme.primaryColor, label: '이달'),
                _LegendDot(
                    color: theme.primaryColor.withValues(alpha: 0.3),
                    label: '기타'),
              ]),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ValueListenableBuilder<int>(
            valueListenable: _touchedBarIndex,
            builder: (context, touchedIdx, _) => SizedBox(
              height: 180,
              child: data.attendanceStatsState == AttendanceStatsState.unavailable
                  ? Center(
                      child: Text('조회 실패',
                          style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.textSecondary)), // [DU329] 조회 실패 안내
                    )
                  : maxWage == 0
                  ? Center(
                      child: Text('데이터 없음',
                          style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.textTertiary)), // [DU329] 데이터 없음
                    )
                  : RepaintBoundary(
                      child: BarChart(
                        BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: maxWage * 1.3,
                        barTouchData: BarTouchData(
                          touchCallback: (event, response) {
                            final spot = response?.spot;
                            if (event is FlTapUpEvent && spot != null) {
                              final idx = spot.touchedBarGroupIndex;
                              _touchedBarIndex.value = idx;
                              _openMonthDetail(idx + 1);
                            } else {
                              _touchedBarIndex.value = -1;
                            }
                          },
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, gi, rod, ri) {
                              final t = trends[gi];
                              if (t.totalWage == 0) return null;
                              return BarTooltipItem(
                                '${t.month}월\n${_fmtWage(t.totalWage)}\n전체 근태 ${t.workCount}건',
                                ResponsiveHelper.tinyStyle(context)
                                    .copyWith(color: Colors.white),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 22,
                              getTitlesWidget: (v, _) {
                                final idx = v.toInt();
                                if (idx < 0 || idx >= 12) {
                                  return const SizedBox();
                                }
                                final m = idx + 1;
                                final isCurrent = m == nowMonth && isCurrentYear;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '$m',
                                    style: ResponsiveHelper.tinyStyle(context)
                                        .copyWith(
                                      color: isCurrent
                                          ? theme.primaryColor
                                          : AppColors.textTertiary, // [DU329] 월 축 글자
                                      fontWeight: isCurrent
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        gridData: FlGridData(
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => const FlLine(
                              color: AppColors.grey100, strokeWidth: 1),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: trends.asMap().entries.map((e) {
                          final isCurrent =
                              e.value.month == nowMonth && isCurrentYear;
                          final isTouched = touchedIdx == e.key;
                          return BarChartGroupData(
                            x: e.key,
                            barRods: [
                              BarChartRodData(
                                toY: e.value.totalWage.toDouble(),
                                color: isTouched
                                    ? theme.primaryColor
                                        .withValues(alpha: 0.85)
                                    : isCurrent
                                        ? theme.primaryColor
                                        : theme.primaryColor
                                            .withValues(alpha: 0.3),
                                width: 18,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
            ),
          ),
          // 근무 건수 서브 행 — [ADMIN-STATS-CLOSEOUT] 그 달 **전체 근태** 건수다(급여 확정만이 아니다).
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text('전체 근태 (건)',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary)), // [DU329] 하위 행 제목
          SizedBox(height: ResponsiveHelper.spacing(context, 2)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: trends.map((t) {
              final isCurrent = t.month == nowMonth && isCurrentYear;
              return Text(
                t.workCount > 0 ? '${t.workCount}' : '',
                textAlign: TextAlign.center,
                style: ResponsiveHelper.tinyStyle(context).copyWith(
                  color: isCurrent
                      ? theme.primaryColor
                      : AppColors.textTertiary, // [DU329] 월 축 수치
                  fontWeight: isCurrent
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkTypeWageSection(AnnualStatsData data) {
    final map = data.wageByWorkType;
    final filtered = map.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (filtered.isEmpty) return const SizedBox.shrink();

    final maxWage = filtered.fold(0, (a, b) => a > b.value ? a : b.value);
    final colors = [AppColors.info, AppColors.success, AppColors.warning, AppColors.purple, AppColors.error];

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('업무별 인건비',
              style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold)),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
          ...filtered.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            final ratio = maxWage == 0 ? 0.0 : e.value / maxWage;
            final color = colors[i % colors.length];
            return Padding(
              padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(e.key,
                          style: ResponsiveHelper.smallStyle(context),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                    // [DU579] 금액 글 = textPrimary(판정141 R2 (a) — 계열색 글 2.16–3.68 보완) · 막대 계열/순서 그대로.
                    Text(_fmtWage(e.value),
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary)
                            .copyWith(fontWeight: FontWeight.w600)),
                  ]),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: AppColors.grey100,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTrustScoreSection(AnnualStatsData data) {
    final scores = data.workerTrustScores.values.toList();
    if (scores.isEmpty) return const SizedBox.shrink();

    // 등급별 인원 집계
    int excellent = 0, good = 0, average = 0, caution = 0, warning = 0;
    for (final s in scores) {
      if (s >= 90) { excellent++; }
      else if (s >= 70) { good++; }
      else if (s >= 50) { average++; }
      else if (s >= 30) { caution++; }
      else { warning++; }
    }
    final total = scores.length;
    final avgScore = total == 0 ? 0 : (scores.reduce((a, b) => a + b) / total).round();

    final grades = [
      ('최우수', excellent, AppColors.success, '90~100'),
      ('우수',   good,      AppColors.info,    '70~89'),
      ('보통',   average,   AppColors.warning,  '50~69'),
      ('주의',   caution,   AppColors.error,    '30~49'),
      ('경고',   warning,   AppColors.grey500,  '0~29'),
    ].where((g) => g.$2 > 0).toList();

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [DU579] B(320·2.0) 오른쪽 160px 넘침(판정141 F141) — 같은 화면 월별 인건비 머리(STATS-TO-ATTENDANCE.27)와 같이 모자라면 평균이 다음 줄로 간다.
          //   제목은 낱말 사이에서만 줄을 바꾼다(읽는 이름 원문 · _StatCell 라벨과 같은 꼴).
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: ResponsiveHelper.spacing(context, 8),
            runSpacing: ResponsiveHelper.spacing(context, 4),
            children: [
            Text(TextLayout.keepWords('근로자 신뢰점수 분포'),
                semanticsLabel: '근로자 신뢰점수 분포',
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(fontWeight: FontWeight.bold)),
            Text('평균 $avgScore점 · $total명',
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.textSecondary)), // [DU329] 평균 요약
          ]),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
          ...grades.map((g) {
            final ratio = total == 0 ? 0.0 : g.$2 / total;
            return Padding(
              padding: EdgeInsets.only(
                  bottom: ResponsiveHelper.spacing(context, 10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    SizedBox(
                      width: ResponsiveHelper.spacing(context, 48),
                      child: Text(g.$1,
                          style: ResponsiveHelper.smallStyle(context)),
                    ),
                    Text(g.$4,
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.textTertiary)), // [DU329] 점수 범위
                    const Spacer(),
                    // [DU579] 인원수 글 = textPrimary(판정141 R3 (a) — 회색 '경고' 2.68 포함) · 등급/문턱/막대 그대로.
                    Text('${g.$2}명 (${(ratio * 100).round()}%)',
                        style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.textPrimary)
                            .copyWith(fontWeight: FontWeight.w600)),
                  ]),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: AppColors.grey100,
                    valueColor: AlwaysStoppedAnimation<Color>(g.$3),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    if (_hasError) {
      // [DU333] 실패 본문에 보이는 '다시 시도'(소급 5 채택 — S079 · S006 과 같은 outlined). 당겨서 새로고침 · AppBar 새로고침은 그대로.
      return AppEmptyState(
        icon: Icons.cloud_off_outlined,
        title: '통계를 불러오지 못했습니다',
        subtitle: '네트워크 상태를 확인 후 당겨서 새로고침하세요',
        subtitleColor: AppColors.textSecondary,
        action: OutlinedButton.icon(
          onPressed: () => unawaited(_loadStats()),
          icon: const Icon(Icons.refresh),
          label: const Text('다시 시도'),
        ),
      );
    }
    return AppEmptyState(
      icon: Icons.bar_chart_outlined,
      title: '$_selectedYear년 데이터가 없습니다',
    );
  }

  // ─── 유틸 ─────────────────────────────────────────────────

  String _fmtWage(int wage) {
    if (wage == 0) return '-';
    if (wage >= 100000000) return '${(wage / 100000000).toStringAsFixed(1)}억';
    if (wage >= 10000000) return '${(wage / 10000000).toStringAsFixed(1)}천만';
    if (wage >= 1000000) return '${wage ~/ 10000}만';
    return '${wage ~/ 1000}천';
  }
}

// ─── 서브 위젯 ────────────────────────────────────────────────

class _ArrowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _ArrowBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
        decoration: BoxDecoration(
          color: onTap == null ? AppColors.grey100 : AppColors.grey200,
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            color: onTap == null ? AppColors.grey300 : AppColors.textSecondary,
            size: ResponsiveHelper.iconSize(context, 20)),
      ),
    );
  }
}

// ── 보조 통계 셀 (라벨 위, 숫자 아래) ──────────────────────────
class _StatCell extends StatelessWidget {
  /// [STATS-TO-ATTENDANCE.27-T1] 라벨('급여 확정'·'재고용률')이 낱말 안에서 갈리지 않을 칸 폭(글자 배율 1.0, 논리 px).
  static const double minCellWidth = 76;

  /// [STATS-TO-ATTENDANCE.27] '미확인 N건' 이 있을 때 그 근무 내역을 연다.
  final VoidCallback? onTap;
  final String label;
  final String value;
  final Color valueColor;
  final double? delta;
  final bool deltaNeutral; // [DU579] 전년 대비 칩 중립(금액 · 건수 — 판정141 R4 (b))
  final String? subValue;
  final Color subValueColor;

  const _StatCell({
    super.key,
    this.onTap,
    required this.label,
    required this.value,
    required this.valueColor,
    this.delta,
    this.deltaNeutral = false,
    this.subValue,
    this.subValueColor = AppColors.grey600, // [DU546] 기본값 사용처 = 재고용률 별점 하나(감사138 R4)
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 라벨 먼저 (작게, 회색)
          // [STATS-TO-ATTENDANCE.27] 한글은 글자 단위로 줄이 바뀌어 '급여 확정 근' / '무' 로 갈렸다 —
          //   낱말 사이에서만 바뀌게 붙임 문자를 넣는다(글자를 줄이거나 자르지 않는다).
          Text(TextLayout.keepWords(label),
              semanticsLabel: label,
              textAlign: TextAlign.center,
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.textTertiary)), // [DU329] 지표 라벨
          SizedBox(height: ResponsiveHelper.spacing(context, 5)),
          // 숫자가 주인공 (크게, 컬러)
          // [STATS-TO-ATTENDANCE.27-T1] '확…' 로 잘려 값을 읽을 수 없었다 — 자르지도 줄이지도 않는다.
          //   칸이 좁으면 위에서 2×2 로 넓힌다.
          Text(value,
              textAlign: TextAlign.center,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.w800, color: valueColor)),
          // 별점 등 부가정보
          if (subValue != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 2)),
            // [UNKNOWN-ATTENDANCE] '근태 확인 필요 N건' 은 좁은 칸에서 줄바꿈된다 — 건수를 자르지 않는다.
            Text(subValue!,
                textAlign: TextAlign.center,
                style: ResponsiveHelper.tinyStyle(context,
                    color: subValueColor,
                    fontWeight: FontWeight.w600)),
          ],
          // delta (있을 때만)
          if (delta != null && delta != 0) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 3)),
            _DeltaBadge(delta: delta!, neutral: deltaNeutral),
          ],
        ],
      ),
      ),
    );
  }

}

// ── 구분선 ───────────────────────────────────────────────────────
class _VLine extends StatelessWidget {
  const _VLine();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, color: AppColors.grey100);
}

class _DeltaBadge extends StatelessWidget {
  final double delta;
  final bool neutral; // [DU579] 금액 · 건수 증감 — 좋음/나쁨 색을 붙이지 않는다(판정141 R4 (b))
  const _DeltaBadge({required this.delta, this.neutral = false});

  @override
  Widget build(BuildContext context) {
    final isPos = delta > 0;
    // [DU546] 전년 대비 칩 = StatusBadge 짝(옅은 면 + 진한 글/화살표) — 오름 success · 내림 error 계열 그대로(뜻 판정은 R4)
    // [DU579] 중립(금액 · 건수) = StatusBadge.neutral 면 grey200 + textSecondary 화살표 · 글(5.10) — 비율(출근율 · 노쇼율)은 위 짝 그대로(판정141 R4).
    final color = neutral ? AppColors.textSecondary : isPos ? AppColors.successDark : AppColors.errorDark;
    final bg = neutral ? AppColors.grey200 : isPos ? AppColors.successBg : AppColors.errorBg;
    final icon = isPos ? Icons.arrow_upward : Icons.arrow_downward;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 5),
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      // [R7-P1-7 후속 P17-S] 부모가 좁아지면 배지 안에서 다시 넘쳤다 —
      //   숫자를 줄이지 않고 배지가 줄어들 수 있게 한다.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          Flexible(
            child: Text(
              '${delta.abs().toStringAsFixed(1)}%',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ResponsiveHelper.tinyStyle(context)
                  .copyWith(color: color, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg; // [DU546] 옅은 면(StatusBadge 짝) — color 는 진한 글
  const _ExBadge({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: ResponsiveHelper.tinyStyle(context)
              .copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        Text(label,
            style: ResponsiveHelper.tinyStyle(context,
                color: AppColors.textSecondary)), // [DU329] 범례
      ],
    );
  }
}

// ─── 진입점 ──────────────────────────────────────────────────

Future<void> pushAdminStatsScreen(BuildContext context) async {
  final userProvider = context.read<UserProvider>();
  final user = userProvider.currentUser;
  if (user == null) {
    ToastHelper.showWarning('로그인 정보를 불러올 수 없습니다');
    return;
  }
  // [ADMIN-STATS-WAGE-GATE 2026-09-04] SUB_ADMIN canManageWage 방어 게이트
  // Home visibility guard에서 1차 차단하나, helper에서 fail-closed 재검증.
  // BUSINESS_ADMIN(user.isSubAdmin == false)은 이 체크 통과.
  if (userProvider.checkCurrentBusiness((p) => p.canManageWage) != PermissionCheck.allowed) {
    ToastHelper.showWarning('급여 관리 권한이 없습니다.');
    return;
  }
  final ids = user.managedBusinessIds;
  // 다중 사업장 관리자
  if (ids.isNotEmpty) {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => AdminStatsScreen(businessIds: ids)));
    return;
  }
  // 단일 사업장: BUSINESS_ADMIN은 businessId, SubAdmin은 subAdminOf → effectiveBusinessId로 통합
  final effectiveBizId = userProvider.effectiveBusinessId;
  if (effectiveBizId != null) {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => AdminStatsScreen(businessIds: [effectiveBizId])));
    return;
  }
  ToastHelper.showWarning('등록된 사업장이 없습니다');
}
