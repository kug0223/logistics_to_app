import 'dart:async' show unawaited;

import '../../services/fcm_service.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Providers
import '../../providers/user_provider.dart';

// Utils
import '../../utils/format_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/tour_helper.dart';
import '../common/tour_screen.dart';

// Services
import '../../services/firestore_service.dart';
import '../../utils/attendance_list_pdf.dart';

// Screens
import '../common/settings_screen.dart';
import '../common/notification_screen.dart';
import '../../widgets/common/notification_badge.dart';
import 'admin_contract_management_screen.dart';
import 'payroll/payroll_payment_dashboard_screen.dart';
// payroll_payment_service.dart — home screen에서 직접 사용 없음 (canonical summary로 대체됨)
import '../../theme/app_colors.dart';
import '../../models/core/business_model.dart';
import 'support_review_queue_screen.dart';
import 'expiring_contracts_screen.dart';
import 'unclosed_action_queue_screen.dart';
import 'Business_form_screen.dart';
import 'work_type_management_screen.dart';
import '../../services/admin_home_summary_service.dart';
import '../../services/business_posting_readiness.dart';
import '../../services/contract_template_service.dart';
import '../../models/core/contract_template_model.dart';
import 'contract_template_list_screen.dart';
import '../../models/ui/admin_home_summary_model.dart';
import 'widgets/business_action_drill_down_sheet.dart';
import '../../widgets/common/business_selector_sheet.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/admin_tab_switcher.dart';
import '../../controllers/workforce_controller.dart';
import '../../services/staffing_readiness_service.dart';
import '../../models/ui/staffing_readiness_model.dart';
import '../../models/core/attendance_model.dart'; // AttendanceModel 타입 어노테이션 직접 사용;
import 'dialogs/day_applicants_dialog.dart'; // [PHASE-2D] 인력 부족 → 지원자 관리 다이얼로그
import 'dialogs/attendance_status_dialog.dart'; // [PHASE-R5.2] 확인 필요 → 출근 현황 리뷰

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
  bool _readinessLoaded = false;

  /// [FP-01] 첫 공고까지 남은 준비 — CreateTO와 같은 canonical fact에서 derive.
  final _contractTemplateService = ContractTemplateService();
  FirstPostingReadiness? _firstPosting;

  // [PHASE-3A] activeTO 카운트 (revision listener로 갱신됨)
  // Phase 2C 이후 Home에서 직접 표시 없음 — Phase 2E에서 표시 또는 완전 제거 예정
  // ignore: unused_field
  int _summaryActiveTO = 0;
  // ignore: unused_field
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

  // [PHASE-2C] 오늘 운영 — Staffing D0 (StaffingReadinessModel 전체를 보관, Phase 2D에서 D+1~D+7 재사용)
  // null = 쿼리 실패 (ERROR≠ZERO 원칙), available:false = CF 부분 실패
  StaffingReadinessModel? _staffingReadiness;
  bool _staffingLoading = true;

  // [PHASE-2C] 오늘 운영 — 출근/확인 필요
  // null = 쿼리 실패 (ERROR≠ZERO 원칙, 0과 구분)
  int? _todayCheckedIn;
  int? _todayNeedsAttention;
  bool _attendanceLoading = true;

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
        unawaited(_loadSummaryCounts());       // activeTO only
        unawaited(_loadCanonicalSummary());   // [PHASE-2C] canonical actions
        unawaited(_loadStaffingReadiness()); // [PHASE-2C] D0~D+7 인력 현황
        unawaited(_loadTodayAttendance());   // [PHASE-2C] 오늘 출근 현황
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
    unawaited(_loadStaffingReadiness());
    unawaited(_loadTodayAttendance());
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
        _loadStaffingReadiness(),
        _loadTodayAttendance(),
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
  //
  // [FP-01] 사업장이 0개이거나 전부 미승인이어도 중단하지 않는다.
  //   신규 관리자에게야말로 "첫 공고까지 무엇이 남았는지"가 필요하다.
  //   이전에는 여기서 early return 해 _readinessLoaded가 false로 남았고,
  //   그 결과 준비 카드가 아예 렌더되지 않았다.
  Future<void> _loadPostingReadiness() async {
    final approvedBizs = _businesses.where((b) => b.isApproved).toList();
    final readinessMap = approvedBizs.isEmpty
        ? <String, BusinessPostingReadiness>{}
        : await BusinessPostingReadiness.forBusinesses(
            approvedBizs,
            _firestoreService,
          );

    // [FP-01] 계약서 템플릿은 관리자 보유분 전체 합산 — CreateTO와 동일 semantics.
    //   (템플릿 소유 모델은 이번에 바꾸지 않는다)
    var hasTemplate = false;
    if (_businesses.isNotEmpty) {
      try {
        final lists = await Future.wait(
          _businesses.map((b) => _contractTemplateService.getTemplates(b.id)),
        );
        hasTemplate = ContractTemplateModel.selectableForNewContract(
          lists.expand((l) => l),
        ).isNotEmpty;
      } catch (e) {
        // 조회 실패 시 "준비됨"으로 올리지 않는다 — CreateTO가 최종 gate다.
        debugPrint('⚠️ [readiness] 계약서 템플릿 조회 실패: $e');
      }
    }

    if (!mounted) return;
    final sealReady =
        context.read<UserProvider>().currentUser?.sealBase64?.isNotEmpty ?? false;

    setState(() {
      _firstPosting = FirstPostingReadiness(
        hasAnyBusiness: _businesses.isNotEmpty,
        businessReady: readinessMap.values.any((r) => r.isApproved && r.hasLicense),
        workTypesReady: readinessMap.values.any((r) => r.hasActiveWorkTypes),
        contractTemplateReady: hasTemplate,
        sealReady: sealReady,
      );
      _readinessLoaded = true;
    });
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

// [PHASE-2C] D0~D+7 인력 현황 로드
  // D0는 오늘 운영 Block에서 사용, D+1~D+7은 Phase 2D(Future Staffing Block)에서 재사용.
  // 실패 시 _staffingReadiness = null 유지 — false zero 방지 (ERROR≠ZERO)
  Future<void> _loadStaffingReadiness() async {
    if (!mounted) return;
    setState(() => _staffingLoading = true);
    try {
      final up = context.read<UserProvider>();
      final selectedBizId = up.currentUser?.isSubAdmin == true
          ? up.effectiveBusinessId
          : null;
      final result = await StaffingReadinessService.fetchReadiness(
        selectedBusinessId: selectedBizId,
      );
      if (!mounted) return;
      setState(() {
        _staffingReadiness = result;
        _staffingLoading = false;
      });
    } catch (e) {
      debugPrint('❌ _loadStaffingReadiness 실패: $e');
      if (!mounted) return;
      setState(() {
        _staffingReadiness = null; // 에러 상태 — 0 표시 금지
        _staffingLoading = false;
      });
    }
  }

  // [PHASE-2C.1] 오늘 출근 현황 로드 — attendance + confirmed roster 결합
  //
  // 출근 (checkedIn):
  //   - attendance record where checkInAt != null (Case C/D)
  //
  // 확인 필요 (needsAttention):
  //   (1) attendance record where status == NO_SHOW || absent  [Case E]
  //   (2) confirmed app where no att record + now >= scheduledStart  [Case B]
  //
  // 그레이스 피리어드: 없음 (코드베이스 전체에 미정의, isLate()도 0분 이상이 기준)
  //
  // [LIMITATION] getConfirmedWorkersByDateAndBusiness는 내부 try-catch로 실패 시 []
  // 반환 → Case B를 집계 못하더라도 확인 필요가 false-zero가 되지 않으려면
  // attendance 기반 (1)이 fallback. attendance 자체 실패 시 전체 null.
  //
  // 실패 시 _todayCheckedIn = null 유지 — false zero 방지 (ERROR≠ZERO)
  Future<void> _loadTodayAttendance() async {
    if (!mounted) return;
    setState(() => _attendanceLoading = true);
    try {
      final businesses = await _getBusinesses();
      if (businesses.isEmpty) {
        if (mounted) {
          setState(() {
            _todayCheckedIn      = 0;
            _todayNeedsAttention = 0;
            _attendanceLoading   = false;
          });
        }
        return;
      }

      final today    = FormatHelper.toKstDate(DateTime.now());
      final nowLocal = DateTime.now(); // 한국 디바이스에서 local = KST

      // 병렬 로드 — 두 Future를 미리 생성해 동시에 실행
      final attFuture = Future.wait(
        businesses.map((b) => _firestoreService.getAttendanceByDate(
          businessId: b.id, date: today)),
      );
      final rosterFuture = Future.wait(
        businesses.map((b) => _firestoreService.getConfirmedWorkersByDateAndBusiness(
          date: today, businessId: b.id)),
      );

      final allAttendance = (await attFuture).expand((l) => l).toList();
      final allConfirmed  = (await rosterFuture).expand((l) => l).toList();

      // applicationId → AttendanceModel (중복 집계 방지용)
      final attMap = <String, AttendanceModel>{};
      for (final a in allAttendance) {
        if (a.applicationId.isNotEmpty) attMap[a.applicationId] = a;
      }

      // 출근: checkInAt != null
      final checkedIn = allAttendance.where((a) => a.hasCheckedIn).length;

      // 확인 필요 (1): attendance 기반 — NO_SHOW / absent
      var needsAttention = allAttendance
          .where((a) => a.isNoShow || a.isAbsent)
          .length;

      // 확인 필요 (2): attendance 없음 + 출근 예정 시간 경과 [Case B]
      for (final app in allConfirmed) {
        if (attMap.containsKey(app.id)) continue; // attendance 있음 → (1)에서 처리
        // startTime: "HH:mm" 또는 "HH:mm:ss" (레거시) — 앞 5자리만 사용
        final raw = app.startTime;
        final timeStr = raw.length >= 5 ? raw.substring(0, 5) : raw;
        final parts = timeStr.split(':');
        if (parts.length < 2) continue;
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h == null || m == null) continue;
        final scheduledStart = DateTime(today.year, today.month, today.day, h, m);
        if (!nowLocal.isBefore(scheduledStart)) needsAttention++; // now >= scheduledStart
      }

      if (!mounted) return;
      setState(() {
        _todayCheckedIn      = checkedIn;
        _todayNeedsAttention = needsAttention;
        _attendanceLoading   = false;
      });
    } catch (e) {
      debugPrint('❌ _loadTodayAttendance 실패: $e');
      if (!mounted) return;
      setState(() {
        _todayCheckedIn      = null; // 에러 상태 — 0 표시 금지 (ERROR≠ZERO)
        _todayNeedsAttention = null;
        _attendanceLoading   = false;
      });
    }
  }

  /// D0 인력 현황 — _staffingReadiness.days[0] (오늘 날짜, CF가 D0부터 반환)
  /// available: false 또는 days 비어있으면 null 반환
  StaffingDayData? get _todayStaffingDay {
    final sr = _staffingReadiness;
    if (sr == null || !sr.available || sr.days.isEmpty) return null;
    return sr.days.first;
  }

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
                    _buildTodayOps(context, s, theme, up),
                    SizedBox(height: 16 * s),
                    _buildFutureStaffing(context, s, theme, up), // [PHASE-2D]
                    SizedBox(height: 16 * s),
                    _buildActionDashboard(context, s, theme, up),
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

  // ── [FP-01] 공고 등록 준비 checklist ─────────────────────────────
  //
  // 이전에는 서버가 강제하는 2개(사업자등록증·업무)만 셌다. CreateTO는 5개를
  // 요구하므로, 홈에서 카드가 사라진 뒤에도 공고 등록에서 계약서 템플릿과
  // 인감 때문에 다시 막혔다 — 준비의 끝이 두 번 오는 구조였다.
  // 이제 CreateTO와 같은 canonical fact를 쓰되, 표시는 사용자 mental model
  // 기준 4개 task로 묶는다(사업자등록증은 사업장 등록 폼에서 함께 받는다).
  //
  // 표시 조건: BUSINESS_ADMIN + readiness 로드 완료 + 미완료 ≥ 1
  //   사업장이 0개여도 보여준다 — 신규 관리자에게 가장 필요한 정보다.
  Widget _buildPostingSetupCard(BuildContext context, double s, ThemeData theme) {
    // SUB_ADMIN은 사업장 소유 설정(등록증·인감)을 수행할 수 없다 — 기존 정책 유지
    if (context.read<UserProvider>().currentUser?.isSubAdmin == true) {
      return const SizedBox.shrink();
    }
    if (!_readinessLoaded) return const SizedBox.shrink();
    final r = _firstPosting;
    if (r == null || r.allReady) return const SizedBox.shrink();

    final done = r.completedCount;
    final navBizId = _businesses.isNotEmpty ? _businesses.first.id : null;
    final navBiz = _businesses.isNotEmpty ? _businesses.first : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(20 * s, 0, 20 * s, 16 * s),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12 * s),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(14 * s, 12 * s, 14 * s, 10 * s),
              child: Row(
                children: [
                  Container(
                    width: 22 * s,
                    height: 22 * s,
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.checklist_rounded,
                        size: 14 * s, color: theme.primaryColor),
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
                  const Spacer(),
                  // 완료/전체 — 남은 개수가 아니라 진척을 보여준다
                  Text(
                    '$done / ${FirstPostingReadiness.totalTasks} 완료',
                    style: TextStyle(
                      fontSize: 11.5 * s,
                      fontWeight: FontWeight.w600,
                      color: theme.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 0.5, color: AppColors.grey100),

            // 4개 task — 강제 순서를 만들지 않는다.
            // 실제 의존성이 있는 항목만 잠그고 나머지는 바로 실행 가능.
            _setupTaskTile(
              context, s, r,
              task: FirstPostingTask.business,
              icon: Icons.store_outlined,
              label: '사업장 등록',
              // 등록됐지만 아직 승인 전이면 완료로 세지 않는다
              pendingHint: r.hasAnyBusiness && !r.businessReady ? '승인 진행 중' : null,
              onTap: () => _safeNavigate(() async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => navBiz == null
                        ? const BusinessFormScreen()
                        : BusinessFormScreen(business: navBiz),
                  ),
                );
                await _reloadReadiness();
              }),
            ),
            Divider(height: 1, thickness: 0.5, color: AppColors.grey100),
            _setupTaskTile(
              context, s, r,
              task: FirstPostingTask.workType,
              icon: Icons.work_outline,
              label: '업무 등록',
              lockedHint: '사업장 등록 후 가능',
              onTap: navBizId == null
                  ? null
                  : () => _safeNavigate(() async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WorkTypeManagementScreen(
                              businessId: navBizId,
                              businessName: navBiz!.name,
                            ),
                          ),
                        );
                        await _reloadReadiness();
                      }),
            ),
            Divider(height: 1, thickness: 0.5, color: AppColors.grey100),
            // [FP-03] 사업장 승인과 무관하다 — Rules도 isAdminOf만 요구한다.
            _setupTaskTile(
              context, s, r,
              task: FirstPostingTask.contractTemplate,
              icon: Icons.description_outlined,
              label: '계약서 템플릿',
              lockedHint: '사업장 등록 후 가능',
              onTap: navBizId == null
                  ? null
                  : () => _safeNavigate(() async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ContractTemplateListScreen(businessId: navBizId),
                          ),
                        );
                        await _reloadReadiness();
                      }),
            ),
            Divider(height: 1, thickness: 0.5, color: AppColors.grey100),
            // [FP-03] users/{uid} 값이라 사업장과 무관 — 가입 직후부터 가능
            _setupTaskTile(
              context, s, r,
              task: FirstPostingTask.seal,
              icon: Icons.verified_outlined,
              label: '인감/서명',
              onTap: () => _safeNavigate(() async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(
                      initialTarget: SettingsTarget.seal,
                    ),
                  ),
                );
                await _reloadReadiness();
              }),
            ),
          ],
        ),
      ),
    );
  }

  /// 준비 CTA에서 돌아온 뒤 상태 재조회 — 수동 새로고침을 요구하지 않는다.
  Future<void> _reloadReadiness() async {
    if (!mounted) return;
    await _loadApprovedBusinessStatus();
    if (!mounted) return;
    await _loadPostingReadiness();
  }

  /// 준비 항목 한 줄.
  /// 완료 / 지금 가능 / 선행 필요 세 상태만 구분한다 — STEP 번호를 붙이지 않는다.
  Widget _setupTaskTile(
    BuildContext context,
    double s,
    FirstPostingReadiness r, {
    required FirstPostingTask task,
    required IconData icon,
    required String label,
    String? lockedHint,
    String? pendingHint,
    VoidCallback? onTap,
  }) {
    final done = r.isDone(task);
    final actionable = r.isActionable(task);
    final hint = done ? null : (actionable ? pendingHint : lockedHint);

    return InkWell(
      onTap: done || !actionable ? null : onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 10 * s),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle : icon,
              size: 15 * s,
              color: done
                  ? AppColors.success
                  : (actionable ? AppColors.textSecondary : AppColors.grey300),
            ),
            SizedBox(width: 9 * s),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5 * s,
                  fontWeight: FontWeight.w500,
                  color: done
                      ? AppColors.textSecondary
                      : (actionable ? AppColors.textPrimary : AppColors.grey400),
                ),
              ),
            ),
            if (hint != null)
              Text(
                hint,
                style: TextStyle(fontSize: 11 * s, color: AppColors.grey400),
              )
            else if (!done && actionable)
              Icon(Icons.chevron_right,
                  size: 16 * s, color: AppColors.grey400),
          ],
        ),
      ),
    );
  }


  // ── [PHASE-2C/R6.1] 오늘 운영 Block ────────────────────────────
  // Staffing D0(필요·확정·부족) + 출근 현황(출근·확인 필요)
  // 부족: canManageTo → DayApplicantsDialog(오늘) [R6.1]
  // 확인 필요: canManageWorkers → AttendanceStatusDialog(오늘) [R5.2]
  // ERROR≠ZERO: 쿼리 실패 시 null 유지 (재시도 UI 표시)
  Widget _buildTodayOps(BuildContext context, double s, ThemeData theme, UserProvider up) {
    final isSub = up.currentUser?.isSubAdmin == true;
    final canSeeStaffing = !isSub
        || up.can((p) => p.canManageTo)
        || up.can((p) => p.canManageWorkers);
    final canSeeAttendance = !isSub || up.can((p) => p.canManageWorkers);

    if (!canSeeStaffing && !canSeeAttendance) return const SizedBox.shrink();

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
          child: Column(children: [
            if (canSeeStaffing) _buildStaffingMetrics(s, theme, up),
            if (canSeeStaffing && canSeeAttendance)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12 * s),
                child: Divider(height: 1, color: AppColors.border),
              ),
            if (canSeeAttendance) _buildAttendanceMetrics(s, theme, up),
          ]),
        ),
      ),
    ]);
  }

  // Staffing 영역: 필요 / 확정 / 부족
  // [R6.1] 부족 tap: canManageTo → DayApplicantsDialog(오늘)
  Widget _buildStaffingMetrics(double s, ThemeData theme, UserProvider up) {
    if (_staffingLoading) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 18 * s),
        child: Center(child: SizedBox(width: 16 * s, height: 16 * s,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: theme.primaryColor))),
      );
    }

    // 쿼리 실패 — null 또는 available:false
    if (_staffingReadiness == null || !_staffingReadiness!.available) {
      return _todayOpsErrorRow(s,
        message: '인력 정보를 불러오지 못했습니다',
        onRetry: () => unawaited(_loadStaffingReadiness()),
      );
    }

    // 정상: day가 null이면 오늘 staffing 없음 → 0/0/0 (정상 상태)
    final day = _todayStaffingDay;
    final required  = day?.requiredCount  ?? 0;
    final confirmed = day?.confirmedCount ?? 0;
    final shortage  = day?.shortageCount  ?? 0;

    // [R6.1] 부족 탭 — canManageTo + shortage > 0 + day 존재 시 DayApplicantsDialog(오늘)
    final isSub = up.currentUser?.isSubAdmin == true;
    final canManageTo = !isSub || up.can((p) => p.canManageTo);
    final onShortageDay = (shortage > 0 && canManageTo) ? day : null;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 14 * s),
      child: Row(children: [
        _opsMetric(s, label: '필요',  value: required,  unit: '명'),
        _opsMetricDivider(s),
        _opsMetric(s, label: '확정',  value: confirmed, unit: '명'),
        _opsMetricDivider(s),
        _opsMetric(s, label: '부족',  value: shortage,  unit: '명',
          valueColor: shortage > 0 ? AppColors.error : null,
          onTap: onShortageDay != null
              ? () => unawaited(_safeNavigate(() => _requireApprovedBusiness(
                    context, () => _navigateToDayApplicantsForDate(context, onShortageDay))))
              : null),
      ]),
    );
  }

  // 출근 현황 영역: 출근 / 확인 필요
  // [PHASE-R5.2] 확인 필요 N명 > → AttendanceStatusDialog (canManageWorkers 필수)
  Widget _buildAttendanceMetrics(double s, ThemeData theme, UserProvider up) {
    if (_attendanceLoading) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 18 * s),
        child: Center(child: SizedBox(width: 16 * s, height: 16 * s,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: theme.primaryColor))),
      );
    }

    // 쿼리 실패 — _todayCheckedIn == null
    if (_todayCheckedIn == null) {
      return _todayOpsErrorRow(s,
        message: '출근 현황을 불러오지 못했습니다',
        onRetry: () => unawaited(_loadTodayAttendance()),
      );
    }

    final needsAttention = _todayNeedsAttention ?? 0;
    final isSub = up.currentUser?.isSubAdmin == true;
    final canManageWorkers = !isSub || up.can((p) => p.canManageWorkers);
    // 탭 조건: 확인 필요 > 0 + canManageWorkers
    final onAttentionTap = (needsAttention > 0 && canManageWorkers)
        ? () => unawaited(_safeNavigate(
              () => _requireApprovedBusiness(
                  context, () => _openTodayAttendanceDialog(context))))
        : null;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 14 * s),
      child: Row(children: [
        _opsMetric(s, label: '출근', value: _todayCheckedIn!, unit: '명'),
        _opsMetricDivider(s),
        _opsMetric(s, label: '확인 필요', value: needsAttention, unit: '명',
          valueColor: needsAttention > 0 ? AppColors.warning : null,
          onTap: onAttentionTap),
      ]),
    );
  }

  /// 오늘 운영 수치 셀 (Expanded — Row 내 균등 분배)
  /// [PHASE-R5.2] onTap 옵션: 수치 > 0 + 권한 있을 때 탭 가능, subtle chevron 표시
  Widget _opsMetric(double s, {
    required String label,
    required int value,
    required String unit,
    Color? valueColor,
    VoidCallback? onTap,
  }) {
    final col = Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(fontSize: 10 * s, color: AppColors.grey500)),
      SizedBox(height: 4 * s),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$value$unit', style: TextStyle(
          fontSize: 18 * s, fontWeight: FontWeight.w800, letterSpacing: -0.3,
          color: valueColor ?? AppColors.textPrimary,
        )),
        if (onTap != null) ...[
          SizedBox(width: 1 * s),
          Icon(Icons.chevron_right, size: 14 * s,
              color: valueColor ?? AppColors.grey400),
        ],
      ]),
    ]);
    return Expanded(
      child: onTap != null
          ? GestureDetector(onTap: onTap, child: col)
          : col,
    );
  }

  Widget _opsMetricDivider(double s) =>
      Container(width: 1, height: 32 * s, color: AppColors.border);

  /// 오늘 운영 영역별 에러 행 — 재시도 버튼 포함
  Widget _todayOpsErrorRow(double s, {
    required String message,
    required VoidCallback onRetry,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
      child: Row(children: [
        Icon(Icons.info_outline, size: 14 * s, color: AppColors.grey400),
        SizedBox(width: 6 * s),
        Expanded(child: Text(message,
          style: TextStyle(fontSize: 12 * s, color: AppColors.grey400))),
        GestureDetector(
          onTap: onRetry,
          child: Text('재시도', style: TextStyle(
            fontSize: 11 * s, color: AppColors.textSecondary,
            decoration: TextDecoration.underline,
          )),
        ),
      ]),
    );
  }

  // ── [PHASE-2D] 다가오는 인력 부족 Block ─────────────────────────
  // [SOURCE] _staffingReadiness.days[1..7] 재사용 — 추가 fetch 없음
  // [RULE] SHOW_ONLY_SHORTAGE_DATES=YES · PENDING_ZERO_DISPLAY=HIDE
  // [RULE] FUTURE_SHORTAGE_MAX_VISIBLE_ROWS=7 (CF: D+1~D+7)
  // [RULE] FUTURE_STAFFING_ORDER=DATE_ASC (CF 이미 정렬, 재정렬 불필요)
  Widget _buildFutureStaffing(
      BuildContext context, double s, ThemeData theme, UserProvider up) {
    final isSub = up.currentUser?.isSubAdmin == true;
    final canSeeBlock = !isSub
        || up.can((p) => p.canManageTo)
        || up.can((p) => p.canManageWorkers);
    if (!canSeeBlock) return const SizedBox.shrink();

    // 로딩: Today Ops와 _staffingLoading 공유 (동일 fetch)
    if (_staffingLoading) {
      return Column(children: [
        _sectionHeader(context, s, '다가오는 인력 부족'),
        SizedBox(height: 8 * s),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16 * s),
          child: Container(
            height: 50 * s,
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Center(
              child: SizedBox(width: 16 * s, height: 16 * s,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: theme.primaryColor))),
          ),
        ),
      ]);
    }

    // 에러: null 또는 available:false (ERROR≠ZERO — 0 표시 금지)
    if (_staffingReadiness == null || !_staffingReadiness!.available) {
      return Column(children: [
        _sectionHeader(context, s, '다가오는 인력 부족'),
        SizedBox(height: 8 * s),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16 * s),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: _todayOpsErrorRow(s,
              message: '향후 인력 현황을 불러오지 못했습니다',
              onRetry: () => unawaited(_loadStaffingReadiness())),
          ),
        ),
      ]);
    }

    // D+1~D+7: D0(첫 요소) skip → shortage > 0 필터 → DATE_ASC 유지
    final futureDays = _staffingReadiness!.days
        .skip(1)
        .where((d) => d.shortageCount > 0)
        .toList();

    // 충원 완료 — 빈 상태 (green card 없음)
    if (futureDays.isEmpty) {
      return Column(children: [
        _sectionHeader(context, s, '다가오는 인력 부족'),
        SizedBox(height: 8 * s),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16 * s),
          child: Container(
            padding:
                EdgeInsets.symmetric(horizontal: 16 * s, vertical: 14 * s),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Icon(Icons.check_circle_outline,
                  size: 16 * s, color: AppColors.grey300),
              SizedBox(width: 8 * s),
              Text('향후 7일 인원 충원 완료',
                  style:
                      TextStyle(fontSize: 13 * s, color: AppColors.grey400)),
            ]),
          ),
        ),
      ]);
    }

    // 부족 날짜 행 목록 (최대 7행)
    return Column(children: [
      _sectionHeader(context, s, '다가오는 인력 부족'),
      SizedBox(height: 8 * s),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 16 * s),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              )
            ],
          ),
          child: Column(
            children: futureDays.asMap().entries.map((e) =>
              _buildFutureShortageRow(
                context, s, theme, up, e.value,
                isFirst: e.key == 0,
                isLast: e.key == futureDays.length - 1,
              ),
            ).toList(),
          ),
        ),
      ),
    ]);
  }

  /// 부족 날짜 단일 행 — 날짜 레이블 + N명 부족 + 지원 대기 N명(옵션)
  Widget _buildFutureShortageRow(
    BuildContext context,
    double s,
    ThemeData theme,
    UserProvider up,
    StaffingDayData day, {
    required bool isFirst,
    required bool isLast,
  }) {
    final isSub = up.currentUser?.isSubAdmin == true;
    // OWNER 또는 SubAdmin canManageTo → 탭 가능
    // SubAdmin canManageWorkers only → 표시는 되나 탭 불가, chevron 없음
    final canNavigate = !isSub || up.can((p) => p.canManageTo);

    final dateLabel  = _futureDateLabel(day.date);
    final shortageStr = '${day.shortageCount}명 부족';

    // PENDING_ZERO_DISPLAY=HIDE: null(실패)·0 → 숨김, >0 → '지원 대기 N명'
    final pendingStr = (day.pendingCount != null && day.pendingCount! > 0)
        ? '지원 대기 ${day.pendingCount}명'
        : null;

    final radius = BorderRadius.only(
      topLeft:     Radius.circular(isFirst ? 16 : 0),
      topRight:    Radius.circular(isFirst ? 16 : 0),
      bottomLeft:  Radius.circular(isLast  ? 16 : 0),
      bottomRight: Radius.circular(isLast  ? 16 : 0),
    );

    final rowContent = Padding(
      padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 13 * s),
      child: Row(children: [
        SizedBox(
          width: 66 * s,
          child: Text(dateLabel,
              style: TextStyle(
                  fontSize: 13 * s,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ),
        SizedBox(width: 8 * s),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(shortageStr,
                  style: TextStyle(
                      fontSize: 13 * s,
                      fontWeight: FontWeight.w700,
                      color: AppColors.warning)),
              if (pendingStr != null) ...[
                Text(' · ',
                    style: TextStyle(
                        fontSize: 12 * s, color: AppColors.grey400)),
                Text(pendingStr,
                    style: TextStyle(
                        fontSize: 12 * s, color: AppColors.grey500)),
              ],
            ],
          ),
        ),
        if (canNavigate) ...[
          SizedBox(width: 8 * s),
          OutlinedButton(
            onPressed: () => unawaited(_safeNavigate(() =>
                _requireApprovedBusiness(context,
                    () => _navigateToDayApplicantsForDate(context, day)))),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.primaryColor,
              side: BorderSide(
                  color: theme.primaryColor.withValues(alpha: 0.6)),
              padding: EdgeInsets.symmetric(
                  horizontal: 10 * s, vertical: 4 * s),
              minimumSize: Size.zero,
              // [R7.4-B] visual compact 유지 + touch target >= 48dp
              tapTargetSize: MaterialTapTargetSize.padded,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              textStyle: TextStyle(
                  fontSize: 12 * s, fontWeight: FontWeight.w600),
            ),
            child: const Text('충원하기'),
          ),
        ],
      ]),
    );

    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (canNavigate)
        InkWell(
          borderRadius: radius,
          onTap: () => unawaited(_safeNavigate(() =>
              _requireApprovedBusiness(context,
                  () => _navigateToDayApplicantsForDate(context, day)))),
          child: rowContent,
        )
      else
        rowContent,
      if (!isLast)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16 * s),
          child: Container(height: 1, color: AppColors.border),
        ),
    ]);
  }

  /// 날짜 레이블 — 내일이면 '내일', 그 외 'M/D (요일)' 포맷
  String _futureDateLabel(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length < 3) return dateStr;
    final year  = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day   = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return dateStr;

    final tomorrowKst =
        FormatHelper.toKstDate(DateTime.now()).add(const Duration(days: 1));
    if (year == tomorrowKst.year &&
        month == tomorrowKst.month &&
        day == tomorrowKst.day) {
      return '내일';
    }
    return FormatHelper.formatDate(DateTime(year, month, day));
  }

  // ── [PHASE-R5.2] 오늘 확인 필요 → AttendanceStatusDialog ────────
  // 탭 조건: _todayNeedsAttention > 0 && canManageWorkers (buildAttendanceMetrics에서 보장)
  // 반환값: hasChanges → _loadTodayAttendance() 재실행
  Future<void> _openTodayAttendanceDialog(BuildContext context) async {
    final businesses = await _getBusinesses();
    if (!context.mounted) return;
    final today = FormatHelper.toKstDate(DateTime.now());
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AttendanceStatusDialog(
        date: today,
        businessIds: businesses.map((b) => b.id).toList(),
        businesses: businesses,
      ),
    );
    if ((changed ?? false) && mounted) {
      unawaited(_loadTodayAttendance());
    }
  }

  // ── [PHASE-2D] 인력 부족 날짜 → DayApplicantsDialog 오픈 ────────
  // shortage > 0인 사업장만 대상, byBusiness 미집계 시 전체 사업장 폴백
  Future<void> _navigateToDayApplicantsForDate(
      BuildContext context, StaffingDayData day) async {
    final parts = day.date.split('-');
    if (parts.length < 3) return;
    final year   = int.tryParse(parts[0]);
    final month  = int.tryParse(parts[1]);
    final dayNum = int.tryParse(parts[2]);
    if (year == null || month == null || dayNum == null) return;

    final date = DateTime(year, month, dayNum);
    final businesses = await _getBusinesses();
    if (!context.mounted) return;

    final shortBizIds = day.byBusiness
        .where((b) => b.shortageCount > 0)
        .map((b) => b.businessId)
        .toList();
    final targetBizIds = shortBizIds.isNotEmpty
        ? shortBizIds
        : businesses.map((b) => b.id).toList();

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DayApplicantsDialog(
        date: date,
        businessIds: targetBizIds,
        businesses: businesses,
      ),
    );
    // [R7.4-A] DAD 내 확정/거절 → shortageCount 변동 시 Home 인력 현황 최신화
    if ((changed ?? false) && mounted) unawaited(_loadStaffingReadiness());
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
      if (available && count == 0) return; // valid 0 → 숨김 (ZERO_COUNT_ACTION_VISIBILITY = HIDE)
      result.add((icon: icon, label: label, badge: badge, countStr: countStr,
          color: color, count: count, available: available, onTap: onTap));
    }

    // 1. 지원 검토 — canManageTo
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

    // 2. 마감 필요 — canManageWage
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

    // 3.5 계약 종료 예정 — canManageContract
    // [GAP-CONTRACT-EXPIRING-UI-01 FIX] ExpiringContractsScreen 진입점 추가
    // 홈 upcoming.expiringContract 데이터가 계산되지만 UI 진입 경로가 없었던 P2 갭 수정
    if (!isSub || up.can((p) => p.canManageContract)) {
      final expiring = cs?.upcoming.expiringContract;
      add(
        icon: Icons.event_busy_outlined, label: '계약 종료 예정',
        color: AppColors.warning,
        count: expiring?.count ?? 0, countStr: '${expiring?.count ?? 0}명',
        available: expiring?.available ?? false,
        onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
          if (!up.can((p) => p.canManageContract)) {
            ToastHelper.showWarning('계약서 관리 권한이 없습니다.'); return;
          }
          if (!_ensureCanonicalSummary(context)) return;
          final sec = _canonicalSummary!.upcoming.expiringContract;
          if (!sec.available) { _showCanonicalError(context); return; }
          if (sec.count == 0) return;
          final businesses = await _getBusinesses();
          if (!context.mounted) return;
          // byBusiness에서 count > 0인 사업장만 전달 (없으면 전체 전달)
          final expiringBizIds = sec.byBusiness
              .where((b) => b.count > 0)
              .map((b) => b.businessId)
              .toList();
          final relevantBiz = businesses
              .where((b) =>
                  expiringBizIds.isEmpty || expiringBizIds.contains(b.id))
              .toList();
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => ExpiringContractsScreen(
              businessIds: expiringBizIds.isEmpty
                  ? businesses.map((b) => b.id).toList()
                  : expiringBizIds,
              businesses: relevantBiz,
            ),
          ));
          if (mounted) unawaited(_loadCanonicalSummary());
        })),
      );
    }

    // 4. 이체 대기 — canManageWage
    if (!isSub || up.can((p) => p.canManageWage)) {
      final wage = cs?.actions.unpaidWage;
      final wageParts = <String>[];
      if ((wage?.overdueCount ?? 0) > 0) wageParts.add('연체 ${wage!.overdueCount}건');
      if ((wage?.missingDueDateCount ?? 0) > 0) wageParts.add('지급일 확인 필요 ${wage!.missingDueDateCount}명');
      // count(지급일 있는 그룹) + missingDueDateCount(지급일 없는 유니크 유저) 합산
      final wageTotal = (wage?.count ?? 0) + (wage?.missingDueDateCount ?? 0);
      add(
        icon: Icons.account_balance_wallet_outlined, label: '이체 대기',
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
            context: context, tab: 0, sheetTitle: '이체 대기',
            bizIds: affectedBiz.map((b) => b.businessId).toList(),
            countPerBiz: countMap, showAllOutstanding: true,
            secondaryLabel: '지급일 확인 필요', secondaryCountPerBiz: missingMap,
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

}

