import 'dart:async' show unawaited;

import '../../services/fcm_service.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Providers
import '../../providers/user_provider.dart';

// Utils
import '../../utils/format_helper.dart';
import '../../utils/text_layout.dart';
import '../../utils/toast_helper.dart';

// Services
import '../../controllers/workforce_controller.dart';
import '../../services/firestore_service.dart';
import '../../utils/attendance_list_pdf.dart';
import '../../utils/attendance_review_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/work_detail_helper.dart';

// Screens
import '../common/settings_screen.dart';
import '../common/notification_screen.dart';
import '../../widgets/common/legal_task_card.dart';
import '../../widgets/common/notification_badge.dart';
import '../../widgets/common/alfit_wordmark.dart';
import 'admin_contract_management_screen.dart';
import 'payroll/payroll_payment_dashboard_screen.dart';
// payroll_payment_service.dart — home screen에서 직접 사용 없음 (canonical summary로 대체됨)
import '../../theme/app_colors.dart';
import '../../theme/concept_tokens.dart';
import '../../models/core/business_member_model.dart'; // [R5.1F.5] MemberPermissions
import '../../models/core/business_model.dart';
import 'support_review_queue_screen.dart';
import 'expiring_contracts_screen.dart';
import 'unclosed_action_queue_screen.dart';
import 'Business_form_screen.dart';
import 'work_type_management_screen.dart';
import '../../services/business_posting_readiness.dart';
import '../../models/core/contract_template_model.dart';
import 'contract_template_list_screen.dart';
import '../../models/ui/admin_home_summary_model.dart';
import 'widgets/business_action_drill_down_sheet.dart';
import '../../widgets/common/business_selector_sheet.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/admin_tab_switcher.dart';
import '../../utils/navigation_helper.dart';
import 'to_management/create_to_screen.dart';
import 'admin_home_reads.dart';
import '../../models/ui/staffing_readiness_model.dart';
import '../../models/core/attendance_model.dart'; // AttendanceModel 타입 어노테이션 직접 사용;
import 'dialogs/day_applicants_dialog.dart'; // [PHASE-2D] 인력 부족 → 지원자 관리 다이얼로그
import 'dialogs/attendance_status_dialog.dart'; // [PHASE-R5.2] 확인 필요 → 출근 현황 리뷰
import 'dialogs/resign_request_management_dialog.dart'; // [AH-V2-02B] 퇴사 요청 → 기존 처리 UI
import 'dialogs/schedule_request_management_dialog.dart'; // [AH-V2-02C] 스케줄 변경 요청 → 기존 처리 UI

// [PERF-2026-07-16] Selector용 record — 필요한 필드만 추출해 불필요한 rebuild 방지
/// [HOME-V2-08D.2] Adaptive Hero가 선택할 수 있는 상태.
///
/// 위에서 처음 참인 것 하나만 쓴다. lifecycle(setup/noPosting/draftOnly)에서만
/// Hero가 CTA를 갖는다 — 운영 상태에서는 행동 경로가 이미 각 섹션에 있다.
enum _HeroState {
  loading,
  error,
  partialInfo,
  setup,
  draftOnly,
  /// [CROSS-DOMAIN-R5.1F.1] 공고를 볼 수 있는 사업장이 하나도 없다.
  /// 0은 "공고가 없다"가 아니라 "볼 수 있는 범위가 없다"이다.
  noPostingScope,
  noPosting,
  shortage,
  attention,
  noToday,
  beforeStart,
  normalToday,
}

/// [CROSS-DOMAIN-R5.1E] Home이 다시 그려져야 하는 이유들.
///
/// 이 화면은 권한을 `context.read`로 읽어 섹션마다 내려준다 — 구독이 아니다.
/// 그래서 Selector가 이름만 보고 있던 동안에는 권한이 회수돼도 화면이 그대로
/// 남아, 누를 수 없는 CTA와 처리할 수 없는 Task가 계속 보였다(서버는 막는다).
/// 권한 자체를 지켜본다 — 바뀔 때만 다시 그린다.
typedef _AdminHomeData = ({
  String userName,
  bool canManageTo,
  bool canManageWorkers,
  bool canManageContract,
  bool canManageWage,
  bool subAdminPermissionsLoaded,
  bool canManageToAnywhere,
  PermissionWatchState permissionHealth,
});

class BusinessAdminHomeScreen extends StatefulWidget {
  const BusinessAdminHomeScreen({super.key, this.reads});

  /// [R7-P1-4 H4] 원시 외부 읽기 경계. production 은 null → `AdminHomeReads.of`.
  ///   테스트가 실제 홈 위젯을 띄워 내용을 렌더할 수 있게 하기 위한 것이며,
  ///   화면의 파생·수치·문구·권한 판정은 이 경계 **바깥이 아니라 안**에 있다.
  final AdminHomeReads? reads;

  @override
  State<BusinessAdminHomeScreen> createState() => _BusinessAdminHomeScreenState();
}

