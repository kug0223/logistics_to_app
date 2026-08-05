import 'dart:async' show unawaited;

import '../../services/fcm_service.dart';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Providers
import '../../providers/user_provider.dart';

// Utils
import '../../utils/navigation_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/tour_helper.dart';
import '../common/tour_screen.dart';

// Services
import '../../services/firestore_service.dart';
import '../../utils/attendance_list_pdf.dart';
import '../../models/core/application_model.dart';

// Screens
import '../common/settings_screen.dart';
import 'to_management/create_to_screen.dart';
import 'workforce_management/integrated_workforce_screen.dart';
import '../common/notification_screen.dart';
import '../../widgets/common/notification_badge.dart';
import 'admin_stats_screen.dart';
import 'admin_contract_management_screen.dart';
import 'payroll/payroll_overview_screen.dart';
import 'payroll/payroll_payment_dashboard_screen.dart';
import '../../services/payroll_payment_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/business_picker_helper.dart';
import '../../models/core/business_model.dart';
import 'dialogs/pending_approval_calendar_dialog.dart';
import 'dialogs/close_management_dialog.dart';
import 'dialogs/expiring_contracts_dialog.dart';
import 'dialogs/attendance_status_dialog.dart';

// [PERF-2026-07-16] Selector용 record — 필요한 필드만 추출해 불필요한 rebuild 방지
typedef _AdminHomeData = ({
  String userName,
});

class BusinessAdminHomeScreen extends StatefulWidget {
  const BusinessAdminHomeScreen({super.key});

  @override
  State<BusinessAdminHomeScreen> createState() => _BusinessAdminHomeScreenState();
}

