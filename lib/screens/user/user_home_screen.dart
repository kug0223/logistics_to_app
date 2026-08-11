import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/fcm_service.dart';

import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/user_model.dart';
import '../../utils/format_helper.dart';
import '../../providers/user_provider.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/attendance_list_pdf.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/tour_helper.dart';
import '../../widgets/auth/account_status_banner.dart';
import '../../widgets/common/notification_badge.dart';
import '../../widgets/work_type_icon.dart';
import '../common/notification_screen.dart';
import '../common/settings_screen.dart';
import '../business_admin/business_admin_home_screen.dart';
import '../common/tour_screen.dart';
import 'all_to_list_screen.dart';
import 'attendance_check_screen.dart';
import 'my_applications_screen.dart';
import 'my_schedule_screen.dart';
import 'user_contracts_screen.dart';

// ── 이번 주 출근 예정 엔트리 ─────────────────────────────────────
class _WeekEntry {
  final ApplicationModel app;
  final DateTime date;
  const _WeekEntry({required this.app, required this.date});
}

// ── 지원자 홈 화면 ────────────────────────────────────────────────
class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen>
    with WidgetsBindingObserver {
  final _appFirestore = FirestoreService();
  List<ApplicationModel> _applications = [];
  List<AttendanceModel> _attendances = [];
  bool _isLoadingData = false;

  // 날짜 탭 시 주간 일정 섹션만 rebuild — setState 없이 처리
  late final ValueNotifier<DateTime> _selectedDayNotifier;

  // ── 초대 카운트 (INVITED 상태 지원서 수) ────────────────────────
  int get _invitedCount =>
      _applications.where((a) => a.status == AppStatus.invited).length;

  // ── 캐시 필드 — _applications/_attendances 변경 시에만 재계산 ────────
  // build 중 getter가 매번 재계산되던 비용 제거 (날짜 탭 시에도 불필요하게 실행됐음)
  int _cachedActualIncome = 0;
  int _cachedExpectedIncome = 0;
  Set<DateTime> _cachedThisWeekEntryDates = {};
  List<ApplicationModel> _cachedRecentApplications = [];

  void _rebuildCaches() {
    _cachedActualIncome = _attendances
        .where((a) => a.isWageConfirmed || a.isWageTransferred)
        .fold(0, (sum, a) => sum + (a.finalWage ?? 0));
    _cachedExpectedIncome = _attendances
        .fold(0, (sum, a) => sum + (a.wageDetail?.effectiveNetWage ?? 0));

    final sorted = [..._applications]
      ..sort((a, b) => b.workDate.compareTo(a.workDate));
    _cachedRecentApplications = sorted.take(3).toList();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDate = today.add(const Duration(days: 6));
    final dates = <DateTime>{};
    for (final app in _applications) {
      if (!AppStatus.confirmedStatuses.contains(app.status)) continue;
      if (!app.isLongTermApplication) {
        final wd = DateTime(app.workDate.year, app.workDate.month, app.workDate.day);
        if (!wd.isBefore(today) && !wd.isAfter(endDate)) dates.add(wd);
      } else {
        for (var d = today; !d.isAfter(endDate); d = d.add(const Duration(days: 1))) {
          if (app.isWorkingOnDate(d)) dates.add(d);
        }
      }
    }
    _cachedThisWeekEntryDates = dates;
  }

  // ── 이번 주 선택된 날의 출근 목록 ────────────────────────────────
  List<_WeekEntry> _entriesForDay(DateTime day) {
    final results = <_WeekEntry>[];
    for (final app in _applications) {
      if (!AppStatus.confirmedStatuses.contains(app.status)) continue;
      if (!app.isLongTermApplication) {
        final wd = DateTime(app.workDate.year, app.workDate.month, app.workDate.day);
        if (wd == day) results.add(_WeekEntry(app: app, date: wd));
      } else {
        if (app.isWorkingOnDate(day)) results.add(_WeekEntry(app: app, date: day));
      }
    }
    return results;
  }

  // ── 오른쪽 상태 텍스트 + 색상 (사용자가 가장 궁금한 정보) ──────────
  (String, Color) _statusAction(ApplicationModel app, ThemeData theme) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final workDay = DateTime(app.workDate.year, app.workDate.month, app.workDate.day);
    return switch (app.status) {
      AppStatus.pending         => ('검토 중',   AppColors.warning),
      AppStatus.contractPending => ('계약 대기', AppColors.info),
      AppStatus.confirmed       => workDay.isBefore(today)
          ? ('근무 완료', AppColors.success)
          : workDay == today
              ? ('오늘 출근!', theme.primaryColor)
              : ('출근 예정', theme.primaryColor),
      AppStatus.rejected        => ('거절됨',   AppColors.error),
      AppStatus.canceled        => ('취소됨',   AppColors.grey400),
      AppStatus.autoCanceled    => ('자동취소', AppColors.grey400),
      _                         => ('기타',     AppColors.grey400),
    };
  }


  late final VoidCallback _onFcmRefresh;
  bool _isLoadingHomeData = false;
  DateTime? _lastAutoRefreshAt;

  @override
  void initState() {
    super.initState();
    // [CRASH-7 수정] _selectedDayNotifier를 addObserver/addListener보다 먼저 초기화
    // addObserver 직후 dispose()가 호출되는 극단적 타이밍에 LateInitializationError 방지
    final now = DateTime.now();
    _selectedDayNotifier = ValueNotifier(DateTime(now.year, now.month, now.day));
    WidgetsBinding.instance.addObserver(this);
    _onFcmRefresh = () { if (mounted) _autoRefresh(); };
    FCMService().addUserDataRefreshListener(_onFcmRefresh);
    AttendanceListPdf.preloadFonts();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!await TourHelper.isCompleted(TourHelper.userHome)) {
        if (mounted) _showTourDialog();
      }
      _loadHomeData();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FCMService().removeUserDataRefreshListener(_onFcmRefresh);
    _selectedDayNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _autoRefresh();
  }

  void _autoRefresh() {
    final now = DateTime.now();
    if (_lastAutoRefreshAt != null &&
        now.difference(_lastAutoRefreshAt!) < const Duration(seconds: 30)) { return; }
    _lastAutoRefreshAt = now;
    _loadHomeData();
  }

  Future<void> _showTourDialog() async {
    await pushTourScreen(context, role: 'USER');
    if (!mounted) return;
    await TourHelper.markCompleted(TourHelper.userHome);
  }

  Future<void> _loadHomeData() async {
    if (_isLoadingHomeData) return; // 동시 실행 방어
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null || !mounted) return;
    _isLoadingHomeData = true;
    setState(() => _isLoadingData = true);
    final now = DateTime.now();
    try {
      final results = await Future.wait([
        _appFirestore.getMyApplications(uid),
        _appFirestore.getMyMonthlyAttendances(userId: uid, year: now.year, month: now.month),
      ]);
      if (!mounted) return;
      final apps = results[0] as List<ApplicationModel>;
      final atts = results[1] as List<AttendanceModel>;
      // 캐시는 setState 전에 계산 — build 중 재계산 없이 준비된 값 사용
      _applications = apps;
      _attendances  = atts;
      _rebuildCaches();
      setState(() => _isLoadingData = false);
    } catch (e) {
      debugPrint('❌ 홈 데이터 로드 실패: $e');
      if (mounted) {
        setState(() => _isLoadingData = false);
        ToastHelper.showError('데이터를 불러오지 못했습니다. 새로고침을 시도해주세요.');
      }
    } finally {
      _isLoadingHomeData = false;
    }
  }

  // ── 반응형 스케일: 화면 너비 기준 ──────────────────────────────
  double _s(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 360) return 0.82;
    if (w < 400) return 0.92;
    if (w < 480) return 1.0;
    return 1.08;
  }

  String _dayLabel(DateTime d) => ['월', '화', '수', '목', '금', '토', '일'][d.weekday - 1];

  @override
  Widget build(BuildContext context) {
    final s = _s(context);

    return Selector<UserProvider,
        ({UserModel? user, bool isAdminMode, bool isSubAdmin, bool permissionsLoaded})>(
      selector: (_, p) => (
        user: p.currentUser,
        isAdminMode: p.isAdminMode,
        isSubAdmin: p.isSubAdmin,
        permissionsLoaded: p.permissionsLoaded,
      ),
      builder: (context, data, _) {
        final up = context.read<UserProvider>();
        final theme = Theme.of(context);
        final user = data.user;

        return Scaffold(
          // SubAdmin은 미서명 계약서 배너 불필요 (hasPendingContract 항상 false)
          // + maintainSize:true 공간이 관리자 홈과 높이 차이를 만드므로 제외
          bottomNavigationBar: data.isSubAdmin ? null : const _PendingContractBar(),
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (user != null)
                  AccountStatusBanner(
                    accountStatus: user.accountStatus,
                    rejectedReason: user.rejectionReason,
                  ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.primaryColor,
                          Color.lerp(theme.primaryColor, theme.colorScheme.secondary, 0.65)!,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      top: false,    // 상단은 외부 SafeArea가 처리
                      bottom: false, // 하단은 흰 Container 내부 SafeArea(top:false)가 처리
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeader(context, s, user, up, theme),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              child: Container(
                                key: ValueKey(data.isAdminMode),
                                decoration: const BoxDecoration(
                                  color: AppColors.grey50,
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(28),
                                    topRight: Radius.circular(28),
                                  ),
                                ),
                                child: SafeArea(
                                  top: false,
                                  left: false,
                                  right: false,
                                  child: _buildUserBody(context, s, up, theme),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 헤더
  // ─────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, double s, UserModel? user,
      UserProvider up, ThemeData theme) {
    return Stack(
      children: [
        // 대형 장식 "A" 레터
        Positioned(
          right: 10 * s,
          top: -8 * s,
          child: Text(
            'A',
            style: TextStyle(
              fontSize: 110 * s,
              fontWeight: FontWeight.w900,
              color: Colors.white.withValues(alpha: 0.10),
              height: 1.0,
              letterSpacing: -4,
            ),
          ),
        ),
        // 보조 원형 장식
        Positioned(
          right: 28 * s, bottom: 20 * s,
          child: Container(
            width: 42 * s, height: 42 * s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ),
        // 콘텐츠
        Padding(
          padding: EdgeInsets.fromLTRB(20 * s, 12 * s, 20 * s, 10 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단 바 — 로고+브랜드명 | 알림+설정
              Row(
                children: [
                  ClipOval(
                    child: Image.asset(
                      'assets/icons/app_icon.png',
                      width: 26 * s, height: 26 * s,
                    ),
                  ),
                  SizedBox(width: 7 * s),
                  Text(
                    'ALfit',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18 * s,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  NotificationBadge(
                    child: _headerBtn(context, s, Icons.notifications_outlined, '알림',
                        () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const NotificationScreen()))),
                  ),
                  SizedBox(width: 8 * s),
                  _headerBtn(context, s, Icons.person_outline, '내 정보',
                      () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen()))),
                ],
              ),

              SizedBox(height: 10 * s),

              // 인사말 + 이름 + 배지 (세로 압축)
              Text(
                '안녕하세요,',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.80),
                  fontSize: 13 * s,
                ),
              ),
              SizedBox(height: 2 * s),

              // 이름 + 역할 배지 + 모드 토글
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      '${user?.name ?? '사용자'}님!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26 * s,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: 8 * s),
                  _buildRoleBadge(context, s, up),
                ],
              ),
              SizedBox(height: 4 * s),

              // 서브타이틀
              Text(
                up.isAdminMode
                    ? '오늘도 사업장을 스마트하게 관리해요'
                    : '오늘도 딱 맞는 일자리를 찾아드릴게요',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.60),
                  fontSize: 11.5 * s,
                ),
              ),

              SizedBox(height: 10 * s),

              // 신뢰점수 칩 + 모드 토글
              Row(
                children: [
                  if (user != null && !up.isAdminMode)
                    _buildTrustChip(context, s, user),
                  const Spacer(),
                  if (up.isSubAdmin) _buildModeToggle(context, s, up),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _headerBtn(BuildContext context, double s, IconData icon, String label,
      VoidCallback onTap) {
    return Semantics(
      label: label,
      button: true,
      child: Material(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.all(8 * s),
            child: Icon(icon, color: Colors.white, size: 22 * s),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleBadge(BuildContext context, double s, UserProvider up) {
    if (up.isAdminMode && up.isSubAdmin) {
      return _buildSubAdminBadge(context, s, up);
    }
    return _chipDecor(
      s,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.person_outline, color: Colors.white, size: 12 * s),
        SizedBox(width: 4 * s),
        Text('지원자',
            style: TextStyle(
                color: Colors.white, fontSize: 11 * s, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildTrustChip(BuildContext context, double s, UserModel user) {
    return _chipDecor(
      s,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('신뢰점수 ',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 12 * s)),
        Text('${user.trustScore}점',
            style: TextStyle(
                color: Colors.white,
                fontSize: 13 * s,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _chipDecor(double s, {required Widget child}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 11 * s, vertical: 6 * s),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1),
      ),
      child: child,
    );
  }

  // ── 모드 토글 (서브어드민 전용) ──────────────────────────────
  Widget _buildModeToggle(BuildContext context, double s, UserProvider up) {
    final isAdmin = up.isAdminMode;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _toggleOpt(context, s, label: '지원자', selected: !isAdmin,
            onTap: () { if (isAdmin) up.toggleAdminMode(); }),
        _toggleOpt(context, s, label: '관리자', selected: isAdmin,
            onTap: () { if (!isAdmin) _switchToAdminMode(context, up); }),
      ]),
    );
  }

  Widget _toggleOpt(BuildContext context, double s,
      {required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Theme.of(context).primaryColor
                : Colors.white.withValues(alpha: 0.85),
            fontSize: 12 * s,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSubAdminBadge(BuildContext context, double s, UserProvider up) {
    final bizIds = up.currentUser?.subAdminBusinessIds ?? [];
    final isMulti = bizIds.length > 1;
    final selId = up.selectedSubAdminBusinessId;
    final bizName = selId != null ? up.subAdminBusinessNames[selId] : null;

    final chip = _chipDecor(s,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.admin_panel_settings_outlined, color: Colors.white, size: 12 * s),
        SizedBox(width: 4 * s),
        Text(
          isMulti && bizName != null ? '$bizName ▼' : '하위관리자',
          style: TextStyle(color: Colors.white, fontSize: 11 * s, fontWeight: FontWeight.w600),
        ),
      ]),
    );

    if (!isMulti) return chip;
    return GestureDetector(onTap: () => _switchBusiness(context, up), child: chip);
  }

  // ─────────────────────────────────────────────────────────────
  // 지원자 바디 (스크롤)
  // ─────────────────────────────────────────────────────────────
  Widget _buildUserBody(BuildContext context, double s, UserProvider up, ThemeData theme) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(28),
        topRight: Radius.circular(28),
      ),
      child: RefreshIndicator(
        onRefresh: _loadHomeData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 22 * s),
              _buildOnboardingBanner(context, s, up),
              _buildMenuRow(context, s, theme),
              _buildInviteBanner(context, s, theme), // 초대 있으면 배너, 없으면 28px 간격
              _buildIncomeSection(context, s, theme),
              SizedBox(height: 24 * s),
              _buildRecentApplications(context, s, theme),
              SizedBox(height: 24 * s),
              _buildThisWeekSchedule(context, s, theme),
              SizedBox(height: 36 * s),
            ],
          ),
        ),
      ),
    );
  }

  // ── 초대 배너 (INVITED 있을 때만 표시) ─────────────────────────
  Widget _buildInviteBanner(BuildContext context, double s, ThemeData theme) {
    final count = _invitedCount;
    // 초대 없음 → 원래 섹션 간격(28px)을 대신 제공
    if (count == 0) return SizedBox(height: 28 * s);

    return Padding(
      padding: EdgeInsets.fromLTRB(20 * s, 14 * s, 20 * s, 20 * s),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            // 초대 탭(index 6) 바로 오픈
            builder: (_) => const MyApplicationsScreen(initialTabIndex: 6),
          ),
        ).then((_) { if (mounted) _loadHomeData(); }),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 16 * s, vertical: 13 * s),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.success, AppColors.successDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.success.withValues(alpha: 0.30),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(children: [
            Container(
              width: 38 * s,
              height: 38 * s,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.mail_outlined,
                  color: Colors.white, size: 20 * s),
            ),
            SizedBox(width: 12 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '업무 초대가 $count개 도착했어요!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14 * s,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2 * s),
                  Text(
                    '24시간 내 수락하지 않으면 자동 만료됩니다',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11 * s,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white, size: 20 * s),
          ]),
        ),
      ),
    );
  }

  // ── 주요 메뉴 한 줄 ─────────────────────────────────────────
  Widget _buildMenuRow(BuildContext context, double s, ThemeData theme) {
    final items = [
      (icon: Icons.search_rounded,          label: '공고찾기',
        tap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AllTOListScreen()))),
      (icon: Icons.assignment_outlined,     label: '지원내역',
        tap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyApplicationsScreen()))),
      (icon: Icons.calendar_month_outlined, label: '근무일정',
        tap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyScheduleScreen()))),
      (icon: Icons.access_time_rounded,     label: '출퇴근',
        tap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceCheckScreen()))),
      (icon: Icons.folder_copy_outlined,    label: '계약서',
        tap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserContractsScreen()))),
    ];

    final circleSize = 52.0 * s;
    final radius = 15.0 * s;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14 * s),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.map((item) {
          return Expanded(
            child: GestureDetector(
              onTap: item.tap,
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: circleSize,
                    height: circleSize,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.primaryColor,
                          Color.lerp(theme.primaryColor, theme.colorScheme.secondary, 0.5)!,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: [
                        BoxShadow(
                          color: theme.primaryColor.withValues(alpha: 0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Icon(item.icon, size: 24 * s, color: Colors.white),
                  ),
                  SizedBox(height: 8 * s),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 11 * s,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── 섹션 헤더 ────────────────────────────────────────────────
  Widget _sectionHeader(BuildContext context, double s, String title,
      {String? action, VoidCallback? onAction}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20 * s),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 16 * s,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const Spacer(),
          if (action != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(action,
                    style: TextStyle(fontSize: 12 * s, color: AppColors.textSecondary)),
                Icon(Icons.chevron_right, size: 16 * s, color: AppColors.textSecondary),
              ]),
            ),
        ],
      ),
    );
  }

  // ── 수입 현황 (독립 섹션) ─────────────────────────────────────
  Widget _buildIncomeSection(BuildContext context, double s, ThemeData theme) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    final monthConfirmed = _applications.where((a) {
      if (!AppStatus.confirmedStatuses.contains(a.status)) return false;
      return !a.workDate.isBefore(monthStart) && !a.workDate.isAfter(monthEnd);
    }).length;
    final pending = _applications.where((a) => a.status == AppStatus.pending).length;

    final ratio = (_cachedExpectedIncome > 0)
        ? (_cachedActualIncome / _cachedExpectedIncome).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, s, '내 수입 현황',
            action: '${now.month}월',
            onAction: null),
        SizedBox(height: 12 * s),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20 * s),
          child: IntrinsicHeight(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 예상수입 카드 (파란 계열) ──
              Expanded(
                child: Container(
                  padding: EdgeInsets.fromLTRB(14 * s, 14 * s, 14 * s, 14 * s),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: theme.primaryColor.withValues(alpha: 0.15), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.trending_up_rounded,
                            size: 13 * s, color: theme.primaryColor),
                        SizedBox(width: 4 * s),
                        Flexible(
                          child: Text('이번 달 예상 수입',
                              style: TextStyle(
                                  fontSize: 11 * s,
                                  color: theme.primaryColor,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                      SizedBox(height: 6 * s),
                      _isLoadingData
                          ? SizedBox(
                              height: 24 * s,
                              child: LinearProgressIndicator(
                                  borderRadius: BorderRadius.circular(4),
                                  color: theme.primaryColor.withValues(alpha: 0.4),
                                  backgroundColor: theme.primaryColor.withValues(alpha: 0.1)))
                          : Text(
                              FormatHelper.formatWage(_cachedExpectedIncome),
                              style: TextStyle(
                                  fontSize: 17 * s,
                                  fontWeight: FontWeight.w800,
                                  color: theme.primaryColor,
                                  letterSpacing: -0.5),
                            ),
                      const Spacer(),
                      // 진행 바
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 4 * s,
                          color: theme.primaryColor,
                          backgroundColor: theme.primaryColor.withValues(alpha: 0.15),
                        ),
                      ),
                      SizedBox(height: 7 * s),
                      Row(children: [
                        Flexible(child: _miniTag(s, '확정 $monthConfirmed건', theme.primaryColor)),
                        SizedBox(width: 5 * s),
                        Flexible(child: _miniTag(s, '대기 $pending건',
                            pending > 0 ? AppColors.warning : AppColors.grey400)),
                      ]),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 10 * s),
              // ── 실수입 카드 (초록 계열) ──
              Expanded(
                child: Container(
                  padding: EdgeInsets.fromLTRB(14 * s, 14 * s, 14 * s, 14 * s),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.20), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.account_balance_wallet_outlined,
                            size: 13 * s, color: AppColors.success),
                        SizedBox(width: 4 * s),
                        Flexible(
                          child: Text('실수입 (확정)',
                              style: TextStyle(
                                  fontSize: 11 * s,
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                      SizedBox(height: 6 * s),
                      _isLoadingData
                          ? SizedBox(
                              height: 24 * s,
                              child: LinearProgressIndicator(
                                  borderRadius: BorderRadius.circular(4),
                                  color: AppColors.success.withValues(alpha: 0.4),
                                  backgroundColor: AppColors.success.withValues(alpha: 0.1)))
                          : Text(
                              FormatHelper.formatWage(_cachedActualIncome),
                              style: TextStyle(
                                  fontSize: 17 * s,
                                  fontWeight: FontWeight.w800,
                                  color: _cachedActualIncome > 0
                                      ? AppColors.success
                                      : AppColors.grey400,
                                  letterSpacing: -0.5),
                            ),
                      const Spacer(),
                      Text(
                        _cachedActualIncome > 0 ? '이번 달 지급 완료' : '지급 내역 없음',
                        style: TextStyle(
                            fontSize: 10.5 * s,
                            color: _cachedActualIncome > 0
                                ? AppColors.success
                                : AppColors.grey400),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),   // Row
          ),   // IntrinsicHeight
        ),     // Padding
      ],
    );
  }

  Widget _miniTag(double s, String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10 * s, color: color, fontWeight: FontWeight.w600)),
    );
  }

  // ── 최근 지원 내역 ────────────────────────────────────────────
  Widget _buildRecentApplications(BuildContext context, double s, ThemeData theme) {
    final recent = _cachedRecentApplications;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, s, '최근 지원 내역',
            action: '전체 보기',
            onAction: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MyApplicationsScreen()))),
        SizedBox(height: 12 * s),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20 * s),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _isLoadingData
                ? Padding(
                    padding: EdgeInsets.all(16 * s),
                    child: Column(
                      children: List.generate(3, (i) => Container(
                        margin: EdgeInsets.only(bottom: i < 2 ? 8 * s : 0),
                        height: 52 * s,
                        decoration: BoxDecoration(
                          color: AppColors.grey100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      )),
                    ),
                  )
                : recent.isEmpty
                    ? Padding(
                        padding: EdgeInsets.symmetric(vertical: 28 * s),
                        child: Column(children: [
                          Icon(Icons.inbox_outlined,
                              size: 32 * s, color: AppColors.grey300),
                          SizedBox(height: 8 * s),
                          Text('아직 지원한 공고가 없어요',
                              style: TextStyle(
                                  fontSize: 12.5 * s, color: AppColors.grey400)),
                          SizedBox(height: 8 * s),
                          GestureDetector(
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(
                                    builder: (_) => const AllTOListScreen())),
                            child: Text('공고 찾아보기 →',
                                style: TextStyle(
                                    fontSize: 12.5 * s,
                                    color: theme.primaryColor,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Column(
                          children: recent.asMap().entries.map((entry) {
                            final i = entry.key;
                            final app = entry.value;
                            return Column(children: [
                              if (i > 0)
                                const Divider(
                                    height: 1, indent: 16, endIndent: 16,
                                    color: AppColors.divider),
                              _appRow(context, s, theme, app),
                            ]);
                          }).toList(),
                        ),
                      ),
          ),
        ),
      ],
    );
  }

  Widget _appRow(BuildContext context, double s, ThemeData theme, ApplicationModel app) {
    final (statusText, statusColor) = _statusAction(app, theme);
    final hasTime = app.startTime.isNotEmpty && app.endTime.isNotEmpty;
    final hasWorkType = app.selectedWorkType.isNotEmpty;

    return InkWell(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const MyApplicationsScreen())),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16 * s, 12 * s, 12 * s, 12 * s),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // ── 업무 유형 아이콘 (썸네일 대체) ──
          WorkTypeIcon.buildWithBackground(
            iconString: app.workTypeIcon ?? 'work',
            iconColor: app.workTypeColor,
            backgroundColor: app.workTypeBackgroundColor,
            size: 20 * s,
            containerSize: 44 * s,
          ),
          SizedBox(width: 12 * s),
          // ── 중앙: 제목 / 사업장+업무유형 / 날짜시간 ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app.toTitle,
                    style: TextStyle(
                        fontSize: 13.5 * s,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                SizedBox(height: 2 * s),
                Text(
                  hasWorkType
                      ? '${app.businessName}  ·  ${app.selectedWorkType}'
                      : app.businessName,
                  style: TextStyle(
                      fontSize: 11.5 * s, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 1 * s),
                Text(
                  hasTime
                      ? '${app.workDate.month}/${app.workDate.day}(${_dayLabel(app.workDate)})  ${app.startTime}~${app.endTime}'
                      : '${app.workDate.month}/${app.workDate.day}(${_dayLabel(app.workDate)})',
                  style: TextStyle(
                      fontSize: 11 * s, color: AppColors.grey400),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(width: 6 * s),
          // ── 우측: 상태 텍스트 ──
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(statusText,
                  style: TextStyle(
                      fontSize: 11.5 * s,
                      fontWeight: FontWeight.w600,
                      color: statusColor)),
              SizedBox(height: 1 * s),
              Icon(Icons.chevron_right, size: 14 * s, color: AppColors.grey300),
            ],
          ),
        ]),
      ),
    );
  }


  // ── 이번 주 출근 일정 (날짜 선택 인터랙티브) ──────────────────────
  // ValueListenableBuilder: 날짜 탭 시 이 섹션만 rebuild — 전체 setState 없음
  Widget _buildThisWeekSchedule(BuildContext context, double s, ThemeData theme) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: _selectedDayNotifier,
      builder: (context, selectedDay, _) =>
          _buildThisWeekScheduleContent(context, s, theme, selectedDay),
    );
  }

  Widget _buildThisWeekScheduleContent(
      BuildContext context, double s, ThemeData theme, DateTime selectedDay) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekDays = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    final entryDates = _cachedThisWeekEntryDates;    // 캐시 — data 변경 시에만 재계산
    final selectedEntries = _entriesForDay(selectedDay);
    final isSelectedToday = selectedDay == today;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, s, '이번 주 출근 일정',
            action: '전체 일정',
            onAction: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MyScheduleScreen()))),
        SizedBox(height: 12 * s),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20 * s),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // ── 주간 요일 스트립 ──
                Padding(
                  padding: EdgeInsets.fromLTRB(8 * s, 16 * s, 8 * s, 10 * s),
                  child: Row(
                    children: weekDays.map((day) {
                      final isToday      = day == today;
                      final isSelected   = day == selectedDay;
                      final hasEntry     = entryDates.contains(day);
                      final isSat        = day.weekday == 6;
                      final isSun        = day.weekday == 7;

                      final textColor = isSelected
                          ? (isToday ? Colors.white : theme.primaryColor)
                          : isSat
                              ? AppColors.info
                              : isSun
                                  ? AppColors.error
                                  : AppColors.grey400;

                      BoxDecoration? circleDeco;
                      if (isToday) {
                        circleDeco = BoxDecoration(
                          color: theme.primaryColor,
                          shape: BoxShape.circle,
                        );
                      } else if (isSelected) {
                        circleDeco = BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.primaryColor,
                            width: 1.5,
                          ),
                        );
                      }

                      return Expanded(
                        child: GestureDetector(
                          onTap: () => _selectedDayNotifier.value = day,
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _dayLabel(day),
                                style: TextStyle(
                                  fontSize: 11 * s,
                                  color: isSelected && !isToday
                                      ? theme.primaryColor
                                      : isToday
                                          ? theme.primaryColor
                                          : isSat
                                              ? const Color(0xFF4A90D9)
                                              : isSun
                                                  ? const Color(0xFFE05252)
                                                  : AppColors.grey400,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              SizedBox(height: 6 * s),
                              Container(
                                width: 30 * s,
                                height: 30 * s,
                                decoration: circleDeco,
                                alignment: Alignment.center,
                                child: Text(
                                  '${day.day}',
                                  style: TextStyle(
                                    fontSize: 13 * s,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: isToday
                                        ? Colors.white
                                        : textColor,
                                  ),
                                ),
                              ),
                              SizedBox(height: 5 * s),
                              Container(
                                width: 5 * s,
                                height: 5 * s,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: hasEntry
                                      ? theme.primaryColor
                                      : Colors.transparent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // 구분선 (스트립 ↔ 일정 내용)
                const Divider(height: 1, thickness: 1, color: AppColors.divider),

                // ── 선택 날짜 라벨 ──
                Padding(
                  padding: EdgeInsets.fromLTRB(16 * s, 10 * s, 16 * s, 4 * s),
                  child: Text(
                    isSelectedToday
                        ? '오늘 출근 일정'
                        : '${selectedDay.month}/${selectedDay.day}(${_dayLabel(selectedDay)}) 출근 일정',
                    style: TextStyle(
                      fontSize: 12 * s,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                // ── 일정 카드 ──
                if (_isLoadingData)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16 * s, 4 * s, 16 * s, 16 * s),
                    child: _scheduleSkeleton(s),
                  )
                else if (selectedEntries.isEmpty)
                  _scheduleEmptyInline(context, s)
                else ...[
                  ...selectedEntries.take(2).map(
                        (e) => _scheduleCardInline(context, s, theme, e, today),
                      ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _scheduleSkeleton(double s) {
    return Column(
      children: List.generate(
        2,
        (_) => Container(
          margin: EdgeInsets.only(bottom: 8 * s),
          height: 56 * s,
          decoration: BoxDecoration(
            color: AppColors.grey100,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _scheduleEmptyInline(BuildContext context, double s) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 24 * s),
      child: Column(children: [
        Icon(Icons.event_available_outlined, size: 28 * s, color: AppColors.grey300),
        SizedBox(height: 8 * s),
        Text('이번 주 예정된 출근이 없어요',
            style: TextStyle(fontSize: 12.5 * s, color: AppColors.grey400)),
      ]),
    );
  }

  Widget _scheduleCardInline(BuildContext context, double s, ThemeData theme,
      _WeekEntry e, DateTime today) {
    final isToday = e.date == today;
    final daysUntil = e.date.difference(today).inDays;
    final dLabel = isToday ? 'D-Day' : 'D-$daysUntil';

    return InkWell(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const MyScheduleScreen())),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 13 * s),
        child: Row(children: [
          // 시간 + D-배지
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e.app.startTime,
                style: TextStyle(
                  fontSize: 13 * s,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 3 * s),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
                decoration: BoxDecoration(
                  color: isToday
                      ? theme.primaryColor
                      : theme.primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  dLabel,
                  style: TextStyle(
                    fontSize: 10 * s,
                    fontWeight: FontWeight.bold,
                    color: isToday ? Colors.white : theme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(width: 14 * s),
          // 제목 + 사업장
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                e.app.toTitle,
                style: TextStyle(
                    fontSize: 14 * s,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 3 * s),
              Text(
                '${e.app.businessName}  ${e.app.startTime}~${e.app.endTime}',
                style: TextStyle(fontSize: 11.5 * s, color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          SizedBox(width: 8 * s),
          // 일정 보기
          OutlinedButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MyScheduleScreen())),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
              side: BorderSide(color: theme.primaryColor.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              '일정 보기',
              style: TextStyle(
                  fontSize: 11 * s,
                  color: theme.primaryColor,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
    );
  }

  // ── 온보딩 배너 ─────────────────────────────────────────────
  Widget _buildOnboardingBanner(BuildContext context, double s, UserProvider up) {
    final user = up.currentUser;
    if (user == null) return const SizedBox.shrink();
    final missing = <String>[];
    if (user.idCardImageUrl == null) missing.add('신분증');
    if (user.bankbookImageUrl == null) missing.add('통장사본');
    if (user.bankName == null || user.accountNumber == null) missing.add('통장 정보');
    if (missing.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(20 * s, 0, 20 * s, 20 * s),
      child: GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SettingsScreen())),
        child: Container(
          padding: EdgeInsets.all(14 * s),
          decoration: BoxDecoration(
            color: AppColors.warningBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.4), width: 1.2),
          ),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 20 * s),
            SizedBox(width: 10 * s),
            Expanded(
              child: Text(
                '지원 전 등록 필요: ${missing.join(', ')}',
                style: TextStyle(
                    fontSize: 12.5 * s,
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(width: 6 * s),
            Text('등록하기',
                style: TextStyle(
                    fontSize: 12 * s,
                    color: AppColors.warning,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.warning)),
          ]),
        ),
      ),
    );
  }

  // ── 네비게이션 헬퍼 ─────────────────────────────────────────
  Future<void> _switchToAdminMode(BuildContext context, UserProvider up) async {
    final bizIds = up.currentUser?.subAdminBusinessIds ?? [];
    if (bizIds.isEmpty) return;
    String? selected;
    if (bizIds.length == 1) {
      selected = bizIds.first;
    } else {
      selected = await DialogHelper.showSheet<String>(
        context,
        builder: (ctx) => _BusinessSelectorSheet(
          businessIds: bizIds,
          businessNames: up.subAdminBusinessNames,
        ),
      );
    }
    if (selected == null || !context.mounted) return;
    await up.switchToAdminMode(selected);
    if (!context.mounted) return;
    // 관리자 홈으로 화면 교체 — 뒤로가기 없이 전환
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const BusinessAdminHomeScreen()),
    );
  }

  Future<void> _switchBusiness(BuildContext context, UserProvider up) async {
    final bizIds = up.currentUser?.subAdminBusinessIds ?? [];
    final newId = await DialogHelper.showSheet<String>(
      context,
      builder: (ctx) => _BusinessSelectorSheet(
        businessIds: bizIds,
        businessNames: up.subAdminBusinessNames,
        currentBizId: up.selectedSubAdminBusinessId,
      ),
    );
    if (newId == null || !context.mounted) return;
    await up.switchToAdminMode(newId);
  }
}

// ── 계약서 서명 배너 (스트림 분리 위젯) ──────────────────────────
class _PendingContractBar extends StatelessWidget {
  const _PendingContractBar();

  @override
  Widget build(BuildContext context) {
    final data = context.select<UserProvider, ({bool show, int count})>(
      (p) => (show: !p.isAdminMode && p.hasPendingContract, count: p.pendingContractCount),
    );
    return Visibility(
      visible: data.show,
      maintainSize: true,
      maintainState: true,
      maintainAnimation: true,
      child: IgnorePointer(
        ignoring: !data.show,
        child: SafeArea(
          top: false,
          child: GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const UserContractsScreen())),
            child: Container(
              width: double.infinity,
              color: AppColors.yellowWarnBg,
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.yellowWarnDark, size: 18),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    '미서명 계약서 ${data.count}건이 있습니다. 탭하여 확인하세요.',
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      color: AppColors.yellowWarnText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.yellowWarnDark, size: 18),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 다중 사업장 선택 바텀시트 ────────────────────────────────────
class _BusinessSelectorSheet extends StatelessWidget {
  final List<String> businessIds;
  final Map<String, String> businessNames;
  final String? currentBizId;

  const _BusinessSelectorSheet({
    required this.businessIds,
    required this.businessNames,
    this.currentBizId,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            ResponsiveHelper.spacing(context, 20),
            ResponsiveHelper.spacing(context, 20),
            ResponsiveHelper.spacing(context, 20),
            ResponsiveHelper.spacing(context, 8),
          ),
          child: Text(
            '사업장 선택',
            style: ResponsiveHelper.subtitleStyle(context)
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        ...businessIds.map((id) {
          final name = businessNames[id] ?? id;
          final isCurrent = id == currentBizId;
          return ListTile(
            title: Text(name,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight:
                        isCurrent ? FontWeight.bold : FontWeight.normal)),
            trailing: isCurrent
                ? Icon(Icons.check,
                    color: Theme.of(context).primaryColor,
                    size: ResponsiveHelper.iconSize(context, 20))
                : null,
            onTap: () => Navigator.pop(context, id),
          );
        }),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
      ],
    );
  }
}