class _BusinessAdminHomeScreenState extends State<BusinessAdminHomeScreen>
    with WidgetsBindingObserver {
  final _firestoreService = FirestoreService();
  late final AdminHomeReads _reads =
      widget.reads ?? AdminHomeReads.of(_firestoreService);

  // [R7-P1-4 H2] 늦은 응답 가드 — loader 별 단조 증가 seq.
  //
  //   같은 loader 를 동시에 깨우는 경로가 여러 개다: initState · FCM
  //   (`_onFcmRefresh`) · 앱 복귀(`didChangeAppLifecycleState`) · 당겨서
  //   새로고침 · 사업장 전환(`_onBusinessSwitchCheck`) · 각 목적지에서 돌아올 때.
  //   `_isRefreshing` 은 **전체 refresh 끼리만** 막고 개별 loader 는 막지 않는다.
  //
  //   가드가 없으면 먼저 보낸 요청이 늦게 도착해 **방금 처리한 결과를 덮는다**
  //   (처리한 할 일이 다시 대기로 보이고, 눌러도 `count == 0` 으로 조용히 닫힌다).
  //   사업장 전환에서는 더 나쁘다 — 이전 사업장의 수치가 새 사업장 화면에 앉는다.
  //   그래서 **가장 마지막에 시작한 호출만** state 를 쓴다. 로딩 플래그도 그
  //   호출이 소유하므로, 밀려난 호출은 spinner 도 끄지 않는다.
  int _summarySeq = 0;
  int _staffingSeq = 0;
  int _attendanceSeq = 0;
  // [SUBADMIN-SCOPE.40] 준비 상태도 사업장 전환·권한 변경으로 겹쳐 돈다 — 같은 가드.
  int _readinessSeq = 0;

  // [SUBADMIN-SCOPE.40] 권한이 필요한 두 loader 가 **마지막으로 출발할 때 본 권한.**
  //   null = 아직 한 번도 출발하지 않았다. 권한 상태가 이 값과 달라지면 그 loader
  //   하나만 다시 돈다(허용이 되면 읽고, 거부가 되면 이전 값을 지운다).
  PermissionCheck? _attendanceGateRun;
  PermissionCheck? _readinessGateRun;
  bool? _hasApprovedBusiness;
  List<BusinessModel> _businesses = [];
  bool _isNavigating = false;

  // [5D.2A] 공고 등록 준비 — 사업장별 readiness (서버 5D.1A 정책과 동일)
  // isApproved + (canonical license OR owner legacy) + active workTypes >= 1
  bool _readinessLoaded = false;

  /// [FP-01] 첫 공고까지 남은 준비 — CreateTO와 같은 canonical fact에서 derive.
  FirstPostingReadiness? _firstPosting;

  /// [POSTING-V2-02C.1] 사업장별 readiness — 4개 task로 접기 전의 원본.
  ///   task bool만 남기면 "어느 사업장이 무엇이 없는지"가 사라져
  ///   CTA가 결핍과 무관한 사업장으로 이동한다. 추가 조회 없이
  ///   _loadPostingReadiness가 이미 받아온 값을 그대로 보관한다.
  Map<String, BusinessPostingReadiness> _readinessMap = const {};

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

  // ── [HOME-V2-08D.2] 오늘 로스터에서 파생한 최소 state ──────────────
  //
  // _loadTodayAttendance()가 이미 확정 로스터 전량(allConfirmed)과 실제 근무
  // 시각(WorkDetailTimeService)을 읽고도 숫자 셋만 남기고 버렸다. Hero와
  // Today gate에 필요한 만큼만 함께 보존한다 — **추가 조회 0**이다.
  //
  // null = 조회 실패. false/빈 문자열과 구분한다 (ERROR ≠ ZERO).

  /// 오늘 확정 로스터가 비어 있지 않은가. Today section gate가 쓴다.
  bool? _hasTodayRoster;

  /// 오늘 가장 이른 실제 근무 시작 시각 ("HH:mm"). 모르면 null.
  String? _todayFirstStart;

  /// 오늘 근무의 사업장·업무·시간 요약. 하나로 확정되지 않으면 개수로 말한다.
  String? _todayWorkSummary;
  /// [DU-VQ-03] 같은 로스터의 **업무·시간만**(사업장명 제외) — Hero 를 부족 행에 합칠 때 오늘 그룹 보조 줄에 쓴다.
  String? _todayWorkTimeSummary;

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
    // [P4.2C-READY-01] 관리 탭에서 돌아왔을 때 준비 상태를 다시 읽는다.
    AdminTabSwitcher.instance.registerHomeReactivation(_onHomeReactivated);
    AttendanceListPdf.preloadFonts();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // [PH1C] 사업장 전환 감지 초기화 — 최초 렌더 전 기준값 확정
      _cachedUp = context.read<UserProvider>();
      _renderedEffectiveBizId = _cachedUp!.effectiveBusinessId;
      _cachedUp!.addListener(_onBusinessSwitchCheck);

      // [R7-P1-4 후속 H2] 투어는 **데이터의 전제가 아니다.**
      //
      //   이전에는 `Future.wait([사업장 조회, 투어 완료 여부])` 를 기다린 뒤에야
      //   네 loader 를 시작했다. 투어 여부는 로컬 저장소(SharedPreferences) 한 줄이고
      //   권한·사업장·수치 어디에도 쓰이지 않는데, 그 future 가 늦거나 던지면
      //   `await` 가 거기서 멈춰 **네 loader 가 시작조차 하지 않았다** — 화면 전체가
      //   끝나지 않는 spinner 로 남고 재시도 버튼도 나오지 않는다(각 재시도는
      //   loader 가 한 번은 돌아 error 상태가 돼야 그려진다).
      //
      //   그래서 순서를 데이터 의존만으로 정한다: 사업장 → 네 loader.
      //   (`_loadPostingReadiness` 는 `_businesses` 를 읽으므로 이 순서가 필요하다.
      //    나머지 셋은 `_getBusinesses()` 로 자체 조회한다.)
      //   투어는 그 뒤에 **독립적으로** 확인하고, 실패는 삼켜서 데이터·화면을
      //   막지 않는다. 실패·timeout 을 완료로 저장하지 않는다 —
      //   `markCompleted` 는 투어를 실제로 끝낸 뒤에만 호출된다(아래 그대로).
      await _loadApprovedBusinessStatus();
      if (mounted) {
        unawaited(_loadCanonicalSummary());   // [PHASE-2C] canonical actions
        unawaited(_loadStaffingReadiness()); // [PHASE-2C] D0~D+7 인력 현황
        unawaited(_loadTodayAttendance());   // [PHASE-2C] 오늘 출근 현황
        unawaited(_loadPostingReadiness());   // [5D.2] compact setup checklist
      }
      // [R7-ONBOARDING.1] 자동 기능 투어를 띄우지 않는다.
      //
      //   이 투어는 가입 직후 보는 온보딩과 **같은 자산**이었다(관리자
      //   5페이지의 제목이 글자까지 같았다). 그래서 온보딩을 끝내면
      //   투어 플래그까지 완료로 찍어 중복을 막고 있었는데, 그건 한쪽이
      //   불필요하다는 뜻이다.
      //
      //   지금 관리자가 홈에서 알아야 하는 것은 기능 목록이 아니라
      //   **다음에 할 일**이고, 그건 바로 아래 준비 체크리스트가 말한다.
      //   기능 설명은 설정의 '가이드 다시 보기' 에서 원할 때 본다.
      //
      //   TourScreen 자체는 지우지 않았다 — 자동으로 밀어 넣지 않을 뿐이다.
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FCMService().removeAdminRefreshListener(_onFcmRefresh);
    WorkforceController.dataRevision.removeListener(_onAdminMutation);
    AdminTabSwitcher.instance.unregisterHomeReactivation(_onHomeReactivated);
    // [PH1C] 사업장 전환 감지 리스너 해제 (postFrameCallback 실행 전 dispose 방어)
    _cachedUp?.removeListener(_onBusinessSwitchCheck);
    super.dispose();
  }

  /// [P4.2C-READY-01] 다른 탭에 있다가 Home이 다시 앞으로 나왔다.
  ///
  ///   예전에는 헤더 버튼이 `SettingsScreen` 을 push 하고 **복귀할 때**
  ///   `_reloadReadiness()` 를 불렀다. 그 화면은 하단 '관리' 탭의 root 와
  ///   같은 위젯인데, **탭으로 들어간 경우에는 아무도 갱신하지 않았다** —
  ///   갱신 owner 가 화면이 아니라 한쪽 입구에 붙어 있었던 것이다.
  ///   owner 를 입구에서 **Home 재활성화**로 옮기면 두 입구가 같아진다.
  ///
  ///   관리 탭에서 온 경우만 본다. 공고·근무 탭의 변경은 이미
  ///   `WorkforceController.dataRevision` 이 나르고 `_onAdminMutation` 이
  ///   받는다. 모든 탭 전환마다 Home을 다시 읽지 않는다.
  ///
  ///   시간 쿨다운은 두지 않았다. "방금 읽었으니 건너뛴다"는 관리 탭에서
  ///   막 인감을 저장하고 돌아온 바로 그 순간을 건너뛸 수 있다 — 이 수정이
  ///   고치려는 상태다. 대신 진행 중인 재조회가 있으면 겹쳐 돌리지 않는다.
  void _onHomeReactivated(int fromTab) {
    if (!mounted) return;
    if (fromTab != AdminTabSwitcher.settingsTab) return;
    if (_isReloadingReadiness) return;
    unawaited(_reloadReadinessGuarded());
  }

  bool _isReloadingReadiness = false;

  Future<void> _reloadReadinessGuarded() async {
    _isReloadingReadiness = true;
    try {
      await _reloadReadiness();
    } finally {
      _isReloadingReadiness = false;
    }
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
    if (newBizId == _renderedEffectiveBizId) {
      _rerunIfPermissionChanged();
      return;
    }
    _renderedEffectiveBizId = newBizId;
    // _businesses 캐시 초기화 → 새 사업장 기준 재조회
    setState(() => _businesses = []);
    _loadApprovedBusinessStatus();
    unawaited(_loadStaffingReadiness());
    unawaited(_loadTodayAttendance());
    unawaited(_loadPostingReadiness());
    unawaited(_loadCanonicalSummary());
  }

  // ── [SUBADMIN-SCOPE.40] 선택 사업장 권한으로 출발 여부가 갈리는 loader ──────
  //
  // 서버는 오늘 출근의 확정 명단(`workerOperation`)에 canManageWorkers 를,
  // 준비 상태의 날인 조회에 canManageTo 또는 canManageContract 를 요구한다.
  // 권한이 없는 사업장(예: 급여만 허용)에서 이 loader 들이 그대로 출발해
  // 거절될 조회 4건을 보냈다. 화면은 이미 그 구역을 그리지 않는다
  // (`_buildTodayOps` 의 canSeeAttendance, 서브관리자 준비 카드 없음) —
  // 조회만 화면과 같은 판정을 따르게 한다. 판정은 `checkCurrentBusiness` 하나다.

  /// 오늘 출근 — 확정 명단이 없으면 근태 기록(급여 권한으로도 읽힘)만으로는
  /// 출근 수를 셀 수 없다. 그래서 명단 권한이 이 loader 의 권한이다.
  ///
  /// 서브관리자만 판정한다 — 소유자는 사업장별 권한이 없다(`_canCreatePosting` 과
  /// 같은 모양).
  PermissionCheck _attendanceGate(UserProvider up) =>
      up.currentUser?.isSubAdmin != true
          ? PermissionCheck.allowed
          : up.checkCurrentBusiness((p) => p.canManageWorkers);

  /// 준비 상태 — 서브관리자에게 이 값의 소비자는 공고 탭과 공고 등록뿐이다
  /// (홈 준비 카드는 서브관리자에게 그리지 않는다). 둘 다 canManageTo 다.
  PermissionCheck _readinessGate(UserProvider up) =>
      up.currentUser?.isSubAdmin != true
          ? PermissionCheck.allowed
          : up.checkCurrentBusiness((p) => p.canManageTo);

  /// 권한이 바뀌었으면 그 권한이 막던 loader 만 다시 돈다. 같은 사업장 안의
  /// 변화다 — 사업장 전환은 위에서 전부 다시 읽는다.
  void _rerunIfPermissionChanged() {
    final up = _cachedUp;
    if (up == null) return;
    final a = _attendanceGateRun;
    if (a != null && _attendanceGate(up) != a) unawaited(_loadTodayAttendance());
    final r = _readinessGateRun;
    if (r != null && _readinessGate(up) != r) unawaited(_loadPostingReadiness());
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
    final seq = ++_summarySeq;
    setState(() => _canonicalSummaryLoading = true);
    try {
      // [PH1D] SUB_ADMIN: effectiveBusinessId scope → 서버가 membership 검증 후 단일 사업장 집계
      // OWNER: null → 기존 전체 aggregate 유지
      final up = context.read<UserProvider>();
      final selectedBizId = up.currentUser?.isSubAdmin == true
          ? up.effectiveBusinessId
          : null;
      final summary = await _reads.summary(
        selectedBusinessId: selectedBizId,
      );
      if (!mounted || seq != _summarySeq) return;
      setState(() {
        _canonicalSummary = summary;
        _canonicalSummaryLoading = false;
      });
    } catch (e) {
      debugPrint('❌ _loadCanonicalSummary 실패: $e');
      if (!mounted || seq != _summarySeq) return;
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
      ToastHelper.showInfo('업무 정보를 불러오고 있어요');
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
      final businesses = await _reads.businessesByIds(ids);
      if (mounted) {
        setState(() {
          _hasApprovedBusiness = businesses.any((b) => b.isApproved);
          _businesses = businesses;
        });
      }
    } catch (e) {
      debugPrint('❌ 사업장 조회 실패: $e');
      if (mounted) ToastHelper.showError('사업장 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요');
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
    // [R7-P4.4E.2A] 판정은 **화면 밖**에서 한다.
    //
    //   예전에는 이 계산이 Home State 안에만 있었다. 그래서 Home 을 한 번도
    //   그리지 않고 공고 탭으로 바로 들어가면 아무도 답을 갖고 있지 않았고,
    //   공고 탭은 그 모름을 '정상 · 공고 0건' 으로 그렸다.
    //   Home 은 여전히 setup UX 의 owner 다 — 전체 체크리스트와 각 단계로
    //   가는 길은 여기에만 있다. 바뀐 것은 **사실을 누가 계산하는가** 뿐이다.
    final up = context.read<UserProvider>();
    final uid = up.currentUser?.uid;
    final scopeKey =
        FirstPostingReadinessStore.scopeKeyOf(_businesses.map((b) => b.id));

    // [SUBADMIN-SCOPE.40] 공고 권한이 확인된 경우에만 계산한다(소유자는 언제나 허용).
    //   허용이 아니면 날인·사업주 문서를 묻지 않는다. 준비 값은 비워 둔다 —
    //   이전 사업장의 값이 남지 않게. 모름이면 아직 끝난 것이 아니다.
    final seq = ++_readinessSeq;
    final gate = _readinessGate(up);
    _readinessGateRun = gate;
    if (gate != PermissionCheck.allowed) {
      if (!mounted) return;
      setState(() {
        _readinessMap = const {};
        _firstPosting = null;
        _readinessLoaded = gate != PermissionCheck.unknown;
      });
      return;
    }

    late final FirstPostingReadinessResult result;
    try {
      result = await FirstPostingReadinessResolver.resolve(
        businesses: _businesses,
        postingReadiness: _reads.postingReadiness,
        contractTemplates: _reads.contractTemplates,
        selectableForNewContract: (list) =>
            ContractTemplateModel.selectableForNewContract(
                    list.cast<ContractTemplateModel>())
                .isNotEmpty,
        callerHasSeal: up.currentUser?.sealBase64?.isNotEmpty ?? false,
      );
    } catch (e) {
      debugPrint('❌ [readiness] 준비 상태 계산 실패: ');
      if (seq != _readinessSeq) return;
      FirstPostingReadinessStore.markFailed(uid: uid, scopeKey: scopeKey);
      return;
    }

    if (!mounted || seq != _readinessSeq) return;
    setState(() {
      _readinessMap = result.readinessMap;
      _firstPosting = result.readiness;
      _readinessLoaded = true;
    });

    // 공고 root·CreateTO 가 같은 값을 본다. 누구의·어느 사업장 집합에 대한
    // 판정인지까지 함께 남긴다 — 계정이 바뀌면 남의 값을 이어 쓰지 않는다.
    FirstPostingReadinessStore.publish(result.readiness,
        uid: uid, scopeKey: scopeKey);
  }

  // ── [POSTING-V2-02C.1] readiness CTA 대상 사업장 ────────────────
  // 이전에는 세 CTA가 모두 `_businesses.first`로 갔다. 업무가 없는 쪽이 A인데
  // 이미 업무가 있는 B의 화면이 열리면, 관리자는 "업무가 있는데 왜 미완료인가"를
  // 보게 된다. 아래 선택은 모두 _readinessMap 위의 순수 계산이다 — 추가 조회 없음.
  //
  // _businesses의 기존 순서를 그대로 쓴다. 새 정렬 정책을 만들지 않는다.

  BusinessModel? _firstBusinessWhere(
    bool Function(BusinessPostingReadiness? r) test,
  ) {
    for (final b in _businesses) {
      if (test(_readinessMap[b.id])) return b;
    }
    return null;
  }

  /// 업무 등록 CTA 대상.
  ///   1순위 — 업무만 추가하면 바로 공고를 만들 수 있는 사업장
  ///   2순위 — 승인됐지만 업무가 없는 사업장 (등록증 결핍은 사업장 task 몫)
  ///   3순위 — 아직 승인 전이라 readiness를 알 수 없는 사업장
  ///           (승인 전에도 업무를 준비할 수 있다는 기존 계약 유지)
  /// 셋 다 없으면 null — 이동시키지 않고 '선행 필요'로 남긴다.
  /// [R8-P7.4] 업무 상태를 못 읽은 사업장은 대상이 아니다 — 업무가 이미 있는
  ///   사업장으로 보내면 "등록하라는데 이미 있다"가 된다.
  BusinessModel? get _workTypeCtaBusiness =>
      _firstBusinessWhere((r) =>
          r != null && r.isApproved && r.hasLicense && r.isMissingWorkTypes) ??
      _firstBusinessWhere(
          (r) => r != null && r.isApproved && r.isMissingWorkTypes) ??
      _firstBusinessWhere((r) => r == null);

  /// 사업장 task CTA 대상 — 승인이나 등록증이 빠진 사업장.
  /// readinessMap은 승인 사업장만 담으므로 r == null은 미승인을 뜻한다.
  BusinessModel? get _businessCtaBusiness =>
      _firstBusinessWhere((r) => r == null || !r.isApproved || !r.hasLicense);

  /// 계약서 템플릿 CTA 대상. 템플릿은 관리자 전체 합산이라 사업장별 결핍이
  /// 없다 — 실제로 공고를 낼 사업장을 우선하고, 없으면 준비 중인 사업장.
  BusinessModel? get _templateCtaBusiness =>
      _firstBusinessWhere((r) => r != null && r.isReady) ??
      _firstBusinessWhere((r) => r != null && r.isApproved && r.hasLicense) ??
      _firstBusinessWhere((r) => r != null && r.isApproved) ??
      _firstBusinessWhere((r) => r == null);

  Future<void> _safeNavigate(Future<void> Function() action) async {
    if (_isNavigating) return;
    _isNavigating = true;
    try {
      await action();
    } catch (e) {
      debugPrint('❌ 탐색 오류: $e');
      if (mounted) ToastHelper.showError('처리 중 오류가 발생했어요');
    } finally {
      _isNavigating = false;
    }
  }

// [PHASE-2C] D0~D+7 인력 현황 로드
  // D0는 오늘 운영 Block에서 사용, D+1~D+7은 Phase 2D(Future Staffing Block)에서 재사용.
  // 실패 시 _staffingReadiness = null 유지 — false zero 방지 (ERROR≠ZERO)
  Future<void> _loadStaffingReadiness() async {
    if (!mounted) return;
    final seq = ++_staffingSeq;
    setState(() => _staffingLoading = true);
    try {
      final up = context.read<UserProvider>();
      final selectedBizId = up.currentUser?.isSubAdmin == true
          ? up.effectiveBusinessId
          : null;
      final result = await _reads.staffingReadiness(
        selectedBusinessId: selectedBizId,
      );
      if (!mounted || seq != _staffingSeq) return;
      setState(() {
        _staffingReadiness = result;
        _staffingLoading = false;
      });
    } catch (e) {
      debugPrint('❌ _loadStaffingReadiness 실패: $e');
      if (!mounted || seq != _staffingSeq) return;
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
    final seq = ++_attendanceSeq;
    // [SUBADMIN-SCOPE.40] 인력 권한이 확인된 경우에만 읽는다(소유자는 언제나 허용).
    //   거부·확인 실패면 묻지 않고 값을 비운다 — 숫자를 0으로 주장하지 않고
    //   (ERROR≠ZERO), 이전 사업장 값도 남기지 않는다. 화면은 이미 이 구역을
    //   그리지 않는다. 모름이면 확인될 때까지 기다린다(spinner 유지).
    final gate = _attendanceGate(context.read<UserProvider>());
    _attendanceGateRun = gate;
    if (gate != PermissionCheck.allowed) {
      setState(() {
        _todayCheckedIn      = null;
        _todayDueNow         = null;
        _todayNeedsAttention = null;
        _hasTodayRoster      = null;
        _todayFirstStart     = null;
        _todayWorkSummary    = null;
        _todayWorkTimeSummary = null;
        _attendanceLoading   = gate == PermissionCheck.unknown;
      });
      return;
    }
    setState(() => _attendanceLoading = true);
    try {
      // [AH-V2-01] 여기 도달했다는 것은 사업장 조회가 성공했다는 뜻이다.
      //   실패는 _getBusinesses()가 throw → 아래 catch에서 ERROR 상태로 간다.
      //   따라서 이 isEmpty는 "접근 가능한 사업장이 실제로 0개"만 의미한다
      //   (SubAdmin 권한 0개 포함) → 정상 0 표시.
      final businesses = await _getBusinesses();
      if (businesses.isEmpty) {
        if (mounted && seq == _attendanceSeq) {
          setState(() {
            _todayCheckedIn      = 0;
            _todayDueNow         = 0;
            _todayNeedsAttention = 0;
            _attendanceLoading   = false;
          });
        }
        return;
      }

      // [DU1 VQ] 주입 clock(LOCAL 렌더 전용) 우선, 없으면 실제 now — production 동작 동일
      final today    = FormatHelper.toKstDate((_reads.clock ?? DateTime.now)());
      final nowLocal = (_reads.clock ?? DateTime.now)(); // 한국 디바이스에서 local = KST

      // 병렬 로드 — 두 Future를 미리 생성해 동시에 실행
      final attFuture = Future.wait(
        businesses.map((b) => _reads.attendanceByDate(
          businessId: b.id, date: today)),
      );
      final rosterFuture = Future.wait(
        businesses.map((b) => _reads.confirmedWorkers(
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
      final timeMap = await _reads.workDetailTimes(allConfirmed);

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
      //   모수는 오늘 확정 로스터 — dialog와 동일하다. Set 의 원소는
      //   **applicationId** 라 근태 문서가 중복돼도 한 근무는 1로 센다.
      //   [R7-P1-4 H1] uid Set 이 아니므로 인원수 보장이 아니다 — 한 사람이
      //   같은 날 겹치지 않는 두 근무를 확정받으면 2 가 된다. 그래서 이 값의
      //   단위는 **건**이고 표시도 `근태 확인 N건` 이다.
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

      // [HOME-V2-08D.2] 이미 읽은 로스터에서 Hero·gate가 쓸 값만 뽑는다.
      //   추가 조회 없음 — 위 루프가 돌던 같은 allConfirmed/timeMap이다.
      String? firstStart;
      final bizNames = <String>{};
      final workTypes = <String>{};
      final ranges = <String>{};
      for (final app in allConfirmed) {
        final start = WorkDetailHelper.effectiveStart(app, timeMap);
        final end = WorkDetailHelper.effectiveEnd(app, timeMap);
        // "HH:mm"은 사전순 비교가 곧 시각 비교다
        if (start.isNotEmpty && (firstStart == null || start.compareTo(firstStart) < 0)) {
          firstStart = start;
        }
        if (app.businessName.isNotEmpty) bizNames.add(app.businessName);
        if (app.selectedWorkType.isNotEmpty) workTypes.add(app.selectedWorkType);
        if (start.isNotEmpty && end.isNotEmpty) ranges.add('$start–$end');
      }

      if (!mounted || seq != _attendanceSeq) return;
      setState(() {
        _todayCheckedIn      = checkedIn;
        _todayDueNow         = dueNow;
        _todayNeedsAttention = needsAttention;
        _hasTodayRoster      = allConfirmed.isNotEmpty;
        _todayFirstStart     = firstStart;
        _todayWorkSummary    = _summarizeWork(bizNames, workTypes, ranges);
        _todayWorkTimeSummary = _summarizeWork(const <String>{}, workTypes, ranges);
        _attendanceLoading   = false;
      });
    } catch (e) {
      debugPrint('❌ _loadTodayAttendance 실패: $e');
      if (!mounted || seq != _attendanceSeq) return;
      setState(() {
        _todayCheckedIn      = null; // 에러 상태 — 0 표시 금지 (ERROR≠ZERO)
        _todayDueNow         = null;
        _todayNeedsAttention = null;
        // [HOME-V2-08D.2] 파생 state도 함께 null — 실패를 '로스터 없음'으로
        //   커밋하면 Today section이 통째로 사라진다.
        _hasTodayRoster      = null;
        _todayFirstStart     = null;
        _todayWorkSummary    = null;
        _todayWorkTimeSummary = null;
        _attendanceLoading   = false;
      });
    }
  }

  /// [HOME-V2-08D.2] 사업장·업무·시간 요약 — 03R.1의 카드 요약과 같은 규칙.
  ///
  /// 하나로 확정되면 실제 값을, 여럿이면 개수를 말한다. 첫 값을 대표로 세우면
  /// 나머지가 없는 것처럼 보인다. 아무것도 모르면 null.
  static String? _summarizeWork(
      Set<String> bizNames, Set<String> workTypes, Set<String> ranges) {
    final parts = <String>[];
    if (bizNames.length == 1) {
      parts.add(bizNames.first);
    } else if (bizNames.length > 1) {
      parts.add('${bizNames.first} 외 ${bizNames.length - 1}곳');
    }
    if (workTypes.length == 1) {
      parts.add(workTypes.first);
    } else if (workTypes.length > 1) {
      parts.add('업무 ${workTypes.length}개');
    }
    if (ranges.length == 1) {
      parts.add(ranges.first);
    } else if (ranges.length > 1) {
      parts.add('시간대 ${ranges.length}개');
    }
    return parts.isEmpty ? null : parts.join(' · ');
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
    final businesses = await _reads.businessesByIds(ids);
    _businesses = businesses; // 캐시만 갱신 — UI에 직접 영향 없으므로 setState 불필요
    return businesses;
  }

  /// [BUSINESS-ARCHIVE] 관리 사업장이 모두 운영 종료·중지 상태인가.
  ///   `isApproved:false` 만 보면 승인 대기와 구별되지 않는다.
  bool get _allBusinessesClosed =>
      _businesses.isNotEmpty && _businesses.every((b) => b.isDeactivated);

  /// [BUSINESS-ARCHIVE] 종료 뒤에도 남는 일 — 지나간 근무의 기록·급여 처리 위치.
  static const String _closedBusinessGuide =
      '새 공고와 모집은 할 수 없어요. 지난 근무의 급여·정산은 급여 탭에서, '
      '계약은 관리 탭의 계약 관리에서 계속 처리할 수 있어요';

  /// STATE P/A/B/C 체크 — 모든 기능 진입 전 공통 게이트
  Future<void> _requireApprovedBusiness(
      BuildContext context, Future<void> Function() proceed) async {
    final up = context.read<UserProvider>();
    // STATE P: 계정 확인 대기 (외국인)
    if (up.currentUser?.accountStatus == 'pending') {
      ToastHelper.showWarning('계정 확인이 완료되면 이용할 수 있어요');
      return;
    }
    // 사업장 정보 로딩 중
    if (_hasApprovedBusiness == null) {
      ToastHelper.showWarning('사업장 정보를 불러오고 있어요. 잠시 후 다시 시도해 주세요');
      return;
    }
    // STATE A: 사업장 없음
    if (_businesses.isEmpty) {
      // SUB_ADMIN은 사업장을 직접 등록하지 않음 — 배정 정보 확인 안내
      ToastHelper.showWarning(
        up.currentUser?.isSubAdmin == true
            ? '사업장 정보를 확인할 수 없어요. 사업장 관리자에게 문의해 주세요'
            : '먼저 사업장을 등록해 주세요',
      );
      return;
    }
    // [BUSINESS-ARCHIVE] STATE D: 모든 사업장이 운영 종료·중지 — 승인 대기가 아니다.
    if (!_hasApprovedBusiness! && _allBusinessesClosed) {
      ToastHelper.showWarning(_closedBusinessGuide);
      return;
    }
    // STATE B: 사업장 승인 대기
    if (!_hasApprovedBusiness!) {
      ToastHelper.showWarning('사업장이 승인되면 이용할 수 있어요');
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
          subtitle: '신분증 확인이 완료되면 이용할 수 있어요',
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

    // [BUSINESS-ARCHIVE] STATE D: 모든 사업장이 운영 종료·중지
    if (!_hasApprovedBusiness! && _allBusinessesClosed) {
      return _stateBannerCard(context, s,
          icon: Icons.storefront_outlined,
          iconColor: AppColors.grey600,
          title: _businesses.every((b) => b.isClosedByOwner)
              ? '운영을 종료한 사업장이에요'
              : '운영이 중지된 사업장이에요',
          subtitle: _closedBusinessGuide,
          bgColor: AppColors.grey100,
          borderColor: AppColors.grey300);
    }

    // STATE B: 사업장 승인 대기
    if (!_hasApprovedBusiness!) {
      return _stateBannerCard(context, s,
          icon: Icons.hourglass_top,
          iconColor: theme.primaryColor,
          title: '사업장 승인 대기',
          subtitle: '운영팀이 사업장을 검토하고 있어요. 승인되면 이용할 수 있어요',
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
                  Text('사업장 등록',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('사업장을 등록하면 공고·계약·급여 관리를 시작할 수 있어요',
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
                label: Text('사업장 등록',
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
    if (!_verified(up, (p) => p.canManageWage)) {
      ToastHelper.showWarning('급여 관리 권한이 없어요');
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
  /// [R7-P1-4 H3] 레이아웃 배율 — 공용 owner 에 위임한다.
  ///
  ///   이 화면에는 사설 사본이 있었다(`0.82/0.92/1.0/1.08`). 책임은
  ///   `ResponsiveHelper.getScale` 과 **같다** — 둘 다 화면 폭으로 정하는
  ///   **레이아웃 치수 전용** 배율이고, 폰트는 [TYPO-01] 에 따라 어느 쪽도
  ///   건드리지 않는다(글자 크기는 base × OS TextScaler 뿐이다).
  ///   같은 책임이 두 벌 있으면 한쪽만 조정돼 화면마다 간격 체계가 갈린다.
  ///
  ///   위임으로 값이 바뀌는 구간: `<360` 0.82→0.85, `<400` 0.92→0.90,
  ///   `>=480` 1.08→1.0(태블릿 여백 확대 없어짐). 정보가 숨거나 줄지 않는다 —
  ///   320·360·390·480·600dp 렌더로 확인했다(`admin_home_content_render_test`).
  ///
  ///   남은 사설 사본 3벌(`user_home_screen`·`income_detail_screen`·
  ///   `wage_detail_screen`)은 같은 곡선이지만 **이 Phase 소유가 아니다.**
  double _s(BuildContext context) => ResponsiveHelper.getScale(context);

  @override
  Widget build(BuildContext context) {
    final s = _s(context);
    return Selector<UserProvider, _AdminHomeData>(
      selector: (_, p) => (
        userName: p.currentUser?.name ?? '관리자',
        // 권한이 바뀌면 값이 바뀌고, 값이 바뀌면 Home이 다시 그려진다.
        canManageTo: p.can((x) => x.canManageTo),
        canManageWorkers: p.can((x) => x.canManageWorkers),
        canManageContract: p.can((x) => x.canManageContract),
        canManageWage: p.can((x) => x.canManageWage),
        // [CROSS-DOMAIN-R5.1F.1] Hero는 선택 사업장이 아니라 배정 전체의
        //   scope를 본다 — 그 판정에 쓰는 값도 같이 구독해야 한다.
        subAdminPermissionsLoaded: p.subAdminPermissionsLoaded,
        canManageToAnywhere:
            p.canForAnyBusiness((x) => x.canManageTo, whenUnknown: true),
        // [CROSS-DOMAIN-R5.1F.5] 권한 bool은 그대로인데 전송 상태만 바뀌는
        //   전이가 있다(verified → error). bool만 구독하면 true→true라
        //   다시 그리지 않아, 검증되지 않은 값으로 Task와 CTA가 남는다.
        permissionHealth: p.currentBusinessPermissionHealth,
      ),
      builder: (context, data, _) {
        final theme = Theme.of(context);
        final up = context.read<UserProvider>();
        return Scaffold(
          // [CP04] 정밀 §6 — 두 홈 배경은 white 로 정돈(전역 Scaffold 기본값은 그대로). 최상위 그룹은 raised 한 겹.
          backgroundColor: AppColors.surface,
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
                    // [CP04] 정밀 §9 — 머리/사업장 scope → 큰 운영 머리·KST 날짜·(허용 시) 등록 → 법적·준비 상태 → Hero → 섹션.
                    _buildOpsHead(context, up),
                    const SizedBox(height: 16),
                    _buildStateBanner(context, s, theme, up),
                    // [R7-LEGAL.1B.1] 약관 재동의 할 일.
                    //   약관 동의는 **개인 계정의 법적 상태**다 — 사업장
                    //   소유 설정(등록증·인감)과 성격이 다르므로 하위관리자
                    //   에게도 그대로 보인다. 해당 없으면 스스로 사라진다.
                    // [CP04] 법적·준비 상태는 Hero(운영 상태) 앞에 둔다(정밀 §9 순서).
                    LegalTaskCard(scale: s, loadReadiness: _reads.legalReadiness),
                    // [HOME-V2-08D.2] Adaptive Hero — 지금 가장 먼저 알아야
                    //   하는 상태 하나를 해석한다. 준비 미완료 카드도 여기로
                    //   들어왔다(state = setup).
                    _buildAdaptiveHero(context, s, theme, up),
                    // [AH-V2-05B] TODAY → TASK → NEXT.
                    //   오늘 상황을 본 다음 바로 지금 처리할 일이 오고,
                    //   다음 운영 준비(향후 인력 부족)가 마지막이다.
                    //   처리할 일이 0건이어도 이 순서는 고정한다 — Home 위치가
                    //   매번 달라지면 관리자가 화면을 학습할 수 없다.
                    //
                    // [HOME-V2-08D.2] 각 섹션은 자기 truth로 렌더 여부를
                    //   정한다. "없다"는 말은 Hero가 한 번만 하고, 섹션은
                    //   보여줄 것이 있을 때만 나온다. 순서는 그대로다.
                    ..._buildSections(context, s, theme, up),
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
      // [HOME-V2-08D.1] page header bar — grouped surface가 아니므로
      //   border/radius 없이 surface 토큰만 쓴다.
      color: AppColors.surface,
      // [CP04] 왼쪽 여백은 큰 운영 머리·섹션과 같은 gutter(<360 16, 그 외 20) — 같은 세로선에 맞춘다.
      // [DU307 Standards §12.1] 아래 0. 마지막 머리 묶음(사업장 줄·권한 요약, SubAdmin 이면 뒤 역할 전환까지) → 큰 운영 머리 합계 8 은
      //   _buildOpsHead 의 위 여백 [_kHeadToHero] 하나가 맡는다(이전 아래 12*s + 16 = W 약 26.8 / B 26.2).
      //   [DU307 L2] 위 8 → 0(배율 s 를 곱하지 않는다 — 지원자 홈과 같은 값). 로고 잉크 top = 머리 시작 + (행 높이 − 28)/2 + 2 —
      //   배너 숨김·행 48 이면 SafeArea top + 12.
      padding: EdgeInsets.fromLTRB(_gutter(context), 0, 16 * s, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단: 로고 + 알림/프로필 버튼
          // [DU1 후속37 §2 S010] 브랜드 표시를 지원자 홈과 같은 한 벌로 — 지원자는 그라데이션 원(32)+전경 아이콘·브랜드색 20/w900,
          //   관리자는 다른 asset(24, 배경 없음)·본문색 17/w800 이라 같은 앱의 두 홈이 다른 로고로 읽혔다.
          //   역할 구별은 아래 '관리자'/SubAdmin 배지와 사업장 줄이 맡는다(이름·배지·사업장 범위는 그대로).
          // [CP01] 로고 = 공용 글자 로고(고정 그림, 정본 DU_concept_precise_spec_audit §3) — 지원자 홈과 같은 한 벌.
          //   원형 앱 아이콘 장식·예전 파랑(infoDark) 글자를 대체한다.
          Row(children: [
            const AlfitWordmark(),
            const Spacer(),
            // [DU307 L2] 머리 위 여백 0 → 배지 위 끝도 버튼 위(0)에 둔다(기본 −4 는 SafeArea 위로 4 돌출). 지원자 홈과 같다.
            NotificationBadge(
              badgeTop: 0,
              child: _headerBtn(context, s, Icons.notifications_outlined,
                  label: '알림',
                  onTap: () => _safeNavigate(() async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const NotificationScreen()));
                  })),
            ),
            SizedBox(width: 6 * s),
            // [P4.2C-NAV-01] 이 버튼은 `const SettingsScreen()` 을 열었다.
            //   하단 '관리' 탭의 root 도 **같은 위젯, 같은 파라미터**다.
            //   그래서 누르면 제목은 '관리' 인데 하단에서 빛나는 탭은 '홈'
            //   이었다 — 같은 목적지인데 내가 어느 영역에 있는지를 shell 이
            //   다르게 말한 것이다.
            //
            //   목적지를 바꾸지 않고(같은 화면이다) **가는 방법만** 바꾼다.
            //   push 대신 그 탭으로 전환하면 제목과 하단 탭이 같은 말을 한다.
            //
            //   아이콘도 목적지를 따라간다. person_outline 은 이 제품에서
            //   '프로필 관리'(지원자 MY 탭 → ProfileEditScreen)를 뜻하는데
            //   여기서는 프로필이 아니라 관리 영역 전체로 갔다.
            //
            //   [P2-01] 의 readiness 재계산은 사라지지 않았다 — 복귀 시점에
            //   묶여 있던 것을 `_onHomeReactivated` 로 옮겼다. 그래야 하단
            //   '관리' 탭으로 들어간 경우까지 같이 갱신된다(예전에는 이 버튼
            //   으로 들어간 경우에만 갱신됐다).
            _headerBtn(context, s, Icons.settings_outlined,
                label: '관리',
                onTap: () => AdminTabSwitcher.instance
                    .switchToTab(AdminTabSwitcher.settingsTab)),
          ]),
          // [DU307 §12.1] 행동행(로고·알림·관리 48) 아래 → 계정 메타(이름·역할) 위 8 — 지원자 홈과 같은 관계(이전 10*s).
          const SizedBox(height: 8),
          // [HOME-V2-08D.1] 이름 + 배지 + [PH1] 사업장/권한 컨텍스트
          //
          // `안녕하세요,`를 빼고 이름을 22px bold → 15px w700로 내렸다.
          // Header는 이 화면에서 **정체성**을 말하는 자리이지 주인공이 아니다.
          // 22px는 화면 전체 최대 텍스트라, 앞으로 들어올 Adaptive Hero(17px)가
          // 그보다 작아져 위계가 뒤집히는 구조였다. greeting 줄과 그 아래
          // 2px spacer도 함께 걷어내 header 높이가 실제로 줄어든다.
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // [CP01] 이름과 역할 배지가 한 줄에 다 들어가지 않으면(긴 이름·긴 사업장·큰 글자) 배지를 다음 줄로 내린다.
            //   예전 Row+Flexible 은 배지 폭만큼 이름을 한 줄 말줄임으로 잘랐다. 이름은 말줄임 없이 전문·자연 높이(글자 크기 그대로).
            // [DU307 §12.1] 메타 내부 4 — 이름↔역할 배지가 다음 줄로 내려갈 때의 줄 간격(이전 4*s).
            Wrap(
              spacing: 8 * s,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // [CP04 · CP01 인계] 표시만 낱말 묶음 — 긴 이름의 마지막 낱말과 `님`이 갈리지 않게(의미 이름 원문).
                Text(TextLayout.keepWords('$name님'),
                    semanticsLabel: '$name님',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2)),
                isSub ? _subAdminBadge(context, s, up, theme) : _adminBadge(s, theme),
              ],
            ),
            // [PH1] Owner: 사업장 컨텍스트 (단일 이름 or "N개 사업장 관리")
            if (!isSub && _businesses.isNotEmpty) ...[
              const SizedBox(height: 4), // [DU307 §12.1] 메타 내부 4(이전 4*s)
              // [ADMIN-HOME.31] 392·2.0 에서 긴 사업장명이 한 줄 말줄임으로 사라졌다('…두 번째 물…').
              //   이 줄이 '어느 사업장의 홈인가'를 말한다 — 낱말 단위로 두 줄까지 보이고, 그래도 넘치면
              //   말줄임(세 줄 이상 늘려 header 가 화면을 밀지 않게). 원문은 접근성 이름.
              // [CP04] 중요한 범위 정보는 말줄임 없이 전문·자연 높이(정밀 §8 B 규칙 1). 낱말 단위로만 줄바꿈(identity 의
              //   긴 낱말 중간 분할을 쓰지 않는다). 메타 14/400.
              Text(
                _businesses.length == 1
                    ? TextLayout.keepWords(_businesses.first.name)
                    : '${_businesses.length}개 사업장 관리',
                semanticsLabel: _businesses.length == 1 ? _businesses.first.name : null,
                style: ConceptText.meta(),
              ),
            ],
            // [PH1] SubAdmin: 권한 요약 compact 1줄
            if (isSub && up.permissionsLoaded) ...[
              const SizedBox(height: 4), // [DU307 §12.1] 메타 내부 4(이전 4*s)
              _buildPermissionSummaryLine(s, up),
            ],
          ]),
          // SubAdmin 전용: 모드 토글 (반응형 라우팅 기반)
          // [DU307 §12.1] 메타 → 뒤 역할 전환 사이(10*s)·토글 자체 높이·내부 간격·48 receiver 는 그대로 —
          //   토글을 가로질러 8 을 강요하지 않는다. 토글 아래 → 큰 머리 합계 8 은 _kHeadToHero 가 맡는다.
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

  /// [CP04] 큰 운영 머리(정밀 §8·§9) — 헤더 →16→ `오늘 운영을 한눈에` 24/700 →4→ KST 오늘 날짜 14/400 + (허용 시) `+ 공고 등록`.
  ///   등록은 기존 `_canCreatePosting`·`_openCreatePosting`(승인 게이트·root 생성 경로·복귀 갱신) 그대로, 의미 이름 `공고 등록`,
  ///   receiver ≥48. 날짜와 한 줄에 들어가지 않으면 등록을 날짜 아래 오른쪽 줄로 내린다(말줄임·축소 없음).
  ///   날짜는 홈의 같은 시각 기준(주입 clock, 없으면 실제 now — production 동작 그대로).
  /// [DU307 Standards §12.1] 마지막 머리 묶음 아래 → 큰 운영 머리 위 = 합계 8(머리 아래 여백 0 + 이 값).
  ///   지원자 홈이 같이 쓰던 ConceptSpace.headerToHero(16)는 바꾸지 않는다(다른 소비처 보존).
  static const double _kHeadToHero = 8;

  Widget _buildOpsHead(BuildContext context, UserProvider up) {
    final g = _gutter(context);
    final today = FormatHelper.toKstDate((_reads.clock ?? DateTime.now)());
    const wd = ['월', '화', '수', '목', '금', '토', '일'];
    final dateText = '${today.month}월 ${today.day}일 ${wd[today.weekday - 1]}요일';
    const title = '오늘 운영을 한눈에';
    final actionStyle = ConceptText.count().copyWith(height: 1.3);
    final actionDisplay = '+${String.fromCharCode(0xA0)}${TextLayout.keepWords('공고 등록')}';
    Widget? action;
    if (_canCreatePosting(up)) {
      void open() => _openCreatePosting(context);
      action = Semantics(
        container: true,
        button: true,
        label: '공고 등록',
        excludeSemantics: true,
        onTap: open,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: open,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: ConceptSpace.minTouch, minHeight: ConceptSpace.minTouch),
            child: Align(
              alignment: Alignment.topRight,
              widthFactor: 1,
              heightFactor: 1,
              child: Text(actionDisplay, semanticsLabel: '공고 등록', style: actionStyle),
            ),
          ),
        ),
      );
    }
    final date = Text(dateText, style: ConceptText.meta());
    final act = action;
    return Padding(
      padding: EdgeInsets.fromLTRB(g, _kHeadToHero, g, 0), // [DU307 §12.1] 머리 →8→ 큰 운영 머리
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(TextLayout.keepWords(title), semanticsLabel: title, style: ConceptText.hero()),
        const SizedBox(height: ConceptSpace.heroToDate),
        if (act == null)
          Align(alignment: Alignment.centerLeft, child: date)
        else
          LayoutBuilder(builder: (context, c) {
            final need = _oneLineWidth(context, dateText, ConceptText.meta()) + 8 +
                _oneLineWidth(context, actionDisplay, actionStyle);
            if (need <= c.maxWidth) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: date), const SizedBox(width: 8), act]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Align(alignment: Alignment.centerLeft, child: date),
              Align(alignment: Alignment.centerRight, child: act),
            ]);
          }),
      ]),
    );
  }

  // ── [HOME-V2-08D.2] Hero 렌더 ──────────────────────────────────────

  /// Hero 공통 껍데기. 섹션 카드와 같은 surface를 쓴다 — 08D.1의 `_groupSurface`.
  Widget _heroShell(
    double s, {
    required IconData icon,
    required Color color,
    required String message,
    String? supporting,
    String? ctaLabel,
    VoidCallback? onCta,
    Widget? body,
  }) {
    // [CP04] Hero 표면은 기존 평면(_groupSurface) 그대로 — conceptRaised 는 오늘/할 일/다가오는 최상위 그룹만(정밀 §6).
    //   좌우 여백만 홈 gutter 로, 보조 문구 14/400(정밀 §8 메타), CTA 는 receiver ≥48·의미 이름(보이는 `+` 제외).
    final cta = ctaLabel != null && ctaLabel.startsWith('+ ') ? ctaLabel.substring(2) : ctaLabel;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _gutter(context)),
      child: Container(
        decoration: _groupSurface,
        padding: EdgeInsets.fromLTRB(16 * s, 14 * s, 16 * s, 14 * s),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 상태색이 칠해지는 유일한 면적 — 나머지는 중립이다.
            Container(
              width: 22 * s,
              height: 22 * s,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 14 * s, color: color),
            ),
            SizedBox(width: 10 * s),
            Expanded(
              // [ADMIN-HOME.31] Hero 문장도 낱말 단위 — 큰 글자에서 '필요|해요' 식 끊김 방지(표시만).
              child: Text(
                TextLayout.keepWords(message),
                semanticsLabel: message,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  height: 1.35,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ]),
          if (supporting != null) ...[
            SizedBox(height: 6 * s),
            Padding(
              padding: EdgeInsets.only(left: 32 * s),
              // [ADMIN-HOME.31] '사업장 · 업무 · 시각' — 큰 글자에서 낱말 안이 끊기지 않게(표시만, 원문은 접근성 이름).
              child: Text(TextLayout.phrases(supporting),
                  semanticsLabel: supporting,
                  style: ConceptText.meta()),
            ),
          ],
          if (body != null) ...[
            SizedBox(height: 12 * s),
            body,
          ],
          // CTA는 lifecycle/error 상태에만 온다. 운영 상태에서 행동 경로는
          //   이미 아래 섹션에 있으므로 Hero가 그것을 가리키지 않는다.
          if (ctaLabel != null && onCta != null) ...[
            SizedBox(height: 4 * s),
            Padding(
              padding: EdgeInsets.only(left: 32 * s),
              child: Semantics(
                container: true,
                button: true,
                label: cta,
                excludeSemantics: true,
                onTap: onCta,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onCta,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: ConceptSpace.minTouch, minHeight: ConceptSpace.minTouch),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text(TextLayout.keepWords(ctaLabel),
                            semanticsLabel: cta, style: ConceptText.count().copyWith(height: 1.3)),
                      ),
                      const Icon(Icons.chevron_right, size: 18, color: AppColors.brand),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  /// 로딩 — 같은 껍데기에 정적 회색 바. shimmer는 쓰지 않는다.
  Widget _heroSkeleton(double s) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: AppColors.grey100,
            borderRadius: BorderRadius.circular(4),
          ),
        );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _gutter(context)),
      child: Container(
        decoration: _groupSurface,
        padding: EdgeInsets.fromLTRB(16 * s, 14 * s, 16 * s, 14 * s),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 22 * s,
              height: 22 * s,
              decoration: const BoxDecoration(
                  color: AppColors.grey100, shape: BoxShape.circle),
            ),
            SizedBox(width: 10 * s),
            Expanded(child: bar(double.infinity, 17 * s)),
          ]),
          SizedBox(height: 10 * s),
          Padding(
            padding: EdgeInsets.only(left: 32 * s),
            child: bar(160 * s, 13 * s),
          ),
        ]),
      ),
    );
  }

  /// [DU-VQ-03] 오늘 그룹에 '오늘 N명 부족' 행이 **실제로 그려지는가** — `_buildTodayIssueRows` 부족 행과 같은 조건.
  bool _todayShortageRowShown(UserProvider up) {
    if (!_showTodaySection || _staffingLoading) return false;
    final canSeeStaffing = _verified(up, (p) => p.canManageTo) || _verified(up, (p) => p.canManageWorkers);
    if (!canSeeStaffing) return false;
    final day = _todayStaffingDay;
    return day != null && day.shortageCount > 0;
  }

  /// [DU-VQ-03] 이번 build 에서 shortage Hero 를 오늘 부족 행으로 합쳤는가 — _buildAdaptiveHero 가 정하고
  ///   바로 뒤 간격(같은 children 목록의 다음 원소)이 읽는다. 상태 derive 를 한 번 더 하지 않기 위해서다.
  bool _heroMergedIntoRow = false;

  Widget _buildAdaptiveHero(
      BuildContext context, double s, ThemeData theme, UserProvider up) {
    final state = _heroStateOf(up);
    // [DU-VQ-03] 같은 날·같은 범위의 부족 행이 보이면 상단 Hero 가 같은 숫자를 반복하지 않는다(행이 정보·행동 위치).
    _heroMergedIntoRow = state == _HeroState.shortage && _todayShortageRowShown(up);
    switch (state) {
      case _HeroState.loading:
        return _heroSkeleton(s);

      case _HeroState.error:
        // [DU307 §12.2·정밀 §4] 완전 조회 실패 = 실제 오류 안내 errorDark(작은 아이콘 원만 칠한다, 문장은 중립 그대로).
        //   같은 실패를 아래 오늘 운영 행(`인력 정보를 불러오지 못했어요`, errorDark)이 동시에 말할 때
        //   Hero 아이콘만 호박색이라 한 사실이 두 색으로 보였다. 부분(partialInfo)은 아래처럼 warningDark 를 유지한다.
        return _heroShell(s,
            icon: Icons.cloud_off_outlined,
            color: AppColors.errorDark,
            message: '오늘 상황을 확인하지 못했어요',
            supporting: '인력 정보를 불러오지 못했어요',
            ctaLabel: '다시 시도',
            onCta: () => unawaited(_loadStaffingReadiness()));

      case _HeroState.partialInfo:
        return _heroShell(s,
            icon: Icons.cloud_off_outlined,
            color: AppColors.warningDark,
            message: '오늘 상황을 일부만 확인했어요',
            supporting: '일부 사업장 정보를 불러오지 못했어요',
            ctaLabel: '다시 시도',
            onCta: () => unawaited(_loadStaffingReadiness()));

      case _HeroState.setup:
        return _buildPostingSetupCard(context, s, theme);

      case _HeroState.noPosting:
        return _heroShell(s,
            icon: Icons.post_add_outlined,
            color: AppColors.grey600,
            message: '등록된 공고가 없어요',
            supporting: '사람이 필요한 날짜와 업무를 등록해 주세요',
            // [§31] 권한이 없으면 CTA를 숨긴다 — disabled teaser를 만들지 않는다.
            ctaLabel: _canCreatePosting(up) ? '+ 공고 등록' : null,
            onCta: _canCreatePosting(up) ? () => _openCreatePosting(context) : null);

      case _HeroState.noPostingScope:
        // [CROSS-DOMAIN-R5.1F.1] 권한 부재를 사업 상태로 번역하지 않는다.
        //   CTA 없음 — 이 사용자가 여기서 할 수 있는 일이 없다.
        return _heroShell(s,
            icon: Icons.lock_outline,
            color: AppColors.grey600,
            message: '공고 정보를 볼 수 있는 권한이 없어요',
            supporting: '공고를 관리할 수 있는 사업장이 배정되어 있지 않아요.\n'
                '필요하면 사업장 관리자에게 권한을 요청해 주세요');

      case _HeroState.draftOnly:
        return _heroShell(s,
            icon: Icons.edit_note,
            color: AppColors.grey700,
            message: '작성 중인 공고가 있어요',
            supporting: '공개하면 지원자가 지원할 수 있어요',
            ctaLabel: _canCreatePosting(up) ? '작성 계속하기' : null,
            onCta: _canCreatePosting(up) ? () => _openDraftPostings(context) : null);

      case _HeroState.shortage:
        if (_heroMergedIntoRow) return const SizedBox.shrink();
        final n = _todayStaffingDay?.shortageCount ?? 0;
        // [CP04 §4] 부족은 빨강 경고가 아니라 연주황 의미색(#8A4B00) — 같은 서버 shortage, 같은 문구.
        return _heroShell(s,
            icon: Icons.warning_amber_rounded,
            color: AppColors.conceptStaffingNeedText,
            message: '$n명 추가 필요',
            supporting: _todayWorkSummary);

      case _HeroState.attention:
        final n = _todayNeedsAttention ?? 0;
        return _heroShell(s,
            icon: Icons.pending_actions_outlined,
            color: AppColors.warningDark,
            message: '오늘 확인할 근태가 $n건 있어요',
            supporting: '미출근·지각·미퇴근 등 확인이 필요한 근무자가 있어요');

      case _HeroState.noToday:
        // [CP04] 문구 생성 단계만 나눈다(상태 선택·순서·로더·권한식 불변). 부재 단정은 근태 권한이 허용이고
        //   오늘 로스터가 성공적으로 비어 있을 때(`_hasTodayRoster == false`)만. null 은 확인하지 못한 것이다.
        final gate = _attendanceGate(up);
        final absent = gate == PermissionCheck.allowed && _hasTodayRoster == false;
        final message = switch (gate) {
          PermissionCheck.allowed => _hasTodayRoster == false ? '오늘 예정된 근무는 없어요' : '오늘 근무 정보를 확인하지 못했어요',
          PermissionCheck.denied => '근태 조회 권한이 없어요',
          PermissionCheck.error => '근태 조회 권한을 확인하지 못했어요',
          PermissionCheck.unknown => '근태 조회 권한을 확인하고 있어요',
        };
        // D+1…D+7 shortage 0 은 `추가 필요 인원 없음`까지만 말한다(전원확정 판정과 다름).
        final allStaffedNext = absent && _upcomingAllStaffed;
        return _heroShell(s,
            icon: Icons.event_available_outlined,
            color: allStaffedNext
                ? AppColors.successDeep
                : AppColors.grey600,
            message: allStaffedNext
                ? '$message\n앞으로 7일은 추가 필요 인원이 없어요'
                : message,
            supporting: allStaffedNext ? null : _nextWorkdaySupporting());

      case _HeroState.beforeStart:
        final t = _todayFirstStart;
        return _heroShell(s,
            icon: Icons.schedule,
            color: AppColors.scheduledDark,
            message: t == null
                ? '오늘 근무가 예정되어 있어요'
                : '오늘 첫 근무는 $t에 시작해요',
            supporting: _todayWorkSummary);

      case _HeroState.normalToday:
        // 출근 정보를 모르면 '문제없이 진행 중'이라고 단정하지 않는다.
        final attendanceKnown = _todayCheckedIn != null;
        return _heroShell(s,
            icon: Icons.check_circle_outline,
            color: AppColors.successDeep,
            message: attendanceKnown
                ? '오늘 근무 현황이에요'
                : '오늘 근무가 예정되어 있어요',
            supporting: _todayWorkSummary);
    }
  }

  /// D+1~D+7에 대상이 있고 부족이 하나도 없는가.
  bool get _upcomingAllStaffed {
    final sr = _staffingReadiness;
    if (sr == null || !sr.hasUsableData || !sr.hasFutureTarget) return false;
    return sr.days.skip(1).every((d) => d.shortageCount == 0);
  }

  /// 다음 근무일 안내 — `days[1..7]`로 알 수 있는 범위만 말한다.
  String? _nextWorkdaySupporting() {
    final sr = _staffingReadiness;
    if (sr == null || !sr.hasUsableData) return null;
    for (final d in sr.days.skip(1)) {
      if (d.requiredCount <= 0) continue;
      final label = _futureDateLabel(d.date);
      final staffing = '${d.requiredCount}명 중 ${d.confirmedCount}명 확정';
      // [CP04] 날짜 전체 합계(R/C)에 첫 사업장명을 붙이지 않는다 — 사업장명은 그 날짜의 상세가 1곳일 때만.
      //   여러 곳이면 `사업장 N곳 합계`(N = 그 날짜 byBusiness 수), 상세가 비면 사업장명 없는 기존 분기.
      if (d.byBusiness.length > 1) {
        return '다음 근무는 $label이에요\n사업장 ${d.byBusiness.length}곳 합계 · $staffing';
      }
      final biz = d.byBusiness.length == 1 ? d.byBusiness.first.businessName : null;
      return biz == null
          ? '다음 근무는 $label이에요\n$staffing'
          : '다음 근무는 $label이에요\n$biz · $staffing';
    }
    // [§15] D+8 이후에만 근무가 있을 수 있다 — 아는 범위까지만 말한다.
    return '앞으로 7일 안에 예정된 근무가 없어요';
  }

  /// 공고 생성/편집 권한 — 기존 permission 계약 그대로.
  /// (서버 게이트 callableCreateTO canManageTo 검증과 같은 기준)
  /// [CROSS-DOMAIN-R5.1F.5] 선택 사업장 권한 — **확인된 허용**에서만 true.
  ///
  /// 예전에는 `!isSub || up.can(...)` 이었다. bool 하나라서 구독이 죽어
  /// 마지막 값만 남은 상태와 방금 확인한 허용이 구분되지 않았고, 그 값으로
  /// Task와 CTA가 계속 열려 있었다. 이제 네 상태 중 allowed만 통과시킨다 —
  /// error/unknown은 fail-closed다(값을 지우는 것이 아니라 쓰지 않는 것이다).
  /// 소유자는 `checkCurrentBusiness`가 먼저 allowed로 돌려주므로 영향이 없다.
  bool _verified(UserProvider up, bool Function(MemberPermissions p) check) =>
      up.checkCurrentBusiness(check) == PermissionCheck.allowed;

  bool _canCreatePosting(UserProvider up) =>
      up.currentUser?.isSubAdmin != true || _verified(up, (p) => p.canManageTo);

  /// [HOME-V2-08D.2] 공고 등록 — Jobs 탭의 생성 버튼과 같은 경로다.
  void _openCreatePosting(BuildContext context) {
    unawaited(_safeNavigate(() => _requireApprovedBusiness(context, () async {
          if (!mounted) return;
          final up = context.read<UserProvider>();
          final initBizId = up.isSubAdmin ? up.effectiveBusinessId : null;
          await NavigationHelper.push<bool>(
            context,
            destination: AdminCreateTOScreen(initialBusinessId: initBizId),
            useRootNavigator: true,
            onChanged: () {
              if (!mounted) return;
              // 새 공고는 Home의 lifecycle signal과 인력 현황을 모두 바꾼다.
              unawaited(_loadStaffingReadiness());
              unawaited(_reloadReadiness());
              WorkforceController.notifyDataChanged(
                origin: AdminMutationOrigin.home,
              );
            },
          );
        })));
  }

  /// [HOME-V2-08D.2] 작성 중인 공고 보기 — 공고 탭으로 전환한다.
  ///
  /// 미공개 공고는 공고 목록 안에서 하단으로 정렬되고(03Q.1) outline 배지로
  /// 구분된다(03S.1). 탭 전환은 canonical `AdminTabSwitcher`를 쓴다 —
  /// 목록의 publish 필터를 외부에서 미리 선택하는 API는 아직 없다.
  void _openDraftPostings(BuildContext context) {
    unawaited(_safeNavigate(() => _requireApprovedBusiness(context, () async {
          AdminTabSwitcher.instance.switchToTab(AdminTabSwitcher.jobsTab);
        })));
  }

  /// [PH1] SUB_ADMIN 권한 요약 한 줄 (compact)
  ///
  /// [CROSS-DOMAIN-R5.1F.5] 여기만 bool `can()`을 그대로 쓴다 — 행동 경로가
  /// 아니라 "무슨 권한을 받았는지" 알려주는 줄이기 때문이다. 전송 상태가
  /// 나빠졌다고 받은 권한이 없어진 것은 아니므로, 목록을 지우면 오히려
  /// ERROR를 DENIED로 말하는 셈이 된다. 누를 수 있는 것은 전부 _verified로
  /// 판정한다.
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

  // ══════════════════════════════════════════════════════════════════
  // [HOME-V2-08D.2] Adaptive Hero
  //
  // Hero는 **지금 가장 먼저 알아야 하는 한 가지 상태**를 해석한다.
  // 운영 action list가 아니다 — 행동은 각 섹션이 맡는다.
  //
  // 상태는 여기 한 곳에서만 derive한다. 렌더 곳곳에서 같은 조건을 다시
  // 계산하면 Hero와 섹션이 서로 다른 판단을 하게 된다.
  // ══════════════════════════════════════════════════════════════════

  /// Hero가 선택할 수 있는 상태. 위에서 처음 참인 것 하나만 쓴다.
  _HeroState _heroStateOf(UserProvider up) {
    final sr = _staffingReadiness;
    final isSub = up.currentUser?.isSubAdmin == true;

    // 로딩 — 판단에 필요한 데이터가 아직 없다. empty를 섣불리 말하지 않는다.
    if (_staffingLoading || _attendanceLoading || !_readinessLoaded) {
      return _HeroState.loading;
    }

    // 0. 전체 조회 실패 — 아무것도 모른다. ERROR ≠ ZERO.
    if (sr == null || !sr.hasUsableData) return _HeroState.error;

    // 1. 준비 미완료. readiness는 staffing과 다른 데이터라 partial과 무관하다.
    //    SubAdmin은 사업장 소유 설정을 할 수 없어 이 분기를 타지 않는다(기존 정책).
    final r = _firstPosting;
    if (!isSub && r != null && !r.allReady) return _HeroState.setup;

    // 2-0. [CROSS-DOMAIN-R5.1F.1] authorized scope 판정이 emptiness보다 먼저다.
    //    publishedPostingCount는 "authorized scope 합"이므로, 공고를 볼 수 있는
    //    사업장이 하나도 없으면 그 0은 언제나 0이다. 그걸 `공고 없음`이라고
    //    말하면 권한 부재를 사업 상태로 바꿔 말하는 것이다.
    //    하이드레이션 전에는 아무 주장도 하지 않는다(UNKNOWN ≠ EMPTY).
    if (isSub) {
      if (!up.subAdminPermissionsLoaded) return _HeroState.loading;
      if (!up.canForAnyBusiness((p) => p.canManageTo, whenUnknown: true)) {
        return _HeroState.noPostingScope;
      }
    }

    // 2·3. lifecycle — **partial이면 건너뛴다.**
    //    부분합의 0은 "없다"가 아니라 "일부만 셌다"이다. 실패한 사업장에
    //    공고가 있을 수 있으므로 `공고 없음`을 확정하면 안 된다(§25).
    if (!sr.partial && sr.publishedPostingCount == 0) {
      return sr.hasDraftPosting ? _HeroState.draftOnly : _HeroState.noPosting;
    }

    // 4·5. 오늘의 문제 — 긍정 주장이라 부분합에서도 참이다.
    final shortage = _todayStaffingDay?.shortageCount ?? 0;
    if (shortage > 0) return _HeroState.shortage;
    if ((_todayNeedsAttention ?? 0) > 0) return _HeroState.attention;

    // 6. 여기부터는 전부 "없다"는 주장이다. 부분합으로는 말할 수 없다.
    if (sr.partial) return _HeroState.partialInfo;

    // 7. 오늘 근무 없음. 로스터가 있으면 staffing이 뭐라 하든 오늘은 있다.
    if (!sr.hasTodayTarget && _hasTodayRoster != true) return _HeroState.noToday;

    // 8. 아직 첫 근무 시작 전
    if (_todayDueNow == 0) return _HeroState.beforeStart;

    // 9. 정상
    return _HeroState.normalToday;
  }

  /// lifecycle 상태인가 — 이 상태에서는 운영 섹션이 없고 Hero가 CTA를 갖는다.
  static bool _isLifecycleHero(_HeroState s) =>
      s == _HeroState.setup ||
      s == _HeroState.noPosting ||
      s == _HeroState.draftOnly;

  // ── [HOME-V2-08D.2] section gate ───────────────────────────────────
  //
  // 공통 원칙: **모르는 동안에는 숨기지 않는다.** 로딩·실패는 각 섹션이 이미
  // 자기 자리에서 스피너와 재시도 행으로 말하고 있고, 그것이 canonical이다
  // (ERROR ≠ ZERO). gate는 "확실히 보여줄 것이 없을 때"만 섹션을 없앤다.

  /// 오늘 — staffing 대상이 있거나 확정 로스터가 있으면 렌더.
  bool get _showTodaySection {
    if (_staffingLoading || _attendanceLoading) return true;
    final sr = _staffingReadiness;
    if (sr == null || !sr.hasUsableData) return true; // 에러 행 유지
    // [HOME-V2-08D.3.1] 여기에 `_todayCheckedIn == null → true`가 있었다.
    //   출근 조회가 실패했다는 사실 자체가 섹션의 존재 이유가 되면서,
    //   공고가 하나도 없는 관리자 화면에 이런 조합이 나왔다:
    //
    //     Hero  현재 등록된 공고가 없어요
    //     오늘 운영  출근 현황을 불러오지 못했습니다  재시도
    //
    //   있지도 않은 오늘 운영의 출근을 못 읽었다고 말한 셈이다.
    //
    //   섹션의 존재 근거는 **오늘 운영 대상이 실재하는가** 하나뿐이다.
    //   대상이 있다고 확인된 뒤에야 그 대상의 출근 실패가 사용자에게 의미를 갖는다
    //   (그 에러 행은 _buildTodayAttendanceLine이 그대로 낸다 — ERROR≠ZERO 유지).
    //   조회 실패로 _hasTodayRoster가 null이면 '로스터가 없다'가 아니라
    //   '모른다'이므로, 모르는 것을 근거로 섹션을 만들지 않는다.
    if (sr.hasTodayTarget) return true;
    return _hasTodayRoster == true;
  }

  /// 다가오는 7일 — D+1~D+7에 대상이 있을 때만 렌더.
  bool get _showUpcomingSection {
    if (_staffingLoading) return true;
    final sr = _staffingReadiness;
    if (sr == null || !sr.hasUsableData) return true; // 에러 행 유지
    return sr.days.skip(1).any((d) => d.requiredCount > 0);
  }

  /// 처리할 일 — **posting lifecycle과 독립이다.**
  ///
  /// 공고가 없어도 급여 미이체·계약 미발송은 남아 있다.
  ///
  /// [HOME-V2-08D.5] rows가 비는 이유는 두 가지이고 서로 다르게 다뤄야 한다:
  ///   · 정상 조회했는데 0건  → Hero 상태를 보고 한 줄 안내를 낼지 정한다
  ///   · 확인하지 못했다       → 숨기지 않는다. 숨기면 "없다"는 뜻이 된다
  bool _showTaskSection(_HeroState hero, bool hasRows, bool hasHealthNotice) {
    if (_canonicalSummaryLoading) return true;
    if (hasRows) return true;
    // [HOME-V2-08D.5] 확인하지 못한 것이 있으면 lifecycle 상태에서도 숨기지
    //   않는다. 섹션을 숨기는 것은 "처리할 일이 없다"는 주장인데, UNKNOWN에서는
    //   그것을 알 수 없다. 조용히 사라지는 것과 0건은 사용자에게 같은 뜻이다.
    if (hasHealthNotice) return true;
    // lifecycle 상태에서는 Hero가 이미 다음 행동을 말했다 — 반복하지 않는다.
    return !_isLifecycleHero(hero);
  }

  List<Widget> _buildSections(
      BuildContext context, double s, ThemeData theme, UserProvider up) {
    final hero = _heroStateOf(up);
    final cs = _canonicalSummary;
    final hasRows = _makeActionRows(context, s, up, cs).isNotEmpty;
    // [HOME-V2-08D.5] 확인하지 못한 항목이 있다는 사실도 섹션의 존재 근거다.
    final hasHealthNotice = cs == null || _unknownTaskCount(up, cs) > 0;

    final sections = <Widget>[
      if (_showTodaySection) _buildTodayOps(context, s, theme, up, hero: hero),
      if (_showTaskSection(hero, hasRows, hasHealthNotice))
        _buildActionDashboard(context, s, theme, up),
      if (_showUpcomingSection) _buildFutureStaffing(context, s, theme, up),
    ];
    if (sections.isEmpty) return const [];

    // [§27] Hero 밑에 아무것도 없으면 여백을 만들지 않는다.
    // [CP04] 정밀 §8 리듬 — 섹션 끝→다음 제목 24. Hero 를 부족 행에 합쳤으면(빈 Hero) 앞 블록의 16 과 합쳐 24 가 되게 8.
    final out = <Widget>[SizedBox(height: _heroMergedIntoRow ? 8 : ConceptSpace.sectionGap)];
    for (var i = 0; i < sections.length; i++) {
      if (i > 0) out.add(const SizedBox(height: ConceptSpace.sectionGap));
      out.add(sections[i]);
    }
    return out;
  }

  /// [HOME-V2-08D.1] Home grouped surface 공통 데코레이션.
  ///
  /// surface · radius 16 · grey200 1px · shadow 없음 — 공고 카드(03S.1)와 같은
  /// admin card 언어다. 이전에는 섹션마다 `Colors.white`와 radius를 따로 적어
  /// 같은 값이 여러 벌 존재했고, 그중 하나(공고 등록 준비)만 radius가 `12 * s`,
  /// border가 0.8px로 달랐다. 한 곳에 두어 다시 갈라지지 않게 한다.
  static final BoxDecoration _groupSurface = BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: AppColors.grey200, width: 1),
  );

  // [.69] 화면 읽기에 이름·버튼 역할이 없었다(종은 배지 값 '읽지 않은 알림 N건'만) — SA 홈(.66)과 같은 방식으로 이름을 준다.
  Widget _headerBtn(BuildContext context, double s, IconData icon,
      {required VoidCallback onTap, required String label}) {
    // [CP01] 누름 영역 최소 48×48(이전 회색 타일 38*s 가 곧 영역). 보이는 회색 타일·아이콘은 그대로 두고
    //   그 바깥 투명 영역까지 누름으로 넓힌다. 물결은 Ink 로 타일 위에 그려 예전처럼 보인다.
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              child: Ink(
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.all(8 * s),
                child: Icon(icon, color: AppColors.textSecondary, size: 22 * s),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _adminBadge(double s, ThemeData theme) {
    // [SCALE-BALANCE.34] 큰 글자에서 테두리·채움 배지가 이름과 같은 무게로 커졌다(392·2.0 기기).
    //   역할은 본인이 아는 낮은 우선순위 정보 — 헤더 폭이 모자라는 배율이면 장식 없이 글자만 둔다.
    //   (하위관리자 배지는 사업장 이름을 말하므로 그대로 둔다.)
    final label = Text('관리자',
        style: TextStyle(
            color: theme.primaryColor,
            fontSize: 12,
            fontWeight: FontWeight.w600));
    if (!TextLayout.fits(context, MediaQuery.sizeOf(context).width, 360)) return label;
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
        label,
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
        // [CP01] 긴 사업장 이름은 배지 안에서 줄바꿈 — 말줄임 없이 전문·자연 높이(▼ 포함). 예전에는 폭 제한이 없어 머리 밖으로 넘칠 수 있었다.
        //   배지는 이제 Wrap 안에 있어 폭 상한을 받는다.
        // [CP04 · CP01 인계] 사업장명은 낱말 단위로만 줄을 바꾼다(B 에서 `제2물류/센터`·`창/고` 음절 분절 관측).
        //   `▼` 는 마지막 낱말에 줄바꿈 없는 공백으로 붙인다. 의미 이름은 원문 그대로.
        Flexible(
          child: Text(
            bizName != null
                ? (isMulti
                    ? '${TextLayout.keepWords(bizName)}${String.fromCharCode(0xA0)}▼'
                    : TextLayout.keepWords(bizName))
                : '하위관리자',
            semanticsLabel: bizName != null ? (isMulti ? '$bizName ▼' : bizName) : '하위관리자',
            style: TextStyle(
                color: theme.primaryColor, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );

    // 단일 사업장: 탭 불필요
    if (!isMulti) return badge;

    // [PH1D] 멀티 사업장: 배지 탭 → 공유 BusinessSelectorSheet (DialogHelper.showSheet 패턴)
    // [CP01] 사업장 선택 배지의 누름 영역 최소 48 높이·48 폭 — 보이는 배지는 그대로, 위아래 투명 영역만 넓힌다.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Align(widthFactor: 1, heightFactor: 1, child: badge),
      ),
    );
  }

  // ── 하위관리자 전용 모드 토글 (지원자 ↔ 관리자) ────────────────
  Widget _buildSubAdminModeToggle(
      BuildContext context, double s, UserProvider up, ThemeData theme) {
    // [CP01] 선택지마다 누름 영역 48×48 이상(이전 글자 높이+8*s ≈ 24). 보이는 모양은 그대로 —
    //   테두리 띠는 선택 알약+위아래 3dp 를 감싸고, 남는 높이는 띠 바깥의 투명한 누름 영역이다.
    final pillH = _modeTogglePillHeight(context, s);
    final optH = pillH + 6 > 48 ? pillH + 6 : 48.0;
    final inset = (optH - (pillH + 6)) / 2;
    return Stack(children: [
      Positioned.fill(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: inset),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border, width: 1),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _toggleOpt(s, theme, label: '지원자', selected: false, height: optH,
              // toggleAdminMode → notifyListeners → AuthWrapper 반응형 라우팅 → UserRootScreen
              onTap: () => up.toggleAdminMode()),
          _toggleOpt(s, theme, label: '관리자', selected: true, height: optH, onTap: () {}),
        ]),
      ),
    ]);
  }

  /// [CP01] 선택 알약 높이 = 글자 줄 높이(실제 글자 배율·번들 글꼴) + 위아래 4*s.
  double _modeTogglePillHeight(BuildContext context, double s) {
    final tp = TextPainter(
      text: TextSpan(
          text: '지원자',
          style: DefaultTextStyle.of(context).style.merge(
              const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final h = tp.height + 8 * s;
    tp.dispose();
    return h;
  }

  Widget _toggleOpt(double s, ThemeData theme,
      {required String label, required bool selected, required double height,
      required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: 48, minHeight: height),
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
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
                // [CP01] 비선택 grey500(grey100 위 2.5:1 안팎) → textSecondary — 지원자 홈 토글과 같은 값.
                color: selected ? Colors.white : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 섹션 헤더 ──────────────────────────────────────────────────
  /// [CP04] 섹션 머리(정밀 §8·§9) — 제목 20/700(표면 밖), 선택 부제(범위 등) 14/400, 행동 14/700 brand + 꺾쇠 18.
  ///   행동 receiver ≥48, 의미 node 1개(바깥 Semantics 에 같은 콜백). 실제 사용 폭에 제목 한 줄 + 행동이 안 들어가면
  ///   행동을 제목 아래 오른쪽 줄로 내린다(말줄임·축소 없음). 좌우 여백은 홈 gutter(<360 16, 그 밖 20).
  Widget _sectionHeader(BuildContext context, double s, String title,
      {String? action, VoidCallback? onAction, String? subtitle}) {
    final titleText = Text(TextLayout.keepWords(title), style: ConceptText.section(), semanticsLabel: title);
    final head = subtitle == null
        ? titleText
        : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            titleText,
            const SizedBox(height: 4),
            Text(TextLayout.keepWords(subtitle), style: ConceptText.meta(), semanticsLabel: subtitle),
          ]);
    final gutter = ConceptSpace.gutter(MediaQuery.sizeOf(context).width);
    if (action == null || onAction == null) {
      return Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: Align(alignment: Alignment.centerLeft, child: head));
    }
    Widget actionWidget({required bool wrap}) {
      final label = Text(TextLayout.keepWords(action), style: ConceptText.count().copyWith(height: 1.3), semanticsLabel: action);
      return Semantics(
        container: true,
        button: true,
        label: action,
        excludeSemantics: true,
        onTap: onAction,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onAction,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: ConceptSpace.minTouch, minHeight: ConceptSpace.minTouch),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (wrap) Flexible(child: label) else label,
              const Icon(Icons.chevron_right, size: 18, color: AppColors.brand),
            ]),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: LayoutBuilder(builder: (context, c) {
        final need = _oneLineWidth(context, title, ConceptText.section()) + 8 +
            _oneLineWidth(context, action, ConceptText.count().copyWith(height: 1.3)) + 18;
        if (need <= c.maxWidth) {
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: head),
            const SizedBox(width: 8),
            actionWidget(wrap: false),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          head,
          Align(alignment: Alignment.centerRight, child: actionWidget(wrap: true)),
        ]);
      }),
    );
  }

  /// [CP04] 한 줄 필요 폭 — 실제 글자 배율·DefaultTextStyle·locale(번들 글꼴). 지원자 홈 CP03 과 같은 측정.
  double _oneLineWidth(BuildContext context, String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
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
    // [SA-AUDIT.49] 모든 사업장이 운영 중지·종료면 준비 단계를 권하지 않는다 — 관리자가 할 수 있는
    //   일이 아니다(위 STATE D 배너가 상황을 말한다). 기기: SA 비활성 뒤 '사업장 등록 · 승인 진행 중'.
    if (_allBusinessesClosed) return const SizedBox.shrink();
    final r = _firstPosting;
    if (r == null || r.allReady) return const SizedBox.shrink();

    final done = r.completedCount;
    // [POSTING-V2-02C.1] CTA 대상은 task별 결핍 사업장 — 목록의 첫 번째가 아니다.
    final bizTarget = _businessCtaBusiness;
    final wtTarget = _workTypeCtaBusiness;
    final tplTarget = _templateCtaBusiness;

    return Padding(
      // [HOME-V2-08D.2] Hero 자리로 옮겼다 — 다른 Hero variant와 같은 gutter를
      //   쓰고, 아래 여백은 _buildSections가 소유한다(섹션이 없으면 여백도 없다).
      padding: EdgeInsets.symmetric(horizontal: 16 * s),
      child: Container(
        // [HOME-V2-08D.1] 이전에는 radius가 `12 * s`라 기기 폭에 따라 모서리가
        //   달라졌고 border도 혼자 0.8px였다. 다른 섹션과 같은 값을 쓴다.
        decoration: _groupSurface,
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
                  SizedBox(width: 10 * s),
                  // [HOME-V2-08D.2] Hero 문장 위계(17 bold)로 올린다 —
                  //   이 상태에서 화면이 말해야 하는 한 문장이다.
                  Expanded(
                    // [ADMIN-HOME.31] 큰 글자에서 '남았|어요' 로 끊겼다 — 낱말 단위(표시만).
                    child: Text(
                      TextLayout.keepWords('공고 등록까지 ${FirstPostingReadiness.totalTasks - done}단계 남았어요'),
                      semanticsLabel: '공고 등록까지 ${FirstPostingReadiness.totalTasks - done}단계 남았어요',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        height: 1.35,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  // [R7-P4.4E.4] `2 / 4 완료` 를 뺐다.
                  //
                  //   제목이 이미 "2단계 남았어요" 라고 말한다. 같은 사실을
                  //   같은 무게로 한 번 더 두면, 읽는 사람이 둘을 대조하느라
                  //   정작 **지금 무엇을 하면 되는지**가 늦게 보인다.
                  //   이 카드는 진행률 KPI 가 아니라 다음 행동을 가리키는
                  //   자리다. 좁은 화면에서 제목을 밀어내던 요소이기도 하다.
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
                    builder: (_) => bizTarget == null
                        ? const BusinessFormScreen()
                        : BusinessFormScreen(business: bizTarget),
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
              // [R8-P7.4] 못 읽었을 때는 "등록하세요"가 아니라 못 읽었다고 말한다.
              //   이동 대상(wtTarget)이 없어 locked로 떨어지는 경로도 같은 문장을
              //   써야 한다 — 그때 '사업장 등록 후 가능'은 사실이 아니다.
              lockedHint: r.workTypesUnknown
                  ? '상태를 확인하지 못했어요'
                  : '사업장 등록 후 가능',
              // [P4.4-CP7-01] 승인 전에는 업무를 등록해도 이 칸이 완료로
              //   바뀌지 않는다. `workTypesReady` 는 **승인된** 사업장만 담은
              //   readinessMap 에서 나오기 때문이다(`_loadPostingReadiness` 가
              //   `approvedBizs` 만 조회한다). 그래서 신규 관리자는 업무를
              //   등록하고 돌아와도 같은 줄이 미완료로 남아 있는 것을 보고,
              //   자기가 뭘 잘못했는지 몰라 같은 화면을 다시 연다.
              //   막힌 이유는 업무가 아니라 **승인**이라는 사실을 말해 준다.
              //   (아직 등록하지 않은 경우에도 참이다 — 완료 표시가 승인
              //    이후에 붙는다는 말이지, 이미 했다는 말이 아니다.)
              pendingHint: r.workTypesUnknown
                  ? '상태를 확인하지 못했어요'
                  : (r.hasAnyBusiness && !r.businessReady
                      ? '사업장 승인 후 반영돼요'
                      : null),
              onTap: wtTarget == null
                  ? null
                  : () => _safeNavigate(() async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WorkTypeManagementScreen(
                              businessId: wtTarget.id,
                              businessName: wtTarget.name,
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
              // [R7-P4.4E.2] 이 안내는 원래 CreateTO 사전조건 카드에 있었다.
              //   그 체크리스트를 Home 으로 일원화하면서 문구까지 사라지면,
              //   "왜 지금 이걸 만들어야 하는가" 를 말해 주던 자리가 없어진다.
              //   소유자가 바뀐 것이지 안내가 필요 없어진 것이 아니다.
              purpose: '한 번 만들면 이후 계약에도 계속 사용할 수 있어요',
              onTap: tplTarget == null
                  ? null
                  : () => _safeNavigate(() async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ContractTemplateListScreen(
                              businessId: tplTarget.id,
                            ),
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
              // [R7-P4.4E.3A] 고용주 날인 상태를 못 읽었으면(SubAdmin) 본인
              //   날인을 등록하라고 권하지 않는다. 계약서 사업주란에 들어가는
              //   것은 사업장 owner 의 날인이고, 여기서 등록되는 것은 호출자
              //   자신의 날인이다 — 눌러도 그 칸은 채워지지 않는다.
              pendingHint: r.sealUnknown ? '사업장 관리자에게 확인해 주세요' : null,
              onTap: r.sealUnknown
                  ? null
                  : () => _safeNavigate(() async {
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
    /// 라벨 아래 줄에 붙는 목적 설명 (완료되면 숨긴다)
    String? purpose,
    VoidCallback? onTap,
  }) {
    final done = r.isDone(task);
    // [POSTING-V2-02C.1] 이동할 대상 사업장이 없으면 '지금 가능'으로 보이게
    //   두지 않는다 — 화살표만 뜨고 눌러도 아무 일이 없는 상태가 된다.
    //   (예: 승인된 사업장 전부가 업무는 있고 등록증만 없는 경우 —
    //    올바른 다음 행동은 업무가 아니라 사업자등록증이다)
    final actionable = r.isActionable(task) && (done || onTap != null);
    final hint = done ? null : (actionable ? pendingHint : lockedHint);

    return InkWell(
      onTap: done || !actionable ? null : onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 10 * s),
        child: Row(
          children: [
            // [R7-P4.4E.4] leading 영역을 고정 폭으로 둔다 — 체크(채움)와
            //   업무·문서(외곽선)는 글리프 폭이 달라서, 그냥 놓으면 라벨
            //   시작점이 행마다 미세하게 어긋난다.
            SizedBox(
              width: 18 * s,
              child: Center(
                child: Icon(
                  done ? Icons.check_circle : icon,
                  size: 15 * s,
                  color: done
                      ? AppColors.success
                      : (actionable
                          ? AppColors.textSecondary
                          : AppColors.grey300),
                ),
              ),
            ),
            SizedBox(width: 9 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: done
                          ? AppColors.textSecondary
                          : (actionable
                              ? AppColors.textPrimary
                              : AppColors.grey400),
                    ),
                  ),
                  // [R7-P4.4E.2] 목적 설명은 **라벨 아래 줄**이다.
                  //   오른쪽 힌트 슬롯은 '사업장 등록 후 가능' 같은 짧은 상태
                  //   문구용이라 폭을 나눠 갖는다. 거기에 문장을 넣었더니
                  //   라벨이 '계약 / 서 템 / 플릿' 으로 쪼개졌다.
                  //   끝난 항목에는 보여주지 않는다 — 이미 한 일의 이유는 소음이다.
                  if (purpose != null && !done) ...[
                    SizedBox(height: 2 * s),
                    Text(
                      purpose,
                      // 힌트 슬롯과 같은 12px — 이 화면의 하한이다.
                      // 새 typography scale 을 만들지 않는다.
                      //
                      // [R7-P4.4E.4] 색을 한 단계 올렸다. grey400 은 이 화면에서
                      //   **비활성**을 뜻하는 톤이라, 읽으라고 쓴 설명이 꺼진
                      //   항목처럼 보였다. 설명문은 본문보다 약하되 분명히
                      //   읽히는 보조 텍스트다.
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (hint != null)
              Text(
                hint,
                style: TextStyle(fontSize: 12, color: AppColors.grey400),
              )
            else if (!done && actionable)
              // [R7-P4.4E.4] 지금 할 수 있는 행동은 chevron **하나만** 파랗다.
              //
              //   완료는 초록 체크로 이미 분명한데, 미완료는 회색 아이콘 ·
              //   검은 글씨 · 회색 chevron 이라 "누를 수 있는 일" 로 읽히지
              //   않았다. 강조는 하나면 충분하다 — 제목을 파랗게 하거나
              //   버튼·배경을 더하면 네 줄이 서로 경쟁한다.
              //   완료 행에는 주지 않는다(§7) — 상태가 행동과 겨루면 안 된다.
              Icon(Icons.chevron_right, size: 16 * s, color: AppColors.info),
          ],
        ),
      ),
    );
  }


  // ── [PHASE-2C/R6.1] 오늘 운영 Block ────────────────────────────
  // [HOME-V2-08D.3] 3-column KPI(필요·확정·부족 / 현재 출근·근태 확인)를 폐기하고
  //   operational group으로 바꾼다:
  //
  //     8명 중 5명 확정          ← 요약(context, tap 없음)
  //     ⚠ 3명 부족 · 평택센터 ›   ← 실제 문제(actionable)
  //     ⏱ 근태 확인 2건 ›
  //     출근 4/5                ← 보조 정보
  //
  //   KPI 5개를 같은 크기로 늘어놓으면 `부족 0`과 `부족 3`이 같은 무게로 읽힌다.
  //   문제는 있을 때만 행으로 나타나고, 없으면 자리 자체가 사라진다.
  // 부족: canManageTo → DayApplicantsDialog(오늘) [R6.1]
  // 근태 확인 / 당일 명단: canManageWorkers → AttendanceStatusDialog(오늘) [R5.2]
  // ERROR≠ZERO: 쿼리 실패 시 null 유지 (영역별 재시도 행 유지)
  // [SCALE-BALANCE.34] hero 는 _buildSections 가 한 번 derive 한 값을 받는다(§2 — 한 곳에서만 derive).
  Widget _buildTodayOps(BuildContext context, double s, ThemeData theme, UserProvider up,
      {_HeroState? hero}) {
    final canSeeStaffing = _verified(up, (p) => p.canManageTo)
        || _verified(up, (p) => p.canManageWorkers);
    final canSeeAttendance = _verified(up, (p) => p.canManageWorkers);

    if (!canSeeStaffing && !canSeeAttendance) return const SizedBox.shrink();

    // [HOME-V2-08D.3] 그룹은 세 덩어리로 읽힌다: 요약 → 문제 → 출근.
    //   비어 있는 덩어리는 divider까지 함께 빠진다. 문제가 하나뿐이어도
    //   빈 issue slot이나 남는 divider가 생기지 않는다.
    final blocks = <Widget>[];

    final summary = canSeeStaffing ? _buildTodayStaffingSummary(s, theme) : null;
    // [DU-VQ-03 · 후속13 §2] Hero 를 부족 행에 합치면 Hero 가 보조로 말하던 **오늘 확정 근무의 업무·시간**(_todayWorkSummary)도
    //   함께 사라졌다. 오늘 전체 확정 근무 context 임을 밝혀 요약 덩어리 안의 보조 줄로 남긴다(부족 위치 아님 — 부족 위치는 부족 행이 말한다).
    // [CP04] 업무·시간이 하나로 확정되면 요약 머리(20/700)가 이미 그 업무·시간을 말한다 — 같은 값을 반복하지 않는다.
    //   여럿이면(`업무 N개`·`시간대 N개`) 기존 `확정 근무 · …` 보조 줄을 그대로 남긴다(부족 위치 아님).
    final mergedContext = hero == _HeroState.shortage && _todayShortageRowShown(up) && !_todayWorkTimeIsSingle
        ? _todayWorkTimeSummary
        : null;
    if (summary != null) {
      blocks.add(mergedContext == null || mergedContext.isEmpty
          ? summary
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              summary,
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(TextLayout.phrases('확정 근무 · $mergedContext'),
                    semanticsLabel: '확정 근무 · $mergedContext', style: ConceptText.meta()),
              ),
            ]));
    }

    final issues = _buildTodayIssueRows(context, s, up,
        canSeeStaffing: canSeeStaffing, canSeeAttendance: canSeeAttendance,
        // [DU-VQ-03] Hero 를 이 행으로 합쳤으면 행이 기본 issue 강조(quiet 아님)
        heroSaysShortage: hero == _HeroState.shortage && !_todayShortageRowShown(up));
    if (issues.isNotEmpty) blocks.add(Column(children: issues));

    final attendance =
        canSeeAttendance ? _buildTodayAttendanceLine(s, theme) : null;
    if (attendance != null) blocks.add(attendance);

    if (blocks.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) {
        children.add(Padding(
          padding: EdgeInsets.symmetric(horizontal: 12 * s),
          child: Divider(height: 1, color: AppColors.border),
        ));
      }
      children.add(blocks[i]);
    }

    // [HOME-V2-08D.3] `당일 명단` — 오늘 전체 로스터·근태 상태·NO_SHOW 복구까지
    //   이미 한 화면에서 제공하는 기존 dialog로 보낸다. 새 화면을 만들지 않는다.
    //   권한이 없으면 disabled teaser를 두지 않고 CTA 자체를 감춘다.
    final canOpenRoster = canSeeAttendance;

    return Column(children: [
      // [HOME-V2-08D.4] `오늘 운영` → `오늘`. 옆에 `당일 명단`이 붙은 뒤로
      //   `운영`은 헤더를 길게만 만들고 아무것도 구분해 주지 않는다.
      _sectionHeader(context, s, '오늘의 근무',
          action: canOpenRoster ? '명단 보기' : null,
          onAction: canOpenRoster
              ? () => unawaited(_safeNavigate(() => _requireApprovedBusiness(
                  context, () => _openTodayAttendanceDialog(context))))
              : null),
      const SizedBox(height: ConceptSpace.sectionTitleToCard),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: _gutter(context)),
        child: Container(
          // [AH-V2-05C] 상태(정상/에러)에 따라 카드 깊이가 달라지지 않는다.
          // [CP04] 최상위 그룹만 conceptRaised 한 겹(정밀 §6) — 안쪽 덩어리는 그림자 0, 구분선으로 나눈다.
          decoration: ConceptSurface.raised(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    ]);
  }

  /// [HOME-V2-08D.3] Staffing 요약 한 줄 — `8명 중 5명 확정`.
  ///
  /// 이 줄은 action이 아니라 context다. tap도 chevron도 없다.
  /// 보여줄 것이 없으면 null을 돌려준다 (divider까지 함께 빠진다).
  Widget? _buildTodayStaffingSummary(double s, ThemeData theme) {
    if (_staffingLoading) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 18 * s),
        child: Center(child: SizedBox(width: 16 * s, height: 16 * s,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: theme.primaryColor))),
      );
    }

    // 쿼리 실패 — null 또는 쓸 수 있는 데이터 없음
    // [AH-V2-03.1] partial(부분합)은 여기서 걸리지 않고 아래로 내려간다.
    // [HOME-V2-08D.3] 실패를 `0명 중 0명 확정`으로 요약하지 않는다. ERROR≠ZERO.
    if (_staffingReadiness == null || !_staffingReadiness!.hasUsableData) {
      return _todayOpsErrorRow(s,
        message: '인력 정보를 불러오지 못했어요',
        onRetry: () => unawaited(_loadStaffingReadiness()),
      );
    }

    // [AH-V2-03] 오늘 인력 운영 대상 자체가 없는 경우 —
    //   0/0/0 수치만 보여주면 "운영 중인데 필요 인원이 0"처럼 읽힌다.
    // [HOME-V2-08D.2] 그 말을 이제 Hero가 한다. 섹션 자체가 gate에서 걸러지고,
    //   여기 남는 경우는 **로스터는 있는데 staffing 대상이 0인** 상태뿐이다.
    //   그때 `오늘 예정된 인력 운영이 없어요`를 출근 수치 옆에 두면 같은 카드가
    //   서로 모순된다 — 아무 말도 하지 않고 출근 행에 자리를 넘긴다.
    if (!_staffingReadiness!.hasTodayTarget) {
      return null;
    }

    final day = _todayStaffingDay;
    final required  = day?.requiredCount  ?? 0;
    final confirmed = day?.confirmedCount ?? 0;
    final shortage  = day?.shortageCount  ?? 0;

    // [HOME-V2-08D.3] 전원 확정은 `8명 중 8명 확정`보다 `8명 전원 확정`이
    //   한 번에 읽힌다. 단 required == 0에서는 쓰지 않는다 —
    //   `0명 전원 확정`은 운영이 있는 것처럼 들린다.
    //   shortageCount는 per-wdId 합산이라 required - confirmed와 다를 수 있으므로
    //   둘 다 만족할 때만 '전원 확정'이라고 말한다.
    // [R7-P1-4 H1] `필요` 와 `더 필요` 는 **다른 모집단**이었다 — 문구로 해결했다.
    //
    //   서버(`callableGetStaffingReadiness`)는 이렇게 센다.
    //     required  += wd.required                        ← 종료된 단위도 포함
    //     shortage  += wd.closed ? 0 : max(0, req - conf)  ← 종료 단위는 0
    //   "종료된 단위는 채울 수 없으므로 부족이 아니다" 가 그 규칙이고, 같은
    //   계약을 일자별 인력 현황도 쓴다(`DayStaffingRow.seedsGroup`).
    //
    //   그래서 정원 축이 `5명 필요` 이고 옆에 `2명 부족` 이 서는 것은 데이터로는
    //   정상인데(5 중 3명분은 모집이 끝난 자리), 두 축이 같은 단어(`필요`/`더 필요`)를
    //   쓰는 바람에 `5 - 0 = 5` 를 기대한 사람에게 어긋난 산술로 읽혔다.
    //
    //   → **정원 축에서 `필요` 를 뺀다.** 같은 화면의 D+1~D+7 행이 같은 서버 세
    //     필드로 이미 `N명 중 M명 확정` + `N명 부족` 을 쓰고 있다
    //     (`_buildFutureShortageRow`). 오늘 카드만 다른 단어를 쓰고 있었다 —
    //     새 라벨을 만드는 대신 그 계약에 합친다. 서버 산술·모집단·지표는 그대로다.
    //   [CORRECTION-R7-HOME-REQUIRED-VS-RECRUITABLE-SHORTAGE-COPY] RESOLVED
    final allStaffed = required > 0 && shortage == 0 && confirmed >= required;
    final summaryText = allStaffed
        ? '$required명 전원 확정'
        : '$required명 중 $confirmed명 확정';

    // [AH-V2-04B] 다사업장에서 이 숫자가 어느 범위의 합계인지.
    //   scope label은 partial일 때 숨긴다 — 성공 사업장 수를 클라이언트가
    //   안전하게 알 수 없고, partial notice가 이미 범위를 말해주기 때문이다.
    final scopeLabel = _staffingScopeLabel();

    // [CP04] 정밀 §8·§9 — 인원 요약 18(확정 수만 700), 정원 N 을 다시 `필요`로 부르지 않는다.
    //   부족은 `N명 추가 필요` 필 한 번(#FDEAC4/#8A4B00 13/700, H10/V4 r8) — 서버 shortage 그대로, hasUsableData 일 때만.
    final lead = allStaffed ? '$required명' : '$required명 중 ';
    final strong = allStaffed ? '' : '$confirmed명';
    final tail = allStaffed ? ' 전원 확정' : ' 확정';
    final staffLine = Text.rich(
      TextSpan(children: [
        TextSpan(text: lead, style: allStaffed ? ConceptText.adminStaffStrong() : ConceptText.adminStaffRegular()),
        if (strong.isNotEmpty) TextSpan(text: strong, style: ConceptText.adminStaffStrong()),
        TextSpan(text: tail, style: ConceptText.adminStaffRegular()),
      ]),
      semanticsLabel: summaryText,
    );
    final needPill = shortage > 0
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: ConceptSurface.staffingNeed(),
            child: Text(TextLayout.keepWords('$shortage명 추가 필요'),
                semanticsLabel: '$shortage명 추가 필요',
                style: ConceptText.pill(AppColors.conceptStaffingNeedText)),
          )
        : null;
    final workTime = _todayWorkTimeSummary;
    final partial = _staffingReadiness?.partial == true;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, partial ? 8 : 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (scopeLabel != null) ...[
            Text(TextLayout.keepWords(scopeLabel), semanticsLabel: scopeLabel, style: ConceptText.meta()),
            const SizedBox(height: 4),
          ],
          if (_todayWorkTimeIsSingle && workTime != null) ...[
            Text(TextLayout.phrases(workTime), semanticsLabel: workTime, style: ConceptText.adminWorkTime()),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [staffLine, if (needPill != null) needPill],
          ),
        ]),
      ),
      // [AH-V2-03] 부분합 고지 — 숫자를 전체 합계로 오해하지 않도록
      _partialStaffingNotice(s),
    ]);
  }

  /// [CP04] 오늘 확정 근무의 업무·시간이 **하나로 확정**됐는가 — 그때만 20/700 머리로 보인다(정밀 §8 관리자 업무·시간).
  ///   `_summarizeWork` 는 여럿이면 `업무 N개`·`시간대 N개` 로 말한다 — 그 개수 표기가 있으면 대표 시간을 세우지 않는다.
  bool get _todayWorkTimeIsSingle {
    final w = _todayWorkTimeSummary;
    return w != null && w.isNotEmpty && !RegExp(r'(업무|시간대) [0-9]+개').hasMatch(w);
  }

  /// [HOME-V2-08D.3] 오늘의 실제 문제 행들. 없으면 빈 목록.
  ///
  /// 순서는 `부족` → `근태 확인` — Hero priority와 같다.
  /// 당일 부족은 충원 가능한 시간이 지나면 복구 기회 자체가 사라진다.
  ///
  /// `부족 0` / `근태 확인 0`은 행을 만들지 않는다. 0을 지면에 남기면
  /// 문제가 없는 날에도 문제 영역을 읽게 된다.
  List<Widget> _buildTodayIssueRows(
    BuildContext context,
    double s,
    UserProvider up, {
    required bool canSeeStaffing,
    required bool canSeeAttendance,
    bool heroSaysShortage = false,
  }) {
    final rows = <Widget>[];

    // 부족 — 로딩 중이거나 조회 실패면 숫자를 주장하지 않는다.
    if (canSeeStaffing && !_staffingLoading) {
      final day = _todayStaffingDay;
      final shortage = day?.shortageCount ?? 0;
      if (day != null && shortage > 0) {
        // [R6.1] canManageTo일 때만 DayApplicantsDialog로 갈 수 있다.
        //   권한이 없어도 상태는 보여준다 — chevron과 tap만 없앤다.
        final canManageTo = _verified(up, (p) => p.canManageTo);
        // [HOME-V2-08D.3] 부족 위치는 shortageBusinesses에서만 온다.
        //   _todayWorkSummary는 오늘 전체 근무 context라 부족 위치와 다를 수 있다.
        //   [AH-V2-04B] 단일 사업장은 header가 이미 사업장명을 말한다.
        final where = _isMultiBusinessScope ? day.shortageLocationLabel() : null;
        // [R7-P1-4 후속 H1] 위 줄의 정원과 이 줄의 부족은 **다른 모집단**이다.
        //   두 수가 정원 - 확정으로 이어지지 않는 날에만 부족의 범위를 말한다.
        //   그 어긋남의 원인은 하나가 아니다 — 모집이 끝난 업무 단위가 정원에는
        //   남아 있거나(`wd.closed`), 어떤 단위가 과충원돼 다른 단위의 부족을
        //   상쇄하지 못하기 때문이다(부족은 단위별 max(0, req-conf) 합산).
        //   그래서 **원인을 단정하지 않고 부족이 세는 범위만** 말한다.
        //   조건은 비교일 뿐이다 — 정원-확정을 부족으로 쓰거나 화면에 보이지 않는다.
        final scopeDiffers =
            (day.requiredCount - day.confirmedCount) != shortage;
        // [CP04] 정밀 §4 — 부족 숫자는 요약의 `N명 추가 필요` 필이 한 번 말한다. 이 행은 같은 숫자를 다시 쓰지 않고
        //   행동 `인원 현황 보기`(기존 권한으로 onTap 이 허용될 때만)와 범위 context(다사업장 부족 위치·집계 기준 차이)만 남긴다.
        //   권한이 없으면 행동 없이 context 만(거짓 꺾쇠·버튼 없음). 목적지·순서는 그대로.
        final detail = _shortageDetailRow(
          where: where,
          scopeDiffers: scopeDiffers,
          onTap: canManageTo
              ? () => unawaited(_safeNavigate(() => _requireApprovedBusiness(
                  context, () => _navigateToDayApplicantsForDate(context, day))))
              : null,
        );
        if (detail != null) rows.add(detail);
      }
    }

    // 근태 확인 — _todayCheckedIn == null은 조회 실패다. 건수를 주장하지 않는다.
    if (canSeeAttendance && !_attendanceLoading && _todayCheckedIn != null) {
      final needsAttention = _todayNeedsAttention ?? 0;
      if (needsAttention > 0) {
        final canManageWorkers = _verified(up, (p) => p.canManageWorkers);
        // [HOME-V2-08D.3] 지각/미출근/미퇴근 breakdown은 여기서 펼치지 않는다.
        //   그것은 AttendanceStatusDialog의 역할이다.
        rows.add(_todayIssueRow(s,
          icon: Icons.schedule_outlined,
          label: '근태 확인 $needsAttention건',
          color: AppColors.warning,
          onTap: canManageWorkers
              ? () => unawaited(_safeNavigate(() => _requireApprovedBusiness(
                  context, () => _openTodayAttendanceDialog(context))))
              : null,
        ));
      }
    }

    return rows;
  }

  /// [HOME-V2-08D.3] 문제 행. icon / label / semantic color / optional tap 뿐이다.
  ///
  /// 두 issue는 같은 높이·같은 typography·같은 chevron 계약을 쓰고
  /// semantic color만 다르다 — Home은 둘을 동등한 actionable issue로 보여준다.
  /// 우선순위를 말하는 것은 Hero의 역할이다.
  /// [CP04] 오늘 부족의 하위 행 — 숫자 없이 행동 `인원 현황 보기`(brand, 허용될 때만)와 범위 context 만.
  ///   보여줄 것(행동·위치·집계 기준 차이)이 하나도 없으면 null(빈 행·구분선 없음).
  static const String _shortageScopeNote = '필요·확정 인원과 추가 필요 인원은 집계 기준이 달라요';
  Widget? _shortageDetailRow({required String? where, required bool scopeDiffers, VoidCallback? onTap}) {
    final lines = <Widget>[
      if (where != null)
        Text(TextLayout.phrases(where), semanticsLabel: where, style: ConceptText.meta()),
      if (scopeDiffers)
        Text(TextLayout.keepWords(_shortageScopeNote), semanticsLabel: _shortageScopeNote, style: ConceptText.meta()),
    ];
    if (onTap == null && lines.isEmpty) return null;
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (onTap != null) Text(TextLayout.keepWords('인원 현황 보기'), semanticsLabel: '인원 현황 보기',
          style: ConceptText.count().copyWith(height: 1.3)),
      for (var i = 0; i < lines.length; i++) ...[
        if (i > 0 || onTap != null) const SizedBox(height: 4),
        lines[i],
      ],
    ]);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: ConceptSpace.minTouch),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Expanded(child: body),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.brand),
          ],
        ]),
      ),
    );
    if (onTap == null) return row;
    final label = ['인원 현황 보기', if (where != null) where, if (scopeDiffers) _shortageScopeNote].join(', ');
    return Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(onTap: onTap, child: row),
    );
  }

  Widget _todayIssueRow(double s, {
    required IconData icon,
    required String label,
    required Color color,
    /// [R7-P1-4 후속 H1] 수치의 **범위**를 말하는 보조 한 줄. 없으면 그리지 않는다.
    ///   숫자를 담지 않는다 — 여기서 새 값을 계산하거나 주장하지 않는다.
    String? note,
    VoidCallback? onTap,
    bool quiet = false,
  }) {
    // [CP04] 글자 16/700(조용하면 400)·note 14 전문(말줄임 제거). 행 전체 receiver ≥48·의미 node(같은 콜백).
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: ConceptSpace.minTouch),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        // [SCALE-BALANCE.34] 아이콘·chevron 은 여러 줄 글자의 세로 가운데가 아니라 첫 줄에 맞춘다.
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: EdgeInsets.only(top: ((MediaQuery.textScalerOf(context).scale(16) * 1.45 - 20) / 2).clamp(0, 40)),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // [ADMIN-HOME.31] 낱말 단위로 줄을 바꾸고 줄 수를 막지 않는다.
                Text(TextLayout.phrases(label),
                    semanticsLabel: label,
                    style: ConceptText.body().copyWith(fontWeight: quiet ? FontWeight.w400 : FontWeight.w700)),
                if (note != null) ...[
                  const SizedBox(height: 4),
                  Text(TextLayout.keepWords(note), semanticsLabel: note, style: ConceptText.meta()),
                ],
              ],
            ),
          ),
          // chevron은 실제로 갈 곳이 있을 때만 — 권한이 없으면 상태만 남는다.
          if (onTap != null)
            Padding(
              padding: EdgeInsets.only(top: ((MediaQuery.textScalerOf(context).scale(16) * 1.45 - 18) / 2).clamp(0, 40)),
              child: const Icon(Icons.chevron_right, size: 18, color: AppColors.conceptChevron),
            ),
        ]),
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      container: true,
      button: true,
      label: [label, if (note != null) note].join(', '),
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(onTap: onTap, child: row),
    );
  }

  /// [AH-V2-04B] 관리 사업장이 2곳 이상인지 — staffing 집계 범위 기준.
  ///
  /// _getBusinesses()가 CF와 같은 scope를 쓴다 (SubAdmin: effectiveBusinessId 1곳,
  /// OWNER: managedBusinessIds). 따라서 SubAdmin은 자연히 false가 된다.
  bool get _isMultiBusinessScope => _businesses.length > 1;

  /// 'YYYY-MM-DD' → 'YYYY.MM.DD'. 형식이 다르면 받은 그대로 둔다(값을 추측하지 않는다).
  static String _dotDate(String ymd) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(ymd) ? ymd.replaceAll('-', '.') : ymd;

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

  /// [DU307 Standards §12.2] 부분 실패 표시 — 작은 주의 아이콘 하나(상태색은 이 면적에만). 의미는 옆 문장이 말한다.
  static const double _kPartialMarkSize = 16;
  Widget _partialMark() => const ExcludeSemantics(
        child: Icon(Icons.cloud_off_outlined, size: _kPartialMarkSize, color: AppColors.warningDark),
      );

  /// [AH-V2-03] 일부 사업장 조회 실패 고지.
  ///
  /// 정상 사업장 데이터는 그대로 보여주되, 표시된 숫자가 전체 합계가
  /// 아니라는 사실을 숨기지 않는다. 실패를 0으로 합산하지 않으므로
  /// 수치 자체는 "성공한 사업장의 정확한 합"이다.
  Widget _partialStaffingNotice(double s) {
    final sr = _staffingReadiness;
    if (sr == null || !sr.partial) return const SizedBox.shrink();
    // [CP04] 부분합 고지 문구·조건 그대로. `다시 시도` brand receiver ≥48·의미 node(같은 콜백).
    // [DU307 Standards §12.2] 부분 실패 = 작은 주의 표시 + 중립 설명 + brand `다시 시도`. 문장 전체 warningDark(호박색)를
    //   중립 메타(14/400 textSecondary)로 낮추고 앞에 작은 주의 아이콘 하나를 둔다(_partialMark). 완전 실패 행(errorDark)과 구별된다.
    final msg = '사업장 ${sr.failedBusinessCount}곳의 정보를 불러오지 못해 나머지 사업장 기준으로 표시했어요';
    final msgStyle = ConceptText.meta();
    final retryStyle = ConceptText.count().copyWith(height: 1.3);
    void retry() => unawaited(_loadStaffingReadiness());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Builder(builder: (context) {
        final retryW = _oneLineWidth(context, '다시 시도', retryStyle);
        return _rowWithTrailing(
          context,
          leading: _partialMark(),
          leadingWidth: _kPartialMarkSize,
          leadingGap: 6,
          body: Text(TextLayout.keepWords(msg), semanticsLabel: msg, style: msgStyle),
          bodyTexts: [(TextLayout.keepWords(msg), msgStyle)],
          trailingWidth: retryW < ConceptSpace.minTouch ? ConceptSpace.minTouch : retryW,
          trailing: Semantics(
            container: true,
            button: true,
            label: '다시 시도',
            excludeSemantics: true,
            onTap: retry,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: retry,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: ConceptSpace.minTouch, minHeight: ConceptSpace.minTouch),
                child: Center(widthFactor: 1, heightFactor: 1, child: Text('다시 시도', style: retryStyle)),
              ),
            ),
          ),
        );
      }),
    );
  }

  /// [HOME-V2-08D.3] 출근 보조 한 줄 — `출근 4/5`.
  ///
  /// 근태 확인 건수는 여기 없다. 그것은 문제이므로 issue row로 올라갔다.
  /// 이 줄은 tap하지 않는다 — 로스터로 가는 길은 header의 `당일 명단`이다.
  /// 보여줄 것이 없으면 null (divider까지 함께 빠진다).
  Widget? _buildTodayAttendanceLine(double s, ThemeData theme) {
    if (_attendanceLoading) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 18 * s),
        child: Center(child: SizedBox(width: 16 * s, height: 16 * s,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: theme.primaryColor))),
      );
    }

    // 쿼리 실패 — _todayCheckedIn == null. `출근 0/0`으로 쓰지 않는다. ERROR≠ZERO.
    if (_todayCheckedIn == null) {
      return _todayOpsErrorRow(s,
        message: '출근 현황을 불러오지 못했어요',
        onRetry: () => unawaited(_loadTodayAttendance()),
      );
    }

    // [AH-V2-06] 분모 0 = 오늘 근무는 있지만 아직 첫 시작 시각 전.
    //   '0/0'은 운영이 없는 것처럼 읽히므로 상태로 말한다.
    //   [HOME-V2-08D.3] 분모 semantics(현재까지 출근 대상)는 그대로다.
    final dueNow = _todayDueNow ?? 0;
    final text = dueNow == 0
        ? '출근 예정 전'
        : '출근 ${_todayCheckedIn!}/$dueNow';

    // [CP04] 메타 14/400(정밀 §8). 분모는 현재까지 출근 대상 그대로 — 화면 읽기는 단위를 붙인다.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            semanticsLabel: dueNow == 0 ? text : '출근 ${_todayCheckedIn!}명, 현재까지 출근 대상 $dueNow명',
            style: ConceptText.meta()),
      ),
    );
  }

  /// 오늘 운영 영역별 에러 행 — 재시도 버튼 포함
  /// 영역별 실패 행 — 실패 문구(정상0과 다른 상태) + 같은 영역 로더 `다시 시도`.
  ///   [CP04] 정밀 §4 조회 실패: 실패 안내 errorDark, 재시도 brand. 재시도 receiver ≥48·의미 node(같은 콜백).
  ///   좁으면 `다시 시도`를 아래 오른쪽 줄로(_rowWithTrailing). 문구 전문·자연 높이.
  ///   [DU307 §12.2] [partial] = 일부만 확인하지 못함 — errorDark 문장 대신 작은 주의 아이콘 + 중립 메타(부분합 고지와 같은 표현).
  ///   완전 실패(기본)는 정밀 §4 그대로 errorDark. 문구·로더·receiver·배치 규칙은 그대로다.
  Widget _todayOpsErrorRow(double s, {
    required String message,
    required VoidCallback onRetry,
    bool partial = false,
  }) {
    final msgStyle = partial
        ? ConceptText.meta()
        : ConceptText.meta().copyWith(color: AppColors.errorDark);
    final retryStyle = ConceptText.count().copyWith(height: 1.3);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Builder(builder: (context) {
        return _rowWithTrailing(
          context,
          // [DU307 audit] body 의 세로 8 패딩을 앞 표시에도 맞춘다. 아래행 분기에서 아이콘만 8 위로 뜨지 않게 한다.
          //   양쪽 대칭 패딩이라 같은행 중앙 정렬과 가로 leading 폭 16 은 그대로다.
          leading: partial
              ? Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: _partialMark())
              : null,
          leadingWidth: partial ? _kPartialMarkSize : 0,
          leadingGap: partial ? 6 : 0,
          body: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(TextLayout.keepWords(message), semanticsLabel: message, style: msgStyle),
          ),
          bodyTexts: [(TextLayout.keepWords(message), msgStyle)],
          trailingWidth: _oneLineWidth(context, '다시 시도', retryStyle) < ConceptSpace.minTouch
              ? ConceptSpace.minTouch
              : _oneLineWidth(context, '다시 시도', retryStyle),
          trailing: Semantics(
            container: true,
            button: true,
            label: '다시 시도',
            excludeSemantics: true,
            onTap: onRetry,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRetry,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: ConceptSpace.minTouch, minHeight: ConceptSpace.minTouch),
                child: Center(widthFactor: 1, heightFactor: 1, child: Text('다시 시도', style: retryStyle)),
              ),
            ),
          ),
        );
      }),
    );
  }

  // ── [PHASE-2D] 다가오는 7일 Block ───────────────────────────────
  // [SOURCE] _staffingReadiness.days[1..7] 재사용 — 추가 fetch 없음
  //
  // [HOME-V2-08D.4] 이 섹션은 shortage monitor가 아니다.
  //   `앞으로 7일 중 어느 날에 근무가 있고, 그 준비가 얼마나 됐는가`를 본다.
  //   부족한 날만 보여주면 전원 확정된 날의 약속이 화면에서 사라지고,
  //   관리자는 "다음 근무가 언제인지"를 Home에서 알 수 없게 된다.
  // [RULE] 표시 대상 = requiredCount > 0 (부족·전원확정 모두)
  // [RULE] 정렬 = 부족 있는 날 먼저, 각 그룹 안에서 date ASC
  Widget _buildFutureStaffing(
      BuildContext context, double s, ThemeData theme, UserProvider up) {
    final canSeeBlock = _verified(up, (p) => p.canManageTo)
        || _verified(up, (p) => p.canManageWorkers);
    if (!canSeeBlock) return const SizedBox.shrink();

    // 로딩: Today Ops와 _staffingLoading 공유 (동일 fetch)
    if (_staffingLoading) {
      return Column(children: [
        _sectionHeader(context, s, '다가오는 근무', subtitle: '앞으로 7일'),
        const SizedBox(height: ConceptSpace.sectionTitleToCard),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _gutter(context)),
          child: Container(
            height: 50 * s,
            decoration: ConceptSurface.raised(),
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
        _sectionHeader(context, s, '다가오는 근무', subtitle: '앞으로 7일'),
        const SizedBox(height: ConceptSpace.sectionTitleToCard),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _gutter(context)),
          child: Container(
            decoration: ConceptSurface.raised(),
            child: _todayOpsErrorRow(s,
              message: '향후 인력 현황을 불러오지 못했어요',
              onRetry: () => unawaited(_loadStaffingReadiness())),
          ),
        ),
      ]);
    }

    // D+1~D+7: D0(첫 요소) skip → 근무가 예정된 날 전부
    final futureDays = _staffingReadiness!.days
        .skip(1)
        .where((d) => d.requiredCount > 0)
        .toList()
      // [HOME-V2-08D.4] 부족한 날이 위로 온다 — 충원 가능한 시간은 날짜가
      //   가까울수록 빨리 사라진다. 각 그룹 안에서는 날짜순이라 "다음 근무"를
      //   찾는 읽기도 깨지지 않는다. date는 'YYYY-MM-DD'라 사전순 = 날짜순.
      ..sort((a, b) {
        final aRank = a.shortageCount > 0 ? 0 : 1;
        final bRank = b.shortageCount > 0 ? 0 : 1;
        if (aRank != bRank) return aRank - bRank;
        return a.date.compareTo(b.date);
      });

    // gate(_showUpcomingSection)가 같은 조건을 쓰므로 여기까지 오면 비지 않는다.
    // 방어적으로만 둔다 — 빈 카드를 만들지 않는다.
    if (futureDays.isEmpty) return const SizedBox.shrink();

    return Column(children: [
      _sectionHeader(context, s, '다가오는 근무', subtitle: '앞으로 7일'),
      const SizedBox(height: ConceptSpace.sectionTitleToCard),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: _gutter(context)),
        child: Container(
          // [AH-V2-05C] 상태에 따라 깊이가 달라지지 않는다 — [CP04] 최상위 그룹은 로딩·오류·목록 모두 conceptRaised 한 겹(정밀 §6).
          decoration: ConceptSurface.raised(),
          child: Column(
            children: [
              ...futureDays.asMap().entries.map((e) =>
                _buildFutureShortageRow(
                  context, s, up, e.value,
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

  /// 다가오는 7일 단일 날짜 행.
  ///
  /// [HOME-V2-08D.4] 주어는 날짜다. 그 아래에 준비 상태가 오고, 문제가 있으면
  /// 오른쪽에 부족 수가 붙는다. 부족 여부와 무관하게 **행 전체가 같은 곳으로
  /// 간다** — `날짜를 누르면 그날 사람을 본다`는 규칙에 예외를 만들지 않는다.
  ///
  /// 전용 `충원하기` 버튼은 없앴다. 행 자체가 이미 그 경로이고, 부족한 날에만
  /// 버튼이 생기면 전원 확정된 날은 눌러도 되는지 알 수 없는 죽은 행처럼 보인다.
  Widget _buildFutureShortageRow(
    BuildContext context,
    double s,
    UserProvider up,
    StaffingDayData day, {
    required bool isFirst,
    required bool isLast,
  }) {
    // OWNER 또는 SubAdmin canManageTo → 탭 가능
    // SubAdmin canManageWorkers only → 상태는 읽히되 탭 불가, chevron 없음
    //   (누를 수 없는 chevron은 거짓 affordance다)
    final canNavigate = _verified(up, (p) => p.canManageTo);

    final dateLabel = _futureDateLabel(day.date);
    final required  = day.requiredCount;
    final confirmed = day.confirmedCount;
    final shortage  = day.shortageCount;

    // [HOME-V2-08D.4] 준비 상태는 숫자로 충분하다 — progress bar를 쓰지 않는다.
    //   shortageCount는 per-wdId 합산이라 required - confirmed와 다를 수 있어
    //   둘 다 만족할 때만 '전원 확정'이라고 말한다 (Today 요약과 같은 규칙).
    final fullyStaffed = shortage == 0 && confirmed >= required;
    final parts = <String>[
      fullyStaffed ? '$required명 전원 확정' : '$required명 중 $confirmed명 확정',
    ];

    // [AH-V2-04B] 어느 사업장의 근무인지 — 다사업장일 때만.
    //   단일 사업장은 header가 이미 사업장명을 말한다.
    //   부족 사업장이 아니라 **근무가 예정된** 사업장이다 — 전원 확정된 날에도
    //   어디의 근무인지는 말해야 한다.
    final bizLine = _isMultiBusinessScope ? day.targetLocationLabel() : null;
    if (bizLine != null) parts.add(bizLine);

    // PENDING_ZERO_DISPLAY=HIDE: null(실패)·0 → 숨김, >0 → '지원 대기 N건'
    // [CROSS-DOMAIN-R5.3B] 단위는 **건**이다 — 사람 수가 아니다.
    //   한 사람이 같은 슬롯의 다른 업무를 제안받으면(A PENDING + B INVITED)
    //   이 카운터에 두 번 들어간다. `N명`이라고 하면 없는 사람을 세게 된다.
    if (day.pendingCount != null && day.pendingCount! > 0) {
      parts.add('지원 대기 ${day.pendingCount}건');
    }

    final radius = BorderRadius.only(
      topLeft:     Radius.circular(isFirst ? 16 : 0),
      topRight:    Radius.circular(isFirst ? 16 : 0),
      bottomLeft:  Radius.circular(isLast  ? 16 : 0),
      bottomRight: Radius.circular(isLast  ? 16 : 0),
    );

    // [CP04] 정밀 §4 다가오는 7일 — 날짜 16/700(전문, 말줄임 없음)·나머지 14/400, 부족은 `N명 추가 필요` 14/700 textSecondary(필·빨강 없음).
    //   부족 글자·꺾쇠는 본문이 좁아지면 아래 오른쪽 줄로 내린다(_rowWithTrailing). 값·정렬·목적지·권한 그대로.
    final detail = parts.join(' · ');
    final dateStyle = ConceptText.body().copyWith(fontWeight: FontWeight.w700, height: 1.35);
    final needStyle = ConceptText.meta().copyWith(fontWeight: FontWeight.w700);
    final hasTrailing = shortage > 0 || canNavigate;
    final trailingW = (shortage > 0 ? _oneLineWidth(context, '$shortage명 추가 필요', needStyle) : 0.0) +
        (shortage > 0 && canNavigate ? 4 : 0) +
        (canNavigate ? 18 : 0);
    final rowContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: _rowWithTrailing(
        context,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 날짜가 행의 주어다 — grey metadata로 묻지 않는다.
            Text(TextLayout.keepWords(dateLabel), semanticsLabel: dateLabel, style: dateStyle),
            const SizedBox(height: 4),
            // [ADMIN-HOME.31] 320·1.3 에서 '[합|성] E7 사업장' 으로 끊겼다 — 낱말 단위, 사업장명 말줄임 없음.
            Text(TextLayout.phrases(detail), semanticsLabel: detail, style: ConceptText.meta()),
          ],
        ),
        bodyTexts: [(TextLayout.keepWords(dateLabel), dateStyle), (TextLayout.phrases(detail), ConceptText.meta())],
        trailingWidth: trailingW,
        trailing: !hasTrailing
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (shortage > 0)
                  Text(TextLayout.keepWords('$shortage명 추가 필요'),
                      semanticsLabel: '$shortage명 추가 필요', style: needStyle),
                if (shortage > 0 && canNavigate) const SizedBox(width: 4),
                if (canNavigate) const Icon(Icons.chevron_right, size: 18, color: AppColors.conceptChevron),
              ]),
      ),
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
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(height: 1 / MediaQuery.devicePixelRatioOf(context), color: AppColors.conceptDivider),
        ),
    ]);
  }

  /// [CP04] 행 = (선택) 앞 아이콘 · 본문 · 뒤(숫자 알약·부족 글자·꺾쇠).
  ///   같은 줄 조건은 지원자 홈 C1 r3 에서 수용된 식과 같다: 본문에 남는 폭 ≥ 본문 표시 조각(공백으로 나눈 낱말) 중
  ///   가장 넓은 것의 한 줄 폭, 그리고 ≥ 안쪽 전체 폭의 절반. 아니면 뒤를 본문 아래 오른쪽 줄로 내린다(정밀 §5 행 기하·§8 B 규칙 5).
  ///   말줄임·축소·고정 높이 없음. 행 탭·목적지는 호출부 그대로다.
  Widget _rowWithTrailing(
    BuildContext context, {
    Widget? leading,
    double leadingWidth = 0,
    double leadingGap = 0,
    required Widget body,
    required List<(String, TextStyle)> bodyTexts,
    Widget? trailing,
    double trailingWidth = 0,
    double trailingGap = 8,
  }) {
    if (trailing == null) {
      return Row(children: [
        if (leading != null) ...[leading, SizedBox(width: leadingGap)],
        Expanded(child: body),
      ]);
    }
    return LayoutBuilder(builder: (context, c) {
      var need = 0.0;
      for (final (text, style) in bodyTexts) {
        for (final unit in text.split(' ')) {
          if (unit.isEmpty) continue;
          final w = _oneLineWidth(context, unit, style);
          if (w > need) need = w;
        }
      }
      final inlineBody = c.maxWidth - leadingWidth - leadingGap - trailingGap - trailingWidth;
      if (inlineBody >= need && inlineBody >= c.maxWidth * 0.5) {
        return Row(children: [
          if (leading != null) ...[leading, SizedBox(width: leadingGap)],
          Expanded(child: body),
          SizedBox(width: trailingGap),
          trailing,
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (leading != null) ...[leading, SizedBox(width: leadingGap)],
          Expanded(child: body),
        ]),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: trailing),
      ]);
    });
  }

  /// [CP04] 화면 좌우 여백 — 폭 360 미만 16, 그 외 20(정밀 §8, 다시 s 를 곱하지 않는다).
  double _gutter(BuildContext context) => ConceptSpace.gutter(MediaQuery.sizeOf(context).width);

  /// 날짜 레이블 — 내일이면 '내일', 그 외 'M/D (요일)' 포맷
  String _futureDateLabel(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length < 3) return dateStr;
    final year  = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day   = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return dateStr;

    // [CP04] 지시 §3 — 같은 홈의 다른 로더와 같은 시각 기준(주입 clock, 없으면 실제 now — production 동작 그대로).
    final tomorrowKst =
        FormatHelper.toKstDate((_reads.clock ?? DateTime.now)()).add(const Duration(days: 1));
    if (year == tomorrowKst.year &&
        month == tomorrowKst.month &&
        day == tomorrowKst.day) {
      return '내일';
    }
    return FormatHelper.formatDate(DateTime(year, month, day));
  }

  // ── [PHASE-R5.2] 오늘 확인 필요 → AttendanceStatusDialog ────────
  // 탭 조건: _todayNeedsAttention > 0 && canManageWorkers (buildAttendanceMetrics에서 보장)
  // 반환값: hasChanges → 근태·인력 현황 재조회 + 다른 탭에 알림
  Future<void> _openTodayAttendanceDialog(BuildContext context) async {
    final businesses = await _getBusinesses();
    if (!context.mounted) return;
    // [CP04] 지시 §3 — 오늘 명단 날짜도 홈의 같은 시각 기준(주입 clock, 없으면 실제 now).
    final today = FormatHelper.toKstDate((_reads.clock ?? DateTime.now)());
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
      // [HOME-V2-07.1] 이 다이얼로그 안에서 NO_SHOW 좌석 반납(대체 인력 충원)이
      //   일어날 수 있다. 좌석이 반납되면 확정 인원이 줄어 같은 카드의 `부족`이
      //   바뀌는데, 이전에는 근태 수치만 다시 읽어서 옆 숫자가 낡은 채로 남았다.
      unawaited(_loadStaffingReadiness());
      // [POSTING-V2-02B.2] 좌석 반납은 slot confirmed/pending을 움직이므로
      //   공고·근무 탭도 stale해진다. Home 자신은 위 두 loader로 이미 갱신됐고,
      //   origin self-skip 계약이 중복 full refresh를 막는다.
      WorkforceController.notifyDataChanged(
        origin: AdminMutationOrigin.home,
      );
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
        const SizedBox(height: ConceptSpace.sectionTitleToCard),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _gutter(context)),
          child: Container(
            height: 56 * s,
            decoration: ConceptSurface.raised(),
            child: Center(child: SizedBox(width: 18 * s, height: 18 * s,
              child: CircularProgressIndicator(strokeWidth: 2, color: theme.primaryColor))),
          ),
        ),
      ]);
    }

    final rows = _makeActionRows(context, s, up, cs);

    // [HOME-V2-08D.5] 업무(task)와 데이터 상태(data health)는 다른 것이다.
    //   rows      = 실제로 처리할 대상이 있는 항목만 (KNOWN_NONZERO)
    //   notice    = 확인하지 못한 것이 있다는 사실 (UNKNOWN)
    //   전체 실패(cs == null)는 `일부`가 아니라 섹션 전체의 상태다.
    final summaryFailed = cs == null;
    final unknownCount = _unknownTaskCount(up, cs);
    final showNotice = summaryFailed || unknownCount > 0;

    // 확인하지 못한 것이 있으면 `처리할 업무가 없어요`라고 확정하지 않는다 —
    // 실제로 없는지 알 수 없기 때문이다. 안심 문구는 전부 성공했을 때만 나온다.
    final showReassurance = rows.isEmpty && !showNotice;

    return Column(children: [
      _sectionHeader(context, s, '처리할 일'),
      const SizedBox(height: ConceptSpace.sectionTitleToCard),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: _gutter(context)),
        child: Container(
          // [AH-V2-05C] 상태에 따라 깊이가 달라지지 않는다 — [CP04] 최상위 그룹은 conceptRaised 한 겹, 안쪽 행은 그림자 0(정밀 §5·§6).
          decoration: ConceptSurface.raised(),
          child: Column(children: [
            if (showReassurance)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline, size: 24, color: AppColors.conceptNavy),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(TextLayout.keepWords('처리할 업무가 없어요'),
                        semanticsLabel: '처리할 업무가 없어요', style: ConceptText.taskDescription()),
                  ),
                ]),
              ),
            ...rows.asMap().entries.map((e) => _buildActionRowWidget(
                  context, s, e.value,
                  // notice가 뒤에 붙으면 마지막 행에도 divider가 필요하다
                  isLast: e.key == rows.length - 1 && !showNotice,
                )),
            if (showNotice) _taskHealthNotice(s, total: summaryFailed),
          ]),
        ),
      ),
    ]);
  }


  List<_TaskRow> _makeActionRows(BuildContext context, double s, UserProvider up, AdminHomeSummaryModel? cs) {
    final result = <_TaskRow>[];
    // [PH1] SUB_ADMIN 권한 게이트: 권한 없는 항목은 목록에서 제외
    // CF aggSimple()이 permCount==0(권한없음)과 실제 쿼리 실패를 모두 available:false로
    // 반환하기 때문에 클라이언트에서 먼저 권한 기반 필터링을 적용한다.

    // [AH-V2-05B.3] atIndex는 '이체 대기' 연체 상향 한 곳에만 쓴다.
    //   행 목록을 점수로 재정렬하는 구조가 아니라, 정해진 자리에 넣는 것이다.
    // [CP04] 정밀 §5 — 제목·정확 일반 설명(동일 canonical N)·숫자 알약(기본 숫자만, 마감은 `N일`)·보조줄(실제 metadata).
    //   색은 행 종류로 칠하지 않는다: 제목·숫자·아이콘 공통색, 실제 긴급·연체·만료 보조줄만 errorDark(§4).
    void add({
      required IconData icon, required String label, required String desc,
      List<_TaskSub> subs = const [], required int count, required bool available, String? pill,
      required VoidCallback onTap,
      int? atIndex,
    }) {
      // [HOME-V2-08D.5] 행은 **처리할 대상이 실제로 있을 때만** 만든다.
      //
      //   available && count == 0  → KNOWN_ZERO   → 행 없음 (기존 규칙)
      //   available && count > 0   → KNOWN_NONZERO→ 행
      //   !available               → UNKNOWN      → **행 없음** (이번 교정)
      //
      // 이전에는 !available이 행을 만들고 `조회 실패` 칩을 달았다. 그런데
      // `퇴사 요청` 행이 존재한다는 것 자체가 "처리할 퇴사 요청이 있다"는 뜻이라,
      // 퇴사 요청을 받은 적 없는 관리자에게 없는 업무를 만들어 보여줬다.
      //
      // 게다가 서버의 available은 `permCount > 0 && successCount === permCount`라
      // **조회 실패와 권한 없음이 같은 false**로 내려온다(aggSimple). 그 값 하나로
      // 사용자에게 오류를 주장할 수 없다. UNKNOWN은 section-level notice가 말한다.
      if (!available || count == 0) return;
      final row = _TaskRow(icon: icon, label: label, desc: desc, pill: pill ?? '$count',
          subs: subs, count: count, onTap: onTap);
      if (atIndex != null) {
        result.insert(atIndex, row);
      } else {
        result.add(row);
      }
    }

    // 1. 퇴사 요청 — canManageWorkers
    // [AH-V2-02B] 다른 항목과 달리 방치하면 D+3에 시스템이 자동 승인한다(소급 요청은 제외 — 수동 검토).
    //   관리자가 결정하지 않은 것과 못 본 것이 같은 결과를 내므로 최상단에 둔다.
    //   기존 발견 경로는 알림뿐이었고, 경고(D+1·D+2)도 알림이라 함께 사라졌다.
    if (_verified(up, (p) => p.canManageWorkers)) {
      final resign = cs?.actions.resignRequest;
      final soon = resign?.soonCount ?? 0;
      // [D3-RETRO-EXCLUDE] 소급 요청은 자동 승인되지 않는다 — 서버가 따로 센 수동 검토 수.
      //   null(구버전 서버가 보내지 않음)이면 말하지 않는다. "0건"으로 확정하지 않는다.
      final manual = resign?.manualReviewCount;
      final resignN = resign?.count ?? 0;
      add(
        icon: Icons.logout_outlined, label: '퇴사 요청',
        desc: '퇴사 요청 $resignN건을 검토해 주세요',
        // [CP04 §4] soon 은 자동승인 제외가 완결되지 않은 집계 — `빠른 검토 필요 N건`/warning(확약 문구 0). 수동 검토는 가용값일 때만.
        subs: [
          if (manual != null && manual > 0) _TaskSub('수동 검토 $manual건'),
          if (soon > 0) _TaskSub('빠른 검토 필요 $soon건', tone: _SubTone.warning),
        ],
        count: resignN,
        available: resign?.available ?? false,
        onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
          if (!_verified(up, (p) => p.canManageWorkers)) {
            ToastHelper.showWarning('근로자 관리 권한이 없어요'); return;
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
    if (_verified(up, (p) => p.canManageTo)) {
      final approval = cs?.actions.approval;
      final approvalN = approval?.count ?? 0;
      add(
        icon: Icons.assignment_late_outlined, label: '지원 검토',
        desc: '대기 중인 지원 $approvalN건을 확인해 주세요',
        subs: [
          if ((approval?.overdueCount ?? 0) > 0) _TaskSub('긴급 ${approval!.overdueCount}건', tone: _SubTone.urgent),
        ],
        // [R7-P1-4 H1] 단위는 **건**이다 — 서버(`srvHomeApproval`)가 세는 것은
        //   `applications where status == PENDING` 이고, 한 사람이 여러 공고에
        //   PENDING 을 동시에 낼 수 있다(Application = 관심 표현). `명` 이라고 하면
        //   없는 사람을 센다. 같은 행의 배지가 이미 `긴급 N건` 이고, 목적지
        //   drill-down 시트도 `총 N건` 이다.
        count: approvalN,
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
    if (_verified(up, (p) => p.canManageWorkers)) {
      final sched = cs?.actions.scheduleChangeRequest;
      add(
        icon: Icons.edit_calendar_outlined, label: '일정 변경 요청',
        desc: '근로자의 일정 변경 요청 ${sched?.count ?? 0}건이 있어요',
        count: sched?.count ?? 0,
        available: sched?.available ?? false,
        onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
          if (!_verified(up, (p) => p.canManageWorkers)) {
            ToastHelper.showWarning('근로자 관리 권한이 없어요'); return;
          }
          if (!_ensureCanonicalSummary(context)) return;
          final sec = _canonicalSummary!.actions.scheduleChangeRequest;
          if (!sec.available) { _showCanonicalError(context); return; }
          if (sec.count == 0) return;
          final affectedBiz = sec.byBusiness.where((b) => b.count > 0).toList();
          final countMap = <String, int>{for (final b in sec.byBusiness) b.businessId: b.count};
          final bizId = await _pickBizFromSummary(
            context: context, sheetTitle: '일정 변경 요청', totalCount: sec.count,
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
    if (_verified(up, (p) => p.canManageContract)) {
      final unsent = cs?.actions.unsentContract;
      add(
        icon: Icons.folder_off_outlined, label: '계약 미발송',
        desc: '발송이 필요한 계약 ${unsent?.count ?? 0}건이 있어요',
        // [R7-P1-4 H1] 단위는 **건**이다 — 서버는 좌석을 가진 지원서를 순회하며
        //   `아직 발송되지 않은 계약서`를 센다(`CONTRACT_SEAT_STATUSES`).
        //   한 사람이 두 자리를 확정받으면 보낼 계약서도 두 건이다.
        count: unsent?.count ?? 0,
        available: unsent?.available ?? false,
        onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
          if (!_verified(up, (p) => p.canManageContract)) {
            ToastHelper.showWarning('계약서 관리 권한이 없어요'); return;
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
    if (_verified(up, (p) => p.canManageWage)) {
      final unclosed = cs?.actions.unclosed;
      final unclosedN = unclosed?.count ?? 0;
      add(
        icon: Icons.lock_open_outlined, label: '마감 필요',
        // [CP04 §5] 사업장×KST 근무일 합계 — 단위 `일`(알약도 `N일`). 같은 날짜여도 사업장별로 각각 센다.
        desc: '사업장별 미마감 근무일 합계 $unclosedN일이에요',
        // [ADMIN-HOME.31] ISO('2026-10-05') 대신 앱의 날짜 표기 — 값·기준은 그대로(연도 보존).
        subs: [
          if (unclosed?.oldestDate != null) _TaskSub('가장 오래된 날 ${_dotDate(unclosed!.oldestDate!)}'),
        ],
        count: unclosedN, pill: '$unclosedN일',
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
    if (_verified(up, (p) => p.canManageWage)) {
      final settlement = cs?.actions.settlementRequest;
      add(
        icon: Icons.payments_outlined, label: '중간정산 요청',
        desc: '대기 중인 중간정산 요청 ${settlement?.count ?? 0}건이 있어요',
        count: settlement?.count ?? 0,
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
    if (_verified(up, (p) => p.canManageWage)) {
      final wageChange = cs?.actions.wageChangeRequest;
      add(
        icon: Icons.edit_calendar_outlined, label: '급여 변경 요청',
        // [CP04 §5] 지급방식(주기) 변경 — 지급액 변경이라고 쓰지 않는다.
        desc: '지급방식 변경 요청 ${wageChange?.count ?? 0}건을 확인해 주세요',
        count: wageChange?.count ?? 0,
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
    if (_verified(up, (p) => p.canManageWage)) {
      final wage = cs?.actions.unpaidWage;
      final wageParts = <_TaskSub>[];
      if ((wage?.overdueCount ?? 0) > 0) wageParts.add(_TaskSub('연체 ${wage!.overdueCount}건', tone: _SubTone.urgent));
      // [R7-P1-4 H1] 단위는 **건**이다. 서버는 이 값을 고유 userId 수로 세지만
      //   (`missingUserIds.size`), 목적지 급여 화면에서 그 사람 하나가 카드
      //   하나(`userId::no_date`)이고 아래 `wageTotal` 이 그 카드 수를 `건` 으로
      //   합산한다. 같은 값이 배지에서는 `명`, 합계에서는 `건` 이면 두 숫자의
      //   관계가 끊긴다 — 처리 단위(카드=이체 묶음)로 맞춘다.
      if ((wage?.missingDueDateCount ?? 0) > 0) wageParts.add(_TaskSub('지급일 확인 필요 ${wage!.missingDueDateCount}건'));
      // count(지급일 있는 그룹) + missingDueDateCount(지급일 없는 유니크 유저) 합산
      final wageTotal = (wage?.count ?? 0) + (wage?.missingDueDateCount ?? 0);
      // [AH-V2-05B.3] 지급예정일이 지난 급여가 있으면 퇴사 요청 바로 뒤로 올린다.
      //   평상시에는 8순위 그대로 — 정기 이체 대기 물량이 많다는 것은 긴급이 아니다.
      //   조건은 canonical overdueCount 하나뿐이다. count·missingDueDateCount·
      //   배지 문자열은 이동 근거로 쓰지 않는다.
      //   available=false면 숫자를 신뢰할 수 없으므로 옮기지 않는다.
      //   [HOME-V2-08D.5] 그때는 행 자체가 생기지 않고, 확인하지 못했다는
      //   사실은 섹션 하단 notice가 말한다.
      final wageOverdue = wage?.available == true && (wage?.overdueCount ?? 0) > 0;
      add(
        icon: Icons.account_balance_wallet_outlined, label: '이체 대기',
        // [CP04 §5] N = count + missingDueDateCount 처리카드 단위. 은행 입금·실지급 완료로 확약하지 않는다.
        desc: '이체 확인이 필요한 급여 $wageTotal건이 있어요',
        subs: wageParts,
        count: wageTotal,
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
    }

    // 9. 계약 확인 필요 — canManageContract
    // [GAP-CONTRACT-EXPIRING-UI-01 FIX] ExpiringContractsScreen 진입점 추가
    // 홈 upcoming.expiringContract 데이터가 계산되지만 UI 진입 경로가 없었던 P2 갭 수정
    //
    // [HOME-V2-08D.5.1] 이 블록은 `이체 대기`(canManageWage)의 if 안에 중첩돼
    //   있었다. 그래서 계약서 권한만 가진 SubAdmin은 실제 종료 예정 계약이
    //   있어도 이 행을 볼 수 없었다 — 없는 업무를 보여주던 08D.5의 반대 방향
    //   결함이다. canonical 권한은 server aggregation·행 onTap 가드·
    //   contractExpiringReminder 알림 모두 canManageContract 단독이다.
    if (_verified(up, (p) => p.canManageContract)) {
      final expiring = cs?.upcoming.expiringContract;
      // [CORRECTION-EXPIRED-UNDECIDED-RENEWAL-ACTION-SURFACE]
      //   `종료 예정`은 이미 끝난 계약을 부를 이름이 아니다. 만료된 미결정
      //   건이 같은 줄에 들어오므로 우산 라벨을 쓰고, 늦은 건수는 따로 말한다.
      final expiredCount = cs?.upcoming.expiredContractCount ?? 0;
      final totalDecisions = expiring?.count ?? 0;
      add(
        icon: Icons.event_busy_outlined, label: '계약 확인 필요',
        // [R7-P1-4 H1] 단위는 **건**이다 — 서버(`srvHomeExpiringContract`)는 갱신
        //   결정이 필요한 **장기 지원서(관계)**를 센다. 한 사람이 같은 사업장에서
        //   두 관계를 가지면 결정도 두 건이다.
        // [CP04 §5] 주 알약 N(같은 집합)과 `만료 후 미결정 M건` 보조줄(expired>0)로 숫자와 사유를 나눈다.
        desc: '연장·종료를 정할 계약 $totalDecisions건을 확인해 주세요',
        subs: [
          if (expiredCount > 0) _TaskSub('만료 후 미결정 $expiredCount건', tone: _SubTone.urgent),
        ],
        count: totalDecisions,
        available: expiring?.available ?? false,
        onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
          if (!_verified(up, (p) => p.canManageContract)) {
            ToastHelper.showWarning('계약서 관리 권한이 없어요'); return;
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

    return result;
  }

  /// [HOME-V2-08D.5] 확인하지 못한 task source의 수 — **행이 아니라 상태다.**
  ///
  /// `available == false`는 서버 `aggSimple`에서
  /// `permCount > 0 && successCount === permCount`의 부정이므로 두 가지를 겸한다:
  ///   · 권한 있는 사업장 중 하나라도 쿼리 실패
  ///   · 그 task에 대한 권한이 **어느 사업장에도** 없음(permCount == 0)
  ///
  /// 그래서 **클라이언트 권한 게이트를 통과한 항목만** 센다. 권한이 없어 비어
  /// 있는 것을 장애라고 말하면 보안·UX가 둘 다 틀린다(§15).
  ///
  /// 전체 실패(cs == null)는 여기서 세지 않는다 — 그건 `일부`가 아니라
  /// 섹션 전체의 상태이고 다른 문구를 쓴다.
  int _unknownTaskCount(UserProvider up, AdminHomeSummaryModel? cs) {
    if (cs == null) return 0;
    // _makeActionRows의 9종과 **같은** 권한 게이트를 쓴다.
    final canWorkers  = _verified(up, (p) => p.canManageWorkers);
    final canTo       = _verified(up, (p) => p.canManageTo);
    final canContract = _verified(up, (p) => p.canManageContract);
    final canWage     = _verified(up, (p) => p.canManageWage);

    var n = 0;
    void chk({required bool permitted, required bool available}) {
      if (permitted && !available) n++;
    }

    final a = cs.actions;
    chk(permitted: canWorkers,  available: a.resignRequest.available);
    chk(permitted: canTo,       available: a.approval.available);
    chk(permitted: canWorkers,  available: a.scheduleChangeRequest.available);
    chk(permitted: canContract, available: a.unsentContract.available);
    chk(permitted: canWage,     available: a.unclosed.available);
    chk(permitted: canWage,     available: a.settlementRequest.available);
    chk(permitted: canWage,     available: a.wageChangeRequest.available);
    chk(permitted: canWage,     available: a.unpaidWage.available);
    chk(permitted: canContract, available: cs.upcoming.expiringContract.available);
    return n;
  }

  /// [HOME-V2-08D.5] 업무 상태를 확인하지 못했다는 **데이터 상태** 한 줄.
  ///
  /// 어떤 업무인지 말하지 않는다 — `퇴사 요청을 확인하지 못했어요`는 퇴사 요청이
  /// 실재한다는 뜻으로 읽힌다(§9). 말하는 것은 "우리가 못 읽었다"까지다.
  /// 재시도는 기존 canonical summary 로더를 그대로 쓴다.
  Widget _taskHealthNotice(double s, {required bool total}) {
    return _todayOpsErrorRow(s,
      message: total
          ? '처리할 업무 상태를 확인하지 못했어요'
          : '일부 업무 상태를 확인하지 못했어요',
      onRetry: () => unawaited(_loadCanonicalSummary()),
      // [DU307 §12.2] 일부 미확인은 부분 실패 표현(작은 주의+중립), 전체 미확인은 실패 안내 errorDark 그대로.
      partial: !total,
    );
  }

  /// [CP04] 처리할 일 한 행(정밀 §5). 상자 없는 Material outlined 아이콘 24(진남색) · 제목 17/700 · 정확 일반 설명 14 ·
  ///   보조줄(실제 metadata, 긴급·연체·만료만 errorDark) · 숫자 알약(#E3EAFE, 기본 숫자만·99+ 없음) · 꺾쇠 18(#45474E).
  ///   행 min 68·H16/V10, 내용이 크면 자연 확장. 뒤(알약·꺾쇠)가 본문을 압박하면 아래 오른쪽 줄(_rowWithTrailing).
  ///   행 전체가 receiver 하나 — 의미 이름 `제목, 설명[, 보조줄], 열기`(아이콘·알약 장식, 같은 콜백). 색은 행 종류로 칠하지 않는다.
  Widget _buildActionRowWidget(
    BuildContext context, double s,
    _TaskRow item,
    {required bool isLast}
  ) {
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(TextLayout.keepWords(item.label), semanticsLabel: item.label, style: ConceptText.taskTitle()),
      const SizedBox(height: 4),
      Text(TextLayout.keepWords(item.desc), semanticsLabel: item.desc, style: ConceptText.taskDescription()),
      for (final sub in item.subs) ...[
        const SizedBox(height: 2),
        Text(TextLayout.keepWords(sub.text), semanticsLabel: sub.text,
            style: ConceptText.taskDescription().copyWith(
                color: sub.color, fontWeight: sub.tone == _SubTone.neutral ? FontWeight.w400 : FontWeight.w700)),
      ],
    ]);
    final pillStyle = ConceptText.count();
    final pillW = _oneLineWidth(context, item.pill, pillStyle) + 20;
    final trailing = Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        constraints: const BoxConstraints(minWidth: 36, minHeight: 24),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: ConceptSurface.count(),
        child: Center(widthFactor: 1, heightFactor: 1, child: Text(item.pill, style: pillStyle)),
      ),
      const SizedBox(width: 8),
      const Icon(Icons.chevron_right, size: 18, color: AppColors.conceptChevron),
    ]);
    final semanticsLabel = [item.label, item.desc, for (final sub in item.subs) sub.text, '열기'].join(', ');
    return Column(children: [
      Semantics(
        container: true,
        button: true,
        label: semanticsLabel,
        excludeSemantics: true,
        onTap: item.onTap,
        child: InkWell(
          onTap: item.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: _rowWithTrailing(
                context,
                leading: Icon(item.icon, size: 24, color: AppColors.conceptNavy),
                leadingWidth: 24,
                leadingGap: 12,
                body: body,
                bodyTexts: [
                  (TextLayout.keepWords(item.label), ConceptText.taskTitle()),
                  (TextLayout.keepWords(item.desc), ConceptText.taskDescription()),
                  for (final sub in item.subs) (TextLayout.keepWords(sub.text), ConceptText.taskDescription()),
                ],
                trailing: trailing,
                trailingWidth: (pillW < 36 ? 36 : pillW) + 8 + 18,
              ),
            ),
          ),
        ),
      ),
      if (!isLast)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(height: 1 / MediaQuery.devicePixelRatioOf(context), color: AppColors.conceptDivider),
        ),
    ]);
  }

}

/// [CP04] 처리할 일 한 행의 표시 값 — 값·조건·권한·목적지는 `_makeActionRows` 의 기존 판정 그대로다.
class _TaskRow {
  const _TaskRow({
    required this.icon,
    required this.label,
    required this.desc,
    required this.pill,
    required this.subs,
    required this.count,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  /// 정밀 §5 의 정확 일반 설명(같은 canonical N).
  final String desc;
  /// 숫자 알약 — 기본 숫자만(마감은 `N일`). 단위는 설명·의미 이름에 남는다.
  final String pill;
  final List<_TaskSub> subs;
  final int count;
  final VoidCallback onTap;
}

enum _SubTone { neutral, warning, urgent }

/// [CP04] 보조줄 — 실제 metadata(긴급·연체·만료·빠른 검토·수동 검토·지급일 확인·가장 오래된 날).
class _TaskSub {
  const _TaskSub(this.text, {this.tone = _SubTone.neutral});
  final String text;
  final _SubTone tone;
  Color get color => switch (tone) {
        _SubTone.urgent => AppColors.errorDark,
        _SubTone.warning => AppColors.warningDark,
        _SubTone.neutral => AppColors.textSecondary,
      };
}

