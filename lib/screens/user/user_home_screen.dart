import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/fcm_service.dart';

import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/to_model.dart';
import '../../models/core/user_model.dart';
import '../../models/core/user_region.dart';
import '../../utils/format_helper.dart';
import '../../providers/user_provider.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/section_header.dart';
import '../../utils/attendance_list_pdf.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/tour_helper.dart';
import '../../widgets/auth/account_status_banner.dart';
import '../../widgets/common/notification_badge.dart';
import '../../widgets/user/cards/job_image_placeholder.dart';
import '../common/notification_screen.dart';
import '../common/document_management_screen.dart';
import '../common/job_posting_screen.dart';
import '../../utils/navigation_helper.dart';
import '../business_admin/business_admin_home_screen.dart';
import '../common/tour_screen.dart';
import 'attendance_check_screen.dart';
import 'my_applications_screen.dart';
import 'user_tab_scope.dart';
import '../../widgets/calendar/app_calendar.dart';
import '../../utils/calendar_helper.dart';
import 'income_detail_screen.dart';
import '../auth/pass_auth_recovery_screen.dart';

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
  List<TOModel> _publishedTos = [];
  /// businessId → BusinessModel 캐시 — 사업장 이미지·혜택 정보 표시용
  Map<String, BusinessModel> _businessCache = {};
  bool _isLoadingData = false;

  // ── 초대 카운트 (INVITED 상태 지원서 수) ────────────────────────
  int get _invitedCount =>
      _applications.where((a) => a.status == AppStatus.invited).length;

  // ── 캐시 필드 — _applications/_attendances 변경 시에만 재계산 ────────
  Set<DateTime> _cachedThisWeekEntryDates = {};
  Set<DateTime> _cachedThisWeekConfirmedDates = {};
  Set<DateTime> _cachedThisWeekPendingDates = {};
  List<ApplicationModel> _cachedRecentApplications = [];
  int _cachedPendingCount = 0;
  int _cachedConfirmedCount = 0;
  int _cachedContractPendingCount = 0;
  Map<String, int> _cachedWorkTypeStats = {};
  // STATE C — 날짜별 공고 수 (오늘 이후 60일 범위, _publishedTos 기반)
  final Map<DateTime, int> _toDateCounts = {};
  // STATE C — 확정 근무가 있는 날짜 Set (Green Dot Indicator용)
  // AppStatus.confirmedStatuses(confirmed, contractPending) 기준
  // contractPending은 계약 대기 상태이지만 시간 점유가 확정된 상태이므로 포함
  final Set<DateTime> _confirmedDateSet = {};
  // STATE C — Hero 7일 스트립의 시작일 (기본: 오늘)
  // 날짜 더보기 캘린더에서 범위 외 날짜 선택 시 해당 날짜로 이동
  late DateTime _stripStart;
  // STATE C — 선택된 날짜 (null = 미선택, CTA 숨김)
  DateTime? _selectedDateChip;

  // ── Priority Hero 캐시 ─────────────────────────────────────────
  // STATE B: 오늘 확정 근무 (출퇴근 CTA 표시)
  ApplicationModel? _heroTodayApp;
  // STATE A: 72시간 이내 미확인 신규 확정
  ApplicationModel? _heroNewConfirmApp;

  // STATE A "미확인" 추적 — SharedPreferences에 persist (앱 재시작 후에도 유지)
  Set<String> _seenConfirmIds = {};
  static const _kSeenKey = 'seen_confirm_ids_v1';

  void _rebuildCaches() {
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

    // ── Priority Hero 캐시 계산 ──────────────────────────────────
    // STATE B: 오늘 확정 근무 존재 여부 (출퇴근 CTA 최우선)
    final todayList = _applications.where((a) {
      if (!AppStatus.confirmedStatuses.contains(a.status)) return false;
      final wd = DateTime(a.workDate.year, a.workDate.month, a.workDate.day);
      return wd == today;
    }).toList();
    _heroTodayApp = todayList.isEmpty ? null : todayList.first;

    // STATE A: STATE B가 없을 때만 평가 — 72시간 이내 미확인 신규 확정
    if (_heroTodayApp == null) {
      final threshold = now.subtract(const Duration(hours: 72));
      final newList = _applications.where((a) =>
        a.status == AppStatus.confirmed &&
        a.confirmedAt != null &&
        a.confirmedAt!.isAfter(threshold) &&
        !_seenConfirmIds.contains(a.id),
      ).toList();
      _heroNewConfirmApp = newList.isEmpty ? null : newList.first;
    } else {
      _heroNewConfirmApp = null; // STATE B 우선이므로 A 캐시 클리어
    }

    // ── 추가 캐시 계산 ──────────────────────────────────────────────
    // 지원현황 카운트
    _cachedPendingCount = _applications.where((a) => a.status == AppStatus.pending).length;
    _cachedConfirmedCount = _applications.where((a) => AppStatus.confirmedStatuses.contains(a.status)).length;
    _cachedContractPendingCount = _applications.where((a) => a.status == AppStatus.contractPending).length;

    // 이번 주 PENDING dot
    _cachedThisWeekPendingDates = {};
    for (final app in _applications) {
      if (app.status != AppStatus.pending) continue;
      final wd = DateTime(app.workDate.year, app.workDate.month, app.workDate.day);
      if (!wd.isBefore(today) && !wd.isAfter(endDate)) {
        _cachedThisWeekPendingDates.add(wd);
      }
    }
    // CONFIRMED dot — _cachedThisWeekEntryDates 재활용
    _cachedThisWeekConfirmedDates = Set.from(_cachedThisWeekEntryDates);

    // 업무 경험 집계 (AttendanceModel.workType)
    _cachedWorkTypeStats = {};
    for (final att in _attendances) {
      // AttendanceModel은 applicationId 통해 workType 접근 — app 목록에서 찾음
      final app = _applications.where((a) => a.id == att.applicationId).firstOrNull;
      final wt = app?.selectedWorkType ?? '';
      if (wt.isNotEmpty) {
        _cachedWorkTypeStats[wt] = (_cachedWorkTypeStats[wt] ?? 0) + 1;
      }
    }

    // ── STATE C: 오늘 이후 60일 날짜별 지원 가능한 공고 수 ────────────
    // 섹션 헤더 "N개 모두보기"와 동일한 기준 사용 — 숫자 일관성 보장
    //   contract: rangeStart/rangeEnd + workDays 날짜 집계
    //   flex: rangeStart/rangeEnd 날짜 범위만 사용 (SlotModel 미로드 → 범위 근사)
    // 필터: _getRecommendedTos와 동일 — 마감·삭제·정원초과·이미지원 TO 제외
    _toDateCounts.clear();
    const dowLabels = ['월', '화', '수', '목', '금', '토', '일'];
    final cutoff = today.add(const Duration(days: 60));
    final appliedToIdsForCount = _applications.map((a) => a.toId).toSet();
    for (final to in _publishedTos) {
      // _getRecommendedTos와 동일한 후보 필터
      if (to.status == TOStatus.closed ||
          to.status == TOStatus.expired ||
          to.status == TOStatus.full ||
          to.status == TOStatus.scheduled) { continue; }
      if (to.isDeleted) { continue; }
      if (to.totalRequired > 0 && to.totalConfirmed >= to.totalRequired) { continue; }
      if (appliedToIdsForCount.contains(to.id)) { continue; }

      // 신규 preset: workStartAvailableFrom ~ Until / custom·legacy: rangeStart ~ rangeEnd
      final rangeS = to.hasWorkStartAvailableRange
          ? to.workStartAvailableFrom
          : to.rangeStart;
      final rangeE = to.hasWorkStartAvailableRange
          ? to.workStartAvailableUntil
          : to.rangeEnd;
      if (rangeS == null) continue;
      final effectiveStart = rangeS.isBefore(today) ? today : rangeS;
      final effectiveEnd = rangeE == null
          ? cutoff
          : (rangeE.isAfter(cutoff) ? cutoff : rangeE);
      if (effectiveStart.isAfter(effectiveEnd)) continue;
      var cur = effectiveStart;
      while (!cur.isAfter(effectiveEnd)) {
        final label = dowLabels[cur.weekday - 1];
        // contract: workDays 필터 적용 / flex: 날짜 범위만으로 집계
        if (to.type != 'contract' ||
            to.workDays.isEmpty ||
            to.workDays.contains(label)) {
          _toDateCounts[cur] = (_toDateCounts[cur] ?? 0) + 1;
        }
        cur = cur.add(const Duration(days: 1));
      }
    }

    // STATE C — 확정 근무 날짜 Set 계산
    // 날짜 스트립 Green Dot: 지원중/검토중 제외, 확정(confirmed+contractPending)만
    _confirmedDateSet.clear();
    for (final app in _applications) {
      if (AppStatus.confirmedStatuses.contains(app.status)) {
        final d = app.workDate;
        _confirmedDateSet.add(DateTime(d.year, d.month, d.day));
      }
    }
  }

  late final VoidCallback _onFcmRefresh;
  bool _isLoadingHomeData = false;
  DateTime? _lastAutoRefreshAt;

  @override
  void initState() {
    super.initState();
    // Hero 7일 스트립: 오늘부터 시작 (과거 없음)
    final now = DateTime.now();
    _stripStart = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addObserver(this);
    _onFcmRefresh = () { if (mounted) _autoRefresh(); };
    FCMService().addUserDataRefreshListener(_onFcmRefresh);
    AttendanceListPdf.preloadFonts();
    _initSeenIds(); // STATE A "미확인" 목록 복원 (SharedPreferences)
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

  // ── STATE A "미확인" 추적 (SharedPreferences) ─────────────────
  Future<void> _initSeenIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_kSeenKey) ?? [];
      if (!mounted) return;
      setState(() {
        _seenConfirmIds = ids.toSet();
        // seenIds 로드 후 Hero 캐시 재계산 — STATE A 노출 여부 갱신
        _rebuildCaches();
      });
    } catch (_) {
      // SharedPreferences 실패 시 빈 set 유지 (STATE A가 과도 표시될 수 있으나 치명적이지 않음)
    }
  }

  Future<void> _markConfirmSeen(String appId) async {
    if (_seenConfirmIds.contains(appId)) return;
    setState(() => _seenConfirmIds.add(appId));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kSeenKey, _seenConfirmIds.toList());
    } catch (_) {}
  }

  Future<void> _showTourDialog() async {
    await pushTourScreen(context, role: 'USER');
    if (!mounted) return;
    await TourHelper.markCompleted(TourHelper.userHome);
  }

  Future<void> _loadHomeData() async {
    if (_isLoadingHomeData) return; // 동시 실행 방어
    final uid = context.read<UserProvider>().currentUser?.uid;
    // 추천 점수 계산에 사용 — await 이전에 동기 캡처 (갱신 주기와 무관하게 안전)
    final user = context.read<UserProvider>().currentUser;
    if (uid == null || !mounted) return;
    _isLoadingHomeData = true;
    setState(() => _isLoadingData = true);
    final now = DateTime.now();
    try {
      final results = await Future.wait([
        _appFirestore.getMyApplications(uid),
        _appFirestore.getMyMonthlyAttendances(userId: uid, year: now.year, month: now.month),
        _appFirestore.getPublishedTOs(), // Hero C 날짜 카운트용
      ]);
      if (!mounted) return;
      final apps = results[0] as List<ApplicationModel>;
      final atts = results[1] as List<AttendanceModel>;
      final tos  = results[2] as List<TOModel>;
      // 캐시는 setState 전에 계산 — build 중 재계산 없이 준비된 값 사용
      _applications = apps;
      _attendances  = atts;
      _publishedTos = tos;
      _rebuildCaches();

      // ── BusinessModel 캐시 로드 — 추천 카드에 사업장 이미지·혜택 표시용
      // _getRecommendedTos 점수 기준 상위 8개 TO의 businessId만 로드한다.
      // · _getRecommendedTos는 _businessCache를 사용하지 않으므로 여기서 안전하게 호출 가능
      // · 홈에 표시되는 카드는 최대 2개이므로 상위 8개면 충분한 버퍼
      // · user가 null인 엣지케이스(로그인 직후 경쟁)에서는 전체 고유 ID 최대 8개로 폴백
      final List<String> targetBizIds;
      if (user != null) {
        final topTos = _getRecommendedTos(user);
        targetBizIds = topTos
            .map((t) => t.businessId)
            .toSet()
            .take(8)
            .toList();
      } else {
        targetBizIds = tos.map((t) => t.businessId).toSet().take(8).toList();
      }
      if (targetBizIds.isNotEmpty) {
        final bizResults = await Future.wait(
          targetBizIds.map((id) => _appFirestore.getBusinessById(id)),
        );
        if (!mounted) return;
        final cache = <String, BusinessModel>{};
        for (var i = 0; i < targetBizIds.length; i++) {
          final biz = bizResults[i];
          if (biz != null) cache[targetBizIds[i]] = biz;
        }
        _businessCache = cache;
      }

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
        final user = data.user;

        return Scaffold(
          backgroundColor: Colors.white,
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
                // PASS Recovery 배너 — 내국인 활성 계정 + passVerifiedAt 없음
                if (user != null && user.needsPassAuthRecovery)
                  _buildPassRecoveryBanner(context),
                // 흰 앱바 헤더 (시안 .ah)
                _buildHeader(context, s, user, up),
                Expanded(
                  child: RefreshIndicator(
                    // pull-to-refresh: 공개 공고 TTL 캐시 무효화 후 재로드
                    onRefresh: () {
                      _appFirestore.invalidatePublishedTOsCache();
                      return _loadHomeData();
                    },
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics()),
                      child: _buildUserBody(context, s, up),
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
  // PASS Recovery 배너
  // ─────────────────────────────────────────────────────────────
  Widget _buildPassRecoveryBanner(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF3E0), // 주황색 경고 배경 (AppColors.warningBg 유사)
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.verified_user_outlined,
                color: Color(0xFFE65100), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '본인인증이 필요합니다. 인증 완료 후 공고 지원이 가능합니다.',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFBF360C),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => const PassAuthRecoveryScreen(),
                  ),
                );
              },
              child: const Text('인증하기',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFE65100),
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 흰 앱바 헤더 (시안 .ah)
  // ─────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, double s, UserModel? user,
      UserProvider up) {
    return Container(
      padding: EdgeInsets.fromLTRB(20 * s, 10 * s, 12 * s, 10 * s),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          // 로고 아이콘 (앱 아이콘 asset 사용)
          Container(
            width: 32 * s, height: 32 * s,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.infoDark, AppColors.info],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            clipBehavior: Clip.hardEdge,
            child: Image.asset(
              'assets/icons/app_icon_foreground.png',
              width: 32 * s,
              height: 32 * s,
              fit: BoxFit.cover,
            ),
          ),
          SizedBox(width: 8 * s),
          Text('ALfit',
              style: TextStyle(
                fontSize: 20 * s,
                fontWeight: FontWeight.w900,
                color: AppColors.infoDark,
                letterSpacing: -0.6,
              )),
          const Spacer(),
          // SubAdmin 모드 토글 (서브어드민 전용) — 구현 계획서 주의사항
          if (up.isSubAdmin) ...[
            _buildModeToggle(context, s, up),
            SizedBox(width: 8 * s),
          ],
          // 알림 버튼
          NotificationBadge(
            child: _headerIconBtn(
                context, s, Icons.notifications_outlined, '알림',
                () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const NotificationScreen()))),
          ),
          // 내 정보 버튼 제거 — 하단 MY 탭이 공식 진입점으로 통일됨
        ],
      ),
    );
  }

  /// 흰 헤더용 아이콘 버튼 (dark icon on white bg)
  Widget _headerIconBtn(BuildContext context, double s, IconData icon,
      String label, VoidCallback onTap) {
    return Semantics(
      label: label,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.all(8 * s),
          child: Icon(icon, color: AppColors.textSecondary, size: 22 * s),
        ),
      ),
    );
  }

  // ── 모드 토글 (서브어드민 전용) — 흰 배경용 색상 ──────────────
  Widget _buildModeToggle(BuildContext context, double s, UserProvider up) {
    final isAdmin = up.isAdminMode;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
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
          color: selected ? AppColors.infoDark : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 12 * s,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────
  // 지원자 바디 — 시안 섹션 순서 그대로
  // ─────────────────────────────────────────────────────────────
  Widget _buildUserBody(BuildContext context, double s, UserProvider up) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ① 인사말
        _buildGreeting(context, s, up),
        // ② Priority Card — State B(오늘 출근) / State A(새 확정) / 없으면 사라짐
        // 날짜 탐색과 독립 — 확정이 있어도 아래 날짜 탐색은 항상 표시
        _buildPriorityCard(context, s, theme),
        // 지원 준비 Compact Card — 서류 미완료 시만 표시, 날짜 Hero 바로 위
        _buildReadinessCard(context, s, up),
        // ③ 날짜 기반 일자리 탐색 — 상시 노출 (신규/기존 회원 동일)
        _buildDateExplorer(context, s, theme),
        // 초대 배너 (INVITED 있을 때)
        _buildInviteBanner(context, s, theme),
        // ④ 일자리 발견 영역 — 날짜 탐색 바로 아래 고정
        // 날짜 선택 → "M월 D일 일자리" / 경험 있음 → "나에게 맞는 일" / 신규 → "지금 지원 가능한 일자리"
        _buildRecommendSection(context, s, up),
        // ⑤ 지원 현황 — 항상 일자리 발견 영역 아래
        Container(height: 8, color: AppColors.background),
        _buildApplicationStatus(context, s),
        // ④ 이번 주 일정 — 8dp 회색 구분 갭
        Container(height: 8, color: AppColors.background),
        _buildThisWeekSchedule(context, s, theme),
        // ⑤ 이번 달 수입 — 8dp 회색 구분 갭
        Container(height: 8, color: AppColors.background),
        _buildIncomeSection(context, s, theme),
        // ⑥ 나의 ALfit — 8dp 회색 구분 갭
        Container(height: 8, color: AppColors.background),
        _buildCareerSection(context, s, up),
        // 하단 여백 (흰 배경이므로 Scaffold와 동색)
        const SizedBox(height: 20),
      ],
    );
  }

  // ── 인사말 (시안 .greeting) ──────────────────────────────────
  Widget _buildGreeting(BuildContext context, double s, UserProvider up) {
    final user = up.currentUser;
    return Container(
      padding: EdgeInsets.fromLTRB(20 * s, 16 * s, 20 * s, 14 * s),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('안녕하세요,',
              style: TextStyle(
                fontSize: 13 * s,
                color: AppColors.textHint,
                fontWeight: FontWeight.w500,
              )),
          SizedBox(height: 2 * s),
          Text('${user?.name ?? '사용자'}님',
              style: TextStyle(
                fontSize: 22 * s,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.6,
              )),
        ],
      ),
    );
  }

  // ── 초대 배너 (INVITED 있을 때만 표시) ─────────────────────────
  Widget _buildInviteBanner(BuildContext context, double s, ThemeData theme) {
    final count = _invitedCount;
    if (count == 0) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(20 * s, 14 * s, 20 * s, 20 * s),
      child: GestureDetector(
        onTap: () => Navigator.of(context, rootNavigator: true).push(
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

  // ─────────────────────────────────────────────────────────────
  // Priority Hero — 3-state 카드 (시안 .hero-wrap)
  // STATE 우선순위: B(오늘 출퇴근) > A(새 확정 미확인) > C(기본)
  // ─────────────────────────────────────────────────────────────
  // ── Priority Card: State B(오늘 출근) / State A(새 확정) / 없으면 숨김 ──
  // 날짜 탐색(_buildDateExplorer)과 독립 — 확정이 있어도 날짜 탐색은 항상 노출
  Widget _buildPriorityCard(BuildContext context, double s, ThemeData theme) {
    // 로딩 중: skeleton (State B/A 여부 미확정이므로 자리 유지)
    if (_isLoadingData) {
      return Container(
        padding: EdgeInsets.all(16 * s),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: AppColors.borderLight)),
        ),
        child: Container(
          height: 90 * s,
          decoration: BoxDecoration(
            color: AppColors.grey100,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    }
    // State B: 오늘 출근 (최우선)
    if (_heroTodayApp != null) {
      return Container(
        padding: EdgeInsets.all(16 * s),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: AppColors.borderLight)),
        ),
        child: _buildHeroStateB(context, s, _heroTodayApp!),
      );
    }
    // State A: 새 확정 미확인
    if (_heroNewConfirmApp != null) {
      return Container(
        padding: EdgeInsets.all(16 * s),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: AppColors.borderLight)),
        ),
        child: _buildHeroStateA(context, s, _heroNewConfirmApp!),
      );
    }
    // 처리할 이벤트 없음 → 영역 자체 숨김
    return const SizedBox.shrink();
  }

  // ── 날짜 기반 일자리 탐색 — 상시 노출 (Priority Card와 독립) ──
  // 확정/출근 유무와 무관하게 항상 표시. ALfit의 핵심 탐색 기능.
  Widget _buildDateExplorer(BuildContext context, double s, ThemeData theme) {
    return Container(
      padding: EdgeInsets.all(16 * s),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: _buildHeroStateC(context, s, theme),
    );
  }

  // ── STATE B: 오늘 출퇴근 (시안 .hB) ──────────────────────────
  Widget _buildHeroStateB(BuildContext context, double s, ApplicationModel app) {
    final hasTime = app.startTime.isNotEmpty && app.endTime.isNotEmpty;

    // 카운트다운 진행 상태 계산
    String progressLabel = '출근 준비 중';
    double progressValue = 0.0;
    if (hasTime) {
      try {
        final now = DateTime.now();
        final today0 = DateTime(now.year, now.month, now.day);
        final sParts = app.startTime.split(':');
        final eParts = app.endTime.split(':');
        final startDt = today0.add(Duration(
            hours: int.parse(sParts[0]), minutes: int.parse(sParts[1])));
        final endDt = today0.add(Duration(
            hours: int.parse(eParts[0]), minutes: int.parse(eParts[1])));
        if (now.isBefore(startDt)) {
          final rem = startDt.difference(now);
          final h = rem.inHours;
          final m = rem.inMinutes % 60;
          progressLabel = h > 0 ? '출근까지 $h시간 $m분' : '출근까지 $m분';
        } else if (now.isAfter(endDt)) {
          progressLabel = '근무 완료';
          progressValue = 1.0;
        } else {
          final total = endDt.difference(startDt).inMinutes;
          final elapsed = now.difference(startDt).inMinutes;
          progressValue = total > 0 ? (elapsed / total).clamp(0.0, 1.0) : 0;
          final rem = endDt.difference(now);
          final h = rem.inHours;
          final m = rem.inMinutes % 60;
          progressLabel = h > 0 ? '퇴근까지 $h시간 $m분' : '퇴근까지 $m분';
        }
      } catch (_) {
        progressLabel = '출근 준비 중';
      }
    }

    return Container(
        padding: EdgeInsets.all(18 * s),
        decoration: BoxDecoration(
          // 시안 .hB: linear-gradient(150deg, #E8F0FE → #F0F4FF), 테두리 #BBDEFB
          gradient: const LinearGradient(
            colors: [Color(0xFFE8F0FE), Color(0xFFF0F4FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFBBDEFB), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 레이블 (시안 .hB-label)
            Row(children: [
              Container(
                width: 7 * s, height: 7 * s,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: AppColors.infoDark),
              ),
              SizedBox(width: 5 * s),
              Text('오늘의 근무',
                  style: TextStyle(
                    fontSize: 11 * s,
                    fontWeight: FontWeight.w700,
                    color: AppColors.infoDark,
                    letterSpacing: 0.5,
                  )),
            ]),
            SizedBox(height: 10 * s),
            // 제목 (시안 .hB-title) — "오늘 N:N 출근이에요"
            Text(
              hasTime ? '오늘 ${app.startTime} 출근이에요' : '오늘 근무가 있어요',
              style: TextStyle(
                fontSize: 20 * s,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
                height: 1.25,
              ),
            ),
            SizedBox(height: 3 * s),
            // 부제목 (시안 .hB-sub)
            Text(
              [
                if (app.selectedWorkType.isNotEmpty)
                  '${app.businessName} · ${app.selectedWorkType}'
                else
                  app.businessName,
                if (hasTime) '${app.startTime} – ${app.endTime}',
              ].join('  |  '),
              style: TextStyle(fontSize: 13 * s, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 14 * s),
            // 진행 박스 (시안 .hB-box)
            if (hasTime) ...[
              Container(
                padding: EdgeInsets.fromLTRB(13 * s, 11 * s, 13 * s, 13 * s),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.80),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(progressLabel,
                        style: TextStyle(
                          fontSize: 13 * s,
                          fontWeight: FontWeight.w700,
                          color: AppColors.infoDark,
                        )),
                    SizedBox(height: 8 * s),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progressValue,
                        minHeight: 6 * s,
                        backgroundColor: AppColors.infoBg,
                        color: AppColors.infoDark,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 14 * s),
            ],
            // 출근하기 버튼 (시안 .h-btn-primary)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const AttendanceCheckScreen())),
                icon: Icon(Icons.login_rounded, size: 18 * s),
                label: Text('출근하기',
                    style: TextStyle(
                        fontSize: 15 * s, fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.infoDark,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 13 * s),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      );
  }

  // ── STATE A: 새 확정 미확인 (시안 .hA — 연초록 카드) ───────────
  Widget _buildHeroStateA(BuildContext context, double s, ApplicationModel app) {
    final dateStr = '${app.workDate.month}월 ${app.workDate.day}일';
    final hasTime = app.startTime.isNotEmpty && app.endTime.isNotEmpty;
    final wageStr = FormatHelper.formatWage(app.wage);

    return GestureDetector(
      onTap: () async {
        // rootNavigator: true — 탭0 스택 오염 없이 루트 Navigator로 push
        final nav = Navigator.of(context, rootNavigator: true);
        await _markConfirmSeen(app.id);
        if (!mounted) return;
        await nav.push(
            MaterialPageRoute(builder: (_) => const MyApplicationsScreen()));
        if (!mounted) return;
        _rebuildCaches();
        setState(() {});
      },
      child: Container(
        padding: EdgeInsets.all(18 * s),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF0FBF1), Color(0xFFFAFFFE), Color(0xFFF5FBFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFC8E6C9), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // "새로운 소식" label (시안 .hA-label)
            Row(children: [
              Container(
                width: 7 * s, height: 7 * s,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.success,
                ),
              ),
              SizedBox(width: 5 * s),
              Text('새로운 소식',
                  style: TextStyle(
                    fontSize: 11 * s,
                    fontWeight: FontWeight.w700,
                    color: AppColors.successDark,
                    letterSpacing: 0.5,
                  )),
            ]),
            SizedBox(height: 10 * s),
            // 제목 "N월 N일 근무가 확정됐어요 🎉" (시안 .hA-title)
            Text('$dateStr 근무가\n확정됐어요 🎉',
                style: TextStyle(
                  fontSize: 20 * s,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                  height: 1.25,
                )),
            SizedBox(height: 14 * s),
            // 흰 정보 박스 (시안 .hA-box)
            Container(
              padding: EdgeInsets.all(13 * s),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.selectedWorkType.isNotEmpty
                        ? '${app.businessName} · ${app.selectedWorkType}'
                        : app.businessName,
                    style: TextStyle(
                      fontSize: 14 * s,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4 * s),
                  Text(
                    hasTime
                        ? '${app.workDate.month}/${app.workDate.day}(${_dayLabel(app.workDate)})  ${app.startTime} – ${app.endTime}\n$wageStr'
                        : '${app.workDate.month}/${app.workDate.day}(${_dayLabel(app.workDate)})  $wageStr',
                    style: TextStyle(
                      fontSize: 13 * s,
                      color: AppColors.textSecondary,
                      height: 1.75,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 14 * s),
            // CTA 텍스트 버튼 (시안 .hA-cta)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('근무 확인하기',
                  style: TextStyle(
                    fontSize: 14 * s,
                    fontWeight: FontWeight.w700,
                    color: AppColors.successDark,
                  )),
              SizedBox(width: 5 * s),
              Icon(Icons.arrow_forward_rounded,
                  size: 18 * s, color: AppColors.successDark),
            ]),
          ],
        ),
      ),
    );
  }

  // ── 날짜 더보기 — 월간 캘린더 BottomSheet ─────────────────────────
  // 현재 7일 범위 밖의 날짜를 선택할 수 있게 한다.
  // 선택 시: _stripStart = 선택일, _selectedDateChip = 선택일, 캐시 재계산
  Future<void> _showDatePickerSheet(BuildContext context, double s) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime focusedDay = _selectedDateChip ?? _stripStart;

    await DialogHelper.showSheet<void>(
      context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSheet) => SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16 * s, 8 * s, 16 * s, 16 * s),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 핸들 바
                Container(
                  width: 36,
                  height: 4,
                  margin: EdgeInsets.only(bottom: 14 * s),
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text('날짜 선택',
                    style: TextStyle(
                      fontSize: 16 * s,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    )),
                SizedBox(height: 8 * s),
                AppCalendar(
                  focusedDay: focusedDay,
                  selectedDay: _selectedDateChip,
                  onDaySelected: (sel, foc) {
                    final selDate = DateTime(sel.year, sel.month, sel.day);
                    if (selDate.isBefore(today)) return; // 과거 선택 불가
                    Navigator.pop(ctx2);
                    // 캘린더에서 선택 → 항상 해당 날짜부터 7일로 범위 이동
                    // (Hero 스트립 직접 탭과 달리 범위 조건 없음)
                    setState(() {
                      _stripStart = selDate;
                      _selectedDateChip = selDate;
                    });
                    _rebuildCaches();
                  },
                  onPageChanged: (foc) => setSheet(() => focusedDay = foc),
                  // 공고 있는 날만 이벤트 1개 (점 on/off용)
                  eventLoader: (day) {
                    final d = DateTime(day.year, day.month, day.day);
                    return (_toDateCounts[d] ?? 0) > 0 ? [1] : [];
                  },
                  // #1565C0 작은 점 — 공고 있는 날짜만
                  markerBuilder: (ctx3, date, events) {
                    if (events.isEmpty) return null;
                    return Positioned(
                      bottom: 6,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: AppColors.infoDark,
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                  enabledDayPredicate: (day) =>
                      !DateTime(day.year, day.month, day.day).isBefore(today),
                ),
                // 범례 — 처음 사용자에게 점의 의미를 설명
                Padding(
                  padding: EdgeInsets.fromLTRB(4 * s, 2 * s, 4 * s, 2 * s),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.infoDark,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 5 * s),
                      Text('공고 있음',
                          style: TextStyle(
                            fontSize: 11 * s,
                            color: AppColors.textHint,
                          )),
                    ],
                  ),
                ),
                SizedBox(height: 4 * s),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── STATE C: 기본 — 날짜 탐색 (시안 .hC) ───────────────────────
  Widget _buildHeroStateC(BuildContext context, double s, ThemeData theme) {
    // 오늘부터 7일 (과거 없음, _stripStart는 날짜 더보기 선택 시 변경됨)
    final stripDays = List.generate(7, (i) => _stripStart.add(Duration(days: i)));
    final hasSelectedDate = _selectedDateChip != null;
    // 범례는 현재 표시 중인 7일 스트립 안에 확정 근무가 있을 때만 표시.
    // _confirmedDateSet.isNotEmpty 조건은 스트립 밖 과거/미래 확정 근무에도 반응하므로 부정확.
    final hasConfirmedInStrip = stripDays.any(
      (d) => _confirmedDateSet.contains(DateTime(d.year, d.month, d.day)),
    );

    // State C 그라데이션 — 파란 계열 (State B와 유사, 더 연하게)
    // 프로토타입 State B: #E8F0FE→#F0F4FF / State C는 더 은은하게
    return Container(
      padding: EdgeInsets.all(18 * s),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEDF4FF), Color(0xFFF4F8FF), Color(0xFFFAFBFF)],
          stops: [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color(0xFFBBDEFB), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목 + 배지 영역
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text('언제 일하고 싶으세요?',
                    style: AppTextStyles.heroTitle(s: s)),
              ),
              // 날짜 더보기 — 캘린더 열어 현재 7일 범위 밖 날짜 선택 가능
              GestureDetector(
                onTap: () => _showDatePickerSheet(context, s),
                child: Padding(
                  padding: EdgeInsets.only(left: 8 * s),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('날짜 더보기',
                        style: TextStyle(
                          fontSize: 12 * s,
                          fontWeight: FontWeight.w600,
                          color: AppColors.infoDark,
                        )),
                    Icon(Icons.chevron_right_rounded,
                        size: 16 * s, color: AppColors.infoDark),
                  ]),
                ),
              ),
            ],
          ),
          SizedBox(height: 3 * s),
          // 부제목 + 범례 (확정 근무가 있을 때만 범례 표시)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text('일할 날짜를 선택해보세요.',
                    style: AppTextStyles.heroDescription(s: s)),
              ),
              if (hasConfirmedInStrip)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 5 * s,
                    height: 5 * s,
                    decoration: const BoxDecoration(
                      color: AppColors.successDark,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 4 * s),
                  Text(
                    '확정 근무',
                    style: TextStyle(
                      fontSize: 12 * s,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ]),
            ],
          ),
          SizedBox(height: 14 * s),
          // 날짜 스트립 — 캘린더 스타일 (구글 캘린더처럼 숫자만 원형 선택)
          // 7일을 Expanded로 균등 분배 → 한눈에 보임, 스크롤 없음
          Row(
            children: stripDays.map((day) {
              final dayKey = DateTime(day.year, day.month, day.day);
              final count = _toDateCounts[dayKey] ?? 0;
              final hasJobs = count > 0;
              // 확정 근무 있는 날 — Green Dot 표시 + 선택 활성
              final hasConfirmed = _confirmedDateSet.contains(dayKey);
              final isSelected = _selectedDateChip == dayKey;
              final isSunday = day.weekday == DateTime.sunday;

              // 공고도 없고 확정 근무도 없는 날만 흐리게
              final cellOpacity =
                  (!isSelected && !hasJobs && !hasConfirmed) ? 0.38 : 1.0;

              // 요일 색상 — 일반 요일: textTertiary / 일요일: error / 토요일은 나중에 isSaturday 분기 가능
              final dowColor = isSunday ? AppColors.error : AppColors.textTertiary;

              // 날짜 숫자 색상 — 원 안(선택)은 흰색, 나머지는 기본
              final dateColor = isSelected
                  ? Colors.white
                  : isSunday
                      ? AppColors.error
                      : AppColors.textPrimary;

              // 원형 크기 — 반응형
              final circleD = 36.0 * s;

              return Expanded(
                child: Opacity(
                  opacity: cellOpacity,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // 공고가 없어도 확정 근무가 있는 날은 선택 가능
                    // (같은 날 추가 근무 탐색, 기존 일정 인지 목적)
                    onTap: (!hasJobs && !hasConfirmed)
                        ? null
                        : () => setState(() {
                              _selectedDateChip =
                                  _selectedDateChip == dayKey ? null : dayKey;
                            }),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 요일
                        Text(_dayLabel(day),
                            style: TextStyle(
                              fontSize: 10 * s,
                              color: dowColor,
                              fontWeight: FontWeight.w500,
                            )),
                        SizedBox(height: 5 * s),
                        // 날짜 숫자 — 선택 시만 원형 배경
                        // 확정 근무가 있으면 원 하단에 Dot을 Positioned overlay로 표시.
                        // Dot이 없는 날짜는 여분 row를 잡지 않으므로 "붕 뜨는" 공간이 생기지 않음.
                        Stack(
                          clipBehavior: Clip.none, // Dot이 원 아래로 overflow 허용
                          alignment: Alignment.topCenter,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              curve: Curves.easeOut,
                              width: circleD,
                              height: circleD,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? AppColors.infoDark
                                    : Colors.transparent,
                              ),
                              child: Center(
                                child: Text('${day.day}',
                                    style: TextStyle(
                                      fontSize: 15 * s,
                                      fontWeight: FontWeight.w700,
                                      color: dateColor,
                                    )),
                              ),
                            ),
                            // Dot: 원 바닥 3dp 아래부터 5dp 크기 → bottom = -(3+5)dp
                            if (hasConfirmed)
                              Positioned(
                                bottom: -8 * s,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: Container(
                                    width: 5 * s,
                                    height: 5 * s,
                                    decoration: const BoxDecoration(
                                      color: AppColors.successDark,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        // Dot overlay 공간 — 모든 셀 동일(10*s)으로 공고수 baseline 통일
                        //   확정 있음: 원↓3dp 간격 → 5dp dot → 2dp 간격 → 공고수
                        //   확정 없음: 10dp 최소 간격만 (기존 12dp 슬롯 대비 간격 대폭 축소)
                        SizedBox(height: 10 * s),
                        // 공고 수 — 작은 파란 텍스트 (없으면 높이 확보용 빈 공간)
                        SizedBox(
                          height: 14 * s,
                          child: hasJobs
                              ? Text('$count개',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10 * s,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.infoDark,
                                  ))
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          // Dot 슬롯(12*s) 추가분을 상쇄 — 카드 전체 높이 유지
          SizedBox(height: 6 * s),
          // CTA — 날짜 선택 후에만 등장 (미선택 시 완전 숨김)
          // 흐름: 날짜 선택 → 공고 수 확인 → 이동
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: hasSelectedDate
                ? Padding(
                    padding: EdgeInsets.only(top: 14 * s),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          final scope = UserTabScope.of(context);
                          if (_selectedDateChip != null) {
                            // 날짜 지정 이동 — 일자리 탭의 날짜 필터로 전달
                            scope?.switchToTabWithDate(1, _selectedDateChip!);
                          } else {
                            scope?.switchToTab(1);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.infoDark,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: EdgeInsets.symmetric(vertical: 13 * s),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        child: Text(
                          '${_selectedDateChip!.month}월 ${_selectedDateChip!.day}일 '
                          '일자리 ${_toDateCounts[_selectedDateChip] ?? 0}개 보기',
                          style: TextStyle(
                            fontSize: 14 * s,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ── 지원 현황 (시안 .sec 지원현황) ──────────────────────────────
  Widget _buildApplicationStatus(BuildContext context, double s) {
    // 3-column 통계
    final pendingCount = _cachedPendingCount;
    final confirmedCount = _cachedConfirmedCount;
    final resultWaitCount = _cachedContractPendingCount;
    // 최근 2건 지원서
    final recent = _cachedRecentApplications.take(2).toList();

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(20 * s, 24 * s, 20 * s, 24 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 헤더
          SectionHeader(
            s: s,
            title: '지원 현황',
            actionText: '전체보기 ›',
            onAction: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const MyApplicationsScreen())),
          ),
          SizedBox(height: 14 * s),
          // 신규 사용자 Empty State — 지원 이력 없음
          if (_applications.isEmpty && !_isLoadingData) ...[
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 24 * s, horizontal: 16 * s),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(Icons.search_rounded,
                      color: AppColors.textHint, size: 32 * s),
                  SizedBox(height: 8 * s),
                  Text('아직 지원한 일자리가 없어요',
                      style: TextStyle(
                        fontSize: 13.5 * s,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center),
                  SizedBox(height: 4 * s),
                  Text('원하는 날짜의 일을 찾아 첫 지원을 해보세요',
                      style: TextStyle(
                        fontSize: 12 * s,
                        color: AppColors.textHint,
                      ),
                      textAlign: TextAlign.center),
                  SizedBox(height: 14 * s),
                  GestureDetector(
                    onTap: () => UserTabScope.of(context)?.switchToTab(1),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('일자리 찾아보기',
                          style: TextStyle(
                            fontSize: 13 * s,
                            fontWeight: FontWeight.w700,
                            color: AppColors.infoDark,
                          )),
                      SizedBox(width: 3 * s),
                      Icon(Icons.arrow_forward_rounded,
                          size: 15 * s, color: AppColors.infoDark),
                    ]),
                  ),
                ],
              ),
            ),
          ] else ...[
          // 3열 통계 (시안 .app-summary)
          Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: EdgeInsets.symmetric(vertical: 12 * s),
            child: Row(children: [
              _statCell(s, '$pendingCount', '검토중', null),
              Container(width: 1, height: 36 * s, color: AppColors.borderLight),
              _statCell(s, '$confirmedCount', '확정', AppColors.success),
              Container(width: 1, height: 36 * s, color: AppColors.borderLight),
              _statCell(s, '$resultWaitCount', '계약 대기', AppColors.warning),
            ]),
          ),
          if (recent.isNotEmpty) ...[
            SizedBox(height: 12 * s),
            // 최근 2건 앱 행 (시안 .app-rows)
            Column(
              children: recent.asMap().entries.map((entry) {
                final i = entry.key;
                final app = entry.value;
                final isConfirmed = AppStatus.confirmedStatuses.contains(app.status);
                final isPending = app.status == AppStatus.pending;
                final badgeText = isConfirmed ? '확정' : isPending ? '대기' : '기타';
                final badgeBg = isConfirmed
                    ? AppColors.successBg
                    : isPending
                        ? AppColors.warningBg
                        : AppColors.grey100;
                final badgeFg = isConfirmed
                    ? AppColors.successDark
                    : isPending
                        ? AppColors.warningDark
                        : AppColors.grey500;
                final hasTime = app.startTime.isNotEmpty && app.endTime.isNotEmpty;

                return Padding(
                  padding: EdgeInsets.only(bottom: i < recent.length - 1 ? 8 * s : 0),
                  child: Container(
                    padding: EdgeInsets.all(11 * s),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(children: [
                      // 아이콘 (시안 .ar-ico)
                      Container(
                        width: 36 * s, height: 36 * s,
                        decoration: BoxDecoration(
                          color: AppColors.infoBg,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(Icons.work_outline_rounded,
                            color: AppColors.infoDark, size: 18 * s),
                      ),
                      SizedBox(width: 10 * s),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              app.selectedWorkType.isNotEmpty
                                  ? '${app.businessName} · ${app.selectedWorkType}'
                                  : app.businessName,
                              style: TextStyle(
                                fontSize: 13 * s,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 1 * s),
                            Text(
                              hasTime
                                  ? '${app.workDate.month}/${app.workDate.day}(${_dayLabel(app.workDate)})  ${app.startTime} – ${app.endTime}'
                                  : '${app.workDate.month}/${app.workDate.day}(${_dayLabel(app.workDate)})',
                              style: TextStyle(
                                fontSize: 12 * s,
                                color: AppColors.textHint,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 8 * s),
                      // 배지 (시안 .badge)
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 9 * s, vertical: 3 * s),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(badgeText,
                            style: TextStyle(
                              fontSize: 11 * s,
                              fontWeight: FontWeight.w700,
                              color: badgeFg,
                            )),
                      ),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ],
          ],  // else ...[] 닫힘
        ],
      ),
    );
  }

  // 3열 통계 셀
  Widget _statCell(double s, String value, String label, Color? color) {
    return Expanded(
      child: Column(children: [
        Text(value,
            style: AppTextStyles.statNumber(s: s, color: color)),
        SizedBox(height: 2 * s),
        Text(label,
            style: AppTextStyles.statLabel(s: s)),
      ]),
    );
  }

  /// 지원서 1건의 일급 계산 — 시급 타입은 시급×시간으로 환산
  static int _scheduledDailyWage(ApplicationModel app) {
    if (app.wageType == 'hourly') {
      int toMin(String t) {
        final p = t.split(':');
        if (p.length < 2) return 0;
        return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
      }
      int startMin = toMin(app.startTime);
      int endMin = toMin(app.endTime);
      if (endMin <= startMin) endMin += 1440; // 야간 교대
      return ((endMin - startMin) / 60 * app.wage).round();
    }
    return app.wage;
  }

  // ── 수입 현황 — 이번 달 compact (섹션 → IncomeDetailScreen) ──────────
  Widget _buildIncomeSection(BuildContext context, double s, ThemeData theme) {
    final now = DateTime.now();
    final monthApps = CalendarHelper.getThisMonthApplications(_applications, now);

    // 근무 완료: 관리자가 임금 확정/지급 처리한 금액 (attendance.finalWage)
    final wageCompleted = CalendarHelper.getConfirmedIncome(_attendances, now);

    // 근무 예정: 이번 달 확정 지원서 중 아직 미출근인 것 (시급 환산 포함)
    final wageScheduled = monthApps
        .where((a) => AppStatus.confirmedStatuses.contains(a.status))
        .where((a) => !_attendances
            .any((att) => att.applicationId == a.id && att.checkInAt != null))
        .fold<int>(0, (sum, a) => sum + _scheduledDailyWage(a));

    final wageTotal = wageCompleted + wageScheduled;

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(20 * s, 24 * s, 20 * s, 24 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 헤더
          SectionHeader(
            s: s,
            title: '수입 현황',
            actionText: '${now.year}년 ${now.month}월 ›',
            onAction: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => IncomeDetailScreen(
                  initialYear: now.year,
                  initialMonth: now.month,
                ),
              ),
            ),
          ),
          SizedBox(height: 14 * s),
          // 신규 사용자 Empty State — 수입 기록 없음
          if (!_isLoadingData && wageCompleted == 0 && wageScheduled == 0)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 20 * s, horizontal: 16 * s),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      color: AppColors.textHint, size: 30 * s),
                  SizedBox(height: 8 * s),
                  Text('아직 이번 달 수입이 없어요',
                      style: TextStyle(
                        fontSize: 13 * s,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center),
                  SizedBox(height: 3 * s),
                  Text('첫 근무를 마치면 여기에 수입이 표시돼요',
                      style: TextStyle(fontSize: 12 * s, color: AppColors.textHint),
                      textAlign: TextAlign.center),
                ],
              ),
            )
          else
            // 3행 테이블: 근무 완료 / 근무 예정 / 구분선 / 총 예상 수입
            Container(
              padding: EdgeInsets.all(16 * s),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  // ── 근무 완료 행 — 관리자가 임금 처리 완료한 금액 ──────
                  _incomeRow(
                    s: s,
                    label: '근무 완료',
                    labelColor: AppColors.textSecondary,
                    value: _isLoadingData ? null : FormatHelper.formatWage(wageCompleted),
                    valueColor: wageCompleted > 0 ? AppColors.successDark : AppColors.textSecondary,
                    valueBold: false,
                  ),
                  // ── 근무 예정 행 — 확정된 미출근 근무의 예상 수입 ────────
                  SizedBox(height: 8 * s),
                  _incomeRow(
                    s: s,
                    label: '근무 예정',
                    labelColor: AppColors.textSecondary,
                    value: _isLoadingData ? null : FormatHelper.formatWage(wageScheduled),
                    valueColor: AppColors.textPrimary,
                    valueBold: false,
                  ),
                  SizedBox(height: 12 * s),
                  Divider(height: 1, color: AppColors.borderLight),
                  SizedBox(height: 12 * s),
                  // ── 예상 수입 합계 ────────────────────────────────────
                  _incomeRow(
                    s: s,
                    label: '예상 수입',
                    labelColor: AppColors.infoDark,
                    value: _isLoadingData ? null : FormatHelper.formatWage(wageTotal),
                    valueColor: AppColors.infoDark,
                    valueBold: true,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }


  // ── 이번 주 일정 — 7일 dot 뷰 + 범례 ─────────────────────────────
  Widget _buildThisWeekSchedule(BuildContext context, double s, ThemeData theme) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekDays = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(20 * s, 24 * s, 20 * s, 24 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 헤더
          SectionHeader(
            s: s,
            title: '이번 주 일정',
            actionText: '일정 ›',
            // switchToTab(2): 탭0 Navigator에 push하지 않고 일정 탭으로 전환
            // Navigator.push 사용 시 탭0 스택에 MyScheduleScreen이 쌓여
            // 탭 전환 후 탭0 복귀 시 일정화면이 홈 자리에 나타나는 버그 발생
            onAction: () => UserTabScope.of(context)?.switchToTab(2),
          ),
          SizedBox(height: 14 * s),
          // 7일 도트 뷰
          Row(
            children: weekDays.map((day) {
              final isToday = day == today;
              final hasConfirmed = _cachedThisWeekConfirmedDates.contains(day);
              final hasPending = _cachedThisWeekPendingDates.contains(day);
              final isSat = day.weekday == 6;
              final isSun = day.weekday == 7;

              final Color dayLabelColor = isSat
                  ? const Color(0xFF4A90D9)
                  : isSun
                      ? const Color(0xFFE05252)
                      : AppColors.textHint;

              final Color dotColor = hasConfirmed
                  ? AppColors.success
                  : hasPending
                      ? AppColors.warning
                      : Colors.transparent;

              return Expanded(
                child: Column(children: [
                  Text(_dayLabel(day),
                      style: TextStyle(
                          fontSize: 11 * s,
                          color: dayLabelColor,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: 4 * s),
                  Container(
                    width: 32 * s,
                    height: 32 * s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isToday ? AppColors.infoDark : Colors.transparent,
                    ),
                    alignment: Alignment.center,
                    child: Text('${day.day}',
                        style: TextStyle(
                          fontSize: 14 * s,
                          fontWeight: FontWeight.w700,
                          color: isToday ? Colors.white : AppColors.textPrimary,
                        )),
                  ),
                  SizedBox(height: 4 * s),
                  Container(
                    width: 5 * s,
                    height: 5 * s,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: dotColor),
                  ),
                ]),
              );
            }).toList(),
          ),
          SizedBox(height: 10 * s),
          // 범례
          Row(children: [
            _legendDot(s, AppColors.success, '확정'),
            SizedBox(width: 12 * s),
            _legendDot(s, AppColors.warning, '지원중'),
          ]),
        ],
      ),
    );
  }

  Widget _legendDot(double s, Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 6 * s, height: 6 * s,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
      SizedBox(width: 4 * s),
      Text(label,
          style: TextStyle(
              fontSize: 11 * s,
              color: AppColors.textHint,
              fontWeight: FontWeight.w600)),
    ]);
  }

  // ── 온보딩 배너 ─────────────────────────────────────────────
  /// 지원 준비 Compact Card
  ///
  /// 사용자 관점의 2단계: ① 신분 확인 · ② 급여정보
  /// - 0/2: "신분증과 급여정보를 등록해주세요"
  /// - 1/2: "지원 준비가 거의 완료됐어요"
  /// - 2/2: SizedBox.shrink (숨김)
  ///
  /// 날짜 Hero보다 시각적 우선순위가 낮은 Compact 스타일.
  /// 탭 → DocumentManagementScreen (내 서류 관리)
  Widget _buildReadinessCard(BuildContext context, double s, UserProvider up) {
    final user = up.currentUser;
    if (user == null) return const SizedBox.shrink();

    // ① 신분 확인: 신분증 이미지 등록 여부 (idCardImagePath 신규 flow + idCardImageUrl legacy 양쪽 허용)
    final hasId = user.hasIdDocument;
    // ② 급여정보: 은행명 + 계좌번호 + 통장사본 세 가지 모두 있어야 완료
    final hasWage = user.bankName != null && user.bankName!.isNotEmpty &&
        user.accountNumber != null && user.accountNumber!.isNotEmpty &&
        user.bankbookImageUrl != null && user.bankbookImageUrl!.isNotEmpty;
    // ③ 계좌 불일치: mismatch 상태면 등록 완료지만 재확인 필요 → 카드 유지
    final isBankMismatch = user.bankVerificationStatus == 'mismatch';

    final completed = (hasId ? 1 : 0) + (hasWage ? 1 : 0);
    if (completed == 2 && !isBankMismatch) return const SizedBox.shrink();

    final subText = isBankMismatch
        ? '계좌 정보를 다시 확인해주세요'
        : completed == 0
            ? '신분증과 급여정보를 등록해주세요'
            : '지원 준비가 거의 완료됐어요';
    final theme = Theme.of(context);

    // ── 디자인: Warning이 아닌 Progress Status ──────────────────────
    // 배경·테두리는 매우 연한 파란 계열 → 날짜 Hero보다 시각적 강도 낮게 유지
    const cardBg     = Color(0xFFF5F9FF); // 매우 연한 파랑 (날짜 카드보다 약함)
    const cardBorder = Color(0xFFD7E7FA); // 연한 blue-gray

    return Padding(
      padding: EdgeInsets.fromLTRB(16 * s, 0, 16 * s, 12 * s),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DocumentManagementScreen()),
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: 16 * s, vertical: 12 * s),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cardBorder),
            // 그림자 없음 — 날짜 Hero와 경쟁하지 않도록
          ),
          child: Row(
            children: [
              // 원형 아이콘 배지 — 체크리스트/준비 계열 (경고 아이콘 사용 금지)
              Container(
                width: 38 * s,
                height: 38 * s,
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.checklist_rounded,
                    size: 20 * s, color: theme.primaryColor),
              ),
              SizedBox(width: 12 * s),
              // 텍스트 영역 — 2줄 고정
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1줄: "지원 준비  0/2"
                    Row(children: [
                      Text('지원 준비',
                          style: TextStyle(
                            fontSize: 15 * s,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          )),
                      SizedBox(width: 6 * s),
                      Text('$completed / 2',
                          style: TextStyle(
                            fontSize: 13 * s,
                            fontWeight: FontWeight.w500,
                            // ALfit Blue — Warning Orange 사용 금지
                            color: theme.primaryColor,
                          )),
                    ]),
                    SizedBox(height: 3 * s),
                    // 2줄: 안내 문구
                    Text(subText,
                        style: TextStyle(
                          fontSize: 13 * s,
                          color: AppColors.grey500,
                        )),
                    // 1/2 상태에서만: 얇은 progress bar (카드 크기 변화 없음)
                    if (completed == 1) ...[
                      SizedBox(height: 6 * s),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: 0.5,
                          minHeight: 3,
                          backgroundColor: theme.primaryColor.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 4 * s),
              Icon(Icons.chevron_right,
                  color: AppColors.grey400, size: 20 * s),
            ],
          ),
        ),
      ),
    );
  }

  // ── 지금 지원 가능한 일자리 — 추천 공고 (지원현황 아래) ──────────────
  //
  // 레벨 정의:
  //   Level 0: totalWorkDays == 0 && _applications.isEmpty → 숨김 (Hero C로 충분)
  //   Level 1+: 지원 기록 or 근무 이력 있으면 표시
  //
  // 점수 기준 (높을수록 우선 노출):
  //   preferredJobRegions 일치(city) +3  / district 추가 +2
  //   homeRegion 일치(city) +2           / district 추가 +1
  //   이미 지원한 TO 제외, 마감·만원 TO 제외
  Widget _buildRecommendSection(BuildContext context, double s, UserProvider up) {
    final user = up.currentUser;
    if (user == null) return const SizedBox.shrink();

    // 전체 정렬 목록 → 홈에는 상위 2개만 표시, 총 개수는 헤더에 사용
    // 신규 사용자도 "지금 지원 가능한 일자리" 제목으로 섹션 표시
    final allRecommended = _getRecommendedTos(user);
    final totalCount = allRecommended.length;
    final homeRegion = user.homeRegion;

    // ── STATE A/B/C/D 분류 — homeRegion 기반 표시 전략 ──────────────
    // STATE A: 내 city TO 2건 이상 → city TO 2건만 표시, city 부제목
    // STATE B: 내 city TO 1건     → city TO 1건 + 타지역 TO 1건 혼합 표시, 부제목 없음
    // STATE C: 내 city TO 0건     → 타지역 TO 2건 표시 + 지역 안내 배너
    // STATE D: 전체 TO 0건        → 빈 상태 안내 메시지
    // STATE 0 (homeRegion 없음 또는 로딩 중): 기존 동작 유지 (상위 2건)
    final List<TOModel> displayedTos;
    final int recState; // 0=no_home, 1=A, 2=B, 3=C, 4=D

    if (!_isLoadingData && homeRegion != null) {
      final cityTos = allRecommended
          .where((to) => to.businessCity == homeRegion.city)
          .toList();
      final nonCityTos = allRecommended
          .where((to) => to.businessCity != homeRegion.city)
          .toList();
      if (cityTos.length >= 2) {
        recState = 1;
        displayedTos = cityTos.take(2).toList();
      } else if (cityTos.length == 1) {
        recState = 2;
        displayedTos = [
          cityTos.first,
          if (nonCityTos.isNotEmpty) nonCityTos.first,
        ];
      } else if (nonCityTos.isNotEmpty) {
        recState = 3;
        displayedTos = nonCityTos.take(2).toList();
      } else {
        recState = 4;
        displayedTos = [];
      }
    } else {
      recState = 0;
      displayedTos = allRecommended.take(2).toList();
    }

    // ── 섹션 제목 — 맥락에 따라 동적 결정 ─────────────────────────
    // 1순위: 날짜 선택됨 → "M월 D일 일자리"
    // 2순위 (STATE A): 내 city TO 2건+ → city 부제목 + 업무경험 여부로 제목 분기
    // 기본: 부제목 없음
    final String sectionTitle;
    final String? sectionSubtitle;
    if (_selectedDateChip != null) {
      sectionTitle =
          '${_selectedDateChip!.month}월 ${_selectedDateChip!.day}일 일자리';
      sectionSubtitle = null; // 날짜가 제목에 있으므로 부제 불필요
    } else if (recState == 1) {
      sectionTitle =
          _cachedWorkTypeStats.isNotEmpty ? '나에게 맞는 일자리' : '지금 지원 가능한 일자리';
      sectionSubtitle = '${homeRegion!.city} 일자리를 먼저 보여드려요.';
    } else {
      sectionTitle =
          _cachedWorkTypeStats.isNotEmpty ? '나에게 맞는 일' : '지금 지원 가능한 일자리';
      sectionSubtitle = null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 8dp 회색 구분 갭 (Scaffold 흰 배경이므로 직접 색상 지정)
        Container(height: 8, color: AppColors.background),
        Container(
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(20 * s, 24 * s, 20 * s, 24 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // 섹션 헤더 — 동적 제목·부제목, 3개 이상일 때만 액션
          SectionHeader(
            s: s,
            title: sectionTitle,
            subtitle: sectionSubtitle,
            actionText: totalCount > 2 ? '$totalCount개 모두보기 ›' : null,
            onAction: totalCount > 2
                ? () {
                    final scope = UserTabScope.of(context);
                    // 날짜가 선택된 상태면 동일한 날짜 필터를 일자리 탭에 전달
                    if (_selectedDateChip != null) {
                      scope?.switchToTabWithDate(1, _selectedDateChip!);
                    } else {
                      scope?.switchToTab(1);
                    }
                  }
                : null,
          ),
          SizedBox(height: 14 * s),
          // 추천 카드 목록
          if (_isLoadingData)
            Column(children: [
              _recommendSkeletonCard(s),
              SizedBox(height: 8 * s),
              _recommendSkeletonCard(s),
            ])
          else if (_selectedDateChip != null && displayedTos.isEmpty)
            // 날짜 선택 + 해당 날짜 TO 없음
            Container(
              padding: EdgeInsets.symmetric(vertical: 20 * s),
              alignment: Alignment.center,
              child: Text(
                '해당 날짜에 지원 가능한 공고가 없어요',
                style: TextStyle(fontSize: 13 * s, color: AppColors.textHint),
              ),
            )
          else if (recState == 4)
            // STATE D: 전체 TO 없음
            Container(
              padding: EdgeInsets.symmetric(vertical: 20 * s),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Text(
                    '지금 지원 가능한 일자리가 없어요',
                    style: TextStyle(
                        fontSize: 13 * s,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4 * s),
                  Text(
                    '새로운 일자리가 등록되면 이곳에서 확인할 수 있어요.',
                    style: TextStyle(fontSize: 12 * s, color: AppColors.textHint),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else ...[
            // STATE C: 내 city TO 없음 → 타지역 공고 표시 + 안내 배너
            if (recState == 3 && homeRegion != null) ...[
              Container(
                margin: EdgeInsets.only(bottom: 10 * s),
                padding: EdgeInsets.symmetric(
                    horizontal: 12 * s, vertical: 10 * s),
                decoration: BoxDecoration(
                  color: AppColors.grey50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.grey200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 14 * s, color: AppColors.textSecondary),
                    SizedBox(width: 6 * s),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${homeRegion.city}에는 아직 모집 중인 일자리가 없어요',
                            style: TextStyle(
                                fontSize: 12 * s,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 2 * s),
                          Text(
                            '대신 지금 지원 가능한 다른 지역 일자리를 보여드릴게요.',
                            style: TextStyle(
                                fontSize: 11 * s,
                                color: AppColors.textHint),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // 카드 목록 (STATE A/B/C/0 공통)
            Column(
              children: displayedTos.asMap().entries.map((entry) {
                final i = entry.key;
                final to = entry.value;
                return Padding(
                  padding: EdgeInsets.only(
                      bottom: i < displayedTos.length - 1 ? 8 * s : 0),
                  child: _recommendToCard(context, s, to, homeRegion),
                );
              }).toList(),
            ),
          ],
            ],
          ),
        ),  // 내부 Container 닫기
      ],  // 외부 Column.children 닫기
    );  // 외부 Column 닫기
  }

  /// 추천 TO 카드 — Group → Date Slot → Work Slot 구조 기반 요약 카드
  ///
  /// 구조:
  ///   ┌────────┐  공고제목            [상태배지] [♡]
  ///   │  사업장 │  사업장명
  ///   │  이미지 │  📅 날짜 요약 (날짜 미선택: 기간·시간대 / 선택: 날짜·가능업무수)
  ///   └────────┘  📍 지역
  ///               ─────────────────────────────────
  ///               급여 범위    [추천사유 1개]       ›
  ///
  /// - 날짜 미선택: Group 전체 요약 (기간 + 시간대 요약 + 최저~최고 급여)
  /// - 날짜 선택: 해당 Date Slot 기준 (가능한 Work Slot 수 + 기존 일정 충돌 제거)
  Widget _recommendToCard(BuildContext context, double s, TOModel to,
      UserRegion? homeRegion) {
    // ── 사업장 정보 (캐시) ─────────────────────────────────────
    final biz = _businessCache[to.businessId];
    final imageUrl = biz?.mainImageUrl;

    // ── 지역 정보 ─────────────────────────────────────────────
    final city = to.businessCity;
    final district = to.businessDistrict;
    final isNearby =
        homeRegion != null && city != null && city == homeRegion.city;
    final locationText = [
      if (city != null && city.isNotEmpty) city,
      if (district != null && district.isNotEmpty) district,
    ].join(' ');

    // ── 마감되지 않은 활성 Work Slot ─────────────────────────
    final activeDetails =
        to.workDetails.where((d) => !d.isClosed && !d.isTimeExpired).toList();

    // 업무 경험 매칭 (가장 많이 한 업무 유형 기준)
    final leadWorkType =
        activeDetails.isNotEmpty ? activeDetails.first.workType : '';
    final expCount = _cachedWorkTypeStats[leadWorkType];

    // ── 날짜 선택 시: 기존 확정 일정과 충돌 검사 ──────────────
    // ApplicationModel.startTime/endTime (HH:mm) vs WorkDetailData.startTime/endTime
    final List<ApplicationModel> confirmedOnDate;
    if (_selectedDateChip != null) {
      confirmedOnDate = _applications.where((a) {
        if (!AppStatus.confirmedStatuses.contains(a.status)) return false;
        final wd =
            DateTime(a.workDate.year, a.workDate.month, a.workDate.day);
        return wd == _selectedDateChip;
      }).toList();
    } else {
      confirmedOnDate = const [];
    }
    final hasExistingSchedule = confirmedOnDate.isNotEmpty;

    // 시간 겹침 여부 (분 단위 비교)
    int toMin(String hhmm) {
      final parts = hhmm.split(':');
      if (parts.length != 2) return 0;
      return (int.tryParse(parts[0]) ?? 0) * 60 +
          (int.tryParse(parts[1]) ?? 0);
    }

    bool overlaps(String sA, String eA, String sB, String eB) {
      final a0 = toMin(sA), a1 = toMin(eA);
      final b0 = toMin(sB), b1 = toMin(eB);
      // 야간 교대(종료<시작)는 단순 처리 — 일반 시간대만 비교
      return a0 < b1 && a1 > b0;
    }

    // 기존 확정 일정과 겹치지 않는 Work Slot만 추출
    final availableDetails = _selectedDateChip == null
        ? activeDetails
        : activeDetails.where((d) {
            return !confirmedOnDate.any(
                (a) => overlaps(d.startTime, d.endTime, a.startTime, a.endTime));
          }).toList();

    // ── 날짜 텍스트 ──────────────────────────────────────────────
    const wd = ['', '월', '화', '수', '목', '금', '토', '일'];
    String dateText;
    if (_selectedDateChip != null) {
      // 날짜 선택 모드: "8/12(수) · 가능한 업무 N개"
      final sd = _selectedDateChip!;
      final dayStr = '${sd.month}/${sd.day}(${wd[sd.weekday]})';
      final count = availableDetails.length;
      dateText = count > 0
          ? '$dayStr · 가능한 업무 $count개'
          : '$dayStr · 지원 가능 업무 없음';
    } else {
      // 날짜 미선택 모드: Group 전체 기간 요약
      if (to.isFlexType) {
        final rs = to.rangeStart;
        if (rs != null) {
          dateText = '${rs.month}/${rs.day}';
          if (to.totalSlots > 1) dateText += ' 외 ${to.totalSlots - 1}일';
        } else {
          dateText = '${to.totalSlots}일';
        }
      } else {
        // 신규 preset: workStartAvailableFrom ~ Until / custom·legacy: rangeStart ~ rangeEnd
        final DateTime? rs = to.hasWorkStartAvailableRange
            ? to.workStartAvailableFrom
            : to.rangeStart;
        final DateTime? endDt = to.hasWorkStartAvailableRange
            ? to.workStartAvailableUntil
            : to.rangeEnd;
        if (rs != null) {
          dateText = '${rs.month}/${rs.day}';
          if (endDt != null) dateText += ' ~ ${endDt.month}/${endDt.day}';
        } else {
          dateText = '';
        }
      }
      // 시간대 요약 — 모든 Work Slot이 같은 시간이면 표시, 다르면 "다양한 시간대"
      final times = activeDetails
          .map((d) => '${d.startTime}~${d.endTime}')
          .toSet();
      if (times.length == 1) {
        if (dateText.isNotEmpty) {
          dateText += ' · ${times.first}';
        } else {
          dateText = times.first;
        }
      } else if (times.length > 1) {
        if (dateText.isNotEmpty) {
          dateText += ' · 다양한 시간대';
        } else {
          dateText = '다양한 시간대';
        }
      }
    }

    // ── 급여 범위 ─────────────────────────────────────────────
    // 날짜 선택 시: 가능한 Work Slot(충돌 제외) 기준
    // 날짜 미선택 시: 전체 활성 Work Slot 기준 (최저~최고 범위)
    final wageSources =
        availableDetails.where((d) => d.wage > 0).toList();
    String wageText = '';
    if (wageSources.isNotEmpty) {
      wageSources.sort((a, b) => a.wage.compareTo(b.wage));
      final minW = wageSources.first;
      final maxW = wageSources.last;
      if (maxW.wage > minW.wage) {
        // 범위 표시: "일급 40,000원~" (최저만, 물결로 범위 암시)
        wageText =
            '${FormatHelper.formatWageWithType(minW.wage, minW.wageType)}~';
      } else {
        wageText =
            FormatHelper.formatWageWithType(minW.wage, minW.wageType);
      }
    }

    // ── 상태 배지 ─────────────────────────────────────────────
    final remaining = to.totalRequired > 0
        ? to.totalRequired - to.totalConfirmed
        : null;
    final isAlmostFull = remaining != null && remaining <= 2;
    final Color badgeBg;
    final Color badgeFg;
    final String badgeLabel;
    if (isAlmostFull) {
      badgeBg = AppColors.warningBg;
      badgeFg = AppColors.warningDark;
      badgeLabel = '마감임박';
    } else {
      badgeBg = AppColors.successBg;
      badgeFg = AppColors.successDark;
      badgeLabel = '모집중';
    }

    // ── 추천 사유 — 우선순위 1개만 표시 ─────────────────────────
    // 우선순위:
    //   1. 날짜 선택 + 기존 일정 있음 + 가능 업무 존재 → "내 일정과 일치"
    //   2. 업무 경험 있음 → "내 업무 경험과 일치"
    //   3. 내 지역 → "내 지역 일자리"
    //   없음 → 추천사유 미표시 (억지 chip 금지)
    // "선택한 날짜와 일치"는 섹션 제목 자체가 날짜를 나타내므로 중복 — 제거
    String? reasonLabel;
    IconData? reasonIcon;
    if (_selectedDateChip != null &&
        hasExistingSchedule && availableDetails.isNotEmpty) {
      // 기존 일정이 있는 날임에도 추가로 지원 가능한 업무가 있음
      reasonLabel = '내 일정과 일치';
      reasonIcon = Icons.event_available_outlined;
    } else if (expCount != null && expCount > 0) {
      reasonLabel = '내 업무 경험과 일치';
      reasonIcon = Icons.thumb_up_alt_outlined;
    } else if (isNearby) {
      reasonLabel = '내 지역 일자리';
      reasonIcon = Icons.location_on_outlined;
    }

    // ── 찜 상태 ─────────────────────────────────────────────────
    final isFav = context.watch<UserProvider>().isFavoriteTo(to.id);

    return GestureDetector(
      onTap: () async {
        final result = await NavigationHelper.push<bool>(
          context,
          destination: JobPostingScreen(
            to: to,
            workDetails: to.workDetails,
          ),
        );
        if (result == true && mounted) _loadHomeData();
      },
      child: Container(
        padding: EdgeInsets.all(12 * s),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14 * s),
          border: Border.all(color: AppColors.borderLight, width: 1.5),
        ),
        child: IntrinsicHeight(
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 사업장 이미지 (너비 고정·높이=텍스트 컬럼 높이) ─────
            ClipRRect(
              borderRadius: BorderRadius.circular(12 * s),
              child: SizedBox(
                width: 96 * s,
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => JobImagePlaceholder(
                          workTypeIcon:
                              to.workDetails.firstOrNull?.workTypeIcon,
                        ),
                        errorWidget: (_, __, ___) => JobImagePlaceholder(
                          workTypeIcon:
                              to.workDetails.firstOrNull?.workTypeIcon,
                        ),
                      )
                    : JobImagePlaceholder(
                        workTypeIcon:
                            to.workDetails.firstOrNull?.workTypeIcon,
                      ),
              ),
            ),
            SizedBox(width: 10 * s),
            // ── 정보 영역 ───────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 공고 제목 + 상태배지 + 찜
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          to.title.isNotEmpty ? to.title : to.businessName,
                          style: AppTextStyles.jobTitle(s: s),
                          maxLines: 1,
                        ),
                      ),
                      SizedBox(width: 6 * s),
                      // 상태 배지
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 7 * s, vertical: 2 * s),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(20 * s),
                        ),
                        child: Text(
                          badgeLabel,
                          style: AppTextStyles.statusBadge(s: s, color: badgeFg),
                        ),
                      ),
                      SizedBox(width: 4 * s),
                      // 찜 버튼
                      GestureDetector(
                        onTap: () async {
                          // ignore: use_build_context_synchronously
                          await context
                              .read<UserProvider>()
                              .toggleFavoriteTo(to.id);
                        },
                        child: Icon(
                          isFav
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 18 * s,
                          color: isFav ? AppColors.error : AppColors.grey400,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 2 * s),
                  // 사업장명 (서브타이틀)
                  Text(
                    to.businessName,
                    style: AppTextStyles.businessName(s: s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 6 * s),
                  // 날짜·업무수 요약 행
                  if (dateText.isNotEmpty)
                    _iconRow(
                        icon: Icons.calendar_today_outlined,
                        text: dateText,
                        s: s),
                  if (dateText.isNotEmpty) SizedBox(height: 3 * s),
                  // 지역 행
                  if (locationText.isNotEmpty)
                    _iconRow(
                        icon: Icons.location_on_outlined,
                        text: locationText,
                        s: s),
                  SizedBox(height: 8 * s),
                  // 구분선
                  Divider(
                      height: 1,
                      thickness: 0.5,
                      color: AppColors.borderLight),
                  SizedBox(height: 8 * s),
                  // 급여 범위 + 추천사유(1개) + 화살표
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (wageText.isNotEmpty)
                        Text(
                          wageText,
                          style: AppTextStyles.pay(s: s),
                        ),
                      const Spacer(),
                      // 추천 사유 1개 (없으면 미표시)
                      if (reasonLabel != null) ...[
                        Icon(reasonIcon,
                            size: 12 * s, color: AppColors.infoDark),
                        SizedBox(width: 3 * s),
                        Text(
                          reasonLabel,
                          style: TextStyle(
                            fontSize: 11 * s,
                            fontWeight: FontWeight.w600,
                            color: AppColors.infoDark,
                          ),
                        ),
                        SizedBox(width: 4 * s),
                      ],
                      Icon(Icons.chevron_right_rounded,
                          size: 18 * s, color: AppColors.grey400),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        ), // IntrinsicHeight
      ),
    );
  }

  /// 수입 섹션 한 행 — 레이블(좌) + 금액(우)
  Widget _incomeRow({
    required double s,
    required String label,
    required Color labelColor,
    required String? value,   // null → 로딩 placeholder
    required Color valueColor,
    required bool valueBold,
  }) {
    return Row(children: [
      Text(label,
          style: TextStyle(
            fontSize: 13 * s,
            color: labelColor,
            fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
          )),
      const Spacer(),
      value == null
          ? SizedBox(
              width: 80 * s,
              height: 16 * s,
              child: LinearProgressIndicator(
                borderRadius: BorderRadius.circular(4),
                color: AppColors.infoDark.withValues(alpha: 0.25),
                backgroundColor: AppColors.borderLight,
              ))
          : Text(value,
              style: TextStyle(
                fontSize: valueBold ? 15 * s : 13 * s,
                fontWeight: valueBold ? FontWeight.w900 : FontWeight.w600,
                color: valueColor,
                letterSpacing: -0.3,
              )),
    ]);
  }

  /// 아이콘 + 텍스트 한 줄 행 (날짜/지역 공통)
  Widget _iconRow(
      {required IconData icon, required String text, required double s}) {
    return Row(
      children: [
        Icon(icon, size: 13 * s, color: AppColors.textTertiary),
        SizedBox(width: 4 * s),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.jobMeta(s: s),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// 스켈레톤 카드 — 시안 카드 구조와 동일한 placeholder
  Widget _recommendSkeletonCard(double s) {
    final radius12 = BorderRadius.circular(12 * s);
    final radius20 = BorderRadius.circular(20 * s);
    return Container(
      padding: EdgeInsets.all(12 * s),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14 * s),
        border: Border.all(color: AppColors.borderLight, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 이미지 placeholder (96×96, radius 12)
          Container(
            width: 96 * s,
            height: 96 * s,
            decoration: BoxDecoration(
                color: AppColors.grey100, borderRadius: radius12),
          ),
          SizedBox(width: 10 * s),
          // 내용 placeholder
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 업무명 + 배지 행
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Container(height: 14 * s, width: 110 * s, color: AppColors.grey100),
                  const Spacer(),
                  Container(
                      height: 16 * s, width: 44 * s,
                      decoration: BoxDecoration(
                          color: AppColors.grey100, borderRadius: radius20)),
                  SizedBox(width: 4 * s),
                  Container(width: 18 * s, height: 18 * s, color: AppColors.grey100),
                ]),
                SizedBox(height: 5 * s),
                // 사업장명
                Container(height: 11 * s, width: 90 * s, color: AppColors.grey100),
                SizedBox(height: 8 * s),
                // 날짜 행
                Container(height: 11 * s, width: 140 * s, color: AppColors.grey100),
                SizedBox(height: 5 * s),
                // 지역 행
                Container(height: 11 * s, width: 80 * s, color: AppColors.grey100),
                SizedBox(height: 10 * s),
                // 구분선
                Container(height: 0.5, color: AppColors.borderLight),
                SizedBox(height: 10 * s),
                // 급여 + 추천이유 행
                Row(children: [
                  Container(height: 13 * s, width: 80 * s, color: AppColors.grey100),
                  const Spacer(),
                  Container(height: 11 * s, width: 70 * s, color: AppColors.grey100),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 추천 TO 목록 — Group → Date Slot → Work Slot 구조 기반
  ///
  /// 반환: 정렬된 전체 목록 (개수 제한 없음, 호출자가 slice)
  ///
  /// 필터링:
  ///   1. 마감·만원·예약공개·소프트삭제 제외
  ///   2. 이미 지원한 TO 제외
  ///   3. 날짜 선택 시: 해당 날짜에 슬롯이 있는 TO만
  ///      - contract: rangeStart~rangeEnd + workDays 검사
  ///      - flex: rangeStart~rangeEnd 내 (SlotModel 미로드 — 근사치)
  ///
  /// 정렬 우선순위:
  ///   1. 시간 충돌 없는 Work Slot 수 (내림차순)
  ///   2. 지역 일치 점수
  ///   3. 업무 경험 일치 여부
  ///   4. 마감임박 (남은 자리 적을수록 우선)
  ///   5. 최신 등록 (Firebase auto-id 역순)
  List<TOModel> _getRecommendedTos(UserModel user) {
    final appliedToIds = _applications.map((a) => a.toId).toSet();

    // ── 날짜 선택 시: 해당 날짜의 확정 일정 캐시 (충돌 검사용) ──
    final List<ApplicationModel> confirmedOnDate;
    if (_selectedDateChip != null) {
      confirmedOnDate = _applications.where((a) {
        if (!AppStatus.confirmedStatuses.contains(a.status)) return false;
        final wd =
            DateTime(a.workDate.year, a.workDate.month, a.workDate.day);
        return wd == _selectedDateChip;
      }).toList();
    } else {
      confirmedOnDate = const [];
    }

    // 시간 겹침 (분 단위)
    int toMin(String hhmm) {
      final p = hhmm.split(':');
      if (p.length != 2) return 0;
      return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
    }

    bool timesOverlap(String sA, String eA, String sB, String eB) =>
        toMin(sA) < toMin(eB) && toMin(eA) > toMin(sB);

    // TO별 충돌 없는 가용 Work Slot 수
    int availCount(TOModel to) {
      final active = to.workDetails
          .where((d) => !d.isClosed && !d.isTimeExpired)
          .toList();
      if (confirmedOnDate.isEmpty) return active.length;
      return active
          .where((d) => !confirmedOnDate.any((a) =>
              timesOverlap(d.startTime, d.endTime, a.startTime, a.endTime)))
          .length;
    }

    // ── 기본 후보 필터 ──────────────────────────────────────────
    var candidates = _publishedTos.where((to) {
      if (to.status == TOStatus.closed ||
          to.status == TOStatus.expired ||
          to.status == TOStatus.full ||
          to.status == TOStatus.scheduled) { return false; }
      if (to.isDeleted) return false;
      if (to.totalRequired > 0 && to.totalConfirmed >= to.totalRequired) {
        return false;
      }
      if (appliedToIds.contains(to.id)) return false;
      return true;
    }).toList();

    // ── 날짜 선택 시: 해당 날짜에 슬롯이 있는 TO만 ───────────────
    if (_selectedDateChip != null) {
      final sd = _selectedDateChip!;
      const dowLabels = ['월', '화', '수', '목', '금', '토', '일'];
      final dowLabel = dowLabels[sd.weekday - 1];

      candidates = candidates.where((to) {
        // 신규 preset: workStartAvailableFrom ~ Until / custom·legacy: rangeStart ~ rangeEnd
        final rs = to.hasWorkStartAvailableRange
            ? to.workStartAvailableFrom
            : to.rangeStart;
        final re = to.hasWorkStartAvailableRange
            ? to.workStartAvailableUntil
            : to.rangeEnd;
        if (rs == null) return false;
        // 날짜 범위 검사
        final sdDate = DateTime(sd.year, sd.month, sd.day);
        final rsDate = DateTime(rs.year, rs.month, rs.day);
        if (sdDate.isBefore(rsDate)) return false;
        if (re != null) {
          final reDate = DateTime(re.year, re.month, re.day);
          if (sdDate.isAfter(reDate)) return false;
        }
        // contract: 요일 검사
        if (to.isContractType) {
          return to.workDays.isEmpty || to.workDays.contains(dowLabel);
        }
        // flex: rangeStart~rangeEnd 내에 있으면 포함 (SlotModel 없이 근사)
        return true;
      }).toList();
    }

    // ── 정렬 ────────────────────────────────────────────────────
    candidates.sort((a, b) {
      // 1. 가용 Work Slot 수 (충돌 제거 후, 내림차순)
      final aAvail = availCount(a), bAvail = availCount(b);
      if (aAvail != bAvail) return bAvail.compareTo(aAvail);

      // 2. 지역 점수
      final rA = _regionScore(a, user), rB = _regionScore(b, user);
      if (rA != rB) return rB.compareTo(rA);

      // 3. 업무 경험 일치 (TO workDetails 중 경험 있는 타입 존재 여부)
      final expA = a.workDetails
              .any((d) => (_cachedWorkTypeStats[d.workType] ?? 0) > 0)
          ? 1
          : 0;
      final expB = b.workDetails
              .any((d) => (_cachedWorkTypeStats[d.workType] ?? 0) > 0)
          ? 1
          : 0;
      if (expA != expB) return expB.compareTo(expA);

      // 4. 마감임박 우선 (남은 자리 적을수록 긴박)
      final remA =
          a.totalRequired > 0 ? a.totalRequired - a.totalConfirmed : 999;
      final remB =
          b.totalRequired > 0 ? b.totalRequired - b.totalConfirmed : 999;
      if (remA != remB) return remA.compareTo(remB);

      // 5. 최신 등록 (Firebase auto-id 역순 — 시간순 생성이므로 근사치)
      return b.id.compareTo(a.id);
    });

    return candidates;
  }

  /// TO ↔ 사용자 지역 점수 (높을수록 우선)
  int _regionScore(TOModel to, UserModel user) {
    int score = 0;
    final toCity = to.businessCity;
    final toDistrict = to.businessDistrict;
    if (toCity == null) return 0;

    // preferredJobRegions 매칭 (가장 높은 가중치)
    for (final region in user.preferredJobRegions) {
      if (toCity == region.city) {
        score += 3;
        if (toDistrict != null &&
            region.district != null &&
            toDistrict == region.district) {
          score += 2;
        }
        break;
      }
    }

    // homeRegion 매칭
    final home = user.homeRegion;
    if (home != null && toCity == home.city) {
      score += 2;
      if (toDistrict != null &&
          home.district != null &&
          toDistrict == home.district) {
        score += 1;
      }
    }

    return score;
  }

  // ── 나의 ALfit — 경력 프로필 (시안 .sec 나의 ALfit) ─────────────
  Widget _buildCareerSection(BuildContext context, double s, UserProvider up) {
    final user = up.currentUser;
    final totalDays = user?.totalWorkDays ?? 0;
    final totalHours = user?.totalWorkHours ?? 0;
    final noShowCount = user?.noShowCount ?? 0;
    final attendanceRate = () {
      final total = totalDays + noShowCount;
      if (total == 0) return 100;
      return ((totalDays / total) * 100).round();
    }();

    // 업무 경험 칩 (최대 5개) — UserModel.workTypeStats 사용 (CF 누적 전체, 이번 달 한정 아님)
    final sortedStats = (user?.workTypeStats ?? {}).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(20 * s, 24 * s, 20 * s, 24 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 헤더
          SectionHeader(s: s, title: '나의 ALfit'),
          SizedBox(height: 14 * s),
          // ── 신규 사용자 Empty State (근무 이력 없음) ──
          if (!_isLoadingData && totalDays == 0) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('아직 쌓인 근무 경험이 없어요.',
                    style: TextStyle(
                      fontSize: 14 * s,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    )),
                SizedBox(height: 4 * s),
                Text('첫 근무부터 나의 기록이 시작됩니다.',
                    style: TextStyle(fontSize: 13 * s, color: AppColors.textHint)),
                SizedBox(height: 16 * s),
                GestureDetector(
                  onTap: () => UserTabScope.of(context)?.switchToTab(1),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('첫 일자리 찾아보기',
                        style: TextStyle(
                          fontSize: 13 * s,
                          fontWeight: FontWeight.w700,
                          color: AppColors.infoDark,
                        )),
                    SizedBox(width: 3 * s),
                    Icon(Icons.arrow_forward_rounded,
                        size: 15 * s, color: AppColors.infoDark),
                  ]),
                ),
              ],
            ),
          ] else ...[
          // ── 근무 이력 있는 사용자 — 한 줄 요약 ──
          RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 13.5 * s, color: AppColors.textSecondary),
              children: [
                const TextSpan(text: '근무 완료 '),
                TextSpan(
                    text: '$totalDays회',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                // 출근율: 3회 이상 근무 시에만 표시
                if (totalDays >= 3) ...[
                  const TextSpan(text: '  ·  출근율 '),
                  TextSpan(
                      text: '$attendanceRate%',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: attendanceRate >= 90
                              ? AppColors.successDark
                              : AppColors.textPrimary)),
                ],
                const TextSpan(text: '  ·  총 '),
                TextSpan(
                    text: '$totalHours시간',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ],
            ),
          ),
          SizedBox(height: 14 * s),
          // 업무 경험 레이블
          Text('업무 경험',
              style: TextStyle(
                fontSize: 12 * s,
                fontWeight: FontWeight.w700,
                color: AppColors.textHint,
                letterSpacing: 0.5,
              )),
          SizedBox(height: 8 * s),
          // 경험 칩 — 업무 유형별 완료 횟수
          if (sortedStats.isEmpty)
            Text('업무 유형 기록이 없어요',
                style: TextStyle(fontSize: 12 * s, color: AppColors.textHint))
          else
            Wrap(
              spacing: 6 * s,
              runSpacing: 5 * s,
              children: sortedStats.take(5).map((e) => Container(
                padding: EdgeInsets.symmetric(horizontal: 13 * s, vertical: 6 * s),
                decoration: BoxDecoration(
                  color: AppColors.infoBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${e.key} ${e.value}회',
                    style: TextStyle(
                      fontSize: 12 * s,
                      fontWeight: FontWeight.w700,
                      color: AppColors.infoDark,
                    )),
              )).toList(),
            ),
          SizedBox(height: 14 * s),
          // "근무 기록 보기 →" 링크 — 일정 탭 현재 달로 이동
          GestureDetector(
            onTap: () => UserTabScope.of(context)?.switchToScheduleNow(),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('근무 기록 보기',
                  style: TextStyle(
                    fontSize: 13 * s,
                    fontWeight: FontWeight.w700,
                    color: AppColors.infoDark,
                  )),
              SizedBox(width: 4 * s),
              Icon(Icons.arrow_forward_rounded, size: 16 * s, color: AppColors.infoDark),
            ]),
          ),
          ],  // else 닫힘
        ],
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
    // 관리자 홈으로 화면 교체 — 탭 네비게이터가 아닌 루트 네비게이터 사용
    // (UserRootScreen 내 탭 Navigator 위가 아니라 앱 최상위로 push)
    Navigator.of(context, rootNavigator: true).pushReplacement(
      MaterialPageRoute(builder: (_) => const BusinessAdminHomeScreen()),
    );
  }

}

// ── 다중 사업장 선택 바텀시트 ────────────────────────────────────
class _BusinessSelectorSheet extends StatelessWidget {
  final List<String> businessIds;
  final Map<String, String> businessNames;

  const _BusinessSelectorSheet({
    required this.businessIds,
    required this.businessNames,
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
          return ListTile(
            title: Text(name, style: ResponsiveHelper.bodyStyle(context)),
            onTap: () => Navigator.pop(context, id),
          );
        }),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
      ],
    );
  }
}