class _BusinessAdminHomeScreenState extends State<BusinessAdminHomeScreen>
    with WidgetsBindingObserver {
  final _firestoreService = FirestoreService();
  final _payrollService = PayrollPaymentService();
  bool? _hasApprovedBusiness;
  List<BusinessModel> _businesses = [];
  bool _isNavigating = false;

  // 오늘의 요약 카운트
  int _summaryActiveTO = 0;
  int _summaryPending = 0;
  int _summaryUnsentContract = 0;
  int _summaryUnpaidWage = 0;
  int _summaryUnclosedDays = 0;
  int _summaryExpiringContracts = 0;
  int _summaryWageChangeReqs = 0;
  int _summaryInterimReqs = 0;
  bool _summaryLoading = true;
  bool _summaryUnclosedLoading = true;

  // 이번 주 근무
  Map<String, int> _weeklyRosterCounts = {};
  int _weeklyTotal = 0;
  bool _weeklyLoading = true;

  // 새로고침 동시 실행 방어 + 자동 쿨다운
  bool _isRefreshing = false;
  DateTime? _lastAutoRefreshAt;

  late final VoidCallback _onFcmRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _onFcmRefresh = () { if (mounted) _autoRefresh(); };
    FCMService().addAdminRefreshListener(_onFcmRefresh);
    AttendanceListPdf.preloadFonts();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final results = await Future.wait([
        _loadApprovedBusinessStatus(),
        TourHelper.isCompleted(TourHelper.adminHome),
      ]);
      final tourDone = results[1] as bool;
      if (!tourDone && mounted) {
        await pushTourScreen(context, role: 'BUSINESS_ADMIN');
        if (mounted) await TourHelper.markCompleted(TourHelper.adminHome);
      }
      if (mounted) {
        unawaited(_loadSummaryCounts());
        unawaited(_loadUnclosedDaysCount());
        unawaited(_loadWeeklyRosterCounts());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FCMService().removeAdminRefreshListener(_onFcmRefresh);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _autoRefresh();
  }

  // 자동 트리거(FCM·앱 복귀)용 — 30초 쿨다운 + 동시 실행 방어
  void _autoRefresh() {
    final now = DateTime.now();
    if (_lastAutoRefreshAt != null &&
        now.difference(_lastAutoRefreshAt!) < const Duration(seconds: 30)) { return; }
    _lastAutoRefreshAt = now;
    _refresh();
  }

  // pull-to-refresh용 — 쿨다운 없이 항상 실행, 동시 실행만 방어
  Future<void> _refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      await Future.wait([
        _loadSummaryCounts(),
        _loadUnclosedDaysCount(),
        _loadWeeklyRosterCounts(),
      ]);
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> _loadApprovedBusinessStatus() async {
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;
    if (uid == null) return;
    try {
      final managedIds = userProvider.currentUser?.managedBusinessIds ?? [];
      final businesses = await _firestoreService.getBusinessesByIds(managedIds);
      if (mounted) {
        setState(() {
          _hasApprovedBusiness = businesses.any((b) => b.isApproved);
          _businesses = businesses;
        });
      }
    } catch (e) {
      debugPrint('❌ 사업장 조회 실패: $e');
      if (mounted) ToastHelper.showError('사업장 정보를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.');
    }
  }

  Future<void> _safeNavigate(Future<void> Function() action) async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await action();
    } catch (e) {
      debugPrint('❌ 탐색 오류: $e');
      if (mounted) ToastHelper.showError('처리 중 오류가 발생했습니다.');
    } finally {
      _isNavigating = false;
    }
  }

  Future<void> _loadSummaryCounts() async {
    final businesses = await _getBusinesses();
    if (businesses.isEmpty || !mounted) return;
    final bizIds = businesses.map((b) => b.id).toList();
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    Future<int> safeCount(Future<int> Function() f) async {
      try {
        return await f();
      } catch (_) {
        return 0;
      }
    }

    try {
      final results = await Future.wait([
        // 셀 1: 진행 중 공고
        safeCount(() async {
          final lists = await Future.wait(
            bizIds.map((id) =>
                _firestoreService.getTOsByBusiness(id, activeOnly: true)),
          );
          return lists.expand((l) => l).where((t) => t.status == 'ACTIVE').length;
        }),
        // 셀 2: 승인 대기
        safeCount(() async {
          final counts = await Future.wait<int>(
            bizIds.map((id) => _firestoreService.getAllPendingApplicationsCount(id)),
          );
          return counts.fold<int>(0, (a, b) => a + b);
        }),
        // 셀 3: 계약 미발송
        safeCount(() async {
          final lists = await Future.wait(
            bizIds.map((id) =>
                _firestoreService.getUnsentApplicationsByBusiness(id)),
          );
          return lists.fold<int>(0, (a, b) => a + b.length);
        }),
        // 셀 4: 급여 미이체
        safeCount(() async {
          final counts = await Future.wait<int>(
            bizIds.map((id) => _payrollService
                .getTotalNotTransferredCount(businessId: id)
                .then((v) => v ?? 0)),
          );
          return counts.fold<int>(0, (a, b) => a + b);
        }),
        // 셀 6: 계약 종료 예정 (D-15 이내)
        safeCount(() async {
          final lists = await Future.wait(
            bizIds.map((id) => _firestoreService.getExpiringLongTermApplications(
                businessId: id, fromDate: todayOnly)),
          );
          return lists.expand((l) => l).where((ApplicationModel app) {
            final end = app.actualResignDate ?? app.workEndDate;
            if (end == null) return false;
            final endOnly = DateTime(end.year, end.month, end.day);
            final diff = endOnly.difference(todayOnly).inDays;
            return diff >= 0 && diff <= 15;
          }).length;
        }),
        // 셀 7: 급여 변경 요청
        safeCount(() async {
          final lists = await Future.wait(
            bizIds.map((id) => _payrollService.getPendingChangeRequests(id)),
          );
          return lists.fold<int>(0, (a, b) => a + b.length);
        }),
        // 셀 8: 중간정산 요청
        safeCount(() async {
          final lists = await Future.wait(
            bizIds.map((id) => _payrollService.getPendingSettlementRequests(id)),
          );
          return lists.fold<int>(0, (a, b) => a + b.length);
        }),
      ]);

      if (!mounted) return;
      setState(() {
        _summaryActiveTO          = results[0];
        _summaryPending           = results[1];
        _summaryUnsentContract    = results[2];
        _summaryUnpaidWage        = results[3];
        _summaryExpiringContracts = results[4];
        _summaryWageChangeReqs    = results[5];
        _summaryInterimReqs       = results[6];
        _summaryLoading           = false;
      });
    } catch (e) {
      debugPrint('❌ 요약 카운트 조회 실패: $e');
      if (mounted) setState(() => _summaryLoading = false);
    }
  }

  Future<void> _loadUnclosedDaysCount() async {
    final businesses = await _getBusinesses();
    if (businesses.isEmpty || !mounted) return;
    final now = DateTime.now();

    try {
      int total = 0;
      for (final biz in businesses) {
        try {
          total += await _firestoreService.getUnclosedDaysCount(
              businessId: biz.id, month: now);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _summaryUnclosedDays    = total;
        _summaryUnclosedLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 마감 미처리 조회 실패: $e');
      if (mounted) setState(() => _summaryUnclosedLoading = false);
    }
  }

  Future<void> _loadWeeklyRosterCounts() async {
    final businesses = await _getBusinesses();
    if (businesses.isEmpty || !mounted) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 일요일 기준 주 시작 (Dart weekday: 1=월~7=일)
    final daysSinceSunday = now.weekday == 7 ? 0 : now.weekday;
    final weekStart = today.subtract(Duration(days: daysSinceSunday));

    try {
      final perBiz = await Future.wait(
        businesses.map((b) => _firestoreService.getWeeklyConfirmedCounts(
            businessId: b.id, weekStart: weekStart)),
      );

      // 사업장별 합산
      final Map<String, int> merged = {};
      for (int d = 0; d < 7; d++) {
        merged[_dateKey(weekStart.add(Duration(days: d)))] = 0;
      }
      for (final bizCounts in perBiz) {
        bizCounts.forEach((k, v) => merged[k] = (merged[k] ?? 0) + v);
      }

      if (!mounted) return;
      setState(() {
        _weeklyRosterCounts = merged;
        _weeklyTotal = merged.values.fold(0, (a, b) => a + b);
        _weeklyLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 주간 근무 조회 실패: $e');
      if (mounted) setState(() => _weeklyLoading = false);
    }
  }

  /// DateTime → 'yyyy-MM-dd' (홈 화면 내부용)
  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<List<BusinessModel>> _getBusinesses() async {
    if (_businesses.isNotEmpty) return _businesses;
    final managedIds =
        context.read<UserProvider>().currentUser?.managedBusinessIds ?? [];
    final businesses = await _firestoreService.getBusinessesByIds(managedIds);
    _businesses = businesses; // 캐시만 갱신 — UI에 직접 영향 없으므로 setState 불필요
    return businesses;
  }

  Future<void> _requireApprovedBusiness(
      BuildContext context, Future<void> Function() proceed) async {
    if (_hasApprovedBusiness == null) {
      ToastHelper.showWarning('사업장 정보를 불러오는 중입니다. 잠시 후 다시 시도해주세요.');
      return;
    }
    if (_hasApprovedBusiness == false) {
      ToastHelper.showWarning('승인된 사업장이 있어야 이용할 수 있습니다.\n사업장 승인 후 다시 시도해주세요.');
      return;
    }
    await proceed();
  }

  // ── 반응형 스케일 ──────────────────────────────────────────────
  double _s(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 360) return 0.82;
    if (w < 400) return 0.92;
    if (w < 480) return 1.0;
    return 1.08;
  }

  @override
  Widget build(BuildContext context) {
    final s = _s(context);
    return Selector<UserProvider, _AdminHomeData>(
      selector: (_, p) => (userName: p.currentUser?.name ?? '관리자'),
      builder: (context, data, _) {
        final theme = Theme.of(context);
        final up = context.read<UserProvider>();
        return Scaffold(
          body: Container(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context, s, data.userName, up),
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.grey50,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(28),
                          topRight: Radius.circular(28),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(28),
                          topRight: Radius.circular(28),
                        ),
                        child: RefreshIndicator(
                          onRefresh: _refresh,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics()),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(height: 22 * s),
                                _buildMenuRow(context, s, theme, up),
                                SizedBox(height: 28 * s),
                                _buildTodaySummary(context, s, theme),
                                SizedBox(height: 24 * s),
                                _buildWeeklyRoster(context, s, theme),
                                SizedBox(height: 36 * s),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 헤더
  // ─────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, double s, String name, UserProvider up) {
    return Stack(
      children: [
        Positioned(
          right: 10 * s, top: -8 * s,
          child: Text('A',
              style: TextStyle(
                  fontSize: 110 * s,
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withValues(alpha: 0.10),
                  height: 1.0,
                  letterSpacing: -4)),
        ),
        Positioned(
          right: 28 * s, bottom: 16 * s,
          child: Container(
            width: 38 * s, height: 38 * s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 1.5),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20 * s, 14 * s, 20 * s, 20 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                ClipOval(
                  child: Image.asset('assets/icons/app_icon.png',
                      width: 26 * s, height: 26 * s, fit: BoxFit.cover),
                ),
                SizedBox(width: 7 * s),
                Text('ALfit',
                    style: TextStyle(
                        fontSize: 18 * s,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5)),
                const Spacer(),
                NotificationBadge(
                  child: _headerBtn(context, s, Icons.notifications_outlined,
                      onTap: () => _safeNavigate(() async {
                        await Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const NotificationScreen()));
                      })),
                ),
                SizedBox(width: 8 * s),
                _headerBtn(context, s, Icons.person_outline,
                    onTap: () => _safeNavigate(() async {
                      await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen()));
                      if (mounted) _loadApprovedBusinessStatus();
                    })),
              ]),
              SizedBox(height: 16 * s),
              Text('안녕하세요,',
                  style: TextStyle(
                      fontSize: 13 * s,
                      color: Colors.white.withValues(alpha: 0.85))),
              SizedBox(height: 4 * s),
              Row(children: [
                Flexible(
                  child: Text('$name님!',
                      style: TextStyle(
                          fontSize: 24 * s,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                SizedBox(width: 8 * s),
                _adminBadge(s),
              ]),
              SizedBox(height: 4 * s),
              Text('오늘도 사업장을 스마트하게 관리해요',
                  style: TextStyle(
                      fontSize: 11.5 * s,
                      color: Colors.white.withValues(alpha: 0.65))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _headerBtn(BuildContext context, double s, IconData icon,
      {required VoidCallback onTap}) {
    return Material(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(8 * s),
          child: Icon(icon, color: Colors.white, size: 22 * s),
        ),
      ),
    );
  }

  Widget _adminBadge(double s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.business_outlined, color: Colors.white, size: 12 * s),
        SizedBox(width: 4 * s),
        Text('관리자',
            style: TextStyle(
                color: Colors.white,
                fontSize: 11 * s,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── 섹션 헤더 ──────────────────────────────────────────────────
  Widget _sectionHeader(BuildContext context, double s, String title,
      {String? action, VoidCallback? onAction}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20 * s),
      child: Row(children: [
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
                  style: TextStyle(
                      fontSize: 12 * s, color: AppColors.textSecondary)),
              Icon(Icons.chevron_right,
                  size: 16 * s, color: AppColors.textSecondary),
            ]),
          ),
      ]),
    );
  }

  // ── 5아이콘 메뉴 행 ────────────────────────────────────────────
  Widget _buildMenuRow(BuildContext context, double s, ThemeData theme, UserProvider up) {
    final items = [
      (
        icon: Icons.post_add_outlined,
        label: '공고등록',
        tap: () => _safeNavigate(() async {
          final user = up.currentUser;
          if (user == null || !context.mounted) return;
          await NavigationHelper.push<bool>(context,
              destination: const AdminCreateTOScreen(),
              onReturn: (r) {
                if (r == true) ToastHelper.showSuccess('공고가 등록되었습니다');
              });
        }),
      ),
      (
        icon: Icons.people_alt_outlined,
        label: '공고관리',
        tap: () => _safeNavigate(() =>
            _requireApprovedBusiness(context, () async {
              await Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => const IntegratedWorkforceScreen()));
            })),
      ),
      (
        icon: Icons.folder_copy_outlined,
        label: '계약서',
        tap: () => _safeNavigate(() =>
            _requireApprovedBusiness(context, () async {
              if (!up.can((p) => p.canManageContract)) {
                ToastHelper.showWarning('계약서 관리 권한이 없습니다.');
                return;
              }
              final biz = await BusinessPickerHelper.pick(context);
              if (biz == null || !context.mounted) return;
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AdminContractManagementScreen(
                          businessId: biz.id)));
            })),
      ),
      (
        icon: Icons.payments_outlined,
        label: '급여정산',
        tap: () => _safeNavigate(() =>
            _requireApprovedBusiness(context, () async {
              if (!up.can((p) => p.canManageWage)) {
                ToastHelper.showWarning('급여 관리 권한이 없습니다.');
                return;
              }
              await Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => const PayrollOverviewScreen()));
            })),
      ),
      (
        icon: Icons.bar_chart_outlined,
        label: '통계',
        tap: () =>
            _safeNavigate(() async => pushAdminStatsScreen(context)),
      ),
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
                          Color.lerp(theme.primaryColor,
                              theme.colorScheme.secondary, 0.5)!,
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
                  Text(item.label,
                      style: TextStyle(
                          fontSize: 11 * s,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── 오늘의 요약 ────────────────────────────────────────────────
  Widget _buildTodaySummary(BuildContext context, double s, ThemeData theme) {
    final activeTO          = _summaryActiveTO;
    final pending           = _summaryPending;
    final unsentContract    = _summaryUnsentContract;
    final unpaidWage        = _summaryUnpaidWage;
    final unclosedDays      = _summaryUnclosedDays;
    final expiringContracts = _summaryExpiringContracts;
    final wageChangeReqs    = _summaryWageChangeReqs;
    final interimReqs       = _summaryInterimReqs;

    Future<void> toPayrollTab(int tab) async {
      final up = context.read<UserProvider>();
      if (!up.can((p) => p.canManageWage)) {
        ToastHelper.showWarning('급여 관리 권한이 없습니다.');
        return;
      }
      final biz = await BusinessPickerHelper.pick(context);
      if (biz == null || !context.mounted) return;
      final now = DateTime.now();
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PayrollPaymentDashboardScreen(
                    businessId: biz.id,
                    businessName: biz.name,
                    year: now.year,
                    month: now.month,
                    initialTab: tab,
                  )));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, s, '오늘의 요약'),
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
            child: Column(children: [
              // Row 1: 공고 / 승인 / 계약 / 급여 미이체
              Padding(
                padding: EdgeInsets.symmetric(vertical: 14 * s),
                child: Row(children: [
                  _summaryCell(context, s, theme,
                      icon: Icons.campaign_outlined,
                      label: '진행 중 공고',
                      value: '$activeTO건',
                      color: theme.primaryColor,
                      isLoading: _summaryLoading,
                      onTap: () => _safeNavigate(() => _requireApprovedBusiness(
                          context,
                          () async => Navigator.push(context,
                              MaterialPageRoute(
                                  builder: (_) => const IntegratedWorkforceScreen()))))),
                  _summaryDivider(s),
                  _summaryCell(context, s, theme,
                      icon: Icons.assignment_late_outlined,
                      label: '승인 대기',
                      value: '$pending명',
                      color: pending > 0 ? AppColors.warning : AppColors.grey400,
                      isLoading: _summaryLoading,
                      onTap: () => _safeNavigate(() => _requireApprovedBusiness(
                          context, () async {
                        final businesses = await _getBusinesses();
                        if (businesses.isEmpty || !context.mounted) return;
                        await showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => PendingApprovalCalendarDialog(
                            initialMonth: DateTime.now(),
                            businessIds: businesses.map((b) => b.id).toList(),
                            businesses: businesses,
                          ),
                        );
                      }))),
                  _summaryDivider(s),
                  _summaryCell(context, s, theme,
                      icon: Icons.folder_off_outlined,
                      label: '계약 미발송',
                      value: '$unsentContract명',
                      color: unsentContract > 0 ? AppColors.error : AppColors.grey400,
                      isLoading: _summaryLoading,
                      onTap: () => _safeNavigate(() => _requireApprovedBusiness(
                          context, () async {
                        final up = context.read<UserProvider>();
                        if (!up.can((p) => p.canManageContract)) {
                          ToastHelper.showWarning('계약서 관리 권한이 없습니다.');
                          return;
                        }
                        final biz = await BusinessPickerHelper.pick(context);
                        if (biz == null || !context.mounted) return;
                        await Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) => AdminContractManagementScreen(
                                    businessId: biz.id,
                                    initialTab: 1)));
                      }))),
                  _summaryDivider(s),
                  _summaryCell(context, s, theme,
                      icon: Icons.account_balance_wallet_outlined,
                      label: '급여 미이체',
                      value: '$unpaidWage명',
                      color: unpaidWage > 0 ? AppColors.error : AppColors.grey400,
                      isLoading: _summaryLoading,
                      onTap: () => _safeNavigate(() => _requireApprovedBusiness(
                          context, () async => toPayrollTab(0)))),
                ]),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16 * s),
                child: Divider(height: 1, thickness: 1, color: AppColors.border),
              ),
              // Row 2: 마감 / 계약종료 / 급여변경 / 중간정산
              Padding(
                padding: EdgeInsets.symmetric(vertical: 14 * s),
                child: Row(children: [
                  _summaryCell(context, s, theme,
                      icon: Icons.lock_open_outlined,
                      label: '마감 미처리',
                      value: '$unclosedDays일',
                      color: unclosedDays > 0 ? AppColors.error : AppColors.grey400,
                      isLoading: _summaryUnclosedLoading,
                      onTap: () => _safeNavigate(() => _requireApprovedBusiness(
                          context, () async {
                        final businesses = await _getBusinesses();
                        if (businesses.isEmpty || !context.mounted) return;
                        await showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => CloseManagementDialog(
                            initialMonth: DateTime.now(),
                            businessIds: businesses.map((b) => b.id).toList(),
                            businesses: businesses,
                          ),
                        );
                      }))),
                  _summaryDivider(s),
                  _summaryCell(context, s, theme,
                      icon: Icons.calendar_month_outlined,
                      label: '계약 종료 예정',
                      value: '$expiringContracts명',
                      color: expiringContracts > 0 ? AppColors.warning : AppColors.grey400,
                      isLoading: _summaryLoading,
                      onTap: () => _safeNavigate(() => _requireApprovedBusiness(
                          context, () async {
                        final businesses = await _getBusinesses();
                        if (businesses.isEmpty || !context.mounted) return;
                        await showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => ExpiringContractsDialog(
                            businessIds: businesses.map((b) => b.id).toList(),
                            businesses: businesses,
                          ),
                        );
                      }))),
                  _summaryDivider(s),
                  _summaryCell(context, s, theme,
                      icon: Icons.compare_arrows,
                      label: '급여 변경 요청',
                      value: '$wageChangeReqs건',
                      color: wageChangeReqs > 0
                          ? const Color(0xFF7C3AED)
                          : AppColors.grey400,
                      isLoading: _summaryLoading,
                      onTap: () => _safeNavigate(() => _requireApprovedBusiness(
                          context, () async => toPayrollTab(2)))),
                  _summaryDivider(s),
                  _summaryCell(context, s, theme,
                      icon: Icons.account_balance_outlined,
                      label: '중간정산 요청',
                      value: '$interimReqs건',
                      color: interimReqs > 0
                          ? const Color(0xFF0EA5E9)
                          : AppColors.grey400,
                      isLoading: _summaryLoading,
                      onTap: () => _safeNavigate(() => _requireApprovedBusiness(
                          context, () async => toPayrollTab(3)))),
                ]),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _summaryCell(BuildContext context, double s, ThemeData theme,
      {required IconData icon,
      required String label,
      required String value,
      required Color color,
      bool isLoading = false,
      VoidCallback? onTap}) {
    return Expanded(
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 4 * s),
          child: Column(children: [
            Container(
              width: 36 * s,
              height: 36 * s,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18 * s, color: color),
            ),
            SizedBox(height: 6 * s),
            isLoading
                ? SizedBox(
                    width: 16 * s,
                    height: 16 * s,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: color),
                  )
                : Text(value,
                    style: TextStyle(
                        fontSize: 17 * s,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: -0.5)),
            SizedBox(height: 2 * s),
            Text(label,
                style: TextStyle(
                    fontSize: 10 * s, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
                maxLines: 2),
          ]),
        ),
      ),
    );
  }

  Widget _summaryDivider(double s) =>
      Container(width: 1, height: 44 * s, color: AppColors.divider);

  // ── 이번 주 근무 ────────────────────────────────────────────────
  Widget _buildWeeklyRoster(BuildContext context, double s, ThemeData theme) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 일요일 기준 주 시작 (Dart weekday: 1=월~7=일)
    final daysSinceSunday = now.weekday == 7 ? 0 : now.weekday;
    final weekStart = today.subtract(Duration(days: daysSinceSunday));
    const weekLabels = ['일', '월', '화', '수', '목', '금', '토'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, s, '이번 주 근무',
            action: '전체 보기',
            onAction: () => _safeNavigate(() => _requireApprovedBusiness(
                context,
                () async => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const IntegratedWorkforceScreen()))))),
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
                // ── 요약 스트립 ──
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: 16 * s, vertical: 11 * s),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.07),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28 * s,
                        height: 28 * s,
                        decoration: BoxDecoration(
                          color: theme.primaryColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.calendar_today_outlined,
                            color: Colors.white, size: 14 * s),
                      ),
                      SizedBox(width: 10 * s),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('이번 주 총 근무자',
                                style: TextStyle(
                                    fontSize: 11 * s,
                                    fontWeight: FontWeight.w700,
                                    color: theme.primaryColor)),
                            Text('확정 근무자 합산',
                                style: TextStyle(
                                    fontSize: 10 * s,
                                    color: AppColors.grey500)),
                          ],
                        ),
                      ),
                      _weeklyLoading
                          ? SizedBox(
                              width: 16 * s,
                              height: 16 * s,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: theme.primaryColor),
                            )
                          : Text(
                              '$_weeklyTotal명',
                              style: TextStyle(
                                  fontSize: 18 * s,
                                  fontWeight: FontWeight.w800,
                                  color: theme.primaryColor,
                                  letterSpacing: -0.5),
                            ),
                    ],
                  ),
                ),
                // ── 7칸 날짜 그리드 ──
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      6 * s, 12 * s, 6 * s, 14 * s),
                  child: Row(
                    children: List.generate(7, (i) {
                      final date = weekStart.add(Duration(days: i));
                      final isToday = date.year == today.year &&
                          date.month == today.month &&
                          date.day == today.day;
                      final isWeekend = i == 0 || i == 6;
                      final count = _weeklyLoading
                          ? -1
                          : (_weeklyRosterCounts[_dateKey(date)] ?? 0);
                      return Expanded(
                        child: _buildDayCell(
                          context, s, theme,
                          label: weekLabels[i],
                          date: date,
                          count: count,
                          isToday: isToday,
                          isWeekend: isWeekend,
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDayCell(
    BuildContext context, double s, ThemeData theme, {
    required String label,
    required DateTime date,
    required int count, // -1 = 로딩 중
    required bool isToday,
    required bool isWeekend,
  }) {
    final isEmpty = count == 0;
    final isLoading = count < 0;

    final Color accentColor;
    if (isToday) {
      accentColor = theme.primaryColor;
    } else if (isWeekend && !isEmpty && !isLoading) {
      accentColor = AppColors.error;
    } else {
      accentColor = theme.primaryColor;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isLoading
          ? null
          : () => _safeNavigate(() => _requireApprovedBusiness(
              context, () async {
            final businesses = await _getBusinesses();
            if (businesses.isEmpty || !context.mounted) return;
            await showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => AttendanceStatusDialog(
                date: date,
                businessIds: businesses.map((b) => b.id).toList(),
                businesses: businesses,
              ),
            );
          })),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10 * s,
                  fontWeight: FontWeight.w600,
                  color: (!isLoading && !isEmpty && isWeekend)
                      ? AppColors.error
                      : AppColors.grey400)),
          SizedBox(height: 5 * s),
          Container(
            width: 28 * s,
            height: 28 * s,
            decoration: BoxDecoration(
              color: isToday ? theme.primaryColor : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${date.day}',
                style: TextStyle(
                    fontSize: 13 * s,
                    fontWeight: FontWeight.w800,
                    color: isToday
                        ? Colors.white
                        : (!isLoading && !isEmpty && isWeekend)
                            ? AppColors.error
                            : (!isLoading && isEmpty)
                                ? AppColors.grey300
                                : AppColors.textPrimary),
              ),
            ),
          ),
          SizedBox(height: 5 * s),
          // 인원 뱃지
          isLoading
              ? Container(
                  width: 20 * s,
                  height: 13 * s,
                  decoration: BoxDecoration(
                    color: AppColors.grey100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                )
              : Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: 4 * s, vertical: 2 * s),
                  decoration: BoxDecoration(
                    color: isEmpty
                        ? Colors.transparent
                        : accentColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isEmpty ? '-' : '$count명',
                    style: TextStyle(
                        fontSize: 9.5 * s,
                        fontWeight: FontWeight.w700,
                        color: isEmpty ? AppColors.grey300 : accentColor),
                  ),
                ),
          SizedBox(height: 4 * s),
          // 점 인디케이터
          Container(
            width: 4 * s,
            height: 4 * s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (isLoading || isEmpty) ? Colors.transparent : accentColor,
            ),
          ),
        ],
      ),
    );
  }

}

