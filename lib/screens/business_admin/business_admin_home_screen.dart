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
import '../../controllers/workforce_controller.dart';
import '../../services/firestore_service.dart';
import '../../utils/attendance_list_pdf.dart';
import '../../utils/attendance_review_helper.dart';
import '../../utils/work_detail_helper.dart';
import '../../services/work_detail_time_service.dart';

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
import '../../services/staffing_readiness_service.dart';
import '../../models/ui/staffing_readiness_model.dart';
import '../../models/core/attendance_model.dart'; // AttendanceModel 타입 어노테이션 직접 사용;
import 'dialogs/day_applicants_dialog.dart'; // [PHASE-2D] 인력 부족 → 지원자 관리 다이얼로그
import 'dialogs/attendance_status_dialog.dart'; // [PHASE-R5.2] 확인 필요 → 출근 현황 리뷰
import 'dialogs/resign_request_management_dialog.dart'; // [AH-V2-02B] 퇴사 요청 → 기존 처리 UI
import 'dialogs/schedule_request_management_dialog.dart'; // [AH-V2-02C] 스케줄 변경 요청 → 기존 처리 UI

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

  // [AH-V2-05A] activeTO 카운트와 posting revision listener 제거.
  //   Phase 2C 이후 화면에 표시되지 않는 값이었고, Home 진입·새로고침마다
  //   사업장 수만큼 callableGetTOsByBiz를 호출한 뒤 결과를 버리고 있었다.
  //   revision listener도 이 값만 갱신했으므로 함께 정리한다.
  //   Home의 신선도는 FCM·앱 복귀(_autoRefresh)와 당겨서 새로고침이 담당한다.

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
  // [AH-V2-06] 지금까지 출근했어야 할 인원 (분모). null = 조회 실패
  int? _todayDueNow;
  int? _todayNeedsAttention;
  bool _attendanceLoading = true;

  // 새로고침 동시 실행 방어 + 자동 쿨다운
  bool _isRefreshing = false;
  DateTime? _lastAutoRefreshAt;

  late final VoidCallback _onFcmRefresh;

  // [POSTING-V2-02B.2] 다른 탭에서 성공한 mutation 수신
  int _lastSeenMutationRevision = 0;

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
    // [POSTING-V2-02B.2] 공고·근무 탭에서 성공한 mutation을 받는다.
    //   관리자 자신의 action은 FCM으로 회수되지 않고, Shell이 IndexedStack이라
    //   탭 재진입으로도 loader가 다시 돌지 않는다. 이 신호가 유일한 회수 경로다.
    //   Home 자신이 낸 mutation은 origin으로 걸러 중복 full refresh를 막는다.
    _lastSeenMutationRevision = WorkforceController.dataRevision.value;
    WorkforceController.dataRevision.addListener(_onAdminMutation);
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
    WorkforceController.dataRevision.removeListener(_onAdminMutation);
    // [PH1C] 사업장 전환 감지 리스너 해제 (postFrameCallback 실행 전 dispose 방어)
    _cachedUp?.removeListener(_onBusinessSwitchCheck);
    super.dispose();
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
    unawaited(_loadStaffingReadiness());
    unawaited(_loadTodayAttendance());
    unawaited(_loadPostingReadiness());
    unawaited(_loadCanonicalSummary());
  }

  // 자동 트리거(FCM·앱 복귀)용 — 30초 쿨다운 + 동시 실행 방어
  // [POSTING-V2-02B.2] 공고·근무 탭 mutation 수신.
  // Home이 낸 mutation은 이미 해당 성공 콜백이 필요한 loader만 돌렸으므로 건너뛴다.
  // _autoRefresh를 재사용하므로 기존 30초 쿨다운이 연속 mutation을 흡수한다.
  void _onAdminMutation() {
    final rev = WorkforceController.dataRevision.value;
    if (rev <= _lastSeenMutationRevision) return;
    _lastSeenMutationRevision = rev;
    if (WorkforceController.lastMutationOrigin == AdminMutationOrigin.home) {
      return;
    }
    if (mounted) _autoRefresh();
  }

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
        _loadCanonicalSummary(),
        _loadStaffingReadiness(),
        _loadTodayAttendance(),
        // [P2-01] 당겨서 새로고침으로도 첫 공고 준비 상태가 갱신돼야 한다.
        //   _reloadReadiness()는 내부에서 사업장 조회를 먼저 await하므로
        //   이 목록에 넣어도 순서가 보장된다.
        _reloadReadiness(),
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
      // [AH-V2-01] 실패를 빈 목록으로 받지 않는다.
      //   []로 받으면 _hasApprovedBusiness=false + _businesses=[] 가 되어
      //   사업장이 있는 관리자에게 '사업장을 등록하세요' 배너가 뜬다.
      //   throw하면 아래 catch가 _hasApprovedBusiness를 null로 유지 → 배너 미표시.
      final businesses = await _firestoreService.getBusinessesByIdsOrThrow(ids);
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
  // [AH-V2-06] roster는 OrThrow variant를 쓴다. 이전에는 내부 try-catch가 []를
  // 반환해 조회 실패가 '확인 필요 0'·'출근 0'으로 새어나갔다 (ERROR != ZERO 위반).
  // 이제 roster·attendance 중 하나라도 실패하면 세 숫자가 함께 null이 된다.
  //
  // 실패 시 _todayCheckedIn = null 유지 — false zero 방지 (ERROR≠ZERO)
  /// [AH-V2-06] "HH:mm"(레거시 "HH:mm:ss") → 오늘 날짜의 DateTime.
  ///   해석할 수 없으면 null — 임의 시각을 만들어 분모에 넣지 않는다.
  static DateTime? _todayStartAt(DateTime day, String raw) {
    final t = raw.length >= 5 ? raw.substring(0, 5) : raw;
    final parts = t.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return DateTime(day.year, day.month, day.day, h, m);
  }

  Future<void> _loadTodayAttendance() async {
    if (!mounted) return;
    setState(() => _attendanceLoading = true);
    try {
      // [AH-V2-01] 여기 도달했다는 것은 사업장 조회가 성공했다는 뜻이다.
      //   실패는 _getBusinesses()가 throw → 아래 catch에서 ERROR 상태로 간다.
      //   따라서 이 isEmpty는 "접근 가능한 사업장이 실제로 0개"만 의미한다
      //   (SubAdmin 권한 0개 포함) → 정상 0 표시.
      final businesses = await _getBusinesses();
      if (businesses.isEmpty) {
        if (mounted) {
          setState(() {
            _todayCheckedIn      = 0;
            _todayDueNow         = 0;
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
        businesses.map((b) => _firestoreService.getConfirmedWorkersByDateAndBusinessOrThrow(
          date: today, businessId: b.id)),
      );

      final allAttendance = (await attFuture).expand((l) => l).toList();
      final allConfirmed  = (await rosterFuture).expand((l) => l).toList();

      // applicationId → AttendanceModel (중복 집계 방지용)
      final attMap = <String, AttendanceModel>{};
      for (final a in allAttendance) {
        if (a.applicationId.isNotEmpty) attMap[a.applicationId] = a;
      }

      // [AH-V2-04A.1] 실제 적용 근무시간 — AttendanceStatusDialog·급여 확정과
      //   같은 소스. 지원서 원본 시각만 쓰면 workDetail override가 걸린 근무에서
      //   Home과 Dialog의 시간 경계가 갈린다.
      //   비용은 근로자 수가 아니라 고유 (toId, slotId) 쌍 수에 비례한다.
      final timeMap = await WorkDetailTimeService.load(allConfirmed);

      // [AH-V2-06] 출근 x / y — 오늘 확정 로스터 하나의 모집단에서 센다.
      //   이전에는 분자를 attendance 문서에서 세어, 로스터에 없는 문서(취소된
      //   지원자의 잔존 기록·applicationId 없는 문서)까지 들어갔다. 옆의
      //   '근태 확인'은 로스터 기준이라 같은 카드에서 모집단이 달랐다.
      //
      //   분모 = 지금까지 근무 시작 시각이 도래한 사람 ∪ 이미 출근한 사람.
      //   '오늘 전체 확정 인원'을 쓰면 아직 출근할 시간이 아닌 오후·야간
      //   근무자가 미출근처럼 보이고, 옆의 '확정'과 같은 값을 두 번 보여준다.
      //   조기 출근이 막혀 있지 않으므로(서버 게이트는 날짜만 검사) 이미
      //   출근한 사람을 분모에 함께 넣어야 x <= y가 깨지지 않는다.
      //
      //   노쇼는 분모에 남는다 — 출근 대상이었으나 오지 않은 결과이므로
      //   빼면 출근 상황이 실제보다 좋아 보인다.
      var checkedIn = 0;
      var dueNow = 0;
      for (final app in allConfirmed) {
        final hasCheckedIn = attMap[app.id]?.checkInAt != null;
        if (hasCheckedIn) checkedIn++;
        final startAt = _todayStartAt(
            today, WorkDetailHelper.effectiveStart(app, timeMap));
        final started = startAt != null && !nowLocal.isBefore(startAt);
        if (started || hasCheckedIn) dueNow++;
      }

      // [AH-V2-04A] 근태 확인 — canonical actionability 판정.
      //   AttendanceReviewHelper가 Home과 AttendanceStatusDialog 검토 탭의
      //   단일 기준이다. 처리를 끝낸 건(NO_SHOW·결근·정산 진입·관리자 확인)은
      //   빠지므로, 처리하면 이 숫자가 실제로 줄어든다.
      //
      //   모수는 오늘 확정 로스터 — dialog와 동일하며, 지원서 단위 Set이라
      //   근태 문서가 중복돼도 한 사람은 1로 센다 ('N명' 단위 보장).
      final reviewAppIds = <String>{};
      for (final app in allConfirmed) {
        if (AttendanceReviewHelper.requiresReviewNow(
          now: nowLocal,
          workDate: today,
          scheduledStart: WorkDetailHelper.effectiveStart(app, timeMap),
          scheduledEnd: WorkDetailHelper.effectiveEnd(app, timeMap),
          attendance: attMap[app.id],
        )) {
          reviewAppIds.add(app.id);
        }
      }
      final needsAttention = reviewAppIds.length;

      if (!mounted) return;
      setState(() {
        _todayCheckedIn      = checkedIn;
        _todayDueNow         = dueNow;
        _todayNeedsAttention = needsAttention;
        _attendanceLoading   = false;
      });
    } catch (e) {
      debugPrint('❌ _loadTodayAttendance 실패: $e');
      if (!mounted) return;
      setState(() {
        _todayCheckedIn      = null; // 에러 상태 — 0 표시 금지 (ERROR≠ZERO)
        _todayDueNow         = null;
        _todayNeedsAttention = null;
        _attendanceLoading   = false;
      });
    }
  }

  /// D0 인력 현황 — _staffingReadiness.days[0] (오늘 날짜, CF가 D0부터 반환)
  /// 쓸 수 있는 데이터가 없거나(hasUsableData=false) days 비어있으면 null
  StaffingDayData? get _todayStaffingDay {
    final sr = _staffingReadiness;
    if (sr == null || !sr.hasUsableData || sr.days.isEmpty) return null;
    return sr.days.first;
  }

  /// 관리 사업장 목록 (최초 1회 조회 후 캐시).
  ///
  /// [AH-V2-01] 조회 실패를 빈 목록으로 변환하지 않는다 — throw한다.
  ///   실패를 []로 바꾸면 호출부가 "사업장 0개"와 구분할 수 없고,
  ///   오늘 출근이 실패를 '0명'으로, 상태 배너가 '사업장을 등록하세요'로
  ///   표시하게 된다. 둘 다 관리자에게 거짓 운영 신호다.
  /// 호출부 계약:
  ///   · 데이터 로더 — 자체 try/catch에서 error 상태로 전환 (수치 표시 금지)
  ///   · 네비게이션 — _safeNavigate가 잡아 오류 토스트 표시
  Future<List<BusinessModel>> _getBusinesses() async {
    if (_businesses.isNotEmpty) return _businesses;
    final up = context.read<UserProvider>();
    // SubAdmin: effectiveBusinessId 단일 ID, BUSINESS_ADMIN: managedBusinessIds 전체
    final ids = up.currentUser?.isSubAdmin == true
        ? [if (up.effectiveBusinessId != null) up.effectiveBusinessId!]
        : (up.currentUser?.managedBusinessIds ?? []);
    final businesses = await _firestoreService.getBusinessesByIdsOrThrow(ids);
    _businesses = businesses; // 캐시만 갱신 — UI에 직접 영향 없으므로 setState 불필요
    return businesses;
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
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('사업장 등록 후 공고·계약·급여 관리를 시작하세요.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ]),
              ),
            ]),
            SizedBox(height: 12 * s),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(Icons.add_business, size: 16 * s),
                label: Text('사업장 등록하기',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                  // [P2-01] 사업장/사용자 canonical 상태가 바뀌었으면
                  //   _firstPosting도 같은 복귀 안에서 다시 계산한다.
                  //   _reloadReadiness()가 _loadApprovedBusinessStatus()를
                  //   먼저 await하므로 중복 호출이 아니고 순서도 보장된다.
                  if (mounted) unawaited(_reloadReadiness());
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
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
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
                    // [AH-V2-05B] TODAY → TASK → NEXT.
                    //   오늘 상황을 본 다음 바로 지금 처리할 일이 오고,
                    //   다음 운영 준비(향후 인력 부족)가 마지막이다.
                    //   처리할 일이 0건이어도 이 순서는 고정한다 — Home 위치가
                    //   매번 달라지면 관리자가 화면을 학습할 수 없다.
                    _buildTodayOps(context, s, theme, up),
                    SizedBox(height: 16 * s),
                    _buildActionDashboard(context, s, theme, up),
                    SizedBox(height: 16 * s),
                    _buildFutureStaffing(context, s, theme, up), // [PHASE-2D]
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
                    fontSize: 17,
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
                  // [P2-01] 사업장/사용자 canonical 상태가 바뀌었으면
                  //   _firstPosting도 같은 복귀 안에서 다시 계산한다.
                  //   _reloadReadiness()가 _loadApprovedBusinessStatus()를
                  //   먼저 await하므로 중복 호출이 아니고 순서도 보장된다.
                  if (mounted) unawaited(_reloadReadiness());
                })),
          ]),
          SizedBox(height: 10 * s),
          // 인사말 + 배지 + [PH1] 사업장/권한 컨텍스트
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('안녕하세요,',
                style: TextStyle(
                    fontSize: 12, color: AppColors.grey500)),
            SizedBox(height: 2 * s),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Flexible(
                child: Text('$name님',
                    style: TextStyle(
                        fontSize: 22,
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
                    fontSize: 12,
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
      style: TextStyle(fontSize: 12, color: AppColors.grey400),
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
                fontSize: 12,
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
              color: theme.primaryColor, fontSize: 12, fontWeight: FontWeight.w600),
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
            fontSize: 12,
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
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        const Spacer(),
        if (action != null && onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(action,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
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
                      fontSize: 13,
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
                      fontSize: 12,
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
                  fontSize: 12.5,
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
                style: TextStyle(fontSize: 12, color: AppColors.grey400),
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
          // [AH-V2-05C] flat surface — 다른 관리자 화면과 같은 depth.
          //   상태(정상/에러)에 따라 카드 깊이가 달라지던 것도 함께 사라진다.
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
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

    // 쿼리 실패 — null 또는 쓸 수 있는 데이터 없음
    // [AH-V2-03.1] partial(부분합)은 여기서 걸리지 않고 아래로 내려간다.
    if (_staffingReadiness == null || !_staffingReadiness!.hasUsableData) {
      return _todayOpsErrorRow(s,
        message: '인력 정보를 불러오지 못했습니다',
        onRetry: () => unawaited(_loadStaffingReadiness()),
      );
    }

    // [AH-V2-03] 오늘 인력 운영 대상 자체가 없는 경우 —
    //   0/0/0 수치만 보여주면 "운영 중인데 필요 인원이 0"처럼 읽힌다.
    //   대상 없음은 수치가 아니라 상태로 말한다.
    if (!_staffingReadiness!.hasTodayTarget) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 16 * s),
        child: Row(children: [
          Icon(Icons.event_available_outlined,
              size: 16 * s, color: AppColors.grey300),
          SizedBox(width: 8 * s),
          Text('오늘 예정된 인력 운영이 없어요',
              style: TextStyle(fontSize: 13, color: AppColors.grey400)),
        ]),
      );
    }

    final day = _todayStaffingDay;
    final required  = day?.requiredCount  ?? 0;
    final confirmed = day?.confirmedCount ?? 0;
    final shortage  = day?.shortageCount  ?? 0;

    // [R6.1] 부족 탭 — canManageTo + shortage > 0 + day 존재 시 DayApplicantsDialog(오늘)
    final isSub = up.currentUser?.isSubAdmin == true;
    final canManageTo = !isSub || up.can((p) => p.canManageTo);
    final onShortageDay = (shortage > 0 && canManageTo) ? day : null;

    // [AH-V2-04B] 다사업장에서 이 숫자가 어느 범위의 합계인지 / 어디가 부족한지.
    //   scope label은 partial일 때 숨긴다 — 성공 사업장 수를 클라이언트가
    //   안전하게 알 수 없고, partial notice가 이미 범위를 말해주기 때문이다.
    final scopeLabel = _staffingScopeLabel();
    final shortageBy = shortage > 0 ? day?.shortageScopeLabel() : null;

    return Column(children: [
      if (scopeLabel != null)
        Padding(
          padding: EdgeInsets.fromLTRB(16 * s, 12 * s, 16 * s, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(scopeLabel,
                style: TextStyle(fontSize: 12, color: AppColors.grey400)),
          ),
        ),
      Padding(
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
      ),
      // [AH-V2-04B] 부족 위치 — 부족이 있을 때만, 다사업장일 때만.
      if (shortageBy != null && _isMultiBusinessScope)
        Padding(
          padding: EdgeInsets.fromLTRB(16 * s, 0, 16 * s, 12 * s),
          child: Row(children: [
            Icon(Icons.place_outlined, size: 13 * s, color: AppColors.grey400),
            SizedBox(width: 5 * s),
            Expanded(
              child: Text(shortageBy,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      // [AH-V2-03] 부분합 고지 — 숫자를 전체 합계로 오해하지 않도록
      _partialStaffingNotice(s),
    ]);
  }

  /// [AH-V2-04B] 관리 사업장이 2곳 이상인지 — staffing 집계 범위 기준.
  ///
  /// _getBusinesses()가 CF와 같은 scope를 쓴다 (SubAdmin: effectiveBusinessId 1곳,
  /// OWNER: managedBusinessIds). 따라서 SubAdmin은 자연히 false가 된다.
  bool get _isMultiBusinessScope => _businesses.length > 1;

  /// 오늘 운영 수치의 집계 범위 라벨. 표시할 필요가 없으면 null.
  ///
  /// 단일 사업장은 header에 이미 사업장명이 있어 중복이다.
  /// partial 상태에서는 숨긴다 — '전체 3개 사업장'이 부분합과 정면으로 충돌하고,
  /// 성공한 사업장 수는 클라이언트가 안전하게 구할 수 없다
  /// (byBusiness는 그날 대상이 없는 사업장을 아예 담지 않는다).
  String? _staffingScopeLabel() {
    if (!_isMultiBusinessScope) return null;
    if (_staffingReadiness?.partial == true) return null;
    return '전체 ${_businesses.length}개 사업장 합계';
  }

  /// [AH-V2-03] 일부 사업장 조회 실패 고지.
  ///
  /// 정상 사업장 데이터는 그대로 보여주되, 표시된 숫자가 전체 합계가
  /// 아니라는 사실을 숨기지 않는다. 실패를 0으로 합산하지 않으므로
  /// 수치 자체는 "성공한 사업장의 정확한 합"이다.
  Widget _partialStaffingNotice(double s) {
    final sr = _staffingReadiness;
    if (sr == null || !sr.partial) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(16 * s, 0, 16 * s, 10 * s),
      child: Row(children: [
        Icon(Icons.info_outline, size: 13 * s, color: AppColors.warning),
        SizedBox(width: 6 * s),
        Expanded(
          child: Text(
            '사업장 ${sr.failedBusinessCount}곳의 정보를 불러오지 못해 '
            '나머지 사업장 기준으로 표시했어요',
            style: TextStyle(fontSize: 12, color: AppColors.warning),
          ),
        ),
        InkWell(
          onTap: () => unawaited(_loadStaffingReadiness()),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
            child: Text('재시도',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning)),
          ),
        ),
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

    // [AH-V2-06] 분모 0 = 오늘 근무는 있지만 아직 첫 시작 시각 전.
    //   '0 / 0'은 운영이 없는 것처럼 읽히므로 상태로 말한다.
    //   오늘 로스터 자체가 없는 경우는 staffing의 hasTodayTarget 분기가 위에서
    //   이미 '오늘 예정된 인력 운영이 없어요'로 처리한다.
    final dueNow = _todayDueNow ?? 0;
    final checkedInText =
        dueNow == 0 ? '예정 전' : '${_todayCheckedIn!} / $dueNow';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 14 * s),
      child: Row(children: [
        _opsMetric(s, label: '현재 출근', value: _todayCheckedIn!, unit: '명',
          valueText: checkedInText),
        _opsMetricDivider(s),
        _opsMetric(s, label: '근태 확인', value: needsAttention, unit: '명',
          valueColor: needsAttention > 0 ? AppColors.warning : null,
          onTap: onAttentionTap),
      ]),
    );
  }

  /// 오늘 운영 수치 셀 (Expanded — Row 내 균등 분배)
  /// [PHASE-R5.2] onTap 옵션: 수치 > 0 + 권한 있을 때 탭 가능, subtle chevron 표시
  /// [AH-V2-06] valueText를 주면 그것을 그대로 쓴다 ('12 / 15', '예정 전').
  ///   주지 않으면 기존대로 '$value$unit'.
  Widget _opsMetric(double s, {
    required String label,
    required int value,
    required String unit,
    String? valueText,
    Color? valueColor,
    VoidCallback? onTap,
  }) {
    final col = Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(fontSize: 12, color: AppColors.grey500)),
      SizedBox(height: 4 * s),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text(valueText ?? '$value$unit', style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3,
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
          style: TextStyle(fontSize: 12, color: AppColors.grey400))),
        GestureDetector(
          onTap: onRetry,
          child: Text('재시도', style: TextStyle(
            fontSize: 12, color: AppColors.textSecondary,
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

    // 에러: null 또는 쓸 수 있는 데이터 없음 (ERROR≠ZERO — 0 표시 금지)
    // [AH-V2-03.1] partial(부분합)은 여기서 걸리지 않고 아래로 내려간다.
    if (_staffingReadiness == null || !_staffingReadiness!.hasUsableData) {
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

    // 부족 없음 — 두 가지 의미를 구분한다 [AH-V2-03]
    //   운영 대상 자체가 없음  vs  대상은 있고 전부 충원됨
    if (futureDays.isEmpty) {
      final hasTarget = _staffingReadiness!.hasFutureTarget;
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
            child: Column(children: [
              Row(children: [
                Icon(
                    hasTarget
                        ? Icons.check_circle_outline
                        : Icons.event_available_outlined,
                    size: 16 * s, color: AppColors.grey300),
                SizedBox(width: 8 * s),
                Expanded(
                  child: Text(
                    hasTarget
                        ? '향후 7일 인원이 모두 충원됐어요'
                        : '향후 7일 예정된 인력 운영이 없어요',
                    style: TextStyle(fontSize: 13, color: AppColors.grey400),
                  ),
                ),
              ]),
              if (_staffingReadiness!.partial) ...[
                SizedBox(height: 8 * s),
                _partialStaffingNotice(s),
              ],
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
          // [AH-V2-05C] flat surface — 부족 목록이 있을 때만 그림자가 생겨
          //   같은 섹션이 상태에 따라 다른 깊이로 보이던 것을 없앤다.
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              ...futureDays.asMap().entries.map((e) =>
                _buildFutureShortageRow(
                  context, s, theme, up, e.value,
                  isFirst: e.key == 0,
                  isLast: e.key == futureDays.length - 1,
                ),
              ),
              // [AH-V2-03] 부분합 고지 — 빠진 사업장의 부족이 누락됐을 수 있다
              _partialStaffingNotice(s),
            ],
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

    // [AH-V2-04B] 부족 위치 — 다사업장일 때만
    final bizLine = _isMultiBusinessScope ? day.shortageScopeLabel() : null;

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
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ),
        SizedBox(width: 8 * s),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(shortageStr,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning)),
                  if (pendingStr != null) ...[
                    Text(' · ',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.grey400)),
                    Text(pendingStr,
                        style: TextStyle(
                            fontSize: 12, color: AppColors.grey500)),
                  ],
                ],
              ),
              // [AH-V2-04B] 어느 사업장이 부족한지 — 다사업장일 때만 compact subline.
              //   날짜 row가 사업장 목록으로 커지지 않도록 2곳 + '외 N곳'으로 접는다.
              if (bizLine != null) ...[
                SizedBox(height: 2 * s),
                Text(bizLine,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.grey500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
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
                  fontSize: 12, fontWeight: FontWeight.w600),
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

    // [AH-V2-04B] Home이 보여준 순서(부족 큰 순)와 같게 넘긴다.
    //   dialog 초기 선택이 businessIds.first이므로 가장 부족한 곳이 먼저 열린다.
    //   (직전 사용 사업장이 저장돼 있고 그것도 부족 목록에 있으면 그쪽이 우선된다)
    final shortBizIds = day.shortageBusinesses
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
    if ((changed ?? false) && mounted) {
      unawaited(_loadStaffingReadiness());
      // [POSTING-V2-02B.2] 확정·거절·초대·업무유형 변경·확정 취소·좌석 반납은
      //   전부 slot confirmed/pending 또는 workDetailCounts를 움직인다.
      //   공고·근무 탭이 stale해지므로 알린다. Home 자신은 위 loader로 이미 갱신됐다.
      WorkforceController.notifyDataChanged(
        origin: AdminMutationOrigin.home,
      );
    }
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
                  style: TextStyle(fontSize: 13, color: AppColors.grey400)),
            ]),
          ),
        )
      else
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16 * s),
          child: Container(
            // [AH-V2-05C] flat surface — 할 일이 있을 때만 그림자가 생겨
            //   로딩·빈 상태와 깊이가 달라지던 것을 없앤다.
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
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

    // [AH-V2-05B.3] atIndex는 '이체 대기' 연체 상향 한 곳에만 쓴다.
    //   행 목록을 점수로 재정렬하는 구조가 아니라, 정해진 자리에 넣는 것이다.
    void add({
      required IconData icon, required String label, required Color color,
      String? badge, required int count, required bool available, required String countStr,
      required VoidCallback onTap,
      int? atIndex,
    }) {
      if (available && count == 0) return; // valid 0 → 숨김 (ZERO_COUNT_ACTION_VISIBILITY = HIDE)
      final row = (icon: icon, label: label, badge: badge, countStr: countStr,
          color: color, count: count, available: available, onTap: onTap);
      if (atIndex != null) {
        result.insert(atIndex, row);
      } else {
        result.add(row);
      }
    }

    // 1. 퇴사 요청 — canManageWorkers
    // [AH-V2-02B] 다른 항목과 달리 방치하면 D+3에 시스템이 자동 승인한다.
    //   관리자가 결정하지 않은 것과 못 본 것이 같은 결과를 내므로 최상단에 둔다.
    //   기존 발견 경로는 알림뿐이었고, 경고(D+1·D+2)도 알림이라 함께 사라졌다.
    if (!isSub || up.can((p) => p.canManageWorkers)) {
      final resign = cs?.actions.resignRequest;
      final soon = resign?.soonCount ?? 0;
      add(
        icon: Icons.logout_outlined, label: '퇴사 요청',
        color: AppColors.error,
        badge: soon > 0 ? '내일 자동 승인 $soon건' : null,
        count: resign?.count ?? 0, countStr: '${resign?.count ?? 0}건',
        available: resign?.available ?? false,
        onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
          if (!up.can((p) => p.canManageWorkers)) {
            ToastHelper.showWarning('근로자 관리 권한이 없습니다.'); return;
          }
          if (!_ensureCanonicalSummary(context)) return;
          final sec = _canonicalSummary!.actions.resignRequest;
          if (!sec.available) { _showCanonicalError(context); return; }
          if (sec.count == 0) return;
          final affectedBiz = sec.byBusiness.where((b) => b.count > 0).toList();
          final countMap = <String, int>{for (final b in sec.byBusiness) b.businessId: b.count};
          final bizId = await _pickBizFromSummary(
            context: context, sheetTitle: '퇴사 요청', totalCount: sec.count,
            bizIds: affectedBiz.map((b) => b.businessId).toList(),
            countPerBiz: countMap,
          );
          if (bizId == null || !context.mounted) return;
          // 기존 처리 UI 재사용 — 이 다이얼로그는 businessId만 받아
          // PENDING 목록을 자체 조회한다 (단건 전용 아님).
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => ResignRequestManagementDialog(
              businessId: bizId,
              onChanged: () {},
            ),
          );
          if (mounted) unawaited(_loadCanonicalSummary());
        })),
      );
    }

    // [AH-V2-05B.3] 연체 급여가 있을 때 '이체 대기'가 들어갈 자리.
    //   퇴사 요청 바로 뒤 — 퇴사 요청이 권한·0건으로 빠졌으면 자연히 맨 앞이 된다.
    //   라벨 비교가 아니라 이 시점의 길이를 쓰므로 뒤 행이 늘어도 흔들리지 않는다.
    final overdueWageSlot = result.length;

    // 2. 지원 검토 — canManageTo
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
          // [AH-V2-04C] Home이 '긴급 N건'을 강조했으면 그 집합으로 바로 착지한다.
          //   긴급이 0이면 기존대로 전체 — 오늘/예정으로 임의 이동하지 않는다.
          //   매 진입 시 최신 canonical summary를 기준으로 다시 판단한다.
          final changed = await Navigator.push<bool>(context,
            SupportReviewQueueScreen.route(
              businessIds: businesses.map((b) => b.id).toList(),
              businesses: businesses,
              initialFilter: (approval?.overdueCount ?? 0) > 0
                  ? SupportReviewFilter.overdue
                  : SupportReviewFilter.all,
            ),
          );
          if (changed == true && mounted) {
            unawaited(_loadCanonicalSummary());
            // [POSTING-V2-02B.2] 승인/거절은 DayApplicantsDialog와 같은
            //   updateApplicationStatus CF를 타므로 동일 카운터를 움직인다.
            WorkforceController.notifyDataChanged(
              origin: AdminMutationOrigin.home,
            );
          }
        })),
      );
    }

    // 3. 스케줄 변경 요청 — canManageWorkers
    // [AH-V2-02C] 지원자가 보낸 휴무/휴무취소/추가근무취소 요청.
    //   서버가 requestedBy == APPLICANT 로 이미 걸러서 내려준다 —
    //   관리자가 보낸 NO_WORK/EXTRA_WORK는 근로자 응답 대기라 여기 없다.
    //   자동 처리가 없어 방치하면 영구 PENDING으로 남는다.
    if (!isSub || up.can((p) => p.canManageWorkers)) {
      final sched = cs?.actions.scheduleChangeRequest;
      add(
        icon: Icons.edit_calendar_outlined, label: '스케줄 변경 요청',
        color: AppColors.info,
        count: sched?.count ?? 0, countStr: '${sched?.count ?? 0}건',
        available: sched?.available ?? false,
        onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
          if (!up.can((p) => p.canManageWorkers)) {
            ToastHelper.showWarning('근로자 관리 권한이 없습니다.'); return;
          }
          if (!_ensureCanonicalSummary(context)) return;
          final sec = _canonicalSummary!.actions.scheduleChangeRequest;
          if (!sec.available) { _showCanonicalError(context); return; }
          if (sec.count == 0) return;
          final affectedBiz = sec.byBusiness.where((b) => b.count > 0).toList();
          final countMap = <String, int>{for (final b in sec.byBusiness) b.businessId: b.count};
          final bizId = await _pickBizFromSummary(
            context: context, sheetTitle: '스케줄 변경 요청', totalCount: sec.count,
            bizIds: affectedBiz.map((b) => b.businessId).toList(),
            countPerBiz: countMap,
          );
          if (bizId == null || !context.mounted) return;
          // 기존 처리 UI 재사용 — businessId만 받아 목록을 자체 조회하고
          // requestedBy == APPLICANT 로 필터한 뒤 PENDING을 기본 표시한다.
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => ScheduleRequestManagementDialog(
              businessId: bizId,
              onChanged: () {},
            ),
          );
          if (mounted) unawaited(_loadCanonicalSummary());
        })),
      );
    }

    // 4. 계약 미발송 — canManageContract
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

    // 5. 마감 필요 — canManageWage
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

    // 6. 중간정산 요청 — canManageWage
    // [AH-V2-02A] 근로자가 보낸 중간정산 요청(interim_settlement_requests
    //   status=PENDING). showPendingSettlementOnly는 "홈 진입 시 true"로
    //   설계돼 있었으나 Home에서 넘기는 곳이 없어 dead parameter였다.
    if (!isSub || up.can((p) => p.canManageWage)) {
      final settlement = cs?.actions.settlementRequest;
      add(
        icon: Icons.payments_outlined, label: '중간정산 요청',
        color: AppColors.info,
        count: settlement?.count ?? 0, countStr: '${settlement?.count ?? 0}건',
        available: settlement?.available ?? false,
        onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
          if (!_ensureCanonicalSummary(context)) return;
          final sec = _canonicalSummary!.actions.settlementRequest;
          if (!sec.available) { _showCanonicalError(context); return; }
          if (sec.count == 0) return;
          final affectedBiz = sec.byBusiness.where((b) => b.count > 0).toList();
          final countMap = <String, int>{for (final b in sec.byBusiness) b.businessId: b.count};
          // 중간정산 탭(3) + PENDING 전용 필터 — 승인·거절·처리완료 건 제외
          await _toPayrollTabDrilldown(
            context: context, tab: 3, sheetTitle: '중간정산 요청',
            bizIds: affectedBiz.map((b) => b.businessId).toList(),
            countPerBiz: countMap,
            showPendingSettlementOnly: true,
          );
        })),
      );
    }

    // 7. 급여 변경 요청 — canManageWage
    // [AH-V2-02A] 근로자가 보낸 급여 지급주기 변경 요청(payment_change_requests
    //   status=PENDING). CF·DTO는 이미 집계해 내려보내고 있었고 Home row만 없었다.
    //   방치하면 effectiveFrom(다음 지급 주기) 전에 처리되지 못한다.
    if (!isSub || up.can((p) => p.canManageWage)) {
      final wageChange = cs?.actions.wageChangeRequest;
      add(
        icon: Icons.edit_calendar_outlined, label: '급여 변경 요청',
        color: AppColors.info,
        count: wageChange?.count ?? 0, countStr: '${wageChange?.count ?? 0}건',
        available: wageChange?.available ?? false,
        onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
          if (!_ensureCanonicalSummary(context)) return;
          final sec = _canonicalSummary!.actions.wageChangeRequest;
          if (!sec.available) { _showCanonicalError(context); return; }
          if (sec.count == 0) return;
          final affectedBiz = sec.byBusiness.where((b) => b.count > 0).toList();
          final countMap = <String, int>{for (final b in sec.byBusiness) b.businessId: b.count};
          // 변경요청 탭(2) — 급여 첫 화면이 아니라 실제 처리 목록으로 진입
          await _toPayrollTabDrilldown(
            context: context, tab: 2, sheetTitle: '급여 변경 요청',
            bizIds: affectedBiz.map((b) => b.businessId).toList(),
            countPerBiz: countMap,
          );
        })),
      );
    }

    // 8. 이체 대기 — canManageWage
    if (!isSub || up.can((p) => p.canManageWage)) {
      final wage = cs?.actions.unpaidWage;
      final wageParts = <String>[];
      if ((wage?.overdueCount ?? 0) > 0) wageParts.add('연체 ${wage!.overdueCount}건');
      if ((wage?.missingDueDateCount ?? 0) > 0) wageParts.add('지급일 확인 필요 ${wage!.missingDueDateCount}명');
      // count(지급일 있는 그룹) + missingDueDateCount(지급일 없는 유니크 유저) 합산
      final wageTotal = (wage?.count ?? 0) + (wage?.missingDueDateCount ?? 0);
      // [AH-V2-05B.3] 지급예정일이 지난 급여가 있으면 퇴사 요청 바로 뒤로 올린다.
      //   평상시에는 8순위 그대로 — 정기 이체 대기 물량이 많다는 것은 긴급이 아니다.
      //   조건은 canonical overdueCount 하나뿐이다. count·missingDueDateCount·
      //   배지 문자열은 이동 근거로 쓰지 않는다.
      //   available=false면 숫자를 신뢰할 수 없으므로 옮기지 않는다 — 그때 행은
      //   '조회 실패' 칩을 달고 제자리에 남는다.
      final wageOverdue = wage?.available == true && (wage?.overdueCount ?? 0) > 0;
      add(
        icon: Icons.account_balance_wallet_outlined, label: '이체 대기',
        color: AppColors.error, badge: wageParts.isNotEmpty ? wageParts.join(' · ') : null,
        count: wageTotal, countStr: '$wageTotal건',
        available: wage?.available ?? false,
        atIndex: wageOverdue ? overdueWageSlot : null,
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
    // 9. 계약 종료 예정 — canManageContract
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
                  fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              if (item.badge != null) ...[
                SizedBox(height: 2 * s),
                // [PH1] badge 텍스트에 item.color 적용 → 긴급 항목("연체 N건") 시각적 강조
                Text(item.badge!, style: TextStyle(fontSize: 12, color: item.color.withValues(alpha: 0.85))),
              ],
            ])),
            SizedBox(width: 8 * s),
            if (!item.available)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
                decoration: BoxDecoration(
                  color: AppColors.grey100, borderRadius: BorderRadius.circular(8),
                ),
                child: Text('조회 실패', style: TextStyle(fontSize: 12, color: AppColors.grey500)),
              )
            else
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 5 * s),
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(item.countStr, style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: item.color)),
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

