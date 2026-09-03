import 'dart:async' show unawaited;

import '../../services/fcm_service.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Providers
import '../../providers/user_provider.dart';

// Utils
import '../../utils/format_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/tour_helper.dart';
import '../common/tour_screen.dart';

// Services
import '../../services/firestore_service.dart';
import '../../utils/attendance_list_pdf.dart';

// Screens
import '../common/settings_screen.dart';
import 'to_management/create_to_screen.dart';
import 'workforce_management/workforce_root_screen.dart';
import '../common/notification_screen.dart';
import '../../widgets/common/notification_badge.dart';
import 'admin_stats_screen.dart';
import 'admin_contract_management_screen.dart';
import 'payroll/payroll_payment_dashboard_screen.dart';
// payroll_payment_service.dart — home screen에서 직접 사용 없음 (canonical summary로 대체됨)
import '../../theme/app_colors.dart';
import '../../utils/business_picker_helper.dart';
import '../../models/core/business_model.dart';
import 'support_review_queue_screen.dart';
import 'unclosed_action_queue_screen.dart';
import 'expiring_contracts_screen.dart';
import 'dialogs/attendance_status_dialog.dart';
import 'Business_form_screen.dart';
import 'work_type_management_screen.dart';
import '../../services/admin_home_summary_service.dart';
import '../../services/business_posting_readiness.dart';
import '../../models/ui/admin_home_summary_model.dart';
import 'widgets/business_action_drill_down_sheet.dart';
import '../../widgets/common/business_selector_sheet.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/admin_tab_switcher.dart';
import '../../controllers/workforce_controller.dart';

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
  bool? _hasApprovedBusiness;
  List<BusinessModel> _businesses = [];
  bool _isNavigating = false;

  // [5D.2A] 공고 등록 준비 — 사업장별 readiness (서버 5D.1A 정책과 동일)
  // isApproved + (canonical license OR owner legacy) + active workTypes >= 1
  Map<String, BusinessPostingReadiness> _bizReadiness = {};
  bool _readinessLoaded = false;

  // 오늘 운영 카운트 — activeTO만 legacy 로더 유지, 나머지는 canonical
  int _summaryActiveTO = 0;
  bool _summaryLoading = true;

  // [PATCH-R2] HOME-COUNT-FRESHNESS-01 — Posting global revision listener
  // WorkforceController.dataRevision 변경 시 Home summary를 자동 갱신한다.
  // _lastSeenPostingRevision: mount 시점 revision 이전 신호는 무시 (과거 replay 방지)
  // _summaryRequestGeneration: 비동기 summary 요청 중 stale overwrite 방지 (latest-wins)
  int _lastSeenPostingRevision = 0;
  int _summaryRequestGeneration = 0;

  // [PHASE-2C] Canonical Action Summary — 4개 Action 셀의 정규 source
  // unsentContract / unpaidWage / wageChangeRequest / settlementRequest
  AdminHomeSummaryModel? _canonicalSummary;
  bool _canonicalSummaryLoading = true;

  // 이번 주 근무
  Map<String, int> _weeklyRosterCounts = {};
  int _weeklyTotal = 0;
  bool _weeklyLoading = true;

  // 새로고침 동시 실행 방어 + 자동 쿨다운
  bool _isRefreshing = false;
  DateTime? _lastAutoRefreshAt;

  late final VoidCallback _onFcmRefresh;

  // [PH1C] SUB_ADMIN 사업장 전환 감지 — provider listener 패턴
  // nullable: addPostFrameCallback 실행 전 dispose 엣지케이스 방어
  UserProvider? _cachedUp;
  String? _renderedEffectiveBizId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _onFcmRefresh = () { if (mounted) _autoRefresh(); };
    FCMService().addAdminRefreshListener(_onFcmRefresh);
    // [PATCH-R2] HOME-COUNT-FRESHNESS-01 — posting revision listener 등록
    // mount 시점 revision 캡처 → 이후 변경만 수신 (과거 신호 replay 방지)
    _lastSeenPostingRevision = WorkforceController.dataRevision.value;
    WorkforceController.dataRevision.addListener(_onPostingRevisionChanged);
    AttendanceListPdf.preloadFonts();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // [PH1C] 사업장 전환 감지 초기화 — 최초 렌더 전 기준값 확정
      _cachedUp = context.read<UserProvider>();
      _renderedEffectiveBizId = _cachedUp!.effectiveBusinessId;
      _cachedUp!.addListener(_onBusinessSwitchCheck);

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
        unawaited(_loadSummaryCounts());      // activeTO only
        unawaited(_loadCanonicalSummary());   // [PHASE-2C] canonical actions
        unawaited(_loadWeeklyRosterCounts());
        unawaited(_loadPostingReadiness());   // [5D.2] compact setup checklist
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FCMService().removeAdminRefreshListener(_onFcmRefresh);
    // [PATCH-R2] posting revision listener 해제
    WorkforceController.dataRevision.removeListener(_onPostingRevisionChanged);
    // [PH1C] 사업장 전환 감지 리스너 해제 (postFrameCallback 실행 전 dispose 방어)
    _cachedUp?.removeListener(_onBusinessSwitchCheck);
    super.dispose();
  }

  // [PATCH-R2] HOME-COUNT-FRESHNESS-01 — global posting revision change handler
  // Jobs·Workforce 탭 경유 TO mutation(create/edit/close/delete/reopen) + Home quick-create 모두 수신.
  // `_summaryLoading`으로 신호를 drop하지 않음 — async load 중에도 revision 수신 → 재요청 허용.
  // 중복·outdated 결과 방지는 _summaryRequestGeneration(latest-wins)이 담당.
  void _onPostingRevisionChanged() {
    final revision = WorkforceController.dataRevision.value;
    if (!mounted || revision <= _lastSeenPostingRevision) return;
    _lastSeenPostingRevision = revision;
    _loadSummaryCounts();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _autoRefresh();
  }

  // [PH1C] SUB_ADMIN 사업장 전환 감지 — effectiveBusinessId 변경 시 갱신
  // OWNER는 effectiveBusinessId가 항상 null → 오작동 없음
  // CF canonical summary는 전체 aggregate → 사업장 전환과 무관하지만 권한 변경 등
  // 연관 상태 변화가 동반될 수 있으므로 함께 갱신
  void _onBusinessSwitchCheck() {
    if (!mounted) return;
    final newBizId = _cachedUp?.effectiveBusinessId;
    if (newBizId == _renderedEffectiveBizId) return;
    _renderedEffectiveBizId = newBizId;
    // _businesses 캐시 초기화 → 새 사업장 기준 재조회
    setState(() => _businesses = []);
    _loadApprovedBusinessStatus();
    unawaited(_loadSummaryCounts());
    unawaited(_loadWeeklyRosterCounts());
    unawaited(_loadPostingReadiness());
    unawaited(_loadCanonicalSummary());
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
        _loadCanonicalSummary(),
        _loadWeeklyRosterCounts(),
      ]);
    } finally {
      _isRefreshing = false;
    }
  }

  // [PHASE-2C] Canonical Action Summary 로드 (4개 Action 셀: unsentContract/unpaidWage/wageChangeRequest/settlementRequest)
  // 실패 시 _canonicalSummary = null 유지 — false zero 방지
  Future<void> _loadCanonicalSummary() async {
    if (!mounted) return;
    setState(() => _canonicalSummaryLoading = true);
    try {
      // [PH1D] SUB_ADMIN: effectiveBusinessId scope → 서버가 membership 검증 후 단일 사업장 집계
      // OWNER: null → 기존 전체 aggregate 유지
      final up = context.read<UserProvider>();
      final selectedBizId = up.currentUser?.isSubAdmin == true
          ? up.effectiveBusinessId
          : null;
      final summary = await AdminHomeSummaryService().fetchSummary(
        selectedBusinessId: selectedBizId,
      );
      if (!mounted) return;
      setState(() {
        _canonicalSummary = summary;
        _canonicalSummaryLoading = false;
      });
    } catch (e) {
      debugPrint('❌ _loadCanonicalSummary 실패: $e');
      if (!mounted) return;
      setState(() {
        _canonicalSummary = null; // 에러 상태 유지 — 0건으로 표시 금지
        _canonicalSummaryLoading = false;
      });
    }
  }

  // [PHASE-2C] canonical summary 준비 여부 확인.
  // 미준비(로딩 중 / 실패)이면 에러 UX 표시 후 false 반환.
  bool _ensureCanonicalSummary(BuildContext ctx) {
    if (_canonicalSummaryLoading) {
      ToastHelper.showInfo('데이터를 불러오는 중입니다...');
      return false;
    }
    if (_canonicalSummary != null) return true;
    // null + loading=false → 로드 실패
    _showCanonicalError(ctx);
    return false;
  }

  // [PHASE-2C] canonical summary 로드 실패 시 Snackbar + 재시도
  void _showCanonicalError(BuildContext ctx) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: const Text('업무 정보를 불러오지 못했어요'),
        action: SnackBarAction(
          label: '다시 시도',
          onPressed: () => unawaited(_loadCanonicalSummary()),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _loadApprovedBusinessStatus() async {
    final up = context.read<UserProvider>();
    if (up.currentUser?.uid == null) return;
    try {
      // SubAdmin: effectiveBusinessId 단일 ID 기준
      // BUSINESS_ADMIN: managedBusinessIds 전체
      final ids = up.currentUser?.isSubAdmin == true
          ? [if (up.effectiveBusinessId != null) up.effectiveBusinessId!]
          : (up.currentUser?.managedBusinessIds ?? []);
      final businesses = await _firestoreService.getBusinessesByIds(ids);
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

  // [5D.2A] 승인 사업장별 readiness 로드 — 서버 5D.1A와 동일 정책
  // isApproved + (canonical license OR ownerId legacy) + active workTypes >= 1
  // 호출자(SubAdmin/co-admin) license는 fallback으로 사용하지 않음
  Future<void> _loadPostingReadiness() async {
    final approvedBizs = _businesses.where((b) => b.isApproved).toList();
    if (approvedBizs.isEmpty) return;
    final readinessMap = await BusinessPostingReadiness.forBusinesses(
      approvedBizs,
      _firestoreService,
    );
    if (mounted) {
      setState(() {
        _bizReadiness = readinessMap;
        _readinessLoaded = true;
      });
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

  // [PHASE-3A] activeTO만 로드 — approval/unclosed 등은 canonical summary에서
  // [PATCH-R2] latest-wins 보호: _summaryRequestGeneration으로 outdated async 결과 폐기.
  // 동시 호출 허용 — 가장 최근 호출의 결과만 setState에 반영.
  Future<void> _loadSummaryCounts() async {
    final myGeneration = ++_summaryRequestGeneration;

    final businesses = await _getBusinesses();
    if (businesses.isEmpty || !mounted) {
      if (mounted && myGeneration == _summaryRequestGeneration) {
        setState(() => _summaryLoading = false);
      }
      return;
    }
    final bizIds = businesses.map((b) => b.id).toList();
    try {
      final lists = await Future.wait(
        bizIds.map((id) => _firestoreService.getTOsByBusiness(id, activeOnly: true)),
      );
      final activeTO = lists.expand((l) => l).where((t) => t.status == 'ACTIVE').length;
      // latest-wins: 더 새로운 요청이 완료됐으면 이 결과를 버린다
      if (!mounted || myGeneration != _summaryRequestGeneration) return;
      setState(() {
        _summaryActiveTO = activeTO;
        _summaryLoading  = false;
      });
    } catch (e) {
      debugPrint('❌ 진행 공고 집계 실패: $e');
      if (mounted && myGeneration == _summaryRequestGeneration) {
        setState(() => _summaryLoading = false);
      }
    }
  }

Future<void> _loadWeeklyRosterCounts() async {
    final businesses = await _getBusinesses();
    if (businesses.isEmpty || !mounted) {
      if (mounted) setState(() => _weeklyLoading = false);
      return;
    }

    final now = DateTime.now();
    final today = FormatHelper.toKstDate(now);
    // 일요일 기준 주 시작 (Dart weekday: 1=월~7=일) — KST 기준 요일 사용
    final daysSinceSunday = today.weekday == 7 ? 0 : today.weekday;
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
    final up = context.read<UserProvider>();
    // SubAdmin: effectiveBusinessId 단일 ID, BUSINESS_ADMIN: managedBusinessIds 전체
    final ids = up.currentUser?.isSubAdmin == true
        ? [if (up.effectiveBusinessId != null) up.effectiveBusinessId!]
        : (up.currentUser?.managedBusinessIds ?? []);
    try {
      final businesses = await _firestoreService.getBusinessesByIds(ids);
      _businesses = businesses; // 캐시만 갱신 — UI에 직접 영향 없으므로 setState 불필요
      return businesses;
    } catch (e) {
      debugPrint('❌ _getBusinesses 조회 실패: $e');
      return []; // 빈 리스트 반환 → 호출부에서 loading=false 처리
    }
  }

  /// STATE P/A/B/C 체크 — 모든 기능 진입 전 공통 게이트
  Future<void> _requireApprovedBusiness(
      BuildContext context, Future<void> Function() proceed) async {
    final up = context.read<UserProvider>();
    // STATE P: 계정 확인 대기 (외국인)
    if (up.currentUser?.accountStatus == 'pending') {
      ToastHelper.showWarning('계정 확인이 완료되면 이용하실 수 있어요.');
      return;
    }
    // 사업장 정보 로딩 중
    if (_hasApprovedBusiness == null) {
      ToastHelper.showWarning('사업장 정보를 불러오는 중입니다. 잠시 후 다시 시도해주세요.');
      return;
    }
    // STATE A: 사업장 없음
    if (_businesses.isEmpty) {
      // SUB_ADMIN은 사업장을 직접 등록하지 않음 — 배정 정보 확인 안내
      ToastHelper.showWarning(
        up.currentUser?.isSubAdmin == true
            ? '사업장 정보를 확인할 수 없습니다. 관리자에게 문의해주세요.'
            : '먼저 사업장을 등록해주세요.',
      );
      return;
    }
    // STATE B: 사업장 승인 대기
    if (!_hasApprovedBusiness!) {
      ToastHelper.showWarning('사업장이 승인 완료되면 이용하실 수 있어요.');
      return;
    }
    // STATE C: 정상
    await proceed();
  }

  // ── STATE P/A/B 배너 ───────────────────────────────────────────

  /// STATE-specific 배너: STATE C(정상) → SizedBox.shrink()
  Widget _buildStateBanner(BuildContext context, double s, ThemeData theme, UserProvider up) {
    final accountPending = up.currentUser?.accountStatus == 'pending';

    // STATE P: 계정 확인 대기 (외국인)
    if (accountPending) {
      return _stateBannerCard(context, s,
          icon: Icons.access_time,
          iconColor: AppColors.warning,
          title: '계정 확인 중',
          subtitle: '신분증 확인 완료 후 모든 기능을 이용할 수 있어요.',
          bgColor: AppColors.warning.withValues(alpha: 0.08),
          borderColor: AppColors.warning.withValues(alpha: 0.30));
    }

    if (_hasApprovedBusiness == null) {
      return const SizedBox.shrink(); // 로딩 중 — 배너 없음
    }

    // STATE A: 사업장 없음 (SUB_ADMIN은 사업장 등록 CTA 불필요 — 소유권 없음)
    if (_businesses.isEmpty) {
      if (up.currentUser?.isSubAdmin == true) return const SizedBox.shrink();
      return _stateABanner(context, s, theme);
    }

    // STATE B: 사업장 승인 대기
    if (!_hasApprovedBusiness!) {
      return _stateBannerCard(context, s,
          icon: Icons.hourglass_top,
          iconColor: theme.primaryColor,
          title: '사업장 승인 대기 중',
          subtitle: '운영팀이 사업장을 검토하고 있어요. 승인 완료 후 모든 기능을 이용할 수 있어요.',
          bgColor: theme.primaryColor.withValues(alpha: 0.06),
          borderColor: theme.primaryColor.withValues(alpha: 0.20));
    }

    return const SizedBox.shrink(); // STATE C: 배너 없음
  }

  /// STATE A: 사업장 등록 CTA 배너
  Widget _stateABanner(BuildContext context, double s, ThemeData theme) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20 * s, 0, 20 * s, 20 * s),
      child: Container(
        padding: EdgeInsets.all(16 * s),
        decoration: BoxDecoration(
          color: theme.primaryColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 36 * s, height: 36 * s,
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.business_outlined,
                    color: theme.primaryColor, size: 20 * s),
              ),
              SizedBox(width: 10 * s),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('사업장을 등록하세요',
                      style: TextStyle(
                          fontSize: 14 * s,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('사업장 등록 후 공고·계약·급여 관리를 시작하세요.',
                      style: TextStyle(
                          fontSize: 11 * s, color: AppColors.textSecondary)),
                ]),
              ),
            ]),
            SizedBox(height: 12 * s),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(Icons.add_business, size: 16 * s),
                label: Text('사업장 등록하기',
                    style: TextStyle(fontSize: 13 * s, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 10 * s),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _safeNavigate(() async {
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const BusinessFormScreen()));
                  if (mounted) _loadApprovedBusinessStatus();
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 공통 배너 카드 (STATE P, STATE B)
  Widget _stateBannerCard(BuildContext context, double s, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Color bgColor,
    required Color borderColor,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20 * s, 0, 20 * s, 20 * s),
      child: Container(
        padding: EdgeInsets.all(14 * s),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(children: [
          Icon(icon, color: iconColor, size: 22 * s),
          SizedBox(width: 10 * s),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 13 * s,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 11 * s, color: AppColors.textSecondary)),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── 드릴다운 헬퍼 (클래스 메서드, 이전엔 _buildTodaySummary 내부 클로저) ──
  Future<String?> _pickBizFromSummary({
    required BuildContext context,
    required String sheetTitle,
    required int totalCount,
    required List<String> bizIds,
    required Map<String, int> countPerBiz,
    String? secondaryLabel,
    Map<String, int>? secondaryCountPerBiz,
  }) async {
    if (bizIds.isEmpty) return null;
    if (bizIds.length == 1) return bizIds.first;
    final businesses = await _getBusinesses();
    final nameMap = {for (final b in businesses) b.id: b.name};
    final items = bizIds.map((id) => BizDrillDownItem(
      businessId:     id,
      businessName:   nameMap[id] ?? id,
      count:          countPerBiz[id] ?? 0,
      secondaryCount: secondaryCountPerBiz?[id],
      secondaryLabel: secondaryLabel,
    )).toList();
    if (!context.mounted) return null;
    return BusinessActionDrillDownSheet.show(
      context, title: sheetTitle, totalCount: totalCount, items: items,
    );
  }

  Future<void> _toPayrollTabDrilldown({
    required BuildContext context,
    required int tab,
    required String sheetTitle,
    required List<String> bizIds,
    required Map<String, int> countPerBiz,
    bool showAllOutstanding = false,
    bool showPendingSettlementOnly = false,
    String? secondaryLabel,
    Map<String, int>? secondaryCountPerBiz,
  }) async {
    final up = context.read<UserProvider>();
    if (!up.can((p) => p.canManageWage)) {
      ToastHelper.showWarning('급여 관리 권한이 없습니다.');
      return;
    }
    final now = DateTime.now();
    final bizId = await _pickBizFromSummary(
      context:              context,
      sheetTitle:           sheetTitle,
      totalCount:           countPerBiz.values.fold(0, (a, b) => a + b),
      bizIds:               bizIds,
      countPerBiz:          countPerBiz,
      secondaryLabel:       secondaryLabel,
      secondaryCountPerBiz: secondaryCountPerBiz,
    );
    if (bizId == null || !context.mounted) return;
    final businesses = await _getBusinesses();
    final bizName = businesses.where((b) => b.id == bizId).firstOrNull?.name;
    if (!context.mounted) return;
    // [NAV-POLICY-N1] Home Task → target domain tab context.
    // target tab popUntil(root) + switch bottom nav + push detail.
    // Back → PayrollOverviewScreen (정산 root). direct-push fallback 금지.
    // [HOME-PAYROLL-NAV-LIFECYCLE-01] route local variable 추출 — popped listener용
    final route = MaterialPageRoute<void>(
      builder: (_) => PayrollPaymentDashboardScreen(
        businessId:                bizId,
        businessName:              bizName,
        year:                      now.year,
        month:                     now.month,
        initialTab:                tab,
        showAllOutstanding:        showAllOutstanding,
        showPendingSettlementOnly: showPendingSettlementOnly,
      ),
    );
    final pushed = AdminTabSwitcher.instance.switchToTabAndPush(
      AdminTabSwitcher.payrollTab,
      route,
    );
    if (!pushed) {
      debugPrint(
        '[HomeNav] _toPayrollTabDrilldown: switchToTabAndPush 실패'
        ' — shell 미등록 또는 정산 탭 비가시',
      );
      return;
    }
    // [HOME-PAYROLL-NAV-LIFECYCLE-01] Dashboard pop 시 Home summary 갱신
    // route.popped: Dashboard가 Settlement Navigator에서 pop될 때 complete.
    // _safeNavigate lock과 독립 — navigation transaction 완료 후 즉시 해제.
    unawaited(
      route.popped.then((_) {
        if (!mounted) return;
        unawaited(_loadCanonicalSummary());
      }),
    );
  }

  // ── 반응형 스케일 ──────────────────────────────────────────────
  double _s(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
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
          backgroundColor: AppColors.grey50,
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(context, s, data.userName, up),
                    SizedBox(height: 12 * s),
                    _buildStateBanner(context, s, theme, up),
                    // [PH1] 준비 미완료 시 운영 섹션보다 먼저 인지되어야 함 (완료 시 자동 숨김)
                    _buildPostingSetupCard(context, s, theme),
                    _buildTodayOperation(context, s, theme),
                    SizedBox(height: 16 * s),
                    _buildActionDashboard(context, s, theme, up),
                    _buildUpcomingSection(context, s, theme),
                    SizedBox(height: 16 * s),
                    _buildWeeklyRoster(context, s, theme),
                    SizedBox(height: 16 * s),
                    _buildQuickMenu(context, s, theme, up),
                    SizedBox(height: 32 * s), // Bottom Nav가 gesture bar padding 내부 처리
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 헤더 (white base — [PHASE-3A])
  // ─────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, double s, String name, UserProvider up) {
    final theme = Theme.of(context);
    final isSub = up.currentUser?.isSubAdmin == true;
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(20 * s, 8 * s, 16 * s, 12 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단: 로고 + 알림/프로필 버튼
          Row(children: [
            ClipOval(
              child: Image.asset('assets/icons/app_icon.png',
                  width: 24 * s, height: 24 * s, fit: BoxFit.cover),
            ),
            SizedBox(width: 7 * s),
            Text('ALfit',
                style: TextStyle(
                    fontSize: 17 * s,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.5)),
            const Spacer(),
            NotificationBadge(
              child: _headerBtn(context, s, Icons.notifications_outlined,
                  onTap: () => _safeNavigate(() async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const NotificationScreen()));
                  })),
            ),
            SizedBox(width: 6 * s),
            _headerBtn(context, s, Icons.person_outline,
                onTap: () => _safeNavigate(() async {
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()));
                  if (mounted) _loadApprovedBusinessStatus();
                })),
          ]),
          SizedBox(height: 10 * s),
          // 인사말 + 배지 + [PH1] 사업장/권한 컨텍스트
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('안녕하세요,',
                style: TextStyle(
                    fontSize: 12 * s, color: AppColors.grey500)),
            SizedBox(height: 2 * s),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Flexible(
                child: Text('$name님',
                    style: TextStyle(
                        fontSize: 22 * s,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              SizedBox(width: 8 * s),
              isSub ? _subAdminBadge(context, s, up, theme) : _adminBadge(s, theme),
            ]),
            // [PH1] Owner: 사업장 컨텍스트 (단일 이름 or "N개 사업장 관리")
            if (!isSub && _businesses.isNotEmpty) ...[
              SizedBox(height: 4 * s),
              Text(
                _businesses.length == 1
                    ? _businesses.first.name
                    : '${_businesses.length}개 사업장 관리',
                style: TextStyle(
                    fontSize: 12 * s,
                    color: AppColors.grey500,
                    fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            // [PH1] SubAdmin: 권한 요약 compact 1줄
            if (isSub && up.permissionsLoaded) ...[
              SizedBox(height: 4 * s),
              _buildPermissionSummaryLine(s, up),
            ],
          ]),
          // SubAdmin 전용: 모드 토글 (반응형 라우팅 기반)
          if (isSub) ...[
            SizedBox(height: 10 * s),
            Row(children: [
              const Spacer(),
              _buildSubAdminModeToggle(context, s, up, theme),
            ]),
          ],
        ],
      ),
    );
  }

  /// [PH1] SUB_ADMIN 권한 요약 한 줄 (compact)
  Widget _buildPermissionSummaryLine(double s, UserProvider up) {
    final perms = <String>[];
    if (up.can((p) => p.canManageTo)) perms.add('공고');
    if (up.can((p) => p.canManageWorkers)) perms.add('인력');
    if (up.can((p) => p.canManageWage)) perms.add('급여');
    if (up.can((p) => p.canManageContract)) perms.add('계약');
    if (up.can((p) => p.canCancelTransfer)) perms.add('이체취소');
    if (perms.isEmpty) return const SizedBox.shrink();
    return Text(
      '권한: ${perms.join(' · ')}',
      style: TextStyle(fontSize: 11 * s, color: AppColors.grey400),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _headerBtn(BuildContext context, double s, IconData icon,
      {required VoidCallback onTap}) {
    return Material(
      color: AppColors.grey100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(8 * s),
          child: Icon(icon, color: AppColors.textSecondary, size: 22 * s),
        ),
      ),
    );
  }

  Widget _adminBadge(double s, ThemeData theme) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.business_outlined, color: theme.primaryColor, size: 12 * s),
        SizedBox(width: 4 * s),
        Text('관리자',
            style: TextStyle(
                color: theme.primaryColor,
                fontSize: 11 * s,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── 하위관리자 배지 ────────────────────────────────────────────
  // [PH1C] context 파라미터 추가 — 멀티 사업장 탭 시 전환 다이얼로그 표시
  Widget _subAdminBadge(BuildContext context, double s, UserProvider up, ThemeData theme) {
    final bizIds = up.currentUser?.subAdminBusinessIds ?? [];
    final isMulti = bizIds.length > 1;
    final selId = up.effectiveBusinessId;
    final bizName = selId != null ? up.subAdminBusinessNames[selId] : null;

    final badge = Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.admin_panel_settings_outlined, color: theme.primaryColor, size: 12 * s),
        SizedBox(width: 4 * s),
        Text(
          bizName != null ? (isMulti ? '$bizName ▼' : bizName) : '하위관리자',
          style: TextStyle(
              color: theme.primaryColor, fontSize: 11 * s, fontWeight: FontWeight.w600),
        ),
      ]),
    );

    // 단일 사업장: 탭 불필요
    if (!isMulti) return badge;

    // [PH1D] 멀티 사업장: 배지 탭 → 공유 BusinessSelectorSheet (DialogHelper.showSheet 패턴)
    return GestureDetector(
      onTap: () async {
        final selected = await DialogHelper.showSheet<String>(
          context,
          builder: (ctx) => BusinessSelectorSheet(
            businessIds: bizIds,
            businessNames: up.subAdminBusinessNames,
            selectedBusinessId: selId,
          ),
        );
        if (selected == null || selected == selId || !context.mounted) return;
        // switchToAdminMode → notifyListeners → _onBusinessSwitchCheck가 갱신 처리
        await up.switchToAdminMode(selected);
      },
      child: badge,
    );
  }

  // ── 하위관리자 전용 모드 토글 (지원자 ↔ 관리자) ────────────────
  Widget _buildSubAdminModeToggle(
      BuildContext context, double s, UserProvider up, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _toggleOpt(s, theme, label: '지원자', selected: false,
            // toggleAdminMode → notifyListeners → AuthWrapper 반응형 라우팅 → UserRootScreen
            onTap: () => up.toggleAdminMode()),
        _toggleOpt(s, theme, label: '관리자', selected: true, onTap: () {}),
      ]),
    );
  }

  Widget _toggleOpt(double s, ThemeData theme,
      {required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 4 * s),
        decoration: BoxDecoration(
          color: selected ? theme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.grey500,
            fontSize: 12 * s,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
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

  // ── 빠른 메뉴 (compact) [PHASE-3A] ────────────────────────────
  Widget _buildQuickMenu(BuildContext context, double s, ThemeData theme, UserProvider up) {
    final isSub = up.currentUser?.isSubAdmin == true;
    final items = [
      if (!isSub || up.can((p) => p.canManageTo))
        (
          icon: Icons.post_add_outlined,
          label: '공고등록',
          tap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
            // [HOTFIX HOME.POSTING.ENTRY.1-R1] SUB_ADMIN: Home effectiveBusinessId를
            // CreateTO 최초 사업장으로 상속. OWNER: null → 기존 flow(ready-first) 유지.
            final initBizId = up.currentUser?.isSubAdmin == true
                ? up.effectiveBusinessId
                : null;
            await NavigationHelper.push<bool>(context,
                destination: AdminCreateTOScreen(initialBusinessId: initBizId),
                useRootNavigator: true,
                onReturn: (r) {
                  if (r != true) return;
                  ToastHelper.showSuccess('공고가 등록되었습니다');
                  // [PATCH-R2] Home quick-create → global revision bump.
                  // Home listener(_onPostingRevisionChanged) + JobsRoot/WorkforceRoot listener가
                  // 수신하여 각자 refresh — direct _loadSummaryCounts() 호출 없음.
                  WorkforceController.notifyDataChanged();
                });
          })),
        ),
      if (!isSub || up.can((p) => p.canManageContract))
        (
          icon: Icons.folder_copy_outlined,
          label: '계약서',
          tap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
            if (!up.can((p) => p.canManageContract)) {
              ToastHelper.showWarning('계약서 관리 권한이 없습니다.');
              return;
            }
            final bizId = isSub
                ? up.effectiveBusinessId
                : (await BusinessPickerHelper.pick(context))?.id;
            if (bizId == null || !context.mounted) return;
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => AdminContractManagementScreen(businessId: bizId)));
          })),
        ),
      if (!isSub || up.can((p) => p.canManageWorkers || p.canManageWage))
        (
          icon: Icons.bar_chart_outlined,
          label: '통계',
          tap: () => _safeNavigate(() =>
              _requireApprovedBusiness(context, () async => pushAdminStatsScreen(context))),
        ),
    ];

    return Column(children: [
      _sectionHeader(context, s, '빠른 메뉴'),
      SizedBox(height: 8 * s),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 16 * s),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 12 * s),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: items.map((item) => Expanded(
                child: GestureDetector(
                  onTap: item.tap,
                  behavior: HitTestBehavior.opaque,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 40 * s,
                      height: 40 * s,
                      decoration: BoxDecoration(
                        color: AppColors.grey100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(item.icon, size: 20 * s, color: AppColors.textSecondary),
                    ),
                    SizedBox(height: 6 * s),
                    Text(item.label,
                        style: TextStyle(
                            fontSize: 10 * s,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ]),
                ),
              )).toList(),
            ),
          ),
        ),
      ),
    ]);
  }

  // ── [5D.2] 공고 등록 준비 checklist ──────────────────────────────
  // 표시 조건: STATE C + readiness 로드 완료 + 미충족 사업장 ≥ 1
  // 서버 정책(5D.1A)과 동일: isApproved + license + workTypes
  // seal/template 는 서버가 강제하지 않으므로 체크리스트에서 제외
  Widget _buildPostingSetupCard(BuildContext context, double s, ThemeData theme) {
    // SUB_ADMIN은 사업장 소유 설정(사업자등록증·업무등록) 불필요
    if (context.read<UserProvider>().currentUser?.isSubAdmin == true) {
      return const SizedBox.shrink();
    }
    if (_hasApprovedBusiness != true) return const SizedBox.shrink();
    if (!_readinessLoaded) return const SizedBox.shrink();

    final approvedBizs = _businesses.where((b) => b.isApproved).toList();

    // 사업장별 gap 계산
    final gapBizs = <({BusinessModel biz, bool licenseMissing, bool workTypesMissing})>[];
    for (final biz in approvedBizs) {
      final r = _bizReadiness[biz.id];
      // r == null이면 로드 미완료 — _readinessLoaded 가드가 이미 처리함
      final licenseMissing = !(r?.hasLicense ?? false);
      final workTypesMissing = !(r?.hasActiveWorkTypes ?? false);
      if (licenseMissing || workTypesMissing) {
        gapBizs.add((biz: biz, licenseMissing: licenseMissing, workTypesMissing: workTypesMissing));
      }
    }

    if (gapBizs.isEmpty) return const SizedBox.shrink();

    final totalGaps = gapBizs.fold(0, (sum, r) => sum + (r.licenseMissing ? 1 : 0) + (r.workTypesMissing ? 1 : 0));
    final multipleApproved = approvedBizs.length > 1;

    return Padding(
      padding: EdgeInsets.fromLTRB(20 * s, 0, 20 * s, 16 * s),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12 * s),
          border: Border.all(color: AppColors.border, width: 0.8),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2),
          )],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더 — USER readiness card 문법 준용 (neutral + subtle warning badge)
            Padding(
              padding: EdgeInsets.fromLTRB(14 * s, 12 * s, 14 * s, 10 * s),
              child: Row(
                children: [
                  Container(
                    width: 24 * s, height: 24 * s,
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.checklist_rounded, size: 14 * s, color: theme.primaryColor),
                  ),
                  SizedBox(width: 8 * s),
                  Text(
                    '공고 등록 준비',
                    style: TextStyle(
                      fontSize: 13 * s,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  SizedBox(width: 6 * s),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 7 * s, vertical: 2 * s),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8 * s),
                    ),
                    child: Text(
                      '미완료 $totalGaps개',
                      style: TextStyle(
                        fontSize: 10.5 * s,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 0.5, color: AppColors.grey100),
            // 사업장별 gap 항목
            for (int bi = 0; bi < gapBizs.length; bi++) ...[
              if (bi > 0) Divider(height: 1, thickness: 0.5, color: AppColors.grey100),
              if (multipleApproved)
                Padding(
                  padding: EdgeInsets.fromLTRB(14 * s, 8 * s, 14 * s, 2 * s),
                  child: Text(
                    gapBizs[bi].biz.name,
                    style: TextStyle(
                      fontSize: 11 * s,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (gapBizs[bi].licenseMissing)
                _readinessItemTile(
                  context, s,
                  icon: Icons.article_outlined,
                  label: '사업자등록증 등록',
                  onTap: () async {
                    await NavigationHelper.push<void>(
                      context,
                      destination: BusinessFormScreen(business: gapBizs[bi].biz),
                    );
                    if (!mounted) return;
                    await _loadPostingReadiness();
                  },
                ),
              if (gapBizs[bi].workTypesMissing)
                _readinessItemTile(
                  context, s,
                  icon: Icons.work_outline_rounded,
                  label: '업무 등록',
                  onTap: () async {
                    await NavigationHelper.push<void>(
                      context,
                      destination: WorkTypeManagementScreen(
                        businessId: gapBizs[bi].biz.id,
                        businessName: gapBizs[bi].biz.name,
                      ),
                    );
                    if (!mounted) return;
                    await _loadPostingReadiness();
                  },
                ),
            ],
            SizedBox(height: 4 * s),
          ],
        ),
      ),
    );
  }

  Widget _readinessItemTile(
    BuildContext context,
    double s, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 9 * s),
        child: Row(
          children: [
            Icon(icon, size: 14 * s, color: AppColors.textSecondary),
            SizedBox(width: 8 * s),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5 * s,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 16 * s, color: AppColors.grey400),
          ],
        ),
      ),
    );
  }

  // ── [PHASE-3A] 오늘 운영 compact card ─────────────────────────
  Widget _buildTodayOperation(BuildContext context, double s, ThemeData theme) {
    final todayStr = _dateKey(FormatHelper.toKstDate(DateTime.now()));
    final todayCount = _weeklyLoading ? null : (_weeklyRosterCounts[todayStr] ?? 0);

    return Column(children: [
      _sectionHeader(context, s, '오늘 운영'),
      SizedBox(height: 8 * s),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 16 * s),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10, offset: const Offset(0, 3),
            )],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 14 * s),
            child: Row(children: [
              _operationStat(context, s, theme,
                icon: Icons.campaign_outlined,
                label: '진행 공고',
                value: '$_summaryActiveTO건',
                isLoading: _summaryLoading,
                color: theme.primaryColor,
                // [PATCH-R1] ADMIN.POSTING.ROUTE-INTEGRITY-01
                // Home "진행 공고" → canonical 공고 탭 전환 (JobsRootScreen)
                // Navigator.push(IntegratedWorkforceScreen) 제거 — bottom nav 불일치 해소
                onTap: () => _safeNavigate(() => _requireApprovedBusiness(
                  context, () async =>
                    AdminTabSwitcher.instance.switchToTab(AdminTabSwitcher.jobsTab),
                )),
              ),
              Container(width: 1, height: 36 * s, color: AppColors.divider),
              _operationStat(context, s, theme,
                icon: Icons.people_outlined,
                label: '오늘 확정',
                value: todayCount == null ? '-' : '$todayCount명',
                isLoading: _weeklyLoading,
                color: theme.primaryColor,
                onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
                  final businesses = await _getBusinesses();
                  if (businesses.isEmpty || !context.mounted) return;
                  await showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => AttendanceStatusDialog(
                      date: FormatHelper.toKstDate(DateTime.now()),
                      businessIds: businesses.map((b) => b.id).toList(),
                      businesses: businesses,
                    ),
                  );
                })),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _operationStat(BuildContext context, double s, ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
    required bool isLoading,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 2 * s),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 32 * s, height: 32 * s,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16 * s, color: color),
            ),
            SizedBox(width: 10 * s),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 10 * s, color: AppColors.grey500)),
              SizedBox(height: 2 * s),
              isLoading
                ? SizedBox(width: 14 * s, height: 14 * s,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: color))
                : Text(value, style: TextStyle(
                    fontSize: 17 * s, fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary, letterSpacing: -0.3)),
            ]),
          ]),
        ),
      ),
    );
  }

  // ── [PHASE-3A] 처리할 일 — 우선순위 액션 리스트 ─────────────────
  Widget _buildActionDashboard(
      BuildContext context, double s, ThemeData theme, UserProvider up) {
    final cs = _canonicalSummary;

    // 로딩 상태
    if (_canonicalSummaryLoading) {
      return Column(children: [
        _sectionHeader(context, s, '처리할 일'),
        SizedBox(height: 8 * s),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16 * s),
          child: Container(
            height: 56 * s,
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16),
            ),
            child: Center(child: SizedBox(width: 18 * s, height: 18 * s,
              child: CircularProgressIndicator(strokeWidth: 2, color: theme.primaryColor))),
          ),
        ),
      ]);
    }

    final rows = _makeActionRows(context, s, up, cs);

    return Column(children: [
      _sectionHeader(context, s, '처리할 일'),
      SizedBox(height: 8 * s),
      if (rows.isEmpty)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16 * s),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 14 * s),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              Icon(Icons.check_circle_outline, size: 18 * s, color: AppColors.grey300),
              SizedBox(width: 10 * s),
              Text('처리할 업무가 없어요',
                  style: TextStyle(fontSize: 13 * s, color: AppColors.grey400)),
            ]),
          ),
        )
      else
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16 * s),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10, offset: const Offset(0, 3),
              )],
            ),
            child: Column(
              children: rows.asMap().entries.map((e) =>
                _buildActionRowWidget(context, s, e.value, isLast: e.key == rows.length - 1)
              ).toList(),
            ),
          ),
        ),
    ]);
  }


  List<({IconData icon, String label, String? badge, String countStr,
      Color color, int count, bool available, VoidCallback onTap})>
  _makeActionRows(BuildContext context, double s, UserProvider up, AdminHomeSummaryModel? cs) {
    final result = <({IconData icon, String label, String? badge, String countStr,
        Color color, int count, bool available, VoidCallback onTap})>[];
    // [PH1] SUB_ADMIN 권한 게이트: 권한 없는 항목은 목록에서 제외
    // CF aggSimple()이 permCount==0(권한없음)과 실제 쿼리 실패를 모두 available:false로
    // 반환하기 때문에 클라이언트에서 먼저 권한 기반 필터링을 적용한다.
    final isSub = up.currentUser?.isSubAdmin == true;

    void add({
      required IconData icon, required String label, required Color color,
      String? badge, required int count, required bool available, required String countStr,
      required VoidCallback onTap,
    }) {
      if (available && count == 0) return; // valid 0 → 숨김
      result.add((icon: icon, label: label, badge: badge, countStr: countStr,
          color: color, count: count, available: available, onTap: onTap));
    }

    // 1. 급여 미이체 — canManageWage
    if (!isSub || up.can((p) => p.canManageWage)) {
      final wage = cs?.actions.unpaidWage;
      final wageParts = <String>[];
      if ((wage?.overdueCount ?? 0) > 0) wageParts.add('연체 ${wage!.overdueCount}건');
      if ((wage?.missingDueDateCount ?? 0) > 0) wageParts.add('지급일 확인 필요 ${wage!.missingDueDateCount}명');
      // [HOME-WAGE-01] 숨김 기준: count(지급일 있는 그룹) + missingDueDateCount(지급일 없는 유니크 유저) 합산.
      // wage.hasData == available && (count > 0 || missingDueDateCount > 0).
      // count만 보면 지급일 미설정 근로자가 있을 때 valid-0으로 오인해 숨겨짐.
      final wageTotal = (wage?.count ?? 0) + (wage?.missingDueDateCount ?? 0);
      add(
        icon: Icons.account_balance_wallet_outlined, label: '급여 미이체',
        color: AppColors.error, badge: wageParts.isNotEmpty ? wageParts.join(' · ') : null,
        count: wageTotal, countStr: '$wageTotal건',
        available: wage?.available ?? false,
        onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
          if (!_ensureCanonicalSummary(context)) return;
          final w = _canonicalSummary!.actions.unpaidWage;
          if (!w.available) { _showCanonicalError(context); return; }
          if (w.count == 0 && w.missingDueDateCount == 0) return;
          final affectedBiz = w.byBusiness.where((b) => b.count > 0 || b.missingDueDateCount > 0).toList();
          final countMap = <String, int>{for (final b in w.byBusiness) b.businessId: b.count};
          final missingMap = <String, int>{for (final b in w.byBusiness) b.businessId: b.missingDueDateCount};
          await _toPayrollTabDrilldown(
            context: context, tab: 0, sheetTitle: '급여 미이체',
            bizIds: affectedBiz.map((b) => b.businessId).toList(),
            countPerBiz: countMap, showAllOutstanding: true,
            secondaryLabel: '지급일 확인 필요', secondaryCountPerBiz: missingMap,
          );
        })),
      );
    }

    // 2. 마감 필요 — canManageWage (근무/정산 마감)
    if (!isSub || up.can((p) => p.canManageWage)) {
      final unclosed = cs?.actions.unclosed;
      add(
        icon: Icons.lock_open_outlined, label: '마감 필요',
        color: AppColors.error,
        badge: unclosed?.oldestDate != null ? '가장 오래된: ${unclosed!.oldestDate}' : null,
        count: unclosed?.count ?? 0, countStr: '${unclosed?.count ?? 0}일',
        available: unclosed?.available ?? false,
        onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
          final changed = await Navigator.push<bool>(context, UnclosedActionQueueScreen.route());
          if (changed == true && mounted) unawaited(_loadCanonicalSummary());
        })),
      );
    }

    // 3. 계약 미발송 — canManageContract
    if (!isSub || up.can((p) => p.canManageContract)) {
      final unsent = cs?.actions.unsentContract;
      add(
        icon: Icons.folder_off_outlined, label: '계약 미발송',
        color: AppColors.warning,
        count: unsent?.count ?? 0, countStr: '${unsent?.count ?? 0}명',
        available: unsent?.available ?? false,
        onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
          if (!up.can((p) => p.canManageContract)) {
            ToastHelper.showWarning('계약서 관리 권한이 없습니다.'); return;
          }
          if (!_ensureCanonicalSummary(context)) return;
          final sec = _canonicalSummary!.actions.unsentContract;
          if (!sec.available) { _showCanonicalError(context); return; }
          if (sec.count == 0) return;
          final unsentBiz = sec.byBusiness.where((b) => b.count > 0).toList();
          final countMap = <String, int>{for (final b in sec.byBusiness) b.businessId: b.count};
          final bizId = await _pickBizFromSummary(
            context: context, sheetTitle: '계약 미발송', totalCount: sec.count,
            bizIds: unsentBiz.map((b) => b.businessId).toList(), countPerBiz: countMap,
          );
          if (bizId == null || !context.mounted) return;
          final businesses = await _getBusinesses();
          final bizName = businesses.where((b) => b.id == bizId).firstOrNull?.name;
          if (!context.mounted) return;
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => AdminContractManagementScreen(
                businessId: bizId, businessName: bizName, initialTab: 1),
          ));
          if (mounted) unawaited(_loadCanonicalSummary());
        })),
      );
    }

    // 4. 중간정산 요청 — canManageWage
    if (!isSub || up.can((p) => p.canManageWage)) {
      final settle = cs?.actions.settlementRequest;
      add(
        icon: Icons.account_balance_outlined, label: '중간정산 요청',
        color: AppColors.info,
        count: settle?.count ?? 0, countStr: '${settle?.count ?? 0}건',
        available: settle?.available ?? false,
        onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
          if (!_ensureCanonicalSummary(context)) return;
          final sec = _canonicalSummary!.actions.settlementRequest;
          if (!sec.available) { _showCanonicalError(context); return; }
          if (sec.count == 0) return;
          final bizIds = sec.byBusiness.where((b) => b.count > 0).map((b) => b.businessId).toList();
          final countMap = <String, int>{for (final b in sec.byBusiness) b.businessId: b.count};
          await _toPayrollTabDrilldown(
            context: context, tab: 3, sheetTitle: '중간정산 요청',
            bizIds: bizIds, countPerBiz: countMap, showPendingSettlementOnly: true,
          );
        })),
      );
    }

    // 5. 지원 검토 — canManageTo
    if (!isSub || up.can((p) => p.canManageTo)) {
      final approval = cs?.actions.approval;
      add(
        icon: Icons.assignment_late_outlined, label: '지원 검토',
        color: AppColors.warning,
        badge: (approval?.overdueCount ?? 0) > 0 ? '긴급 ${approval!.overdueCount}건' : null,
        count: approval?.count ?? 0, countStr: '${approval?.count ?? 0}명',
        available: approval?.available ?? false,
        onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
          final businesses = await _getBusinesses();
          if (businesses.isEmpty || !context.mounted) return;
          final changed = await Navigator.push<bool>(context,
            SupportReviewQueueScreen.route(
              businessIds: businesses.map((b) => b.id).toList(),
              businesses: businesses,
            ),
          );
          if (changed == true && mounted) unawaited(_loadCanonicalSummary());
        })),
      );
    }

    // 6. 급여 변경 요청 — canManageWage
    if (!isSub || up.can((p) => p.canManageWage)) {
      final wageChg = cs?.actions.wageChangeRequest;
      add(
        icon: Icons.compare_arrows, label: '급여 변경 요청',
        color: AppColors.purple,
        count: wageChg?.count ?? 0, countStr: '${wageChg?.count ?? 0}건',
        available: wageChg?.available ?? false,
        onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
          if (!_ensureCanonicalSummary(context)) return;
          final sec = _canonicalSummary!.actions.wageChangeRequest;
          if (!sec.available) { _showCanonicalError(context); return; }
          if (sec.count == 0) return;
          final bizIds = sec.byBusiness.where((b) => b.count > 0).map((b) => b.businessId).toList();
          final countMap = <String, int>{for (final b in sec.byBusiness) b.businessId: b.count};
          await _toPayrollTabDrilldown(
            context: context, tab: 2, sheetTitle: '급여 변경 요청',
            bizIds: bizIds, countPerBiz: countMap,
          );
        })),
      );
    }

    return result;
  }

  Widget _buildActionRowWidget(
    BuildContext context, double s,
    ({IconData icon, String label, String? badge, String countStr,
      Color color, int count, bool available, VoidCallback onTap}) item,
    {required bool isLast}
  ) {
    return Column(children: [
      InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.only(
          topLeft:     Radius.circular(isLast ? 0 : 0),
          bottomLeft:  Radius.circular(isLast ? 16 : 0),
          bottomRight: Radius.circular(isLast ? 16 : 0),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 13 * s),
          child: Row(children: [
            Container(
              width: 36 * s, height: 36 * s,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, size: 18 * s, color: item.color),
            ),
            SizedBox(width: 12 * s),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.label, style: TextStyle(
                  fontSize: 14 * s, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              if (item.badge != null) ...[
                SizedBox(height: 2 * s),
                // [PH1] badge 텍스트에 item.color 적용 → 긴급 항목("연체 N건") 시각적 강조
                Text(item.badge!, style: TextStyle(fontSize: 10 * s, color: item.color.withValues(alpha: 0.85))),
              ],
            ])),
            SizedBox(width: 8 * s),
            if (!item.available)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
                decoration: BoxDecoration(
                  color: AppColors.grey100, borderRadius: BorderRadius.circular(8),
                ),
                child: Text('조회 실패', style: TextStyle(fontSize: 11 * s, color: AppColors.grey500)),
              )
            else
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 5 * s),
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(item.countStr, style: TextStyle(
                    fontSize: 13 * s, fontWeight: FontWeight.w800, color: item.color)),
              ),
            SizedBox(width: 4 * s),
            Icon(Icons.chevron_right, size: 18 * s, color: AppColors.grey400),
          ]),
        ),
      ),
      if (!isLast)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16 * s),
          child: Divider(height: 1, color: AppColors.border),
        ),
    ]);
  }

  // ── [PHASE-3A] 곧 확인할 일 — 계약 종료 예정 ──────────────────
  Widget _buildUpcomingSection(BuildContext context, double s, ThemeData theme) {
    if (_canonicalSummaryLoading) return const SizedBox.shrink();
    final section = _canonicalSummary?.upcoming.expiringContract;
    // section == null → 섹션 자체 없음. available && count == 0 → 유효 0건 → 숨김.
    // !available → 조회 실패 → 숨기지 않고 error row 표시 (false-zero 방지)
    if (section == null) return const SizedBox.shrink();
    if (section.available && section.count == 0) return const SizedBox.shrink();

    return Column(children: [
      SizedBox(height: 16 * s),
      _sectionHeader(context, s, '곧 확인할 일'),
      SizedBox(height: 8 * s),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 16 * s),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10, offset: const Offset(0, 3),
            )],
          ),
          child: InkWell(
            onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
              if (!_ensureCanonicalSummary(context)) return;
              final sec = _canonicalSummary!.upcoming.expiringContract;
              if (!sec.available) { _showCanonicalError(context); return; }
              if (sec.count == 0) return;
              // [PH1D] SUB_ADMIN: CF가 effectiveBusinessId scope로 집계 →
              // count/drill-through 모두 동일 scope (_getBusinesses = effectiveBusinessId)
              final businesses = await _getBusinesses();
              if (businesses.isEmpty || !context.mounted) return;
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => ExpiringContractsScreen(
                  businessIds: businesses.map((b) => b.id).toList(),
                  businesses: businesses,
                ),
              ));
            })),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 13 * s),
              child: Row(children: [
                Container(
                  width: 36 * s, height: 36 * s,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.calendar_month_outlined, size: 18 * s, color: AppColors.warning),
                ),
                SizedBox(width: 12 * s),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('계약 종료 예정', style: TextStyle(
                      fontSize: 13 * s, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  SizedBox(height: 2 * s),
                  Text('15일 이내 계약 종료 예정자', style: TextStyle(
                      fontSize: 10 * s, color: AppColors.textSecondary)),
                ])),
                SizedBox(width: 8 * s),
                // available==false: action row와 동일한 "조회 실패" chip
                if (!section.available)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
                    decoration: BoxDecoration(
                      color: AppColors.grey100, borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('조회 실패', style: TextStyle(fontSize: 11 * s, color: AppColors.grey500)),
                  )
                else
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 5 * s),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${section.count}명', style: TextStyle(
                        fontSize: 13 * s, fontWeight: FontWeight.w800, color: AppColors.warning)),
                  ),
                SizedBox(width: 4 * s),
                Icon(Icons.chevron_right, size: 18 * s, color: AppColors.grey400),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
  // ── 이번 주 근무 ────────────────────────────────────────────────
  Widget _buildWeeklyRoster(BuildContext context, double s, ThemeData theme) {
    final now = DateTime.now();
    final today = FormatHelper.toKstDate(now);
    // 일요일 기준 주 시작 (Dart weekday: 1=월~7=일) — KST 기준 요일 사용
    final daysSinceSunday = today.weekday == 7 ? 0 : today.weekday;
    final weekStart = today.subtract(Duration(days: daysSinceSunday));
    const weekLabels = ['일', '월', '화', '수', '목', '금', '토'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, s, '이번 주 근무',
            action: '전체 보기',
            // [PATCH-R2A1] ADMIN.POSTING.ROUTE-INTEGRITY-01
            // Home "이번 주 근무" → canonical 인력 탭 전환 (WorkforceRootScreen)
            // Shell active: workforceTab 전환 / Shell 미활성: WorkforceRootScreen standalone push
            onAction: () => _safeNavigate(() => _requireApprovedBusiness(
                context,
                () async {
                  if (!AdminTabSwitcher.instance.switchToTab(
                      AdminTabSwitcher.workforceTab)) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WorkforceRootScreen(),
                      ),
                    );
                  }
                }))),
        SizedBox(height: 12 * s),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20 * s),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
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
                            Text('이번 주 확정',
                                style: TextStyle(
                                    fontSize: 11 * s,
                                    fontWeight: FontWeight.w700,
                                    color: theme.primaryColor)),
                            Text('일별 확정 합계',
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