// ── 계약서 미발송 배지 카드 ────────────────────────────────────────
class _UnsentContractBadgeCard extends StatefulWidget {
  final double cardHeight;
  final List<String> businessIds;
  final void Function(VoidCallback reload) onTap;

  const _UnsentContractBadgeCard({
    required this.cardHeight,
    required this.businessIds,
    required this.onTap,
  });

  @override
  State<_UnsentContractBadgeCard> createState() =>
      _UnsentContractBadgeCardState();
}

class _UnsentContractBadgeCardState extends State<_UnsentContractBadgeCard> {
  int _count = 0;
  final _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadCount();
    });
  }

  @override
  void didUpdateWidget(_UnsentContractBadgeCard old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.businessIds, widget.businessIds)) _loadCount();
  }

  Future<void> _loadCount() async {
    if (widget.businessIds.isEmpty) return;
    if (!context.read<UserProvider>().can((p) => p.canManageContract)) return;
    final counts = await Future.wait(
      widget.businessIds.map((bizId) async {
        try {
          final apps =
              await _firestoreService.getUnsentApplicationsByBusiness(bizId);
          return apps.length;
        } catch (e) {
          debugPrint('⚠️ 계약서 미발송 배지 조회 실패 ($bizId): $e');
          return 0;
        }
      }),
    );
    final total = counts.fold<int>(0, (acc, n) => acc + n);
    if (mounted) setState(() => _count = total);
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.cardHeight;
    final iconCircle = ch * 0.38;
    final iconPad = iconCircle * 0.22;
    final iconSizePx = iconCircle - iconPad * 2;
    final vPad = ch * 0.08;
    final gap1 = ch * 0.07;
    final gap2 = ch * 0.03;
    final titleSize = (ch * 0.13).clamp(11.0, 16.0);
    final subSize = (ch * 0.10).clamp(9.0, 13.0);

    final card = Card(
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: () => widget.onTap(_loadCount),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: vPad),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: iconCircle,
                  height: iconCircle,
                  padding: EdgeInsets.all(iconPad),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .primaryColor
                        .withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.folder_outlined,
                      size: iconSizePx,
                      color: Theme.of(context).primaryColor),
                ),
                SizedBox(height: gap1),
                Text('계약서 관리',
                    style: TextStyle(
                        fontSize: titleSize, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                SizedBox(height: gap2),
                Text('계약서 현황·서명',
                    style:
                        TextStyle(fontSize: subSize, color: AppColors.grey600),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );

    if (_count <= 0) return card;

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        card,
        Positioned(
          top: 10,
          right: 10,
          child: Semantics(
            label: '계약서 미발송 ${_count > 99 ? '99명 이상' : '$_count명'}',
            child: Container(
              constraints:
                  const BoxConstraints(minWidth: 20, minHeight: 20),
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: ExcludeSemantics(
                child: Text(
                  _count > 99 ? '99+' : '$_count',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 오늘 지급 배지 카드 ──────────────────────────────────────────
class _TodayPaymentBadgeCard extends StatefulWidget {
  final double cardHeight;
  final List<String> businessIds;
  final void Function(VoidCallback reload) onTap;

  const _TodayPaymentBadgeCard({
    required this.cardHeight,
    required this.businessIds,
    required this.onTap,
  });

  @override
  State<_TodayPaymentBadgeCard> createState() =>
      _TodayPaymentBadgeCardState();
}

class _TodayPaymentBadgeCardState extends State<_TodayPaymentBadgeCard> {
  int _count = 0;
  final _payrollService = PayrollPaymentService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadCount();
    });
  }

  @override
  void didUpdateWidget(_TodayPaymentBadgeCard old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.businessIds, widget.businessIds)) _loadCount();
  }

  Future<void> _loadCount() async {
    if (widget.businessIds.isEmpty) return;
    if (!context.read<UserProvider>().can((p) => p.canManageWage)) return;
    try {
      final counts = await Future.wait(widget.businessIds
          .map((id) => _payrollService.getTotalNotTransferredCount(businessId: id)));
      final total = counts.fold<int>(0, (acc, n) => acc + (n ?? 0));
      if (mounted) setState(() => _count = total);
    } catch (e) {
      debugPrint('⚠️ 미이체 배지 조회 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.cardHeight;
    final iconCircle = ch * 0.38;
    final iconPad = iconCircle * 0.22;
    final iconSizePx = iconCircle - iconPad * 2;
    final vPad = ch * 0.08;
    final gap1 = ch * 0.07;
    final gap2 = ch * 0.03;
    final titleSize = (ch * 0.13).clamp(11.0, 16.0);
    final subSize = (ch * 0.10).clamp(9.0, 13.0);

    final card = Card(
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: () => widget.onTap(_loadCount),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: vPad),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: iconCircle,
                  height: iconCircle,
                  padding: EdgeInsets.all(iconPad),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .primaryColor
                        .withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.account_balance_wallet_outlined,
                      size: iconSizePx,
                      color: Theme.of(context).primaryColor),
                ),
                SizedBox(height: gap1),
                Text('급여 관리',
                    style: TextStyle(
                        fontSize: titleSize, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                SizedBox(height: gap2),
                Text('월별 급여·지급 현황',
                    style:
                        TextStyle(fontSize: subSize, color: AppColors.grey600),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );

    if (_count <= 0) return card;

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        card,
        Positioned(
          top: 10,
          right: 10,
          child: Semantics(
            label: '미이체 ${_count > 99 ? '99명 이상' : '$_count명'}',
            child: Container(
              constraints:
                  const BoxConstraints(minWidth: 20, minHeight: 20),
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: ExcludeSemantics(
                child: Text(
                  _count > 99 ? '99+' : '$_count',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
